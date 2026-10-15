# Git-like C1 replication QA — development Build 6

Status: local headless gates passed; release approval **BLOCKED** by independent security review, desktop UI/visual acceptance and enrollment/activation UX. Runtime fixes are committed at `4091bf91de877f00979c8e25128b0d4f8126a9fa`. Branch `feature/gitlike-c1-multidevice` is stacked on Monorepo `1832df0`; PR #2 remains Draft and untouched. Source is public, runtime/QA artifacts remain local. No installation or production Worker deployment is part of this task.

## Evidence scope

Tests use fresh synthetic identities, private temporary SwiftData/media directories and local Workers state. Original physical SwiftData models, production Bundle ID, identity file locations, old pins and V1 Relay binding remain unchanged. Compatibility is proved by a pinned old-source generated store, stable-key/space migration tests, actual SIGKILL recovery and four native local clients. This is not a guarantee about every possible production store or physical network.

Earlier focused checks are retained as development evidence, not substitutes for the fresh full gate below. The latest six adversarial recovery regressions also passed independently after all runtime fixes.

## Final gates

| Gate | Status / actual evidence |
| --- | --- |
| Swift full suite | **PASS: 125 passed / 0 failed / 3 skipped / 128 discovered**. Skips are the optional production-copy rehearsal, child-only crash probe and opt-in performance case; none are relabelled as passed. |
| Generated old-store upgrade | **PASS**, actual pinned 0.0.1 source creates 11 signed facts in a private temporary store; upgrade/reopen retains keys, tasks, wishes, gifts, avatar, presentation state, pins and Relay binding, initializes finance without changing physical SwiftData classes. |
| Four native clients / old V1 / SIGKILL | **PASS**, actual local Wrangler, four independent Swift clients/keys/sockets, concurrent task/finance writes, original photo hash + gift receipt, offline catch-up and revocation. Separate legacy URLSession session and killed child-process restart passed. One Mac, not four physical devices. |
| Relay / portable conformance | **PASS**, TypeScript check, 18 Worker runtime tests and 14 Python conformance tests; QA tools 7, visual review tools 7 and publication-safety tools 3 passed. |
| Publication safety | **PASS** before source commits; tracked files plus all reachable/ref/reflog history scanned. Re-run before each push; reports stay in ignored `qa/results`. This is not an independent security approval. |
| Debug / Universal Release / DMG | **PASS**, 0.2.1 Build 6, unchanged `com.together.app`, arm64 + x86_64, macOS 14+, DMG mounted metadata/hash/signature/shortcut checks. Ad-hoc signature, **Gatekeeper REJECTED / notarization NOT RUN**. Nothing installed. |
| 100,000 actual signed/certified operations | **PASS**, final immutable-runtime `4091bf9` run: 1 benchmark passed, 468.459 s test duration; exact phase/resource measurements below. It is separate from the full suite's opt-in SKIP. |
| Copy | **WARN: 0 Error / 13 existing Warning**; individual dispositions retained in the copy review index. No audit rule disabled or broad ignore added. |
| UI / visual | **NOT RUN / REVIEW REQUIRED**: final retry selected 3 UI methods, runner failed to initialize before any app assertion. Zero exported XCTest captures; no new baseline approved. |
| External security / physical devices | Independent security review BLOCKED; physical Mac/Mac, Mac/Android and four devices NOT RUN |

## UI verification and startup incident

The final selected XCUITest retry failed before executing assertions: “Timed out while enabling automation mode.” Xcode records one runner infrastructure failure, **0 passed app assertions and 3 requested methods NOT RUN**. The result bundle is `qa/results/ui-20261016-015042.xcresult`, summary `qa/results/ui-c1-final.json`; Xcode also logs its CoreDevice plugin/CoreSimulator mismatch. No system toolchain or input-method reconfiguration was attempted. Four attempted own-view AppKit captures had incomplete compositing/transparency and are **INCOMPLETE**, not visual acceptance. Native computer-use inspection of a live isolated fixture checked Mark Reviewed, close/reopen persistence and routing into the existing task editor; it does not replace screenshot baseline approval.

