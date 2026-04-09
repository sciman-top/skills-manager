# skills-manager

[中文](README.md) | English

`skills-manager` is a Windows-first PowerShell tool that turns scattered AI agent skills into one controlled local workspace.

It is built for the common case where you use multiple agents, pull from multiple skill sources, and do not want to keep cloning, copying, patching, and re-syncing directories by hand.

## Positioning

Think of this repository as a local skill assembly layer:

- upstream: aggregate multiple skill repositories
- local: decide what to enable, import, or override
- downstream: sync one built output to Claude, Codex, Gemini, Trae, and similar targets

All of that is driven by a single configuration file: `skills.json`.

## Why It Exists

- avoid hand-maintaining several `~/.xxx/skills` directories
- enable only the skills you actually want
- keep local patches in `overrides/` instead of editing cached upstream content
- make the final build output explicit in `agent/`
- support both junction-based and mirrored sync on Windows

## Core Model

- single entry point: `skills.ps1`
- single config source: `skills.json`
- single generated output: `agent/`

Source layers:

- `vendors`: full upstream repositories
- `imports`: targeted skill or subpath imports
- `overrides`: local patches and custom additions

## overrides Grouping Convention

Use grouped naming under `overrides/` with clear prefixes:

- `custom-*`: fully custom skills (not a direct upstream replacement)
- `patch-*`: local patched variants of upstream skills
- `<skill-name>`: direct same-name override when replacement is intentional

Recommendation: prefer `custom-*` and `patch-*` for clarity, and use `<skill-name>` only when you explicitly need same-name override behavior.

## Repository Layout

```text
repo/
  skills.ps1        # main entry point
  skills.json       # single configuration source
  build.ps1         # rebuilds skills.ps1 from src/
  src/              # source modules
  tests/            # unit and end-to-end verification
  overrides/        # local override layer
  imports/          # targeted imported sources
  vendor/           # upstream cache, generated locally
  agent/            # built output, generated locally
```

## Typical Flow

```powershell
.\skills.ps1 发现
.\skills.ps1 构建生效
.\skills.ps1 doctor --strict
```

For first-time setup, you can start from the interactive menu:

```powershell
.\skills.ps1
```

Recommended order:

1. add one or more upstream repositories
2. enable the skills you want
3. build and apply
4. verify the result with `doctor --strict`

## Sync Modes

`skills.json` supports two sync strategies through `sync_mode`:

- `link`: preferred on Windows; uses junctions to point target directories at `agent/`
- `sync`: mirrors the built output with `robocopy /MIR`

Use `link` when you want direct local iteration. Use `sync` when links are restricted.

## Imports and Locking

Common operations:

- import one skill: `.\skills.ps1 add <repo> --skill <name>`
- write lock data: `.\skills.ps1 锁定`
- strict build from lock: `.\skills.ps1 构建生效 -Locked`
- preview upgrades: `.\skills.ps1 更新 -Plan`
- upgrade and refresh lock data: `.\skills.ps1 更新 -Upgrade`

## Quality Gates

This repository validates changes in a fixed order:

```powershell
./build.ps1
./skills.ps1 发现
./skills.ps1 doctor --strict
./skills.ps1 构建生效
```

That sequence is the minimum pre-submit verification set.

## Repository Hygiene

The remote repository must not include local-only agent state or temporary artifacts, including:

- `.claude/`, `.codex/`, `.gemini/`, `.trae/`
- local agent rule files such as `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`
- logs, backups, and temporary files
- `_probe_*`, `_debug_*`, and `_tree_*` import snapshots

Those files may exist locally, but they are outside the repository contract. CI now checks this explicitly.

## Related Docs

- [Chinese README](README.md)
- [Contributing](CONTRIBUTING.md)
- [Security Policy](SECURITY.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
