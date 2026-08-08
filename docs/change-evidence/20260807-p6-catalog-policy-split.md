# SMV-P6-004 Catalog Compiler and Eligibility Policy Evidence

**task**: `SMV-P6-004`
**task_truth_level**: `repo_verified`
**phase_truth_level**: `planning_contract`
**runtime_migration**: `not_started`
**profile_router_cold_load_retirement**: `not_started`
**host_loaded**: `not_run`
**live_accepted**: `not_run`
**full_gate**: `not_passed`
**provider_calls**: `0`
**native_mutations**: `0`
**writes**: `0`

## Scope and write-set

This slice separates the reusable catalog and safety seams from the legacy capability router while retaining the router's existing compatibility output. The exact implementation set is:

- `src/Domain/SkillCatalog.ps1`
- `src/Application/SkillCatalogCompiler.ps1`
- `src/Application/SkillEligibilityPolicy.ps1`
- `overrides/custom/capability-router/scripts/route-capability.ps1`
- `tests/Unit/SkillCatalogCompiler.Tests.ps1`
- `tests/Unit/SkillEligibilityPolicy.Tests.ps1`
- `docs/change-evidence/20260807-p6-catalog-policy-split.md`

`SkillCatalogCompiler` now compiles all supplied managed roots or direct entries into a deterministic canonical `SkillCatalog` with path/source provenance, content and metadata hashes, duplicate decisions and completeness findings. It does not read or apply profile membership, active/current profile state or semantic ranking. Its contract reports `decision_owner=host_ai`, `semantic_selection_applied=false`, `profile_filter_applied=false` and zero side-effect counters.

`SkillEligibilityPolicy` is a deterministic allow/deny/needs-activation boundary for containment, freshness, availability, dependencies, surface compatibility, side effect and approval. Stale/unknown or unsafe facts fail closed; semantic selection/confidence/profile inputs cannot widen a deny. The policy reports `decision_owner=deterministic_policy`, does not perform semantic selection or profile filtering and remains zero-write/provider-free.

The legacy router now loads these seams when the repository sources are present, compiles its assembled skill inventory and exposes a `catalog_policy_compatibility` envelope. The envelope is explicitly `legacy_router_compatibility`, preserves the legacy schema-3 selection behavior, and keeps the new core's catalog/policy decisions observable without replacing the current compatibility path. No second semantic ranking path was added.

## Red-green and verification evidence

- RED: the new compatibility test initially failed because `catalog_policy_compatibility` was absent from the legacy router result; this was the expected missing-adapter failure.
- GREEN: `Invoke-Pester tests/Unit/SkillCatalogCompiler.Tests.ps1` → 3 passed, 0 failed, including the compatibility-envelope test.
- POLICY: `Invoke-Pester tests/Unit/SkillEligibilityPolicy.Tests.ps1` → 2 passed, 0 failed.
- LEGACY CHARACTERIZATION: `Invoke-Pester tests/Unit/CapabilityRouter.Tests.ps1` → 25 passed, 0 failed before and after the adapter bridge.
- ROUTING CONTRACT: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-skill-routing.ps1 -Json` → `ok=true`, `blocking=false`, 1 existing warning finding, no write.
- BUILD: `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` → exit 0, `Build success`; the post-build focused suites remained green.

The compatibility fixture proves one contained fresh skill is compiled and policy-evaluated while the envelope remains profile-free, semantic-free and `provider_calls=0`, `native_mutations=0`, `writes=0`. The existing router characterization preserves explicit invocation, negative constraints, domain/profile compatibility, host snapshot fail-closed behavior, session reuse and deterministic activation policy.

## Truth boundary and rollback

This is repository-verified only. P6 remains `planning_contract`; runtime migration, all-enabled native projection, profile/router/cold-load retirement, host loading, live acceptance and the full quality gate remain open or not run. The routing contract's warning is non-blocking and does not change that boundary.

To roll back this slice, remove the catalog domain/compiler/policy modules, the router compatibility bridge, the two focused test additions and this evidence file; restore `SMV-P6-004` to pending in the manifest/plan/todo. Do not alter P6-001 through P6-003 evidence, generated/cache output, host configuration or unrelated concurrent watch-runtime changes.
