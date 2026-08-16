# PowerShell runtime contract

**Contract version**: 2
**Status**: `PS7_ONLY_STATUS: repo_verified`
**Effective date**: 2026-08-05
**Owner**: skills-manager maintainers

## Support boundary

`skills-manager` is a Windows-first project whose supported runtime is PowerShell 7 (`pwsh`) only.
Windows PowerShell 5.1 is not supported by this project.

| Runtime | Project status | Required evidence |
| --- | --- | --- |
| PowerShell 7.0+ (`pwsh`, PowerShell 7.6 LTS recommended) | Supported | build, generated sync, Pester/E2E and risk-triggered quality gates |
| Windows PowerShell 5.1 (`powershell.exe`) | Not supported | no CI job, no installer fallback, no compatibility smoke, and no supported execution path |

This is a project support decision, not a claim that Microsoft has stopped supporting Windows PowerShell 5.1. Microsoft documents 5.1 as a Windows support channel, while PowerShell 7 follows the .NET support lifecycle. The project chooses one supported runtime to reduce parser, quoting, encoding, process-invocation, and AI-generated-script variability.

The current validated release family is PowerShell 7.6 LTS. Patch versions are not hard-coded in the repository; operators should use the latest supported patch for their platform. The official lifecycle currently lists PowerShell 7.6 LTS through 14-Nov-2028 and PowerShell 7.4 LTS through 10-Nov-2026.

## Migration guide

1. Install PowerShell 7 from [Microsoft's PowerShell installation guide](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows) or `winget install --id Microsoft.PowerShell --source winget`.
2. Open a new terminal and verify `pwsh --version` reports PowerShell 7 or later.
3. Run the repository entry point explicitly with `pwsh`:

   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Mode CurrentUser
   ```

4. For portable use, run `skills.cmd`; it resolves only `pwsh.exe` and fails with an actionable installation message when PowerShell 7 is absent.
5. If a downstream automation invokes `powershell.exe`, change it to `pwsh -NoProfile -ExecutionPolicy Bypass -File ...`. Do not restore a legacy fallback or set `CODEX_ALLOW_WINDOWS_POWERSHELL`.

The official migration guidance remains useful for users who need to move other scripts from 5.1 to 7; this repository does not promise that every external script is automatically portable.

## Engineering rules

- `src/Version.ps1`, `build.ps1`, and `install.ps1` require PowerShell 7.0 or later.
- `src/Core.ps1` and generated `skills.ps1` resolve only `pwsh`; missing PowerShell 7 fails closed with a clear message.
- The MCP environment wrapper uses `pwsh.exe` on Windows. Generic discovery of `powershell` commands in target-repository audit text is observation of external input, not a supported project runtime.
- CI and Azure Pipelines use `pwsh` only. There is no Windows PowerShell job or bounded 5.1 smoke.
- The generated bundle keeps a deterministic UTF-8 BOM for Windows file detection. This is a release-encoding choice, not a 5.1 compatibility promise.
- Pester fixtures and contract tests execute under PowerShell 7; tests must not silently skip because `powershell.exe` is absent.
- PowerShell remains the current CLI/host adapter truth. The typed-core PoC remains shadow-only and does not expand this runtime decision into a production rewrite.

## Rollback and support handling

The migration is reversible at the repository/release level, not by keeping a hidden 5.1 execution path:

1. If a PS7 release regression is found, stop rollout and revert the migration commit or publish the last known-good release.
2. Restore PowerShell 7 on the operator machine; do not run this repository under `powershell.exe` as a workaround.
3. Fix the PS7 path, rerun the ordered gates, and publish a new release with a dated evidence record.
4. Reconsider 5.1 only through a new user-authorized product decision with measured consumer evidence; it must not reappear as an ad-hoc fallback.

## Verification

Select one proportional repository verification path. For an ordinary change:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1 -TestPath .\tests\Unit\CapabilityInventory.Tests.ps1
git diff --check
```

For runtime, packaging, public-contract, or cross-surface risk, freeze inputs and run the full gate once without pre-running its internal commands:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\quality\run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree
```

Repository verification proves `repo_verified`. It does not prove that a new shell session loaded changed files or that a live MCP/skill workflow was accepted.

## Official references

- [PowerShell Support Lifecycle](https://learn.microsoft.com/powershell/scripting/install/powershell-support-lifecycle?view=powershell-7.6) — Microsoft support policy and release dates.
- [Migrating from Windows PowerShell 5.1 to PowerShell 7](https://learn.microsoft.com/powershell/scripting/whats-new/migrating-from-windows-powershell-51-to-powershell-7?view=powershell-7.6) — side-by-side migration guidance.
- [What is Windows PowerShell?](https://learn.microsoft.com/powershell/scripting/what-is-windows-powershell?view=powershell-7.6) — distinction between Windows PowerShell 5.1 and PowerShell 7.
