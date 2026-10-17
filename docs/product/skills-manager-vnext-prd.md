# skills-manager PRD

## 1. 产品目标

在 Windows 和 PowerShell 7 环境中，用一个本地、可审查、可回滚的配置管理技能来源、安装映射、MCP server、目标仓审查、规则审查和宿主原生技能投影。

成功不是“建立万能 AI 控制面”，而是把用户高频维护动作压缩为短、真实、可验证的 CLI 主链。

## 2. 用户与任务

主要用户是使用 ChatGPT Desktop/Codex、Claude Code、ZCode 或 Antigravity 等宿主，并维护多个技能来源和 Windows 项目仓库的个人开发者；他们按任务选择当前可用的模型与宿主，不预设固定接力链。这里的 Claude 支持面是 Claude Code 的本机配置与技能投影，包括 Claude Desktop 内的 Code 会话；普通 Claude Desktop 聊天使用账号同步 skills/plugins，不由本机 `.claude` 投影管理或验收。核心任务：

1. 浏览、安装、卸载、更新和锁定技能。
2. 管理 MCP server 清单及目标配置。
3. 扫描目标仓与当前技能/MCP，生成可审阅建议，并在显式授权后应用。
4. 审查全局/项目规则：单仓规则在 reviewed desired file 下计划与应用；全局规则经 `global-rules-*` 投影与回滚。
5. 把最小技能集合投影给宿主，同时保留完整可移植 catalog 供显式发现。

## 3. 范围

### 包含

- `skills.json` / `skills.lock.json` 配置与锁定
- vendor/import/mapping/target 构建
- MCP install/uninstall/profile/sync
- target audit 三文件 bundle、recommendations preflight/dry-run/apply
- rule audit、single-repo patch、global rule projection
- canonical skill inventory、native projection（metadata budget 与 description 截断复用宿主原生能力）
- host-selected `capability-router` cold discovery/policy validation when visible metadata is insufficient
- 可由宿主/operator 调度的 skills-only maintenance runner
- build、focused tests、contract/invariant checks、risk-triggered full gate；CI 与本地共用 `resolve-gate-profile.ps1`，本地默认 auto。未跟踪文件参与同一分类：文档走 docs，规则走专项测试，已映射源码走行为测试；未知路径、未映射源码、风险变更或分类失败才选 full。main push 与 PR 共用策略，发布标签运行 full。

### 不包含

- 模型、provider、auth、context、sandbox、会话或权限管理
- 宿主 semantic router、agent orchestrator、daemon、数据库或 Web UI
- 宿主 AI 的无界自主学习、永久记忆、自动创建/修改/删除全局技能，或未经当前授权的自我升级
- Hermes/Codex 的任务队列、Kanban 数据库、Gateway lifecycle、cron/消息平台配置、worktree 调度与分支合并
- 插件打包/分发/安装控制面
- 独立于 Git review/source admission 之外的 skill candidate lifecycle/review/staging 控制面或第二状态数据库
- profile reconciliation/canary/hot-switch
- 无当前消费者的 reference candidate backlog
- tracked task/evidence/archive 作为第二状态数据库

### 3.1 冻结面（仅真实故障修复，不新增能力）

下列能力仍在仓库中，但不属于 §2 的核心任务，也不是日常主链。修复真实故障可以做；新增功能、扩大范围或接入日常主链，须先由用户明确解冻：

- 冷技能路由（`capability-router`、CSR 系列）：工程冻结。治理层（场景矩阵、receipt verifier、验收 runbook 与路线图）已移除，仅保留功能层（router、冷发现 catalog、native-agent bridge）。
- 独立模型 preset 工具（`src/model-orchestration/`）：独立于主 CLI 构建链，不参与技能/MCP 构建。

## 4. 产品原则

