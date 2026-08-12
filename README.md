# skills-manager

[English](README.en.md) | 中文

`skills-manager` 是一个 Windows 优先的 PowerShell 管理器，用来把多来源 AI agent skills 汇总到统一工作区，生成稳定产物，并同步到 Claude、Codex、Gemini、Trae 等本地 CLI。

它适合这些场景：

- 同时维护多个 agent 的 skills 目录，不想分别手工拷贝。
- 需要混用整库 vendor、定向 import、本地 override 三种来源。
- 希望把可手改输入层和不可手改生成层明确分开。
- 需要把 MCP 清单、目标仓审查包、portable 发布和新机安装纳入同一套脚本入口。

## 当前状态与边界

- 单一命令入口：`skills.ps1`
- 单一配置真源：`skills.json`
- 源码入口：`src/`；运行 `./build.ps1` 生成根目录 `skills.ps1`
- 默认 skills 同步目标：`~/.claude/skills`、`~/.codex/skills`、`~/.gemini/skills`、`~/.gemini/antigravity/skills/`、`~/.trae/skills/`
- MCP 托管真源：`skills.json` 的 `mcp_servers`；落地产物由 `.\skills.ps1 同步MCP` 生成
- 非 MCP 宿主设置不在本仓托管边界内，例如 Codex `windows.sandbox`、approval/model/context，Claude/Gemini 的 auth/provider/model/context/sandbox

## 产品方向（vNext）

本项目将按已落盘的 vNext 规划，演进为 Windows-first、local-first 的 AI capability curator 与 rule advisor：继续管理 skills/MCP，并增加官方 plugin awareness、统一但不扁平化的 capability inventory、全局/项目规则只读诊断，以及经过 plan/diff/显式 apply/receipt 保护的受管写入。

它不会成为 agent runtime、插件商店、provider/model/auth/session 管理器、中央目标仓 registry 或跨仓规则同步服务。规则能力默认 advisory-first，宿主加载和 live acceptance 必须由各自 native/真实工作流证据证明。

- [产品文档索引](docs/product/README.md)
- [vNext PRD](docs/product/skills-manager-vnext-prd.md)
- [vNext 架构](docs/product/skills-manager-vnext-architecture.md)
- [vNext 路线图](docs/product/skills-manager-vnext-roadmap.md)
- [规则治理参考采纳矩阵](docs/product/rule-governance-adoption-matrix.md)
- [当前 Phase 5 任务 manifest](tasks/skills-manager-vnext-phase5.tasks.json)
- [Agent workflow advisory spec](docs/superpowers/specs/2026-08-05-agent-workflow-advisory-runtime.md) / [任务 manifest](tasks/skills-manager-vnext-agent-workflow-advisory.tasks.json)
- [历史 Phase 4 任务 manifest](tasks/skills-manager-vnext-phase4.tasks.json)
- [历史 Phase 3 任务 manifest](tasks/skills-manager-vnext-phase3.tasks.json)
- [Phase 2 历史任务 manifest](tasks/skills-manager-vnext-phase2.tasks.json)
- [Phase 1 历史任务 manifest](tasks/skills-manager-vnext-phase1.tasks.json)
- [Phase 0 历史任务 manifest](tasks/skills-manager-vnext-phase0.tasks.json)

vNext P0-P5 已完成 repo-side 验收（P0/P1 各 9/9，P2/P3 各 7/7，P4 6/6，P5 5/5）；这是历史仓库契约真值，不等于自然语言路由实效。P5-local maintenance 已把语义选择权交回宿主 AI，并把 profile-first cold discovery 重构为 `domain purpose catalog -> host domain/candidate adjudication -> deterministic policy`；只读 App Server snapshot、session reuse 建议和 containment/freshness/availability/side-effect/approval/activation policy 继续保留。plugin/MCP 安装、OAuth、host/profile/session 写入、重启与 `live_accepted` 仍不在边界。

本项目仅支持 PowerShell 7 (`pwsh`)；PowerShell 7.6 LTS 是推荐基线。Windows PowerShell 5.1 不再提供安装 fallback、CI 或 smoke 支持，缺少 `pwsh` 时入口 fail-closed。迁移、编码与回滚边界见 [`docs/runbooks/powershell-runtime-compatibility.md`](docs/runbooks/powershell-runtime-compatibility.md)。

PowerShell 仍是当前唯一运行真源，但不再是所有未来领域逻辑的默认永久归宿。针对 AI 生成脚本常见的 parser/quoting/动态类型/encoding/native-process 返工，目标架构采用 `versioned protocol -> 条件性 C#/.NET typed core -> PowerShell thin shell`。当前 TC0/TC1 已对 `OperationPlan/Receipt v1` 建立 package-free C#/.NET `shadow_only` PoC，并在固定 corpus 上实现 PowerShell/C# parity；它没有接入 CLI/生成 bundle，TC2 生产迁移仍为 `not_started`，禁止直接全仓重写或形成双真源。

