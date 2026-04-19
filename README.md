# skills-manager

> Skill lifecycle and governance manager for Codex agent repositories.

## Overview
- Centralizes skill discovery, import, override, build, and sync workflows
- Keeps local patches in `overrides/` instead of editing cached upstream content
- Uses a single config source, `skills.json`, to drive the built output in `agent/`

## Core Model
- `skills.ps1`: main command entry point
- `skills.json`: single source of configuration
- `agent/`: built output and sync target
- `imports/`: imported skill subsets
- `overrides/`: local patches and custom skills
- `vendor/`: upstream caches generated locally

## Quick Start
```powershell
.\skills.ps1
.\skills.ps1 发现
.\skills.ps1 doctor --strict
.\skills.ps1 构建生效
```

## Sync Modes
- `link`: preferred on Windows; uses junctions to point targets at `agent/`
- `sync`: mirrors the built output with `robocopy /MIR`

## Common Commands
- `.\skills.ps1 add <repo> --skill <name>`
- `.\skills.ps1 锁定`
- `.\skills.ps1 构建生效 -Locked`
- `.\skills.ps1 更新 -Plan`
- `.\skills.ps1 更新 -Upgrade`

## 目标仓技能审查

外层 AI 代理可以让脚本生成目标仓审查包，再由 AI 自行研究官方文档、社区最佳实践、`skills.sh`、GitHub Trending 或 `find-skills` 结果，并把推荐写回 `recommendations.json`。

```powershell
.\skills.ps1 审查目标 初始化
.\skills.ps1 审查目标 添加 my-repo ..\my-repo
.\skills.ps1 审查目标 扫描 --target my-repo
.\skills.ps1 审查目标 应用 --recommendations reports\skill-audit\<run-id>\recommendations.json
.\skills.ps1 审查目标 应用 --recommendations reports\skill-audit\<run-id>\recommendations.json --apply --yes
```

默认 `应用` 只做 dry-run。只有同时传入 `--apply --yes` 才会安装新增技能、构建生效并运行 doctor。重叠技能只写入报告，不会自动卸载。

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

## Verification Order
1. `./build.ps1`
2. `./skills.ps1 发现`
3. `./skills.ps1 doctor --strict`
4. `./skills.ps1 构建生效`

That sequence is the minimum pre-submit verification set.

## Repository Hygiene
Do not commit local-only agent state or temporary artifacts, including:
- `.claude/`, `.codex/`, `.gemini/`, `.trae/`
- local agent rule files such as `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`
- logs, backups, and temporary files
- `_probe_*`, `_debug_*`, and `_tree_*` import snapshots

## Related Docs
- [English README](./README.en.md)
- [Contributing](./CONTRIBUTING.md)
- [Security Policy](./SECURITY.md)
- [Code of Conduct](./CODE_OF_CONDUCT.md)

## License
MIT

## Why this project
- Pain: Skill files drift across repos and lifecycle state becomes hard to audit.
- Result: Skill promotion, verification, and lifecycle review become repeatable.
- Differentiator: Governance scripts enforce skill quality and cross-repo consistency.

## Who it is for
- Agent platform maintainers and automation engineers
- Managing shared skills, trigger evaluation, and promotion workflows
- Use this when skill updates are frequent and manual sync becomes error-prone

## Quick Start (5 Minutes)
### Prerequisites
- PowerShell 7+
- Repository with governance scripts and policy files

### Run
```bash
powershell -File scripts/doctor.ps1
```

### Expected Output
- HEALTH=GREEN in doctor output
- Skill governance checks report PASS

## What you can try first
- Run verify before promoting skill candidates
- Use lifecycle review to inspect merge/retire candidates
- Distribute shared policies through install flow

## FAQ
- Q: Promotion is blocked
- A: Check trigger-eval status and required policy fields, then rerun promotion

## Limitations
- Focuses on governance/lifecycle, not runtime model behavior
- Relies on configured skill registry and policy files

## Next steps
- docs/
- RELEASE_TEMPLATE.md
- issues/
