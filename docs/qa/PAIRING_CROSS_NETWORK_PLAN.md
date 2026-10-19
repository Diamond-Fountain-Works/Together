# Native partner pairing acceptance

Status: local implementation under verification; no new public service deployed.

The physical Samsung is a different partner, not the Mac owner's additional
device. Partner invitations and signed own-device enrollment are separate
purposes. Existing identity keys, aliases, stores and bindings are retained.

## Isolated public test gate

Explicit user deployment permission is required before running:

```
cd services/relay
npx wrangler deploy --config wrangler.pairing-staging.jsonc
```

This creates `together-pairing-staging`, using new Durable Object namespaces.
It does not update `together-connection`, its routes, namespaces or production
data. No Cloudflare secret is bundled with either app. The staging hostname is
`together-pairing-staging.together-connection-service.workers.dev` only if the
account confirms that subdomain. Verify the actual deploy result and HTTPS
health response before clients connect; do not infer deployment from source.

Staging remains live relay only, without an offline mailbox or media storage.
The independently reviewed security gate for production Protocol 4 remains open.
Rollback: disconnect the isolated test clients and remove their staging
configuration. Production continues using its unchanged Worker. Disable/delete
the staging Worker only after its test records are no longer needed and with
explicit cleanup authorization. Never delete production Durable Objects.

## Two independent cases

1. Samsung creates a native partner invitation; isolated Mac joins by text.
2. A new isolated Mac creates the invitation; a new isolated Samsung workspace
   joins by text. Do not reverse roles in an already-paired workspace.

For each: create distinct user/device keys, check equal six-digit verification
codes, require both confirmations, exchange bounded encrypted signed history,
verify identical co-signed genesis/space/checkpoint, then run the existing
Protocol 4 C1 sessions. Check bidirectional new/offline tasks, tombstones,
signed persistence ACK, finance and verified media. No copied private keys,
database snapshots or test content may enter the actual user workspace.

Mac uses Wi-Fi; Samsung uses its independent mobile/hotspot connection. Record
the actual Android active transport and Mac interface. `adb reverse --list`
must be empty before and after the run. USB is for test control, screenshots
and logs only. Loopback integration, physical USB-forwarded integration and
public cross-network acceptance are separate results.

Screenshots/logs/one-time codes stay local under ignored `qa/results` and
`qa/visual/candidates`; publish only aggregate, sanitized results. Never print
real identifiers, tokens, message content or private media in public reports.

## Compatibility boundary

Legacy `/v1/invitations` keeps the deployed 10-minute behavior and legacy
protocol checks. Issue #1 / PR #3 still tracks its formal 8-hour correction.
New purpose-specific `/v2/partner-invitations` uses a fixed server-controlled
8 hours, one-time atomic consumption and independent 60-second auth tickets.
Neither path silently enrolls another device under an existing user's ID.
Protocol 4 signed operation/envelope/ACK and domain semantics are unchanged.
