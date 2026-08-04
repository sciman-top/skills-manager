# Engineered agent workflow maintenance design evidence

**program_id**: `skills-manager-vnext`
**track**: `maintenance_design`
**milestone**: `M0.2`
**evidence_group**: `engineered_workflow_m0_2`
**status**: `repo_verified`
**date**: 2026-08-05
**base_revision**: `be9aa612`
**truth_ceiling**: `repo_verified planning_contract`

## Goal

把用户提出的 coordinator、lease、Git CAS、Trellis task workflow、技能学习、知识库和代码图组合建议，转换为当前 `skills-manager` 可执行且不会复制宿主控制面的规划合同。结果必须让后续 AI 能明确判断何时只读讨论、何时并行、谁能写哪些路径、如何集成、何时采用外部工具，以及何时退役 skill；同时保持 P5 maintenance hold、M1 collecting 0/10、zero runtime/host mutation 和 live acceptance not run。

## Baseline and gap decision

当前仓库已经拥有 capability inventory、portable cold catalog、host-owned semantic selection、deterministic policy、OperationPlan/freshness/atomic write/receipt/rollback、task manifest、planning verifier、worktree/Git 约定和 Lean Delivery pilot。缺口不是另一个 runtime，而是以下语义没有被 planning verifier 守住：

- read-only design panel 与 writable subagent 的 authority 不同。
- shared write set 必须单 writer；并行只允许 fixed base + disjoint paths + independent candidate + integration owner。
- lease 是 coordinator admission claim，不是文件锁。
- Git ref CAS/file hash 只拒绝 stale writer，不排队文件、不自动选 winner。
- 社区 workflow/context tool 必须有 disposition、native baseline、consumer、data/auth/write boundary、evaluation、maintenance cost 和 retirement trigger。
- M1 样本需要观察 coordination/tool/adapter/skill lifecycle，但不得增加第二个 registry 或强制使用工具。

因此 disposition 是：扩展既有 `maintenance_design` 为 M0.2；不创建 P6，不新增 schema major、`src/` module、scheduler、daemon、database、provider router、host/profile mutation 或社区安装。

## Official sources

