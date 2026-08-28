# MOR-001：自动故障切换的离线模拟准入规格

**状态**：proposed / design-only（2026-08-29）；不改变 [MOR-000](MOR-000-brief.md) 的 `decided_deferred`，不授权创建 runtime、网络探测、模型调用、宿主写入或后台进程。
**归属**：未来独立 `<runtime-root>` 中的可选模块；不得进入 `skills-manager` runtime、`skills.json`、`skills.ps1` 或当前 MOR 的离线 `Resolve` 实现。
**关联**：[PRD](../product/cross-host-model-orchestration-prd.md) §4.2、§6.1、§9 · [架构](../product/cross-host-model-orchestration-architecture.md) §1、§3、§6 · [MOR-000](MOR-000-brief.md)
**Truth boundary**：本文件和未来 synthetic test 最多证明 `repo_verified` / `simulated_runtime_verified`；绝不证明 `filesystem_projected`、`host_loaded`、模型可用、账户授权、结果质量或 `live_accepted`。

## 1. 决议与不变量

当前 MOR 的正式合同仍为“人工声明 -> scoped `operator_override` -> 离线 Resolve”，任务失败只能追加 receipt，**不得** reroute、retry、切换 preset 或写入状态。本规格只定义未来是否准入一个独立的自动故障切换模块；未获该模块的独立授权前，任何自动行为均为禁止。

该模块必须是一个深模块：调用方只提交结构化失败证据、当前选择与一份策略快照，获得一个无副作用的 `FailoverDecision`。失败分类、fallback 图、风险门、熔断、冷却、恢复滞后和 receipt redaction 都在模块内部；调用方不得各自实现 `if Sol then Terra`。

```text
EvaluateFailover(FailoverRequest, FailureEvidence, FailoverSnapshot, Clock)
  -> FailoverDecision
```

`Clock` 与 `HostHealthAdapter` 都是内部测试 seam：离线模拟使用 fake clock 和 scripted adapter；生产候选若获批准才可接入真实观察。`EvaluateFailover` 本身不得发网络请求、读 credential、改 host state、改 preset、重试任务或启动新任务。

## 2. 候选策略（尚未启用）

每个 scope 固定为 `(canonical_host, identity_binding, workspace_scope)`；不得把一个身份或工作区的失败扩散到其他 scope。普通新任务的候选图为：

```text
Sol-only   -- eligible service fault --> Terra-only -- eligible service fault --> Luna-only
Terra-only -- eligible service fault --> Sol-only   -- eligible service fault --> Luna-only
Luna-only  -- eligible service fault --> Sol-only   -- eligible service fault --> Terra-only
```

这里的顺序仅是用户选定的候选顺序，不表达模型质量、能力或高风险等价性。一次决策最多给出一个下一候选；不会在单一任务中串行执行多个模型。正在运行的任务永不热切换，决策最多影响一个尚未开始的后续新任务。

以下规则优先于图：

| 条件 | 决策 |
| --- | --- |
| `risk_level=high` | `blocked_high_risk`；Terra substitute 仍需现行 emergency approval，Luna-only 固定 block |
| native bridge (`design-griller` / `cold-capability-runner`) | `out_of_scope_bridge_pin`；继续使用独立 Terra/high pin |
| 当前模型/effort 的 host tuple 未经 exact fixture 与 live observation 证实 | `manual_host_selection_required`；不得自动写选择 |
| 候选 preset 不满足单模型族、三 route key 或 operation/constraint 合同 | `blocked_policy` |
| 运行中的任务 | `not_applicable_running_task` |

## 3. 失败分类与熔断

自动切换不是任何错误的同义词。生产候选只能把独立、结构化的宿主观察映射为稳定 reason code；不能从 prompt、模型名字、异常文本模糊匹配或一次 timeout 猜测。

| 证据类别 | 初始 disposition | 原因 |
| --- | --- | --- |
| `service_overload`、`service_unavailable`、已分类 `server_error` | `eligible_service_fault` 候选 | 可进入模拟 fallback 图，但仍受 tuple、风险和 cooldown 门约束 |
| `transport_error` / timeout | `manual_diagnosis_required` | 可能是本机网络、代理或宿主问题，不能误报为模型故障 |
| `auth_error`、`permission_error`、`organization_policy` | `manual_intervention_required` | 换模型通常不能修复身份或组织策略 |
| `billing_error`、`account_state`、`rate_limit` | `manual_intervention_required` | 不能把账户或限额问题隐蔽为模型选择 |
| `request_invalid`、`unsupported_model_or_effort` | `manual_mapping_required` | 需要修正静态 Adapter 合同或请求，而非自动跨族降级 |
| 未分类、证据冲突或缺少 observed source | `blocked_unclassified_failure` | fail closed |

每个 scope 的 future state 只能包含最小必需的 circuit state：`closed`、`open`、`half_open`、`cooldown_until`、`last_reason_code` 与 policy revision。进入 `open` 后只能在 fake/受控 clock 到达 `cooldown_until` 时允许一次 `half_open` 观察；失败会延长 cooldown，成功才回到 `closed`。不得设置 daemon、watcher 或定时扫描；生产恢复观察必须属于一项明确授权的新任务入口。

恢复不是立即反复回切。fallback preset 在其 scope 的 cooldown 内保持 sticky；恢复原默认需要一个合格的 `half_open` 观察和新的、尚未开始的任务。这样避免 Sol/Terra 来回抖动，也不改变已经冻结的 RouteDecision。

## 4. 仅离线模拟验收

模拟器的 HostHealthAdapter 只从 scenario 读取预写值，严禁访问网络、OAuth、模型、gateway、`~/.codex` 或任何用户级配置。每个 scenario 必须使用固定假时钟、固定 policy revision、固定 scope 和明确的 expected decision；不得以真实时间或上次运行结果决定输出。

