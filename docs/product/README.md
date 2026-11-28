# 产品契约索引

skills-manager 是 local-first 的技能/MCP curator、目标仓审查器和规则 advisor。稳定产品合同包括：

- [PRD](skills-manager-vnext-prd.md)：用户、范围、功能、非功能和验收边界。
- [Architecture](skills-manager-vnext-architecture.md)：模块、接口、数据流、真值与删除原则。

跨宿主模型编排、自定义子代理投影与冷路由专用执行合同（已于 2026-11-28 退休，模型、effort、子代理和权限归宿主）及历史归档文档见 [docs/archive/README.md](../archive/README.md)。

动态 HSM 执行状态、运行模式、commit 与 receipt 必须保存在相应 POC 仓的任务 brief/receipt 中；本目录只保留稳定的目标、边界、进入条件和最低证明，不复制阶段快照。

附属参考件：

- [AI 编码工作流与约束](ai-coding-workflow-guide.md)：合并后的单一参考件，含工作流、强制层级与外部依据；不是规则或门禁。

运行真值不写入本目录：

- 配置：`skills.json` / `skills.lock.json`
- 生成：`skills.ps1` / `agent/`
- 审查与 receipt：ignored `reports/`
- 门禁：`scripts/quality/run-local-quality-gates.ps1`

仓库结果只证明 `repo_verified`。宿主新会话加载与真实业务验收分别属于 `host_loaded`、`live_accepted`，不得由文档或 synthetic corpus 推导。
