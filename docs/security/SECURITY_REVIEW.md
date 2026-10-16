# Relay security status and review boundary

Status: implemented CryptoKit/WebCrypto mechanisms and local tests; independent application-protocol review still required. No claim of a reviewed Noise/Signal protocol, Double Ratchet, static-file encryption or encrypted offline mailbox.

## Identities and transport

Existing Ed25519/Curve25519.Signing device identity remains bound to deviceId/userId/initialSpaceId. By the user's 2026-10-10 storage revision, it lives in an owner-only local file (directory 0700, file 0600), not Keychain during normal operation. This is not encrypted at rest and does not protect against other processes running as the same user. Legacy keys are retrieved only after an explicit migration action, verified against prior local signatures, then atomically linked into place without overwriting an existing identity. Refusal/missing/corrupt/mismatched keys never cause silent rotation or data reset. The original Keychain item is not automatically deleted. Invitations never grant permanent authorization by themselves. Native URLSession uses normal TLS certificate validation, production HTTPS/WSS, no WebView and no certificate bypass. Debug HTTP is loopback-only.

Server authentication uses fresh 32-byte nonce challenges (60 seconds, consumed once), request-body SHA-256 and method/path/device-bound Ed25519 signatures. Tickets are random, route/member-scoped, one-use, 60 seconds, sent in Authorization headers rather than URLs. Invitations are 12 secure base32 characters, 10 minutes, hash-only storage, one successful join, rate-limited create/join/challenge routes. Unknown/used/expired share an error to reduce enumeration.

## Pair confirmation and application encryption

Each connection generates ephemeral X25519 key agreement keys and UUID nonces. Signed hello binds protocol, route, immutable device descriptor, ephemeral key and claimed profile name. The transcript is SHA-256 over both canonical signed hellos, sorted by device identity. Existing device pins must match before migration. Users verify consistent SAS and fingerprints and both send transcript-bound signed consent. Server confirmation must agree, but server status alone can never authorize a peer.

CryptoKit X25519 shared secret plus HKDF-SHA256 derives separate directional 256-bit keys, domain-separated by transcript and sender/receiver. ChaChaPoly authenticates version/session/device/recipient/sequence AAD. Unique monotonic 64-bit nonces are used within fresh directional keys. Strict receive sequence rejects duplicates, gaps and reflection; fresh ephemeral keys/transcripts reject old-session replay. Sessions reconnect/rekey before the frame counter limit. Invalid tags/counter/session/pins disconnect; pending logs survive.

Long-term identity key rotation is not automatic. A key mismatch is refused; future replacement needs explicit bilateral rebind and log/membership migration review, not silently swapping keys. Session keys live in memory, rotate on connection/peer-session changes and are not persisted on the server. Routing bindings/public pins persist locally in the existing SwiftData LocalRecord schema. Local originals/databases remain unencrypted at rest.

## Data and service visibility

Signed Operation Log, grant/wish/gift text, profiles and binary media resource payloads are encrypted before WebSocket forwarding. Future Time Capsule must use the same authenticated content channel; there is no Time Capsule implementation in this app yet. Server sees public identities, claimed names, routing, IP/time/frame sizes and availability. It can deny/delay/drop traffic and observe metadata. Independent protocol review is needed before promoting production privacy guarantees.

RelayRoom forwards bounded 524,288-byte packets only between authorized route members, rejects encrypted packets until mutual confirmation, and rate-limits frames. Original media uses existing 64 KiB stop-and-wait requests, partial-file offset recovery and SHA-256/format validation. A socket send/server availability does not produce Synced; the recipient must persist log/content/media and return an authenticated matching receipt.

Only realtime forwarding exists. No stored ciphertext mailbox or media object store; a sender going offline before peer synchronization makes unsynchronized content unavailable. The EncryptedMailbox interface is an extension boundary, not a delivered service.

## Migration and rollback

Legacy NWListener/NWConnection and LegacyTailscaleTransport remain for regression. The shared OperationLogSyncSession carries the same operation/media protocol. Existing signed user/task/wish/gift logs and canonical space IDs remain. Old paired-device pins must match both invitation membership and signed handshake; both parties manually approve the initial relay binding. Peer/binding local records commit atomically. Subsequent sessions reconnect to the same pins without a fresh invite. No trust replacement, data wipe or new duplicate space is permitted.

## Evidence and outstanding checks

Local tests cover signature forgery, different pins, consent, AEAD tampering, replay/reflection/old sessions, preserved tasks/wishes/space, original-file export, invitation expiry/reuse/rates, ticket scope and real local URLSession WebSockets carrying encrypted operations and large-media chunks. Record actual results in TEST_PLAN and qa/results; passing primitives does not prove the entire protocol against a malicious relay implementation.

