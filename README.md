# Together 0.0.1 · Build 1

原生 macOS 双人协作应用。SwiftUI、SwiftData、签名 Operation Log 与 Lamport 合并保持 Local-first。新连接流程使用原生邀请码配对和 Cloudflare 实时中继；正式用户不需要 Tailscale、IP、VPN 或路由器设置。服务不决定业务状态，不保存任务、愿望或媒体内容。

## 当前功能

- 左侧竖排 Home、Plans、Wishes，Connection 和 Settings 位于底部。Plans 通过 Pending / Upcoming / Completed 筛选同一份任务；Wishes 打开原额度账本，不再使用横向 Tasks / Wishes 切换；没有未实现的 Our Story 页面。
- Tasks 的唯一主要新建入口位于 Pending，Command + N 在各筛选复用同一个 TaskEditor。Home 仅保留摘要和最多三项 Upcoming、最近一笔愿望额度，摘要跳转到对应模式/筛选。
- Tasks CRUD、Tombstone、Regular / Flexible Recurring，按原日历计划计算下一实例。
- 分批愿望额度、可审计调整、申请与确认兑现、推导统计和并发冲突。
- 五步 Initial Setup、本人 Profile、统一关系标签回退、原图头像与非破坏性裁剪。
- 每人每个共享日历日一份 Love Gift，文字、一个音频、一个原图照片可任意非空组合；草稿仅本地，删除不退额度。
- 原生录音/导入/主动播放、流式哈希、64 KiB 分块与恢复，没有原图总大小或像素限制。
- File → Send Love Gift…（⌘⇧L），Window → Love Gift History；没有 Home 卡片或 Sidebar 礼物页。
- 合格新礼物在启动时密封展示，点击 Open 才显示文字/照片/播放器；使用中收到的礼物留至下一次启动自动展示。
- Save Photo 使用 NSSavePanel，只复制校验后的原图，格式、尺寸和字节不变。
- 邀请码、双方指纹/校验码确认、可信设备绑定、自动重连、应用层认证加密；复用日志与媒体同步。
- Advisor、What's New、Light/Dark、Reduce Motion；原有 60 天和每日额度规则保留。

## 构建与运行

需要 macOS 14+ 和可用 Xcode。当前 Xcode 27、macOS 27 SDK；Deployment Target 为 14.0。

```sh
cd 0.0.1
./script/build_and_run.sh --release-build-only
```

当前交付为 Release，日常入口为 `/Applications/Together.app`；普通 `--build-only` 保留 Debug 开发入口。构建暂存产物为 `0.0.1/dist/Together.app`，版本 0.0.1 / Build 1。完成 `make package` 后执行 `make install`，安装到 Applications、将最新 DMG 放到桌面，并清除生成的 App/测试 Runner 副本和失效启动注册；源码、安装包、QA 结果及用户数据保留。安装前需正常退出 Together；原目录的暂存 App 在安装成功后移除。当前 Debug / Release 均为 ad-hoc 签名，未完成 Developer ID 签名和公证。

公开服务 origin 已保存于 `0.0.1/Configuration/RelayService.json`，生成 `Configuration/Info.plist` 模板并实际写入 App 的 `TogetherRelayURL`；构建入口会核查产物中的地址和签名。开发者可用 `TOGETHER_RELAY_URL` 覆盖；正常用户不需要配置地址。默认服务：https://together-connection.together-connection-service.workers.dev。

## 安装包

在项目根目录执行 `make package`。入口先构建 Release，再生成 `0.0.1/dist/Together-0.0.1-Build1-Universal.dmg`，包含 Together.app、Applications 拖放快捷方式和安装说明。支持 Intel / Apple 芯片、macOS 14+。包内没有开发源码、测试数据或用户数据库；无需额外安装 Tailscale。

打开 DMG，将 Together.app 拖入 Applications 后，从 Applications 打开。本机也可以执行 `make install`：先核对 App 与 DMG 内完整文件清单/哈希，再安装并清理生成的副本；统一入口 `/Applications/Together.app`，桌面仅放安装 DMG，不额外生成说明或校验文件。重新打包不会修改已有用户数据。脚本实际校验 DMG 校验和、只读挂载后每个 App 文件的 SHA-256、可执行权限、签名、版本、服务 origin 和两种架构；项目中的 `.dmg.sha256` 与 `.json` 保存包哈希和验证结果。失败时不替换已有成功的安装包。