长链路任务的模型与子 Agent 编排继续由宿主 AI 负责；本仓已实现可审查、runtime-independent 的 TaskGraph/FailurePacket v1、RadarSnapshot v2、completion receipt、barrier wave、三档宿主 proposal 校验和 failure escalation 建议。`Sol xhigh / Sol medium / Luna max` 是可覆盖软锚点，Luna max 是当前用户默认；它们不是仓库动态路由。本仓不拉起 subagent、不调用 provider、不抓取 Radar，也不修改 active session、custom-agent、provider/auth 或 host config。仓库侧验证与计划入口：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\skills.ps1 agent-validate --input .\tests\fixtures\agent-workflow\valid-request.json --json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\skills.ps1 agent-plan --input .\tests\fixtures\agent-workflow\valid-request.json --json
```

输出固定 `decision_owner=host_ai`、`executor=host_native_runtime` 和 `provider_calls/native_mutations/writes=0`。实际并发由宿主按当前 wave/group 使用原生 subagent/worktree 拉起，并以 verified completion receipt 解锁下一 wave；serial/high-risk/high-ambiguity、共享 seam、schema/migration、Git/external state 与最终 full gate 始终串行。模型可用性按目标 surface 归一为 `confirmed_available / confirmed_unavailable / unknown`，`unknown` 不得被 Radar 或另一 provider receipt 提升。当前最大真值是本仓 `repo_verified/repo_advisory_only` 加独立 `host_evaluation_partial`；Luna max 的 read-only CLI/provider probe 已通过，但 collaboration spawn 当前为 `confirmed_unavailable`，历史 Radar v1 receipt 也不满足 v2 revalidation。

Phase 1 的只读入口（未指定 `--out` 时不写文件）：

```powershell
.\skills.ps1 capability-inventory --json
.\skills.ps1 rule-audit --repo . --host codex --json
.\skills.ps1 rule-estate-audit --workspace-root D:\CODE --registry .\audit-targets.json --json
```

`rule-estate-audit` 默认排除 `external` 与 `文档`，自动发现工作区直属 Git 仓，报告目标清单漂移、Codex/Claude common/delta 对齐、规则版本和 `Global Rule -> Repo Action` 覆盖。`--out <report.json>` 只允许在显式 workspace root 内写一个报告文件，不得穿过 reparse/junction 祖先，也不允许覆盖发现到的规则文件；plan/apply 控制文件使用同一边界。

经人工或登记策略审阅的全局/项目规则 change-set 可进入受控多目标流程：

```powershell
.\skills.ps1 rule-estate-plan --review <reviewed-change-set.json> --workspace-root D:\CODE --out <estate-plan.json> --json
.\skills.ps1 rule-estate-apply --plan <estate-plan.json> --workspace-root D:\CODE --token APPLY_RULE_ESTATE_PATCH --out <estate-receipt.json> --json
.\skills.ps1 rule-estate-rollback --receipt <estate-receipt.json> --action-id <action-id> --workspace-root D:\CODE --token ROLLBACK_RULE_ESTATE_PATCH --json
```

该流程先全量预检，再逐目标原子写入并持久化 receipt；失败立即停止，已完成目标不自动回滚，可从 receipt resume 或单独 rollback。默认拒绝 AI 自声明 reviewed、目标规则 stale hash、目标集合漂移、锁冲突和越界文件；仓内无关 dirty paths 只记录并原样保留，不修改 provider/auth/model/sandbox/plugin/native host 配置，也不自动 commit/push。

P2 事务入口支持 fixture、单仓和 reviewed rule-estate 三种显式授权域：

```powershell
.\skills.ps1 rule-plan --target <fixture-rule> --desired-file <reviewed-file> --fixture-root <fixture-root> --json --out <fixture-plan.json>
.\skills.ps1 rule-apply --plan <fixture-plan.json> --fixture-root <fixture-root> --token APPLY_RULE_PATCH --json
.\skills.ps1 rule-plan --target <repo-rule> --desired-file <reviewed-file> --repo-root <git-root> [--allow-create] --json --out <repo-plan.json>
.\skills.ps1 rule-apply --plan <repo-plan.json> --repo-root <git-root> --token APPLY_RULE_REPO_PATCH --json
```

单仓模式只允许精确 Git 根内的 `AGENTS.md`、`AGENTS.override.md` 或 `CLAUDE.md`，并执行 hash freshness、reparse、原子写入和回滚守卫；全域模式另以 reviewed change-set 和更严格的根文件 allowlist 管理全局用户规则及多个目标仓。

P3 plugin-aware 命令中，inventory/lint/eval 为只读；export 仍严格 fixture-only：

```powershell
.\skills.ps1 plugin-inventory --official <snapshot.json> [--personal <snapshot.json>] [--workspace <snapshot.json>] --json
.\skills.ps1 plugin-lint --path <plugin-root> --json
.\skills.ps1 plugin-export --candidate <candidate.json> --fixture-root <fixture-root> --out <new-folder> --token EXPORT_PLUGIN_FIXTURE --json
.\skills.ps1 plugin-eval --path <plugin-root> --json
```

本阶段只支持已验证的 Codex skills-only package。命令不会安装/启停 plugin、修改 marketplace/host profile、调用 provider，model snapshot 也不作为 deterministic blocker。

## 路径与编辑策略

| 路径 / 键 | 作用 | 编辑策略 |
| --- | --- | --- |
| `skills.json` | 单一配置真源，托管 `vendors / mappings / imports / targets / sync_mode / mcp_servers` | 直接修改；用 `scripts/verify-skills-config.ps1 -Mode enforce` 做只读校验 |
| `config/skills.schema.json` | `skills.json` v1 结构、兼容与敏感信息输出策略 | 版本化维护；缺少 `schema_version` 按 legacy v1 observation 读取 |
| `config/host-capability-matrix.json` | 宿主 surface、所有权、activation 与最高自动验证层级的只读合同 | 用 `scripts/verify-host-capability-matrix.ps1` 校验；不得写成 live inventory |
| `src/` | 源模块 | 在这里改逻辑，再运行 `./build.ps1` |
| `skills.ps1` | 生成后的入口脚本 | 不手改；由 `build.ps1` 生成 |
| `vendor/` | 上游整库缓存 | 不手改；通过 `更新` 或锁文件重建 |
| `imports/` | 定向导入来源落地层 | 仅作为输入层维护，不把它当生成产物修补 |
| `overrides/` | 已审阅的本地输入层 | `custom/` 放本仓自定义能力，`patches/` 放上游替换/补丁，`resources/` 放无 `SKILL.md` 的资源桥；根级只放具名单文件 override |
| `agent/` | 生成产物与同步源 | 不手改；通过 `构建生效` 重建 |
| `reports/skill-audit/<run-id>/ai-brief.md` | 审查运行包摘要 | 运行态产物，不手改 |
| `reports/skill-audit/<run-id>/outer-ai-prompt.md` | 外层 AI 执行提示词 | 运行态产物；改默认提示词请改 `src/Commands/AuditTargets.ps1` 或 `overrides/audit-outer-ai-prompt.md` |

分类目录的叶子名仍是稳定输出名：`overrides/<category>/<leaf>` 会生成 `agent/<leaf>`。旧的 `overrides/<leaf>` 扁平目录只在迁移窗口内兼容读取；新内容不得继续放入扁平目录，跨分类同名会阻断构建。详见 [overrides/README.md](overrides/README.md)。

## 快速开始

首次使用建议直接进入交互菜单：

```powershell
.\skills.ps1
```

最小上手路径：

```powershell
.\skills.ps1 发现
.\skills.ps1 安装
.\skills.ps1 构建生效
.\skills.ps1 doctor --strict --threshold-ms 8000
```

交互菜单按“高频动作直达 + 领域子菜单”组织：

- 浏览技能
- 选择安装
- 粘贴命令导入
- 卸载技能
- 重建并同步（CLI 命令仍为 `构建生效`）
- 更新上游（CLI 命令仍为 `更新`）
- 目标仓审查
- MCP 服务
- 技能库管理
- 更多

## 一键工作流

```powershell
.\skills.ps1 一键 --list
.\skills.ps1 一键 新手
.\skills.ps1 一键 维护 --continue-on-error
.\skills.ps1 一键 审查 --no-prompt
.\skills.ps1 workflow all --no-prompt
```

当前内置场景：

- `新手` / `quickstart` / `start` / `onboarding`
  浏览技能 -> 选择安装 -> 重建并同步 -> `doctor --strict --threshold-ms 8000`
- `维护` / `maintenance` / `maintain`
  更新上游 -> 重建并同步 -> 同步 MCP -> `doctor --strict --threshold-ms 8000`
- `审查` / `audit`
  查看需求 -> 目标仓列表 -> 生成审查包 -> 查看最近状态
- `全流程` / `all` / `full`
  更新上游 -> 浏览技能 -> 重建并同步 -> 同步 MCP -> `doctor --strict --threshold-ms 8000`

未指定场景且传入 `--no-prompt` 时，默认执行 `all`。

## 常用命令

### 发现、导入、安装、卸载

```powershell
.\skills.ps1 发现
.\skills.ps1 安装
.\skills.ps1 命令导入安装
.\skills.ps1 add <repo> [--skill <name>] [--ref <branch/tag>] [--mode manual|vendor] [--sparse]
.\skills.ps1 npx "skills add <repo> --skill <name>"
.\skills.ps1 卸载 [<skill-name>|<index>|all] [--yes] [--filter <keyword>]
.\skills.ps1 清理无效映射 [--yes] [--no-build]
```

说明：

- `add` 未指定 `--skill` 时，只登记技能库，不会安装整库技能。
- 指定 `--skill` 时，默认按 `manual` 导入到 `imports/`；传 `--mode vendor` 可改为 vendor 管理。
- `命令导入安装` 支持连续粘贴多条 `add` / `npx skills add` / `npx add-skill` 命令；行尾用 `\` 可续行。
- `卸载` 不带参数时进入交互选择；传技能名、序号或 `all` 时可配合 `--yes` 非交互执行。
- `清理无效映射` 的英文别名是 `prune-invalid-mappings`。

### 构建、更新、锁定、维护

```powershell
.\skills.ps1 构建生效
.\skills.ps1 更新 -Plan
.\skills.ps1 更新 -Upgrade
.\skills.ps1 锁定
.\skills.ps1 新增技能库
.\skills.ps1 删除技能库
.\skills.ps1 自动更新设置
.\skills.ps1 解除关联
.\skills.ps1 清理备份
.\skills.ps1 doctor [--json] [--fix] [--dry-run-fix] [--strict] [--strict-perf] [--threshold-ms <ms>]
```

说明：

- 只想把当前配置重新输出到 `agent/` 和目标目录时，用 `构建生效`。
- `构建生效` 在写入仓库外的宿主技能/config 目录前要求当前技能源是 clean Git commit，并在 projection manifest 记录 source revision、dirty 状态和 promotion mode。`-AllowUnverifiedHostProjection` 只用于明确接受风险的例外，manifest 会如实标记 `unverified_override`，不会伪装成已通过 full gate。
- 需要拉取上游新内容时，用 `更新`；`-Plan` 只看预览，`-Upgrade` 会更新后刷新 `skills.lock.json`。
- `锁定` 会生成或刷新 `skills.lock.json`，给后续 `更新 -Locked` 和 portable 安装重放使用。
- `doctor --strict` 在校验不通过时会返回非零退出码，适合作为脚本门禁。

### MCP 管理

```powershell
.\skills.ps1 安装MCP context7 -- npx -y @upstash/context7-mcp@3.2.3
.\skills.ps1 卸载MCP context7
.\skills.ps1 同步MCP
.\skills.ps1 mcp-sync --plan --json
.\skills.ps1 mcp-sync --plan --json --out .\reports\mcp-plan.json
.\skills.ps1 MCP配置 列表
.\skills.ps1 MCP配置 使用 coding
```

说明：

- `安装MCP` / `卸载MCP` 会更新 `skills.json`，随后自动执行一次 `同步MCP`。
- `同步MCP` 会把 MCP 服务清单写入目标根目录 `.mcp.json`、Gemini/Trae 配置以及 Codex `config.toml` 的 `[mcp_servers.*]` 段。
- `mcp-sync --plan --json` 复用 apply 的 desired-state calculation，输出确定性、脱敏的 `OperationPlan v1`；plan 不写 MCP 目标、不调用 native add/remove，也不修改 active profile。只有显式 `--out` 会写指定的 plan 文件。
- 未传 `--plan` 的 `同步MCP` / `mcp-sync` 保持原有 apply 行为；旧 `-DryRun` 人类可读预演语义也保持兼容。
- `skills.json.mcp_profiles` 是用途 profile 真源；`MCP配置 使用 <name>` 会持久化 active profile 并同步。Codex 保留完整服务清单，通过 `enabled` / `enabled_tools` 启停和收窄工具面；Claude/Gemini/Trae 只接收当前 profile 启用的服务。
- 默认 profile 仅启用 `microsoft-learn` 与 `openaiDeveloperDocs`；`coding`、`codebase`、`browser`、`database` 等 profile 按任务启用其他服务。切换不会卸载 MCP，`node_repl` 等宿主自有服务不会被同步器删除。GitHub 语义操作优先使用宿主 GitHub app/`gh`，本地文件读写使用 Codex 原生工具，因此不再托管重复的 `github` 与 `filesystem` MCP。
- `postgres` MCP 预检要求 `POSTGRES_CONNECTION_STRING` 为 `postgresql://...`；若检测到 Npgsql/ADO 风格 key-value 连接串，会自动转换并写回 User scope。
- 本机 weekly task `skills-manager-weekly-update-friday-2000` 的顺序是 `更新 -> 同步MCP`，所以 MCP 启动环境修复必须落在真源链上，不能只改 live `~/.codex/config.toml`。

