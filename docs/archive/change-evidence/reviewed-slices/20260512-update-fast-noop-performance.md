# 2026-05-12 update fast no-op performance

## Rule / Risk
- Rule: R2 small closure, R6 hard gate, R8 traceability.
- Risk: low. The change only affects the `更新` no-change path after preflight and dirty-cache checks.

## Basis
- Baseline no-change update after upstream refresh: `update_total=51099ms`, `build_agent cache_hit=true`.
- Bottleneck: unchanged repositories still entered update/reset phases or serial remote commit probes.

## Changes
- `src/Commands/Update.ps1`
  - `Invoke-ParallelGitPrefetch` now returns success/failure so the planner can trust prefetched local refs only after a clean prefetch.
  - Added local remote-ref resolution for update planning after successful prefetch.
  - Added fast no-op guard: every planned source must be unchanged, present, and clean before skipping fetch/reset.
- `tests/Unit/ConfigUpdate.Tests.ps1`
  - Added coverage for clean unchanged fast no-op, dirty-cache rejection, and prefetched-ref planning.
- `skills.json`
  - `d3-viz` import uses sparse checkout to avoid unrelated Windows cleanup failures in the upstream cache.

## Commands / Evidence
- `./build.ps1`
  - exit 0; `Build success: D:\CODE\skills-manager\skills.ps1`
- `Invoke-Pester -Script tests\Unit\ConfigUpdate.Tests.ps1 -EnableExit`
  - exit 0; `Tests Passed: 32, Failed: 0`
- `./tests/check-generated-sync.ps1 -AllowDirtyWorktree`
  - exit 0; generated output matches current `src`.
- `./skills.ps1 更新`
  - exit 0; `并行预取完成：41 个仓库路径（并发=8）。`
  - exit 0; `更新快路径：44 个缓存源均已是目标版本，跳过 fetch/reset，仅验证构建生效。`
  - exit 0; `构建 Agent 输入未变化，跳过重建：outputs=87, signature=188496d78a53`
  - measured runtime after `d3-viz` sparse config: `44.6s`; log metric `update_total=44286ms`.
- `./skills.ps1 发现`
  - exit 0; current effective skills: 87.
- `./skills.ps1 doctor --strict --threshold-ms 8000`
  - exit 0; `Your system is ready for skills-manager.`
- `./skills.ps1 构建生效`
  - exit 0; target links already match `agent/`; build cache hit.

## Rollback
- Revert `src/Commands/Update.ps1`, `tests/Unit/ConfigUpdate.Tests.ps1`, generated `skills.ps1`, and the `d3-viz` sparse flag in `skills.json`.
- Re-run: `./build.ps1`, `Invoke-Pester -Script tests\Unit\ConfigUpdate.Tests.ps1 -EnableExit`, `./skills.ps1 doctor --strict --threshold-ms 8000`, `./skills.ps1 构建生效`.
