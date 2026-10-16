# Replication 4 / Relay API 2

Opt-in capability, not a silent reinterpretation of Device Protocol 3. The normal released pairing flow still uses Relay API 1. App version/build and physical SwiftData schema remain independent. No new production Worker has been deployed for this capability.

## Encoding and signatures

The existing `CanonicalJSON` is authoritative: UTF-8 JSON, sorted object keys, unescaped slashes, uppercase UUID strings, standard base64, integer epoch-millisecond dates. The historical `SyncOperation`, `SignedOperation` and tagged `LogValue` encodings are unchanged. Finance minor units/rates remain decimal strings. General integers here are bounded below 9,000,000,000,000,000 for exact cross-platform parsing. Dates and decimal values must not be passed through binary floating-point business calculations.

An `AuthorizedOperation` signs its canonical `body`: version 4, frozen space ID, device grant/epoch UUID, positive sequence, previous certificate SHA-256, and the original inner SignedOperation. Both signatures are mandatory. Sequence/head prove a contiguous per-device authorization chain; they do not replace Lamport/device/operation ordering in business merge. Root epochs are deterministic from the signed genesis; additional grant epochs are unique UUIDs. A grant binds a user, device, independent public key and initial space. A self-declared user ID is never authorization.

Genesis contains exactly two users and their previously trusted root devices, stable original SharedSpace/aliases/time zone and a legacy inventory checkpoint. Both roots independently sign the same canonical body. Owner control events are signed by that owner's original root; compare-and-swap revision/previous digest serializes each owner stream. Restore sorts streams by owner UUID then revision before hashing the archive. Mutable display name/protocol capability does not rotate an already pinned device key. Revocation retains public historical keys and pins an accepted sequence/certificate digest; records beyond that frontier are rejected regardless of `createdAt`.

## Inventory and frames

An entry has `operationId`, `contentDigest = SHA256(canonical SignedOperation)` and, for certified records, `certificationDigest = SHA256(canonical AuthorizedOperation)`. The checkpoint sorts entries lexically by uppercase UUID. SHA-256 is updated with UTF-8 `Together-Inventory-4\n`, followed by each `UUID:contentDigest[:certificationDigest]\n`. A same-ID content **or certificate** mismatch is an error, not a last-writer choice.

The JSON Schema and synthetic CryptoKit/WebCrypto/Python vectors define exact objects. Frames are explicitly tagged by `kind`:

| Kind | Fields and behavior |
| --- | --- |
| `syncHint` | `hintId`: wake the peer's pull pass after a committed local/forwarded change; coalesce during a current pass |
| `inventoryStart` | `passId`: request an immutable source snapshot |
| `inventoryPage` | `passId`, `page`: checkpoint, optional after/next cursor, at most 128 sorted entries |
| `inventoryNext` | `passId`, `cursor`: next source page, tied to that pass |
| `operationRequest` | `passId`, `requestId`, at most 32 exact missing entries |
| `operationBatch` | Same pass/request, at most 32 `legacy`/`authorized` records and 240,000 encoded record bytes |
| `inventoryFinished` | `passId`, checkpoint: verify the complete inventory stream before considering convergence |
| `acknowledgement` | `receipt`: signed exact entries or a complete-set checkpoint, never both |

Each peer runs a pull pass in both directions with one outstanding operation request. Immutable inventory pages live in rebuildable local cache rows; data written after capture triggers another pass. If writes race capture, that capture aborts and retries. A transport reconnect starts a fresh pass against already persisted facts/staging/receipts. Cursors are not evidence of durable delivery; max Lamport is never a completeness cursor. A revoked historical chain may be staged until its pinned prefix verifies. An incomplete legacy baseline is not projected.

## ACK semantics

Receivers generate signed ACKs only after promoted facts are durably committed. Body: version, space, receiving device, current epoch, up to 32 exact inventory entries **or** a checkpoint with an empty entries array. A checkpoint ACK is applied to a frozen exact local set; writes after it are not accidentally acknowledged. Duplicate/lost/reordered receipts are safe; signed proofs and per-device content/certificate mappings persist locally.

