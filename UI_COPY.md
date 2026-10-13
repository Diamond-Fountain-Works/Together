# Together UI copy contract

## Source and categories

Formal static product copy lives in `0.2.1/Sources/TogetherCore/Resources/UI.xcstrings`, with review metadata in `qa/ui_copy_review.json`. Swift code references stable keys via `Copy.text`; never add a visible literal without adding its catalog entry and review record. ReleaseNotes structured copy is also scanned. User-authored tasks, wishes, gifts, nicknames and private memories are never audit inputs.

Native permission copy uses `TogetherApp/Resources/InfoPlist.xcstrings` and the same review index. The generated base Info.plist keeps the matching fallback; changing it requires changing the catalog and review too.

Every entry has exactly one category: Navigation, Action, Status, Guidance, Empty State, Error or Emotional. Static errors include a useful cause/recovery when possible. Do not print user text or complete invitation codes in diagnostic logs.

## Budgets

Chinese ordinary actions: 8 characters; page titles: 14; ordinary card guidance: one sentence, preferably at most 30. Empty states: one prompt and a useful action. Status feedback is short, accurate and literal. English menus should be short and desktop-native. Over-budget copy is a Warning requiring a named review reason; never truncate semantic copy automatically. Existing long privacy/error text is tracked for review, not silently deleted.

Forbidden copy produces Error: Lorem Ipsum, product placeholder/sample data, fictional-data explanations, invented user records/counts, unimplemented feature promotions, emotional filler on ordinary task/Home/settings pages, and unregistered newly visible copy. Subjective length, repeated phrasing and excess emoji produce Warning for a human to assess.

## Approved scope

The user-specified Love Gift/Gift Reveal titles, relationship-label branches, “Open Your Gift ♡”, “收到啦 ❤️” and conditional reply copy are approved Emotional entries. They resolve the actual verified sender Profile; unknown uses TA, pure attachments use 小礼物. Role labels never grant permissions. Initial Setup welcome is functional onboarding, not permission to add welcome banners elsewhere.

Send/history entry labels and Save Photo are explicitly requested actions. Ordinary pages use factual headings/status only. No Love Gift card or sidebar page. Do not claim Delivered from local submission or a relay socket; Synced requires the remote durable/media acknowledgement. Realtime relay does not imply offline delivery.

The latest navigation correction uses user-requested Plans / Wishes as vertically stacked left sidebar entries, replacing the Our Plans title and horizontal Tasks / Wishes picker. Pending / Upcoming / Completed / New Task / Add Wishes remain functional labels. New `plans.*` entries cover factual empty/search states and real dated grant quantities. Task Pending keeps a distinct translation context from media Pending. Identity migration adds only `identity.*` functional recovery copy: original keys are preserved, one-time migration is explicit, failures never advertise a successful rebind. No romantic filler is added to either workspace.

## Review and changes

Catalog import labels existing copy as legacy inventory; policy exceptions and long entries retain a review reason. New unreviewed keys fail the audit. Review metadata must identify category, context, review state, reason and the SHA-256 of the exact reviewed text. Changing the value under an existing key without updating its review fails; keeping an old key does not authorize new wording. Setting approved is not a substitute for user approval where the change is important. Candidate visual images do not approve copy.

Run `make copy-qa` (or `python3 scripts/audit_ui_copy.py --json qa/results/copy.json`). The report lists path, key, issue type, severity and suggested action. Copy audit, business tests and visual review are separate gates. Fixture strings are deliberately excluded by path, not by broadly suppressing words found in live product code.

## Our Finances copy

The `finance.*` catalog entries are functional names, actions, filters, true ledger states, reminder prompts, audit formats and recoverable errors from the approved 0.2.1 scope. ISO 4217 currency names/precision are bundled from SIX List One (2026-09-17); eight common names are localized, others retain official names. No invented amounts or emotional finance copy. `待核对` is provisional bookkeeping; `已核对` is user reconciliation, never bank confirmation. Original/CNY/rate values, category names and actor names are user or derived data and remain outside static-copy lint. Dynamic enum prefixes require concrete catalog coverage tests; a prefix is not an invented visible entry. Existing long-copy warnings remain for human review.
