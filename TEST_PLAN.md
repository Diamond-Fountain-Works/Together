## Final QA status — 0.2.1 Build 4

See [qa/FINAL_QA_BUILD4.md](qa/FINAL_QA_BUILD4.md). Final business suite: 77 PASS / 0 FAIL / 1 SKIP, with the skipped actual-store-copy case separately PASS. Final full UI suite: 12 PASS / 1 FAIL / 1 SKIP; disappearing input-candidate AX reference persists. Visual 67/68, not approved. Release/DMG PASS, get-task-allow absent, not notarized. NOT READY FOR LOCAL INSTALL.

## Historical Build 2 run (2026-10-14; superseded by Build 3 final QA)

Business + actual legacy-store upgrade: **77 PASS, 0 FAIL, 0 SKIP** with local relay enabled. Workers: **8 PASS**; quality tools: **6 PASS**. Native Debug and Universal Release/DMG built; public native relay integration: **2 PASS** on this Mac, including preserved V2 route -> V3 upgrade.

Copy: **WARN, 0 errors / 58 warnings** (long legacy guidance and translation-context duplicates). XCUITest: **14 NOT RUN** because macOS automation mode initialization timed out before any case. Detail renderer: **14 usable / 4 incomplete**; manual Settings/close/day-wheel/currency/save checks recorded. **Visual REVIEW REQUIRED**, no approved baseline. OS notification delivery and physical dual-Mac/different-WiFi acceptance pending. Installed 0.0.1 Build 1 binary hash remains unchanged. No production database was opened by test fixtures. See qa/results/finance-delivery.json, summary.json, finance-public-relay.log and finance-package.log.

# Together 0.2.1 — Finance Acceptance

## Separate evidence

Report native build, monetary/domain unit tests, real local Workers integration, actual old-code store upgrade, UI behavior, copy, own-view rendering and physical dual-Mac networking separately. Production Application Support and /Applications are not test fixtures.

`TOGETHER_RUN_RELAY_TESTS=1 python3 scripts/run_finance_migration_test.py --all-tests` creates a private real 0.0.1 store and runs new code against it plus local native WebSocket clients. `make qa` records reproducible results. Each run's actual logs, return codes and counts belong in qa/results; no earlier PASS replaces current evidence.

## Finance automated coverage

- Decimal/checked integers, actual CNY priority, FX snapshot validation, ISO precision, AA stable odd-unit allocation and conserved totals.
- Opening/deposits/revokes, four funding methods, negative balances, shared/date/standalone unique Expenses, per-category/period/participant statistics.
- 31-day clamp and leap year, DST and continuous shared/personal cycles; no bill means no generation/reminder.
- Next natural-month amount/payment revisions, sparse concurrent field edits, per-period override, late offline revisions, historical FX immutability.
- Due Provisional, pre-due forecast without actual record, confirm/edit/skip without second expense, pause/resume/termination preserving past history, future candidates suppressed, offline simultaneous logical instance deduplication.
- Signed invalid/foreign-owner changes rejected, rule history immutable, cards last-four only/private not logged/source independent; genuine before/after changes and local reminder presentation persistence.
- Two real native local WebSocket clients: invite/consent, finance/profile/tasks/wishes/media, offline edits, reconnect, disk reopen. Separate V2 saved route -> V3 reconnect uses the same key/route/space without new pairing.
- Actual old source writes a store; new source verifies all original signed-operation byte hashes, key files/public fingerprint, peer/route, task recurrence, wish fulfillment, avatar, gift content and once-only reveal state; finance/private card/review state survive restart.

## UI and rendering

Native UI tests add tabs/one create action/actual expense/invalid inputs/currency reset, provisional confirmation, settings dismissal and 18 finance screenshot cases. Original product behavior tests remain. XCUITest automation initialization failures are environment NOT RUN, not passes. Fallback `scripts/capture_finance_views.py` captures only a Debug fixture's own AppKit content view in light/dark, empty/populated, offline and compact/reduced conditions. This is separate from UI behavior tests and uses no production data. Candidate hashes require human approval; the script never replaces approved baseline images.

Manually check the currency wheel with scroll, trackpad and arrow keys; no old amount reuse. Check tab transitions, long names/amounts, compact layout, primary buttons and closable sheets. Review changes in exact locations, not adjectives. System notification delivery while the App is closed requires opt-in permission and manual hardware/OS acceptance; core schedule/calendar logic is tested independently.

## Physical two-Mac test — NOT INFERRED from localhost or one Mac

