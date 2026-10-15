# Monorepo foundation — 0.2.1 Build 5 candidate

- Consolidates the current macOS source, TogetherCore package, C1 Relay and authoritative docs without business/transport/schema changes; restores legacy migration source from pinned verified Git history.
- Preserves Build 4 human-approved image baselines and all recoverable Git history. Standard project `.git` replaces cache dependence; original external objects and verified external backups remain.
- Adds platform-neutral schema/DTO/calendar/money/signed-log/media vectors, public-source safety gate and read-only CI. No Android/iOS/watchOS app is claimed.
- Public Organization repository created by explicit instruction. Invitation remains 10 minutes in code; the formal 8-hour requirement is tracked in Issue #1. No Worker deployment, installation or binary release upload.
- Build 5 increments the candidate because package/resource paths can change the binary. Actual regression and packaging results are in [monorepo QA](../qa/reports/MONOREPO_QA.md).

## Prior version records

# Together changelog

## 0.2.1 · Build 4 — input-method QA follow-up (no new product binary)

- Compared the original failing finance snapshot case under temporarily selected ABC and restored Pinyin; retained both complete logs and verified the original configured input sources/hotkeys were preserved.
- Corrected only XCUITest input-dialog waiting and fresh currency-row lookup; kept currency-selection/closure assertions and added light/dark Latin/Chinese search coverage. No Chinese input restriction was introduced.
- Recovered the missing dark personal-financial-cycle capture. Human baseline approval remains distinct from automated capture.
- Reviewed all 13 remaining copy warnings individually without modifying product text or disabling audit rules.
- Created and restore-verified a durable all-refs Git bundle outside the cache directory; the live repository was not moved.
- Release Build 4 binary/DMG remain unchanged; no installation, production-data, identity or pairing change. Actual final results are recorded in qa/FINAL_QA_BUILD4.md.

## 0.2.1 · Build 2 — Our Finances (development)

- Added three-tab finance workspace, one shared/individual/AA expense ledger, derived reserve balances and dated deposits.
- Added ISO 4217 currency wheels, integer/Decimal frozen CNY settlements, categories/date events/period filters and safe card metadata.
- Added monthly rule revisions, deterministic Provisional instances, backfill, nonblocking reminders and confirm/correct/skip actions.
- Added signed finance operations, audit changes, remote one-time notifications and V3 compatibility checks with preserved V2 route/identity upgrade.
- Kept physical SwiftData schema and original source; added a real old-source store migration fixture, finance tests and native UI/rendering evidence gates.
- Existing installed 0.0.1 App is not replaced by this task. No bank connectivity, debt settlement, Android, offline mailbox or automatic updater.
- Final acceptance details and remaining environment/physical-network limits: TEST_PLAN.md and qa/results.

# Changelog

## 0.0.1 · Build 1 — 2026-10-10 incremental development

### Plans / Wishes vertical navigation

- 按最新 UI 修订，将 Plans、Wishes 放到左侧竖排，Home 在上方，Connection / Settings 仍在底部；移除内容顶部的横向 Tasks / Wishes 切换。
- 两个入口共享稳定工作区 View，保留任务筛选、搜索、滚动位置、统一编辑器与愿望账本。Home 的任务和愿望摘要分别导航到正确入口。
- Catalog 中导航名称更新为 Plans；文案审核、设计规范和 UI 行为检查同步更新。业务模型、身份文件、同步和礼物规则未变。

### Our Plans / local identity follow-up

