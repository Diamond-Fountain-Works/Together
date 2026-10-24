#!/usr/bin/env python3
"""Deployment range regression tests; no toolchain or application is started."""
import json
from pathlib import Path
import tempfile
import unittest
import select_apple_sdk as sdk
from test_release_delivery import minimum_android_api


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
