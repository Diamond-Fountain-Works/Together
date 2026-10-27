#!/usr/bin/env python3
"""iPhone/iPad package regressions. No build, launch, simulator or private data.

Generate a small isolated project from the real generator so that normal/QA
product boundaries and device eligibility are checked without altering the
developer's checked-out project. Runtime layout acceptance remains separate.
"""
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

from test_release_delivery import ios_device_eligibility, ios_localized_resources_match

REPO = Path(__file__).resolve().parents[1]
RUN = REPO / "qa/results/iphone-client-20261027"


class IOSDeviceEligibilityTests(unittest.TestCase):
    def setUp(self):
        self.info = {
            "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
            "UISupportedInterfaceOrientations~ipad": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
            "UIRequiresFullScreen": False,
        }

    def test_complete_phone_tablet_package_is_eligible(self):
        self.assertTrue(all(ios_device_eligibility(self.info).values()))

    def test_toolchain_arm64_requirement_matches_all_ios15_devices(self):
        for capabilities in (["arm64"], {"arm64": True}):
            with self.subTest(capabilities=capabilities):
                self.info["UIRequiredDeviceCapabilities"] = capabilities
                self.assertTrue(ios_device_eligibility(self.info)["noRestrictiveDeviceCapabilities"])

    def test_optional_camera_or_microphone_cannot_exclude_devices(self):
        for capabilities in (["microphone"], ["camera-flash"], ["arm64", "arkit"], {"gps": True}, {"telephony": False}, {"arm64": False}):
            with self.subTest(capabilities=capabilities):
                self.info["UIRequiredDeviceCapabilities"] = capabilities
                self.assertFalse(ios_device_eligibility(self.info)["noRestrictiveDeviceCapabilities"])

    def test_accidental_full_screen_setting_blocks_multitasking_gate(self):
        self.info["UIRequiresFullScreen"] = True
        self.assertFalse(ios_device_eligibility(self.info)["tabletMultitaskingAllowed"])

    def test_phone_portrait_only_and_missing_tablet_rotation_are_rejected(self):
        self.info["UISupportedInterfaceOrientations"] = ["UIInterfaceOrientationPortrait"]
        self.info["UISupportedInterfaceOrientations~ipad"].remove("UIInterfaceOrientationPortraitUpsideDown")
        checks = ios_device_eligibility(self.info)
        self.assertFalse(checks["phonePortraitAndLandscape"])
        self.assertFalse(checks["tabletAllOrientations"])

    def test_malformed_orientation_values_are_not_accepted(self):
        for malformed in (None, "UIInterfaceOrientationPortrait", [123]):
            with self.subTest(malformed=malformed):
                self.info["UISupportedInterfaceOrientations"] = malformed
                self.assertFalse(ios_device_eligibility(self.info)["phonePortraitAndLandscape"])


class IOSGeneratedProjectTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        RUN.mkdir(parents=True, exist_ok=True)
        cls.temporary = tempfile.TemporaryDirectory(prefix="ios-project-fixture-", dir=RUN)
        cls.root = Path(cls.temporary.name)
        relative_files = [
            "apps/apple/iOS/script/generate_project.py",
            "apps/apple/macOS/Configuration/ReleaseVersion.json",
            "apps/apple/macOS/Sources/TogetherApp/Resources/InfoPlist.xcstrings",
            "packages/together-native-source/platform-support.json",
        ]
        for relative in relative_files:
            target = cls.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPO / relative, target)
        for relative in ["apps/apple/iOS/Sources/TogetherIOSApp.swift",
                         "apps/apple/macOS/Sources/TogetherApp/Views/HomeView.swift",
                         "apps/apple/macOS/Sources/TogetherApp/App/TogetherApp.swift",
                         "apps/apple/macOS/Sources/TogetherApp/UITesting/Fixture.swift",
                         "apps/apple/macOS/Sources/TogetherApp/Networking/NativeAcceptance.swift"]:
            target = cls.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("// synthetic source inclusion sentinel\n")
        cls.script = cls.root / "apps/apple/iOS/script/generate_project.py"
        subprocess.run([sys.executable, "-B", str(cls.script)], check=True, capture_output=True)
        cls.app = cls.root / "apps/apple/iOS"
        cls.info = plistlib.loads((cls.app / "Configuration/Info.plist").read_bytes())
        cls.project = (cls.app / "Together.xcodeproj/project.pbxproj").read_text()

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_generated_package_keeps_optional_hardware_and_multitasking(self):
        self.assertTrue(all(ios_device_eligibility(self.info).values()))
        self.assertEqual(self.project.count('TARGETED_DEVICE_FAMILY = "1,2";'), 4)
        minimum = json.loads((self.root / "packages/together-native-source/platform-support.json").read_text())["iOS"]["minimumVersion"]
        self.assertIn('IPHONEOS_DEPLOYMENT_TARGET = "' + minimum + '";', self.project)

    def test_normal_and_qa_launches_are_distinct(self):
        schemes = self.app / "Together.xcodeproj/xcshareddata/xcschemes"
        normal = ET.parse(schemes / "TogetheriOS.xcscheme")
        qa = ET.parse(schemes / "TogetheriOSQA.xcscheme")
        self.assertEqual(normal.findall(".//EnvironmentVariable"), [])
        variables = {element.get("key"): (element.get("value"), element.get("isEnabled"))
                     for element in qa.findall(".//EnvironmentVariable")}
        self.assertEqual(variables, {"TOGETHER_IOS_QA": ("1", "YES")})
        self.assertEqual(self.project.count('PRODUCT_BUNDLE_IDENTIFIER = "com.together.app";'), 2)
        self.assertEqual(self.project.count('PRODUCT_BUNDLE_IDENTIFIER = "com.together.app.ios.qa";'), 2)
        self.assertEqual(self.project.count(' TOGETHER_IOS_QA'), 2)

    def test_phone_uses_shared_features_without_mac_or_fixture_entrypoints(self):
        self.assertIn("Views/HomeView.swift", self.project)
        self.assertIn("Sources/TogetherIOSApp.swift", self.project)
        self.assertNotIn("App/TogetherApp.swift", self.project)
        self.assertNotIn("UITesting/Fixture.swift", self.project)
        self.assertNotIn("Networking/NativeAcceptance.swift", self.project)

    def test_generation_is_reproducible(self):
        originals = {str(path.relative_to(self.app)): path.read_bytes()
                     for path in self.app.rglob("*") if path.is_file() and path != self.script}
        subprocess.run([sys.executable, "-B", str(self.script)], check=True, capture_output=True)
        self.assertEqual(originals, {str(path.relative_to(self.app)): path.read_bytes()
                                    for path in self.app.rglob("*") if path.is_file() and path != self.script})


class IOSLocalizedArtifactTests(unittest.TestCase):
    def setUp(self):
        self.catalog = {"title": {"localizations": {locale: {"stringUnit": {"value": value}}
                        for locale, value in (("en", "Phone and tablet"), ("zh-Hans", "手机和平板"))}}}
        self.resources = {"en": {"title": "Phone and tablet"}, "zh-Hans": {"title": "手机和平板"}}

    def test_exact_both_language_values_are_required(self):
        self.assertTrue(ios_localized_resources_match(self.catalog, self.resources))
        self.resources["zh-Hans"]["title"] = "iPhone 和 iPad"
        self.assertFalse(ios_localized_resources_match(self.catalog, self.resources))

    def test_missing_language_or_empty_value_is_rejected(self):
        self.assertFalse(ios_localized_resources_match(self.catalog, {"en": self.resources["en"]}))
        self.resources["en"]["title"] = ""
        self.catalog["title"]["localizations"]["en"]["stringUnit"]["value"] = ""
        self.assertFalse(ios_localized_resources_match(self.catalog, self.resources))


if __name__ == "__main__":
    unittest.main()
