# 跨宿主模型编排控制面架构

**状态**：design-only；目标为独立的 host-local runtime，不修改 skills-manager runtime
**关联**：[PRD](cross-host-model-orchestration-prd.md) · [路线图](cross-host-model-orchestration-roadmap.md) · [实施计划](cross-host-model-orchestration-implementation-plan.md) · [验收 Runbook](../runbooks/cross-host-model-orchestration-acceptance.md)

## 1. 架构结论

实现一个小而深的 **Model Orchestration Module**，只处理“指定宿主和身份的新任务，应使用哪个已批准的 model/effort route”。它不是 gateway、provider manager、账号管理器或第二套任务执行器。

日常模式固定为：

```text
每个 (host, identity) 有一套稳定 host_default
  -> 正常任务只做离线 Resolve
  -> 用户发现可用性变化后，向当前宿主 AI 明确声明
  -> 该宿主只写当前 scope 的 operator_override
  -> 用户说“恢复默认”时，只删除当前 scope 的 override
```

它没有运行期环境发现：不读模型列表、OAuth、token、gateway、账号套餐或请求状态；任务失败也不会自动重试、换模型、改写 preset/default/override，或修改宿主配置。变化来自用户明确声明，证据等级标为 `operator_declared_unverified`。

## 2. 深模块、Adapter 与数据流

```text
                reviewed policy_source (tracked, no secrets)
                                  |
          static Adapter contract + workload/risk policy
                                  |
private host_default ------> Model Orchestration Module <------ private operator_override
                                  |
                            frozen RouteDecision
                           /                    \
                 PrepareLaunch               PlanProjection
                      |                           |
             native command/handoff      verified native target only
                      |                           |
                task receipt           projection/rollback receipt
```

模块内部拥有 route-source precedence、三档 workload 模板、风险 gate、静态 allowlist、receipt redaction 与受控投影事务。Host Adapter 只翻译经人工复核的宿主语法和已验证 target；它不能自己选模型、猜 effort、处理认证/限流、重写共享配置或扩张身份范围。

若删除模块，default/override precedence、风险约束、脱敏和回滚规则会重新散落到 Codex、Claude Code、ZCode 调用者中，因此该模块通过 deletion test。无实际 caller 的插件框架、daemon、数据库、监控器或 provider abstraction 不应建立。

## 3. 受限 Interface

```text
Resolve(RouteRequest) -> RouteDecision
PrepareLaunch(RouteDecision, LaunchRequest) -> LaunchPlan | ManualSelection
PlanProjection(ProjectionRequest) -> ProjectionPlan | ManualSelection
ApplyProjection(ProjectionPlan, confirmationToken) -> ProjectionReceipt
RollbackProjection(ProjectionReceipt, confirmationToken) -> RollbackReceipt
RecordTaskOutcome(RouteReceipt, Outcome) -> ReceiptReference
```

### 3.1 Resolve

```json
{
  "request_id": "uuid",
  "host": "codex_cli",
  "identity_selector": "current-redacted-identity",
  "workload": "bounded_implementation",
  "risk_level": "normal",
  "operation": "workspace_write",
  "workspace_root": "D:\\CODE\\example",
  "manual_override": null
}
```

输入不含 prompt、secret、完整 base URL 或未经合同批准的自由模型名。**canonical host identifier** 固定为 `codex_cli | zcode | claude_code`；`codex` 仅为自然语言/CLI 输入别名，入口归一化为 `codex_cli`——state scope key、receipt、Adapter lookup 一律使用 canonical 值（MOR-050/MOR-060 含 alias normalization 测试）。输出必须是以下之一：

| status | 含义 | 后续 |
| --- | --- | --- |
| `selected` | route 满足静态 Adapter 合同和风险策略 | 允许生成 launch/projection plan |
| `blocked` | 缺 mapping、风险越界或缺 emergency approval | 返回稳定 reason code 和人工动作 |
| `manual_host_selection_required` | 当前宿主不能安全表达或投影该选择 | 输出精确 model/effort handoff |
| `manual_mapping_required` | 用户声明不能无歧义映射到已有合同/模板 | 要求用户补 map，禁止猜测 |

