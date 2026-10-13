# Together 0.0.1 · 实施记录

原 A–O 为历史记录；文末“最新增量”替代 Home 礼物卡、Tailscale 正常流程和旧验收状态。

## 环境和交付

- 原目录 `0.0.1/` 初始为空；后续 Addendum 在已实现代码上增量开发，没有重新创建或重置本地数据库。
- Xcode 27.0 / Build 27A266a，macOS 27 SDK，最低部署 macOS 14，Swift 6。
- 源码：`0.0.1/Sources/`；原生项目：`0.0.1/Together.xcodeproj`；App：`0.0.1/dist/Together.app`。
- 版本 0.0.1 / Build 1 / Bundle ID com.together.app。
- 当前项目继承 home Git 仓库，没有创建嵌套仓库。
- 未检测到 Tailscale App/CLI，真实跨网络双 Mac 待人工验收。
- Icon Composer 已安装；无可信 MCP / icontool，交付 SVG/PNG/Assets，不虚构 `.icon`。

## Phase A — 基础工程、模型、SwiftData、原生 UI

文件：README、ARCHITECTURE、REQUIREMENTS、TEST_PLAN；Package.swift、Models/Domain.swift、Models/Identity.swift、Synchronization/Operations.swift、Persistence/Repository.swift；TogetherApp、ApplicationModel、RootView、TogetherTheme、generate_project.py、build_and_run.sh。

实现：两人身份、Keychain 签名、SwiftData 日志/缓存、NavigationSplitView 七页和单 Window Scene。业务不用 UserDefaults，不覆盖已有数据。

验证：Core 首轮 1 项通过；后续完整测试和原生构建通过。未完成：真实 GUI 辅助功能验收。

下一阶段：Tasks/Recurrence（已完成代码接入）。

## Phase B — Tasks、Regular / Flexible

文件：ReplicaEngine、Projector、RecurrenceCalculator、TasksView、TaskEditorView/NextTimeView、ReplicationTests、BusinessTests。

实现：CRUD、筛选、Tombstone、计划锚点/月份/DST、确定性下一实例、Flexible 选时间或稍后，不猜日期，到期/重启恢复。

验证：离线任务、独立字段合并、冲突、去重、乱序、删除、Regular/Flexible 自动测试通过。未完成：双实体 Mac 与键盘/点击验收。

下一阶段：Wishes（已完成代码接入）。

## Phase C — Wishes

文件：WishProjector、WishesView、WishEditors、BusinessTests、Domain。

实现：分批额度、CivilDate、具体愿望、申请/确认兑现、审计调整、推导总计/兑现/剩余/可填写额度、并发超额冲突。无 Mock/虚构统计说明。

验证：3+2 历史分别存在、兑现后剩余 4、重复确认不扣、权限/并发/调整测试通过。未完成：双 Mac UI 操作验收。

下一阶段：Profiles 与 P2P（原始头像需求已由 Phase I 正式替换）。

## Phase D / E — 原有 Profiles 和日志 P2P

文件：AvatarProcessor（保留旧小图兼容）、Identity、ReplicaEngine、PeerService、WireProtocol、SettingsView、ConnectionView、NetworkAndPersistenceTests。

实现：本人 Profile 编辑、对端只读、签名握手、人工校验和公钥 pin、NWListener/NWConnection、日志交换/去重、同时连接选择。新资源和自动重连见 Phase I/L。

验证：原有 Profile、小头像兼容、磁盘重开、真实 loopback TCP 与断线测试通过。未完成：跨 Wi-Fi/Tailscale 实验。

下一阶段：Advisor/图标（已实现）；原图扩展进入 H–O。

## Phase F / G — Advisor、What's New、视觉、图标、构建

