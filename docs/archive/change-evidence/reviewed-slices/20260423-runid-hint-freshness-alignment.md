# 2026-04-23 run-id 自动解析提示口径修复

## 规则与归宿
- Rule IDs: `R1,R2,R6,R8`
- 当前落点: `src/Commands/AuditTargets.ps1`, `tests/Unit/AuditTargets.Tests.ps1`
- 目标归宿: `<run-id>` 解析与提示文案使用同一 freshness 判定口径，避免“提示可用但实际不可用”

## 风险分级
- 风险等级: 中
- 影响面: `--run-id` / `--recommendations` 占位符解析失败提示信息
- 兼容策略: 保持解析策略不变（仍优先 fresh，stale-only 仍阻断），仅修复提示歧义并补测试

## 执行命令与关键输出
1. `./build.ps1`
   - `Build success: D:\CODE\skills-manager\skills.ps1`
2. `Invoke-Pester -Path ./tests/Unit/AuditTargets.Tests.ps1`
   - `Passed: 65 Failed: 0`
3. `./skills.ps1 发现`
   - 映射发现流程通过
4. `./skills.ps1 doctor --strict --threshold-ms 8000`
   - `Your system is ready for skills-manager.`
5. `./skills.ps1 构建生效`
   - `构建完成：agent/ (共 89 项技能)`，目标链接同步成功

## 变更摘要
- 新增 run 候选分类函数：按 `fresh / stale / unknown / missing_required` 分类。
- `Get-AuditLatestRunId` 与 `Get-AuditRunIdHintText` 复用同一分类数据。
- 提示文案调整为：
  - 有 fresh 时：显示 `可用 fresh run-id`
  - 无 fresh 时：明确提示先扫描，并附 `stale run-id` / `unknown` / `missing_required` 明细
- 单测补强：`only stale` 场景断言提示包含 `stale run-id` 与扫描提示。

## 回滚动作
1. 回滚上述两个源码文件到变更前版本。
2. 重新执行：
   - `./build.ps1`
   - `Invoke-Pester -Path ./tests/Unit/AuditTargets.Tests.ps1`
   - `./skills.ps1 发现`
   - `./skills.ps1 doctor --strict --threshold-ms 8000`
   - `./skills.ps1 构建生效`