### Codex 技能去重投影

`skills.json.skill_projection` 管理用户技能根、受管逐技能 Junction 与 Codex 路径级开关。`构建生效` 先把 `managed_source_path` 下的技能逐目录投影到标准 `user_skill_root`，保留 `.system`，再扫描配置中的 sources，以声明的技能名称分组，并按以下顺序选主：

1. `.system` 技能；
2. source `priority`；
3. source 声明顺序与规范化路径。

非主副本不会被删除或移动，而是写入 `~/.codex/config.toml` 的受管块，以 `[[skills.config]]` + `enabled = false` 精确停用。完整的来源、内容哈希、包哈希、选主结果和冲突记录写入 `reports/skill-projection/current.json`。配置发生变化时，原文件先备份到 `~/.codex/config-backups/config.toml.skills-projection.<timestamp>.bak`。

`skill_projection.managed_link_excludes` 按受管目录名排除 Codex 的逐技能 Junction；被排除项仍保留在 `agent/`，也不影响 Claude 指向 `agent/` 的根 Junction。该字段适用于保留其他宿主所需技能、但避免其与 Codex `.system` 技能同名冲突的场景。

`skill_projection.aliases` 记录旧名称到替代项的迁移，不把近似能力重新复制成默认技能；`profiles` 控制当前用途下启用的 canonical 技能，`.system` 技能始终保留。顶层 `budget_limit_chars` 对“启用技能名称与描述 + 插件预留”设置 8000 字符 hard ceiling；profile 可用更低的同名字段收紧自身上限，当前 `default` 为 8000、`coding` 为 7500。`external_metadata_reserve_chars` 至少为 system/plugin Skill 预留 3500 字符，实时外部元数据更大时以实时值为准。任一 profile 超限都会阻断投影。

