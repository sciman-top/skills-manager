# Windows Process Environment Recovery

This runbook covers Windows entrypoints that depend on `Python`, `Node`, `Codex`, or child `PowerShell` processes.

## Symptoms

- `node -e` or `codex --version` fails only inside a wrapper process.
- `codex exec` fails with DNS errors such as `os error 11003` unless `HTTP_PROXY` / `HTTPS_PROXY` are set explicitly.
- `Get-Command codex -All` resolves to npm shims, but the native binary is fine.
- Child processes fail because common Windows process variables are missing or incomplete.

## Recovery

1. Dot-source `Initialize-WindowsProcessEnvironment.ps1`.
2. Run `Initialize-WindowsProcessEnvironment`.
3. If a local proxy is configured in Codex `shell_environment_policy.set` or User/Machine environment, the initializer imports only safe proxy variables such as `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, and `NO_PROXY`; it does not import tokens.
4. Re-run the target entrypoint.
5. If the process still fails, verify the same probe in a fresh elevated PowerShell before changing system networking or crypto settings.

## Verification

Use the same probes that the profile records:

```powershell
python -c "import asyncio; print('asyncio ok')"
node -e "console.log('node ok')"
'HTTP_PROXY=' + $env:HTTP_PROXY
'HTTPS_PROXY=' + $env:HTTPS_PROXY
'NO_PROXY=' + $env:NO_PROXY
```

## Notes

- Prefer process-local repair before host-level repair.
- Prefer `codex`, `codex.cmd`, or a configurable Codex command path. Do not hard-code the exact `.exe` executable name unless that file exists on the target machine.
- Only treat Winsock or IP reset as a later step after the probes fail in a clean elevated shell.
