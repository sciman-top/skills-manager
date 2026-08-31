# 跨宿主模型编排控制面 PRD

**状态**：design-only；未进入 skills-manager runtime 范围
**目标实现归属**：待用户选择独立 host-local runtime 根目录；可作为受控 Cockpit 扩展或既有治理 runtime 的独立模块，不能进入 `skills.json`、`skills.ps1` 或本仓 host projection 主链
**关联**：[架构](cross-host-model-orchestration-architecture.md) · [MOR-000 暂缓决议](../decision/MOR-000-brief.md) · [MOR-090 静态证据](../decision/MOR-090-static-adapter-evidence.md)

## 1. 产品决策

本产品采用 **人工声明、宿主内更新、三套 GPT-5.6 常用预设**，不实现自动可用性探测。

```text
每个 (host, identity) 先有一个稳定日常 default
  -> 正常编码：按 default 离线解析，无探测
  -> 可用性变化：用户告诉当前宿主 AI 哪个模型族/effort 可用
  -> 当前宿主 AI 仅更新自己的 scoped operator_override
  -> 用户说“恢复默认”：只删除该 scope 的 override
```

`gpt56_sol_only` 是 Codex 的**intended policy default**；只有当前 `(host, identity, surface)` 对 Sol/low、Sol/medium、Sol/high 的逐项 static Adapter fixture 均获证实后，才可成为实际 `host_default`。证实前 Resolve 必须 `manual_mapping_required` 或 `blocked`，不得把 API 面能力外推为 Codex config 面可用。用户可在同一证据门槛下切换 `gpt56_terra_only` 或 `gpt56_luna_only`。三者都保留相同的三条**基础 route key**，并共享首版固定的五个 execution slot；slot 可复用 route key，未来如确有证据需要扩展，必须走独立的 policy major change。普通切换只改变模型族和 route map，不要求用户重学一套任务分类。

ZCode、Claude Code 各自维护独立 `host_default`，但两者的模型/effort 模板当前均为 **candidate**，不是可用事实：`GLM-3.5-Flash` 未见于当前 GLM Coding Plan 官方阵容（2026-08-28 检索；当前为 GLM-5.3 / GLM-5.3-Flash / GLM-5.2 / GLM-5-Turbo）。GLM 侧 surface 词表已证实：bigmodel Chat Completion API 的 `reasoning_effort` 为枚举参数，GLM-5.2+ 支持 `low / high / max`（默认 `max`），ZCode 选择面提供 低/高/最高 三档与之对应；但 `thinking` 不可关闭（GLM-5.3+ 不再支持 `thinking.type: disabled`），且 ZCode 宿主投影面（UI/计划层之外能否由控制面表达）未取证，故仍为 candidate。DeepSeek 组合虽在 provider 面词表内，仍须分别通过 ClaudeCodeHostAdapter 与 DeepSeekProviderDialect 双重静态证据后才可启用。它们不继承 Codex 的路由，也不因 Codex 的可用性声明发生变化。

## 2. 问题、目标与成功定义

不同宿主、账号、OAuth/API 身份、网关和模型供应商的可用集合会变化。将模型名散写在 `AGENTS.md`、项目提示词或某个宿主的私有配置中，会造成三类问题：

1. 变化发生时，使用者不知道应改哪一处，且容易误伤其他宿主或身份。
2. 模型/effort 与任务风险混在一起，出现“临时换模型就顺便放开高风险任务”的隐性降级。
3. 通过扫描网关、OAuth、模型列表、请求探测和失败自动回退来“自动化”，会扩大权限、成本、账号隔离和会话连续性风险。

成功定义不是“永远自动找到可用模型”，而是：

1. 用户只需告诉当前宿主 AI 一句明确指令，即可将当前 `(host, identity)` 的有效路由更新并落盘。
2. 每次新任务可解释其 workload、风险、route source、model、effort、约束与回滚引用。
3. 各个 host default 独立；Terra/Luna 变化绝不自动广播给 Codex、Claude Code、ZCode 的其他身份。
4. 风险不因 `max`、`xhigh` 或模型名称而自动升级。缺少安全 route 时 fail closed。
5. 可区分 `repo_verified -> filesystem_projected -> host_loaded -> live_accepted`，不会把配置、文档或 receipt 当作真实模型可用性。