`PrepareLaunch` 冻结 candidate fingerprint、policy/Adapter revision、model、effort、operation 与脱敏命令；没有单独 `--execute` 授权时只给 dry-run。 `RecordTaskOutcome` 仅追加诸如 `launch_failed`、`host_loaded_observed`、`business_verifier_passed` 或 `not_observable` 的引用，绝不能触发再次 Resolve、重试、切换或写入。

## 4. 五个配置/状态 plane

| plane | owner | 位置 | 何时变化 | 内容 |
| --- | --- | --- | --- | --- |
| `policy_source` | maintainer / 用户 | tracked runtime repo | reviewed patch | workload/risk、静态 Adapter allowlist、preset、emergency approval |
| `host_default` | 当前用户 | private user-local root | 明确设定 | 一组 host/identity 日常 route map |
| `operator_override` | 当前用户 / 当前宿主 AI | 同一 private root | 用户明确声明 | 当前 scope 的替代 route map |
| `resolved_route` | resolver | append-only private receipt | 每次显式 Resolve | requested/resolved/observed 三段 + fallback/clamp 记录 |
| `host_projection` | projection transaction | 已验证 native target + private receipt | plan/token/授权齐备 | 可表达的 model/effort/profile 字段 |

`resolved_route` 的“自动更新”只指每次显式 Resolve 按 precedence 重新计算并写 receipt；不后台运行，不根据环境或 task result 改持久化 state。控制面 resolved 不等于宿主生效：宿主可能自行 clamp 或 fallback（Claude Code effort clamp 与 `fallbackModel` 链、DeepSeek 未知名回落 flash、组织策略静默限制），必须由独立观察证据记入 `observed_host_route`，不得以 resolved 充当宿主事实。

### 4.1 Private host state

```json
{
  "schema_version": 1,
  "scope": {"host": "codex_cli", "identity_selector": "redacted-current"},
  "host_default": {
    "selection_plane": "host_default",
    "route_map_id": "gpt56_sol_only",
    "policy_revision": "sha256:...",
    "updated_at": "UTC timestamp",
    "rollback_reference": "private receipt id"
  },
  "operator_override": {
    "override_id": "uuid",
    "source": "operator_declared_unverified",
    "selection_plane": "operator_override",
    "route_map_id": "gpt56_terra_only",
    "route_keys": {
      "light": {"model": "gpt-5.6-terra", "effort": "medium"},
      "standard": {"model": "gpt-5.6-terra", "effort": "high"},
      "deep": {"model": "gpt-5.6-terra", "effort": "xhigh"}
    },
    "declared_at": "UTC timestamp",
    "requires_reconfirm_after": null,
    "policy_revision": "sha256:...",
    "rollback_reference": "private receipt id"
  }
}
```

每次 persistent write 必须执行：`canonical scope check -> single-writer lock -> target recheck -> before-hash -> backup -> atomic replace -> after-hash -> private receipt`。lock 必须先于 before-hash，hash 在锁内重验；lock 是本 runtime 的协作写者语义，其范围、stale-lock 崩溃检测与释放机制由 MOR-140 定义，不约束非协作外部写者，防漂移由锁内 before-hash 重验兜底。未知字段、scope 不匹配、并发、reparse escape、hash 漂移或无 backup 均 fail closed。恢复默认只删除当前 scope 的 `operator_override`，不变更 `host_default`，不触及任何其他 host/identity。

### 4.2 Route receipt

```json
{
  "schema_version": 1,
  "request_id": "uuid",
  "scope": {"host": "codex_cli", "identity_selector": "redacted-current"},
  "requested": {
    "workload": "routine_maintenance",
    "risk_level": "normal",
    "operation": "workspace_write"
  },
  "execution_slot": "routine_maintenance",
  "route_key": "standard",
  "selection_plane": "operator_override",
  "route_map_id": "gpt56_terra_only",
  "verification": "operator_declared_unverified",
  "requested_route": null,
  "resolved_route": {"model": "gpt-5.6-terra", "effort": "high", "constrained": false},
  "fallback_applied": false,
  "clamp_applied": false,
  "observed_host_route": null,
  "observed_by": null,
  "observation_status": "not_observable",
  "policy_revision": "sha256:...",
  "adapter_revision": "sha256:...",
  "truth_boundary": "repo_verified",
  "projection_receipt_ref": null,
  "redaction_verified": true
}
```

