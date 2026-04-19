# Contributing

## Scope
- Issues: bugs, feature requests, and questions
- Pull requests: documentation, tests, and code

## Basic Workflow
1. Fork the repository and create a branch.
2. Make one focused change.
3. Run the local gates in order.
4. Open a PR with context and verification evidence.

## Local Gates

```powershell
./build.ps1
./skills.ps1 发现
./skills.ps1 doctor --strict --threshold-ms 8000
./skills.ps1 构建生效
```

## PR Checklist
- What user problem this change addresses
- How to reproduce or validate the change
- Screenshots, logs, or sample output when relevant
- Any release note or migration impact
- README or demo updates if user-facing behavior changed

## Scope Discipline

- Do not edit generated `agent/` output by hand.
- Keep custom skills and local patches in `overrides/`.
- Avoid committing local agent state, logs, caches, or temporary files.
