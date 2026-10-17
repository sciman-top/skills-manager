# 产品契约索引

skills-manager 是 local-first 的技能/MCP curator、目标仓审查器和规则 advisor。稳定产品合同包括：

- [PRD](skills-manager-vnext-prd.md)：用户、范围、功能、非功能和验收边界。
- [Architecture](skills-manager-vnext-architecture.md)：模块、接口、数据流、真值与删除原则。

模型能力分为两部分：已实现的[独立 preset 工具](../../src/model-orchestration/README.md)负责显式配置与受控启动；完整跨宿主编排、自动故障切换仍是 deferred design。独立工具不进入技能/MCP 主 CLI，不作为日常编码的必经入口：

- [MOR-000 边界决议](../decision/MOR-000-brief.md)：§4 区分已实现的独立 preset 工具与仍暂缓的完整控制面；§3 仅为后者的历史设计输入。
- [MOR-001 自动故障切换模拟准入规格](../decision/MOR-001-automatic-failover-simulation.md)：未来独立 failover module 的离线 scenario、失败分类、熔断/恢复与 receipt 合同；不改变当前人工切换禁令，也不构成 runtime 或真实探测授权。
- [MOR-090 静态证据包](../decision/MOR-090-static-adapter-evidence.md)：Codex/ZCode/Claude/DeepSeek 的一手 model/effort/field 事实、来源与未决项，是未来 Adapter fixture 的唯一输入底稿。
- MOR PRD 与 Architecture（约 800 行 design-only 全文）已随 2026-09-15 精简归档至 `docs/archive/`；Hermes 集成三部曲（R0–R4 已收口）与 2026-08 加固任务卡同批归档，见 [docs/archive/README.md](../archive/README.md)。

这些计划文档是 versioned design input，不是 Hermes、Codex、CI 或人工验收的运行状态。它们不会授权安装软件、修改 `~/.codex` / `~/.hermes`、创建计划任务、投影技能、合并分支或执行线上操作。跨宿主模型编排文档同样不授权读取 OAuth/API 凭据、扫描网关/模型列表、发送模型探测请求，或改写 OAuth/API 凭据、网关、宿主配置、会话或插件缓存；只有独立 runtime 在当前授权、静态 Adapter contract 和受控投影事务均满足时，才可变更已验证的非秘密宿主模型选择字段。

动态 HSM 执行状态、运行模式、commit 与 receipt 必须保存在相应 POC 仓的任务 brief/receipt 中；本目录只保留稳定的目标、边界、进入条件和最低证明，不复制阶段快照。

附属参考件：

- [AI 编码工作流与约束](ai-coding-workflow-guide.md)：合并后的单一参考件，含工作流、强制层级与外部依据；不是规则或门禁。

运行真值不写入本目录：

- 配置：`skills.json` / `skills.lock.json`
- 生成：`skills.ps1` / `agent/`
- 审查与 receipt：ignored `reports/`
- 门禁：`scripts/quality/run-local-quality-gates.ps1`

仓库结果只证明 `repo_verified`。宿主新会话加载与真实业务验收分别属于 `host_loaded`、`live_accepted`，不得由文档或 synthetic corpus 推导。