1. Install the same reviewed 0.2.1 build on both Macs only after explicit installation approval. Verify saved data/pins before and after. Do not reset a store to fix a failure.
2. Different Wi-Fi, no Tailscale. Both must first reach `https://together-connection.together-connection-service.workers.dev/health` in Safari and see protocol 3 listed. A failed DNS/TLS/HTTP route must be repaired before pairing acceptance. The other Mac previously could not reach this origin.
3. Existing paired machines relaunch: no new invitation, same fingerprints/space/route. New users perform normal invitation and mutual verification. Mixed V2/V3 clients show upgrade error, retain offline data.
4. Each add a deposit offline, then reconnect; both records and derived balances match. Online add a deposit and observe one non-bank Banner on the peer. Reconnect/restart does not re-notify that operation.
5. Create shared/own/partner/AA expenses (including odd cents and JPY), DateEvent and standalone records. Verify total = personal shares + reserves and repeated frames do not inflate it. Concurrent title/notes and same-amount edits converge.
6. Add a monthly bill with original currency/actual CNY, day 31, defined zone. Change default before/after due; only next natural month changes. Simulate date with test clock only in isolated fixture, never change the real system clock/data for tests.
7. Let both Apps generate the same occurrence; one Expense, one shared balance deduction. Confirm keeps amount, edit adjusts same ID, skip reverses its impact, next month remains active. Pause/terminate only future occurrences.
8. Verify cycle boundaries in two zones, personal/shared differences, reference rates never rewrite history, shared/private card visibility, and locally-only planned dates do not create deposits.
9. Close/reopen both; finance, original Tasks/Wishes/Gifts, media, keys, route and local notification state remain. Check light/dark/reduced motion/window resize on each.

## Preserved 0.0.1 test history

The following historical records describe prior runs, not proof that this new version passed those UI or physical tests.

# Together 0.0.1 测试与验收

## 分开报告

Build、Swift 业务测试、Workers 服务测试、XCUITest 行为、Copy QA、Visual QA 和 Security 分开。编译不等于 UI 验收，localhost/同机公网不等于两个实体 Mac 跨 Wi-Fi。

机器证据：`qa/results/summary.json`、`business.log`、`server-tests.log`、`ui.json`/时间戳 `.xcresult`、`copy.json`、`visual.json`。本轮结果完成后更新下方记录，未经执行不写 PASS。

## 自动化

- 原 30 项覆盖日志乱序/去重/字段冲突/Tombstone，双向离线任务，Recurrence 只生成一次、月末/DST/Flexible，3+2 愿望历史/确认/调整/超额，Profile/原图/持久化，礼物组合/每日额度/时区/回复/删除/重开，Advisor/版本优先级，真实本机 TCP/资源恢复与确认。
- 新 7 项覆盖认证加密篡改/重放/反射/旧会话、伪造 hello/pin/consent、迁移原任务/愿望/同空间/拒绝替换、晚同步/缓存启动、有界服务 origin/离线安全、原图导出、实际本地及公网 Workers + 原生 URLSession WebSocket，资料/愿望确认/任务/三内容礼物/原图头像、照片及音频分块/receipt/断线重连/重开。
- Workers 7 项在真实本地运行时覆盖邀请加入、期限/已使用、并发消费、签名挑战、限速、身份迁移 pin、双方同 transcript 确认、一次性 ticket、非法来源和配对前密文拒绝。详细断言见 server/test。
- QA 工具 6 项验证未注册可见字面量、旧 key 改文案不能沿用审核、用户数据/注释不扫描、真实输入 placeholder 不误报为 Mock、视觉全部 case、相同/小差异/明显差异/尺寸改变。

本地服务：`cd server && npm ci --legacy-peer-deps && npm run dev`。在 `0.0.1` 执行 `TOGETHER_RUN_RELAY_TESTS=1 swift test`；未启用明确跳过。独立服务测试 `npm run check && npm test`。

统一入口根目录 `make qa`。QA Python 是项目 `.qa-runtime`，Pillow 固定版本。Swift 和服务测试不读取生产数据库。

## 原生 UI 与截图

TogetherUITests 是真正的 macOS UI Test Target；TogetherNative 是 App target，产品仍 Together。DEBUG `--ui-testing` 使用私有临时根目录、独立 SwiftData/媒体/偏好，绝不回退生产路径。固定 clock 2026-10-09T04:00:00Z、zh-Hans/zh_CN、窗口内容 1100×760 pt。

