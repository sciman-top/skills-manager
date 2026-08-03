# 20260424 mcp timeout and doctor diagnostics

## Scope
- Rule: R2 small closure, R6 hard gate, R8 traceability.
- Risk: low.
- Landing: `src/Commands/Mcp.ps1`, `src/Commands/Doctor.ps1`, generated `skills.ps1`, focused tests, user-level Codex shim.
- Target: fix external-command argument propagation and timeout diagnostics; improve doctor OS detection when CIM is unavailable.

## Changes
- Replaced the timeout wrapper's `$args` parameter with `CommandArgs` plus `Alias("args")`, preserving the public `-args` call shape while avoiding PowerShell automatic-variable collision.
- Timeout handling now attempts process-tree kill where supported, waits briefly, returns captured stdout/stderr, and disposes the `Process` object.
- `doctor` now falls back to `[System.Runtime.InteropServices.RuntimeInformation]` when `Get-CimInstance Win32_OperatingSystem` fails.
- User-level `codex` shims now bypass the npm Node wrapper and call the installed native `codex.exe` directly because the host Node runtime crashes in `ncrypto::CSPRNG` before command handling.

## Evidence
- `codex --version`, `codex --help`, `codex status`
  - Initial result: failed before command handling with Node native assertion `Assertion failed: ncrypto::CSPRNG(nullptr, 0)`.
  - Fix: patched `C:\Users\sciman\AppData\Roaming\npm\codex.ps1`, `codex.cmd`, and `codex` to call the native Codex binary directly.
  - Backups: `C:\Users\sciman\AppData\Roaming\npm\codex.ps1.bak-20260424-213847`, `codex.cmd.bak-20260424-213847`, `codex.bak-20260424-213847`.
  - Final result: `codex --version` passed with `codex-cli 0.124.0`; `codex --help` passed; `codex mcp list` passed.
  - `codex status`: `platform_na`; reason: non-interactive shell returns `Error: stdin is not a terminal`.
  - Expires: next npm Codex package reinstall/update or host Node crypto repair.
- `./build.ps1`
  - Result: passed; regenerated `skills.ps1`.
- `Invoke-ExternalCommandWithTimeout -command "cmd" -args @("/c", "echo wrapper-args-ok") -timeoutSeconds 5`
  - Result: `timed_out=false`, `exit_code=0`, output includes `wrapper-args-ok`.
- `Invoke-ExternalCommandWithTimeout "cmd" @("/c", "echo before-timeout && ping -n 4 127.0.0.1 >nul") ... 1`
  - Result: `timed_out=true`, `exit_code=124`, output includes `before-timeout`.
- `./skills.ps1 doctor --json`
  - Result: passed; `checks.os=Microsoft Windows 10.0.26200 X64`.
- `./skills.ps1 发现`
  - Result: passed; listed 96 skills.
- `./skills.ps1 doctor --strict --threshold-ms 8000`
  - Result: passed.
- `./skills.ps1 构建生效`
  - Result: passed; built 89 skills and refreshed configured junction targets.
- `scripts/quality/check-doctor-json.ps1 -SyncMcpThresholdMs 10000`
  - Result: passed.
- `scripts/quality/run-local-quality-gates.ps1 -AllowDirtyWorktree`
  - Result: passed.
- `./skills.ps1 doctor --strict --strict-perf --threshold-ms 8000`
  - Result: passed.
- `./tests/run.ps1`
  - Result: `gate_na`.
  - Reason: Pester module is not installed in this environment; PowerShell Gallery access is blocked by host service/provider failure (`无法加载或初始化请求的服务提供程序`) and PSResourceGet repository-store locking.
  - Alternative verification: focused manual function checks plus non-Pester quality gates above.
  - Expires: when Pester is installed on this host.

## Rollback
- Revert this commit or restore the previous implementations in `src/Commands/Mcp.ps1` and `src/Commands/Doctor.ps1`, then run `./build.ps1`.
- Restore user-level Codex shims from `C:\Users\sciman\AppData\Roaming\npm\codex*.bak-20260424-213847`, or reinstall the npm Codex package after host Node is repaired.
