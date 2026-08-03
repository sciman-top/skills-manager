# 20260422-audit-prompt-mcp-alignment

- rule_id: R1,R2,R6,R8
- risk_level: low
- scope: `src/Commands/AuditTargets.ps1`、`skills.ps1`、`tests/Unit/AuditTargets.Tests.ps1`

## Basis
- 用户要求在新增 MCP 建议功能后，自动连续执行并评估、优化本仓提供给 AI 代理的内置提示词。
- 目标：让默认提示词、`ai-brief.md`、运行态 `outer-ai-prompt.md` 与真实 recommendations 校验器保持一致，减少外层 AI “自检通过但 apply 失败”的情况。

## Commands
1. `./build.ps1`
2. `Invoke-Pester tests/Unit/AuditTargets.Tests.ps1`
3. `./skills.ps1 发现`
4. `./skills.ps1 doctor --strict --threshold-ms 8000`
5. `./skills.ps1 构建生效`

## Key Output
- build: `Build success: D:\CODE\skills-manager\skills.ps1`
- unit test: `Passed: 51 Failed: 0`
- test(发现): 成功列出技能清单（exit_code=0）
- contract/invariant(doctor): `Your system is ready for skills-manager.`
- hotspot(构建生效): `=== 构建生效流程完成 ===`

## Rollback
1. 回退源码与测试文件：`src/Commands/AuditTargets.ps1`、`tests/Unit/AuditTargets.Tests.ps1`
2. 重新生成入口：`./build.ps1`
3. 按门禁顺序复验：`Invoke-Pester tests/Unit/AuditTargets.Tests.ps1`、`发现`、`doctor --strict --threshold-ms 8000`、`构建生效`

## Notes
- 提示词新增约束：target-repo 模式必须读取 `user-profile.json` 与 `installed-skills.json`，自检需覆盖 `decision_basis.summary`、MCP `name == server.name`、重复建议阻断。
- 同步修复 `Write-AuditAiBrief` 中未转义单反引号导致的 Markdown 控制字符污染问题。
