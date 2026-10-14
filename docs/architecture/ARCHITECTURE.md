# Together 0.2.1 Architecture

## Monorepo foundation

Source ownership and rollback are defined in [MONOREPO_MIGRATION.md](MONOREPO_MIGRATION.md). SwiftUI/Xcode resides in `apps/apple/macOS`, the TogetherCore package in `packages/together-core-swift`, C1 Worker in `services/relay`. Shared core remains macOS-tested and contains SwiftData/Network/AppKit adapters; this is not an iOS/watchOS compatibility claim. [Platform contracts](../../protocol/COMPATIBILITY.md) are Codable DTOs and operation envelopes, never SwiftData classes. App, device-sync and storage generations are separately recorded in `protocol/versions.json`. No runtime protocol/schema/identity/production service change accompanies directory movement.

## Finance boundary and storage

`packages/together-core-swift/Sources/TogetherCore/Finances` owns Money, calendar, models, projector, services and audit/reminders. `apps/apple/macOS/Sources/TogetherApp/Views/Finances` owns the three-tab workspace and common editors. No second expense store. Reserve balances, allocations, bill next occurrence and statistics are derived. LocalFinancialReviewState is recipient-local; private cards use LocalRecord and are never transmitted. Shared cycle/personal cycle/shared card metadata uses the existing log.

SwiftData physical schema remains byte-compatible in definition: OperationRecord (signed JSON), LocalRecord (local JSON), EntityRecord (rebuildable projection JSON). No destructive migration or schema deletion. The real old-source fixture stores profiles/avatar, tasks/recurrence, wishes/fulfillment, gifts/presentation, peer/route and identity; the new source opens it, validates original byte hashes and retains it after adding/reopening finance records. This verifies the compatible path, not a production-store migration performed on the user's Mac.

## Money and dates

Currency precision is the bundled SIX ISO 4217 List One, published 2026-09-17; 165 codes with numeric minor-unit precision 0–4. Input parsing is explicit, no binary floating-point accumulation. Monetary payloads encode minor units as decimal strings; amount snapshots keep original currency, actual/reference basis, frozen final CNY and optional immutable exchange quote. CNY uses Decimal plain rounding (half away from zero); non-CNY original entry must fit its currency precision. Individual magnitude is bounded at 90,000,000,000,000 minor units; checked Int64 sums report overflow rather than wrap. Actual CNY overrides a reference rate. Reference snapshots validate the calculated final amount. There is no network exchange-rate dependency.

CivilDate is year/month/day, FinanceMonth is Gregorian YYYY-MM. Bill rules explicitly store IANA zone, original recurrence day and optional minute; short months clamp each month independently. Financial cycles use half-open [start,end), next anchor is the clamped following month, and personal settings are keyed by owner UUID. Natural-month revisions are independent of financial cycles. Lifecycle revisions retain created instant and calendar date, so pausing future rules does not reverse a due instance. App startup and the existing 30-second clock reconcile missed occurrences; opt-in local UNCalendarNotificationTrigger reminders survive closing the App, subject to OS authorization.

## Log and convergence

New entity types: reserveEntry, dateEvent, expense, recurringBill, billRevision, billOccurrence, financeSettings, paymentMethod. Operation envelope/signature/authentication and transport are reused. Amount/payment snapshots are atomic fields; notes/title/category edits send only changed fields. Delete is a permanent Tombstone. Bill revisions are immutable auditable operations; invalid current-month defaults are diagnosed. A forecast override is not an actual Expense. Generated IDs are SHA-256 stable UUIDs of `finance-bill:<UPPERCASE bill UUID>:<YYYY-MM>`, with existing StableID version/variant normalization. Both devices may log a generation, but projection/statistics contain one logical instance. Late valid rule/forecast operations deterministically resolve unreviewed instances; reconciliation freezes accepted values. Future inactive candidates are skipped without changing already reviewed actual history.

FinanceChange derives real before/after data from validated operation history and caches it between changes. Remote Banner IDs and dismissed reminder IDs persist locally, not as partner approvals. No independent mutable remaining/balance counters. Cards never change funding source; owner permission protects personal settings and card writes. Already shared history stays auditable when sharing is disabled.