投影 manifest 为当前 profile 排除项保留 `decision = profile_excluded`，并通过 `profile_reachability` 与 `available_profiles` 区分“可从其他 profile 使用”和“未被任何 profile 路由”。`python`、`mcp`、`review`、`marketing` 与 `video` 用于承接高价值低频技能，避免把整个安装库存塞入 `default`。常用命令：

GPT-5.6 日常路径优先使用 Codex 原生 Plan、Goal、Review、skill 语义匹配和 agent 控制。`default` 保留故障诊断、完成验证，以及 `grill-with-docs` 所需的聚焦设计访谈依赖闭包；`coding` 增加增量实现、评审、API 与安全能力；`engineering` 面向产品澄清、spec、计划、领域/模块设计和官方研究。`coding-strict` 才额外提供 TDD 与强约束工作流。profile 是任务边界的预热候选包，当前任务不会热加载 profile 变更，vendor 与技能文件也不会因日常精简而删除。

PPT 路由保持职责单一：`custom-teacher-courseware-ppt` 决定课堂课件结构，Presentations 创建或编辑 PPTX，`powerpoint-automation` 只操作 live PowerPoint/COM，`custom-powerpoint-accessibility` 在内容稳定后验证标题、替代文本、阅读顺序、表格、链接、字幕、对比度与动画。可访问性验证不能由截图单独判定；无法检查阅读顺序或辅助技术行为时必须标记为 `not_verified`。

