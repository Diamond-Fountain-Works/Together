# Build 4 remaining copy review

13/13 warnings examined against current source. No static product text or copy-audit rule was changed. All 12 duplicate-text warnings describe independent translation contexts; one privacy disclosure still needs independent review. This is **WARN**, not PASS.

| Key | Exact text | Classification / decision | Evidence |
| --- | --- | --- | --- |
| `copy.empty_state.6b4beaf7f321` | 照片和语音保存在本机。中继仅转发加密帧，本机文件不另加密。 | 独立审核未完成 — Settings 隐私边界；PairingService 在发送 WirePayload 前调用 secure.seal，RelayCrypto 使用 ChaChaPoly；MediaStore 持久化原文件，不另做文件内容加密。技术事实与代码一致，但不能由同一实施者冒充独立安全审核。 Retain warning. | `0.2.1/Sources/TogetherApp/Views/Settings/SettingsView.swift` |
| `status.media.local` | Local | 合理的不同语义 — 附件文件已在本地，与礼物提交的 Local 是不同领域状态；未承诺远端收到。 Retain warning. | `0.2.1/Sources/TogetherCore/Localization/StatusCopy.swift` |
| `setup.title.welcome` | Welcome | 合理的独立流程 — Initial Setup 与 Advisor 是独立启动流程，在同一时刻不叠加；不是 Home 中重复欢迎横幅。 Retain warning. | `0.2.1/Sources/TogetherApp/Onboarding/InitialSetupView.swift` |
| `plans.filter.pending` | Pending | 合理的不同语义 — 任务筛选 Pending 与媒体传输 Pending 独立；任务未完成不等于附件等待同步。 Retain warning. | `0.2.1/Sources/TogetherApp/ViewModels/PlansNavigation.swift`; `0.2.1/Sources/TogetherApp/Views/HomeView.swift` |
| `finance.currency.VES` | Bolívar Soberano | 参考数据同名 — VED/VES 是独立币种代码；显示时保留代码，不能以同名合并币种身份。 Retain warning. | Dynamic domain key mapping / catalog reference |
| `finance.bill.pause` | 暂停 | 合理的不同语义 — 暂停账单未来规则，与语音播放暂停是不同操作；独立翻译上下文。 Retain warning. | `0.2.1/Sources/TogetherApp/Views/Finances/OurFinancesView.swift` |
| `finance.source.all` | 全部 | 合理的独立筛选 — 来源全部与付款方式全部是两个独立筛选维度，不是重复的同一操作。 Retain warning. | Dynamic domain key mapping / catalog reference |
| `finance.change.reserveEntry.create` | 新增存款 | 真实历史与操作分离 — 历史中记录已发生的新增存款，与新增存款按钮区分时态、领域用途；记录由实际操作生成。 Retain warning. | `0.2.1/Sources/TogetherApp/Views/Finances/FinanceReviewViews.swift` |
| `finance.change.dateEvent.create` | 新增约会 | 真实历史与操作分离 — 历史中新增约会，与新建约会按钮区分已发生事件/命令；不是重复说明。 Retain warning. | `0.2.1/Sources/TogetherApp/Views/Finances/FinanceReviewViews.swift` |
| `finance.change.expense.create` | 新增支出 | 真实历史与操作分离 — 支出变更历史与新增支出命令分别翻译；不凭空生成支出记录。 Retain warning. | `0.2.1/Sources/TogetherApp/Views/Finances/FinanceReviewViews.swift` |
| `finance.change.recurringBill.create` | 新增账单 | 真实历史与操作分离 — 账单创建历史与新增账单按钮分别服务于审计和命令。 Retain warning. | `0.2.1/Sources/TogetherApp/Views/Finances/FinanceReviewViews.swift` |
| `finance.change.billOccurrence.patch` | 修改本期预计 | 真实历史与操作分离 — 修改本期预计的历史事件与当前操作分开；只修改实际期次。 Retain warning. | `0.2.1/Sources/TogetherApp/Views/Finances/FinanceReviewViews.swift` |
| `finance.change.amount` | %@ → %@ | 模板同形但含义不同 — 金额前后变化与关系方向共用箭头形状，但分别是 Decimal 金额和昵称/身份；应独立翻译，且显示真实动态值。 Retain warning. | `0.2.1/Sources/TogetherApp/Views/Finances/FinanceReviewViews.swift` |

User-authored messages, tasks, wishes, nicknames and financial data were never audit inputs. Keeping these warnings does not hide unresolved review or modify published Build 4 binary content.
