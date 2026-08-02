# PowerShell runtime compatibility contract

**Contract version**: 1
**Effective date**: 2026-08-01
**Owner**: skills-manager maintainers

## Support levels

| Level | Runtime | Required coverage | Blocking meaning |
| --- | --- | --- | --- |
| Primary | PowerShell 7 (`pwsh`) | build, generated sync, full Pester, contracts, doctor, dependency and full quality gates | Release/repository changes are blocked on failure |
| Bootstrap fallback | Windows PowerShell 5.1 (`powershell.exe`) | `install.ps1` may select it only when `pwsh` is unavailable | Keeps existing Windows bootstrap usable; does not make 5.1 the development runtime |
| Compatibility smoke | Windows PowerShell 5.1 | parse generated `skills.ps1`; construct plain OperationPlan/Receipt objects; exercise atomic UTF-8 helper and selected fixture scripts | Blocks known syntax/basic-contract regressions when 5.1 is available; does not promise every workflow or provider path |

Current host evidence on 2026-08-01: PowerShell `7.6.3` primary and Windows PowerShell `5.1.26100.8972` compatibility runtime.

## Engineering rules

- New source must pass the PowerShell 7 full path. PS5.1 compatibility must not permanently constrain primary-path improvements that can be isolated behind a small adapter or fallback.
- A PS7-only API is allowed only when the caller has an explicit runtime guard, a tested 5.1 fallback, or a clear fail-closed message for a primary-only operation.
- `src/Version.ps1` keeps `#requires -Version 5.1` during this compatibility window. Generated `skills.ps1` preserves the current UTF-8 BOM release encoding and remains parseable by both runtimes; runtime-managed data writers keep their separately tested atomic UTF-8 contract.
- CI uses `pwsh` for authoritative gates. Windows PowerShell runs only the bounded smoke and must not be described as full support.
- Missing `powershell.exe` is `platform_na` outside Windows: record the missing executable, use PS7 parse/contract tests as alternative evidence, and recover when a Windows runner is available.

## Compatibility removal gate

Do not remove the 5.1 fallback, raise `#requires`, or use incompatible syntax across the generated bundle until all conditions are met:

1. At least one versioned usage observation shows no required 5.1-only installation path, or an approved migration identifies affected users and machines.
2. Release notes announce the change and provide an upgrade path to supported PowerShell 7.
3. `install.ps1`, CI, README, portable packaging, scheduled-task behavior and generated-script encoding are migrated in one reviewed change.
4. A release candidate passes the PS7 full gate and migration tests; rollback is documented.
5. The task/ADR explicitly records owner, decision date, evidence links and the first release that drops compatibility.

Until then, 5.1 is a bounded compatibility window, not a deprecated path that may silently rot and not a second full test matrix.

## Local verification

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[void][scriptblock]::Create((Get-Content -Raw .\skills.ps1)); 'parse-ok'"
```

Repository verification proves only `repo_verified`. It does not prove a new shell session loaded changed files or that a live MCP/skill workflow was accepted.
