# Local visual review

`make visual-review` generates `qa/results/build5-visual-review-20261014-214009/browser/index.html` from the frozen Build 5 matrix and the approved Build 4 hashes. Open the generated HTML locally. Pillow is supplied by the existing `requirements-qa.txt` QA environment. No application build or production data access is needed.

The 68 source screenshots, their generated difference masks, analysis JSON, browser feedback and Playwright captures stay local. Generated output belongs under ignored `qa/results/`; browser verification belongs under ignored `output/playwright/`. Do not publish new screenshots or feedback without a separate provenance/privacy check. Some native popover captures contain background window pixels.

## Review controls

- Filter by automatic result, page name, screenshot ID or evidence classification. The initial filter shows REVIEW REQUIRED.
- Compare Build 4 on the left and Build 5 on the right, or use a draggable wipe / opacity overlay. Zoom or view original pixels; paired scrolling stays synchronized.
- Difference outlines identify the strong-difference bounding box and eight busiest 128 px tiles. The optional mask displays max RGB >16 pixels. These are diagnostic overlays; source PNGs and existing comparison thresholds are unchanged.
- Read the original native XCTest element/window Frame attachment and image hashes under each screenshot. An optional later pointer-neutral run is auxiliary evidence, never a replacement for the frozen candidate.
- Enter ordinary-language feedback for an ID such as `S001`. Record whether a fix is needed and the final human opinion. Export JSON before switching browsers, relocating the HTML or clearing browser storage; `file://` persistence varies by browser. Import validates the frozen manifest and each image hash.

Feedback is stored in the browser, keyed by the frozen manifest hash. Exported feedback is not an automatic baseline approval command. AI/browser tests must never select approval on behalf of the user. Applying approval requires the user's explicit recognition of the reviewed hashes; PR merge requires a separate explicit authorization.

## Interpreting evidence

Pixel PASS means zero pixels exceed the existing max RGB >16 condition. REVIEW REQUIRED and FAIL retain the existing 2% failure boundary. All 68 Build 5 images initially have zero human approvals, including automatic PASS images. Do not lower thresholds, mask backgrounds out of comparison, or replace approved images to obtain a pass.

The classifier separates identical native Frames with differences confined to a measured outer band from interior differences. This can support a window edge/background hypothesis, but cannot establish overall readability, acceptable layout, unobstructed buttons or approval. Ordinary-motion opened gifts have interior animation/hover differences; later pointer-neutral evidence is linked explicitly. Missing metadata and unexplained changes remain manual review.

Our Story and Time Capsule are not implemented and have no fabricated captures. Existing 13 Copy QA warnings remain documented in [Build 4 copy review](reports/COPY_REVIEW_BUILD4.md); this review tool does not waive them.

## Stage gates

1. Generate, verify input hashes, test reviewer controls and open the local review for the user.
2. Convert explicit user feedback into scoped UI repairs; increment the product build if application code changes, rebuild, rerun affected UI checks and capture a fresh immutable matrix.
3. After human visual acceptance, run final build/unit/UI/relay/protocol/migration/security/CI checks. Preserve the migration backup, production identities and installed application.
4. Keep PR #2 Draft until visual acceptance. Ready for Review is not permission to merge. Present final evidence and request one explicit merge approval.

The reviewer generator safety tests run in the portable CI job and local QA runner. They use small synthetic images, test hash/matrix tamper rejection, safe output boundaries, inline metadata escaping, Frame provenance and the separation of pixel evidence from human approval.
