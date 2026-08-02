# Phase 2 fixture CLI and MCP receipt evidence

- Task: `SMV-P2-006`.
- `rule-plan` and `rule-apply` expose one compressed JSON envelope through the generated `skills.ps1` entry point.
- All rule transaction writes require a marked fixture root; target, desired, plan, and output paths are bounded and report output cannot overwrite an input or target.
- Apply requires `APPLY_RULE_PATCH`; wrong token, stale content, semantic source, missing marker, and boundary violations fail closed.
- MCP planning now projects a valid `dry_run` receipt whose actions and repo/host/live verification remain `not_run`; it performs no native mutation.
- PowerShell 7 build and targeted unit/E2E verification are required before task closeout.
