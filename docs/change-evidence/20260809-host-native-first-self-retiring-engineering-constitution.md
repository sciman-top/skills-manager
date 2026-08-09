# Host-native-first self-retiring engineering constitution

**status**: `repo_contract_candidate`
**base_revision**: `53866ae831495187c02fb365a11832dbd4065854`
**candidate_revision_authority**: `Git HEAD after this logical slice is committed`
**full_gate_authority**: `reports/quality-gates/current.json`
**scope**: `repository_standard_path_only`
**truth_boundary**: `repo_contract_enforced_after_exact-current-source-full-receipt`

## Outcome

本切片把以下原则固化为 PRD 唯一规范性正文，并通过现有 planning/advisory verifier 和 TaskGraph 合同承接机械约束：

1. `host-native-first`：宿主 AI 是唯一语义 coordinator，本仓只补经证据确认的真实缺口。
2. `main-chain-first`：先跑通用户、真实入口、关键 seam、可运行终态、直接证据与回滚构成的最短主链。
3. `anti-overdesign`：没有真实重复、稳定协议、已证实风险或量化热点，不新增长期抽象、治理或优化层。
4. `self-retiring`：宿主覆盖、功能重叠、消费者消失或维护成本超过净收益时，能力进入有证据的弱化/兼容/退役处置；缺少遥测本身不能证明没有消费者。
5. `no-second-governance-plane`：不创建第二语义 owner、runtime、scheduler、registry、daemon、database、ledger 或 telemetry service。

保护优先级保持为：

```text
user authority / safety / data integrity / compatibility / truth boundary
  > verified user outcome
  > host-native-first / main-chain-first / anti-overdesign / self-retiring
  > breadth / future flexibility / speculative optimization
```

## Major workflows

主要软件工程与 AI 编码工作流复用现有产品合同，不建立第二套流程引擎：

```text
Discovery
  -> Main-chain
  -> Stabilize observed failures
  -> Refactor characterized behavior
  -> Release exact-current-source candidate
  -> Operate / Observe
  -> new Discovery input or evidence-backed retirement
```

- `Discovery`：确认用户、问题、真实入口、native baseline、复用决定、风险、write set、checkpoint 和停止条件。
- `Main-chain`：交付最薄真实路径，禁止以文件/测试/schema 数量代替用户结果。
- `Stabilize`：只修已观察失败、已证实边界和根因，不扩展猜测式容错矩阵。
- `Refactor`：只在主链通过且重复、协议、风险或热点已有证据时改善结构。
- `Release`：candidate commit 后运行唯一 full gate，以 exact-current-source receipt 判定 repo closeout。
- `Operate / Observe`：保持 repo、host invocation、live acceptance 和 operational stability 分层；真实反馈进入下一次 Discovery 或 retirement review。
- `Direct fix`：继续使用轻量路径，不要求 native baseline、复杂度 admission、完整 spec 或生命周期 artifact。

## Contract changes

- PRD 增加 `PP-000 Host-native-first main-chain-first self-retiring`；`AGENTS.md` 只保留一条项目动作映射。
- `verify-vnext-planning.ps1` 阻断 PP-000 或项目映射漂移，不新增 verifier。
- `TaskGraph v2` 在既有任务合同上增加 `delivery_stage / admission_scope / user_outcome / entrypoint / main_chain_checkpoint / reuse_decision`。
- 既有 `verification[]` 直接承接 minimum-sufficient verification，未创建同义字段。
- `ai_capability / governance / long_lived_surface` 要求 native baseline；`long_lived_surface` 进一步要求真实消费者、允许的复杂度依据、维护成本和 retirement trigger。
- stage 依赖只能向前；`stabilize/refactor/release` 需要 main-chain ancestor，`operate` 需要 release ancestor，但没有真实失败时不强制机械经过 stabilize/refactor。
- TaskGraph v1 仍可显式 compatibility validation，但不能证明 v2 delivery admission 已通过。
- advisory wave 只投影已验证的 `task_id / delivery_stage / main_chain_checkpoint`；task selection、wave ordering 和 effect counters 不变。

## TDD evidence

| Slice | RED | GREEN |
|---|---|---|
| PP-000 planning mapping | 18 passed / 2 expected failed：missing constitution findings 尚不存在 | 20 passed / 0 failed |
| TaskGraph v2 admission | 24 passed / 12 expected failed：v2/schema/admission/stage 尚未实现 | 36 passed / 0 failed |
| advisory projection/verifier | 44 passed / 2 expected failed：projection 与 drift findings 尚不存在 | 46 passed / 0 failed |

最终 affected 验证：

```text
build.ps1: exit 0, generated skills.ps1
ProductPlanning.Tests.ps1 + AgentWorkflowContracts.Tests.ps1 + AgentWorkflowAdvisoryPlanning.Tests.ps1: 66 passed / 0 failed
verify-vnext-planning.ps1 -Json: pass=true, finding_count=0
verify-agent-workflow-advisory.ps1 -Json: status=pass, findings=[], provider_calls=0, native_mutations=0, writes=0
```

## Truth boundary

- `repo_contract_enforced` 只有在本切片 candidate commit 对应的 exact-current-source full receipt 通过后成立。
- `host_loaded`：`not_changed`；未修改或热加载宿主配置。
- `host_invocation_observed`：`not_observed`；fixture、Pester、CLI verifier 不构成 native execution 观察。
- `live_accepted`：`not_accepted`；未执行真实业务 workflow。
- `operationally_stable`：`not_claimed`；需要后续真实 pilot/运行证据。
- M1 仍为 `collecting (0/10)`；本切片及其 synthetic fixture 不计入真实样本。

## Exclusions

- 未修改 P6、AWA 或 maintenance 历史 manifest 状态。
- 未修改 provider、auth、model、session、permissions、active profile、plugin/MCP 或 host runtime。
- 未修改 GitHub branch protection、required checks 或远端管理策略。
- 未创建 P7、第二 task registry、scheduler、telemetry 或新 quality-gate step。

## Rollback

按反向 commit 顺序只撤销本逻辑切片：

1. 撤销 advisory projection、verifier markers、当前文档、generated bundle 和本 evidence。
2. 撤销 TaskGraph v2 admission；TaskGraph v1 compatibility 恢复为唯一合同。
3. 撤销 PP-000、AGENTS mapping 与 planning verifier findings。

回滚不得覆盖其他任务改动，不删除历史 spec/evidence，不修改宿主或远端策略。
