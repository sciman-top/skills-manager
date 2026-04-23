# 2026-04-23 Functional Healthcheck

## Scope
- Repo: `D:\CODE\skills-manager`
- Goal: Execute major `skills.ps1` capabilities and verify runtime health.
- Mode: direct_fix

## Destination
- Current landing: runtime command execution + diagnostics
- Target landing: command-level health verdict + reproducible evidence
- Verification: exit code + key output + side-effect check

## Platform diagnostics (B.2)
- `codex --version` => exit 0, `codex-cli 0.122.0`
- `codex --help` => exit 0
- `codex status` => `platform_na`
  - reason: non-interactive terminal (`stdin is not a terminal`)
  - alternative_verification: use `codex --version` + `codex --help`
  - evidence_link: this file
  - expires_at: 2026-05-23

## Hard gates (C.2 order)
1. build: `./build.ps1` => pass
2. test: `./skills.ps1 发现` => pass
3. contract/invariant: `./skills.ps1 doctor --strict --threshold-ms 8000` => pass
4. hotspot: `./skills.ps1 构建生效` => pass

## Additional functional checks
- `./skills.ps1 一键 --list` => pass
- `./skills.ps1 workflow all --no-prompt --continue-on-error -DryRun` => pass (but observed non-dry side effects in build/link stage)
- `./skills.ps1 锁定 -DryRun` => fail (`无法读取仓库 HEAD`)
- `./skills.ps1 锁定` => pass
- `./skills.ps1 清理无效映射 --yes --no-build -DryRun` => pass
- `./skills.ps1 同步MCP -DryRun` => pass (security risk: token printed in command preview)
- `./skills.ps1 安装MCP smoke-test -- cmd /c echo hi -DryRun` => pass but actually wrote configs (non-dry side effects)
- `./skills.ps1 卸载MCP smoke-test` => pass but stale `smoke-test` remained in target MCP configs
- `./skills.ps1 同步MCP` => pass but stale `smoke-test` still remained
- `./skills.ps1 解除关联 -DryRun` => pass but actually performed unlink/restore (non-dry side effects)
- recovery: `./skills.ps1 构建生效` => pass (re-linked all targets)
- `./skills.ps1 审查目标 状态` => pass
- `./skills.ps1 审查目标 需求查看` => pass
- `./skills.ps1 审查目标 扫描 --target skills-manager --out reports/skill-audit/... --force` => pass
- `./skills.ps1 审查目标 预检 --run-id 20260423-011906-248` => fail (missing recommendations.json)
- `./skills.ps1 审查目标 发现新技能 --query "ppt 教学" --out reports/skill-audit/profile-only-smoke --force` => pass
- `./skills.ps1 doctor --json` => pass, perf anomaly `sync_mcp`
- `./skills.ps1 一键 审查 --no-prompt -DryRun` => fail (`审查包缺少关键产物 user-profile.json`)

## Findings

### F1 (High) DryRun is not honored for destructive commands
- Commands:
  - `安装MCP ... -DryRun`
  - `解除关联 -DryRun`
  - `workflow all ... -DryRun` (build/link segment)
- Observed: real writes/removals executed.
- Risk: user environment mutated during supposed preview.

### F2 (High) MCP uninstall/sync does not remove stale service entries in target configs
- Repro:
  1) install `smoke-test`
  2) uninstall `smoke-test`
  3) sync MCP
- Observed: `smoke-test` still present in `.claude/.codex/.gemini/.trae` MCP files and `~/.codex/config.toml`.

### F3 (High) Secret leakage in dry-run logs
- Command: `同步MCP -DryRun`
- Observed: preview command prints GitHub PAT literal (`github_pat_***` should be redacted).

### F4 (Medium) Lock command DryRun path broken
- Command: `锁定 -DryRun` / `生成锁文件 -DryRun`
- Observed: `无法读取仓库 HEAD` due dry-run intercepting `git rev-parse` output.

### F5 (Medium) Audit workflow dry-run path fails
- Command: `一键 审查 --no-prompt -DryRun`
- Observed: fails at scan with missing `user-profile.json` in generated run package.

### F6 (Low/Perf) sync_mcp performance anomaly
- Evidence: `doctor --json` reports `sync_mcp: last=44211ms avg=41617ms threshold=10000ms`.

## Cleanup and rollback actions done
- Re-linked all skill targets by re-running `./skills.ps1 构建生效`.
- Manually removed residual `smoke-test` entries from:
  - `~/.claude/.mcp.json`
  - `~/.codex/.mcp.json`
  - `~/.gemini/.mcp.json`
  - `~/.gemini/settings.json`
  - `~/.gemini/antigravity/settings.json`
  - `~/.trae/mcp.json`
  - `D:\CODE\skills-manager\.trae\mcp.json`
  - `~/.codex/config.toml`

## Traceability (R8)
- Basis: project AGENTS hard gates + user request for autonomous functional execution.
- Commands: listed above (in order).
- Evidence: command outputs in session + this file.
- Rollback: environment relink + stale test MCP entry cleanup completed.
