# Hermes + Codex 实施计划与任务清单

**文档角色**：稳定的 14 项任务合同；动态执行状态、运行模式、commit、receipt 与当前 host 事实只保存于对应 POC 仓的任务 brief/receipt。
**执行原则**：每个任务都是独立授权单元；未满足前置条件时返回 `not_started` / `blocked`，不以“继续”自动扩大到主机配置、安装、合并或发布。
**并发原则**：文档任务可与不重叠的代码任务并行；同一 repo/worktree、同一 Hermes profile、同一 Codex config 的写任务必须串行。

## 1. 执行合同

每张任务卡必须在开始时声明：

```text
Goal
Exact write set
Authority domain
Minimum proof
Stop condition
Rollback scope
Truth boundary
```

每张任务卡还必须声明一个执行类别，避免让人工重复完成机械检查：

| 执行类别 | 行为 |
| --- | --- |
| `auto_evidence` | 只自动运行无共享宿主写入的 preflight、hash/inventory 对比、package/schema/test、固定 no-tool/read-only marker、worktree/receipt 汇总。 |
| `auto_stop` | 遇到 marker 缺失、显式 provider/API 失败、shared config/MCP/plugin 非预期差异、write-set 越界或并发 writer 时记录证据并停止；不重试、不换账户/提供方、不改配置、不回滚共享资产。 |
| `human_decision` | 只用于共享配置的保留/窄回滚、认证/权限/安装、共享技能 admission/projection、非预授权 merge、push/release 与真实验收。 |

`auto_evidence` 与 `auto_stop` 不能推导 `host_loaded` 或 `live_accepted`，也不得新建任务数据库、watcher 或常驻 daemon。

| 授权域 | 典型资产 | 不能由其推导的授权 |
| --- | --- | --- |
| 仓库 | `src/`、tests、`skills.json`、tracked docs、generated `skills.ps1`/`agent/` | `~/.hermes`、`~/.codex`、安装软件、Gateway、Git push |
| Hermes 宿主 | installer、profile、`.env`、Gateway、memory、cron | Codex config、共享技能 root、生产凭据、仓库 merge |
| Codex 宿主 | login、plugins、MCP、sandbox、`~/.codex` | Hermes profile、skills-manager config、业务验收 |
| Git/发布 | worktree、commit、push、merge、release | host_loaded、live_accepted |

## 2. 任务总表

| ID | 准入方式 | 依赖 | 目标 | 主要 owner | 写入域 |
| --- | --- | --- | --- | --- | --- |
| HSM-DOC-001 | baseline design | 无 | 固化策略、PRD、架构、路线图和任务卡 | skills-manager maintainer | tracked docs |
| HSM-POC-010 | 当前 host 授权 | HSM-DOC-001 | 同机协调模式 preflight | operator | 只读 host + POC repo |
| HSM-POC-020 | 当前安装授权 | HSM-POC-010 | 安装 Hermes、建立独立 profile | operator | Hermes host |
| HSM-POC-030 | POC write approval | HSM-POC-020 | 项目级技能消费验证 | Hermes + operator | POC repo only |
| HSM-POC-040 | 当前 Hermes/Codex host 授权 | HSM-POC-030 | 同机受控 Codex runtime 探针 | operator + Hermes + Codex | POC host config + one worktree |
| HSM-POC-050 | 当前 worktree/merge-policy 授权 | HSM-POC-040 的已批准 runtime path | 单需求实现/测试/review/人工收口 | Hermes + Codex + human | one worktree |
| HSM-DEC-060 | reviewed decision | HSM-POC-050 | 判断是否真的需要 consumer code | human + maintainer | reviewed decision only |
| HSM-CODE-100 | conditional code authorization | HSM-DEC-060=add | 定义最小 consumer contract | skills-manager maintainer | source/tests/docs/generated seam |
| HSM-CODE-110 | conditional code authorization | HSM-CODE-100 | 实现 projection transaction 或复用现有路径 | skills-manager maintainer | source/tests/config/generated seam |
| HSM-CODE-120 | conditional code authorization | HSM-CODE-110 | 负例、rollback 与 host-boundary 验证 | skills-manager maintainer | tests/scripts/docs |
| HSM-EVO-200 | POC write approval | HSM-DOC-001 | 受控技能演进的 proposal/review/admission 试运行 | human + host AI | sandbox/project skill + Git review |
| HSM-EVO-210 | conditional code authorization | HSM-EVO-200 evidence | 增加最小 admission verifier | skills-manager maintainer | source/tests/config/generated seam |
| HSM-OBS-220 | conditional code authorization | stable Hermes CLI contract | Hermes 只读 observer | skills-manager maintainer | source/tests/docs |
| HSM-REF-300 | explicit reference refresh authorization | real consumer | Hermes reference shelf 准入 | maintainer | manifest + external checkout |

