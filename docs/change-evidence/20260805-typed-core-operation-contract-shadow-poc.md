# Change Evidence — Typed-core Operation Contract TC0/TC1

## Result

- Track: `typed_core_shadow_poc`
- Seam: `operation_contract_validation_v1`
- TC0: `repo_verified`
- TC1: `repo_verified` (`shadow_only`)
- TC2: `not_started`
- PowerShell runtime: `authoritative`
- Production integration: `not_started`
- P6: `hold`
- Live acceptance: `not_run`

## Basis and disposition

- Repo truth: `OperationPlan.ps1`/`Receipt.ps1` are pure domain modules; current `OperationContracts.Tests.ps1` passed 10/10 before implementation.
- Real callers: MCP planning, MCP command validation and RulePatch receipt creation.
- Official basis: Microsoft Learn .NET release/support, `global.json`, System.Text.Json DOM and .NET deployment documentation. .NET 10 is LTS through November 2028.
- Source diagnosis: dotnet/dotnet `35b593bebfcba58f8e78298cef14c2761f5d86c6`, `InstallerBase.cs`; missing `PROCESSOR_ARCHITECTURE` caused workload info only to fail. Process-local normalization fixed the probe; no SDK reinstall or machine-level mutation was performed.
- Tool disposition: built-in .NET SDK/BCL `adopt`; external code graph/daemon/database/package framework `reject`; no open-source package installation was needed.

## Fixed corpus and protocol evidence

`scripts/verify-typed-core-shadow.ps1` reported:

- 4/4 fixtures with exact PowerShell/C# pass, finding fingerprint, exit and empty-stderr parity;
- invalid plan: 12 findings, exit 2;
- invalid receipt: 6 findings, exit 2;
- valid plan/receipt: 0 findings, exit 0;
- 4/4 invalid-request cases returned exit 64 with the expected structured code;
- typed-core planning verifier accepted the 3/3 current task set and failed closed on production-integration status drift, an injected `PackageReference`, and missing reviewed evidence;
- Release build: 0 warnings, 0 errors;
- no `PackageReference`; no production `src/**/*.ps1` typed-core reference.

Fixture hashes are frozen in the companion spec and runtime report. The ignored runtime receipt is `reports/typed-core/current.json`; it is supporting evidence, not a tracked production artifact.

## Publish observation

| Mode | File count | Total bytes | Median startup |
| --- | ---: | ---: | ---: |
| framework-dependent | 4 | 78,078 | 105 ms |
| self-contained | 192 | 80,429,942 | 122 ms |
| self-contained single-file | 2 | 73,590,949 | 112 ms |

The publish directories were temporary and deleted by the verifier. These single-machine numbers do not prove a production distribution choice. The 73–80 MB self-contained cost is a TC2 admission concern.

## Verification contract

- `build.ps1`
- affected Pester: Operation contracts, typed-core shadow, Lean planning and product planning
- `scripts/verify-typed-core-shadow.ps1`
- `scripts/verify-typed-core-pilot-planning.ps1`
- `scripts/verify-lean-ai-delivery-planning.ps1`
- unique closeout: `scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree`
- `git diff --check`, JSON parse and Git boundary

This evidence is valid as `repo_verified` only with the successful unique full-gate execution for the same final write set. It does not claim host loading, production invocation or live acceptance.

## Rollback

Delete/revert `typed-core/`, `global.json`, the two typed-core verifier/test files, this spec/manifest/evidence and their product/status references. No production PowerShell implementation or generated bundle needs restoration because TC1 never wired the typed core into runtime.
