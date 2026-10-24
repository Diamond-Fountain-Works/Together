# Together Android — 0.2.4 compatibility candidate and isolated QA

Native Kotlin / Jetpack Compose / Room client. Phone drawer and ≥600dp tablet rail share one domain/state/persistence implementation. Minimum Android 7/API24, compile/target36, JDK21, Gradle8.13, Java/Kotlin bytecode17 with maintained Java/NIO API desugaring. The normal 0.2.4 candidate contains **arm64-v8a and armeabi-v7a** libraries rebuilt at API24. It does not claim all-ABI or physical-device release acceptance. No user records, test identities, private media or credentials are bundled.

## Current variants

| Variant | Application ID | Transport and storage | Signing |
| --- | --- | --- | --- |
| `release` | `com.together.android` | Native Iroh adapter, ordinary private workspace; no Relay URL or QA namespace | External long-lived Release key required |
| `nativeQa` | `com.together.android.qa.native` | Same native adapter, guarded `NATIVE-APP` isolated workspace | Debug test key; visibly Together QA |
| `debug` | `com.together.android.debug` | Retained C1 WebSocket implementation and independent app storage | Debug test key |

The authoritative version is in `app/build.gradle.kts` (0.2.4, code17 for this candidate). A normal Release launches without test arguments, requires an explicit first-run nickname/relationship choice and starts with empty business data. It does not load QA fixtures. Existing identities, signed operations and Room schema1 are preserved; missing keys with existing storage fail closed rather than silently rotating identity.

Native pairing uses the existing signed partner contact, human verification, co-signed genesis, Protocol4 anti-entropy and durable ACK. It can use a direct QUIC path or an encrypted Iroh relay path; an invitation or successful socket send does not prove the partner persisted data. It needs network infrastructure for discovery/relay fallback, but does not require Tailscale or a VPN. No Cloudflare Worker deployment or persistent offline mailbox is part of this Release. Native mode currently supports one paired partner device; C1-only additional-device/revoke actions are hidden instead of pretending they work without a Relay binding.

## Compatibility boundary

The authoritative OS/ABI contract is [platform-support.json](../../packages/together-native-source/platform-support.json).
The pinned Iroh Android wrapper declares API24. Android6/API23 is not enabled by
manifest overrides or by downgrading the reviewed native dependency. The app
backports `java.time`, `java.util.Base64` and `java.nio.file` with
`desugar_jdk_libs_nio:2.1.5`; canonical payloads, identities and Room schema1 do not change.

Each advertised ABI must have its own API24 build receipt, actual ELF API note,
unchanged generated classes/FFI exports and 16KiB LOAD alignment. A manifest edit
alone cannot make an API28 native binary work on API24. No x86, all-OEM, future-OS,
physical ARMv7 or actual Android7 runtime acceptance is implied. The present
compatibility run uses the existing Android15/API35 ARM64 emulator; real API24
hardware/runtime remains **NOT RUN**. `targetSdk36` is not a maximum OS version.
On Android7/8, HEIC originals pass bounded HEVC-container/metadata/extent checks and
remain available for authenticated transfer and export; the absent system decoder
is shown as an unavailable preview. No HEIF rendering on those systems is claimed,
and original files are never silently converted or compressed. The matched JNA5.19.1
Java/JNI AAR contains upstream 16KiB-call and older-Android reflection fixes.

## Signed Release build

Use an existing Android SDK, NDK28.2.13676358 and Rust1.96.0 with `aarch64-linux-android`. Build the native library from the pinned FFI source and reviewed secure lock first; do not package the original Maven native library or merely ZIP-align it. The Maven FFI version1.1.0 originally contains Rust Iroh1.0.2. The tracked [source manifest](../../packages/together-native-source/source-manifest.json) and `Cargo.lock` pin the corrected Iroh1.1.0 dependencies. The wrapper/JVM API remains unchanged.

From the repository root, with generated outputs below ignored `qa/results`:

```sh
mkdir -p qa/results/native-release
git clone --filter=blob:none --no-checkout https://github.com/n0-computer/iroh-ffi.git qa/results/native-release/iroh-ffi
git -C qa/results/native-release/iroh-ffi checkout --detach 5e451092dba0c1a09ee83ff6e5be37b1152a5c58
curl -fL https://repo.maven.apache.org/maven2/computer/iroh/iroh-android/1.1.0/iroh-android-1.1.0.aar \
  -o qa/results/native-release/original.aar
python3 scripts/rebuild_android_native.py \
  --source qa/results/native-release/iroh-ffi \
  --ndk "$ANDROID_HOME/ndk/28.2.13676358" \
  --original-aar qa/results/native-release/original.aar \
  --output qa/results/native-release/iroh-secure-16k.aar \
  --android-api 24 --abi arm64-v8a --abi armeabi-v7a --jobs 4
```