## 3. 原子任务卡

### HSM-DOC-001：版本化设计合同

- **Goal**：把策略、路线图、任务依赖和 PRD/Architecture 边界写入 tracked docs。
- **Exact write set**：`docs/product/README.md`、PRD、Architecture、strategy、roadmap、implementation plan。
- **不得触及**：`src/`、`skills.json`、`skills.ps1`、`agent/`、`~/.codex`、`~/.hermes`。
- **Minimum proof**：所有索引链接存在；PRD、Architecture 与任务卡都将 Hermes 标为外部/未来/POC 门禁；`git diff --check` 通过。
- **Stop condition**：发现现有文档或并发改动已定义冲突的产品边界；停止并以 diff 说明冲突。
- **Rollback**：仅撤销本任务的文档行。
- **Truth boundary**：`repo_verified`；不代表 Hermes 已安装或任何宿主加载。

### HSM-POC-010：同机协调模式 preflight

- **Goal**：为同一 Windows 用户下的低侵入协作建立可比较基线。
- **Exact write set**：默认无；若用户授权，可创建 POC repo 与其内的基线清单。不得改主机配置。
- **输入**：当前 Codex config 路径/哈希、公开 plugin/MCP inventory、主 `~/.agents/skills` 路径/哈希、POC repo Git status、工作目录与计划门禁。
- **步骤**：
  1. 读取而不修改主 Codex/Hermes 目录。
  2. 建立小型 POC repo 或选择干净测试仓；只创建一个 worktree。
  3. 写出一个任务 brief：task id、repo、worktree、允许写集、gate、stop、rollback。
  4. 记录“同机协调模式不启用 Hermes Codex runtime”。
- **Minimum proof**：所有基线可复读；POC repo 清楚指向一个 worktree；未发现生产 token/私钥被 POC 使用。
- **Stop condition**：无法区分主配置与 POC 配置，或 POC 已包含生产凭据。
- **Rollback**：删除本次 POC repo/worktree 前先确认无未提交用户资产；不改主机状态。
- **Truth boundary**：只证明 preflight，不能证明 Hermes/Codex 联通。

### HSM-POC-020：Hermes 安装与 profile 初始化

- **Goal**：在同机协调模式下获得一个独立 Hermes profile，而不启用 Codex runtime。
- **Authority domain**：Hermes host；需要当前安装授权。
- **Exact write set**：Hermes installer 所创建的安装目录、`codex-poc` profile 的 config/`.env`/session root；不含 `~/.codex`。
- **步骤**：
  1. 优先使用 Hermes 官方 Desktop installer；CLI 安装方式只在当前操作者确认后使用。
  2. 运行 `hermes doctor`，创建 `codex-poc` profile。
  3. 设置 POC `terminal.cwd`，启用 `skills.write_approval` 与 `memory.write_approval`。
  4. 不添加 Gateway token、cron、Kanban、production MCP，不开启 `codex_app_server` runtime。
- **Minimum proof**：Desktop/CLI 使用 `codex-poc` profile；profile 与默认 profile 分离；主 Codex config 哈希不变。
- **Stop condition**：安装器要求非预期提权，或写入/修改主 Codex config。
- **Rollback**：使用 Hermes 官方卸载/配置恢复路径仅移除 `codex-poc`；不批量删除 `~/.hermes`。
- **Truth boundary**：`filesystem_projected`（Hermes profile）；不代表 Gateway、Codex runtime 或自动化已验收。

### HSM-POC-030：项目级技能消费

