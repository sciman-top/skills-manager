# sparse-checkout warning cleanup

## Scope
- Rule IDs: R3, R6, R8, E4
- Risk: low
- Target: managed vendor/import git caches used by `更新` and `weekly-auto-update.ps1`

## Root Cause
On Windows, `git sparse-checkout init/set` can emit exit-code-0 warnings such as `warning: failed to remove directory ...` when old sparse-excluded directory shells retain Windows attributes such as `ReadOnly`/`Pinned`. The update itself succeeds, but the warnings make scheduled update output look unhealthy.

## Changes
- Route sparse checkout setup through `Set-GitSparseCheckout`.
- Pre-prune tracked paths outside the next sparse set when safe.
- Capture `sparse-checkout init/set` output, suppress only repairable `failed to remove directory` warnings, and immediately remove the verified in-repo paths with PowerShell `Remove-Item -LiteralPath -Recurse -Force`.
- Keep `sparse-checkout disable` as the no-sparse fallback path.

## Verification
- `./build.ps1`: passed.
- `Invoke-Pester -Path ./tests/Unit/GitLockRecovery.Tests.ps1`: 14 passed, 0 failed.
- `Invoke-Pester -Path ./tests/Unit/ConfigUpdate.Tests.ps1`: 41 passed, 0 failed.
- Forced `./scripts/weekly-auto-update.ps1` full update path with a temporary ignored cache residue: exit code 0.
- Log keyword check after forced update: `warning: failed to remove directory=0`, `fatal:=0`, `❌=0`, `CONFLICT=0`, `refusing=0`.
- MCP sync during forced update: `claude` and `codex` config-state checks passed.
- `./skills.ps1 发现`: 102 skills listed.
- `./skills.ps1 doctor --strict --threshold-ms 8000`: passed.
- `./skills.ps1 构建生效`: passed.

## Rollback
- Revert `src/Git.ps1`, `src/Commands/Update.ps1`, `src/Config.ps1`, rebuilt `skills.ps1`, and the related unit tests.
- Run `./build.ps1`, `./skills.ps1 发现`, `./skills.ps1 doctor --strict --threshold-ms 8000`, and `./skills.ps1 构建生效` after rollback.