- 原生优先：宿主能完成的语义选择与执行不在仓库复制。
- 最短真实主链：只保留用户实际调用的 interface；删除后复杂度不转移给 caller 的 module 应退役。
- 最低充分：验证覆盖当前失败模式即停；普通变更不跑重复 full gate。
- 效能目标：在满足用户结果与必要资产边界的前提下，降低每个验收通过任务的总耗时、人工纠错和维护成本；测试数量、报告数量和代理数量不是成功指标。新增功能在现有需求或 Git review 中说明当前调用方、宿主能力缺口与最小验收，不新增审批或状态系统。
- 显式写入：host/MCP/rule/config 外部写入必须有当前授权、预演、receipt 和回滚。
- 真值分层：`repo_verified != host_loaded != live_accepted`。

## 5. 功能需求

### 5.1 技能与配置

- `FR-SKL-001`：`skills.json` 是 source、mapping、target、MCP 与 projection 的唯一配置真源。
- `FR-SKL-002`：来源路径、输出路径和名称冲突必须 fail closed；生成物不得手改。
- `FR-SKL-003`：update/lock/build 能检测 dirty source、revision drift、duplicate output 和 dependency gap。
- `FR-SKL-004`：本地 override 只进入 `overrides/{custom,patches,resources}`，patch 记录 provenance。
- `FR-SKL-005`：卸载只撤配置与受管输出，不删除未授权源码或宿主-owned assets。
- `FR-SKL-006`：`check-updates --json` 只读报告 current/target/changed/source；仓库可提供可重复调用且 fail-closed 的 skills-only maintenance runner，但计划任务的创建、更新、删除、运行账户、触发频率与宿主验收由 host/operator 持有；runner 不同步 MCP、不 push。调度注册是交互式 operator 的显式动作；调度 runner 仅检查/更新 skills-manager 自身，绝不修改宿主 MCP 配置。
- `FR-SKL-007`（当前实现）：`skills.json` schema v3 顶层为 allowlist，仅允许 `schema_version`、`sync_mode`、`update_force`、`skill_projection`、`vendors`、`mappings`、`imports`、`targets`、`mcp_servers`、`mcp_profiles`、`mcp_targets`；v3 下未知顶层字段 fail closed。v2 保持只读迁移兼容并仅输出 observation；v2 到 v3 的迁移已按一次性、可回滚与迁移/回滚/兼容三件套验证完成。后续 schema 变更仍须遵守 [加固实施计划](../archive/skills-manager-hardening-implementation-plan.md) HSM-CFG-300/310 的兼容窗口与回滚合同。

### 5.2 MCP

- `FR-MCP-001`：支持 stdio/http MCP 的安装、卸载、profile 选择与同步；配置字段 `http` 表示 Streamable HTTP 兼容入口。
- `FR-MCP-002`：配置只保存 secret 的环境变量名，不保存 secret 值。
- `FR-MCP-003`：同步必须区分仓库配置写入、宿主投影和 live health；失败不得报告成功。
- `FR-MCP-004`：doctor 必须报告 Streamable HTTP 语义，并对非 loopback 明文 HTTP 发出风险提示；URL 解析或配置检查不证明 live health、服务端 Origin 校验或认证已生效。

### 5.3 目标仓审查

- `FR-AUD-001`：扫描同时读取用户需求、目标仓事实与已安装 skills/MCP；宿主状态不在仓库内猜测。
- `FR-AUD-002`：bundle 位于 `reports/skill-audit/<run-id>/` 且固定为三个文件：不可变输入 `snapshot.json`、唯一 AI 可编辑文件 `recommendations.json`、机器维护记录 `receipt.json`。
- `FR-AUD-003`：recommendations 必须经过 schema/source/staleness/preflight/dry-run；只有 `--apply --yes` 写入。
- `FR-AUD-004`：应用重新读取当前配置并校验输入快照、选择清单和补偿；失败 truthful。
- `FR-AUD-005`：preflight、dry-run、workflow、apply 与 compensation 只更新 `receipt.json` 对应 section；不得生成第四个报告或 markdown evidence 文件。

### 5.4 规则治理