- **Goal**：证明 Hermes 在 POC repo 中能读取已批准的项目技能，而不修改共享全局技能 root。
- **Exact write set**：仅 `<poc-repo>/.agents/skills/` 的经过 Git 审查的样本；Hermes pending 目录可产生待审批 artifact，但不得 apply。
- **步骤**：
  1. 在 POC repo 放置一个最小 SKILL.md fixture，包含清晰 name/description 和无外部副作用步骤。
  2. 启动 Hermes 时显式使用 POC repo 为 cwd。
  3. 检查技能发现结果、pending skill/memory 写入队列、主 `~/.agents/skills` 前后 hash。
  4. 运行一个只读任务，要求 agent 引用该项目技能但不改文件。
- **Minimum proof**：预期 skill 可见；主共享 root 未变；无 pending write 被误 apply。
- **Stop condition**：Hermes 对项目技能或共享 root 发起未审批写入。
- **Rollback**：还原 POC repo Git change；拒绝 pending write；不删除外部 root。
- **Truth boundary**：skill discoverable，不代表 skill 已在真实任务正确执行。

### HSM-POC-040：同机受控 Codex runtime 探针

- **Goal**：在明确授权后，验证一个明确命名的运行路径。`native_openai_codex` 用于隔离 profile 中的一次有界 Hermes→Codex 调用；`codex_app_server` 用于评估 opt-in app-server 对当前用户 Codex config 的实际影响。两条路径的通过证据不得互相替代。
- **Authority domain**：Hermes + Codex host；必须单独获得当前授权，不能从 HSM-POC-020 推导。选择 `codex_app_server` 还须明确授权当前用户 Codex config 的预期 Hermes managed block 写入。
- **Exact write set**：`native_openai_codex` 仅可写 POC profile-owned auth/session/receipt state，主 Codex config 与 POC worktree 保持不写；`codex_app_server` 才可写 POC profile、当前用户 Codex config 的预期 Hermes managed block，以及一个 POC worktree。两种模式均不得触及其他 repo/worktree 或主共享技能 root。
- **步骤**：
  1. 明确记录所选 runtime path，备份并 hash 当前 Codex config，读取公开 plugin/MCP inventory。
  2. 分别完成 `codex login` 与 Hermes `openai-codex` 授权；认证成功本身不证明 app-server 已启用。
  3. `native_openai_codex`：可作为 `auto_evidence` 运行一条固定、无工具或 read-only Codex 任务，并核对主 config 与 POC worktree 未发生未授权变化；marker 缺失或显式 provider/API 失败时立即 `auto_stop`。
  4. `codex_app_server`：直接 process-scoped read-only probe 只有在当前 task brief 明确允许且预期不写共享 config 时才可 `auto_evidence`；启用 Hermes CLI runtime、managed-block migration 或任何 shared-config 写入仍是 `human_decision`。启用后立即比较 config diff，确认 only expected managed block、MCP/plugin 描述与权限变化；首回合保持 read-only 或逐操作审批。
  5. 只有所选路径的最低证明通过后，才允许 HSM-POC-050 的另行授权 write task；app-server 路径仍需先通过步骤 4 才能放开任何 workspace write。
- **Minimum proof**：native 路径需要 profile/auth 状态、任务 marker/receipt、主 config 与 POC worktree 未变；app-server 路径还需要 app-server 已启用的直接证据、审查后的 config diff 与 POC worktree containment。两者都要求无自动 merge/push，且结果可回溯至 task brief。
- **Stop condition**：主 config 出现 managed block 外的非预期改动、未批准 plugin/MCP migration、写入越过 worktree、或无法解释的权限变化时 `auto_stop`；只生成脱敏差异摘要，等待 `human_decision`，不得自动重试、换账户、修改/恢复 shared config。
- **Rollback**：native 路径只移除本次 profile-owned credential/session state（若被拒绝）；app-server 路径用步骤 1 备份恢复本次 managed block/POC config，只回滚该任务 worktree；两者均不覆盖用户其他 Codex 配置。
- **Truth boundary**：`native_openai_codex_verified` 不等于 `codex_app_server_verified`；任一一次 runtime POC 均不代表持续稳定、CI 适用、`host_loaded` 或主生产系统已接受。

