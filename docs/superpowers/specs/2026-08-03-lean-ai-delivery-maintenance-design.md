# Lean AI Software Delivery maintenance design

**program_id**: `skills-manager-vnext`
**track**: `maintenance_design`
**base_phase**: `P5`
**status**: `repo_verified`
**P6_ADMISSION_STATUS: hold**
**PILOT_STATUS: collecting**
**RUNTIME_IMPLEMENTATION_STATUS: no_runtime_implementation**
**LIVE_ACCEPTANCE_STATUS: not_run**
**METRICS_MODE: observe_only**
**METRICS_COMPLETION_GATE: false**
**CONTROL_PLANE_STATUS: not_introduced**
**SHARED_WRITE_SET_POLICY: single_writer**
**GIT_CAS_SEMANTICS: ref_freshness_not_file_queue**
**TOOL_DISPOSITION_POLICY: adopt_adapt_defer_reject**
**MODEL_POLICY_STATUS: host_advisory_only**
**RADAR_SNAPSHOT_POLICY: advisory_expiring_snapshot**
**TYPED_CORE_STATUS: poc_not_started**
**POWERSHELL_COMPATIBILITY_STATUS: ps7_primary_ps51_bounded_smoke**
**日期**: 2026-08-05

## 1. Problem and evidence

AI 编码的主要浪费不再只是模型不会写代码，而是交付控制面失真：需求与定位未澄清便开始实现；先搭框架、治理、角色和测试矩阵，首条用户价值链却未跑通；多个“角色”机械交接但无人对端到端结果负责；同一风险被多层门禁重复证明；局部失败持续打补丁而不重新检查方向；一次成功或自我总结被直接写成长期 skill，污染后续工作流。

本仓已有事实同时给出约束和复用面：P5 已提供结构化 task model、最小 capability DAG、session/preheat recommendation 和只读 host snapshot；现有 PRD/task/plan/evidence 已能表达 goal、write set、verification、rollback 和 truth level；full gate 已是唯一 closeout 编排入口。因此当前问题可以先通过 advisory contract、文档追踪和 deterministic verifier 处理，没有证据需要第二套 agent runtime。

本设计响应的用户证据是：需要从模糊产品想法连续推进到设计、实现和验证，同时避免过度设计、方向漂移、角色接力、门禁膨胀与 token 空耗。M0 只证明这些要求被准确落盘并可机械校验；真实效果必须由后续 pilot 观察。

M0.2 进一步响应“AGOS coordinator/lease/Git CAS + Trellis task workflow + OptSkills/GBrain/code graph”组合建议。可复用的是明确 owner、write scope、candidate、freshness、evidence、replay/eval 和退役思想；不能照搬的是第二套 scheduler/ledger/lease database、自动 reviewer、provider/embedding/solver、长期 daemon/knowledge database 或全仓多 Agent 索引。Git CAS 只保护 ref/expected-old 与内容 freshness，不是文件级队列；同一路径必须由 coordinator admission 和单 writer 解决。

## 2. Goal and target user

目标是让单个高级用户把 ChatGPT/Codex/Claude 等宿主 Agent 与 skills-manager 组合为更高效的软件交付工作流：用户提供初始目标与必要决策，主 Agent 负责讨论、规划、实施、修复和证据闭环，skills-manager 帮助选择最小能力组合并守住范围、停止条件和完成等级。

Primary user 是 Windows-first、维护多个本地仓库、希望显著减少人工盯守但不接受虚假完成的个人开发者。Secondary user 是需要一致任务契约、可审查证据和低维护成本的仓库维护者。AI Agent 是合同消费者，不是本产品托管的 worker。

## 3. Product constitution

North Star：在不复制宿主原生推理、编码和运行能力的前提下，最大化 verified value、correctness 和 user outcome，同时最小化 user attention、wall-clock latency、provider/model spend、token/context、retry、coordination/integration、maintenance cost 与不可逆失败风险；任何辅助功能都必须证明相对 native baseline 的 Pareto 净收益，并始终可绕过、可回滚、可替换、可删除。

