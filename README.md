# Together

Native macOS and Android, Local-first shared space for two people. Tasks, Wishes and Daily Love Gifts use a signed operation log; Our Finances uses one Expenses ledger and derived reserve balances. SwiftUI, SwiftData and the current C1 WebSocket Relay remain the architecture. No central business database, offline mailbox or banking connection is included. Android Phase B adds native Tasks, Wishes, Finances, event-driven Gifts and change review on the existing Kotlin Protocol 4 core. Phase C records physical Samsung and native Swift interoperability over a USB-reversed local Relay. Public cross-network acceptance and independent security review remain release gates.

## Source of truth

| Location | Responsibility |
| --- | --- |
| `apps/apple/macOS/` | Xcode project, SwiftUI app, UI tests and release scripts |
| `apps/android/` | Kotlin/Compose app, Room/Keystore adapters, Protocol 4 and domain JVM modules |
| `packages/together-core-swift/` | TogetherCore library, services, storage/network adapters and Swift tests |
| `services/relay/` | Cloudflare Workers / Durable Objects source, local tests and deployment instructions |
| `protocol/` | Platform-neutral DTO schemas, compatibility notes and synthetic vectors |
| `tests/integration/` | Pinned old-source restoration and isolated upgrade harness |
| `tests/conformance/` | Independent Python checks of portable vectors and JSON Schema |
| `docs/` | Product, architecture, domain, design, security, QA, roadmap and release authorities |
| `qa/visual/` | Human-approved synthetic baselines; unreviewed candidates stay local |
| `scripts/` | Build/QA orchestration and publication safety checks |

Current source is not copied per version. Old tracked source is recoverable in Git; local ignored build/release artifacts are retained. [Migration and rollback](docs/architecture/MONOREPO_MIGRATION.md) records the checkpoint and path changes. TogetherCore is currently macOS-tested and still contains Apple adapters; iOS/watchOS require further adapter work. [Android Phase A](apps/android/README.md) records the actual Kotlin/Compose/Room build and its remaining UI/device limits.

## Build and QA

macOS 14+ runtime; Swift 6 / Xcode 26+ development. Node 22.16+ (CI uses 24), Python 3.10+ for QA.

```sh
cd services/relay
npm ci --legacy-peer-deps
cd ../..
make build
make test
make qa
make package
```

`make qa` starts its own loopback Worker with private state, creates an old database from pinned Git source, runs Swift/relay/protocol/copy/security tests, builds Debug, runs native UI tests and compares screenshots. Production stores, media, identities and pairing records are not test fixtures. `./scripts/qa.sh --skip-ui` is for headless CI and reports UI/visual **NOT RUN**. [CI scope](docs/qa/CI.md) separates hosted checks from local desktop and real two-Mac acceptance.

`make visual-review` builds the [local screenshot review](docs/qa/VISUAL_REVIEW.md) from frozen captures and approved hashes. It supports side-by-side, wipe/overlay, zoom, Frame evidence and local human feedback; it never approves baselines or merges a PR.

`make package` emits a Universal Release app/verified DMG in `apps/apple/macOS/dist/`; it does not install, publish a binary or deploy. Version/Build: `apps/apple/macOS/Configuration/ReleaseVersion.json`. Bundle ID remains `com.together.app`; production Application Support, identity files and logs keep their paths. Ad-hoc signing is not Developer ID distribution, notarization or automatic updates.

## Networking and compatibility

Normal pairing uses an invitation and explicit mutual identity confirmation, then native URLSession WebSocket live/catch-up sync. Legacy TCP remains for regression; this refactor does not switch to C2 or deploy a Worker. Relay forwards online ciphertext only; a sender closing before peer sync cannot promise delivery. Application-encryption framing still requires [independent security review](docs/security/SECURITY_REVIEW.md). Physical two-Mac/different-Wi-Fi acceptance is separate from localhost or one-Mac public-service tests.

