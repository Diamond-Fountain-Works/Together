#!/usr/bin/env python3
"""Install the verified local release and remove only generated Together bundles."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LS = Path('/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister')
APP_ID = 'com.together.app'
RUNNER_ID = APP_ID + '.UITests.xctrunner'
DESTINATION = Path('/Applications/Together.app')


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def manifest(bundle):
    result = {}
    for path in sorted(bundle.rglob('*')):
        name = str(path.relative_to(bundle))
        if path.is_symlink():
            result[name] = {'link': os.readlink(path)}
        elif path.is_file():
            result[name] = {'sha256': digest(path), 'executable': bool(path.stat().st_mode & 0o111)}
    return result


def identity(bundle):
    if bundle.is_symlink() or not bundle.is_dir():
        raise RuntimeError('Expected a real generated bundle: ' + str(bundle))
    return plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())['CFBundleIdentifier']


def registered():
    dump = subprocess.check_output([str(LS), '-dump'], text=True)
    paths = set()
    for block in re.split(r'^-{10,}\s*$', dump, flags=re.M):
        if not re.search(r'^identifier:\s+com\.together\.app(?:\.UITests\.xctrunner)?\s*$', block, re.M):
            continue
        match = re.search(r'^path:\s+(.+?)\s+\(0x[0-9a-f]+\)\s*$', block, re.M)
        if match:
            paths.add(Path(match.group(1)))
    return paths


def data_metadata():
    # Metadata only: never read private keys, user text, database contents or media.
    base = Path.home() / 'Library/Application Support/Together'
    rows = []
    if base.exists():
        for path in [base, *sorted(base.rglob('*'))]:
            value = path.lstat()
            rows.append((str(path.relative_to(base)), value.st_ino, value.st_size, value.st_mtime_ns))
    return hashlib.sha256(json.dumps(rows).encode()).hexdigest()


def verify_image_app(image, expected):
    # Catch a Debug dist App overwritten after the Release installer was created,
    # even when both use the same 0.0.1 / Build 1 version numbers.
    cache = Path.home() / '.cache/Together'
    cache.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='installer-check-', dir=cache) as work:
        mount = Path(work) / 'mounted'
        subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', str(mount), str(image)],
                       check=True, stdout=subprocess.DEVNULL)
        try:
            app = mount / 'Together.app'
            if identity(app) != APP_ID or manifest(app) != expected:
                raise RuntimeError('App differs from the verified Release installer; run make package before installing')
        finally:
            subprocess.run([str(LS), '-u', str(mount / 'Together.app')], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(['hdiutil', 'detach', str(mount)], check=True, stdout=subprocess.DEVNULL)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--plan', action='store_true', help='Validate and list exact targets without copying or deleting.')
    args = parser.parse_args()
    project = (ROOT / json.loads((ROOT / 'qa/project.json').read_text())['projectDirectory']).resolve()
    if ROOT not in project.parents:
        raise RuntimeError('Selected project must be inside Together')
    dist = project / 'dist'
    source = dist / 'Together.app'
    if identity(source) != APP_ID:
        raise RuntimeError('Source is not Together')
    source_info = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
    report_path = dist / ('Together-' + source_info['CFBundleShortVersionString'] + '-Build' + source_info['CFBundleVersion'] + '-Universal.json')
    package = json.loads(report_path.read_text())
    if package['status'] != 'PASS' or Path(package['artifact']).name != package['artifact']:
        raise RuntimeError('Package report is invalid')
    image = dist / package['artifact']
    if digest(image) != package['sha256']:
        raise RuntimeError('Installer hash differs from its verified package report; nothing removed')
    subprocess.run(['python3', str(project / 'script/verify_bundle.py'), str(source)], check=True)
    expected = manifest(source)
    if (source_info['CFBundleShortVersionString'], source_info['CFBundleVersion']) != (package['version'], package['build']):
        raise RuntimeError('App and installer versions differ')
    verify_image_app(image, expected)
    if DESTINATION.exists() and identity(DESTINATION) != APP_ID:
        raise RuntimeError('Destination is occupied by another app')
    products = project / '.derivedData/Build/Products'
    ui_products = Path.home() / '.cache/Together/UIQA-DerivedData/Build/Products/Debug'
    generated = [source, products / 'Debug/Together.app', products / 'Release/Together.app',
                 products / 'Debug/TogetherUITests-Runner.app', ui_products / 'Together.app',
                 ui_products / 'TogetherUITests-Runner.app']
    for path in generated:
        if path.exists() and identity(path) != (RUNNER_ID if path.name == 'TogetherUITests-Runner.app' else APP_ID):
            raise RuntimeError('Generated cleanup target has unexpected identity: ' + str(path))
    entries = registered()
    stale = [path for path in entries if not path.exists() and path.parent.name == 'payload'
             and path.parent.parent.parent == dist and path.parent.parent.name.startswith('together-package-')]
    desktop = Path.home() / 'Desktop' / image.name
    print(json.dumps({'install': str(DESTINATION), 'desktopInstaller': str(desktop),
                      'generatedAppsToRemove': [str(p) for p in generated if p.exists()],
                      'staleRegistrationsToRemove': sorted(map(str, stale))}, ensure_ascii=False, indent=2))
    if args.plan:
        return
    if subprocess.run(['pgrep', '-x', 'Together'], stdout=subprocess.DEVNULL).returncode == 0:
        raise RuntimeError('Together is running; quit it normally before installing. No app was replaced.')
    original_data = data_metadata()
    removed = []
    with tempfile.TemporaryDirectory(prefix='.together-install-', dir='/Applications') as work:
        stage = Path(work) / 'bundle'
        subprocess.run(['ditto', str(source), str(stage)], check=True)
        if manifest(stage) != expected:
            raise RuntimeError('Staged App differs from the verified release')
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(stage)], check=True)
        if DESTINATION.exists():
            old = Path(work) / 'previous'
            DESTINATION.rename(old)
            try:
                stage.rename(DESTINATION)
            except Exception:
                old.rename(DESTINATION)
                raise
        else:
            stage.rename(DESTINATION)
        if manifest(DESTINATION) != expected:
            raise RuntimeError('Installed App failed full bundle verification; source retained')
    desktop.parent.mkdir(exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix='.Together-installer-', suffix='.partial', dir=desktop.parent, delete=False) as handle:
        partial = Path(handle.name)
    try:
        shutil.copy2(image, partial)
        if digest(partial) != package['sha256']:
            raise RuntimeError('Desktop installer failed integrity verification')
        os.replace(partial, desktop)
    finally:
        partial.unlink(missing_ok=True)
    registry_calls = []
    for path in sorted(set(generated) | set(stale)):
        call = subprocess.run([str(LS), '-u', str(path)], capture_output=True, text=True)
        registry_calls.append({'path': str(path), 'exitCode': call.returncode})
    for path in generated:
        if path.exists():
            shutil.rmtree(path)
            removed.append(str(path))
    # A background app indexer can re-register a bundle between the first
    # unregister and deletion. Repeat only these exact owned paths afterwards.
    for path in sorted(set(generated) | set(stale)):
        call = subprocess.run([str(LS), '-u', str(path)], capture_output=True, text=True)
        registry_calls.append({'path': str(path), 'exitCode': call.returncode, 'phase': 'after-removal'})
    subprocess.run([str(LS), '-f', str(DESTINATION)], check=True)
    remaining = registered()
    generated_remaining = [str(path) for path in generated if path.exists() or path in remaining]
    stale_remaining = sorted(str(path) for path in stale if path in remaining)
    result = {'status': 'PASS' if not generated_remaining and not stale_remaining else 'REVIEW REQUIRED',
              'installedApp': str(DESTINATION), 'version': package['version'], 'build': package['build'],
              'desktopInstaller': str(desktop), 'installerSHA256': digest(desktop),
              'sourceBundleManifest': expected, 'installedBundleMatchesSource': manifest(DESTINATION) == expected,
              'removedGeneratedApps': removed, 'unregisteredStaleEntries': sorted(str(p) for p in stale if p not in remaining),
              'remainingGeneratedEntries': generated_remaining, 'remainingStaleEntries': stale_remaining,
              'remainingTogetherRegistrations': sorted(map(str, remaining)),
              'registryCalls': registry_calls, 'userDataMetadataUnchanged': data_metadata() == original_data,
              'checkedAt': datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
              'signing': package['signing'], 'notarization': package['notarization']}
    (ROOT / 'qa/results/local-install.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    if not result['installedBundleMatchesSource'] or not result['userDataMetadataUnchanged']:
        raise RuntimeError('Post-install verification failed; see qa/results/local-install.json')
    print('Install:', result['status'], str(DESTINATION))
    print('Desktop installer:', str(desktop))
    print('Removed generated App bundles:', len(removed), 'cleared stale registrations:', len(result['unregisteredStaleEntries']))


if __name__ == '__main__':
    main()