1. 用户价值主链优先：先有可演示结果，再稳定化和重构。
2. 官方/宿主原生优先：复用模型推理、Codex/Claude 执行、plugins、skills、MCP、hooks 和权限系统。
3. 本地与目标仓真值优先：repo 文件、当前命令和 native probe 高于中央模板与模型记忆。
4. 最小能力组合：只加载当前模式需要的 lens/skill/tool，不串联完整流程目录。
5. 有界自主：可逆、授权内、write-set 内连续执行；方向、风险、权限或生产边界变化才询问。
6. 根因与两次失败重规划：同一问题第二次失败后停止补丁循环。
7. 最低充分验证：一个风险由最低能证明它的层级覆盖；full suite 只由 closeout gate 统一运行。
8. 证据决定状态：规划、实现、repo、host 与 live 状态严格分层。
9. 学习必须可回放、可否定、可退役：未经 reviewed promotion 的总结不能成为稳定规则。
10. 可删除性优先：模型/宿主能力增强或 pilot 无净收益时，主动删除、合并或降级本项目功能。
11. 单一结果 owner：设计可并行讨论，写入只能在明确 coordinator、base revision、write set、集成 owner 与回收条件下并行。
12. Git 是 truth spine，不是 control plane：branch/worktree/candidate commit 保存版本与隔离，任务排队、lease/reassign 和业务裁决仍由宿主与当前计划负责。
13. 工具按证据准入：没有 native baseline 缺口、真实消费者、安全边界、evaluation 和 retirement trigger 的候选保持 defer。

## 4. In scope / out of scope

In scope：

- 把面向高效 AI 软件交付的总体定位、问题、需求、原则、模式和指标并入既有产品真源。
- 定义 Product Baseline、Slice Contract、checkpoint、bounded autonomy、责任 lens 和 skill lifecycle 的逻辑合同。
- 定义 M0-M3 maintenance 路线和 10-task observe-only pilot 的准入/退出方法，并以轻量 registry 启动真实样本收集。
- 提供 machine-readable maintenance manifest、companion verifier、负向测试和一份 reviewed evidence。
- 在同一 maintenance manifest 中增加 M0.2 工程化协调/工具组合任务，扩展 M1 sample observation，但不增加样本类别、runtime object 或第二个 registry。
- 在同一 manifest 中增加 M0.3 host-owned TaskGraph/model policy、Radar snapshot、failure escalation 与 typed-core migration decision；只增加 planning/verifier/test/evidence，不改 host/runtime。

Out of scope：

- 新 agent runtime、planner service、长期任务引擎、daemon、数据库、模型/provider router 或固定角色团队。
- 修改 `src/`、`overrides/`、`skills.json`、profile、schema major、host auth/config/session、plugins/MCP 状态。
- 安装或运行 Hermes、Obsidian 插件、Spec Kit、OpenHands、LangGraph 或其他社区 runtime。
- 安装或运行 Trellis、AGOS、OptSkills、GBrain、CodeGraphContext、Understand Anything；创建 coordinator/lease daemon、dashboard、数据库、自动 reviewer 或 Git hook control plane。
- 伪造、回填或在当前切片内宣称完成真实 10-task pilot；生产部署、付费模型调用、跨仓 apply 或业务 `live_accepted` 验收。
- 把 spec-driven development 的强制 TDD、每任务文件数限制或全流程人工审批移入本仓契约。
- 动态抓取 Codex Radar、静默选择/切换模型、修改 `.codex/agents`/active session、实现 model router/scheduler/provider gateway，或在本切片创建 C#/.NET project/PoC、迁移任何 PowerShell 生产 seam。

## 5. Lifecycle modes

| Mode | 核心问题 | 最小输出 | Checkpoint |
| --- | --- | --- | --- |
| `Discovery` | 为谁解决什么，何为成功？ | baseline、最多三项关键问题、假设与非目标 | 方案选择所需信息充分 |
| `Main-chain` | 最短用户价值链怎样跑通？ | 端到端薄切片、真实输入、可观察结果 | 主路径最低充分验证通过 |
| `Stabilize` | 已观察失败的根因是什么？ | 根因修复、必要边界测试 | 同一失败不可复现且无关键回归 |
| `Refactor` | 哪个重复/热点已有证据？ | 行为保持的最小结构改进 | contract 保持且热点改善 |
| `Release` | 如何安全交付和回滚？ | 唯一 closeout gate、发布/回滚证据 | 目标等级验证完成 |
| `Operate` | 如何观察、分流、恢复和学习？ | 事件证据、owner、恢复与反馈 | 事件闭合或形成新 Discovery 输入 |

模式可回退，不是瀑布。主链回归就回到 Main-chain；用户价值或验收变化就回到 Discovery。简单、边界清楚的修复无需补齐所有模式文档。

## 6. Product Baseline

复杂或方向敏感任务开始前，以现有 PRD/spec/task 字段建立一页内逻辑 baseline：

