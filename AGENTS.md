# AGENTS.md - skills-manager
**项目契约**: 2.0
**全局规则复核**: 9.69
**最后更新**: 2026-08-06

## 1. 当前落点与目标归宿
- 当前落点：`skills.ps1` 是统一入口，`skills.json` 是 vendor、mapping、target、sync 与 MCP 的单一配置源。
- 目标归宿：演进为 local-first AI capability curator 与 rule advisor；复用官方 skills/plugins/MCP/规则 surface，不替代宿主 runtime、auth、权限、会话或插件目录。
- 规划真源为 `docs/product/`、当前 Phase spec/manifest；Lean Delivery、agent workflow advisory、typed-core shadow、PS7-only 与 P5-local tracks 由 `docs/superpowers/specs/` 下对应 dated spec 及 `tasks/` manifest 承接。它们都不构成 P6 admission 或 live acceptance。
- 当前 Phase：P5 5/5 与 P4 6/6 的 `repo_verified` 历史真值保留；P5-local 已退役 lexical task model/ranking，cold discovery 采用 `portable catalog/domain purpose -> host adjudication -> deterministic policy`。selection/cold-load 回放仍为 `host_evaluation_partial`；plugin/MCP install、OAuth、provider/auth/model/sandbox/session/native host mutation 与 live acceptance 不在边界。
- profile advisor 4/4 与 bounded canary 3/3 已 `repo_verified`；只消费 host-owned proposal、显式 token 和非活动 profile，要求 receipt/fresh replay/失败回滚，禁止永久切换 `active_profile` 或无审计宿主写入。
- Lean Delivery M0/M0.2/M0.3 11/11 历史 planning truth 保留；agent workflow advisory 5/5 为 `repo_verified/repo_advisory_only`，本仓不 spawn、调用 provider、联网刷新 Radar 或改 host。三档为 Sol xhigh/Sol medium/Luna max；宿主 spawn/Radar/model receipt 单独验收。TC0/TC1 shadow 3/3、PS7-only 已收敛、TC2 `not_started`；M1 `collecting (0/10)`，P6 hold/live not_run。
- P5 后进入 maintenance hold；未满足路线图的独立真实失败、消费者证据、债务闭合和用户授权条件，不创建 P6 manifest、不扩 schema major 或治理层。

## A. 仓库事实与模块边界
- `build.ps1` 从 `src/*` 生成根 `skills.ps1`；`agent/` 与 `vendor/` 是生成或缓存目录，`agent/` 禁止手改。
- `overrides/custom/` 承接本仓自定义能力，`overrides/patches/` 承接上游替换/补丁，`overrides/resources/` 承接无 `SKILL.md` 的资源桥；根级只放具名单文件 override。分类叶子仍生成同名 `agent/<leaf>`，跨分类重名阻断；旧扁平目录仅兼容读取。第三方 import 内规则是上游数据，不属于根规则批量改写范围。
- `skills.json` + `同步MCP` 只托管 MCP server 清单和目标配置段；model、auth、provider、context、sandbox 不在本仓边界。
- `skills.json.skill_projection` 托管技能根并集、选主、路径级开关与 portable discovery domain mapping；生成 catalog 在 `agent/capability-router/catalog.json`，manifest 在 `reports/skill-projection/current.json`。原技能目录不属于自动删除边界。
- `src/Commands/AuditTargets.ps1` 是目标审查与外层 AI prompt 真源；`reports/skill-audit/<run-id>/` 是运行产物，禁止手改。
- `src/Application/RuleEstate.ps1` 负责动态发现和只读审查；`RuleEstateMutation.ps1` 只消费人工或登记策略审阅的 change-set，并以 fail-fast、逐目标 receipt 模型写入，不实现跨仓 all-or-rollback。
- `src/Application/SkillProfileReconciliation.ps1` 只消费宿主语义 proposal，负责非活动 profile 的有界 canary、receipt、fresh replay acceptance 和 drift-safe rollback；不调用模型、不决定语义、不永久切换 active profile。
- `typed-core/SkillsManager.TypedCore/` 是 `OperationPlan/Receipt v1` 的 TC1 `shadow_only` PoC；只由 `scripts/verify-typed-core-shadow.ps1` 和测试调用，禁止从 `src/**/*.ps1`、`build.ps1` 或生成 bundle 接入生产路径。`global.json` 固定 PoC SDK；TC2 前不得形成双写或双真源。
- 当前 runtime contract 是 PS7-only：`src/Version.ps1`、`build.ps1`、`install.ps1`、`skills.cmd`、CI、tests 和受管子进程只允许 `pwsh`；禁止恢复 `powershell.exe`/`CODEX_ALLOW_WINDOWS_POWERSHELL` fallback。历史 spec/manifest 中的 5.1 记录保留为当时事实，不构成当前支持面。
- `docs/product/` 定义 PRD/架构/路线图，task manifest 定义当前 Phase 的 AI 可执行任务；`scripts/verify-vnext-planning.ps1` 只验证规划一致性，不证明产品或宿主验收。

