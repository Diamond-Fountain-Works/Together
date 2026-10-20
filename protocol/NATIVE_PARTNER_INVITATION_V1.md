# Native first-partner invitation v1 — isolated App acceptance

This additive invitation routes a first partnership over the existing native
transport. It does not change Protocol 4 operations, authorization, deterministic
projection or durable ACKs. The normal production C1 route is unchanged.

The dedicated QA Apps exchange canonical UTF-8 JSON:

`{body:{version:1,transport:"iroh-quic",invitationId,descriptor,endpointId,relayURL?,directAddresses,issuedAt,expiresAt},signature}`

- UUIDs, the public device descriptor, base64 Ed25519 signature and canonical JSON
  use the existing platform-independent encoding.
- `endpointId` is the independent transport public key, 64 lowercase hex digits.
  It must match the connected native TLS endpoint and differ from the signing key.
- `issuedAt` and `expiresAt` are integer Unix milliseconds. Validity is exactly
  **28,800,000 ms (8 hours)**, matching the current C1 source contract and product rule.
  This branch does not change or deploy the C1 service. Local system clocks are
  trusted for this self-contained invitation; no server-time assurance is claimed.
- The complete body is signed. Routing metadata grants no business authority.
  Bounds are 32 direct addresses of at most 128 UTF-8 bytes each and an HTTPS relay
  URL of at most 2,048 bytes, without user info, query or fragment.
- The joiner sends its own signed contact for the same invitation ID. Both native
  endpoint IDs and descriptor signatures are checked before the existing signed
  hello and six-digit transcript comparison. Both users must explicitly consent.
- The existing bounded partner-history exchange and co-signed genesis establish
  the two-user space. Successful first pairing pins the partner; reusing an invite
  cannot replace an existing paired user. No C1 route/binding is fabricated.
- A pinned contact can be signature-verified after invitation expiry. Reconnect
  still requires the current authorization archive, signed `PeerTransportBinding`
  and fresh existing Protocol 4 authenticated channel; expiry never revokes a pair.
  Signature-only reading also accepts the earlier QA-only 600,000 ms contact
  interval to preserve an already pinned test pair. It is rejected for a new join;
  all newly issued and freshly joined invitations use the exact 8-hour interval.
- New business operations use existing paginated replication and signed durable
  receipts. Native socket send success is not remote persistence.

`fixtures/native-partner-contact-v1.json` contains synthetic public data only and
is checked by both Swift and Kotlin tests. Protocol conformance is distinct from
normal-App physical-device and independent-network acceptance.
