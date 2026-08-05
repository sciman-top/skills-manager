# Agent workflow advisory runtime

**track**: `agent_workflow_advisory_runtime`
**base_phase**: `P5`
**TRACK_STATUS**: `repo_verified`
**IMPLEMENTATION_STATUS**: `repo_advisory_only`
**DECISION_OWNER**: `host_ai`
**EXECUTOR**: `host_native_runtime`
**RUNTIME_SCHEDULER_STATUS**: `not_introduced`
**PROVIDER_CALL_STATUS**: `none`
**NATIVE_MUTATION_STATUS**: `none`
**RADAR_FETCH_STATUS**: `not_implemented`
**HOST_LOADED_STATUS**: `host_evaluation_partial_pass`
**HOST_ORCHESTRATION_STATUS**: `native_spawn_observed`
**HOST_RADAR_REFRESH_STATUS**: `scheduled_run_pass`
**LIVE_ACCEPTANCE_STATUS**: `not_run`
**P6_ADMISSION_STATUS**: `hold`
**SCHEMA_POLICY**: `operation_contract_v1_compatible_no_major`

## 1. 决策摘要

用户提出的动态模型选择、长链路主 Agent、任务拆分、串并行子 Agent 协调、Radar 成本/时延参考和失败升档，属于宿主 AI 的语义与执行职责；它们不应被实现成仓库内第二个 Agent runtime。Codex 原生已经提供 subagent spawn、wait、steer、thread 汇总、custom-agent 的 model/reasoning effort 和 worktree 隔离。本 track 只补一层 runtime-independent advisory contract，让宿主可以生成可审查的任务图、请求确定性 admission、消费模型软锚点与失败建议。

本实现采用以下责任分界：

| 参与者 | 责任 | 本 track 是否写入 |
| --- | --- | --- |
| 用户 | 目标、价值排序、不可逆风险、生产/外部授权和最终否决 | 否；用户输入是 authority |
| 宿主 AI | 需求澄清、TaskGraph、串并行、模型/effort、spawn/wait/steer、升级、集成和最终综合 | 否；输出 `decision_owner=host_ai` |
| `skills-manager` | TaskGraph/Radar/FailurePacket 合同、deterministic admission、模型建议、证据和 zero-write envelope | 是 |
| Codex native runtime | 实际 agent thread、worktree、模型调用、等待、steer 和 candidate integration | 否；由宿主使用 |
| Git/tests/live probe | freshness、代码正确性、外部效果和验收真值 | 否；只记录边界 |

因此，本 track 不修改 `active_profile`、custom agent、provider/auth、sandbox、session 或当前模型；不抓取 Radar、不保存 token、不启动 daemon/queue/database，不安装社区 orchestration 项目。宿主侧的全局委派规则、默认子代理配置和 Scheduled automation 属于独立 host acceptance，不改变本仓 effect counters 或产品边界。

## 2. 为什么加入而不违背产品定位

`skills-manager` 的定位是 Windows-first/local-first capability curator 与 Rule Estate manager。TaskGraph、admission 和模型建议是已有 plan/freshness/receipt/gate 语义在 AI 软件交付场景的窄扩展：它们可验证、可回滚、复用宿主原生执行面，且不会生成第二个产品目标、注册表或控制面。它们改善的是“宿主如何安全地编排本仓任务”的可追溯性，不是替代 Codex。

仍然保留最高等级原则：官方/本仓运行事实优先；用户授权优先于模型或子代理意见；`repo_verified`、`host_loaded`、`live_accepted` 分层；不以 LLM 分数作为硬门禁；缺权限/凭据/生产授权/用户决策时 fail-closed；只选最大合理切片；shared seam 单 writer；失败先找根因再升档；任何外部写入有明确 owner、freshness、verification 和 rollback。

## 3. 输入合同

CLI 输入是 UTF-8 JSON，schema version 1，最小字段如下。字段名与 `tests/fixtures/agent-workflow/valid-request.json` 保持一致；不再增加第二套 task manifest。

