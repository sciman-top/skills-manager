# skills-manager vNext 工程架构

**program_id**: `skills-manager-vnext`
**architecture_version**: 1
**status**: accepted-direction
**最后更新**: 2026-08-01

## 1. 架构结论

采用“PowerShell 模块化单体 + build-time 单文件 bundle + 文件型 versioned contracts + host adapters”的架构。

本项目位于宿主和能力来源之间，负责本地 inventory、选择、plan、显式 apply 和 evidence；宿主继续负责 agent execution、auth、permission、session、plugin/connector runtime 和 native loading。

```text
Official directories / Git / local inputs / host inventory
                         |
                    Source adapters
                         |
        +----------------+----------------+
        |                                 |
 Capability Catalog                Rule Advisor
        |                                 |
        +--------- Desired State ---------+
                         |
                  Operation Planner
                         |
              explicit Apply + freshness
                         |
                    Host adapters
                         |
          repo verify / native probe / receipt
```

## 2. 当前架构事实

- `build.ps1` 按固定顺序拼装 `src/*.ps1`，输出根 `skills.ps1`。
- `skills.json` 同时承载 vendors、mappings、imports、targets、skill projection 和 MCP 配置。
- `src/Commands/Install.ps1`、`Mcp.ps1`、`AuditTargets*.ps1` 包含应用、IO、宿主适配和显示逻辑。
- Pester 承担 unit/E2E，Python verifier 承担 dependency baseline，PowerShell scripts 承担生成同步、完整性、路由和 doctor contract。
- `reports/skill-projection/current.json`、audit bundles 和 change evidence 已提供部分 manifest/evidence 模式。

当前问题不是 PowerShell 本身，而是 bounded context、应用层和 IO seam 不够明确。Phase 0 先建立 seam，不做语言重写。

## 3. Bounded contexts

### 3.1 `CapabilityCatalog`

职责：发现和规范化 skill、plugin、MCP descriptor 的身份、来源、版本、兼容和 lifecycle。

不负责：profile 选择、宿主写入、OAuth、运行 MCP server。

核心类型：

```text
CapabilityDescriptor
  id
  kind: skill | plugin | mcp
  name
  source
  version_or_revision
  checksum
  license
  trust_tier
  lifecycle_status
  host_compatibility[]
  components[]
```

### 3.2 `SkillProjection`

职责：保留当前 skill source、canonical selection、alias、profile budget、Junction 和 Codex path enable/disable。

不负责：plugin 安装、规则优化、删除非受管技能根。

### 3.3 `McpGovernance`

职责：保留当前 MCP server/profile/target，生成受控工具面和宿主 projection plan。

不负责：服务托管、连接器账号、凭据保存或业务级验收。

### 3.4 `RuleAdvisor`

职责：发现规则、建立加载候选链、静态诊断、repo truth 核对、建议 surface、生成 patch plan。

不负责：中央规则库、跨仓同步、权限 enforcement、Phase 1 中的任何写入。

核心类型：

```text
RuleDocument
  id
  host
  scope: global | repo | subtree | override
  responsibility: common | platform_delta | project_action | deterministic_enforcement | task_local
  path
  owner
  content_hash
  byte_size
  precedence
  source_of_truth
  findings[]
  verification_state
```

`RuleDocument` 不继承 `CapabilityDescriptor`。两者只通过 planner 的 `target_ref` 被操作。

规则协同的最小分析单位不是某个固定 heading，而是 `RuleResponsibility`：

```text
RuleResponsibility
  constraint_id
  common_intent
  platform_deltas[]
  project_actions[]
  enforcement_refs[]
  coverage: covered | gap | conflict | duplicated | not_applicable
  evidence[]
```

`covered` 需要共同意图、适用平台差异和至少一个可执行项目动作互相兼容；只有共同规则或只有项目命令都不构成 1+1>2。结构 profile 只帮助发现，不改变宿主真实 precedence，也不替代 native probe。

### 3.5 `TargetAudit`

职责：扫描目标仓事实、用户画像、当前能力和推荐候选，为 capability/rule plan 提供证据。

不负责：把 AI recommendation 直接当作 apply authority。

### 3.6 `OperationPlanning`

职责：为所有受管写入提供一致的 plan、freshness、apply、receipt 和 rollback envelope。