行为：导航、无常驻礼物 UI、真实新建任务/取消、菜单编辑器/空内容禁发、密封隐私/主动播放器/可关闭/一次自动模态、发送 Pending Sync/当日再发禁止、历史重开、缓存离线重启不重弹、NSSavePanel 原图字节 SHA-256。

XCTest 保留 attachments 为证据。普通页面 Home/Tasks/Wishes/菜单礼物编辑器/Settings × Light/Dark × empty/populated（disconnected）20 张；Reveal × Light/Dark × normal/reduced × sealed/opened 8 张，共 28 张。Reduced Motion 通过与系统设置相同的 MotionPreference 分支测试覆盖，未修改用户系统设置；真实系统设置人工验收另列。

Our Story/Time Capsule 无实现，测试显式 SKIP，缺失截图不以 Mock 替代。新图为 candidates；approved manifest 当前没有人工批准基线，必须 REVIEW REQUIRED。本轮缺图失败，不能沿用旧 candidate。基准文件/哈希变化、尺寸改变或超过 2% 像素明显差异 FAIL；小差异报告 bounding box 要求复核。绝不自动覆盖基准。

## 两台实体 Mac 的 Relay 验收（尚未执行）

1. 完成 Cloudflare 邮箱验证及真实部署，检查 HTTPS /health 返回 protocol 1、realtime-only；把该 origin 编入两端 App。服务故障时先确认本地数据仍可操作。
2. 两台 Mac 位于不同 Wi-Fi，退出 Tailscale/VPN，不开放路由器端口。安装同版本 App，保留已有数据库；新用户分别完成主动身份/昵称选择，可导入 JPEG/PNG/HEIC 原图。
3. A 创建邀请码，B 输入。核对双方设备指纹和一致校验码；只一端确认时不建立永久授权、不交换业务。双方确认后显示 Connected/Syncing，稳定后 Connected。
4. 对已过期、使用过、错误邀请码操作，观察拒绝/限速；不能重复使用、篡改设备 ID/签名或未经授权接管旧共享空间。
5. 旧 Tailscale 已配对两端升级：记录原 spaceId、任务/愿望/礼物/原图哈希；首次 Relay 绑定双方明确确认，升级/重开后全部保留同空间，错误设备不能替换。
6. 双方分别创建任务、离线新增不同任务/编辑不同字段，恢复网络后全部保留；同字段冲突收敛；重复日志不重复创建，删除不复活。服务不裁判业务状态。
7. 每端每日一礼物：分别测试文字、纯音频、纯照片、三种组合；本地提交 Pending Sync。对端退出时不能 Synced。收到全部日志/附件验证后才 Synced，无 Delivered/已读伪造。
8. 录音真实申请麦克风权限，拒绝提示；录制/暂停/停止/试听/导入原音频，接收者 Open 后主动播放/暂停/进度正常，不自动播放。
9. 大 JPEG/PNG/HEIC 头像/照片记录原字节大小/像素/SHA-256；检查多块进度，中断后恢复或安全重试，损坏块/磁盘不足/格式错误可诊断，完成后原哈希一致。
10. A 发送并在 B 完成同步前退出，B 不能取得尚未同步内容；再次双方在线才恢复。不能将 realtime-only 描述成离线 mailbox。
11. B 已缓存完整未展示礼物，断网重启仍密封自动展示；第一次启动同步窗口内收到完整礼物可展示。启动不被网络无限阻塞。
12. B 编辑任务期间同步收到新礼物，不抢编辑 Sheet；下一次真实进程启动才自动 Reveal。关闭或 Profile 更新/重复同步不会重新弹出。
13. 密封时 pixels/AX 不暴露文字、播放器或图片；Open 后按真实 sender Profile 使用男友/女友/TA 文案，附件标题准确，未知标签不隐藏合法内容。
14. NSSavePanel 用户指定私有测试目录；导出与内部原图 SHA-256/格式/像素一致。取消/失败不动内部原图，不自动写 Downloads/Photos。历史可再次打开并保存。
15. Reply 使用回复者当天额度，删除不退额度；两端不同本机时区按固定共享时区同一天，跨午夜长运行刷新、DST 正确。
16. 初始设置/礼物/版本/Advisor 按优先级单一自动模态；60 天与 Never Show Again 独立。Light/Dark、系统 Reduce Motion、键盘和 VoiceOver 操作可达。
17. 同时重启自动连接，无再输入邀请码；断网退避、网络恢复同步；对端独自离线或服务关闭不误报在线或丢待同步操作。

## Legacy 回归