```json
{
  "schema_version": 1,
  "now": "RFC3339",
  "task_graph": {
    "schema_version": 1,
    "graph_id": "stable-id",
    "base_revision": "git-revision-or-explicit-baseline",
    "integration_owner": "host-agent-id",
    "tasks": [
      {
        "task_id": "stable-task-id",
        "goal": "one outcome",
        "inputs": [],
        "outputs": [],
        "depends_on": [],
        "risk": "low|medium|high",
        "ambiguity": "low|medium|high",
        "parallelizable": true,
        "exact_write_set": [],
        "coordination_keys": [],
        "external_state": [],
        "verification": ["command-or-check"],
        "result_owner": "one-owner",
        "integration_order": 1,
        "stop_condition": "observable-condition"
      }
    ]
  },
  "radar_snapshot": {
    "schema_version": 1,
    "snapshot_id": "immutable-id",
    "source": "https://codexradar.com/",
    "captured_at": "RFC3339",
    "expires_at": "RFC3339",
    "raw_hash": "sha256",
    "entries": []
  },
  "completed_task_ids": [],
  "requested_parallel_task_ids": [],
  "model_proposals": []
}
```

`FailurePacket` 是换档、重试或重切片的前置输入，必须包含 `issue_id/task_id/base_revision/failure_kind/attempt_count/escalation_count/attempted_tier/commands/failures/verified_facts/unresolved_questions/artifacts/exact_write_set`。failure kind 只允许 `task/context/tool/capacity/permission/credential/production_authorization/user_decision/unknown`。

## 4. 任务拆分与编排

宿主 AI 按以下顺序拆分，每个 task 只拥有一个可验证结果：

1. 读取 Product Baseline，澄清最多三个会改变方案/验收的问题；把不可逆授权和未决问题显式化。
2. 先建立 read-only discovery/impact/constraint task，固定 `base_revision`，记录输入、输出和停止条件。
3. 按结果依赖形成 DAG。若任务需要前序输出或共享事实，保留依赖；不要为了“并行”复制上下文或制造角色接力。
4. 对每个 task 声明 tracked、generated、untracked、external 的精确 write set、coordination key、外部读写和验证命令。
5. 将低风险、边界清楚、互不写同一资源的实现/文档/测试切成独立候选；把 schema/migration、生成链、共享配置、Git index/ref、最终集成和 full gate 固定为串行。
6. 每个候选都要能单独验证、丢弃和回滚；由一个 integration owner 按拓扑顺序消费候选。

### 4.1 串行/并行决策表

| 情形 | 调度 | 原因 |
| --- | --- | --- |
| 需求澄清、架构基线、影响分析 | 串行主链；可有 2–3 个只读 panel | 只有宿主能综合冲突和决定目标 |
| 互不依赖、只读探索/日志分片/测试盘点 | 可并行 | read-heavy，结果可独立验证 |
| 不同精确文件、固定 base、无共享 key 的实现/文档/单测 | 可在隔离 worktree 并行 | write set 互斥且候选可丢弃 |
| 同一文件/目录、source/generated 对、lock/config、schema/migration | 串行 single writer | merge 成功不能证明语义安全 |
| 同一外部 issue/API/数据库对象或生产系统写入 | 串行且需授权 | external state 有不可逆副作用 |
| 依赖前序产物、冲突解决、candidate integration、full gate | 串行 | 需要稳定输入和唯一 owner |

### 4.2 确定性 wave 算法

`New-AgentExecutionPlan` 先验证 TaskGraph，再按 `integration_order/task_id` 做拓扑排序。每一 wave 只放入依赖已完成的 task；同 wave 内先放 serial task，再把 `parallelizable=true` 的 task 按 exact write set、coordination key、external resource 做 greedy disjoint grouping。任何验证失败都返回 `pass=false`，不返回可执行 wave。该算法只输出计划，不创建线程、不等待、不调用模型。

## 5. 并行 admission 与并发拉起

`Test-AgentParallelAdmission` 必须在宿主拉起并发前通过。准入条件是：

- 请求至少包含两个已声明 task，task ID 不重复且均存在；
- 所有 `depends_on` 已在 `completed_task_ids` 中，DAG 无 unknown/cycle；
- `base_revision` 相同且非空；
- 每个 task 有唯一 `result_owner`、`verification` 和 stop condition；
- `exact_write_set` 无通配符，候选间路径互斥；空 write set 只代表 read-only，不代表可写共享；
- `coordination_keys` 不出现同资源的任意 write 冲突；外部 `write` 与任何同资源任务冲突；
- candidate 能在自己的 worktree/branch 独立构建、测试、丢弃；integration owner/order 已声明。

通过 admission 后，由宿主 AI 调用 Codex 原生 subagent/worktree surface，并为每个 task 传递最小 context、base、write set、verification 和 stop condition。宿主等待同一 wave 的结果，再由 integration owner 串行集成；本仓 CLI 的 `provider_calls/native_mutations/writes` 永远为 0。

