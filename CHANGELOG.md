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
- 将数据刷新从启动时单次读取调整为 5 秒准实时轮询，以便 UI 后续反映 token 增长。
- 将存量项目文档统一转换为中文，并明确后续文档默认以中文维护。
- 将文档维护规则收敛为轻量模式：默认只维护 `CHANGELOG.md`，停止继续维护 `docs/records/` 类过程记录目录。

### 文档

- 移除 `docs/records/` 记录体系，不再为每次讨论、阶段性实现或临时设计资源新增记录文档。
- 更新 README、文档中心和 Agent 接入指南，明确 `CHANGELOG.md` 是唯一默认迭代记录入口。
