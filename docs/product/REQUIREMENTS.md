# Repository migration scope and invitation requirement correction

This repository migration preserves all current runtime behavior. The formally required invitation lifetime is **8 hours**, one successful use. The current 10-minute implementation is an acknowledged legacy gap, not the final requirement. Correct it in a separate coordinated network-protocol PR (server calculation, client wording, specification and tests); deploy only after separate authorization. Do not change C1, identities or production Worker during the directory refactor.

# Together 0.2.1 — Our Finances

## 本版本优先约束

本节覆盖旧财务/导航设计冲突，原非财务规则保留。Marketing Version 0.2.1；Build 以 `apps/apple/macOS/Configuration/ReleaseVersion.json` 为准并递增。在独立 Git 分支开发，不覆盖已安装 App，不重置生产存储、身份、配对或日志。原版本源码由经过验证的 Git 历史保留。Our Story 未实现。

- Our Finances 仅 Reserves / Expenses / Recurring Bills 三 Tab；周期、付款工具放设置，AA 为付款方式。
- 唯一支出账本；约会/独立/周期实例通过同一服务 CRUD 和 Tombstone。共同支出只扣共同账户，个人/AA 不扣共同账户。
- 原币整数最小单位 + 固定 CNY 整数金额 + 可选汇率/来源/日历日期。实际 CNY 优先；Decimal 参考计算、人民币半入舍入。历史不重算。ISO 4217 货币精度可搜索滚轮复用。
- 开账余额/存款/撤销/修改保存历史，账户余额由有效流水推导，可为负。Provisional 同时列明待核对；核对/跳过更新原实例，不能重复扣账。
- 四种付款方式真实 userId；AA 50% 理论平分，最小单位余数给排序更小 UUID。分摊合计严格等于原币/CNY 总额，不创建债务。
- bill/month 稳定实例，日 1–31 按月末夹取，保留设定日；明确时区、Gregorian/DST 和重启补建。默认金额/付款版本下自然月生效，不使用财务周期替代自然月。
- 本期预计可在到期前修改；到期仅新增一条待核对 Expense。次日允许正确/修改/未发生；状态持久，未处理不反复强制弹窗。暂停/终止不撤销已经发生的账目。
- 共同/本人不同财务周期连续，无重叠；可读伴侣周期用于统计。发薪/计划存款日不生成流水。
- 卡片仅银行/名称/持有人/类型/后四位/可选币种/可见性；不存完整卡号/CVV/PIN/登录。个人档案不上共享日志；共享历史可审计，撤回可见性不能保证清除副本。
- 合法共享变更使用原签名操作、Lamport + Device ID + Operation ID 字段合并和原中继，不需要伴侣审批。远端存款/修改通知按操作 ID 本地去重，Banner 不代表银行验证。
- 双方升级设备协议 3 方可财务同步；长期身份/route/空间不变，服务继续支持旧协议 2。新旧客户端不兼容必须提示，不得清库或重新生成身份。
- 无汇率 API 强依赖、银行交易、债务追讨、Android、独立聊天/相册或新增中心数据库。

## 继承的 0.0.1 需求记录

以下保留作为原业务需求历史；财务和版本以本节为准。验收状态以 TEST_PLAN 和机器证据为准。

# Together v0.0.1 需求基线

## 产品与平台

- 原生 macOS，Swift / SwiftUI / SwiftData / Network.framework / Codable。
- 两名用户、每人一台 Mac；角色标签只用于显示，权限绑定用户和已确认设备密钥。
- 应用名称 Together，Bundle ID `com.together.app`，0.0.1 / Build 1，最低 macOS 14。
- 所有业务数据在 SwiftData 中保存；UserDefaults 只保存 UI 与引导偏好。

## 页面

NavigationSplitView：Home、Tasks、Upcoming、Wishes、Completed、Connection、Settings。
Help 提供 Together Advisor 与 What's New。未实现能力不显示为有效按钮。

## Profiles

独立 userId/deviceId/displayName/relationshipLabel/avatarAssetId/avatarCrop/updatedAt；仅可编辑自己的资料。原始 JPEG、PNG、HEIC 等图片完整保存于 Application Support，不设置人为大小、分辨率或像素数上限，不压缩原图。裁剪是独立显示参数，ImageIO 生成独立缩略图，默认圆形显示。原图走资源通道，Profile 文本和引用走操作日志。旧 avatarData 仅为历史小头像兼容。

## Tasks 与重复

