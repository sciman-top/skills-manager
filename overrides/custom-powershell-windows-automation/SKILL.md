---
name: custom-powershell-windows-automation
description: Use when writing or repairing Windows PowerShell automation for local agent tooling, scheduled tasks, startup wrappers, file sync, MCP config, git helpers, or safe system maintenance.
---

# PowerShell Windows Automation

Use this skill for durable Windows automation rather than one-off shell snippets.

## Rules

1. Prefer native PowerShell cmdlets end-to-end for file operations.
2. Before recursive move/delete, resolve and verify the absolute target path.
3. Use `-LiteralPath` for filesystem paths, especially Chinese paths and paths with spaces.
4. Keep generated config writes idempotent and backup-aware.
5. For scheduled tasks or startup helpers, use hidden wrappers when visible consoles would disturb the desktop.

## Patterns

- Use structured JSON/TOML/CSV parsing instead of text replacement when practical.
- For environment variables, distinguish Process/User/Machine scopes in logs.
- For CLIs, capture `cmd`, `exit_code`, short key output, and timestamp.
- For agent/MCP config, separate source of truth from generated projection files.

## Verification

- Run a dry-run path first when available.
- Re-run the command after writes to prove idempotence.
- Check for encoding, path, and locked-file failures on Windows PowerShell 5.1 and modern PowerShell when relevant.
