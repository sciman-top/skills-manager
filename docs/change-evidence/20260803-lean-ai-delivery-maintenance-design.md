# Lean AI Software Delivery maintenance design evidence

**program_id**: `skills-manager-vnext`
**track**: `maintenance_design`
**base_phase**: `P5`
**verification_level**: `repo_verified`（仅 maintenance design planning package）
**baseline_commit**: `6a234d7bc3f1a5767ec48da39e88e28556d0e330`
**baseline_worktree**: clean `main...origin/main`
**日期**: 2026-08-03

## 1. 用户授权与问题背景

用户明确授权落盘 skills-manager 面向高效 AI 软件交付的总体方案、PRD、路线图、实施计划、spec、verifier、任务清单和证据。核心问题是 AI 编码容易在需求/定位未澄清时过度设计、预优化和堆叠门禁，主链没有跑通；固定角色接力、无差别全流程和未经验证的自学习又放大 token、返工和方向漂移。

授权边界只包含规划资产、只读 companion verifier、Pester fixtures 和本证据；不包含新 Agent Runtime、长期任务引擎、固定角色系统、10-task pilot、生产动作、付费模型调用或宿主写入。

## 2. 起点与工作树分界

- 起点：`main...origin/main`，HEAD 如文件头所示；实施前 `git status --short --branch` 无工作树改动。
- `tasks/skills-manager-vnext-phase6.tasks.json` 在起点不存在。
- 本切片开始时没有需要保留或排除的既有用户改动。
- 本切片不得修改 `src/`、`overrides/`、`agent/`、`vendor/`、`reports/`、`skills.json`、provider/auth/model/sandbox/session 或 plugin/MCP 状态。

## 3. Write set

更新：

- `docs/product/skills-manager-vnext-prd.md`
- `docs/product/skills-manager-vnext-architecture.md`
- `docs/product/skills-manager-vnext-roadmap.md`
- `docs/product/README.md`
- `tasks/plan.md`
- `tasks/todo.md`
- `AGENTS.md`

新增：

- `docs/superpowers/specs/2026-08-03-lean-ai-delivery-maintenance-design.md`
- `tasks/skills-manager-vnext-maintenance-design.tasks.json`
- `scripts/verify-lean-ai-delivery-planning.ps1`
- `tests/Unit/LeanAiDeliveryPlanning.Tests.ps1`
- `docs/change-evidence/20260803-lean-ai-delivery-maintenance-design.md`

## 4. 官方与社区参考

本次只读核对当前 Codex manual（2026-08-04 本机 helper 报告 cache current）中的 Best practices、AGENTS.md、Skills、Plugins、MCP 与 Hooks 章节；采用其 surface 分工：prompt/thread 承载一次性约束，短而准确的 `AGENTS.md` 承载稳定仓库事实，重复稳定 workflow 进入 skill，外部动态数据/动作使用 MCP/connector，plugin 组合可安装能力，确定性 enforcement 进入 hook/script/CI。官方来源链接已登记在 PRD。

社区项目只作为产品级结构参考；本轮没有 clone、fetch、安装或执行上游脚本：

| Source | Disposition | 采纳/边界 |
| --- | --- | --- |
| OpenAI Codex official surfaces | `adopt` | 最小 surface、native runtime/approval、skills/MCP/plugin 分工、evidence-before-acceptance |
| `github/spec-kit` | `adapt` | 采用 requirement→architecture→spec→plan→task→verifier 追踪；不继承强制 TDD、固定文件数或全程人工审批 |
| `obra/superpowers` | `adapt` | 采用可组合 workflow、根因调试和完成前验证；不启用 always-on 全套流程 |
| Obsidian | `defer` | 可作为用户拥有的 Markdown 知识库；不成为 runtime、数据库或必需依赖 |
| Hermes agent | `defer` | 只在外置长任务场景另行验证；不成为本仓执行内核或 auth/session 真源 |
| OpenHands / LangGraph | `defer` | 作为 agent runtime/state graph 对照；当前无 P6/runtime 准入证据 |
| 固定多角色 Agent 团队 | `reject` | 保留责任 lens，拒绝机械角色实例化、接力文档与多 writer 冲突 |
| 未回放即自动沉淀 skill | `reject` | 使用 candidate→replay→shadow→canary→reviewed promotion→retire |

