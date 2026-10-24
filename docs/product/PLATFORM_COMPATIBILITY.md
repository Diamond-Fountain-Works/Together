# Platform compatibility

The implementation target for this branch is Apple Silicon macOS 11,
iOS/iPadOS 15, and Android 7/API 24 on ARM64/ARMv7. These are adaptation
targets, not evidence that every version or physical device has passed.
The machine-readable build authority is
`packages/together-native-source/platform-support.json`.

## Boundaries

- Existing canonical signed operations, Protocol 4, user/device identifiers,
  pairing pins, Lamport ordering and domain projections are unchanged.
- Existing macOS SwiftData model names and stores remain intact on supported
  systems. A transactional SQLite backend serves systems without SwiftData.
  An existing legacy store stays readable after an OS upgrade. Unknown or newer
  stores fail closed rather than being replaced with an empty database.
- Older Apple systems use Combine observation and available native controls.
  Visual fallbacks preserve actions and access to content, not just appearance.
- The iPhone/iPad application shares core and feature views. UIKit adapters
  replace desktop panels; iPad uses the same domain and synchronization engine.
- Native Rust libraries are rebuilt from the same reviewed source and secure
  lock for each platform/ABI. Minimum versions apply to actual native code,
  not only Info.plist or Gradle declarations. No older vulnerable prebuilt is
  accepted as a compatibility shortcut.
- The exact pinned Android FFI wrapper declares API 24. Supporting Android 6
  would require a separately reviewed wrapper fork; manifest overrides are not
  evidence of support. Current AndroidX also no longer covers very old Android.
- Xcode 27.1's default Mac SDK starts at macOS 12. The Mac builder selects
  the already installed CLT SDK 26.5 (supports 11), passes an explicit frontend
  and linker target, embeds the arm64 concurrency runtime, and verifies actual
  Mach-O minimum 11. It does not download an obsolete SDK or edit SDK metadata.
  SwiftData/Observation remain weak-linked. iOS device builds use Xcode SDK 27.1
  with minimum 15. Supporting earlier iOS would require another toolchain and
  more API work, not a metadata-only change.
- A target SDK is not a maximum OS version. Newly released OS versions need
  regression tests. No maximum SDK filter is introduced.

## Validation record

Results must distinguish compile/link availability checks, isolated fallback
backend tests, simulator tests, physical tests and public-network acceptance.
An old-system deployment target does not substitute for running that old OS.
No production store, installed Mac application, phone application or Relay is
modified by compatibility development. New screenshots remain candidates.

The final report will record which SDKs/runtimes/devices actually ran, missing
old-system runtime coverage and the independent network security gate. All
task-owned temporary checkouts, build caches, test devices and disposable stores
must be cleaned after retaining named deliverables and minimal review evidence.

## Actual validation

| Platform | Configured floor | Built / executed here | Still unrun |
| --- | --- | --- | --- |
| Mac | 11, arm64 | Real minimum11 Release app + DMG, synthetic storage/logic tests | Physical macOS11 and other M generations |
| iPhone/iPad | 15, arm64 | Normal Release + separate QA generic-device compile/link | Simulator (user deferred), physical devices, signed IPA |
| Android | API24, ARM64+ARMv7 | Both native ABIs + signed APK; Android15 ARM64 emulator instrumentation and Release UI | API24 runtime, ARMv7 runtime, physical phone, 16KiB kernel |

[Detailed QA](../qa/reports/PLATFORM_COMPATIBILITY_QA.md) contains exact counts,
artifact hashes, residual warnings and cleanup. No newer OS version is claimed
tested solely because it is above the minimum.
