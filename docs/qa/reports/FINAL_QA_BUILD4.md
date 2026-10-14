# Together 0.2.1 Build 4 — Final QA and safe upgrade

**READY FOR LOCAL INSTALL** as a controlled local candidate. The user explicitly approved all 68 frozen image hashes; current comparisons passed 68/68. Pinyin UI, isolated migration/restart and package integrity checks passed. This is not notarized public distribution or physical cross-Wi-Fi acceptance. No Applications install/replacement is authorized or performed.

| Gate | Actual result / boundary |
| --- | --- |
| Build | PASS: native Debug test build and unchanged Universal Release 0.2.1 Build 4. Bundle/signature/entitlements and DMG rechecked; no Release debugger access. |
| Unit Tests | Existing complete suite: 77 PASS / 0 FAIL / 1 SKIP; skipped existing-copy case separately passed. Follow-up old-source migration 1 PASS; existing-copy/restart case 1 PASS. These reruns do not inflate unique-case counts. Server 8 PASS; quality tools 6 PASS. |
| UI Tests | **14 PASS / 0 FAIL / 1 SKIP** in one complete original-Pinyin run, including the original 14 methods and an added focused Latin/Chinese currency-search regression. Our Story is the explicit unimplemented skip. |
| Copy QA | **WARN: 0 errors / 13 warnings**, all individually reviewed; 12 legitimate independent translation contexts and 1 independently unreviewed security disclosure. Product strings and audit rules unchanged. |
| Visual QA | **PASS: 68/68 required cases**, plus 3 diagnostic images. Missing dark personal-cycle capture recovered; four shared Settings captures are complete native sheets. All 68 frozen hashes were explicitly approved by the user and current comparisons passed; no baseline was self-approved. |
| Migration Safety | PASS: original 0.0.1 generated store and actual production-store private copy. Three store reopens and two real Debug app processes use the private copy; original operations/entities/local records and identity preserved; production fingerprints unchanged. |
| Network Sync | Previously verified unchanged local Worker/native WebSocket and public Relay tests with repeated reconnects remain PASS. Physical two-Mac/different-Wi-Fi test is **NOT RUN**. No offline relay delivery claim. |
| Release Artifact | Build 4 Universal DMG, 5.10 MiB; SHA-256 unchanged. Ad-hoc signing; Gatekeeper **REJECTED**; notarization **NOT RUN**. This report does not make it a notarized public distribution. |
| Remaining Issues | One independent security/disclosure review; real cross-Wi-Fi dual-Mac acceptance; notarization/Developer ID. Live external Git remains in `.cache`, but verified durable recovery bundles are now available. |

## Fixed / passed in this follow-up

- Recorded current Pinyin, enabled keyboard/input methods and shortcut settings before switching through existing native UI. ABC original harness passed; restored Pinyin original harness reproduced the same disappearing 84×77pt native AX dialog failure at JPY selection. Full failed logs/result bundles were retained.
- Fixed only tests: wait for the live `app.dialogs` query to reach zero, then resolve a fresh currency identifier; remove the ineffective stale-dialog monitor. A persistent dialog fails rather than receiving permission. JPY selection, true currency value and closure assertions remain. A dedicated light/dark case checks JPY and 日元 under the current input source. No runtime input restriction or product/business/sync change.
- Focused Pinyin case and complete 15-method Pinyin suite passed. Original keyboard/input-method list, active Pinyin/layout and shortcut settings were verified after the full run. A system-registered Non Keyboard EmojiFunctionRowItem difference is explicitly retained in the restoration record; no IME was deleted/reconfigured. See [INPUT_METHOD_REVIEW_BUILD4.md](INPUT_METHOD_REVIEW_BUILD4.md).
- A follow-up script failed before opening data because system Python 3.9 lacks `hashlib.file_digest`. Corrected the QA script to bounded streaming SHA-256 and ensured fingerprint failures produce a fresh FAIL report. Re-running with Python 3.9 passed actual-copy migration and two isolated app launches. The initial traceback is preserved in `qa/results/existing-store-upgrade-python-compat-error.log`.
- Generated old-source migration again passed with a fresh private fixture. Actual local-copy rehearsal preserved 5 operations, 3 original entity hashes and 4 local records; no peer/binding exists in that actual source. Paired migration is covered by the separate populated old-code fixture and saved-route integration checks, not falsely claimed for absent actual records.
- `/Applications/Together.app` remains absent at inspection; no installer/removal action occurred. Existing production Application Support database and identity fingerprints match before/after this follow-up. No Keychain access, identity rotation, pairing replacement or production-store write.
- Durable all-refs Git backup, bundle verification, temporary mirror restore, ref equality and `fsck --full` passed. Live history directory was neither moved nor removed. See [GIT_STORAGE_REVIEW.md](GIT_STORAGE_REVIEW.md).

## Changed files

- `0.2.1/Tests/TogetherUITests/TogetherUITests.swift`: input-dialog wait, fresh row resolution and focused current-input-source regression.
- `scripts/run_existing_store_upgrade.py`: Python-compatible bounded hash and truthful failure reporting.
- `README.md`, `TEST_PLAN.md`, `UI_COPY.md`, `CHANGELOG.md`: actual follow-up rules/evidence; no runtime catalog change.
- `qa/INPUT_METHOD_REVIEW_BUILD4.md`, `qa/COPY_REVIEW_BUILD4.md`, `qa/copy-build4-followup.json`, `qa/GIT_STORAGE_REVIEW.md`, this report and frozen visual inventory/gallery: diagnosis, per-warning decisions, backup evidence and human-review artifacts.
- No `0.2.1/Sources`, configuration, release scripts, physical SwiftData schema, original `0.0.1`, installed app or production user data changed in this follow-up. Existing Build 4 binary/DMG are byte-identical; no new marketing/build identity is required for test/docs-only changes.

## Evidence and human approval

- Complete UI result: `qa/results/ui-20261014-125814.xcresult`; full log: `qa/results/ui-test.log`.
- Original comparison logs: `qa/results/ui-abc-finance-test.log` (PASS) and `ui-pinyin-finance-test.log` (FAIL); corrected focused log: `ui-pinyin-wait-fix-test.log` (PASS).
- [Frozen 68-image gallery and hashes](../../../qa/visual/reviews/build4-final-20261014-1309/REVIEW.md); manifest SHA-256 `9060d1deb2dca8c16b2d5ffbf435ea343f1b20a4b3107b67b81f63bf352c6544`. Explicit user approval was received and recorded in `APPROVAL.json`; all 68 hashes were verified before entering approved/. This approval does not authorize installation.
- [All 13 copy decisions](COPY_REVIEW_BUILD4.md). No blanket suppression or manufactured Copy PASS.
- [Build 4 Universal DMG](../../../0.2.1/dist/Together-0.2.1-Build4-Universal.dmg); SHA-256 `19735b41056a03469eed8eb9efe223d1240477dd33415ace7566ee4a0f35e950`.
- Machine-readable report: `qa/results/final-upgrade-preparation.json`. Earlier failed runs remain historical evidence, not current acceptance results. SDK CoreDevice/CoreSimulator mismatch warnings remain diagnostic; they did not block this native Mac suite and iOS testing is outside scope.
