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
