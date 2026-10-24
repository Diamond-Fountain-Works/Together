# 0.2.4 — compatibility candidate (unreleased)

- Target Apple Silicon/macOS11, iPhone/iPad15 and Android/API24 ARM64+ARMv7.
- Share existing Apple feature views and signed business core; add UIKit file,
  media and lifecycle adapters and native phone/tablet navigation fallbacks.
- Preserve existing modern SwiftData records. Add transactional SQLite for older
  Apple systems, readonly incompatible-store guards and isolated migration tests.
- Backport observation, clocks, networking and native control availability;
  verify actual linked minimums and bundled concurrency runtime on Mac.
- Rebuild reviewed native dependencies for each platform/ABI. Update Android JNA
  and desugaring; retain original HEIC content when the old OS cannot preview it.
- Fix immediate Chinese resource propagation in Compose menus/dialogs.
- Mac Build24 / Android code17. No new public release, production installation,
  identity reset, Relay deployment or independent security approval is implied.

[Builds, runtime scope and remaining gates](../qa/reports/PLATFORM_COMPATIBILITY_QA.md).

# 0.2.3 — Chinese and English

- Add an icon-only globe menu in Settings on macOS and Android, with device-local
  Chinese/English choice and immediate UI refresh.
- Complete both catalogs, including affectionate gift copy, currencies, native
  permission purposes, status/error messages and release notes.
- Remove repeated settings/finance explanations and defensive product prose.
- Keep calendar-date semantics and existing data/identity/protocols unchanged;
  dates follow the selected interface language. Change history translates status
  fields and preserves user-authored text that happens to match a status word.
- Add bilingual resource and formatter/review regression gates to local QA and CI.
- App metadata: macOS 0.2.3 Build 21; Android 0.2.3 code 16.

[Build and acceptance evidence](../qa/reports/RELEASE_0_2_3.md).

---

# 0.2.2 — delivery preparation (unreleased)

- Add normal persistent-storage native App startup and empty first-run setup;
  retain independently isolated QA targets and existing signed-log/domain rules.
- Prepare Mac Build 20 (Apple Silicon/macOS 14.5+, ad-hoc/unnotarized) and Android
  code 15 (arm64, optimized Release, externally managed release signing).
- Keep existing paired C1 Mac transport and recovery errors for missing identity;
  never import QA data or silently replace keys.
- Keep unsupported native own-device enrollment controls unavailable; do not
  present them as a completed multi-device workflow.
- Rebuild the unchanged native FFI wrappers with a fixed Rust Iroh/base/dns/relay
  1.1.0 dependency lock and NoQ 1.2.0, addressing the disclosed upstream relay
  denial-of-service and associated transport fixes. Android arm64 uses actual
  16KiB-aligned ELF segments; unsafe prebuilt-library fallback is rejected.
- Earlier Build 19/code13 candidates were withdrawn before publication. The code
  14 runtime test then found JNA JNI fields renamed by R8; code 15 preserves that
  native ABI while keeping application optimization. Historical QA downloads
  carry a security warning.

Artifact, fresh-start and network acceptance are reported separately in
[0.2.2 QA](../qa/reports/RELEASE_0_2_2.md). This entry is not a stable-release claim.

---

# Native normal-App QA — Mac Build 18 / Android code 12 (unreleased)

- Connect isolated normal App pairing, task/wish/finance editors and lifecycle to
  the existing native transport, signed bootstrap, Protocol 4 replication/ACK.
- Reuse the existing original-media engine and exact C1 content envelope under a
  distinct App-only ALPN; preserve legacy CLI and default production builds.
- Harden missing-bootstrap-ACK errors, pinned identity recovery, cancellation and
  ordered mixed media/operation ciphertext sending.
- Record physical normal-App and domain results with the explicit **Mac VPN
  active / Samsung VPN off** qualification; no fully VPN-free release claim.
- Compile both isolated normal Apps in CI without uploading APKs or runtime data.
- No production installation, Worker deployment, PR merge or baseline approval.

# P2P transport foundation — development Build 14 (not packaged/installed)

- Harden the physical QA driver against hotspot/Wi-Fi misclassification, locked
  device starts and premature participant exit; preserve exact ACK/restart gates.
- Add explicit LAN versus shared-uplink encrypted-relay diagnostics and
  test-process network restoration. Physical retry is blocked on phone unlock;
  the current shared hotspot is not independent-network acceptance.
- Add isolated native Android instrumentation, Mac QA CLI and a bounded physical
  public-network driver. Require no VPN/proxy/USB network path, exact signed
  checkpoints, durable ACKs and distinct-process recovery. Public acceptance
  remains blocked by device disconnection; [report](../qa/reports/P2P_PUBLIC_ACCEPTANCE.md).
