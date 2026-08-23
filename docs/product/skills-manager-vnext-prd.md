# skills-manager PRD

## 1. 产品目标

在 Windows 和 PowerShell 7 环境中，用一个本地、可审查、可回滚的配置管理技能来源、安装映射、MCP server、目标仓审查、规则审查和宿主原生技能投影。

成功不是“建立万能 AI 控制面”，而是把用户高频维护动作压缩为短、真实、可验证的 CLI 主链。

## 2. 用户与任务

主要用户是同时维护多个 Codex/Claude/Gemini 技能来源和 Windows 项目仓库的个人开发者。核心任务：

1. 浏览、安装、卸载、更新和锁定技能。
2. 管理 MCP server 清单及目标配置。
3. 扫描目标仓与当前技能/MCP，生成可审阅建议，并在显式授权后应用。
4. 审查全局/项目规则，在 reviewed change-set 下计划、应用和回滚。
5. 把最小技能集合投影给宿主，同时保留完整可移植 catalog 供显式发现。

## 3. 范围

### 包含

- `skills.json` / `skills.lock.json` 配置与锁定
- vendor/import/mapping/target 构建
- MCP install/uninstall/profile/sync
- target audit 三文件 bundle、recommendations preflight/dry-run/apply
- rule audit、single-repo patch、rule-estate transaction
- canonical skill inventory、native projection（metadata budget 与 description 截断复用宿主原生能力）
- host-selected `capability-router` cold discovery/policy validation when visible metadata is insufficient
- 按任务显式启用的可选 core/secondary reference shelf refresh/verify
- 可由宿主/operator 调度的 skills-only maintenance runner
- 通过隔离 POC 证明后，向 Hermes 一类外部宿主提供可选、只读优先的 skill consumer contract；该 contract 复用现有 source、package hash、projection receipt 与 rollback 语义，不接管其 runtime
- 通过 reviewed Git change-set 准入的受控 skill evolution：宿主 AI 可以提出、草拟、测试技能候选；skills-manager 只负责确定性检查、显式准入、受控投影与回滚
- build、focused tests、contract/invariant checks、risk-triggered full gate；CI 与本地门禁共用同一 gate profile 分类器（`Resolve-QualityGateProfile`），本地支持 `-Profile auto`，base 缺失、变更集不可读或 non-ignored untracked file 出现时 fail-safe 选择 full。该实现由 [HSM-GAT-100/110/120](skills-manager-hardening-implementation-plan.md) 落地，后续修改必须继续保持分类器单一权威副本

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

## 4. 产品原则

- 原生优先：宿主能完成的语义选择与执行不在仓库复制。
- 最短真实主链：只保留用户实际调用的 interface；删除后复杂度不转移给 caller 的 module 应退役。
- 最低充分：验证覆盖当前失败模式即停；普通变更不跑重复 full gate。
- 显式写入：host/MCP/rule/config 外部写入必须有当前授权、预演、receipt 和回滚。
- 真值分层：`repo_verified != host_loaded != live_accepted`。

## 5. 功能需求

### 5.1 技能与配置

- `FR-SKL-001`：`skills.json` 是 source、mapping、target、MCP 与 projection 的唯一配置真源。
- `FR-SKL-002`：来源路径、输出路径和名称冲突必须 fail closed；生成物不得手改。
- `FR-SKL-003`：update/lock/build 能检测 dirty source、revision drift、duplicate output 和 dependency gap。
- `FR-SKL-004`：本地 override 只进入 `overrides/{custom,patches,resources}`，patch 记录 provenance。
- `FR-SKL-005`：卸载只撤配置与受管输出，不删除未授权源码或宿主-owned assets。
- `FR-SKL-006`：`check-updates --json` 只读报告 current/target/changed/source；仓库可提供可重复调用且 fail-closed 的 skills-only maintenance runner，但计划任务的创建、更新、删除、运行账户、触发频率与宿主验收由 host/operator 持有；runner 不同步 MCP、不 push。
- `FR-SKL-007`（当前实现）：`skills.json` schema v3 顶层为 allowlist，仅允许 `schema_version`、`sync_mode`、`update_force`、`skill_projection`、`vendors`、`mappings`、`imports`、`targets`、`mcp_servers`、`mcp_profiles`、`mcp_targets`；v3 下未知顶层字段 fail closed。v2 保持只读迁移兼容并仅输出 observation；v2 到 v3 的迁移已按一次性、可回滚与迁移/回滚/兼容三件套验证完成。后续 schema 变更仍须遵守 [加固实施计划](skills-manager-hardening-implementation-plan.md) HSM-CFG-300/310 的兼容窗口与回滚合同。

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

