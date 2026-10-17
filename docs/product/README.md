# 产品契约索引

skills-manager 是 local-first 的技能/MCP curator、目标仓审查器和规则 advisor。稳定产品合同包括：

- [PRD](skills-manager-vnext-prd.md)：用户、范围、功能、非功能和验收边界。
- [Architecture](skills-manager-vnext-architecture.md)：模块、接口、数据流、真值与删除原则。
- [Cold-skill routing roadmap](cold-skill-routing-roadmap.md)：冷目录发现、原生执行 bridge、host 验收与专项工件验收的阶段、依赖和退出条件。**当前状态：engineering-frozen（core-lean 常态主发现路径，不再扩展演进，见文内 §0）。** 已闭卷的 CSR-100–170 实施计划见 `docs/archive/`。

模型编排与 MOR 设计已随独立 preset 工具移出主线；历史设计与决议见 [docs/archive](../archive/README.md)。

这些计划文档是 versioned design input，不是 Hermes、Codex、CI 或人工验收的运行状态。它们不会授权安装软件、修改 `~/.codex` / `~/.hermes`、创建计划任务、投影技能、合并分支或执行线上操作。跨宿主模型编排文档同样不授权读取 OAuth/API 凭据、扫描网关/模型列表、发送模型探测请求，或改写 OAuth/API 凭据、网关、宿主配置、会话或插件缓存；只有独立 runtime 在当前授权、静态 Adapter contract 和受控投影事务均满足时，才可变更已验证的非秘密宿主模型选择字段。

动态 HSM 执行状态、运行模式、commit 与 receipt 必须保存在相应 POC 仓的任务 brief/receipt 中；本目录只保留稳定的目标、边界、进入条件和最低证明，不复制阶段快照。

两个附属合同：

- [Reviewed rule-estate change-set](rule-estate-reviewed-change-set.md)：多目标规则写入的唯一 reviewed input 格式。
- [Reference shelf](../EXTERNAL_REFERENCE_REPO_TIERS.md)：外置参考仓的 owned-root 与刷新边界。

附属参考件：

- [Cold-skill routing acceptance runbook](../runbooks/cold-skill-routing-acceptance.md)：host-specific 验收的输入、receipt 和停止条件；它不替代仓库测试。
- [AI 编码效能手册](ai-coding-playbook.md)：六杠杆/常见坑到既有机制的映射、宿主元数据预算观测口径（`capability-inventory` 的 `metadata_budget`）、GPT/GLM 分工与资产积累节奏。它仍是参考件，不是规则或门禁；高频稳定闭环已提炼到默认投影的 `overrides/custom/ai-coding-workflow/SKILL.md`，手册全文不直接进入宿主上下文。
- [AI 编码效能通用指南](ai-coding-general-guide.md)：面向**任意项目**的通用实践与常见问题清单（上下文工程、任务定义四要素、工作流四阶段、指令减法、验证闭环、沉淀资产；六大类坑与防法），每条标注官方来源与核实日期。它同样是参考件，不是规则或门禁，也不进入宿主上下文。与手册的分工固定为：**本指南讲"通用为什么"，手册讲"本仓怎么映射"**——同一事实只在一处维护，避免两份文档漂移。

运行真值不写入本目录：

- 配置：`skills.json` / `skills.lock.json`
- 生成：`skills.ps1` / `agent/`
- 审查与 receipt：ignored `reports/`
- reference inventory：`references/reference-shelf.manifest.json`
- 门禁：`scripts/quality/run-local-quality-gates.ps1`

仓库结果只证明 `repo_verified`。宿主新会话加载与真实业务验收分别属于 `host_loaded`、`live_accepted`，不得由文档或 synthetic corpus 推导。
