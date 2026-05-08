# TallyClaw

TallyClaw 是一个本地、只读的 macOS token 可观测宠物。它读取本机既有工具和网关的 token 使用数据，将长期用量持久化到项目自有账本，并通过轻量桌面宠物提供日常观测入口。

本项目第一阶段不代理流量，也不改造既有网关。TallyClaw 只能读取已批准的数据源，归一化用量记录，谨慎去重，并在上游源文件后续被删除时仍保留已经观测到的历史统计。

## 当前范围

- 为本地 token 数据源提供只读适配器，优先覆盖 cockpit tools 与 `local-ai-gateway`。
- 独立持久化日、周、月、永久总量等 token 统计。
- 提供轻量桌面宠物 UI，支持流畅动画、拖动放置和简约观测状态。
- 使用 `CHANGELOG.md` 简要记录功能迭代、问题修复和重要变更，避免维护过重的记录体系。

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
│   └── guides/
│       └── operations/
├── src/
│   ├── app/
│   ├── core/
│   ├── data-sources/
│   ├── ledger/
│   └── ui/
├── script/
│   └── build_and_run.sh
├── assets/
│   ├── pet/
│   └── icons/
└── tools/
```

根目录保持克制，只放仓库入口文件。默认不要新增零散记录文档；功能迭代、问题修复和重要变更统一简要写入 `CHANGELOG.md`。只有长期有效的架构说明或决策，才放入 `docs/architecture/` 或 `docs/decisions/`。

## 文档入口

- [技术方案](docs/architecture/technical-plan.md)
- [Agent 接入指南](docs/guides/agent-onboarding.md)
- [决策记录](docs/decisions/README.md)

## 本地开发

当前工程使用 SwiftPM 组织 macOS 原生应用。

常用命令：

- `swift test`：运行核心测试。
- `swift build`：编译全部 SwiftPM target。
- `./script/build_and_run.sh`：构建并以 `.app` 形式启动 TallyClaw。
- `./script/build_and_run.sh --verify`：启动后检查进程是否存在。

## 维护原则

本项目后续仍会大量通过 AI Agent 开发，但文档维护需要保持轻量。不要为了每次讨论、每个阶段性实现或每个设计资源额外创建记录文件。

默认维护规则：

- `CHANGELOG.md`：唯一默认迭代记录入口，按日期降序简要记录功能迭代、问题修复和重要结构变更。
- `docs/architecture/`：仅维护长期有效的架构、数据流和能力边界。
- `docs/decisions/`：仅在存在长期有效且需要保留取舍原因的架构决策时维护。
- `docs/guides/`：仅维护稳定的开发或 Agent 接入规则。
