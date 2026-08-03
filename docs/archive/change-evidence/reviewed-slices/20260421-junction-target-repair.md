# 2026-04-21 junction target repair

## Rules
- R1: 当前落点为 `src/Core.ps1`、生成入口 `skills.ps1`、`skills.json`、用户级 skills junction；目标归宿为所有 target 指向本仓 `agent/`。
- R2: 小步闭环：先修源码与回归测试，再构建、发现、doctor、构建生效、独立读取 target。
- R6: 门禁顺序：build -> test -> contract/invariant -> hotspot。
- R8: 留存依据 -> 命令 -> 证据 -> 回滚。

## Risk
- level: medium
- reason: 修改用户级 `~/.codex/skills`、`~/.claude/skills`、`~/.gemini/skills`、`~/.gemini/antigravity/skills`、`~/.trae/skills` junction；用户已明确要求立即修复。

## Basis
- 发现所有用户级 skills junction 均指向已废弃路径：`D:\OneDrive\CODE\skills-manager\.worktrees\menu-restructure\agent`。
- 目标归宿应为当前仓库：`D:\OneDrive\CODE\skills-manager\agent`。
- `find-skills` 已在 `imports` 中，但未在 `mappings` 白名单中；干净构建后不应依赖旧 `agent/` 残留。

## Changes
- `src/Core.ps1`: 新增 `Test-PathEntry`，用 `Get-Item -LiteralPath -Force` 识别普通路径和 reparse point。
- `src/Core.ps1`: `Invoke-RemoveItem`、`Is-ReparsePoint`、`Backup-DirIfNeeded`、`New-Junction`、`Remove-JunctionAndRestore` 改为兼容 broken junction。
- `skills.json`: 添加 `manual/find-skills -> find-skills` mapping。
- `skills.json`: 恢复 27 个已登记 manual imports 的 mappings，使 `manual_imports=31` 与 `manual_mappings=31` 对齐。
- `tests/Unit/Core.Tests.ps1`: 增加 broken junction 替换回归测试。
- `skills.ps1`: 由 `./build.ps1` 生成。
- 旧事务备份清理：将 7 个历史残留技能从 `.txn\build-3838547b49\agent.backup` 复制到 `D:\OneDrive\CODE\repo-governance-hub\overrides`，逐项校验目录清单摘要后删除源目录。

## Commands
- `codex --version`
- `codex --help`
- `codex status`
- `./build.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\Core.Tests.ps1"`
- `./skills.ps1 发现 -Filter find-skills`
- `./skills.ps1 doctor --strict --threshold-ms 8000`
- `./skills.ps1 构建生效`
- PowerShell copy/verify/remove script for 7 historical residue directories from `.txn\build-3838547b49\agent.backup` to `D:\OneDrive\CODE\repo-governance-hub\overrides`.

## Evidence
- `codex --version`: `codex-cli 0.121.0`
- `codex --help`: command list available; no load-chain status in help output.
- `codex status`: `platform_na`
  - reason: non-interactive execution returned `Error: stdin is not a terminal`
  - alternative_verification: active repo rules were provided in task context; local path and generated script were verified by commands above.
  - evidence_link: this file
  - expires_at: 2026-05-21
- build: `Build success: D:\OneDrive\CODE\skills-manager\skills.ps1`
- unit test: `Passed: 123 Failed: 0`
- discovery: `1) [*] [skills] find-skills`
- doctor strict: exit code `0`; reported `Mappings: 91` and `Your system is ready for skills-manager.`
- hotspot: `构建完成：agent/ (共 91 项技能)` and all 5 target junctions recreated.
- manual import reconciliation: `manual_imports=31`, `manual_mappings=31`, `unmapped_manual=0`.
- independent count verification: `agent_dirs=91`, `codex_dirs=91`, `mappings=91`.
- independent target verification:
  - `C:\Users\sciman\.codex\skills -> D:\OneDrive\CODE\skills-manager\agent`
  - `C:\Users\sciman\.claude\skills -> D:\OneDrive\CODE\skills-manager\agent`
  - `C:\Users\sciman\.gemini\skills -> D:\OneDrive\CODE\skills-manager\agent`
  - `C:\Users\sciman\.gemini\antigravity\skills -> D:\OneDrive\CODE\skills-manager\agent`
  - `C:\Users\sciman\.trae\skills -> D:\OneDrive\CODE\skills-manager\agent`
- `~/.codex/skills/find-skills/SKILL.md`: readable and starts with `name: find-skills`.
- historical residue backup/clear:
  - copied and removed from source:
    - `agent-skills-skills-composition-patterns` (`14` files)
    - `agent-skills-skills-react-best-practices` (`76` files)
    - `custom-windows-encoding-guard` (`2` files)
    - `governance-clarification-protocol` (`1` file)
    - `governance-teaching-lite-output` (`1` file)
    - `skills-2-skills-remotion` (`42` files)
    - `skills-skills-.curated-cloudflare-deploy` (`312` files)
  - source verification: all 7 source directories no longer exist under `.txn\build-3838547b49\agent.backup`.
  - destination verification: all 7 destination directories exist under `D:\OneDrive\CODE\repo-governance-hub\overrides`.
  - old backup directory count after cleanup: `90`.

## Rollback
- Revert code/config changes:
  - `git restore -- src/Core.ps1 skills.ps1 skills.json tests/Unit/Core.Tests.ps1 docs/change-evidence/20260421-junction-target-repair.md`
- Rebuild old output after revert:
  - `./build.ps1`
  - `./skills.ps1 构建生效`
- To remove user-level junctions without restoring old code:
  - `./skills.ps1 解除关联`
