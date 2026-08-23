# Hermes + Codex 协作路线图

**文档角色**：稳定路线图；动态 HSM 阶段状态、运行模式、commit 与 receipt 位于对应 POC 仓的任务 brief/receipt，不在本文件保存。
**基线**：现有 skills-manager 产品主链保持不变；本路线图不授权宿主改动。
**路线图原则**：每一阶段只解锁下一阶段所需的最小风险，不以“自动化程度”替代可验证性。

## 1. 阶段总览

| 阶段 | 目标 | 允许的写入 | 退出条件 | 明确不做 |
| --- | --- | --- | --- | --- |
| R0 | 文档与边界冻结 | 本仓产品文档 | PRD、架构、策略、路线图、任务卡一致 | 安装 Hermes、改宿主 config、改运行代码 |
| R1 | 同机 Hermes 协调基线 | 当前用户的独立 profile、POC repo | Desktop/CLI/profile 正常，且不启用 Codex runtime/共享全局技能写入 | Gateway/cron/Kanban/生产凭据 |
| R2 | 项目级技能 POC | POC repo `.agents/skills` | Hermes 可发现项目技能，无越界写入 | 共享主 `~/.agents/skills` |
| R3 | Hermes → Codex 单任务 POC | 当前用户受控 profile 或 VM/第二账户、单 worktree | 一项任务通过 gate/review，人为收口 | 自动 merge/push、并行写入 |
| R4 | 评估 consumer 差异 | 设计/receipt/POC 证据 | 证明确有 native projection 无法承载的差异 | 为假设需求新增 adapter |
| R5 | 可选 skills-manager consumer 实现 | 新 source/test/config/generated seam | source/hash/ownership/receipt/rollback 闭环 | runtime、daemon、task database |
| R6 | 受控技能演进准入 | sandbox/project skill、reviewed change-set | 候选从 proposal 到 admitted 可复现 | 自主覆盖全局技能、AI self-approval |
| R7 | 受限规模化 | Hermes task state、独立 worktrees | 多任务无 write collision，CI/人工收口 | 无人监管发布或自动 business acceptance |

## 2. R0：文档与边界冻结

### 目标

把目标架构落到可审查文本，使 AI 执行者能区分“计划中的 consumer contract”与“当前已运行功能”。

### 产物

- `skills-manager-hermes-integration-strategy.md`
- 本路线图
- `skills-manager-hermes-implementation-plan.md`
- PRD/Architecture 中的 POC 门禁与受控技能演进合同

### 退出条件

1. 文档明确 `skills-manager` 不管理 Hermes/Codex runtime。
2. 文档明确“自主学习”只能产生 proposal，不能直接 admission/projection。
3. 文档提供隔离 POC 的安装、配置、验证、停止和回滚边界。

## 3. R1：同机 Hermes 协调基线

### 进入条件

- R0 完成。
- 用户明确授权安装软件；安装授权不自动覆盖主机配置或生产凭据。

### 执行边界

- 默认使用当前 Windows 用户；Hermes 建立独立 `codex-poc` profile。
- 通过 Hermes 官方 installer 或官方 Windows CLI 安装路径安装。
- 创建 `codex-poc` profile；不复用默认 profile 的 memory、cron 或 bot token。
- 运行 `hermes doctor`；只保存 POC 环境的诊断结果。
- 不启用 Hermes Codex app-server runtime；此阶段不改动 Codex managed block，不允许 Hermes 处理主共享技能 root。

### 最低证明

| 检查 | 期望结果 | 不能证明 |
| --- | --- | --- |
| Hermes Desktop/CLI 可启动 | POC 环境可用 | Codex runtime 已联通 |
| `codex-poc` profile 独立存在 | Hermes 状态隔离 | 文件系统 sandbox 或 Codex config 隔离 |
| profile config 指向 POC repo | 默认工作目录受限 | 进程不能访问其他可读路径 |
| `skills.write_approval=true`、`memory.write_approval=true` | 写入会被审查 | 所有工具调用无副作用 |

### 停止条件

- 安装器/依赖要求管理员权限、生产凭据或非预期网络/系统改动。
- Hermes profile 与已有生产 profile 混用。
- 无法证明实际进程所用的 Windows 用户、home 和工作目录。

## 4. R2：项目级技能消费 POC

### 进入条件

- R1 通过。
- POC repo 有小而可测的 `.agents/skills` 样本。

### 执行边界

- 只使用 `<repo>/.agents/skills`。
- 不配置 `skills.external_dirs` 指向主 `~/.agents/skills`。
- 不允许 Hermes skill management 修改项目级技能；候选修改只通过 Git diff 审查。

### 退出条件

1. Hermes 可在 POC repo 中发现预期项目技能。
2. 运行前后快照显示主 `~/.agents/skills` 未变化。
3. 未产生未经批准的 skill/memory write。
4. 清楚记录“可发现”只证明候选可见，不证明正确调用或业务效果。

### 停止条件

- Hermes 对项目技能、共享 root 或 POC repo 之外的路径发起未审批写入。
- 运行前后基线 hash 不可复读，无法证明主 `~/.agents/skills` 未变化。

## 5. R3：Hermes → Codex 单任务 POC

### 进入条件

- R2 通过。
- 明确选择 `native_openai_codex` 或 `codex_app_server` 作为本轮 runtime path；两者的 evidence 不得互相替代。
- 完成 Codex login 与 Hermes `openai-codex` 授权；若选择 `codex_app_server`，只在档位 B（当前用户受控 POC）或档位 C（VM/第二账户）中启用。
- POC worktree 已分配、Git baseline 与最低门禁已记录。

