# iPhone client — 0.2.4 Build26 QA

Date: 2026-10-27. Branch `feature/iphone-client`, based on verified
`bf3e0f0df9b0800b74049ba3f4ae6ed210094b76` (Draft PR #15).
This is source/build delivery, not an installable iOS release or runtime approval.

## Implemented scope

- Native SwiftUI phone drawer with the Android destinations: Home, Plans, Wishes,
  Our Finances, Connection and Settings. Regular iPads use a split layout; large
  iPhones in landscape retain the phone drawer. No fake Story or Gift destination.
- One real ApplicationModel/core, editor/modal queue and signed business log.
  Pending/Completed and the three finance tabs retain their existing facts/rules.
- Compact/accessibility form reflow, native currency/day wheels, keyboard-aware
  sheets, reachable actions, 44pt phone controls and system text scaling.
- Settings globe, Photos/Files source selection, original selected-file copying,
  user-initiated original export and manual audio. Picker dismissal/stale callbacks
  are scoped to their session. Library edits may already be part of its selected
  representation; no application UIImage re-encoding is used.
- Shared history no longer imposes desktop620pt width on a phone. Unopened
  received Gift history uses an unopened marker instead of private message text.
  Identified desktop spacing/typography changes were restored in source; no
  desktop pixel-parity or new visual approval is inferred.

## Support and build boundary

The authoritative policy remains `platform-support.json`: iOS/iPadOS15, ARM64,
phone/tablet families1/2. No optional camera, modem or biometric capability is
required. Xcode inserts only the inherent arm64 requirement. This supports the
first iPhone SE/6s hardware generation on iOS15 and subsequent compatible models
as an eligibility target, **not tested hardware coverage**. Older32-bit phones
are not targets. iPad portrait, upside-down and both landscapes and iPhone
portrait/both landscapes remain enabled; full-screen-only is not required.
[Apple's iOS15 announcement](https://www.apple.com/uk/newsroom/2021/09/ios-15-is-available-today/)
confirms the iPhone6s-and-later baseline.

Host: macOS27.0.1; Xcode27.1. Native dependencies were built from the unchanged
pinned Rust source/lock for macOS and iOS device slices. No simulator runtime was
installed or launched by this task. A device-list query emitted CoreDevice helper
initialization/version diagnostics; no Together installation command was used.
User explicitly deferred connecting an iPhone and had already deferred simulator
acceptance. Production Apps, stores, keys, pairings and Relay are untouched.

## Executed checks

| Check | Actual result |
| --- | --- |
| iOS normal unsigned Release and separate fail-closed QA Debug | PASS; final Build26 receipts retained locally |
| Actual iOS bundle/Mach-O/resources/eligibility gate | 24/24 PASS; exact compiled translations compared to source |
| Project/eligibility/negative stale-resource regressions | 12/12 PASS |
| Core/business/synthetic migration and local Relay | 182 PASS /0 FAIL /6 opt-in SKIP;188 discovered |
| Legacy0.0.1 source-created data upgrade | PASS; isolated fixture, identity/facts retained |
| Existing four-client local Relay, signed ACK/media/revoke | PASS; synthetic loopback only |
| Crash recovery | PASS; synthetic process/store |
| P2P adapter | 17/17 PASS; local relay-disabled QUIC, not public iPhone networking |
| Relay tests/typecheck | 21/21 PASS; local Worker |
| Protocol conformance | 18/18 PASS |
| SDK/native-binary parser regressions | 10/10 PASS |
| Copy | WARN:0 errors/28 inherited context/security warnings; no rule suppressed |
| Localization | PASS;904 Apple catalog keys,298 Android keys;0 errors/0 warnings |
| Security scan | PASS; source/history scan receipt; independent protocol review still open |
| Simulator/physical iPhone/iPad/Photos/VoiceOver/UI screenshots | NOT RUN; user deferred |
| iPhone↔Mac/Android physical/public independent-network sync | NOT RUN |
| Signing, provisioning, installable IPA/TestFlight | NOT RUN |
| Visual baseline approval | NOT RUN; existing Mac/Android baseline state unchanged |

`./scripts/qa.sh --skip-ui` exits2 because Copy is WARN and UI/visual/security
review gates remain open. It does not relabel those checks PASS. Final shared UI
edits also receive incremental Mac/iOS builds. Current CI status belongs to the
latest PR commit/Checks, not a historical green run.

## Failure retained and fixed

An initial localization run rejected English brand words in new Chinese release
copy. The title became 手机和平板 with a refreshed exact review hash; no lint
exception was added. An initial eligibility gate rejected Xcode's arm64 metadata;
it now permits only that inherent architecture and retains negative tests for
optional hardware restrictions. Stale compiled translations now fail the artifact
gate even when key sets match.

A full suite exposed an inherited storage failure:179 PASS/1 FAIL/6 SKIP in
`migrationAndDatabaseReopenRetainTasksWishesAndPeer`. Isolated repetitions also
failed. A disposable diagnostic source copy identified SQLiteBUSY5 at
`BEGIN; PRAGMA schema_version`, before backup. CoreData WAL teardown can briefly
hold the just-released store. The fix applies the existing250ms budget, capped by
maximumDuration, to that first readonly read, then resets its busy handler before
the existing backup retry budget. READONLY/NOFOLLOW, private metadata snapshots,
source DB/WAL byte assertions and future-store rejection remain unchanged.

New real exclusive-lock fixtures prove transient recovery and bounded permanent
rejection without source byte changes. The pre-fix negative control fails as
expected; after correction, focused modern/legacy/lock tests17/17 and the exact
identity-reopen test100 repetitions pass. Final full suite182/0/6 passes. No schema,
SignedOperation or business merge changes are part of the fix.

## Deliverable and evidence

Local only: `apps/apple/iOS/dist/Together-0.2.4-Build26-iOS-unsigned.app.zip`
and its SHA-256 receipt:11,298,973 bytes,
`20e879c1898ac91ba94fc7ad1f689ffdb2c201c5538005dfda2ea04e9b61b842`.
This is an unsigned `.app` archive for inspection or
re-signing, **not an installable IPA**. It contains no test user/database/media.
Android code17 and published release packages are unchanged.

Minimal evidence is retained in `qa/results/iphone-client-20261027/`:
`ios26-build-summary.json`, `ios26-artifact.json`, generic build logs,
`storage-busy-fix-receipt.json`, original failed/negative-control logs,
`full-qa-final26.log`, core/Relay/copy/localization/security results and the final
cleanup inventory/receipt. Disposable build trees, diagnostic source copies,
package caches, old unpublished Build25 archive and test runtimes are cleaned
only after the final named archive and evidence have been retained and verified.
Raw logs, archives and private device information are not uploaded to Public GitHub.

The PR stays Draft. It does not authorize production installation, deployment,
merge, new visual approval or claims of independent security review.