Local Saved, Pending Sync, Transferring, Remote Persisted and Converged describe different transport states. Reviewed/Dismissed are local user actions; Domain Confirmed comes from domain rules, such as beneficiary confirmation of a wish. Neither is inferred from a network ACK. Partner delivery means at least one currently authorized device owned by the other user persisted the operation; one's own phone is not partner delivery. Other devices may remain offline. Gift `Synced` additionally requires the existing content-bound receipt after all original attachments pass SHA-256/format verification.

## Relay and media

HTTPS V2 paths: signed challenge/authentication, bootstrap `POST /v2/spaces`, authenticated `GET /v2/spaces/{id}`, owner event `POST /v2/spaces/{id}/devices`, one-use 60-second ticket `POST /v2/spaces/{id}/ticket`, `WSS /v2/socket/{id}`. The V1 route must match both original public keys/users/devices/aliases before bootstrap. Repeated bootstrap cannot erase grants/revocations. No server-selected replacement root is trusted.

Directed `relay4` envelopes contain sender device, recipient device and a `RelayPacket`. One socket belongs to a device, not a user. Pairwise hello protocol 2 binds replication 4, authorization digest, frozen space, independent ephemeral X25519 public key and nonce; both pinned Ed25519 keys sign. Signed consent binds the sorted-hello transcript. X25519 + HKDF-SHA256 uses direction-specific `Together-Relay-2:{sender}:{recipient}` context; ChaChaPoly AAD binds framing version, transcript, device sender/recipient and strict counter. Counter/nonce space is per fresh pairwise session. A reconnect gets a new ticket and ephemeral keys. No user-wide shared private key exists.

Original media uses the existing encrypted request/chunk/complete/receipt channel with 64 KiB chunks and verified resume offsets. Any authorized replica holding the verified original can serve missing bytes. Download leases prevent multiple peers writing the same partial file. No total image-byte/pixel limit is introduced. The relay caps each directed frame at 524,288 bytes, control frames at 8 KiB and sockets at 200 frames/second. Client queue bounds/backpressure are independent of total media length.

Metadata schema 2 is additive beside V1 routes/rooms. Public authorization metadata is capped at 131,072 bytes and 32 active devices; control-history paging is pending and exhaustion fails closed. Rate limits include separate V2 IP and verified-device budgets so several devices behind one NAT do not inherit V1's small challenge budget. The relay stores only public control/routing data and temporary authentication state: no operation plaintext, originals, persistent ciphertext mailbox or offline delivery guarantee. Public identity/profile metadata, lengths, timing and denial of service remain in its trust boundary.

## Conformance and release gates

`ReplicationConformanceTests`, Workers `replication-conformance.test.ts`, and Python `tests/conformance/test_replication_v4.py` consume the same synthetic fixture. No fixture contains a persistent private key or real user content. Existing V3 fixture hashes and signed DTOs remain valid. Unknown versions, unauthorized devices, identity/space mismatches, signature errors, chain forks and content collisions fail explicitly.

Four native clients on one Mac against an actual local Worker are integration evidence, not four physical devices or Android interoperability. Native enrollment exchange is implemented; desktop/human acceptance, independent protocol review, physical cross-WiFi acceptance and authorized production deployment remain separate release gates. Root recovery/rotation, authorization-history paging, encrypted backup UI, fully incremental dependent-domain projection, C2 and mailbox delivery are not implemented here.

## Native enrollment and local receipt cache

[Enrollment exchange v1](DEVICE_ENROLLMENT.md) adds signed public files and explicit native verification without reinterpreting legacy operations or API 2 routing. Existing roots and SharedSpace remain stable. A retry exports all currently known signed authorization, not an obsolete completion cache.

Checkpoint ACK wire bytes are unchanged. Local derived membership uses bounded 128-entry pages, signed by the local independent device over exact entries, the remote proof digest and both device IDs. Promote the receipt/current pointer only after pages are durable. Restart verifies both signatures; later local writes are not members of an older receipt. Legacy per-operation ACK rows remain readable; entry receipts need exact membership and old whole-set proofs need current inventory equality. Only superseded derived membership pages are cleaned after a new complete checkpoint; signed operations, tombstones, authorization history and receipt proofs are retained.
