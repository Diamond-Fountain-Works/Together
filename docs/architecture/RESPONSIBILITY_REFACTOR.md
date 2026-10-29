# Together 职责拆分记录

基线：`5f726a602b76dec59b5fb481cef1ae9be6a90d5b`。
分支：`refactor/responsibility-boundaries`，依赖 `feature/iphone-client` / PR #16。

## 拆分方法

保留现有 Monorepo 和 TogetherCore 模块，在原模块内按职责移动声明。
现有调用方继续使用相同公开接口和运行时对象，没有创建第二套数据库或同步引擎。

### ReplicaEngine

路径前缀：`packages/together-core-swift/Sources/TogetherCore/Synchronization/`。

| 文件 | 拆分后的职责 | 行数 |
| --- | --- | ---: |
| `ReplicaEngine.swift` | 原有状态、日志、业务与同步协调 | 528 → 450 |
| `ReplicaConfiguration.swift` | RecurrenceDraft、ListenerSettings、TogetherError | 21 |
| `ReplicaEngine+Production.swift` | production 工厂：打开已有存储、恢复及校验原设备身份 | 46 |
| `ReplicaEngine+Wishes.swift` | 愿望额度、具体愿望、兑现及调整命令 | 21 |

Production/Wishes 使用同一类型的 Swift extension；不复制实例状态。
依赖 private 状态的任务、礼物和授权逻辑仍留在原协调器，没有扩大 private 可见性。

### C1ReplicationService

路径前缀：`packages/together-core-swift/Sources/TogetherCore/Networking/Relay/`。

| 文件 | 拆分后的职责 | 行数 |
| --- | --- | ---: |
| `C1ReplicationService.swift` | 原有连接生命周期、私有 peer/channel、收发队列和同步协调 | 645 → 472 |
| `C1ReplicationBinding.swift` | 持久化连接绑定数据 | 14 |
| `C1RelayAPI.swift` | API 请求/响应类型和既有 endpoints | 59 |
| `C1ReplicationContent.swift` | 日志、媒体消息的 Codable 编解码 | 26 |
| `C1ReplicationService+Bootstrap.swift` | 迁移提案、签名、迁移工厂和新设备准备入口 | 85 |

private 请求类型跟随 API 实现移动；private 通道类型保留在协调器文件。
没有把 private 改成 internal/public，也没有修改 actor 隔离声明。

## 不变性核验

原文件仅删除下列基线片段；新文件增加必要 imports 和 extension 包装，文件末尾分隔空行规范为单个换行。
逐字节检查包含注释、访问修饰符、方法签名、默认参数及方法体，9/9 文件检查通过。

| 原文件 | 基线行范围（含尾部空行） |
| --- | --- |
| `ReplicaEngine.swift` | 5–24、77–117、345–361 |
| `C1ReplicationService.swift` | 6–17、18–42、55–78、80–110、196–247、264–292 |

公开 API、持久化键、Schema、Canonical JSON、签名、Lamport、ACK、重连和业务规则保持原样。
`protocol/`、原生依赖、UI/文案资源、Android 源码和发布配置未修改。
SwiftPM 自动发现新增 Core 文件，Xcode 继续引用同一个本地 Package。

这是职责归档和入口分离，没有宣称建立独立 WishService 或完成深层运行时解耦。
本轮不发布安装包；App/同步/存储版本不变。

## 验证结果

| 检查 | 实际结果 |
| --- | --- |
| 完整 headless QA | 无 FAIL；退出码 2 保留原有 WARN / NOT RUN / REVIEW REQUIRED |
| Swift Core | 182 PASS / 0 FAIL / 6 条原有 opt-in SKIP |
| 旧 0.0.1 合成库迁移、身份/配对保留 | PASS |
| 四客户端本地 Worker、ACK、媒体、撤销和重连 | PASS；非公网真机验收 |
| Crash recovery | PASS |
| 本地 macOS App 编译 | PASS；legacy C1 回归配置，没有启动 App |
| iOS 15 ARM64 Core Release 交叉编译 | PASS；不是完整 iPhone App 运行验收 |
| Relay / 协议测试、源码安全、双语资源检查 | PASS |
| Copy QA | 0 错误 / 26 条既有上下文重复警告 |
| UI / Visual QA | 未重跑；UI/资源未修改，旧候选/基线状态保持原样 |
| 原生 Mac/iPhone App 与 Android/跨平台 CI | 以该 PR 最新提交的 GitHub Checks 为准 |

本地证据：`qa/results/summary.json` 和 `qa/results/responsibility-refactor/`。
日志只留本地。完整原生 App 构建交 GitHub CI，避免本机重复编译未修改的 Rust 多平台依赖。
独立协议安全审查和真实跨网络验收保持原有待完成状态。

## 回退与后续

在功能分支上 revert 本次拆分提交即可恢复原文件布局，不需要数据库迁移或重配设备。
后续若抽取独立运行时服务，应单独确定依赖和状态所有权，并复用现有业务回归测试。
