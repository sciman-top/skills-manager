# SMV-P6-005 Native Metadata Planner Evidence

**task**: `SMV-P6-005`
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

This slice adds the deterministic, zero-write metadata budget planner and its policy source:

- `src/Application/NativeMetadataPlanner.ps1`
- `config/native-skill-metadata-policy.json`
- `tests/Unit/NativeMetadataPlanner.Tests.ps1`
- `docs/change-evidence/20260807-p6-native-metadata-planner.md`

Known effective context uses `floor(context_window * 0.02)` as the nominal token ceiling. A fresh host `metadata_budget` fact is applied as a stricter ceiling when present. The planner exposes both the nominal ceiling and a configurable 20% headroom (`usable_tokens = floor(ceiling * 0.80)`), with source, freshness, formula and host-ceiling provenance.

When context and explicit host metadata budget are unknown, the planner uses the documented conservative 8,000-character fallback with the same headroom (`usable_characters=6,400`). It marks the measurement unit as `characters`; it does not convert the character cap into a token claim or use token estimates as the fallback selection unit. Known-context plans use provided token estimates when available, otherwise a visible UTF-8-byte estimate. Character count and token estimate remain separate fields.

All enabled entries are considered together. If the raw cost exceeds the usable budget, descriptions are deterministically compacted first. If the compacted set still does not fit, the plan is `blocked`, `truncated=true`, every enabled name is explicitly listed in `omitted`, and exact overflow offenders/costs are returned. No profile state, semantic ranking, tokenizer service, provider, host renderer or native projection write is consulted.

## Red-green and verification evidence

- RED: `Invoke-Pester tests/Unit/NativeMetadataPlanner.Tests.ps1` initially reported 4 failures because `Plan-NativeMetadata` was absent; the failures were the expected missing-planner failures.
- GREEN: `Invoke-Pester tests/Unit/NativeMetadataPlanner.Tests.ps1` → 4 passed, 0 failed. Cases cover 272000 context (`5440` token ceiling), unknown-context fallback, explicit token estimate versus long character description, and compact-then-fail exact-offender behavior.
- BUILD: `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` → exit 0, `Build success`.
- DEPENDENCY REGRESSION: `SkillCatalogCompiler.Tests.ps1` → 3 passed; `SkillEligibilityPolicy.Tests.ps1` → 2 passed; `HostCapabilitySnapshot.Tests.ps1` → 4 passed; `HostCapabilityAdapter.Tests.ps1` → 8 passed.

The planner contract reports `decision_owner=deterministic_planner`, `semantic_selection_applied=false`, `profile_filter_applied=false`, and `provider_calls=0`, `native_mutations=0`, `writes=0`. A passing plan requires `enabled_total == kept_total`, `omitted_total=0` and `truncated=false`; an overflow plan fails closed with explicit omission and offender evidence.

## Truth boundary and rollback

This is repository-verified only. P6 remains `planning_contract`; all-enabled native projection, profile/router/cold-load retirement, host loading, live acceptance and the full quality gate remain open or not run. The planner does not prove the host renderer's effective tokenization or native semantic selection.

To roll back this slice, remove `NativeMetadataPlanner.ps1`, `native-skill-metadata-policy.json`, its focused test and this evidence file; restore `SMV-P6-005` to pending in the manifest/plan/todo. Keep P6-004 catalog/policy seams, generated output, host configuration and unrelated concurrent watch-runtime changes unchanged.
