# Together UI copy contract

## Source and categories

Formal static product copy lives in `packages/together-core-swift/Sources/TogetherCore/Resources/UI.xcstrings`, with review metadata in `qa/ui_copy_review.json`. Swift code references stable keys via `Copy.text`; never add a visible literal without adding its catalog entry and review record. ReleaseNotes structured copy is also scanned. User-authored tasks, wishes, gifts, nicknames and private memories are never audit inputs.

Native permission copy uses `apps/apple/macOS/Sources/TogetherApp/Resources/InfoPlist.xcstrings` and the same review index. The generated base Info.plist keeps the matching fallback; changing it requires changing the catalog and review too.

Every entry has exactly one category: Navigation, Action, Status, Guidance, Empty State, Error or Emotional. Static errors include a useful cause/recovery when possible. Do not print user text or complete invitation codes in diagnostic logs.

## Budgets

Chinese ordinary actions: 8 characters; page titles: 14; ordinary card guidance: one sentence, preferably at most 30. Empty states: one prompt and a useful action. Status feedback is short, accurate and literal. English menus should be short and desktop-native. Over-budget copy is a Warning requiring a named review reason; never truncate semantic copy automatically. Existing long privacy/error text is tracked for review, not silently deleted.

Forbidden copy produces Error: Lorem Ipsum, product placeholder/sample data, fictional-data explanations, invented user records/counts, unimplemented feature promotions, emotional filler on ordinary task/Home/settings pages, and unregistered newly visible copy. Subjective length, repeated phrasing and excess emoji produce Warning for a human to assess.

## Approved scope

The user-specified Love Gift/Gift Reveal titles, relationship-label branches, “Open Your Gift ♡”, “收到啦 ❤️” and conditional reply copy are approved Emotional entries. They resolve the actual verified sender Profile; unknown uses TA, pure attachments use 小礼物. Role labels never grant permissions. Initial Setup welcome is functional onboarding, not permission to add welcome banners elsewhere.

Send/history entry labels and Save Photo are explicitly requested actions. Ordinary pages use factual headings/status only. No Love Gift card or sidebar page. Do not claim Delivered from local submission or a relay socket; Synced requires the remote durable/media acknowledgement. Realtime relay does not imply offline delivery.

The latest navigation correction uses Plans / Wishes as vertically stacked left sidebar entries. Plans has only Pending / Completed on both platforms; the former Upcoming tab is merged into Pending. Upcoming is retained only as a factual Home summary linking to Pending, not another workspace filter. New Task / Add Wishes remain functional actions. `plans.*` entries cover factual empty/search states and real dated grant quantities. Task Pending keeps a distinct translation context from media Pending. Identity migration uses `identity.*` functional recovery copy: keys are preserved, migration is explicit and failures do not advertise a successful rebind. No romantic filler is added.

## Review and changes

Catalog import labels existing copy as legacy inventory; policy exceptions and long entries retain a review reason. New unreviewed keys fail the audit. Review metadata must identify category, context, review state, reason and the SHA-256 of the exact reviewed text. Changing the value under an existing key without updating its review fails; keeping an old key does not authorize new wording. Setting approved is not a substitute for user approval where the change is important. Candidate visual images do not approve copy.

Run `make copy-qa` (or `python3 scripts/audit_ui_copy.py --json qa/results/copy.json`). The report lists path, key, issue type, severity and suggested action. Copy audit, business tests and visual review are separate gates. Fixture strings are deliberately excluded by path, not by broadly suppressing words found in live product code.

## Our Finances copy

The `finance.*` catalog entries are functional names, actions, filters, true ledger states, reminder prompts, audit formats and recoverable errors from the approved 0.2.1 scope. ISO 4217 currency names/precision are bundled from SIX List One (2026-09-17); eight common names are localized, others retain official names. No invented amounts or emotional finance copy. `待核对` is provisional bookkeeping; `已核对` is user reconciliation, never bank confirmation. Original/CNY/rate values, category names and actor names are user or derived data and remain outside static-copy lint. Dynamic enum prefixes require concrete catalog coverage tests; a prefix is not an invented visible entry. Existing long-copy warnings remain for human review.

## Build 3 final review

