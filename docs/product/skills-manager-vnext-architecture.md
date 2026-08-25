# skills-manager Architecture

## 1. 架构目标

架构只服务五条真实主链：技能配置与构建、MCP、目标仓审查、规则治理、原生技能投影。每条主链拥有一个清晰 interface；跨主链只共享配置、文件/Git 原语和 receipt，不建立中央 orchestrator。

## 2. 模块与 interface

### CLI shell

- Interface：`skills.ps1 <command> [args]`
- Source：`src/Version.ps1`、`src/Main.ps1`、`src/Commands/*`
- Responsibility：参数分派、用户交互、exit code 与 JSON 输出

`build.ps1` 按固定顺序拼接 source，生成根 `skills.ps1`。生成 bundle 是发布物，不是编辑 seam。

帮助与菜单只展示 canonical commands。仍需兼容的少量历史名称集中在 CLI shell 的 compatibility map，调用时输出 deprecation warning；已无调用价值的 `一键/workflow` 与 `自动更新设置` 不保留 compatibility 路由。

### Config and source materialization

- Interface：`skills.json`、`skills.lock.json`
- Implementation：`src/Config.ps1`、`src/Git.ps1`、install/update/build commands
- Outputs：`vendor/`、`imports/`、`agent/`、targets

配置 validator 负责 schema、path containment、duplicate name、mapping、MCP 与 projection invariants。当前 `skills.json` 使用 schema v3：11 个受管顶层字段采用 allowlist，未知顶层字段 fail closed；v2 仍保留只读迁移兼容并仅输出 observation。该迁移由 [HSM-CFG-300/310](skills-manager-hardening-implementation-plan.md) 按 observe→enforce 两步落地，后续 schema 变更必须保留兼容窗口与回滚合同。未知顶层字段不得成为新的 runtime/任务控制面入口。source update 负责 revision/origin/dirty checks；build 只消费验证后的 source 和 override。

`scripts/weekly-skills-update.ps1` 是外部调用 seam 上的 skills-only maintenance adapter：它复用 update 与 quick gate，并限制分支、并发和 tracked write set。Windows Task Scheduler 的注册、更新、删除、运行账户与触发频率属于 host/operator lifecycle，不是本仓 module。

### MCP

- Interface：`安装MCP`、`卸载MCP`、`MCP配置`、`同步MCP`
- Implementation：`src/Commands/Mcp.ProfileAndSafety.ps1`（profile、输入规范化与 secret 安全）和 `src/Commands/Mcp.ps1`（adapter、规划、事务与同步）
- State：`skills.json.mcp_servers/mcp_profiles/mcp_targets`

MCP config mutation、host projection、live readiness 是三个不同状态。仓库保存环境变量名，不保存 credential value。

只读宿主观察通过 Codex CLI 的公开 JSON 面读取 `plugin list`、`mcp list` 与 `doctor`。适配器只保留插件标识/数量、MCP 名称与启用/认证/transport 类型、doctor 的 schema/version/status/check 摘要；plugin 与 standalone/system skill 同名时只生成 `native_source_preferred` finding。它不读取插件 cache 私有结构、不执行 plugin mutation、不保留 MCP command/env/header 或 doctor details，也不把观察结果提升为 `host_loaded`。

### Target audit

- Interface：`审查目标 扫描/预检/应用确认/应用`
- Implementation：`src/Commands/AuditTargets*.ps1`
- Runtime state：`reports/skill-audit/<run-id>/`

数据流：

```text
repo scan -> scan-derived target profile + installed inventory
  -> immutable snapshot.json + editable recommendations.json + machine receipt.json
  -> reviewed recommendations.json
  -> preflight + dry-run + input fingerprint
  -> explicit apply
  -> config/source mutation + compensation + receipt section update
```

`snapshot.json` 聚合审查输入且不可编辑；`recommendations.json` 是唯一 AI 决策文件；`receipt.json` 聚合 phase/result/rollback/truth。Recommendations 是数据，不是授权。apply 重新读取 current config 与 snapshot，snapshot 缺失或发现 drift 即阻断。