During that inspection, after the fixture process exited, the app selector launched the normal source Debug bundle without fixture arguments. It was stopped immediately without any UI action or business edit; nothing was installed. Ordinary startup accessed production storage/preferences and may have run automatic reconciliation. Those effects are **not proven unchanged**; no real-data rollback, cleanup or key reset was attempted. Private diagnostic details remain in ignored local QA output. This is an execution incident, not a successful production-data isolation check.

The follow-up adds a dedicated `UITesting` Xcode configuration with `com.together.app.qa` and a fail-closed `TOGETHER_UI_TEST_HOST` bootstrap. Core production startup also rejects that QA bundle. Normal Debug/Release keep `com.together.app`. All further UI automation must target a confirmed live QA-host fixture; the primary installation is not launched/replaced. Retain the original Build 4 approved hashes and Build 5 18 PASS / 50 REVIEW REQUIRED / 0 FAIL states.

## Compatibility and recovery limits

Protocol 3 SignedOperation bytes still verify; Protocol 4 adds an outer epoch/sequence signature, not a rewrite. Exact fact/proof/head transactions, durable chain gaps, per-device signed receipts and actual child-process SIGKILL recovery are tested. Invalid or superseded candidates are diagnosed/history-only. Local signed operations are canonicalized to the already-defined millisecond representation before publication so local state equals persisted/replayed state.

The normal app path remains Protocol 3 until explicit co-signed activation. New-device public authorization/provisioning and root-controlled view/revoke domain APIs exist; user-facing enrollment/QR exchange and migration proposal exchange do not. No private key copying, root-loss recovery, encrypted backup UI, authorization-history pagination, complete incremental dependent-domain index or safe automatic history pruning is claimed. Full-history/background projection and complex-domain replay remain real performance costs.

Per-device signed ACK means durable receiver facts; one partner device is sufficient for partner sync, while one's own phone alone is insufficient. Media requires original SHA-256/format validation before its gift receipt. Review is local presentation state, not partner approval or wish fulfillment confirmation.

## Source security review and fixes

The sealed, skill-owned source diff scan covers `1832df0..4eb3e5d`, scan ID `a0bea1b5-ce5b-42bc-a845-571cef534d36`: 85 changed files reviewed, four reportable findings (one High, three Medium). It is retained locally rather than uploaded with private machine diagnostics. It must not be described as a zero-finding scan of the later fix commit or as independent cryptographic certification.

Commit `4091bf9` fixes retired signed-hello rollback/key-counter reuse, poisoned durable predecessor staging, stripped post-migration facts poisoning the legacy baseline, and revoked fork records bypassing the exact accepted cutoff digest. Follow-up source review also found the partial-baseline overflow variant and a stale asynchronous projection/authorization race; both are fixed in the same commit. Six executable adversarial tests passed: replayed old hellos, invalid staged chains with restart repair, complete/partial legacy poisoning recovery, exact revoked-prefix recovery with raw rejected history retained, and a deterministically paused stale projection unable to reinstall revoked facts. These are tested remediations, **not** a rewritten result for the earlier sealed scan. Independent protocol review remains **BLOCKED**.

## Reproduction and package evidence

Local host: Apple M4, 24 GiB RAM, macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Swift 6.4. Full gate: `TOGETHER_QA_PYTHON=<configured QA Python> ./scripts/qa.sh --skip-ui`, then `python3 scripts/check_ci_report.py`. This runs synthetic/temporary data and a fresh loopback Worker. Current detailed results are in ignored `qa/results/summary.json` and per-gate logs; hosted desktop UI is intentionally not inferred from CI.

