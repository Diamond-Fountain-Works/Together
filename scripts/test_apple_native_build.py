#!/usr/bin/env python3
"""Negative provenance/path tests; no Rust build, application launch or user data."""
import json
from pathlib import Path
import tempfile
import unittest

import rebuild_apple_native as build


class AppleNativeGateTests(unittest.TestCase):
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
