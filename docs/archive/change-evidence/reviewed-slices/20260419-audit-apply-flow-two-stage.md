# 2026-04-19 审查目标应用流程优化（两阶段确认）

## 依据
- 用户反馈：dry-run 与 apply 流程容易被误解为“已落盘”。
- 目标：把菜单单入口改为“两阶段执行（dry-run -> 确认口令 -> apply）”，同时保留 `--apply --yes` 直达能力。

## 变更落点
- `src/Commands/AuditTargets.ps1`
  - 新增子命令别名：`应用确认` / `apply-flow`
  - 新增子命令别名：`状态` / `status`
  - dry-run 阶段新增“未落盘”明确提示及 apply 命令指引
  - dry-run 增加显式确认口令 `我知道未落盘`（支持 `--dry-run-ack` 非交互传入）
  - 新增 `Get-AuditApplyConfirmationToken`
  - 新增 `Get-AuditDryRunAckToken`
  - 新增 `Invoke-AuditRecommendationsTwoStageApply`
  - `apply-report.json` 新增 `persisted`、`changed_counts`
  - 在命令分发中新增 `apply_flow` 动作
- `src/Commands/Utils.ps1`
  - 帮助文本加入 `应用确认 --recommendations <file>`、`状态`、`--dry-run-ack`
  - 菜单 10 改为两阶段入口（调用 `apply-flow`）
  - 菜单 11 保留直接 `--apply --yes`
  - 菜单新增“查看最近审查应用状态”
- `tests/Unit/AuditTargets.Tests.ps1`
  - 新增 `apply-flow` / `应用确认` 解析测试
  - 新增 `status/状态` 解析测试
  - 新增 dry-run 确认 + `persisted/changed_counts` 测试
- `tests/E2E/SkillAudit.Tests.ps1`
  - 新增 apply 成功后的 `persisted/changed_counts` 断言
- 文档：
  - `README.md`
  - `README.en.md`
- 生成产物：
  - `skills.ps1`（由 `build.ps1` 生成）

## 执行命令与证据
1. `./build.ps1`
   - 关键输出：`Build success: D:\OneDrive\CODE\skills-manager\skills.ps1`
2. `./skills.ps1 发现`
   - 关键输出：命令执行成功（Exit 0），技能清单正常输出。
3. `./skills.ps1 doctor --strict --threshold-ms 8000`
   - 关键输出：`Your system is ready for skills-manager.`
4. `./skills.ps1 构建生效`
   - 关键输出：`=== 构建生效流程完成 ===`
5. `Invoke-Pester -Path tests/Unit/AuditTargets.Tests.ps1`
   - 关键输出：`Passed: 35 Failed: 0`
6. `Invoke-Pester -Path tests/E2E/SkillAudit.Tests.ps1`
   - 关键输出：`Passed: 2 Failed: 0`
7. `./skills.ps1 审查目标 状态`
   - 关键输出：显示最近一次 `mode/success/persisted/changed_counts`

## 回滚方案
1. 回退以下文件到变更前版本：
   - `src/Commands/AuditTargets.ps1`
   - `src/Commands/Utils.ps1`
   - `tests/Unit/AuditTargets.Tests.ps1`
   - `tests/E2E/SkillAudit.Tests.ps1`
   - `README.md`
   - `README.en.md`
2. 执行 `./build.ps1` 重建 `skills.ps1`。
3. 重新执行门禁顺序验证：`发现 -> doctor --strict -> 构建生效`。