外部项目的 revision/license/checksum 仅在未来实际复制、安装或执行前锁定；当前 disposition 不构成供应链准入。

## 5. 实现摘要

- 既有 PRD/架构/路线图继续作为唯一产品真源；新增 JTBD、FR/NFR、ADR、生命周期模式、Product Baseline、Slice Contract、bounded autonomy、责任 lens、反过度设计停止条件、skill 生命周期和工具组合边界。
- 新建非 Phase 的 maintenance spec/manifest；四个 planning tasks 共用本 evidence，M1 pilot 不进入当前 manifest。
- companion verifier 先调用现有 P5 planning verifier，再检查 maintenance 元数据、依赖、引用覆盖、todo 状态、runtime write-set denylist、共享 evidence、P6/pilot/runtime/live 状态、observe-only 指标和 full-suite 单次声明。
- 新 tests 使用只复制 verifier 所需文件的 fixtures，覆盖 current pass 与关键 fail-closed 场景。
- 根 `AGENTS.md` 只登记维护真源与非 P6/live 边界，没有复制完整方案。

## 6. Verification evidence

有序执行在产品/规划/测试文件稳定后完成。第一次 full 命令的外层观察通道在 120 秒超时（exit 124），遗留 gate 进程随后结束但 stdout/exit code 句柄不可恢复，因此该次不作为验收证据；确认无并发进程后，以 10 分钟外层超时执行一次权威恢复运行并取得完整 exit 0 输出。没有单独调用完整 suite。

| Order | Command | Result |
| ---: | --- | --- |
| 1 | `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` | exit 0；`Build success: D:\CODE\skills-manager\skills.ps1` |
| 2 | focused `ProductPlanning.Tests.ps1,LeanAiDeliveryPlanning.Tests.ps1` | exit 0；29 passed / 0 failed（P5 13 + maintenance 16） |
| 3 | `scripts/verify-vnext-planning.ps1 -Json` | exit 0；P5 pass，5 done / 0 open / 0 findings |
| 4 | `scripts/verify-lean-ai-delivery-planning.ps1 -Json` | exit 0；maintenance pass，4 done / 0 open / 0 findings |
| 5 | `scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` | 权威恢复运行 exit 0；Unit 729、E2E 18 全通过；107 skills；routing findings 0；host matrix 5/7；P5 planning 5/5；total 147859 ms |
| 6 | `git diff --check` / `git status --short --branch` | exit 0；仅 12 个本切片文件；`main...origin/main`；P6 manifest=false；forbidden changed paths=0 |

full 输出中的写入/更新日志全部来自 Pester `TestDrive`/临时 fixture；最终仓库 name-only 边界未包含 runtime/config/host 路径。full 后只修改本 evidence 的结果表；随后重跑 companion/P5 planning verifier 与 `git diff --check`，不重复完整 suite。

## 7. Truth boundary

- P5 保持 5/5 `repo_verified`；本切片不改 P5 runtime、schema 或历史 evidence。
- `P6_ADMISSION_STATUS` 保持 `hold`，不创建 P6 manifest。
- M0 仅在上述门禁通过后表述为“maintenance design planning package repo_verified”。
- M1-M3 为 `conditional`；10-task observe-only pilot 未执行，TTFV/返工/人工打断等尚无新 baseline 或效果结论。
- 没有 host/runtime/provider/auth/session/plugin/MCP 变化；没有新的业务 workflow、host load 或 production acceptance 证据。

## 8. Rollback

只撤销第 3 节列出的本切片文件/增量。删除 companion verifier/tests 后，原 P5 verifier 仍是独立真源；撤销 maintenance spec/manifest/plan/todo 章节不影响 P0-P5 历史合同。不得回滚或覆盖任何实施后出现的无关用户改动、生成物、imports、runtime reports 或宿主配置。