```powershell
.\skills.ps1 技能配置 列表
.\skills.ps1 技能配置 调和
.\skills.ps1 技能配置 调和 .\proposal.json
.\skills.ps1 技能配置 使用 coding
.\skills.ps1 技能配置 使用 coding-strict
.\skills.ps1 技能配置 使用 python
```

`调和/reconcile` 是 profile 维护的只读 advisor。无 proposal 时报告 `unrouted`、失效引用、全部 metadata 预算和跨多个 profile 的重叠观察，同时输出 `host_handoff`；传入 proposal 时只接受 `schema_version=1`、`decision_owner=host_ai` 和当前 `skills.json` 的 `base_config_sha256`，再校验 skill/profile、protected skill、add/remove、no-op、理由、预算与 routing policy。advisor 本身始终 `apply_allowed=false`、`writes_performed=false`。

技能投影会比较 canonical skill 的 name/path/description；真实增删或 metadata 变化时，在 ignored `reports/skill-profile-reconciliation/pending.json` 写入 `reconciliation_needed`，并提示当前宿主运行上述只读 advisor。profile-only/no-op 不产生新信号，signal 不会自行修改 profile。host evaluation 报告会分开 cumulative cached/uncached input 与 tool rounds；日常只跑 1–2 个 focused cold case，全量 8-case corpus 仅用于结构变化或 closeout。cold discovery 对未知 domain fail-closed、显式报告候选截断，并让 current host snapshot 覆盖静态 skill/MCP availability；disabled、needs-auth 或 not-callable 能力不会自动 load/use。

宿主已生成最小 proposal 后，可用独立事务 manager 做 apply preview，或在常驻授权下对非活动 profile 运行 canary：

```powershell
.scripts\manage-skill-profile-reconciliation.ps1 -Mode Plan -ProposalPath .\proposal.json -Json
.scripts\manage-skill-profile-reconciliation.ps1 -Mode Apply -ProposalPath .\proposal.json -Token APPLY_PROFILE_RECONCILIATION_CANARY -Json
.scripts\manage-skill-profile-reconciliation.ps1 -Mode Accept -ReceiptPath <receipt> -ReplayReportPath <report> -CorpusPath <corpus> -Token ACCEPT_PROFILE_RECONCILIATION_CANARY -RollbackOnFailure -Json
```

canary 最多修改 5 个 skill/10 个 membership action，默认至少保留 256 字符 metadata headroom，并禁止触碰当前 active profile；配置写入有原子 backup/receipt。接受必须来自 fresh ephemeral host replay，覆盖 changed skill 的正负 prompt 并证明 profile 已恢复；失败时按 hash 自动回滚。日常只重放 changed profile/skill 的 4–6 个场景，全量 corpus 只用于结构变化或 closeout。脚本不调用第二个模型、不安装/删除 skill，也不提供当前任务 profile 热切换。运行态 receipt/backup 位于忽略的 `reports/skill-profile-reconciliation/`。