PeerService TCP tests 继续运行。真实 Tailscale/MagicDNS 回归需另行双端授权安装和可达性测试；它不是正式用户要求。每端旧 NWListener 默认 58431，确认系统防火墙和 tailnet 策略允许入站/出站；两端使用保存可信身份重开。没有实际两台 Mac 就不能填写 PASS。

## 安全与发布门槛

独立应用协议审查（transcript/KDF/consent/reconnect/migration/恶意 relay/控制帧/身份丢失恢复）、真实跨网络、Cloudflare 平台配额/成本与 TLS、Developer ID/公证不由本地单测替代。Sandbox 当前 OFF，入站/出站、音频、用户文件 entitlement 已核查；开启需数据/Keychain 迁移验证。

部署 2026-10-10：第一次被邮箱未验证（10034）拒绝，随后用户完成验证，真实部署和 HTTPS/WSS 检查已通过；真实跨 Wi-Fi 双 Mac 仍未执行。


## 本轮实际结果（2026-10-10）

- Native Debug / Release Build：PASS，Bundle 0.0.1 / Build 1，codesign strict 校验通过，UI/InfoPlist String Catalog 均实际编入 App。
- Swift Testing：37 PASS / 0 FAIL，含实际 localhost Workers + URLSession 加密日志/媒体/重连；旧 TCP 回归保留。
- Workers：TypeScript check PASS，7 PASS / 0 FAIL。
- QA 工具：6 PASS / 0 FAIL。
- XCUITest：7 PASS / 0 FAIL / 1 SKIP（Our Story 未实现）。原图 NSSavePanel、SHA-256、重启只展示一次、历史重开、菜单发送/额度/Pending Sync、密封隐私与可关闭 Sheet 实际执行。
- Copy QA：WARN，0 Error / 34 Warning，主要是既有长说明、重复文案和人工安全文案复核；没有自动截断用户内容。
- Visual QA：REVIEW REQUIRED，28 张本轮原生截图全部捕获，尚无人工批准基线。已检查空 Home 和 Dark Reveal 候选；原图保存/结束提示在三种内容较长时需滚动，底部接收按钮保持可达。
- Security：机制测试 PASS，独立协议审查未完成。Cloudflare 邮箱验证/部署已完成；真实跨 Wi-Fi 双 Mac 和麦克风硬件 NOT RUN。

最后通过的 UI 证据：`qa/results/ui-20261010-101158.xcresult`。本轮 UI 保存面板的确定性初始目录通过 fixture 注入；生产默认仍由用户选择，未增加系统目录权限。测试曾因错误 native button selector 和 Runner 沙盒目录被拒绝而失败，已按原生 OKButton 标识及测试自身目录修正并完整重跑通过，不隐藏历史失败日志。


## 公网部署验收跟进

Origin：https://together-connection.together-connection-service.workers.dev。Worker Version ID：d214ea2f-5034-4b1a-9f31-dca118b1b245；健康 HTTP 200，protocol 1 / realtime-only。

公网 native integration 实际通过：1 Test / 0 Failure（23.874 秒），两个隔离身份和 SwiftData/媒体目录，HTTPS 认证/邀请码/双方核对确认，Profiles、WishGrant/WishItem 申请/确认、任务与离线合并、8200px 原始头像/照片、语音+照片+文字、分块 SHA-256、匹配 receipt、重连与重开。原图仍无人工尺寸上限。日志 qa/results/relay-public-integration.log；一次先行基础用例也通过，不累加为不同测试。

App 配置在 Configuration/RelayService.json，显式 Info.plist 模板保留自定义 origin，build_and_run 自动核查实际 bundle，防止自定义 INFOPLIST_KEY 被 Xcode 忽略。每次默认构建/Run 都复用实际服务地址，普通用户无需地址设置。业务与生产数据没有清空。

当前完整质量门禁保持 37 业务 + 7 Workers + 6 工具 + 7 UI PASS，1 UI SKIP（Our Story）；另有 1 次公网同用例执行 PASS。Visual 28 本轮截图 REVIEW REQUIRED，Copy 0 Error / 34 Warning。不是双实体 Mac、两个 Wi-Fi 的验收，也不是独立安全评审或离线信箱交付。

最终 Debug / Release 均实际构建并通过实际 origin/版本/签名验证；交付 dist/Together.app 为 Release，默认 Run 的 Debug 同样保留公网配置。未进行 Developer ID 公证。

## 安装包验收