**Invitation lifetime:** current code is **10 minutes**. The formal product requirement is **8 hours**; [Issue #1](https://github.com/Diamond-Fountain-Works/Together/issues/1) tracks a separate coordinated protocol/client/server/test change and later deployment. This refactor preserves runtime behavior.

App, sync protocol and storage generation are [separate dimensions](protocol/versions.json): device protocol 3, Relay service protocol 1, physical SwiftData storage generation 1. Protocol 2/3 client mismatch is diagnosed; upgraded identities/routes remain pinned. The storage generation index does not claim a new VersionedSchema migration.

## Rules and evidence

[AGENTS.md](AGENTS.md) indexes development rules. Authorities: [requirements](docs/product/REQUIREMENTS.md), [architecture](docs/architecture/ARCHITECTURE.md), [finance contract](docs/domains/FINANCE_PROTOCOL.md), [design](docs/design/DESIGN_SYSTEM.md), [copy](docs/design/UI_COPY.md), [tests](docs/qa/TEST_PLAN.md), [phases](docs/roadmap/PHASES.md), [changelog](docs/releases/CHANGELOG.md). [Relay instructions](services/relay/README.md) contain local/deployment operations; credentials never belong in the app/repository.

[Build 4 acceptance](docs/qa/reports/FINAL_QA_BUILD4.md) precedes migration. [Monorepo evidence](docs/qa/reports/MONOREPO_QA.md) records current results. Repository: [Diamond-Fountain-Works/Together](https://github.com/Diamond-Fountain-Works/Together), **Public** by explicit user instruction. Public source contains synthetic fixtures only; databases, keys, private media, logs and build artifacts are excluded and scanned before push.

## Git-like C1 multi-device foundation (opt-in)

[Replication architecture](docs/architecture/GITLIKE_REPLICATION.md) and [wire contract](protocol/REPLICATION_V4.md) describe the new versioned capability. A stable two-person space can authorize independent device keys without changing old user/space IDs. Protocol 4 adds certified durable history, paged content inventory, per-device signed persistence receipts, background/scoped projection, universal change review and additive Relay API 2 directed sessions. The unchanged Protocol 3 path remains the normal released flow; native signed-file enrollment and two-Mac migration confirmation are implemented; desktop acceptance, independent review and deployment remain incomplete.

Local integration uses four native Swift clients and an actual loopback Worker, including media verification, offline catch-up and revocation. [Draft stacked PR #4](https://github.com/Diamond-Fountain-Works/Together/pull/4) depends on Monorepo PR #2; neither is automatically merged. [C1 QA](docs/qa/reports/GITLIKE_C1_QA.md) records fresh counts, 100,000-operation measurements and explicit release blockers. This is not physical cross-WiFi or Android acceptance. The independent [8-hour invitation PR #3](https://github.com/Diamond-Fountain-Works/Together/pull/3) has not been deployed; ten minutes remains the core branch/last-known deployment behavior.

[Device enrollment](protocol/DEVICE_ENROLLMENT.md) and [ADR 006](docs/architecture/adr/006-native-device-enrollment.md) describe the native add/list/revoke workflow and independent-key storage. [Hardening evidence](docs/qa/reports/C1_HARDENING.md) separates incident findings, actual 100k measurements, headless tests and blocked desktop acceptance. QA must use the dedicated host and loopback service, never normal Debug as a fallback.

## Android clients (stacked on Protocol 4)

`make android-qa` builds a real Debug APK, runs shared Kotlin protocol/domain vectors, Android lint and Android copy audit. An explicit loopback Relay URL enables the three-device actual WebSocket integration test; absent URL is reported SKIP. Native Swift validates Kotlin-produced certificates, projection and encrypted packets without changing the Mac business implementation. [Android instructions](apps/android/README.md) distinguish JVM, instrumented runtime, emulator and physical-device evidence. No production Relay deployment, Mac installation or real-user Protocol 4 activation is authorized.

[Android Phase B architecture](docs/architecture/ANDROID_BUSINESS_PHASE_B.md) and [QA report](docs/qa/reports/ANDROID_PHASE_B.md) distinguish native/JVM C1, Android emulator, actual APK replacement and physical-device results. No parent PR is merged. Shared original-media bytes and receipts reuse the existing authenticated channel; no mailbox, C2 or Worker deployment is added.

[Physical Phase C evidence](docs/qa/reports/ANDROID_PHASE_C.md) keeps real Samsung results separate
from historical emulator results. [Device acceptance](docs/architecture/ANDROID_DEVICE_ACCEPTANCE.md)
defines the opt-in, same-signer, non-destructive instrumentation path; do not use Gradle connected
tests on a phone whose test data must be retained. The [staging plan](docs/qa/ANDROID_STAGING_ACCEPTANCE.md)
is unexecuted and requires separate deployment authorization. Main [branch protection](docs/security/REPOSITORY_PROTECTION.md)
requires PRs and the existing CI checks; it is not permission to merge or deploy.

## Native partner pairing correction (development)

Current Plans correction on both platforms: **Pending / Completed** only;
Upcoming is included in Pending. [Build 13 / Android code 8 evidence](docs/qa/reports/UNIFIED_PLANS.md)
records native tests, candidate screenshots and the non-destructive local upgrade.

Partner invitations now have a native create/join text interface, separate from
own-device signed-file enrollment. Signed bootstrap history activates the existing
Protocol 4 engine with recoverable join/genesis state. [Pairing evidence](docs/qa/reports/NATIVE_PARTNER_PAIRING.md)
separates local, physical, VPN-dependent and failed VPN-free tests. Production
API 1 is unchanged. The current Workers endpoint is not a verified VPN-free path
on the tested mobile network; P2P is a separate transport change.

## VPN-free P2P workstream (not installed)

[Architecture and actual gates](docs/architecture/P2P_INCREMENTAL_REPLICATION.md)
record the user's new transport direction. The optional `TogetherP2P` package uses
native Iroh QUIC around the existing signed Protocol 4 log. `make p2p-test` tests a
relay-disabled direct link, paged history, durable ACKs, tombstone convergence and
identity/replay rejection. It does not link into the production app yet. Android,
public NAT traversal, platform compatibility and independent security review
remain open; installed applications are not silently described as P2P-capable.
