# vX.Y.Z - YYYY-MM-DD

## TL;DR
- <user-facing value 1>
- <user-facing value 2>
- <user-facing value 3>

## Added
- <new capability>

## Improved
- <upgrade>

## Fixed
- <bug fix>

## Try it now
- <shortest validation command>
- <sample input or demo>
- <expected signal>

## Breaking Changes
- <none or scope>

## Upgrade Guide
1. <step 1>
2. <step 2>
3. <verification>

## Compatibility
- Runtime: PowerShell 7 (`pwsh`) only; minimum 7.0, current LTS recommended. Windows PowerShell 5.1 is unsupported.
- Migration: replace `powershell.exe` invocations with `pwsh -NoProfile -ExecutionPolicy Bypass`; entry points fail closed when `pwsh` is missing.
- Boundary: this shell-runtime policy does not imply typed-core production integration or downstream live acceptance.

## Rollback
- Restore the last verified release and PowerShell 7 runtime; do not re-enable a hidden Windows PowerShell 5.1 fallback.

## Full Changelog
- <compare link>
