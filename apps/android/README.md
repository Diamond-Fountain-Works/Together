# Together Android — Phase B

Native Kotlin / Jetpack Compose / Room client. Phone drawer and ≥600dp tablet rail share one domain/state/persistence implementation. Minimum Android 9/API28, compile/target36, JDK21, Gradle8.13, Java/Kotlin bytecode17. No production Relay origin, user records or credentials are bundled. [Phase A](../../docs/qa/reports/ANDROID_PHASE_A.md) remains historical evidence; [Phase B QA](../../docs/qa/reports/ANDROID_PHASE_B.md) records current results and remaining gates.

## Build and tests

```sh
# Repository root, existing SDK or ignored apps/android/local.properties:
make android-qa
# Dedicated emulator + explicit loopback Relay; the Runner rejects physical hardware:
apps/android/gradlew -p apps/android -Ptogether.testRelay=http://127.0.0.1:8797 :app:connectedDebugAndroidTest
```

Debug APK: `apps/android/app/build/outputs/apk/debug/app-debug.apk`, application ID `com.together.android.debug`, version `0.2.1-phaseB`, code2. The reserved normal ID is `com.together.android`; no signed production Android release is delivered. Do not uninstall real user data to solve a signing mismatch. The Debug emulator-only QA activity can reopen an existing synthetic namespace, never create a replacement identity; it is absent from Release.

## Business implementation

- Home / Our Plans / Wishes / Our Finances / Connection / Settings. No false Our Story page or permanent Love Gift destination/card.
- One Tasks editor, assignee/due dates, Pending/Upcoming/Completed, regular every-N calendar recurrence and flexible Set Next Time/complete-later. Atomic command groups validate a fresh projection; unchanged editor fields do not overwrite concurrent changes.
- Separate Wishes grants/history, two real member directions, beneficiary items, fulfillment request/beneficiary confirm/reject and auditable quota adjustments/conflicts. Ordinary changes never require partner approval.
- Exactly Reserves/Expenses/Bills: integer CNY, original currency/frozen rates, deterministic AA, negative reserves, one expense ledger, bill/month uniqueness, provisional/confirmed/skipped, next-natural-month default revisions, forecasts, financial cycles and local/private or shared four-digit card metadata. Reminders are in-app, not a promise of background system notification.
- Overflow Send Gift / Gift History, local drafts, one shared-zone day per sender, immutable sends and no deletion refund. Original photo/audio are streamed, separate thumbnail caches, 64KiB existing encrypted media frames, durable partial offsets and SHA-256/format validation. Recipient content receipt is separate from operation ACK. Explicit Android recording, manual player and SAF original export; no auto-play or automatic public export.
- Cached startup gifts open sealed once, only when ready; normal-use arrival is a nonblocking unread notice. Force-stop/relaunch presentation state is independent of sync/What’s New. Review metadata never exposes sealed text/assets. Review pages compute effective before/after values from logical prefixes off-main; reviewed/notified state is local.

## Identity, enrollment and lifecycle

Add My Device retains the Phase A signed-file workflow: import a public Mac offer, compare code/fingerprint, generate an independent key, save a proof-of-possession request via Android SAF, import the root-signed completion and atomically activate its own Room workspace. Old unpaired facts are preserved separately. Same user/space, no third partner, no private-key import/export.

Authorized devices show active/revoked state. Existing Protocol4-v1 permits only the original owner root to grant/revoke. An enrolled Android is not silently promoted to root; original-Mac authorization/revocation UI remains required. The root device must stay available. This is not invitation-based creation of a new partner pair on Android.

Foreground C1 API2 challenge/ticket and directed authenticated-encrypted WebSockets use the existing SyncEngine; offline edits persist, foreground reconnect catches up, background cancels sockets. No permanent background connection, C2, offline mailbox or central business database. Local saved / pending / remote persisted / converged / reviewed / domain confirmed are distinct. No Delivered/read/bank-payment claim.

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

Independent protocol review, physical Samsung/dual-device use, minimum API28, real tablet/TalkBack and human visual approval remain separate gates. Upstream authorization archive remains bounded (128KiB/32 active devices), root-loss recovery/archive paging are absent, and offline revocation freshness cannot be guaranteed. OkHttp assembles messages before application bounds; adversarial-server memory behavior remains an upstream transport review item. Projection/recovery is linear in history; no Android100k claim. Unsupported platform codecs report an error and preserve original bytes. No C2, production deployment, Mac installation or real-user Protocol4 activation is implied.
