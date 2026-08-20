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

配置 validator 负责 schema、path containment、duplicate name、mapping、MCP 与 projection invariants。source update 负责 revision/origin/dirty checks；build 只消费验证后的 source 和 override。

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
user profile + repo scan + installed inventory
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

## 6. 删除原则

Module 删除后若复杂度直接消失，而不在真实 caller 重现，则该 module 是浅层控制面，应删除。当前禁止重新引入：

- plugin fixture distribution CLI
- candidate/review/staging control plane
- skill profile reconciliation/canary/runtime selector
- phase/task/evidence archive 作为当前状态库
- 无明确 consumer 的 conditional reference candidate backlog
- typed shadow 双实现
- 静态一键 workflow 与自动更新计划任务生命周期控制面

只有新的真实失败、至少一个稳定消费者、现有 interface 无法承载、对比净收益和可回滚迁移同时成立时，才准入新 module 或 seam。
