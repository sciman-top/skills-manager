# skills.json v1 schema and validator contract

## Scope and boundary

- Task: `SMV-P0-003` only.
- Source/target: add a versioned declarative schema, reusable version contract, and independent read-only observe/enforce verifier for `skills.json`.
- Runtime boundary: the current `skills.json` was not rewritten, formatted, migrated or projected to any host.
- Ownership boundary: auth, provider, model, context, sandbox, rule and plugin configuration remain outside this repository contract.

## Decisions

- Current schema version is `1`. An absent `schema_version` is read as legacy v1 and produces `legacy_schema_version_missing`; it is not silently persisted.
- Explicit v1 uses strict top-level array/scalar/object types. Existing runtime semantics in `Get-CfgContractErrors` remain authoritative for enums, references and safe relative paths.
- Unknown properties remain compatible because the existing configuration contains evolving product surfaces; tightening them requires a later migration window and fixtures.
- `observe` returns a non-blocking diagnostic with `would_block=true`; `enforce` returns nonzero for findings. The repository quality gate uses `enforce` because current config passes.
- Verifier output contains only codes, JSON-like paths, generic messages and input hashes. It does not echo rejected values, credentials or config payloads.
- The standalone verifier reads source files explicitly as UTF-8, allowing both PowerShell 7 and the bounded Windows PowerShell 5.1 probe to parse the existing non-BOM source safely.

## Changes

- Added Draft 2020-12 `config/skills.schema.json` with v1 structure, defaults, enums, compatibility metadata and sensitive-output policy.
- Added version helpers to `src/Config.ps1` without changing `LoadCfg`, normalization or persistence behavior.
- Added `scripts/verify-skills-config.ps1` with observe/enforce modes, safe findings and before/after SHA-256 proof.
- Added known-good, legacy, wrong-type, unknown-enum and unsafe-path fixtures plus Pester coverage.
- Inserted `skills-config-contract` after dependency baseline and before planning/doctor contracts in quick/full gates.
- Updated README routing, generated `skills.ps1`, task truth, todo and planning fixtures.

## Verification

The fixed order is `build -> test -> contract/invariant -> hotspot/full`. Results below are filled from the final fresh closeout run.

| Command | Result |
| --- | --- |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` | exit 0; generated `skills.ps1`. |
| targeted `ConfigSchema.Tests.ps1`, `QualityGateScripts.Tests.ps1` and `ProductPlanning.Tests.ps1` | exit 0; 22/22 passed. |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1` | exit 0; Unit 521/521 and E2E 12/12 passed. |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-skills-config.ps1 -Mode enforce` | exit 0; valid=true, finding=0, legacy observation=1, before/after SHA-256 identical. |
| `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-skills-config.ps1 -Mode enforce` | exit 0; same version/hash/finding/observation result as PowerShell 7. |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-vnext-planning.ps1 -Json` | exit 0; tasks=9, done=3, open=6, findings=0. |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict --threshold-ms 8000` | exit 0; current config contract valid and doctor ready. |
| `python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline` | exit 0; repository dependency baseline verified. |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` | exit 0; build, hygiene, generated sync, 105-skill integrity, routing findings=0, dependency, config, planning, doctor and all tests passed. |

## Migration, compatibility and rollback

- Migration window: missing version remains supported as legacy v1 observation. No automatic writeback occurs.
- Recovery condition: a future explicit migration may add `schema_version` only after backup, full config fixtures and host behavior parity evidence.
- Rollback only this task's schema/verifier/Config source/generated output/tests/gate/README/task/evidence files, then rebuild `skills.ps1`.
- Never restore `skills.json` from a whole-worktree operation or alter host configuration as part of this rollback.

## N/A and open acceptance

| Type | Reason | Alternative verification | Recovery condition |
| --- | --- | --- | --- |
| `platform_na` host load | This task validates repository config without applying it. | Hash-stable verifier, doctor and full gate. | Run host probes only in a task that changes a host-loaded surface. |
| `gate_na` live workflow | No user workflow or projection behavior changed. | Current/fixture contracts and full repo tests. | Execute a real workflow before any `live_accepted` claim. |

## Truth boundary

This evidence closes only `SMV-P0-003` at config-contract/repo-verifier scope. `SMV-P0-004` through `SMV-P0-009`, Phase 0 completion, host loading and live workflow acceptance remain open.
