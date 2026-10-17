# Android Phase C — physical device and native C1 acceptance

Date: 2026-10-17. Baseline PR #6 / `7e9d0c1182ff2741af748e0f976509058039d2c4`.
Worktree `android-physical-phase-c`, branch `feature/android-physical-phase-c`; stack targets Phase B,
not the pre-Monorepo main. PR #2/#3/#4/#5/#6 were checked: all OPEN Draft, unchanged parent SHAs.
Repository remains Public. No PR merge, production Worker deploy or macOS App install is authorized.

## Device and installation

Physical Samsung SM-S9210, Android16/API36, ARM64-v8a, security patch 2026-08-05. Initial display
1080×2340, density480, font1.0, light mode; serial and device-local metadata stay in ignored evidence.
ADB was live-authorized before control. Android Studio/SDK/ADB/JDK21 already existed; no new SDK/JDK
or unrelated app was installed. Normal and Debug Together packages were absent initially.

The exact Phase B APK SHA-256 `3f9843fa3b07b563917c1a671516a93cbc0d8190b0895abe196ede90516735e1`
was verified before installation. Same Debug certificate, package `com.together.android.debug`,
version `0.2.1-phaseB`/code2. First real cold launch `am start -W`: **516ms TotalTime**, single Debug
sample, not a release startup benchmark. Later QA changes retain the package/signer with `install -r`;
no uninstall, data-clear or production namespace access. Final candidate hash/version is recorded below
after final validation.

## Verified results to date

| Gate | Result | Scope / local evidence |
|---|---|---|
| Physical Room/Keystore/business/Compose | Final 16 PASS / 0 FAIL / 0 SKIP | `samsung-final-code5-r2`, 69.107s; initial/second failed attempts remain separate |
| Microphone and recording | PASS | User granted native permission; real pause/resume/stop, M4A original, audio-only gift consumes one quota |
| Physical Android ↔ native Swift C1 | PASS | `native-physical-4/result.json`: two phone instrumentation cases + one native Swift test; actual USB-reversed local Worker |
| Enrollment/history/identity | PASS in isolated native/domain workflow | Independent Android key, same owner/space, signed root completion, retained V3 checkpoint and tombstone |
| Business merge/ACK/media/revoke | PASS | 25-fact count/content digest equality; book balance1967 CNY minor/personal999, one bill, fulfilled wish; both originals match; force-stop restores signed per-device ACK; revoked ticket error `NOT_AN_AUTHORIZED_DEVICE` |
| Controlled reliability | PASS | `samsung-reliability-1`: link loss, automatic backoff, abrupt WS close, eight cancel/connect races, 1,025-fact catch-up; independent lost/duplicate ACK frame-pump assertions |
| Same-signer candidate replacement | PASS | `code5-upgrade-format`: code4 → code5 retains the previous physical native round's25 facts, identity, binding, ACK/media; no production migration claim |
| Kotlin JVM/native regression | 53 PASS / 0 FAIL / 0 SKIP | Explicit local/native flags; existing Phase B workload and assertions unchanged |
| Relay / portable conformance | 18 PASS / 17 PASS | Local service, TypeScript check; proper existing QA Python env |
| Copy | PASS | 552 Android resources / 0 errors / 0 warnings; no new product copy |
| Public network / physical four devices | NOT RUN | USB is not cross-WiFi; no API2 staging/production deployed |
| Independent protocol/security review | BLOCKED | Developer tests and publication scanning do not substitute |

Detailed integration stages: offer/root completion, initial history, live wish/media, offline barrier,
reconnect, actual force-stop/reopen and revocation. Native comparison verifies both Mac stores match
Android's 25-fact checkpoint. ACK proof is distinct from a socket send or relay forward. Content SHA
and gift receipts are additionally required; no false Delivered/read/payment state is introduced.

The reliability case converged all three clients at 1,032 facts before its final two-client ACK-loss
subcase. That subcase adds one fact with the third client intentionally stopped; final counts
`[1033,1033,1032]` are **not** represented as three-client convergence. It completed in94.059s;
phase timings include offline fact creation and receipt persistence, not just network transit.

