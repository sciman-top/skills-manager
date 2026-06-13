# Contributing

## Scope

- Issues: bugs, feature requests, workflow friction, documentation drift
- Pull requests: code, tests, docs, gates, release tooling, and evidence updates

## Development Loop

1. Edit the real source of truth for the change.
2. Regenerate derived artifacts when needed.
3. Run verification in the documented order.
4. Update docs and evidence for any user-visible, workflow-visible, or contract-visible change.

## Source of Truth Rules

- Edit `src/` for script behavior, then run `./build.ps1` to regenerate `skills.ps1`.
- Edit `skills.json` for source libraries, mappings, targets, sync mode, and MCP inventory.
- Put local customizations in `overrides/`; do not patch `vendor/` or generated `agent/` output directly.
- Treat `reports/skill-audit/<run-id>/ai-brief.md` and `outer-ai-prompt.md` as runtime artifacts. If the default audit prompt must change, update `src/Commands/AuditTargets.ps1` or `overrides/audit-outer-ai-prompt.md`.

## Required Verification

Run the project hard gates in this exact order:

```powershell
./build.ps1
./skills.ps1 发现
./skills.ps1 doctor --strict --threshold-ms 8000
./skills.ps1 构建生效
```

Additional quality gates are available when you need local/CI parity:

```powershell
./scripts/quality/run-local-quality-gates.ps1 -Profile quick
./scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree
```

Profiles:

- `quick`: `build -> repo-hygiene -> generated-sync -> dependency-baseline -> doctor-json-contract`
- `full`: `quick + tests`

## Documentation and Evidence Expectations

- Update `README.md` and `README.en.md` whenever command surface, boundaries, install flow, release flow, or hygiene rules change.
- Add or update a `docs/change-evidence/YYYYMMDD-topic.md` entry when the change affects workflow, contracts, release packaging, governance, or user guidance.
- Keep examples aligned with actual help output and current scripts.

## PR Checklist

- Explain the user or operator problem being solved.
- Summarize the smallest intended scope of the change.
- Include the verification commands you actually ran and the result.
- Mention docs, migration, release, or MCP behavior changes when relevant.
- Call out any N/A gates or skipped verification explicitly, with reason and fallback evidence.

## Scope Discipline

- Do not edit generated `skills.ps1` or `agent/` output by hand.
- Do not commit local agent state, logs, caches, or temporary artifacts.
- Root `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` are tracked project documents; host-local copies and imported temporary rule snapshots are not.
- Keep changes focused. Separate behavior changes, refactors, and doc-only cleanup when possible.