创建、编辑标题/备注/负责人/截止日期、完成/取消完成、删除、筛选。删除为不可复活的 Tombstone。
独立 RecurrenceRule，支持 Daily、Weekly、Monthly 及 Every N days/weeks/months。以规则原定 anchorAt 及时区计算 occurrenceIndex，使用确定性的下一实例 taskId 避免重复生成。
Flexible Recurring 的 Set Next Time 进入日志。完成后可以立即选择下一次时间或稍后设置；未选择时不生成。未来实例使用 availableAt，重启时按当前时间恢复展示。

## Wishes

WishGrant 与 WishItem 分开建模。Grant 保存本次额度、约定日历日期、双方身份、真实创建时间与备注。约定日为 CivilDate，不按设备 UTC 转换日历日。
受益人填写愿望，兑现者申请完成，受益人确认后才兑现；确认去重且不可重复扣减。
调整额度为独立可审计操作；总额度、兑现和剩余额度从日志推导。按确定性顺序校验占用，超额/非法调整显示冲突并保留历史。

## 连接与同步（正式迁移修订）

正常用户只安装 Together，使用 12 位安全随机一次性邀请码（10 分钟）和双方明确身份确认配对；不要求安装 Tailscale、输入 IP/VPN/开放端口。Cloudflare Workers + Durable Objects 负责邀请、公开路由和实时转发，不判断业务状态或保存业务正文。

SyncTransport 抽象 connect/disconnect/send/receive/state/error；URLSessionWebSocketTask 提供 RelayWebSocketTransport，旧 PeerService、NWListener/NWConnection 与 LegacyTailscaleTransport 保留回归。双方确认、公钥绑定、认证握手、HTTPS/WSS、应用层认证加密与重放保护必须先于业务交换。设备私钥按最新需求存本机受限文件；旧身份需主动迁移，不得静默重置。Cloudflare 凭据不得进入 App 或仓库。

## UI refactor · Our Plans（2026-10-10）

按最新 UI 修订，主 Sidebar 为 Home / Plans / Wishes，左侧竖排两个工作区入口，底部 Connection / Settings；尚未实现的 Our Story 不显示。移除右侧横向 Tasks / Wishes 切换，工作区切换保留 UI 状态。Plans 使用 Pending / Upcoming / Completed 筛选共享 TaskListView，统一 TaskEditor 和原 ReplicaEngine CRUD。Pending 包括未设日期和逾期的可执行任务；Upcoming 必须为未来计划时间；Completed 按实际完成时间倒序。只有 Pending 显示主要 New Task，Command + N 复用相同编辑器。Home 摘要导航到相应模式/筛选，不复制完整工作区。

Wishes 继续双向额度统计、按日 Grant History 和记录详情中的具体愿望管理；不合并业务模型。没有 Love Gifts 常驻入口。Quick 180ms / Standard 280ms / Expressive 420ms，原生字体、浅深色与 Reduce Motion。此重构不修改 Schema、同步协议、Lamport、Recurrence/愿望/礼物/Advisor/版本的业务规则。

保存可信 RelayBinding，启动自动连接、指数退避、网络恢复重新同步。继续 UUID 去重、Lamport/Device ID 确定性合并、Tombstone、乱序恢复及原图分块。旧配对公钥和设备必须匹配，首次 Relay 绑定须双方确认，不重置用户数据或建立重复 SharedSpace。

只实现双方在线时转发。没有持久化加密邮箱或对象存储，不承诺发送者关闭后取得尚未同步礼物。未获远端持久化/媒体校验确认保持 Pending Sync。协议安全独立审查与真实不同 Wi-Fi 双 Mac 验收不能用模拟替代。

## Advisor / What's New

Advisor 七步：Welcome、Shared Tasks、Recurring Tasks、Wishes、Profiles & Avatars、Daily Love Gifts、Connecting Two Macs；Previous / Next / Skip / Finish / Never Show Again。
真正进程启动时先读取上次日期再更新，首次或相隔至少 60×24 小时展示；永久关闭只影响自动 Advisor，Help 始终可手动打开。
What's New 独立 Sheet 与结构化数据源；读取 Bundle 版本，升级时自动一次。首次先 Initial Setup；自动模态优先级为 Initial Setup → 已准备好的 Gift Reveal → What's New → Advisor，同一时刻只展示一个。Advisor 的 60 天与永久关闭规则保持不变。

## 视觉与图标