`make package` 重新构建 Release，验证 dist 与 Release 文件完全一致，生成压缩 DMG 后实际校验映像并只读挂载。必须通过挂载 App 的逐文件 SHA-256 / 可执行权限、Bundle 元数据/签名、Intel/arm64 架构和 Applications 快捷方式检查。证据为 `0.0.1/dist/Together-0.0.1-Build1-Universal.json` 和对应 `.dmg.sha256`。

打包 PASS 与 Gatekeeper / 公证结果独立。当前 ad-hoc 包的 Gatekeeper 为 REJECTED、Notarization 为 NOT RUN；不能宣称另一台 Mac 无提示直接打开。实体第二台 Mac 安装、升级保留数据及不同 Wi-Fi 配对同步仍须按上方步骤实际验收。

2026-10-10 实际执行：`make qa` 57 PASS / 0 FAIL / 1 SKIP，Copy 0 Error / 34 Warning，28 张截图 REVIEW REQUIRED；UI 证据 `qa/results/ui-20261010-110707.xcresult`。随后 `make package` Release Build 和 6 项映像/挂载文件/元数据/签名/架构/安装入口检查 PASS，生成 3,833,344 字节（3.66 MiB）DMG。未运行第二台实体 Mac 安装或 Apple 公证。


## Our Plans / identity-file refactor acceptance

新增领域测试 6 项：新安装/重启不调用 Keychain，700/600 权限；旧身份仅主动迁移；拒绝/缺失不换钥匙；一次迁移保留原 32 字节；损坏/不匹配不覆盖；并发创建收敛于同一文件；真实 SwiftData 重开保留任务/愿望/配对。真实用户旧 Keychain 授权不是 stub 测试可以代替的验收。

新增 UI 流程：旧 Tasks / Upcoming / Completed 顶层入口消失，最新 Plans / Wishes 在左侧竖排，无横向模式 Picker；验证两个入口的位置与可点击性、三个原生任务筛选；无日期/逾期/12 天后计划/已完成记录来自同一 fixture 数据源；Upcoming/Completed 无 New Task，Command + N 仍打开同一编辑器；完成状态保存后跨筛选更新；搜索/筛选状态保留，Home 摘要路由正确；真实日期 Grant History、详情与关闭；900×620 的小窗口和 Reduce Motion。

当前截图矩阵扩展至 38：7 个 ordinary contexts × light/dark × empty/populated = 28，Gift Reveal 8，compact/reduced Tasks / Wishes 2。Tasks / Upcoming / Completed 是 Plans 内的筛选；Wishes 是相邻的左侧竖排入口，复用原愿望账本和稳定工作区 View；不恢复独立 Upcoming / Completed Sidebar。修改前的 28 张实际 XCTest 截图保留于 qa/results/our-plans-before，来自 ui-20261010-110707.xcresult，作为变更对照而非人工批准基线。后续完整新结果在 qa/results/summary.json 与对应 xcresult；未经实际完成不写 PASS。

迭代中发现并记录：原生 Picker 为 RadioGroup；父容器 accessibilityIdentifier 覆盖 Grant Close；自定义滚动定位/几何动画导致元素点击坐标不可用。任务使用原生 List、原生筛选 Picker 和原生 Sheet，工作区按最新需求改为左侧竖排导航；所有仍要求实际点击通过，不使用跳过代替。


UI 验证补充：系统曾阻挡测试 Runner 对 Documents 的访问，导致虚假的无效点击坐标和输入失败。截图改为仅保留 XCTest attachments，由命令行导出；UI QA DerivedData 位于 ~/.cache/Together/UIQA-DerivedData，生产构建仍在版本目录。测试只对明确属于 TogetherUITests-Runner / Documents / automated testing 的请求选择“不允许”，不授予新目录权限。误定位的几何/滚动实现已收敛为原生 List / Picker / Sheet，并保持两个工作区 View 的稳定身份，模式切换不重建数据。自动化失败和临时诊断日志均保留，最后结果单独记录。


### Final Our Plans results

43 Core + 7 Workers + 6 tools + 10 UI = 66 PASS / 0 FAIL; 1 UI SKIP (Our Story absent). Final UI evidence `/Users/giga_fortress0/Documents/ProjectsLocal/Together/qa/results/ui-20261010-131239.xcresult`. 38 current captures REVIEW REQUIRED, Copy 0 Error / 35 Warning. Universal Release build and mounted DMG artifact checks PASS. Actual user Keychain migration, independent security review, notarization and second physical Mac remain unverified; no user data was reset.


### Vertical Plans / Wishes follow-up — actual results

