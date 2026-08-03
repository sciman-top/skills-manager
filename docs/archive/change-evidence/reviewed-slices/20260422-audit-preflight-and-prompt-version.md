# 20260422-audit-preflight-and-prompt-version

- rule_id: R1,R2,R6,R8
- risk_level: low
- scope: `src/Commands/AuditTargets*.ps1`、`src/Commands/Utils.ps1`、`tests/Unit/AuditTargets.Tests.ps1`

## Basis
- 用户确认实施三项优化：预防占位符 run-id、研究前 stale 预检、运行态提示词版本校验。
- 目标：把阻断前移到“研究前”，减少无效审查执行，并降低 run 产物提示词版本漂移风险。

## Commands
1. `./build.ps1`
2. `Invoke-Pester tests/Unit/AuditTargets.Tests.ps1`
3. `./skills.ps1 发现`
4. `./skills.ps1 doctor --strict --threshold-ms 8000`
5. `./skills.ps1 构建生效`

## Key Output
- build: `Build success: D:\CODE\skills-manager\skills.ps1`
- unit test: `Passed: 53 Failed: 0`
- test(发现): 成功列出技能清单（exit_code=0）
- contract/invariant(doctor): `Your system is ready for skills-manager.`
- hotspot(构建生效): `=== 构建生效流程完成 ===`

## Rollback
1. 回退文件：
   - `src/Commands/AuditTargets.Apply.ps1`
   - `src/Commands/AuditTargets.Args.ps1`
   - `src/Commands/AuditTargets.Bundle.ps1`
   - `src/Commands/AuditTargets.ps1`
   - `src/Commands/Utils.ps1`
   - `tests/Unit/AuditTargets.Tests.ps1`
2. 重新生成入口：`./build.ps1`
3. 按门禁顺序复验：`Invoke-Pester tests/Unit/AuditTargets.Tests.ps1`、`发现`、`doctor --strict --threshold-ms 8000`、`构建生效`

## Notes
- 新增 `审查目标 预检`（`preflight`）命令，支持 `--run-id` 或 `--recommendations`：
  - 前置检查 `stale_snapshot`
  - 校验 run 包提示词契约版本
  - 输出 `preflight-report.json`
- 审查包新增 `audit-meta.json`，记录 `prompt_contract_version` 供预检比对。
- 运行态 `outer-ai-prompt.md` 追加 `Prompt-Contract-Version` 元数据行。
