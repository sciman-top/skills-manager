# Codex 子代理并发、深度、生命周期与 token 成本控制研究

**日期**：2026-08-09
**范围**：Windows Codex Desktop 当前宿主；只读研究，不修改宿主配置，不运行模型探针。
**源码快照**：`openai/codex@936f5eb3ee223ab34dcb221fa7c5f9943c8092bd`（2026-08-09 查询 `main`）。

## 结论先行

**AI 推荐：当前保留 `agents.max_concurrent_threads_per_session = 2` 作为宿主安全上限，同时把“单任务最多 4 个子代理”改成任务级动态总量上限，而不是默认生成量。**

- 日常默认：0-2 个子代理；只有两个以上真正独立、边界清楚、写集互斥的任务才并行。
- 单任务总量：最多 4 个，包含所有 wave 和后代；当前宿主同时最多运行 2 个，4 个任务应按 `2 + 2` wave 调度。
- 深度：默认只允许 `root -> child` 一层；子代理不得再次委派，除非主控为已审查的只读 fan-out 明确授权。
- `xhigh`：当前最多同时 1 个，且不得作为探索、扫描、常规测试或摘要的默认；先用 `low/medium`，确有复杂推理缺口再升级。
- 生命周期：每个 wave 必须 `spawn -> bounded wait/monitor -> collect -> stop/interrupt if needed -> close/确认终态` 后才能开始下一 wave；“已经返回结果”不能自动等同于“线程已关闭、槽位已释放”。

`2 concurrent / 4 total` 目前是合理的保护性策略，但应动态化的是**任务是否使用 0、1、2 或 4 个子代理以及模型/effort**，不建议在已出现高 token 和未终止异常时动态抬高宿主并发配置。

## 研究问题与事实边界

本研究区分三类事实：

1. **公开产品契约**：OpenAI 官方文档明确承诺的字段和行为。
2. **当前实现事实**：固定 commit 的 `openai/codex` 源码；未来版本可能变化。
3. **本机观察**：任务提供的已知样本，不代表模型或 Codex 的普遍统计规律。

本机已知样本为：父任务约 936k token；一个 `xhigh` 子代理约 799k；`medium` 约 164k；`low` 约 60k；另有一个 `xhigh` 子代理未正常终止。样本量小，适合制定保护栏，不足以拟合稳定成本模型。

## OpenAI Codex：已证实事实

### 1. 并发上限的公开语义

OpenAI 官方把 subagent workflow 定义为并行运行专门代理，再把结果汇总回主响应；每个 subagent 在独立 agent thread 中工作。本地 Codex 仅在用户直接要求，或适用的 `AGENTS.md` / skill 指令要求时委派。[O1]

公开配置字段为：

```toml
[agents]
max_concurrent_threads_per_session = 2
```

该值限制**同时 open 的 spawned-agent threads，不包括 primary thread**。未设置时由 Codex 选择默认值；官方文档不承诺固定默认数字，旧配置名 `agents.max_threads` 只是 legacy alias。[O1][O2]

官方示例分别展示 `6` 和 `8`，并给出一次六维 PR review 的提示词示例；这些是能力示例，不是适合所有桌面宿主的推荐默认值。[O1]

### 2. 当前源码的 V1/V2 实现差异

固定源码快照中：

- V1 默认 `DEFAULT_AGENT_MAX_THREADS = Some(6)`。
- V2 内部默认 `DEFAULT_MULTI_AGENT_V2_MAX_CONCURRENT_THREADS_PER_SESSION = 4`，这个内部值包含 primary；因此未显式配置时有效 spawned-agent 数为 3。
- 公开配置值不含 primary；V2 解析时先对用户值 `+1` 转成内部总槽位，再在计算 spawned-agent 上限时 `-1`。因此用户配置 `2` 的公开语义仍是两个子代理，而不是一个。[O3][O4][O5]