- `target_user`：谁使用，谁拥有最终接受权。
- `problem_and_evidence`：当前可复核痛点、样本或失败，不以假想扩展代替。
- `desired_outcome`：用户可观察的变化，不写内部组件数量。
- `success_signals`：首个主链 checkpoint 与目标 verification level。
- `scope / non_goals`：本切片做什么和明确不做什么。
- `constraints`：兼容、安全、资源、时间、权限和外部依赖。
- `assumptions / open_questions`：可逆假设与最多三项真正改变方案的问题。
- `truth_boundary`：最高允许声明到 designed、implemented、repo_verified、host_loaded 或 live_accepted 的哪一级。

baseline 放在当前任务 spec/plan 中；不创建第二个数据库、全局 registry 或长期 memory。事实变化时显式更新并说明影响的 slice，而不是在实现中静默漂移。

## 7. Slice Contract and checkpoint

每个实施切片复用 task manifest 字段：ID、goal、depends_on、preconditions、exact write_set、implementation_steps、tests、verification、rollback、done_when 和 out_of_scope。plan 只添加顺序与 exit checkpoint，todo 只提供同 ID 状态。

checkpoint 回答四个问题：用户可见/可验证增量是否出现；write set 是否仍在授权边界；最低充分验证是否通过；下一步是继续、稳定化、重构、发布还是回到 Discovery。切片没有用户增量或风险证据时，不以新增 schema、wrapper、fixture、evidence 或抽象数量代替进展。

## 8. Bounded autonomy loop

主 Agent 按以下循环持续执行：读取当前 repo/user truth；选择当前 mode 与最大合理切片；在授权和 write set 内实施；运行 affected verification；对照 checkpoint；通过则记录证据并继续；首次可恢复失败先做根因诊断与一次修复；同一 `issue_id` 第二次失败则停止局部补丁并重规划。

必须询问或停止的情况：产品方向/目标用户/验收发生实质变化；write set、权限或风险等级越界；需要凭据、付费、生产、不可逆或外部协作动作；多个可行方案会导致不同产品结果且无法由仓库事实裁决。其余可逆细节以显式假设推进。

自主循环不以固定 Agent 数、固定轮数、token 消耗或所有 lens 都被调用为完成条件。完成只由 slice checkpoint 与相应证据决定。

## 9. Role responsibility lenses

主 Agent 保持单一端到端 owner，并按当前 mode 启用责任 lens：product/business 负责用户价值与范围；project/delivery 负责关键路径与依赖；UX/accessibility 负责旅程和状态；architecture/data 负责 seam、兼容、迁移与回滚；frontend/backend/mobile 只在对应产品面存在时负责实现；quality/security 负责真实失败、权限与供应链；release/operations 负责环境、观测与恢复。

lens 是问题清单，不是常驻角色、审批者或独立状态机。只在探索、测试或审查可以独立且 write set 不重叠时才使用多 Agent；共享 seam 采用单 writer，分支/worktree 隔离并由主 Agent 集成和收口。

当目标/功能/需求/定位或关键 seam 需要多视角时，coordinator 可让 2–3 个 Agent 只读地产生独立候选。每个候选必须声明假设、推荐 interface、trade-off、风险、验证和反例；coordinator 只综合一份决定进入本 spec/task。panel 不修改文件、不向外部系统发消息、不发布，也不因“多数同意”获得 authority。

写入并行必须通过 admission：依赖完成、base revision 固定、每个 writer 的 exact write set 互斥、generated/external writes 已声明、candidate 可独立丢弃/验证、integration order 与 owner 明确。共享文件、source/generated seam、schema/migration、lock/config、Git index/ref、同一外部对象或内容依赖任务一律单 writer/串行。

lease 只是当前 coordinator 记录的 `owner + task_id + write_set + base_revision + expires_or_recovery + revoke/reassign` claim，不落独立服务。过期不删除 worktree/commit；reassign 前必须确认旧 writer 停止并复核 candidate/base/target hash。Git `update-ref`/`--force-with-lease` 和 file hash 只检测 stale；它们不排队文件、不提供公平锁、不自动决定 winner。

## 10. Capability routing behavior

路由顺序为：识别 task type/domain/operations/risk；确定 lifecycle mode；应用用户显式要求和 required/excluded intent；优先复用当前已加载且只读的能力；只为当前 checkpoint 建最小 ordered DAG；弱证据 abstain；任何写/安装/认证/生产能力都只生成 approval/activation plan。

默认 surface 映射：一次性约束进 prompt/thread；稳定仓库事实进 `AGENTS.md`；重复且验证稳定的单一工作流进 skill；需要可安装组合时进 plugin；动态外部数据/动作进 MCP/connector；确定性生命周期拦截进 hook/script/CI；计划和证据继续留在 Markdown/JSON/Git。不得因为能力可用就全部预热或级联调用。

