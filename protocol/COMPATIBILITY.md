# Together protocol compatibility

App Version/Build: authoritative source apps/apple/macOS/Configuration/ReleaseVersion.json. Device/sync feature protocol: 3. Relay API/frame protocol: 1. Database storage generation: 1 (existing three SwiftData models, no migration/change in this refactor). These are independent dimensions. The opt-in Git-like foundation additionally supports replication **4** / Relay API **2**, with the same physical storage generation. Default normal pairing remains Device 3 / Relay 1; activating 4 requires an explicit verified migration, not a build-number guess.

C1 HTTPS/WSS realtime relay remains active; C2 Iroh/P2P is future work. No encrypted mailbox. Signed operations are ordered by Lamport/device/operation ID, not system time. Server routes encrypted frames; clients validate signatures/membership and merge. Core namespace TogetherCore, Bundle ID and Application Support/identity/pairing locations are unchanged.

UUIDs are uppercase canonical strings; dates are integer epoch milliseconds within the existing 1900–3000 range; civil dates/months have Gregorian components and explicit IANA zones. LogValue uses Swift Codable's existing tagged JSON shape, including _0 values, base64 data and null {}. Do not replace this without a versioned protocol change. Financial amount minor units and rate are strings; CNY rounding is HALF_UP and stored historical settlements are immutable. Other Int64 envelope fields remain JSON integers and must use lossless 64-bit handling in Kotlin/other clients.

Schemas describe portable DTOs and the current signed envelope, never SwiftData objects. DeviceIdentity schema exposes only the public DeviceDescriptor; private identity material is not a protocol field. Stored local paths are derived from verified asset IDs, not accepted from remote absolute paths. Models which are derived-only (balance, allocations, rendered occurrence) are not another authoritative ledger.

## Invitation requirement gap

The formally approved lifetime is **8 hours / 28800000ms**, one successful use. The current old implementation remains **10 minutes / 600000ms** on this core network branch. [PR #3](https://github.com/Diamond-Fountain-Works/Together/pull/3) implements the independent coordinated fix locally; production deployment is separately authorized. The target vector is explicitly pending and is not reported as a passed current capability. Nonces/socket tickets keep independent 60-second lifetimes.

## Cross-platform status

macOS Swift Core is extracted and tested. It still contains SwiftData, Network and macOS AppKit/ImageIO adapters; iOS/watchOS builds are not claimed. Future Apple clients can reuse domain logic after narrowing platform adapters. Android now has a native Kotlin/Room client; [Phase B evidence](../docs/qa/reports/ANDROID_PHASE_B.md) is historical. [Phase C](../docs/qa/reports/ANDROID_PHASE_C.md) records physical Samsung/native Swift interoperability through a local USB-reversed Worker, not public cross-WiFi or Mac GUI acceptance. Fixtures remain the shared behavioral contract.

## Protocol 4 opt-in compatibility

[Wire contract](REPLICATION_V4.md), [architecture](../docs/architecture/GITLIKE_REPLICATION.md), [JSON Schema](schemas/replication-v4.schema.json) and [synthetic signed vectors](fixtures/replication-v4.json) define the additional capability. Protocol 3 SignedOperation/LogValue canonical bytes and signatures remain unchanged inside the versioned certificate. Original IDs/keys/space aliases and V1 binding survive migration. Raw V3 merge is rejected once a replica activates V4; it must receive the certified legacy checkpoint or an epoch-authorized wrapper through V4. An incompatible client fails explicitly; it never silently replaces membership.

App Build 10 is development evidence, not an automatic rollout. Relay API 2 has only local tests and no deployment authorization. Native enrollment/migration exchange is implemented with public signed files and independent device keys; desktop/human acceptance, external security review, physical interoperability and coordinated rollout remain release gates. See DEVICE_ENROLLMENT.md.

## Android Phase A consumer

`apps/android/core/protocol` consumes the unchanged P4/Enrollment/finance contracts. Pure JVM tests verify existing Swift signatures and `LogValue` bytes; the new public synthetic `android-phase-a-v4.json` is verified/replayed by `AndroidPhaseAConformanceTests.swift`, including BC↔CryptoKit encrypted framing. App version, Room schema 1 and P4/API2 are separate. Android does not speak legacy P3 live transport: it retains/verifies historical signed bytes under the co-signed migration checkpoint. No production P4 activation or physical interoperability is inferred from vectors/local tests.

## Android Phase B media and business consumer

The existing P4 signed envelope, enrollment, authorization epochs, per-device ACK and finance facts are unchanged. Native business editors emit the existing operations atomically into Room1. On-demand effective review is a local derived projection, not another ledger or wire format.

The existing authenticated `media` content channel carries Codable `mediaRequest/Chunk/Complete/Verified/Failure` and `giftReceipt`. Raw chunks are exactly at most65536 bytes; original files are never put in a signed operation payload. Swift UUID-keyed receipt hashes use the existing alternating JSON array encoding, normalized in Kotlin. A content receipt binds gift/creation operation/recipient/exact asset hashes; a same-user device or log ACK cannot claim partner media completion. Actual native Swift/Kotlin C1 tests cover this encoding and SHA equality. No new protocol version, migration or production rollout is introduced.
