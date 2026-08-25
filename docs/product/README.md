# 产品契约索引

skills-manager 是 local-first 的技能/MCP curator、目标仓审查器和规则 advisor。稳定产品合同包括：

- [PRD](skills-manager-vnext-prd.md)：用户、范围、功能、非功能和验收边界。
- [Architecture](skills-manager-vnext-architecture.md)：模块、接口、数据流、真值与删除原则。
- [Cold-skill routing roadmap](cold-skill-routing-roadmap.md)：冷目录发现、原生执行 bridge、host 验收与专项工件验收的阶段、依赖和退出条件。**当前状态：frozen（2026-08-25 决议，应急工具保留，重启条件见文内 §0）。**
- [Cold-skill routing implementation plan](cold-skill-routing-implementation-plan.md)：可直接交给 AI 或工程师的 CSR-100 至 CSR-170 原子任务、接口、write set、验证和回滚。

面向 Hermes + Codex 协作的受控演进计划分为三份互补文档：

- [Hermes integration strategy](skills-manager-hermes-integration-strategy.md)：目标架构、职责边界、安装/隔离 POC 与受控技能演进决策。
- [Hermes roadmap](skills-manager-hermes-roadmap.md)：阶段、进入/退出条件、风险与 go/no-go 决策。
- [Hermes implementation plan and backlog](skills-manager-hermes-implementation-plan.md)：可直接交给 AI 或工程师执行的原子任务、预期 write set、验证与停止条件。

这些计划文档是 versioned design input，不是 Hermes、Codex、CI 或人工验收的运行状态。它们不会授权安装软件、修改 `~/.codex` / `~/.hermes`、创建计划任务、投影技能、合并分支或执行线上操作。

动态 HSM 执行状态、运行模式、commit 与 receipt 必须保存在相应 POC 仓的任务 brief/receipt 中；本目录只保留稳定的目标、边界、进入条件和最低证明，不复制阶段快照。

两个附属合同：

- [Reviewed rule-estate change-set](rule-estate-reviewed-change-set.md)：多目标规则写入的唯一 reviewed input 格式。
- [Reference shelf](../EXTERNAL_REFERENCE_REPO_TIERS.md)：外置参考仓的 owned-root 与刷新边界。
- [Hardening implementation plan](skills-manager-hardening-implementation-plan.md)：2026-08 双独立审计五轮交叉评审收敛的 P0–P3 任务卡（共享 gate 分类器、schema v3 allowlist、单宿主静态 guard POC、规则减法实验、工作区清理与投影决策）。
- [Cold-skill routing acceptance runbook](../runbooks/cold-skill-routing-acceptance.md)：host-specific 验收的输入、receipt 和停止条件；它不替代仓库测试。

运行真值不写入本目录：

- 配置：`skills.json` / `skills.lock.json`
- 生成：`skills.ps1` / `agent/`
- 审查与 receipt：ignored `reports/`
- reference inventory：`references/reference-shelf.manifest.json`
- 门禁：`scripts/quality/run-local-quality-gates.ps1`

仓库结果只证明 `repo_verified`。宿主新会话加载与真实业务验收分别属于 `host_loaded`、`live_accepted`，不得由文档或 synthetic corpus 推导。