这些数字是当前实现快照，不是公开稳定契约。不能因为源码当前默认可运行 3 个子代理，就推导 Windows Desktop 必须配置为 3 或更高。

### 3. 深度

当前源码保留 V1 默认 `max_depth = 1`，V1 在 `child_depth > max_depth` 时拒绝 spawn。但源码注释明确说明这个配置对 V2 ignored；V2 的默认协作指令允许 child agent 再 spawn 自己的 subagent。[O6][O7][O8]

没有找到公开、稳定的 V2 nesting-depth 数值上限。由此只能得出“V2 支持递归委派且未公开等价 depth cap”，不能得出“V2 深度无限或递归是安全的”。因此项目策略应自行限制深度和所有后代总量。

### 4. wait、stop、close

官方文档说明 Codex 负责 spawn、follow-up routing、waiting 和 closing；好的委派提示应明确是否等待全部结果。Desktop 用户可要求 Codex steer/stop 正在运行的子代理，并 close 已完成线程。[O1]

当前源码存在版本语义差异：

- V1 `wait_agent(targets)` 是等待多个目标中的**任意一个**先完成；主控若要 wait-all，需继续等待尚未完成者。[O9]
- V2 `wait_agent` 等 mailbox activity、用户 steering 或 timeout；默认 30 秒，允许范围 10 秒到 3600 秒。[O10][O11]
- V1 `close_agent` 的工具契约明确：关闭目标及其 open descendants；completed agent 在 close 前仍可保持 open 并占用并发上限。[O12]

最后一条不能无条件外推为所有 V2 Desktop 版本的稳定底层契约，但足以支持一个安全操作原则：**把“结果已收到”“agent 已终止”“thread 已关闭/槽位已释放”作为三个分别确认的状态。**

### 5. token 成本与模型选择

OpenAI 明确说明，每个子代理都独立进行 model work 和 tool work，所以多代理比可比的单代理运行消耗更多 token；更高 reasoning effort 也会增加响应时间和 token 用量。[O1]

官方建议把轻量、只读、范围清楚的并行工作交给更快、更经济的模型/effort，并把 `medium` 作为多数代理的平衡起点，`low` 用于明确、重复、速度优先任务；`xhigh/max` 留给特别困难的推理。[O1]

没有找到 OpenAI 官方的“代理数 × 固定倍数”成本公式，也没有找到当前 Codex 为每个子代理公开的强制 token cap。并发数、任务总量、effort、上下文大小、输出契约和生命周期必须组合治理。

## 其他一手项目实践

### Anthropic Claude Code agent teams

Claude Code 官方文档指出 agent teams 有独立上下文，token 成本随 active teammates 线性增长；协调成本与冲突随团队规模增加，收益会递减。其建议多数工作从 3-5 个 teammates 起步，15 个独立任务可先用 3 个 teammates，并以每人 5-6 个任务维持吞吐；同时强调三个专注成员常优于五个分散成员。[A1]

官方还建议：先从 research/review 开始；避免同文件编辑；持续 monitor/steer；不要让团队长时间无人照管；明确 wait；teammate 关闭可能要等当前请求或 tool call 完成，因此 shutdown 会慢。[A1]

**不可直接类比**：agent teams 是实验性、多会话、成员可互相通信的团队机制，而 Codex subagents 通常由主控汇总；Claude 文档说没有 hard teammate limit，而 Codex 有明确的 per-session open-thread cap。Claude 的 3-5 是该机制的起步建议，不应覆盖本机已观察到的 799k `xhigh` 和未终止异常。

### Microsoft AutoGen AgentChat

AutoGen 官方提供可组合终止条件：`MaxMessageTermination`、`TokenUsageTermination`、`TimeoutTermination` 和由外部 `set()` 控制的 `ExternalTermination`；示例会把文本终止条件与最大消息数并用，避免无限循环。[M1][M2]

