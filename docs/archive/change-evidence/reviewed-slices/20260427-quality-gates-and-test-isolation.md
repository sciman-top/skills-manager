# 20260427-quality-gates-and-test-isolation

## Scope
- landing: tests and quality gates
- target: keep audit dry-run tests isolated and make repository hygiene part of reusable local and GitHub CI gates
- risk: low
- rule_ids: R2, R6, R8, E4

## Baseline
- `.\build.ps1` -> exit 0, `Build success: D:\CODE\skills-manager\skills.ps1`
- `.\skills.ps1 发现` -> exit 0, 91 skills listed
- `.\skills.ps1 doctor --strict --threshold-ms 8000` -> exit 0, `Your system is ready for skills-manager.`
- `.\skills.ps1 构建生效` -> exit 0, 91 skills built and linked
- `.\tests\run.ps1` -> exit 0, Unit `317 passed`, E2E `11 passed`

## Changes
- `tests/Unit/AuditTargets.Tests.ps1`: isolate the dry-run acknowledgement test under `$TestDrive` by overriding `$script:Root` for that case, and assert runtime evidence is written under the test workspace.
- `scripts/quality/run-local-quality-gates.ps1`: add `repo-hygiene` after `build` so the reusable local gate runs the existing hygiene checker.
- `.github/workflows/ci.yml`: add `Check repository hygiene` before generated script sync.
- `tests/Unit/QualityGateScripts.Tests.ps1`: add drift tests for the reusable gate and GitHub CI hygiene step.
- `scripts/quality/check-repo-hygiene.ps1`: add non-blocking untracked runtime artifact reporting via `-ReportUntrackedRuntimeArtifacts`, with explicit `-FailOnUntrackedRuntimeArtifacts` for stricter local checks.

## Verification
- `Invoke-Pester -Script @('tests\Unit\AuditTargets.Tests.ps1','tests\Unit\QualityGateScripts.Tests.ps1')` -> exit 0, `70 passed`
- `Invoke-Pester -Script tests\Unit\QualityGateScripts.Tests.ps1` -> exit 0, `4 passed`
- `.\scripts\quality\check-repo-hygiene.ps1 -ReportUntrackedRuntimeArtifacts` -> exit 0, repository hygiene passed
- `.\scripts\quality\run-local-quality-gates.ps1 -Profile quick -AllowDirtyWorktree` -> exit 0, build, repo-hygiene, generated-sync, dependency-baseline, doctor-json-contract passed
- `.\tests\run.ps1` -> exit 0, Unit `321 passed`, E2E `11 passed`
- `.\build.ps1` -> exit 0
- `.\skills.ps1 发现` -> exit 0
- `.\skills.ps1 doctor --strict --threshold-ms 8000` -> exit 0
- `.\skills.ps1 构建生效` -> exit 0
- `git diff --check` -> exit 0; only existing line-ending normalization warnings were printed

## Rollback
- Revert:
  - `.github/workflows/ci.yml`
  - `scripts/quality/run-local-quality-gates.ps1`
  - `tests/Unit/AuditTargets.Tests.ps1`
  - `tests/Unit/QualityGateScripts.Tests.ps1`
  - `docs/change-evidence/20260427-quality-gates-and-test-isolation.md`

## N/A
- platform_na: none
- gate_na: none