## 3. 用户、术语与主链

| 用户 | 高频动作 | 应得到的结果 |
| --- | --- | --- |
| 个人开发者 | 修复、审查、调试、重构、发布前复核 | 以一个明确模型族预设进入适合的 route key 和执行槽位 |
| 维护者 | 修改 default、声明可用集合、恢复默认、审查预设 | scoped、可回滚的配置变化与脱敏 receipt |
| AI coding agent | 根据用户声明启动下一项任务 | 只消费 resolved route；不猜模型、不改 provider |

- **workload**：结构化工作类型，固定落入 `quick_triage`、`routine_maintenance`、`standard_review`、`bounded_implementation` 或 `deep_investigation_or_implementation` 之一。
- **基础 route key**：日常用于模型/effort 切换的当前三档：`light`、`standard`、`deep`。它们是当前命名 preset 的便捷层，不是 schema 上限；未来只能通过版本化的新 preset/map revision 新增 `review`、`max_depth` 等 key。
- **执行槽位**：policy 依据 workload、risk 与 operation 派生出的稳定语义类别（semantic workload slot），不是可调度的并发槽位，也不是 effort 的同义词。首版目录固定提供五项：`quick_triage`、`routine_maintenance`、`standard_review`、`bounded_implementation`、`deep_investigation_or_implementation`；多个 slot 可复用同一 route key。workload 是调用方声明的任务意图，slot 是 policy 派生结果；首版两者共用相同五个 identifier，属 1:1 实现细节，不是同一领域对象。并发/队列/超时等宿主容量语义不在本控制面（它是明确的非目标），未来如需要走独立 host-specific capacity contract，不改 slot 枚举。
- **风险 gate**：`high_risk_adjudication` 覆盖任何 workload 的垂直风险 gate，不是第四个常用 route key。
- **constrained**：policy 输出的决策属性，不是 effort 标签，也不是裸布尔——启用时必须携带冻结形状的约束对象（`constraint_reasons`/`max_risk_level`/`allowed_operations`/`required_verifiers`，形状见架构 §4.2），并进入 MOR-020 contracts、resolver 输出与 receipt verifier。
- **capability profile**：独立概念已删除；如需展示别名，必须由 execution slot/route key 唯一派生并在 schema 注明派生规则，不参与 Resolve、Adapter 或 receipt 合同。
- **candidate**：一个 `(host, identity, model, effort, operation/risk bound)` 组合；gateway route 只能作为脱敏 fingerprint 成分，不能被控制面读取或修改。
- **host_default**：一个 `(host, identity)` 的稳定日常 route-map 选择引用，而非 route map 副本。
- **operator_override**：用户明确声明后，为相同 scope 写入的持久替代选择引用；完整 route map 不存入私有 state。
- **resolved_route**：一次显式 resolve 的 `selected`、`blocked` 或 `manual` 结果；它只写 private receipt。旧名 `effective_route` 已废弃——控制面选择不等于宿主生效事实，宿主生效必须由独立观察证据另行记录（见 `MOR-FR-036`）。
- **静态 Adapter contract**：人工复核、版本化的宿主 model/effort/field/target 能力表；不是自动发现结果。
- **Preset Review**：只读审查。它只输出 `keep/promote/demote/block/insufficient_evidence` 建议，不直接写配置。

主链：

```text
workload + risk + exact host/identity
  -> host_default or scoped operator_override
  -> static Adapter/risk validation
  -> resolved route or block
  -> dry-run / controlled projection / new task
  -> private receipt
```

## 4. 范围与非目标

### 4.1 包含

- 用稳定 workload/risk 选择模型与 effort，不让项目规则硬编码 provider。
- 读取 versioned policy、private `host_default`/`operator_override` 与人工维护的 Adapter static contract。
- 提供三套 GPT-5.6 可手动切换预设：`gpt56_sol_only`、`gpt56_terra_only`、`gpt56_luna_only`。
- 让 ZCode、Claude Code 使用其独立 default/override；可在将来用静态 Adapter contract 接入 GLM、DeepSeek 等模型。
- 生成 route、launch、projection 和 rollback receipt；不含 secret。
- 在 Adapter target ownership 已证实且有当前授权时，以 plan/token/backup/hash/rollback 方式投影模型选择字段。

