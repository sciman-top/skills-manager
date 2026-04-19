# skills-manager

[中文](README.md) | English

`skills-manager` is a Windows-first PowerShell tool for assembling AI agent skills from multiple sources into one controlled local workspace.

Use it when you:

- run multiple agents such as Claude, Codex, Gemini, or Trae
- import skills from several repositories
- want local patches in `overrides/` instead of editing upstream caches
- want one generated output in `agent/`, then sync it to each CLI target

## Core Model

- `skills.ps1`: single command entry point
- `skills.json`: single configuration source
- `agent/`: generated output and sync source
- `vendors`: full upstream repositories
- `imports`: targeted skill or subpath imports
- `overrides`: local patches and custom skills

## Quick Start

Chinese commands:

```powershell
.\skills.ps1
.\skills.ps1 发现
.\skills.ps1 doctor --strict
.\skills.ps1 构建生效
```

English aliases:

```powershell
.\skills.ps1
.\skills.ps1 doctor --strict
```

`发现` and `构建生效` currently have no English aliases (N/A).

For first-time setup, start from the interactive menu:

```powershell
.\skills.ps1
```

Recommended flow:

1. Add a skill repository, or import one skill with an `add` / `npx` command.
2. Run `发现` to list available skills.
3. Install the skills you need into `mappings`.
4. Run `构建生效` to generate `agent/` and sync targets.
5. Run `doctor --strict` to validate configuration and sync state.

## Common Commands

Chinese commands:

```powershell
.\skills.ps1 add <repo> --skill <name>
.\skills.ps1 锁定
.\skills.ps1 构建生效 -Locked
.\skills.ps1 更新 -Plan
.\skills.ps1 更新 -Upgrade
```

English aliases:

```powershell
.\skills.ps1 add <repo> --skill <name>
```

`锁定`, `构建生效`, and `更新` currently have no English aliases (N/A).

Notes:

- Without `--skill`, `add` only registers a vendor. It does not install every skill in that repository.
- With `--skill`, imports default to `manual` mode under `imports`; use `--mode vendor` for vendor-managed installs.
- `更新` fetches upstream repositories. Use `构建生效` when you only need to rebuild local configuration.

## Sync Modes

`skills.json` selects sync behavior through `sync_mode`:

- `link`: recommended on Windows; uses junctions to point target directories at `agent/`
- `sync`: mirrors `agent/` with `robocopy /MIR`

Use `link` for local iteration. Use `sync` when links are restricted.

## overrides Naming

Use clear prefixes under `overrides/`:

- `custom-*`: fully custom skills
- `patch-*`: locally patched variants of upstream skills
- `<skill-name>`: intentional same-name replacement of generated output

Prefer `custom-*` and `patch-*`. Use same-name overrides only when replacement is intentional.

## Target Repository Skill Audit

Outer AI agents can ask the script to generate a target repository audit bundle, perform their own research using official docs, community best practices, `skills.sh`, GitHub Trending, or `find-skills`, and then hand recommendations back as JSON.

Chinese commands:

```powershell
.\skills.ps1 审查目标 初始化
.\skills.ps1 审查目标 添加 my-repo ..\my-repo
.\skills.ps1 审查目标 扫描 --target my-repo
.\skills.ps1 审查目标 应用 --recommendations reports\skill-audit\<run-id>\recommendations.json
.\skills.ps1 审查目标 应用 --recommendations reports\skill-audit\<run-id>\recommendations.json --apply --yes
```

`应用` defaults to dry-run. It installs new skills only when `--apply --yes` is provided, then runs build/apply and doctor. Overlapping skills are reported only and are not removed automatically.

Equivalent English aliases:

```powershell
.\skills.ps1 audit-targets init
.\skills.ps1 audit-targets add my-repo ..\my-repo
.\skills.ps1 audit-targets scan --target my-repo
.\skills.ps1 audit-targets apply --recommendations reports\skill-audit\<run-id>\recommendations.json
.\skills.ps1 audit-targets apply --recommendations reports\skill-audit\<run-id>\recommendations.json --apply --yes
```

## Repository Layout

```text
repo/
  skills.ps1        # main entry point, generated from src/
  skills.json       # single configuration source
  build.ps1         # rebuilds skills.ps1 from src/
  src/              # source modules
  tests/            # unit and end-to-end verification
  overrides/        # local override layer
  imports/          # targeted imported sources
  vendor/           # upstream cache, generated locally
  agent/            # generated output, generated locally
```

## Local Gates

Run these in order before submitting changes:

Chinese commands:

```powershell
./build.ps1
./skills.ps1 发现
./skills.ps1 doctor --strict --threshold-ms 8000
./skills.ps1 构建生效
```

English aliases:

```powershell
./build.ps1
./skills.ps1 doctor --strict --threshold-ms 8000
```

`发现` and `构建生效` currently have no English aliases (N/A).

## Repository Hygiene

Do not commit local-only agent state, logs, caches, or temporary artifacts, including:

- `.claude/`, `.codex/`, `.gemini/`, `.trae/`
- local rule files such as `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`
- logs, backups, and temporary files
- `_probe_*`, `_debug_*`, and `_tree_*` import snapshots

Those files may exist locally, but they are outside the repository contract.

## Related Docs

- [Contributing](CONTRIBUTING.md)
- [Security Policy](SECURITY.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)

## License

MIT
