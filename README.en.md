# skills-manager

A Windows-first, local-first PowerShell 7 manager for AI skills and MCP servers. It consolidates scattered sources into one versioned configuration, pins revisions, builds portable skill directories, and safely projects them to hosts such as Codex and Claude.

It is aimed at individuals and teams that want the same skill set across Windows machines, auditable repository rules, and a shared MCP inventory without handing model, account, or runtime ownership to another framework.

This repository is not a second AI runtime. It does not select models, own provider/auth/session state, replace host semantic routing, or manage plugin caches. Repository verification proves only `repo_verified`; host loading and live business acceptance remain separate checks.

This project is licensed under the [MIT License](LICENSE). Third-party skills and dependencies remain subject to their original licenses.

## Quick start

PowerShell 7 (`pwsh`) and Git are required. Windows PowerShell 5.1 is unsupported.

### Recommended: one-step Release install

The current stable release is [v2026.08.27.1](https://github.com/sciman-top/skills-manager/releases/tag/v2026.08.27.1). Download the matching `bootstrap.zip` from [GitHub Releases](https://github.com/sciman-top/skills-manager/releases), verify `SHA256SUMS.txt`, extract it, and run:

```powershell
.\setup.cmd
```

For offline or USB-style green use, download `portable.zip`, extract it, and run `skills.cmd`. It does not write host directories automatically. See the [installation and migration guide](docs/INSTALLATION_AND_MIGRATION.md) for package selection, checksums, and migration boundaries. Local outputs follow the `deliveries/history/work` layout: migrations are separated as `artifacts/deliveries/migration/{general,private,rescan}/<run-id>/`, and release staging uses `artifacts/deliveries/release/<version>/`.

`artifacts/` is only a local ignored output directory. Public downloads, checksums, and attestations are sourced from the GitHub Release, not from this directory. See [`artifacts/README.md`](artifacts/README.md) for the local retention rules.

### From source

```powershell
pwsh -NoProfile -File .\skills.ps1 help
pwsh -NoProfile -File .\skills.ps1 发现
pwsh -NoProfile -File .\skills.ps1 安装
pwsh -NoProfile -File .\skills.ps1 doctor --strict
```

You can also run `skills.cmd` to open the interactive menu.

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

## Distribution models

Each version has one delivery root, `artifacts/deliveries/<version>/`, with four sibling forms: `standard-install/bootstrap.zip`, `portable/portable.zip`, `source/source.zip`, and the local-only `private-snapshot/private-all.zip`. The first three are public tool/source baselines with no `agent/`, skill inventory, MCP inventory, target state, `vendor/`, or `imports/`; a new machine scans its own target repositories before the user chooses what to install. The source archive contains development files but not Git history; clone/fork/tag remains the development truth. Only `private-all` carries the current complete skills/MCP state, as a plaintext, no-passphrase private snapshot. Repository `rules/global/` source is present only in the source archive and private snapshot, and never overwrites effective host-global rules automatically. `rescan` is an auxiliary scan list, not a fifth delivery form.

Release installations can check for a newer skills-manager release and, only after explicit confirmation, verify the published SHA-256, preserve a sibling backup, and hand off a directory switch to an independent updater. Source checkouts must use Git rather than the Release updater.

```powershell
.\skills.ps1 release-update --check --json
.\skills.ps1 release-update --apply --yes
.\skills.ps1 release-update-schedule --enable --time=09:00
```

`--auto-apply` is an explicit scheduler option. It never migrates host login, provider/auth/session state, plugin caches, or MCP credentials, and it does not prove host loading or live acceptance.

## Sources of truth

`skills.json` owns vendors, imports, mappings, targets, MCP configuration, and skill projection. `skills.lock.json` pins resolved sources. `src/` is the CLI source and `build.ps1` generates `skills.ps1`; `overrides/{custom,patches,resources}` generates `agent/`. Do not hand-edit generated, vendored, or runtime report directories.

## Common commands

```powershell
# Skills
.\skills.ps1 发现
.\skills.ps1 安装
.\skills.ps1 卸载 <name> --yes
.\skills.ps1 check-updates --json
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

`check-updates --json` reports only `current/target/changed/source`; it does not apply, build, project, or sync MCP. `构建生效` writes projected output outside the repository. For repository-only generated synchronization, run `build.ps1` instead. `scripts/weekly-skills-update.ps1` remains a skills-only runner that a host/operator may schedule, but the repository provides no entry to create, update, or delete that legacy Windows scheduled task; `doctor` only reports it read-only and cleanup is a host-side decision. In contrast, `release-update-schedule --enable` explicitly creates a non-elevated scheduled task under the current interactive user, and `--disable` removes it.

## Projection and explicit fallback

Host-native metadata is the normal selection surface. `capability-router` is an explicit cold-discovery or policy-validation fallback. It accepts `DomainHint`, returns candidates, and validates host selections; it does not rank semantically, switch profiles, or mutate host state.

```powershell
# Default: read repository skill surfaces only; do not invoke the host CLI.
.\skills.ps1 capability-inventory --view skill-surfaces --json

# Opt in only when a current, read-only host observation is needed.
.\skills.ps1 capability-inventory --view skill-surfaces --host-probe --json
```

By default the inventory returns repository and projected skill surfaces only. `--host-probe` opts into public Codex CLI JSON for plugins, MCP servers, and doctor facts; the result is redacted and read-only. When an enabled plugin and a standalone/system skill share a name, it emits a report-only native-source preference. It never installs, removes, or enables plugins, never reads or writes plugin caches, and does not prove host loading or actual skill invocation.

## Reference shelf

`references/reference-shelf.manifest.json` contains only the current core and secondary reference set below `D:\CODE\external\skills-manager-references`. Refreshing is read-only comparison; it never authorizes adoption, installation, execution, or runtime-import removal.

```powershell
.\scripts\refresh-reference-repos.ps1 -FetchOnly -SkipDirtyRepos
.\scripts\refresh-reference-repos.ps1 -Tier secondary -CloneMissing -FetchOnly -SkipDirtyRepos
.\scripts\verify-reference-governance.ps1
```

Each refresh writes an ignored `reports/reference-refresh/<run-id>/receipt.md`; no dynamic latest state is tracked. Candidates without a current consumer are rediscovered when needed instead of being kept in a permanent backlog.

## Development and verification

```powershell
pwsh -NoProfile -File .\build.ps1
pwsh -NoProfile -File .\scripts\verify-skill-integrity.ps1
pwsh -NoProfile -File .\scripts\verify-skills-config.ps1 -Mode enforce
git diff --check
```

Use affected tests for ordinary changes. Runtime, security, data, migration, public-contract, dependency, or packaging changes justify one full gate:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\quality\run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree
```

See [docs/product/README.md](docs/product/README.md), [CONTRIBUTING.md](CONTRIBUTING.md), and [docs/runbooks/powershell-runtime-compatibility.md](docs/runbooks/powershell-runtime-compatibility.md).

Build both release packages with:

```powershell
pwsh -NoProfile -File .\scripts\release\build-release.ps1 -Version <version>
```

Maintainers should read [the release guide](docs/RELEASING.md), especially the third-party provenance and clean-machine acceptance requirements.
