# Together 0.2.1 · Build 4 QA candidate

原生 macOS 双人协作应用，沿用 SwiftUI、SwiftData、签名 Operation Log、Lamport 合并和现有 Together Relay。当前开发目录为 `0.2.1/`；`0.0.1/` 保留原样。Our Story 尚未实现，没有占位导航。

## Our Finances

侧边栏增加 Our Finances，内部仅 United Reserves / Expenses / Recurring Bills。共同账户、个人付款和 AA 共用一份 Expenses 账本；账面余额从有效存款和共同支出推导，允许负数。待核对周期支出计入账面余额，确认不重复扣账，修改/未发生只调整原实例。

金额以整数最小单位保存，汇率计算使用 Decimal。支持搜索、滚动和键盘的币种选择；按 ISO 4217 定义 0–4 位小数。人民币入账采用半入舍入，用户填写的实际人民币金额优先，历史金额不随汇率变动。可手动记录参考汇率，不依赖在线汇率服务。

四种付款方式保存真实用户 ID。AA 按 UUID 固定分配最小单位余数，两人合计与原币和人民币总额分别一致。可创建同日多次约会或独立支出，按日期、个人/共同财务周期、付款、分类、来源和核对状态筛选。

周期账单按每月 1–31 日与账单时区发生，短月取月末。默认金额/付款方式变更从下个自然月生效；本期修改不会覆盖未来规则。账单只生成确定性 bill/month 支出，重启补建、重复同步去重。提醒可展开查看，系统通知需用户主动开启；无账单时无账单提醒。暂停/终止只影响未来，保留历史。

财务设置包含共同/个人周期、发薪日、计划存款日及仅尾号四位的付款工具档案。计划不自动记存款，卡片不覆盖资金来源。个人卡片仅本机保存；共享卡片经过日志同步，撤回共享不能抹除对方已保存的旧资料。修改记录与一次性同步 Banner 来自真实操作，无双人审批或银行连接。

原 Tasks/Recurring、Wishes、Profiles/原图头像、菜单式 Love Gifts、密封 Gift Reveal、Advisor/What's New、媒体同步继续使用现有服务和规则。

## 构建、测试与安装边界

需要 macOS 14+、Xcode。版本/Build 在 `0.2.1/Configuration/ReleaseVersion.json` 管理，Build 2 财务候选包后递增为 3，再因 Release 调试权限修正递增为 4。

```sh
make build
make test
make qa
make package
```

`make package` 构建 Universal Release 并验证 DMG，输出至 `0.2.1/dist/`。本次**不运行 make install、不覆盖 /Applications、不向桌面交付**。本轮检查时 `/Applications/Together.app` 不存在；原 Application Support 数据仍在，本轮不会自动安装。当前签名为 ad-hoc，未完成 Developer ID、公证或自动更新。

独立验证：`python3 scripts/run_finance_migration_test.py` 用原 0.0.1 源码创建真实临时数据库，再由 0.2.1 打开。`server/npm run dev` 启动本地 Workers；`TOGETHER_RUN_RELAY_TESTS=1 python3 scripts/run_finance_migration_test.py --all-tests` 同时执行业务、原生 WebSocket 与升级测试。统一 QA 的实际状态在 `qa/results/summary.json`；不能以构建代替 UI 验收。

## 数据与同步升级

SwiftData 仍只有 OperationRecord / LocalRecord / EntityRecord，物理 Schema 未改变；新增的是 Codable 财务领域实体及可重建投影。生产路径、Bundle ID `com.together.app`、设备私钥、User ID、SharedSpace、原日志和配对关系保持。隔离测试覆盖旧代码生成的完整 store 和只读取得的既有数据库副本；所有升级写入限于临时副本。

财务实体需要客户端设备协议 3。双方须升级至 0.2.1；旧协议 2 与新协议 3 的客户端在业务交换前明确拒绝互连。长期公钥及 Relay route 不变，已配对的双方升级后自动恢复，不要求重新配对。服务兼容 2/3 路由，旧客户端之间仍可运行。旧 Tailscale TCP 保留回归，正常流程仍为邀请码 + 原生 WebSocket Relay。

Relay 只实时转发密文，没有离线邮箱；发送方关闭时不能承诺对方取得尚未同步的变更。现有应用层加密已实现，仍需独立协议审查，不宣称银行验证、静态加密或真实双 Mac 跨 Wi-Fi 已通过。另一台 Mac 曾无法访问 workers.dev；跨网络验收必须先确认双方 `/health` 可达。

## 质量证据

规则索引见 AGENTS.md / DESIGN_SYSTEM.md / UI_COPY.md。新增功能与更改文案均注册 String Catalog。XCUITest 使用隔离 DEBUG Fixture；曾发生的自动化初始化超时与当前实际测试结果分开记录。可用 `scripts/capture_finance_views.py --app <Debug Together.app>` 生成自身视图的 AppKit 渲染截图；它们是视觉候选，不是通过的 XCUITest，也不能自动批准基线。Light/Dark、空/有数据、离线、小窗口、Reduce Motion 与人工点击证据分开记录。

完整规则与双 Mac 验收：REQUIREMENTS.md、ARCHITECTURE.md、TEST_PLAN.md、PHASES.md、CHANGELOG.md；服务部署说明见 server/README.md。

最终验收记录：[qa/FINAL_QA_BUILD4.md](qa/FINAL_QA_BUILD4.md)。Git 历史仍在外置缓存目录，风险及未执行的迁移方案见 [qa/GIT_STORAGE_REVIEW.md](qa/GIT_STORAGE_REVIEW.md)。