| Source | Current fact used | Adoption decision |
| --- | --- | --- |
| [OpenAI Codex manual](https://developers.openai.com/codex/codex-manual.md)（2026-08-05 current helper snapshot） | `AGENTS.md` 保存 durable repo guidance；skill 是 progressive-disclosure workflow；plugin 是 installable bundle；MCP/connector 处理 external data/action；hooks/scripts/CI 处理 mechanical enforcement；Goal/Plan/subagents/worktrees 由宿主执行 | adopt native surface ownership；本仓只保留 advisory/planning/verifier seam |
| [OpenAI subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents) | exploration、tests、triage 可有界并行；共享写入需要隔离和主 Agent 集成 | adapt 为 read-only panel + disjoint worktree + one integration owner |
| [Git update-ref](https://git-scm.com/docs/git-update-ref) | ref 只在 current object 等于 expected old object 时条件更新 | adopt as ref freshness guard；reject file-lock/task-queue interpretation |
| [Git push --force-with-lease](https://git-scm.com/docs/git-push) | remote ref lease 保护 expected ref 状态 | adopt only as stale remote-ref guard；不作为 task lease 或 merge authority |

## Community source disposition

社区 README、代码、license 和 release/tag 只作不可信只读输入；未运行其安装脚本、hook、MCP、provider 或测试。

| Candidate / revision | License / observed shape | Disposition | Product landing / reason | Re-evaluation trigger |
| --- | --- | --- | --- | --- |
| [mindfold-ai/Trellis `v0.7.0-beta.1`](https://github.com/mindfold-ai/Trellis/tree/v0.7.0-beta.1) `1019808318a5573c5fc73c3e90bd19abefa7b6e4` | AGPL-3.0；repo spec/task/workspace journal；Plan/Implement/Verify/Finish 自动 skills/subagents | `adapt` ideas, `defer` install | 复用 spec/task/journal/verification 结构；本仓已有同类真源与宿主编排，安装会形成竞争控制面并引入 AGPL 分发审查 | 两个以上真实任务证明现有 task/spec/native host 无法满足，且 license/distribution 已审阅 |
| [zsr131550/agos](https://github.com/zsr131550/agos/tree/cc174d03f73bccb1f0a042daf4454ed89575616c) `cc174d03...` | MIT；0.1.0 Alpha；ledger、write_scope、candidate patch、review/merge gate、dashboard/hooks；README 明示全程 AI 制作且无人审核 | `adapt` protocol, `reject` runtime now | 采用 write scope/candidate/evidence/freshness vocabulary；不采用 scheduler/ledger service/dashboard/automatic reviewer | 独立多执行器/CI provenance 成为产品目标，人工代码/安全审计和 P6 admission 均完成 |
| [fujiwaranoM0kou/OptSkills](https://github.com/fujiwaranoM0kou/OptSkills/tree/7d3194098e17f8f032359d8ad507bbe6bfc208fa) `7d319409...` | MIT；数学优化 agent；trajectory cluster/learning/eval/checkpoint；provider/embedding、Python 3.12、solver/Gurobi | `adapt` learning method only | 采用 real sample/replay/shadow/canary/eval/serialized promotion；拒绝把领域研究系统解释为通用 workflow auto-upgrader | 本仓 skill candidate 有代表样本、negative case、provider-free replay 和 reviewed promotion 需求 |
| [garrytan/gbrain](https://github.com/garrytan/gbrain/tree/e5dee4fb78481f0fb7c78016fc7e450bef252caa) `e5dee4fb...`, release `v0.42.73.0` | MIT；database/daemon/MCP、ingestion、graph/synthesis、auth/scopes、many skills/tools | `defer` | 当前 repo docs/rg/connector 没有两个独立失败样本；数据、密钥、长期 daemon、索引和权限面过重 | 两个独立跨资料 retrieval failures + privacy/auth/backup/restore/resource evidence |
| [CodeGraphContext `v0.5.5`](https://github.com/CodeGraphContext/CodeGraphContext/tree/v0.5.5) `0aa7017b...` | MIT；CLI/MCP + graph database；23 languages；当前列表不含 PowerShell | `defer` | 可借鉴 read-only relationship/impact query；本仓主要语言未覆盖，不能成为默认 codegraph | PowerShell coverage、relation accuracy、fresh index、resource/rollback canary 全部成立 |
| [Egonex-AI/Understand-Anything `v2.9.0`](https://github.com/Egonex-AI/Understand-Anything/tree/v2.9.0)（current main `fe8c5bc5...`） | MIT；multi-agent whole-repo analysis、persistent graph/dashboard、incremental hook；README 明示首次运行 token 高 | `defer` | 可借鉴 guided onboarding/diff impact；当前没有大仓理解失败证据，且 token/hook/graph lifecycle 较重 | 两个真实 onboarding/impact failures + language/privacy/token/hook/index lifecycle evidence |
| “souljourney lightweight workflows” | GitHub 名称搜索不能唯一映射到相关工程 workflow；source/revision/license unknown | `defer` | fail-closed，不把口述名称写成采用来源 | 提供唯一公开仓库或可核来源与 license |

2026-08-05 收口时以 `git ls-remote` 复核上述 tag/HEAD：Trellis `1019808318a5...`、AGOS `cc174d03f73b...`、OptSkills `7d3194098e17...`、GBrain `e5dee4fb7848...`、CodeGraphContext `v0.5.5 -> 0aa7017b8c27...`、Understand Anything `v2.9.0 -> f08763d11d02...` / main `fe8c5bc59171...`；GitHub repository metadata 同步确认 Trellis 为 AGPL-3.0，其余五项为 MIT。该复核只证明来源身份，不构成安全、质量、兼容或安装验收。

## Adopted architecture contract

```text
goal / repo truth
  -> one host-owned coordinator
  -> optional 2-3 read-only design proposals
  -> one accepted decision + task DAG
  -> fixed base revision + exact write sets
  -> single agent, or disjoint worktree writers
  -> candidate commits/patches
  -> topology-ordered integration by one owner
  -> affected verification
  -> one full gate
  -> repo/host/live truth closeout
```

Hard boundaries:

- `SHARED_WRITE_SET_POLICY = single_writer`。
- lease = `owner + task + write_set + base + expiry/recovery + revoke/reassign` admission claim；no service。
- `GIT_CAS_SEMANTICS = ref_freshness_not_file_queue`。
- candidate/local test pass 不升级整体完成态；integration owner 负责冲突、全局门禁和 truth closeout。
- tool default = host-native + repo-native + Git + gates；external context adapter 需两个独立真实失败样本和完整 language/privacy/freshness/resource/supply-chain/uninstall evidence。
- tool learning = sample -> replay -> shadow -> canary -> reviewed promotion -> retain/revise/retire；no automatic promotion。

## Planning assets and write set

- `AGENTS.md`
- `docs/product/README.md`
- `docs/product/skills-manager-vnext-prd.md`
- `docs/product/skills-manager-vnext-architecture.md`
- `docs/product/skills-manager-vnext-roadmap.md`
- `docs/superpowers/specs/2026-08-03-lean-ai-delivery-maintenance-design.md`
- `tasks/skills-manager-vnext-maintenance-design.tasks.json`
- `tasks/skills-manager-vnext-lean-delivery-pilot.json`
- `tasks/plan.md`
- `tasks/todo.md`
- `scripts/verify-lean-ai-delivery-planning.ps1`
- `tests/Unit/LeanAiDeliveryPlanning.Tests.ps1`
- `skills.lock.json`（仅刷新当前 8 vendor / 44 import 的本地 HEAD parity）
- this evidence file

Forbidden write set remained `src/**`, `overrides/**`, `agent/**`, `vendor/**`, `reports/**`, `skills.json`, host config/profile/plugin/MCP/auth/session and any community checkout.

## Verifier changes

- Require exact `SMV-MD-001..008` task set.
- Require stable `evidence_group`; done tasks only need shared evidence within their logical group, preserving M0 evidence immutability while allowing M0.2 independent rollback.
- Require `CONTROL_PLANE_STATUS: not_introduced`、`SHARED_WRITE_SET_POLICY: single_writer`、`GIT_CAS_SEMANTICS: ref_freshness_not_file_queue`、`TOOL_DISPOSITION_POLICY: adopt_adapt_defer_reject`。
- Require M0.2 PRD/ADR/roadmap contracts and the explicit sentence `Git CAS is not a file lock or task queue`。
- Require M1 observation dimensions and validate future sample enums/dispositions.
- Continue to invoke the existing P5 verifier first and block P6/runtime/live truth drift.

## Verification evidence

| Order | Command / probe | Observed result |
| --- | --- | --- |
| 1 | `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 锁定` | exit 0；`vendors=8`、`imports=44`；只刷新时间戳及实际漂移的 Remotion/agent-browser/find-skills/mcp-cli/slidev commit，之后 manual import HEAD parity 通过 |
| 2 | `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` | exit 0；`Build success: D:\CODE\skills-manager\skills.ps1` |
| 3 | focused Pester: `ProductPlanning.Tests.ps1` + `LeanAiDeliveryPlanning.Tests.ps1` | `36 passed / 0 failed / 0 skipped` |
| 4 | `scripts/verify-vnext-planning.ps1` | exit 0；P5 `tasks=5, done=5, open=0` |
| 5 | `scripts/verify-lean-ai-delivery-planning.ps1` | exit 0；maintenance `tasks=8, done=8, open=0`；two evidence groups；M1 `collecting 0/10` |
| 6 | `scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` | final tracked-content run exit 0；802 unit + 18 E2E；build/repo-hygiene/generated-sync/107-skill integrity/routing/dependency/config/host/planning/doctor gates passed；`total_elapsed_ms=194183` |
| 7 | source/tag/license read-only recheck | all recorded revisions resolved；Trellis AGPL-3.0，AGOS/OptSkills/GBrain/CodeGraphContext/Understand Anything MIT；no install/script/hook/MCP/provider executed |
| 8 | post-gate parity | `git diff --check` clean；8 vendor / 44 import lock retained；manual import HEAD parity passed；tracked diff remained inside declared planning/evidence/lock write set |

第一次 full-gate 调用被外层 120 秒命令时限中断，但子进程继续自然结束且未被作为证据；随后以可回收退出码的长时限调用完整重跑，并在最终 tracked write set 同步后再次完整重跑。上表只记录最终一次的 exit 0 和汇总。

## Truth boundary and rollback

Maximum intended result is `repo_verified planning_contract` for M0.2. It does not prove coordinator/lease runtime, tool installation, multi-Agent speedup, knowledge/code-graph quality, skill auto-upgrade, host load, M1 execution, business benefit, P6 admission or `live_accepted`.

Rollback only the M0.2 write set and this evidence group. Preserve M0 historical evidence, P0-P5 artifacts, M1 real samples (currently none), all runtime/config/host state, user changes and community sources.
