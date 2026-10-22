# Together 0.2.3 localization and copy review

Date: 2026-10-22. Scope: source-controlled static product resources and synthetic
test fixtures. This report does not inspect user databases, gifts, photos, audio,
tasks, financial records, device keys or production preferences.

## Implemented interaction

The latest user decision supersedes the earlier sidebar language request:
**one globe menu at the upper right of Settings, on both platforms**. It offers
Chinese and English. There is no language control in either sidebar/navigation
drawer, and no second language picker elsewhere in Settings.

- macOS: `Views/Settings/SettingsView.swift` composes `LanguageMenu` beside its
  heading; `LanguageMenu.swift` owns the native menu.
- Android: `ui/TogetherApp.kt` adds `LanguageMenu` to the Settings top-bar actions
  only; its test tag is `settings.language`.
- UI language is a local preference. User-written content, stored enum values,
  signatures, protocol payloads, identities and pairing data are not translated.

## Executed checks

These results are a source snapshot taken after the Settings-only globe change and the five catalog/call-site cleanup fixes.
They are engineering checks, **not human approval of wording or visual baselines**.

| Check | Actual result |
| --- | --- |
| `python3 scripts/test_localizations.py` | **23 PASS, 0 FAIL, 0 SKIP** |
| `python3 scripts/audit_localizations.py` | **PASS: 896 Apple keys, 297 Android keys, 0 Error, 0 Warning** |
| Apple resource coverage | 895 `UI.xcstrings` keys + 1 `InfoPlist.xcstrings` permission key, each in `en` and `zh-Hans` |
| Android resource coverage | 297 keys in each language; 594 localized values |
| `python3 scripts/audit_ui_copy.py` | **WARN: 0 Error, 28 Warning** after 5 real fixes; all 33 original dispositions appear below |
| `python3 scripts/audit_android_copy.py` | **PASS: 594 localized values, 0 Error, 0 Warning** |
| Visual baseline approval | **NOT APPROVED by this report**; new captures remain candidates |
| Physical-device or real-network acceptance | Not performed by these static copy checks |

Machine reports are generated under ignored
`.local-only/localization-0.2.3/{localization-final,copy-final,android-copy-final}.json`.
They contain static copy findings, not user records. No screenshot is included in
this document.

The new localization audit complements the original Apple and Android copy
audits. Neither original script nor its warnings, budgets or review rules were
disabled, weakened or replaced. No duplicate warning was hidden through a budget
exception. The 23 tests include missing translations, changed argument types,
changed integer widths, reordered arguments, stale/missing per-language hashes,
Chinese/English leakage, exact whitelist boundaries, defensive filler, real
permission/identity recovery, nonzero failure exit status and static-resource-only
scope. Injected invalid fixtures fail as expected.

## Language review

- Both languages have explicit translations rather than relying on source-language
  fallback. Each exact language value has a SHA-256 review record.
- printf argument indexes, types, integer widths and occurrence order match across
  the two translations; literal `%%` is not counted as an argument.
- Chinese resources contain no ordinary English labels. The gate permits exact
  `Together` branding, the explicitly enumerated supported ISO 4217 currency
  identifiers, and real file extensions following a dot. An arbitrary uppercase
  token, a brand substring, or the word `app` outside an extension fails.
- Currency names are Chinese in Chinese mode, including the previously English
  fallback names. The gate checks 165 concrete currency entries; the separate
  `finance.currency.search` entry is a search label, not a currency.
- English gift copy retains the intimate intent without mechanically translating
  affectionate Chinese diminutives as “little boyfriend/girlfriend”. The shared
  affectionate forms are `your guy` / `your girl`, producing, for example,
  `A love note from your guy, just for you ♡`. Ending sentences use `him` / `her`.
  Unknown senders use an independent neutral branch, not a guessed partner role.
- In Chinese, unknown-role gift copy uses “对方”. Attachment-only gifts use
  “小礼物”, rather than describing nonexistent written text.
- Technical identifiers in stored records are preserved. This is separate from
  the user-visible language gate; user-authored text is never rewritten.

## Removed duplication and defensive prose

The source diff removes the following rendered paragraphs rather than just
changing the audit classification:

