# Contributing

## Scope

Contributions may change code, tests, documentation, gates, release tooling, skills, MCP configuration, target audit, or rule audit. Keep one coherent user/operator outcome per change.

## Sources of truth

- Edit `src/`, then run `build.ps1` to regenerate `skills.ps1`.
- Edit `skills.json` for sources, mappings, targets, MCP, and projection.
- Put local skills in `overrides/{custom,patches,resources}`; do not patch `vendor/`, `imports/`, generated `agent/`, or runtime `reports/` directly.
- Change audit prompt defaults in `src/Commands/AuditTargets*.ps1` or `overrides/audit-outer-ai-prompt.md`, never in a generated run directory.

## Development loop

1. Freeze the intended behavior, exact write set, minimum verification, and stop condition.
2. Edit the real source and regenerate affected artifacts.
3. Run `git diff --check` plus the affected test or verifier.
4. Use a full gate only for runtime, security, data, migration, public-contract, dependency, packaging, release, or cross-surface risk.

```powershell
pwsh -NoProfile -File .\build.ps1
pwsh -NoProfile -File .\tests\run.ps1
pwsh -NoProfile -File .\scripts\verify-skill-integrity.ps1
pwsh -NoProfile -File .\scripts\verify-skills-config.ps1 -Mode enforce
```

`tests/run.ps1` uses the repository bootstrap to fetch hash-pinned Pester 6.1.0 into ignored `reports/test-runtime/`; do not install or mutate a global PowerShell module for this repository.

For a risk-triggered full closeout:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\quality\run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree
```

Run the full gate once after inputs are frozen. `构建生效`, `同步MCP`, host projection, live doctor, commit, and push are separate actions; do not include them implicitly in a repository-only change.

## Release tooling

`scripts/release/build-release.ps1` is the single release-package entrypoint. It creates bootstrap and portable ZIPs plus a SHA-256 list under ignored `artifacts/`. Do not hand-assemble or upload a package containing `.git`, runtime reports, credentials, host configuration, or plugin caches. Follow [docs/RELEASING.md](docs/RELEASING.md); every public package must include the repository MIT `LICENSE` while preserving third-party license obligations.

## Documentation and evidence

- Update only the document that owns the changed stable contract.
- Do not create task manifests, ADRs, archives, or tracked change-evidence for ordinary work.
- Git diff plus actual verification output is the default evidence.
- Runtime receipts belong under ignored `reports/`, next to the workflow that produced them.
- Add durable evidence only when an external release/compliance contract explicitly requires it.

## Pull request checklist

- State the real problem and smallest intended scope.
- List the verification actually run and its result.
- Call out migration, release, MCP, or host behavior changes.
- Report skipped/N/A verification with reason and alternative evidence.
- Preserve unrelated user/concurrent changes and describe the rollback for this slice only.
