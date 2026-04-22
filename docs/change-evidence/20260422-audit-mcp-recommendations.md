# 2026-04-22 审查目标增加 MCP 新增/卸载建议

## 变更归宿
- 当前落点：`src/Commands/AuditTargets*`、`tests/Unit/AuditTargets.Tests.ps1`、`tests/E2E/SkillAudit.Tests.ps1`、`README*.md`
- 目标归宿：目标仓审查流程支持 **技能 + MCP** 双通道建议（生成模板、dry-run 摘要、apply 执行、索引选择、状态报告）

## 规则映射
- `R1` 先定归宿再改动：先确认只改审查链路与对应测试/文档。
- `R2` 小步闭环：模板/快照 -> plan -> apply -> 参数解析 -> 测试。
- `R6` 硬门禁：执行 `build -> test -> contract/invariant -> hotspot`。
- `R8` 可追溯：记录命令、关键输出与回滚方式。

## 风险分级
- 风险等级：`medium`
- 原因：变更覆盖审查建议 schema 与 apply 执行路径，涉及交互选择与状态统计。

## 执行命令与证据
1. `./build.ps1`
   - 结果：`Build success: D:\CODE\skills-manager\skills.ps1`
2. `./skills.ps1 发现`
   - 结果：发现列表正常输出（96 项）。
3. `./skills.ps1 doctor --strict --threshold-ms 8000`
   - 结果：`Your system is ready for skills-manager.`
4. `./skills.ps1 构建生效`
   - 结果：构建和关联流程完成，预检 `OK`。
5. `Invoke-Pester tests/Unit/AuditTargets.Tests.ps1`
   - 结果：`Passed: 51 Failed: 0`
6. `Invoke-Pester tests/E2E/SkillAudit.Tests.ps1`
   - 结果：`Passed: 3 Failed: 0`

## 关键改动
- recommendations schema 新增：
  - `mcp_new_servers`
  - `mcp_removal_candidates`
- `installed-skills.json` 快照新增 MCP 事实与 MCP 指纹字段，stale 检测覆盖 MCP。
- 审查执行链路新增 MCP 计划/汇总/应用：
  - dry-run 输出 MCP 新增/卸载项
  - apply 支持 MCP 选择参数并执行新增/卸载
  - `changed_counts` 扩展 MCP 统计字段
- CLI 新参数：
  - `--mcp-add-indexes`
  - `--mcp-remove-indexes`
- 外层提示词与 brief 同步 MCP 建议约束与摘要格式。

## N/A 记录
- 无 `platform_na`
- 无 `gate_na`

## 回滚动作
1. 回滚源码：`git restore --source=HEAD -- <changed-files>`
2. 回滚生成脚本：恢复 `skills.ps1` 到上一个稳定提交版本并重新执行 `./build.ps1`
3. 回滚运行态：执行 `./skills.ps1 构建生效` 重新同步代理目录