| ID | 初始选择 / scripted evidence | 期望决策 | 必须断言 |
| --- | --- | --- | --- |
| `SIM-001` | Sol-only；Sol=`service_unavailable`，Terra=`healthy` | `recommend_temporary_terra_only` | 仅影响后续新任务；无 host write、无模型调用 |
| `SIM-002` | Sol-only；Sol/Terra=`service_unavailable`，Luna=`healthy` | `recommend_temporary_luna_only` | receipt 保留 Sol -> Terra -> Luna 的已评估链与最终候选 |
| `SIM-003` | Terra-only；Terra=`service_overload`，Sol=`healthy` | `recommend_temporary_sol_only` | 回探顺序先 Sol 后 Luna |
| `SIM-004` | Luna-only；Luna=`server_error`，Sol=`healthy` | `recommend_temporary_sol_only` | 不跨任务重试，不修改 persistent default |
| `SIM-005` | 任一；三者皆 `service_unavailable` | `blocked_no_eligible_candidate` | 不循环、不写 override、不伪造 healthy |
| `SIM-006` | Sol-only；`auth_error` | `manual_intervention_required` | 不探测 Terra/Luna |
| `SIM-007` | Terra-only；`rate_limit` | `manual_intervention_required` | 不探测 Sol/Luna |
| `SIM-008` | Sol-only；`transport_error` / timeout | `manual_diagnosis_required` | 不把传输故障升级为服务故障 |
| `SIM-009` | 任一；`risk_level=high` + eligible service fault | `blocked_high_risk` | 不选 Terra/Luna；现有审批要求不被绕过 |
| `SIM-010` | Sol fallback 后，在 cooldown 内 Sol 反复 healthy/unavailable | `keep_current_temporary_selection` | 无抖动、无第二次探测、无 persistent write |
| `SIM-011` | Sol fallback 后，clock 到期；Sol=`healthy` | `recommend_restore_sol_only` | 只对新任务；需明确 half-open 证据 |
| `SIM-012` | bridge role 的 Terra/high pin 失败 | `out_of_scope_bridge_pin` | 通用 preset 图完全不介入 |
| `SIM-013` | 候选 Codex tuple 不在 host tuple allowlist | `manual_host_selection_required` | 不以 API 面 verified 外推 Codex config 面 |
| `SIM-014` | 已运行任务收到 eligible service fault | `not_applicable_running_task` | 不热切换、不改变 frozen candidate |

`SIM-001` 至 `SIM-014` 全部通过只能证明 simulated state machine 对该策略快照的确定性一致，不是任何真实 provider/host 健康结论。

## 5. Simulation receipt 合同

模拟 receipt 是未来 runtime 的独立工件，不能伪装为现有 MOR `RouteReceipt`，也不能含 `observed_host_route`、`host_loaded` 或 `live_accepted`。最低形状如下：

```json
{
  "schema_version": 1,
  "scenario_id": "SIM-003",
  "mode": "offline_simulation",
  "truth_boundary": "simulated_runtime_verified",
  "scope": {
    "host": "codex_cli",
    "identity_binding": "synthetic-redacted",
    "workspace_scope": "synthetic"
  },
  "initial_selection": "gpt56_terra_only",
  "failure_evidence": {
    "reason_code": "service_overload",
    "source": "scripted_host_health_adapter",
    "observed_at": "2026-01-01T00:00:00Z"
  },
  "policy_revision": "sha256:synthetic",
  "evaluated_candidates": ["gpt56_sol_only"],
  "decision": "recommend_temporary_sol_only",
  "state_mutation": "none",
  "network_calls": 0,
  "host_writes": 0,
  "model_calls": 0
}
```

Verifier 必须拒绝缺少 `scenario_id`、非 `offline_simulation` 模式、未知 reason/decision、跨 scope 候选、`state_mutation != none`、或任一调用计数非零的 receipt。secret、prompt、完整 endpoint、token、cookie、账户信息和真实 workspace path 一律禁止写入。

## 6. 推进门与停止条件

| 阶段 | 允许工作 | 进入条件 | 退出证据 |
| --- | --- | --- | --- |
| 当前：规格 | 文档审查、离线 scenario 设计 | 无；保持 MOR-000 deferred | 本文 reviewed；无 runtime 或 host 改动 |
| Future A：纯离线 simulator | 独立 runtime 的 pure evaluator、fake adapter、fake clock、scenario tests | 用户指定 `<runtime-root>` 和 owner；单独确认 write set | `SIM-001..014` 通过，且零网络/零 host write 由 test spy 证明 |
| Future B：人工确认切换 | 只读诊断 + 生成 temporary override plan | A 通过；每个目标 host tuple 已静态验证 | 当前用户确认后才可应用 scoped/expiring override |
| Future C：自动切换候选 | 受控 health observation、circuit breaker、expiry/recovery | B 的代表性 host fixture 与 live observation；单独风险审批、rollback、审计方案 | 不同 error class、抖动、身份隔离、risk/bridge 排除和真实 host write/readback 全部验证 |

任何阶段若 tuple、identity binding、target ownership、失败分类、审批、回滚或 receipt verifier 不完整，结果都是 `blocked` 或人工 handoff。Future C 不是当前用户对网络探测、模型调用、宿主写入、常驻后台进程或自动恢复的授权。

## 7. 回滚

本文件在 design-only 阶段没有运行态副作用；删除本文件及索引链接即可回滚文档切片。未来任何 runtime 实现都必须单独记录其代码、状态、host projection 与 rollback receipt，不能使用本文替代。
