# 20260420-audit-targets-hardening

- rule_id: R1,R2,R3,R6,R8
- risk_level: medium
- scope: `src/Commands/AuditTargets.ps1` + `tests/Unit/AuditTargets.Tests.ps1`
- current_anchor: `src/Commands/AuditTargets.ps1`（审查目标命令）
- target_destination: 同文件修复并通过 `build.ps1` 同步到根 `skills.ps1`

## Basis
- 目标：全面深查“审查目标”代码，修复真实缺陷并增强鲁棒性。
- 发现问题：
  - 双引号 here-string 内使用 Markdown 反引号，触发 PowerShell 转义（如 `` `r ``），导致 `outer-ai-prompt.md`/`ai-brief.md` 混入控制字符。
  - `Load-AuditRecommendations` 对 `decision_basis.*` 使用 `[bool]` 强转，字符串 `"true"` 会被误判为通过。
  - `sources` 仅校验数组长度，空白字符串与重复项可穿透。

## Changes
1. 将审查提示词与 brief 相关 here-string 中的 Markdown 反引号改为双反引号字面量，避免控制字符注入。
2. 新增严格布尔校验：`decision_basis.user_profile_used/target_scan_used/source_strategy_used` 必须是布尔值 `true`。
3. 新增 `Normalize-AuditSources`：对 `sources` 做 trim、去重，并阻断“全空白 source”。
4. 清理 `Invoke-AuditRecommendationsApply` 中未使用的 `$applied` 累积变量。
5. 修正参数报错文案：`add/update` 共用提示改为“目标仓操作需要 name 和 path”。
6. 补充单测覆盖：
  - 提示词无控制字符污染；
  - `decision_basis` 非布尔值阻断；
  - `sources` 去重归一与空白阻断。

## Commands
1. `./build.ps1`
2. `Invoke-Pester -Path tests/Unit/AuditTargets.Tests.ps1 -PassThru`
3. `./build.ps1`
4. `./skills.ps1 发现 skill`
5. `./skills.ps1 doctor --strict --threshold-ms 8000`
6. `./skills.ps1 构建生效`

## Key Output
- unit test: `Passed: 39 Failed: 0`
- build: `Build success: D:\OneDrive\CODE\skills-manager\skills.ps1`
- test(发现): 成功输出技能列表，exit_code=0
- contract/invariant(doctor): `Your system is ready for skills-manager.`
- hotspot(构建生效): `=== 构建生效流程完成 ===`

## N/A
- supply_chain_gate: `gate_na`
- reason: 本次仅修改 PowerShell 逻辑与单测，无新增依赖与锁文件变化。
- alternative_verification: `git diff` 人工审查 + 全量门禁链路通过。
- evidence_link: `docs/change-evidence/20260420-audit-targets-hardening.md`
- expires_at: `2026-04-27`

## Rollback
1. 回退文件：`src/Commands/AuditTargets.ps1`、`tests/Unit/AuditTargets.Tests.ps1`
2. 重新生成：`./build.ps1`
3. 复验门禁：`./skills.ps1 发现 skill` -> `./skills.ps1 doctor --strict --threshold-ms 8000` -> `./skills.ps1 构建生效`
