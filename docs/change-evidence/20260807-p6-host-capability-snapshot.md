# SMV-P6-002 HostCapabilitySnapshot Contract Evidence

**task**: `SMV-P6-002`
**task_truth_level**: `repo_verified`
**phase_truth_level**: `planning_contract`
**runtime_migration**: `not_started`
**host_loaded**: `not_run`
**live_accepted**: `not_run`
**full_gate**: `not_passed`
**provider_calls**: `0`
**host_writes**: `0`

## Scope and write-set

This slice adds only the pure `HostCapabilitySnapshot` plain-object contract, the deterministic source-precedence resolver, its focused Pester tests, and this evidence. It does not modify the existing static host-capability matrix, generated bundle, host configuration, provider/auth/model state or live session.

The resolved source order is fixed per field:

```text
turn_override -> thread_runtime -> config_layered -> model_catalog -> unknown_fallback
```

Each fact carries `source`, `captured_at`, `freshness` and `unknown_reason`. A stale higher-precedence value remains selected and visibly stale; an unavailable or invalid value falls through without being promoted to current runtime truth.

## Red-green evidence

- RED: `HostCapabilitySnapshot.Tests.ps1` initially failed 1/1 because `Resolve-HostCapabilitySnapshot` was not yet present; after adding the null-source guard, the focused suite exercised the missing-source branch without parameter-binding errors.
- GREEN: `pwsh -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Path 'tests/Unit/HostCapabilitySnapshot.Tests.ps1'"` → 4 passed, 0 failed.
- BUILD: `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` → exit 0, `Build success`.

The focused cases cover turn-over-thread precedence, thread-over-config precedence, conservative unknown context with an explicit fallback reason, and stale higher-precedence source observability.

## Truth boundary and rollback

This is a repository contract only. It does not prove host loading, native skill selection, full `SKILL.md` injection, provider connectivity or business acceptance. Remove the two source modules, focused test and this evidence to roll back this slice; do not touch unrelated watch-runtime changes or the existing host-capability matrix.