The script verifies the exact source tree and original AAR, installs only the tracked secure lock in that isolated checkout, compiles both ARM targets with `--locked`, API24 NDK compilers and 16KiB linker flags, verifies actual ELF architecture/Android API notes, compares FFI exports and retains original JVM classes. The generated adjacent JSON receipt is required. Only the two receipt-listed ARM ABIs are replaced; the Release APK excludes unrepaired x86 libraries. Keep the generated AAR, compiler logs and APKs out of Git.

Provide an owner-only signing properties file **outside tracked source** (for example the project’s ignored `ReleaseSigning/` directory), containing `storeFile`, `storePassword`, `keyAlias`, `keyPassword`; keep a recoverable secure backup of that long-lived key. Equivalent environment names are `TOGETHER_ANDROID_KEYSTORE`, `TOGETHER_ANDROID_KEYSTORE_PASSWORD`, `TOGETHER_ANDROID_KEY_ALIAS`, `TOGETHER_ANDROID_KEY_PASSWORD`. Never use the Debug key for Release and never commit passwords.

```sh
# Replace the signing path and use absolute native artifact paths.
cd apps/android
./gradlew :app:assembleRelease :app:lintRelease :app:testReleaseUnitTest \
  -Ptogether.signingProperties=/secure/location/android-signing.properties \
  -Ptogether.nativeReleaseAar=/absolute/path/iroh-secure-16k.aar \
  -Ptogether.nativeReleaseAarSha256=<sha256-of-that-aar> \
  --dependency-verification=strict --console=plain
cd ../..
python3 scripts/test_release_delivery.py \
  --android-apk apps/android/app/build/outputs/apk/release/app-release.apk \
  --json qa/results/native-release/artifact.json
```

Release packaging rejects missing signing, missing native provenance, an obsolete unsafe lock, changed wrapper classes or non-16KiB ARM64 ELF segments. R8 remains enabled; the JNA native ABI is explicitly retained. **Static artifact checks are not a runtime test.** Validate a fresh install, initial setup, process restart and Connection → Create Invitation → Cancel using the exact optimized signed APK. Earlier code14 failed this native-init flow because R8 renamed JNA fields; its crash is retained as evidence and it is not a deliverable. Also separately test real-device pairing/ACK/offline catch-up and original media with the final artifact. Samsung release testing is NOT RUN while the phone is disconnected.

## Build and tests for development

```sh
# Repository root, existing SDK or ignored apps/android/local.properties:
make android-qa
# Dedicated emulator + explicit loopback Relay (physical hardware uses the guarded driver below):
apps/android/gradlew -p apps/android -Ptogether.testRelay=http://127.0.0.1:8797 :app:connectedDebugAndroidTest
```

Debug APK: `apps/android/app/build/outputs/apk/debug/app-debug.apk`. Native QA build and its helper APK: `:app:assembleNativeQa :app:assembleNativeQaAndroidTest -Ptogether.testBuildType=nativeQa`. Debug/QA builds and JVM unit tests do not require Release credentials or the rebuilt Release AAR. Never uninstall real user data to solve a signing mismatch. The Debug QA activity can reopen an existing synthetic namespace, never create a replacement identity; it is absent from Release. Physical reopening requires a short-lived namespace-bound local QA permit. Normal test rules use their own explicitly isolated repository, never the default workspace.

Physical runs require live ADB authorization/model verification and
`scripts/run_android_physical_qa.py --serial <device> --expect-model SM-S9210 --relay http://127.0.0.1:<port> --authorize-physical-test-app`.
Only this driver's explicit `--install` uses same-signer `install -r`; it checks both APK IDs and
never uninstalls or clears data. Do **not** use Gradle connected tests on the physical phone.
Native permissions are handled by the user, not auto-granted. See
[device isolation and limitations](../../docs/architecture/ANDROID_DEVICE_ACCEPTANCE.md).

## Business implementation

- Home / Our Plans / Wishes / Our Finances / Connection / Settings. No false Our Story page or permanent Love Gift destination/card.
- One Tasks editor, assignee/due dates, Pending/Completed, regular every-N calendar recurrence and flexible Set Next Time/complete-later. Future, overdue and undated unfinished tasks share Pending. Atomic command groups validate a fresh projection; unchanged editor fields do not overwrite concurrent changes.
- Separate Wishes grants/history, two real member directions, beneficiary items, fulfillment request/beneficiary confirm/reject and auditable quota adjustments/conflicts. Ordinary changes never require partner approval.
- Exactly Reserves/Expenses/Bills: integer CNY, original currency/frozen rates, deterministic AA, negative reserves, one expense ledger, bill/month uniqueness, provisional/confirmed/skipped, next-natural-month default revisions, forecasts, financial cycles and local/private or shared four-digit card metadata. Reminders are in-app, not a promise of background system notification.
- Overflow Send Gift / Gift History, local drafts, one shared-zone day per sender, immutable sends and no deletion refund. Original photo/audio are streamed, separate thumbnail caches, 64KiB existing encrypted media frames, durable partial offsets and SHA-256/format validation. Recipient content receipt is separate from operation ACK. Explicit Android recording, manual player and SAF original export; no auto-play or automatic public export.
- Cached startup gifts open sealed once, only when ready; normal-use arrival is a nonblocking unread notice. Force-stop/relaunch presentation state is independent of sync/What’s New. Review metadata never exposes sealed text/assets. Review pages compute effective before/after values from logical prefixes off-main; reviewed/notified state is local.