## 6. 四档模型软锚点

四档只作为 host proposal 的可覆盖起点，不能被 deterministic script 静默路由：

| tier | 软锚点 | 默认适用任务 |
| --- | --- | --- |
| `sol_xhigh` | `gpt-5.6-sol + xhigh` | 需求/产品澄清、总体架构、跨服务生产 RCA、高价值高风险审查、最终裁决 |
| `sol_medium` | `gpt-5.6-sol + medium` | 一般实现、日常 Bug 排查、中等复杂度审查、集成准备 |
| `terra_high` | `gpt-5.6-terra + high` | 用户偏好的 balanced 默认；read-heavy 扫描、独立评审、边界清晰的中等任务与成本/时延敏感任务 |
| `luna_max` | `gpt-5.6-luna + max` | 常规接口、SQL、单测、技术文档、机械变换和边界清晰的重复任务 |

实际选择优先级为 `user override -> local comparable outcomes -> current host availability -> fresh Radar snapshot -> host native default`。`Terra high` 是当前用户明确覆盖的 balanced 默认；Radar 后续变化只能生成可审计建议，不能自动提升为 `Terra max`。费用、wall-clock、token/context、重试/返工和不可逆风险一起构成 Pareto 观察；不得把每天变化的 Radar 排名硬编码为总分或永久配置。模型不存在、宿主不可用或 snapshot stale 时返回 `host_default` 与 fallback reason。

## 7. Radar snapshot

Radar 只允许通过显式导入/刷新动作产生不可变 snapshot；本 track 不实现联网抓取。每个 entry 必须有 `model_label/model_family/reasoning_effort/score/estimated_cost/estimated_duration_seconds/sample_count/confidence`，snapshot 必须有 `source/captured_at/expires_at/raw_hash`。`expires_at <= now`、来源非 HTTP(S)、hash 非 SHA-256、样本/指标缺失或 schema 不兼容时 fail-closed，并忽略 Radar 对模型选择的影响。

本地历史结果必须能记录同类任务的 gate pass、rework、actual cost/duration、人工纠正和集成成本；Radar 的社区分数不能替代真实任务证据，也不能证明 `live_accepted`。2026-08-05 的 host acceptance 已手工生成并验证 ignored snapshot，并创建每日 21:00 的宿主 Scheduled automation；首个 scheduled run 于 21:05 产生 21-entry fresh snapshot 并通过本仓 validator。它不构成本仓 scheduler/provider runtime，也不能自动修改模型配置。

## 8. 失败与难度超预期

失败处理是有限状态机，而不是无限重试：

```text
route
  -> root-cause packet
  -> one corrected retry (same tier, corrected context/tool)
  -> task/context: add evidence or rescope/replan
  -> tool: repair tool or reassign
  -> capacity only: Luna max -> Terra high -> Sol medium -> Sol xhigh
  -> same issue_id second failure: supervisor serial takeover / clarify
  -> permission, credential, production authorization, user decision: fail-closed
```

`Get-AgentEscalationDecision` 只在 `Test-AgentFailurePacketContract` 通过后给建议。一次失败不直接升档；同一 issue 第二次失败必须重新规划，两个升档或 high-risk task 由 supervisor 串行接管。缺权限、凭据、生产授权或用户产品决定时，升档没有意义，必须停止并请求相应授权/澄清。升级不会改变 write set、base 或用户授权。

## 9. CLI 与零副作用合同

