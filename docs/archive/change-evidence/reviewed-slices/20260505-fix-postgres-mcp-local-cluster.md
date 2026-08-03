# 2026-05-05 fix postgres MCP local connectivity

## Goal

- Current location: `D:\CODE\skills-manager`
- Target home: make the managed `postgres` MCP usable without committing database credentials.
- Verification: local PostgreSQL readiness, MCP live health, protocol-level `query` call, and project gates.

## Root Cause

- `postgres` MCP was installed and enabled, but the host had no `POSTGRES_CONNECTION_STRING` in process, user, or machine environment.
- The existing PostgreSQL 17 Windows service on port `5432` was running, but requires `scram-sha-256` password authentication. No reusable `.pgpass` or `PG*` environment credential was available.
- Direct failure was reproducible as `POSTGRES_CONNECTION_STRING is required for postgres MCP.` / exit code `64`.

## Fix

- Created an isolated local PostgreSQL 17 cluster for MCP usage:
  - Data directory: `%LOCALAPPDATA%\skills-manager\postgres-mcp\17\data`
  - Host/port: `127.0.0.1:55432`
  - User: `mcp_user`
  - Database: `postgres`
- Generated a random local password and stored only the resulting connection URL in the user-level `POSTGRES_CONNECTION_STRING` environment variable.
- Added user logon task `skills-manager-mcp-postgres-start` to start the isolated cluster after login.
- Updated managed `postgres` MCP command in `skills.json` to read `POSTGRES_CONNECTION_STRING` from:
  1. process environment
  2. user environment
  3. machine environment

The repository does not contain the connection string or password.

## Commands

```powershell
.\skills.ps1 安装MCP postgres --cmd pwsh -- -NoLogo -NoProfile -Command '<wrapper that reads POSTGRES_CONNECTION_STRING from process/user/machine env>'

$env:SKILLS_MCP_NATIVE_SYNC='1'
$env:SKILLS_MCP_VERIFY_LIVE_CLI='1'
$env:SKILLS_MCP_VERIFY_ATTEMPTS='1'
.\skills.ps1 同步MCP
```

## Key Output

- `pg_isready -h 127.0.0.1 -p 55432 -U mcp_user`: accepting connections
- `psql <user-env POSTGRES_CONNECTION_STRING> -Atc 'select 1 as mcp_ready;'`: `1`
- Protocol probe:
  - `initialize`: pass
  - `tools/list`: returned `query`
  - `tools/call query` with `select 1 as mcp_ready;`: returned `mcp_ready = 1`
- `claude mcp list`: `postgres ... - Connected`
- `.\skills.ps1 同步MCP` with native/live verification: all managed MCPs passed for Claude, Codex, and Gemini.

## Verification

- `.\build.ps1`: pass
- `.\skills.ps1 发现`: pass, 87 skills
- `.\skills.ps1 doctor --strict --threshold-ms 8000`: pass
- `.\skills.ps1 构建生效`: pass
- `.\scripts\quality\run-local-quality-gates.ps1 -Profile quick -AllowDirtyWorktree`: pass
- `git diff --check`: pass

## Rollback

```powershell
$data = Join-Path $env:LOCALAPPDATA 'skills-manager\postgres-mcp\17\data'
& 'C:\Program Files\PostgreSQL\17\bin\pg_ctl.exe' stop -D $data -m fast

Unregister-ScheduledTask -TaskName 'skills-manager-mcp-postgres-start' -Confirm:$false
[Environment]::SetEnvironmentVariable('POSTGRES_CONNECTION_STRING', $null, 'User')

# Optional after confirming no data is needed:
Remove-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'skills-manager\postgres-mcp') -Recurse -Force

.\skills.ps1 同步MCP
```

If the command-wrapper change itself must be reverted, revert the commit that added this evidence file and the `skills.json` wrapper update, then rerun `.\skills.ps1 同步MCP`.