Warm Ivory / Soft Rose / Muted Gray；原生控件、适度 opacity/movement、180–450ms 微交互、spring 与 matchedGeometryEffect；遵循 Reduce Motion、Light/Dark Mode 和键盘操作。
图标为暖白底、玫瑰色饱满心形，无文字。检查 Icon Composer；无 MCP 时提供 SVG 与手动导入说明，图标集成必须经实际构建。

## 排除项

不实现 AI、支付、社交动态、中心云数据库、普通即时聊天、语音/视频通话、独立相册、多图媒体库、iOS/iPadOS、家庭多人、完整卸载器。媒体仅用于头像和每日礼物的一段语音、一张照片。

## 增量需求与冲突裁定（2026-10-10）

后续 Addendum 明确替换：原来的 512×512/128 KiB 头像上限、将媒体安排到未来版本的排除项、轻量 Love Notes 的自由发送语义、旧启动展示优先级。均以合并后的 Daily Love Gift 需求为准，保持 0.0.1 / Build 1。

用户已明确批准：称呼使用对方已验证的关系标签，未知用 TA，不根据自己标签反推对方；未知发送者纯附件标题用“一份小礼物”，有文字用“一份爱意”。该中性规则也用于未配对的头像提示，避免同标签情侣被错误称呼。

Wishes 禁止演示数据与虚构统计；统计从真实日志推导。Home 的 Upcoming 没有内容时隐藏整个卡片，Upcoming 页面没有情感说明或空状态提示。

## Initial Setup

独立五步 Welcome / Choose Your Role / Set Your Profile / Connect Your Partner / Your First Love Gift。身份不预选，只能主动选 boyfriend 或 girlfriend；昵称必填，头像可跳过；配对可稍后。未配对礼物只保存本地草稿，配对后必须用户确认发送。完成状态仅本机 UserDefaults 保存；升级后第一次补齐设置不清除旧业务数据。

## 关系标签与来源验证

统一 RelationshipLabel 解析 canonical boyfriend/girlfriend/unknown，trim、大小写及明确中文旧值映射；nil/空/无法识别/未来标签回退 unknown。双方同标签合法。异常只回退文案，Settings 提示重选，不重置任务、愿望、配对、额度或引导。

Gift Reveal 根据 senderId 查询当前已验证 Profile；Profile 暂缺用 TA，后续更新自动刷新。礼物必须匹配当前空间、当前接收者与已授权设备签名；错误身份拒绝并记录冲突，标签不作为认证依据。

## Daily Love Gift

每人每个共享日历日最多一份，支持文字（最多 4,000 字 / 16,000 UTF-8 bytes）、一个语音附件、一个照片附件的任意非空组合。草稿独立且只在本机；确认发送时附件清单、礼物创建与唯一额度槽在同一 SwiftData transaction 中保存。

唯一键 spaceId + senderId + dayKey；稳定 giftId、领域校验和持久化唯一槽避免重复点击/重启/网络失败重复发送。发送记录不可变，只能由发送者追加删除 Tombstone，删除不退额度。并发同日候选按 Lamport/device/operation 排序选唯一有效记录，冲突可诊断。

DateProvider 可注入；Date() 的系统时刻通过指定共享 IANA 时区的 Gregorian Calendar 得到 YYYY-MM-DD，不能用当地时区或滚动 24 小时。首次共享空间创建者的时区确定后固定并同步；双方各建本地空间时，由确定性排序的设备作为共同空间创建者。界面跨共享午夜和重新激活时刷新。时间回拨至早于历史发送日会拒绝，不能宣称完全防止手改系统时间。

## 媒体

原图完整保存，ImageIO 按 URL 读取/生成显示缓存，不将巨图整体读为 Data。导入前提示 GPS 等元数据隐私，保留原图意味着元数据也保留。

AVFoundation 录制 AAC/M4A，正确麦克风说明与授权、拒绝提示；可暂停、停止、导入、试听、移除草稿附件。接收者主动 Play/Pause，有进度和时长，不自动播放。导入音频保留原文件。

MediaAsset 的资源 ID、所有者、格式、原文件名、SHA-256、byteCount 与业务引用进日志；路径与 transferStatus 是本机受控状态。原始文件通过共同同步服务的独立资源消息传输，正常流程使用认证加密 Relay WebSocket，旧 TCP 保留回归；媒体采用，64 KiB 分块（不是总文件上限），支持部分文件 offset 恢复、进度、哈希/格式校验后提交；远端路径不用于文件操作。

## 确认与 Gift Reveal

