#!/usr/bin/env python3
"""Generate the shared-source iPhone/iPad project. Never builds or launches it."""
from pathlib import Path
import hashlib
import json
import os
import plistlib

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[2]
MAC = ROOT.parent / "macOS"
version = json.loads((MAC / "Configuration/ReleaseVersion.json").read_text())
policy = json.loads((REPO / "packages/together-native-source/platform-support.json").read_text())
minimum = policy["iOS"]["minimumVersion"]
assert minimum == policy["iPadOS"]["minimumVersion"]
purposes = json.loads((MAC / "Sources/TogetherApp/Resources/InfoPlist.xcstrings").read_text())["strings"]
info = {
    "CFBundleDisplayName": "$(PRODUCT_NAME)", "CFBundleName": "$(PRODUCT_NAME)",
    "CFBundleExecutable": "$(EXECUTABLE_NAME)", "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
    "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)", "LSRequiresIPhoneOS": True,
    "MinimumOSVersion": "$(IPHONEOS_DEPLOYMENT_TARGET)",
    "TogetherTransport": "native", "TogetherDeviceProtocolVersion": version["deviceProtocolVersion"],
    "UILaunchScreen": {}, "UIRequiresFullScreen": False,
    "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False},
    "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
    "UISupportedInterfaceOrientations~ipad": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
}
for name in ["NSMicrophoneUsageDescription", "NSLocalNetworkUsageDescription"]:
    info[name] = purposes[name]["localizations"]["zh-Hans"]["stringUnit"]["value"]
(ROOT / "Configuration").mkdir(exist_ok=True)
(ROOT / "Configuration/Info.plist").write_bytes(plistlib.dumps(info, sort_keys=True))

objects = []
def key(value): return hashlib.sha256(value.encode()).hexdigest()[:24].upper()
def add(name, value):
    identifier = key(name); objects.append("\t\t" + identifier + " = { " + value + " };\n"); return identifier
def quoted(value): return json.dumps(str(value))
def file_reference(path, kind):
    relative = os.path.relpath(path, ROOT)
    return add("file:" + relative, "isa = PBXFileReference; lastKnownFileType = " + kind + "; path = " + quoted(relative) + "; sourceTree = SOURCE_ROOT;")

files = sorted((ROOT / "Sources").rglob("*.swift"))
for path in sorted((MAC / "Sources/TogetherApp").rglob("*.swift")):
    relative = path.relative_to(MAC / "Sources/TogetherApp")
    if relative.parts[0] in ("App", "UITesting") or str(relative) == "Networking/NativeAcceptance.swift": continue
    files.append(path)
source_refs = [file_reference(path, "sourcecode.swift") for path in files]
resource_files = [
    (ROOT / "Resources/Assets.xcassets", "folder.assetcatalog"),
    *[(MAC / ("Sources/TogetherApp/Resources/" + name), kind) for name, kind in [
        ("ReleaseNotes.json", "text.json"), ("InfoPlist.xcstrings", "text.json.xcstrings"),
        ("Iroh-LICENSE-MIT.txt", "text"), ("Iroh-LICENSE-APACHE.txt", "text")]],
]
resource_refs = [file_reference(path, kind) for path, kind in resource_files]
products = []
packages = []
package_products = []
for name, folder in [("TogetherCore", "together-core-swift"), ("TogetherP2P", "together-p2p-swift")]:
    package = add("package:" + name, 'isa = XCLocalSwiftPackageReference; relativePath = "../../../packages/' + folder + '";')
    packages.append(package)
    package_products.append(add("package-product:" + name, "isa = XCSwiftPackageProductDependency; package = " + package + "; productName = " + name + ";"))