不负责：理解每个领域的业务决策。领域模块负责产生 actions 和领域 verification，planner 负责通用安全边界。

## 4. 目标源码结构

结构按渐进迁移建立，不要求 Phase 0 一次移动全部旧函数：

```text
src/
  Domain/
    Capability.ps1
    RuleDocument.ps1
    OperationPlan.ps1
    Receipt.ps1
  Application/
    CapabilityInventory.ps1
    RuleAdvisor.ps1
    OperationPlanner.ps1
  Adapters/
    Sources/
      GitSource.ps1
      LocalSource.ps1
      OfficialDirectorySource.ps1
    Hosts/
      CodexHost.ps1
      ClaudeHost.ps1
      GeminiHost.ps1
      TraeHost.ps1
  Infrastructure/
    JsonFiles.ps1
    Hashing.ps1
    AtomicWrite.ps1
    Redaction.ps1
    NativeProcess.ps1
  Commands/
  Main.ps1
```

迁移规则：

- 新文件先由 `build.ps1` 按依赖顺序加入 bundle。
- 旧 public/CLI function 保留薄 wrapper；每个切片只迁移一个有测试覆盖的 seam。
- 不为了目录对称创建空模块。
- 不引入 PowerShell class hierarchy；优先使用 plain object + validator function，保持 PS 5.1 兼容窗口。
- 领域函数尽量 pure：输入对象，返回对象；IO、Write-Host、exit 和环境变量读取留在 adapter/command 层。

## 5. OperationPlan contract

### 5.1 Plan

```json
{
  "schema_version": 1,
  "operation_id": "op-<timestamp>-<nonce>",
  "domain": "mcp|skill_projection|rules|plugin",
  "mode": "dry_run|apply",
  "created_at": "RFC3339",
  "source_revision": "optional git revision",
  "targets": [
    {
      "target_ref": "stable domain identifier",
      "path": "absolute or repo-relative normalized path",
      "before_hash": "sha256 or absent",
      "desired_hash": "sha256",
      "owner": "domain adapter"
    }
  ],
  "actions": [
    {
      "action_id": "stable within plan",
      "type": "create|update|delete|native_command",
      "target_ref": "...",
      "summary": "redacted summary",
      "risk": "low|medium|high"
    }
  ],
  "preconditions": [],
  "verification": [],
  "rollback": []
}
```

计划不保存 token、完整连接串、OAuth material 或未脱敏进程参数。

### 5.2 Freshness

Apply 前必须逐目标检查：

1. path 仍在本次授权 root 内。
2. target owner 与执行 adapter 一致。
3. 当前 hash 与 `before_hash` 一致；原本不存在的目标仍不存在。
4. source/config revision 未漂移，或领域 validator 明确允许 additive drift。
5. 所需 native CLI/version/capability 仍满足 precondition。

任何失败都返回 stale/blocked，不部分写入未开始的 action。

### 5.3 Receipt

```json
{
  "schema_version": 1,
  "operation_id": "same as plan",
  "status": "dry_run|applied|partial|failed|rolled_back",
  "started_at": "RFC3339",
  "completed_at": "RFC3339",
  "actions": [],
  "backups": [],
  "verification": {
    "static_validated": "pass|fail|not_run|not_applicable",
    "repo_gates_passed": "pass|fail|not_run|not_applicable",
    "host_loaded": "pass|fail|not_run|not_applicable",
    "live_accepted": "pass|fail|not_run|not_applicable"
  },
  "rollback": []
}
```

`host_loaded` 不得由静态配置解析自动置为 pass；`live_accepted` 不得由 native list/smoke 自动置为 pass。

## 6. 写入与事务

- Repo 内文件：写临时文件、解析验证、atomic replace、保留 before hash。
- Host-local 文件：限制在 adapter 声明的受管块/路径，写前备份到 host-local ignored backup root。
- Native CLI：记录经过脱敏的 argv、exit code 和关键输出；优先原生命令而非手写完整宿主配置解析。
- 多目标 operation：先完成全部 preflight，再按 action 顺序写；出现失败后仅回滚本 operation 已应用 action。
- 不用 Git reset/checkout 作为产品 rollback；rollback 是精确文件/受管块恢复。
- 运行态 plan/receipt 默认写入忽略目录，只有无敏感信息的 change evidence 可提交。

