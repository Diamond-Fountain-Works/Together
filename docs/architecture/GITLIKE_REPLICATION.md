# Git-like replication: C1 evolution

Status: implementation in progress on `feature/gitlike-c1-multidevice`, based on verified Monorepo commit `1832df0`. PR #2 remains Draft; its 68 Build 5 candidates are not approved by this work. No production deployment, installation, identity rotation, database reset or C2 change is authorized.

## Audited baseline

| Component | Already implemented / verified | Needs refactoring or missing |
| --- | --- | --- |
| SyncOperation / SignedOperation / CanonicalJSON | Stable UUID, actor/device, logical order, canonical millisecond JSON, Ed25519; legacy DTO fixtures and 85 business tests passed on the baseline | Keep these signed bytes unchanged; add versioned replication metadata outside them |
| ReplicaContext / PairedPeer | One local and one peer, two actual users | Additional devices currently change the derived space; freeze the existing space/aliases/time zone before enrollment |
| ReplicaEngine / OperationProjector | Field merge, Lamport/device/operation ordering, tombstones, recurring/wish/gift/finance invariants | Full synchronous replay, repeated signature verification and whole-log fetch/duplicate checks |
| TogetherRepository | OperationRecord, LocalRecord, EntityRecord; durable local saves and gift-slot transaction | Indexed bounded inventory, atomic replication metadata and per-device acknowledgements |
| OperationLogSyncSession | Bidirectional live/catch-up and resumable verified media | Full ID list, 10,000-ID guard, ID-only digest, one-operation replay and volatile completion state |
| SyncTransport / RelayWebSocketTransport | Native URLSession WSS, frame limits, authenticated cipher payloads; legacy TCP retained | Versioned inventory flow control and multiple independent remote sessions |
| PairingService / RelayAPI | Invitation, mutual signed confirmation, fresh tickets, saved route, retry/backoff | Partner pairing and own-device authorization must be distinct |
| ConnectionDirectory / RelayRoom | Cloudflare DOs, atomic challenges/invites/tickets, two-member routes, one socket per member, no mailbox | Add an additive v2 metadata schema and per-device directed sockets; do not overwrite v1 routes |
| FinanceChangeReview | Actual finance operations, local review state, no partner approval | Extend audited applied-operation effects to other domains |
| MediaStore | Originals, 64 KiB chunks, partial-file recovery, bounded hashing, format validation | Allow any authorized replica holding verified bytes to serve them; receipts remain content-bound |
| Invitation / versions | Actual 600,000 ms; Device 3 / Relay 1 / storage generation 1 | Formal 28,800,000 ms remains Issue #1, delivered separately from core replication |
| Security | CryptoKit/WebCrypto primitives and application framing tested locally | Independent protocol/security review remains BLOCKED for release claims; WSS alone is not E2EE |

Baseline tests are prior evidence, not acceptance of the new implementation. Each new phase records fresh results in `docs/qa/reports/`.

## Invariants

Local-first database → immutable signed operations → anti-entropy → deterministic domain projection → local change review. Relay stores public membership/routing metadata, never business plaintext or media. No snapshot replaces another replica's operations. App version, device replication protocol, Relay API and physical storage generation are independent.

Protocol 3 operation encoding remains readable and verifiable. Protocol 4 is an explicit replication capability; a legacy session never receives an unknown v4 message. Existing private keys, user/device IDs, pair pins, initial spaces and v1 Relay binding remain intact. New multi-device membership stores the existing effective SharedSpace ID and original aliases, rather than deriving a new ID from an expanded device list.

## Decisions

See [ADR 001](adr/001-replication-identity.md), [ADR 002](adr/002-paged-anti-entropy.md), [ADR 003](adr/003-authorization-and-revocation.md), [ADR 004](adr/004-directed-c1-sessions.md) and [ADR 005](adr/005-durable-receipts.md).

### Authorization