### 4.2 明确不包含

- 不读取 `/v1/models`，不扫描 gateway，不查看 OAuth/account/token/API key，不抓 UI，也不发送探测请求。
- 不维护外部执行状态缓存、失败分类路由、自动恢复/替代、后台 watcher、daemon、数据库、定时任务或自学习评分。
- 不因模型任务失败自动修改 `host_default`、`operator_override`、policy、已投影配置或其他宿主。
- 不管理 provider、base URL、auth、cookie、token、sandbox、approval、plugin cache、session、账户切换或网关重启。
- 不热切换正在运行的 ChatGPT/Codex/Claude/ZCode 会话；只影响新任务。
- 不将 `max`、`xhigh`、供应商宣传或一次成功，解释成跨模型等价、全宿主有效或高风险授权。
- 不将实现嵌入 skills-manager runtime；本仓只保存设计、规则和未来投影接口边界。

## 5. GPT-5.6 三套三档预设

### 5.1 基础 route-key 矩阵（用户选定的初始 baseline，非性能最优结论）

| 基础 route key | `gpt56_sol_only` | `gpt56_terra_only` | `gpt56_luna_only` |
| --- | --- | --- | --- |
| 轻量只读：定位、摘要、日志归纳、简单 diff | Sol/low | Terra/high | Luna/high，`constrained` |
| 有界实现 / 标准审查：小写集修复、单模块实现、多文件常规 review | Sol/medium | Terra/xhigh | Luna/xhigh，`constrained` |
| 深度实现：复杂调试、跨模块重构、隔离复杂实现 | Sol/high | Terra/max | Luna/max，`constrained` |
| 高风险门：安全、迁移、发布、公开契约、高扇出变更 | Sol/high + high-risk policy | Terra/max + 当前 emergency approval | `blocked` |

`gpt56_sol_only` 是 Codex 的 intended policy default；它采用用户提出的 `Sol/high`、`Sol/medium`、`Sol/low` 三档。只有 Codex config surface 对这三项 exact tuple 的 static Adapter fixture 全部通过后，它才可成为实际 host default。

`gpt56_terra_only` 和 `gpt56_luna_only` 是直接替换相同三条基础 route key 的应急日常预设。Terra/Luna 使用 `max/xhigh/high`，不是因为它们和 Sol 的同名 effort 等价，而是为了在单一模型族时以更保守的推理投入承接深度、有界和轻量只读任务。

Luna-only 的 `high_risk_adjudication=blocked` 是硬边界。Luna/max 可以执行有明确写集、独立验证和回滚入口的深度任务；它不能自动解锁安全裁决、迁移、发布、公开契约或高扇出变更。

三个 `*_only` preset 的作用域固定为 `parent_route_only`：它只约束当前 Resolve 产生的父任务 route 和该 route 的 model family，不自动重写或约束 native bridge、custom subagent 或宿主已有的其他角色。现有 bridge pin 继续由独立角色合同管理；未来若要约束父子任务使用同一模型族，必须另行增加 versioned policy、迁移和 fresh-session 验证，不能从 `*_only` 名称推导。

### 5.2 固定五个 execution slot、可扩展 route key

当前三个 route key 不是 future route-key 数量的上限。首版 policy 固定维护以下五个 slot；其中 `standard` 被有意复用，既避免把常规写入降到 light，也避免仅为了名称差异制造第四个 effort：

| execution slot | 默认通道 | 区分依据 | 最低验证 |
| --- | --- | --- | --- |
| `quick_triage` | light | 只读定位、摘要、日志归纳、简单 diff | 引用定位或结论可复核 |
| `routine_maintenance` | standard | 单目标、小写集的日常修复/配置调整 | 受影响 gate 或明确 N/A |
| `standard_review` | standard | 多文件常规 review、非高风险语义判断 | finding 定位、独立复核或受影响测试 |
| `bounded_implementation` | standard | 写集、回滚和验收边界清楚的实现 | 受影响 build/test/contract |
| `deep_investigation_or_implementation` | deep | 复杂调试与调查、跨模块重构、隔离复杂实现 | 只读分支要求计划、深度证据和可定位结论；写入分支另需最小充分 gate 与明确 rollback |