## Protocol compatibility and Android boundary

Production 0.2.1 DeviceDescriptor uses protocolVersion 3 with the same private key, UUIDs and space. Relay hello is signed with its descriptor; V2/V3 mismatch is rejected before operation exchange. Pinned identity matching ignores only the supported version upgrade, not device/user/public key/initial space. Saved V2 routes can reconnect with both upgraded V3 clients without an invitation. Workers routing accepts both versions and leaves existing Durable Objects intact; the legacy TCP adapter also rejects mixed clients.

The wire data is Codable JSON, not SwiftData objects. FinanceMoney minor-unit strings, ISO codes, CivilDate, user UUID allocation, explicit bill/month and rule effective month are platform-independent. Existing LogValue.data wraps canonical UTF-8 finance JSON in base64; a future Kotlin client must follow the existing signed-envelope canonicalization and uppercase UUID StableID scheme. See FINANCE_PROTOCOL.md. No Android code or C2 mailbox added.

## Retained architecture history

The remaining sections document preserved 0.0.1 services; updated version/finance semantics above take precedence.

# Together 0.0.1 架构

## 保留的数据与业务层

TogetherCore 包含 Codable 模型、SwiftData、签名日志、确定性投影、日历重复、愿望和礼物服务。TogetherApp 提供 SwiftUI、原生菜单/面板、录音、设计系统与引导。日志为事实来源，投影可重建；UserDefaults 仅用于 UI/引导。

未替换 SwiftData Schema，未清空或移动生产数据。新路由/确认/草稿/额度/展示状态使用原 LocalRecord 唯一键。长期 Ed25519 身份按最新要求改存本机 Identity 目录（700）内的 32 字节文件（600），deviceId/userId/initialSpaceId/公钥共同绑定。旧 Keychain 只供用户主动的一次性迁移；提交前核对已有本机签名操作，不自动换钥匙或清空数据。文件存储没有 Keychain 的秘密保护。

operationId 去重，同 ID 不同内容拒绝；排序为 Lamport、Device ID、Operation ID，字段独立合并。乱序/更新先于创建可重放，Tombstone 不复活。系统时钟不决定同步冲突胜负。

共同空间仍按原双方身份确定性生成，旧本地空间为已验证别名。Regular 从 RecurrenceRule 原 anchor 和时区计算，稳定下一实例 ID 去重；Flexible 未设 nextAt 不生成，future availableAt 重启恢复。

WishGrant/WishItem 分开，CivilDate 保留约定日；额度调整可审计，受益人确认才兑现，统计从唯一事件推导。超额或非法候选保留日志并标记冲突。

## Transport 与共同同步

SyncTransport 定义 connect/disconnect/send/receive、状态和错误。RelayWebSocketTransport 使用 URLSessionWebSocketTask，LegacyTailscaleTransport 保留 NWConnection 回归适配；业务服务不依赖 IP/NWConnection。

OperationLogSyncSession 是共同服务：日志 ID 双向交换、缺失请求、验签持久化、摘要收敛、资源请求/数据块/完成/验证/失败和礼物 receipt。旧 PeerService 保留原监听、挑战、同时连接去重，认证后调用同一服务，避免另写业务合并。

恢复时交换状态，既发送对方缺失项，也请求自身缺失项。socket send 不算收敛；即使摘要未变化，也正确释放 Syncing。

## 邀请、身份与自动重连

PairingService/RelayAPI 使用固定 HTTPS origin。Release HTTPS/WSS；Debug loopback 才可 HTTP。origin 不能带凭据、query、fragment 或路径；URLSession 拒绝重定向签名/ticket，HTTP 响应有界读取，保留系统 TLS 校验。

服务挑战为安全随机 32 字节 nonce、60 秒、一次使用；Ed25519 签名绑定域、nonce、method/path、正文 SHA-256 和 deviceId。邀请码为 12 位 base32、10 分钟、一次成功加入，错误/过期/已用统一报错，创建/尝试限速。

加入仅是 Pending Confirmation。双方核对签名 hello、校验码和指纹，各自签名 consent。旧配对须同时匹配原设备/用户/初始空间/公钥。服务器 paired 不能代替客户端签名确认。trusted peer 与 RelayBinding 同一本地事务保存，不建立重复空间。

