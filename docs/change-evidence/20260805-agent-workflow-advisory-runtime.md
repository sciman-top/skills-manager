# Agent workflow advisory runtime evidence

**track**: `agent_workflow_advisory_runtime`
**verification_level**: `repo_verified`
**truth_boundary**: `repo_advisory_only`
**Maximum claim: `repo_verified / repo_advisory_only`**

## Goal and disposition

用户要求把长链路 Agent 的目标澄清、任务拆分、串并行调度、Sol xhigh/Sol medium/Luna max 选择、Radar 成本/时间参考和失败升档变成可执行方案与代码。复核本仓定位、Codex 官方 subagent/worktree/model surface 和既有 M0.3 规划后，采纳的最小切片是 `TaskGraph + RadarSnapshot + FailurePacket + deterministic advisory CLI`。它复用宿主原生执行面，只补合同和门禁；不创建第二 scheduler、daemon、database、provider gateway 或模型路由器。

## Source and implementation write set

- Domain: `src/Domain/AgentWorkflow.ps1`
- Application: `src/Application/ModelAndAgentPolicy.ps1`
- Command/build: `src/Commands/AgentWorkflow.ps1`, `src/Main.ps1`, `src/Version.ps1`, `build.ps1`
- Fixtures/tests: `tests/fixtures/agent-workflow/*.json`, `tests/Unit/AgentWorkflowContracts.Tests.ps1`
- Verifier/full gate: `scripts/verify-agent-workflow-advisory.ps1`, `tests/Unit/AgentWorkflowAdvisoryPlanning.Tests.ps1`, `scripts/quality/run-local-quality-gates.ps1`
- Planning/product: `docs/superpowers/specs/2026-08-05-agent-workflow-advisory-runtime.md`, `tasks/skills-manager-vnext-agent-workflow-advisory.tasks.json`, PRD/architecture/roadmap/index/plan/todo/AGENTS/README mirrors

Generated `skills.ps1` is rebuilt from `src/`; `agent/`, vendor/import caches, reports and host-local state are not hand-edited or promoted by this track.

## Contract facts

- `TaskGraph` validates required goal/input/output/dependency/risk/ambiguity/parallelizable/write-set/external-state/verification/owner/order/stop fields, unknown dependencies, self references, duplicate IDs/orders and cycles.
- `Test-AgentParallelAdmission` requires completed dependencies, fixed base, exact disjoint write sets, non-conflicting coordination/external state, verification and result owners. Shared seams and integration remain serial.
- `New-AgentExecutionPlan` emits deterministic dependency waves and groups `implement + document` as isolated parallel work only when the fixture proves disjoint paths.
- `RadarSnapshot` validates HTTP(S) source, ISO timestamps, SHA-256 hash, expiry and non-negative score/cost/duration/sample metrics. Stale snapshots cannot drive a proposal.
- `New-ModelPolicyProposal` emits three host-owned soft anchors and uses local outcomes before Radar before host default; unavailable/stale data returns `host_default` with reason.
- `FailurePacket` is required before retry/escalation; permission, credential, production authorization and user decision failures fail closed; capacity-only escalation is bounded.
- `agent-validate` and `agent-plan` are read-only, repo-contained, provider-free and native-mutation-free. Every JSON envelope declares `decision_owner=host_ai`, `executor=host_native_runtime`, and zero effect counters.

## Fresh verification receipts

The following receipts were run after implementation changes; future changes invalidate them and require rerun:

| Gate | Command | Result |
| --- | --- | --- |
| focused contract | `Import-Module Pester -RequiredVersion 4.10.1; Invoke-Pester tests/Unit/AgentWorkflowContracts.Tests.ps1` | 12/12 pass |
| build | `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` | exit 0 |
| CLI validate | `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 agent-validate --input tests/fixtures/agent-workflow/valid-request.json --json` | exit 0; provider/native/write counters 0 |
| CLI plan | `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 agent-plan --input tests/fixtures/agent-workflow/valid-request.json --json` | exit 0; waves `discover -> implement+document -> integrate` |
| advisory verifier | `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-agent-workflow-advisory.ps1 -Json` | rerun at closeout; must be 0 findings |
| full gate | `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` | final closeout only; must be exit 0 |

The first implementation test run was intentionally RED (`12 failed` because the functions did not exist); the focused run after implementation was GREEN (`12/12`).

## Truth and rollback boundary

This evidence does not prove subagents were spawned, a model was called, Radar was refreshed, a host profile/config was loaded, or any external/production workflow was accepted. `repo_verified` is the maximum current claim until a separately authorized fresh-host and live workflow produces evidence. Rollback removes only this track's files and wiring, rebuilds the bundle, and reruns the PS7-only/full gates; it does not touch `~/.codex`, provider/auth/session, M0/M0.2/M0.3 historical evidence, M1 samples or user work.

## Official basis

- [Codex subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [Codex models](https://learn.chatgpt.com/docs/models)
- [Codex long-running work](https://learn.chatgpt.com/docs/long-running-work)
- [Codex Radar](https://codexradar.com/) as an untrusted, expiring community observation only
