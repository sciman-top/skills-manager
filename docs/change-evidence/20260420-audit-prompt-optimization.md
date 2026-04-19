# 20260420-audit-prompt-optimization

- rule_id: R1,R2,R6,R8
- risk_level: low
- scope: `src/Commands/AuditTargets.ps1`（内置 AI 提示词三处增强） + `skills.ps1`（由 build 同步生成）
- current_anchor: `src/Commands/AuditTargets.ps1`
- target_destination: 保持审查链路不变，仅提升提示词可执行性/一致性

## Basis
- 用户要求：对项目中给 AI 代理的内置提示词做改进、完善、优化。
- 本次聚焦“实际生效链路”三处提示词：
  - `Get-DefaultAuditOuterAiPrompt`
  - `Write-AuditAiBrief`
  - `Write-AuditOuterAiPromptFile`
- 目标：在不改 schema 和命令语义前提下，降低外层 AI 漏项与越序执行风险。

## Changes
1. 强化阶段门禁：明确“先产出 recommendations.json -> 再 dry-run -> 再等待确认 apply”。
2. 增加自检要求：dry-run 前检查 JSON 可解析、字段同构、关键理由/来源字段完整。
3. 强化质量约束：新增“证据不足允许不推荐”“不得臆造 repo 事实或来源”。
4. 统一输出契约：空列表说明、序号稳定、双理由展示、未确认不得 `--apply --yes`。

## Commands
1. `./build.ps1`
2. `./skills.ps1 发现`
3. `./skills.ps1 doctor --strict --threshold-ms 8000`
4. `./skills.ps1 构建生效`
5. `pwsh -NoProfile -Command "Invoke-Pester -Path 'tests/Unit/AuditTargets.Tests.ps1'"`
6. `codex --version`
7. `codex --help`
8. `codex status`

## Key Output
- build: `Build success: D:\OneDrive\CODE\skills-manager\skills.ps1`
- test(发现): 成功输出技能清单，exit_code=0
- contract/invariant(doctor): `Your system is ready for skills-manager.`
- hotspot(构建生效): `=== 构建生效流程完成 ===`
- unit test: `Passed: 39 Failed: 0`
- codex --version: `codex-cli 0.121.0`
- codex --help: 成功返回命令帮助，exit_code=0

## N/A
- type: `platform_na`
- item: `codex status`
- reason: 当前非交互终端环境，命令返回 `stdin is not a terminal`
- alternative_verification: 使用 `codex --version` + `codex --help` + 本地规则与门禁证据补齐平台诊断
- evidence_link: `docs/change-evidence/20260420-audit-prompt-optimization.md`
- expires_at: `2026-04-27`

- type: `gate_na`
- item: `supply_chain_gate`
- reason: 本次仅修改提示词文本与生成脚本文案，无依赖/锁文件变更
- alternative_verification: 全链路门禁 + 定向单测 + diff 人工审查
- evidence_link: `docs/change-evidence/20260420-audit-prompt-optimization.md`
- expires_at: `2026-04-27`

## Rollback
1. 回退文件：`src/Commands/AuditTargets.ps1`、`skills.ps1`
2. 重新生成：`./build.ps1`
3. 复验门禁：`./skills.ps1 发现` -> `./skills.ps1 doctor --strict --threshold-ms 8000` -> `./skills.ps1 构建生效`
