# P6-010 Profile Reachability Retirement Evidence

**date**: `2026-08-07`
**task**: `SMV-P6-010`
**task_status**: `repo_verified`
**truth_level**: `planning_contract`
**runtime_migration**: `not_started`
**host_loaded**: `not_run`
**live_accepted**: `not_run`
**full_gate**: `not_passed`

## Scope and write-set

This slice migrates the repository configuration contract only. The legacy
`skill_projection.active_profile` and `skill_projection.profiles` fields are
removed from the active projection input and preserved under a versioned,
read-only `ProfileCompatibilityView`. The view is migration/reporting data and
has no reachability authority. `New-SkillProjectionPlan` therefore sees all
enabled canonical skills after migration instead of treating profile membership
as a filter.

The implementation write-set is:

- `skills.json`
- `src/Application/SkillProfileReconciliation.ps1`
- `scripts/plan-skill-profile-reconciliation.ps1`
- `scripts/manage-skill-profile-reconciliation.ps1`
- `tests/Unit/SkillProfileReconciliation.Tests.ps1`
- `tests/Unit/SkillProfileOptimization.Tests.ps1`
- generated `skills.ps1` through `build.ps1`
- this evidence file

The concurrent watch-runtime `resident_names` change and existing native
projection configuration in `skills.json` were retained. No host config,
session, provider, model or profile switch was performed.

## Contract

`ProfileCompatibilityView` uses `schema_version=1`,
`status=read_only`, `reachability_authority=none`, and preserves the legacy
`active_profile` value and profile membership order. The migration plan is
zero-write and emits a deterministic operation id, target hash and rollback
receipt shape. Explicit `MIGRATE_SKILL_PROFILE_CONFIG` writes only the repository
config plus a local backup/receipt; explicit
`ROLLBACK_SKILL_PROFILE_CONFIG` restores the original bytes after a hash/CAS
check. Legacy profile canary `Apply`/`Accept` manager modes now return
`profile_reconciliation_retired` with `writes_performed=0`.

## Red-green evidence

The first focused run added five tests and failed with missing production
commands (`Get-SkillProfileCompatibilityView`, `New-SkillProfileMigrationPlan`
and `Invoke-SkillProfileMigration`). Subsequent focused RED runs caught the
standalone script contract, profile-order preservation and deprecated canary
mode before the minimal implementation was adjusted. The final focused
sequence was:

```text
pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Path 'tests/Unit/SkillProfileReconciliation.Tests.ps1','tests/Unit/SkillProfileOptimization.Tests.ps1'"
```

Result: `16 passed, 0 failed`.

The tests cover legacy read compatibility, the read-only view, all-enabled
reachability after migration, active-profile preservation, provider/host
zero-side-effect planning, atomic migration, receipt creation, exact rollback,
standalone planner/manager contracts, and deprecated canary blocking.

## Real migration receipt

The ignored receipt
`reports/skill-profile-reconciliation/20260807-p6-010-migration-receipt-v2.json`
records:

- `operation_id=profile-migration-97f8b40e6678825c`
- `status=migrated`, `legacy_profile_count=16`
- `active_profile=default` before and after migration
- `before_config_sha256=1e5b5cb70b27c444e4df5536632013cfc630409fe48c44a0bd9db857694c1f33`
- `after_config_sha256=63d7946547628925aa59a1d41c34ff955d658c4d137ecd4e5ae228bb394730a6`
- backup exists and rollback is available
- `host_mutation=false`, `provider_calls=0`, `native_mutations=0`, `writes=1`

The first trial migration was explicitly rolled back before this final receipt
was produced, after a RED test identified unnecessary membership sorting.

## Verification and remaining boundary

- `build.ps1`: exit 0, `Build success`.
- P6-010 focused Pester: `16/16` passed.
- `scripts/verify-skills-config.ps1 -Mode enforce -NoExit`: `valid=true`, `pass=true`, `finding_count=0`, input hash unchanged.
- `git diff --check` for the P6-010 files: no content errors; only the repository's existing LF/CRLF normalization warnings.
- The legacy `SkillProjection.Tests.ps1` profile-policy context remains a P6-012 consumer: its three historical assertions still read removed direct profile fields and fail, while the unaffected projection tests and all `SkillProfileReconciliationTransaction.Tests.ps1` tests pass. This is recorded as a staged-removal boundary, not converted into a P6-010 full-gate claim.
- The full quality gate was not run. P6-011 remains pending; P6-012 owns legacy routing-verifier/test removal, fresh host acceptance and the unique full gate.

## Rollback

Use the final receipt with `-Mode RollbackMigration` and token
`ROLLBACK_SKILL_PROFILE_CONFIG`. The rollback verifies receipt identity, target
hash and backup hash before restoring the original `skills.json` bytes. It does
not touch host state or historical P5/P6 evidence.
