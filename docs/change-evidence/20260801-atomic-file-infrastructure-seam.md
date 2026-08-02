# SMV-P0-005 atomic file Infrastructure seam evidence

**Date**: 2026-08-01
**Scope**: one bounded file-write seam and one direct production caller
**Runtime baseline**: PowerShell 7.6.3 primary; Windows PowerShell 5.1.26100.8972 bounded smoke

## Selection evidence

`Set-ContentUtf8` had more than 30 real source call sites spanning Config, Audit, MCP, SkillProjection, Install, Update and Doctor. Existing tests already characterized read-only and hidden-file behavior. This made UTF-8 atomic writing a proven shared concern without inventing a new abstraction for a single caller.

Rejected alternatives:

- JSON serialization: depth and validation semantics remain domain-specific; extracting them now would create a generic nullable helper.
- File hashing: already small, stable and independently used; moving it would add directory churn without reducing current risk.
- Broad filesystem adapter/DI: explicitly out of scope and unsupported by current caller needs.

## Changes

- Added `src/Infrastructure/AtomicFile.ps1` with `Write-Utf8FileAtomic` and its private attribute-reset helper.
- Kept `Set-ContentUtf8([string]$path, [string]$content)` as the legacy public/internal compatibility wrapper, including DryRun suppression.
- Migrated only `SaveCfg` to call `Write-Utf8FileAtomic` directly. `SaveCfgSafe`, lock, Audit, MCP, SkillProjection and other callers remain on the wrapper.
- Added the Infrastructure source before Core in the generated build order.
- Removed the now-unused Core attribute-reset implementation.

## Behavior and failure boundary

- UTF-8 remains no-BOM and nested parent directories are created.
- ReadOnly/Hidden/System attributes are cleared before replacement, preserving current Windows behavior.
- Existing files use same-directory temp + `File.Replace`; new files use same-directory temp + `File.Move`.
- Retryable IO/access failures clean transaction artifacts and retry. Exhaustion throws while leaving the original file intact.
- The old final in-place `WriteAllBytes` fallback was intentionally removed because it could truncate an existing file after atomic replacement failed. Restricted hosts that deny atomic replacement now fail closed instead of risking partial persistence.

## Characterization and compatibility

| Command | Result |
| --- | --- |
| `pwsh ... build.ps1` | exit 0 |
| Pester: `InfrastructureSeam.Tests.ps1`, `SetContentUtf8.Tests.ps1`, `ConfigUpdate.Tests.ps1` | 53 passed, 0 failed |
| Windows PowerShell 5.1 bounded parse/write smoke | no-BOM bytes `70-73-35-31` |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1` | Unit 536/536; E2E 12/12 |
| planning/config/doctor/dependency/generated-sync contracts | all exit 0; planning 5 done/4 open/0 findings; config hash unchanged |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` | exit 0; full local quality gates passed |

Coverage proves helper/wrapper byte parity, Unicode/no-BOM output, nested paths, read-only/hidden overwrite, failure preservation/cleanup, direct caller wiring and legacy wrapper availability.

## N/A and truth boundary

| Classification | Reason | Alternative evidence | Recovery condition |
| --- | --- | --- | --- |
| `platform_na` host projection | This seam writes only paths supplied by existing repo/application callers; no host projection was executed. | Characterization, compatibility and full repository gates. | A later consumer task must run its own host probe. |
| `gate_na` live workflow | No CLI command shape or product workflow changed. | Existing Unit/E2E regression suite. | Run a real workflow when a command is migrated directly. |

This evidence closes only `SMV-P0-005` at repository implementation scope. It does not claim all writers migrated, host loading, live acceptance or Phase 0 completion. P0-006 through P0-009 remain open.

## Rollback

Restore the previous `Set-ContentUtf8` implementation in Core, return `SaveCfg` to the wrapper, remove `Infrastructure/AtomicFile.ps1` from the build list, remove this task's tests/evidence/status changes, and rebuild `skills.ps1`. Do not touch config data, audit reports, imports or unrelated worktree changes.
