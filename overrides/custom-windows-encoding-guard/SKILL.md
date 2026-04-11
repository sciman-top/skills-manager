---
name: custom-windows-encoding-guard
description: Use when running AI coding workflows on Windows PowerShell to prevent UTF-8/Chinese mojibake and repeated encoding mistakes.
---

1. Run `scripts/bootstrap.ps1` at session start to enforce UTF-8 input/output settings.
2. Before reading/writing text files, prefer explicit encoding flags such as `-Encoding UTF8`.
3. If output is still garbled, re-run `scripts/bootstrap.ps1 -AsJson` and check `compliant_after=true`.
4. Keep this skill focused on encoding guardrails. Do not mix with unrelated build/test logic.
