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
- [当前 Phase 3 任务 manifest](tasks/skills-manager-vnext-phase3.tasks.json)
- [Phase 2 历史任务 manifest](tasks/skills-manager-vnext-phase2.tasks.json)
- [Phase 1 历史任务 manifest](tasks/skills-manager-vnext-phase1.tasks.json)
- [Phase 0 历史任务 manifest](tasks/skills-manager-vnext-phase0.tasks.json)

vNext Phase 0、Phase 1、Phase 2 与 Phase 3 均已完成 repo-side 验收（P0/P1 各 9/9，P2/P3 各 7/7）。P3 提供只读 inventory adapter、personal manifest lint、一个 fixture-only Codex skills-only exporter 和分层 evaluation。P4 entry decision 为 `not_started/deferred`，未创建 P4 manifest。plugin install、marketplace mutation、host/profile 修改、provider call 与 native mutation 仍禁止；Codex fresh-process 规则加载已在 9 个目标仓验证，Claude 无 provider-free prompt renderer，`live_accepted` 仍为 `not_run`。

运行时以 PowerShell 7 (`pwsh`) 为开发、CI 和完整门禁主路径；Windows PowerShell 5.1 仅保留安装 fallback、generated script parse 和 plain-object/selected fixture smoke。完整边界与移除条件见 [`docs/runbooks/powershell-runtime-compatibility.md`](docs/runbooks/powershell-runtime-compatibility.md)。

Phase 1 的只读入口（未指定 `--out` 时不写文件）：

```powershell
.\skills.ps1 capability-inventory --json
.\skills.ps1 rule-audit --repo . --host codex --json
.\skills.ps1 rule-estate-audit --workspace-root D:\CODE --registry .\audit-targets.json --json
```

`rule-estate-audit` 默认排除 `external` 与 `文档`，自动发现工作区直属 Git 仓，报告目标清单漂移、Codex/Claude common/delta 对齐、规则版本和 `Global Rule -> Repo Action` 覆盖。`--out <report.json>` 只允许显式写一个报告文件，且不允许覆盖发现到的规则文件。

P2 事务入口支持 fixture 与单仓两种显式授权域：

```powershell
.\skills.ps1 rule-plan --target <fixture-rule> --desired-file <reviewed-file> --fixture-root <fixture-root> --json --out <fixture-plan.json>
.\skills.ps1 rule-apply --plan <fixture-plan.json> --fixture-root <fixture-root> --token APPLY_RULE_PATCH --json
.\skills.ps1 rule-plan --target <repo-rule> --desired-file <reviewed-file> --repo-root <git-root> [--allow-create] --json --out <repo-plan.json>
.\skills.ps1 rule-apply --plan <repo-plan.json> --repo-root <git-root> --token APPLY_RULE_REPO_PATCH --json
```

仓库模式只允许精确 Git 根内的 `AGENTS.md`、`AGENTS.override.md` 或 `CLAUDE.md`，并执行 hash freshness、reparse、原子写入和回滚守卫；它不授权全局用户目录、host 配置或无审阅的跨仓批量覆盖。

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
| `overrides/` | 本地自定义和补丁层 | 放自定义 skill、本地 patch、同名替换 |
| `agent/` | 生成产物与同步源 | 不手改；通过 `构建生效` 重建 |
| `reports/skill-audit/<run-id>/ai-brief.md` | 审查运行包摘要 | 运行态产物，不手改 |
| `reports/skill-audit/<run-id>/outer-ai-prompt.md` | 外层 AI 执行提示词 | 运行态产物；改默认提示词请改 `src/Commands/AuditTargets.ps1` 或 `overrides/audit-outer-ai-prompt.md` |

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

`skill_projection.aliases` 记录旧名称到替代项的迁移，不把近似能力重新复制成默认技能；`profiles` 控制当前用途下启用的 canonical 技能，`.system` 技能始终保留。顶层 `budget_limit_chars` 对“启用技能名称与描述 + 插件预留”设置 10000 字符 hard ceiling；profile 可用更低的同名字段收紧自身上限，当前 `default` 与 `coding` 均为 7500。`external_metadata_reserve_chars` 至少为 system/plugin Skill 预留 3500 字符，实时外部元数据更大时以实时值为准。任一 profile 超限都会阻断投影。