receipt 永不保存 secret、token、cookie、prompt、完整 command、未脱敏环境变量或 provider 配置。`requested_route` 为 `null` 表示该次请求无显式 model/effort（preset/模板级声明）；仅当调用方显式携带 model/effort 时记录原始值，使 verifier 能区分"请求→解析"是否发生过真实转换。**`host_loaded` 不是持久字段**：由 `observation_status` 推导（`match`→true / `route_mismatch`→false / `not_observable`→not_observable），receipt 只持久化 `observation_status` 与 `observed_host_route`。字段 `route_source` **已废弃**：canonical 为 `selection_plane`（`manual_override | operator_override | host_default`）+ `route_map_id`（override 情形另有 `override_id`）；schema 禁止 `route_source` 进入任何 plane。

**constrained 约束对象（frozen shape）**——`constrained` 不是裸布尔标签：

```json
{
  "constrained": true,
  "constraint_reasons": ["no_high_risk_adjudication", "bounded_write_set_only", "independent_verifier_required"],
  "max_risk_level": "normal",
  "allowed_operations": ["read_only", "workspace_write"],
  "required_verifiers": ["contract", "focused_test"]
}
```

规则：`constrained=false` 时不得出现任何限制字段；`constrained=true` 时三个限制字段必须非空；route 的 risk/operation/写集/verifier 与约束对象不一致即 fail closed；receipt verifier 必须覆盖该约束。除非另有独立 host 证据，所有用户声明 route 都保持 `operator_declared_unverified`。

## 5. 静态 effort 合同与三档模板

### 5.1 支持集合和实际路由集合必须分离

`low/medium/high/xhigh/max` 是某模型**可被 Adapter 表达的可能 effort 标签**，不是预设必须逐一使用的等级。静态合同和日常 preset 分开：

```yaml
adapter_supported_efforts:          # 人工复核、按 surface 分列、版本化；不是运行期枚举
  codex_config_surface:             # model_reasoning_effort / profile / -c：官方词表 minimal..xhigh
    gpt-5.6-sol:   [low, medium, high, xhigh]   # xhigh model-dependent
    gpt-5.6-terra: [low, medium, high, xhigh]
    gpt-5.6-luna:  [low, medium, high, xhigh]
  codex_security_cli_surface:       # 独立 surface；max 为 candidate，MOR-090 取证后单列
    max: candidate

preset_used_efforts:               # 当前日常方案只选实际需要的三档
  gpt56_sol_only:      [low, medium, xhigh]
  gpt56_terra_only:   [medium, high, xhigh]
  gpt56_luna_only:    [medium, high, xhigh]
```

任何列表都只是样例合同形状；实际 host/identity 必须先有相应 static Adapter allowlist。若 `Sol/low` 未被合同证实，`gpt56_sol_only` 不可启用，必须 `manual_mapping_required` 或选择已有日常 default；不能降默认为另一个参数。

模型支持但预设不使用的 effort（如 Sol/Terra 的 `high`），以及不属于当前 surface 词表的值（如 config 面的 `max`），保持候选状态，不自动加进路由。新增某档必须有明确 workload、operation/risk 限制、对应 surface 的静态 Adapter 合同和 reviewed policy patch；不能仅因为数字更大或营销名称更强。

### 5.2 最终推荐：当前三条基础 route key

| 基础 route key | `gpt56_sol_only`（日常默认） | `gpt56_terra_only` | `gpt56_luna_only` |
| --- | --- | --- | --- |
| 轻量只读：定位、摘要、日志归纳、简单 diff | Sol/low | Terra/medium | Luna/medium，`constrained` |
| 有界实现 / 标准审查：小写集修复、单模块实现、多文件常规 review | Sol/medium | Terra/high | Luna/high，`constrained` |
| 深度实现：复杂调试、跨模块重构、隔离复杂实现 | Sol/xhigh | Terra/xhigh | Luna/xhigh，`constrained` |
| 高风险门：安全、迁移、发布、公开契约、高扇出变更 | Sol/xhigh + high-risk policy | Terra/xhigh + 当前 emergency approval | `blocked` |