宿主 Agent/Goal/Plan/subagents/worktree/review 负责执行控制面；本项目只校验 planning interface。candidate 集成固定为：验证 base 与 declared write set -> 检查 target/hash freshness -> 按依赖顺序 merge/cherry-pick/apply -> integration owner 处理冲突和 affected gate -> 文件稳定后唯一 full gate -> truth closeout。子 Agent 局部 pass、candidate commit 或 CAS 更新成功不证明整体完成。

## 11. Anti-overdesign stop conditions

出现任一信号立即回到 checkpoint：主链未通却新增三个以上非产品 artifact；计划外长期维护面出现；一个风险被两层以上重复门禁覆盖；新抽象没有两个真实调用点、稳定外部协议、安全 seam 或量化热点；实现无法用一句话说明用户增量；focused feedback 被重复 full gate 取代；文档、角色或测试数量增长但失败证据没有减少。

默认处置优先级是删除 > 复用 > 直接实现 > 延后 > 新抽象。必要止血补丁要记录回收条件；重构只在主链已通且行为 characterization 可证明时进行。门禁失败必须修复根因，但不得借失败扩张到无关治理。

## 12. Skill learning/promotion/retirement

经验先保留为 task-local note。只有同一 workflow 在至少两个代表任务重复、包含一个失败/反例、输入输出可定义时成为 `skill_candidate`。候选依次经过 replay（历史样本）、shadow（不改变真实执行）、canary（有限真实任务）、人工 reviewed promotion；每步记录相对无 skill baseline 的 TTFV、返工、打断、误触发和 artifact 成本。

promotion 后仍需 owner、适用/禁止场景、版本、失败分流和退役条件。模型/宿主原生能力覆盖、触发精度下降、长期无消费者、维护成本高于收益或流程产生方向性误导时，选择 revise/merge/retire。find-skills 得到的第三方 skill 先作为不可信候选，核对来源/revision/license，再按相同 lifecycle 适配；不直接在全局生效。

OptSkills 只证明数学优化领域可以从 trajectory/cluster 提取候选库并分离 learning/eval/checkpoint；它不证明本仓 skills/workflow 可自动升级。M0.2 采用更窄的 `real sample -> replay -> shadow -> bounded canary -> reviewed promotion -> retain/revise/retire`，并要求 library/write promotion 串行、provider-free deterministic gate 与 host/live evidence 分层。

## 13. Tool-combination boundaries

默认组合是 `host-native execution + repo-native search/docs/tests + Git/worktree + affected gates + one closeout gate`。新增工具必须通过一个 reviewed `ToolDispositionView`：source/revision/license/trust、problem evidence、native equivalent、real consumers、`adopt | adapt | defer | reject`、integration mode、data/auth/write boundary、evaluation、maintenance cost、retirement trigger 和 truth level。字段不全保持 defer。

| Surface/tool | 当前决定 | 准入条件 | 回退/退役 |
| --- | --- | --- | --- |
| ChatGPT/Codex/Claude + Goal/Plan/subagents/worktree/review | adopt native baseline | 当前宿主可用且符合权限/仓库契约 | surface 不可用时单 Agent + Git；不由本仓复制 |
| `AGENTS.md` | adopt durable repo guidance | 跨会话稳定、仓库特有、可落命令/边界 | 低频细节下沉 spec/runbook/skill |
| skills-manager | adopt current curator/advisor/verifier | 本仓独有 discovery/policy/transaction/evidence seam | native equivalent 出现或 M1 无净收益则缩减 |
| narrow skill | adapt after replay | 两个代表任务 + 一个反例 + baseline 净收益 + 禁止触发 | revise/merge/retire |
| plugin | conditional | 确有重复分发对象、无官方等价、供应链 owner | 回到 source skill/MCP 或官方 plugin |
| MCP/connector | conditional current external data/action | live truth/action 是任务必需且 auth/side effect 可见 | disable/remove，回到 repo/static docs |
| Trellis `v0.7.0-beta.1` | adapt ideas / defer install | 本仓现有 spec/task/journal 无法满足的重复真实缺口 + AGPL/distribution review | 继续使用现有 task/spec/AGENTS/native host |
| AGOS `0.1.0` Alpha | adapt protocol / reject runtime now | 独立多执行器/CI provenance 成为真实产品目标且人工审计完成 | current task/write set/Git/receipt |
| OptSkills | adapt learning method only | workflow 有代表样本、provider-free replay 和 reviewed promotion | task note/candidate，禁止自动 promotion |
| GBrain | defer | 两个独立跨资料检索失败 + privacy/auth/database/daemon/backup/restore evidence | Markdown/docs/rg/connector |
| CodeGraphContext | defer | 当前语言覆盖（本仓 PowerShell）、关系准确、fresh index 和资源净收益 | rg/symbol/test/dependency verifier |
| Understand Anything | defer | 大仓 onboarding/impact 分析真实失败 + 首轮 token/LLM/hook/graph 生命周期可接受 | repo docs/native exploration |
| “souljourney lightweight workflows” | defer unknown source | 唯一 repo/source/revision/license 可核验 | 不采纳口述名称 |