投影 manifest 为当前 profile 排除项保留 `decision = profile_excluded`，并通过 `profile_reachability` 与 `available_profiles` 区分“可从其他 profile 使用”和“未被任何 profile 路由”。`python`、`mcp`、`review`、`marketing` 与 `video` 用于承接高价值低频技能，避免把整个安装库存塞入 `default`。常用命令：

GPT-5.6 日常路径优先使用 Codex 原生 Plan、Goal、Review 和 agent 控制。`default` 只保留领域入口、故障诊断与完成验证，`coding` 只保留按问题触发的调试、验证、评审、API 与安全能力；两者都不常驻 `using-superpowers`、通用 research、强制 brainstorming、细粒度计划、TDD、worktree 或 subagent 编排。`coding-strict` 是高证据编码档：额外提供 TDD、领域建模和可按设计质询语义隐式触发的 `grill-with-docs`，但同样不加载总入口、强制计划、自动代理或强制 worktree。当前任务不会热加载新 profile，vendor 与技能文件也不会因日常精简而删除。

PPT 路由保持职责单一：`custom-teacher-courseware-ppt` 决定课堂课件结构，Presentations 创建或编辑 PPTX，`powerpoint-automation` 只操作 live PowerPoint/COM，`custom-powerpoint-accessibility` 在内容稳定后验证标题、替代文本、阅读顺序、表格、链接、字幕、对比度与动画。可访问性验证不能由截图单独判定；无法检查阅读顺序或辅助技术行为时必须标记为 `not_verified`。

```powershell
.\skills.ps1 技能配置 列表
.\skills.ps1 技能配置 使用 coding
.\skills.ps1 技能配置 使用 coding-strict
.\skills.ps1 技能配置 使用 python
```

用无模型模式校验 GPT-5.6 profile A/B 语料，或显式执行 12 场景 × 2 profile 的只读 benchmark：

```powershell
.\scripts\benchmark-codex-skill-profiles.ps1
.\scripts\benchmark-codex-skill-profiles.ps1 -Execute
```

benchmark 使用 ephemeral、read-only Codex 任务，记录 skill 选择、计划/代理/worktree 倾向、耗时和 token；产物写入忽略的 `artifacts/skill-profile-benchmark/`。它验证路由开销，不替代真实代码修改、测试质量和回归率评测。

设计访谈统一使用 `grill-with-docs`：在 CLI/IDE 中可显式输入 `$grill-with-docs`，在 Work/Codex 桌面端可从技能选择器指定，也可由模型仅在“grill/设计质询/把方案磨清楚”等明确语义下隐式调用。它不会因为普通实现或重构请求自动启动；完成访谈后只有用户确认的持久决策才写入 `CONTEXT.md`、词汇表或 ADR。`grilling` 与 `domain-modeling` 作为依赖闭包保留，只有在直接进行决策树访谈或领域建模时才单独调用。

工程 profile 另外提供 `draft-spec` 与 `draft-tickets`：两者可隐式触发，但只在回复中生成待审阅 Markdown，不写仓库文件、不调用 tracker，也不建立外部阻塞关系。`to-spec`、`to-tickets`、`setup-matt-pocock-skills` 和 `improve-codebase-architecture` 继续保持显式调用，因为它们会发布、修改仓库配置或执行高成本架构扫描。

`-DryRun` 只生成内存计划，不写配置或 manifest。Codex 在新任务加载技能配置；当前已运行任务不会热更新，因此投影后需用新任务复核可见技能列表，不应通过删除 `.agents/skills` 强制生效。

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
.\install.ps1 -Mode CurrentUser
```

默认行为：

1. 运行 `build.ps1`
2. 若存在 `skills.lock.json` 且未传 `-SkipRebuildLocked`，执行 `.\skills.ps1 更新 -Locked`
3. 否则执行 `.\skills.ps1 构建生效`
4. 若传 `-SyncMcp`，执行 `.\skills.ps1 同步MCP`
5. 最后执行 `.\skills.ps1 doctor --strict --threshold-ms 8000`

常用模式：

```powershell
.\install.ps1 -Mode CurrentUser -SyncMcp
.\install.ps1 -Mode PortableOnly
.\install.ps1 -Mode CurrentUser -DoctorThresholdMs 12000
```

说明：

- `PortableOnly` 只做 `build + doctor`，不会写用户 skills 目录，也会忽略 `-SyncMcp`。
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
- 审查运行态证据，例如 `docs/change-evidence/*-audit-runtime-*.md`
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
