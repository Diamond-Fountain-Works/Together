# Historical finance visual review — 0.2.1 Build 2

Superseded by [BUILD3_SCREENSHOTS.md](BUILD3_SCREENSHOTS.md). The limitations below describe the previous run, not final Build 3 evidence.

Candidates are not approved baselines. No human-approved image was overwritten. The manifest remains empty until explicit image/hash review.

## Actual evidence

- Native XCUITest target compiles, but macOS fails to initialize automation mode before any test case. Fourteen UI tests are NOT RUN, including the new finance cases; build is reported separately.
- Computer Use inspected the isolated Debug app, its real financial data and accessibility controls. Three tabs and one primary create control were present; USD switching cleared the previous amount; a typed USD expense with actual CNY saved and closed the sheet. These are limited manual checks, not a full UI suite.
- `scripts/capture_finance_views.py` creates 18 isolated light/dark, empty/populated, offline and compact/reduced captures (14 complete financial detail images; four settings sheet images have incomplete transparent backing and are not accepted as baseline evidence) from actual SwiftUI/AppKit content. Native layer-backed sidebar/toolbar cannot be reliably rasterized by AppKit cacheDisplay; they are explicitly excluded from detail captures, and settings captures use the presented sheet. These are rendering evidence, not full-window XCUITest screenshots. Metadata and hashes are in `qa/results/finance-content-capture.json`.

## Locations for review

- Expense summary: four amounts, role/name wrapping, aligned numeric baselines in the 900-point window.
- Financial header: three tabs fit without adding another navigation layer; settings/create remain native toolbar actions checked manually.
- Reminders: one collapsed count row preserves ledger visibility; expanded cards show genuine forecast/reconciliation actions. The header is absent with no rules.
- Reserves: separate book/reconciled/pending numbers and explicit non-bank guidance. Empty state has no invented opening record.
- Settings: day wheel, independent shared/personal scope, opt-in notification toggle and actual safe card metadata. Footer remains outside scroll content.
- Dark mode: semantic text/negative colors and rose controls; ordinary surfaces have no continuous gradients or looping motion.

No visual PASS is claimed without approved baselines. Review remains required; task CRUD, reminders and settings need the blocked XCUITest suite or further manual checks. Historical Our Story screenshots are absent because the feature is not implemented.

Final manual check: native Settings text/controls rendered correctly, switching to personal cycle moved the wheel to day 15, and Cancel closed the sheet. Keyboard/trackpad behavior still needs the full blocked UI suite; it is not marked passed.
