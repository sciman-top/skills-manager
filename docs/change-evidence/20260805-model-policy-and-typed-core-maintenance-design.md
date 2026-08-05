# Host-owned model policy and typed-core maintenance design evidence

**program_id**: `skills-manager-vnext`
**track**: `maintenance_design`
**milestone**: `M0.3`
**evidence_group**: `model_policy_typed_core_m0_3`
**status**: `repo_verified`
**date**: 2026-08-05
**base_revision**: `b4dda7b8`
**truth_ceiling**: `repo_verified planning_contract`

## Goal

把用户提出的动态模型选择、长链路主 Agent、子任务串并行、失败升档和 Codex Radar 参考转换为 host-owned advisory contract；同时处理 AI 在 Windows PowerShell 中频繁出现 parser/quoting/动态类型/encoding/native-process/5.1-7 兼容返工的问题，给出可执行但不直接重写的技术路线。

本切片只允许更新 PRD、架构、路线图、maintenance spec/manifest、plan/todo、runbook、README/AGENTS、planning verifier/tests 和本 evidence。禁止 `src/**`、`overrides/**`、`skills.json`、生成/缓存/report、`.codex`/host config、provider/auth/session、Radar live fetch、subagent/model runtime 和 typed-core project。

## Current repository evidence

| Probe | Result | Meaning |
| --- | --- | --- |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` | exit 0, generated `skills.ps1` | 当前 PS7 build path 可用 |
| `powershell.exe ... [scriptblock]::Create(skills.ps1)` | `parse-ok`, exit 0 | 当前 generated bundle 在 5.1 可解析；不证明完整 workflow |
| focused `PowerShellCompatibility.Tests.ps1` | 6/6 pass | PS7 primary、5.1 bounded smoke、installer/CI/encoding contract 当前成立 |
| 误用 `tests/run.ps1 -TestFiles ...` | unknown parameter, exit 1 | 根因是 AI 未先读取脚本参数而猜测接口，不是 PowerShell parser；说明动态脚本入口需要可发现 contract，不能把所有失败归咎于语言 |
| `dotnet --list-sdks` | `8.0.423`, `10.0.300`, `10.0.302` | 本机可做 .NET PoC 可行性评估；不构成仓库依赖、SDK pin 或实现完成 |
| `node --version`, `python --version` | Node `24.12.0`, Python `3.11.9` | 只证明本机存在；不证明它们是本仓更优核心 |

当前结论：PowerShell 不是“完全不可用”，现有门禁也能守住已知兼容面；但 dynamic contract、AI edit feedback、quoting/encoding/native process 和双 runtime 语义确实让复杂领域逻辑的长期维护成本偏高。最优处置不是立即重写，而是让当前 PowerShell 保持单一运行真源，先稳定 protocol，再用一个 read-only C#/.NET typed-core PoC 量化净收益。

## Official sources and adoption

| Source | Current fact used | Disposition |
| --- | --- | --- |
| [OpenAI Codex Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents) | 主 Agent负责需求/决策/最终输出；探索、测试、日志分析可有界分派；写密集工作需谨慎 | adopt host-owned coordinator and bounded parallelism |
| [OpenAI Codex Models](https://learn.chatgpt.com/docs/models) | 模型与 reasoning effort 是宿主可用能力，选择应按任务复杂度与成本 | adapt as soft tier anchors, never deterministic runtime routing |
| [OpenAI Configuration Reference](https://learn.chatgpt.com/docs/config-file/config-reference) | custom agents/default subagent model/effort 由宿主配置面拥有，显式 spawn 可覆盖默认值 | keep config proposal-only; reject silent active-session mutation |
| [OpenAI Codex + Agents SDK](https://learn.chatgpt.com/docs/mcp-server) | project manager 可生成 requirements/test/tasks 后 gated handoff 给专门 agents，并保留 trace | adapt TaskGraph/FailurePacket and gated handoff; reject second runtime |
| [Microsoft PowerShell differences](https://learn.microsoft.com/powershell/scripting/whats-new/differences-from-windows-powershell) | PowerShell 7 与 Windows PowerShell 5.1 存在明确行为/模块差异 | adopt PS7 primary + bounded 5.1 smoke |
| [Microsoft .NET deployment](https://learn.microsoft.com/dotnet/core/deploying/) | framework-dependent/self-contained 等发布方式有不同 runtime/体积/更新权衡 | require PoC measurements before choosing distribution |
| [Microsoft .NET single-file deployment](https://learn.microsoft.com/dotnet/core/deploying/single-file/overview) | typed CLI 可单文件发布但仍有平台/体积/兼容权衡 | evaluate, do not assume single-file is automatically best |

Official documentation does not validate Codex Radar as a production-quality oracle. Radar is treated as an external, time-varying advisory source with `captured_at`, `expires_at`, sample/confidence and raw hash. It may influence a proposal only; local comparable task outcomes and current host availability take precedence.

## Community sources and best-practice adaptation

| Source | Adopt/adapt | Rejected boundary |
| --- | --- | --- |
| [obra/superpowers parallel agents](https://github.com/obra/superpowers/tree/main/skills/dispatching-parallel-agents) | parallelize independent problem domains; provide self-contained briefs; integrate after focused review | parallel shared state/write set; absolute one-size-fits-all rules |
| [obra/superpowers subagent-driven development](https://github.com/obra/superpowers/tree/main/skills/subagent-driven-development) | use the lowest model that can reliably finish; change conditions or escalate when stuck; task review then final review | repeated same prompt, child scope expansion, child declaring global completion |
| [OpenAI Cookbook Codex multi-agent example](https://github.com/openai/openai-cookbook/blob/main/examples/codex/codex_mcp_agents_sdk/building_consistent_workflows_codex_cli_agents_sdk.ipynb) | requirements/test/tasks artifacts, gated handoffs, traceable integration | copying the example as a mandatory runtime or fixed role team |

## Adopted model and task policy

```text
user intent/authority
  -> host AI: TaskGraph + serial/parallel + model/effort + spawn/wait/steer
  -> skills-manager: candidate/Radar/cost/risk/admission/escalation advice
  -> Codex native runtime: execute agents
  -> integration owner: topology-ordered merge + affected gates
  -> one full gate
  -> repo/host/live truth closeout
