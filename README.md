# skills-manager

Windows-first、local-first 的 PowerShell 7 技能与 MCP 管理器。它把多个来源的技能收敛到一个版本化配置，生成可移植技能目录，并提供目标仓审查、规则审查和受控投影。

本项目不做第二套 AI runtime：不选择模型，不管理 provider/auth/session，不接管 Codex/Claude 的语义路由，也不直接维护插件缓存。仓库测试只证明 `repo_verified`；宿主新会话加载和真实业务验收必须分别验证。

## 快速开始

要求 PowerShell 7 (`pwsh`) 和 Git。Windows PowerShell 5.1 不受支持。

```powershell
pwsh -NoProfile -File .\skills.ps1 help
pwsh -NoProfile -File .\skills.ps1 发现
pwsh -NoProfile -File .\skills.ps1 安装
pwsh -NoProfile -File .\skills.ps1 doctor --strict --threshold-ms 8000
```

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
- `skill_projection`：技能来源、别名、domain catalog、metadata budget 和 native placement

`skills.lock.json` 锁定已解析来源。`src/` 是 CLI 源码，`build.ps1` 生成根 `skills.ps1`；`overrides/{custom,patches,resources}` 生成 `agent/`。不要手改 `skills.ps1`、`agent/`、`vendor/` 或运行态 `reports/`。

## 常用命令

### 技能

```powershell
.\skills.ps1 发现
.\skills.ps1 安装
.\skills.ps1 卸载 <name> --yes
.\skills.ps1 add <repo> --skill <path>
.\skills.ps1 锁定
.\skills.ps1 verify-lock
.\skills.ps1 更新 -Plan
.\skills.ps1 更新 -Upgrade
.\skills.ps1 构建生效
```

`构建生效` 会重建并写入宿主目标，属于外部投影动作。仅需仓库内同步时运行 `build.ps1`；不要用 `构建生效` 代替普通构建验证。

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

扫描产物位于 ignored `reports/skill-audit/<run-id>/`。`recommendations.json` 必须经过 preflight 和 dry-run；只有显式 `--apply --yes` 才写配置。runtime evidence 与 recommendations 同目录，不进入 tracked 文档。

### 规则审查

```powershell
.\skills.ps1 rule-audit --repo <repo-root> --host codex --json
.\skills.ps1 rule-plan --target <AGENTS.md> --desired-file <reviewed.md> --repo-root <repo> --out <plan.json> --json
.\skills.ps1 rule-apply --plan <plan.json> --repo-root <repo> --token APPLY_RULE_REPO_PATCH --json
.\skills.ps1 rule-estate-audit --workspace-root D:\CODE --json
.\skills.ps1 rule-estate-plan --review <reviewed-change-set.json> --workspace-root D:\CODE --out <plan.json> --json
.\skills.ps1 rule-estate-apply --plan <plan.json> --workspace-root D:\CODE --token APPLY_RULE_ESTATE_PATCH --json
```

审查默认只读。单仓和全域写入都要求 reviewed input、精确根目录、before hash、显式 token、receipt 与回滚入口；全域事务逐目标 fail-fast，不承诺跨仓原子性。

### 技能投影与 fallback

宿主原生 metadata 是普通请求的首选选择面。`capability-router` 只在显式 cold discovery 或 policy validation 时使用；它接受 `DomainHint`，返回候选并校验宿主选择，不执行语义排序、不切换 profile、不写宿主状态。

```powershell
.\skills.ps1 capability-inventory --view skill-surfaces --json
pwsh -NoProfile -File .\scripts\verify-capability-routing.ps1 -Json
pwsh -NoProfile -File .\scripts\verify-native-skill-metadata.ps1 -Json
```

## 外置参考仓

`references/reference-shelf.manifest.json` 只登记当前使用的 core/secondary 参考集，owned root 为 `D:\CODE\external\skills-manager-references`。刷新不会自动采纳、安装或执行外部内容，也不会联动修改 `skills.json`。

```powershell
.\scripts\refresh-reference-repos.ps1 -FetchOnly -SkipDirtyRepos
.\scripts\refresh-reference-repos.ps1 -Tier secondary -CloneMissing -FetchOnly -SkipDirtyRepos
.\scripts\verify-reference-governance.ps1
```

没有当前消费者的候选不进入 manifest；需要时重新研究和登记，不保留永久候选池。

## 开发与验证

```powershell
pwsh -NoProfile -File .\build.ps1
pwsh -NoProfile -File .\tests\check-generated-sync.ps1 -AllowDirtyWorktree
pwsh -NoProfile -File .\scripts\verify-skill-integrity.ps1
pwsh -NoProfile -File .\scripts\verify-skills-config.ps1 -Mode enforce
git diff --check
```

按风险选择 closeout：普通切片跑受影响测试；runtime、安全、数据、迁移、公开契约、依赖或打包变更才跑一次 full gate。

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\quality\run-local-quality-gates.ps1 -Profile full -ReuseCurrentReceipt
# exact-current receipt 不存在且确需新 full 时：
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\quality\run-local-quality-gates.ps1 -Profile full -ForceFresh -AllowDirtyWorktree
```

产品边界见 [docs/product/README.md](docs/product/README.md)，贡献规则见 [CONTRIBUTING.md](CONTRIBUTING.md)，PowerShell 支持边界见 [docs/runbooks/powershell-runtime-compatibility.md](docs/runbooks/powershell-runtime-compatibility.md)。