| Previous rendered copy | Current UI disposition |
| --- | --- |
| `finance.balance.guidance` beneath the reserves balance | Removed from `Views/Finances/OurFinancesView.swift`; the three factual balance labels remain |
| The same `finance.balance.guidance` beneath the deposit banner | Removed from `Views/Finances/FinanceReviewViews.swift`; the actual depositor/amount remains |
| `finance.reserves.openingGuidance` beneath opening-balance fields | Removed from `Views/Finances/FinanceEditors.swift`; the opening-balance heading and fields identify the operation |
| Repeated relationship-label caption `copy.status.cd960931fa8a` | Removed from Settings below the already-labelled relationship picker |
| Reduce Motion implementation paragraph `copy.guidance.e2ee62dfbb66` | Removed from Settings; system motion behavior remains implemented |
| Settings connection/security explanation card | Removed from Settings, including its repeated local-storage and protocol explanation; the app version remains a concise footer |
| Separate-replica explanatory caption `device.guidance.preserve` | Removed from device-join confirmation; explicit authorization and identity comparison controls remain |

Resource entries retained for historical/review inventory are not evidence that
these paragraphs remain rendered. In particular, the old storage-security entry
still carries its independent-review warning; deleting its UI paragraph does not
complete a security review.

Other copy is shortened to the current action or state: gift timezone/daily-rule
guidance, Flexible recurrence next-date guidance, pairing completion, unavailable
identity recovery and missing release-service configuration. “Your data is safe”
and “no replacement identity was generated” reassurances are not appended to
ordinary error messages.

Necessary choices remain explicit:

- Original-photo sharing asks for consent about location/private metadata
  (`copy.guidance.fdb33a105fcd`); Android keeps `guidance_photo_metadata` next to
  original-media sharing. This is an actual sharing consequence.
- Retracting a gift still explains that the daily allowance remains consumed
  (`copy.guidance.244e9103eea5`). Neither language promises removal of a recipient’s
  previously exported copy.
- Microphone permission purpose and recovery remain localized in the permission
  catalog/resources; recording is not described as available after permission
  denial.
- Device-name/fingerprint/code comparison, signed authorization, expiration,
  legacy identity restoration and existing-data rejection remain actionable.
  They are authentication and recovery requirements, not generic filler.
- Pending sync, remote persistence, media verification and user review remain
  distinct states. Neither translation converts pending delivery into “Delivered”,
  nor ledger reconciliation into bank verification.

## Every original Apple Copy Audit warning

`A/` below means `apps/apple/macOS/Sources/TogetherApp/`; `C/` means
`packages/together-core-swift/Sources/TogetherCore/`. Locations name current
consumers, including dynamic catalog lookups. **The initial scan had 33 warnings; 5 are now fixed and the remaining 28 stay visible.** “Retain” is a contextual engineering disposition, not a lint
suppression or human baseline approval.