任何 slot 一旦涉及安全、迁移、发布、公开契约或高扇出变更，都先通过 high-risk gate；gate 通过后必须使用 `route_key=deep`，再按该 route 的 operation、写集和 verifier 约束执行，无法表达或不满足约束时 `blocked`。五个 slot 不会随着模型档位数量变化而增删；若确需增删、改名或拆分，必须走 policy major change，包含迁移规则、跨宿主兼容评估、fixture/receipt compatibility tests 和 rollback。不得以“模型多一个档位”作为修改 slot 的理由。

规范化规则固定为：`risk_level=high -> route_key=deep`；它只在 high-risk gate 通过后成立，Luna-only 的 high-risk block 和自动故障切换的更严格阻断不被该规则绕过。

路由数据需显式分层，便于将来把五个可表达 effort 用在五个不同 route key，而不改变执行槽位、用户口令或 receipt 形状。`preset_route_maps` 是唯一 Resolve 输入：当前三个命名 preset 各自恰有 `light | standard | deep` 三 key，三 key 的精确 model 必须同属该 preset 的 model family；不得跨 Sol/Terra/Luna 拼接，也不得从其他 preset 补充缺失 key：

```yaml
execution_slots:
  quick_triage: { route_key: light, operations: [read_only] }
  routine_maintenance: { route_key: standard, operations: [workspace_write] }
  standard_review: { route_key: standard, operations: [read_only] }
  bounded_implementation: { route_key: standard, operations: [workspace_write] }
  deep_investigation_or_implementation: { route_key: deep, operations: [read_only, workspace_write] }

# 当前 GPT 常用预设：5 slot 复用 selected preset 的 3 条 route key
preset_route_maps:
  gpt56_sol_only:
    model_family: gpt-5.6-sol
    route_keys:
      light:    { model: gpt-5.6-sol, effort: low }
      standard: { model: gpt-5.6-sol, effort: medium }
      deep:     { model: gpt-5.6-sol, effort: high }
  gpt56_terra_only:
    model_family: gpt-5.6-terra
    route_keys:
      light:    { model: gpt-5.6-terra, effort: high }
      standard: { model: gpt-5.6-terra, effort: xhigh }
      deep:     { model: gpt-5.6-terra, effort: max }
  gpt56_luna_only:
    model_family: gpt-5.6-luna
    route_keys:
      light:
        { model: gpt-5.6-luna, effort: high, constrained: true,
          constraint_reasons: [no_high_risk_adjudication, independent_verifier_required],
          allowed_operations: [read_only], required_verifiers: [independent_review], max_risk_level: normal }
      standard:
        { model: gpt-5.6-luna, effort: xhigh, constrained: true,
          constraint_reasons: [no_high_risk_adjudication, bounded_write_set_only, independent_verifier_required],
          allowed_operations: [read_only, workspace_write], required_verifiers: [independent_review], max_risk_level: normal }
      deep:
        { model: gpt-5.6-luna, effort: max, constrained: true,
          constraint_reasons: [no_high_risk_adjudication, bounded_write_set_only, independent_verifier_required],
          allowed_operations: [workspace_write], required_verifiers: [focused_test, independent_review], max_risk_level: normal }

# 将来的经审查新 preset/map revision 可以增加 review/max_depth，而不重写 slot 目录
# route_keys.review:    { model: <approved>, effort: high }
# route_keys.max_depth: { model: <approved>, control: <surface-specific> }
# 注意：max_depth 是 route-key 命名空间；其宿主表达必须经 surface adapter 显式映射，
# 不得假设内部档位名等于宿主 effort token（config 面当前无 max）。
```

Resolve 固定先从 slot 得到 route key，再从**选定** preset 的同名 key 读取 exact model/effort。五个 slot 可以重复使用该 preset 的三个档位；任何未知 preset、缺/多 key、跨族 slug、或 resolved route 偏离选定 preset map 的结果都必须 `blocked`，不能静默降级或换用另一个 preset。`risk_level=high` 在 high-risk gate 通过后强制把 route key 提升为 `deep`；若该 preset/宿主的 deep route 不允许当前 operation，仍然 `blocked`。若将来确需第四/第五 key，必须创建版本化的新的 preset/map revision，不能修改这三个命名 preset。high-risk 是额外 policy gate，不是第四个模型档位。

