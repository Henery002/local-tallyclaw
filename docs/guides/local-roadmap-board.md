# TallyClaw 本机自用推进看板

本看板面向 TallyClaw 的本机长期自用形态，不把签名、公证、安装包、自动更新等对外发布工程列为近期主线。

## 当前定位

TallyClaw 当前已进入“可本机长期自用并持续打磨”的阶段。后续重点不是做大型 dashboard，也不是做发布包装，而是把它打磨成低打扰、长期可信、动效灵活的本机 token observability companion。

当前阶段的观测重心是 cockpit / Codex 侧 token 产生，因为 Codex 是当前最主要的开发工具。OpenClaw 是第二优先级，local-ai-gateway 当前停服但保留兼容和后续恢复空间；Hermes 暂不作为近期主线。后续“继续”时应优先推进 cockpit 可用性、准确性、解释性和交互反馈，避免在暂时低频来源上过度投入。

## 后续主线

1. 边缘吸附缩略态
   - 左右贴边后自动吸附，变成半露出的缩略态。
   - hover 或点击时探出，保持宠物像贴身助理而不是普通窗口。

2. 精细追溯面板
   - 在轻量展开面板之外，提供来源、模型、provider、渠道和时间窗口 drill-down。
   - 第一版可先做趋势、来源榜单和模型榜单，避免一次性做成重 dashboard。

3. 事件级账本
   - 从快照级 ledger 逐步升级为事件级观测。
   - 引入稳定 event id、fingerprint、confidence、conflict 标记和读取水位线，提高长期准确性。

4. 性能画像与读取节流
   - 针对 5 秒轮询、SQLite 写入、OpenClaw/Hermes 文件扫描做 CPU/IO profiling。
   - 根据画像决定是否引入文件 watcher、增量读取或自适应刷新间隔。
   - 已推进：来源读取状态记录本次读取耗时，展开面板的来源健康会显示最慢读取耗时；轮询从固定 5 秒改为自适应节流，活跃时保持 5 秒，连续空闲后退到 15/30 秒，读取失败时使用 10 秒重试。
   - 下一步：根据真实长期运行耗时判断是否继续引入 OpenClaw/Hermes 文件级增量扫描或文件 watcher。

5. 源适配抗变更能力
   - 对 cockpit、local-ai-gateway、OpenClaw、Hermes 的 schema 变化提供版本判断和容错。
   - 上游变化时要显式呈现“不确定/读取异常”，不能静默算错。
   - 已推进：`local-ai-gateway` 事件读取兼容旧 schema 中缺失 `source_event_key` / `upstream_model_id` 的情况，分别回退到 `id` / `model_alias`。
   - 已推进：`local-ai-gateway` 与 Hermes 的 SQLite 读取会在查询前校验核心必需列，缺列时明确报告 schema mismatch 和缺失列名，便于来源健康面板展示可理解错误。
   - 已推进：cockpit JSON 解码错误会转成 schema mismatch 并包含字段路径；OpenClaw legacy ledger 会跳过单条 malformed 事件，避免局部坏数据拖垮整个来源。

6. UI 与动效持续打磨
   - 保持宠物本体为主，避免把主界面做成重面板。
   - 优化状态色、呼吸节奏、hover peek、warning 表情、数字可读性和窗口裁切。
   - 交互基线：点击展开面板时宠物本体不能弹跳或被窗口位移动画带走，应保持原地稳定，面板在宠物下方缓动展开；左右贴边与 hover 探出属于边缘缩略态逻辑，不能混入普通点击展开。

## 实用能力候选

- 今日 digest：总结今天 token 用量、相对昨天变化、主要来源。
  - 已推进：展开面板已增加轻量今日摘要，展示今日 token、相对 7 日均值和主要来源；后续如需“相对昨天变化”，需要先补日级历史基线。
- 软预算/软阈值：只提醒，不拦截请求，例如今日达到 80% 时进入轻微提醒态。
- token 峰值提醒：短时间暴涨时进入警觉态，并在面板中标出峰值时间。
- 来源健康面板：展示 available、missing、failed、最近读取时间和错误摘要。
- 趋势小火花线：展开面板中展示 6h / 7d token sparkline。
  - 已推进：窗口趋势已接入最近 6h / 30m token 曲线，数据来自 ledger 已观测持久化增量，并支持 hover 查看单个半小时桶 tokens；最新半小时桶有轻量脉冲和当前累计文案，用于观察实时滚动变化。
- 模型/来源榜单：展示 top provider、top model、top source。
- 低噪声通知：只在异常、跨阈值、来源失联时提示。
- 快速复制摘要：一键复制今日、7 天、30 天、总计和主要来源。

## 稳定炫酷能力候选

- 边缘缩略态：贴边后只露半张脸或一只眼睛，有 token 活动时探头。
- 活动强度动效：小增量只亮眼或核心闪烁，大增量才出现明显能量脉冲。
  - 已推进：活动监视器已输出 low / medium / high 强度，UI 会用强度调节 `+tokens` 粒子数量、核心光强和活跃节奏，先保持克制不做大幅弹跳。
- 来源差异化动效：不同来源活跃时用细节动效区分，而不是只换颜色。
- 异常侦测表情：读取失败、统计跳变、来源失联时短暂困惑或警觉。
- 跨天轻动效：本地新一天开始时轻微重置反馈。
- hover peek：鼠标靠近时宠物看向鼠标，再展开小浮层。
- 拖拽惯性：拖动结束时有轻微跟手缓动，但避免弹跳过度。
- 睡眠/勿扰态：长时间无活动时低功耗睡眠，有 token 活动时醒来。

