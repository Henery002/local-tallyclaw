# Agent 接入指南

本指南面向后续进入 TallyClaw 仓库的 AI Agent 或开发者。

## 先读这里

1. 阅读 `README.md`。
2. 阅读 `docs/architecture/technical-plan.md`。
3. 阅读 `docs/records/README.md`。
4. 阅读 `docs/records/operations/current-state.md`。
5. 查看 `CHANGELOG.md`。
6. 编辑前先执行 `git status --short --branch`。

## 工作规则

- 与项目所有者协作时，默认使用中文。
- 项目文档默认使用中文维护；必要的技术名词、路径、模块名、字段名和代码标识可以保留英文。
- 回答和记录优先采用“先结论、后证据路径、再给具体下一步”的顺序。
- 严格维护对 cockpit tools、`local-ai-gateway` 和未来源系统的只读边界。
- 绝不写入源工具或网关的数据文件。
- 除非得到明确授权且确有必要，否则绝不刷新、轮换、修复或查看凭据内容。
- 保持根目录整洁。新笔记应放在 `docs/records/`、`docs/decisions/` 或其他合适子目录。
- 用户可见、结构性、功能迭代、问题修复或重要文档变更需要更新按日期降序维护的 `CHANGELOG.md`。
- 每次重要迭代、重大讨论或问题修复，都应在 `docs/records/` 下新增或更新记录。
- 每轮较完整的开发或分析结束前，更新 `docs/records/operations/current-state.md`，让下一个 Agent 能从当前状态继续。

## Agent 工作流

进入项目时：

1. 先继承文档上下文，不直接实施。
2. 检查 git 状态，识别未提交或非自己产生的改动。
3. 阅读当前运维状态，确认最近进展、下一步、风险和安全边界。
4. 如涉及外部数据源，先确认只读读取方式，再做任何实现。

退出项目前：

1. 说明完成了什么、没有完成什么。
2. 更新相关记录文档。
3. 更新 `docs/records/operations/current-state.md`。
4. 必要时更新 `CHANGELOG.md`。
5. 给出后续可执行任务，避免只留下笼统建议。

## 文档习惯

修改项目时，尽量在同一轮同步更新记录：

- 架构或方向变化：更新 `docs/architecture/`，通常还要新增决策记录。
- 实现里程碑：更新 `docs/records/iteration-log.md`。
- 当前进度、风险、下一步：更新 `docs/records/operations/current-state.md`。
- 重大讨论：在 `docs/records/discussions/` 下新增或更新文件。
- 问题修复：如果上下文有长期价值，在 `docs/records/fixes/` 下添加修复记录。
- 用户可见变更、功能迭代或问题修复：更新 `CHANGELOG.md`，并将最新日期放在最上方。

## 安全提醒

TallyClaw 只做观测，不治理、不修复、不修改上游系统。