### HSM-POC-050：单任务实现闭环

- **Goal**：验证 Hermes 任务状态与 Codex 执行在一个真实但低风险需求中的 handoff。
- **前置**：HSM-POC-040 的已批准 runtime path 已完成其对应最低证明；若任务声称 `codex_app_server` 行为，必须使用已验证的 app-server 路径，不能复用 native 路径证据。
- **Exact write set**：唯一获分配 worktree、Hermes POC task state、必要的 POC receipt。禁止主分支直接写入。
- **步骤**：
  1. ChatGPT Desktop 产出 task brief；写任务需要当前授权或已声明的 standing policy。若希望减少人工 merge，brief 必须显式写入 `allow_auto_local_merge=true` 及其封闭条件。
  2. Hermes 创建/记录 task；明确 worktree owner 和 gate。
  3. Codex 完成实现；只在该 worktree 内调用有界子代理。
  4. 执行仓库最低 build/test/contract gate。
  5. 独立进行 code review；仅在无 remote 的 POC 仓、唯一 worktree、固定 write set、无 host 差异、无凭据/生产配置/外部资产、gate/review 均通过且 brief 显式允许时，自动本地 commit/merge 并记录 receipt；其余情况由人工决定提交、合并或回滚。
- **Minimum proof**：task state、Git diff、gate output、review result，以及人工决定或满足封闭条件的 local merge receipt 可关联；无写入碰撞。
- **Stop condition**：任务重入、多个 writer、gate/review 未通过、auto-merge envelope 不完整或出现 remote/push 请求时 `auto_stop` 并转 `human_decision`。
- **Rollback**：仅撤销该 worktree/branch 的本次切片；任务标记 `rejected` 或 `rolled_back`。
- **Truth boundary**：`repo_verified` 与人工的仓库级决定；除非实际业务任务验收，否则不标记 `live_accepted`。

### HSM-DEC-060：是否需要改 skills-manager

- **Goal**：防止“成功运行 POC”被误解为“必须写 Hermes adapter”。
- **输入**：HSM-POC-030/040/050 的受审查证据；HSM-POC-040 必须标明 runtime path，不能用 native 路径证据声明 app-server 差异。
- **决策问题**：现有项目级技能与 native projection 是否已经满足 Hermes？若不满足，缺失的是 source/hash、target ownership、write policy、receipt 还是 rollback？
- **输出**：`no_code_needed`、`document_only` 或 `add_minimal_consumer_contract`。当自动收集的受审查证据未显示可复现 contract 缺口时，可直接输出 `no_code_needed`；只有要求新增 consumer contract 时才进入 `human_decision`。
- **Minimum proof**：每个 claimed gap 都能由一次可复现 POC 失败或重复人工成本证明。
- **Stop condition**：差异只是假设、审美偏好或“未来可能需要”。
- **Truth boundary**：设计决策，不是代码或宿主验收。
- **Decision rule**：若 reviewed evidence 未显示可复现的 contract 缺口，输出 `no_code_needed`，不创建 Hermes adapter、consumer registry、task state、runtime bridge 或新的 projection transaction。HSM-CODE-100、HSM-CODE-110、HSM-CODE-120 保持 `not_eligible`，直至一个真实、重复的 consumer 需求表明现有 native projection 无法表达 `consumer_id + source fingerprint + target root + ownership/write policy + receipt + rollback`。

### HSM-CODE-100：最小 consumer contract（条件实现）