**可借鉴**：不要只设置并发阈值；还应同时有工作量预算、token/时间预算、语义终止条件和外部停止通道。

**不可直接类比**：AutoGen 是应用框架，开发者拥有 event loop、模型 usage 数据与 termination condition；Codex Desktop 当前并未向项目规则暴露等价的、可强制执行的 per-subagent token termination API。

### LangGraph

LangGraph 官方把并行节点放在同一个 super-step 中，并提供 `recursion_limit` 约束单次执行的最大 super-steps；还提供 proactive remaining-steps 和达到上限后抛错两种控制方式。[L1]

其 subgraph 文档进一步说明：per-invocation persistence 适合多数独立 subagent 调用并支持并行；per-thread stateful subgraph 不支持同一 subgraph 的并行调用，因为共享 checkpoint namespace 会冲突，需要禁用该并行或显式限流。[L2]

**可借鉴**：并发资格不只看“任务数量”，还要看 state/checkpoint/write seam 是否隔离；并为递归/步骤提供独立预算。

**不可直接类比**：LangGraph 的 `recursion_limit` 计算 graph super-steps，不等于 Codex 的代理 nesting depth；checkpoint namespace 冲突也不是 Codex thread slot 的同一种资源。

## 本机样本的成本解读

以已知样本做相对比较：

| 样本 | token | 相对 `low` | 相对 `medium` |
| --- | ---: | ---: | ---: |
| `low` 子代理 | 约 60k | 1.00x | 0.37x |
| `medium` 子代理 | 约 164k | 2.73x | 1.00x |
| `xhigh` 子代理 | 约 799k | 13.32x | 4.87x |
| 父任务 | 约 936k | 15.60x | 5.71x |

单个 `xhigh` 子代理已达到父任务 token 的约 85%。若两个同类代理同时出现，光子代理样本外推就约 1.60M token，尚未包含主控、工具输出和失败重试。该外推不是成本预测，只用于说明“并发 2”无法单独防止 token 爆炸。

未终止的 `xhigh` 更重要：它意味着成本、并发槽位和完成状态可能同时失控。在根因未确认前，提高并发会放大异常，而不是提高有效吞吐。

## 建议矩阵

| 任务形态 | 子代理总量 | 同时运行 | effort/model 策略 | 深度 | 生命周期与停止条件 | 推荐 |
| --- | ---: | ---: | --- | ---: | --- | --- |
| 简单、顺序、主控已掌握上下文 | 0 | 0 | 主控完成 | 0 | 无委派 | 默认 |
| 单一边界清楚的只读调查/验证 | 1 | 1 | `low`；确有歧义用 `medium` | 1 | 明确 deliverable，收到结果即确认终态并 close | 推荐 |
| 两个独立 read/review/test slice | 2 | 2 | 优先 `low/medium`；避免两个高 effort | 1 | wait-all；任何一个跑偏即 steer/stop | 推荐上限 |
| 3-4 个独立 slice | 3-4 total | 2 | `2 + 1/2` waves；第二 wave 仅在第一 wave 有净收益时启动 | 1 | 每 wave 完整收口；不得让完成线程残留占槽 | 条件推荐 |
| 共享文件、共享状态、相同 checkpoint/外部副作用 | 0-2 total | 1 | 串行 worker；主控合并 | 1 | 共享 seam 只允许一个 writer | 禁止并行写 |
| 复杂推理/安全/架构审查 | 1-2 total | `xhigh` 同时最多 1 | 先 `medium/high`，证据证明不足才 `xhigh` | 1 | 给窄问题、证据格式、时间/轮次检查点；超限 stop | 严格门禁 |
| 子代理要求再委派 | 计入 4 total | 默认不允许 | 仅已审查的只读 fan-out | 最多 2（例外） | 主控保留全局计数；后代也必须关闭 | 默认拒绝 |
| 已出现卡住、未终止、状态不明 | 0 new | 0 new | 不启动替代高 effort agent | - | 一次 steer/stop，必要时 interrupt；确认终态/槽位后再决策 | 硬阻断 |