所有 profile 只共享轻量常驻 `capability-router`。`capability-router` 现为兼容名称：宿主 AI 先根据完整请求、对话和可见 skill description 原生选择；只有没有可见匹配、用户询问可用能力或需要跨 profile 冷发现时，才先读取 domain `name + purpose`，选择最多两个 domain 后再取得候选。脚本不再用正则/词频理解任务，也不再给出语义置信度；宿主选定最多 3 个候选后，脚本只验证路径、freshness、availability、side effect 与 activation。profile 是 domain/index partition 和任务边界预热包，不会在当前 turn 静默切换。旧 `watch-interrupted-task` 已从 resident set 移除，仅保留 fail-closed 清理 stub，禁止创建、恢复或武装 heartbeat；替代架构规划位于 `D:\CODE\codex-watch-runtime`。

P4/P5 的 lexical selector、task model 和 ranking 是历史 repo_verified 实现；真实中文场景回放证明它们不能代表路由实效，已在 maintenance correction 中退役为 `decision_owner=host_ai`、`semantic_routing_performed=false` 的 discovery/policy contract。`scripts/verify-capability-routing.ps1` 使用 direct、indirect、negative、多阶段、架构、调试、评审、跨领域和 side-effect 自然语言 corpus，分别验证候选可达性、宿主标注选择后的 policy 与零自动语义选择；它仍不把 repo corpus 外推为 live acceptance。

`scripts/get-codex-app-server-capability-snapshot.ps1` 只调用稳定只读 App Server RPC；陈旧、不可访问、不可调用和认证缺失事实 fail-closed，单来源故障报告 `partial`。session/profile 输出只是 `apply=false` 的计划或预热建议，不会静默切换宿主状态。

技能初始列表预算的全局硬上限为 `8000` 字符。`resident_names ∪ active_profile.enabled_names` 必须整体通过预算门禁；低频研究、发布、专用执行器优先冷加载，不在多个 profile 中重复常驻。

用无模型模式校验 GPT-5.6 profile A/B 语料，或显式执行 12 场景 × 2 profile 的只读 benchmark：

```powershell
.\scripts\benchmark-codex-skill-profiles.ps1
.\scripts\benchmark-codex-skill-profiles.ps1 -Execute
```

benchmark 使用 ephemeral、read-only Codex 任务，记录 skill 选择、计划/代理/worktree 倾向、耗时和 token，并核对 `original_profile`/`restored_profile`；产物写入忽略的 `artifacts/skill-profile-benchmark/`。它是 `host_evaluation_partial`，用于 canary 代表 prompt 验证和路由开销观察，不替代真实 skill-body trace、代码质量或 live acceptance。

设计访谈统一使用 `grill-with-docs`：在 CLI/IDE 中可显式输入 `$grill-with-docs`，在 Work/Codex 桌面端可从技能选择器指定，也可由模型仅在“grill/设计质询/把方案磨清楚”等明确语义下隐式调用。它不会因为普通实现或重构请求自动启动；完成访谈后只有用户确认的持久决策才写入 `CONTEXT.md`、词汇表或 ADR。`grilling` 与 `domain-modeling` 作为 `default` 的完整依赖闭包保留，防止主技能可见但运行依赖缺失；只有在直接进行决策树访谈或领域建模时才单独调用。

工程 profile 常驻 `draft-spec`，并用 `planning-and-task-breakdown` 承担可审阅的任务拆分；`draft-tickets` 仍保留为显式冷调用能力，避免与通用计划能力重复占用 metadata 预算。这些 draft/planning 能力不调用 tracker，也不建立外部阻塞关系。`to-spec`、`to-tickets`、`setup-matt-pocock-skills` 和 `improve-codebase-architecture` 继续保持显式调用，因为它们会发布、修改仓库配置或执行高成本架构扫描。

`-DryRun` 只生成内存计划，不写配置或 manifest。Codex 在新任务加载初始技能列表；当前已运行任务不会热更新该列表。常驻 router 可以在当前任务读取磁盘上的冷技能，实现能力层无缝切换，但不能把 profile 变更伪装成热加载。投影后仍应以 fresh process/task 复核初始列表，不应通过删除 `.agents/skills` 强制生效。

`$HOME/.agents/skills` 是当前标准用户技能根，根目录及其 `.system` 子目录不能整体删除。受管技能以 Junction 形式存在于该根，`$HOME/.codex/skills` 不再是受管 target；Codex 仍可能自动创建其中的 `.system` 兼容目录。历史普通目录应先退役到带哈希清单的归档，脚本会保留受管 Junction：

```powershell
# 默认仅预演并生成 reports/skill-retirement/<run-id>/manifest.json
pwsh -NoProfile -File .\scripts\retire-agents-user-skills.ps1

# 核对目录数、文件数、字节数后再迁移；始终保留 .system
pwsh -NoProfile -File .\scripts\retire-agents-user-skills.ps1 -Apply
```