- `FR-RUL-001`：发现遵循宿主 global/repo/nested precedence，并区分 Codex/Claude surface。
- `FR-RUL-002`：审查默认只读；finding 必须定位到真实文件和可执行修复方向。
- `FR-RUL-003`：单仓 apply 要求 Git 根、已知规则文件、reviewed desired file、before hash 和显式 token。
- `FR-RUL-004`：rule-estate 只消费 `review_status=reviewed` 且非 AI self-approval 的 change-set。
- `FR-RUL-005`：全域 apply 为 `preflight-all -> apply-one-by-one -> receipt-after-each -> fail-fast`，不承诺跨仓原子性。

### 5.5 投影与发现

- `FR-PRJ-001`：canonical inventory 对 source、enabled、dependency 和 placement 做确定性归一化。
- `FR-PRJ-002`：native projection 只投影 `managed_link_includes`，以完整 package hash 绑定 plan/apply，并仅按当前 managed root 或上一份受验证 receipt 清理历史受管 link，保持 managed/external ownership 分离。
- `FR-PRJ-003`：本仓不得复制宿主 metadata budget/description compaction；投影保留全部 eligible entry，并报告真实 conflict。
- `FR-PRJ-004`：普通语义选择归宿主；router 只接受 `DomainHint` 和宿主选择，禁止 lexical ranking、profile switch 与 host mutation。
- `FR-PRJ-005`：inventory/corpus 只能证明候选与 policy contract，不证明宿主真实 invocation。
- `FR-PRJ-006`：只读 inventory 使用公开 plugin CLI JSON 识别 plugin/system/standalone 同名能力，优先建议 native plugin source；finding 仅报告，不安装、卸载、启用 plugin 或读写 cache。

### 5.6 Reference shelf

- `FR-REF-001`：reference shelf 是可选只读开发缓存；`skills.json` 是 runtime 真源，外置 checkout 缺失或未刷新不得阻断普通 build/test/update/projection。
- `FR-REF-002`：manifest 只在显式 refresh/verify 中适用，owned root 固定为 `D:\CODE\external\skills-manager-references`。
- `FR-REF-003`：manifest 只保留 active core/secondary/conditional repo，name/path 唯一；conditional 必须有明确 consumer 且只显式刷新，default set 只引用 core。
- `FR-REF-004`：refresh 校验 origin、dirty 状态和 containment，只做 fetch/fast-forward/clone。
- `FR-REF-005`：refresh/verify 失败只阻断该参考工作流，不授权采纳、安装、执行或 runtime import 删除；无消费者候选需要时重新发现。
- `FR-REF-006`：每次 refresh 写入 ignored `reports/reference-refresh/<run-id>/receipt.md`；Git 只跟踪 manifest 和稳定说明，不跟踪动态 latest 状态。

### 5.7 外部 AI consumer 与受控技能演进（未来、POC 门禁）

本节定义产品目标，不表示当前已存在 Hermes runtime、Hermes host adapter 或自动学习实现。任何实现必须先完成 `docs/product/skills-manager-hermes-roadmap.md` 的 POC 退出条件。

