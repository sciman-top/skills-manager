# 2026-07-11 Skills / MCP profile remediation

## Scope

- Rule IDs: R1, R2, R4, R6, R8, E4, E5
- Risk: medium (persistent user-level Codex skill, MCP, and plugin activation state)
- Source of truth: `skills.json`, `src/Commands/SkillProjection.ps1`, `src/Commands/Mcp.ps1`

## Basis

- The cross-root projection previously found 81 duplicate-name groups and 57 package-content conflicts; equal names were not treated as proof of equal packages.
- Eleven main skills were canonical only under `~/.agents/skills`. Eight have maintained upstream/import sources; three are superseded names.
- Ten Codex plugins and eight managed MCP servers were enabled or installed without purpose profiles, exceeding the intended fixed-context budget.

## Changes

- Added seven maintained Superpowers mappings and the existing `ui-ux-pro-max` import to the managed build.
- Added aliases: `social-content -> social`, `to-prd -> to-spec`, `to-issues -> to-tickets`.
- Added skill profiles and an 8,000-character metadata gate. The default profile is estimated at 7,843 characters, including a 1,400-character plugin reserve after restoring the Windows-focused `computer-use` plugin.
- Added MCP profiles plus verified tool allowlists. Default enables only Microsoft Learn and OpenAI developer docs.
- Codex keeps disabled MCP definitions; generic hosts receive only active-profile servers. Host-owned `node_repl` is preserved.
- Disabled six lower-frequency Codex plugins without uninstalling them. Documents, presentations, spreadsheets, PDF, and the Windows-focused `computer-use` plugin remain enabled. The later-installed `sites` plugin remains disabled because it otherwise adds fixed skills and the `sites-design-picker` MCP outside the original snapshot.

## Evidence

- `codex --version`: `codex-cli 0.144.1`
- Build result: 110 generated skill directories; projection schema v2; 203 source entries; 116 unique names; 23 active names.
- Projection result: 86 duplicate-name groups; 62 different-package conflicts; default metadata budget `7793/8000`, pass.
- All nine skill profiles have no missing names and remain below 8,000 characters.
- The eight real unique capabilities are managed by this repository. The three superseded names are disabled as aliases.
- MCP config state: two managed servers enabled, six disabled, host-owned `node_repl` enabled.
- Plugin config state: five plugins enabled (the four Office plugins plus `computer-use`) and six disabled (`template-creator`, `browser`, `chrome`, `visualize`, `github`, and `sites`).

## Rollback

- Skills/MCP: restore the prior `skills.json`, rebuild `skills.ps1`, then run `构建生效` and `同步MCP`.
- Codex skill projection: restore the matching file under `~/.codex/config-backups/config.toml.skills-projection.*.bak`.
- Plugin activation: restore `~/.codex/config-backups/config.toml.plugins-before-closeout.20260711-175305-050.bak` or the earlier `config.toml.plugins-before-default-profile.20260711-004649-751.bak`.
- No skill directory was deleted. No Codex, Claude, or desktop process was restarted or stopped.

## N/A

- `platform_na`: client hot reload was not available or assumed. Alternative verification used `codex plugin list`, `codex mcp list`, generated config inspection, and a future new task. Evidence: this file. Expires: next Codex task.
