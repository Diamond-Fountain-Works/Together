# Together

Native macOS and Android, Local-first shared space for two people. Tasks, Wishes and Daily Love Gifts use a signed operation log; Our Finances uses one Expenses ledger and derived reserve balances. SwiftUI, SwiftData and the existing signed-log engine remain the architecture. Normal 0.2.2 clients use the native peer adapter; established legacy C1 Mac bindings retain their WebSocket route. No central business database, offline mailbox or banking connection is included. Android Phase B adds native Tasks, Wishes, Finances, event-driven Gifts and change review on the existing Kotlin Protocol 4 core. Phase C records physical Samsung and native Swift interoperability over a USB-reversed local Relay. Public cross-network acceptance and independent security review remain release gates.

## 0.2.3 — Chinese and English

Mac Build 21 and Android code 16 add a globe in Settings. Open its menu to
choose Chinese or English; the choice stays on that device and refreshes the
interface immediately. Gifts keep their affectionate tone; everyday actions,
statuses and errors use concise wording. User-written content stays as written.

`make localization-qa` checks complete bilingual resources, format arguments,
review hashes, mixed-language leaks and defensive filler. The existing copy
and human visual review gates remain separate. Release evidence and remaining
checks are in [0.2.3 QA](docs/qa/reports/RELEASE_0_2_3.md).

## 0.2.2 clean-install delivery preparation

The `release/0.2.2-delivery` branch prepares ordinary, empty-on-install clients:
`com.together.app` on Apple Silicon/macOS 14.5+ and `com.together.android` on
Android 9+/arm64. Existing Tasks/Wishes/Finances/Gifts and signed Protocol 4 facts
are reused. There are no bundled users, pairings, personal records or media.
Normal launches use persistent application storage and the native peer adapter;
the explicitly isolated QA targets remain separate. Legacy paired C1 Mac spaces
keep their current transport. A fresh install does not import any QA workspace.
Current candidates are Mac 0.2.2 Build 20 and Android 0.2.2/code 15. Android code
14 was withdrawn after a real invitation action exposed an R8/JNA JNI-field
crash; code 15 must pass the actual native invitation retry, not just compilation.

Actual artifact hashes, build/signing checks and remaining acceptance gates are
recorded in [0.2.2 delivery evidence](docs/qa/reports/RELEASE_0_2_2.md).
The Mac package is **not notarized**; no paid Developer ID account is available.
Android uses an external long-term release signing key, never the Debug key.
A successful build or removal of QA labels is not stable network acceptance:
full VPN-free, opposite-direction public pairing and independent security review
remain unverified until separately recorded. The source histories and earlier
reports below are historical checkpoints, not approval of the new binaries.

## Source of truth

| Location | Responsibility |
| --- | --- |
| `apps/apple/macOS/` | Xcode project, SwiftUI app, UI tests and release scripts |
| `apps/android/` | Kotlin/Compose app, Room/Keystore adapters, Protocol 4 and domain JVM modules |
| `packages/together-core-swift/` | TogetherCore library, services, storage/network adapters and Swift tests |
| `packages/together-p2p-swift/` | Native transport adapter around the unchanged Protocol 4 engine |
| `packages/together-native-source/` | Fixed Rust dependency lock, source manifest and text-only Swift/C ABI inputs |
| `services/relay/` | Cloudflare Workers / Durable Objects source, local tests and deployment instructions |
| `protocol/` | Platform-neutral DTO schemas, compatibility notes and synthetic vectors |
| `tests/integration/` | Pinned old-source restoration and isolated upgrade harness |
| `tests/conformance/` | Independent Python checks of portable vectors and JSON Schema |
| `docs/` | Product, architecture, domain, design, security, QA, roadmap and release authorities |
| `qa/visual/` | Human-approved synthetic baselines; unreviewed candidates stay local |
| `scripts/` | Build/QA orchestration and publication safety checks |

Current source is not copied per version. Old tracked source is recoverable in Git; local ignored build/release artifacts are retained. [Migration and rollback](docs/architecture/MONOREPO_MIGRATION.md) records the checkpoint and path changes. TogetherCore is currently macOS-tested and still contains Apple adapters; iOS/watchOS require further adapter work. [Android Phase A](apps/android/README.md) records the actual Kotlin/Compose/Room build and its remaining UI/device limits.

## Build and QA

Normal 0.2.2 runtime: Apple Silicon/macOS 14.5+; Swift 6 / Xcode 26+ development and the pinned Rust native build. Node 22.16+ (CI uses 24), Python 3.10+ for QA.