这三档是**基础 route key**，并非宣称跨模型的同 effort 能力等价。它有四个设计目的：

1. Sol 正常可用时，默认只需认识 `xhigh / medium / low` 三个努力档；Sol/low 仅承接轻量只读，Sol/medium 承接有界写入或标准审查，Sol/xhigh 承接深度实现或获批高风险工作。
2. Terra-only 与 Luna-only 保持相同三个基础 route key，切换时只更换 model family；为降低单一替代模型的不确定性，轻量/有界写入使用 `medium/high`，而不使用 `low`。
3. 原先独立的 Terra/xhigh 日常槽位删除；深度实现转入 Sol/xhigh。Terra/xhigh 仍作为 Terra-only 的深度 route 以及未来人工 override 的候选。
4. Luna/xhigh 只能进入有明确写集和验证的深度工作；它绝不成为 Sol/xhigh 等价，也不能自动解锁安全、迁移、发布、公开契约或 high-risk adjudication。

当前三条 route key 不是 schema 上限：若未来静态 Adapter contract 与同类 verifier 同时证明必要性，policy 可为一个 exact host/identity 新增 `review`、`max_depth` 等第四/第五 key。该变更不会重命名 slot，也不会改变自然语言 intent、receipt 或 projection transaction；它只是 route-key 到 model/effort 的 reviewed mapping patch。

### 5.3 固定五个 execution slot、可扩展 route key

执行槽位与 route key 是不同对象。**首版固定维护以下五个执行槽位**，以保持所有宿主、自然语言指令、receipt 和 verifier 的语义一致。workload 是调用方声明的任务意图，execution slot 是 policy 依 workload、risk 与 operation 派生的稳定语义类别；首版两者共用相同五个 identifier，属 1:1 实现细节，不是同一领域对象。slot 有自己的 operation、写集和验证语义，并引用一个 route key。多个 slot 可复用同一个 model/effort mapping：

| execution slot | 默认 route key | 用途 | 不可简化的区别 |
| --- | --- | --- | --- |
| `quick_triage` | light | 只读定位、摘要、日志归纳、简单 diff | 不写工作区，要求结论可定位 |
| `routine_maintenance` | standard | 单目标、小写集日常修复 | 有写入和受影响 gate |
| `standard_review` | standard | 多文件常规 review | 有 finding/复核语义，不应被当作轻量摘要 |
| `bounded_implementation` | standard | 可回滚、边界明确的实现 | 有 build/test/contract 验证 |
| `deep_investigation_or_implementation` | deep | 复杂调试、跨模块重构、隔离复杂实现 | 要求计划、深度证据和明确 rollback |

这五个是稳定骨架而非当前模型档位的镜像。修改 slot（包括新增、删除、改名或拆分）属于 policy major change，必须有迁移规则、跨宿主兼容评估、fixture/receipt 兼容测试和 rollback；普通“模型多一个档位”不应触发 slot 变更。新增 route key 则必须有静态 contract + 可比较 verifier 说明 model/effort 的额外区分有净收益。`high_risk_adjudication` 是覆盖任何 slot 的垂直 gate，不计入五个执行槽位。

```yaml
execution_slots:                 # 五个语义 slot 稳定；未来新模型不必改它们
  quick_triage: { route_key: light, operation: read_only }
  routine_maintenance: { route_key: standard, operation: workspace_write }
  standard_review: { route_key: standard, operation: read_only }
  bounded_implementation: { route_key: standard, operation: workspace_write }
  deep_investigation_or_implementation: { route_key: deep, operation: workspace_write }

route_keys:                      # 当前 GPT 预设使用三条
  light:    { model: gpt-5.6-sol, effort: low }
  standard: { model: gpt-5.6-sol, effort: medium }
  deep:     { model: gpt-5.6-sol, effort: xhigh }

# 后续经过审查，可新增 review/max_depth，而不改变上方五个 execution_slots。
# max_depth 是 route-key 命名空间；其宿主表达须经 surface adapter 显式映射，
# 不得假设内部档位名等于宿主 effort token（config 面当前无 max）。
```

### 5.4 ZCode 与 Claude 的静态三 route-key 映射

这两套默认与 GPT preset 同样是 policy 中的静态 route map；它们不读取当前网关、OAuth 或模型列表：

