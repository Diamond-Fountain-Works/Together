# Android Phase B — evidence and release boundary

Date: 2026-10-17. Independent worktree `Together-Worktrees/android-business-phase-b`, branch `feature/android-business-phase-b`, baseline `1dfce291ac02726e48717558f48f76f196662032` (PR #5). Repository remains Public. PRs #2/#3/#4/#5 are open Drafts; this client must stack on `feature/android-foundation`. No parent branch, production installation/data, device identity or Worker deployment is changed.

## Implementation

| Surface | Status | Scope |
| --- | --- | --- |
| Native business navigation | IMPLEMENTED / TESTED | Home, Our Plans, Wishes, Our Finances, Connection, Settings; phone drawer / tablet rail; no fake Our Story or permanent Gift page/card |
| Tasks | IMPLEMENTED / TESTED | One CRUD editor, owner/due date, three filters, regular every-N and flexible recurrence/Set Next Time; tombstones and offline commands |
| Wishes | IMPLEMENTED / TESTED | Two member directions, dated grants/items, request/confirm/reject, audit adjustments and diagnosed quota conflicts |
| Finance | IMPLEMENTED / TESTED | One Expenses ledger; deposits/negative reserves, frozen CNY/original amounts, deterministic AA, bills/revisions/forecast/confirmation/skip, cycles, date events and private/shared card metadata |
| Gifts and originals | IMPLEMENTED / TESTED | Daily shared-zone quota, any nonempty text/photo/audio combination, original streaming/64KiB resume/SHA, recording/manual playback, sealed reveal/history and explicit original export |
| Change review | IMPLEMENTED / TESTED | Actor/device origin, effective before/after, pagination, local reviewed/notified; sealed gift metadata only; no ordinary partner approval |
| Android lifecycle | IMPLEMENTED / TESTED | Foreground live sync/reconnect, offline CRUD, Room/Keystore reopen and process death; no permanent background connection/mailbox |
| Physical Mac/Samsung use | NOT RUN | No connected Samsung or separately authorized production API2 rollout |
| Production acceptance | BLOCKED | Independent protocol review, physical use and human candidate approval remain separate gates |

## Reproducible automated evidence

All clients/stores/media below are synthetic and loopback-only. Runtime artifacts, screenshots, APKs, logs, original media and identities remain ignored/local; source fixtures and test code are public-safe.

| Check | Actual result | Local evidence / command |
| --- | --- | --- |
| Kotlin JVM | 53 PASS, 0 FAIL, 0 SKIP with both opt-ins | `TOGETHER_RUN_SWIFT_ANDROID=1 TOGETHER_LOCAL_RELAY_URL=http://127.0.0.1:8797 apps/android/gradlew -p apps/android :core:domain:test :core:protocol:test`; XML under `core/*/build/test-results/test/` |
| Native Swift/Kotlin C1 | TESTED, with one retained intermittent timeout noted below | `NativeBridgeIntegrationTest`, actual local Worker; `qa/results/android-phase-b/native-{bridge.log,result.json,diagnostic.json}` |
| Instrumentation | 16 unique PASS, 0 FAIL, 3 standalone hooks SKIP | Full phone-light and large/reduced suites each 19 cases; dark/tablet UI-only each 6 PASS. Repeated configurations are not counted as additional unique tests. `qa/results/android-phase-b/instrumentation/*.xml`, `visual-matrix.json`; skipped hooks are orchestrated separately |
| Debug APK / test APK | PASS | `:app:assembleDebug :app:assembleDebugAndroidTest` |
| Actual APK upgrade | PASS on exact final APK hash | `qa/results/android-phase-b/apk-upgrade/result.json`; six facts, original key/signatures/binding/schema retained |
| Actual process/SAF/media UI | PASS | `qa/results/android-phase-b/process-launch/result.json`; cached offline sealed once, explicit playback completion, byte-identical export and persisted opened state; strengthened Compose pause assertion also passed |
| Android lint | PASS with 11 dependency-update warnings, 0 errors | Nine `GradleDependency`, two `NewerVersionAvailable`; no rule suppression. `app/build/reports/lint-results-debug.xml` |
| Android Copy QA | PASS, 552 resources, 0 errors, 0 warnings | `scripts/audit_android_copy.py`; exact base/Chinese hashes/categories in `qa/android_copy_review.json` |
| Swift regression suite | 138 PASS, 0 FAIL, 4 SKIP | Headless `scripts/qa.sh --skip-ui`; `qa/results/business.log` and `summary.json`. Bridge-specific native execution is reported separately |
| Relay | 18 PASS; TypeScript check PASS | `qa/results/server-tests.log`, `server-check.log`; no production deployment |
| Portable conformance | 17 PASS | `qa/results/protocol-conformance.log` |
| Existing SwiftData upgrade / four-client C1 / crash recovery | PASS in isolation | `qa/results/summary.json`; original-source legacy fixture and private temporary store, no production data |
| macOS Debug build | PASS; no production app launch/install | `qa/results/build.log`; Apple runtime source is unchanged |
| Apple Copy / UI / Visual | WARN / NOT RUN / NOT RUN in this headless run | Existing 14 copy warnings retained; previous approved/candidate baselines are not overwritten or approved |

Shared Swift/Kotlin fixtures retain UUID/CanonicalJSON/Ed25519/authorization/certificate/ACK/P3 compatibility and domain results. The native bridge runs one Swift test process with two independent clients plus Kotlin, exchanging tasks, wishes, CNY/AA/reserves/bill uniqueness, original PNG/WAV hashes, content receipts, offline edits and catch-up. Public descriptors are signed by synthetic roots; private keys stay in their generating process. This is not physical Mac/Android or Mac GUI acceptance.

### Retained failures and diagnosis

- Earlier setup failures (test serialization, synthetic filename/URI expectations, shared test rate bucket) remain in ignored logs and were corrected in tests, without weakening production checks.
- Actual defects corrected: deleting a gift now consults its dedicated projection; flexible complete-later clears an old proposed next time; confirming a forecast expense explicitly freezes derived amount/payment rather than filtering equal fields out; player `ON_STOP` only pauses when playing, avoiding a Prepared-state error during native SAF export.
- The first native offline test used a full Swift task edit that also wrote unchanged notes. The current distinct-field test emits a title-only native domain operation and keeps same-field conflict tests. Mac GUI editor field-baseline tracking was not added and remains a known upstream UX limitation.
- One later full run timed out at native reconnect convergence. No root cause was proved for that occurrence. The unchanged assertions passed in the following isolated native run and the subsequent complete 53-test run. Stage/connection/error/notes/receipt diagnostics were added; the original timeout log remains `qa/results/android-phase-b/native-reconnect-timeout.log`, with the full failing invocation in `full-run-reconnect-failure.log`. It is not relabelled as a fixed runtime defect or silently erased. CI/repeated local evidence must remain visible.
- The stalled-provider regression first exposed a test-APK Kotlin class-loader failure; its provider now uses platform Java. An immediate post-click assertion then needed a bounded wait for the asynchronous draft save. Final regression invokes the real GiftEditor `OpenDocument` callback and cancellation-owned job via an injected picker result; it does not claim to test the external picker UI itself.
- Native playback QA originally paused after a fixed 1.2 seconds and expected a nonzero whole-second label. `dumpsys media.player` measured 611ms output latency, so actual progress could still round to `0:00`. The driver now waits for the real fixture completion; the Compose test separately waits for real progress and pauses. No application playback rule, assertion threshold or test size was reduced.

## Storage, upgrade and original-media acceptance

Room remains schema 1, with no destructive fallback. Business command groups validate a fresh candidate and atomically commit signed facts, certificates and Lamport before networking. Private cards/drafts/presentation/review state remain local records. Missing Keystore material fails closed; independent Android keys never replace/copy the Mac root or create a third partner.

`scripts/test_android_apk_upgrade.py` verifies the checksum-pinned original Phase A APK (`c8d35f118fb88f6323f892d99f6b7055d2a4c22e8f60125d9dea23ac2e9b9534`) using actual emulator `adb install -r`, not a Room-only mock. Its seed/verify instrumentation preserves six signed facts (task, grant/item, reserve, expense and gift), exact signed bytes, identity/public key, binding and Room1, then signs a new operation with the original key. Results: `qa/results/android-phase-b/apk-upgrade/{result,before,after}.json`. No uninstall/clear, physical-device installation or macOS installation is part of the driver.

`scripts/test_android_gift_lifecycle.py` force-stops/relaunches the real dedicated QA Activity. It removes the test adb reverse for cached offline sealed display, checks once-only/opened state after process death, explicitly starts audio and requires its completed timeline, and uses the native SAF save panel. The Compose test separately pauses after actual progress. Exported original: 230659 bytes, SHA-256 `c17eac6d26c6b162dd3df10ff669366238c0de3df74d2913095e09385c7fede7`. The reverse is restored in `finally`. `process-launch/result.json` distinguishes native UI/export evidence from an in-memory media test.

Encrypted media interruption tests hold requests after offset 65536, close/reopen Room and Keystore, reconnect, resume at the durable offset and require original SHA plus recipient receipt. A log ACK alone is asserted insufficient. Separate cases exercise photo-only, audio-only, combined content, deletion without quota refund and a shared-zone new day.

## Security follow-up

Managed immutable diff review `77af8419-cafb-49a0-9b80-f3de82740a50` covers `1dfce291..a264595`, 40 source files, with generated architecture model, candidate validation and attack paths. It reports one Medium unreferenced-media storage issue and one Low provider/mutex availability issue on that older tree; it is not a clean scan of later commits. A bounded PoC staged one 64KiB chunk from a valid signed but unreferenced declared 1TB asset. No disk was filled.

Later code restricts automatic fetching to live references, budgets combined remaining leases against dynamic free space, retains a database/OS reserve and checks every write. Provider I/O no longer holds the repository mutex; dismissal cancels/closes the stream. `MediaImportLease` acquires completed-file ownership before cancellable handoffs, cleans unpublished originals and retains committed ones. Eight JVM media tests and the Android real-callback/stalled-pipe UI regression cover these controls. Read-only developer follow-up found no remaining concrete issue in these corrections; this is not independent security certification.

Correction commit: `f47ba70` (separate from the immutable reviewed `a264595` tree). Neither original findings nor failed test attempts are overwritten to manufacture a clean result.

The sealed report is local under the Codex Security scan directory, not uploaded with user/workbench metadata. Tool-reported usage for this scan: total 12,871,117; input 12,793,570; cached input 12,307,200 tokens (complete accounting). This is tool metadata, not a cost estimate. Publication scanning covers tracked source plus every ref/reflog-reachable historical blob; ignored private/runtime files remain excluded. It cannot prove the absence of every unlabeled secret or replace protocol review.

## Visual candidates

Local candidate set: `qa/visual/candidates/android-phase-b/`. The matrix contains 20 views × four configurations (80 screenshots): phone light, phone dark, tablet light (1600×2560/density240), and phone dark with font1.3/animation scales0. Four native process/SAF captures are separate. Local `index.html` and `manifest.json` provide names, originals and exact hashes. Approved Android baselines: **0**. Status: **CANDIDATE / REVIEW REQUIRED**, never auto-approved. Apple baseline state is preserved.

Checked surfaces include task filters/editor, wish fulfillment, all finance tabs/editor/day wheel/currency/cycle, settings/connection/review, sealed/opened gifts and audio editor. Footer buttons remain outside scrolling form content. Dark/large-text captures retain accessible contrast and scrollable content; only present gift content is exposed after Open. The AVD status-bar glyph clipping also occurs in the native launcher (`qa/results/android-phase-b/systemui-home.png`), so that environment evidence is retained rather than silently cropping/changing screenshot thresholds. No physical tablet, TalkBack or human visual approval is inferred. Emulator size/density/night/font/motion settings are recorded and restored in `emulator-settings-{before,after}.json`.

## Artifact and remaining gates

Debug APK: `apps/android/app/build/outputs/apk/debug/app-debug.apk`; `com.together.android.debug`, `0.2.1-phaseB` (code 2), min28/target36. Current candidate: **39,915,549 bytes**; SHA-256 **`3f9843fa3b07b563917c1a671516a93cbc0d8190b0895abe196ede90516735e1`**. Signed with the existing Android Debug identity, not production/store signing. Local `apk.json`, badging and signature reports bind the artifact. No APK, media or screenshot is committed to Public GitHub.

NOT RUN / BLOCKED: Samsung/physical Mac↔phone/four-device/cross-WiFi, minimum API28, actual tablet/OEM lifecycle/TalkBack, physical power-loss, independent security review, root-loss/delegated authorization/archive paging, production API2 rollout and store signing. An already populated standalone workspace is not silently reassigned during enrollment. Android100k performance and C2 are not claimed. In-app bill reminders do not promise background alarms. No parent/new PR is merged or production service installed/deployed.

GitHub delivery: the source branch and new Draft PR must target `feature/android-foundation`; CI results are checked against the final pushed SHA and reported separately from emulator/physical acceptance. Existing Apple review states and Public visibility remain unchanged.
