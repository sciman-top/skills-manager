# 2026-07-30 Skills / MCP Overlap Consolidation

## Result

- Added one focused validator skill: `custom-powerpoint-accessibility`.
- Removed five overlapping imported skills: `design-taste-frontend`, `ui-ux-pro-max`, `use-my-browser`, `md2wechat-lite`, and `guizang-ppt-skill`.
- Removed two overlapping repo-managed and host-local MCP configurations: `github` and `filesystem`.
- Added no MCP server and installed no plugin.
- Retained `setup-matt-pocock-skills` in `engineering`: the initial removal attempt was rejected by the fail-closed dependency gate because `to-spec` / `to-tickets` use it as a runtime setup fallback. Its upstream `disable-model-invocation: true` keeps it from implicit invocation.
- Preserved Context7, Playwright, and codebase-memory as disabled/on-demand MCP entries. Preserved Microsoft Learn and OpenAI Developer Docs as enabled official-document sources.
- Did not restart, stop, or kill Codex, Claude, ChatGPT, PowerPoint, or any other process.
- Did not commit or push. The implementation crossed local midnight; research and the initial decision were completed on 2026-07-30 and final verification ran on 2026-07-31.

## Research Basis

The decision used source hierarchy rather than popularity alone:

1. Current official Codex documentation for Skills and MCP boundaries: reusable procedural guidance belongs in a Skill; authenticated live data and controlled external actions are MCP concerns.
   - https://developers.openai.com/codex/skills
   - https://developers.openai.com/codex/mcp
2. Current Microsoft PowerPoint accessibility and Accessibility Checker guidance. These sources support titles, alt text, reading order, table headers, meaningful links, captions, contrast, non-color cues, and native checker evidence.
   - https://support.microsoft.com/en-us/office/make-your-powerpoint-presentations-accessible-to-people-with-disabilities-6f7772b2-2f33-4bd2-8ca7-dae3b2b3ef25
   - https://support.microsoft.com/en-us/office/rules-for-the-accessibility-checker-651e08f2-0fc3-4e10-aaca-74b4a67101c1
3. `skills.sh` all-time and trending discovery plus `find-skills` searches for WPF, PowerPoint/courseware, publishing, physics animation, multi-agent engineering, security, and Office automation.
   - https://skills.sh/
4. GitHub monthly Trending and repository metadata used for candidate freshness and maintenance signals, not as installation authority.
   - https://github.com/trending?since=monthly
5. Community comparison: `Community-Access/accessibility-agents` at revision `0872b4a7763145fc0e5847d8357fb446a857c683`.
   - https://github.com/Community-Access/accessibility-agents/tree/0872b4a7763145fc0e5847d8357fb446a857c683

The cross-check did not justify Hallmark/Emil design bundles, OfficeCLI, another WPF skill, video skill, or new MCP. Their useful capability was already covered by installed first-party plugins, focused domain routers, native Codex tools, or lower-permission CLIs. The only material gap was a fail-closed PowerPoint accessibility validator.

## Changes

### Skill and routing truth

- `overrides/custom-powerpoint-accessibility/` defines a validator with native checker, editable structure, render/preview, reading-order, and assistive-technology truth boundaries.
- `ppt` profile now includes the new validator.
- `teacher-courseware-ppt` routing keeps Presentations as the PPTX executor and `powerpoint-automation` as the live PowerPoint/COM operator; the new skill composes only as a validator.
- `design` no longer carries `ui-ux-pro-max` or `design-taste-frontend`.
- `engineering` retains setup/bootstrap material only to close the declared runtime fallback of `to-spec` / `to-tickets`; it is not part of `default` or `coding`.
- Fresh projection: `107` unique entries, `11` active in `default`, `96` disabled, `0` conflicts; all profile budgets pass.
- Relevant final profile budgets: `ppt=7947/10000`, `design=7479/10000`, `engineering=7150/10000`, and `default=6729/7500`.

### Import and MCP truth

- Mappings: `102 -> 97`.
- Imports: `49 -> 44`; lock summary is `8` vendors / `44` imports.
- Repo-managed MCP servers: `7 -> 5`.
- Remaining repo-managed MCP names: `context7`, `microsoft-learn`, `openaiDeveloperDocs`, `playwright`, `codebase-memory-mcp`.
- The obsolete `github` MCP profile was removed, leaving no dangling profile reference.
- The five gitlinks had no `.gitmodules` entries, so ordinary `git rm` could not resolve submodule names. Their exact paths were verified under `D:\CODE\skills-manager\imports`, removed from the index, and physically deleted with path-scoped `git clean -ffdx`. A read-only directory attribute on `ui-ux-pro-max` was cleared before its final empty-directory cleanup.

## Host Projection

