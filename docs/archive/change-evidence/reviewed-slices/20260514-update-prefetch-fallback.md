# 2026-05-14 update prefetch fallback hardening

## Rule / Scope
- Rule IDs: R2, R6, R8, E4
- Scope: `src/Commands/Update.ps1`, generated `skills.ps1`, and `tests/Unit/ConfigUpdate.Tests.ps1`
- Risk: low. Behavior-preserving for successful parallel prefetch; safer fallback for failed or timed-out prefetch.

## Basis
- Baseline gates showed `./build.ps1` succeeded in about 185ms, `./skills.ps1 发现` in about 3810ms, and `./skills.ps1 doctor --strict --threshold-ms 8000` in about 4484ms.
- Review found `更新` passed `-SkipFetch` based on whether parallel prefetch was attempted, not whether it succeeded.
- If parallel prefetch partially failed, per-source update paths could skip fetch and continue from stale local refs.
- Follow-up review found `Invoke-ParallelGitPrefetch` waited for background jobs without a timeout boundary.
- Follow-up simplification review found duplicated import archive/snapshot fallback blocks and unit tests that performed real `git ls-remote` calls.

## Change
- `更新` now passes `-SkipFetch:$prefetchOk` to `更新Imports` and `更新Vendor`.
- `Invoke-ParallelGitPrefetch` now reads `SKILLS_UPDATE_PREFETCH_TIMEOUT_SECONDS` with bounds `1..1800`, stops/removes timed-out jobs by job id, and returns failure so the normal per-source update path can continue.
- `更新Imports` now uses `Invoke-ImportArchiveFallback` for the two import archive/snapshot fallback branches while preserving existing messages and failure text.
- `ConfigUpdate.Tests.ps1` now mocks remote commit resolution in import fallback tests, avoiding real network calls in those unit cases.
- Added regression coverage for both branches:
  - failed prefetch falls back to per-source fetch.
  - successful prefetch still skips redundant per-source fetch.
  - timed-out prefetch jobs are cleaned up and do not call `Receive-Job`.
  - failed `git archive` fallback continues through GitHub tree snapshot fallback.

## Verification
- `./build.ps1`: pass, about 700ms after the final change.
- `./skills.ps1 发现`: pass, about 2200ms after the final change.
- `./skills.ps1 doctor --strict --threshold-ms 8000`: pass, about 2500ms after the final change.
- `./skills.ps1 构建生效`: pass, about 4400ms after the final change.
- `Invoke-Pester -Script tests\Unit\ConfigUpdate.Tests.ps1 -PassThru`: pass, 37 passed, 0 failed, about 7.82s after removing real remote lookups from import fallback unit tests.
- `./tests/check-generated-sync.ps1 -AllowDirtyWorktree`: pass.
- `./tests/run.ps1`: pass, Unit 369 passed / 0 failed; E2E 11 passed / 0 failed.
- `git diff --check`: pass, with Git line-ending warnings only.

## Rollback
- Revert this evidence file, the `src/Commands/Update.ps1` `-SkipFetch` argument change, the prefetch timeout helper/job-id cleanup changes, the import archive fallback helper, the generated `skills.ps1` change, and the added/adjusted tests in `tests/Unit/ConfigUpdate.Tests.ps1`.
