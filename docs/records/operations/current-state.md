# 当前项目状态

最后更新：2026-05-08  
维护对象：TallyClaw 项目长期运维与 AI Agent 续接

## 当前阶段

项目处于初始化与方案固化阶段。

已完成：

- 创建仓库基础目录结构。
- 明确 TallyClaw 的产品方向：本地、只读、长期持久化的 token 可观测宠物。
- 明确第一版推荐技术架构：原生 macOS 应用、SwiftUI/AppKit、SQLite 自有账本、只读数据源适配器。
- 建立中文文档规范。
- 将记录性文档升级为面向 AI Agent 的长期运维文档。
- 将更新日志规范调整为按日期降序记录每次功能迭代、问题修复和重要项目变更。
- 生成首版宠物 UI 概念预览图，供后续确认视觉方向。

尚未开始：

- Swift/macOS 工程初始化。
- 数据源 schema 探查。
- cockpit tools 只读适配器实现。
- `local-ai-gateway` 只读适配器实现。
- SQLite ledger schema 设计与实现。
- 宠物视觉资产与动画实现。

当前已有概念预览，但尚未进入可运行 UI 实现。

## 不可突破的安全边界

- TallyClaw 只能读取已批准的数据源。
- 不得写入 cockpit tools、`local-ai-gateway` 或其他上游工具的数据文件、数据库、日志、配置、账号文件或凭据。
- 不得刷新、轮换、修复或读取不必要的凭据内容。
- 不得触发 cockpit tools 中 Codex 账号的 `refresh_token` 刷新流程。
- 不得删除、压缩、迁移、修复或重置源 token 统计。
- TallyClaw 的长期统计只能写入项目自有存储。

## 当前文档入口

- 项目概览：[README.md](../../../README.md)
- 技术方案：[docs/architecture/technical-plan.md](../../architecture/technical-plan.md)
- 架构决策：[docs/decisions/2026-05-08-read-only-native-ledger.md](../../decisions/2026-05-08-read-only-native-ledger.md)
- Agent 接入指南：[docs/guides/agent-onboarding.md](../../guides/agent-onboarding.md)
- 初始方案讨论：[docs/records/discussions/2026-05-08-initial-tallyclaw-plan.md](../discussions/2026-05-08-initial-tallyclaw-plan.md)
- UI 预览讨论：[docs/records/discussions/2026-05-08-ui-preview.md](../discussions/2026-05-08-ui-preview.md)
- 迭代记录：[docs/records/iteration-log.md](../iteration-log.md)
- 更新日志：[CHANGELOG.md](../../../CHANGELOG.md)
- UI 概念预览：[assets/previews/tallyclaw-ui-preview-2026-05-08.svg](../../../assets/previews/tallyclaw-ui-preview-2026-05-08.svg)

## 已知风险

- cockpit tools 与 `local-ai-gateway` 的 token 统计口径可能不一致。
- 历史导入与实时采集可能重复，需要保守去重与来源追溯。
- 源数据可能轮转或删除，TallyClaw 必须在自有账本中保存已观测总量。
- 如果数据源读取方式不稳定，第一版统计可能只能标记为部分或估算。
- 桌面宠物动画需要控制 CPU、内存和磁盘写入，避免为了可视化牺牲轻量目标。

## 下一步建议

1. 初始化原生 macOS 工程前，先决定 SwiftPM 还是 Xcode project 组织方式。
2. 只读探查 cockpit tools 统计数据位置与 schema，记录证据路径，不修改源文件。
3. 只读探查 `local-ai-gateway` 统计数据位置与 schema，记录证据路径，不修改源文件。
4. 基于两个数据源的共同字段设计 SQLite ledger schema。
5. 先实现离线导入与聚合验证，再接实时或准实时 watcher。
6. 宠物 UI 先做最小可运行浮窗与占位动画，再接入真实统计状态。

## Agent 交接提示

新的 Agent 进入项目时，应先读本文件，再读技术方案和 Agent 接入指南。不要直接开始写代码；先确认 git 状态、当前用户要求和只读边界。

如果本文件与其他文档冲突，应先向用户汇报冲突点和建议，再修改文档或代码。
