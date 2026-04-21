# 2026-04-21 profile-only skill discovery

## Goal
- 当前落点：`src/Commands/AuditTargets.ps1` 的目标仓审查链路。
- 目标归宿：把“发现新技能”合并为 `审查目标` 的 profile-only 模式，复用审查包、外层 AI 提示词、`recommendations.json`、dry-run/apply，不新增独立流程。
- 风险等级：中。原因是扩展审查包 schema 语义与生成入口，但保持 `schema_version = 2` 和目标仓审查默认行为兼容。

## Changes
- 新增子命令：`./skills.ps1 审查目标 发现新技能 [--query <text>] [--out <dir>]`，英文别名 `discover-skills` / `discover`。
- 新增 profile-only 审查包生成函数：输出 `user-profile.json`、`installed-skills.json`、`source-strategy.json`、`recommendations.template.json`、`ai-brief.md`、`outer-ai-prompt.md`，不输出 `repo-scan.json`。
- 新增 `source-strategy.json`，显式列出官方文档、`skills.sh`、GitHub Trending monthly、高质量社区项目、最佳实践、`find-skills` 等默认来源策略。
- `recommendations.template.json` 增加 `recommendation_mode` 与 `discovery_query`；目标仓模式仍要求 `target_scan_used = true`，profile-only 模式要求 `target_scan_used = false`。
- 菜单、帮助、README、单测同步更新。

## Verification
- `./build.ps1`
  - exit_code: `0`
  - key_output: `Build success: D:\OneDrive\CODE\skills-manager\skills.ps1`
- `Invoke-Pester -Script tests\Unit\AuditTargets.Tests.ps1`
  - exit_code: `0`
  - key_output: `Passed: 50 Failed: 0`
- `./skills.ps1 审查目标 发现新技能 --query "repo governance" --out <temp-dir>`
  - exit_code: `0`
  - key_output: `新技能发现包已生成`; generated `source-strategy.json`; no `repo-scan.json` is required in profile-only mode.
- `./skills.ps1 发现`
  - exit_code: `0`
  - key_output: discovered list rendered; selected skills include `find-skills`; total visible entries reached `132`.
- `./skills.ps1 doctor --strict --threshold-ms 8000`
  - exit_code: `0`
  - key_output: `Mappings: 91`; `Your system is ready for skills-manager.`
- `./skills.ps1 构建生效`
  - exit_code: `0`
  - key_output: `构建完成：agent/ (共 91 项技能)`; all five target skill directories recreated as junctions to `D:\OneDrive\CODE\skills-manager\agent`.

## Codex diagnostics
- `codex --version`
  - exit_code: `0`
  - key_output: `codex-cli 0.121.0`
- `codex --help`
  - exit_code: `0`
  - key_output: command list includes `exec`, `review`, `mcp`, `apply`, `resume`, `cloud`, `features`.
- `codex status`
  - classification: `platform_na`
  - reason: non-interactive terminal lacks TTY.
  - exit_code: `1`
  - key_output: `Error: stdin is not a terminal`
  - alternative_verification: recorded active repo path and verified generated junction targets point to `D:\OneDrive\CODE\skills-manager\agent`.
  - evidence_link: this file.
  - expires_at: `2026-05-21`

## Rollback
- Revert this change set in `README.md`, `skills.ps1`, `src/Commands/AuditTargets.ps1`, `src/Commands/Utils.ps1`, and `tests/Unit/AuditTargets.Tests.ps1`.
- Re-run gates in order: `./build.ps1` -> `./skills.ps1 发现` -> `./skills.ps1 doctor --strict --threshold-ms 8000` -> `./skills.ps1 构建生效`.
