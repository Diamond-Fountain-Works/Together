#!/usr/bin/env python3
"""Negative provenance/path tests; no Rust build, application launch or user data."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import rebuild_apple_native as build


class AppleNativeGateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        (build.ROOT / ".native-build").mkdir(exist_ok=True)

    def test_policy_matches_shared_apple_minima(self):
        self.assertEqual(build.platform_gate()["macOS"]["minimumVersion"], "11.0")
        self.assertEqual(build.platform_gate()["iOS"]["minimumVersion"], "15.0")

    def test_reviewed_slice_layout_is_bounded(self):
        files = build.package_files(["macos", "ios", "ios-simulator"])
        self.assertEqual(len(files), 15)
        self.assertIn("Iroh.xcframework/ios-arm64/libiroh_ffi.a", files)
        self.assertNotIn("Iroh.xcframework/ios-x86_64/libiroh_ffi.a", files)

    def test_native_object_cannot_raise_declared_minimum(self):
        with tempfile.TemporaryDirectory(dir=build.ROOT / ".native-build") as temporary:
            library = Path(temporary) / "lib.a"
            library.write_bytes(b"!<arch>\n")
            def checked(*args):
                return "iroh_ffi.test.rcgu.o" if args[0] == "ar" else "platform MACOS\nminos 14.5"
            with patch.object(build, "checked", side_effect=checked), patch.object(build.subprocess, "check_output", return_value=b"object"):
                with self.assertRaisesRegex(RuntimeError, "raises"):
                    build.verify_native_platform(library, "macos")

    def test_wrong_native_platform_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=build.ROOT / ".native-build") as temporary:
            library = Path(temporary) / "lib.a"
            library.write_bytes(b"!<arch>\n")
            def checked(*args):
                return "iroh_ffi.test.rcgu.o" if args[0] == "ar" else "platform MACOS\nminos 11.0"
            with patch.object(build, "checked", side_effect=checked), patch.object(build.subprocess, "check_output", return_value=b"object"):
                with self.assertRaisesRegex(RuntimeError, "platform mismatch"):
                    build.verify_native_platform(library, "ios")

    def test_reviewed_secure_lock_and_unchanged_abi_inputs(self):
        self.assertEqual(build.source_manifest()["dependencyVersions"]["iroh"], "1.1.0")
        self.assertEqual(len(build.binding_gate()["files"]), 4)

    def test_missing_receipt_rejected(self):
        with tempfile.TemporaryDirectory(dir=build.ROOT / ".native-build") as temporary:
            package = Path(temporary) / "iroh-ffi"
            package.mkdir()
            with self.assertRaises((RuntimeError, OSError)):
                build.verify(package)

    def test_old_binary_receipt_rejected(self):
        with tempfile.TemporaryDirectory(dir=build.ROOT / ".native-build") as temporary:
            package = Path(temporary) / "iroh-ffi"
            package.mkdir()
            (package / "secure-build.json").write_text(json.dumps({"format": build.MAGIC,
                "sourceCommit": build.REF, "secureCargoLockSHA256": build.UPSTREAM_LOCK_SHA256}))
            with self.assertRaisesRegex(RuntimeError, "stale"):
                build.verify(package)

    def test_output_outside_ignored_root_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "ignored"):
            build.output_path(build.ROOT / "packages/iroh-ffi")

    def test_output_symlink_rejected(self):
        with tempfile.TemporaryDirectory(dir=build.ROOT / ".native-build") as temporary:
            base = Path(temporary)
            (base / "target").mkdir()
            (base / "iroh-ffi").symlink_to(base / "target", target_is_directory=True)
            with self.assertRaisesRegex(RuntimeError, "Symlink"):
                build.output_path(base / "iroh-ffi")


if __name__ == "__main__":
    unittest.main()