- Sidebar 合并为 Home / Our Plans，Connection / Settings 位于底部；Tasks / Wishes 模式、任务 Pending / Upcoming / Completed 共用数据与编辑器。
- Upcoming 严格显示未来日期任务，Completed 按完成时间倒序；Home 摘要可导航，任务详情复用编辑器，空 Upcoming 不占用 Home。
- Wishes 按约定日期分组真实额度历史，详情复用既有愿望创建/申请/确认/调整；没有更改额度、Recurring、Gift 或同步规则。
- 原生菜单 Command + N、唯一 New Task / Add Wishes、180/280/420ms 动效与 Reduce Motion；新增功能性 Catalog 文案和前后截图证据。
- 按需求将设备身份私钥改存 700/600 本机目录/文件。旧 Keychain 只在主动迁移时读取一次；校验原签名、保留身份及业务数据，缺失或拒绝不自动换钥匙。

### Added

- DESIGN_SYSTEM、UI_COPY、短 AGENTS 规则索引、String Catalog 和精确文案哈希审核。
- Copy Audit、make qa、隔离原生 XCUITest fixtures、候选截图和不可自动覆盖的人工基线比较。
- 共用 OperationLogSyncSession、SyncTransport、RelayWebSocketTransport 与保留的 LegacyTailscaleTransport。
- Workers/Durable Objects 实时中继：一次性邀请码、认证请求、双确认、路由/socket ticket、限速和清理。
- CryptoKit 会话签名/密钥协商/认证加密/重放保护，可信身份与原共享空间安全迁移。
- Gift Reveal 原图 NSSavePanel 导出；本机原图保持完整。

### Changed

- Love Gift 从 Home/Sidebar 常驻模块移除，改为 File 发送（⌘⇧L）和 Window 历史菜单。
- 启动礼物同步窗口有界，缓存礼物离线可展示，使用中收到礼物下次启动自动展示；保留密封隐私、一次展示与额度规则。
- 普通页面移除冗余标题说明；显示状态与协议 raw value 分离，关系称呼沿用已批准分支。
- Tasks 编辑状态由 Sheet 独立持有，匹配几何仅作用于标题，保留原领域提交与重复规则。

### Verification / release boundary

详细机器结果在 qa/results，人工状态在 TEST_PLAN。Cloudflare OAuth/邮箱验证已完成，Worker/DO 已实际部署，HTTP 200 与原生 HTTPS/WSS 全流程通过；公开 origin 自动编入 App。

应用协议独立安全审查、实体双 Mac 跨 Wi-Fi、麦克风硬件和人工截图批准仍待完成。没有离线邮箱/静态加密/Our Story/Time Capsule/普通聊天/独立相册；不将它们标记为已发布。


### Deployment follow-up

- 新增 Configuration/RelayService.json 与 server/deployment.json，保存实际公开服务 origin/部署版本，默认构建和 Run 不会丢失服务配置。
- 扩充 RelayIntegrationTests，公网验证 Profiles、愿望申请/确认、原图头像、音频+照片礼物、哈希、receipt、重连与持久化。
- 使用真实部署服务，不改变既有业务模型或用户数据；没有离线邮箱或额外联网配置需求。

- 显式生成 App Info.plist 模板，并在 build_and_run 中验证实际 Bundle 服务 origin/版本/签名，防止成功编译但缺失联网地址。
- 构建入口支持 --release-build-only，将经过版本/origin/签名校验的 Release App 放入 dist；默认 Debug 开发入口保留。

### Packaging

- 新增 `make package` / `0.0.1/script/package_app.py`：构建 Universal Release，生成压缩 UDZO DMG、Applications 快捷方式、安装说明、SHA-256 和机器验证报告。
- 交付前只读挂载，逐文件核对 Release、版本/服务 origin、签名、架构与安装入口；不包含或改动用户数据。
- 当前为 ad-hoc 开发测试分发，Developer ID 签名/公证未完成，Gatekeeper 拒绝；不把打包成功当作正式分发信任验收。

### Current navigation verification

- 66 automated tests PASS / 0 FAIL, 1 UI SKIP; 38 final native captures require human approval. Copy: 0 errors / 35 warnings.
- Updated dist/Together.app and Universal DMG (3,987,456 bytes, 3.80 MiB), mounted hash/signature/metadata checks PASS. Version remains 0.0.1 Build 1.


