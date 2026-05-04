# 2026-05-04 invalid mapping resolver reuse

## 规则与风险
- 规则: R1/R2/R5/R6/R8
- 风险等级: low
- 落点: `src/Commands/Install.ps1` + generated `skills.ps1`
- 目标归宿: `Get-InvalidMappings` 复用 agent mapping resolver，避免清理路径、cache-check 路径和真实构建路径各自维护一套 mapping 解析逻辑。

## 任务拆分状态
- 总任务数: `5`
- 已完成: `4`
  - agent build cache skip
  - directory fingerprint fast path
  - agent mapping resolver refactor
  - invalid mapping resolver reuse
- 待推进: `1`
  - final audit of remaining large hot files and push/收口 decision

## 依据
- `Get-InvalidMappings` 仍手写 vendor/manual source 解析、safe path 校验、source validity 检查。
- 第 3 轮已引入 `Resolve-AgentMappingForAgent`，继续保留第三套解析会增加长期维护漂移风险。

## 变更
- `Get-InvalidMappings` 改为使用 `New-AgentMappingResolveContext` 和 `Resolve-AgentMappingForAgent`。
- 继续复用 `Test-ResolvedAgentMappingSkillDir` 与 `Get-ResolvedAgentMappingInvalidReason` 判断 source validity。
- 保留清理命令原有短 reason 分类：`非法 mapping.from`、`非法 mapping.to`、`manual 导入不存在或无效`、`mapping.from 越界`、`源目录不存在`、`缺少标记文件`。
- 补充 Pester 覆盖：invalid mapping discovery 复用 resolver context，重复 manual/vendor source 只解析一次。

## 执行命令与关键输出
- `.\build.ps1`
  - `Build success: D:\CODE\skills-manager\skills.ps1`
- `pwsh -NoProfile -Command "Invoke-Pester -Path 'tests/Unit/BuildCache.Tests.ps1'"`
  - `Tests Passed: 23, Failed: 0`
- `.\skills.ps1 发现`
  - discovered `87` skills
- `.\skills.ps1 doctor --strict --threshold-ms 8000`
  - `Your system is ready for skills-manager.`
- `.\skills.ps1 构建生效`
  - wall time: `3436ms`
  - `构建 Agent 输入未变化，跳过重建：outputs=87, signature=3c0bcdd1a996`
- post-check doctor:
  - `build_agent_cache_check: last=2025ms`
  - `build_apply_total: last=3707ms`
- `.\tests\run.ps1`
  - Unit: `Tests Passed: 350, Failed: 0`
  - E2E: `Tests Passed: 11, Failed: 0`
- `.\scripts\quality\run-local-quality-gates.ps1 -Profile quick -AllowDirtyWorktree`
  - `Local quality gates passed (quick).`
- `git diff --check`
  - pass; CRLF conversion warnings only.

## 回滚
- Revert:
  - `src/Commands/Install.ps1`
  - generated `skills.ps1`
  - `tests/Unit/BuildCache.Tests.ps1`
- Then rerun:
  - `.\build.ps1`
  - `.\skills.ps1 发现`
  - `.\skills.ps1 doctor --strict --threshold-ms 8000`
  - `.\skills.ps1 构建生效`