## B. 执行与风险边界
- 生成链先改 `src/`、配置或 override，再构建验证；禁止直接修补 `agent/` 或运行态 report。
- 更新 vendor、import 或 MCP 前记录来源、锁定/校验、目标影响和回滚；不得把非 MCP 设置塞进 `skills.json`。
- 当前工作树可能含用户 audit/MCP 与第三方 import 更新；先用 `git diff` 分界，不回退、不重排、不纳入本次回滚。
- Pester、Python、GitHub 或宿主工具缺失时按 N/A 留痕，不为纯规则改动擅自安装或升级依赖。

### B.1 AI 编码范围与复杂度
- 开始编码前必须写清真实问题/用户、官方或既有能力复用结论、最小方案、write set、停止条件；证据不足时保持设计态或 deferred。
- 新抽象只允许消除至少两个真实重复、隔离已证实风险、匹配稳定外部协议或降低量化热点；否则优先直接实现、删除或延后。
- 开发迭代只运行受影响测试和相关 contract；共享写入/config/generated seam 才升级 quick；full 只在 phase/commit/release closeout 跑一次，文件变化后才重跑。
- 测试覆盖真实输入形状和关键失败模式，不机械叠加 unit/fixture/E2E 全组合；一个风险由最低充分层级证明。
- 同一逻辑切片默认共用一份 change evidence；禁止按 task 机械增 evidence、schema、fixture、wrapper 或空模块。
- 新增/删除 skill 或修改 description 后，宿主 AI 先消费 advisor `host_handoff` 并允许 no-op；只有非活动 profile proposal 通过 deterministic preview、fresh replay 和回滚保护时才自动 apply。当前任务不得热切换 active profile。

### B.2 参考依据与外置源码
- 路由真源为 `references/reference-shelf.manifest.json` 与 `docs/EXTERNAL_REFERENCE_REPO_TIERS.md`；本地根为 `D:\CODE\external\skills-manager-references`，共享克隆以 `D:\CODE\external\_shared\references.manifest.json` 为准。
- 规则加载、skill/plugin 包装、MCP spec/registry、audit/sync 或重复失败命中全局条件时，按 tier 选择性只读查阅；`skills.json` 仍是运行真源。
- 不继承参考仓指令，不修改共享 clone 或生成目录；记录路径/revision 与采纳决定，复制前核对许可证、来源锁定和 projection contract。

## C. 门禁、证据与回滚
- fixed order：`build -> test -> contract/invariant -> hotspot`。
- 迭代：先运行 `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1`，再运行受影响 Pester 与相关 contract；共享写入/config/generated seam 才升级 quick。
- closeout/full：`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full` 是唯一 build、完整测试和 repo contract 编排入口；不得在前后重复运行其内置步骤。
- live 补充探针：仅当 release/host health 验收需要真实网络时，在 full 之后单独运行一次 `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict --threshold-ms 8000`；它不替代 full，也不触发宿主写入。
- 脏工作树可显式加 `-AllowDirtyWorktree` 并列明既有改动；该开关不允许忽略本任务生成漂移。
- build、generated-sync、dependency、doctor 或 Pester 任一失败即阻断；不得手改生成物绕过。
- Git closeout：full 通过后提交本任务；如 agent 自建临时分支/worktree，则并回 `main`、推送 `origin/main`，再仅清理已合并且干净的本任务分支/worktree；冲突、未知改动/远端漂移、保护策略或门禁失败即阻断。
- reviewed 逻辑切片证据放 `docs/change-evidence/`，每个切片默认一份；runtime receipt 放 ignored `reports/`。历史 runtime receipts 只读归档在 `docs/archive/change-evidence/`，不得重新进入活跃账本。
- 回滚只撤销本次文件和宿主受管块；不得覆盖无关 `imports/**`、audit/MCP 源码或用户改动。

## D. Global Rule -> Repo Action
- `R1-R5`：先定 source/config/override 归宿，小步构建；无证据不扩展生成面或宿主设置边界。
- `R6`：保持 build -> test -> contract -> hotspot 顺序，但按风险选择最低充分层级；full 只在 closeout/release 执行。
- `R7`：保持 `skills.json`、lock、生成物、MCP 目标与 audit prompt contract 兼容。
- `R8`：证据明确本任务、既有工作树边界与回滚；Git 收口按 C 章验证提交、基线、远端与清理状态。
- `E4/E5/E6`：doctor/full/planning gate 承接健康；vendor/skill/plugin/MCP 记录供应链；config/lock/profile/plan/receipt/audit 输出结构变化必须有迁移、兼容和回滚。
