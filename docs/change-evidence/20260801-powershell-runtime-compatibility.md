# SMV-P0-008 PowerShell runtime compatibility evidence

**Date**: 2026-08-01
**Scope**: runtime support contract, CI projection and bounded local smoke
**Truth ceiling**: `repo_verified`; no host restart or live workflow acceptance

## Contract

- PowerShell 7 is the authoritative development, CI, build, test, doctor and full-gate runtime.
- Windows PowerShell 5.1 remains a bounded bootstrap fallback and compatibility smoke, not a second full runtime matrix.
- `install.ps1` already resolves `pwsh` before `powershell.exe`; this behavior is now locked by tests without changing installation semantics.
- `#requires -Version 5.1` remains. The generated bundle preserves its current UTF-8 BOM release encoding and parses in both runtimes.
- Compatibility removal requires usage/migration evidence, release notice, coordinated installer/CI/docs/packaging migration, release-candidate gates and a versioned owner/decision record.

## CI and local coverage

- GitHub Actions and Azure Pipelines explicitly require PowerShell 7 for authoritative gates.
- Both Windows CI definitions run a separate PowerShell 5.1 parse and OperationPlan/Receipt plain-object smoke.
- Local Pester verifies documentation, runtime ownership, installer selection order, generated encoding, PS7 parse and the available PS5.1 smoke.

## Current evidence

| Probe | Result |
| --- | --- |
| `pwsh --version` | `PowerShell 7.6.3` |
| `powershell.exe ... $PSVersionTable.PSVersion` | `5.1.26100.8972` |
| `tests/Unit/PowerShellCompatibility.Tests.ps1` | 6 passed, 0 failed |
| `tests/Unit/ProductPlanning.Tests.ps1` after evidence fixture update | 6 passed, 0 failed |
| direct Windows PowerShell generated-script parse | `parse-ok`, exit 0 |
| final full local quality gate | rerun in Phase 0 closeout evidence |

## N/A and boundary

- CI configuration was statically validated and exercised through contract tests locally; no remote CI run was triggered because commit/push is outside this task.
- The 5.1 smoke does not claim all skills, MCP providers, Git paths or scheduled tasks were executed under 5.1.
- No shell, Codex/Claude process, host config, authentication, provider or active profile was restarted or modified.

## Rollback

Remove the runtime runbook/tests/evidence and the two bounded CI steps, restore README/task status, and retain the pre-existing installer fallback and `#requires -Version 5.1`. Do not modify host PowerShell installations.