此包用于开发测试分发，尚未完成 Developer ID 签名及 Apple 公证，当前 Gatekeeper 评估拒绝。另一台 Mac 可能阻止首次打开：确认来源可信后，尝试打开，再在系统设置 → 隐私与安全性选择“仍要打开”。操作说明见 [Apple 官方文档](https://support.apple.com/zh-cn/102445)；不要关闭整个系统的 Gatekeeper。对无需手动允许的正式分发，需要 Developer ID Application 证书和公证授权。

## 开发验证

```sh
cd server
npm ci --legacy-peer-deps
npm run dev
```

另一个终端在项目根目录执行 `make qa`。项目专属 `.qa-runtime` 使用 Python 3.10+ 和固定 Pillow，不更改全局 Python。文案、工具、业务、Workers、原生构建、XCUITest 和视觉分别报告，机器结果在 `qa/results/summary.json`。

`make test` 运行 Swift Testing。本地 Workers 就绪后在 `0.0.1` 执行 `TOGETHER_RUN_RELAY_TESTS=1 swift test`；未启用时该集成测试明确跳过。`TOGETHER_RELAY_TEST_URL` 可选择已部署 origin；同机公网测试仍不是不同 Wi-Fi 双 Mac 验收。

规则：[AGENTS.md](AGENTS.md)、[DESIGN_SYSTEM.md](DESIGN_SYSTEM.md)、[UI_COPY.md](UI_COPY.md)。`qa/project.json` 选择版本目录，后续 0.1.2 及以上可复用。UI Tests 仅使用 DEBUG 显式开启的隔离临时数据库、媒体与偏好。截图进入 candidates；approved 基线须人工批准，脚本不会覆盖。

## 数据与迁移

生产数据保留于 `~/Library/Application Support/Together/`。SwiftData 日志/投影/LocalRecord 和 `Media/assets/<UUID>/` 原始文件不重建；UserDefaults 仅保存本机偏好。

按本次需求，长期设备身份私钥改存 `Identity/device-<deviceId>.key`，目录权限 700、文件权限 600。它是本机普通文件，没有钥匙串或额外静态加密保护；同一用户下能访问此文件的进程可取得该身份。新安装和已迁移设备的日常启动不访问 Keychain。旧版本已有日志、但缺少身份文件时，显示“迁移设备身份”；用户点击“迁移并继续”后才尝试读取旧钥匙串条目，可能需要一次系统授权。成功后保存完全相同的密钥并验证原日志签名，不改变指纹、SharedSpace、配对或业务数据。原密钥缺失、权限拒绝、损坏或不匹配时保留数据并报错，绝不静默换密钥；旧钥匙串条目不会自动删除。

旧 Tailscale 配对迁移须匹配已保存设备身份/公钥，并由双方明确确认首次 Relay 绑定。同一 SharedSpace 和操作日志保留，失败不清空数据。原 PeerService、NWListener/NWConnection 和 LegacyTailscaleTransport 保留回归；正常界面只用新的 PairingService。旧客户端需双方升级，不静默替换身份。

## 服务和边界

本地/部署/故障步骤见 [server/README.md](server/README.md)。OAuth 凭据在仓库外加密保存、密钥在 macOS Keychain；客户端不含 Cloudflare 密码或 API 密钥。邮箱验证后已实际部署，公网 `/health` 为 HTTP 200。两个隔离原生客户端通过 HTTPS/WSS 已验证邀请码/双方确认、资料与愿望、加密礼物、原图头像/照片及音频分块、确认与重连。验证状态见 [TEST_PLAN.md](TEST_PLAN.md) 和 `qa/results`。

实时转发没有 Encrypted Mailbox：发送方关闭后，接收方不能取得尚未同步内容。Pending Sync 只有远端持久化和所有附件校验确认后才为 Synced，不代表已读。原图可能含 GPS 元数据，导入前提示；保存仅由用户主动操作。

Ed25519、X25519、HKDF-SHA256、ChaChaPoly 和重放保护已实现并测试；应用协议仍需独立安全审查，见 [SECURITY_REVIEW.md](SECURITY_REVIEW.md)。不声称静态加密或已审查的 Noise/Signal 协议。

Sandbox 保持原有 OFF，网络/音频/文件选择 entitlement 和麦克风声明已配置；开启 Sandbox 需另行迁移验证。系统 iOS CoreDevice/CoreSimulator 插件不匹配提示不影响已验证的 macOS 构建，本任务未修复系统环境。

实体双 Mac 跨 Wi-Fi、麦克风硬件/权限、人工动画与截图基线仍需验收。Our Story / Time Capsule 未实现，不用 Mock 补齐。已有 SVG、PNG 预览和 Asset Catalog 图标，未虚构 Icon Composer `.icon` 导出。

界面前后对照：[PLANS_SIDEBAR_REVIEW.md](qa/visual/PLANS_SIDEBAR_REVIEW.md)。导航迭代 66 项自动化通过、1 项跳过；38 张实际截图待人工批准。最新左侧 Plans / Wishes 竖排界面已安装到 `/Applications/Together.app`；退出旧进程后从 Applications 打开。安装/清理验证见 `qa/results/local-install.json`。

更多：[REQUIREMENTS.md](REQUIREMENTS.md)、[ARCHITECTURE.md](ARCHITECTURE.md)、[TEST_PLAN.md](TEST_PLAN.md)、[PHASES.md](PHASES.md)、[CHANGELOG.md](CHANGELOG.md)。
