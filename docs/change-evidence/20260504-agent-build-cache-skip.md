# 2026-05-04 agent build cache skip

## 规则与风险
- 规则: R1/R2/R6/R8, E4
- 风险等级: low-to-medium
- 落点: `src/Commands/Install.ps1` + generated `skills.ps1`
- 目标归宿: `构建生效` 在 agent 输入未变化时跳过完整重建，保留原事务构建作为 cache miss / unsafe fallback。

## 依据
- 基线 `doctor --strict --threshold-ms 8000` 通过，但 `build_agent` / `mapping` 仍是主要慢路径。
- 旧 `.build-cache.json` 在真实构建后保持 `{}`，因为 `Start-BuildTransaction` 会先移走 `agent/`，导致每个 mapping 的目标目录都不存在，旧 mirror cache 无法产生重复构建 skip。

## 变更
- 新增 agent build state signature：包含算法版本、同步 mapping、override、源目录指纹和预期输出目录。
- `构建生效` 在事务开始前做保守 cache hit 判断：仅当签名匹配、`agent/` 存在且每个预期输出目录存在时跳过 `构建Agent`。
- cache miss、签名不匹配、输出缺失、invalid source、dry-run 时仍走原完整事务构建。
- 成功完整构建后写入 `__agent_build_*` 元数据；构建失败或复用旧目录失败时不写入快路径状态。

## 执行命令与关键输出
- `.\build.ps1`
  - `Build success: D:\CODE\skills-manager\skills.ps1`
- `Invoke-Pester -Script tests\Unit\BuildCache.Tests.ps1`
  - `Tests Passed: 20, Failed: 0`
- cache warm-up: `.\skills.ps1 构建生效`
  - `构建阶段耗时：mapping=10977ms, overrides=1ms, postscan=431ms`
- cache hit run: `.\skills.ps1 构建生效`
  - `构建 Agent 输入未变化，跳过重建：outputs=87, signature=4b473f40ddae`
  - shell wall time: about `6.6s` to `8.1s` on repeated local runs
- post-check: `.\skills.ps1 doctor --strict --threshold-ms 8000`
  - `Your system is ready for skills-manager.`
  - latest observed metrics after cache-hit runs: `build_agent last=10ms`, `build_agent_cache_check last=5250ms`, `build_apply_total last=7023ms`
- full regression: `.\tests\run.ps1`
  - Unit: `Tests Passed: 347, Failed: 0`
  - E2E: `Tests Passed: 11, Failed: 0`
- local quality gate: `.\scripts\quality\run-local-quality-gates.ps1 -Profile quick -AllowDirtyWorktree`
  - `Local quality gates passed (quick).`
- whitespace check: `git diff --check`
  - exit `0`; only CRLF normalization warnings from Git.

## 回滚
- Revert:
  - `src/Commands/Install.ps1`
  - generated `skills.ps1`
  - `tests/Unit/BuildCache.Tests.ps1`
- Delete ignored runtime cache if needed:
  - `.build-cache.json`
- Then rerun:
  - `.\build.ps1`
  - `.\skills.ps1 发现`
  - `.\skills.ps1 doctor --strict --threshold-ms 8000`
  - `.\skills.ps1 构建生效`
