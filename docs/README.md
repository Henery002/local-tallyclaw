# 文档中心

本目录保存 TallyClaw 长期有效的项目文档。

文档维护以轻量为原则。功能迭代、问题修复和重要结构变更默认只记录到仓库根目录的 `CHANGELOG.md`，不要为每次讨论或每次实现额外创建记录文档。

## 目录说明

- `architecture/`：当前系统设计、数据流、持久化模型和技术边界。
- `decisions/`：长期有效的架构决策记录。
- `guides/`：面向人类开发者和 AI Agent 的接入与操作指南。

## 维护规则

- 默认只更新 `CHANGELOG.md`，简要记录功能迭代、问题修复和重要结构变更。
- 只有长期有效的架构内容才更新 `docs/architecture/`。
- 只有需要保留长期取舍原因的事项才新增或更新 `docs/decisions/`。
- 不再维护 `docs/records/` 类按时间堆叠的记录目录。

## 语言规范

项目文档默认使用中文维护。必要的技术名词、路径、模块名、字段名和代码标识可以保留英文。

## 常用入口

- [Agent 接入指南](guides/agent-onboarding.md)
- [Figma 设计迁移检查清单](guides/figma-migration-checklist.md)
- [本机自用推进看板](guides/local-roadmap-board.md)