knowledge/code-graph adapter 只允许 read-only canary，并同时声明最小 root、敏感数据/redaction、language/parser coverage、index source revision/captured_at、stale/rebuild、CPU/RAM/disk/token/latency、package/revision/license、外部调用、卸载和索引删除。任何缺口 fail-closed 并回退 `rg`、符号、测试、依赖报告与仓库文档；图谱、摘要和知识库永不成为源码、task 或 acceptance 真源。

组合协议优先普通 Markdown、JSON、Git、路径和显式 receipt。任何工具都可被替换或退役，不允许形成隐式双写、共享私有状态、静默 host/profile mutation 或要求另一个工具先在线。

面向用户只保留四类稳定意图：`Discover` 发现能力与仓库事实；`Advise` 生成最小组合、规划/规则建议和退役判断；`Transact` 仅通过既有显式 token、freshness、backup/receipt/rollback seam 执行受管写入；`Verify` 分层证明 repo、host 与 live 状态。Lean Delivery 只消费 `Discover + Advise + Verify`，不会借 advisory 自动取得 `Transact` 权限。

### 13.1 Host-owned TaskGraph and model policy

责任边界固定为：user intent = authority owner；host AI = accountable semantic coordinator；skills-manager = evidence and policy advisor；deterministic verifier = admission and safety guard；Codex native runtime = subagent executor；Git/tests/scripts/live probes = truth adjudicator。宿主负责拆分、串并行、spawn/steer/wait/stop、模型档位、升级、集成和最终综合，本仓不得以 lexical router、LLM proxy 或后台 scheduler 替代。

长链路任务的最小合同：

```text
TaskGraph:
  task_id, goal, inputs, outputs, depends_on, risk, ambiguity,
  parallelizable, exact_write_set, external_state, verification,
  result_owner, integration_order, stop_condition

ModelPolicy:
  radar_snapshot_id, captured_at, expires_at, model, reasoning_effort,
  host_availability, score, estimated_cost, estimated_duration,
  sample_count, confidence, fallback, escalation_trigger, user_override

FailurePacket:
  base_revision, task_id, attempted_model, attempted_effort, commands,
  failures, verified_facts, unresolved_questions, artifacts,
  exact_write_set, next_recommendation
```

三档默认策略只是软锚点：

| 档位 | Host-resolved pair | 默认任务 | 不应自动承担 |
| --- | --- | --- | --- |
| `Sol xhigh` | `gpt-5.6-sol` + `xhigh` | 需求/产品澄清、架构与大型重构、跨服务生产 RCA、高风险代码审查、最终 integration/adjudication | 清楚且机械的批量任务 |
| `Sol medium` | `gpt-5.6-sol` + `medium` | 一般实现、日常 Bug 排查、中等复杂度审查、集成准备 | 缺权限/工具/用户决策的问题 |
| `Luna max` | `gpt-5.6-luna` + `max` | 清楚、窄、可重复和高吞吐的 CRUD/SQL/单测/文档/机械转换、异步 workers | 承重架构裁决或失败后的无限重试 |

`Host-resolved pair` 是当前可理解的 model/effort 组合，不是永久 model ID 白名单；宿主不可用、名称变化或 Radar stale 时由宿主选择当前官方/default，并在 ModelPolicy 中记录实际值和 override reason。

Radar refresh 与 task execution 分离；snapshot 必须显式产生、记录原始 hash 和过期时间，不能在每个 task 隐式联网。stale/unavailable 时回退宿主官方/default；本地同类任务的 gate、返工、费用、时长和人工纠正优先于榜单。Radar 不证明准确率、生产质量或 live acceptance，模型策略不压成永久单分数。

串并行 admission：完全只读或 exact write set 互斥、base 固定、依赖完成、外部写入可见、candidate 可独立验证/丢弃、integration owner/order 明确时才可并行。共享 file/config/lock/source-generated seam、schema/migration/backfill、Git index/ref、同一外部对象、内容依赖和 final integration/full gate/closeout 一律串行。并发数由宿主可用槽位和任务独立性共同约束，不以“模型更强”放宽 write-set 规则。