Required before production security approval: independent transcript/KDF/consent/reconnect/migration review; adversarial scheduling and control-frame abuse; relay compromise and metadata threat review; deployed origin/TLS/Cloudflare policy checks; two physical Macs across Wi-Fi; key-loss/rotation recovery design if introduced; rate/quotas/cost review. Do not market unreviewed protocol guarantees or offline delivery.

Primary primitive references: [CryptoKit](https://developer.apple.com/documentation/cryptokit), [Cloudflare Web Crypto](https://developers.cloudflare.com/workers/runtime-apis/web-crypto/), [hibernating sockets](https://developers.cloudflare.com/durable-objects/best-practices/websockets/).

## Public deployment evidence

2026-10-10: verified-account deployment and HTTP 200 health check completed at https://together-connection.together-connection-service.workers.dev. Actual native HTTPS/WSS integration covered mutual confirmation, encrypted profiles/operations/wish ledger and confirmation, original avatar/photo and audio chunks with SHA-256, recipient acknowledgement, reconnect and persistent binding. Default App configuration uses this public origin, no Cloudflare credentials.

These results verify a deployed service and native public network path on one Mac. They do not complete independent protocol/security review, cross-Wi-Fi physical two-Mac acceptance, mailbox, static encryption or large-scale cost/abuse review.

## Replication 4 / API 2 security boundary

Implemented primitives and local tests are not independent protocol review. Co-signed genesis pins the original space and legacy content; separate owner-root CAS streams authorize independent public device keys/epochs. A v4 outer signature binds the unchanged inner signed operation and contiguous device certificate chain. Revocation pins the accepted head, keeps old keys and rejects beyond-cutoff records without trusting wall-clock backdating. Control equivocation, ID/content/certificate collisions and invalid source/recipient/space fail closed.

Each device pair authenticates fresh X25519/Ed25519 hellos and consent bound to the authorization digest, derives directional HKDF/ChaChaPoly keys and enforces strict replay counters. Relay API 2 verifies per-device signed challenges/tickets and active authorization, directs ciphertext to a named device and closes stale authorization sockets. WSS/Tailscale alone are not this application encryption. No global user private key, media upload storage or ciphertext mailbox was introduced.

The relay can observe public identity/routing/profile metadata, ciphertext length/timing and online state, and can deny service. Compromised authorized endpoints can read their space; rollback-resistant trust is not protected against an attacker who can replace the local database/keys. File identity remains owner-only local storage, not hardware-backed. Root rotation/loss recovery and forward-secret historical at-rest encryption are not implemented. Authorization archive paging is pending; current 128 KiB metadata bound fails closed instead of deleting historical keys. An unseen pre-revocation offline signature cannot prove creation time from an editable computer clock.

Release gate: independent review of genesis migration, owner/root recovery policy, revocation frontier liveness, pairwise session framing and cross-platform canonical bytes. Four-client localhost and synthetic tamper/replay tests do not satisfy this gate. Production API 2 deployment, physical cross-WiFi and new-device enrollment UI acceptance are not complete. The source PR must remain Draft while any required security/compatibility/visual gate is outstanding.

### Source review follow-up (2026-10-16)

A sealed source diff review of `1832df0..4eb3e5d` reported one High and three Medium findings: retired hello rollback, invalid durable staging, legacy checkpoint poisoning and acceptance of a divergent revoked prefix. The later `4091bf9` commit fixes these plus the partial-checkpoint overflow and stale asynchronous authorization/projection race identified during follow-up. Six adversarial executable regressions pass; the full suite reports 125 passed, 0 failed, 3 skipped. The original sealed findings are retained, not relabelled as a clean scan of new code. Exact evidence/scope is in [C1 QA](../qa/reports/GITLIKE_C1_QA.md). This local source review and regression testing do not replace the independent review gate above.

## Enrollment hardening follow-up

[Build 10 evidence](../qa/reports/C1_HARDENING.md) retains the new immutable 34-file review's one Medium stale-completion finding and its later tested correction (`cf75c38`). Completed retries now include all authorization known by the owner root, without another grant; already-exported offline files still cannot reveal revocations unknown at export. QA copied fixtures no longer query legacy Keychain, and QA networking is restricted to an explicitly supplied loopback origin. These source reviews/regressions do not satisfy independent protocol certification. Root-key loss, long authorization history and controlled rollout remain explicit [architecture boundaries](../architecture/adr/006-native-device-enrollment.md).
