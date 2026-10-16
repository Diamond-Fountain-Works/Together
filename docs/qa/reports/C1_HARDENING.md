# C1 hardening and device enrollment — development Build 10

Status: implementation and headless tests complete; **release acceptance BLOCKED** by visual failures/human verification, independent protocol review, physical interoperability and an authorized API 2 rollout. PR #4 remains Draft. No app installation, production data correction, root-key reset, Worker deployment or PR merge is authorized by this report.

## Incident investigation

[The read-only incident report](STARTUP_INCIDENT_REVIEW.md) distinguishes confirmed startup writes from UNKNOWN preference history. Owner-only frozen raw copies, copied-file hashes, a separate SQLite analysis copy and detailed manifests are outside Git. Identity content matches trusted earlier evidence; retained history contains no new business operation or recurring bill. Startup did insert the local change-review record and update last-launch time. The main-file hash alone cannot prove unchanged logical data because WAL/SHM changed. No rollback or deletion was performed.

A later read-only source comparison found all four Application Support file contents/mtimes and the preferences content unchanged from this audit's frozen capture. This establishes no additional changes during the follow-up, not a claim that the earlier incident had no effect. Production databases were never opened with a database API by this audit.

## Implementation and compatibility

| Area | Evidence / boundary |
| --- | --- |
| Native device controls | Connection and Window menu open one native device sheet: list/fingerprints/self/online/offline/revoked, Add My Device, public-file import/export, explicit code checks, root-controlled revoke. No new sidebar or business module. |
| Independent enrollment | Offer/request/completion signatures, exact owner/space/origin binding, new private key, one-off request claim, separate staged store and last-step active pointer. Existing business data cannot be silently joined or discarded. |
| Legacy migration | Both original Mac keys sign the same current content checkpoint; before/after-network and activation checks reject changed history. Original IDs/keys, old binding and signed bytes remain. |
| History and revocation | Four native clients exercise the actual signed-file enrollment path, full-history catch-up, finance, original media hash, offline reconnect and revoke against an isolated real Worker. This is one Mac, not four physical devices. |
| Storage | Physical SwiftData classes unchanged. Scoped ModelContexts avoid retaining fetched model graphs; bounded bulk key lookup retains one fact/proof/head save boundary. Original-source upgrade and SIGKILL recovery tests pass. |
| Durable ACK | Wire receipts unchanged; whole-set membership uses 128-entry locally signed cache pages and an atomic final pointer. Restart/new local writes/tampered cache and borrowed unrelated legacy proof tests pass. Signed facts/tombstones/history are not pruned. |
| Key loss / archive growth | No silent root replacement or private-key copying. Root loss blocks owner control without its original key; see [ADR 006](../../architecture/adr/006-native-device-enrollment.md). Authorization paging remains [assessed, not implemented](../../architecture/AUTHORIZATION_HISTORY_PAGING.md); current 128 KiB cap fails closed. |

P4/API2 remains explicitly opt-in. Normal pairing is P3/API1; core invitation TTL stays 10 minutes. The formal 8-hour correction stays in separate Draft PR #3 and is not deployed. C2, Android UI, encrypted mailbox and central business storage are excluded.

## Automated gates

The final full headless run reports **136 Swift PASS / 0 FAIL / 3 SKIP / 139 discovered**; optional production-copy, child-only probe and opt-in 100k remain explicit skips. The separate opt-in 100k run below passed. A later focused revoked-target retry extension also passes. TypeScript check and **18 Relay tests**, **17 portable Python tests**, quality tools **7**, visual review tools **7** and publication-safety tools **3** pass.

Original-source 0.0.1 store upgrade, legacy V1 native integration, native four-client C1, and a real SIGKILL/restart test pass using synthetic/private temporary data. A supplemental tooling invocation accidentally used Xcode’s system Python 3.9 and failed imports (`PIL`/`jsonschema`); rerunning in the already configured `.qa-runtime` passes 17 conformance, 7 quality and 7 visual-tool tests. No dependency was installed to conceal this failure. No physical Mac/Mac, Android or four-device test is inferred. Debug build and Universal Release are separate checks. One concurrent Debug/Release build attempt encountered Xcode's locked build database; its failure log is retained, and the unchanged Debug source passed a serial retry.

## Same 100,000-operation workload

The test source/workload is unchanged: 100,000 actual inner/outer signatures, two disk-backed SwiftData replicas, encoded bidirectional inventory/fact/ACK exchange, reopen/verification, full business projection/change review and a scoped-correction/full-oracle equivalence assertion. The wire is in-process, not a WebSocket throughput or UI-frame benchmark. Single runs and concurrent host load are not statistically stable service promises.