## 7. Host adapter contract

每个 host adapter 必须声明：

| 字段 | 含义 |
| --- | --- |
| `host_id` | `codex`、`claude`、`gemini`、`trae` 等稳定 ID |
| `supported_surfaces` | skills/plugin/MCP/rules 中真实支持的集合 |
| `read_paths` | 允许读取的文件/目录 |
| `managed_write_paths` | 允许写入的精确路径或受管块 |
| `native_commands` | list/install/enable/verify 等已由 help 证明的命令 |
| `trust_boundary` | 用户级、项目级、managed/admin 或 hosted boundary |
| `activation_boundary` | 当前 session、fresh session、restart 或 unknown |
| `verification_levels` | adapter 能真实证明的最高层级 |

适配原则：

- Codex/ChatGPT 的 public product 语义以官方 manual/docs 和当前可调用能力为准。
- ChatGPT hosted surface 不继承本机文件或 sandbox；没有 connector/plugin/API 证据时不得声称已投影。
- Plugin install/enable 优先调用官方目录或 CLI；本项目不反向生成官方商店状态。
- 不支持的能力返回 `platform_na`，不通过隐式 fallback 写其他配置。

## 8. Rule advisor pipeline

```text
Discover -> Classify -> Build candidate load chain -> Parse -> Diagnose
         -> Verify repo facts -> Select smallest surface -> Produce findings
         -> Patch plan (Phase 2) -> Explicit apply -> Fresh native probe
```

诊断规则分四类：

1. `structural`：文件名、scope、precedence、size、BOM、wrapper、required headings。
2. `semantic`：重复、冲突、层级错位、不可执行表述、把建议当权限。
3. `repo_truth`：命令/path/gate 与当前代码、CI、README 不一致。
4. `host_truth`：官方加载语义、config/help/schema 或 native probe 不支持。

责任覆盖另输出五态：`covered`、`gap`、`conflict`、`duplicated`、`not_applicable`。它与 finding severity 分离，避免把“结构不同”直接判为错误。

Semantic findings 在没有 deterministic evidence 时只能是 recommendation，不作为 blocker。命令/path/encoding/schema 等 deterministic finding 才能 fail gate。

默认 profile 可以建议 common/platform/project 分区、全局与项目体量预算及薄 wrapper，但 profile 必须可配置。宿主官方加载模型、目标仓规模或真实差异不匹配时，应给出 `adapt` 或 `defer`，不能为了模板一致性改写仓库。

## 9. 配置与 schema

- `skills.json` 在兼容窗口内继续是 skill/MCP runtime truth，不加入 rules 文本或 host auth/model 设置。
- Phase 0 为 `skills.json` 建立 schema 和 migration/version policy；先 observe 再 enforce。
- Rule advisor 配置只在 Phase 1 有真实字段后建立独立文件，禁止预建空的万能 `rulesets.json`。
- Operation plan/receipt 分别拥有独立 schema version。
- task manifest 属于 planning contract，不属于产品 runtime config。

## 10. 技术栈决策

### 10.1 当前条件下的最优性

不存在脱离目标、约束和时间尺度的单一“全局最优技术栈”。这里把全局最优定义为：在所有已知目标上位于 Pareto 前沿，并保留最大未来选择权的参考架构；任何一项继续改善都会显著损害成本、可靠性、兼容、交付速度或可逆性中的至少一项。

若暂时忽略本仓迁移成本，一个更接近全局最优的长期参考形态是：protocol-first 的稳定 domain contracts、可替换的 source/host adapters、无宿主状态的 planning engine、显式事务/证据协议、跨平台 typed core，以及按真实规模选择的 CLI/TUI/API 和可选本地索引。它是 north star，不是当前 backlog；database、daemon、remote control、extension SDK 等只有触发条件成立后才进入实现。

当前约束下的适配性最优则把已验证事实纳入目标函数：Windows-first、现有 PowerShell/Pester 投资、单文件便携分发、当前用户规模、CLI/Junction/Git 密集工作和兼容成本。当前核心工作是建立模块 seam 和合同，以最低行为风险获得主要维护收益。

