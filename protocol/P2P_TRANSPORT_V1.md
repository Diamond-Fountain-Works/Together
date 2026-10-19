# P2P transport envelope v1 — development, not deployed

This is an additive transport contract around Protocol 4, not a new database or
operation-signature version. Compatibility is gated by
[P2P architecture](../docs/architecture/P2P_INCREMENTAL_REPLICATION.md).

`PeerTransportBinding = {body, signature}` uses existing CanonicalJSON rules and
base64 Ed25519 signatures. Body fields:

| Field | Encoding |
| --- | --- |
| version | integer 1 |
| transport | `iroh-quic` |
| spaceId | existing canonical UUID |
| device | existing DeviceDescriptor, no private key |
| endpointId | 64 lowercase hex characters, independent Iroh public key |
| authorizationDigest | current verified SpaceAuthorization digest |

Reject bad signatures, stale membership digest, wrong space, revoked/unknown
devices, a mismatched TLS remote endpoint and unsupported format/transport.
Unsigned network addresses are untrusted routing hints, not authorization. Do
not connect to arbitrary hints from an unverified invitation in a product UI.

QUIC ALPN: `together/p4/1`. One bidirectional ordered stream carries frames:
four-byte unsigned big-endian length followed by exactly that many bytes.
Lengths 0 or above 524288 close the connection before body allocation. Existing
64 KiB media chunks remain separate frames; there is no original-file size cap.

The application handshake/cipher is the existing Protocol 4 RelayPacket format
(hello/consent/encrypted). Both hello signatures, current trust digest and peer
device pin are verified. Fresh ephemeral keys and strict cipher sequence checks
protect the application stream across reconnects; QUIC identity alone does not
grant business permissions. Encrypted replication payloads use existing
ReplicationFrame canonical encoding and signed per-device persistence receipts.

Portable Kotlin vectors, stream media dispatch, public discovery and invitation
exchange are NOT IMPLEMENTED by this document. Do not claim cross-platform wire
acceptance merely because this contract is written down.
