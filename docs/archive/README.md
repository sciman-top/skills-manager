# 归档：已收口/冻结/搁置的设计文档

本目录是 versioned design input 的历史留存（git mv 保留全部历史），不属于现行产品契约，也不被任何门禁或 verifier 引用。

| 文档 | 归档原因（2026-09-15） |
| --- | --- |
| skills-manager-hermes-{integration-strategy,roadmap,implementation-plan}.md | Hermes 集成线 R0–R4 已收口；阶段执行状态以 POC 仓 brief/receipt 为准 |
| cross-host-model-orchestration-{prd,architecture}.md | MOR 为 design-only（MOR-000 决议暂缓实现）；现行事实以 `docs/decision/MOR-090` 为准 |
| skills-manager-hardening-implementation-plan.md | 2026-08 加固任务卡全部执行完后冻结；选档矩阵已被 vnext-architecture §5 + resolve-gate-profile.ps1 取代 |
| cold-skill-routing-implementation-plan.md | CSR-100–170 任务卡已闭卷；验收口径以 `docs/runbooks/cold-skill-routing-acceptance.md` 为准 |

恢复方式：`git log --follow docs/archive/<file>` 追溯，或直接 `git mv` 移回 `docs/product/` 并更新 `docs/product/README.md` 索引。