退役归档不是立即删除项。至少用新任务验收普通编码、PPT/文档、Claude Junction 和 `.NET` + `microsoft-code-reference` 四条路径，并确认没有配置引用归档后，才可在保留一个回滚窗口后物理删除对应的 `~/.agents/retired/skills-user-<run-id>`。回滚时按 manifest 逐项把 `archive_path` 移回 `source_path`，发现同名目标时必须停止。

### 目标仓审查

```powershell
.\skills.ps1 审查目标 初始化
.\skills.ps1 审查目标 需求设置
.\skills.ps1 审查目标 需求查看
.\skills.ps1 审查目标 需求结构化 --profile reports\profile.json
.\skills.ps1 审查目标 添加 my-repo ..\my-repo
.\skills.ps1 审查目标 修改 my-repo ..\my-repo
.\skills.ps1 审查目标 删除 my-repo
.\skills.ps1 审查目标 列表
.\skills.ps1 审查目标 目标列表
.\skills.ps1 审查目标 扫描 --target my-repo
.\skills.ps1 审查目标 发现新技能 --query "repo governance and agent workflows"
.\skills.ps1 审查目标 预检 --run-id <run-id>
.\skills.ps1 审查目标 应用确认 --recommendations reports\skill-audit\<run-id>\recommendations.json
.\skills.ps1 审查目标 应用 --recommendations reports\skill-audit\<run-id>\recommendations.json
.\skills.ps1 审查目标 应用 --recommendations reports\skill-audit\<run-id>\recommendations.json --apply --yes --add-indexes "1,3" --remove-indexes "2" --mcp-add-indexes "1" --mcp-remove-indexes "2"
.\skills.ps1 审查目标 状态
```

关键规则：

- `发现新技能` 是 profile-only 模式：生成同样的审查包，但不生成 `repo-scan.json`。
- 正式审查必须同时依赖两层上下文：全局用户画像 + 目标仓事实。
- `应用` 默认只做 dry-run；只有同时传 `--apply --yes` 才真正落盘。
- `应用确认` 是单入口两阶段流程：先 dry-run，再要求确认口令 `APPLY <run-id>`。
- dry-run 模式下必须显式确认 `我知道未落盘`；非交互场景可传 `--dry-run-ack "我知道未落盘"`。
- `应用` / `应用确认` 会校验同目录 `installed-skills.json` 与当前 live state 是否 stale；仅在明确接受风险时，才用 `--allow-stale-snapshot` 和 `--stale-ack "<token>"` 跳过阻断。
- `--out` 指向已存在且非空目录时默认阻断；确需复用时显式传 `--force`。

如果外层 AI 具备工作区执行能力，优先把本次 run 目录的 `outer-ai-prompt.md` 交给它，而不是只给 `ai-brief.md`。

## English aliases

当前英文别名主要覆盖适合脚本化的命令面：

| 中文入口 | 英文别名 |
| --- | --- |
| `帮助` | `help`, `--help`, `-h` |
| `doctor` | `doctor` |
| `审查目标` | `audit-targets` |
| `一键` | `workflow` |
| `安装MCP` | `mcp-install` |
| `卸载MCP` | `mcp-uninstall` |
| `同步MCP` | `mcp-sync` |
| `MCP配置` | `mcp-profile` |
| `技能配置` | `skill-profile` |
| `清理无效映射` | `prune-invalid-mappings` |
| `add` | `add` |
| `npx` | `npx` |

以下高频中文命令目前仍无英文别名：`发现`、`安装`、`构建生效`、`更新`、`锁定`、`新增技能库`、`删除技能库`、`自动更新设置`、`解除关联`、`清理备份`。

## 同步模式

`skills.json` 通过 `sync_mode` 控制 skills 目录同步方式：

- `link`：Windows 默认推荐；使用 junction 指向 `agent/`
- `sync`：使用 `robocopy /MIR` 镜像 `agent/`

本地迭代优先 `link`。受限环境无法创建链接时再切换到 `sync`。如需把 MCP 同步目标和 skills 同步目标拆开，可在 `skills.json` 里补 `mcp_targets`。

## 发布与新机迁移

推荐发布可重建的 portable 包，而不是直接复制整个工作目录：

```powershell
.\scripts\release\pack-portable.ps1 -Version vX.Y.Z
```

常用附加参数：

```powershell
.\scripts\release\pack-portable.ps1 -Version vX.Y.Z -AllowDirtyWorktree
.\scripts\release\pack-portable.ps1 -Version vX.Y.Z -SkipVerification
```

portable 包包含可迁移源码与配置，例如 `skills.ps1`、`skills.cmd`、`install.ps1`、`skills.json`、`skills.lock.json`、`src/`、`scripts/`、`tests/`、`overrides/` 和治理文档；不会包含 `agent/`、`vendor/`、`imports/`、`reports/`、`.codex/`、`.claude/`、`.gemini/`、`.trae/`、日志、缓存、发布输出和审查运行态证据。