| Measurement | Earlier `4091bf9` reference | Fresh pre-optimization | Scoped contexts + hex | Plus membership pages |
| --- | ---: | ---: | ---: | ---: |
| Signed local writes | 67.984 s | 99.663 s | 49.189 s | 48.808 s |
| Bidirectional synchronization | 343.095 s | 490.643 s | 215.361 s | **198.123 s** |
| Reopen/projection/review | 46.584 s | 75.419 s | 39.725 s | 40.501 s |
| Scoped correction/context | 2.760 s | 3.077 s | 1.085 s | 1.135 s |
| Full oracle | 7.761 s | 12.298 s | 6.181 s | 9.780 s |
| Total measured phases | 468.185 s | 681.100 s | 311.541 s | **298.347 s** |
| Peak RSS | 841.2 MiB | 773.0 MiB | 738.5 MiB | **722.8 MiB** |

Every run exchanges 28,152 frames, largest 31,560 bytes, queue peak 5. Final slowest local write batch is 41.5 ms; this is not a SwiftUI frame-time measurement. Full history and dependent-domain projection still require O(history) work/memory. No signature, operation count or domain check was skipped. Later enrollment retry/isolation and QA-launch fixes do not change this benchmark's exercised path; the result is not a second benchmark of those unrelated changes.

Main costs observed from code/phase measurements: repeated SwiftData per-key fetches and long-lived model retention, high-volume formatted hex allocation, and one persistent local ACK row per fact for complete checkpoints. The new implementation uses existing unique key indexes, bounded IN queries, scoped contexts, exact-byte hex encoding and signed page membership; it does not introduce a schema migration or change deterministic merge. Raw logs and JSON measurements remain in ignored `qa/results/replication-100k-hardening-{before,after,final}.json`.

## Source security review

The fixed range `8b3ebf6..93939f8` was reviewed under scan `13224739-f01a-4d93-ae71-922d456daa6b`: all 34 changed files accounted for, one Medium finding. A cached enrollment completion could omit revocations already known to its issuer. A real synthetic test failed before correction. Commit `cf75c38` refreshes authorization on retry while retaining unchanged cache bytes, rejects revoked targets and never issues another grant. Nine enrollment/isolation tests pass, and a separate source follow-up found the reported root cause addressed. This is not a zero-finding rewrite of the sealed earlier scan or independent protocol certification. Complete hostile-relay handshake exploitation was source-traced, not executed.

QA hardening also disables legacy Keychain fallback in copied fixtures and confines QA origin resolution to the explicit loopback Worker, including imported bindings. Original product release origins retain HTTPS validation. The old reviewed scan/fixes and independent security gate remain documented in [C1 QA](GITLIKE_C1_QA.md).

## Desktop QA and local permissions

**Final complete Build 10 run: 20 PASS / 0 FAIL / 1 SKIP, 80 captures.** The absent Our Story case is explicitly skipped. All three native device methods pass together with the original business/navigation/privacy tests: root authorization/revoke, independent-device join/full history and two-original-Mac migration. This is actual macOS UI with native file panels and an isolated real Worker, not two physical users performing the workflow.

The actual generated xctestrun targets `com.together.app.qa` and `com.together.app.qa.UITests.xctrunner`. Private temporary stores/preferences, file-only keys, an explicit loopback origin and both host/core fail-closed guards exclude production fallback. The Runner's temporary write exception covers only `/private/tmp/together-ui-qa/`. QA binary and test-source hashes match before/after this full run. Input-source inspection still reports the original Chinese Pinyin; this task did not switch it.

The final run is `qa/results/ui-build10-complete.json`, result `ui-20261016-133043.xcresult`, candidates `qa/visual/candidates/20261016-133043/`. All remain local/ignored. Earlier focused runs and failures remain available:

- Three device methods passed (3/0); expanded state/review queries passed (2/0). A later complete attempt recorded 5 PASS / 15 FAIL / 1 SKIP after an AX connection loss. Its exact original cause is UNKNOWN. It is not relabelled as passing.
- The finance capture matrix subsequently passed alone (1/0, 28 captures). A separate complete attempt was interrupted after a fail-closed QA launch screen. Discarded in-process new-window experiments did not present the scene.
- Build 10 removes the host delegate's asynchronous bundle self-relaunch. Tests now own/await native reopen with explicit fixture arguments/environment, verify the original PID, and reuse the helper on the cached-gift restart. The focused restart/device run passed 4/0 before the complete 20/0/1 regression.
- Corrected setup/locator failures include protected temp roots, target/Runner paths, Release-built package flags hiding the DEBUG-only loopback configuration, stale ad-hoc AX trust, overbroad/offscreen file matches, export-write races, AXValue/AXLabel and grouped reviewed-row queries. The test no longer queries a stale external notification-center process.
- An earlier native Open/Save XPC service crashed with an AppKit/HIToolbox/IMK stack during Go to Folder input. Exact causation is not independently proven. The final chooser selects the exact visible filename through native List view and restores the prior view, avoiding path typing/input-source changes. Currency search commits its query through paste and restores the complete clipboard. Existing CoreDevice/CoreSimulator version warnings are retained; no toolchain reinstall is claimed.