升级状态机：initial route -> root-cause diagnosis 后一次 corrected retry -> task/context 问题则补证据或 re-scope -> 只有 capacity 问题按 `Luna max -> Sol medium -> Sol xhigh` 升档 -> 同一 issue 两次失败 clarify/re-plan -> 两次升级或承重风险由 supervisor 串行接管。缺 auth/permission/tool/production/user decision 直接 fail-closed。禁止无 `FailurePacket` 换档、同 prompt 无限重试、子 Agent 扩大 write set 或运行中无审计热切换。

### 13.2 PowerShell and typed-core migration contract

当前事实：PS7 build 和 generated bundle 通过，PS5.1 parse/plain-object smoke 通过；这些证据只证明当前有界兼容合同，不证明 PowerShell 对 AI 长期维护最优。PowerShell 动态类型、parser/quoting、encoding、native process、错误传播与 5.1/7 差异确实增加 AI 修改的返工面，因此技术方向从“永久 PowerShell core”柔化为“当前 PowerShell runtime + protocol-first + 条件性 C#/.NET typed core”。

候选比较结论：C#/.NET 在 Windows/native CLI、编译期类型、结构化并发、测试、framework-dependent/self-contained/single-file 分发上最匹配，推荐作为唯一 PoC；TypeScript/Node 增加 Node/npm/打包面，Python 增加解释器/venv/Windows path/encoding 面，Rust 的迁移/维护成本在当前规模过高，均保持 defer。PowerShell 仍保留 installer、旧 CLI aliases、Junction/host adapter、bundle 和错误呈现；typed candidate 只承接纯 domain/policy/validation。

PoC admission 必须同时满足：一个 read-only pure seam；至少两个真实 caller；已有 characterization corpus；versioned stdin/stdout UTF-8 JSON、stable finding/exit contract；当前受支持 .NET LTS pin proposal；PowerShell 与 candidate shadow parity；framework-dependent/self-contained 的启动/体积/发布数据；无外部写入/daemon/provider/host mutation；旧路径可一键回退；PoC 可删除。通过后仍按一个 seam 一次迁移并保持单一实现真源；不允许长期双写、双配置或全仓重写。

## 14. Outcome metrics and pilot design

M1 需要 10 个真实任务，覆盖模糊需求、从零主链、缺陷修复、重构、跨 seam 实现、测试策略、发布、运维、能力选择和简单任务负样本。`tasks/skills-manager-vnext-lean-delivery-pilot.json` 只在任务达到证据停止点后追加样本；synthetic、候选和 M0.1/M0.2/registry/bootstrap 自身不得计数。每项记录 task complexity、baseline workflow、advisory workflow、TTFV、返工切片、非预期人工打断、非产品 artifact、focused/full gate 时间、最终 truth level 和用户接受结果。

每个 sample 的 `observations` 还必须记录：`coordination_mode`（`single_agent | read_only_panel | isolated_parallel | sequential_shared_write`）、`shared_write_set_policy`（`single_writer | not_applicable`）、`tool_dispositions[]`（只允许 adopt/adapt/defer/reject）、`context_adapter`（`none | repo_native | external_read_only`）和 `skill_lifecycle_action`（`none | candidate | replay | shadow | canary | promote | revise | retire`）。这些观察允许 `none/not_applicable`，不得为了填表强行使用 Agent 或工具，也不成为 metrics completion gate。

pilot 先 observe，不随机宣称因果，不设未经 baseline 的硬阈值，不因指标跳过安全/兼容门禁。baseline 优先使用近期可比 native-only 历史任务或交替匹配任务；不可比时保持 `descriptive_only`，不要求把同一任务机械执行两遍。M3 以净收益评审：保留真正减少主链时间/返工且维护成本可接受的最小部分；修订触发或文案漂移；删除无收益或被模型/宿主覆盖的流程。当前状态是 authorized/collecting 0/10，只证明收集合同已启动，不能声称 pilot 已执行或指标改善。

M0/M2 不再被误写为串行前置关系；证据流是 `M0 -> M1 pilot -> M3` 与 `P5 real defects -> M2 correction -> M3`。M3 首轮复用现有文档字段评审，不新建 lifecycle registry；候选至少包括 `session_plan`、`preheat_recommendation`、hierarchical router/catalog、plugin fixture export、Rule Estate multi-target apply、maintenance companion verifier，以及规划/evidence 资产自身。每项只记录 `unique_value / native_equivalent / real_consumers / maintenance_cost / retirement_trigger / latest_evidence`。