targets = []
for scheme, qa in [("TogetheriOS", False), ("TogetheriOSQA", True)]:
    product_name = "Together QA" if qa else "Together"
    product = add(scheme + ":product", "isa = PBXFileReference; explicitFileType = wrapper.application; path = " + quoted(product_name + ".app") + "; sourceTree = BUILT_PRODUCTS_DIR;")
    products.append(product)
    builds = [add(scheme + ":source:" + value, "isa = PBXBuildFile; fileRef = " + value + ";") for value in source_refs]
    resources = [add(scheme + ":resource:" + value, "isa = PBXBuildFile; fileRef = " + value + ";") for value in resource_refs]
    frameworks = [add(scheme + ":framework:" + value, "isa = PBXBuildFile; productRef = " + value + ";") for value in package_products]
    phases = []
    for name, isa, entries in [("sources", "PBXSourcesBuildPhase", builds), ("resources", "PBXResourcesBuildPhase", resources), ("frameworks", "PBXFrameworksBuildPhase", frameworks)]:
        phases.append(add(scheme + ":" + name, "isa = " + isa + "; buildActionMask = 2147483647; files = (" + ", ".join(entries) + "); runOnlyForDeploymentPostprocessing = 0;"))
    configs = []
    for configuration in ["Debug", "Release"]:
        conditions = "TOGETHER_NATIVE_TRANSPORT" + (" TOGETHER_IOS_QA" if qa else "") + (" DEBUG" if configuration == "Debug" else "")
        settings = {
            "PRODUCT_NAME": product_name, "PRODUCT_MODULE_NAME": "TogetherApp",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.together.app.ios.qa" if qa else "com.together.app",
            "MARKETING_VERSION": version["marketingVersion"], "CURRENT_PROJECT_VERSION": str(version["buildNumber"]),
            "INFOPLIST_FILE": "Configuration/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
            "IPHONEOS_DEPLOYMENT_TARGET": minimum, "TARGETED_DEVICE_FAMILY": "1,2",
            "SDKROOT": "iphoneos", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
            "ARCHS": "arm64", "SUPPORTS_MACCATALYST": "NO", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
            "SWIFT_VERSION": "6.0", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": conditions,
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if configuration == "Debug" else "-O",
            "CODE_SIGN_STYLE": "Automatic", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
            "ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES": "YES", "CLANG_ENABLE_MODULES": "YES",
        }
        configs.append(add(scheme + ":config:" + configuration, "isa = XCBuildConfiguration; name = " + configuration + "; buildSettings = { " + " ".join(k + " = " + quoted(v) + ";" for k, v in settings.items()) + " };"))
    config_list = add(scheme + ":configs", "isa = XCConfigurationList; buildConfigurations = (" + ", ".join(configs) + "); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
    target = add(scheme + ":target", "isa = PBXNativeTarget; name = " + scheme + "; productName = " + quoted(product_name) + "; productType = \"com.apple.product-type.application\"; productReference = " + product + "; buildConfigurationList = " + config_list + "; buildPhases = (" + ", ".join(phases) + "); dependencies = (); packageProductDependencies = (" + ", ".join(package_products) + ");")
    targets.append(target)
    scheme_dir = ROOT / "Together.xcodeproj/xcshareddata/xcschemes"; scheme_dir.mkdir(parents=True, exist_ok=True)
    reference = '<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="' + target + '" BuildableName="' + product_name + '.app" BlueprintName="' + scheme + '" ReferencedContainer="container:Together.xcodeproj"/>'
    (scheme_dir / (scheme + ".xcscheme")).write_text('<?xml version="1.0" encoding="UTF-8"?>\n<Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForRunning="YES" buildForTesting="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">' + reference + '</BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><BuildableProductRunnable runnableDebuggingMode="0">' + reference + '</BuildableProductRunnable></LaunchAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>\n')

source_group = add("sources", 'isa = PBXGroup; name = "Shared Sources"; children = (' + ", ".join(source_refs) + '); sourceTree = "<group>";')
resource_group = add("resources", 'isa = PBXGroup; name = Resources; children = (' + ", ".join(resource_refs) + '); sourceTree = "<group>";')
product_group = add("products", 'isa = PBXGroup; name = Products; children = (' + ", ".join(products) + '); sourceTree = "<group>";')
main_group = add("main", 'isa = PBXGroup; children = (' + ", ".join([source_group, resource_group, product_group]) + '); sourceTree = "<group>";')
project_configs = [add("project:" + name, "isa = XCBuildConfiguration; name = " + name + "; buildSettings = { SDKROOT = iphoneos; SWIFT_VERSION = 6.0; IPHONEOS_DEPLOYMENT_TARGET = " + minimum + "; }; ") for name in ["Debug", "Release"]]
project_list = add("project-configs", "isa = XCConfigurationList; buildConfigurations = (" + ", ".join(project_configs) + "); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
project = add("project", 'isa = PBXProject; attributes = { LastUpgradeCheck = 2700; }; buildConfigurationList = ' + project_list + '; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; knownRegions = (en, "zh-Hans", Base); mainGroup = ' + main_group + '; productRefGroup = ' + product_group + '; projectDirPath = ""; projectRoot = ""; packageReferences = (' + ", ".join(packages) + '); targets = (' + ", ".join(targets) + ');')
(ROOT / "Together.xcodeproj/project.pbxproj").write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + "".join(objects) + '}; rootObject = ' + project + '; }\n')
print("Generated shared iPhone/iPad project; minimum", minimum, "; normal and fail-closed QA products")
