# Menu Restructure Evidence

- date: 2026-04-20
- branch: `feat/menu-restructure`
- target: interactive menu labels, submenu structure, help copy, README copy, workflow copy
- risk: low-to-medium; user-facing navigation/copy changes, no CLI command contract changes intended

## Rule Mapping

- R1 current location -> target location: `main` worktree -> isolated `.worktrees/menu-restructure` branch -> future merge back to main
- R2 small closures: implemented as four staged commits with focused tests
- R6 gate order: `build -> test -> contract/invariant -> hotspot`
- R7 compatibility: kept CLI handlers and aliases unchanged; changed only interactive labels, help/docs wording, workflow display titles/descriptions
- R8 traceability: this file records basis, commands, evidence, and rollback

## Basis

- Approved design: main menu should favor frequent direct actions for experienced users.
- Approved structure: top-level actions first; complex domains grouped under `目标仓审查`, `MCP 服务`, `技能库管理`, and `更多`.
- Approved copy principle: short labels, result-oriented wording, and clear distinction between recommended and advanced audit actions.

## Commands And Evidence

```text
codex --version
=> codex-cli 0.121.0

codex --help
=> command completed successfully

codex status
=> Error: stdin is not a terminal
platform_na: non-interactive Codex status is unavailable in this environment.
alternative_verification: active AGENTS instructions were supplied in-session; work executed in isolated git worktree.
expires_at: next interactive Codex session where status can be queried.
```

```text
./build.ps1
=> Build success: D:\OneDrive\CODE\skills-manager\.worktrees\menu-restructure\skills.ps1

powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\MenuStructure.Tests.ps1"
=> Passed: 3 Failed: 0

powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\AuditTargets.Tests.ps1"
=> Passed: 43 Failed: 0

powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\Workflow.Tests.ps1"
=> Passed: 9 Failed: 0

./skills.ps1 发现
=> exit 0; listed 3 workspace skills

./skills.ps1 doctor --strict --threshold-ms 8000
=> exit 0; "Your system is ready for skills-manager."
```

## Hotspot Gate

```text
./skills.ps1 构建生效
=> exit 0, but output reports build failure and rollback:
   "构建生效部分失败（28 项）"
   examples:
   - mapping:manual/playwright-best-practices => manual 导入不存在或无效：playwright-best-practices
   - mapping:manual/agent-browser => manual 导入不存在或无效：agent-browser
   - mapping:manual/architecture-patterns => manual 导入不存在或无效：architecture-patterns
   "已回滚 agent/ 到构建前状态。"
```

classification: known pre-existing hotspot blocker, not introduced by this menu restructure.

- reason: repository configuration currently contains missing/invalid `manual/*` mappings unrelated to menu labels, help/docs, or workflow copy.
- alternative_verification: `./build.ps1`, `./skills.ps1 发现`, `doctor --strict`, and focused Pester suites passed; `构建生效` rolled back `agent/`.
- evidence_link: this file and terminal output from 2026-04-20 23:51.
- expires_at: before publishing a release or merging if hotspot gate is required to be clean.

## Rollback

To revert this menu restructure branch:

```powershell
git revert 3502590..53976a9
```

If only the final workflow-copy step must be reverted:

```powershell
git revert 53976a9
```

The `./skills.ps1 构建生效` run already rolled back `agent/` automatically after the unrelated mapping failure.
