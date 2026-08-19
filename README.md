# skills-manager

Windows-first、local-first 的 PowerShell 7 技能与 MCP 管理器。它把分散在多个仓库的 AI 技能收敛到一份版本化配置，锁定来源、生成可移植技能目录，并安全投影给 Codex/Claude 等宿主。

适合希望在多台 Windows 电脑上复用同一套技能、审计目标仓规则、统一管理 MCP 清单，同时又不愿把模型、账号和运行时交给另一层框架的个人或团队。

本项目不做第二套 AI runtime：不选择模型，不管理 provider/auth/session，不接管 Codex/Claude 的语义路由，也不直接维护插件缓存。仓库测试只证明 `repo_verified`；宿主新会话加载和真实业务验收必须分别验证。

本项目采用 [MIT License](LICENSE)。第三方技能与依赖仍各自遵循其原始许可证。

## 快速开始

要求 PowerShell 7 (`pwsh`) 和 Git。Windows PowerShell 5.1 不受支持。

### 推荐：Release 一键安装

从 [GitHub Releases](https://github.com/sciman-top/skills-manager/releases) 下载 `bootstrap.zip`，解压后运行：

```powershell
.\setup.cmd
```

需要离线或 U 盘绿色运行时下载 `portable.zip`，解压后运行 `skills.cmd`；它不会自动写宿主目录。两种包的选择、SHA-256 校验和迁移步骤见 [安装、绿色运行与迁移](docs/INSTALLATION_AND_MIGRATION.md)。

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
- `targets`：生成技能的目标目录
- `mcp_servers` / `mcp_profiles` / `mcp_targets`：MCP 清单与同步目标
- `skill_projection`：技能来源、domain catalog 和 native placement；metadata budget 与 description 截断由宿主原生处理

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
```

`check-updates --json` 只报告每个来源的 `current/target/changed/source`，不 apply、不构建、不投影、不同步 MCP。`构建生效` 会重建并写入宿主目标，属于外部投影动作。仅需仓库内同步时运行 `build.ps1`；不要用 `构建生效` 代替普通构建验证。仓库不再创建或管理 Windows 自动更新计划任务；`doctor` 只读提示同名旧任务，清理由用户在宿主侧决定。

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
.\skills.ps1 审查目标 扫描 --target <name>
.\skills.ps1 审查目标 预检 --recommendations <file>
.\skills.ps1 审查目标 应用确认 --recommendations <file>
.\skills.ps1 审查目标 应用 --recommendations <file> --apply --yes
```

扫描产物位于 ignored `reports/skill-audit/<run-id>/`，每个 run 固定只有三个文件：`snapshot.json` 是不可变审查输入，`recommendations.json` 是唯一允许 AI 编辑的决策文件，`receipt.json` 是命令维护的阶段、结果、补偿/回滚与 truth-boundary 记录。`recommendations.json` 必须经过 preflight 和 dry-run；只有显式 `--apply --yes` 才写配置。缺少 snapshot 直接阻断，不生成第四个报告或 evidence 文件。

### 规则审查

```powershell
.\skills.ps1 rule-audit --repo <repo-root> --host codex --json
.\skills.ps1 rule-plan --target <AGENTS.md> --desired-file <reviewed.md> --repo-root <repo> --out <plan.json> --json
.\skills.ps1 rule-apply --plan <plan.json> --repo-root <repo> --token APPLY_RULE_REPO_PATCH --json
.\skills.ps1 rule-estate-audit --workspace-root D:\CODE --json
.\skills.ps1 rule-estate-plan --review <reviewed-change-set.json> --workspace-root D:\CODE --out <plan.json> --json
.\skills.ps1 rule-estate-apply --plan <plan.json> --workspace-root D:\CODE --token <plan.apply.required_token> --json
```

全局 Codex/Claude 规则以 `rules/global/` 为唯一源，通过计划绑定、备份和 receipt 投影到用户目录：

```powershell
.\skills.ps1 global-rules-plan --out .\reports\global-rule-projection\plan.json --json
.\skills.ps1 global-rules-apply --plan .\reports\global-rule-projection\plan.json --token <plan.apply.required_token> --out .\reports\global-rule-projection\receipt.json --json
.\skills.ps1 global-rules-apply --plan .\reports\global-rule-projection\plan.json --token <plan.apply.required_token> --out .\reports\global-rule-projection\receipt.json --resume --json
.\skills.ps1 global-rules-check --json
.\skills.ps1 global-rules-rollback --receipt .\reports\global-rule-projection\receipt.json --token <receipt.rollback.required_token> --json
```

投影事务使用 schema v2：apply 会从当前显式 roots 重新推导唯一的 Codex/Claude source-target action 集，并在任何用户规则写入前落盘 journal；中断后仅可用同一 plan、receipt、roots 和显式 `--resume` 续跑。plan/receipt 只能位于 `reports/global-rule-projection/`（`backups/` 保留给内部备份），schema v1 产物 fail closed，需重新执行 plan。默认 Codex 用户根优先使用 `CODEX_HOME`，未设置时使用 `~/.codex`；Claude 用户根优先使用 `CLAUDE_CONFIG_DIR`，未设置时使用 `~/.claude`；CLI 显式 root 优先级最高。文件相等只证明 `filesystem_projected`，fresh run/session 探针才可证明 `host_loaded`。

审查默认只读。全域 plan 仅接受动态发现的直属 Git 仓库规则文件，不接受用户级 Codex/Claude 规则；全局规则变更必须先修改 tracked `rules/global/` 源，再走专用 `global-rules-plan/apply/rollback/check` 投影。plan 从 reviewed input、精确 roots、target set 与 actions 生成 plan-bound 显式确认 token；apply 仍校验 before hash、路径、锁与 TOCTOU，并保留 receipt、resume 和逐目标回滚。全域事务逐目标 fail-fast，不承诺跨仓原子性。

### 技能投影与 fallback

宿主原生 metadata 是普通请求的首选选择面。`capability-router` 允许宿主在可见 metadata 不足时按需选择，用于 cold discovery 或 policy validation；它接受 `DomainHint`，返回候选并校验宿主选择，不作普通请求前置，不执行语义排序、不切换 profile、不写宿主状态。

```powershell
.\skills.ps1 capability-inventory --view skill-surfaces --json
```

该命令还会读取 `codex plugin list --json`、`codex mcp list --json` 与 `codex doctor --json`，只保留脱敏的只读 host observation。若 enabled plugin 与 standalone/system skill 同名，会输出 `plugin_native_source_preferred` 和 report-only source preference；它不会安装、卸载或启用插件，也不读写 plugin cache。该观察不证明技能已经 `host_loaded` 或完成真实调用；公开 CLI 不可用时按 `platform_na`/not observed 报告。

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

按风险选择一个 closeout 入口。普通变更运行 build、受影响测试、适用的受影响 verifier 和 diff check：

```powershell
pwsh -NoProfile -File .\build.ps1
pwsh -NoProfile -File .\tests\run.ps1 -TestPath .\tests\Unit\CapabilityInventory.Tests.ps1
# 仅在适用时运行对应的受影响 verifier，例如：
pwsh -NoProfile -File .\scripts\verify-skills-config.ps1 -Mode enforce
git diff --check
```

runtime、安全、数据、迁移、公开契约、依赖、打包或跨面风险改动，在输入冻结后只运行一次 full gate；不要预先重复执行其内部命令：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\quality\run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree
```

测试入口会在 ignored `reports/test-runtime/` 中按固定 SHA-256 准备 Pester 6.1.0，不要求全局安装模块；CI 复用同一 bootstrap。

一键发布包：

```powershell
pwsh -NoProfile -File .\scripts\release\build-release.ps1 -Version 2026.08.13
```

### 每周 skills-only 自动更新

需要无人值守维护 skills 来源时，可注册每周五 20:00 的本机计划任务：

```powershell
pwsh -NoProfile -File .\scripts\register-weekly-skills-update.ps1
pwsh -NoProfile -File .\scripts\weekly-skills-update.ps1 -DryRun
```

任务只执行 skills 来源检查、`更新 -Upgrade`、quick gate 和本地 lock 提交；不会同步 MCP，也不会 push。非 `main`、tracked 工作树不干净、并发运行或出现预期外 tracked 写入时均会阻断。

发布者须先阅读 [发布指南](docs/RELEASING.md)，尤其是第三方来源和 clean-machine 验收边界。产品边界见 [docs/product/README.md](docs/product/README.md)，贡献规则见 [CONTRIBUTING.md](CONTRIBUTING.md)，PowerShell 支持边界见 [docs/runbooks/powershell-runtime-compatibility.md](docs/runbooks/powershell-runtime-compatibility.md)。