### 5.3 “支持五档”与“日常只用三通道”

静态 Adapter contract 按 **surface** 记录模型可表达的 effort 词表；不同 surface 词表不同，不得合并为一个 allowlist。旧 C1 官方快照未列 config/max，但当前宿主的 `codex-cli 0.150.1` model catalog 已对 Sol/Terra/Luna 列出 `max`，且九个目标 profile 均 strict-load 成功（C7）。这只建立当前宿主的 config-load 证据；其他 host 仍须独立 fixture，不得借用 API/security surface，也不得把 profile load 外推为 provider 调用。一个 preset 只应使用工作真正需要的 2–4 个 effort；本版 GPT baseline 固定只用三档。

```yaml
adapter_supported_efforts:           # 人工维护、按 surface 分列的静态事实；示例，不是运行期发现
  codex_config_surface:              # model_reasoning_effort / profile / -c 覆盖共用
    gpt-5.6-sol:   [low, medium, high, xhigh, max]   # max 为 C7 current-host partial
    gpt-5.6-terra: [low, medium, high, xhigh, max]
    gpt-5.6-luna:  [low, medium, high, xhigh, max]
  codex_security_cli_surface:        # 独立 surface；candidate，MOR-090 取证后单列
    max: candidate

preset_used_efforts:
  gpt56_sol_only:   [low, medium, high]
  gpt56_terra_only: [high, xhigh, max]
  gpt56_luna_only:  [high, xhigh, max]
```

若当前 `(host, identity, surface)` 的 static contract 没有 `Sol/low`、Terra/max、Luna/max 或其他所需项，该预设不能静默近似；resolver 必须返回 `manual_mapping_required` 或 `blocked`。当前宿主的 C7/profile hash 只对本机有效；未来模型档位数增减仍只能创建版本化的新 preset/map revision，五个 execution slot 保持不变。

### 5.4 人工切换语句

```text
当前 Codex 只使用 GPT-5.6 Sol，切换 Sol-only 三档编排并落盘。
当前 Codex 只有 GPT-5.6 Terra 可用，切换 Terra-only 三档编排并落盘。
当前 Codex 只有 GPT-5.6 Luna 可用，切换 Luna-only 三档编排并落盘。
当前 Codex 恢复默认模型编排。
```

前三句都只影响 current Codex/current identity。第四句只删除该 scope 的 override，重新使用该 scope 已获证实的 host default；若 Sol-only 的三个 Codex config tuple 尚未取证，结果为 `manual_mapping_required` 或 `blocked`，而不是把 intended policy default 当作已生效默认。若用户说“落盘/应用配置”，默认授权 private override 更新；只有在已验证 Adapter target、standing projection authorization 和 plan token 都满足时，才允许继续写 native host target。

## 6. 功能需求

### 6.1 Resolve 与风险门禁

- `MOR-FR-001`：常规入口必须接受 exact `host`、`identity_selector`、`workload`、`risk_level`、`operation`、`workspace_root` 和可选的一次性 `manual_override`；不得从 prompt、目录名、模型名或上次任务猜复杂度。canonical host identifier 为 `codex_cli | zcode | claude_code`（`codex` 为输入别名，归一化后使用；state/receipt/Adapter 只存 canonical 值）。`--execution-slot` 只作为 fixture/dry-run 直通入口，且必须校验与 workload 派生结果一致；缺 `risk_level`/`operation`/`workspace_root` 一律拒绝。
- `MOR-FR-002`：workload/operation/risk/slot/route-key 映射只能来自 versioned policy；未知 workload、slot 或 route key fail closed；`risk_level` 枚举固定为 `normal | high`（`high` 必须通过 high-risk gate，gate 通过后强制使用 `route_key=deep`）；请求 `operation` 超出 slot 允许 operation（如 read_only slot 收到 workspace_write）时 `blocked`，不得自动改派 slot。
- `MOR-FR-003`：选择 precedence 固定为 `manual_override -> operator_override -> host_default`；每项都必须再经过静态 Adapter、工作区、数据分级、operation 和风险校验。
- `MOR-FR-004`：无安全 mapping、参数不在 allowlist、缺少 risk approval、或宿主选择面未知时，返回 `blocked`、`manual_host_selection_required` 或 `manual_mapping_required`；不得启用隐式 fallback。
- `MOR-FR-005`：`high_risk_adjudication` 的 Terra substitute 必须同时有 current emergency approval 的 `owner/reason/expires_at` 与 policy 许可；Luna-only 固定 block。
- `MOR-FR-006`：`RecordTaskOutcome` 只能记录 outcome receipt；不触发 reroute、retry、改 default/override/policy 或宿主写入。

