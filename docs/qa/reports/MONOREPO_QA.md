# Monorepo QA — source migration and release checks

Baseline main: `1cb1a22e7f6c601a38d5044a3accd468d49e4071`. Work branch: `refactor/monorepo-foundation`. Public source migration, no installation or production Worker deployment.

## Verified gates

| Gate | Actual evidence |
| --- | --- |
| Precondition | Build 4 completed before restructuring: original Pinyin UI 14 PASS / 0 FAIL / 1 SKIP; 68 human-approved baseline images; generated/actual copied-store upgrade PASS. |
| Production source | 101 current app/core source/resource and relay runtime/test files byte-identical to original baseline. Initial relocation including existing Swift/UI tests: 114/114 identical. Subsequent changes affect test harness/capture tooling only. |
| Native build | Debug PASS. Universal Release 0.2.1 Build 5 PASS; Bundle ID `com.together.app`, macOS 14 minimum, arm64 + x86_64. |
| Swift business | Full local suite 85 PASS / 0 FAIL / 1 conditional existing-store SKIP; 86 discovered. Includes 8 new portable conformance tests. The actual existing-store case was independently run and passed below. |
| Migration fixture | All 104 pinned old-source files restored identically. Actual legacy-source store generation/upgrade PASS; preserved original signed operations, avatar, tasks, wishes, gifts, presentation state, keys, peer pins and Relay binding; finance adds/reopens successfully. |
| Actual store copy | PASS: owner-only temporary copy, 3 store opens, 2 real Debug process launches; 5 operation hashes / 3 entity hashes / 4 local records retained; production source/key hashes unchanged. Actual source has no saved peer/binding, so those are covered by the generated fixture, not falsely claimed for the live copy. |
| Relay | Typecheck PASS; 8 service runtime tests PASS; two native local WebSocket scenarios PASS within Swift suite. This refactor did not deploy or modify production Worker. |
| Portable tools | Python conformance 9 PASS; QA tools 7 PASS (including per-run image tamper/path rejection); repository-safety tools 3 PASS. |
| Copy | WARN: 0 Error / 13 individually reviewed Warning. No String Catalog/product wording changes; duplicate-context and independent security-review warnings remain visible. |
| GitHub CI | Both macOS and portable jobs PASS on [code checkpoint e80191f](https://github.com/Diamond-Fountain-Works/Together/actions/runs/38574041936). Hosted UI/visual explicitly NOT RUN; no deployment/production credentials. |

First post-move full UI run: **14 PASS / 0 FAIL / 1 intentional absent-Our-Story SKIP** (`ui-20261014-145043.xcresult`). Raw comparison was 16 PASS / 49 REVIEW REQUIRED / 3 FAIL. A focused retry was interrupted by an AX helper connection loss after screenshot capture, not a monetary/domain failure. Its failed result is retained. Final rerun and focused resting-state results are recorded below after execution.

## Final native UI and visual result

Full rerun `ui-20261014-214009.xcresult`: **15 PASS / 0 FAIL / 1 intentional SKIP** (16 cases, including the new transient-surface regression). All **68/68 required captures** plus 3 diagnostics were exported to immutable run directory `qa/visual/candidates/20261014-214009/` with per-file SHA-256. Raw baseline comparison: **18 PASS / 50 minor REVIEW REQUIRED / 0 FAIL**. No comparison threshold was changed. The final pointer-neutral capture helper was separately compiled/exercised in `ui-20261014-215214.xcresult`: **1 PASS / 0 FAIL / 0 SKIP**, with four diagnostic surfaces and no major visual failure.

The exact full-run 68-image set is frozen locally in `qa/results/build5-visual-review-20261014-214009/`; manifest SHA-256 **0d1e94c5f098bf10bff6dae0867e79de8de6acd123e962d819dbbc6570e964a1**. The review lists each changed ratio, reference and image hash. It is pending explicit human approval; images remain local. Build 4 approved manifest/hash and pixels remain intact. The PR stays Draft until this review is resolved. User approval of images does not authorize installation/deployment.

## Visual review boundary

No approved baseline or approval hash has been changed. The initial raw FAIL cases were the light/dark Currency Picker and normal-motion light Gift Reveal. Exact native element/window frames match Build 4. Window corners and popover material include the desktop/behind-window pixels; changing the desktop behind them affects raw comparison. Gift Reveal is sensitive to spring timing and the pointer remaining over a newly expanded photo, exposing its valid hover action. Reduced-motion opened captures matched the approved references exactly in the initial full run.

Test-only changes wait for animation, move the pointer to a neutral owned area for the resting-state shot, read AX frame metadata before capturing, and bind each screenshot to a unique run directory/SHA-256. Major pixel differences remain FAIL and minor ones REVIEW REQUIRED; no threshold/rule suppression or automatic baseline replacement was used. Actual new image hashes require human review before any replacement baseline. Until that review resolves the remaining differences, **do not merge or claim final Visual QA PASS**.

## Release artifact

Local-only `apps/apple/macOS/dist/Together-0.2.1-Build5-Universal.dmg`, 5,353,984 bytes; SHA-256 **ce667f8ea81b0ce1171570877a9bed433c9e44ffa7e7608e89cd2a0d8332127c**. DMG checksum, read-only mount, mounted bundle/file hashes, signatures, Universal architectures, version/Bundle ID, installation shortcut and instructions PASS. Release has network client/server, selected-file and microphone entitlements; `get-task-allow` absent. Ad-hoc signing, Gatekeeper REJECTED, notarization NOT RUN. It was not installed or uploaded as a Release.

`/Applications/Together.app` was absent at the pre-migration check and remains absent; no existing installation was removed/replaced. Original Application Support, key files and untracked local QA documents/images remain intact. Source publication scan examines tracked files plus all ref/reflog-reachable objects; no real store/media/key/credential was found/uploaded. The scan is not a claim to detect every unlabeled secret or an independent cryptographic review.

## Outstanding release limits

- Formal invitation requirement is one-use **8 hours**; unchanged legacy implementation is **10 minutes**. [Issue #1](https://github.com/Diamond-Fountain-Works/Together/issues/1) requires a separate coordinated network PR, test and later authorized deployment.
- Physical two-Mac/different-Wi-Fi acceptance NOT RUN; hosted/local tests do not clear the other Mac's prior workers.dev reachability issue.
- Independent application-protocol review, Developer ID/notarization, system-notification hardware acceptance and future Android/iOS/watchOS apps remain outside this completed source/build work.
- Visual differences require review; a Draft PR may carry the work without claiming it is merge-ready.