重启读取绑定，无需邀请码。一次性 60 秒 socket ticket 在 Authorization header，每成员仅一个 socket；重连采用 1…60 秒退避，NWPathMonitor 网络恢复重置。对端离线显示 Waiting/Offline，不伪造 Connected；本地待同步操作保留。

## 应用层认证加密

签名 hello 绑定 Relay 协议 1、路由、业务协议 2 的原设备描述符、新鲜 X25519 ephemeral 公钥和 nonce。双方 canonical hello 按设备排序形成 SHA-256 transcript，consent 绑定 transcript。X25519 + HKDF-SHA256 派生独立双向 ChaChaPoly 密钥；AAD 绑定版本、会话、发送者/接收者、严格单调序号。

坏 tag、反射、重复、旧会话重放和序号异常拒绝；新连接/对端更换会话重新握手/换密钥。服务器只转发客户端加密的日志/愿望/礼物/资料/资源，不持有明文共享空间密钥。公开身份、声明昵称、流量和在线状态仍可见，服务可以拒绝/延迟/丢帧。

密码原语成熟不等于应用协议已经独立审查。未实现静态加密、自动长期换钥、Time Capsule 或 Noise/Signal 协议；详细状态见 SECURITY_REVIEW.md。

## Cloudflare 服务与媒体

Worker 的 ConnectionDirectory Durable Object 保存挑战、限速、邀请码哈希、双人公开路由/确认/ticket；RelayRoom 使用 hibernating WebSockets 和有界帧转发。事务确保 challenge/invite/ticket 一次消费、双方确认；alarm 清理过期临时记录。已配对公开路由至成员签名 revoke 才清理。

单帧 524,288 bytes、控制帧 8 KiB、每 socket 200 帧/秒，另受平台真实配额/吞吐限制；不是媒体总大小或分辨率上限。服务不存媒体/业务正文，没有离线队列；EncryptedMailbox 只是接口。

MediaStore 在受控 Media/assets/UUID 保存原图/音频、独立 thumbnail 和验证标记。路径由 UUID/允许格式生成，远端文件名仅显示。FileHandle 64 KiB 有界读写、流式 SHA-256；ImageIO 从 URL 验证/生成缓存，不全量加载巨图。目录 0700、文件 0600。裁剪仅保存显示参数，原始字节不变。

staged media/草稿只在本机。设置头像/确认发送才原子发布 manifest/reference。既有 stop-and-wait offset/chunk 协议经过认证加密 WebSocket；部分文件重连按实际长度恢复，长度/哈希/格式验证后提交，后台校验与约 10 Hz 进度节流。

Save Photo 仅 verified photo。NSSavePanel 用户选择目标，后台有界复制、复核哈希、原子提交，保留格式与内部原图；不会自动导出至公共目录。

## 礼物与启动展示

DateProvider 可注入，固定共享 IANA 时区的 Gregorian Calendar 产生 YYYY-MM-DD；时间归一到数据库毫秒精度。唯一额度槽 space:sender:day、manifest 和 gift.create 同事务保存，稳定 giftId，删除不退额度；同日候选按 Lamport 只选一个有效实体。

本地提交 Pending Sync；接收方持久化并校验全部附件，返回 creationOperationId/recipientId/准确附件哈希的认证 receipt，发送方保存后才 Synced，不等于已读。GiftPresentationState 独立本地持久，不因 Profile 更新或删除清空。

原生 File 菜单发送，Window 菜单查看历史，没有 Home/Sidebar 礼物模块。GiftLaunchPolicy 注入 Clock，15 秒启动同步窗口；已缓存且完整礼物不等网络，晚于窗口或用户已开始工作的新礼物留至下次启动。一次自动入口容纳多份礼物，密封时不构造私人内容/播放器，onAppear 才写 hasAutoPresented，Open 才写 openedAt。

ApplicationModel 的单 Sheet 队列：Initial Setup → Gift Reveal → What's New → Advisor。每日额度、Advisor 60 天和 Never Show Again 不变。关系文案统一 RelationshipLabel/LoveCopy，使用真实 sender Profile，未知 TA，不按当前用户反推伴侣身份。

