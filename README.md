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

## 路径与编辑策略

| 路径 / 键 | 作用 | 编辑策略 |
| --- | --- | --- |
| `skills.json` | 单一配置真源，托管 `vendors / mappings / imports / targets / sync_mode / mcp_servers` | 直接修改 |
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
.\skills.ps1 安装MCP context7 -- npx -y @upstash/context7-mcp
.\skills.ps1 安装MCP filesystem --cmd npx --arg -y --arg @modelcontextprotocol/server-filesystem --arg D:\CODE\skills-manager
.\skills.ps1 安装MCP github --transport http --url https://api.githubcopilot.com/mcp/ --bearer-token-env-var GITHUB_PERSONAL_ACCESS_TOKEN
.\skills.ps1 卸载MCP context7
.\skills.ps1 同步MCP
```

说明：

- `安装MCP` / `卸载MCP` 会更新 `skills.json`，随后自动执行一次 `同步MCP`。
- `同步MCP` 会把 MCP 服务清单写入目标根目录 `.mcp.json`、Gemini/Trae 配置以及 Codex `config.toml` 的 `[mcp_servers.*]` 段。
- `postgres` MCP 预检要求 `POSTGRES_CONNECTION_STRING` 为 `postgresql://...`；若检测到 Npgsql/ADO 风格 key-value 连接串，会自动转换并写回 User scope。
- `github` MCP 会优先尝试 `gh auth token`，并把结果写入 User scope 的 `CODEX_GITHUB_PERSONAL_ACCESS_TOKEN`；Codex 配置只写 `bearer_token_env_var`，不写明文 token。
- 本机 weekly task `skills-manager-weekly-update-friday-2000` 的顺序是 `更新 -> 同步MCP`，所以 MCP 启动环境修复必须落在真源链上，不能只改 live `~/.codex/config.toml`。

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

- `quick`：`build -> repo-hygiene -> generated-sync -> dependency-baseline -> doctor-json-contract`
- `full`：`quick + tests`

## MCP 与门禁环境变量

- `POSTGRES_CONNECTION_STRING`：postgres MCP 的连接串；推荐 `postgresql://...`
- `CODEX_GITHUB_PERSONAL_ACCESS_TOKEN`：Codex GitHub MCP 使用的 User/Process scope token 变量
- `SKILLS_MCP_VERIFY_GEMINI_CLI=1|true|yes|on`：启用 Gemini CLI 实机校验（默认关闭）
- `SKILLS_MCP_VERIFY_LIST_TIMEOUT_SECONDS`：统一设置 `mcp list` 校验超时（秒）
- `SKILLS_MCP_VERIFY_LIST_TIMEOUT_SECONDS_<CLI>`：按 CLI 覆盖超时（例如 `_CLAUDE` / `_CODEX` / `_GEMINI`）
- `SKILLS_MCP_NATIVE_TIMEOUT_SECONDS`：原生 `claude mcp add/remove` 超时（秒）
- `SKILLS_MCP_VERIFY_ATTEMPTS`、`SKILLS_MCP_VERIFY_INTERVAL_SECONDS`：跨 CLI MCP 校验重试次数与重试间隔（秒）
- `SKILLS_SYNC_MCP_THRESHOLD_MS`：`check-doctor-json.ps1` 中 `sync_mcp` 性能阈值（毫秒）

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

- [Contributing](CONTRIBUTING.md)
- [Security Policy](SECURITY.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [overrides README](overrides/README.md)

## License

MIT
