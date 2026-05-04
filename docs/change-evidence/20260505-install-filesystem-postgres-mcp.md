# 2026-05-05 install filesystem and postgres MCP

## Goal

- 当前落点: `D:\CODE\skills-manager`
- 目标归宿: 通过本仓统一入口 `skills.ps1` 把 `filesystem` 与 `postgres` MCP 写入 `skills.json` 并同步到托管目标。
- 验证方式: 按项目硬门禁执行 `build -> test -> contract/invariant -> hotspot`，并补充 native/live MCP 状态检查。

## Risk

- 风险等级: 中
- 原因: MCP 会写入用户级 CLI 配置。`filesystem` 需要限制访问根目录；`postgres` 需要连接串，不能把数据库凭据落入仓库。
- 风险处理:
  - `filesystem` 根目录限定为 `D:\CODE\skills-manager`。
  - `postgres` 使用 `POSTGRES_CONNECTION_STRING` 环境变量，并在变量为空时以 exit code 64 明确失败。

## Commands

```powershell
.\skills.ps1 安装MCP filesystem --cmd npx -- -y @modelcontextprotocol/server-filesystem D:\CODE\skills-manager

$postgresCommand = 'if ([string]::IsNullOrWhiteSpace($env:POSTGRES_CONNECTION_STRING)) { Write-Error "POSTGRES_CONNECTION_STRING is required for postgres MCP."; exit 64 }; npx -y @modelcontextprotocol/server-postgres $env:POSTGRES_CONNECTION_STRING'
.\skills.ps1 安装MCP postgres --cmd pwsh -- -NoLogo -NoProfile -Command $postgresCommand

.\build.ps1
Invoke-Pester -Path 'tests/Unit/Core.Tests.ps1','tests/E2E/Workflow.Tests.ps1'
.\skills.ps1 同步MCP
.\skills.ps1 发现
.\skills.ps1 doctor --strict --threshold-ms 8000
.\skills.ps1 构建生效
.\scripts\quality\run-local-quality-gates.ps1 -Profile quick -AllowDirtyWorktree
.\tests\run.ps1
git diff --check
codex mcp list
claude mcp list
```

## Key Output

- `skills.json`: `mcp_servers` 从 5 个增加到 7 个，新增 `filesystem` 与 `postgres`。
- `codex mcp list`: `filesystem` 与 `postgres` 均为 `enabled`。
- `claude mcp list`: `filesystem` 为 `Connected`；`postgres` 为 `Failed to connect`，原因是当前未设置 `POSTGRES_CONNECTION_STRING`。
- 直接执行 `postgres` 包装命令时，空环境变量会明确报错: `POSTGRES_CONNECTION_STRING is required for postgres MCP.`
- `@modelcontextprotocol/server-postgres@0.6.2` 当前由 npm 报出 deprecated warning；本次按用户指定包安装，后续可单独评估替代 MCP。

## Fixes

- 修复 managed `filesystem` 会被 legacy prune 逻辑误删的问题: 只有未在 `skills.json` 显式托管的 legacy MCP 名称才会被清理。
- 修复 explicit native Claude MCP sync 遇到已存在服务时无法更新命令的问题: 现在会先 `claude mcp remove <name> --scope user`，再重试 add。
- 增加回归测试覆盖:
  - 显式托管的 legacy 名称不会被 prune。
  - explicit native Claude sync 可以替换已存在 MCP。
  - E2E 同步产物保留 managed legacy 名称。

## Verification

- `.\build.ps1`: pass
- `Invoke-Pester -Path 'tests/Unit/Core.Tests.ps1','tests/E2E/Workflow.Tests.ps1'`: pass, 160 passed
- `.\skills.ps1 同步MCP`: pass
- `.\skills.ps1 发现`: pass, 87 skills
- `.\skills.ps1 doctor --strict --threshold-ms 8000`: pass, with non-blocking performance warning for `sync_mcp` average
- `.\skills.ps1 构建生效`: pass
- `.\scripts\quality\run-local-quality-gates.ps1 -Profile quick -AllowDirtyWorktree`: pass
- `.\tests\run.ps1`: pass, Unit 356 passed, E2E 11 passed
- `git diff --check`: pass

## Rollback

```powershell
.\skills.ps1 卸载MCP filesystem
.\skills.ps1 卸载MCP postgres
.\skills.ps1 同步MCP

# 如果 explicit native Claude sync 已写入原生注册表，可同步清理:
claude mcp remove filesystem --scope user
claude mcp remove postgres --scope user
```

## Follow-up

- 若要让 `postgres` live health 通过，需要在宿主环境设置有效连接串:

```powershell
$env:POSTGRES_CONNECTION_STRING = 'postgresql://user:password@host:5432/dbname'
claude mcp list
```