### 执行边界

1. `native_openai_codex` 首个任务使用无工具或 read-only；主 Codex config 不应被它修改。
2. `codex_app_server` 启用前，备份并比较隔离环境的 Codex config；第一次任务保持 read-only 或逐操作审批。
3. 只对确定的 POC worktree 逐步允许写入；一项任务只允许一个 Codex 主执行者，任何子代理要么只读，要么有互斥 write set。
4. 不启动 Gateway/cron/Kanban 自动分派或自动 push。无共享宿主写入的 hash/inventory/marker/gate/receipt 可自动收集；缺 marker、显式 API 失败或 config/MCP/plugin/write-set 异常必须自动停止，不得重试或改配置。无 remote 的 POC 本地 merge 仅在 task brief 预先声明封闭 auto-merge envelope 时允许。

### 最低证明

| 证据 | 通过定义 |
| --- | --- |
| config diff | native 路径证明主 config 未被未授权修改；app-server 路径只允许预期 Hermes managed block、MCP/plugin 描述与 POC profile 变化 |
| worktree diff | 所有代码写入均位于获分配 worktree |
| gate | POC repo 最低 build/test/contract 检查通过 |
| review | Codex/人工 review 分开报告；两者不互相替代 |
| completion | Hermes 记录成功/失败/阻塞及 runtime path，不把结果直接当作 merge 决定或另一路径的验收 |

自动 receipt 只能压缩人工收集证据的工作量，不能替代 shared-config 处置、认证/权限升级、共享技能准入、push/release 或 `live_accepted` 的人类决策。

### 停止/回滚

- 若 Hermes 修改主日常 Codex config、共享技能 root 或非 POC worktree，立即停止扩大范围。
- 只回滚 POC profile、POC managed block、POC worktree 中本次切片；不得删除用户其他 profile、会话或技能资产。

## 6. R4：consumer 差异决策

R3 通过不等于必须改 skills-manager。只有出现下列可测差异，才进入 R5：

1. Hermes 无法安全消费项目级技能或现有 native projection。
2. 需要由 skills-manager 生成受 hash 绑定的 Hermes 专用只读副本/链接。
3. 现有 projection receipt 无法表达该副本的 ownership 或 rollback。

若没有任何差异，决策为：**不编码**；Hermes 继续通过项目级技能或受控外部副本消费。

若 reviewed R4 evidence 未显示上述可测差异，决策为 `no_code_needed`；现有 POC 无论使用何种 runtime path，都不授权将 project-owned candidate 自动投影、合并到共享 root 或变成 Hermes runtime 依赖。

## 7. R5：可选 consumer 实现

### 必要前置

- 已批准的 R4 evidence。
- 明确 consumer_id、目标根目录、所有权、写策略、source fingerprint、receipt、rollback。
- 完整的 test fixture 与 migration/rollback 方案。

### 目标接口

```text
Plan-ConsumerProjection
Apply-ConsumerProjection
Read-ConsumerProjectionReceipt
Rollback-ConsumerProjection
```

上述为目标 interface 名称，不是当前存在的 CLI 命令。实现时必须优先复用现有 native projection transaction；若只是薄转发，不新增 module。

### 退出条件

- 受管对象完全由 receipt 识别。
- collision、stale target、ownership drift、reparse-point、partial write 都 fail closed。
- 不触碰 `~/.hermes`、`~/.codex`、Gateway/cron/task database。

### 停止条件

- 实现退化为对现有 native projection 的薄转发，或需要表达 Hermes task/session/model 语义。
- collision、drift、ownership 或 rollback 无法给出 fail-closed 的可重复测试。

## 8. R6：受控技能演进准入

### 设计目标

将“AI 能写技能”变成一个可回滚的软件供应链动作，而不是一个永久自治学习系统。

### 进入条件

- HSM-EVO-200 试运行已证明 proposal 可自动验证，且人工 admission 的重复成本或缺口已被记录。

### 准入清单

1. 需求或失败证据。
2. sandbox/project-local candidate 与 Git diff。
3. skill name/frontmatter/schema 检查。
4. containment、junction/reparse、special file、package safety 检查。
5. 许可证、来源、revision、provenance、content hash。
6. 受影响测试、负例、预期副作用。
7. 独立 owner review（前六项的 schema/package/hash/test 检查与摘要可自动完成；自动验证只保留 `proposal`，不自称 review）。
8. 显式 admission 到 source/config/lock。
9. build/projection receipt。
10. fresh host probe 与真实任务验收。

### 非目标

- 自动从 memory 生成/覆盖生产技能。
- AI 自审、自批、自发布。
- 长期候选库、隐式训练集或在 skills-manager 中保留 Hermes task 历史。

### 停止条件

- 候选被自动复制到全局技能目录、自动进 lock、自动投影或自动发布。
- AI author 与 admission approver 无法保持独立。

## 9. R7：受限规模化

只有 R3、R5（如需要）和 R6 都有稳定证据后，才考虑：

- 单一 Hermes Gateway 入口；
- 显式任务租约和 worktree 分配；
- 只读探索/测试/review 的 Codex 子代理；
- CI 使用 Codex SDK 或现有 CI，而非以 app-server beta 作为唯一发布机制；
- 仅在不满足预先声明的本地 POC auto-merge envelope 时人工批准 merge；任何 push/release 仍由人工批准。

任何并行写入必须满足“互斥 write set + 独立 gate + 串行集成”。若无法满足，保持串行。

### 停止条件

- 出现 write collision，或互斥 write set 与串行集成无法维持。
- 任一环节要求无人监管的 merge/push/release 或自动业务验收。