- Add an optional pinned Iroh QUIC package around the existing Protocol 4 log,
  signed independent endpoint credentials, bounded frames/queue and reused cipher.
- Verify local relay-disabled paged convergence, genuine ACK and tombstone;
  retain explicit Android/public-network, key persistence and security gates.
- Keep installed App behavior/C1 unchanged. See [scope and evidence](../architecture/P2P_INCREMENTAL_REPLICATION.md).

# Unified Plans — 0.2.1 Build 13 / Android code 8

- Merge Upcoming into Pending on both Mac and Android; retain only Pending /
  Completed and the existing task editor. Date order keeps undated tasks last.
- Preserve scheduled recurrence execution boundaries. Home's upcoming summary
  routes to Pending; old Android saved filter state is normalized.
- Add native Mac and physical Android UI checks and candidate screenshots. No
  storage/signed protocol/identity change. See [QA evidence](../qa/reports/UNIFIED_PLANS.md).

# Native partner pairing correction (development Build 12 / Android code 7)

- Separate partner create/join text UI from signed-file own-device enrollment.
- Add mixed-root signed bootstrap, bounded history/checkpoint exchange and durable
  join/genesis recovery before activating the existing Protocol 4 engine.
- Add strict independent staging QA and two isolated native Mac app fault tests.
- Keep production API 1 unchanged. VPN-free public reachability failed on the
  measured Samsung network; P2P, independent security and full public acceptance
  are not claimed. See [QA evidence](../qa/reports/NATIVE_PARTNER_PAIRING.md).

# Android 0.2.1-phaseC (versionCode 5, unreleased)

- Add fail-closed physical Debug QA enrollment, namespaced Activity reopening and explicit same-signer install guards. Production Mac identity/data and Android Release UI remain unchanged.
- Exercise a physical Samsung with native Swift roots, USB-reversed local C1, durable ACK/restart/revocation and exact business/media comparisons. Public network and independent security acceptance are separate gates.
- Add controlled link/session/ACK reliability, original-media, finance and opt-in 100k signed Room benchmarks; retain failed attempts and scope limits in [Phase C QA](../qa/reports/ANDROID_PHASE_C.md).
- Correct test focus/scroll handling for Samsung keyboard/layout transitions. No user input-method restriction, protocol weakening or general timeout extension.
- Configure/read back main branch protection: no force push/delete, administrator enforcement and PR/CI/conversation requirements. No merge or production deployment.

# Android 0.2.1-phaseB (versionCode 2, unreleased)

- Native phone/tablet business workspaces: Tasks/recurrence, Wishes ledger/confirmation, Reserves/Expenses/Bills and finance settings.
- Original photo/audio gift composition, Android recording/manual playback, resumable authenticated media, sealed reveal/history and explicit original export.
- Bounded on-demand effective change review; local reviewed/notified state independent of transport receipts/domain confirmation.
- Actual old Debug APK replacement and independent native Swift/Kotlin C1 tests. Android candidates await human approval; physical device and independent security gates remain open.
- Existing Protocol 4, API2, Room schema1, SwiftData, production Worker/Apple App and original signed identities are retained. This is a Draft client branch, not production rollout.

# Unreleased — Android Phase A

- Add isolated Kotlin/Compose/Room client and real Debug APK build; no macOS version or binary change.
- Port existing Protocol 4 signatures, enrollment, paged log synchronization, exact ACK and domain vectors; add Swift verification of Kotlin output.
- Add local task editor, authorized-device enrollment/status, native copy gate and Android CI.
- Full Android business/media UI, physical phone/cross-Mac acceptance and independent protocol review remain pending. No production deployment or App installation.

# Development — 0.2.1 Build 10 (unreleased)

- Isolated XCTest now owns and awaits the existing host's native reopen, checks the PID, and carries its fixture arguments/environment. Removed the QA delegate's asynchronous self-relaunch and stale external notification-center query. Production startup remains unchanged.
- Build number increments after App-source changes; prior Build 9 artifacts and failed desktop attempts remain available. No installation or deployment.

# Development — 0.2.1 Build 9 (unreleased)

- Added native signed-file Add My Device, device fingerprints/list/revoke and bilateral legacy migration confirmation; stable original identities, space and log remain. Desktop/human acceptance is pending.
- Scoped SwiftData contexts/bulk local lookup and durable signed ACK membership pages reduce the same 100k benchmark's measured synchronization cost. Wire operations, deterministic business merge and physical schema are unchanged.
- Corrected cached enrollment exports to retain current known revocations; added explicit regression, key-loss guards and QA file-key/loopback confinement.
- Added read-only startup-incident findings with explicit UNKNOWN items, root-loss boundaries and authorization-paging assessment.
- No production install/deployment/merge; independent protocol review, physical networking, desktop QA and visual acceptance remain gates.

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
