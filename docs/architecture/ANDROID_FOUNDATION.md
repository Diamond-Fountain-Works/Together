# Android Phase A architecture

## Authority and scope

Incremental Kotlin client on Protocol 4 / Relay API 2 at `eff5f8420728470ca2d9444f54a39e356537b953`. Parent PR #4 is unmerged; Android work lives in an independent worktree/stacked branch. Apple application code, SwiftData, original stable members/space/identity/route and production service behavior are unchanged. New Swift code is a test of Kotlin output, not a second Swift SyncEngine.

| Boundary | Source | Responsibility |
| --- | --- | --- |
| Pure JVM protocol | `apps/android/core/protocol` | Canonical Codable bytes, BC primitives, public device trust, signed-file enrollment, certificate chains, inventory/ACK and OkHttp C1 |
| Pure JVM domains | `apps/android/core/domain` | Validated field merge, permanent tombstones, Tasks/recurrence, wishes, gifts and finance projections/planners |
| Android adapters | `apps/android/app/.../data` | Room transactions/indexes, app-private Keystore wrapping, staged/active workspace |
| Android UI | `apps/android/app/.../ui` | Native adaptive Compose, task editor, device enrollment/status, local change history |
| Test-only fixtures | `core/protocol/src/testFixtures` and `app/src/androidTest` | Random synthetic roots/local Worker provisioning; never packaged in the application APK |

## Exact protocol compatibility

UTF-8 sorted-key JSON, literal `/`, uppercase UUIDs, standard base64, exact integer epoch milliseconds; operation envelopes and `LogValue` tagged `{"string":{"_0":"…"}}` / `{"null":{}}` follow the existing Swift encoding. Decimal money/rates remain strings inside canonical base64 `LogValue.data`. No SwiftData classes enter the transport. Fractional metadata such as avatar crop stays opaque signed `data`; it is not reformatted before signature verification. Duplicate JSON keys, invalid Unicode, excessive nesting/frames and unsupported frame kinds fail closed. Typed decoding tolerates unknown server fields like Foundation Codable; signatures always verify canonical known DTOs.

Original Swift fixtures validate authorization, envelope/certificate/content digests, ACK, enrollment code/signatures, original Protocol 3 bytes, money, cycles and calendars. New `android-phase-a-v4.json` is public synthetic Kotlin output independently replayed by the unchanged Swift projector; CryptoKit opens the BC packet and a local generated CryptoKit response is opened in Kotlin. Passing vectors does not constitute independent security approval or exhaustive Unicode/time-zone implementation equivalence.

## Durable facts and projection

Room generation 1 has `operations`, `local_records`, `inventory_cache`; exported schema is tracked. Facts contain canonical signed records, indexed by identity/epoch sequence and entity/Lamport. Raw row metadata is checked against signed bytes on load. WAL with synchronous FULL, actual transactions, collision rejection and append-before-send provide process-crash safety. No destructive fallback/migration reset exists. Physical power-cut acceptance has not been performed.

Verified out-of-order certificates remain staging until the contiguous previous-hash chain is available. Legacy roots are allowed only in the co-signed complete legacy checkpoint. An unsealed baseline cannot become business state or allow new edits. Revoked historical proofs must form the root-pinned cutoff digest prefix; later operations fail regardless of system time. Signatures/public keys remain available to verify retained history. Local heads are rebuilt from facts on reopen; no max-Lamport completeness shortcut.

Projection sorts Lamport/device/operation UUID, merges fields, preserves tombstones and keeps invalid/superseded candidates diagnosable. Wish confirmation/quota and one-ledger finance/calendar rules remain domain operations, not transport approvals. Recurrence/bill planners run after restore and persisted changes; stable IDs prevent duplicate logical instances. No snapshot overwrites another replica's facts. Full projection remains linear in history; the >10k protocol test does not establish 100k Android UI/RSS performance.

## Device identity and enrollment

A new device generates its own Ed25519 seed, wrapped by AES-GCM under Android Keystore. AAD binds the public descriptor. Neither root/Mac keys nor a user-wide shared private key are imported. Software Ed25519 is not described as hardware-backed. Missing/invalidated wrappers fail closed, never rotate silently. Cloud backup/device-transfer exclusions prevent copying a seed without its wrapping key.

The initial unpaired database contains only locally signed private facts, not certified replication history. Signed offer/request/completion verification follows `DEVICE_ENROLLMENT.md`. Explicit code comparison precedes new identity/request creation; completion binds request, original genesis, all known prior grants/revocations and exact service/route. The authorized workspace is a separate database/identity; a durable active pointer is written after validation and initialization. A local business workspace cannot be overwritten by joining. Public exchange files are bounded, selected/exported with Android's Storage Access Framework.

Only the original owner root can grant/revoke under current Protocol 4. An enrolled Android may list devices and consume revocations but cannot promote itself to root. Root-loss recovery, control-history paging beyond 128KiB, delegated grant powers and automatic identity recovery remain unimplemented upstream. Offline revocation freshness remains an independent-review issue. The debug-only test namespace isolates instrumented repositories without altering the default production path; the test Runner rejects production IDs and physical hardware.

## C1 transport and ACK

OkHttp HTTPS/WSS uses fresh signed challenge and short-lived ticket, existing v2 routes and per-device presence. Only debug loopback accepts HTTP. Redirects carrying signatures/tickets are rejected. Pairwise X25519/HKDF-SHA256 directional keys, signed hello/consent, ChaCha20-Poly1305 AAD/transcript and strict counters match Swift. A serialized event loop prevents overlapping peer/crypto mutation; foreground-owned jobs close on backgrounding and reconnect with exponential backoff. Socket send is never a persistence receipt.

128-entry frozen inventories are paged from local cache; at most 32 exact records/240000 encoded bytes are requested. Content and certificate digests detect same-ID forks. Hints arriving during a pass trigger another pass; reconnect starts a new pass over retained facts/staging/ACK. Checkpoint ACK binds only the complete frozen exact set, not later writes. Per-device signed receipt proofs and locally signed membership bind the accepted content/certificate set. At least one active partner-owned device must have persisted an entry before `partnerPersisted` is true; one's own other device does not count. Review state stays local and separate from Wish confirmation.

Receive/application queues are bounded. OkHttp itself assembles messages before callbacks; adversarial oversized-message memory protection requires further transport review. Original media transfer and gift/media receipts are not yet implemented on Android: manifests/history survive but no completed media receipt is emitted. No offline mailbox, C2 or plaintext business storage was added to the Relay.

## Versioning and evidence

Android app version/code, Protocol 4/API 2 and Room schema 1 are independent; Apple version/schema stay unchanged. P3 history is verified only through the explicit P4 migration checkpoint, not exposed as a P3 Android transport. Invitation behavior remains 10 minutes; Issue #1/PR #3 owns the separate 8-hour change.

Actual results: [Android QA](../qa/reports/ANDROID_PHASE_A.md). Full Android Wishes/Finance/Gift/media UI, physical phone/tablet acceptance, real Mac↔Android networking, independent cryptographic review and production deployment remain separate gates.
