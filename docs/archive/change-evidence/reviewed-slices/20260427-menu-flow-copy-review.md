# 2026-04-27 menu flow and copy review

## Scope

- Rule IDs: R1/R2/R6/R8, E4
- Risk: low
- Landing: interactive menu and help copy in `src/Commands/Utils.ps1`, workflow picker wording in `src/Commands/Workflow.ps1`
- Target: make menu flow easier to scan while preserving all CLI command names and aliases

## Changes

- Reorganized `目标仓审查` into the visible flow `需求 -> 审查包 -> 预检 -> 应用`.
- Moved target repository CRUD into `目标仓管理`.
- Moved structured profile import, audit config init, prompt editing, and direct apply into `审查高级设置`.
- Shortened submenu labels for MCP, skill library management, and maintenance utilities.
- Rewrote `帮助` into workflow-first grouped copy instead of a long flat command list.
- Changed help output to a single-quoted here-string so Markdown backticks render literally.
- Added `Read-MenuChoice` so blank menu input returns/ exits instead of causing non-interactive infinite menu loops.
- Updated README copy, generated `skills.ps1`, and focused menu/workflow tests.

## Verification

- `./build.ps1`
  - exit 0
  - key output: `Build success: D:\CODE\skills-manager\skills.ps1`
- `./skills.ps1 menu`
  - exit 0
  - key output: menu printed once and returned under non-interactive input
- `./skills.ps1 帮助`
  - exit 0
  - key output: grouped help output; backtick paths such as `reports\skill-audit\...` rendered literally
- `./skills.ps1 发现`
  - exit 0
  - key output: 96 skills listed
- `./skills.ps1 doctor --strict --threshold-ms 8000`
  - exit 0
  - key output: `Your system is ready for skills-manager.`
- `./skills.ps1 构建生效`
  - exit 0
  - key output: `构建完成：agent/ (共 91 项技能)` and `=== 构建生效流程完成 ===`
- `./scripts/quality/run-local-quality-gates.ps1 -Profile quick -AllowDirtyWorktree`
  - exit 0
  - key output: `Local quality gates passed (quick).`

## N/A

- type: gate_na
- reason: `./tests/run.ps1` requires the Pester module, which is not installed in this host session.
- alternative_verification: build, generated-sync, discover, doctor strict, build-apply hotspot, and quick quality gates all passed.
- evidence_link: this file
- expires_at: when Pester is installed or bundled for this host.

## Rollback

- Restore `src/Core.ps1`, `src/Commands/Utils.ps1`, `src/Commands/Workflow.ps1`, README files, and focused tests from the previous commit.
- Run `./build.ps1` to regenerate `skills.ps1`.
- Re-run gates in order: `./build.ps1` -> `./skills.ps1 发现` -> `./skills.ps1 doctor --strict --threshold-ms 8000` -> `./skills.ps1 构建生效`.
