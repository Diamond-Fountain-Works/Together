# P2P transport foundation — development Build 14, 2026-10-19

This optional library is not linked into the installed applications. Current
local installs remain Mac Build 13 / Android code 8 with the merged Plans UI.
No P2P production installation/deployment or PR merge occurred.

## Verified scope

- Native package compiles on the local arm64 Mac. Official Iroh dependency is
  pinned; direct tests disable every relay/discovery service and bind loopback.
- Three core endpoint-binding/trust/replay tests pass. A transport endpoint may
  not reuse an archived device signing key. Current authorization is checked for
  content access; old cipher packets and revoked credentials are rejected.
- Two real local QUIC tests pass: unchanged paged replication, 258 independent
  facts, authentic durable ACK, then a tombstone as fact 259; and rejection of a
  malicious 4 GiB frame length before body allocation. Selected paths must be IP
  direct and not relay. This is not public-network or physical Android evidence.
- Default Swift regression: 138 PASS / 0 FAIL / 11 explicit prerequisite SKIP.
  Portable Python conformance: 17 PASS. The current 100k QUIC workload is NOT RUN.

## Retained failure and snapshot hardening

The first P2P CI job failed after its convergence observer reached the unchanged
15-second bound; it surfaced only `.closed`. Its original log/run remains
`39269660036`, job `118118295259`. This initial log alone does not prove a cause.

Receiver errors are now propagated into the test observer instead of remaining
in an unobserved background task. Repeating the identical 258+1-fact workload
locally reproduced `.inventoryChanged` on run 7. A new fact can invalidate the
optimistic inventory scan while ACK/inventory work is in progress.

`OperationInventoryIndex.snapshot` now retries only that stale-scan condition up
to eight times, with bounded 1–64 ms backoff (127 ms total scheduled delay).
It still revalidates revision/visibility, discards invalid caches and throws if
stability cannot be obtained. All other errors propagate. No operation, signature,
merge rule, receipt condition or wire format changes, and no global network/test
timeout was increased. This is a narrow index-read recovery change, not a new
SyncEngine. It also applies to the retained C1 callers of the same index.

After the change the same workload passed **12/12 consecutive local runs** and
the full 149-case default suite passed with the 11 explicit skips. The original
failure is retained; latest-commit CI is checked separately before delivery. The
scheduled wait bound is not a claim about total scan cost under a 100k workload.

## Unverified/release gates

Android production P2P and shared wire vectors; actual Mac–Samsung/public NAT traversal;
user-facing invitation/reconnect/media integration; transport-key persistence,
rotation and recovery; 100k transport performance; independent protocol review.
Upstream's prebuilt Apple binary is arm64/macOS 14.5+; the existing Universal /
macOS 14 app must not silently lose support. No visual baseline is approved by
these tests. Private stores, keys, network logs and screenshots remain excluded.

Follow-up: a compiled Android instrumentation-only adapter, native QA CLI and
bounded physical driver are implemented. The first physical attempt stopped
before payload exchange and the phone disconnected; [public acceptance](P2P_PUBLIC_ACCEPTANCE.md)
is still blocked, not a public-network PASS.
