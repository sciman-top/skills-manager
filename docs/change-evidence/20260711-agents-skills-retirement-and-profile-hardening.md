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
- All nine skill profiles pass the 8,000-character budget. Default is 6,638/8,000 after a 1,700-character external plugin reserve; coding is 7,660/8,000; .NET is 7,076/8,000.

## MCP and Plugin Result

- Default managed MCP: Microsoft Learn and OpenAI Developer Docs.
- On-demand MCP: Context7, GitHub, codebase memory, Playwright, and PostgreSQL. Filesystem remains disabled and is not assigned to a profile.
- Host-owned `node_repl` remains enabled and outside the managed deletion boundary.
- Enabled plugins: Documents, PDF, Spreadsheets, Presentations, Chrome, and Computer Use.
- Disabled plugins remain installed for explicit future enablement; none was uninstalled.

## Archive Deletion Gate

Do not delete the retirement archive until all of these pass in fresh tasks:

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
- `tests/run.ps1`: pass, including the inactive-profile budget regression tests.
- `skills.ps1 doctor --strict --threshold-ms 8000`: pass. Existing `apply_targets` performance remains a non-blocking warning under the current contract.
- Dependency baseline verifier: pass.
- Full local quality gate with `-AllowDirtyWorktree`: pass. The flag was required because the audit/import worktree already contained unrelated user changes.
- Projection and host state were checked after persistence; no client process was restarted or stopped.