| 维度 | 全局最优参考 | 当前适配性最优 |
| --- | --- | --- |
| 优化范围 | 已知及合理未来场景 | 当前用户、仓库和近两个 Phase |
| 迁移成本 | 可作为长期投资处理 | 作为真实高权重成本 |
| 不确定性 | 用可替换边界保留选择权 | 延迟未被证据证明的能力 |
| 技术选择 | 可接受 typed core/多入口/可选索引 | PowerShell 模块化单体 + 单文件 bundle |
| 验收 | 跨平台、规模、生态和演进性 | 兼容、门禁、可回滚和真实工作流 |
| 主要风险 | 过早平台化 | 被当前实现锁死、错过重评时点 |

| 方案 | 现有兼容/迁移风险 | Windows 与 native CLI 适配 | 分发复杂度 | 长期类型/并发能力 | 当前决定 |
| --- | --- | --- | --- | --- | --- |
| PowerShell 模块化单体 + 单文件 bundle | 高兼容、低迁移风险 | 高 | 低 | 中 | 采用 |
| .NET 单体 CLI | 中低兼容、需迁移入口/测试 | 高 | 中 | 高 | 条件重评 |
| TypeScript/Node CLI | 中低兼容、增加 runtime/打包 | 中 | 中高 | 高 | 当前拒绝 |
| daemon/API + database | 破坏 local single-process 边界 | 中 | 高 | 高 | 无需求证据，拒绝 |

改进方向不是重写，而是依次完成：纯 Domain contract、Application orchestration、Infrastructure/Host adapter seam、结构化 plan/receipt、兼容 wrapper 和 characterization tests。只有出现可量化的跨平台、并发、类型安全或性能瓶颈，且连续多个有界切片无法解决，才启动替代技术栈 ADR/PoC；PoC 必须证明迁移收益、兼容策略、分发和回滚，不能仅以代码风格作为理由。

选择算法固定为：先列 hard constraints 和不可接受结果；再比较满足约束方案的用户价值、总拥有成本、风险、可逆性和 option value；删除被支配方案；选择能完成下一真实里程碑的最小 Pareto 方案；最后为未选择的更重方案记录量化重评触发。全局参考用于检查方向，适配性方案用于决定当前实现。

### 10.2 运行与工程工具

- Runtime：PowerShell 7 主路径；Windows PowerShell 5.1 仅保留有界 bootstrap/smoke 兼容窗口。
- Source/build：`src/*.ps1` 模块化源码 + `build.ps1` 确定性 bundle + 根 `skills.ps1` 便携入口。
- Contracts：UTF-8 JSON、显式 `schema_version`、plain object validator 和稳定 finding/exit contract；具体 schema validator 在 `SMV-P0-003` 以当前依赖事实选定。
- Tests：Pester 4.10.1 unit/E2E、fixture/golden/characterization/fault injection，以及 Python dependency baseline verifier。
- Distribution/state：Git、lock/manifest、文件 hash、ignored plan/receipt/backup；不增加数据库或常驻服务。
- Integration：优先 native CLI/plugin/connector，缺少原生入口时才使用精确 scoped file adapter。

### `ADR-SMV-001 Keep PowerShell modular monolith`

决定：继续使用 PowerShell，按模块 seam 演进，保留单文件发行。

理由：当前主要工作是 Windows 文件、Git、Junction、CLI 和宿主配置；现有测试/发布投资大，重写不会直接改善产品价值。

重评触发：非 Windows 成为核心使用量、需要常驻 API/并发服务、类型/性能缺陷连续多个 Phase 无法通过 seam 修复。

### `ADR-SMV-002 PowerShell 7 primary, 5.1 compatibility window`

决定：开发/CI 以 PowerShell 7 为主；5.1 保留 bootstrap 和显式 smoke。

理由：避免 legacy runtime 永久限制结构化错误处理、跨平台和依赖能力，同时保持现有 Windows 用户迁移路径。

### `ADR-SMV-003 Separate domain models`

决定：Capability、RuleDocument、Profile 不建立通用继承树；共享 OperationPlan/Receipt envelope。

理由：三者 identity、lifecycle、trust 和 apply 语义不同；过早统一会制造 nullable mega-object。

### `ADR-SMV-004 Official-first host integration`

决定：先调用 native CLI/plugin/connector；只有无原生入口时才维护精确配置段。

理由：降低宿主格式漂移、认证复制和深耦合。

