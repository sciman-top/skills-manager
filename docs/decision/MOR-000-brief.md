# MOR-000：runtime 归属与控制面边界决议（草案）

**状态**：draft；除 `<runtime-root>` 外的全部决议项已钉定，`<runtime-root>`/owner 为 `blocked: awaiting owner decision`
**依据**：[PRD](../product/cross-host-model-orchestration-prd.md) §9 · [实施计划](../product/cross-host-model-orchestration-implementation-plan.md) MOR-000
**回滚**：删除本文件即回滚本决议；不影响任何已提交设计文档或宿主状态
**Truth boundary**：human design decision（draft）；不证明任何 host/模型事实

## 1. 已钉定决议

| 决议项 | 内容 |
| --- | --- |
| 首期 host | `codex_cli`（唯一首期宿主；ZCode/Claude 等各自静态合同取证后再接入） |
| 首期 default preset | `gpt56_sol_only`（Sol/low、Sol/medium、Sol/xhigh；高风险=Sol/xhigh + policy），以用户明确偏好选定，非测量最优 |
| identity binding | 必须使用不可伪造、可审计的绑定来源；无法绑定时状态 `identity_unbound`，禁止持久 override 与 projection，仅允许 offline resolve 与 dry-run/manual handoff |
| native bridge role pin | `overrides/resources/native-agent-bridge/design-griller.toml` 与 `cold-capability-runner.toml` 显式钉 `gpt-5.6-terra/high`：**pin 优先于通用 route resolver 且完全排除在其外**；任何 preset 切换不得静默覆盖 bridge pin；改 pin 需配对实测（独立授权域，不在本决议内执行） |
| 普通任务 ingress | 常规入口为上游调用方/用户确认产生的结构化 RouteRequest（workload/risk_level/operation/workspace_root）；宿主 AI 不得从 prompt 私自推断；AI 分类仅可为标注建议并需确认（PRD `MOR-FR-045`） |
| override 重确认 | 持久 override 支持可选 `requires_reconfirm_after`，仅在下一次显式 resolve 检查（无 watcher），过期返回 `manual_mapping_required`（PRD `MOR-FR-026`） |
| private state/receipt root | 约定 `<runtime-root>/state/`（ignored、仅当前用户可读）；确切路径待 root 选定时一并钉定 |
| 授权模型 | 控制面零网络、零 OAuth 读取、零 gateway 扫描、零模型调用（PRD `MOR-FR-014`）；host write、fresh task、外部模型调用是独立授权域 |
| 投影目标原则 | Codex 投影优先评估 additive per-profile 文件（`$CODEX_HOME/<name>.config.toml` + `--profile`）而非改写用户级顶层键；仅到 `filesystem_projected`，`host_loaded` 另验 |

## 2. blocked 项（等待 owner 决定）

| 项 | 阻塞内容 | 解除条件 |
| --- | --- | --- |
| `<runtime-root>` | 独立 host-local runtime 的 Git root 路径；不得放在 skills-manager 内 | 用户显式指定路径 |
| owner | runtime 维护者身份 | 同上 |
| native projection target / rollback entry | 仅记录为待证实事实（MOR-090/后续任务采集） | root 选定后按 MOR-090 采集 |

`<runtime-root>` 未选定期间：实施计划中 MOR-010 及之后的全部任务保持 `blocked`；本仓仅维护设计/决议/证据文档。

## 3. 与既有资产的边界

- 本决议不修改 `skills.json`、`skills.ps1`、`build.ps1` 主链，不读取凭据，不调用模型，不改 provider/auth/gateway。
- bridge pin 的现值（`gpt-5.6-terra/high`）继续按既有共识运行；本决议只钉其**优先级与排除规则**，不改其值。