文件：LocalAppPreferences、AdvisorView、WhatsNewView、ReleaseNotes.json、TogetherTheme、RootView、IconSource/*、Assets.xcassets、ICON_COMPOSER.md、generate_icon.swift、generate_project.py；PreferencesTests 和文档。

实现：独立 Guide/Release Notes，进程级 60 天与永久关闭，原生微动画/Reduce Motion/Light-Dark，SVG 心形与已集成 Asset Catalog 图标、真实 Xcode Target/构建入口。

验证：原始 16 项测试、原生 App 构建/启动通过；用户此前确认能看到 Advisor。未完成：`.icon` 实际导出（工具不可用）；动画和可访问性人工验收。

下一阶段：按 Addendum 增量 H–O（以下代码已实现）。

## Phase H — Initial Setup 与关系身份

文件：Onboarding/InitialSetupView.swift、LocalAppPreferences、GiftLaunchPolicy、Domain/UserProfile、Gifts/LoveGift.swift、SettingsView、ApplicationModel、RootView；RelationshipTests、PreferencesTests。

实现：独立五步设置、无预选角色、必填昵称/可跳过头像、可稍后连接、本地首份草稿、完成后正常重启不强制重来。统一 trim/大小写/中文旧值映射，invalid/nil/missing 回退 TA；同标签双方合法，Settings 重选提示，不重置业务。

验证：初始状态与 Advisor 独立持久化、标签全分支、缺失/null 历史 Profile 数据兼容测试通过；SwiftUI 编译通过。未完成：实际首次流程逐步点击。

下一阶段：原图与媒体资源基础设施（已完成代码与模型/TCP 验证）。

## Phase I — 原图头像与资源存储

文件：Media/MediaAsset.swift、MediaStore.swift、Domain、Projector、ReplicaEngine、AvatarCropView、AvatarView/TogetherTheme、SettingsView、ApplicationModel。

实现：原图保留，无人为总文件/分辨率/像素上限；ImageIO URL 缩略图缓存，裁剪元数据不破坏原图；GPS/元数据提示，受控路径、流式哈希、本机未发布媒体暂存；旧 avatarData 兼容保留。

验证：8200 像素宽原图、字节哈希、裁剪后原图不变、无效 crop/坏图、头像真实 TCP/磁盘重开通过。未完成：真实 HEIC 与不同双 Mac 图片 UI/大文件磁盘异常手工验收。

下一阶段：每日礼物模型、日期与唯一额度（已完成）。

## Phase J — Daily Love Gift 与共享时区

文件：LoveGift.swift、GiftProjector.swift、ReplicaEngine、Repository、Domain；LoveGiftTests。

实现：不可变礼物与独立草稿，文字/单语音/单照片任意组合；stable gift ID；领域检查 + SwiftData transaction 原子提交资源清单/礼物/唯一槽；重复、离线、重启、删除不退额度；同日候选确定性冲突。固定共享时区和 Clock，跨午夜及保守回拨保护。

验证：两时区一致、DST/午夜前毫秒边界、双向发送/回复、同日拒绝、删除/重开/重复/非法身份/同日候选收敛通过。未完成：真实系统时区与长时间运行 UI 边界手工检查。

下一阶段：语音与照片编辑器（代码已接入）。

## Phase K — 语音、照片附件

文件：Views/Gifts/AudioComponents.swift、GiftEditorView.swift、MediaStore、ReplicaEngine、Together.entitlements、generate_project.py。

实现：AAC/M4A 录音、暂停/继续/停止、导入原音频、试听、移除未发送文件；照片原图、预览与用户点击打开原图；播放进度/时间、无自动播放；麦克风权限说明/拒绝提示；纯命令行 bundle 缺失权限说明时不请求录音。

验证：纯音频、纯照片、三项组合、草稿不共享附件清单、未发布附件文件移除测试通过；原生 Info.plist/entitlement 构建检查通过。未完成：真实麦克风授权、录音、耳机/扬声器播放点击验收。

下一阶段：P2P 文件和礼物确认（已完成 loopback 验证）。

## Phase L — P2P 资源和礼物同步

文件：PeerService、WireProtocol、ReplicaEngine、GiftReceipt、MediaStore、ConnectionView；MediaTransferTests、NetworkAndPersistenceTests。

实现：协议 2 协商、原签名设备/会话认证；MagicDNS 后台解析并校验 Tailscale IP；每端启动监听；已保存身份自动连接、同时握手去重、指数退避、网络/监听恢复。独立资源 request/chunk/complete/verified/failure，分块进度、持久部分文件恢复、哈希/格式校验提交。收到真实礼物/附件确认才 Synced。

验证：真实本机 TCP 双向连接、签名人工配对、自动启动双方监听/无重新配对/对端恢复、头像/语音/照片、多次分块、哈希失败、持久恢复、Synced 与 Pending 区别、单端删除同步测试通过。修复了单端日志更新不能主动请求缺失操作以及数据收敛后状态仍停 Syncing 的问题。

未完成：真实不同 Wi-Fi 的 Tailscale/MagicDNS、系统防火墙/访问策略验证；此处不能替代跨网络验收。Sandbox 当前保持原有 OFF，入站/出站声明已核查，未来启用需数据迁移。

下一阶段：Reveal/History/Reply（已完成代码与展示策略测试）。

## Phase M / N — Reveal、历史、Home、引导与文案

文件：GiftRevealView、GiftHistoryView、DailyGiftCard、HomeView、GiftEditorView、GiftLaunchPolicy、ApplicationModel、RootView、AdvisorView、ReleaseNotes.json、TasksView。

实现：一入口拆礼物、同界面逐一看，实际文字/音频/照片与统一 sender Profile 文案、收到啦关闭、回赠遵守额度。hasAutoPresented/openedAt 独立本地持久，关闭/删除/Profile 更新不重弹；运行中未读提示不抢编辑 Sheet。Home 简洁入口与历史，单次 Heart、Reduce Motion，7 步 Advisor 和真实新功能 Release Notes。空 Upcoming 卡片与情感说明移除，Wishes 没有演示说明。

验证：本地展示/打开标记、标签更新、自动一次/后续非打断策略和模态优先级测试通过，SwiftUI 与原生构建通过。未完成：原生 AX/点击、信封动画、Reduce Motion、Light/Dark 人工验收；Computer Use 的 native pipe 故障阻挡自动检查。

下一阶段：最终构建和文档（以下）。

## Phase O — 测试、构建与文档

文件：Tests/TogetherCoreTests/LoveGiftTests.swift、MediaTransferTests.swift、NetworkAndPersistenceTests.swift、PreferencesTests.swift；README、REQUIREMENTS、ARCHITECTURE、TEST_PLAN、PHASES；构建脚本/项目。

结果：完整 30 项 Swift Testing / 8 Suite 通过；实际 Xcode macOS App 构建和进程启动通过；0.0.1、Build 1、最低 macOS 14、麦克风说明、网络入站/出站与音频 entitlement 核查。无需新建或重置数据库；旧 Tasks/Wishes/日志和小头像保留。

仍未完成的验收：真实双 Mac/Tailscale/MagicDNS、麦克风硬件与权限、GUI/动画和辅助功能；`.icon` 导出、Developer ID/公证非本次可验证交付。详见 TEST_PLAN，不标记成已通过。

下一步：按照 TEST_PLAN 在两台实体 Mac 上执行手工验收；遇到具体问题在本 0.0.1 项目内继续修复，不新增聊天/相册/服务器功能。

## 原生 UI 重试补充

Computer Use 已恢复。实际检查交付 App 的 Home、Upcoming、Wishes、Gift Editor/History、附件菜单和文件选择器、Settings、Connection、Advisor、What's New；重启没有重复 Initial Setup，未修改业务记录。发现端口文本被本地化成 58,431，修改 ConnectionView 的 endpoint Text 为 verbatim 字符串，Xcode 构建/进程启动通过，界面确认 127.0.0.1:58431。

检查范围及仍未验收项目见 TEST_PLAN 的“本次原生界面复查”。未将没有真实配对和礼物数据的 Reveal/媒体播放记为 GUI 通过。


## 最新增量 — Design Gate / Relay / Love Gift UX（2026-10-10）

### Migration A–B：审计与传输提取

文件：ARCHITECTURE、SyncTransport、OperationLogSyncSession、PeerService。保留原签名日志/SwiftData/业务投影和 TCP 回归，抽取共同双向日志、媒体、receipt；没有数据迁移或清空。原 TCP 测试与完整 37 项业务测试实际通过；收敛后卡 Syncing 已修复。

### Migration C–D：服务和邀请

文件：server/package/lock、wrangler.jsonc、src/index.ts、test、README；RelayAPI、PairingService。实现 challenge/签名、12 位/10 分钟/一次邀请、限速、双确认、一次 ticket、双人 socket。TypeScript 检查与 7 项本地 Workers 测试实际通过。最初被 10034 阻止，邮箱验证后已实际部署；详情见文末跟进。

### Migration E–G：重连、共同同步、安全

文件：RelayWebSocketTransport、RelayCrypto、RelayURLSession、ReplicaEngine、Repository、SECURITY_REVIEW、RelayTests。实际原生 localhost WSS 对应 WS 测试完成：邀请码/双确认/加密日志/分块照片/receipt/断线恢复/重开持久化。HTTPS-only Release、拒绝 redirect、响应有界、会话重放/反射/篡改测试通过。未将原语测试当独立协议审查。

### Migration H：兼容

文件：ReplicaEngine.bindRelay、RelayBinding、PairingService、RelayTests。旧身份 pin、双边明确首次绑定、原子保存、保留任务/愿望/空间与日志、拒绝接管；自动重连不用邀请码。模拟身份/本地实网通过，实体旧两端不同 Wi-Fi 未验证。

### UX 修订

文件：TogetherApp、HomeView、ApplicationModel、GiftLaunchPolicy、GiftRevealView、MediaStore、Tasks/TaskEditorDraft；删除 DailyGiftCard。原生菜单发送/历史、Home/Sidebar 无常驻礼物、启动同步有界/缓存离线/晚礼物不打断、NSSavePanel verified 原图保存。额度/模型/业务同步规则不变。任务保存与取消原生行为已通过，完整 UI 结果见 TEST_PLAN/qa/results。

### Migration I / Design Gate：统一验证

文件：DESIGN_SYSTEM、UI_COPY、AGENTS、UI.xcstrings、StatusCopy、qa 审核/基线配置、audit/compare/run 脚本、Makefile、UIFixture、TogetherUITests、CHANGELOG 和其余文档。

Copy Audit 管理静态正文与精确哈希；新增或旧 key 改值未审核报错，主观冗长/重复 Warning。6 项 QA 工具测试通过。28-case 截图矩阵、原生行为测试和人工 approved 基线分开；Our Story 缺失显式跳过。没有人工批准基线时不称 Visual PASS。最终机器记录在 qa/results/summary.json。

下一步仅外部验收：Cloudflare 邮箱验证后部署/公网集成、两个实体 Mac 跨 Wi-Fi、独立安全审查、麦克风/系统 Reduce Motion 和人工候选截图审批。不擅自增加聊天、独立相册或业务功能。


## 部署跟进 — 邮箱验证完成

文件：Configuration/RelayService.json、generate_project.py、server/deployment.json、RelayTests、README/ARCHITECTURE/REQUIREMENTS/TEST_PLAN/CHANGELOG/server README。Worker/DO 上传和发布成功，公网 HTTP 200；双隔离原生客户端 HTTPS/WSS 测试通过（资料/愿望/任务、三内容礼物、原图头像/照片、音频、哈希确认、断线重连与磁盘恢复）。默认 App 构建自动使用真实 origin。

部署版本 d214ea2f-5034-4b1a-9f31-dca118b1b245。仍需实体两台 Mac 跨 Wi-Fi、硬件/权限、独立安全审查和人工视觉基线；没有离线信箱或公证声明。最终构建/质量入口记录见 TEST_PLAN 与 qa/results。


## 2026-10-10 · Our Plans / local identity follow-up

Files: RootView, OurPlansView, ApplicationModel / PlansNavigation, TaskListView / TaskEditorView / TaskEditorDraft, HomeView, WishesView / GrantDetailView, TogetherTheme, TogetherApp / StartupIdentityView; IdentityFileStore / DeviceIdentity / ReplicaEngine production bootstrap; catalogs/review, UI fixtures/tests, identity-file tests, QA scripts/config and rules/documentation.

Implemented: two main sidebar destinations, bottom utilities, native Tasks/Wishes and three shared task filters, one primary create action and shared editor/commands, Home routing, dated Wishes ledger/details, native state-preserving transitions, owner-only identity files with explicit existing-key migration. No schema, recurrence/projector, transport/protocol, daily gift quota or automatic-modal rule change.

Validation: 43 domain + 7 Workers + 6 tools + 10 UI = 66 PASS / 0 FAIL, 1 SKIP; 38 current screenshots REVIEW REQUIRED, Copy 0 errors / 35 warnings; Debug / Universal Release and 6 DMG checks PASS. Final UI: ui-20261010-131239.xcresult. Early failures and system-warning diagnostics remain recorded.

Open work: human visual baseline approval; real legacy-user Keychain migration consent; Developer ID/notarization, independent protocol review and physical two-Mac cross-Wi-Fi acceptance. Next work follows user review; no new business feature is added.


## 2026-10-10 · Plans / Wishes left sidebar correction

Files: RootView, OurPlansView, ApplicationModel, TogetherUITests, UI.xcstrings/review metadata; AGENTS, DESIGN_SYSTEM, UI_COPY, README, ARCHITECTURE, REQUIREMENTS, TEST_PLAN, CHANGELOG; current QA reports and before/after native captures.

Implemented: Plans and Wishes are separate vertically stacked native left sidebar rows. Removed the horizontal Tasks/Wishes picker; section is the navigation authority. Shared views preserve filters/search/positions and original task/wish actions, with Home routing to the right entry. No business, identity or networking changes.

Validation: 66 PASS / 0 FAIL, 1 SKIP; 38 captures REVIEW REQUIRED; Copy 0 Error / 35 Warning; Debug + Universal Release and six DMG checks PASS. UI evidence: ui-20261010-170246.xcresult. dist App and installer updated, version remains 0.0.1 Build 1.

Open work: human screenshot/animation review and existing notarization, independent security and physical two-Mac acceptance. Next work follows user review; no new feature is added.


## 2026-10-11 · Local app installation and duplicate cleanup

Files: scripts/install_local.py, Makefile, AGENTS, README, CHANGELOG, QA installation/verification records. Installed /Applications/Together.app and copied the current Universal DMG to Desktop. Removed only the inventoried generated App/Runner bundles and stale registrations; retained source, QA results and user data.

Checks: installed bundle and Desktop installer full hashes/signature PASS; source/DMG equality PASS; user-data metadata unchanged; one Launch Services registration and native NSWorkspace application URL confirmed. Quality tools 6 PASS. No new Swift build/UI run (same verified Release). Installation first caught a registration recreated by an indexer; the scoped post-removal pass resolved it and is now part of the helper.

Open work remains Developer ID/notarization and the previously documented independent security/physical two-Mac/human visual acceptance. Next release: make package, then make install to keep a single daily app entry.
