# Together protocol compatibility

## Current platform backport — no wire-format revision

The 0.2.4 compatibility branch prepares Apple Silicon macOS 11 and native
iOS/iPadOS 15 clients while reusing the existing signed replication and native
partner adapters. Deployment metadata and successful compilation do not certify
every device/OS release; inspect the actual Mach-O minimums, embedded runtime,
platform QA and release report. An older SDK plus explicit frontend target is
needed to avoid a macOS 11-labelled SwiftPM build being raised to 12. iOS
simulator/physical acceptance remains NOT RUN when unavailable or skipped;
watchOS is not implemented.

The persistence implementation is not the protocol. Modern Apple systems retain
the existing three SwiftData model types/fields. Older systems use a marked
system-SQLite backend with the same canonical operations, local records,
transactional quota/head/ACK semantics and bounded inventory pages. A legacy
SQLite store stays readable after an OS upgrade; an existing modern/unknown store
is never reset or silently downgraded to make an old OS accept it. Owned-file and
read-only modern-schema checks precede writable opening. The legacy SQLite marker
and schema version are local implementation metadata, not changes to signed DTOs
or the database-generation number assigned to the existing SwiftData models.

UUID encoding, millisecond timestamps, canonical JSON, operation IDs/signatures,
Lamport/device/operation tie-breaks, Tombstones, authorization epochs, media
hashes/chunks and per-device persistence receipts are unchanged. Original keys,
User IDs, Device IDs, SharedSpace IDs and saved pairings are retained. A socket
send or an OS background transition does not imply remote persistence, review or
business confirmation. No transport/server deployment, new central ledger,
mailbox or protocol activation is authorized by lowering a deployment target.

The historical C1/monorepo baseline below is retained for its versioned migration
contracts. Current purpose-specific invite encoding and time authority are
recorded in `versions.json` and `NATIVE_PARTNER_INVITATION_V1.md`; platform work
does not change those rules.

## Historical monorepo and C1 baseline

App Version/Build: authoritative source apps/apple/macOS/Configuration/ReleaseVersion.json. Device/sync feature protocol: 3. Relay API/frame protocol: 1. Database storage generation: 1 (existing three SwiftData models, no migration/change in this refactor). These are independent dimensions. The opt-in Git-like foundation additionally supports replication **4** / Relay API **2**, with the same physical storage generation. Default normal pairing remains Device 3 / Relay 1; activating 4 requires an explicit verified migration, not a build-number guess.

C1 HTTPS/WSS realtime relay remains active; C2 Iroh/P2P is future work. No encrypted mailbox. Signed operations are ordered by Lamport/device/operation ID, not system time. Server routes encrypted frames; clients validate signatures/membership and merge. Core namespace TogetherCore, Bundle ID and Application Support/identity/pairing locations are unchanged.

UUIDs are uppercase canonical strings; dates are integer epoch milliseconds within the existing 1900–3000 range; civil dates/months have Gregorian components and explicit IANA zones. LogValue uses Swift Codable's existing tagged JSON shape, including _0 values, base64 data and null {}. Do not replace this without a versioned protocol change. Financial amount minor units and rate are strings; CNY rounding is HALF_UP and stored historical settlements are immutable. Other Int64 envelope fields remain JSON integers and must use lossless 64-bit handling in Kotlin/other clients.

Schemas describe portable DTOs and the current signed envelope, never SwiftData objects. DeviceIdentity schema exposes only the public DeviceDescriptor; private identity material is not a protocol field. Stored local paths are derived from verified asset IDs, not accepted from remote absolute paths. Models which are derived-only (balance, allocations, rendered occurrence) are not another authoritative ledger.

## Historical invitation requirement gap (monorepo baseline)

The formally approved lifetime is **8 hours / 28800000ms**, one successful use. At the historical monorepo baseline, the old implementation was **10 minutes / 600000ms**. [PR #3](https://github.com/Diamond-Fountain-Works/Together/pull/3) implements the independent coordinated fix locally; production deployment is separately authorized. The target vector is explicitly pending and is not reported as a passed current capability. Nonces/socket tickets keep independent 60-second lifetimes.

## Cross-platform status

The shared Swift Core conditionally exposes SwiftData on macOS 14/iOS 17 and uses the same repository contract on earlier supported systems. AppKit and UIKit adapters are separated. The 0.2.4 candidate compiles the native macOS and generic-device iPhone/iPad frontends; this does not certify runtime behavior on every target OS, and watchOS remains unimplemented. Android has a native Kotlin/Room client; [Phase B evidence](../docs/qa/reports/ANDROID_PHASE_B.md) is historical. [Phase C](../docs/qa/reports/ANDROID_PHASE_C.md) records physical Samsung/native Swift interoperability through a local USB-reversed Worker, not public cross-WiFi or Mac GUI acceptance. The compatibility branch separately reruns a four-native-client C1 migration/catch-up/revocation test and the Swift–Kotlin native bridge against isolated loopback Workers. These are protocol/runtime integration tests, not normal GUI or physical-network acceptance. Fixtures remain the shared behavioral contract.

## Protocol 4 opt-in compatibility

[Wire contract](REPLICATION_V4.md), [architecture](../docs/architecture/GITLIKE_REPLICATION.md), [JSON Schema](schemas/replication-v4.schema.json) and [synthetic signed vectors](fixtures/replication-v4.json) define the additional capability. Protocol 3 SignedOperation/LogValue canonical bytes and signatures remain unchanged inside the versioned certificate. Original IDs/keys/space aliases and V1 binding survive migration. Raw V3 merge is rejected once a replica activates V4; it must receive the certified legacy checkpoint or an epoch-authorized wrapper through V4. An incompatible client fails explicitly; it never silently replaces membership.

App Build 10 is development evidence, not an automatic rollout. Relay API 2 has only local tests and no deployment authorization. Native enrollment/migration exchange is implemented with public signed files and independent device keys; desktop/human acceptance, external security review, physical interoperability and coordinated rollout remain release gates. See DEVICE_ENROLLMENT.md.

## Android Phase A consumer

`apps/android/core/protocol` consumes the unchanged P4/Enrollment/finance contracts. Pure JVM tests verify existing Swift signatures and `LogValue` bytes; the new public synthetic `android-phase-a-v4.json` is verified/replayed by `AndroidPhaseAConformanceTests.swift`, including BC↔CryptoKit encrypted framing. App version, Room schema 1 and P4/API2 are separate. Android does not speak legacy P3 live transport: it retains/verifies historical signed bytes under the co-signed migration checkpoint. No production P4 activation or physical interoperability is inferred from vectors/local tests.

## Android Phase B media and business consumer

The existing P4 signed envelope, enrollment, authorization epochs, per-device ACK and finance facts are unchanged. Native business editors emit the existing operations atomically into Room1. On-demand effective review is a local derived projection, not another ledger or wire format.

The existing authenticated `media` content channel carries Codable `mediaRequest/Chunk/Complete/Verified/Failure` and `giftReceipt`. Raw chunks are exactly at most65536 bytes; original files are never put in a signed operation payload. Swift UUID-keyed receipt hashes use the existing alternating JSON array encoding, normalized in Kotlin. A content receipt binds gift/creation operation/recipient/exact asset hashes; a same-user device or log ACK cannot claim partner media completion. Actual native Swift/Kotlin C1 tests cover this encoding and SHA equality. No new protocol version, migration or production rollout is introduced.