| # | Warning key / type | Actual use and matching entry | Disposition |
| --- | --- | --- | --- |
| 1 | `copy.empty_state.6b4beaf7f321` / `human_review` | Local unencrypted media-storage disclosure; removed from the current Settings explanation card, retained in catalog/review inventory | **OPEN**: independent protocol/security review remains required. Neither localization tests nor removing a paragraph closes it. |
| 2 | `copy.guidance.3ae0703dd5cd` / `duplicate_copy` | Settings relationship Picker (`A/Views/Settings/SettingsView.swift`) matches removed caption key `copy.status.cd960931fa8a` | **FIXED**: removed the duplicate rendered caption and its unused catalog/review entry; this warning is absent in the final scan. |
| 3 | `copy.status.9622d2850be8` / `duplicate_copy` | Task-row recurrence badge (`A/Views/Tasks/TaskListView.swift`) versus recurrence choice `copy.guidance.dabbb0b4041f` in `TaskEditorView.swift` | Retain: English `Flexible` badge versus `Flexible Recurring` form choice; independent compact/status and editor contexts. |
| 4 | `copy.empty_state.2b9aaa6ee4f4` / `duplicate_copy` | No current app consumer found; matches active New Task action `copy.action.718e58cc20d6` used by menu, toolbar and editor | **FIXED**: removed the unused legacy empty-state catalog/review entry. Existing UI uses the unified task editor; this warning is absent in the final scan. |
| 5 | `copy.action.3d4a799b170e` / `duplicate_copy` | New-wish editor heading (`A/Views/Wishes/WishEditors.swift`) versus `copy.action.2b5c98884cf4` in `GrantDetailView.swift` | **FIXED**: editor and button now reuse `copy.action.2b5c98884cf4`; the redundant catalog/review entry was removed. English article differences were a style difference, not a business distinction. |
| 6 | `copy.action.8d12fc0d4eb2` / `duplicate_copy` | Recording pause (`A/Views/Gifts/GiftEditorView.swift`) versus playback pause `copy.action.858e4ba7a29f` in `AudioComponents.swift` | Retain separate recording/playback control contexts; both currently say Pause. |
| 7 | `copy.status.c74259555cfc` / `duplicate_copy` | `Together %@` in `A/ReleaseNotes/WhatsNewView.swift` versus `copy.guidance.5e362a89fa84` in Settings version footer | **FIXED**: both places now use `copy.guidance.5e362a89fa84`; redundant catalog/review metadata was removed. |
| 8 | `copy.action.31fbef162594` / `duplicate_copy` | Initial Setup next-step Continue versus recording Resume `copy.action.7c9691192f1b` | Retain: English `Continue` and `Resume` differ; Chinese “继续” alone does not establish interchangeable meaning. |
| 9 | `copy.action.a6c7a84baa67` / `duplicate_copy` | Advisor final Finish (`A/Onboarding/AdvisorView.swift`) versus sheet Done `copy.action.c0b3fbff51cc` | Retain: completing onboarding versus dismissing a picker/history/release sheet. English Finish/Done remains distinct. |
| 10 | `copy.navigation.9a9a3b610caa` / `duplicate_copy` | Release-note Partner Profiles title (`A/Resources/ReleaseNotes.json`) versus partner-profile caption `copy.status.bffe51e12e5e` in Settings | Retain: plural feature title and singular actual-profile status; English differs. |
| 11 | `nav.completed` / `duplicate_copy` | Plans filter/title and completion toggle (`A/ViewModels/PlansNavigation.swift`, `TaskEditorView.swift`) versus historical task status `copy.guidance.f28461bb49c8` in `SharedChangeHistoryView.swift` | Retain filter/navigation versus historical status contexts; do not combine task completion with unrelated Done actions. |
| 12 | `status.media.local` / `duplicate_copy` | `C/Localization/StatusCopy.swift` media transfer state versus `status.gift.local` business-gift delivery state | Retain: local media availability and local gift operation persistence are independent state machines. |
| 13 | `status.recurrence.day` / `duplicate_copy` | Inline recurrence unit in `C/Localization/StatusCopy.swift` versus `copy.guidance.5a730047d83f` editor choice | Retain: English lowercase unit `day` and selectable `Days` have different grammar. |
| 14 | `status.recurrence.week` / `duplicate_copy` | Inline recurrence unit versus `copy.guidance.977e8de6b21d` editor choice | Retain: English `week` versus `Weeks`; same reason as row 13. |
| 15 | `status.recurrence.month` / `duplicate_copy` | Inline recurrence unit versus `copy.guidance.37ebdc8c2ff9` editor choice | Retain: English `month` versus `Months`; same reason as row 13. |
| 16 | `setup.title.welcome` / `duplicate_copy` | Initial Setup stage title versus Advisor welcome title `copy.navigation.0e2226b5235f` | Retain independent onboarding-stage and optional Advisor tutorial contexts. Both have real flow behavior; neither is a decorative Home banner. |
| 17 | `setup.title.connect` / `duplicate_copy` | Initial Setup Connect Your Partner stage title versus `copy.action.e3b0859f5da0` Connect My Partner action | Retain: heading and action use different English perspective; an action opens the pairing controls. |
| 18 | `plans.filter.pending` / `duplicate_copy` | Plans/Home pending filter label versus `copy.status.7f750504c5ba` historical pending task value (`SharedChangeHistoryView.swift`) | Retain navigation/filter versus history-value contexts. Pending and Upcoming were not reintroduced as separate task filters. |
| 19 | `finance.bill.pause` / `duplicate_copy` | Recurring-bill rule pause in `A/Views/Finances/OurFinancesView.swift` versus recording pause `copy.action.8d12fc0d4eb2` | Retain distinct rule-lifecycle and audio-session actions. Pausing a bill affects future accounting generation; pausing recording does not. |
| 20 | `finance.source.all` / `duplicate_copy` | Dynamic `finance.source.*` expense-source filter (`OurFinancesView.swift`) versus generic `finance.filter.all` filter option | **FIXED**: the source-filter All branch now reuses `finance.filter.all`; the redundant catalog/review entry was removed. The scanner was not changed. |
| 21 | `finance.source.bill` / `duplicate_copy` | Dynamic expense-source option versus `finance.tab.bills` workspace tab (`A/ViewModels/FinanceNavigation.swift`) | Retain: singular English `Recurring Bill` source versus plural `Recurring Bills` section. |
| 22 | `finance.cycle.shared` / `duplicate_copy` | Cycle-scope choice in `A/Views/Finances/FinanceSettingsView.swift` versus `finance.tab.reserves` tab title | Retain explicit domain contexts: a financial-cycle scope choice versus the United Reserves workspace tab. Both English values currently read United Reserves; no different English wording is claimed. No second accounting model or filter is created. |
| 23 | `finance.change.reserveEntry.create` / `duplicate_copy` | Dynamic past change label in `A/Views/Finances/FinanceReviewViews.swift` versus `finance.action.new.reserves` | Retain: English Deposit Added event versus Add Deposit command; real persisted event is not an available action. |
| 24 | `finance.change.dateEvent.create` / `duplicate_copy` | Dynamic Date Event Added event versus `finance.events.new` command | Retain event/command distinction; actual date-event creation and history share the same ledger facts. |
| 25 | `finance.change.expense.create` / `duplicate_copy` | Dynamic Expense Added event versus `finance.action.new.expenses` command/editor title | Retain event/command distinction; no second expense record is created for the history label. |
| 26 | `finance.change.recurringBill.create` / `duplicate_copy` | Dynamic Bill Added event versus `finance.action.new.bills` command | Retain event/command distinction; templates remain separate from generated Expenses. |
| 27 | `finance.change.billOccurrence.patch` / `duplicate_copy` | Dynamic Expected Occurrence Changed event versus `finance.bill.editOccurrence` command/editor title | Retain: completed change versus actionable Edit This Occurrence. |
| 28 | `finance.change.amount` / `duplicate_copy` | Old/new money formatting in `FinanceReviewViews.swift` versus `copy.guidance.3e122095ba88` directional fulfiller/beneficiary relationship in Home/Wishes | Retain: amount transition and directional relationship have independent argument semantics despite the same arrow template. |
| 29 | `sync.changes.profiles` / `duplicate_copy` | Profiles change-history domain in `A/Views/SharedChangeHistoryView.swift` versus `copy.navigation.7289f8ec5827` Settings Your Profile heading | Retain: plural cross-user change domain versus current user’s profile editor; English differs. |
| 30 | `device.status.revoked` / `duplicate_copy` | Device authorization revoked in `DeviceManagementView.swift` / `DeviceEnrollmentModel.swift` versus `finance.status.revoked` deposit tombstone status | Retain different authorization/accounting domains. Reusing wording must not conflate revoked access with a reversed ledger entry. |
| 31 | `device.status.online` / `duplicate_copy` | Individual authorized-device session in `DeviceManagementView.swift` versus `copy.status.0d21bd52022c` member presence in `HomeView.swift` | Retain device-level versus member-presence context; multiple devices may contribute to a member’s presence. |
| 32 | `device.status.offline` / `duplicate_copy` | Individual device session versus `status.connection.offline` connection state used by `StatusCopy.swift` and Home | Retain device-level session versus app/partner connection context. An offline extra device does not imply all communication is offline. |
| 33 | `native.sync.pending` / `duplicate_copy` | Operation persistence status in `A/Networking/NativeAcceptance.swift` versus `status.gift.pendingSync` gift delivery status | Retain: operation ACK and gift/media-complete acknowledgement are different conditions; combining them could misrepresent delivery. |

The five fixed rows were implemented by the coordinating engineer in the actual
call sites/catalog/review index and then re-audited. This report task did not edit
concurrent app source. The final scan contains 27 context-specific duplicate-copy
warnings and the separate unresolved security-review warning; none was suppressed
or hidden behind a new rule or budget exception.

## Remaining gates

- Original Apple Copy QA is **WARN: 28 warnings**, not PASS. The table accounts for
  all 33 initial warnings, including the five verified fixes.
- Security review remains independent from translation and developer self-tests.
- Candidate screenshots and bilingual visual layouts need their own recorded
  inspection; this source-only report grants no visual baseline approval.
- Builds, physical devices, networking and release installation are separate QA
  results and are not inferred from static localization success.