| host default（均 candidate，启用前一律 `manual_mapping_required`） | 轻量只读 | 有界实现 / 标准审查 | 深度实现 | 高风险门 |
| --- | --- | --- | --- | --- |
| `zcode_glm_candidate`（当前候选 slug `glm-5.3-flash`；surface 词表 `low/high/max` 已证实，`thinking` 不可关闭、默认 `max`；ZCode 投影面未取证） | candidate（`low`） | candidate（`high`），`constrained` | candidate（`max`），`constrained` | `blocked` |
| `claude_deepseek_candidate`（须过 ClaudeCodeHostAdapter + DeepSeekProviderDialect 双合同） | candidate | candidate，`constrained` | candidate | candidate + high-risk policy |

每个精确 model/effort token 都必须同时出现在该 host/identity、该 surface 的 Adapter allowlist 中；candidate 未取证前一律 `manual_mapping_required`。`DeepSeek V4 Pro/max` 的高风险 route 还要求 policy、当前 operation、明确写集、独立 verifier 与当次授权；它并非模型名称带 `Pro`/`max` 就自然获得的权限。

## 6. 确定性 Resolve 算法

```text
1. Validate request schema, exact host/identity scope, workload, operation, workspace policy and risk.
2. Load the exact scoped host_default.
3. If one-task manual_override exists, validate it first.
4. Else if exact scoped operator_override exists, check `requires_reconfirm_after` first: if expired（`requires_reconfirm_after <= now`），return `manual_mapping_required` with reason `override_reconfirmation_required`——不自动切换、不静默续期；未过期才选择其 route map.
5. Else select host_default route map.
6. Validate the chosen model/effort against static Adapter allowlist, allowed data class,
   operation, maximum risk and any required emergency approval.
7. Return selected, blocked, manual_host_selection_required or manual_mapping_required.
8. Freeze the candidate fingerprint; launch/projection cannot re-resolve or mutate it.
```

precedence 固定为 `manual_override -> operator_override -> host_default`。没有运行时 fallback chain：缺 route、参数不兼容、超过风险、或缺 approval 就 block。跨 profile substitute 只在**当前用户明确批准**且 reviewed policy 同时携带 `reason/owner/expires_at` 时成立，receipt 要记录原档、替代档与有效期。

```text
task failure -> append outcome receipt -> no reroute / no retry / no mutation
             -> user declares a revised map, or says restore default
```

## 7. Host Adapter 静态合同

每个 Adapter 只实现：

```text
GetStaticCapabilities() -> StaticAdapterContract
ValidateCandidate(candidate) -> valid | incompatible | unknown
BuildLaunch(decision, request) -> LaunchPlan | ManualSelection
ParseLaunchOutcome(events) -> Outcome | not_observable
PlanNativeProjection(selection_plane, route_map_id) -> ProjectionPlan | ManualSelection
```

| Adapter | 负责的事实 | 明确不证明 |
| --- | --- | --- |
| `codex_cli` | 按 surface 分列的 static contract：config/profile/`-c` 面词表（`minimal..xhigh`）、launch 面（`-m`/`-c model_reasoning_effort`）、其他 surface（如 security 扫描面的 `max`）单列候选、dry-run 命令形状、已验证 native target | 把不同 surface 词表合并成一个 allowlist；正在运行 Codex Desktop 可热切换；`~/.codex` 任意文件可安全修改 |
| `zcode` | 经本机静态证据复核的 ZCode 宿主 model/effort field contract（GLM 模板现为 candidate，见 PRD §7） | skills/MCP 投影等同模型选择权 |
| `claude_code` | ClaudeCodeHostAdapter：宿主 model 选择、`effortLevel`、`fallbackModel` 链、组织 clamp、fresh-session 可观察性 | 以 provider 方言可表达字段推断宿主当前环境生效 |
| `deepseek_provider_dialect` | DeepSeekProviderDialect：exact 模型名（`deepseek-v4-flash`/`deepseek-v4-pro`）、未知名回落 flash、`output_config` effort 透传、thinking budget 不可设 | 宿主侧结论；跨 provider 复用 |