## 建议优先级

1. cockpit / Codex 观测准确性与解释性。
   - 当前重点：优先保证 cockpit 聚合窗口、ledger 持久化、状态解释、活动触发和 UI 展示准确可靠。
   - 已推进：今日 digest 第一版已接入展开面板，用现有 snapshot 解释今日用量、相对 7 日均值和主要来源。
   - 已推进：窗口趋势卡片已补充今日/7 天/30 天/总计的口径说明，明确自然日、滚动窗口和长期累计差异。
   - 下一步：围绕 cockpit 做异常解释和更贴近 Codex 调用的活动反馈。
2. 精细追溯面板第一版：趋势、来源榜单、模型榜单。
   - 已推进：第一版已经接入窗口趋势、来源健康、来源/事件榜单。
   - 已推进：窗口趋势已补充过去 7 个本地自然日 token 柱状图；成功率栏补充请求数、失败数和延迟，面板整体改为纵向滚动，避免后续模块裁切。
   - 已推进：窗口趋势 7 日柱状图支持 hover 查看单日 token；成功率默认口径明确为 7 天滚动请求窗口，并在标题中标注为 `7 天成功率`。
   - 已推进：事件追溯改为近 7 天 exact 逐请求事件榜单，并在面板中明确 cockpit 目前是聚合快照，不进入逐请求榜单；旧 OpenClaw 历史事件不再默认压住近期状态。
   - 下一步：优先补 cockpit 侧的窗口解释与 digest；OpenClaw 作为第二来源补充，local-ai-gateway 仅保留可恢复兼容。
3. 事件级账本最小实现。
   - 已开始：当前 ledger 已增加 `usage_observations` 观测表，用来源 lifetime 快照生成稳定 fingerprint，避免重复轮询刷出重复观测。
   - 已推进：`local-ai-gateway` 已接入真实事件级读取和写入，ledger 记录 provider、model、sourceName，并用 exact 事件水位避免每轮全量重扫。
   - 已推进：展开追溯面板会优先展示真实事件级模型、provider 和来源榜单；没有事件级数据时继续回退到快照来源占比。
   - 已推进：OpenClaw 基于 legacy ledger key 与 trajectory dedupe key 接入事件级观测，Hermes 基于 sessions.id 接入事件级观测；两者都继续排除本地网关转发流量，避免与 `local-ai-gateway` 重复记账。
   - 已推进：cockpit tools 当前只暴露聚合统计 JSON，因此接入为 `snapshot` 级观测，记录 cockpit/codex 来源维度但不伪装成 exact 逐请求事件。
   - 已推进：当主要来源为 cockpit 聚合快照、事件榜单来自 exact 事件来源时，展开面板会明确标注 snapshot / exact 语义差异，避免误读。
   - 下一步：不要继续为了低频来源过度扩展事件模型；优先做 cockpit 窗口 drill-down 和异常解释，并把 OpenClaw 作为次重点保持健壮。
4. 性能画像与读取节流。
   - 已推进：新增来源读取耗时画像与自适应刷新间隔，减少长期空闲时的重复扫描。
   - 下一步：优先观察 cockpit 读取稳定性和 UI 活动触发是否符合 Codex 使用体感；OpenClaw/Hermes 文件 watcher 暂不主动推进，除非实际耗时明显影响体验。
5. 来源 schema 抗变更与健康解释。
   - 已推进：先补齐 `local-ai-gateway` 旧 schema 兼容与 SQLite 必需列缺失解释；Hermes 也会在 schema 变化时明确列出缺失列。
   - 已推进：cockpit JSON 缺核心字段时会报告可读的 schema mismatch 与字段路径；OpenClaw legacy ledger 单条事件缺 `provider` 等字段时会跳过坏事件并保留其他有效记录。
   - 下一步：优先增强 cockpit schema/窗口语义说明；OpenClaw trajectory 兼容保持第二优先级。
6. 边缘吸附缩略态、hover peek 与更细状态动效。
   - 已推进：边缘吸附缩略态已完成第一版，并修复点击展开时误触发边缘 reveal/restore 位移动画导致的弹跳回归。
   - 已推进：贴边缩略态点击展开会拉出完整面板，并取消 hover reveal 延迟收回造成的半遮掩回归；普通点击展开不再触发整窗/宠物弹跳。
   - 已推进：活动强度动效完成第一步，小/中/大 token 增量会映射到不同粒子数量和能量节奏。
   - 已推进：活动监视器会记住最近 token 增量的主要来源；当来源为 cockpit / Codex 时，宠物活跃态面屏会出现克制扫描光，作为 Codex 正在产生活动的轻量差异化反馈。
   - 已推进：hover peek 的第一层微交互已接入，鼠标悬停宠物时 idle 眼睛会轻微跟随鼠标位置，增强“贴身助理”感且不影响拖拽/贴边/展开。
   - 已推进：hover 小浮层在今日 tokens 之外补充主要来源及占比，让常用的 cockpit / Codex 观测不必每次展开面板。
   - 已推进：activity 态眼睛从尖号调整为专注扫描猫眼，粗胶囊核心动效改为细能量条，继续保持宠物本体不因点击展开而弹跳。
   - 下一步：围绕 Codex/cockpit 活动来源做更细反馈，例如 cockpit 活跃时的轻量“专注/读写中”状态；也可继续补睡眠/勿扰态和低噪声阈值提醒。

## 近期暂不推进

- 面向外部用户的签名、公证、安装包、自动更新和发布流水线。
- 自动治理、自动修复、清理或迁移上游数据。
- 读取、展示或传播 prompt、response、密码、token、API key 等敏感内容。