```sh
python3 scripts/rebuild_apple_native.py --jobs 2
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

`python3 scripts/rebuild_apple_native.py` prepares the verified source-built native dependency. `make package` emits an Apple Silicon Release app/verified DMG in `apps/apple/macOS/dist/`; it does not install, publish a binary or deploy. Version/Build: `apps/apple/macOS/Configuration/ReleaseVersion.json`. Bundle ID remains `com.together.app`; production Application Support, identity files and logs keep their paths. Ad-hoc signing is not Developer ID distribution, notarization or automatic updates.

## Networking and compatibility

Fresh normal 0.2.2 Mac and Android Apps generate a signed self-contained JSON
contact using `NativePartnerContact`, compare the verified identities and require
mutual consent. The existing co-signed genesis then activates Protocol 4 live and
catch-up replication. Native traffic uses QUIC with discovery/encrypted relay
helpers when required; selecting a relay is not direct-P2P proof or a VPN-free
network acceptance result. There is no persistent offline mailbox.

Established C1 Mac bindings retain URLSession WebSocket sync; the native Android
Release does not silently migrate an existing C1 pairing. Its missing-native-
binding state is a recovery limitation, not permission to reset a store. Legacy
TCP remains for regression. No production Worker is deployed by this release.
A sender closing before peer persistence cannot promise delivery. Application
encryption still requires [independent review](docs/security/SECURITY_REVIEW.md).
Physical independent-network acceptance remains separate from localhost tests.

Invitation purposes are distinct; [current version metadata](protocol/versions.json)
records their encoding and time authority:

| Purpose | Lifetime | Encoding and authority |
| --- | --- | --- |
| Fresh normal Mac/Android native pairing | 8 hours | Signed canonical JSON contact; issuer timestamp, receiver system-clock validation |
| C1 `/v2/partner-invitations` source implementation | 8 hours | Opaque random code; server expiry and atomic consumption |
| Legacy C1 `/v1/invitations` | 10 minutes | Opaque random code; server expiry and atomic consumption |

The native App does not call a Relay API to issue its contact and does not claim
server-controlled time. An expired invitation does not revoke an already pinned
partner; reconnect verifies current authorization and a fresh signed session.
[Issue #1](https://github.com/Diamond-Fountain-Works/Together/issues/1) and older
fixtures preserve the earlier C1 work history, not a blanket ten-minute claim
about current native pairing. Source implementation is not production deployment
verification.

App, sync and storage are separate dimensions: app 0.2.2, active signed
replication Protocol 4, preserved Protocol 3 history, and physical SwiftData
storage generation 1. Existing descriptors/keys are not relabelled or replaced
to force activation. Relay API 1/2 metadata describes optional legacy C1, not the
normal native contact. The storage index does not claim a new VersionedSchema.
Both native libraries are rebuilt from the [fixed source inputs](packages/together-native-source/README.md);
old FFI 1.1.0 prebuilt binaries contained affected Rust core 1.0.2 and cannot be
used as a safe fallback. Native dependency builds and an artifact PASS still do
not replace installed-App or independent security acceptance.

## Rules and evidence

The phase sections below retain historical implementation/evidence. For actual 0.2.2 artifact status use the clean-install delivery report above; historical PASS does not approve a newly built binary.

[AGENTS.md](AGENTS.md) indexes development rules. Authorities: [requirements](docs/product/REQUIREMENTS.md), [architecture](docs/architecture/ARCHITECTURE.md), [finance contract](docs/domains/FINANCE_PROTOCOL.md), [design](docs/design/DESIGN_SYSTEM.md), [copy](docs/design/UI_COPY.md), [tests](docs/qa/TEST_PLAN.md), [phases](docs/roadmap/PHASES.md), [changelog](docs/releases/CHANGELOG.md). [Relay instructions](services/relay/README.md) contain local/deployment operations; credentials never belong in the app/repository.

[Build 4 acceptance](docs/qa/reports/FINAL_QA_BUILD4.md) precedes migration. [Monorepo evidence](docs/qa/reports/MONOREPO_QA.md) records current results. Repository: [Diamond-Fountain-Works/Together](https://github.com/Diamond-Fountain-Works/Together), **Public** by explicit user instruction. Public source contains synthetic fixtures only; databases, keys, private media, logs and build artifacts are excluded and scanned before push.

## Historical checkpoint — Git-like C1 multi-device foundation (opt-in)

The remaining phase sections retain their original checkpoint claims and
limitations. Statements such as “not linked into production” or “Protocol 3 is
normal” describe those earlier builds; use the current sections and delivery
report above for the 0.2.2 candidates. They are not live PR/deployment status.

[Replication architecture](docs/architecture/GITLIKE_REPLICATION.md) and [wire contract](protocol/REPLICATION_V4.md) describe the new versioned capability. A stable two-person space can authorize independent device keys without changing old user/space IDs. Protocol 4 adds certified durable history, paged content inventory, per-device signed persistence receipts, background/scoped projection, universal change review and additive Relay API 2 directed sessions. The unchanged Protocol 3 path remains the normal released flow; native signed-file enrollment and two-Mac migration confirmation are implemented; desktop acceptance, independent review and deployment remain incomplete.

Local integration uses four native Swift clients and an actual loopback Worker, including media verification, offline catch-up and revocation. [Draft stacked PR #4](https://github.com/Diamond-Fountain-Works/Together/pull/4) depends on Monorepo PR #2; neither is automatically merged. [C1 QA](docs/qa/reports/GITLIKE_C1_QA.md) records fresh counts, 100,000-operation measurements and explicit release blockers. This is not physical cross-WiFi or Android acceptance. The independent [8-hour invitation PR #3](https://github.com/Diamond-Fountain-Works/Together/pull/3) has not been deployed; ten minutes remains the core branch/last-known deployment behavior.

[Device enrollment](protocol/DEVICE_ENROLLMENT.md) and [ADR 006](docs/architecture/adr/006-native-device-enrollment.md) describe the native add/list/revoke workflow and independent-key storage. [Hardening evidence](docs/qa/reports/C1_HARDENING.md) separates incident findings, actual 100k measurements, headless tests and blocked desktop acceptance. QA must use the dedicated host and loopback service, never normal Debug as a fallback.

## Historical checkpoint — Android clients (stacked on Protocol 4)

`make android-qa` builds a real Debug APK, runs shared Kotlin protocol/domain vectors, Android lint and Android copy audit. An explicit loopback Relay URL enables the three-device actual WebSocket integration test; absent URL is reported SKIP. Native Swift validates Kotlin-produced certificates, projection and encrypted packets without changing the Mac business implementation. [Android instructions](apps/android/README.md) distinguish JVM, instrumented runtime, emulator and physical-device evidence. No production Relay deployment, Mac installation or real-user Protocol 4 activation is authorized.

[Android Phase B architecture](docs/architecture/ANDROID_BUSINESS_PHASE_B.md) and [QA report](docs/qa/reports/ANDROID_PHASE_B.md) distinguish native/JVM C1, Android emulator, actual APK replacement and physical-device results. No parent PR is merged. Shared original-media bytes and receipts reuse the existing authenticated channel; no mailbox, C2 or Worker deployment is added.

[Physical Phase C evidence](docs/qa/reports/ANDROID_PHASE_C.md) keeps real Samsung results separate
from historical emulator results. [Device acceptance](docs/architecture/ANDROID_DEVICE_ACCEPTANCE.md)
defines the opt-in, same-signer, non-destructive instrumentation path; do not use Gradle connected
tests on a phone whose test data must be retained. The [staging plan](docs/qa/ANDROID_STAGING_ACCEPTANCE.md)
is unexecuted and requires separate deployment authorization. Main [branch protection](docs/security/REPOSITORY_PROTECTION.md)
requires PRs and the existing CI checks; it is not permission to merge or deploy.

## Historical checkpoint — Native partner pairing correction

Current Plans correction on both platforms: **Pending / Completed** only;
Upcoming is included in Pending. [Build 13 / Android code 8 evidence](docs/qa/reports/UNIFIED_PLANS.md)
records native tests, candidate screenshots and the non-destructive local upgrade.

Partner invitations now have a native create/join text interface, separate from
own-device signed-file enrollment. Signed bootstrap history activates the existing
Protocol 4 engine with recoverable join/genesis state. [Pairing evidence](docs/qa/reports/NATIVE_PARTNER_PAIRING.md)
separates local, physical, VPN-dependent and failed VPN-free tests. Production
API 1 is unchanged. The current Workers endpoint is not a verified VPN-free path
on the tested mobile network; P2P is a separate transport change.

## Historical checkpoint — Native App transport acceptance (isolated QA builds)

[The normal-App checkpoint](docs/qa/reports/NATIVE_APP_NETWORK_ACCEPTANCE.md)
records an actual Samsung-initiated pairing, explicit identity confirmation,
task persistence with a signed remote ACK, offline edits/catch-up and Samsung
process restart through the SwiftUI/Compose Apps. The Samsung used mobile data
without VPN; the Mac still used a VPN. The successful path was an encrypted relay,
so this is **not VPN-free or public direct-P2P acceptance**. Subsequent normal-App
reserve, shared/AA expense and beneficiary-confirmed wish results also agree.
Reverse invitation, broader recurring-bill cases and original-media acceptance
remain separate checks.
Only dedicated QA bundles are used; the production Mac App is not replaced.

[Architecture and actual gates](docs/architecture/P2P_INCREMENTAL_REPLICATION.md)
record the user's new transport direction. The optional `TogetherP2P` package uses
native Iroh QUIC around the existing signed Protocol 4 log. `make p2p-test` tests a
relay-disabled direct link, paged history, durable ACKs, tombstone convergence and
identity/replay rejection. It does not link into the production app yet. A
test-only Android adapter and bounded physical driver are also retained; see
[earlier transport-only evidence](docs/qa/reports/P2P_PUBLIC_ACCEPTANCE.md). Compiling
the instrumentation is not physical/public-network acceptance. Public NAT
traversal, platform compatibility and independent security review remain open;
installed applications are not silently described as P2P-capable.

The physical driver distinguishes independent public networks, a shared-hotspot
LAN, and an explicitly constrained public encrypted-relay test over a shared
uplink. The latter two cannot approve independent-network NAT traversal. It
requires an awake/unlocked phone, exact persisted checkpoints and ACKs, actual
test-process exit, network-binding restoration and fresh-process recovery; no
device unlock or system network setting is automated.