实施顺序只能是“收集一次可复核静态事实 -> 提交 contract/fixture -> 测试 contract -> 允许 resolver 消费”。运行时不从宿主、网关或认证面读取候选，不将 task error 变成 route state。

## 8. 受控投影

```json
{
  "plan_id": "uuid",
  "scope": {"host": "codex_cli", "identity_selector": "redacted-current"},
  "selection_plane": "operator_override",
  "override_id": "uuid",
  "policy_revision": "sha256:...",
  "adapter_revision": "sha256:...",
  "actions": [{
    "target_path": "redacted verified native target",
    "before_sha256": "sha256:...",
    "after_sha256": "sha256:...",
    "allowed_fields": ["model", "model_reasoning_effort"]
  }],
  "confirmation_token": "plan-bound-nonsecret-token",
  "rollback_entry": "private receipt action id"
}
```

Apply 顺序固定：`canonical target containment -> single-writer lock -> target recheck -> before hash -> backup -> atomic apply -> after hash -> receipt`；lock 必须先于 before-hash，hash 在锁内重验。任何失败立即停止；已完成 action 只能按 receipt 精确 rollback。 `filesystem_projected` 只证明文件事务完成，不证明 fresh host 已采用配置或模型已完成任务。

“更新并落盘”可授权当前 scope 的 private override；只有 Adapter 已证明 target/allowed field/rollback entry、当前有 standing projection authorization 且确认 token 匹配时，才可继续 Apply。否则只输出 projection plan 或 `manual_host_selection_required`。投影永不写 provider、OAuth、token、base URL、session、plugin cache、sandbox 或 approval。

## 9. 宿主 AI 的一句话 action contract

宿主 AI 的薄 Skill 只把明确用户指令转换为同一个 CLI/module 的结构化操作；它不能用 prose 声称“已切换”，不能跨 host 广播，也不能绕过投影事务。

| 用户句子 | 动作 | scope | 持久化结果 |
| --- | --- | --- | --- |
| “当前 Codex 只有 Terra 可用，切换 Terra-only 并落盘。” | `reconcile --preset gpt56_terra_only` | current Codex/current identity | scoped override；条件具备才投影 |
| “当前 Codex 只有 Luna 可用，按默认模板更新。” | `reconcile --preset gpt56_luna_only` | current Codex/current identity | scoped override |
| “当前 ZCode 可用 GLM-5.3-Flash/max，按默认模板更新。” | `reconcile --declare-available <map> --optimize-from-default` | current ZCode/current identity | scoped override；声明集未被静态合同覆盖的档位保持 `manual_mapping_required` |
| “当前 Codex 恢复默认模型编排。” | `reconcile --restore-default` | current Codex/current identity | 只删除该 override |

问句、转述日志、未指定 host、混合多个身份、未知 model/effort，或“所有环境都切”而没有逐 host map 时，Parser 必须零写入并返回 `clarify_required` 或 `manual_mapping_required`。成功 receipt 必须说明：当前 route 是人工声明、未读取认证/网关、未启动验证、未影响其他宿主，以及是否只写了 private override、仅生成投影 plan 或已完成投影事务。

## 10. 会话、身份和验证边界

- route 只影响新任务，不能热切换运行中的会话；跨身份续做只能生成 handover summary，`continuity=not_proven`。
- identity 是 candidate fingerprint 的一部分；个人/团队、OAuth/API、region、gateway 或 data classification 不同的结果不能混用。
- identity 必须有不可伪造、可审计的绑定来源（MOR-000 钉定）；无法绑定时状态为 `identity_unbound`，禁止持久 override 与 projection，只允许 offline resolve 与 dry-run/manual handoff。
- 不因认证、限流、可见性或失败结果重启/kill 应用、gateway 或代理，也不改共享 provider。
- policy/state/receipt 对未知属性 fail closed；secret-like value 出现即拒绝写入。
- Preset Review 是只读工序，输入为静态合同、用户声明、route/outcome receipt、同类 verifier 与风险矩阵；输出 `keep/promote/demote/block/insufficient_evidence`，不会自行修改任何 plane。

真值边界固定为 `repo_verified -> filesystem_projected -> host_loaded -> live_accepted`。文档、静态合同、route receipt 或投影成功均不得跳过 fresh host 采用和独立业务验收。
