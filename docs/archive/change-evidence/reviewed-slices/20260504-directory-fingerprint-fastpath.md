# 2026-05-04 directory fingerprint fast path

## 规则与风险
- 规则: R1/R2/R6/R8, E4
- 风险等级: low
- 落点: `src/Commands/Install.ps1` + generated `skills.ps1`
- 目标归宿: 降低 `构建生效` cache-hit 前的目录指纹扫描成本，保持 cache miss 时原事务重建路径不变。

## 依据
- 上一轮 agent build cache skip 已让重复构建避开完整 `agent/` 重建。
- 剩余热点集中在 `build_agent_cache_check`，本地 `doctor` 记录约 `5487ms`，主要来自 `Get-AgentBuildState -> Get-DirectoryFingerprint` 的 PowerShell pipeline 递归枚举与排序。

## 变更
- `Get-DirectoryFingerprint` 在 PS 7/.NET 支持时从 `Get-ChildItem | Sort-Object` 改为 .NET `Directory.GetFiles` + `Array.Sort` + `StringBuilder`。
- 保留 Windows PowerShell 5.1 兼容回退：缺少 `System.IO.EnumerationOptions` 时走原 PowerShell pipeline 实现。
- 保持原有 metadata fingerprint 语义：相对路径、文件长度、`LastWriteTimeUtc.Ticks`。
- 显式跳过 hidden/system 文件并忽略不可访问路径，保持与原 `Get-ChildItem` 默认枚举边界接近。
- bump agent build cache algorithm 到 `agent-build-v20260504.2`，避免旧签名跨实现复用。
- 补充单元测试覆盖 unchanged nested tree 的 fingerprint 稳定性。

## 执行命令与关键输出
- `.\build.ps1`
  - `Build success: D:\CODE\skills-manager\skills.ps1`
- `.\tests\run.ps1`
  - Unit: `Tests Passed: 348, Failed: 0`
  - E2E: `Tests Passed: 11, Failed: 0`
- `.\skills.ps1 发现`
  - discovered `87` skills
- `.\skills.ps1 doctor --strict --threshold-ms 8000`
  - `Your system is ready for skills-manager.`
- cache warm-up after algorithm bump: `.\skills.ps1 构建生效`
  - wall time: `18448ms`
  - `构建阶段耗时：mapping=11924ms, overrides=2ms, postscan=398ms`
- cache-hit run: `.\skills.ps1 构建生效`
  - first measured wall time after warm cache: `1858ms`
  - final compatibility retest wall time: `3419ms`
  - `构建 Agent 输入未变化，跳过重建：outputs=87, signature=3c0bcdd1a996`
- post-check doctor:
  - best observed `build_agent_cache_check: last=1089ms`
  - final compatibility retest `build_agent_cache_check: last=1618ms`
  - final compatibility retest `build_apply_total: last=3151ms`
- Windows PowerShell 5.1 smoke:
  - dot-sourced `skills.ps1`
  - `Get-DirectoryFingerprint` returned non-empty fingerprint prefix `422dc8fe2475`
- `.\scripts\quality\run-local-quality-gates.ps1 -Profile quick -AllowDirtyWorktree`
  - `Local quality gates passed (quick).`
- `git diff --check`
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