构建后的 `skills.ps1` 提供：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 agent-validate --input tests/fixtures/agent-workflow/valid-request.json --json
pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 agent-plan --input tests/fixtures/agent-workflow/valid-request.json --json
```

两个命令只读取 repo-contained JSON，输出稳定 envelope：`truth_boundary=repo_advisory_only`、`decision_owner=host_ai`、`executor=host_native_runtime`、`provider_calls=0`、`native_mutations=0`、`writes=0`。验证失败 exit code 为 2；输入路径越界、缺失或非法选项直接报错。领域/application 代码不得读取文件、时钟、环境变量、网络或 terminal；IO 仅在 command adapter。

## 10. 实施切片

| Slice | 文件 | 停止条件 |
| --- | --- | --- |
| AWA-001 | 本 spec、manifest、产品映射 | 产品边界、truth level、非目标和官方依据可追踪 |
| AWA-002 | `src/Domain/AgentWorkflow.ps1` | TaskGraph/Radar/FailurePacket v1 纯合同通过 focused tests |
| AWA-003 | `src/Application/ModelAndAgentPolicy.ps1` | wave/admission/model/escalation deterministic tests 通过 |
| AWA-004 | `src/Commands/AgentWorkflow.ps1`、`src/Main.ps1`、`src/Version.ps1`、`build.ps1` | CLI build、JSON envelope、zero-write/provider-free 通过 |
| AWA-005 | verifier、tests、evidence、产品/任务索引 | verifier + full gate 通过；未产生 host/live 变更 |

每个切片保持单一 write set；生成的 `skills.ps1` 只由 build 生成，`agent/`、vendor、reports 和 host state 不属于本 track 的手工写入。

## 11. 验证矩阵

| 层级 | 命令 | 证明 |
| --- | --- | --- |
| focused | `Import-Module Pester -RequiredVersion 4.10.1; Invoke-Pester tests/Unit/AgentWorkflowContracts.Tests.ps1` | 领域/application/command 合同、负例和 zero-write |
| build | `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` | 依赖顺序和生成入口 |
| CLI | `skills.ps1 agent-validate/agent-plan ... --json` | 真 bundle 的 exit/envelope/wave |
| verifier | `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-agent-workflow-advisory.ps1 -Json` | track、边界、代码接线、软锚点、禁止项 |
| full | `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` | 唯一 closeout gate；顺序为 build -> tests -> contracts -> hotspot |

缺失 Pester、Python 或宿主工具按仓库 N/A 规则记录；不以 synthetic fixture、Radar snapshot 或 CLI pass 宣称业务收益、host_loaded、live acceptance 或模型质量。

## 12. 回滚与退役

回滚只撤销 AWA-001..005 声明的源码、CLI 接线、verifier、测试、文档、manifest 和 evidence；保留 PS7-only 迁移、M0/M0.2/M0.3 历史 truth、M1 registry、host config、provider/auth、generated cache 和用户改动。回滚后重建 bundle 并运行 PS7 policy/full gate。

若 Codex 原生未来提供等价、可验证的 TaskGraph/admission/model proposal/FailurePacket trace，则本 track 缩减为兼容 verifier；若真实 M1 replay 没有相对 native-only baseline 的净收益，删除 advisory CLI 和非必要字段，不创建 P6。只有跨进程/跨主机真实并发反复超出 native worktree + Git + host ownership 能力，且用户重新授权时，才进入 P6 评估独立 coordinator。

## 13. 官方与社区依据

- Codex manual：`https://learn.chatgpt.com/docs/agent-configuration/subagents`、`https://learn.chatgpt.com/docs/automations`、`https://learn.chatgpt.com/docs/models`、`https://learn.chatgpt.com/docs/long-running-work`。官方说明 Codex 可因适用 `AGENTS.md`/skill 条件性委派，subagent 适合 read-heavy/可独立任务，写入需隔离 worktree；Sol 适合复杂开放任务，Terra 适合速度/效率优先的辅助工作，Luna 适合快速、清晰、重复任务；更高 reasoning effort 增加时间和 token；宿主负责 spawn/wait/steer/汇总，Scheduled task 承接稳定重复工作。
- Codex configuration：`https://learn.chatgpt.com/docs/config-file/config-reference`。custom agent 可以声明 model/reasoning effort，但显式 spawn/宿主配置优先级属于宿主边界，本仓不修改。
- Codex Radar：`https://codexradar.com/` 只作为用户指定的时变社区观察输入；其每日成本/时延/分数必须经 snapshot、hash、expiry 和本地结果复核后才可影响建议。
- 社区项目只提供协议启发，按既有 `references/reference-shelf.manifest.json` 和 `docs/EXTERNAL_REFERENCE_REPO_TIERS.md` 记录，不执行外部脚本，不引入第二控制面。

**最大声明**：本 track `repo_verified` 只证明 deterministic advisory contract、CLI 接线、文档和 verifier。独立 host acceptance 已观察到 Sol xhigh、Sol medium、Terra high 原生子代理，fresh CLI 已加载全局规则/配置，手工与首个 scheduled Radar snapshot 均通过本仓 validator；这些仍只是 `host_evaluation_partial_pass`，不证明任意任务都会自动委派、Luna 在所有 spawn surface 可用、模型策略产生普遍净收益、外部生产动作获授权或业务 `live_accepted`。
