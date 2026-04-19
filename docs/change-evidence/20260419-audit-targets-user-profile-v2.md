# 2026-04-19 audit-targets user profile v2

- 规则 ID: R1, R2, R6, R8, E6
- 风险等级: medium
- 当前落点: `src/Commands/AuditTargets.ps1`, `src/Commands/Utils.ps1`, `README.md`, `README.en.md`, `tests/Unit/AuditTargets.Tests.ps1`, `tests/E2E/SkillAudit.Tests.ps1`
- 目标归宿: `audit-targets` 工作流支持全局 `user_profile` schema v2、recommendations schema v2，以及“新增/卸载建议按序号选择执行”并补齐入口文案

## 依据

- 项目计划: `docs/superpowers/plans/2026-04-19-skill-audit-user-profile-integration.md`
- 设计文档: `docs/superpowers/specs/2026-04-19-skill-audit-user-profile-design.md`

## 命令

- `codex --version`
- `codex --help`
- `codex status`
- `./build.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester tests\Unit\AuditTargets.Tests.ps1"`
- `powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester tests\E2E\SkillAudit.Tests.ps1"`
- `./skills.ps1 发现`
- `./skills.ps1 doctor --strict --threshold-ms 8000`
- `./skills.ps1 构建生效`

## 关键输出

- `codex --version`: `codex-cli 0.121.0`
- `codex status`: 非交互终端失败，输出 `Error: stdin is not a terminal`
- `./build.ps1`: `Build success: D:\OneDrive\CODE\skills-manager\skills.ps1`
- `Invoke-Pester tests\Unit\AuditTargets.Tests.ps1`: `Passed: 20 Failed: 0`
- `Invoke-Pester tests\E2E\SkillAudit.Tests.ps1`: `Passed: 1 Failed: 0`
- `./skills.ps1 doctor --strict --threshold-ms 8000`: `Your system is ready for skills-manager.`
- `./skills.ps1 构建生效`: 完成 `agent/` 重建并重新关联本地 skills junction

## 变更摘要

- `audit-targets.json` 默认 schema 从 `version=1` 升级到 `version=2`
- 新增 `user_profile` 默认结构与自动迁移/补齐逻辑
- 新增 `profile-set`, `profile-show`, `profile-structure` 及中文别名解析
- 新增 `Set-AuditUserProfileRawText`, `Show-AuditUserProfile`, `Import-AuditUserProfileStructured`
- `scan` 前置校验 `user_profile.raw_text`，缺失时阻断
- `scan` 新增 `user-profile.json` 输出，并强化 `ai-brief.md` 的“双依据 + 可联网研究 + 不自动安装”约束
- `recommendations` schema 升级到 `version=2`，要求 `decision_basis`、`reason_user_profile`、`reason_target_repo`、`removal_candidates`
- `apply` 现在会列出“新增建议 / 卸载建议”双清单，每项带序号与简短依据说明
- 执行时支持按序号分别选择新增项和卸载项；卸载不再只是报告，可以由用户显式选中后执行
- 两份清单独立编号；新增和卸载的序号解析在真正状态变更前完成，先选卸载不会影响新增清单的命中关系
- 主菜单新增 `17) 审查目标` 子入口，帮助文本与中英文 README 同步说明 profile、双依据、编号选择与 `--add-indexes` / `--remove-indexes`
- 单元与 E2E 测试覆盖 v2 schema、导入结构化需求、扫描阻断、建议卸载保留到 plan、按序号执行新增与卸载、菜单入口存在、跨清单编号稳定性

## N/A

- `platform_na`
- reason: `codex status` 在当前非交互终端环境下不可执行
- alternative_verification: 使用 `codex --version`、`codex --help` 和仓库内 `AGENTS.md`/运行门禁确认当前 CLI 与工作区状态
- evidence_link: `docs/change-evidence/20260419-audit-targets-user-profile-v2.md`
- expires_at: `2026-04-26`

## 回滚

- `git checkout -- src/Commands/AuditTargets.ps1 src/Commands/Utils.ps1 README.md README.en.md tests/Unit/AuditTargets.Tests.ps1 tests/E2E/SkillAudit.Tests.ps1 skills.ps1`
- 如需回退运行态产物，再执行 `./build.ps1` 与 `./skills.ps1 构建生效`
