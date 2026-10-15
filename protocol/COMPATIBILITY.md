# Together protocol compatibility

App Version/Build: authoritative source apps/apple/macOS/Configuration/ReleaseVersion.json. Device/sync feature protocol: 3. Relay API/frame protocol: 1. Database storage generation: 1 (existing three SwiftData models, no migration/change in this refactor). These are independent dimensions; a build increment does not change transport or storage.

C1 HTTPS/WSS realtime relay remains active; C2 Iroh/P2P is future work. No encrypted mailbox. Signed operations are ordered by Lamport/device/operation ID, not system time. Server routes encrypted frames; clients validate signatures/membership and merge. Core namespace TogetherCore, Bundle ID and Application Support/identity/pairing locations are unchanged.

UUIDs are uppercase canonical strings; dates are integer epoch milliseconds within the existing 1900–3000 range; civil dates/months have Gregorian components and explicit IANA zones. LogValue uses Swift Codable's existing tagged JSON shape, including _0 values, base64 data and null {}. Do not replace this without a versioned protocol change. Financial amount minor units and rate are strings; CNY rounding is HALF_UP and stored historical settlements are immutable. Other Int64 envelope fields remain JSON integers and must use lossless 64-bit handling in Kotlin/other clients.

Schemas describe portable DTOs and the current signed envelope, never SwiftData objects. DeviceIdentity schema exposes only the public DeviceDescriptor; private identity material is not a protocol field. Stored local paths are derived from verified asset IDs, not accepted from remote absolute paths. Models which are derived-only (balance, allocations, rendered occurrence) are not another authoritative ledger.

## Invitation requirement gap

The formally approved and locally implemented lifetime is **8 hours / 28800000ms**, one successful use. The server rejects expiry at `now >= expiresAt` and consumes a successful join atomically. Existing clients render the actual server expiration timestamp, so no hardcoded ten-minute label remains. Nonces/socket tickets keep independent 60-second lifetimes. This separate Issue #1 PR does not deploy production; the last audited production lifetime is **10 minutes / 600000ms**. Protocol 3 JSON, saved routes and identities remain unchanged.

## Cross-platform status

macOS Swift Core is extracted and tested. It still contains SwiftData, Network and macOS AppKit/ImageIO adapters; iOS/watchOS builds are not claimed. Future Apple clients can reuse domain logic after narrowing platform adapters. Android is documentation only; fixtures are the common behavioral contract, not an Android implementation.
