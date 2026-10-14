# Build 4 — temporary input-source comparison

The user authorized a temporary ABC switch on 2026-10-14. Current source/settings were recorded before any change; no input source was removed or reconfigured. UI switching used the Mac’s existing Command-Space shortcut through Computer Use, not preference writes or TIS selection code.

| Check | Actual result | Evidence |
| --- | --- | --- |
| Before | Pinyin `com.apple.inputmethod.SCIM.ITABC`; ABC already enabled | `qa/results/input-method/before.json` |
| ABC, original harness | 1 PASS / 0 FAIL; 28 native finance captures including the missing dark personal cycle | `qa/results/ui-abc-finance-test.log`; `ui-abc-finance.json` |
| Restore original Pinyin | PASS: active input mode/layout, configured keyboard sources, hotkeys and recorded other preferences match | `qa/results/input-method/restored.json`; `final-verification.json` |
| Pinyin, original harness | 0 PASS / 1 FAIL; same disappearing native AX dialog at JPY click | `qa/results/ui-pinyin-finance-test.log`; `ui-pinyin-finance.json` |
| Pinyin, focused corrected harness | 1 PASS / 0 FAIL; light Latin JPY and dark Chinese 日元 searches select JPY and close correctly | `qa/results/ui-pinyin-wait-fix-test.log`; `ui-pinyin-wait-fix.json` |
| Complete suite after correction | PASS: 14 passed / 0 failed / 1 explicit Our Story skip; all 68 required captures present | `qa/results/ui-test.log`; `ui.json` |

## Failure and correction

The original Pinyin run identified an 84×77pt native dialog next to the search field, then XCTest’s default interruption handler retained a reference after the dialog vanished. It failed with `Failed to get matching snapshot: No matches found for Descendant with identity binding to AX element`. The original ABC comparison passed. This links the failure to input UI under Pinyin; it does not claim an independent diagnosis of macOS internals.

The corrected test waits on the live `app.dialogs` query until count is zero, then resolves the currency row again by stable identifier. It fails for a persistent dialog instead of granting permissions. The ineffective custom monitor was removed; original JPY selection, real data-bound currency value and sheet-closure assertions remain. A dedicated current-input-method case exercises both light/dark and Latin/Chinese search text. No production control, locale, supported input method or business rule changed.

## Restoration detail

The first raw-array equality check failed because macOS dynamically registered `com.apple.inputmethod.EmojiFunctionRowItem` as a **Non Keyboard Input Method**. This discrepancy is retained in the restoration record; it was not hidden or removed. A second check compared active keyboard identity and the complete configured keyboard/input-method list, hotkeys and other preferences; all matched the original Pinyin setup. No preference reset, input-source deletion or Chinese IME reconfiguration was performed. History/update-time changes from switching are expected and recorded.

If automatic restoration ever fails: open the menu-bar input-source selector and choose 拼音. On this Mac, the recorded input-source shortcut is Command-Space; verify 拼音 in the menu afterward. Do not delete/add input sources to recover. At present restoration is verified, so no manual recovery is needed.

## Safety

All app launches use isolated DEBUG fixture roots. No Applications replacement, installation, production identity/pairing change, Keychain access or production database write is part of this test. Full failed logs and result bundles are retained. Tests/docs are the only source changes; the Build 4 release app/DMG content is unchanged.