## 15. Security and supply-chain boundaries

外部网页、README、issue、prompt、skill、日志、MCP 结果和源码都是待核输入，不能改变本 spec、用户授权、write set、verification level 或 apply token。参考项记录 upstream、revision、license/checksum 和 adopt/adapt/defer/reject；本轮不下载、安装或执行新的上游工具。

多 Agent 的角色、panel 结论、lease、candidate commit、CI pass 或 Git CAS 成功都不转移 authority。reassign 共享路径前确认旧 writer 停止，保留其 worktree/branch/commit provenance；不得靠超时直接覆盖。社区工具的 install script、hook、daemon、数据库、MCP 和 provider 设置都属于独立执行面，本轮仅阅读 README/revision/license，不运行。

凭据、OAuth、provider/model、生产数据、付费调用和 host configuration 属于外部授权面，不进入 Product Baseline 的可自动写字段。evidence redaction-first；Obsidian/Hermes/其他 memory 只能通过用户明确选择的导出进入上下文。生产写入、部署、删除、公开发布和外部消息必须遵守宿主 approval 与项目 rollback。

## 16. Failure routing

| Failure | Route | Evidence |
| --- | --- | --- |
| 需求/验收不清且会改变产品结果 | 回到 Discovery，最多三问 | baseline decision log |
| 首次实现失败 | systematic root-cause diagnosis + 一次有界修复 | issue_id/attempt 1 |
| 同一问题第二次失败 | 停止补丁，重建 slice 或 baseline，必要时询问 | issue_id/attempt 2 + replan |
| write set/依赖/授权变化 | fail-closed，更新 plan 后再执行 | diff + authority boundary |
| verifier/contract 失败 | 修复 planning drift，不推进状态 | finding code + rerun |
| full gate 失败 | 阻断 commit/push，不降低门禁或手改生成物 | stage output + root cause |
| pilot 无净收益 | revise/retire，不把流程晋级为 skill/P6 | reviewed metric worksheet |
| write-set overlap / owner missing | 拒绝并行，改为单 writer 或重切互斥 slice | admission record + exact paths |
| lease expired / writer status unknown | 停止 reassign，确认旧 writer 并保存 candidate | task/worktree/branch/hash evidence |
| target/base/hash drift | 拒绝 candidate integration，rebase/replan 后重新验证 | expected/current revision + diff |
| Git CAS 被描述为文件锁/队列 | planning verifier fail-closed，修正文档/任务 | `ref_freshness_not_file_queue` contract |
| context adapter admission 不完整 | 保持 defer，回退 repo-native 工具 | language/privacy/freshness/resource/supply-chain matrix |
| Radar snapshot 过期/来源或样本不可核验 | 忽略 snapshot，回退官方/native default；不改 host config | captured_at/expires_at/raw_hash + host availability |
| 子任务首次失败 | 诊断 task/context/tool/capacity 根因，只允许一次 corrected retry | issue_id + FailurePacket + attempt 1 |
| 同一 issue 第二次失败或两次升档 | 停止并行，re-scope/clarify；承重任务由 supervisor 串行接管 | attempt/escalation history + new TaskGraph |
| PowerShell 语法/兼容回归 | 先缩小 seam、修当前运行真源并通过 PS7/full + 5.1 bounded smoke；不得借机全仓重写 | parser/error + compatibility tests |
| typed-core parity/分发/回滚不达标 | 删除 PoC，继续 PowerShell 单一真源；不得保留双实现 | corpus diff + delete/rollback receipt |
| host/live 未执行 | 保持 not_run/not_verified | truth boundary |

## 17. Verification order

`VERIFICATION_DECLARATION_START`

1. `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1`
2. 运行 `ProductPlanning.Tests.ps1`、`LeanAiDeliveryPlanning.Tests.ps1` 与 `PowerShellCompatibility.Tests.ps1` 的 focused Pester tests。
3. `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-vnext-planning.ps1 -Json`
4. `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-lean-ai-delivery-planning.ps1 -Json`（同时校验 M1 registry/status/counting/truth boundary）
5. `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree`
6. `git diff --check` 与 `git status --short --branch`

`VERIFICATION_DECLARATION_END`

full quality gate 只运行一次并拥有完整 suite；focused tests 用于本切片反馈，不在 closeout 前后重复声明独立完整 suite。verifier 均为 local/read-only，不访问网络、host auth/config 或 provider。

## 18. Task mapping

