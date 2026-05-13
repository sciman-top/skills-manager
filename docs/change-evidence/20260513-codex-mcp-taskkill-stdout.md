# Codex MCP taskkill stdout cleanup

- rule_ids: R1, R6, R8
- risk: medium
- target_disposition: keep Codex App and Codex CLI MCP stdio clean while preserving Claude/Gemini/Trae MCP sync behavior
- basis: Codex App logs and `codex exec` showed non-JSON `taskkill` success text on the MCP pipe, causing parse failures and flickering conversation content.

## Changes

- Updated `src/Commands/Mcp.ps1` so Codex skips known leaky Windows npx stdio MCPs by default:
  - `@upstash/context7-mcp`
  - `@modelcontextprotocol/server-filesystem`
  - `@playwright/mcp`
- Added `SKILLS_CODEX_INCLUDE_LEAKY_STDIO_MCP=1` as an explicit override for local experiments.
- Kept Claude/Gemini/Trae MCP output unchanged for those npx servers.
- Wrapped Codex `postgres` through `~/.codex/scripts/mcp-postgres-env-wrapper.mjs`.
- Rebuilt root `skills.ps1` and re-ran `./skills.ps1 同步MCP`.

## Commands

- `./build.ps1`
- `./skills.ps1 发现`
- `Invoke-Pester -Script tests\Unit\Core.Tests.ps1`
- `./skills.ps1 同步MCP`
- `codex mcp list`
- `codex exec --ephemeral --skip-git-repo-check --output-last-message <temp> "Reply exactly OK."`
- `./skills.ps1 doctor --strict --threshold-ms 8000`
- `./skills.ps1 构建生效`

## Key Output

- `codex mcp list` shows Codex stdio MCP only as `postgres`; HTTP MCPs remain `github`, `microsoft-learn`, and `openaiDeveloperDocs`.
- `codex exec` exit_code was `0`, stdout was exactly `OK`, and `last_message` was `OK`.
- `Invoke-Pester -Script tests\Unit\Core.Tests.ps1`: `157` tests passed, `0` failed.
- `./skills.ps1 doctor --strict --threshold-ms 8000`: `Your system is ready for skills-manager.`
- `./skills.ps1 构建生效`: completed successfully.

## Rollback

- `git restore -- src/Commands/Mcp.ps1 tests/Unit/Core.Tests.ps1 skills.ps1 docs/change-evidence/20260513-codex-mcp-taskkill-stdout.md`
- Re-run `./build.ps1`, `./skills.ps1 同步MCP`, and `./skills.ps1 构建生效` after rollback if live MCP output needs to be restored.
