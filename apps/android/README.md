# Together Android — Phase A

Native Kotlin / Jetpack Compose / Room client, isolated from the Apple build. Android phone and tablet use the same domain/state/Room implementation; width ≥600dp selects a navigation rail. Minimum Android 9 (API 28), compile/target 36, JDK 21 running Gradle 8.13, Java/Kotlin bytecode 17. No production Relay address, user records or credentials are bundled.

## Build

```sh
# At repository root; point ANDROID_HOME at an existing SDK, or use ignored local.properties.
make android-qa
# Requires a dedicated emulator (the automated Runner rejects physical hardware):
cd apps/android
./gradlew :app:connectedDebugAndroidTest
```

Debug APK: `apps/android/app/build/outputs/apk/debug/app-debug.apk`; application ID `com.together.android.debug`. Normal production ID is reserved as `com.together.android`; there is no signed production Android release. A debug build is not a Play Store release, physical-phone acceptance or production API 2 activation. Do not uninstall an installation holding real data to resolve a signing mismatch.

`app` owns Compose, lifecycle, Android Keystore and Room adapters. `core/protocol` is a pure JVM implementation of the existing Protocol 4 contracts and native OkHttp transport. `core/domain` projects authorized facts and implements existing money/calendar/task/wish/gift/finance rules. Shared fixtures are read directly from `protocol/fixtures`; ISO precision is packaged from the existing authoritative Swift resource, not a second currency list. Room schema JSON is checked in. SwiftData, Apple identities, original SharedSpace IDs and production Relay code are unchanged.

## Functional scope

- Real local task create/edit/complete/reopen/delete; one editor. Private unpaired workspace can work offline. Joining an existing space refuses to overwrite local business data; the old database is preserved.
- Add My Device imports a public signed Mac offer, shows the comparison code/fingerprint, generates an independent identity, saves a proof-of-possession request via Storage Access Framework, imports the root-signed completion and activates a separate Room workspace atomically. Same stable user/space, independent device/key. No third partner and no private-key import/export.
- Authorized device list, active/revoked state, owner-root authorization boundary. Protocol 4 v1 permits only the original owner root to grant/revoke. An enrolled Android is not silently promoted to root: management requiring that root is performed on the original Mac. Domain/API revocation support is present for an identity that actually is the root.
- Signed inner operations and outer device certificates, staged chain/baseline recovery, Lamport/UUID merge, tombstones, 128-entry inventory, 32-operation/240000-byte batches, exact signed per-device ACK and protected local membership. Data commits precede receipts. Change history/review is local and separate from domain confirmation.
- Foreground C1 API 2 challenge/ticket, directed per-device encrypted WebSockets, automatic exponential retry/catch-up. Background lifecycle cancels sockets; reopening reconnects. Pure real-time Relay, no offline mailbox. Local saved, pending synchronization, partner persisted and global connection are distinct; no Delivered/read/payment claim.
- Domain layer covers Tasks/Regular/Flexible recurrence, wishes/confirmation, one finance ledger, frozen CNY/AA/reserves/calendar bills/revisions, daily gift quota and sealed change metadata. Complete Android Wishes/Finance/Gift/media UI is subsequent work, not a set of placeholder pages.

## Safety and limits

Each Ed25519 seed is generated independently using Bouncy Castle primitives and AES-GCM wrapped by an Android Keystore AES key. Ed25519 is software, not advertised as hardware-backed. Android backup and device transfer exclude app facts/identity. Missing/invalidated wrapping keys fail closed. Uninstall/device loss can destroy Keystore access: there is no secret recovery or root-key replacement protocol; preserve the original trusted root and reenroll a genuinely new device. Existing local records are never silently reset.

Pairwise X25519/HKDF-SHA256/ChaCha20-Poly1305 and canonical signing match existing Swift fixtures. Independent protocol review remains a release gate. No new cryptographic design, C2, server deployment or real-user activation is implied. The current control archive remains bounded at 128KiB/32 active devices; paging/root-loss recovery remain absent upstream. Revocation freshness while offline cannot be guaranteed.

Media manifests/history are retained, but Android binary attachment transfer, original-image UI and gift/media receipts are not implemented in Phase A. The client does not acknowledge media as complete. OkHttp callbacks enforce bounded frame/application queues, but OkHttp assembles an incoming message before the callback; an adversarial-server oversized-message memory boundary needs separate transport review. Replay and content validation do not establish independent security approval. Projection/recovery remains linear in history; no Android 100k performance claim.

## Local integration and interoperability

Run the existing Worker only locally, with separate state:

```sh
cd services/relay
npm ci --legacy-peer-deps
./node_modules/.bin/wrangler dev --local --ip 127.0.0.1 --port 8796 --persist-to ../../qa/results/android-phase-a/relay-state
# In another shell, repository root:
TOGETHER_LOCAL_RELAY_URL=http://127.0.0.1:8796 make android-qa
```

Without the explicit loopback URL, the local-runtime integration test reports SKIP, not PASS. It provisions only synthetic legacy roots, bootstraps API 2, authorizes a same-user third device, tests simultaneous sessions/offline catch-up and checks exact ACKs. It never calls the production Worker.

`AndroidPhaseAConformanceTests.swift` verifies Kotlin-produced public certificates/business projection and opens its Bouncy Castle packet with CryptoKit. For the reverse response test:

```sh
mkdir -p qa/results/android-phase-a
TOGETHER_ANDROID_RESPONSE_PATH="$PWD/qa/results/android-phase-a/cryptokit-response.json" swift test --package-path packages/together-core-swift --filter AndroidPhaseAConformanceTests
TOGETHER_ANDROID_RESPONSE_PATH="$PWD/qa/results/android-phase-a/cryptokit-response.json" apps/android/gradlew -p apps/android :core:domain:test --rerun-tasks
```

The deterministic synthetic fixture is exported only by an explicit developer flag; normal tests cannot overwrite it. Cryptographic fixtures/native library tests are not physical Mac↔phone acceptance.

Toolchain basis: [AGP compatibility](https://developer.android.com/build/releases/agp-8-13-0-release-notes), [Compose compiler](https://developer.android.com/develop/ui/compose/setup-compose-dependencies-and-compiler), [Room](https://developer.android.com/jetpack/androidx/releases/room), [Bouncy Castle Java](https://www.bouncycastle.org/documentation/documentation-java/). Dependency versions are pinned to a tested baseline; lint upgrade advisories remain visible.

Status/evidence and next steps: [Android Phase A QA](../../docs/qa/reports/ANDROID_PHASE_A.md).

The final local source/Debug APK, exact SHA-256, 31 JVM / 7 emulator results and 17 unapproved screenshot candidates are recorded there. Android instrumentation was run on Android 15/API35 ARM64 only; minimum API28, physical phones/tablets and real Mac↔Android acceptance remain NOT RUN. [Draft PR #5](https://github.com/Diamond-Fountain-Works/Together/pull/5) is stacked on the unmerged Protocol 4 branch; hosted CI does not claim emulator coverage.