## 动态策略：动态化任务，不动态抬高宿主上限

建议把任务级策略表达为以下决策顺序：

1. **并行资格**：至少两个可独立验证的 slice；依赖、write set、共享状态、外部副作用不重叠。
2. **最小数量**：能用 0/1 个完成就不启动 2 个；3-4 个只通过 wave 使用。
3. **最小 effort**：探索/检索/日志筛选从 `low`；常规分析从 `medium`；高 effort 仅处理已定位的困难问题。
4. **总量预算**：单任务最多 4 个 spawned descendants，包含失败替代和嵌套后代；替代代理不是免费重试。
5. **生命周期门禁**：前一 wave 的所有代理都达到可解释终态，并确认没有残留 active/open 线程，再启动下一 wave。
6. **异常降级**：一次未终止、token 异常或重复失败，即从并行切回单代理，并禁止 `xhigh` 自动重试。

可采用下列伪策略（不是当前 Codex 配置字段）：

```text
host_spawned_concurrency_cap = 2
task_descendant_total_cap = 4
default_depth_cap = 1
xhigh_concurrency_cap = 1

if slices < 2 or shared_write_or_state:
    run_serially
else:
    run_up_to_2_in_wave
    wait_and_close_wave
    start_next_wave_only_if_remaining_value > coordination_cost
```

## 等待与关闭 runbook

1. Spawn 时记录：agent id、slice、write set、模型/effort、预期 deliverable、停止条件。
2. 使用长一些的 bounded wait，避免高频 busy polling；收到状态更新后只对需要介入的代理 steer。
3. 结果返回后核对 deliverable 和 final status；不要仅凭一段总结判断线程已终止。
4. 对超出范围、无进展或明显高耗的代理先发一次 stop/steer；若仍运行，再 interrupt。
5. 对已完成线程执行/请求 close，并确认 active/open 计数恢复；再开始下一 wave。
6. 若 stop/interrupt 后状态仍不明，记为 lifecycle incident；保持串行，不启动替代 `xhigh`，也不提高并发配置。

## 对当前两个参数的明确判断

### `max_concurrent_threads_per_session = 2`

**保留。** 它低于当前源码 V2 未配置时的三个 spawned-agent 实现默认，也低于官方示例，但符合当前 Windows Desktop 的保护目标。已知样本显示风险不是“并发太低”，而是高 effort 单代理 token 极高、且出现未终止生命周期异常。等至少积累一组干净样本后再评估 3：

- 连续多个多代理任务均能确认 stop/close/槽位释放；
- 没有残留 active thread；
- `low/medium` 能覆盖大多数 read-heavy slice；
- 并发 2 的 wall-clock 确实是瓶颈，而非共享写入、429、上下文或协调成本；
- 有按任务记录 token、时长、失败和终态的证据。

满足这些条件时，只建议短期 canary 到 3，不直接跳到 6/8；canary 失败立即回到 2。

### 单任务最多 4 个子代理

**保留为 hard total cap，但改成动态额度。** 普通任务默认额度 0-2；只有 3-4 个独立 slice 且前一 wave 证明值得继续时，才消费到 4。这个上限应统计所有 descendants、失败替代和跨 wave 代理，而不是只统计同时 active 数。

四个同时运行在当前宿主上不合理；四个总量按 `2 + 2` wave 是合理的。若任务确需超过 4 个，优先合并小 slice、缩短提示和输出，或换成确定性脚本/批处理；不要先扩大代理队伍。

## 来源

### OpenAI

