# skills-manager vNext 产品文档索引

**program_id**: `skills-manager-vnext`
**文档状态**: active
**最后更新**: 2026-08-03

## 1. 目的

本目录定义 `skills-manager` 从“skills/MCP 管理脚本”演进为“本地 AI 能力策展器与规则全域管理器”的产品方向。这里描述的是产品目标、架构和后续实施契约，不把设计态能力写成当前已实现能力。

产品终态保持以下边界：

- Windows-first、local-first、single-process、CLI-first。
- 辅助 ChatGPT Work、Codex App/CLI/IDE 和其他受支持宿主，不替代宿主 runtime、插件目录、权限、认证、模型、会话或 agent loop。
- 优先复用官方应用、官方插件、原生 CLI、MCP/Agent Skills 等开放协议和高质量社区实现。
- 管理发现、筛选、期望状态、差异、显式投影、验证、证据和回滚，不建设中央跨仓控制面。
- 规则能力默认 `advisory-first`；任何写入必须经过显式 plan/apply 边界。

## 2. 文档职责

| 文档 | 唯一职责 | 不得承载 |
| --- | --- | --- |
| [PRD](skills-manager-vnext-prd.md) | 用户、问题、需求、非目标、产品级验收 | 代码文件级步骤 |
| [架构](skills-manager-vnext-architecture.md) | bounded context、模块依赖、数据契约、ADR、技术栈 | 路线状态和任务勾选 |
| [路线图](skills-manager-vnext-roadmap.md) | Phase、依赖、入口/退出门禁、状态边界 | 逐文件实现细节 |
| [规则治理参考采纳矩阵](rule-governance-adoption-matrix.md) | 官方/参考仓模式的 adopt/adapt/reject/defer 与验证边界 | 当前宿主安装或跨仓写入状态 |
| [规则全域 reviewed change-set](rule-estate-reviewed-change-set.md) | 全局/多目标仓 plan、apply、resume、rollback 输入契约 | AI 自行批准或宿主加载证明 |
| [Phase 5 Spec](../superpowers/specs/2026-08-03-capability-manager-vnext-phase-5-design.md) | 当前 adaptive decision plane、host snapshot、兼容和测试契约 | 宿主 runtime 或认证实现 |
| [实施计划](../../tasks/plan.md) | Phase 5 执行顺序、检查点、失败分流 | 产品背景全文 |
| [任务 manifest](../../tasks/skills-manager-vnext-phase5.tasks.json) | AI 可解析的任务、依赖、write set、验证、回滚、完成条件 | 长篇设计解释 |
| [任务清单](../../tasks/todo.md) | 人类可扫描的当前任务状态 | manifest 中的结构化细节副本 |
| [planning verifier](../../scripts/verify-vnext-planning.ps1) | 机械校验上述资产的一致性 | 判断产品价值或宿主 live acceptance |

## 3. 事实优先级

发生冲突时按以下顺序裁决产品事实：

1. 当前代码、命令输出和宿主 native probe。
2. 根 `AGENTS.md`、本目录 PRD/架构、当前 Phase spec。
3. 任务 manifest、实施计划、todo。
4. README、历史计划、change evidence。
5. 外部参考仓和社区资料。

官方文档决定宿主加载、技能、插件、MCP、hooks 和配置语义；当前 session 的可调用能力可证明当前环境事实。社区项目只提供结构、测试和打包启发。

## 4. 状态词汇

| 状态 | 含义 | 可否写成“已完成” |
| --- | --- | --- |
| `implemented` | 代码已存在并通过本仓相应门禁 | 仅限门禁覆盖的 repo-side 范围 |
| `planning_contract` | 文档、任务和 verifier 已落地 | 只能说规划契约完成 |
| `designed` | 已有被接受的行为/架构设计，尚未实现 | 否 |
| `pending` | 已进入任务 manifest，尚未开工 | 否 |
| `conditional` | 只有触发条件满足后才评估 | 否 |
| `repo_verified` | 仓库侧静态/测试验证通过 | 不等于宿主加载或 live acceptance |
| `host_loaded` | fresh native probe 证明宿主加载 | 不等于用户/生产验收 |
| `live_accepted` | 明确的真实工作流或人工验收已完成 | 可以，必须附证据范围 |

## 5. 当前基线

截至 2026-08-03：

- `skills.ps1`、`skills.json`、skill projection、MCP profile/sync、目标仓审查、doctor、reference shelf 和质量门禁已经存在。
- 本目录、Phase 0 spec、Phase 0 task manifest 和 planning verifier 属于本轮新增的 `planning_contract`。
- OperationPlan/Receipt v1 的 pure constructors、validators、freshness、truth-state 和 redaction已达到 `repo_verified`；通用 legacy write path 未整体迁移，Rule Estate 已采用专用 reviewed plan/receipt/resume/rollback 合同。
- UTF-8 atomic file writer 已提取到 Infrastructure，`SaveCfg` 是首个直接 caller，其他 caller 继续通过 legacy wrapper 保持兼容。
- host capability/truth-state matrix 已达到 `repo_verified`：5 个宿主、7 条 evidence，validator 禁止无证据 affirmative claim、unknown 写入和自动 `live_accepted`；它不扫描本机安装状态。
- P0/P1/P2 已分别 9/9、9/9、7/7 `repo_verified`；2026-08-02 follow-through 增加 `rule-estate-audit`、单仓 patch，以及 reviewed global/project multi-target plan/apply/receipt/resume/rollback。真实 apply 仍需独立 review/token，且不等于 `host_loaded` 或 `live_accepted`。
- P3 已完成 7/7 `repo_verified`：只读 inventory、manifest lint、fixture-only exporter 和分层 eval 均有仓库证据；plugin install/host load/live acceptance 未执行。
- P4 已完成 6/6 `repo_verified`：unified selection + activation planning、真实投影和 16-profile fresh prompt probe 已通过；不接管宿主 runtime，未执行 plugin/MCP activation、OAuth 或 live acceptance。
- P5 已完成 6/6 `repo_verified`：字段级 runtime truth、App aliases、MCP protocol defaults、复合工具风险聚合、逐 capability identity probe、source/runtime 双证据与 ordered full gate 均已通过。authenticated business action 与 `live_accepted` 未执行。
- `governed-ai-coding-runtime` 只作为静态规则模型参考；不得恢复其已退役的目标仓 registry、同步器或中央 verifier。
- “全局 + 项目 1+1>2”已定义为 `common + platform_delta + project_action` 的责任覆盖合同；read-only Rule Advisor 已接通显式责任映射和 repo path/command 静态核验，通用自然语言语义精度仍不作外推。

## 6. 维护规则

- 改产品范围先改 PRD，再判断是否影响架构、路线图和任务 manifest。
- 改模块、数据契约或写入协议先改架构和当前 Phase spec。
- 改 Phase 状态先提供退出门禁证据，再改路线图和 task status。
- task manifest 是任务 ID、依赖、write set 和完成条件真源；todo 只保留相同 ID 的简表。
- 运行 `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-vnext-planning.ps1` 校验文档和任务一致性。
- 规划 verifier 通过只证明规划资产内部一致，不证明产品代码、宿主加载或真实使用效果。
