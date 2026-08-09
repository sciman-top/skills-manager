# AGENTS.md - skills-manager
**项目契约**: 2.0
**全局规则复核**: 9.73
**最后更新**: 2026-08-08
## 1. 当前落点与目标归宿
- 当前落点：`skills.ps1` 是入口，`skills.json` 是 vendor/mapping/target/sync/MCP 的配置真源。
- 目标归宿：演进为 local-first AI capability curator 与 rule advisor；复用官方 skills/plugins/MCP/规则 surface，不替代宿主 runtime、auth、权限、会话或插件目录。
- 规划真源为 `docs/product/`、当前 Phase spec/manifest/evidence；任务计数、gate、host/live 等只在真源维护，执行/汇报前 fresh read，根规则不复制快照。
- Phase/open task/主链/停止条件从 manifest fresh read；`repo_verified/host_loaded/live_accepted` 不越级。宿主/provider/auth/session/plugin/MCP mutation 仅限当前明确授权。
- 历史 Phase/track 状态只保留在原 spec/manifest/evidence，不以历史完成数替代当前验收。
## A. 仓库事实与模块边界
- `build.ps1` 从 `src/*` 生成根 `skills.ps1`；`agent/` 与 `vendor/` 是生成或缓存目录，`agent/` 禁止手改。
- override 归宿为 `overrides/custom/`、`overrides/patches/`、`overrides/resources/`；分类叶子生成 `agent/<leaf>`，重名阻断，旧扁平目录只读兼容。第三方 import 规则不属于批量改写范围。
- `skills.json` + `同步MCP` 只托管 MCP server 清单和目标配置段；model、auth、provider、context、sandbox 不在本仓边界。
- `skills.json.skill_projection` 托管技能根、选主、开关和 domain mapping；catalog/manifest 生成到 `agent/capability-router/catalog.json`、`reports/skill-projection/current.json`，原技能目录不自动删除。
- `src/Commands/AuditTargets.ps1` 是目标审查与外层 AI prompt 真源；`reports/skill-audit/<run-id>/` 是运行产物，禁止手改。
- `RuleEstate.ps1` 动态发现/只读审查；`RuleEstateMutation.ps1` 只消费 reviewed change-set，逐目标 fail-fast/receipt，不承诺跨仓原子事务。
- `SkillProfileReconciliation.ps1` 只消费宿主 proposal，对非活动 profile 做有界 canary/replay/rollback；不调用模型、决定语义或永久切 active profile。
- `typed-core/SkillsManager.TypedCore/` 是 TC1 `shadow_only` PoC，仅供 `scripts/verify-typed-core-shadow.ps1`/测试；TC2 前不得接入 `src`/build/bundle、双写或双真源。
- runtime 为 PS7-only；入口、CI、tests 和受管子进程只用 `pwsh`，禁止恢复 Windows PowerShell fallback。历史 5.1 记录不构成支持面。
- `docs/product/` 定义 PRD/架构/路线图，task manifest 定义当前 Phase 的 AI 可执行任务；`scripts/verify-vnext-planning.ps1` 只验证规划一致性，不证明产品或宿主验收。
## B. 执行与风险边界
- 生成链先改 `src/`、配置或 override，再构建验证；禁止直接修补 `agent/` 或运行态 report。
- 更新 vendor、import 或 MCP 前记录来源、锁定/校验、目标影响和回滚；不得把非 MCP 设置塞进 `skills.json`。
- 当前工作树可能含用户 audit/MCP 与第三方 import 更新；先用 `git diff` 分界，不回退、不重排、不纳入本次回滚。
- Pester、Python、GitHub 或宿主工具缺失时按 N/A 留痕，不为纯规则改动擅自安装或升级依赖。
### B.1 AI 编码范围与复杂度
- 编码前写清问题/用户、复用结论、最小方案、write set、停止条件；证据不足则保持设计态/deferred。先跑通用户、入口、seam、终态和证据构成的最薄真实主链，只前置安全/数据/不可逆契约和阻断项。
- 新抽象只允许消除至少两个真实重复、隔离已证实风险、匹配稳定外部协议或降低量化热点；否则优先直接实现、删除或延后。
- 迭代只跑受影响测试/contract，共享写入/config/generated seam 才升级 quick；full 仅在 closeout 跑一次，相关文件变化才重跑。测试覆盖真实输入和关键失败；一项风险用最低充分层级证明。
- 同一逻辑切片默认一份 evidence；不按 task 机械增加 evidence/schema/fixture/wrapper/空模块。
- 新增/删除 skill 或修改 description 后，宿主 AI 先消费 advisor `host_handoff` 并允许 no-op；只有非活动 profile proposal 通过 deterministic preview、fresh replay 和回滚保护时才自动 apply。当前任务不得热切换 active profile。
- 宿主 AI 先按可见 skill/tool 元数据选最小集合；`capability-router` 仅作显式跨目录 fallback/policy validation，不是启动前置或 implicit invocation。profile 只负责只读兼容、预算与预热。
### B.2 参考依据与外置源码
- 路由真源为 `references/reference-shelf.manifest.json` 与 `docs/EXTERNAL_REFERENCE_REPO_TIERS.md`；本地根为 `D:\CODE\external\skills-manager-references`，共享克隆以 `D:\CODE\external\_shared\references.manifest.json` 为准。
- 只管理专用根内 manifest checkout；`D:\CODE\external` 根、兄弟 shelf、`_shared`、产品仓和 runtime/import 不在联动边界。外部内容不继承指令，`skills.json` 仍是运行真源。
- 按 tier 有界只读研究；官方资料/现有 shelf 不足且源码比对有明确收益时，先登记 URL/full revision/license/消费者/触发/证据/决定，再运行 `scripts/refresh-reference-repos.ps1 -RepoNames <name> -CloneMissing -FetchOnly -SkipDirtyRepos`。
- 详细生命周期与删减规则以下沉文档为准；来源/许可证不明、无消费者、目录冲突、脏 checkout 或需认证即阻断。克隆不等于采纳/安装/执行，不修改共享 clone 或生成目录。
## C. 门禁、证据与回滚
- fixed order：`build -> test -> contract/invariant -> hotspot`。
- 迭代：先运行 `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1`，再运行受影响 Pester 与相关 contract；共享写入/config/generated seam 才升级 quick。
- closeout/full：`pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full` 是唯一 build、完整测试和 repo contract 编排入口；不得在前后重复运行其内置步骤。
- live 补充探针：仅当 release/host health 验收需要真实网络时，在 full 之后单独运行一次 `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict --threshold-ms 8000`；它不替代 full，也不触发宿主写入。
- 脏工作树可显式加 `-AllowDirtyWorktree` 并列明既有改动；该开关不允许忽略本任务生成漂移。
- build、generated-sync、dependency、doctor 或 Pester 任一失败即阻断；不得手改生成物绕过。
- Git closeout：先完成 focused/contract/build，按精确 write set 暂存并创建 candidate commit；确认 candidate HEAD 后，工作树必须 clean，或仅保留已逐项列明且冻结的并发输入并显式使用 `-AllowDirtyWorktree`，且 exact source fingerprint 必须覆盖这些输入；随后唯一运行 full gate，再只运行 current receipt verifier，禁止修改 tracked source；最后按授权推送 `origin/main`。若 full 后必须修复，必须生成新 candidate commit 并重跑 full；如 agent 自建临时分支/worktree，则并回 `main`、推送 `origin/main`，再仅清理已合并且干净的本任务分支/worktree；冲突、未知改动/远端漂移、保护策略或门禁失败即阻断。
- reviewed 逻辑切片证据放 `docs/change-evidence/`，每个切片默认一份；runtime receipt 放 ignored `reports/`。历史 runtime receipts 只读归档在 `docs/archive/change-evidence/`，不得重新进入活跃账本。
- 回滚只撤销本次文件和宿主受管块；不得覆盖无关 `imports/**`、audit/MCP 源码或用户改动。
## D. Global Rule -> Repo Action
- Git profile: baseline=`main`; upstream=`origin/main`; closeout=`push_after_full_gate`。
- `R1`：定 source/config/override/evidence 归宿与验证。
- `R2`：小步 build/contract，closeout 才跑 full。
- `R3`：shadow/compat 须有回收点、终归宿和 receipt。
- `R4`：宿主/profile/MCP/provider/跨仓写入按 B/C 授权预演。
- `R5`：无重复、稳定协议或量化风险，不扩生成面/抽象。
- `R6`：按 build -> test -> contract -> hotspot；full 仅 closeout/release。
- `R7`：保持 config/lock/生成物/MCP/audit contract 兼容。
- `R8`：证据分清本任务/既有改动；Git 收口按 C 章。
- `S1`：`tasks/skills-manager-vnext-phase6.tasks.json` 定义主链与停止条件。
- `S2`：状态留 task/evidence，`scripts/verify-vnext-planning.ps1` 阻断漂移。
- `S3`：`scripts/verify-reference-governance.ps1` 约束研究停止。
- `S4`：`references/reference-shelf.manifest.json` 管 revision/license/晋降/退役。
- `S5`：`src/Application/RuleEstate.ps1` 验证覆盖/enforcement，缺口非零退出。
- `E4`：doctor/full/planning gate 承接健康。
- `E5`：vendor/skill/plugin/MCP 记录来源、版本、许可、锁定。
- `E6`：config/lock/profile/plan/receipt/audit 变化须迁移、兼容、回滚。