### Local installation / cleanup — 2026-10-11

- Added `make install` / scripts/install_local.py for validated local delivery. Current 0.0.1 Build 1 lives at /Applications/Together.app; the 3.80 MiB Universal installer is on Desktop.
- Verified App identity, full bundle/file hashes against the mounted DMG, code signature, installed-file equality and Desktop image hash before cleanup. Six generated bundles and four obsolete registrations removed; one app/registration remains. Source, QA evidence, distribution DMG and user data retained.
- Instructions now use Applications as the daily entry; future local delivery is make package followed by make install. No UI or business changes.

## 0.2.1 · Build 3 — Final QA candidate

- Individually reviewed all 58 copy warnings; shortened functional/privacy/recovery descriptions and reused equivalent catalog actions. Retained distinct translation-context and independent security warnings.
- Added full-row currency/day hit areas, stable test window sizing and Financial Cycle accessibility identification; business models, quotas and sync protocol remain unchanged.
- Strengthened UI waits and real compact-size assertions; extended native screenshots to bill editors, currency popovers and personal-cycle settings.
- Added a read-only production-store copy rehearsal, repeated identity/store reopen checks and signed-log deduplication checks. Original user storage and Applications are not modified.
- Corrected QA pass counts to distinguish skipped Swift Testing cases. Current acceptance evidence is in qa/FINAL_QA_BUILD3.md; this entry alone is not a passed release claim.
- Final QA additionally reproduced and corrected a reconnect transcript race in the existing PairingService; retained strict signatures, current-session confirmation and AEAD checks. Added three real reconnect regression rounds and isolated local Worker test state. No server deployment, protocol/schema migration or new business feature.

- Shortened financial sheets to fit the 620pt supported compact content area and moved existing expense review/delete actions outside scroll content. Native captures target complete sheets/popovers, preserving visible footer actions.

## 0.2.1 · Build 4 — Release entitlement correction

- Disabled Xcode base-entitlement injection for Release; get-task-allow is absent. Required network, microphone and file-panel access plus hardened runtime are retained.
- Bundle verifier now rejects debugger access in Release and checks actual required entitlements. Marketing version remains 0.2.1; no business/schema/protocol change.
- Verified Universal DMG/checksum/mounted bundle; ad-hoc and not notarized. Final candidate is NOT READY FOR LOCAL INSTALL because one native UI capture case still fails and one required screenshot is missing.

## 0.2.1 Build 6 — Git-like C1 foundation (development, not deployed/installed)

- Add explicit replication 4/API 2 capability alongside unchanged legacy Protocol 3: stable two-user space, independent signed device grants/epochs, retained revocation history, certified operation chains and co-signed old-log migration.
- Add immutable paged content/certificate inventory, bounded bidirectional batches, live sync hints, durable per-device signed receipts and restarted gap recovery.
- Reuse original domain merge with off-main verification/replay, scoped local entity recomputation and changed-row derived-cache updates; keep original physical SwiftData schema and identity/bindings.
- Add directed encrypted multi-device relay sessions and reused resumable verified media; no mailbox, bank integration, C2 or Android UI.
- Add local universal change history/review, with sealed gift privacy, same-user other-device origin and superseded history. Dedicated QA-host configuration isolates test startup.
- Add cross-runtime signed fixtures, four native-client local Worker tests, actual SIGKILL recovery and a 100,000-signed-operation benchmark. [Evidence and limits](../qa/reports/GITLIKE_C1_QA.md).
- Harden retired-hello replay, invalid staged-chain recovery, sealed legacy-baseline retry and exact revoked-prefix verification; retain rejected raw history and prevent stale asynchronous projection from restoring revoked authorization. Six adversarial regressions pass.
- Invitation eight-hour fix remains a separate PR #3 with no production deployment. New enrollment UI, external security/physical acceptance and human visual approval remain release gates.