## Retained failures and corrected test machinery

- The first physical UI run had13 passes and2 failures. Samsung IME movement required ending keyboard
  interaction before calculating a Save touch; a finance-settings control was outside the lazy-list
  viewport and now explicitly scrolls into view. A task reopen/delete lookup waits for the actual
  merged node after animation. The strengthened two-case run passed without larger business timeouts.
- The first complete code5 rerun had15 passes and1 failure: an IME/layout transition prevented opening
  the recurrence menu after typing the title. The test now closes the keyboard before measuring the
  menu button, waits for the actual option and keeps the selection assertion. Complete rerun
  `samsung-final-code5-r2` passed all16 in69.107s, with no Runner teardown timeout. Recording now also
  explicitly previews its actual M4A until playback advances, pauses and then sends.
- One intermediate rebuild failed before packaging because Espresso was not a direct test dependency;
  a retry accidentally used the previous test APK. Its failure is retained and is not counted as a
  post-fix regression result. The test-only dependency is now explicit, and four exact artifacts were
  independently fetched from Google Maven and matched to pinned verification metadata. Strict
  dependency verification remains enabled. No production dependency was added.
- Permission UI temporarily removes Compose hierarchies. The recording test now waits for the actual
  OS permission before querying Compose; it never taps or programmatically grants a physical permission.
- Native bridge attempts1–3 failed in new QA orchestration: missing-file error text returned on ADB
  stdout with exit0, a wrong Wish projection lookup, and a fixture outside the deliberately restricted
  owned-media cache path. The driver now polls actual JSON, queries Wish.title and copies only its
  generated sample into the allowed cache. No production path/signature/authorization check was weakened.
- A first portable check used Xcode's Python without jsonschema; all three import errors are retained
  in `protocol-conformance-environment-error.log`. Running the established QA environment gave17 passes.
- Phase B's original native reconnect timeout and full failing invocation are copied intact to
  `retained-phase-b/`. Its root cause is still **UNKNOWN / NOT REPRODUCED** by the new passing native
  and fault runs. No SyncEngine runtime fix or global timeout increase is claimed.

## Runtime artifacts and remaining validation

All paths below are relative to ignored `qa/results/android-phase-c/`, unless marked candidate.
Device serial, app-scoped Logcat, stores, Keystore wrappers, recordings, original files, screenshots,
APKs and CPU traces stay local. Public reports use only synthetic operation results and hardware model.
The existing84 Android candidates and Apple approved/review states are preserved.

### Final candidate and regression

Candidate `0.2.1-phaseC` / versionCode5, separate Debug ID and original Debug signer.
APK `apps/android/app/build/outputs/apk/debug/app-debug.apk`, **39,064,177 bytes**,
SHA-256 **`a8cfb799cc32658a0415a8cf622665dc43c427604aba38443466f608d0a49cdb`**.
Actual same-signer installation and physical16-case regression passed. Only candidate version,
Debug QA host and test machinery changed; no production business/SyncEngine/schema redesign.
Kotlin53/53 and normal/optimized host safety5/5 each passed again on the final source. Android copy
552 entries/0 errors/0 warnings. Lint completed with0 errors and11 dependency-update warnings
(9 `GradleDependency`,2 `NewerVersionAvailable`); these are not hidden as a warning-free result.

Headless existing QA: Swift138 PASS /0 FAIL /5 explicit SKIP, native Debug build, isolated original
SwiftData migration, legacy Relay, four-native-client C1 and child-process crash recovery PASS.
Portable conformance17 and Relay18 PASS. Mac UI/visual NOT RUN this phase; existing Apple copy
14 warnings, approved baselines and Build5 human-review dispositions remain unchanged.

### Interrupted manual-UI automation

