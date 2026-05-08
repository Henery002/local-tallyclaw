# 更新日志

本文件按日期降序简要记录 TallyClaw 的功能迭代、问题修复、文档调整、架构决策和重要安全边界变化。

## 记录规则

- 最新日期放在最上方。
- 同一天可以合并记录，但需要按类别分组。
- 功能迭代、问题修复、重要架构调整、安全边界变化和用户可见变更应记录。
- 普通讨论、阶段性探索、临时设计资源和低价值过程信息不需要记录。
- 记录应简明说明“发生了什么”，必要时附相关文档路径。

常用类别：

- `新增`：新的能力、文档或目录结构。
- `变更`：对既有行为、方案或规范的实质调整。
- `修复`：问题修复。
- `安全`：安全、隐私、凭据、只读边界相关变更。
- `文档`：文档结构、维护规则或说明调整。

## 2026-05-08

### 新增

- 增加 `SQLiteLedgerStore` 最小可用实现，使用项目自有 SQLite 存储长期 token 统计。
- 增加 `TallyClawLedgerTests`，覆盖重复快照去重、跨来源聚合、上游 reset 后永久总量不倒退和数据库重开读取。
- 初始化 SwiftPM macOS 工程，包含 `TallyClaw` 可执行 target 与 `TallyClawCore`、`TallyClawDataSources`、`TallyClawLedger`、`TallyClawUI` 模块。
- 增加最小可运行 SwiftUI/AppKit 桌面宠物浮窗骨架。
- 增加核心用量模型、只读数据源协议、内存账本协议和 Core 测试。
- 增加 `script/build_and_run.sh` 与 Codex Run action 配置，支持后续一键构建运行。
- 增加 cockpit tools 与 `local-ai-gateway` 首轮只读数据源适配器，以及 fixture 驱动测试。
- 增加多来源 `UsageSnapshot` 合并逻辑，并让 app 启动后读取真实本地统计来源。
- 创建 TallyClaw 初始仓库骨架。
- 增加首版技术方案，明确 TallyClaw 是只读、本地、可持久化的 token 可观测宠物。
- 增加首版 TallyClaw 宠物 UI 概念预览图，存放于 `assets/previews/`。

### 变更

- 将 app 数据路径从“直接展示只读源临时合并快照”调整为“只读源写入 TallyClaw 自有 ledger，再由 UI 读取 ledger 聚合结果”。
- 将首版 SwiftUI 宠物浮窗 UI 替换为 Figma Version 18 设计翻译版，包含独立宠物本体、状态色、idle/high/warning 动效、token 粒子、hover 数据叶片和 click 展开数据条。
- 将应用窗口调整为更小的透明无边框浮窗，并隐藏传统窗口按钮，弱化 widget / dashboard 感。
- 微调宠物浮窗 UI：移除宠物外圈背景、降低 idle/高活跃状态动效幅度、缩小宠物本体、修复 hover 数据叶片与底部展开面板裁切，并让点击面板从宠物下方展开且显示中文观测数据。
- 增加真实用量活动监视器，宠物 activity 状态改为由 lifetime token / request 增量触发，并在短暂活跃窗口后自动回落 idle，避免仅因已有历史用量长期保持 activity。
- 校准快照健康状态语义：成功读取的静态快照标记为 idle，读取异常才标记 warning；同时记录每个数据源的 available / missing / failed 状态、最近读取时间和错误摘要。
- ledger 增加 `source_read_statuses` 持久化表，保存每个来源最近一次读取状态，应用重启后仍可恢复 source 健康上下文。
- 新增 `OpenClawUsageDataSource` 与 `HermesUsageDataSource`，并默认排除经 `local-ai-gateway` (`127.0.0.1:8787`) 转发的流量，避免与网关事件表重复统计。
- 去重规则扩展到 `cockpit` 本地 API 中转端口 `127.0.0.1:56267`；同时主展示总量不再将 cache token 计入，避免“今日/总计”显著偏高。
- 将 `local-ai-gateway`、`openclaw`、`hermes` 的 7 天 / 30 天窗口统一修正为过去 `7 x 24h` / `30 x 24h`；今日维持当天 0 点到现在。
- 点击展开面板改为两排四项：`今日`、`7 天`、`30 天`、`总计`。
- 将数据刷新从启动时单次读取调整为 5 秒准实时轮询，以便 UI 后续反映 token 增长。
- 增加浮窗桌面生命周期偏好：拖拽后位置持久化、常驻顶层/普通浮窗模式切换、开机启动开关。
- 增加系统菜单栏入口，便于直接切换常驻顶层、开机启动、打开设置或退出应用。
- 应用改为系统级常驻形态：启动后不在 Dock 保留图标，并拦截终止请求为隐藏主界面，保留菜单栏入口常驻。
- 将存量项目文档统一转换为中文，并明确后续文档默认以中文维护。
- 将文档维护规则收敛为轻量模式：默认只维护 `CHANGELOG.md`，停止继续维护 `docs/records/` 类过程记录目录。

### 文档

- 移除 `docs/records/` 记录体系，不再为每次讨论、阶段性实现或临时设计资源新增记录文档。
- 更新 README、文档中心和 Agent 接入指南，明确 `CHANGELOG.md` 是唯一默认迭代记录入口。
- 增加 Figma 设计迁移检查清单，约束后续增量迁移时的尺寸、动效、hover、面板、透明边界和截图验证。