A signed genesis binds exactly two stable user IDs, their existing trusted root device keys, the frozen space/time zone and a content-digest checkpoint of legacy operations. Existing pairs authenticate with their old pins; creating a new route must not seize an existing space. Genesis needs both existing root signatures. Reinstalling without an identity backup does not silently create a replacement identity.

Each owner has a signed, hash-linked authorization control stream. The initial owner root authorizes its additional devices; device/user IDs and independent public keys are bound into grants. A grant UUID is the device's authorization epoch. Control updates use compare-and-swap and fail on equivocation rather than selecting trust by wall clock or a Lamport tie-break. An ordinary user/device claim is not a grant. Automatic controller/key recovery is outside this phase.

Protocol 4 wraps the unchanged SignedOperation in a signed grant/sequence/previous-digest record. Revocation binds an authenticated accepted sequence/head. A revoked key cannot create valid new records beyond that frontier. Missing predecessor records are staged; a revoked historical prefix must match the pinned head before use. Unknown offline records outside the certified prefix are diagnostic candidates, not silently backdated with `createdAt`. Their bytes are retained and corrections use new operations. It is impossible to prove whether an unseen offline signature preceded a revocation using an editable computer clock.

Legacy history is sealed by count + SHA-256 over a sorted ID/content inventory. A new replica verifies the complete sealed legacy set before projecting it; existing replicas retain their already verified local facts during migration. This checkpoint is a trust boundary/cache, not a database snapshot. No re-signing or rewriting of legacy SignedOperation bytes is allowed.

### Anti-entropy

Use sorted, keyset-paginated UUID + SHA-256 inventory, bounded requests and byte-bounded operation batches. A per-pass high-water ID and content checkpoint define a stable scan; writes during a pass trigger another pass. Never infer completeness from maximum Lamport or an operation count alone. Resume cursors are tied to their pass/source checkpoint; changed state restarts safely from durable local facts. Identical IDs with different bytes fail and are diagnosed. A disconnect loses transport work, not committed operations.

Keep bounded in-flight pages/batches and backpressure. Hash/signature verification and domain replay run off the main actor; SwiftData fetch/save work is bounded. Incremental projection may replay affected entity/dependency groups only when equivalence to full replay is established. Full verified replay remains the oracle. No unproven automatic log pruning or tombstone removal.

### Confirmation and review

Local Saved / Pending Sync / Transferring / Remote Persisted / Converged / Reviewed / Domain Confirmed are distinct. Signed per-device ACKs bind exact operation IDs and content digests after database commit. A socket write or relay status is not an ACK. Lost ACKs are retried from persisted state; duplicate ACKs are idempotent. Partner-synced means at least one currently authorized partner device persisted the operation; all-device progress is separate. Required media must be hash-verified before a gift receipt. Wish fulfillment confirmation retains its original domain rule.

Change events use authoritative projection effects, preserve before/after values and identify partner versus another device owned by the current user. Rejected/superseded operations are not successful-change notifications. Reviewed/dismissed state is local, durable and independent from delivery or business confirmation. No technical hashes/clocks are exposed as product copy.

### C1 and future boundaries

Add v2 metadata beside v1 routes in the existing Directory/Room framework. Each authorized device has its own socket. Routing envelopes name sender/recipient devices; each pair has independent ephemeral authenticated keys and replay counters. One user's phone must not replace their Mac socket. Renew tickets on reconnect, validate current authorization on send/receive, rate/frame/device-bound limits, and close revoked sockets. v1 pins/routes and rollback remain available; activation requires local migration checks and an authorized service deployment.

C2 Iroh/QUIC, encrypted mailbox, central business storage, media hosting and platform UI clients are not part of this work. Real two-Mac, Mac/Android and four-physical-device tests stay NOT RUN without hardware/client evidence. Local four-replica tests are explicitly simulations/integration tests.

## Implementation ledger

Architecture audit/design: recorded. Trust, indexed durable log, paged sessions, ACK, universal review, Relay v2 and large-log measurements: pending implementation/tests. Invitation eight-hour change: separate branch/PR. No entry in this document alone means a capability is complete or production deployed.