### 6.2 静态 Adapter contract

- `MOR-FR-010`：每个 Adapter 的 model、effort、identity selector、launch field、可投影字段、target root 和 rollback entry 必须来自 reviewed static contract；未知字段/model/effort 必须 fail closed。
- `MOR-FR-011`：contract 的来源、revision、支持范围和 target ownership 在代码接入前经人工复核并提交；运行期不得访问 host/gateway/OAuth/catalog 以补全它。
- `MOR-FR-012`：`low/medium/high/xhigh/max` 只作为原样 effort token；不以 token 排序推断供应商间能力。
- `MOR-FR-013`：Adapter 必须能声明 `can_launch`、`can_project_model_config`、`can_observe_host_loaded`；未知即 false。
- `MOR-FR-014`：离线 resolve、intent parse、plan/apply/rollback、receipt verifier 和 preset review 都必须零网络、零 OAuth 读取、零 gateway 扫描、零模型调用。

### 6.3 人工声明与“运行时有效路由”

- `MOR-FR-020`：`host_default` 是每个 `(host, identity)` 的私有日常**选择引用**；它只保存 `selection_kind`、`route_map_id` 与 `policy_revision`，完整 route map 只能从该 revision 的 tracked policy source 解引用。没有 override 时，resolver 使用这个引用，不要求任何环境事实。
- `MOR-FR-021`：人工声明可选择命名 GPT preset，或选择已由 reviewed patch 加入 policy source 的 `reviewed_custom_single_family_map`。两类 map 均须完整覆盖 `light|standard|deep`，每一 key 的 exact model 必须等于同一个 model family，且每个 tuple 都在静态 allowlist 中；private state 不得保存其 `route_keys` 副本。用户临时提出未审查的模型/effort 集合时，只能生成 `manual_mapping_required` 计划，不能落盘为 default/override。
- `MOR-FR-022`：`manual_override` 仅为当前 RouteRequest 的一条 exact model/effort 候选，必须通过同一 static allowlist、operation/risk/constraint 校验；它不能定义五槽位 map、不能持久化、不能成为 preset 或 host default。model/effort 集合不能无歧义覆盖当前 slot 所需 route key 时，产出可审查的 route plan 或 `manual_mapping_required`；不得猜测 effort。
- `MOR-FR-023`：人工声明只写当前 `(host, identity)` 的 `operator_override` **选择引用**，并随下一次显式 resolve 产生新的 `resolved_route` receipt；不广播到 peer host。
- `MOR-FR-024`：用户说“恢复默认”时，只删除相同 scope 的 override；任务结果、错误、时间流逝或 assistant 建议都不能自动恢复默认。
- `MOR-FR-025`：成功 action receipt 必须标 `verification=operator_declared_unverified`，说明控制面没有检测任何 runtime/provider/gateway/auth 状态。
- `MOR-FR-026`：持久 override 必须支持可选 `requires_reconfirm_after`；只在下一次显式 resolve 时检查（无 watcher），过期返回 `manual_mapping_required` 并要求用户重申，不自动切换或恢复默认。

### 6.4 受控投影与安全

