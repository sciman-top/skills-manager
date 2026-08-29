# skills-manager

Windows-first、local-first 的 PowerShell 7 技能与 MCP 管理器。它把分散在多个仓库的 AI 技能收敛到一份版本化配置，锁定来源、生成可移植技能目录，并安全投影给 Codex、Claude、ZCode 等宿主。

适合希望在多台 Windows 电脑上复用同一套技能、审计目标仓规则、统一管理 MCP 清单，同时又不愿把模型、账号和运行时交给另一层框架的个人或团队。

本项目不做第二套 AI runtime：不选择模型，不管理 provider/auth/session，不接管 Codex、Claude、ZCode 的语义路由，也不直接维护插件缓存。仓库测试只证明 `repo_verified`；宿主新会话加载和真实业务验收必须分别验证。

本项目采用 [MIT License](LICENSE)。第三方技能与依赖仍各自遵循其原始许可证。

## 快速开始

要求 PowerShell 7 (`pwsh`) 和 Git。Windows PowerShell 5.1 不受支持。

### 推荐：Release 一键安装

当前稳定版为 [v2026.08.27.1](https://github.com/sciman-top/skills-manager/releases/tag/v2026.08.27.1)。从 [GitHub Releases](https://github.com/sciman-top/skills-manager/releases) 下载对应版本的 `bootstrap.zip`，先核对 `SHA256SUMS.txt`，再解压运行：

```powershell
.\setup.cmd
```

需要离线或 U 盘绿色运行时下载 `portable.zip`，解压后运行 `skills.cmd`；它不会自动写宿主目录。两种包的选择、SHA-256 校验和迁移步骤见 [安装、绿色运行与迁移](docs/INSTALLATION_AND_MIGRATION.md)。

`artifacts/` 只是本机 ignored 输出目录，不是公共下载目录；正式公共制品、校验清单和 attestation 以 GitHub Release 为准。目录按 `deliveries/history/work` 分层，规则见 [`artifacts/README.md`](artifacts/README.md)。

### 从源码使用

```powershell
pwsh -NoProfile -File .\skills.ps1 help
pwsh -NoProfile -File .\skills.ps1 发现
pwsh -NoProfile -File .\skills.ps1 安装
pwsh -NoProfile -File .\skills.ps1 doctor --strict
```

也可直接运行 `skills.cmd` 打开交互菜单。新手通常只需“浏览技能 → 选择安装 → 重建并同步 → doctor”。

交互菜单按“高频动作直达 + 领域子菜单”组织：

- 浏览技能
- 选择安装
- 粘贴命令导入
- 重建并同步（CLI 命令仍为 `构建生效`）
- 更新上游（CLI 命令仍为 `更新`）
- 目标仓审查
- MCP 服务
- 技能库管理
- 更多

## 配置真源

`skills.json` 管理：

- `vendors` / `imports`：技能来源
- `mappings`：安装白名单与输出名
- `targets`：生成技能的目标目录；`managed_link_only` target 按其 `host` 解析的 Skills profile 建立逐技能链接（旧配置可由路径推导宿主）
- `mcp_servers` / `mcp_profiles` / `mcp_targets`：MCP 清单与同步目标

### 同一版本下的四类交付物

| 形态 | 获取方式 | 内容与边界 |
| --- | --- | --- |
| 标准安装版 | `<version>/standard-install/bootstrap.zip` | 公共工具与源码；不带 skills/MCP，首次扫描新电脑的目标仓后再选择安装。 |
| 完整绿色版 | `<version>/portable/portable.zip` | 公共工具与源码；不带 skills/MCP，不自动写宿主目录。 |
| 公共源码开发版 | `<version>/source/source.zip` 或 Git clone/fork/tag | 无 skills/MCP；ZIP 含开发文件，完整 Git 历史仍以 clone/fork/tag 为准。 |
| 私用全量快照 | `<version>/private-snapshot/private-all.zip` | 唯一携带全部现有 skills/MCP 的明文、无口令恢复包；不含 Git 历史，不得公开分发。 |

同一版本的四类交付物统一位于 `artifacts/deliveries/<version>/`。三个公共包都不携带 `agent/`、MCP 清单、目标仓状态、`vendor/` 或 `imports/`；`rules/global/` 只随源码开发版和私用快照作为规则源携带，绝不自动覆盖宿主已生效的全局规则。`rescan` 只是辅助扫描清单，不是第五种交付物。

### 项目迁移

可用 `迁移` 命令生成私用全量快照。默认交付路径必须提供版本号，因此它与三个公共包同处一个版本根目录。

```powershell
# 唯一的私用状态交付物：全部当前 skills + MCP，明文、无口令
.\skills.ps1 迁移 --mode private-all --version <version>
# 可选辅助清单，不是第五种交付物
.\skills.ps1 迁移 --mode rescan --version <version>
```

迁移包默认不会包含宿主登录态、插件缓存、`reports/` 或目录链接；当前生成器只生成携带完整 skills/MCP 状态的 `private-all` 明文快照，凭据写入 `MIGRATION-MCP-CREDENTIALS.json`，不询问口令。`all`、`general`、`private-general` 和 `--encrypt` 不再是生成选项；为兼容历史包，`migration-unlock` 仍可读取 manifest 指向的旧 `MIGRATION-MCP-CREDENTIALS.enc.json`。所有非 `rescan` 模式都会携带恢复所需的 `src/`、`config/`、`tests/`、`scripts/`、`docs/`、`overrides/`、`references/`、`.github/`、源物化目录和 `LICENSE`，并带 `MIGRATION-CONTENT.json` 逐文件 SHA-256 校验；它们不包含 `.git` 历史，不能替代公共 Git 开发版。`private-all` 解压后可运行 `migration-apply`，必要时再运行 `构建生效`/`同步MCP`。`rescan` 包只含清单：新电脑须先安装同版本的 skills-manager，再运行 `发现`、`安装` 和 `同步MCP`，因此不会声称已完成 `host_loaded` 或 `live_accepted`。

`private-all` 是允许携带 MCP `env`/`headers` 值的私用模式。当前生成的快照为明文，不需要口令；它只应通过你控制的本地或私有介质传输，绝不要上传公共 GitHub、公共 Release 或公共网盘。历史加密快照在 `migration-unlock` 时才会询问口令，口令不进入命令行、日志或 manifest。新电脑解压后可直接运行：

```powershell
.\skills.ps1 migration-apply
# 只恢复包内配置和 skills，暂不同步宿主 MCP：
.\skills.ps1 migration-apply --skip-mcp
```

等价手动流程是先运行 `migration-unlock`，再运行 `setup.cmd -SkipRebuildLocked -SyncMcp`；当前明文包的 `migration-unlock` 不会询问口令，历史加密包才会询问。`private-all` 使用相同的 `migration-apply`/`migration-unlock` 流程，携带全部技能和 MCP。迁移完成后建议轮换长期或高权限 token。
- `skill_projection`：技能来源、domain catalog、native placement 与按宿主的 projection profiles；metadata budget 与 description 截断由宿主原生处理

`skills.lock.json` 锁定已解析来源。`src/` 是 CLI 源码，`build.ps1` 生成根 `skills.ps1`；`overrides/{custom,patches,resources}` 生成 `agent/`。`vendor/` 与 `imports/` 都是可由配置和锁文件重建的本地物化目录；不要手改 `skills.ps1`、`agent/`、`vendor/`、`imports/` 或运行态 `reports/`。

## 常用命令

### 技能

```powershell
.\skills.ps1 发现
.\skills.ps1 安装
.\skills.ps1 卸载 <name> --yes
.\skills.ps1 add <repo> --skill <path>
.\skills.ps1 锁定
.\skills.ps1 verify-lock
.\skills.ps1 check-updates --json
.\skills.ps1 更新 -Plan
.\skills.ps1 更新 -Upgrade
.\skills.ps1 构建生效
.\skills.ps1 构建生效 -SkillProfile full-compatible
```

`check-updates --json` 只报告每个来源的 `current/target/changed/source`，不 apply、不构建、不投影、不同步 MCP。`构建生效` 会重建并写入宿主目标，属于外部投影动作。仅需仓库内同步时运行 `build.ps1`；不要用 `构建生效` 代替普通构建验证。仓库保留 `scripts/weekly-skills-update.ps1` 作为可由宿主/operator 调度的 skills-only runner，但不提供创建、更新或删除 Windows 计划任务的入口；现有同名任务属于宿主状态，`doctor` 只读报告，清理由用户在宿主侧决定。
公开分发通过 GitHub Releases 的 `bootstrap.zip`/`portable.zip` 完成下载和安装。公共源码开发版应从 GitHub clone、fork 或 tag 获取，保留 Git 历史；Release ZIP 是安装制品，不替代源码仓。发布包包含运行所需源码、脚本、文档与 MIT `LICENSE`，第三方 `vendor/`/`imports/` 仍按各自许可证。

`check-updates` 继续只检查上游技能；以下命令检查并更新 skills-manager 本体 Release。它只接受未被本地修改的 GitHub Release 安装目录，先核对 GitHub 发布的 SHA-256，再把目录替换交给独立进程，保留同级旧目录备份。源码开发版必须通过 Git 更新，不能使用此命令覆盖。

```powershell
.\skills.ps1 release-update --check --json
.\skills.ps1 release-update --apply --yes
# 自动更新成功后才同步 MCP；默认不会同步 MCP
.\skills.ps1 release-update --apply --yes --sync-mcp

# 每天 09:00 检查并弹出更新提示
.\skills.ps1 release-update-schedule --enable --time=09:00
# 每天 09:00 检查、通知并自动启动已校验更新
.\skills.ps1 release-update-schedule --enable --time=09:00 --auto-apply
.\skills.ps1 release-update-schedule --disable
```

调度任务仅在用户显式运行 `--enable` 时创建，使用当前交互用户和非提权权限；更新后的 `reports/release-update/last.json` 保存结果。下载、checksum、解压、安装或切换任一步失败都会保持或回滚到旧目录。它仍不迁移登录态、provider/auth/session、插件缓存，也不证明 `host_loaded` 或 `live_accepted`。

### Skills 投影档位

`agent/` 是受管技能的完整构建资产；它不等于每个宿主都应默认常驻的提示词元数据。当前配置以 `skill_projection.projection_profiles` 为唯一策略源（旧 `managed_link_*` 字段仅用于没有 profiles 的历史配置回退）：`构建生效` 未指定参数时，Codex、Claude、ZCode 均使用轻量 `core`；技能集合和数量以 `skills.json` 的 profile 为准（本次 fresh read 为 9 个通用治理技能）。显式传入 `-SkillProfile full-compatible` 才会将所有当前兼容技能投影到对应宿主。profile 解析 fail closed：未知 profile/host、重复或空技能名、profile 内 include/exclude 冲突、以及 `include_all=true` 同时列出 include 都会阻断投影。

| 宿主 | `core` | `full-compatible` 的宿主适配 |
| --- | --- | --- |
| ChatGPT/Codex | 当前 `core` profile 集合（本次 fresh read 为 9 个） | 全量受管技能，排除 Claude 专属评测流程的 `skill-creator` 和 Claude Artifacts 的 `web-artifacts-builder` |
| Claude | 当前 `core` profile 集合（本次 fresh read 为 9 个） | 全量受管技能 |
| ZCode | 当前 `core` profile 集合（本次 fresh read 为 9 个） | 排除 `agent-browser`（外部 CLI stub）、`skill-creator`（Claude 专属评测流程）和 `web-artifacts-builder`（Claude Artifacts） |

`full-compatible` 增加宿主初始元数据与自动触发竞争，尤其 ZCode 仍会把已启用 Skills 的元数据放入固定上下文预算；它是显式的能力面扩展，不是默认优化。投影成功仅证明 `filesystem_projected`。请用新会话或宿主原生 Skills 页面/探针确认 `host_loaded`；单个自然语言任务的命中不证明全部 Skills 的自动路由或业务效果。

### MCP

```powershell
.\skills.ps1 安装MCP <name> -- <command> [args...]
.\skills.ps1 安装MCP <name> --transport http --url <url>
.\skills.ps1 卸载MCP <name>
.\skills.ps1 MCP配置 列表
.\skills.ps1 MCP配置 使用 default
.\skills.ps1 同步MCP
```

本仓只管理 MCP server 清单和目标配置段。模型、provider、auth、context 与 sandbox 不属于 `skills.json`。

### 目标仓审查

```powershell
.\skills.ps1 审查目标 列表
.\skills.ps1 审查目标 添加 <name> <path>
.\skills.ps1 审查目标 扫描 [--query "<user-goal>"]
.\skills.ps1 审查目标 预检 --recommendations <file>
.\skills.ps1 审查目标 应用确认 --recommendations <file>
.\skills.ps1 审查目标 应用 --recommendations <file> --apply --yes
```

扫描产物位于 ignored `reports/skill-audit/<run-id>/`，每个 run 固定只有三个文件：`snapshot.json` 是不可变审查输入，`recommendations.json` 是唯一允许 AI 编辑的决策文件，`receipt.json` 是命令维护的阶段、结果、补偿/回滚与 truth-boundary 记录。扫描固定汇总全部 enabled 目标仓；`--target` 仅为兼容保留，不再缩小范围。`--query` 用于冻结本次任务语境；省略时只生成仓库能力盘点，不得据此声称存在用户需求缺口，也不能据此新增、删除或替换 skill/MCP。`snapshot.json` 还记录 `scan_contract`、全仓汇总画像和 `scan_coverage`，用于披露证据范围与采样上限。`recommendations.json` 必须经过 preflight 和 dry-run；只有显式 `--apply --yes` 才写配置。缺少 snapshot 直接阻断，不生成第四个报告或 evidence 文件。

自 `prompt_contract_version=audit-prompt-v20260829.3`（skills 口径改为 current-profile 有效库存 + configured supply 双轨、MCP 指纹纳入 env/header 值域摘要）起，此前所有 run 的 `snapshot.json` 因指纹口径切换必然 stale，预检会 fail closed 要求重扫——这是预期的口径迁移行为，不是环境故障。

### 规则审查

```powershell
.\skills.ps1 rule-audit --repo <repo-root> --host codex|claude|zcode --json
.\skills.ps1 rule-plan --target <AGENTS.md> --desired-file <reviewed.md> --repo-root <repo> --out <plan.json> --json
.\skills.ps1 rule-apply --plan <plan.json> --repo-root <repo> --token APPLY_RULE_REPO_PATCH --json
.\skills.ps1 rule-estate-audit --workspace-root D:\CODE --json
.\skills.ps1 rule-estate-plan --review <reviewed-change-set.json> --workspace-root D:\CODE --out <plan.json> --json
.\skills.ps1 rule-estate-apply --plan <plan.json> --workspace-root D:\CODE --token <plan.apply.required_token> --json
```

全局 Codex/Claude/ZCode 规则以 `rules/global/` 为唯一源，通过计划绑定、备份和 receipt 投影到用户目录：

```powershell
.\skills.ps1 global-rules-plan --out .\reports\global-rule-projection\plan.json --json
.\skills.ps1 global-rules-apply --plan .\reports\global-rule-projection\plan.json --token <plan.apply.required_token> --out .\reports\global-rule-projection\receipt.json --json
.\skills.ps1 global-rules-apply --plan .\reports\global-rule-projection\plan.json --token <plan.apply.required_token> --out .\reports\global-rule-projection\receipt.json --resume --json
.\skills.ps1 global-rules-check --json
.\skills.ps1 global-rules-rollback --receipt .\reports\global-rule-projection\receipt.json --token <receipt.rollback.required_token> --json
```

投影事务使用 schema v2：apply 会从当前显式 roots 重新推导唯一的 Codex/Claude/ZCode source-target action 集；三份受管源的版本必须一致，但各宿主 B 段保留真实加载与安全差异。若 `~/.zcode` 存在，或通过 `--zcode-user-root` 指定，则会一并加入 ZCode `AGENTS.md` action，并在任何用户规则写入前落盘 journal。中断后仅可用同一 plan、receipt、roots 和显式 `--resume` 续跑。plan/receipt 只能位于 `reports/global-rule-projection/`（`backups/` 保留给内部备份），schema v1 产物 fail closed，需重新执行 plan。默认 Codex 用户根优先使用 `CODEX_HOME`，未设置时使用 `~/.codex`；Claude 用户根优先使用 `CLAUDE_CONFIG_DIR`，未设置时使用 `~/.claude`；ZCode 默认根为 `~/.zcode`；CLI 显式 root 优先级最高。文件相等只证明 `filesystem_projected`，fresh run/session 探针才可证明 `host_loaded`。

### ZCode

ZCode 使用同一个项目根 `AGENTS.md`，不需要另建项目规则文件；它只读取用户级 `~/.zcode/AGENTS.md` 与当前 Workspace 根 `AGENTS.md`。`构建生效` 会按 ZCode profile 把受管 Skills 投影到 `~/.zcode/skills`；`同步MCP` 会将 `skills.json` 的当前 MCP profile 写入 ZCode 原生 `mcp.servers`：用户目标写入 `~/.zcode/cli/config.json`，工作区 `.zcode` 目标写入 `<workspace>/.zcode/config.json`。原生 `.zcode` MCP 优先于 `.agents/mcp.json`，因此本工具不会在 `.zcode` 下生成兼容 `.mcp.json`。这些均是显式宿主投影，不属于普通 build/test，也不证明 ZCode 已加载或真实调用。

审查默认只读。`rule-estate-audit` 默认排除 `external`、`docs` 与 `文档`，并在已配置的 ZCode 用户目录中同时呈现三宿主的静态加载面；ZCode 缺少受管用户规则会 fail closed。全域 plan 仅接受动态发现的直属 Git 仓库规则文件，不接受用户级 Codex/Claude/ZCode 规则；全局规则变更必须先修改 tracked `rules/global/` 源，再走专用 `global-rules-plan/apply/rollback/check` 投影。plan 从 reviewed input、精确 roots、target set 与 actions 生成 plan-bound 显式确认 token；apply 仍校验 before hash、路径、锁与 TOCTOU，并保留 receipt、resume 和逐目标回滚。全域事务逐目标 fail-fast，不承诺跨仓原子性。

### 技能投影与 fallback

宿主原生 metadata 是普通请求的首选选择面。只有用户明确要求使用当前不可见的本地技能，或宿主高置信度判定没有足够的可见技能匹配完整请求且确实需要专门工作流时，才调用一次 `capability-router` 做 cold discovery 或 policy validation；它接收完整请求和至多两个宿主选择的 `DomainHint`，返回小候选集，仍由宿主语义选择。提及或讨论技能、以及语义不确定的普通请求都不是调用；不确定时默认使用通用推理或可见技能。随后 router 校验一个精确候选及其依赖闭包，不作语义排序、不切换 profile、不写宿主状态。输出中的 `routing_receipt` 只保存 query SHA-256、候选/闭包、catalog fingerprint、`truth_boundary` 和写入计数，不回显原始请求；它用于证明“候选发现/候选校验”边界，不等于宿主已加载或真实调用技能。

Codex 与 Claude 默认只投影同一份小型 managed allowlist；其余已安装技能保留为 cold catalog，需要真实任务触发后再读取。这里的“可见”不代表每个请求都会加载或调用完整 `SKILL.md`。

Codex 的 `core` 另保留显式 `$grill-me` 薄入口。`构建生效` 会从受控模板投影 `design-griller` 与 `cold-capability-runner` 两个原生 custom agent 到 `~/.codex/agents`，并为替换保留备份和 ignored receipt。所有 cold catalog 条目都带 execution contract：未显式声明的条目是 `host_admission_required`，可发现、可校验但不能交给 runner；带 side-effect 声明的可运行 entrypoint 必须另有精确 contract。`one_shot` 只能交给后者；`parent_user_input` 必须由父任务向用户取回输入；`multi_turn_user_decision` 必须交给前者一题一轮，父任务保留 child id、转发问题并等待用户答案，不能以“给出结论”降格为单轮摘要。所有 closure entrypoint 必须有路径、`SKILL.md` hash、覆盖同包资源的 package hash 与最大 side-effect 声明：read-only admission 只可运行无写入子集；`controlled_write` 必须另有用户实施请求、精确 write set、最低验证与 stop。未声明副作用的 cold 技能保持 `unknown`、拒绝 runner admission。它们不会切换共享 skill profile，也不会对每条自然语言请求自动 cold discovery。CSR-100 实现后，受管 custom-agent template 将静态声明 `model` / `model_reasoning_effort`，以优先于全局 subagent 默认值；它不改变 provider/auth，也不构成动态模型路由。模板/文件存在只证明 `filesystem_projected`；父 task 的 live sandbox override 可覆盖子代理默认 sandbox，且多轮路由必须以 fresh Codex session 的实际行为另行验收。完整阶段与任务合同见 [冷技能路由路线图](docs/product/cold-skill-routing-roadmap.md)、[实施计划](docs/product/cold-skill-routing-implementation-plan.md) 和 [验收 Runbook](docs/runbooks/cold-skill-routing-acceptance.md)。

```powershell
# 默认只读取仓库侧技能面，不调用宿主 CLI
.\skills.ps1 capability-inventory --view skill-surfaces --json

# 需要当前宿主观测时才显式启用；只调用公开 JSON 命令，不写宿主状态
.\skills.ps1 capability-inventory --view skill-surfaces --host-probe --json
```

默认模式只生成仓库和已投影技能面的快照；只有显式 `--host-probe` 才会读取 `codex plugin list --json`、`codex mcp list --json` 与 `codex doctor --json`。host probe 只保留脱敏的只读 observation：若 enabled plugin 与 standalone/system skill 同名，会输出 `plugin_native_source_preferred` 和 report-only source preference；对仍会被 Codex `full-compatible` 投影的仓库技能，另输出 `retirement_candidates` 的 host-profile 排除候选。候选只保留精确重叠、目标配置路径和不改变的跨宿主/冷目录范围，不能自行卸载，也不把插件存在推断成成功调用。它不会安装、卸载或启用插件，也不读写 plugin cache。该观察不证明技能已经 `host_loaded` 或完成真实调用；公开 CLI 不可用时按 `platform_na`/not observed 报告。

## 外置参考仓

外置参考棚只是按任务显式启用的只读开发缓存，不是产品运行时、普通编码主链或质量门禁。`skills.json` 始终是 runtime 真源；即使外置 checkout 不存在或没有刷新，普通 build、test、update 和 projection 也应继续工作。

需要源码对比时，`references/reference-shelf.manifest.json` 才登记本次可用的 core/secondary 集合，owned root 为 `D:\CODE\external\skills-manager-references`。以下命令只在显式 refresh/verify 工作流中运行：

```powershell
.\scripts\refresh-reference-repos.ps1 -FetchOnly -SkipDirtyRepos
.\scripts\refresh-reference-repos.ps1 -Tier secondary -CloneMissing -FetchOnly -SkipDirtyRepos
.\scripts\verify-reference-governance.ps1
```

refresh/verify 失败只阻断该次参考研究，不外推为产品主链失败。每次 refresh 写入 ignored `reports/reference-refresh/<run-id>/receipt.md`，不在 Git 中维护动态 latest 状态。刷新不会自动采纳、安装或执行外部内容，也不会联动修改 `skills.json`；没有当前消费者的候选不进入 manifest。

## 开发与验证

按风险选择一个 closeout 入口。普通变更运行 build、受影响测试、适用的受影响 verifier 和 diff check。测试入口支持 `-TestPath`、`-TestName` 和标签筛选，适合从大型测试文件中只运行受影响行为：

```powershell
pwsh -NoProfile -File .\build.ps1
pwsh -NoProfile -File .\tests\run.ps1 -TestPath .\tests\Unit\CapabilityInventory.Tests.ps1
# 仅在适用时运行对应的受影响 verifier，例如：
pwsh -NoProfile -File .\scripts\verify-skills-config.ps1 -Mode enforce
git diff --check
```

文档-only 变更只需运行 diff check；单个行为修复可使用 focused gate，避免误跑整套测试：

```powershell
pwsh -NoProfile -File .\scripts\quality\run-local-quality-gates.ps1 -Profile docs
pwsh -NoProfile -File .\scripts\quality\run-local-quality-gates.ps1 -Profile focused -TestPath .\tests\Unit\Core.Tests.ps1 -TestName '*目标行为*' -Verifier config
```

本地收口优先使用 auto 档位：它与 CI 共享同一分类器（含 non-ignored untracked fail-safe），按可解析基线与当前工作区自动选档，无需人工选择 docs/focused/full：

```powershell
pwsh -NoProfile -File .\scripts\quality\run-local-quality-gates.ps1 -Profile auto
```

runtime、安全、数据、迁移、公开契约、依赖、打包或跨面风险改动，在输入冻结后只运行一次 full gate；不要预先重复执行其内部命令：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\quality\run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree
```

测试入口会在 ignored `reports/test-runtime/` 中按固定 SHA-256 准备 Pester 6.1.0，不要求全局安装模块；CI 复用同一 bootstrap。

一键发布包：

```powershell
pwsh -NoProfile -File .\scripts\release\build-release.ps1 -Version <version>
```

发布者须先阅读 [发布指南](docs/RELEASING.md)，尤其是第三方来源和 clean-machine 验收边界。产品边界见 [docs/product/README.md](docs/product/README.md)，贡献规则见 [CONTRIBUTING.md](CONTRIBUTING.md)，PowerShell 支持边界见 [docs/runbooks/powershell-runtime-compatibility.md](docs/runbooks/powershell-runtime-compatibility.md)。