### Rule governance

- Interface：`rule-audit`、`rule-plan/apply`、`rule-estate-*`
- Domain：RuleDocument、RuleFinding、RuleResponsibility、RulePatchPlan、OperationPlan/Receipt
- Implementation：`src/Application/Rule*.ps1`

只读 discovery/diagnostics/advisor 与 mutation 分离。单仓 mutation 是原子文件替换；全域 mutation 是逐目标事务。每个成功 action 有独立 receipt，因此后续失败不需要回滚无关目标。

### Skill projection

- Interface：canonical inventory、projection plan/apply、`capability-inventory`
- Implementation：`src/Domain/SkillCatalog.ps1`、`src/Application/Skill*`、`src/Commands/SkillProjection.ps1`。宿主原生负责 description 截断与 metadata budget；本仓只管理 eligibility、路径、投影、ownership 与回滚。
- Runtime outputs：`reports/skill-projection/*.json` 与受管 user skill links

Canonical inventory 统一来源；eligibility 处理 enabled/dependency/placement；宿主原生处理 metadata budget 与 description 截断；projection transaction 用完整 package hash 绑定 plan/apply/receipt，并只删除当前 managed root 或上一份受绑定 receipt 能证明 ownership 且 target 未漂移的 links，外部 skill 永不被当作受管资产删除。

`capability-router` 是宿主按需选择的 fallback adapter，仅在可见 metadata 不足或需要确定性 policy validation 时适用。它从 portable catalog 读取候选，按 `DomainHint` 限定集合，并对宿主提供的 Candidate 做确定性 existence、containment、entrypoint hash、availability 与 side-effect disclosure 校验。它不作普通请求前置，不维护 session、preheat、activation plan 或 MCP/plugin 编排；语义选择始终属于宿主。

可选 Codex native-agent bridge 是同一投影边界内的薄适配器：它只物化仓库 `agent/native-agent-bridge/` 中带 ownership marker 的 TOML 模板到固定 `~/.codex/agents`，不实现 provider/auth、agent runtime、队列、会话或动态模型路由。模板可携带针对该受管角色的静态 `model` / `model_reasoning_effort`；这只是避免继承全局默认值的配置事实，不建立模型选择器、fallback 或调度策略。bridge-only 配置也必须进入 `Test-ConfiguredHostProjection` 的 host promotion 检查；写入前拒绝 reparse ancestor/target，写入后记录 source revision、promotion mode、模板 hash、备份与回滚信息。该能力的文件存在只证明 `filesystem_projected`，不证明 Codex fresh session 已加载或 live 任务接受。

冷路由验收是两个独立 seam：`capability-router` 的 deterministic seam 只返回 `candidate_discovery_only` 或 `candidate_load_validated`；宿主执行 seam 必须单独观测 `host_visible`、host 对闭包 `SKILL.md` 的真实读取（若不可见则 `not_observable`）、native child 的 id/model/effort/lifecycle、授权副作用及用户结果。receipt 把 `expected`、`observed` 与 `assertion` 分离，避免用 `pass` 同时表示“事件发生”和“预期满足”。ZCode 没有 native custom-agent 机制时只能记录 `parent-mediated/not_supported`，不得升格为 Codex `host_specific_live_accepted`。

### Hermes consumer 与受控技能演进（未来、POC 门禁）

Hermes 不是本仓的第六条运行主链，也不是本仓需要嵌入的 runtime。它是一个可能消费技能的外部宿主；目前不存在 `HermesAdapter`、Gateway controller、Kanban bridge 或任何对 `~/.hermes` 的写路径。Codex `~/.codex/agents` 的 native-agent bridge 是独立、可选且受投影晋级合同约束的宿主适配，不改变 Hermes 边界。

在隔离 POC 未证明真实差异前，Hermes 只应消费项目级 `.agents/skills`，或消费经 ACL/独立用户保护的只读副本。现有 native projection 已能表达 source、package hash、managed/external ownership、receipt 和 rollback 时，不新增 consumer module。