- `skills.ps1 构建生效` created `C:\Users\sciman\.agents\skills\custom-powerpoint-accessibility` and removed the five retired managed Junctions.
- `skills.ps1 同步MCP` projected the current repo-owned default MCP set to `C:\Users\sciman\.claude\.mcp.json`.
- Current repo targets do not own the Codex TOML MCP surface. Before host removal, `C:\Users\sciman\.codex\config.toml` still contained `github` and `filesystem`.
- Verified official command semantics with `codex mcp remove --help`, backed up the TOML, then ran `codex mcp remove github` and `codex mcp remove filesystem`.
- Backup: `C:\Users\sciman\.codex\config-backups\skills-mcp-overlap-20260731-001812\config.toml`.
- Backup SHA-256: `40613B937A39C393E82490795855A1467A06FCE750D98015682A7F4A24484DE9`.
- Post-change TOML parses successfully. `codex mcp list` contains neither removed name; official docs remain enabled, Context7/Playwright/codebase-memory remain disabled, and host-owned `node_repl` plus host-local disabled `postgres` remain outside this repo's managed list.
- No process restart was required. Existing tasks may retain already-loaded metadata until a new task, but persisted config and fresh prompt probes reflect the new state.

## Worktree Boundary

- Start state: clean `main`, `HEAD=4b898997a6dcdcc24a4cebf0b4957230a0f1d212`, `origin/main=c91342cb88a5d3115140e11d60491aa57a2a6feb`.
- The existing local commit `feat: 优化技能路由并刷新上游锁定` was already present and remained untouched; local `main` was one commit ahead of remote before this work.
- The initial implementation changed the documented config, routing, verifier, lock, override, evidence, and five retired gitlinks. No unrelated worktree change was reverted.
- At commit/push closeout on 2026-07-31, 18 additional tracked import gitlinks had advanced after the earlier verified snapshot: `agent-browser`, `data-visualization`, `domain-modeling`, `drawio-diagram-forge`, `find-skills`, `grill-with-docs`, `grilling`, `improve-codebase-architecture`, `mcp-cli`, `modern-python`, `powerpoint-automation`, `prd-to-issues`, `research`, `storyboard-creation`, `supabase-postgres-best-practices`, `ui-animation`, `windows-desktop-e2e`, and `write-a-prd`.
- The user's commit/push instruction covered the whole worktree. These revisions were therefore adopted, `skills.lock.json` was regenerated against all 44 imports, and `构建生效` plus the full quality gate were rerun before commit. The refreshed build signature reported unchanged generated skill inputs; projection remained 107 unique entries with zero conflicts.

## Verification

| Command | Result |
| --- | --- |
| `quick_validate.py overrides/custom-powerpoint-accessibility` | exit 0, skill valid |
| `pwsh -File build.ps1` | exit 0 |
| `pwsh -File skills.ps1 锁定` | exit 0, 8 vendors / 44 imports |
| `pwsh -File skills.ps1 构建生效` | exit 0, 104 built skills, projection persisted |
| `pwsh -File skills.ps1 同步MCP` | exit 0, repo target config validated |
| `pwsh -File tests/run.ps1` | exit 0, Unit 501/501 and E2E 12/12 |
| `pwsh -File skills.ps1 doctor --strict --threshold-ms 8000` | exit 0; non-blocking `apply_targets` performance warning only |
| `python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline` | exit 0 |
| `pwsh -File scripts/verify-codex-skill-profiles.ps1` | first run timed out at 180s and left `video` active; stale assertions were corrected, `default` restored; both the corrected run and the post-dependency-fix run exited 0 for all 16 profiles |
| `pwsh -File scripts/benchmark-codex-skill-profiles.ps1` | exit 0, 2 profiles / 12 cases / 24 planned calls |
| `codex mcp list` plus TOML parser | exit 0; removed entries absent and TOML valid |
| `pwsh -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` | first run correctly failed because removing `setup-matt-pocock-skills` broke the `to-spec` / `to-tickets` profile dependency closure; final rerun exit 0, Unit 501/501 and E2E 12/12 |

The first profile-verifier timeout was not treated as success. Its interrupted profile side effect was explicitly repaired, the stale design/PPT expectations were updated, and the full fresh-context verifier then passed. The first full quality gate was also not treated as success: it exposed that the proposed setup-skill profile removal contradicted the repository's verified dependency contract, so the required dependency was restored instead of weakening the gate.

## Rollback

- Repo rollback must be limited to the files listed in this evidence and the five named gitlinks. Do not reset or overwrite unrelated work.
- Reintroducing any retired import requires restoring its exact `skills.json` import/mapping and locked revision before rebuilding; popularity alone is insufficient.
- Reverting the new skill requires removing its PPT profile/routing references before deleting the override, then rerunning build, lock, projection, and gates.
- Host MCP rollback should merge only the two removed MCP blocks from the timestamped backup after comparing the current TOML; do not blindly replace the full config because host-owned fields can change concurrently.
- After any rollback, rerun `构建生效`, `同步MCP`, `codex mcp list`, TOML parsing, and the fixed gate order.

## Truth Boundary

Completed: current-source research, one focused Skill addition, five managed Skill retirements, two repo and host MCP removals, lock/projection refresh, fresh-context profile validation, and repo-side tests.

Not claimed: existing open Codex tasks hot-reloaded all metadata; PowerPoint assistive-technology behavior was tested on a real classroom deck; any unrelated product repo, onsite classroom workflow, remote deployment, plugin cache, model/provider/auth setting, or roadmap was changed or accepted.
