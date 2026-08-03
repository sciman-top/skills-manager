# 2026-07-11 .agents skills retirement and profile hardening

## Scope

- Source/config truth: `skills.json`, `src/Commands/SkillProjection.ps1`
- Host scope: `~/.agents/skills`, Codex plugin and managed MCP blocks
- Risk: medium; reversible directory migration and persistent profile projection

## Changes

- Added fail-closed metadata validation for every configured skill profile, including inactive profiles, and persisted `profile_budgets` in the projection manifest.
- Reduced overlapping default, coding, .NET, PPT, content, and browser skill sets. Installed skills remain available through task profiles; no managed skill package was uninstalled.
- Split MCP duties into `coding`, `github`, and `codebase` profiles. Disabled MCP definitions remain installed and do not start until their profile is selected.
- Enabled Chrome for authenticated WeChat/Zhihu workflows and kept Computer Use enabled for Windows GUI work. Browser, Sites, Visualize, GitHub, and Template Creator plugins remain disabled.
- Retired all 89 non-system directories from `~/.agents/skills` into a timestamped archive. The standard root and `.system` were preserved.
- Replaced the deprecated root Junction `~/.codex/skills -> agent` with 111 per-skill Junctions under the standard `~/.agents/skills` root. Claude keeps its root Junction to `agent`.
- Removed Codex-created `.system` contamination from generated `agent/`. Codex may recreate `~/.codex/skills/.system` as a normal host-owned compatibility directory; it is no longer a repository target.

## Retirement Evidence

- Applied manifest: `reports/skill-retirement/20260711-185437-567/manifest.json`
- Archive: `C:\Users\sciman\.agents\retired\skills-user-20260711-185437-567`
- Moved: 89 directories, 903 files, 90 `SKILL.md` files, 14,202,195 bytes
- Preserved: `C:\Users\sciman\.agents\skills\.system`
- Host backup before Chrome enable: `C:\Users\sciman\.codex\config-backups\config.toml.before-chrome-enable.20260711-185640-689.bak`

## Projection Result

- Source entries: 116
- Unique names: 114
- Active default names: 18, including five system skills
- Duplicate/conflict groups: 2, limited to `openai-docs` and `skill-creator`; the system copy wins and the cross-host managed copy is disabled for Codex.
- Disabled paths: 98
- All nine skill profiles pass the 8,000-character budget. Default is 6,638/8,000 after a 1,700-character external plugin reserve; coding is 7,276/8,000; content is 7,726/8,000; .NET is 7,076/8,000.

## MCP and Plugin Result

- Default managed MCP: Microsoft Learn and OpenAI Developer Docs.
- On-demand MCP: Context7, GitHub, codebase memory, Playwright, and PostgreSQL. Filesystem remains disabled and is not assigned to a profile.
- Host-owned `node_repl` remains enabled and outside the managed deletion boundary.
- Enabled plugins: Documents, PDF, Spreadsheets, Presentations, Chrome, and Computer Use.
- Disabled plugins remain installed for explicit future enablement; none was uninstalled.

## Archive Deletion Gate

Fresh-context loading checks 1-4 now pass. Do not delete the retirement archive until the remaining rollback-window condition also passes:

1. A normal Codex coding task loads the managed profile skills.
2. A PPT/document task uses the official runtime plugin skills.
3. A Claude task loads skills through `~/.claude/skills -> agent`.
4. A .NET task loads `microsoft-code-reference` under the `.NET` profile.
5. No config, link, report, or task references the archive path, and a short rollback window has elapsed.

The root `~/.agents/skills` and `.system` are not deletion candidates. Only the timestamped retirement archive may be deleted after the gate.

## Rollback

- Skills: read the applied manifest and move each `archive_path` back to `source_path`; stop on any collision.
- Projection/MCP: restore `skills.json`, rebuild, then run `构建生效` and `同步MCP`.
- Plugin: restore the recorded `config.toml` backup.
- Do not restart or stop Codex/Claude as part of rollback; verify with a fresh task.

## Verification

- `build.ps1`: pass; generated `skills.ps1` matches `src`.
- Fixed the PowerShell property-output boundary that collapsed a single-item `skill_projection.sources` array into a scalar. Added a JSON-backed regression test that preserves the array container and passes the full config contract.
- `tests/run.ps1`: pass, including 431 unit tests and 12 E2E tests; the inactive-profile budget and single-source projection regressions are covered.
- `skills.ps1 doctor --strict --threshold-ms 8000`: pass. Existing `apply_targets` performance remains a non-blocking warning under the current contract.
- Dependency baseline verifier: pass.
- Full local quality gate with `-AllowDirtyWorktree`: pass on the final tree. The flag was required because the audit/import worktree already contained unrelated user changes.
- `scripts/verify-codex-skill-profiles.ps1`: pass for coding, PPT/plugin, .NET, and default contexts using the official model-visible `codex debug prompt-input` surface; default was restored in `finally`.
- A real ephemeral `codex exec` reached the configured GPT-5.6 model but response generation was blocked by the account usage limit. The official no-generation prompt-input diagnostic supplied the loading proof instead.
- A real non-persistent Claude task invoked `/microsoft-code-reference` through `~/.claude/skills -> agent` and returned `CLAUDE_SKILL_OK`.
- After removing the old Codex Junction and rerunning all fresh-context checks, `agent/.system` was not recreated. Projection and host state were checked after persistence; no client process was restarted or stopped.
- Final host inventory: `~/.agents/skills` contains 111 managed per-skill Junctions plus the ordinary host-owned `.system`; `~/.codex/skills` is not a Junction and contains only its host-owned `.system`.
- Final projection inventory: 116 entries, 114 unique names, 18 active default names, 98 disabled paths, and two intentional conflicts (`openai-docs`, `skill-creator`). All nine profile budgets pass.
- Final live inventory: six enabled plugins and five disabled plugins; Microsoft Learn and OpenAI Developer Docs are the only enabled managed MCP servers, six managed MCP servers remain installed but disabled, and host-owned `node_repl` remains enabled.
- Final retirement dry-run: pass with zero historical candidates; all 111 managed Junctions were recognized and preserved.
