# Shared UI copy cleanup — 0.2.4 Build27 / Android18

Scope: Mac, iPhone/iPad and Android static UI copy. User-authored records are unchanged.

## Removed visible text

| Area | Removed |
| --- | --- |
| Wishes | Grant-use explanation; adjustment-history assurance |
| AA / currency | Remainder algorithm explanation; repeated actual-CNY priority text |
| Profile/setup | Duplicate role, photo and crop instructions; extra partner-caption label |
| Recurring tasks/reminders | Repeated next-time and planned-deposit instructions |
| Gifts | Unconditional draft-saved caption; extra sealed-card prose |
| Devices | Permanent offline footer; repeated own-device introduction |

18 visible text calls were removed.21 Apple and3 Android resource entries were deleted, including6 unused Apple explanation/disclosure entries and an old self-descriptive release highlight.8 entries use shorter factual wording.

Card-history guidance appears when changing an existing shared card to private; short-month guidance appears for selected days29–31. Save logic, permissions, errors, receipt states, ledger rules and the prescribed gift titles/endings are unchanged.

## Deleted Apple resource keys

- `copy.status.3cfd61f73f08`
- `copy.status.01b6f9e2d127`
- `finance.aa.rounding`
- `finance.amount.rateGuidance`
- `copy.status.af495a06b2de`
- `copy.status.bffe51e12e5e`
- `copy.status.6a8ae976f27c`
- `copy.status.1bb474fad984`
- `copy.status.dbfd5d14c799`
- `copy.guidance.08a8bfd082bf`
- `finance.cycle.planGuidance`
- `copy.status.99d1094feca8`
- `copy.status.e23f8f7eb807`
- `copy.empty_state.6b4beaf7f321`
- `copy.guidance.9dd62bb75ce0`
- `copy.guidance.e2ee62dfbb66`
- `finance.balance.guidance`
- `finance.reserves.openingGuidance`
- `device.guidance.preserve`
- `release.0.2.3.copy.title`
- `release.0.2.3.copy.detail`

Android deletes `guidance_offline`, `guidance_actual_cny`, and `guidance_planned_deposit`. The duplicate enrollment use of `guidance_add_device` is removed; the entry-page distinction remains.

## Shorter wording

| Key | Chinese | English |
| --- | --- | --- |
| `copy.emotional.3ceeec638ae6` | 配对后可发送 | Pair to send |
| `copy.guidance.c17ea66392d2` | 共享时区：%@ | Shared time zone: %@ |
| `copy.status.854395e0abf2` | 已配对 | Paired |
| `finance.cards.privacy` | 历史共享记录仍保留 | Previously shared records remain |
| `copy.guidance.34509ac3c987` | 核对安全码后确认配对 | Compare the code with your partner, then confirm |
| `copy.guidance.a98b94457fae` | 一起安排任务和愿望 | Plan tasks and wishes together |
| `finance.release.syncDetail` | 同步存款、支出和账单 | Sync deposits, expenses, and bills |
| Android `guidance_card_history` | 历史共享记录仍保留 | Previously shared records remain |

## Verification

- Localization PASS:883 Apple catalog keys and295 Android keys;0 errors/0 warnings.
- Apple Copy QA WARN:0 errors/26 context-duplicate warnings. Android Copy QA PASS:590 localized entries,0 errors/0 warnings.
- Existing audit rules and review budgets remain enabled; exact locale hashes were refreshed.
- Core/business182 PASS/0 FAIL/6 opt-in SKIP, including isolated migration/local Relay/crash recovery.
- iOS normal Release and isolated QA Build27 compile;24 artifact checks and12 configuration/locale-negative regressions pass. The compiled881 UI values per locale match current source.
- Final macOS Build27 compiles and passes bundle validation.
- Android18 compile/JVM/lint/native-ABI verification are recorded in the local build receipt and latest PR Checks.
- Visual and physical iPhone/iPad acceptance remain NOT RUN under the user’s deferral; no baseline was replaced.

Local evidence: `qa/results/iphone-client-20261027/copy27-*.json`, `ios27-artifact.json`, `ios27-archive.json`, final build logs and cleanup receipts. Raw artifacts/logs stay local. Current hosted status belongs to the latest PR commit; the previous Build26 green checkpoint remains separately retained.

The iOS archive is unsigned; signing/provisioning and physical-device acceptance are still required. The PR remains Draft.
