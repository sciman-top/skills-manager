# 20260419-audit-profile-import-and-bundle-hardening

- rule_id: R1,R2,R3,R6,R8
- risk_level: medium
- scope:
  - `src/Commands/AuditTargets.ps1`
  - `tests/Unit/AuditTargets.Tests.ps1`
  - `tests/E2E/SkillAudit.Tests.ps1`

## Basis
- 目标：增强“导入结构化需求”和“生成审查包”的鲁棒性与可追溯性。
- 关键改进：
  - 结构化需求导入强校验/归一化（拒绝非法 structured，标量自动归一为数组）。
  - 审查包关键文件从“仅存在校验”升级为“存在 + 可解析 + 关键字段校验”。
  - 审查包提示词明确列出 repo-scan 输入路径（单目标/多目标）。
  - installed-skills 生成失败不再静默吞错，改为显式失败。
  - run_id 升级为毫秒精度，降低同秒冲突风险。

## Commands
1. `./build.ps1`
2. `Invoke-Pester -Path tests/Unit/AuditTargets.Tests.ps1`
3. `Invoke-Pester -Path tests/E2E/SkillAudit.Tests.ps1`
4. 门禁顺序复验：
   - `./build.ps1`
   - `./skills.ps1 发现`
   - `./skills.ps1 doctor --strict --threshold-ms 8000`
   - `./skills.ps1 构建生效`

## Key Output
- Unit: `Passed: 33 Failed: 0`
- E2E: `Passed: 2 Failed: 0`
- build: `Build success: ...\skills.ps1`
- discover: 正常输出技能清单（exit_code=0）
- doctor: `Your system is ready for skills-manager.`
- hotspot: `=== 构建生效流程完成 ===`

## Rollback
1. 回退源码：
   - `src/Commands/AuditTargets.ps1`
   - `tests/Unit/AuditTargets.Tests.ps1`
   - `tests/E2E/SkillAudit.Tests.ps1`
2. 重新生成主脚本：`./build.ps1`
3. 按门禁顺序复验：`发现 -> doctor --strict -> 构建生效`

## Notes
- 首次 `doctor` 曾出现瞬时 DNS 解析失败（github.com），重试后恢复正常；最终以通过结果计入门禁证据。

## Platform Diagnostics (Codex)
- cmd: `codex --version`
  - exit_code: 0
  - key_output: `codex-cli 0.121.0`
- cmd: `codex --help`
  - exit_code: 0
  - key_output: `Codex CLI ...`
- cmd: `codex status`
  - exit_code: 1
  - key_output: `Error: stdin is not a terminal`
  - classification: `platform_na`
  - reason: non-interactive execution environment does not support terminal-bound status command
  - alternative_verification: use `codex --version` and `codex --help` as minimum diagnostic evidence
  - evidence_link: `docs/change-evidence/20260419-audit-profile-import-and-bundle-hardening.md`
  - expires_at: `2026-05-31`
