# 2026-05-09 MCP env contract hardening

## Goal

- 当前落点: `D:\CODE\skills-manager`
- 目标归宿: 让 weekly `更新 -> 同步MCP` 在写入 Codex/Claude/Gemini/Trae MCP 配置前先修复或阻断 GitHub/Postgres 环境漂移。
- 验证方式: 单元测试、真实 `同步MCP`、项目硬门禁 `build -> test -> contract/invariant -> hotspot`。

## Root Cause

- weekly task `skills-manager-weekly-update-friday-2000` 会运行 `scripts/weekly-auto-update.ps1`，脚本依次执行 `更新` 与 `同步MCP`。
- `同步MCP` 会重写用户级 MCP 配置，尤其是 `C:\Users\sciman\.codex\config.toml` 的 `[mcp_servers.*]` 段。
- `github` MCP 对 Codex 需要 `CODEX_GITHUB_PERSONAL_ACCESS_TOKEN`，而不是只依赖 `GITHUB_PERSONAL_ACCESS_TOKEN` 或 `codex mcp login github`。
- `postgres` MCP 当前包要求 `postgresql://...` URL；当 `POSTGRES_CONNECTION_STRING` 漂成 `Host=...;Port=...` 形态时，server 进程会在 MCP handshake 前退出。

## Changes

- `src/Commands/Mcp.ps1`
  - 新增 scoped env 读取 helper，明确 Process/User/Machine 来源。
  - 新增 `Convert-PostgresKeyValueConnectionStringToUrl`，支持将 Npgsql/ADO key-value 连接串转换为 `postgresql://` URL。
  - 新增 `Ensure-PostgresMcpEnvironment`，在 `同步MCP` 写配置前检测 postgres MCP，缺失或不可转换时阻断；可转换时写回 User scope 并设置当前 Process env。
  - 扩展 `Ensure-GhAuthForGithubMcp`，通过 `gh auth token` 同步 User scope 的 `CODEX_GITHUB_PERSONAL_ACCESS_TOKEN`，避免新 Codex 会话继续缺 token。
- `tests/Unit/Core.Tests.ps1`
  - 覆盖 Postgres key-value 到 URL 的转换。
  - 覆盖 postgres MCP 同步前的 Process/User env 归一化。

## Commands

```powershell
./build.ps1
Invoke-Pester -Path 'tests\Unit\Core.Tests.ps1'
./skills.ps1 同步MCP
./skills.ps1 发现
./skills.ps1 doctor --strict --threshold-ms 8000
./skills.ps1 构建生效
```

## Key Output

- `./build.ps1`: `Build success: D:\CODE\skills-manager\skills.ps1`
- `Invoke-Pester -Path 'tests\Unit\Core.Tests.ps1'`: `Tests Passed: 154, Failed: 0`
- `./skills.ps1 同步MCP`:
  - `Postgres MCP 连接串已归一化到 User scope`
  - `GitHub MCP gh 认证预检通过：sciman-top`
  - `Codex 检测到 GitHub MCP 且存在 Token，将写入 bearer_token_env_var=CODEX_GITHUB_PERSONAL_ACCESS_TOKEN。`
  - `MCP 配置态校验通过：codex -> context7, filesystem, github, microsoft-learn, openaiDeveloperDocs, playwright, postgres`
- `./skills.ps1 doctor --strict --threshold-ms 8000`: `Your system is ready for skills-manager.`
- `./skills.ps1 构建生效`: completed, agent input unchanged and target junctions valid.

## Rollback

```powershell
git checkout -- src/Commands/Mcp.ps1 tests/Unit/Core.Tests.ps1 docs/change-evidence/20260509-mcp-env-contract-hardening.md
./build.ps1
./skills.ps1 同步MCP
```

If the live User environment must be reverted separately, restore the previous User-scope values for `POSTGRES_CONNECTION_STRING` and `CODEX_GITHUB_PERSONAL_ACCESS_TOKEN`, then restart Codex so MCP startup re-reads the environment.
