# 2026-05-14 update prefetch fallback hardening

## Rule / Scope
- Rule IDs: R2, R6, R8, E4
- Scope: `src/Commands/Update.ps1`, generated `skills.ps1`, and `tests/Unit/ConfigUpdate.Tests.ps1`
- Risk: low. Behavior-preserving for successful parallel prefetch; safer fallback for failed prefetch.

## Basis
- Baseline gates showed `./build.ps1` succeeded in about 185ms, `./skills.ps1 发现` in about 3810ms, and `./skills.ps1 doctor --strict --threshold-ms 8000` in about 4484ms.
- Review found `更新` passed `-SkipFetch` based on whether parallel prefetch was attempted, not whether it succeeded.
- If parallel prefetch partially failed, per-source update paths could skip fetch and continue from stale local refs.

## Change
- `更新` now passes `-SkipFetch:$prefetchOk` to `更新Imports` and `更新Vendor`.
- Added regression coverage for both branches:
  - failed prefetch falls back to per-source fetch.
  - successful prefetch still skips redundant per-source fetch.

## Verification
- `./build.ps1`: pass, about 102ms after the change.
- `./skills.ps1 发现`: pass, about 1520ms after the change.
- `./skills.ps1 doctor --strict --threshold-ms 8000`: pass, about 1561ms after the change.
- `./skills.ps1 构建生效`: pass, about 4222ms after the change.
- `Invoke-Pester -Script tests\Unit\ConfigUpdate.Tests.ps1 -PassThru`: pass, 34 passed, 0 failed.
- `./tests/check-generated-sync.ps1 -AllowDirtyWorktree`: pass.
- `./tests/run.ps1`: pass, Unit 366 passed / 0 failed; E2E 11 passed / 0 failed.
- `git diff --check`: pass, with Git line-ending warnings only.

## Rollback
- Revert this evidence file, the `src/Commands/Update.ps1` `-SkipFetch` argument change, the generated `skills.ps1` change, and the two added tests in `tests/Unit/ConfigUpdate.Tests.ps1`.
