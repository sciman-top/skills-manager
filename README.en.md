# skills-manager

A Windows-first, local-first PowerShell 7 manager for skills and MCP servers. It consolidates skill sources into one versioned configuration, builds portable skill directories, and provides target-repository audit, rule audit, and controlled native projection.

This repository is not a second AI runtime. It does not select models, own provider/auth/session state, replace host semantic routing, or manage plugin caches. Repository verification proves only `repo_verified`; host loading and live business acceptance remain separate checks.

## Quick start

PowerShell 7 (`pwsh`) and Git are required. Windows PowerShell 5.1 is unsupported.

```powershell
pwsh -NoProfile -File .\skills.ps1 help
pwsh -NoProfile -File .\skills.ps1 发现
pwsh -NoProfile -File .\skills.ps1 安装
pwsh -NoProfile -File .\skills.ps1 doctor --strict --threshold-ms 8000
```

The interactive menu uses direct frequent actions plus domain submenus.

- Browse Skills
- Pick Install
- Paste Command Import
- Rebuild and Sync (CLI command remains `构建生效`)
- Update Upstream (CLI command remains `更新`)
- Target Repo Audit
- MCP Services
- Skill Library Admin
- More

The `Target Repo Audit` submenu follows the workflow: scan, preflight, dry-run, then explicit apply.

## Sources of truth

`skills.json` owns vendors, imports, mappings, targets, MCP configuration, and skill projection. `skills.lock.json` pins resolved sources. `src/` is the CLI source and `build.ps1` generates `skills.ps1`; `overrides/{custom,patches,resources}` generates `agent/`. Do not hand-edit generated, vendored, or runtime report directories.

## Common commands

```powershell
# Skills
.\skills.ps1 发现
.\skills.ps1 安装
.\skills.ps1 卸载 <name> --yes
.\skills.ps1 更新 -Plan
.\skills.ps1 更新 -Upgrade
.\skills.ps1 构建生效

# MCP
.\skills.ps1 安装MCP <name> -- <command> [args...]
.\skills.ps1 安装MCP <name> --transport http --url <url>
.\skills.ps1 卸载MCP <name>
.\skills.ps1 MCP配置 列表
.\skills.ps1 同步MCP

# Target audit
.\skills.ps1 审查目标 扫描 --target <name>
.\skills.ps1 审查目标 预检 --recommendations <file>
.\skills.ps1 审查目标 应用确认 --recommendations <file>
.\skills.ps1 审查目标 应用 --recommendations <file> --apply --yes

# Rule audit and reviewed mutation
.\skills.ps1 rule-audit --repo <repo-root> --host codex --json
.\skills.ps1 rule-estate-audit --workspace-root D:\CODE --json
.\skills.ps1 rule-estate-plan --review <reviewed-change-set.json> --workspace-root D:\CODE --out <plan.json> --json
.\skills.ps1 rule-estate-apply --plan <plan.json> --workspace-root D:\CODE --token APPLY_RULE_ESTATE_PATCH --json
```

Target-audit runtime bundles and receipts live under ignored `reports/skill-audit/<run-id>/`. Only explicit `--apply --yes` persists recommendations. Rule mutation additionally requires reviewed input, exact roots and hashes, a token, a receipt, and rollback data.

`构建生效` writes projected output outside the repository. For repository-only generated synchronization, run `build.ps1` instead.

## Projection and explicit fallback

Host-native metadata is the normal selection surface. `capability-router` is an explicit cold-discovery or policy-validation fallback. It accepts `DomainHint`, returns candidates, and validates host selections; it does not rank semantically, switch profiles, or mutate host state.

```powershell
.\skills.ps1 capability-inventory --view skill-surfaces --json
pwsh -NoProfile -File .\scripts\verify-capability-routing.ps1 -Json
pwsh -NoProfile -File .\scripts\verify-native-skill-metadata.ps1 -Json
```

## Reference shelf

`references/reference-shelf.manifest.json` contains only the current core and secondary reference set below `D:\CODE\external\skills-manager-references`. Refreshing is read-only comparison; it never authorizes adoption, installation, execution, or runtime-import removal.

```powershell
.\scripts\refresh-reference-repos.ps1 -FetchOnly -SkipDirtyRepos
.\scripts\refresh-reference-repos.ps1 -Tier secondary -CloneMissing -FetchOnly -SkipDirtyRepos
.\scripts\verify-reference-governance.ps1
```

Candidates without a current consumer are rediscovered when needed instead of being kept in a permanent backlog.

## Development and verification

```powershell
pwsh -NoProfile -File .\build.ps1
pwsh -NoProfile -File .\tests\check-generated-sync.ps1 -AllowDirtyWorktree
pwsh -NoProfile -File .\scripts\verify-skill-integrity.ps1
pwsh -NoProfile -File .\scripts\verify-skills-config.ps1 -Mode enforce
git diff --check
```

Use affected tests for ordinary changes. Runtime, security, data, migration, public-contract, dependency, or packaging changes justify one full gate:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\quality\run-local-quality-gates.ps1 -Profile full -ReuseCurrentReceipt
# If no exact-current receipt exists and a fresh full run is required:
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\quality\run-local-quality-gates.ps1 -Profile full -ForceFresh -AllowDirtyWorktree
```

See [docs/product/README.md](docs/product/README.md), [CONTRIBUTING.md](CONTRIBUTING.md), and [docs/runbooks/powershell-runtime-compatibility.md](docs/runbooks/powershell-runtime-compatibility.md).