Temporary permission restoration is **verified**: targeted reset followed by a fresh native System Settings inspection shows the Runner row/toggle absent, matching its original state. DevToolsSecurity is disabled, the Settings page is returned to Battery, the bounded restoration watchdog exited, and no owned QA process remains. The temporary system prompt later disappeared; its exact dismissal mechanism is UNKNOWN (the user reported not seeing a fingerprint prompt). This is not a claim the user performed biometric authentication. No system password was read or entered.

## Visual comparison — still blocked

The complete formal 68-case matrix has **16 PASS / 50 REVIEW REQUIRED / 2 FAIL**, without changing thresholds or approved pixels. Twelve supplementary captures are candidates too. New human approvals: **0**. Build 4's approved 68 hashes and Build 5's 18 PASS / 50 REVIEW REQUIRED / 0 FAIL review remain unchanged.

The two raw failures are `reveal-dark-normal-opened.png` (2.7105% strong pixels) and `reveal-light-normal-opened.png` (2.0934%). Both remain 1320×1274 pixels. Static inspection shows a content-region vertical difference; an explicitly diagnostic crop comparison finds best candidate Y shifts -5/-3 pixels, reducing strong differences from 45,560 to 3,539 and from 35,205 to 8,016 pixels respectively. Header/footer are outside the observed raw difference bounding boxes. The GiftRevealView source is byte-identical to the Monorepo base. These observations suggest position/motion/capture differences but do **not** prove an environmental cause or approve the layout. Formal comparison is unaligned and still FAIL. Native privacy, Close, original-save and active-control assertions passed separately. Raw comparisons, side-by-side diagnostic images and exact provenance stay local. Human review and any separately justified targeted correction remain required.

## Release and remaining gates

Build 9 incremented the artifact after the device UI accessibility/owner-label correction (the retry security fix was Build 8). Build 10 increments it again after the QA bootstrap correction. Debug and Universal Release/DMG Build 10 passed; the 7,036,928-byte DMG has SHA-256 `76d07f2ff427ccb1cf0b2883a2118b3095a2d76c7662a07040f95fcc40de8785`. Verification checks version, unchanged `com.together.app`, both architectures, signature/entitlements, mounted content hashes and installer shortcut. It remains **ad-hoc signed, Gatekeeper rejected, notarization NOT RUN**; packaging is not permission to install. Binary/DMG/private diagnostic artifacts stay outside public Git. A final read-only check found no `/Applications/Together.app` or Together-named app in the two standard Applications directories; installed-binary continuity therefore remains NOT VERIFIED. This task performs no installation, app deletion or repair.

Remaining: resolve/review the two raw visual failures and all pending candidates, independent protocol/security review, physical cross-WiFi acceptance, API2 coordinated deployment authorization, authorization-history paging and separately reviewed root-loss recovery. No automatic log cleanup, production install or merge is performed. Public source publication is guarded by tracked-file plus all-ref/reflog credential/data scans and a verified external Git recovery backup.

## Changed source locations

- Native model/view: `apps/apple/macOS/Sources/TogetherApp/ViewModels/DeviceEnrollmentModel.swift`, `Views/Connection/DeviceManagementView.swift`, existing ApplicationModel/ConnectionView/RootView and menu commands.
- Domain/security: `packages/together-core-swift/Sources/TogetherCore/Networking/Relay/DeviceEnrollment.swift`, C1ReplicationService, RelayAPI, PairingService and Identity.
- Persistence/performance: Repository, ReplicaEngine, DurableAcknowledgement, PagedReplicationSession and ReplicationInventory; physical SwiftData model classes are unchanged.
- Tests/contracts: DeviceEnrollmentTests, DeviceAcknowledgementTests, C1MultiDeviceTests, native TogetherUITests, QA fixtures/Runner entitlements/project generator, public enrollment schema/vector and Python conformance.
- Governance: requirements, architecture/ADR, authorization-history assessment, design/copy, release notes, roadmap, test plan and protocol compatibility. Actual media/databases/private incident snapshots/new captures are excluded.