- [O1] OpenAI, “Subagents”, definitions, triggering, model/effort, orchestration, management, global settings and examples: https://learn.chatgpt.com/docs/agent-configuration/subagents
- [O2] OpenAI, “Configuration Reference”: https://learn.chatgpt.com/docs/config-file/config-reference#configtoml
- [O3] `openai/codex`, V1/V2 default constants: https://github.com/openai/codex/blob/936f5eb3ee223ab34dcb221fa7c5f9943c8092bd/codex-rs/core/src/config/mod.rs#L212-L216
- [O4] `openai/codex`, effective spawned-agent limit subtracts primary: https://github.com/openai/codex/blob/936f5eb3ee223ab34dcb221fa7c5f9943c8092bd/codex-rs/core/src/config/mod.rs#L1605-L1617
- [O5] `openai/codex`, public configured value converted to internal total: https://github.com/openai/codex/blob/936f5eb3ee223ab34dcb221fa7c5f9943c8092bd/codex-rs/core/src/config/mod.rs#L2733-L2744
- [O6] `openai/codex`, V1 default depth and V2 usage instructions: https://github.com/openai/codex/blob/936f5eb3ee223ab34dcb221fa7c5f9943c8092bd/codex-rs/core/src/config/mod.rs#L217-L284
- [O7] `openai/codex`, depth configuration is ignored by V2: https://github.com/openai/codex/blob/936f5eb3ee223ab34dcb221fa7c5f9943c8092bd/codex-rs/core/src/config/mod.rs#L883-L896
- [O8] `openai/codex`, V1 spawn depth rejection: https://github.com/openai/codex/blob/936f5eb3ee223ab34dcb221fa7c5f9943c8092bd/codex-rs/core/src/tools/handlers/multi_agents/spawn.rs#L63-L70
- [O9] `openai/codex`, V1 wait waits for whichever finishes first: https://github.com/openai/codex/blob/936f5eb3ee223ab34dcb221fa7c5f9943c8092bd/codex-rs/core/src/tools/handlers/multi_agents_spec.rs#L848-L874
- [O10] `openai/codex`, V2 wait tool parameters: https://github.com/openai/codex/blob/936f5eb3ee223ab34dcb221fa7c5f9943c8092bd/codex-rs/core/src/tools/handlers/multi_agents_spec.rs#L876-L885
- [O11] `openai/codex`, V2 wait defaults: https://github.com/openai/codex/blob/936f5eb3ee223ab34dcb221fa7c5f9943c8092bd/codex-rs/core/src/config/mod.rs#L213-L216
- [O12] `openai/codex`, V1 close semantics and slot retention: https://github.com/openai/codex/blob/936f5eb3ee223ab34dcb221fa7c5f9943c8092bd/codex-rs/core/src/tools/handlers/multi_agents_spec.rs#L318-L330

### 其他官方项目

- [A1] Anthropic, “Orchestrate teams of Claude Code sessions”, team sizing, token usage, waiting, monitoring, shutdown and limitations: https://code.claude.com/docs/en/agent-teams
- [M1] Microsoft AutoGen, “Termination Conditions”: https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/tutorial/termination.html
- [M2] Microsoft AutoGen AgentChat conditions API: https://microsoft.github.io/autogen/stable/reference/python/autogen_agentchat.conditions.html
- [L1] LangGraph, “Graph API overview”, parallel super-steps and recursion limit: https://docs.langchain.com/oss/python/langgraph/graph-api
- [L2] LangGraph, “Subgraphs”, persistence and parallel-call constraints: https://docs.langchain.com/oss/python/langgraph/use-subgraphs

## 未证实事项

- 未找到 OpenAI 官方对 Windows Desktop 单独给出的最优并发数字。
- 未找到公开稳定的 Codex V2 nesting-depth 数值上限。
- 未找到 Codex subagent 数量与 token 成本的固定倍率公式。
- 未通过模型探针复测本机 token 或生命周期异常；本研究只使用任务提供的已知观察。
- 未修改或验证当前宿主配置的实际加载结果；`max_concurrent_threads_per_session = 2` 按任务提供的当前值评估。