## Historical C1 enrollment and lifecycle

[Phase A](../../docs/qa/reports/ANDROID_PHASE_A.md), [Phase B QA](../../docs/qa/reports/ANDROID_PHASE_B.md) and [Phase C QA](../../docs/qa/reports/ANDROID_PHASE_C.md) record earlier builds and their exact test environments. Their C1/USB-reverse results do not establish current native Release acceptance. The following retained enrollment implementation applies to C1 Debug, not the single-peer native Release.

Add My Device retains the Phase A signed-file workflow: import a public Mac offer, compare code/fingerprint, generate an independent key, save a proof-of-possession request via Android SAF, import the root-signed completion and atomically activate its own Room workspace. Old unpaired facts are preserved separately. Same user/space, no third partner, no private-key import/export.

Authorized devices show active/revoked state. Existing Protocol4-v1 permits only the original owner root to grant/revoke. An enrolled Android is not silently promoted to root; original-Mac authorization/revocation UI remains required. The root device must stay available. This is not invitation-based creation of a new partner pair on Android.

Foreground C1 API2 challenge/ticket and directed authenticated-encrypted WebSockets use the existing SyncEngine; offline edits persist, foreground reconnect catches up, background cancels sockets. Native Release reuses the same local signed-log business semantics with its native adapter. Neither variant promises a permanent background connection or offline mailbox. Local saved / pending / remote persisted / converged / reviewed / domain confirmed are distinct. No Delivered/read/bank-payment claim.

Each software Ed25519 seed is independently generated and AES-GCM wrapped by an Android Keystore AES key. This does not claim hardware Ed25519 or encryption of the entire Room database. App backup/device-transfer excludes facts/identity. Missing/invalidated keys fail closed; uninstall/device loss can destroy access. There is no root-loss recovery or silent identity rotation. Preserve the trusted root and authorize a genuinely new device.

## Local native interoperability

```sh
cd services/relay
npm ci --legacy-peer-deps
./node_modules/.bin/wrangler dev --local --ip 127.0.0.1 --port 8797 --persist-to ../../qa/results/android-business-relay
# In another shell, repository root:
TOGETHER_LOCAL_RELAY_URL=http://127.0.0.1:8797 TOGETHER_RUN_SWIFT_ANDROID=1 \
  apps/android/gradlew -p apps/android -Ptogether.jvmOnly=true :core:domain:test :core:protocol:test
```

A native Swift process hosting two clients and Kotlin use independent keys and actual local C1 encrypted transport. Tasks, wishes, CNY/AA/reserves/bills, original PNG/WAV hashes, media receipts and offline field merge are asserted. Shared JSON conformance vectors remain authoritative. This is native test runtime interoperability, not physical Mac↔Samsung acceptance or Mac GUI editor acceptance. No Mac runtime source or production Worker is changed.

`test_android_apk_upgrade.py` verifies checksum-pinned Phase A APK → B with real `adb install -r`, retained Room1 facts, old key signatures, binding and new signature. `test_android_gift_lifecycle.py` exercises actual process death, cached gift with Relay route removed, once-only display, explicit player and native SAF byte-exact original export. Both require an identified dedicated emulator and synthetic local identities; see root TEST_PLAN and QA report.

## Limits and release gates

Physical Samsung SM-S9210/API36 and native Swift/USB-reversed local C1 have executed evidence in the
Phase C report. Public cross-network/graphical Mac enrollment, independent protocol review,
minimum API28, real tablet/TalkBack and human visual approval remain separate gates. Upstream
authorization archive remains bounded (128KiB/32 active devices), root-loss recovery/archive paging
are absent, and offline revocation freshness cannot be guaranteed. OkHttp assembles messages before
application bounds; adversarial-server memory behavior remains an upstream transport review item.
Projection/recovery is linear in history; the opt-in100k benchmark measures storage/paging/restart,
not full100k business UI or public transfer. Unsupported platform codecs report an error and preserve
original bytes. No C2, production deployment, Mac installation or real-user Protocol4 activation is implied.
