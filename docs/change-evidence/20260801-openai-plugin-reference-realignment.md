# OpenAI plugin reference shelf realignment

## Scope and boundary

- Task: `SMV-P0-002` only.
- Source/target: make `openai/plugins` the current official plugin reference and retain `openai/skills` as deprecated historical compatibility evidence.
- Runtime boundary: no `skills.json`, installed skill, MCP target, host-local configuration, provider, model, auth or session state was changed.
- External shelf boundary: clone/fetch is read-only reference maintenance, not product runtime projection or live acceptance.

## Decisions

- `openai-plugins` is `core-mainline`, `active` and `current-official`; it replaces `openai-skills` in `default_refresh_set`.
- `openai-skills` remains present as `historical-compatibility`, `deprecated`, with an explicit replacement and deprecation evidence revision. It is not deleted or used as a default new-install source.
- Default refresh validates that every selected entry exists and has `status=active`; historical refresh requires the explicit `-Tier historical` route.
- The upstream repository has no root-wide license file. Licensing is therefore `per-plugin`: material may be inspected read-only, but copying or redistribution requires checking the selected plugin's own license and provenance first.
- Existing portable packaging already includes the three reference-governance files, so this slice adds a regression assertion rather than changing packaging behavior.

## Sources and supply-chain evidence

| Source | Revision/state | Decision |
| --- | --- | --- |
| `https://github.com/openai/plugins.git` | `11c74d6ba24d3a6d48f54a194cd00ef3beea18f9`; clean local clone at `D:\CODE\external\skills-manager-references\core\openai-plugins` | Current official read-only structural reference. |
| `D:\CODE\external\skills-manager-references\core\openai-plugins\README.md` | Declares curated Codex plugin examples and per-plugin layout | Adopt repository/plugin structure as reference input only. |
| `D:\CODE\external\skills-manager-references\core\openai-plugins` licensing scan | No root `LICENSE`; 180 plugin directories, with plugin-local license files not uniformly present | Require per-plugin license review before copying; do not infer a repository-wide grant. |
| `https://github.com/openai/skills.git` | Deprecation evidence pinned as `README.md@49f948faa9258a0c61caceaf225e179651397431` | Preserve only as historical/runtime compatibility evidence. |

The external source was treated as untrusted read-only input. No upstream script was run.

## Changes

- Updated the manifest default set, source disposition, status, replacement and license policy fields.
- Added historical tier routing and an active-only invariant for default refresh.
- Updated reference shelf docs and current/historical authority wording.
- Added manifest, refresh isolation and portable package regression tests.
- Updated the planning fixture so every done task carries its exact evidence and todo status drift remains fail-closed as the done set grows.
- Refreshed the default reference shelf with `-CloneMissing -FetchOnly -SkipDirtyRepos`; only `openai-plugins` was cloned, while existing repositories were fetched without pulling their local branches.
- Recorded the dated refresh report and updated the stable latest pointer.

## Verification

The required order is `build -> test -> contract/invariant -> hotspot/full`. Results below are filled from the fresh closeout run for this task.

| Command | Result |
| --- | --- |
| Dated refresh report plus independent origin/revision/worktree inspection | `references/updates/reference-refresh-20260801-134159.md` records successful clone/fetch; `openai-plugins` is clean at `11c74d6ba24d3a6d48f54a194cd00ef3beea18f9` with the expected origin. |
| Targeted `Core.Tests.ps1` and `ReleasePackaging.Tests.ps1` | exit 0; 191/191 passed (Core 188 plus packaging 3). |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` | exit 0; generated `skills.ps1`. |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1` | exit 0; Unit 512/512 and E2E 12/12 passed. |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict --threshold-ms 8000` | exit 0; config contract valid and doctor ready. |
| `python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline` | exit 0; repository dependency baseline verified. |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-vnext-planning.ps1 -Json` | exit 0; tasks=9, done=2, open=7, findings=0. |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` | exit 0; build, hygiene, generated sync, 105-skill integrity, routing findings=0, dependency, planning, doctor contract and all tests passed. |

## N/A and open acceptance

| Type | Reason | Alternative verification | Recovery condition |
| --- | --- | --- | --- |
| `platform_na` host load | This task changes reference governance only. | Manifest, routing and package tests. | Run a native probe only when a later task changes a host-loaded surface. |
| `gate_na` live workflow | No runtime capability or user workflow was added. | Repo tests and full local gate. | Execute a real host workflow before any `live_accepted` claim. |

## Rollback

Restore only this task's manifest/docs/refresh/test/evidence files. Do not delete the external clone, remove installed skills, modify `skills.json`, or roll back unrelated planning-contract changes.

## Truth boundary

This evidence closes only `SMV-P0-002` at reference-governance/repo-verifier scope. `SMV-P0-003` through `SMV-P0-009`, Phase 0 completion, host loading and live workflow acceptance remain open.