| Task | Requirements | ADRs | Deliverable |
| --- | --- | --- | --- |
| `SMV-MD-001` | FR-LDL-001/002/004/005/006 | ADR-SMV-012/013/015/016 | 同步 PRD、架构、路线图和产品索引 |
| `SMV-MD-002` | FR-LDL-001/002/003/006 | ADR-SMV-013/014/015 | 落盘本 spec、manifest、plan 和 checklist |
| `SMV-MD-003` | FR-AIE-005、NFR-LDL-001/002 | ADR-SMV-013/014/016 | companion verifier 与最小 fixtures 测试 |
| `SMV-MD-004` | FR-EVD-003、NFR-LDL-003 | ADR-SMV-012/013/016 | 根契约、共享 evidence、有序门禁和 truth closeout |
| `SMV-MD-005` | FR-EWF-001/003/004/005/006/007 | ADR-SMV-024 | coordinator、只读 panel、lease/write-set admission 与 Git CAS truth |
| `SMV-MD-006` | FR-EWF-008/009/010/011/012 | ADR-SMV-025 | tool disposition、context adapter、skill lifecycle 与 M1 observation contract |
| `SMV-MD-007` | FR-AIE-005、NFR-EWF-001/002/003/004 | ADR-SMV-024/025 | companion verifier 的 evidence-group、M0.2 和负向边界测试 |
| `SMV-MD-008` | FR-EVD-003、NFR-TRU-001、NFR-EWF-001 | ADR-SMV-013/024/025 | 产品索引/根契约、M0.2 evidence、唯一 full gate 与 truth closeout |
| `SMV-MD-009` | FR-EWF-013/014/015/016/017、NFR-EWF-005 | ADR-SMV-026 | TaskGraph、模型三档、Radar snapshot、并发 admission 与 escalation contract |
| `SMV-MD-010` | PP-012、NFR-EWF-006、NFR-TEC-001 | ADR-SMV-001/002/027 | PowerShell 风险判断、typed-core 目标架构、TC0-TC3 与兼容/回滚边界 |
| `SMV-MD-011` | FR-AIE-005、FR-EVD-003、NFR-TRU-001 | ADR-SMV-026/027 | M0.3 verifier/tests、产品/根状态、独立 evidence 和唯一 full gate |

manifest 是 M0/M0.2/M0.3 依赖、write set、步骤、验证、回滚、evidence group 和 done_when 的机器真源。本表只提供 requirement/ADR 可追踪入口；M1 不进入 maintenance task DAG，而由独立轻量 registry 登记真实样本。

## 19. Rollback

回滚范围只包含 maintenance design 的产品真源增量、当前 spec/manifest、M1 registry observation 增量、plan/todo maintenance 章节、companion verifier/tests、PowerShell compatibility runbook、产品索引/AGENTS/README 状态行和本逻辑切片 evidence。M0、M0.2、M0.3 使用独立 evidence group，回滚 M0.3 不改写前两组历史证据。不得修改或回滚 P0-P5 manifest/spec/evidence、`src/`、`overrides/`、`agent/`、`vendor/`、`skills.json`、reports、host/model config 或宿主状态。

若 verifier 设计本身错误，先保持 track 为未验证并修复或删除 companion 资产；P5 仍由原 verifier 和历史真源独立成立。若后续 pilot 无净收益，删除/降级 advisory 候选和 pilot metadata，不删除已验证的 P5 capability selection/runtime-independent contracts。

## 20. Done definition

M0/M0.2 历史完成真值保持不变。M0.3 完成仅当：现有 PRD/架构/路线图仍为唯一产品真源；maintenance spec/manifest/plan/todo 与 M1 registry 完整；M0 四项、M0.2 四项和 M0.3 三项 planning tasks 均为 done；三个 evidence group 各自可追；错误 Git CAS/shared-write、runtime model routing、stale Radar、无 failure packet 升档、PowerShell/typed-core 双真源、P6/runtime/live 越级的负向 tests fail-closed；新旧 verifier、focused tests 和唯一 full gate 通过；P5 保持 5/5 `repo_verified`；P6 保持 hold 且不存在 P6 manifest；pilot 为 collecting 0/10，`TYPED_CORE_STATUS=poc_not_started`，live/runtime 状态保持本文件头部声明。

允许的完成表述是“maintenance design M0/M0.2/M0.3 与 M1 collecting contract repo_verified”。禁止表述为 coordinator/lease/model-routing runtime、Radar 模型选择效果已证明、custom-agent/host config 已修改、typed core/PoC 已实现、PowerShell 已替换、Trellis/AGOS/GBrain/code graph 已安装，多 Agent/工具组合收益已证明，10-task pilot 已执行/完成、P6 已准入或产品已 `live_accepted`。
