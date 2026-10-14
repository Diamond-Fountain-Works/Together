# Together 0.2.1 Build 4 — Final QA and safe upgrade

**NOT READY FOR LOCAL INSTALL.** Release packaging and migration are verified, but the final complete UI run retains one failure and one required image is absent. No Applications install, repository move or production-store reset is authorized by this report.

| Gate | Evidence / boundary |
| --- | --- |
| Build | PASS: Universal Release 0.2.1 Build 4; signature/bundle/DMG verification passed. Release get-task-allow is absent. |
| Unit Tests | 77 PASS / 0 FAIL / 1 SKIP in the complete suite; the skipped existing-store-copy case separately passed, covering 78 unique business test methods. Server 8 PASS; quality tools 6 PASS. |
| UI Tests | FAIL: final complete run 12 PASS / 1 FAIL / 1 SKIP. Our Story is the explicit skip. FinanceSnapshotMatrix fails on a disappearing native input-candidate AX reference after JPY search. USD save/reset and expense reconciliation focused checks passed. |
| Copy QA | WARN: 0 errors, 13 retained warnings after individual review of all 58 originals. Rules unchanged; qa/COPY_REVIEW_BUILD3.md. |
| Visual QA | FAIL / REVIEW REQUIRED: final complete run 67/68 required captures. Missing finance-settings-personal-dark-compact-reduced.png. Four requested shared financial Settings captures are complete native images. No approved baseline overwritten. |
| Migration Safety | PASS: generated populated 0.0.1 store and actual old-store private copy; three store reopens, two actual Debug app launches, byte-identical identity and original-source fingerprints. |
| Network Sync | Local Worker/native WebSocket and public Relay tests; original reconnect plus three extra rounds. Physical dual-Mac/different-Wi-Fi is not simulated or claimed. |
| Release Artifact | [Build 4 Universal DMG](../0.2.1/dist/Together-0.2.1-Build4-Universal.dmg), 5.10 MiB; all packaging checks passed. Ad-hoc signing; Gatekeeper REJECTED; notarization NOT RUN. |
| Remaining Issues | One reproducible SDK/input-candidate UI failure; one missing image; no human-approved baseline; physical dual-Mac acceptance and independent security review unrun. Temporary input-method comparison remains unapproved; no input method was changed. |

## Repaired and retained findings

- Previous automation-mode initialization failure is historical. Today the same Mac's runner entered automation and executed tests without enabling Developer mode or changing system security permissions. The exact cause of the earlier session failure is unproven. Xcode's CoreDevice/CoreSimulator mismatch warnings remain, but they did not prevent native Mac UI execution. Runner target/host, launch flags, private data roots and waits were checked.
- Current input source is Pinyin. Test locale alone does not select a keyboard input source; committed native paste restores the complete prior clipboard and avoids uncommitted Latin-code composition. Tests wait for actual filtering/visible day state before click coordinates. Currency popover search state is owned by its content view; native code search disables autocorrection.
- Real compact fixtures now assert 900pt width. Full native sheets/popovers can extend beyond a compact parent window, so captures use that owned element instead of clipping it through the parent window. Header/list windows remain window screenshots. The previous four incomplete Settings rasterizations are not acceptance evidence.
- A real reconnect failure was observed, preserved, fixed and exercised on both local and public services; see qa/NETWORK_RECONNECT_REVIEW.md. No authentication check, rate limit or timeout was loosened. Business entity/model/schema/clock rules are unchanged.
- Dedicated Git history is intact at ~/.cache/Together/finance-development.git, with no remote; the cache-cleanup loss risk and proposed copy/bundle migration are in qa/GIT_STORAGE_REVIEW.md. Nothing was moved or deleted.

## Upgrade boundary

The populated old-source fixture includes Tasks/Recurring, dated WishGrant/confirmed WishItem, Profile/avatar, received Love Gift/presentation state, signed operations and trusted peer/RelayBinding. New finance data initializes and persists; replayed old operations remain idempotent. Existing identity-file reload occurs before any legacy Keychain read, including when migration is requested again.

The actual local store copy currently contains five original operations, three entity hashes and four local records; no peer/binding is present in that source. Those absent relationships are not claimed to have been tested in the actual copy: paired migration is covered by the populated fixture and real saved-route integration tests. Both real app launches use an isolated Debug-only storage root and suppress network restore, never the live store or live pair.

At initial and final inspection, `/Applications/Together.app` is absent. Its absence predates any install action in this task; no installer action is performed. The existing Application Support store and identity remain present and fingerprint-identical. Rehearsal does not constitute an authorized in-place installation or a test of quarantined Release/Gatekeeper launch.

## UI findings at the final form size

Financial forms now fit 620pt compact content, with scrollable fields and fixed Cancel/Save actions. Existing expense reconciliation/skip/delete actions moved to a fixed supplementary footer after manual native inspection showed they could sit below the scroll viewport. Native action verification confirmed reconciliation updates the original expense and closes without changing the total. A focused XCUITest then passed this same action/closure check.

macOS 27 also intermittently reports an input-candidate AX dialog and removes it before XCTest's default interruption handler resolves it. This failure is retained in the raw logs. The test monitor handles only a dialog that no longer exists; it never grants or clicks a real permission/confirmation. Final acceptance must reflect the actual final rerun outcome, not a prior pass.

## Final artifacts and provenance

- Artifact: `0.2.1/dist/Together-0.2.1-Build4-Universal.dmg`; SHA-256 `19735b41056a03469eed8eb9efe223d1240477dd33415ace7566ee4a0f35e950`.
- Build 3 was superseded after Xcode injected debugger access into its Release signature. Build 4 disables base-entitlement injection in Release; required network/microphone/file-picker entitlements and hardened runtime remain. Signature/DMG mounted-bundle checks passed. No package is installed.
- Full UI result: `/Users/giga_fortress0/Documents/ProjectsLocal/Together/qa/results/ui-20261014-110535.xcresult`; targeted SDK failure and attempted monitor: `qa/results/ui-finance-capture-final.json`. Failed runs remain preserved.
- Current machine-readable report: `qa/results/final-upgrade-preparation.json`. Earlier Build 2/3 documents are historical; they cannot override this result.

Current screenshot inventory and missing-case evidence: [visual/BUILD4_SCREENSHOTS.md](visual/BUILD4_SCREENSHOTS.md). No human baseline is approved. Temporary ABC input-method comparison remains pending the separate user confirmation requested under Computer Use rules; absence of a reply is not authorization.