- `MOR-FR-030`：persistent state 写入与 host projection 必须执行 `scope/target containment -> lock -> before-hash -> backup -> atomic replace -> after-hash -> receipt`。
- `MOR-FR-031`：projection 只允许 Adapter 明确支持的 non-secret model/profile/effort 字段；provider、auth、token、base URL、cookie、session、plugin cache、sandbox 和 approval 必须拒绝。
- `MOR-FR-032`：`filesystem_projected` 仅证明文件事务；必须有 fresh host 观察才能报告 `host_loaded`。
- `MOR-FR-033`：正在运行会话、unknown target ownership、schema 不明、target hash drift、路径逃逸、无 backup、并发 lock 或 UI-only surface 均 fail closed。
- `MOR-FR-034`：默认 `PrepareLaunch` 只生成 dry-run。没有明确当前执行授权时不得启动 child/task。
- `MOR-FR-035`：日志、receipt、错误和 hash input 不得出现 secret、完整 command、prompt、未脱敏环境变量或 cookie。
- `MOR-FR-036`：route receipt 必须分列 `requested_route`（调用方**显式**请求的 model/effort；普通 RouteRequest 只含 workload/risk/operation，model/effort 是 resolve 产物，故无显式请求时为 `null`；仅 manual_override 或用户声明携带显式 model/effort 时记录原始值）、`resolved_route`（控制面按 policy 选中）与 `observed_host_route`（仅当存在独立 host 证据时填写），并记录 `fallback_applied`/`clamp_applied`、结构化 `route_events`（冻结形状见架构 §4.2：kind/source/from/to/reason/observed_at/observed_by；布尔 true 无事件、false 有事件、缺字段、未知 source 均拒绝）与 `observed_by`/`observed_at`/`observation_status`。`host_loaded` 状态机固定为三态：无宿主观察证据 = `not_observable`；观察到且与 `resolved_route` 一致 = `host_loaded=true`；观察到但不一致 = `host_loaded=false`、`observation_status=route_mismatch`、**hard fail**——不得把"宿主错误加载"隐藏成"无法观察"。宿主自身 fallback/clamp（如 Claude Code effort clamp 与 `fallbackModel` 链、DeepSeek 未知名回落 flash）不是控制面失败，但必须留痕。

### 6.5 宿主 AI 一句话操作

- `MOR-FR-040`：只有“明确可用性声明 + 更新/切换/恢复/落盘动作 + 可确定 scope”的句子才能触发写入；问句、讨论、转述日志和模糊“切一下”必须零写入。
- `MOR-FR-041`：默认 scope 是 current host/current identity；多 host 指令必须逐 host/identity 给 map，生成多个独立 plan/receipt。
- `MOR-FR-042`：一句话路径必须复用 CLI/module 的同一 schema、risk gate、projection transaction 和 verifier；不得按 prompt 直接编辑用户 config。
- `MOR-FR-043`：没有 CLI/Adapter/权限时返回 `control_plane_not_available`、plan 或 handoff；禁止用自然语言伪称已生效。
- `MOR-FR-044`：无论输入来自人还是宿主 AI，均不触发模型发现、探测、重试、自动 fallback、provider/auth 修改或网关调用。
- `MOR-FR-045`：普通任务的编排入口是上游调用方/用户确认产生的结构化 RouteRequest；宿主 AI 不得私自从 prompt 推断 workload/operation/risk。AI 提出的分类只能标记为建议，并需父任务/用户确认后才写入请求。

## 7. 各宿主默认配置

| host / identity | 日常 default | 人工变化动作 | 隔离边界 |
| --- | --- | --- | --- |
| Codex / 当前 API gateway 或 OAuth identity | `gpt56_sol_only` intended policy default；三项 config tuple 证实前无实际 default | 切 Sol-only、Terra-only、Luna-only；未审查新 map 只生成 manual plan | 仅当前 Codex identity |
| ZCode / 当前 identity | 无已证实 default（GLM 模板为 candidate） | MOR-090 钉定 exact model/effort 后按 ZCode 模板生成 default | 不影响 Codex/Claude |
| Claude Code / 当前 identity | 无已证实 default（DeepSeek 模板为 candidate） | Claude host adapter 与 DeepSeek provider dialect 双合同取证后启用 | 不影响 Codex/ZCode |

建议将另两宿主也配置为同一“三槽位 + 风险门”形状；这是静态骨架与用户选定的初始 baseline，不是当前网关可用性断言，更不是性能最优结论：

