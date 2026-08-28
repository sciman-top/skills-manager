# MOR-000：runtime 归属与控制面边界决议

**状态**：decided_deferred（2026-08-28）：**暂不实现，保持 design-only**——§3 替代决定生效；不创建 `D:\CODE\model-orchestration`，不填充未经确认的 owner，不进入 MOR-010 runtime 写入。MOR-090 static-fact 基线保留；只读审查与文档修订车道持续开放。当 owner 明确指定已有 runtime 或新的独立项目根、以及真实人类/团队 owner 后，再依 §3 基线启动 MOR-010。
**依据**：[PRD](../product/cross-host-model-orchestration-prd.md) §9 · [实施计划](../product/cross-host-model-orchestration-implementation-plan.md) MOR-000
**回滚**：删除本文件即回滚本决议；不影响任何已提交设计文档或宿主状态
**Truth boundary**：human design decision（decided_deferred）；不证明任何 host/模型事实

## 1. 已钉定决议

| 决议项 | 内容 |
| --- | --- |
| 首期 host | `codex_cli`（唯一首期宿主；ZCode/Claude 等各自静态合同取证后再接入） |
| GPT preset invariant | 每次仅选择一个 `gpt56_sol_only` / `gpt56_terra_only` / `gpt56_luna_only`；该 preset 恰含 `light/standard/deep` 三个同族 route key，五个 execution slot 可复用三 key，禁止跨 Sol/Terra/Luna 混搭；high-risk 是额外 gate，不是第四档 |
| 首期 default preset | `gpt56_sol_only`（Sol/low、Sol/medium、Sol/xhigh；高风险=Sol/xhigh + policy），以用户明确偏好选定，非测量最优 |
| identity binding | 必须使用不可伪造、可审计的绑定来源；无法绑定时状态 `identity_unbound`，禁止持久 override 与 projection，仅允许 offline resolve 与 dry-run/manual handoff |
| native bridge role pin | `overrides/resources/native-agent-bridge/design-griller.toml` 与 `cold-capability-runner.toml` 显式钉 `gpt-5.6-terra/high`：**pin 优先于通用 route resolver 且完全排除在其外**；任何 preset 切换不得静默覆盖 bridge pin；改 pin 需配对实测（独立授权域，不在本决议内执行） |
| 普通任务 ingress | 常规入口为上游调用方/用户确认产生的结构化 RouteRequest（workload/risk_level/operation/workspace_root）；宿主 AI 不得从 prompt 私自推断；AI 分类仅可为标注建议并需确认（PRD `MOR-FR-045`） |
| override 重确认 | 持久 override 支持可选 `requires_reconfirm_after`，仅在下一次显式 resolve 检查（无 watcher），过期返回 `manual_mapping_required`（PRD `MOR-FR-026`） |
| private state/receipt root | canonical path：`<runtime-root>/.ai/state/` 与 `<runtime-root>/.ai/receipts/<yyyy-mm-dd>/<run-id>/`（ignored、仅当前用户可读；runbook §2 同此约定） |
| 授权模型 | 控制面零网络、零 OAuth 读取、零 gateway 扫描、零模型调用（PRD `MOR-FR-014`）；host write、fresh task、外部模型调用是独立授权域 |
| 投影目标原则 | Codex 投影优先评估 additive per-profile 文件（`$CODEX_HOME/<name>.config.toml` + `--profile`）而非改写用户级顶层键；仅到 `filesystem_projected`，`host_loaded` 另验 |

## 2. blocked 范围与归宿选项

**blocked 的精确范围**：`<runtime-root>`/owner 未定时，被阻塞的仅是 **MOR runtime 的持久化实现**（schema、resolver、fixture、CLI 的创建与写入）。不受阻塞的工作车道：只读事实采集（MOR-090）、文档审查与修订、evidence 包维护、设计讨论。

**归宿三选项**（roadmap §2）：① 已有的 host-local runtime；② 受控的 Cockpit 扩展；③ 另一个已存在、具备治理边界的 runtime。只有 skills-manager 本身不得作为归宿。当前机器 `D:\CODE` 下未发现此前提过的 `local-ai-dev-orchestrator`，不能当作现成候选。

## 3. 推荐决策基线（已搁置：2026-08-28 决定暂不实现；未来启动时作为现成输入，非创建授权）

| 项 | 推荐值 |
| --- | --- |
| `runtime_root` | `D:\CODE\model-orchestration`（新建；三归宿选项中的新 host-local runtime） |
| `owner` | `<待 owner 填写明确个人/团队标识>` |
| first-host | `codex_cli` |
| state-root / receipt-root | `<runtime_root>\.ai\state` / `<runtime_root>\.ai\receipts` |
| 首期 projection | `none`（仅 offline resolve + dry-run launch；`~/.codex`、Claude、ZCode、provider、gateway 均不触碰） |
| identity binding | manual binding required；未完成可审计绑定前禁止持久 override |
| native bridge | `design-griller`/`cold-capability-runner` 继续 `gpt-5.6-terra/high`，排除于通用 preset 覆盖外 |

**决策输入句模板**（填入 owner 后即构成 MOR-000 正式决议）：

> 批准将跨宿主模型编排 runtime 放在 `D:\CODE\model-orchestration`，owner 为 `<owner>`；首期仅接入 codex_cli，只实现 offline schema/policy/resolver 与 dry-run launch，state/receipt 使用 runtime 私有目录，暂不执行 host projection；identity 未完成可审计绑定前禁止持久 override，现有 design-griller 与 cold-capability-runner 保持 Terra/high 并排除在通用 route 覆盖之外。

**同等合法的替代决定**：暂不选择 runtime-root，继续保持 design-only；不进入 MOR-010 实现，但保留只读 MOR-090 事实审查车道。

## 4. 未决字段（root 选定时一并钉定）

| 项 | 状态 |
| --- | --- |
| `<runtime-root>` / owner | `blocked: awaiting owner decision`（见 §3 基线） |
| native projection target / rollback entry | 仅记录为待证实事实；首期 projection=none 使其不阻断 R1 |
| 首期授权边界 | 随决议句一并生效：零网络、零 OAuth、零模型调用；host write 为独立授权域 |

## 5. 与既有资产的边界

- 本决议不修改 `skills.json`、`skills.ps1`、`build.ps1` 主链，不读取凭据，不调用模型，不改 provider/auth/gateway。
- bridge pin 的现值（`gpt-5.6-terra/high`）继续按既有共识运行；本决议只钉其**优先级与排除规则**，不改其值。
- §3 基线本身**不构成创建目录的授权**；目录创建只在 owner 给出正式决议句后随 MOR-010 切片执行。
