# skills-manager

[中文](README.md) | English

`skills-manager` is a Windows-first PowerShell tool for aggregating, curating, building, and syncing AI agent skills from multiple upstream repositories into a single local workspace.

It is designed for users who want one controlled entry point for Claude, Codex, Gemini, Trae, and similar tools without manually cloning, copying, and reconciling skill folders.

## What It Does

- Aggregates skills from multiple upstream repositories.
- Lets you enable only the skills you want through explicit mappings and imports.
- Builds a clean local skill bundle into `agent/`.
- Syncs that bundle to local targets such as `~/.claude/skills` or `~/.codex/skills`.
- Supports both linked and mirrored deployment modes on Windows.
- Keeps the workflow scriptable while still providing an interactive Chinese menu.

## Why This Repo Exists

Managing skills manually breaks down quickly:

- different vendors use different layouts
- local overrides get mixed with upstream content
- updates become risky
- target directories drift out of sync

`skills-manager` standardizes that workflow around:

- one entry script: `skills.ps1`
- one source of truth: `skills.json`
- one generated output: `agent/`

## Core Concepts

### Source Layers

- `vendors`: full upstream repositories managed as configured sources
- `imports`: manually imported skills or targeted subpaths
- `overrides`: local patches or custom additions that should win over upstream content

### Generated Output

- `agent/`: the built skill set produced from vendor mappings, manual imports, and overrides

### Target Sync

- `link`: preferred on Windows; uses junctions to point target directories at `agent/`
- `sync`: falls back to mirrored copies when links are not allowed

## Repository Layout

```text
repo/
  skills.ps1        # main entry point
  skills.json       # single config source
  build.ps1         # rebuilds skills.ps1 from src/
  src/              # source modules for the main script
  tests/            # unit and end-to-end tests
  overrides/        # local maintained overrides
  imports/          # imported skill sources
  vendor/           # upstream cache, generated locally
  agent/            # built output, generated locally
```

## Quick Start

### Prerequisites

- Windows 10 or 11
- PowerShell 5.1 or later
- Git available in `PATH`
- `robocopy` available on the system

### Run the Interactive Menu

```powershell
.\skills.ps1
```

### Recommended First-Time Flow

1. Add one or more vendor repositories.
2. Select the skills you want to enable.
3. Build and apply.
4. Verify the targets were updated correctly.

### Useful Commands

```powershell
.\skills.ps1 发现
.\skills.ps1 构建生效
.\skills.ps1 更新
.\skills.ps1 doctor --strict
```

## Configuration

`skills.json` is the single configuration source for:

- `vendors`
- `mappings`
- `imports`
- `targets`
- `sync_mode`
- `mcp_servers`

This keeps repository behavior explicit and reviewable.

## Development

Quality gates in this repository run in the following order:

```powershell
./build.ps1
./skills.ps1 发现
./skills.ps1 doctor --strict
./skills.ps1 构建生效
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution expectations.

## Repository Hygiene

This repository intentionally does not treat local IDE or agent state as distributable project content.

Examples of local-only content:

- `.claude/`, `.codex/`, `.gemini/`, `.trae/`
- temporary logs and backup files
- temporary probe/debug snapshots created during import or diagnosis

Those files may exist locally, but they are not part of the remote repository contract.

## Related Docs

- [Chinese README](README.md)
- [Contributing](CONTRIBUTING.md)
- [Security Policy](SECURITY.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
