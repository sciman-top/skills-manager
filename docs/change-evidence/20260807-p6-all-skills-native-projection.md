# SMV-P6-006 All-Skills Native Projection Evidence

**task**: `SMV-P6-006`
**task_truth_level**: `repo_verified`
**phase_truth_level**: `repo_verified`
**runtime_migration**: `native_projection_applied_unverified_dirty_tree`
**profile_router_cold_load_retirement**: `native_default_legacy_compatibility_only`
**host_loaded**: `accepted_124_of_124_fresh_inventory`
**live_accepted**: `not_accepted_observability_gap`
**baseline_full_gate**: `passed_1097_of_1097`
**current_tree_full_gate**: `passed_1121_of_1121`
**projection_provider_calls**: `0`
**live_host_mutations**: `0`
**live_host_notification**: `not_sent`

## Scope and write-set

This slice adds the application-level native discovery projection and its explicit transaction boundary:

- `src/Application/SkillProjection.ps1`
- `src/Application/NativeSkillProjection.ps1`
- `skills.json`
- `tests/Unit/SkillProjection.Tests.ps1`
- `tests/Unit/NativeSkillProjection.Tests.ps1`
- `docs/change-evidence/20260807-p6-all-skills-native-projection.md`

The new seam consumes the canonical catalog, deterministic eligibility decisions and the P6-005 metadata plan. It does not read or apply `active_profile`; profile fields remain in `skills.json` as compatibility inputs for the legacy command until P6-010. Eligible enabled entries are projected as complete rows containing source path, target path, content hash, metadata hash and concise native metadata. Disabled entries and denied entries are excluded.

`skills.json.skill_projection.native_projection` declares the target owner, native user-skill root, receipt path, explicit-token requirement and a `skills/changed` `plan_only` notification mode. The configuration is descriptive and does not mutate the live host.

`Apply-NativeSkillProjection` requires the exact plan token, verifies source hashes and target-root containment, creates junctions through a temporary path, and writes an atomic JSON receipt. A partial apply removes only the directories created by that transaction. `Rollback-NativeSkillProjection` compares every target with the recorded after-state before changing anything; target drift blocks rollback fail-closed. The receipt records before/after states, changed names, notification-not-sent status and rollback guard. Tests use isolated `TestDrive` roots only.

## Red-green and verification evidence

- RED: `Invoke-Pester -Path tests/Unit/NativeSkillProjection.Tests.ps1` initially reported 3 failures, each because `New-NativeSkillProjectionPlan` was not defined. This was the expected feature-missing failure.
- GREEN: `Invoke-Pester -Path tests/Unit/SkillProjection.Tests.ps1,tests/Unit/NativeSkillProjection.Tests.ps1` → `39 passed, 0 failed, 0 skipped`. Cases cover formerly profile-excluded enabled skills, disabled paths, complete path/hash/metadata rows, explicit token rejection, atomic partial rollback, receipt creation, changed notification planning and drift-safe rollback.
- DEPENDENCY REGRESSION: `Invoke-Pester -Path tests/Unit/SkillCatalogCompiler.Tests.ps1,tests/Unit/SkillEligibilityPolicy.Tests.ps1,tests/Unit/NativeMetadataPlanner.Tests.ps1,tests/Unit/NativeSkillProjection.Tests.ps1` → `12 passed, 0 failed, 0 skipped`.
- BUILD: `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` → exit 0, `Build success: D:\CODE\skills-manager\skills.ps1`.
- GENERATED SYNC: `pwsh -NoProfile -ExecutionPolicy Bypass -File tests/check-generated-sync.ps1 -AllowDirtyWorktree` → exit 0, consecutive build hashes matched and generated sync passed. The pre-existing dirty `skills.ps1` boundary remains recorded; no generated file was hand-edited.
- CONFIG CONTRACT: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-skills-config.ps1 -Mode enforce` → `valid=true`, `pass=true`, `finding_count=0`, `observation_count=0`.
- ROUTING COMPATIBILITY: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-skill-routing.ps1 -Json` → `ok=true`, `blocking=false`; one existing `strong_trigger_signal` warning for `grilling` remains non-blocking.
- PLANNING CONTRACTS: `verify-host-native-skill-lifecycle-planning.ps1 -Json` → `pass=true`, `finding_count=0`; `verify-vnext-planning.ps1 -Json` → `pass=true`, `done_count=6`, `open_count=6`, `evidence_count=6`, `finding_count=0`.
- HOTSPOT: `git diff --check` → exit 0; only existing Windows LF/CRLF normalization warnings were emitted.

The plan contract enforces `enabled_total == kept_total`, `omitted_total=0` and `truncated=false` for a ready plan. Planning has zero provider calls and zero writes; fixture apply writes are isolated transaction tests and are not live host evidence.

## Production coordinator and authorized projection follow-up

The initial application seam is now connected to production through
`NativeSkillProjectionCoordinator.ps1`, the generated bundle and
`Sync-CodexSkillProjection`. The coordinator compiles top-level generated
packages, applies eligibility and adaptive metadata planning, validates the
complete native projection contract, then performs compatibility reconciliation
only as stale cleanup. Semantic names such as `debug:dotnet` remain intact
while Windows target directories use safe source-package leaves such as
`debug-dotnet`.

Focused RED reproduced three production-only defects: the legacy profile
budget blocked native authority, fixed 160-character metadata compaction could
not fit all 106 skills, and a namespaced semantic name was rejected as a
Windows directory name. Focused GREEN added native authority precedence,
deterministic adaptive compaction to a 73-character maximum, and separate
semantic/target names. The final plan retained 106/106 eligible skills with
zero omission and `truncated=false`.

The authorized dirty-tree projection used
`skills.ps1 构建生效 -AllowUnverifiedHostProjection`; the manifest records
`promotion_mode=unverified_override`, `source_worktree_dirty=true`. Receipt
`nsr-ee280d58772b26ea` for plan `nsp-4bbd7b8bfe669a2e` is `applied`, with
106 before and 106 after, zero changed names, zero writes, zero native
mutations, plan-only notification not sent, and drift-safe rollback available.
Zero writes is an observed no-op because all managed junctions already matched;
it is not a fabricated mutation receipt.

Fresh App Server snapshot `hcs-2003353adbc51a2f` then observed 124/124 enabled
skills with fresh inventory and zero errors. The snapshot remains globally
`partial` only because `metadata_budget` is unavailable. This accepts
`host_loaded`, not universal selection or `live_accepted`.

## Truth boundary and rollback

This is repository-verified only. P6 remains `planning_contract`; runtime migration, resident router/profile/cold-load retirement, fresh host loading, live acceptance and the unique full quality gate remain open or not run. A passing projection fixture proves the transaction and completeness contract, not that the host has loaded the root, selected a skill, injected a full body or executed a live task. No plugin/MCP installation, App Server notification, provider call or silent live host mutation occurred.

To roll back this slice, use the recorded receipt against its owned fixture/target root only, or remove the two new application modules, the native projection config block, the new focused test/evidence assets, and restore `SMV-P6-006` to `pending` in the manifest/plan/todo. Rebuild `skills.ps1` after source/config restoration. Preserve the pre-existing watch-runtime, planning, generated-output and unrelated worktree changes.
