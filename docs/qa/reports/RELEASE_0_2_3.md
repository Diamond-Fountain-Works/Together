# Together 0.2.3 — bilingual release QA

2026-10-22. Source branch: `feature/localization-0.2.3`, stacked on the verified
0.2.2 delivery branch. Release candidates use normal application IDs; no App was
installed and no production database, identity or pairing was opened for testing.

## Changes

Settings contains one globe menu on macOS and Android. Its closed state shows
only the icon; clicking opens Chinese/English choices. Navigation contains no
language control. The choice is device-local and survives relaunch. SwiftUI
Observation and Android's StateFlow/configuration context update existing UI
without recreating the database, repository or synchronization session.

The complete resource sets cover 895 Apple product keys, one native microphone
purpose and 297 Android keys in both languages. English gifts keep the intimate
“your guy / your girl” tone; ordinary actions and states are concise. Chinese
labels contain Chinese, with exact brand/currency/file identifiers preserved.
Repeated settings/finance explanations were removed. Required photo-sharing
consent and identity verification remain short and actionable.

Dates and times are formatted using the chosen display locale. Gregorian civil
calendar dates keep their original components and never move a day due to display
language. Change history translates statuses while preserving user-written titles
or notes, including text that happens to equal a status word.

## Executed checks

| Gate | Result |
| --- | --- |
| macOS Xcode Release / verified DMG | PASS; 0.2.3 Build 21, arm64, macOS 14.5+ |
| Android optimized, signed Release | PASS; 0.2.3 code 16, arm64, Android 9+ |
| Swift core | 154 PASS / 0 FAIL / 11 SKIP |
| Native P2P unit/integration | 17 PASS / 0 FAIL / 0 SKIP; local relay-disabled QUIC is separate from public-network acceptance |
| macOS launch-policy unit tests | 4 PASS / 0 FAIL / 0 SKIP |
| Isolated pinned old-store upgrade | 1 PASS / 0 FAIL |
| Kotlin app/protocol/domain | 71 PASS / 0 FAIL / 3 SKIP |
| Protocol conformance | 18 PASS / 0 FAIL |
| Localization gate regression tests | 23 PASS / 0 FAIL |
| Existing copy quality-tool tests | 7 PASS / 0 FAIL |
| Relay typecheck / local tests | PASS / 21 PASS |
| Android Lint | 0 Error / 17 Warning; warnings retained in the report |
| Bilingual resource audit | PASS; 896 Apple keys + 297 Android keys, 0 Error / 0 Warning |
| Existing Apple Copy QA | WARN; 0 Error / 28 Warning; each disposition recorded separately |
| Android Copy QA | PASS; 594 translated values, 0 Error / 0 Warning |
| Repository and recoverable-history data/credential scan | PASS; no private files or secrets found |

The 11 Swift skips require explicit isolated bridge/relay/performance/crash probe
settings. The three Kotlin skips require isolated Relay/Swift bridge settings.
They remain skips. They are not included in pass counts. Physical Samsung,
Android instrumentation execution and new cross-network acceptance are NOT RUN.

## UI and visual evidence

Six distinct macOS UI methods pass using `com.together.app.qa`: globe menu and
language persistence, bilingual light/dark page captures, compact/Reduce Motion,
navigation without permanent Gift UI, real task editor actions and sealed Gift
privacy/one modal. Captures cover Home, Plans, Wishes, all three finance tabs,
Settings, sealed/open Gift Reveal and task editing. The final date assertion
checks actual accessibility text/value in both languages.

An initial UI attempt read a sidebar container's empty label. Its locator was
corrected to the visible child. A legacy compact test still expected the English
word “Pending” in Chinese mode; it now resolves the exact locale-specific label.
Screenshot inspection found native Date Text retaining Chinese formatting in an
English Gift. Display formatting was moved before Text creation, and the sheet
receives the chosen locale explicitly. The first date assertion then read only
AX label; macOS exposes this static text in AX value. The corrected assertion
requires the real timestamp, not an empty string. Original failure logs remain
local alongside successful retries.

Current run manifests are `qa/results/ui-localization-dates.json` and
`qa/results/ui-localization-behavior-final.json`; generated captures stay in
`qa/visual/candidates/`. Only synthetic names, titles, gifts and amounts are used.
No candidate screenshots are committed or uploaded. Visual QA remains
**REVIEW REQUIRED**; no approved baseline is replaced.

The Android resource-switch and Settings-navigation instrumentation tests compile.
No phone/emulator was installed or controlled in this task. Android visual and
physical UI checks are **NOT RUN**.

## Artifact verification

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| Together-0.2.3-Build21-AppleSilicon.dmg | 10,545,152 | `41d8f19ffc37711b9186e942001f4824ebba1b97704864f909a057dc88587d5b` |
| Together-0.2.3-16-arm64.apk | 22,938,328 | `535c5a028c1c160b08e0d3af356383970bb5501e41fa35c07c668ad931f0097a` |

The Mac DMG checksum, mounted-file manifest, app metadata, entitlements and
ad-hoc signature pass. Gatekeeper assessment is **REJECTED**; Developer ID signing
and Apple notarization are **NOT RUN**. The bilingual installation guide gives the
system's manual Open Anyway path.

Android uses the retained release signer
`88d94e362ebbfbead8798ffabe7bf2a86c86a6b63ca5a1fa4d428781e26276a1`.
APK signature, normal package ID, non-debuggable/non-test-only flags, shipped
JNA JNI members, original-file exclusion and 16 KiB native ELF/ZIP alignment pass.
Both compiled Apple `.lproj/UI.strings` sets and native permission purposes are
present. The APK bundles both languages for offline choice.

## Data, networking and release boundaries

No SwiftData/Room schema or signed/protocol encoding changed. Existing keys,
shared-space IDs, pairings, recurrence, daily gift allowance and financial
calculation rules remain in place. Tests use private synthetic stores; production
storage is not a test input. QA derived data and migration build caches now default
to ignored project-local paths instead of `~/.cache/Together`.

This version's scope is bilingual presentation and copy. No Relay was deployed,
no PR merged, and no macOS/Android production installation was replaced.
Independent protocol security review and physical VPN-free Mac/Samsung network
acceptance remain separate open gates. Source safety scanning is not a substitute
for that review.

See [per-warning copy dispositions](LOCALIZATION_COPY_0_2_3.md). Local test logs,
result bundles, exact file hashes and delivery metadata live under
`qa/results/localization-0.2.3/` and remain ignored by Git.
