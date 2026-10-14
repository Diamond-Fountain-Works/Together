#!/usr/bin/env python3
from pathlib import Path
import hashlib
import json
import os
import plistlib
from urllib.parse import urlsplit

root = Path(__file__).resolve().parent.parent
release_version = json.loads((root / "Configuration/ReleaseVersion.json").read_text())
relay_config = root / "Configuration/RelayService.json"
default_relay = json.loads(relay_config.read_text()).get("origin", "") if relay_config.exists() else ""
relay_url = os.environ.get("TOGETHER_RELAY_URL", default_relay)
if relay_url:
    parsed = urlsplit(relay_url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username is not None or parsed.password is not None or parsed.path not in ["", "/"] or parsed.query or parsed.fragment or any(c in relay_url for c in ["\"", "\\", "\n", "$", "(", ")"]): raise SystemExit("Invalid HTTPS relay build origin")
microphone_copy = json.loads((root / "Sources/TogetherApp/Resources/InfoPlist.xcstrings").read_text())["strings"]["NSMicrophoneUsageDescription"]["localizations"]["zh-Hans"]["stringUnit"]["value"]
info = {
    "CFBundleDisplayName": "Together",
    "CFBundleExecutable": "$(EXECUTABLE_NAME)",
    "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
    "CFBundleName": "$(PRODUCT_NAME)",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    "LSMinimumSystemVersion": "$(MACOSX_DEPLOYMENT_TARGET)",
    "LSApplicationCategoryType": "public.app-category.productivity",
    "NSPrincipalClass": "NSApplication",
    "NSMicrophoneUsageDescription": microphone_copy,
}
if relay_url: info["TogetherRelayURL"] = relay_url
info_path = root / "Configuration/Info.plist"
info_path.parent.mkdir(parents=True, exist_ok=True)
info_path.write_bytes(plistlib.dumps(info, sort_keys=True))
project = root / "Together.xcodeproj"
project.mkdir(exist_ok=True)
objects = []
def key(text): return hashlib.sha256(text.encode()).hexdigest()[:24].upper()
def add(name, content):
    ident = key(name)
    objects.append(f"\t\t{ident} = {{ {content} }};")
    return ident
def ref(name): return key(name)
sources = sorted((root / "Sources/TogetherApp").rglob("*.swift"))
file_refs, build_refs = [], []
for path in sources:
    relative = str(path.relative_to(root))
    file_id = add(relative, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{relative}"; sourceTree = SOURCE_ROOT;')
    file_refs.append(file_id)
    build_refs.append(add(relative + ":build", f"isa = PBXBuildFile; fileRef = {file_id};"))
resource_builds, resource_refs = [], []
for relative, filetype in [("Sources/TogetherApp/Resources/ReleaseNotes.json", "text.json"), ("Sources/TogetherApp/Resources/InfoPlist.xcstrings", "text.json.xcstrings"), ("Sources/TogetherApp/Resources/Assets.xcassets", "folder.assetcatalog")]:
    f = add(relative, f'isa = PBXFileReference; lastKnownFileType = {filetype}; path = "{relative}"; sourceTree = SOURCE_ROOT;')
    resource_refs.append(f)
    resource_builds.append(add(relative + ":build", f"isa = PBXBuildFile; fileRef = {f};"))
product = add("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Together.app; sourceTree = BUILT_PRODUCTS_DIR;')
src = add("source-group", f'isa = PBXGroup; name = "App Sources"; children = ({", ".join(file_refs)}); sourceTree = "<group>";')
res = add("resources-group", f'isa = PBXGroup; name = Resources; children = ({", ".join(resource_refs)}); sourceTree = "<group>";')
products = add("products", f'isa = PBXGroup; name = Products; children = ({product}); sourceTree = "<group>";')
main = add("main-group", f'isa = PBXGroup; children = ({src}, {res}, {products}); sourceTree = "<group>";')
package = add("package", 'isa = XCLocalSwiftPackageReference; relativePath = .;')
dependency = add("core-product", f'isa = XCSwiftPackageProductDependency; package = {package}; productName = TogetherCore;')
core_build = add("core-build", f"isa = PBXBuildFile; productRef = {dependency};")
source_phase = add("sources", f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(build_refs)}); runOnlyForDeploymentPostprocessing = 0;')
resource_phase = add("resources", f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(resource_builds)}); runOnlyForDeploymentPostprocessing = 0;')
framework_phase = add("frameworks", f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({core_build}); runOnlyForDeploymentPostprocessing = 0;')
project_configs, target_configs = [], []
for configuration in ["Debug", "Release"]:
    project_configs.append(add("project-" + configuration, f'isa = XCBuildConfiguration; name = {configuration}; buildSettings = {{ MACOSX_DEPLOYMENT_TARGET = 14.0; SDKROOT = macosx; SWIFT_VERSION = 6.0; CLANG_ENABLE_MODULES = YES; }};'))
    settings = 'PRODUCT_NAME = Together; PRODUCT_MODULE_NAME = TogetherApp; PRODUCT_BUNDLE_IDENTIFIER = com.together.app; MARKETING_VERSION = __VERSION__; CURRENT_PROJECT_VERSION = __BUILD__; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_CFBundleDisplayName = Together; INFOPLIST_KEY_NSMicrophoneUsageDescription = "__MICROPHONE_COPY__"; CODE_SIGN_ENTITLEMENTS = Sources/TogetherApp/Resources/Together.entitlements; INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.productivity"; MACOSX_DEPLOYMENT_TARGET = 14.0; SWIFT_VERSION = 6.0; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; CODE_SIGN_STYLE = Manual; CODE_SIGN_IDENTITY = "-"; ENABLE_APP_SANDBOX = NO; ENABLE_HARDENED_RUNTIME = YES; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";'
    settings = settings.replace("__VERSION__", release_version["marketingVersion"]).replace("__BUILD__", release_version["buildNumber"])
    settings = settings.replace("__MICROPHONE_COPY__", microphone_copy.replace(chr(92), chr(92) * 2).replace(chr(34), chr(92) + chr(34)).replace(chr(10), chr(92) + "n"))
    settings += ' INFOPLIST_FILE = Configuration/Info.plist;'
    if configuration == "Debug": settings += ' SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG; ONLY_ACTIVE_ARCH = YES;'
    else: settings += ' CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO;'
    target_configs.append(add("target-" + configuration, f'isa = XCBuildConfiguration; name = {configuration}; buildSettings = {{ {settings} }};'))
project_list = add("project-configs", f'isa = XCConfigurationList; buildConfigurations = ({", ".join(project_configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target_list = add("target-configs", f'isa = XCConfigurationList; buildConfigurations = ({", ".join(target_configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = add("target", f'isa = PBXNativeTarget; name = TogetherNative; productName = Together; productType = "com.apple.product-type.application"; productReference = {product}; buildConfigurationList = {target_list}; buildPhases = ({source_phase}, {framework_phase}, {resource_phase}); dependencies = (); packageProductDependencies = ({dependency});')
ui_files, ui_builds = [], []
for path in sorted((root / "Tests/TogetherUITests").rglob("*.swift")):
    relative = str(path.relative_to(root))
    f = add(relative, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{relative}"; sourceTree = SOURCE_ROOT;')
    ui_files.append(f); ui_builds.append(add(relative + ":build", f'isa = PBXBuildFile; fileRef = {f};'))
ui_product = add("ui-product", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = TogetherUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
ui_group = add("ui-group", f'isa = PBXGroup; name = "UI Tests"; children = ({", ".join(ui_files)}); sourceTree = "<group>";')
# Include the test files/products in navigator without replacing app groups.
for n, obj in enumerate(objects):
    if obj.startswith("\t\t" + main + " = "): objects[n] = obj.replace(f"{src}, {res}, {products}", f"{src}, {res}, {ui_group}, {products}")
    if obj.startswith("\t\t" + products + " = "): objects[n] = obj.replace(f"children = ({product})", f"children = ({product}, {ui_product})")
ui_source = add("ui-sources", f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(ui_builds)}); runOnlyForDeploymentPostprocessing = 0;')
ui_framework = add("ui-frameworks", 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
ui_configs = []
for configuration in ["Debug", "Release"]:
    ui_configs.append(add("ui-"+configuration, f'isa = XCBuildConfiguration; name = {configuration}; buildSettings = {{ PRODUCT_NAME = TogetherUITests; PRODUCT_BUNDLE_IDENTIFIER = com.together.app.UITests; GENERATE_INFOPLIST_FILE = YES; MACOSX_DEPLOYMENT_TARGET = 14.0; SWIFT_VERSION = 6.0; CODE_SIGN_STYLE = Manual; CODE_SIGN_IDENTITY = "-"; TEST_TARGET_NAME = TogetherNative; ONLY_ACTIVE_ARCH = YES; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @loader_path/../Frameworks @executable_path/../Frameworks"; }};'))
ui_list = add("ui-configs", f'isa = XCConfigurationList; buildConfigurations = ({", ".join(ui_configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;')
proxy = add("ui-proxy", f'isa = PBXContainerItemProxy; containerPortal = {ref("project")}; proxyType = 1; remoteGlobalIDString = {target}; remoteInfo = Together;')
ui_dependency = add("ui-dependency", f'isa = PBXTargetDependency; target = {target}; targetProxy = {proxy};')
ui_target = add("ui-target", f'isa = PBXNativeTarget; name = TogetherUITests; productName = TogetherUITests; productType = "com.apple.product-type.bundle.ui-testing"; productReference = {ui_product}; buildConfigurationList = {ui_list}; buildPhases = ({ui_source}, {ui_framework}); dependencies = ({ui_dependency});')
proj = add("project", f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; TargetAttributes = {{ {ui_target} = {{ TestTargetID = {target}; }}; }}; }}; buildConfigurationList = {project_list}; compatibilityVersion = "Xcode 16.0"; developmentRegion = en; knownRegions = (en, Base); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target}, {ui_target}); packageReferences = ({package});')
text = '// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 77;\n\tobjects = {\n' + '\n'.join(objects) + f'\n\t}};\n\trootObject = {proj};\n}}\n'
(project / "project.pbxproj").write_text(text)
schemes = project / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
buildable = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Together.app" BlueprintName="TogetherNative" ReferencedContainer="container:Together.xcodeproj"/>'
(schemes / "Together.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.7">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable}</BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ui_target}" BuildableName="TogetherUITests.xctest" BlueprintName="TogetherUITests" ReferencedContainer="container:Together.xcodeproj"/></TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(project)
