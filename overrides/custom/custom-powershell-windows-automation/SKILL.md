---
name: custom-powershell-windows-automation
description: Use when writing or repairing PowerShell 7 automation on Windows for local agent tooling, scheduled tasks, startup wrappers, file sync, MCP config, git helpers, or safe system maintenance. Treat Windows PowerShell 5.1 as an explicit external legacy constraint, never an implicit default.
---

# PowerShell 7 Windows Automation

Use this skill for durable Windows automation rather than one-off shell snippets.

## Rules

1. Prefer native PowerShell cmdlets end-to-end for file operations.
2. Before recursive move/delete, resolve and verify the absolute target path.
3. Use `-LiteralPath` for filesystem paths, especially Chinese paths and paths with spaces.
4. Keep generated config writes idempotent and backup-aware.
5. For scheduled tasks or startup helpers, use hidden wrappers when visible consoles would disturb the desktop.
6. Use `pwsh` and PowerShell 7 syntax by default. Do not add a `powershell.exe` fallback unless the user explicitly asks to maintain an external Windows PowerShell 5.1 consumer.
7. Invoke native tools directly when ordinary argument passing is sufficient. Check `$LASTEXITCODE` immediately; stderr alone is not failure. Use `Start-Process` only when the workflow needs process-level control such as a hidden window, redirected streams, credentials, or a different working directory, and use `-Wait -PassThru` when the exit code is evidence.

## Patterns

- Use structured JSON/TOML/CSV parsing instead of text replacement when practical.
- For environment variables, distinguish Process/User/Machine scopes in logs.
- For CLIs, capture `cmd`, `exit_code`, short key output, and timestamp.
- For agent/MCP config, separate source of truth from generated projection files.
- For file replacement, write and validate the candidate before an atomic replace when the target format or consumer makes partial writes risky.

## Verification

- Run a dry-run path first when available.
- Re-run the command after writes to prove idempotence.
- Check encoding, path, native-process exit, and locked-file behavior under the supported PowerShell 7 runtime.
- When an explicitly scoped external legacy consumer requires Windows PowerShell 5.1, isolate that compatibility path and verify it separately; do not weaken the primary PS7 contract.
- Report changed paths, backup/rollback location, commands run, and the lowest truth layer actually verified. A successful source edit or scheduled-task definition is not proof that a new process or future trigger loaded it.