- `FR-RUL-001`：发现遵循宿主 global/repo/nested precedence，并区分 Codex 与 Claude Code 执行面；Claude Desktop 内的 Code 会话按 Claude Code 执行面处理，普通聊天的账号同步 skills/plugins 不由本机 `.claude` 投影证明已加载。
- `FR-RUL-002`：审查默认只读；finding 必须定位到真实文件和可执行修复方向。
- `FR-RUL-003`：单仓 apply 要求 Git 根、已知规则文件、reviewed desired file、before hash 和显式 token。

### 5.5 投影与发现

- `FR-PRJ-001`：canonical inventory 对 source、enabled、dependency 和 placement 做确定性归一化。
- `FR-PRJ-002`：native projection 按 `skill_projection.projection_profiles` 解析宿主有效集合；`managed_link_includes` 仅为无 profiles 的历史配置回退。以完整 package hash 绑定 plan/apply，并仅按当前 managed root 或上一份受验证 receipt 清理历史受管 link，保持 managed/external ownership 分离。
- `FR-PRJ-003`：本仓不得复制宿主 metadata budget/description compaction；投影保留全部 eligible entry，并报告真实 conflict。
- `FR-PRJ-004`：普通语义选择归宿主；router 只接受 `DomainHint` 和宿主选择，禁止 lexical ranking、profile switch 与 host mutation。
- `FR-PRJ-005`：inventory/corpus 只能证明候选与 policy contract，不证明宿主真实 invocation。
- `FR-PRJ-006`：只读 inventory 使用公开 plugin CLI JSON 识别 plugin/system/standalone 同名能力，优先建议 native plugin source；finding 仅报告，不安装、卸载、启用 plugin 或读写 cache。
- `FR-PRJ-007`：可选 native-agent bridge 只把仓库受控模板投影到固定 Codex `~/.codex/agents` 或 Claude Code `~/.claude/agents`；写入必须经过既有 host promotion（clean commit 或明确 unverified override）、模板 ownership/reparse 校验、receipt 与回滚。bridge 不负责 provider/auth、agent runtime、队列、会话、动态模型路由或跨宿主编排；但受管 Codex custom-agent template 可以声明静态 `model` / `model_reasoning_effort`，以避免无意继承全局 subagent 默认值。每个静态钉选必须有 source-template 测试、投影 hash receipt 与 fresh Codex child 验收。Claude 模板不钉选模型或 effort，沿用宿主当前选择；本机投影不覆盖普通 Desktop 聊天。
- `FR-PRJ-008`：cold routing 的真值必须拆为 `host_visible`、`candidate_load_validated`、`skill_md_loading`、`native_child` 与 `host_specific_live_accepted`。router receipt 只能证明发现或精确闭包校验；ZCode 父任务代行、模板存在、投影成功、模型可列举或 AI 自述均不得证明 Codex native child 已启动或 `SKILL.md` 已加载。

### 5.6 外置参考仓

参考仓棚（manifest、refresh/verify、ACL 锁与基线）已移出本仓范围。外置目录属于其他项目，本仓不对其做任何读取、刷新或校验；普通 build、test、update 与 projection 不依赖外置路径。

## 6. 非功能需求

- PowerShell 7-only，UTF-8，Windows-first。
- local-first；除显式 source refresh、MCP 或 live probe 外不依赖网络。
- secret-redaction-first；日志和 receipt 不写 token、header value 或环境 secret。
- 所有写路径有 containment、freshness、授权、rollback 或 compensation。
- generated sync、config 或公开契约失败即阻断；其他检查按当前风险触发。
- 不新增只有一个 adapter 的 seam；不为历史兼容保留无 caller interface。

## 7. 验收

Repository closeout 至少满足：

1. `build.ps1` 成功且生成物同步。
2. 受影响 Pester/verifier 通过。
3. `git diff --check` 通过。
4. 若触发 runtime/安全/数据/迁移/公开契约/依赖/打包风险，在输入冻结后运行一次 full gate。
5. 报告删除量、保留主链和未验证边界。


`host_loaded` 需要新宿主会话/投影事实；`live_accepted` 需要真实用户工作流。二者不属于 repository tests 的自动结论。