草稿 Local；本地提交 Pending Sync；只有已验证对端完成持久化与所需附件校验后返回匹配的签名会话确认，才能 Synced，不使用 Delivered 或伪造已读状态。

启动时缓存或首次同步取得的完整礼物可自动展示；用户已开始工作后不强行打断，普通使用收到的新礼物保存至下次启动，不添加常驻展示区域。每次启动至多一个自动 Gift Reveal 入口，多天礼物在同一个界面切换。hasAutoPresented/autoPresentedAt/openedAt 本地 SwiftData 保存，真正呈现后才标记；关闭或 Profile 更新不重弹，历史可再次手动查看。

拆开后根据发送者标签及文字是否存在生成标题；依次展示真实文字、语音、照片与聊天引导，主要按钮“收到啦 ❤️”关闭，次要“回赠一份爱意 ♡”进入现有编辑器并占用回复者当天额度。没有聊天或外部聊天软件启动行为。遵循 Reduce Motion、Light/Dark 和单次微动画。

## Love Gift UX 正式修订

Love Gift 是事件驱动 Sheet，不是常驻页面。Home 移除卡片/欢迎区域，Sidebar 无 Love Gifts。File → Send Love Gift…（Command+Shift+L）发送成功自动关闭；Window → Love Gift History 仅主动打开。

启动检查完整本地礼物并尝试认证同步/附件下载，15 秒启动同步窗口防止无限等待；缓存礼物离线可展示，使用期间新礼物不打断编辑，下一次真正启动自动出现。密封状态不渲染任何私人内容，Open 后才构造实际文字、播放器和照片，语音不自动播放。

Save Photo 用 NSSavePanel 用户指定位置，仅导出已校验原图，不变格式/尺寸/字节，无自动公共导出。历史可以手动重看与再次保存；关闭不删除礼物/资源，不退额度，不重复自动展示。

## Design Quality Gate

DESIGN_SYSTEM.md / UI_COPY.md / AGENTS.md 长期约束所有原生页面。静态 UI 使用 String Catalog 和类别/原因/精确文字哈希审核索引；Error 阻止验收，主观冗长/重复文案 Warning 待人工审阅，不扫描或改写用户原创内容。

隔离 DEBUG fixtures 固定时间、语言、窗口，XCUITest 提供 Light/Dark、empty/populated、disconnected、sealed/opened、normal/reduced 截图和实际行为检查。新截图不是已批准基线，脚本不能覆盖 approved；明显未经批准差异失败，细微差异要求复核。Our Story/Time Capsule 未实现，缺失必须明确记录，不新增 Placeholder。

make qa 分开报告 Build、业务/服务/UI Tests、Copy QA、Visual QA 和 Security。成功编译不代替 UI/视觉验收；不可运行的项目必须 NOT RUN。

## 安全和验收边界

只接受两台已人工确认、认证设备的签名业务与资源。角色只影响文案，不认证身份。应用层会话加密机制已实现，仍需独立协议审查；没有静态加密或已实现离线邮箱。删除不能保证清除另存副本。系统时间不用于操作排序。

真实 localhost NWConnection/URLSession 测试不算不同 Wi-Fi 双 Mac。麦克风硬件、系统权限、实际两端跨网络、人工动画和截图基线批准需独立验收。部署权限与邮箱验证已完成；Cloudflare 服务实际上线，公网 HTTPS/WSS 集成已通过。它仍不等于真实双 Mac 跨 Wi-Fi 验收。

## Git-like C1 multi-device increment

Two stable partner User IDs may own independently authorized device keys in one existing SharedSpace. Add My Device is an owner-root authorization operation, separate from partner invitation. Preserve original key/identity/pins/space/logs. New replication 4/API 2 is an explicit opt-in capability; raw Protocol 3 facts keep their exact historic signed encoding and must not be silently reinterpreted.

New requirements are paged content/certificate anti-entropy, durable per-device ACK, deterministic old domain projection, local universal change review and directed encrypted C1 routing. Relay remains online-only, with no business ledger/media mailbox. Partner-synced means at least one active partner device persisted the operation; media receipt also requires hash verification. Reviewed and wish/domain confirmation remain separate.

Implementation, tested evidence and missing enrollment/recovery/deployment work are tracked in [GITLIKE_REPLICATION](../architecture/GITLIKE_REPLICATION.md) and [C1 QA](../qa/reports/GITLIKE_C1_QA.md), not inferred from this requirement text. Eight-hour invitation correction is independent PR #3; no production Worker deployment is authorized here.