| host default（均 candidate，启用前一律 `manual_mapping_required`） | 轻量只读 | 有界实现 / 标准审查 | 深度实现 | 高风险门 |
| --- | --- | --- | --- | --- |
| `zcode_glm_candidate`（`glm-5.3-flash`；ZCode 投影面未取证） | candidate（Flash/low） | candidate（Flash/high），`constrained` | candidate（Flash/max），`constrained` | `blocked` |
| `claude_deepseek_candidate`（须过 ClaudeCodeHostAdapter + DeepSeekProviderDialect 双合同） | candidate（Flash/high） | candidate（Flash/max），`constrained` | candidate（Pro/max） | candidate（Pro/max + high-risk policy） |

实施阶段仅在静态 Adapter contract 已证实精确模型名、effort token 与选择面时启用。Claude 侧必须分别取证 `ClaudeCodeHostAdapter`（宿主 model/effortLevel/fallback/clamp 面与 fresh-session 可观察性）与 `DeepSeekProviderDialect`（exact 模型名、未知名回落、effort 透传）；provider 方言可表达不等于宿主当前环境生效。尤其 DeepSeek V4 Pro/max 进入高风险门并不表示“Pro/max 自动安全”；仍需当前 policy、明确 operation/写集和独立验证。GLM 或 DeepSeek Flash 不从 GPT 三档模板自动继承高风险权限。

## 8. Preset Review 和提升门槛

“最优”不是模型名称或 effort 标签能够证明的。Preset Review 只读审查当前 host/identity 的 static contract、route/outcome receipt、同类 verifier、workspace/risk matrix 与 rollback point，输出建议而非写入。

| 检查对象 | 当前保守建议 | 必要补证 |
| --- | --- | --- |
| `gpt56_sol_only` | `keep`，前提是 Sol/low、medium、high 均为静态可表达项 | 同 workload 的 host 采用与 verifier 证据 |
| `gpt56_terra_only` critical | `keep_emergency`，不是 Sol 等价 | 当前 emergency approval + 高风险验证 |
| `gpt56_luna_only` critical | `block` | 独立风险决策；单次表现不能解除 |
| GLM Flash `max` | `constrained` 或 `insufficient_evidence` | ZCode 内同类 bounded-write 与 verifier 证据 |
| DeepSeek Flash `max` | `constrained` 或 `insufficient_evidence` | Claude 内同类 bounded-write 与 verifier 证据 |

要把一个 candidate 提升为 default/deep/critical，必须同时有：

1. Adapter proof：host 能静态表达该 model/effort，或明确为不可观察；
2. operation proof：同类写集有最低验证和回滚，不以回复文本代替；
3. comparability：相同 `case_id`、source/input hash、workspace 条件、adapter revision 与验证标准；
4. risk proof：公开契约、安全、迁移或高扇出变更还要有仓库测试/独立 review；
5. owner decision：reviewed policy patch 与可逆 rollback point。

## 9. 实施前决策门与非功能需求

- Windows-first、PowerShell 7-first、local-first；首期不引入常驻进程。
- policy/default/override/receipt 均 schema-validated、unknown-property fail closed、单写者、原子替换。
- 默认 CI 和日常 control-plane 命令零供应商调用。
- 目标 runtime 由用户在 R0 明确选择；未选择时本仓只保留设计文档。
- 每个启用宿主需提供可脱敏的本机 help/schema/source evidence，以及人工复核的 target ownership/rollback entry。
- Adapter static contract 的取证顺序固定为：官方产品/CLI 文档与 schema -> 当前机器的只读 help/schema -> 已映射、可审查源码 -> 许可清楚的社区项目结构启发。社区资料只能影响模块/事务结构，不能证明 model/effort 可用、参数被当前 gateway 接受或拥有写入目标。
- 一手资料不可获取或结论不完整时，记录 `platform_na`/`unknown`，保持 dry-run/manual；不得以网页片段、模型名相似、社区配置或 OAuth/gateway 探查补齐。
- 首期建议只实现一个宿主（Codex CLI）和三套 GPT preset；ZCode、Claude 必须等各自静态合同清楚后再接入。

本 PRD 的任何 `repo_verified` 结果都不证明 provider 可用、host 已读取设置、模型实际被接受或真实任务已经成功。
