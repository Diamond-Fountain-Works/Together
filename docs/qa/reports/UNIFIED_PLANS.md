# Unified Plans filters — 2026-10-19

User correction applies to **both macOS and Android**: merge Upcoming into
Pending. Plans now exposes exactly Pending / Completed. Future, overdue and
undated unfinished tasks share one due-date ordered list, undated last. The
existing editor, completion commands, recurrence rules, tombstones, storage and
sync messages remain unchanged. Future recurrence availability still prevents
premature completion. Home's dated summary links to Pending, not another filter.

Mac enum/source and Android segmented controls no longer expose Upcoming. Old
Android saved Activity state normalizes into Pending. The historical Mac
`upcoming` screenshot fixture name maps to Pending; new capture matrices omit
that duplicate case, without deleting old approved baselines. No static wording
was invented or user text rewritten.

## Verification

- macOS native XCUITest: shared editor / Home routing and compact Reduce Motion
  passed in the first run. Shared editor/routing plus dark compact Pending /
  Completed passed in the final run: **three unique cases, four executions, zero
  failures/skips**. Only the verified dedicated QA Host was launched.
- Android protocol/domain: **53 passed / 0 failed / 3 skipped**. The added query
  case checks overdue/future/undated/scheduled inclusion, completed/deleted
  exclusion and deterministic date ordering. Existing recurrence rules are used.
- Android build/lint: PASS. Physical Samsung light/dark final combined run:
  **2 passed / 0 failed / 0 skipped**, 4.301 s. The first combined attempt passed
  light but stalled during dark and was terminated; its cause remains UNKNOWN.
  Added stage diagnostics and bounded teardown. Dark alone then passed (2.089 s),
  and the full two-case retry passed. Do not call the original runner stall a
  proven UI/root-cause fix. All original logs are retained locally.
- Copy: Android **PASS**, 578 entries / 0 errors / 0 warnings. Apple **WARN**,
  0 errors / 14 established warnings. No rule suppression or baseline approval.
- Visual: actual light/dark screenshots in ignored candidates; **REVIEW REQUIRED**,
  not human-approved. Inspect native buttons, full list bounds and due-date rows.

## Local upgrade

Universal macOS 0.2.1 Build 13 was packaged, signed/DMG verified and installed at
the user-authorized `/Applications/Together.app`, without launching it. The source
and installed bundle manifests match; production data-file hashes did not change.
The previous Build 11 app remains in a private recoverable backup. Signature is
ad-hoc; Gatekeeper rejects it and notarization remains NOT RUN.

Samsung Debug code 8 (`0.2.1-phaseC-plans`) replaced code 7 using `adb install -r`
after signer comparison and a private data backup. No uninstall, data clear,
network setting change or USB reverse rule. Local artifact/data checks are in
`qa/results/plans-android-install.json`, excluded from public source.

Read-only before/after archive comparison: 534 existing Android app files are
byte-identical, including databases and identity material. One existing file,
`shared_prefs/android.app.ActivityThread.IDS.xml`, changed its sole integer
`IDSCount` value after app/test launches. Its precise OS purpose was not verified;
it is recorded separately, not hidden behind an "all files unchanged" claim.
No existing file was deleted. New synthetic QA namespaces/screenshots are expected.

This UI change does not activate the separate P2P development package or deploy
a Worker. Production network limitations and independent security-review gates
remain open.
