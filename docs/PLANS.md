# PLANS.md

## Objective
- 建立 skills-manager 的可验证治理闭环：目标明确、门禁可复现、分发可追溯。

## Scope
- In scope:
  - 明确 skills-manager 的年度治理目标与阶段里程碑。
  - 固化仓内硬门禁口径与验收标准。
  - 保持 source-of-truth 与目标仓 `docs/PLANS.md` 一致。
- Out of scope:
  - 新增上游 vendor 源。
  - 变更现有 CLI 行为契约。
  - 引入付费依赖或外部托管能力。

## Current phase
- Phase 1: Baseline clarity complete; gate stability and evidence cadence in progress.

## Steps
1. 每次迭代前更新目标、范围和非目标。
2. 固定顺序执行 `build -> test -> contract/invariant -> hotspot`。
3. 每周回顾一次门禁趋势和失败根因，沉淀到证据文档。

## Validation
- build: `powershell -File ./build.ps1`
- test: `powershell -File ./skills.ps1 发现`
- contract: `powershell -File ./skills.ps1 doctor --strict`
- hotspot: `powershell -File ./skills.ps1 构建生效`

## Risks
- 外部网络抖动导致 `doctor --strict` 偶发失败。
- 导入映射扩大后性能回退。
- 本地覆盖层与上游变更冲突导致行为偏移。

## Rollback
- 若本轮目标定义或门禁策略引发阻断，回滚至上一版 `docs/PLANS.md` 并重跑全门禁验证。
