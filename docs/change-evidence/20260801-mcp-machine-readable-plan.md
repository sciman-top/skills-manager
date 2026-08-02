# SMV-P0-006 MCP machine-readable plan evidence

**Date**: 2026-08-01
**Scope**: repository-side MCP desired-state planning and existing apply parity
**Truth ceiling**: `repo_verified`; `host_loaded=not_run`; `live_accepted=not_run`

## Implemented contract

- Added `src/Application/McpPlanning.ps1` as the shared desired-state calculation for plan and apply.
- Added `mcp-sync --plan --json [--out <path>]` and the equivalent `同步MCP --plan` route without changing the unplanned apply route.
- Plan output uses `OperationPlan v1`, stable target refs/hashes/action IDs, changed/unchanged counts, and no desired content.
- Read-only plan loading validates and normalizes `skills.json` without calling the legacy auto-repair/writeback path.
- Plan does not write managed MCP targets, call native MCP add/remove, change active profile, or claim host/live verification. An explicit `--out` writes only the requested evidence file.
- Existing Chinese/English apply aliases and legacy `-DryRun` human preview remain in place.

## Defects found during verification

- Operation IDs initially depended on pre-normalized target enumeration. The planner now sorts targets/actions before fingerprinting.
- Nested root arrays returned by the legacy resolver initially collapsed multiple roots into one invalid path. The Application boundary now accepts the legacy shape and flattens roots before target enumeration.

## Verification

| Order | Command | Result |
| ---: | --- | --- |
| 1 | `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` | exit 0 |
| 2 | Pester `tests/Unit/McpPlanning.Tests.ps1` | 7 passed, 0 failed |
| 3 | Pester `tests/E2E/Workflow.Tests.ps1` | 10 passed, 0 failed; legacy MCP apply tests retained |
| 4 | `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 mcp-sync --plan --json` | exit 0; one valid JSON envelope; 1 target, 0 actions, unchanged 1, native/profile false |
| 5 | full local quality gate | rerun after final status synchronization; see final Phase 0 evidence |

The live `skills.json` SHA-256 remained `4fe42dc2dfa385f785a3bade3650d011d4961e24f5fa5456900b8f2f3699053f` through the plan probe. No host-local MCP file was written by plan mode and no native/live probe was requested.

## Rollback

Remove the Application planner and CLI plan route, restore the prior `同步MCP` body, remove the targeted tests/docs/evidence, and rebuild `skills.ps1`. Do not touch `skills.json`, host MCP config, active profile, imports, or unrelated worktree changes.
