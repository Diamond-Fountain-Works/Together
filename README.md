# Together

Native macOS, Local-first shared space for two people. Tasks, Wishes and Daily Love Gifts use a signed operation log; Our Finances uses one Expenses ledger and derived reserve balances. SwiftUI, SwiftData and the current C1 WebSocket Relay remain the architecture. No central business database, offline mailbox, banking connection or Android app is included.

## Source of truth

| Location | Responsibility |
| --- | --- |
| `apps/apple/macOS/` | Xcode project, SwiftUI app, UI tests and release scripts |
| `packages/together-core-swift/` | TogetherCore library, services, storage/network adapters and Swift tests |
| `services/relay/` | Cloudflare Workers / Durable Objects source, local tests and deployment instructions |
| `protocol/` | Platform-neutral DTO schemas, compatibility notes and synthetic vectors |
| `tests/integration/` | Pinned old-source restoration and isolated upgrade harness |
| `tests/conformance/` | Independent Python checks of portable vectors and JSON Schema |
| `docs/` | Product, architecture, domain, design, security, QA, roadmap and release authorities |
| `qa/visual/` | Human-approved synthetic baselines; unreviewed candidates stay local |
| `scripts/` | Build/QA orchestration and publication safety checks |

Current source is not copied per version. Old tracked source is recoverable in Git; local ignored build/release artifacts are retained. [Migration and rollback](docs/architecture/MONOREPO_MIGRATION.md) records the checkpoint and path changes. TogetherCore is currently macOS-tested and still contains Apple adapters; iOS/watchOS require further adapter work. [Android boundary](apps/android/README.md) documents future Kotlin/Compose/Room work without a template app.

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

**Invitation lifetime:** this branch implements one-use **8 hours**, controlled by server time. Production was last audited at **10 minutes** and is not changed by this source PR. The client already renders the actual server `expiresAt`, so it does not advertise a hardcoded lifetime. [Issue #1](https://github.com/Diamond-Fountain-Works/Together/issues/1) remains open until separately authorized deployment and production verification. Challenges/tickets stay 60 seconds; old pair bindings remain valid.

App, sync protocol and storage generation are [separate dimensions](protocol/versions.json): device protocol 3, Relay service protocol 1, physical SwiftData storage generation 1. Protocol 2/3 client mismatch is diagnosed; upgraded identities/routes remain pinned. The storage generation index does not claim a new VersionedSchema migration.

## Rules and evidence

[AGENTS.md](AGENTS.md) indexes development rules. Authorities: [requirements](docs/product/REQUIREMENTS.md), [architecture](docs/architecture/ARCHITECTURE.md), [finance contract](docs/domains/FINANCE_PROTOCOL.md), [design](docs/design/DESIGN_SYSTEM.md), [copy](docs/design/UI_COPY.md), [tests](docs/qa/TEST_PLAN.md), [phases](docs/roadmap/PHASES.md), [changelog](docs/releases/CHANGELOG.md). [Relay instructions](services/relay/README.md) contain local/deployment operations; credentials never belong in the app/repository.

[Build 4 acceptance](docs/qa/reports/FINAL_QA_BUILD4.md) precedes migration. [Monorepo evidence](docs/qa/reports/MONOREPO_QA.md) records current results. Repository: [Diamond-Fountain-Works/Together](https://github.com/Diamond-Fountain-Works/Together), **Public** by explicit user instruction. Public source contains synthetic fixtures only; databases, keys, private media, logs and build artifacts are excluded and scanned before push.
