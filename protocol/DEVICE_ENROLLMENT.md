# Device enrollment exchange v1

This is a public signed-file exchange for opt-in replication 4 / Relay API 2. It changes neither Protocol 3 SignedOperation bytes nor partner invitation semantics. [Schema](schemas/device-enrollment-v1.schema.json), [synthetic vectors](fixtures/device-enrollment-v1.json) and Swift/Python conformance checks describe portable DTOs rather than SwiftData models.

| File | Signed body |
| --- | --- |
| Offer | kind `Together-Device-Offer-1`, offer UUID, issuer device, owner user, public authorization archive, C1 binding, expiration in canonical epoch milliseconds |
| Request | kind `Together-Device-Request-1`, offer UUID and full signed-offer SHA-256, independent public DeviceDescriptor; signed by the new key |
| Completion | kind `Together-Device-Completion-1`, full signed-request SHA-256, current public authorization archive and target binding; signed by the original owner root |
| Legacy proposal | kind `Together-Legacy-Migration-4`, original two-root genesis with one or both local signatures |

Use the existing CanonicalJSON encoding, Ed25519 signatures, uppercase UUIDs and standard base64. Offer/request comparison codes are the first 96 digest bits, uppercase in six four-character groups; they are out-of-band comparison values, not online passwords. Full new-device fingerprints are also visible. A checkbox records explicit human verification; it cannot itself authenticate a stranger.

An offer is valid for 30 minutes for new authorization, and binds the stable two-member space plus original issuer. A request must prove the independent key, match owner/space/protocol 4, and name a device absent from the offered archive. The root persists one exact request claim per offer before the network call. Re-exporting a completed request keeps current known trust; a revoked target is rejected. A completion must extend the offered signed history, preserve origin/legacy route, identify the requested device and contain its active grant. It exports no private key, operation payload, reusable ticket or local storage path.

Imports are bounded to 512 KiB public JSON, separately from the existing 128 KiB Relay authorization metadata cap. Media has its own chunked channel and no new original-image size limit. This version does not paginate authorization history or solve malicious-relay freshness for revocations unknown at export time. It provides no automatic root-key replacement or recovery from public archives.

The local new-replica pointer and intent/selection files are implementation details, not cross-platform wire DTOs. Future Android clients generate their own key and consume the same public exchange and signed operation/history contracts.