`native_openai_codex` POC 与 `codex_app_server` POC 是两种不可互相替代的证据模式：前者不能证明后者的 host integration、managed block 或 MCP/plugin migration。两者都不能单独证明 `host_loaded`；每个拟议 consumer 必须以匹配的 runtime 路径、fresh host probe 和真实调用验收。

为减少操作性人工，协作 harness 可以自动执行无共享宿主写入的证据收集，但这不是新的 Hermes/skills-manager runtime 或状态库。每次 POC 只将既有 task brief/receipt 分类为 `auto_evidence`、`auto_stop` 或 `human_decision`：前者仅收集基线 hash、公开 inventory、固定 marker、package/schema/test 结果和 worktree 状态；后者在缺 marker、显式 provider/API 失败、shared config/MCP/plugin 非预期差异、write-set 越界或无法归因的权限变化时停止而不重试。`human_decision` 只承接共享宿主配置的保留/窄回滚、认证/权限升级、共享技能准入、非预授权 merge/push/release 与真实业务验收。自动证据收集、自动停止或 Git receipt 均不证明 `host_loaded` 或 `live_accepted`。

一个 task brief 可以预先声明 `allow_auto_local_merge=true`，但仅适用于无 remote 的 POC 仓：单一 worktree、固定 write set、无共享宿主差异、最低 gate 与独立 review 均通过、且 diff 不含凭据/生产配置/外部资产。满足该封闭条件时 harness 可在本地 commit/merge 并记录 receipt；任何条件不满足即回到 `human_decision`。这不允许自动 push、release 或改变 merge/release/live acceptance 的 owner。

只有同时满足下列条件才允许实现独立 consumer seam：

1. 一个与拟议 consumer runtime 匹配的隔离 POC 已证明 Hermes 对现有 native projection 有无法承载的稳定差异。
2. 至少一个真实 consumer 和一个可复现的 caller/验收流程存在；差异不是未来猜测。
3. 新 interface 可以保持为 `consumer_id + source fingerprint + target root + ownership/write policy + receipt + rollback`，且不泄露模型、会话、任务或权限语义。
4. 配置、计划、应用、回滚与 host probe 都能单独验证；缺少任何一项时保持 `not_implemented`。

若上述条件成立，consumer module 的 depth 应集中管理受管副本/链接、hash 绑定、ownership、原子替换、receipt 与 rollback；其 interface 不得演化为通用 agent orchestration framework。

技能演进同样不是 daemon。正确的数据流是：

```text
observed need
  -> project-local or sandbox candidate
  -> deterministic package/schema/safety validation
  -> reviewed Git change-set or reviewed source root
  -> explicit admission into skills.json / lock / overrides
  -> build + affected tests
  -> optional projection receipt
  -> fresh-host probe
  -> real task acceptance
```

其中 `observed need` 可以来自 ChatGPT Desktop、Hermes、Codex、CI 或人工；但 candidate 仍是普通文件/Git change-set，review/admission 是人工或被明确指定的独立 owner 决策。任何 Agent 的自动反思、记忆或自评都只能生成 proposal，不能越过 admission。

`Assert-SkillPackageSafe`、canonical identity、path containment、完整 package hash、受管 projection receipt 与 source/lock 是该链的确定性基础。不得为 proposal 新建第二任务数据库、长期 evidence archive、hidden memory store 或自动发布系统。

### MCP transport diagnostics

配置继续使用兼容字段 `transport=http`，运行语义统一标注为 `streamable_http`。doctor 只做脱敏的静态诊断：HTTPS 标为 encrypted，loopback HTTP 标为 local plaintext，非 loopback HTTP 输出风险；这些结果不证明远端服务可用、Origin 校验或认证已由服务端执行。

### Reference shelf

- Role：主架构之外、按任务显式启用的可选只读开发缓存
- Interface：`references/reference-shelf.manifest.json` 与 `scripts/refresh-reference-repos.ps1`
- Verification：`scripts/verify-reference-governance.ps1`
- Owned root：`D:\CODE\external\skills-manager-references`

