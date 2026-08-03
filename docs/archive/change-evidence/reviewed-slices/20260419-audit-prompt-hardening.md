# 20260419-audit-prompt-hardening

- rule_id: R1,R2,R6,R8
- risk_level: low
- scope: `src/Commands/AuditTargets.ps1` 内置审查提示词增强（增删理由、空列表说明、序号稳定、缺字段阻断）

## Basis
- 用户要求“直接在提示词原处修改、优化”。
- 目标：降低外层 AI 输出遗漏“增删理由”的概率，并明确完成判定。

## Commands
1. `./build.ps1`
2. `./skills.ps1 发现`
3. `./skills.ps1 doctor --strict --threshold-ms 8000`
4. `./skills.ps1 构建生效`

## Key Output
- build: `Build success: D:\OneDrive\CODE\skills-manager\skills.ps1`
- test(发现): 成功列出技能清单（无报错退出，exit_code=0）
- contract/invariant(doctor): `Your system is ready for skills-manager.`
- hotspot(构建生效): `=== 构建生效流程完成 ===`

## Rollback
1. 回退源码文件：`src/Commands/AuditTargets.ps1`
2. 重新执行：`./build.ps1`
3. 按门禁顺序复验：`发现 -> doctor --strict -> 构建生效`

## Notes
- 本次仅修改内置提示词文本与输出契约文案，不改变 schema 结构与执行命令路径。
