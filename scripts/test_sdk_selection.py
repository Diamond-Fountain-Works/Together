#!/usr/bin/env python3
"""Deployment range regression tests; no toolchain or application is started."""
import json
from pathlib import Path
import tempfile
import unittest
import select_apple_sdk as sdk
from test_release_delivery import apple_build_targets, contains_file_markers, minimum_android_api, modern_weak_imports


class SDKSelectionTests(unittest.TestCase):
    def test_android_minimum_is_not_confused_with_target(self):
        for field in ["sdkVersion:'24'", "minSdkVersion: '24'"]:
            self.assertEqual(minimum_android_api(field + "\ntargetSdkVersion:'36'"), 24)
        self.assertIsNone(minimum_android_api("targetSdkVersion:'36'"))
        self.assertIsNone(minimum_android_api("minSdkVersion:'invalid'"))

    def test_android_minimum_aliases_must_agree(self):
        self.assertEqual(minimum_android_api("sdkVersion:'24'\nminSdkVersion: '24'\n"), 24)
        for rows in ["sdkVersion:'24'\nminSdkVersion:'28'\n",
                     "minSdkVersion:'28'\nsdkVersion:'24'\n",
                     "sdkVersion:'24'\nsdkVersion:'28'\n"]:
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                minimum_android_api(rows)

    def test_android_malformed_minimum_cannot_be_hidden_by_another_row(self):
        for rows in ["minSdkVersion:'invalid'\nsdkVersion:'24'\n",
                     "sdkVersion:'24'\nminSdkVersion:'24' trailing-garbage\n",
                     "sdkVersion:'24' trailing-garbage\n"]:
            with self.subTest(rows=rows):
                self.assertIsNone(minimum_android_api(rows))

    def test_ios_macho_target_does_not_accept_simulator_mac_or_duplicate_records(self):
        record = "Load command 11\n cmd LC_BUILD_VERSION\n platform IOS\n minos 15.0\n sdk 27.1\n"
        expected = [{"platform": "IOS", "minos": "15.0"}]
        self.assertEqual(apple_build_targets(record), expected)
        for text in [record.replace("IOS", "IOSSIMULATOR"), record.replace("IOS", "MACOS"),
                     record.replace("15.0", "17.0"), record + record, ""]:
            with self.subTest(text=text):
                self.assertNotEqual(apple_build_targets(text), expected)

    def test_macho_target_with_missing_or_contradictory_fields_fails_closed(self):
        for body in ["platform IOS", "platform IOS\n minos 15.0\n minos 17.0",
                     "platform IOS\n platform MACOS\n minos 15.0"]:
            with self.subTest(body=body), self.assertRaises(ValueError):
                apple_build_targets("Load command 1\n cmd LC_BUILD_VERSION\n " + body + "\n")

    def test_modern_frameworks_require_actual_weak_commands(self):
        swiftdata = "Load command 31\n cmd LC_LOAD_WEAK_DYLIB\n name /System/Library/Frameworks/SwiftData.framework/SwiftData (offset 24)\n"
        observation = "Load command 49\n cmd LC_LOAD_WEAK_DYLIB\n name /usr/lib/swift/libswiftObservation.dylib (offset 24)\n"
        self.assertTrue(all(modern_weak_imports(swiftdata + observation).values()))
        for text in ["", swiftdata, observation, (swiftdata + observation).replace("LC_LOAD_WEAK_DYLIB", "LC_LOAD_DYLIB"),
                     swiftdata + observation + swiftdata.replace("LC_LOAD_WEAK_DYLIB", "LC_LOAD_DYLIB")]:
            with self.subTest(text=text):
                self.assertFalse(all(modern_weak_imports(text).values()))

    def test_qa_binary_marker_across_stream_boundary_is_not_missed(self):
        marker = b"together-native-app-ios-qa-"
        with tempfile.TemporaryDirectory(dir=self.root) as temporary:
            binary = Path(temporary) / "synthetic-executable"
            binary.write_bytes(b"x" * (1024 * 1024 - 3) + marker + b"x")
            self.assertTrue(contains_file_markers(binary, (marker, b"TOGETHER_IOS_QA")))
            binary.write_bytes(b"clean synthetic executable")
            self.assertFalse(contains_file_markers(binary, (marker, b"TOGETHER_IOS_QA")))

    def setUp(self):
        self.root = sdk.ROOT / "qa/results/sdk-selection-tests"
        self.root.mkdir(parents=True, exist_ok=True)

    def test_old_system_is_not_supported_by_new_sdk_declaration(self):
        with tempfile.TemporaryDirectory(dir=self.root) as temporary:
            path = Path(temporary)
            (path / "SDKSettings.json").write_text(json.dumps({"SupportedTargets": {"macosx": {
                "MinimumDeploymentTarget": "12.0", "MaximumDeploymentTarget": "27.0.99"}}}))
            self.assertFalse(sdk.supports(path, "macos", "11.0"))
            self.assertTrue(sdk.supports(path, "macos", "12.0"))

    def test_installed_older_sdk_must_explicitly_cover_requested_floor(self):
        with tempfile.TemporaryDirectory(dir=self.root) as temporary:
            path = Path(temporary)
            (path / "SDKSettings.json").write_text(json.dumps({"SupportedTargets": {"macosx": {
                "MinimumDeploymentTarget": "10.13", "MaximumDeploymentTarget": "26.5.99"}}}))
            self.assertTrue(sdk.supports(path, "macos", "11.0"))
            self.assertFalse(sdk.supports(path, "macos", "27.0"))
            self.assertFalse(sdk.supports(path, "ios", "15.0"))

    def test_missing_and_malformed_metadata_fail_closed(self):
        with tempfile.TemporaryDirectory(dir=self.root) as temporary:
            path = Path(temporary)
            self.assertFalse(sdk.supports(path, "macos", "11.0"))
            (path / "SDKSettings.json").write_text("not json")
            self.assertFalse(sdk.supports(path, "macos", "11.0"))


if __name__ == "__main__":
    unittest.main()