`skills.json` 保持 runtime 真源；普通 build/test/update/projection 不读取 shelf。manifest 只保留 active core/secondary/conditional set，其中 conditional 必须绑定明确 consumer 且不进入默认刷新；manifest 只在显式 refresh/verify 中适用。refresh 对已有 checkout 先验证 origin identity 和 dirty state，并把单次结果写入 ignored `reports/reference-refresh/<run-id>/receipt.md`；clone/fetch/pull 不改变 runtime config。候选 backlog 与动态 latest 状态都不持久化。

## 3. 真值与状态

| 状态 | 真源 | 能证明什么 |
| --- | --- | --- |
| 配置 | `skills.json` / lock | 仓库期望 |
| 生成 | `skills.ps1` / `agent/` | source 与 generated 一致 |
| audit/projection/quality | ignored `reports/` | 一次运行的 receipt |
| reference（显式可选） | manifest + checkout Git state | 当前参考集合与 revision；不证明产品主链健康 |
| external consumer（未来） | reviewed consumer contract + projection receipt | 一次受管副本/链接的结果；不证明 Hermes/Codex 已加载或任务完成 |
| skill evolution（未来） | reviewed Git change-set / source root + admission decision | 候选已审查或已准入；不证明投影、宿主加载或业务验收 |
| host | 宿主配置/可见 inventory/新会话 | `host_loaded` |
| business | 真实用户任务 | `live_accepted` |

Tracked docs 只写稳定合同，不保存动态 task count、阶段状态或历史 receipt。

## 4. 写入安全

所有写路径至少包含：

1. exact authorized root/path containment
2. before hash for each mutable target
3. explicit token/flag（中高风险）
4. atomic replace 或逐 action receipt
5. rollback/compensation
6. truthful status when rollback fails

宿主目录、MCP、跨仓 rule estate 和 release 是不同授权域，不互相推导授权。

Tag release 在 checksum 与 ZIP 内 manifest 之外，为三个发布资产签发 GitHub OIDC build provenance attestation。它只证明资产摘要与仓库/workflow/tag 构建来源，不能证明宿主加载或业务验收。

## 5. 构建与验证

验证顺序为 `build -> test -> contract/invariant -> hotspot`：

- build：生成 bundle 与 agent tree
- test：受影响 Pester/E2E
- contract：committed generated bundle、config、host scheduler ownership 与公开契约；reference contract 仅由显式 reference verify 触发
- hotspot：仅在真实性能/安全/发布风险存在时执行

full gate 仅顺序执行一次 build、tests、committed generated bundle、lock、skill integrity 和 config contract。普通改动使用受影响验证，不重复 full。

CI 与本地共用 `scripts/quality/resolve-gate-profile.ps1`（`Resolve-QualityGateProfile`），本地提供 `-Profile auto`。分类按可解析基线与当前工作区执行；base 缺失、变更集不可读、untracked 枚举失败或出现 non-ignored untracked file 时 fail-safe 选择 full。分类正则的唯一权威副本驻留在该脚本，CI 不维护第二份内联副本；[HSM-GAT-100/110/120](skills-manager-hardening-implementation-plan.md) 是该 seam 的实现与迁移记录。

## 6. 删除原则

Module 删除后若复杂度直接消失，而不在真实 caller 重现，则该 module 是浅层控制面，应删除。当前禁止重新引入：

- plugin fixture distribution CLI
- 独立于 Git review/source admission 之外的 candidate/review/staging control plane 或第二状态数据库
- skill profile reconciliation/canary/runtime selector
- phase/task/evidence archive 作为当前状态库
- 无明确 consumer 的 conditional reference candidate backlog
- typed shadow 双实现
- 静态一键 workflow 与自动更新计划任务生命周期控制面
- Hermes/Codex runtime bridge、Gateway/cron/Kanban/task database、worktree lease manager 与自动 merge/push
- 无审查的 self-learning curator、直接修改全局 skill root 的 agent、或把 memory/AI self-review 当作 admission

只有新的真实失败、至少一个稳定消费者、现有 interface 无法承载、对比净收益和可回滚迁移同时成立时，才准入新 module 或 seam。