### `ADR-SMV-005 No service or database`

决定：当前不建设 daemon、Web API、数据库、RBAC 或远程控制面。

理由：单用户本地工作流没有证据需要这些成本；文件、Git、lock 和 receipt 足够。

### `ADR-SMV-006 Advisory-first rules`

决定：Phase 1 规则能力严格只读；Phase 2 才允许显式单目标 apply。

理由：规则优化包含语义判断，自动跨仓写入的误伤和真值漂移风险高。

### `ADR-SMV-008 Responsibility coverage over universal template`

决定：以 `common + platform_delta + project_action` 的责任覆盖和证据判断协同效果；固定 `1/A/B/C/D`、体量预算和 wrapper 只作为可配置 profile。

理由：这保留参考仓已验证的边界设计，同时避免把单一用户/宿主结构固化成所有目标仓的规则框架。

### `ADR-SMV-007 Machine-readable current-phase tasks`

决定：只为当前实施 Phase 维护详细 JSON task manifest，后续 Phase 在 entry gate 通过后再展开。

理由：给 AI 足够执行细节，同时避免维护数十个尚未验证的猜测任务。

## 11. 安全与供应链

- 外部内容是不可信输入，不执行其仓库指令或脚本，除非单独评估并授权。
- 记录 source revision/checksum/license；floating `latest` 只能用于 discovery，不能直接进入 locked apply。
- MCP/plugin capability 必须声明 external data/action 和 auth boundary。
- plan/receipt/evidence 统一 redaction；测试包含 token、URL userinfo、connection string 和 env value fixtures。
- hooks 视为代码执行面，必须显式 review/trust；本项目不自动启用第三方 hook。
- 规则 prose 不是权限系统；确定性拦截放 native policy、hooks、scripts 或 CI。

## 12. 性能与资源

- inventory 扫描使用 root allowlist、目录排除、mtime/content fingerprint 和有界并行。
- external reference refresh 与 runtime scan 分离，不在日常 doctor 中隐式 fetch/clone。
- package hash cache 继续 fail-safe；未知 schema 或 fingerprint mismatch 回退 full hash。
- native probe 有 timeout、重试上限和可观察 exit；不无限等待宿主进程。
- 不为性能跳过 checksum、freshness、schema 或 redaction。

## 13. 迁移策略

1. Phase 0 先添加 schema、seam 和 contract，不改变现有 CLI 行为。
2. 新 application/domain function 与旧 wrapper 并行，使用 golden/compat tests 证明输出一致。
3. 每迁移一个 command seam 后才从旧大文件移除对应 implementation。
4. 新 OperationPlan 先用于一个低风险路径 observe；receipt 与旧结果对比通过后再 enforce。
5. rules advisor Phase 1 不接入写入路径。
6. 兼容窗口结束必须有 usage evidence、迁移说明和 rollback，不按日期自动删除。

## 14. 反过度设计守卫

以下任一提案默认拒绝，除非有重复真实问题、明确用户和验收证据：

- 通用 agent runtime、planner、memory、model router 或 provider gateway。
- 中央目标仓 registry、跨仓自动同步或统一规则服务。
- 为每个宿主复制完整插件商店、OAuth 或 connector 管理。
- 只为展示 inventory 而建设数据库、搜索集群、Web/WPF UI。
- 为尚未实现的 Phase 预建空接口、空配置或通用 extension SDK。
- 用 LLM score 直接阻断安装、写规则或自动删除能力。
- 因目录“更干净”一次性重写全部 PowerShell 模块。

新抽象必须至少满足一项：消除两个真实调用点的重复、形成可测试安全边界、匹配稳定外部协议，或降低已量化热点复杂度。

## 15. 验证矩阵

| 层级 | 证明 | 不证明 |
| --- | --- | --- |
| schema/unit | object 和 validator 行为 | CLI/宿主行为 |
| golden/fixture | 兼容输出、diff、redaction | native load |
| repo gate | 构建、测试、contract、hotspot | host loaded |
| native list/probe | 当前 host 发现/加载 | 真实业务效果 |
| live workflow | 特定真实任务成功 | 其他宿主/账号/环境 |
| human acceptance | 指定用户/场景认可 | 普遍产品完成 |

任何报告必须选择最高实际执行层级，不得从低层自动推断高层。
