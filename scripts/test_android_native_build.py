#!/usr/bin/env python3
"""Compatibility/provenance regression checks; no build, device or user storage."""
import struct
import unittest
import rebuild_android_native as build


def elf(abi, api=24, alignment=16384):
    wide = abi == "arm64-v8a"
    data = bytearray(512)
    data[:7] = b"\x7fELF" + bytes((2 if wide else 1, 1, 1))
    struct.pack_into("<H", data, 18, 183 if wide else 40)
    struct.pack_into("<" + ("Q" if wide else "I"), data, 32 if wide else 28, 64)
    size = 56 if wide else 32
    struct.pack_into("<HH", data, 54 if wide else 42, size, 2)
    if wide:
        struct.pack_into("<IIQQQQQQ", data, 64, 1, 4, 0, 0, 0, 512, 512, alignment)
        struct.pack_into("<IIQQQQQQ", data, 64 + size, 4, 4, 256, 0, 0, 24, 24, 4)
    else:
        struct.pack_into("<IIIIIIII", data, 64, 1, 0, 0, 0, 512, 512, 4, alignment)
        struct.pack_into("<IIIIIIII", data, 64 + size, 4, 256, 0, 0, 24, 24, 4, 4)
    struct.pack_into("<III", data, 256, 8, 4, 1)
    data[268:276] = b"Android\0"
    struct.pack_into("<I", data, 276, api)
    return bytes(data)


class AndroidNativeCompatibilityTests(unittest.TestCase):
    def test_legacy_build_defaults_remain_api28_arm64(self):
        plan = build.android_build_plan()
        self.assertEqual([(p["abi"], p["androidAPI"]) for p in plan], [("arm64-v8a", 28)])
        self.assertEqual(plan[0]["target"], build.TARGET)
        self.assertEqual(plan[0]["entry"], build.NATIVE_PATH)

    def test_both_broad_abis_require_independent_targets(self):
        plan = build.android_build_plan(["arm64-v8a", "armeabi-v7a"], 24)
        self.assertEqual({p["target"] for p in plan}, {"aarch64-linux-android", "armv7-linux-androideabi"})
        self.assertEqual({p["androidAPI"] for p in plan}, {24})
        self.assertEqual({p["machine"] for p in plan}, {183, 40})

    def test_wrapper_floor_unsupported_and_repeated_abis_fail_closed(self):
        for abis, api in [(["arm64-v8a"], 23), (["x86"], 24),
                          (["arm64-v8a", "arm64-v8a"], 24), (["armeabi-v7a"], 24.5)]:
            with self.subTest(abis=abis, api=api), self.assertRaises(RuntimeError):
                build.android_build_plan(abis, api)

    def test_actual_elf32_and_elf64_alignment_and_api_note(self):
        for abi in build.ABI_TARGETS:
            with self.subTest(abi=abi):
                self.assertEqual(build.android_api_note(elf(abi)), 24)
                self.assertEqual(len(build.verify_android_elf(elf(abi), abi, max_api=24)), 1)

    def test_wrong_abi_bad_alignment_newer_api_and_missing_note_rejected(self):
        for abi in build.ABI_TARGETS:
            other = "armeabi-v7a" if abi == "arm64-v8a" else "arm64-v8a"
            with self.subTest(abi=abi):
                with self.assertRaises(RuntimeError): build.verify_android_elf(elf(other), abi, max_api=24)
                with self.assertRaises(RuntimeError): build.verify_android_elf(elf(abi, alignment=4096), abi, max_api=24)
                with self.assertRaises(RuntimeError): build.verify_android_elf(elf(abi, api=28), abi, max_api=24)
                without_note = bytearray(elf(abi)); without_note[268:276] = b"Unknown\0"
                with self.assertRaises(RuntimeError): build.verify_android_elf(bytes(without_note), abi, max_api=24)

    def test_truncated_note_is_not_a_valid_provenance_claim(self):
        for abi in build.ABI_TARGETS:
            with self.subTest(abi=abi), self.assertRaises(RuntimeError):
                build.android_api_note(elf(abi)[:275])


if __name__ == "__main__":
    unittest.main()
