# VPN-free P2P incremental replication

Decision updated by the user on 2026-10-19: P2P transport is now authorized. The
earlier C1-only / future-C2 phase boundary remains historical, not a prohibition
on this new workstream. The working production transport is not silently changed.

## Preserve the facts, replace connectivity

Each device keeps its local database and durable signed operation history.
Changes still flow through authorization, canonical JSON signatures, paged
anti-entropy, deterministic domain projection and per-device persisted ACKs.
Neither QUIC packets nor a database snapshot replace these facts. An encrypted
socket send is not a persisted receipt. Deletion still produces a tombstone.

No VPN, Tailscale account, central business database or offline cloud mailbox is
required by the new transport package. Iroh QUIC is the initial native transport
candidate. It can operate with direct addresses and every relay/discovery service
disabled. NAT traversal/optional encrypted-frame relay are connectivity services;
they do not host Tasks, Wishes, financial records or original media. A reachable
helper may still be necessary on some network combinations. A local direct test
does not demonstrate that public NAT traversal works without a helper.

## Independent transport identity

Keep the existing User ID, Device ID, SharedSpace ID and operation signing key.
Generate a separate Iroh transport key; never copy an existing device's private
key to another device. Before any production integration this transport key must
be saved using the existing owner-only/Keystore-wrapped storage boundary, and
missing keys must become explicit recovery errors rather than silent rotation.

`PeerTransportBinding` is an additive signed credential. Its body includes a
format version, transport name, stable space, exact device descriptor, endpoint
public key and current authorization digest. The existing Ed25519 device key
signs canonical bytes. Verify both the current membership archive and the TLS
remote endpoint before exchanging application content. An unknown or revoked
device cannot acquire membership by claiming a User ID or presenting a QUIC key.

`AuthorizedPeerCipher` wraps the existing Protocol 4 hello, signed consent,
X25519/HKDF and authenticated cipher framing. Existing signed bytes, key
derivation labels and operation encoding do not change. Fresh transport sessions
use fresh ephemeral keys; old cipher packets and wrong endpoint bindings fail.
An authorization-digest change closes/re-establishes the link using fresh verified
bindings. Legitimate pre-revocation history retains its existing proof rules.

## Existing pairing and invitation UX

The tested adapter accepts already-authorized devices only. Production pairing
and enrollment are not yet connected to it. Existing co-signed genesis/epochs
remain valid; old spaces must not be regenerated when choosing another transport.

A self-contained P2P contact cannot fit a full cryptographic endpoint key into a
short random invitation code. The next UX integration must explicitly support a
signed copyable invitation/QR or a reachable short-code lookup service, preserve
mutual identity confirmation and separate partner invites from Add My Device.
Do not silently replace the text field with a file picker or authorize devices
merely from a pasted contact. The current legacy/native expiry contracts remain
unchanged until that invitation change has its own verified contract.

## Platform/dependency gate

The optional `packages/together-p2p-swift` package pins official iroh-ffi v1.1.0
commit `5e451092dba0c1a09ee83ff6e5be37b1152a5c58`; upstream's Swift manifest
verifies the binary checksum. No monitoring client/API key is enabled. Direct-only
mode is the default. Automatic public discovery/relays require explicit selection.

Upstream's prebuilt macOS framework is arm64 / macOS 14.5+. Do not drop Together's
Universal / macOS 14.0 support by linking it unconditionally. The app target does
not yet link this optional package. A source-built compatible slice or a clearly
bounded supported-platform strategy is required before release. Kotlin
application integration and real physical network tests remain separate gates.
The Android test target contains a native adapter; the production client does
not link it.

## Current evidence

IMPLEMENTED / TESTED: bounded ordered QUIC frames, independent transport keys,
signed endpoint bindings, current authorization checks, reused Protocol 4 cipher,
and the existing paged replication engine over a relay-disabled local QUIC link.
The test converges 258 independent signed operations, obtains genuine persisted
ACKs, then converges a tombstone as operation 259. Both selected paths must report
direct IP and not relay. A malicious 4 GiB length prefix is rejected before its
payload is allocated. Three additional core trust/replay/revocation tests pass.

NOT PASSED: Mac-to-Samsung P2P (first shared-hotspot native connect timed out,
cause UNKNOWN). NOT RUN: independent public NAT traversal, no-VPN public
direct/relay acceptance, 100k QUIC workload, P2P gift-media ACK and production
key persistence.
IMPLEMENTED / BUILD TESTED: a test-only Android native adapter, bounded public
physical driver and native isolated QA CLI, including fresh-process recovery
assertions. See [actual attempt status](../qa/reports/P2P_PUBLIC_ACCEPTANCE.md).
NOT IMPLEMENTED: user-facing P2P invitation/reconnect integration and Android
production transport adapter. BLOCKED for release: independent protocol/security review and
the platform support gate above. The installed Mac/Android applications still use
C1; they must not be advertised as P2P builds.

Local command: `make p2p-test`. Tests use synthetic identities and independent
in-memory stores, no production database or Cloudflare deployment. Candidate
screenshots, runtime artifacts and real network metadata remain local.

The physical driver fails closed on shared uplinks in its default public scope.
Explicit LAN and shared-uplink encrypted-relay scopes are separate diagnostics.
The latter uses the pinned public preset API to bind both Mac application QUIC
address families to loopback and checks selected relay paths on every application
frame. This does not claim all helper UDP traffic is disabled. On Android, only
LAN QA selects the exact local-only AP network for the test process; public relay
QA retains the mobile default. A post-cleanup restoration witness and actual
JUnit exit are required before the Mac is allowed to exit. Native teardown
timing and these physical runtime paths still require an unlocked-phone retry.

[QA and retained failures](../qa/reports/P2P_TRANSPORT_FOUNDATION.md) records the
initial CI timeout, reproduced optimistic-snapshot race, bounded index-read
recovery, identical-workload reruns and remaining release gates.
