# SMV-P6-003 Host Capability Adapter Evidence

**task**: `SMV-P6-003`
**task_truth_level**: `repo_verified`
**phase_truth_level**: `planning_contract`
**runtime_migration**: `not_started`
**host_loaded**: `not_run`
**live_accepted**: `not_run`
**full_gate**: `not_passed`
**provider_calls**: `0`
**host_writes**: `0`

## Scope and write-set

This slice implements the official-first read-only adapter seam for the frozen `HostCapabilitySnapshot` schema. The exact implementation set is:

- `src/Infrastructure/HostCapabilityAdapters.ps1`
- `scripts/get-codex-app-server-capability-snapshot.ps1`
- `tests/Unit/HostCapabilityAdapter.Tests.ps1`
- `docs/change-evidence/20260807-p6-host-capability-adapters.md`

The adapter has three input paths:

- `app_server`: bounded `config/read`, `model/list`, `modelProvider/capabilities/read` and `skills/list` responses are mapped to the common snapshot. Missing methods and RPC errors remain `partial`/unknown; error diagnostics are redacted.
- `cli`: a fresh `codex debug prompt-input` capture is parsed for actual message/content/text skill metadata. Missing model, context and budget facts remain `unknown_fallback`; unavailable launchers are represented as `platform_na`.
- `offline_config`: selected scalar values are read from explicit config text/path. The top-level `source=config_fallback` remains visible while capability facts use only the legal `config_layered` source, so raw config is never promoted to current runtime truth.

All outputs carry the same schema version and adapter envelope (`adapter`, `source`, `status`, `coverage`, `errors`, `read_only`, `provider_calls`, `writes`, `native_mutations`). The validator rejects non-zero side-effect counters, illegal source labels, fallback fact promotion and unredacted sensitive values. Explicit `-OutputPath` is only report serialization; it does not change the adapter's host/provider counters.

No thread mutation, host restart, skill injection, provider call, auth/model/profile change or live configuration write was performed. Existing watch-runtime and unrelated dirty-worktree changes remain outside this slice.

## Red-green and verification evidence

- RED: `HostCapabilityAdapter.Tests.ps1` initially failed because the App Server adapter command did not exist; subsequent RED cases covered missing/partial RPC data, CLI `platform_na`, fresh prompt-input metadata, config fallback labeling/redaction, shared zero-side-effect validation and redacted RPC diagnostics.
- GREEN: `pwsh -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Path 'tests/Unit/HostCapabilityAdapter.Tests.ps1'"` → 8 passed, 0 failed.
- SNAPSHOT REGRESSION: `pwsh -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Path 'tests/Unit/HostCapabilitySnapshot.Tests.ps1'"` → 4 passed, 0 failed.
- BUILD: `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` → exit 0, `Build success`.
- NATIVE PROBE: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/get-codex-app-server-capability-snapshot.ps1 -Mode cli -TimeoutSeconds 30` → exit 0; `schema_version=1`, `adapter=cli`, `source=cli`, `status=partial`, 23 parsed skill metadata entries, `error_count=0`, `provider_calls=0`, `writes=0`, `platform_na=false`. The local npm `codex.ps1` shim was used through PS7 after the WindowsApps `codex.exe` launcher returned access denied.
- DIFF CHECK: `git diff --check` → exit 0; only existing Windows LF/CRLF normalization warnings were reported.

The native probe is `host_evaluation_partial`: it proves a bounded CLI snapshot path and metadata observation only. It does not prove `host_loaded`, native semantic selection, full skill-body injection, provider connectivity or business/live acceptance.

## Truth boundary and rollback

This slice is repository-verified only. P6 remains `planning_contract`; runtime migration, profile/router/cold-load retirement, `host_loaded`, `live_accepted` and the full quality gate remain open/not run. To roll back this slice, remove the new adapter module/test/evidence and restore the prior read-only snapshot script; then restore the P6-003 manifest/plan/todo bookkeeping to pending. Do not touch unrelated watch-runtime changes, P6-001/P6-002 evidence or host-local configuration.
