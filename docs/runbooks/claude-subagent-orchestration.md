# Claude 子代理编排与模型/档位规则（运行手册）

**状态**: 运行边界；模型与并发建议未经基准测试；官方事实已于 2026-10-17 核对（见 §1）。
**适用**: Claude Code 宿主（Desktop Code tab 与 CLI）。
**不适用**: Codex / ZCode 的 `src/model-orchestration/presets.json` 策略。该策略没有 Claude 写入适配器，不得外推到 Claude。
**边界**: 本手册不修改 `presets.json`，不写 `~/.claude` 设置，也不声称宿主已按本规则运行。

## 1. 官方能力边界（已核对）

来源：[子代理](https://code.claude.com/docs/en/sub-agents)、[模型配置](https://code.claude.com/docs/en/model-config)、[速率限制](https://platform.claude.com/docs/en/api/rate-limits)。

- 子代理可并行。默认并发上限 20，可由 `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` 改变；超限时新派发报 `Concurrent subagent limit reached`。
- 嵌套默认深度 3。`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` 可关闭嵌套。
- 子代理模型解析顺序：Agent 调用的 `model` 参数 → frontmatter `model` → `CLAUDE_CODE_SUBAGENT_MODEL` → 主会话模型。
- 子代理 frontmatter 的 `effort` 覆盖会话级 effort，但不覆盖 `CLAUDE_CODE_EFFORT_LEVEL`。
- Agent 工具的宿主说明要求：只有用户、CLAUDE.md 或 skill 明确要求时才设置 `effort`，不得凭自身判断设置。
- 自动委派由子代理 `description` 与当前上下文决定。`context: fork` 的 skill 不继承父对话历史。
- 速率限制：429 表示当前请求被限流；`retry-after` 是服务端给出的等待依据。不能仅凭缺少 `retry-after` 推断为消费上限，须按响应正文、错误代码和当前 provider 状态分类。

## 2. 派发条件

- 只有同时满足以下条件才派发子代理：用户或适用规则授权委派；切片彼此独立；写集互斥；有最低证明；有停止条件。
- “继续”或要求深入分析不构成委派授权。
- 任务简单、可在父代理顺序完成时，不派发。

## 3. 模型选择（可选经验）

| 任务形态 | 建议 model | 说明 |
| --- | --- | --- |
| 只读检索、分诊、定位文件 | `haiku` | 结果由父代理复核 |
| 常规实现、标准审查、有界修改 | `sonnet`（或继承） | 默认档 |
| 跨模块架构、安全、疑难根因 | `opus` | 派发说明须写明理由 |

- 上表是任务复杂度参考，不是硬性路由合同。除非用户或适用项目规则明确要求固定档位，默认继承主会话模型与 effort。
- 不得为绕过某个模型的限流、配额或风控错误而静默切换模型。
- 不在派发时临时设置 `effort`。需要固定档位时，写在用户维护的子代理定义 frontmatter 中，属于用户授权的配置。
- 未指定时继承主会话模型与 effort。

## 4. 并发（可选经验）

- 并发上限不是性能目标。只有切片独立、写集互斥、最低证明和停止条件都已明确，且并行净收益为正时才并行。
- 批量任务可以先以少量切片核对结果与成本，再在原有授权范围内放量。连续没有 429 只说明未观察到限流，不能证明并行提升了验收效率。

## 5. 重试与升级（核心规则）

| 信号 | 动作 |
| --- | --- |
| 429 / quota / rate-limit | 停止当前任务，报告失败分类和证据；`retry-after` 只作为等待与后续决策依据，不触发自动重试 |
| 429 且没有 `retry-after` | 同上；保留响应正文与错误代码，缺头本身不等于消费上限 |
| 529 / overload / unavailable | 只有在当前规则明确允许且已确认该分类时，下一有界任务最多做一次显式重选；目标档位须经宿主当前能力验证并记录原因 |
| 认证、权限、风控类错误 | 停止，等待用户处理 |
| 工具失败、输入缺失 | 不升档，不重放，先修复输入 |
| 写操作已发生或不确定 | 不重放提示，不并行发起重复请求 |

- 升档不是修复错误的方式。失败后不因“换更强的模型”而重试。
- 不自动重试限流、配额、认证、权限、风控或计费失败；再次派发须来自用户授权、provider 状态恢复或新的有界任务。
- 不静默降档或换模型。任何模型变化都须显式、可追溯。

## 6. 与冷技能契约的映射

与 [capability-router](../../overrides/custom/capability-router/SKILL.md) 的 `execution_contract` 一致：

- `one_shot`：仅当宿主存在对应的子代理定义时使用子代理；否则父代理 parent-mediated 执行，并如实标注。
- `multi_turn_user_decision`：父代理一次只提出一个问题并等待回答。不得由子代理替代为一次性总结。
- `host_admission_required`：父代理读取已校验闭包，按当前用户授权执行。不得伪造 runner 的 admission。

## 7. 证据要求

- 声称“已派发”“已用某模型”或“已并行”，须有宿主事件（工具调用记录）作证据。子代理的自述不能替代事件。
- 声称“冷发现已触发”，须有 `capability-router` 的 Skill 调用与 `route-capability.ps1` 的 Bash 调用记录。

## 8. 未验证项

- 官方文档没有说明“重试或并行会导致封号或降智”。本手册的保守重试与限流控制是基于速率限制文档的预防措施，不是对封号机制的证明。
- 本手册的模型分档与并发数是建议值，尚未经过基准测试。
- Claude 子代理定义的写入不在本手册范围内。写入 `~/.claude/agents` 或 `~/.claude/settings.json` 需要单独授权。