- `FR-HER-001`：外部 AI consumer 的最小 contract 只描述 `consumer_id`、受管 source identity/hash、target root、ownership mode、read/write policy、projection receipt 与 rollback entry。它不得描述模型、会话、任务、提示词、工具调用或调度语义。
- `FR-HER-002`：consumer 默认只读；若 consumer 需要读取共享技能，必须先验证其进程没有对目标 root 的未授权写入能力，或由隔离用户/ACL/副本提供等效保护。目录存在、config 已写入或 inventory 可见都不证明宿主已加载。
- `FR-HER-003`：Hermes 的 app-server/Codex runtime、MCP/plugin migration 与 `~/.codex/config.toml` 变更属于宿主授权域。skills-manager 不生成、不写入、不迁移该配置，只能在显式只读 probe 中报告观察结果与真值边界。
- `FR-HER-004`：只有完成与拟议 consumer runtime 相匹配的隔离 POC、存在真实 consumer、且现有 native projection 无法承载所需差异时，才允许新增 consumer adapter。`native_openai_codex` 的 POC 证据不得证明 `codex_app_server` 的 host integration；只有一个假设 consumer 时，不创建泛化 host adapter framework。
- `FR-HER-005`：受控协作可自动完成无共享宿主写入的 preflight、hash/inventory 对比、固定 marker 检查、package/schema/test 验证与 receipt 摘要；每次运行必须分类为 `auto_evidence`、`auto_stop` 或 `human_decision`。缺 marker、显式 provider/API 失败、共享 config/MCP/plugin 的非预期差异或 write-set 越界必须 `auto_stop`，不得自动重试、切换账户、改变 profile/config 或执行回滚。
- `FR-EVO-001`：宿主 AI 可以在项目级 `.agents/skills` 或隔离 sandbox 草拟、修复和测试候选技能；候选必须以普通 Git change-set 或明确 source root 提交审核，不能直接写入全局受管 root。
- `FR-EVO-002`：准入前必须验证 skill identity、path containment、reparse-point/special-file safety、来源/revision/license/provenance、内容 hash、受影响测试与兼容性。建议、扫描结果或 AI 自评不是准入授权。
- `FR-EVO-003`：准入至少分为 `proposal -> reviewed -> admitted -> projected -> host_loaded -> live_accepted`。`reviewed` 与 `admitted` 必须有独立的人类或指定 owner 决策；AI 不能批准自己的候选。
- `FR-EVO-004`：已准入技能仍遵循现有 `skills.json` / lock、build、projection receipt 与 rollback 规则。失败时只回滚本次候选的 source/mapping/projection，不删除 external-owned 或其他宿主资产。
- `FR-EVO-005`：技能演进不新增长期候选数据库、自治 curator、hidden prompt memory 或自动发布链；动态 proposal/task state 属于 Hermes、目标仓 issue/PR 或 operator 工具，不是本仓 tracked runtime state。
- `FR-EVO-006`：候选的 proposal、确定性验证与“保持未准入”可自动完成；只有从项目/sandbox 范围提升到共享 root、lock、projection、push/release 或 host probe 时才请求独立 owner 的单次决策。自动化不得把技术验证伪装成 `reviewed` 或 `admitted`。

## 6. 非功能需求

- PowerShell 7-only，UTF-8，Windows-first。
- local-first；除显式 source refresh、MCP 或 live probe 外不依赖网络。
- secret-redaction-first；日志和 receipt 不写 token、header value 或环境 secret。
- 所有写路径有 containment、freshness、授权、rollback 或 compensation。
- Hermes consumer 与 skill evolution 的任何宿主集成默认 fail closed：缺失 POC evidence、source/target hash、owner、write policy、review 或 rollback 时不得投影、更不得修改宿主配置。
- generated sync、config 或公开契约失败即阻断；reference 只在显式 refresh/verify 时 fail closed，其他检查按当前风险触发。
- 不新增只有一个 adapter 的 seam；不为历史兼容保留无 caller interface。

## 7. 验收

Repository closeout 至少满足：

1. `build.ps1` 成功且生成物同步。
2. 受影响 Pester/verifier 通过。
3. `git diff --check` 通过。
4. 若触发 runtime/安全/数据/迁移/公开契约/依赖/打包风险，在输入冻结后运行一次 full gate。
5. 报告删除量、保留主链和未验证边界。

Hermes consumer / skill evolution 的实现 closeout 还必须满足：

6. 每个实际 consumer 都有 source/target/owner/write-policy/hash/receipt/rollback 的可核对 contract；没有 consumer 时不得以“未来兼容”为理由扩展 runtime。
7. 候选技能的 proposal、review、admission、projection 与宿主验收状态可区分；任何低层证据不得跳级为 `host_loaded` 或 `live_accepted`。
8. 受控 POC 在隔离 profile 或等效环境中证明：只有指定 worktree 与受管测试 root 被写入，主 `~/.codex`、主 `~/.agents/skills` 和生产凭据没有被改变。

`host_loaded` 需要新宿主会话/投影事实；`live_accepted` 需要真实用户工作流。二者不属于 repository tests 的自动结论。