`python3 script/package_app.py` from `apps/apple/macOS` builds, mounts and verifies `dist/Together-0.2.1-Build6-Universal.dmg`: 6,620,672 bytes, SHA-256 `a70ce867dd08104355f162269f412c686b68e78cabb95742beef93a14a7215bd`. The public Relay origin is configuration, not a claim that API 2 has been deployed. The binary/DMG and machine QA files are excluded from the public source repository. Packaging does not authorize installation.

### Large-history measurements

Command: `TOGETHER_RUN_REPLICATION_PERF=1 TOGETHER_PERF_OUTPUT=<absolute existing QA directory>/replication-100k-4091bf9.json swift test -c release --package-path packages/together-core-swift --filter ReplicationPerformanceTests`. Output and complete log are retained locally. One earlier invocation failed at result-file output because its relative destination did not exist; the corrected absolute-output run and this final repeat passed. No failed attempt is substituted for the final result.

The final run generates 100,000 independently signed operations and outer certificates, writes two isolated on-disk SwiftData replicas, exchanges actual encoded paged frames through an in-process test wire, then reopens/replays and compares a scoped correction with the full projector oracle. It measures cryptography/storage/encoded protocol behavior, **not WebSocket RTT, physical cross-WiFi throughput, or SwiftUI frame latency**.

| Measurement | Final `4091bf9` Release run |
| --- | --- |
| Local signed/certified writes | 67.984 s |
| Bidirectional anti-entropy | 343.095 s |
| Reopen + verified projection + change history | 46.584 s |
| Scoped correction including context | 2.760 s; 1 changed cache row |
| Full correction oracle | 7.761 s |
| Measured phases total / test duration | 468.185 s / 468.459 s |
| Encoded frames / largest frame / queued frames | 28,152 / 31,560 bytes / 5 |
| Slowest local batch | 0.0848 s; this is not a measured UI frame time |
| Process peak RSS | 882,065,408 bytes (about 841 MiB) |

Pagination bounds wire frames/queues and repository fetches; it does not make the complete legal-operation set, projection or review history constant-memory. Large dependent-domain indexing and lower peak RSS remain follow-up work. `databaseSchemaChanged: false` in the benchmark output is configuration metadata; the separate old-store migration test supplies migration evidence.

## Source delivery and recoverability

Core source is [Draft stacked PR #4](https://github.com/Diamond-Fountain-Works/Together/pull/4), based on `refactor/monorepo-foundation`; check the latest head's live GitHub Actions, rather than treating an earlier run as current. Hosted headless CI intentionally reports desktop UI/visual NOT RUN and security REVIEW REQUIRED. No merge is authorized.

An owner-only external backup at `RepositoryBackups/Together/c1-runtime-4091bf91de87-20261016-020744` retains raw Git objects/reflogs, all original references and the then-uncommitted documentation patch. The all-refs/reflog bundle was restored into an independent mirror: **20/20 recoverable commits, bundle verify and full fsck PASS**; bundle SHA-256 `6a4be9a9383c703c1ae7da91a7f10bace0a88c5a2305b784d81b870aa48c0880`. Previous verified backups and the live standard `.git` remain intact. No backup or runtime artifact is published.

## Rollout restrictions

Do not deploy API 2, merge to main, install Build 6 or replace approved screenshots on the basis of this document. The independent eight-hour invitation correction is [Draft PR #3](https://github.com/Diamond-Fountain-Works/Together/pull/3), both CI jobs passed at `32a19cac0aebc9f803404d3f91a1eab348ee5196`; it is not deployed. Core branch still has the existing ten-minute TTL, and challenges/tickets remain 60 seconds.

Existing V1 routes and trusted bindings are retained. Pre-activation rollback is additive; after new V4 writes, an old binary cannot safely consume the new trust/certificates. Any coordinated restore needs explicit recovery approval and retained history, never deletion/reset of live state. See [architecture](../../architecture/GITLIKE_REPLICATION.md) for exact limits and activation/rollback steps.
