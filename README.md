# TallyClaw

TallyClaw 是一个本地、只读的 macOS token 可观测宠物。它读取本机既有工具和网关的 token 使用数据，将长期用量持久化到项目自有账本，并通过轻量桌面宠物提供日常观测入口。

本项目第一阶段不代理流量，也不改造既有网关。TallyClaw 只能读取已批准的数据源，归一化用量记录，谨慎去重，并在上游源文件后续被删除时仍保留已经观测到的历史统计。

## 当前范围

- 为本地 token 数据源提供只读适配器，优先覆盖 cockpit tools 与 `local-ai-gateway`。
- 独立持久化日、周、月、永久总量等 token 统计。
- 提供轻量桌面宠物 UI，支持流畅动画、拖动放置和简约观测状态。
- 沉淀产品决策、架构变更、迭代记录、修复记录和长期运维状态，服务后续 AI Agent 接入与持续开发。

## 非目标

- 不写入源工具、网关数据库、日志、账号文件、凭据或 refresh token 配置。
- 不刷新、修复、迁移、清理或修改 cockpit tools 或网关数据。
- 第一版不承诺覆盖所有本机 API 客户端，也不承诺跨 provider 的绝对精确账务统计。
- 日常迭代不在仓库根目录产生大量零散文件。

## 仓库结构

```text
.
├── CHANGELOG.md
├── README.md
├── docs/
│   ├── README.md
│   ├── architecture/
│   ├── decisions/
│   ├── guides/
│   └── records/
│       └── operations/
├── src/
│   ├── app/
│   ├── core/
│   ├── data-sources/
│   ├── ledger/
│   └── ui/
├── assets/
│   ├── pet/
│   └── icons/
└── tools/
```

根目录保持克制，只放仓库入口文件。新的设计说明、讨论记录、实现日志和排障记录应放入 `docs/records/` 或 `docs/decisions/`，不要散落在根目录。

## 文档入口

- [技术方案](docs/architecture/technical-plan.md)
- [项目记录索引](docs/records/README.md)
- [长期运维状态](docs/records/operations/current-state.md)
- [Agent 接入指南](docs/guides/agent-onboarding.md)
- [决策记录](docs/decisions/README.md)

## 面向 Agent 优先的维护原则

本项目后续默认由 AI Agent，尤其是 Codex，作为主力开发者持续推进。因此文档不只面向人类阅读，也必须能让新的 Agent 快速继承上下文、判断边界、继续开发。

每次重要工作结束前，应同步更新：

- `CHANGELOG.md`：按日期降序记录用户可见、结构性、功能迭代、问题修复或重要文档变更。
- `docs/records/iteration-log.md`：记录高层进展。
- `docs/records/operations/current-state.md`：记录当前状态、下一步和风险。
- 必要时更新 `docs/records/discussions/`、`docs/records/fixes/` 或 `docs/decisions/` 下的专项记录。