Latest correction uses two vertically stacked left sidebar destinations, removes the horizontal mode Picker, and derives the workspace mode from selected section to avoid conflicting navigation state. The shared views retain stable identity across the two selections. Existing filters, editor, grant ledger and Home routes remain.

43 Core + 7 Workers + 6 tools + 10 UI = 66 PASS / 0 FAIL, 1 UI SKIP. Current complete UI result: `/Users/giga_fortress0/Documents/ProjectsLocal/Together/qa/results/ui-20261010-170246.xcresult`. All 38 current captures available; Visual REVIEW REQUIRED, Copy 0 Error / 35 Warning. Debug, Universal Release and six mounted DMG checks PASS. Before/after review: qa/visual/PLANS_SIDEBAR_REVIEW.md. No approved screenshot was replaced and no user data was modified.

## 0.2.1 Build 3 final QA

- Run `make qa` for separate quality-tool, copy, server, signed-business/migration, native Debug build, XCUITest and visual reports. Swift Testing skipped cases are reported separately from passes.
- XCUITest must execute all 14 methods; the absent Our Story case is an explicit skip, never a passed placeholder. Currency tests wait for the filtered result set before resolving a moved row. Compact captures assert a real 900pt window. Personal cycle tests wait for its stored day to be visible.
- The expanded native capture matrix has 68 required images, including the three financial tabs at compact width, bill editors, currency popovers and personal Financial Cycle settings. Four previously incomplete financial settings images are replaced by opaque native XCTest window captures; fallback rasterizations are not used as acceptance evidence.
- `scripts/run_finance_migration_test.py` uses untouched 0.0.1 source to generate an isolated populated old store, including signed history, profiles/avatar, recurrence/tasks, grant/fulfilled wish, cached gift/presentation state and pinned peer/relay binding. Verify repeated operation replay is a no-op and reopening with an existing identity file never requires Keychain migration again.
- `scripts/run_existing_store_upgrade.py --app <Debug Together.app>` copies the quiescent existing store, WAL/SHM, identity and media to a private temporary directory. Old-code audit and three new-code reopens compare hashes of all original entities/local records and signed operations; two actual Debug app processes open the same copy. Production source fingerprints must remain identical. No original SwiftData store or Keychain is opened for writing.
- Native real-WebSocket local Worker integration and optional public Relay tests are one-Mac checks. Real two-Mac/different-Wi-Fi acceptance is separate and still requires both machines to reach `/health` and run protocol-3 clients. No offline delivery claim.
- `make package` is last, after all native builds/tests, because Debug builds also copy their bundle into project `dist`. Build 3 must have its own DMG, checksum and bundle manifest; do not replace Applications.
- Human-approved baselines remain immutable. With an empty approval manifest, complete screenshots still require human review; no automatic baseline approval or Visual PASS.

Build 3 supplementary verification: currency fixtures commit exact queries through native paste while preserving the clipboard, rather than switching the user's Pinyin input method. Native sheet/popover captures include complete owned elements even when their bounds extend outside the compact parent window. A focused capture report can be selected with `compare_visuals.py --capture-report qa/results/ui-visual-capture.json`; this does not combine old candidate files into a current run. Client reconnect lifecycle corrections, unchanged crypto checks and real repeated-reconnect evidence are documented in qa/NETWORK_RECONNECT_REVIEW.md.

## Build 4 input-method final acceptance

- Record HIToolbox current/selected/configured input sources and symbolic input shortcuts before an authorized temporary switch. ABC is a comparison condition, never a Together runtime requirement. Use native UI to switch; do not rewrite preferences or remove IMEs.
- Save full ABC/Pinyin result bundles/logs; restore Pinyin and verify actual active source plus all configured keyboard sources/hotkeys, including when a test fails. Nonkeyboard system helper registrations must be disclosed separately.
- The original 14 UI methods remain; an additional focused current-input-method currency case checks Latin JPY and Chinese 日元 in light/dark. Wait for the live input-dialog query to settle before fresh currency-row lookup. Persistent dialogs fail rather than receive automatic permissions. No JPY, business-status, sealed-privacy or closure assertion is waived.
- Use a complete post-fix Pinyin suite for final acceptance. A focused pass or an ABC pass alone cannot clear the original full-suite failure. See [qa/INPUT_METHOD_REVIEW_BUILD4.md](qa/INPUT_METHOD_REVIEW_BUILD4.md).
- Git all-refs backup is verified in durable Documents storage; live repository migration remains a separate action. Candidate snapshots need explicit human approval tied to exact hashes.
