#!/usr/bin/env python3
"""Build an M-series .app with an already-installed compatible SDK.

Uses the unmodified SDK, compiler availability checks and linker inputs for the
actual deployment floor. Never patches Mach-O versions, installs toolchains,
launches an App, opens a production database or replaces /Applications.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

APP = Path(__file__).resolve().parents[1]
REPO = APP.parents[2]
sys.path.insert(0, str(REPO / 'scripts'))
from select_apple_sdk import select, supports, version


def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True, text=True, **kwargs)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def owned(path):
    path = Path(os.path.abspath(path))
    require(APP in path.parents and path.resolve() == path, 'Build output must stay in this project without symlink redirection')
    require(APP / '.derivedData' in path.parents or APP / '.build' in path.parents,
            'Compatibility output must be in a project-local ignored build directory')
    return path


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def mach_info(path):
    output = run('xcrun', 'vtool', '-arch', 'arm64', '-show-build', path).stdout
    platform_match = re.search(r'^\s*platform\s+(\S+)', output, re.M)
    minimum = re.search(r'^\s*minos\s+(\S+)', output, re.M)
    if minimum is None:
        minimum = re.search(r'^\s*version\s+(\S+)', output, re.M)
    sdk = re.search(r'^\s*sdk\s+(\S+)', output, re.M)
    require(minimum is not None, 'Missing actual Mach-O deployment record: ' + path.name)
    return {'platform': platform_match.group(1) if platform_match else 'MACOS',
            'minimum': minimum.group(1), 'sdk': sdk.group(1) if sdk else None}


def verify_code(path, minimum, exact=False):
    architectures = run('lipo', '-archs', path).stdout.split()
    require(architectures == ['arm64'], 'Unexpected code architecture: ' + path.name)
    info = mach_info(path)
    require(info['platform'] == 'MACOS', 'Non-macOS code in desktop application: ' + path.name)
    require(version(info['minimum']) == version(minimum) if exact else version(info['minimum']) <= version(minimum),
            'Code raises the declared OS minimum: ' + path.name)
    return info


def weak_frameworks(executable):
    commands = run('otool', '-l', executable).stdout.split('Load command ')
    found = {}
    for block in commands:
        command = re.search(r'^\s*cmd\s+(\S+)', block, re.M)
        name = re.search(r'^\s*name\s+(.*?)\s+\(offset', block, re.M)
        if not command or not name:
            continue
        if any(x in name.group(1) for x in ['SwiftData.framework', 'Observation.framework', 'libswiftObservation.dylib']):
            require(command.group(1) == 'LC_LOAD_WEAK_DYLIB', 'Modern-only framework is strongly linked: ' + name.group(1))
            found[name.group(1)] = command.group(1)
    require(any('SwiftData.framework' in x for x in found), 'Missing weak-linked modern storage framework')
    return found


def compile_strings(source, destination):
    run('xcrun', 'xcstringstool', 'compile', source, '--output-directory', destination,
        '--language', 'zh-Hans', '--language', 'en', '--serialization-format', 'binary')


def stage_resources(built, resources, work):
    source_bundle = built / 'TogetherCore_TogetherCore.bundle'
    require(source_bundle.is_dir() and not source_bundle.is_symlink(), 'SwiftPM resource bundle missing')
    core = resources / source_bundle.name
    shutil.copytree(source_bundle, core, symlinks=False)
    catalog = core / 'UI.xcstrings'
    require(catalog.is_file(), 'Core bilingual catalog missing')
    compile_strings(catalog, core)
    catalog.unlink()
    expected = json.loads((REPO / 'packages/together-core-swift/Sources/TogetherCore/Resources/UI.xcstrings').read_text())['strings']
    for language in ['zh-Hans', 'en']:
        table = core / (language + '.lproj/UI.strings')
        values = plistlib.loads(table.read_bytes())
        require(set(values) == set(expected), 'Incomplete embedded UI language: ' + language)
    require((core / 'FinanceCurrencies.json').is_file(), 'Currency reference missing')
    assets = APP / 'Sources/TogetherApp/Resources'
    compile_strings(assets / 'InfoPlist.xcstrings', resources)
    for name in ['ReleaseNotes.json', 'Iroh-LICENSE-MIT.txt', 'Iroh-LICENSE-APACHE.txt']:
        shutil.copy2(assets / name, resources / name)
    iconset = work / 'AppIcon.iconset'
    iconset.mkdir()
    icon_source = assets / 'Assets.xcassets/AppIcon.appiconset'
    icons = json.loads((icon_source / 'Contents.json').read_text())['images']
    for entry in icons:
        if entry.get('idiom') != 'mac' or entry.get('appearances'):
            continue
        name = entry.get('filename')
        if not name:
            continue
        size = entry['size'].split('x')[0]
        scale = '@2x' if entry['scale'] == '2x' else ''
        shutil.copy2(icon_source / name, iconset / ('icon_' + size + 'x' + size + scale + '.png'))
    run('xcrun', 'iconutil', '-c', 'icns', iconset, '-o', resources / 'AppIcon.icns')


def embed_runtimes(executable, frameworks, minimum):
    frameworks.mkdir()
    # Apple's tool follows the executable's real Swift runtime imports and
    # selects the provided concurrency back-deployment library automatically.
    run('xcrun', 'swift-stdlib-tool', '--copy', '--scan-executable', executable,
        '--platform', 'macosx', '--destination', frameworks)
    require((frameworks / 'libswift_Concurrency.dylib').is_file(), 'Required concurrency back-deployment runtime missing')
    result = {}
    for library in sorted(frameworks.glob('*.dylib')):
        architectures = run('lipo', '-archs', library).stdout.split()
        if library.name == 'libswiftCore.dylib' and architectures == ['x86_64']:
            # The tool also enumerates the pre-ABI-stability Intel runtime.
            # Every supported ARM Mac starts at macOS 11 and already supplies
            # /usr/lib/swift/libswiftCore.dylib. It is not an @rpath app import.
            imports = run('otool', '-L', executable).stdout
            require(version(minimum) >= version('11.0') and
                    '/usr/lib/swift/libswiftCore.dylib (' in imports and
                    '@rpath/libswiftCore.dylib (' not in imports,
                    'Cannot rely on the system Swift ABI runtime for this executable')
            library.unlink()
            continue
        require('arm64' in architectures, 'Apple runtime lacks the supported architecture: ' + library.name)
        if architectures != ['arm64']:
            selected = library.with_suffix('.arm64')
            run('lipo', library, '-thin', 'arm64', '-output', selected)
            selected.replace(library)
        library.chmod(0o755)
        result[library.name] = verify_code(library, minimum)
        run('codesign', '--force', '--sign', '-', '--timestamp=none', library)
    return result


def build(configuration, sdk):
    require(platform.system() == 'Darwin' and platform.machine() == 'arm64', 'M-series macOS build host required')
    minimum = json.loads((REPO / 'packages/together-native-source/platform-support.json').read_text())['macOS']['minimumVersion']
    require(supports(sdk, 'macos', minimum), 'SDK does not support the real deployment minimum')
    sdk_version = json.loads((sdk / 'SDKSettings.json').read_text())['Version']
    native = os.environ.get('TOGETHER_LEGACY_C1') != '1'
    if native:
        run(sys.executable, '-B', REPO / 'scripts/rebuild_apple_native.py', '--verify-only')
    scratch = owned(APP / '.derivedData/compatibility-swiftpm')
    scratch.mkdir(parents=True, exist_ok=True)
    log_root = owned(APP / '.build/logs')
    log_root.mkdir(parents=True, exist_ok=True)
    log = log_root / ('compatibility-' + configuration.lower() + '.log')
    target = 'arm64-apple-macosx' + minimum
    command = ['swift', 'build', '--build-system', 'native', '--package-path', str(APP),
               '--scratch-path', str(scratch), '--sdk', str(sdk), '--triple', target,
               '--configuration', configuration.lower(), '--product', 'Together',
               '-Xswiftc', '-target', '-Xswiftc', target]
    developer = Path(run('xcode-select', '-p').stdout.strip())
    plugins = developer / 'Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins'
    for name in ['SwiftData', 'Foundation', 'Observation']:
        plugin = plugins / ('lib' + name + 'Macros.dylib')
        require(plugin.is_file(), 'Required compiler macro plugin missing: ' + name)
        command.extend(['-Xswiftc', '-load-plugin-library', '-Xswiftc', str(plugin)])
    # Source files and native archives are actually compiled for the same floor.
    # Configure the link, rather than forging load commands after linking.
    for value in ['-platform_version', 'macos', minimum, sdk_version, '-syslibroot', str(sdk),
                  '-rpath', '@executable_path/../Frameworks']:
        command.extend(['-Xlinker', value])
    with log.open('w') as stream:
        result = subprocess.run(command, cwd=REPO, stdout=stream, stderr=subprocess.STDOUT)
    require(result.returncode == 0, 'Compatibility build failed; inspect ' + str(log))
    bin_result = run(*command, '--show-bin-path', cwd=REPO)
    built = Path(bin_result.stdout.strip().splitlines()[-1])
    require(scratch in built.parents and built.resolve() == built, 'Unexpected SwiftPM output path')
    binary = built / 'Together'
    executable_record = verify_code(binary, minimum, exact=True)
    require(version(executable_record['sdk']) == version(sdk_version), 'Linked SDK differs from selected compatible SDK')
    weak = weak_frameworks(binary)
    product_dir = owned(APP / ('.derivedData/native-secure' if native else '.derivedData') / 'Build/Products' / configuration)
    product_dir.mkdir(parents=True, exist_ok=True)
    product = product_dir / 'Together.app'
    release = json.loads((APP / 'Configuration/ReleaseVersion.json').read_text())
    with tempfile.TemporaryDirectory(prefix='compatibility-stage-', dir=product_dir) as temporary:
        work = Path(temporary)
        staged = work / 'Together.app'
        contents = staged / 'Contents'
        macos = contents / 'MacOS'
        resources = contents / 'Resources'
        macos.mkdir(parents=True); resources.mkdir()
        executable = macos / 'Together'
        shutil.copy2(binary, executable)
        executable.chmod(0o755)
        if configuration == 'Release':
            run('strip', '-S', executable)
        stage_resources(built, resources, work)
        info = plistlib.loads((APP / 'Configuration/Info.plist').read_bytes())
        replacements = {'EXECUTABLE_NAME': 'Together', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.together.app',
                        'PRODUCT_NAME': 'Together', 'MARKETING_VERSION': release['marketingVersion'],
                        'CURRENT_PROJECT_VERSION': release['buildNumber'], 'MACOSX_DEPLOYMENT_TARGET': minimum}
        for key, value in list(info.items()):
            if isinstance(value, str):
                for variable, replacement in replacements.items():
                    value = value.replace('$(' + variable + ')', replacement)
                require('$(' not in value, 'Unresolved bundle setting: ' + key)
                info[key] = value
        permission = json.loads((APP / 'Sources/TogetherApp/Resources/InfoPlist.xcstrings').read_text())['strings']
        for key in ['NSMicrophoneUsageDescription', 'NSLocalNetworkUsageDescription']:
            info[key] = permission[key]['localizations']['zh-Hans']['stringUnit']['value']
        info.update({'CFBundleIconFile': 'AppIcon.icns', 'CFBundleDevelopmentRegion': 'zh-Hans',
                     'CFBundleLocalizations': ['zh-Hans', 'en'], 'CFBundleSupportedPlatforms': ['MacOSX'],
                     'NSHighResolutionCapable': True, 'DTPlatformName': 'macosx', 'DTSDKName': 'macosx' + sdk_version})
        (contents / 'Info.plist').write_bytes(plistlib.dumps(info, sort_keys=True))
        runtimes = embed_runtimes(executable, contents / 'Frameworks', minimum)
        run('codesign', '--force', '--sign', '-', '--timestamp=none', '--options', 'runtime',
            '--entitlements', APP / 'Sources/TogetherApp/Resources/Together.entitlements', staged)
        run('codesign', '--verify', '--deep', '--strict', staged)
        verify_code(executable, minimum, exact=True)
        if product.exists():
            require(product.resolve() == product and not product.is_symlink(), 'Refuse redirected old build product')
            shutil.rmtree(product)
        shutil.move(str(staged), product)
    report = {'status': 'PASS', 'configuration': configuration, 'sdk': str(sdk), 'sdkVersion': sdk_version,
              'minimumMacOS': minimum, 'architectures': ['arm64'], 'executable': executable_record,
              'weakModernFrameworks': weak, 'bundledAppleRuntimes': runtimes,
              'systemSwiftCore': 'ABI-stable OS runtime on ARM macOS 11+; no Intel-only legacy runtime shipped', 'product': str(product),
              'bundleIdentifier': 'com.together.app', 'version': release['marketingVersion'], 'build': release['buildNumber'],
              'signing': 'ad-hoc', 'notarization': 'NOT RUN', 'physicalMacOS11': 'NOT RUN',
              'productionLaunch': False, 'deploymentMetadataPatched': False}
    (log_root / ('compatibility-' + configuration.lower() + '.json')).write_text(json.dumps(report, indent=2) + '\n')
    print('Compatibility App PASS:', product)
    print('Actual arm64 minimum:', minimum, 'SDK:', sdk_version, 'Apple runtime libraries:', len(runtimes))
    return product


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--configuration', choices=['Debug', 'Release'], default='Release')
    parser.add_argument('--sdk', type=Path)
    args = parser.parse_args()
    try:
        sdk = select('macos', str(args.sdk) if args.sdk else os.environ.get('TOGETHER_MACOS_SDK'))
        build(args.configuration, sdk)
    except (RuntimeError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            print(error.stdout or '', file=sys.stderr); print(error.stderr or '', file=sys.stderr)
        raise SystemExit(1)
