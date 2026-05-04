# 2026-05-04 agent mapping resolver refactor

## 规则与风险
- 规则: R1/R2/R5/R6/R8
- 风险等级: low-to-medium
- 落点: `src/Commands/Install.ps1` + generated `skills.ps1`
- 目标归宿: 让 `Get-AgentBuildState` 与 `构建Agent` 共用 agent mapping 解析逻辑，减少重复校验与缓存代码，保持构建失败分流不变。

## 任务拆分状态
- 总任务数: `5`
- 已完成: `3`
  - agent build cache skip
  - directory fingerprint fast path
  - agent mapping resolver refactor
- 待推进: `2`
  - invalid mapping / cleanup path 复用 resolver
  - final audit of remaining large hot files and push/收口 decision

## 依据
- 前两轮已把 `构建生效` 重复执行从完整重建推进到 cache-hit 快路径。
- `Get-AgentBuildState` 与 `构建Agent` 仍各自维护 vendor/manual source 解析、safe path 校验、source validity cache 和 output path 计算，后续维护容易产生语义漂移。

## 变更
- 新增 `New-AgentMappingResolveContext`，集中持有 `vendor_base`、`manual_source`、`skill_dir_validity` 缓存。
- 新增 `Resolve-AgentMappingForAgent`，统一解析 sync mapping、manual/vendor source、output relative path、destination path 和 cache key。
- 新增 `Test-ResolvedAgentMappingSkillDir` 与 `Get-ResolvedAgentMappingInvalidReason`，统一 source validity 判断与错误原因。
- `Get-AgentBuildState` 改为使用 resolver 生成 signature records。
- `构建Agent` 改为使用 resolver 执行真实 mirror，保留无效技能跳过、manual source 缺失失败、path 越界失败的原分流。
- 补充 Pester 覆盖：同一 resolver context 下重复 manual/vendor source 只解析一次。

## 执行命令与关键输出
- `.\build.ps1`
  - `Build success: D:\CODE\skills-manager\skills.ps1`
- `.\tests\run.ps1`
  - Unit: `Tests Passed: 349, Failed: 0`
  - E2E: `Tests Passed: 11, Failed: 0`
- `.\skills.ps1 发现`
  - discovered `87` skills
- `.\skills.ps1 doctor --strict --threshold-ms 8000`
  - `Your system is ready for skills-manager.`
- `.\skills.ps1 构建生效`
  - wall time: `3505ms`
  - `构建 Agent 输入未变化，跳过重建：outputs=87, signature=3c0bcdd1a996`
- post-check doctor:
  - `build_agent_cache_check: last=1665ms`
  - `build_apply_total: last=3236ms`
- Windows PowerShell 5.1 smoke:
  - dot-sourced `skills.ps1`
  - `New-AgentMappingResolveContext` returned expected cache keys
- `.\scripts\quality\run-local-quality-gates.ps1 -Profile quick -AllowDirtyWorktree`
  - `Local quality gates passed (quick).`
- `git diff --check`
  - exit `0`; only CRLF normalization warnings from Git.

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