新电脑解压后：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Mode CurrentUser
```

默认行为：

1. 运行 `build.ps1`
2. 若存在 `skills.lock.json` 且未传 `-SkipRebuildLocked`，执行 `.\skills.ps1 更新 -Locked`
3. 否则执行 `.\skills.ps1 构建生效`
4. 若传 `-SyncMcp`，执行 `.\skills.ps1 同步MCP`
5. 最后执行 `.\skills.ps1 doctor --strict --threshold-ms 8000`

常用模式：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Mode CurrentUser -SyncMcp
pwsh -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Mode PortableOnly
pwsh -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Mode CurrentUser -DoctorThresholdMs 12000
```

说明：

- `PortableOnly` 只做 `build + doctor`，不会写用户 skills 目录，也会忽略 `-SyncMcp`。
- 安装器和 `skills.cmd` 只解析 `pwsh`；Windows PowerShell 5.1 不受支持，也没有隐藏 fallback。
- `-SkipEnvironmentCheck` 适合受控测试夹具，不建议日常安装使用。
- 若要在新电脑上同步 MCP，先准备本机 token、数据库连接串等宿主环境，再执行 `-SyncMcp`。

## 本地门禁

项目级硬门禁顺序固定为：

```powershell
./build.ps1
./skills.ps1 发现
./skills.ps1 doctor --strict --threshold-ms 8000
./skills.ps1 构建生效
```

仓库还提供本地 / CI 同款质量门禁脚本：

```powershell
./scripts/quality/run-local-quality-gates.ps1 -Profile quick
./scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree
```

含义：

- `quick`：`build -> repo-hygiene -> generated-sync -> skill-integrity -> skill-routing -> dependency-baseline -> skills-config-contract -> planning-contract -> doctor-json-contract`
- `full`：`quick + tests`

规划合同也可单独执行：

```powershell
./scripts/verify-vnext-planning.ps1
./scripts/verify-vnext-planning.ps1 -Json
```

该 verifier 从 `tasks/plan.md` 的 `current_phase` 选择当前 spec/manifest，也可用 `-SpecPath`/`-ManifestPath` 验证历史 Phase。它只证明规划文件的机器一致性，不证明产品代码、宿主加载或 live acceptance。

## MCP 与门禁环境变量

- `POSTGRES_CONNECTION_STRING`：postgres MCP 的连接串；推荐 `postgresql://...`
- `SKILLS_MCP_VERIFY_GEMINI_CLI=1|true|yes|on`：启用 Gemini CLI 实机校验（默认关闭）
- `SKILLS_MCP_VERIFY_LIST_TIMEOUT_SECONDS`：统一设置 `mcp list` 校验超时（秒）
- `SKILLS_MCP_VERIFY_LIST_TIMEOUT_SECONDS_<CLI>`：按 CLI 覆盖超时（例如 `_CLAUDE` / `_CODEX` / `_GEMINI`）
- `SKILLS_MCP_NATIVE_TIMEOUT_SECONDS`：原生 `claude mcp add/remove` 超时（秒）
- `SKILLS_MCP_VERIFY_ATTEMPTS`、`SKILLS_MCP_VERIFY_INTERVAL_SECONDS`：跨 CLI MCP 校验重试次数与重试间隔（秒）
- `SKILLS_SYNC_MCP_THRESHOLD_MS`：`check-doctor-json.ps1` 中 `sync_mcp` 性能阈值（毫秒）；clean CI 没有历史样本，因此用 `-WarnOnly` 记录 observation，只有具备真实样本的专用性能门禁才能作阻断
- 测试套件使用 Pester `4.10.1` 语法；CI 精确安装该版本，`tests/run.ps1` 会在版本缺失时 fail-closed

## 仓库卫生

不要提交本地 agent 状态、日志、缓存或临时产物，包括：

- `.claude/`、`.codex/`、`.gemini/`、`.trae/`、`.txn/`
- `agent/`、`artifacts/`、`reports/*.log`
- `imports/_debug_*`、`imports/_probe_*`、`imports/_tree_*`、`imports/*.zip`
- 审查运行态证据位于已忽略的 `reports/skill-audit/<run-id>/runtime-evidence-*.md`；115 份旧 runtime receipts 已原样移入 [`docs/archive/change-evidence/`](docs/archive/change-evidence/README.md)，不得重新放入活跃 `docs/change-evidence/`
- 备份与临时文件，例如 `build.log*`、`acl-backup-git-*.txt`、`.tmp_*`

边界说明：

- 仓库根的 `AGENTS.md`、`CLAUDE.md`、`GEMINI.md` 是受版本管理的项目规则文档，不属于“本地垃圾文件”。
- 不要把宿主目录中的本地规则副本、导入快照里的临时规则文件，或下游工具自动生成的 host-local 配置混进提交。

## 相关文档

- [Product direction and planning contract](docs/product/README.md)
- [Contributing](CONTRIBUTING.md)
- [Security Policy](SECURITY.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [overrides README](overrides/README.md)

## License

MIT