- **仅在**：HSM-DEC-060=`add_minimal_consumer_contract` 时执行。
- **Goal**：在现有 projection 不能承载的真实差异上增加一个深 module，而非 generic host framework。
- **先读后写**：先只读检查 `src/Config.ps1`、`src/Application/SkillProjectionPlanning.ps1`、`src/Application/SkillProjection.ps1`、`src/Application/NativeSkillProjection.ps1` 与 `src/Application/NativeSkillProjectionCoordinator.ps1`。若已有 `native_projection` 或项目级 `.agents/skills` 已能表达 POC 的 consumer root、ownership、write policy、receipt 与 rollback，输出 `no_code_needed`，不得编码。
- **冻结 write set（仅确有表达缺口时）**：`skills.json`、`src/Config.ps1`、经 HSM-DEC-060 指定的一个既有 projection module、`tests/Unit/ConfigSchema.Tests.ps1`、`tests/Unit/ConfigUpdate.Tests.ps1`、`tests/Unit/NativeSkillProjection.Tests.ps1`、`tests/Unit/SkillProjection.Tests.ps1`；随后运行 `build.ps1` 生成 `skills.ps1`/`agent/`。PRD/Architecture 只在公开 contract 发生变化时同步更新。
- **不得触及**：`~/.hermes`、`~/.codex`、Hermes runtime、Gateway、task state。
- **目标数据**：`consumer_id`、`source_fingerprint`、`target_root`、`ownership_mode`、`write_policy`、`receipt_path`、`rollback`。
- **Minimum proof**：schema fail closed；root containment；hash drift；collision；external ownership；rollback；generated bundle sync。
- **Stop condition**：实现只是在 native projection 外包一层薄转发，或需要把 model/session/task 字段塞进 contract；不得为假设中的第二个 consumer 提前创建 adapter registry。

### HSM-CODE-110：projection transaction（条件实现）

- **仅在**：HSM-CODE-100 的 approved contract 无法由当前 plan/apply/receipt 路径直接承载时执行。
- **Goal**：优先在既有深 module 中复用或深化 consumer 的 plan/apply/receipt/rollback，不建立 Hermes orchestration framework。
- **冻结 write set**：plan 位于 `src/Application/SkillProjectionPlanning.ps1`；transaction/receipt 位于 `src/Application/SkillProjection.ps1` 与 `src/Application/NativeSkillProjection.ps1`；runtime assembly 仅在必要时改 `src/Application/NativeSkillProjectionCoordinator.ps1`。配置变化才改 `src/Config.ps1` 与 `skills.json`。对应更新 `tests/Unit/NativeSkillProjection.Tests.ps1`、`tests/Unit/SkillProjection.Tests.ps1`、`tests/Unit/CapabilityInventory.Tests.ps1`，并在 `build.ps1` 后核对生成物。
- **Minimum proof**：同一冻结 plan 可被独立 apply；receipt 绑定 source fingerprint、target root、ownership 与 write policy；stale source hash、target drift、external-owned asset 均 fail closed；rollback 只回收本 transaction 拥有的资源。
- **Stop condition**：现有 native projection 已经满足 approved contract，或实现需要读写 Hermes task/session/model/approval 状态。

### HSM-CODE-120：负例、rollback 与 host-boundary 验证（条件实现）

- **仅在**：HSM-CODE-110 有实际变更时执行；它是 HSM-CODE-110 的独立验证任务，不是第二个生产功能。
- **Goal**：把 transaction 的安全反例、补偿与 host 边界固化为可重复的 repo tests。
- **冻结 write set**：只改 `tests/Unit/SkillPackageSafety.Tests.ps1`、`tests/Unit/NativeSkillProjection.Tests.ps1`、`tests/Unit/SkillProjection.Tests.ps1`、`tests/Unit/CapabilityInventory.Tests.ps1`，以及确有新公开验证入口时的最小 scripts/docs；测试 fixture 必须在 `TestDrive:` 或临时 root，不能使用真实主机目录。
- **最小负例**：stale source hash、target drift、root escape、junction/reparse point、同名 conflict、partial failure、external-owned asset 与 rollback failure。package/root 输入复用 `Assert-SkillPackageSafe`，不得复制第二套 containment policy。
- **验证命令基线**：`build.ps1`、受影响 Pester 测试、`scripts/verify-skills-config.ps1 -Mode enforce`、`scripts/verify-skill-integrity.ps1`、`git diff --check`；跨面风险才运行一次 full gate。
- **Stop condition**：任何测试依赖真实 Hermes Desktop、`~/.hermes`、`~/.codex` 或真实主机写入；这些属于 POC/host acceptance，而非本任务。

### HSM-EVO-200：受控技能演进试运行