Every original warning is recorded in [qa/COPY_REVIEW_BUILD3.md](../qa/reports/COPY_REVIEW_BUILD3.md) and its machine-readable companion. Twelve functional descriptions were shortened without changing business semantics. Equivalent buttons/navigation labels now reuse one catalog key; unused current-version inventory keys were removed, while the original 0.0.1 catalog was preserved. No audit rule or script was disabled.

The remaining 13 warnings stay visible: 12 independent translation contexts (including task/media Pending, currency codes VED/VES and financial change-history phrases), plus the security-boundary disclosure that still requires independent review. This is WARN, not a manufactured PASS. There are no outstanding copy-budget errors or newly unregistered product strings.

## Build 4 warning follow-up

[qa/COPY_REVIEW_BUILD4.md](../qa/reports/COPY_REVIEW_BUILD4.md) checks all 13 remaining warnings against actual uses. Twelve equal-text entries have distinct task/media, setup/advisor, ISO currency, bill/audio, filter, change-history or relationship/amount contexts. No unreviewed wording or redundant product paragraph was found in these 13. Keep the warnings visible; do not disable duplicate detection or add a batch exception. The remaining privacy disclosure has matching technical evidence but independent security review is still pending. No catalog text changed, and Copy QA remains WARN.

## Protocol 4 change review

The `sync.*` additions name actual domains, device origins, projected operations and local review states. `已同步 %@ 项变更` counts persisted remote operations; it does not imply all devices received them or a person approved them. Gift review shows only creation/deletion metadata, keeping sealed text/media private until the existing reveal flow opens them. No hashes, Lamport clocks or internal field names appear in this UI.

## Device management copy review

`device.*` names requested native enrollment/migration actions, explicit identity comparison, truthful device/history states and recovery errors. Public exchange filenames are user-visible save defaults, not network credentials. All exact values are in the catalog/review index. Copy QA is **WARN: 0 errors / 14 warnings**. The prior 13 dispositions remain unchanged; the additional `device.status.revoked` / `finance.status.revoked` equal-text warning is retained because revoking device authorization and revoking a ledger entry are separate translation contexts. No suppression or audit rule change was made. Human candidate-screen approval is still separate.

## Android Phase A resources

Android uses native `apps/android/app/src/main/res/values*/strings.xml`, with exact-text/category/context SHA-256 records in `qa/android_copy_review.json`. `make android-copy-qa` checks base/Chinese coverage, unreviewed changes, forbidden placeholders, copy budgets and visible Kotlin literals without reading Room or user text. This is the native Android equivalent of the Apple String Catalog gate; it does not suppress or approve the 14 existing Apple warnings. Functional identity verification/recovery guidance is necessary copy. No new emotional wording or fake delivery state was added.

## Android Phase B copy review

`qa/android_copy_review.json` registers exact English/Chinese resource hashes and the seven established categories. B adds requested task/wish/finance/media controls, necessary validation and the existing approved sender-label Gift copy. Relationship labels use one parser; the verified partner/sender is looked up, never guessed from the current user. Gift status distinguishes pending operation sync from content-verified partner receipt; no Delivered/read/bank-payment claim. Numeric English labels use “Unopened gifts: N” / “Wishes added: N” / “Changes synced: N” so singular counts remain grammatical. Unused action/status strings are removed, not hidden from the scanner. Existing Apple copy warnings retain their original disposition.

The 552 current localized resources include a specific storage recovery error: “Not enough free storage. Free some space, then retry.” / “存储空间不足。请腾出空间后重试。” It describes actual available-capacity failure, not an application-imposed original-file size limit.

## 0.2.3 bilingual copy

Chinese and English are complete resource sets. Settings exposes only a globe
icon until its menu opens. Language choice is local to each device. Chinese
product labels use Chinese; Together, ISO currency identifiers and genuine file
extensions keep their exact spellings. English gift copy keeps the intimacy of
“小男友 / 小女友” with “your guy / your girl”; neutral branches use “them”.
No relationship is inferred from the current user.

Use direct actions and actual states. Remove repeated implementation explanations,
hypothetical assurances and defensive filler. Keep concise file-sharing consent,
identity verification and an actionable explanation of a real failure.
User-authored titles, messages, names and notes remain untouched. Every locale
has its own reviewed text hash. `make localization-qa` checks both language sets;
the original copy audit continues to report context-specific duplicate warnings.
See [copy dispositions](../qa/reports/LOCALIZATION_COPY_0_2_3.md).
