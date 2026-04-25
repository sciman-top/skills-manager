# Windows Process Environment Recovery

This runbook covers Windows entrypoints that depend on `Python`, `Node`, `Codex`, or child `PowerShell` processes.

## Symptoms

- `node -e` or `codex --version` fails only inside a wrapper process.
- `Get-Command codex -All` resolves to npm shims, but the native binary is fine.
- Child processes fail because common Windows process variables are missing or incomplete.

## Recovery

1. Dot-source `Initialize-WindowsProcessEnvironment.ps1`.
2. Run `Initialize-WindowsProcessEnvironment`.
3. Re-run the target entrypoint.
4. If the process still fails, verify the same probe in a fresh elevated PowerShell before changing system networking or crypto settings.

## Verification

Use the same probes that the profile records:

```powershell
python -c "import asyncio; print('asyncio ok')"
node -e "console.log('node ok')"
```

## Notes

- Prefer process-local repair before host-level repair.
- Only treat Winsock or IP reset as a later step after the probes fail in a clean elevated shell.