`samsung-lifecycle-1` passed preparation, actual offline cached sealed display, real restart and
persisted once-only inspection. Before history/native SAF interaction completed, the phone's foreground
changed away from Together and the UI hierarchy became unavailable. The fail-closed driver stopped
without operating another application. Overall driver **FAIL (interrupted environment)**; original
save/photo selection/manual WAV playback/background UI steps remain **NOT RUN**, not PASS.
The user was asked whether the phone can be left available; dependent device control is paused.
Dark/font/rotation, large-original/finance benchmarks and the100k corrected full rerun are pending
that availability. Display settings were not changed by these unexecuted mode tests.

### Performance: first100k attempt and reporting defect

`samsung-100k-1` executed100,000 real certified facts (32-write batches,1000 entities,128-entry
inventory/keyset pages) and reached the final output after persistence, digest, snapshot, indexed
lookup and restart-verification assertions. It then failed at diagnostic JSON output in1168.865s
(1169.518s host wall time): protocol canonical JSON correctly rejects fractional timing values.
**Overall FAIL,0 PASS.** Do not reuse that elapsed time as a successful end-to-end benchmark.

The test-only output now uses atomic ordinary diagnostic JSON, with a dedicated physical fractional
format smoke test that passed. Signed-wire canonicalization is unchanged. Phase checkpoints retain
timings before final formatting, and a new100k run keeps its own independent Keystore-wrapped test
identity/public authorization so its Room history is recoverable. The complete same-size rerun is
still required; neither the formatter smoke test nor a smaller workload clears the first failure.

An own-package5-second Simpleperf seed sample captured2625 samples/0 lost. ART stack walking,
CAS, write/fdatasync, BC field multiplication and allocation appear; this short Debug sample does
not prove a single performance root cause. The sampled seeding PSS reached128346KiB; it is not the
whole run's peak. The phone has11350768KiB MemTotal and a256MiB Java heap limit. Full100k business
projection/public-network synchronization and release-mode cold-start distributions are NOT RUN.

### Default Debug workspace cross-check

The default Debug identity and main Room file hashes match their pre-test values; copied current
state has0 operations. WAL/SHM hashes differ. No earlier logical WAL snapshot exists, so their exact
logical equality is **UNKNOWN**, not a byte-identical claim. This workspace was newly created by the
authorized checksum-pinned baseline launch, not a pre-existing user/production installation. Final
test rules select fresh explicit namespaces. No restore, deletion or overwrite is performed.

Twenty final light screenshots plus the separate cached-sealed lifecycle captures stay local
**CANDIDATE / REVIEW REQUIRED**;0 newly approved. They show real test-control accessibility and
synthetic fixture data, not user content. Dark/large-text/landscape and human visual approval remain
open. Original84 Phase B candidates and Apple baselines/review states are preserved.

Pre-commit publication scan PASS:500 tracked files and786 refs/reflog-reachable historical blobs,
0 rule matches. The sealed developer source diff scan `804c73a0-7612-4485-a916-5c130ac2da0f`
reviewed the34-file patch (20 source inventory files plus14 docs/config),0 reportable findings.
Canonical report/coverage/model are retained locally. This is not independent protocol certification.
Native UI automation remains ambient input after tree checks and requires an available foreground;
the interruption is preserved rather than bypassing that prerequisite.

Review-equivalent source commits: `dedeecc` (physical QA/focus), `9797670` (C1/recovery/workloads),
`a675ce3` (evidence/CI/protection). This later documentation appendix does not change executable code.
Final post-commit publication scan, Draft PR and latest-SHA CI are recorded when executed; no
unexecuted step is a completed gate. Public API2 staging/physical cross-network and independent
protocol/security review remain NOT RUN/BLOCKED.

## GitHub main protection follow-up

The user's additional GitHub warning was resolved by configuring and reading back actual `main`
branch protection. No force push/deletion, admins enforced, PR required, both existing quality
checks bound to GitHub Actions app15368, up-to-date branch and conversation resolution required.
There is one write-capable collaborator, so independent approval count is0 rather than an impossible
self-approval requirement. Main SHA did not change; no PR was merged. See
[repository policy](../../security/REPOSITORY_PROTECTION.md).
