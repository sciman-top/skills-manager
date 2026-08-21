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
- build、focused tests、contract/invariant checks、risk-triggered full gate

### 不包含

- 模型、provider、auth、context、sandbox、会话或权限管理
- 宿主 semantic router、agent orchestrator、daemon、数据库或 Web UI
- 插件打包/分发/安装控制面
- skill candidate lifecycle/review/staging 控制面
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

## 6. 非功能需求

- PowerShell 7-only，UTF-8，Windows-first。
- local-first；除显式 source refresh、MCP 或 live probe 外不依赖网络。
- secret-redaction-first；日志和 receipt 不写 token、header value 或环境 secret。
- 所有写路径有 containment、freshness、授权、rollback 或 compensation。
- generated sync、config 或公开契约失败即阻断；reference 只在显式 refresh/verify 时 fail closed，其他检查按当前风险触发。
- 不新增只有一个 adapter 的 seam；不为历史兼容保留无 caller interface。

## 7. 验收

Repository closeout 至少满足：

1. `build.ps1` 成功且生成物同步。
2. 受影响 Pester/verifier 通过。
3. `git diff --check` 通过。
4. 若触发 runtime/安全/数据/迁移/公开契约/依赖/打包风险，在输入冻结后运行一次 full gate。
5. 报告删除量、保留主链和未验证边界。

`host_loaded` 需要新宿主会话/投影事实；`live_accepted` 需要真实用户工作流。二者不属于 repository tests 的自动结论。
