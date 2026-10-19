# Native partner pairing — development evidence, 2026-10-19

## Scope and delivery state

`fix/device-pairing-ux` is stacked on Android Phase C. The Samsung is a separate
partner, not another device of the Mac owner. Partner invitation creation and a
text code input are separate from signed-file **own-device** enrollment. Existing
keys, user IDs, signed facts, storage schema and authorization rules are retained.
No production Worker was deployed and no user store was reset.

The native bootstrap is an additive Protocol 3/4 negotiation followed by the
existing Protocol 4 service. Protocol 4 signed bytes do not change. Native invite
expiry is eight hours; the legacy endpoint stays ten minutes. Challenges/tickets
stay sixty seconds. Retrying one authenticated join intent returns its original
route; another intent/device cannot reuse the consumed invitation.

## Verification and limits

| Evidence | Result | Scope |
| --- | --- | --- |
| Worker typecheck / tests | PASS, 21 tests | Local Worker, synthetic identities |
| Swift default suite | PASS, 135 passed / 11 skipped | Explicit integration/performance prerequisites skipped |
| Portable protocol | PASS, 17 tests | Python conformance |
| Native Swift pairing | PASS, both invitation directions | Actual local Worker; native test processes |
| Native Kotlin pairing/recovery | PASS, two tests | Local WebSocket and post-genesis recovery |
| Samsung partner UI/recovery | PASS, three instrumentation tests | Typed invite, error state, Room/Keystore reopen |
| Two actual Mac QA apps | PASS | Independent stores and loopback fault proxies |
| Physical Samsung invites Mac | PASS with VPN active | Separate networks; not VPN-free acceptance |
| Physical Mac invites Samsung | FAIL | Original incomplete handshake retained |
| Later VPN-free Samsung attempt | FAIL | TCP timeout before TLS to current Workers hosts |
| P2P | NOT RUN in this change | These WebSocket checks are not P2P |
| Independent protocol security review | BLOCKED | Developer tests are not independent review |

Two native QA apps used 80 ms / 128 KiB/s and 450 ms / 64 KiB/s profiles. During
B's outage B saved a task locally: A had four signed facts, B had five. Restoring
B's proxy automatically reconnected after 36.22 s. Both had the same five operation
IDs and content hashes; both windows showed Connected and both tasks. This is a
single-Mac fault-injection result, not public-network/NAT-traversal acceptance.

VPN-free Samsung probes resolved DNS but timed out connecting to staging and
production `workers.dev`, on both IPv4 and IPv6, before TLS. HTTPS controls gave
HTTP 200. This establishes failure on the measured path, not a universal
Cloudflare restriction or input-method defect. Automation did not change VPN or
network settings. Public tests used no USB reverse rule.

## Safety and private evidence

Tests use private isolated stores, media and identities. Mac twins use
`com.together.app.qa.a` / `.qa.b` and the fail-closed QA host. Runtime artifacts
stay in ignored `qa/results/`: `partner-cross-network/20261019-210904`,
`partner-cross-network/20261019-211936`, `partner-reachability/`, and
`qa-twins-20261019-213054/`. Screenshots are candidates, not approved baselines.

The production-copy upgrade rehearsal retained five signed operations, three
entities, five local records and the identity file across three reopens; its
source hash stayed unchanged. Authorized local install: Build 11. A separate
Universal Build 12 artifact is not automatically installed. Both are ad-hoc
signed, unnotarized. Production API 1 is unchanged and cannot provide this native
partner bootstrap.

The user now requires VPN-free P2P operation-log replication. That is a new
transport workstream; the blocked public WebSocket path does not meet it.
Connectivity helpers may forward encrypted frames; they do not host the business
database or an offline mailbox.