```

- `Sol xhigh`: load-bearing clarification, architecture/refactor, production RCA, high-risk review, final adjudication.
- `Sol medium`: general implementation, normal debugging/review, integration preparation.
- `Luna max`: clear, bounded, repeatable CRUD/SQL/unit-test/docs/mechanical work.
- The three tiers are overrideable anchors. Unknown/unavailable/stale data falls back to current host official/default behavior.
- Parallel work requires satisfied dependencies, fixed base, read-only or disjoint exact write sets, declared external state, independent verification/discard, and integration owner/order.
- Shared files/config/lock/source-generated seam/schema/migration/Git refs/external object, content-dependent tasks, final integration, full gate and closeout are serial.
- Failure flow: root-cause diagnosis -> one corrected retry -> re-scope/context repair -> capacity-only tier escalation -> second same issue clarify/re-plan -> two escalations or load-bearing risk supervisor serial takeover.
- Missing tool/auth/permission/production/user decision is fail-closed, not a model-capacity escalation.

## Technology decision

| Option | Decision | Reason |
| --- | --- | --- |
| Continue adding all logic to PowerShell | reject as long-term default | lowest migration cost but preserves the observed AI-edit and dynamic-contract risk |
| C#/.NET typed core + PowerShell thin shell | `AI 推荐`, conditional PoC | strongest Windows/native CLI fit, compile-time types, structured concurrency/testing, flexible distribution, current host SDK availability |
| C#/.NET full rewrite | reject | large compatibility/regression blast radius and loss of existing CLI/Pester evidence |
| TypeScript/Node core | defer | adds Node/npm/runtime and packaging surface without a current UI/plugin requirement |
| Python core | defer | useful for data/eval helpers but adds interpreter/venv/packaging and Windows path/encoding surface |
| Rust core | defer | excellent safety/single-binary potential, but current migration/team/FFI cost is not justified by performance evidence |

Migration remains `TC0 baseline -> TC1 shadow PoC -> TC2 one-seam strangler migration -> TC3 retain/revise/retire`. No stage after TC0 is admitted by this evidence. Production must never have two authoritative implementations or configs.

## Planning assets and rollback

The M0.3 manifest contains `SMV-MD-009..011`, all sharing this evidence group. Rollback only M0.3 additions in the declared planning/verifier/test/index/root/README/runbook files and this evidence. Preserve M0/M0.2 evidence, P0-P5 truth, M1 samples, all current PowerShell runtime/source/generated artifacts, host config, and external sources.

## Verification evidence

| Order | Command / probe | Observed result |
| --- | --- | --- |
| 1 | `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` | exit 0；generated `skills.ps1` success |
| 2 | focused Pester: `ProductPlanning.Tests.ps1` + `LeanAiDeliveryPlanning.Tests.ps1` + `PowerShellCompatibility.Tests.ps1` | 44 passed / 0 failed / 0 skipped；nested `pwsh -Command` 首次因外层 `$` 展开失败，改用单引号脚本块后通过；该失败证明 quoting 风险，不计为测试失败 |
| 3 | `scripts/verify-vnext-planning.ps1 -Json` | exit 0；P5 tasks 5/5；0 findings |
| 4 | `scripts/verify-lean-ai-delivery-planning.ps1 -Json` | exit 0；M0/M0.2/M0.3 tasks 11/11；3 evidence groups；model policy advisory、Radar expiring、typed core `poc_not_started`、M1 0/10、0 findings |
| 5 | `scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` | exit 0；817 unit + 18 E2E = 835 Pester tests；build/repo-hygiene/generated-sync/107-skill integrity/routing/dependency/config/host/planning/doctor contracts passed；`total_elapsed_ms=209972` |
| 6 | post-gate `git diff --check` / manifest parse / PowerShell 5.1 generated-script parse / tracked write-set review | exit 0；manifest JSON parsed；`parse-ok`；no whitespace error；all tracked changes remain inside the declared M0.3 planning/verifier/test/index/root/README/runbook/evidence write set |

The full gate ran exactly once after functional planning files stabilized. This evidence row was finalized afterward without changing code, manifest semantics, verifier behavior or runtime state; the companion planning verifier and diff checks are rerun below as the focused alternative verification for this record-only edit.

## Truth boundary

Maximum claim: `M0.3 repo_verified planning_contract`. It does not prove runtime model routing, Radar accuracy/cost benefit, custom-agent config changes, subagent orchestration benefit, typed-core PoC/implementation, PowerShell replacement, M1 execution, P6 admission, host load, or business `live_accepted`.
