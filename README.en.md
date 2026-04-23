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

The interactive menu is organized around expert-first direct actions. The top level now prioritizes:

- Browse Skills
- Pick Install
- Paste Command Import
- Remove Skills
- Rebuild and Sync (CLI command remains `构建生效`)
- Update Upstream (CLI command remains `更新`)
- Target Repo Audit
- MCP Services
- Skill Library Admin
- More

Recommended flow:

1. Add a skill repository, or import one skill with an `add` / `npx` command.
2. Run `发现` to list available skills.
3. Install the skills you need into `mappings`.
4. Run `构建生效` to generate `agent/` and sync targets.
5. Run `doctor --strict` to validate configuration and sync state.

## One-Click Workflows (Recommended)

```powershell
.\skills.ps1 一键 --list
.\skills.ps1 一键 新手
.\skills.ps1 一键 维护 --continue-on-error
.\skills.ps1 一键 审查 --no-prompt
.\skills.ps1 workflow all --no-prompt
```

Workflow profiles:

- `新手`: `浏览技能 -> 选择安装 -> 重建并同步 -> doctor --strict`
- `维护`: `更新上游 -> 重建并同步 -> 同步MCP -> doctor --strict`
- `审查`: `查看需求 -> 目标仓列表 -> 生成审查包 -> 查看最近状态`
- `all`: `更新上游 -> 浏览技能 -> 重建并同步 -> 同步MCP -> doctor --strict`

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

After each `scan`, prefer handing the run-local `outer-ai-prompt.md` to the outer AI instead of only handing over `ai-brief.md`. That runtime prompt already defines the expected execution order:

- read `ai-brief.md`
- fill `recommendations.json` using the `recommendations.template.json` schema
- run a self-check first: schema, placeholders, dual reasons, and real sources must all pass
- run `apply-flow` after that (dry-run -> confirmation token -> apply)
- present add/remove recommendation lists with the original dry-run indexes
- or run `apply --apply --yes` directly when explicit execution is intended

Formal audits must always use both context layers:

- global user profile: long-lived work types, preferences, constraints, and common tasks
- target repository: current project stack, rule files, build facts, and test facts

Do not start a formal audit without a user profile. Once the audit workflow starts, the outer AI may research online within that workflow, but research does not imply automatic install or automatic removal.

After `profile-set` saves the raw long-form input, the script automatically enters the structured-profile import flow:

- press Enter: use the default path `reports\skill-audit\user-profile.structured.json`
- provide a custom value: use your custom path and filename
- if the target file does not exist: the script creates a structured-profile draft file for AI or manual completion
- enter `0`: skip structured import for now

Chinese commands:

```powershell
.\skills.ps1 审查目标 初始化
.\skills.ps1 审查目标 需求设置
.\skills.ps1 审查目标 需求查看
.\skills.ps1 审查目标 需求结构化 --profile reports\profile.json
.\skills.ps1 审查目标 添加 my-repo ..\my-repo
.\skills.ps1 审查目标 扫描 --target my-repo
.\skills.ps1 审查目标 状态
.\skills.ps1 审查目标 应用确认 --recommendations reports\skill-audit\<run-id>\recommendations.json
.\skills.ps1 审查目标 应用 --recommendations reports\skill-audit\<run-id>\recommendations.json
.\skills.ps1 审查目标 应用 --recommendations reports\skill-audit\<run-id>\recommendations.json --dry-run-ack "我知道未落盘"
.\skills.ps1 审查目标 应用 --recommendations reports\skill-audit\<run-id>\recommendations.json --apply --yes
.\skills.ps1 审查目标 应用 --recommendations reports\skill-audit\<run-id>\recommendations.json --apply --yes --add-indexes "1,3" --remove-indexes "2" --mcp-add-indexes "1" --mcp-remove-indexes "2"
```

`应用` defaults to dry-run. Only `--apply --yes` executes the specific installs and removals you selected, then runs build/apply and doctor.
`应用确认` is the single-entry two-stage flow: it runs dry-run first, then requires confirmation token `APPLY <run-id>` before any persisted changes.
In dry-run mode, the script prints a red non-persisted warning and requires explicit ack token `我知道未落盘` (for non-interactive runs, pass `--dry-run-ack`).
`状态` reads the latest `apply-report.json` and shows `mode / success / persisted / changed_counts`.

Before applying, the script prints four independent recommendation lists:

- add recommendations: each item has an index, skill name, user-profile reason, and target-repo reason
- removal recommendations: each item has an index, skill name, installed locator, user-profile reason, and target-repo reason
- MCP add recommendations: each item has an index, MCP name, user-profile reason, and target-repo reason
- MCP removal recommendations: each item has an index, MCP name, user-profile reason, and target-repo reason

You can choose skill/MCP indexes interactively, or pass them non-interactively through `--add-indexes`, `--remove-indexes`, `--mcp-add-indexes`, and `--mcp-remove-indexes`. All four lists are independently numbered, and selections in one list never remap indexes in another list.

If the outer AI has workspace execution capability, the most direct handoff is to ask it to execute the run-local `outer-ai-prompt.md`, with the expectation that it self-checks `recommendations.json` before dry-run.

Equivalent English aliases:

```powershell
.\skills.ps1 audit-targets init
.\skills.ps1 audit-targets profile-set
.\skills.ps1 audit-targets profile-show
.\skills.ps1 audit-targets profile-structure --profile reports\profile.json
.\skills.ps1 audit-targets add my-repo ..\my-repo
.\skills.ps1 audit-targets scan --target my-repo
.\skills.ps1 audit-targets status
.\skills.ps1 audit-targets apply-flow --recommendations reports\skill-audit\<run-id>\recommendations.json
.\skills.ps1 audit-targets apply --recommendations reports\skill-audit\<run-id>\recommendations.json
.\skills.ps1 audit-targets apply --recommendations reports\skill-audit\<run-id>\recommendations.json --dry-run-ack "我知道未落盘"
.\skills.ps1 audit-targets apply --recommendations reports\skill-audit\<run-id>\recommendations.json --apply --yes
.\skills.ps1 audit-targets apply --recommendations reports\skill-audit\<run-id>\recommendations.json --apply --yes --add-indexes "1,3" --remove-indexes "2" --mcp-add-indexes "1" --mcp-remove-indexes "2"
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

Quality gate scripts (local/CI parity):

```powershell
./scripts/quality/run-local-quality-gates.ps1 -Profile quick
./scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree
```

## MCP and Gate Environment Variables

- `SKILLS_MCP_VERIFY_GEMINI_CLI=1|true|yes|on`: enable real Gemini CLI verification (disabled by default; default path uses config-state verification).
- `SKILLS_MCP_VERIFY_LIST_TIMEOUT_SECONDS`: global timeout in seconds for `mcp list` verification.
- `SKILLS_MCP_VERIFY_LIST_TIMEOUT_SECONDS_<CLI>`: per-CLI timeout override (for example `_CLAUDE`, `_CODEX`, `_GEMINI`).
- `SKILLS_MCP_NATIVE_TIMEOUT_SECONDS`: timeout in seconds for native `claude mcp add/remove`.
- `SKILLS_MCP_VERIFY_ATTEMPTS` and `SKILLS_MCP_VERIFY_INTERVAL_SECONDS`: retry count and retry interval (seconds) for cross-CLI MCP verification.
- `SKILLS_SYNC_MCP_THRESHOLD_MS`: `sync_mcp` performance threshold in `check-doctor-json.ps1` (milliseconds, CI recommendation: `12000`).

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