## 质量门禁

DESIGN_SYSTEM/UI_COPY/AGENTS 是规则入口。UI.xcstrings + exact textSHA256 审核索引，新增 key 和旧 key 改文案都可追踪；审计不读用户数据库和媒体。

DEBUG UI fixture 显式开关、独立临时存储/偏好、固定 clock/locale/window，实际调用领域服务，不能在生产加载。行为、业务、文案、视觉分开报告。XCTest attachments 为截图来源，本次缺图不能用旧 candidates 补齐；人工 approved manifest 带哈希，自动检查缺失/修改/尺寸/像素差异，永不自动批准或覆盖。

当前 Sandbox 沿用 OFF，开启需另行本机目录/旧 Keychain 迁移验证；Debug / Release ad-hoc 签名，无公证声明。

## Our Plans presentation refactor

RootView 的 NavigationSplitView 主入口依次为 Home / Plans / Wishes，底部 Connection / Settings。Plans 与 Wishes 是两个左侧竖排选项，不提供横向模式切换。ApplicationModel 从当前 section 推导工作区模式，保留任务筛选、搜索及每个筛选最近操作的任务位置；两个工作区 View 共享稳定身份，切换不重建 ReplicaEngine 或数据库。任务使用原生 List / ScrollViewReader，切换模式时恢复仍存在的最近操作项，不将一个筛选的滚动锚点写入另一个筛选。TaskListView 只读取同一个 snapshot：Pending 为当前可执行未完成任务（含无日期及逾期），Upcoming 为有未来 dueAt 的未完成任务（含尚未 available 的实例），Completed 按 completedAt 倒序。没有独立 Upcoming / Completed CRUD。

工具栏、Command + N、Home 任务详情共同使用 AppSheet.task 与 TaskEditorView / TaskEditorDraft。完成开关调用原 setCompleted，Flexible 后续日期仍走原 NextTimeView；模型、RecurrenceCalculator、愿望投影与网络协议未变。Wishes 按日期分组真实 Grant，统计由原 balance 推导，GrantDetailView 复用原 WishItem 申请/确认/调整操作。Love Gift 菜单及自动模态策略不变。


## 已部署 origin

`Configuration/RelayService.json` 保存公开 HTTPS origin，generate_project 默认读取并生成显式 Configuration/Info.plist 模板，Target 采用该模板；verify_bundle.py 检查实际产物（仅 INFOPLIST_KEY 自定义 build setting 并不足以确保写入），环境变量可覆盖。没有 Cloudflare 密钥/密码。已部署 https://together-connection.together-connection-service.workers.dev，版本和健康检查证据见 server/deployment.json / TEST_PLAN。

原生 public integration 使用两个隔离身份/SwiftData 数据库，经实际 HTTPS/WSS 完成双确认、Profiles/Wishes/Tasks、三内容礼物、8200px 原图头像/照片、音频、校验/确认、离线合并和重开。此机公网路径不是双实体 Mac 跨 Wi-Fi。

## Final QA upgrade rehearsal (Build 3)

No physical SwiftData model, finance rule, wire protocol, pairing or production identity format was changed in final QA. DEBUG-only fixture sizing now waits for a real attached window; XCUITest verifies filtered-list layout before coordinate clicks. Native day/currency rows explicitly cover their full clickable area. Existing-store rehearsal is confined to owner-only temporary copies and reports aggregate hashes/counts, never keys or private contents. See qa/GIT_STORAGE_REVIEW.md for the unchanged external Git directory and proposed durable history migration.

Final QA found and corrected a client handshake lifecycle race, without changing the network architecture or packet format: a changed peer hello clears peer/session state while keeping the local connection's hello stable; a genuine disconnect rotates it once. Stale authentic consents grant no permissions. Path-monitor callbacks and cancelled senders cannot restart an ongoing session. See [qa/NETWORK_RECONNECT_REVIEW.md](../qa/reports/NETWORK_RECONNECT_REVIEW.md). Debug copied-store fixtures suppress restore independently of persisted RelayBinding addresses.