- **Goal**：验证 AI 可提出技能改进而不获得自动生产写权限。
- **Exact write set**：一个 POC repo 的项目级 `.agents/skills/<candidate>/`，以及对应 Git diff/review；不写全局 root。
- **步骤**：需求/失败证据 -> sandbox candidate -> 自动 package/schema/safety checks 与 diff/receipt -> 独立 review -> 显式 admission 决策 -> 可选 projection -> fresh host probe -> real task acceptance。自动验证可把候选保持在 `proposal`，但不得把它标记为 `reviewed` 或 `admitted`。
- **Minimum proof**：每个状态都有 owner、证据、下一步与回滚；AI author 与 admission approver 不同。
- **Stop condition**：proposal 被自动复制到全局技能目录、自动进 lock、自动投影或自动发布。

### HSM-EVO-210：admission verifier（条件实现）

- **仅在**：HSM-EVO-200 显示“手工验证步骤重复且现有 config/install/build seam 无法表达”时执行。
- **Goal**：把 package safety、identity、provenance、hash、reviewed input 与 explicit apply 收敛在小 interface 后。
- **非目标**：候选市场、长生命周期数据库、AI reviewer、agent memory、自动发布。
- **先读后写**：先检查 `src/Application/SkillSupply.ps1` 的 `Assert-SkillPackageSafe`、`src/Domain/SkillMetadata.ps1`、`src/Application/SkillCatalogCompiler.ps1` 与 `src/Config.ps1`；若 Git review + 已有 package safety + install/build/projection seam 已足以表达 admission，输出 `no_code_needed`。
- **冻结 write set（仅确有缺口时）**：只在上述 module、其既有配置 seam 与 `skills.json` 中实现最小 verifier；对应改 `tests/Unit/SkillPackageSafety.Tests.ps1`、`tests/Unit/SkillMetadata.Tests.ps1`、`tests/Unit/SkillCatalogCompiler.Tests.ps1`、`tests/Unit/ConfigSchema.Tests.ps1`，并在 `build.ps1` 后核对生成物。
- **Minimum proof**：无 reviewed input、provenance/license/hash 缺失或同一 AI self-approval 时 fail closed；测试覆盖 source/target escape、partial admission、package identity 与 explicit apply。不得写候选数据库或 `~/.agents/skills`。
- **Stop condition**：实现只是把现有 `Assert-SkillPackageSafe`、Git review 或 projection receipt 再包一层，或要求技能作者自动批准自己的候选。

### HSM-OBS-220：Hermes 只读 observer（条件实现）

- **仅在**：Hermes 发布稳定、公开、机器可读的 CLI/JSON contract 且真实 operator 需要时执行。
- **Goal**：报告 `not_observed`、`platform_na` 或 read-only observation，绝不推导 `host_loaded`。
- **不得触及**：profile config、memory、Gateway、task DB、skill write、Codex config。
- **Stop condition**：需要解析私有 Hermes 数据库/缓存，或 observer 被用于自动修复。

### HSM-REF-300：Hermes reference shelf 准入（条件实现）

- **仅在**：存在已实现 consumer 或明确 POC 维护需求时执行。
- **Goal**：以 `secondary` 或 `conditional` 记录 Hermes 的 URL、revision、license、consumer、refresh/rollback 影响。
- **Minimum proof**：manifest 验证、origin/dirty/containment 检查；普通 build/test 不依赖 checkout。
- **Stop condition**：仅因“热门/可能有用”就 clone，或尝试从 reference 自动导入 runtime code。

## 4. AI 执行提示模板

任何后续 AI 在领取 HSM-* 任务时，应先输出以下内容，并仅在 `human_decision` 时等待相应授权域：

```text
Task: HSM-XXX
Goal:
Current evidence:
Exact write set:
Out-of-scope assets:
Minimum verification:
Stop condition:
Rollback:
Truth boundary after completion:
Execution class: auto_evidence | auto_stop | human_decision
```

当任务涉及 Hermes/Codex 宿主时，必须额外声明：当前 Windows 用户、profile、repo/worktree、是否启用 runtime、是否会改变 `~/.codex`、是否含生产凭据。未知项、shared-config 写入或 block 外差异一律为 `human_decision`；其余不写共享资产的固定检查可直接 `auto_evidence`，而不是为人工收集重复日志。
