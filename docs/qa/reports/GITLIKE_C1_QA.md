# Git-like C1 replication QA — development Build 6

Status: final validation in progress. Branch `feature/gitlike-c1-multidevice` is stacked on Monorepo `1832df0`; PR #2 remains Draft and untouched. Source is public, runtime/QA artifacts remain local. No installation or production Worker deployment is part of this task.

## Evidence scope

Tests use fresh synthetic identities, private temporary SwiftData/media directories and local Workers state. Original physical SwiftData models, production Bundle ID, identity file locations, old pins and V1 Relay binding remain unchanged. Compatibility is proved by a pinned old-source generated store, stable-key/space migration tests, actual SIGKILL recovery and four native local clients. This is not a guarantee about every possible production store or physical network.

Earlier focused current-code checks: 17 Swift tests passed, including four native clients through an actual local Worker; 44 focused scope/finance/progress tests passed; Workers typecheck and 18 runtime tests passed; Python conformance 13 passed. These are retained local logs, not substitutes for the final full gate below.

## Final gates

| Gate | Status / actual evidence |
| --- | --- |
| Swift full suite / generated old-store upgrade | Pending final run |
| Four native clients / old V1 / SIGKILL | Pending final integrated gate; focused checks passed |
| Relay / portable conformance / publication safety | Pending final gate |
| Debug / Universal Release / DMG | Pending final build |
| 100,000 actual signed/certified operations | Running Release benchmark; figures recorded after completion |
| Copy | 0 Error / 13 existing reviewed Warning in prior focused audit; keep WARN pending final audit |
| UI / visual | Automation initialization previously timed out; retry pending. No new baseline approved. |
| External security / physical devices | Independent security review BLOCKED; physical Mac/Mac, Mac/Android and four devices NOT RUN |

## UI verification and startup incident

An initial selected XCUITest run failed before executing assertions: “Timed out while enabling automation mode.” It is **NOT RUN**, not a passed or failed app assertion. Four attempted own-view AppKit captures had incomplete compositing/transparency and are **INCOMPLETE**, not visual acceptance. Native computer-use inspection of a live isolated fixture checked Mark Reviewed, close/reopen persistence and routing into the existing task editor; it does not replace screenshot baseline approval.

During that inspection, after the fixture process exited, the app selector launched the normal source Debug bundle without fixture arguments. It was stopped immediately without any UI action or business edit; nothing was installed. Ordinary startup accessed production storage/preferences and may have run automatic reconciliation. Those effects are **not proven unchanged**; no real-data rollback, cleanup or key reset was attempted. Private diagnostic details remain in ignored local QA output. This is an execution incident, not a successful production-data isolation check.

The follow-up adds a dedicated `UITesting` Xcode configuration with `com.together.app.qa` and a fail-closed `TOGETHER_UI_TEST_HOST` bootstrap. Core production startup also rejects that QA bundle. Normal Debug/Release keep `com.together.app`. All further UI automation must target a confirmed live QA-host fixture; the primary installation is not launched/replaced. Retain the original Build 4 approved hashes and Build 5 18 PASS / 50 REVIEW REQUIRED / 0 FAIL states.

## Compatibility and recovery limits

Protocol 3 SignedOperation bytes still verify; Protocol 4 adds an outer epoch/sequence signature, not a rewrite. Exact fact/proof/head transactions, durable chain gaps, per-device signed receipts and actual child-process SIGKILL recovery are tested. Invalid or superseded candidates are diagnosed/history-only. Local signed operations are canonicalized to the already-defined millisecond representation before publication so local state equals persisted/replayed state.

The normal app path remains Protocol 3 until explicit co-signed activation. New-device public authorization/provisioning and root-controlled view/revoke domain APIs exist; user-facing enrollment/QR exchange and migration proposal exchange do not. No private key copying, root-loss recovery, encrypted backup UI, authorization-history pagination, complete incremental dependent-domain index or safe automatic history pruning is claimed. Full-history/background projection and complex-domain replay remain real performance costs.

Per-device signed ACK means durable receiver facts; one partner device is sufficient for partner sync, while one's own phone alone is insufficient. Media requires original SHA-256/format validation before its gift receipt. Review is local presentation state, not partner approval or wish fulfillment confirmation.

## Rollout restrictions

Do not deploy API 2, merge to main, install Build 6 or replace approved screenshots on the basis of this document. The independent eight-hour invitation correction is [Draft PR #3](https://github.com/Diamond-Fountain-Works/Together/pull/3), both CI jobs passed at `32a19cac0aebc9f803404d3f91a1eab348ee5196`; it is not deployed. Core branch still has the existing ten-minute TTL, and challenges/tickets remain 60 seconds.

Existing V1 routes and trusted bindings are retained. Pre-activation rollback is additive; after new V4 writes, an old binary cannot safely consume the new trust/certificates. Any coordinated restore needs explicit recovery approval and retained history, never deletion/reset of live state. See [architecture](../../architecture/GITLIKE_REPLICATION.md) for exact limits and activation/rollback steps.
