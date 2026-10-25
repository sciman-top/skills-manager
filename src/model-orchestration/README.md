# Model Presets

Independent PowerShell 7 tooling for explicit subagent model presets. `presets.json` is the policy source; `Set-ModelPreset.ps1` resolves, plans, projects and rolls back; `Start-ModelSlot.ps1` is a separate bounded one-shot CLI launcher. This tool does not manage credentials, providers, gateways or host processes.

## Model pool and host boundaries

The 2026-10-25 user request restores four model families. Every model has one selected effort per host; the names are host catalog values, not a shared intelligence scale.

| Preset | Codex model ID | Codex effort | Other host policy |
| --- | --- | --- | --- |
| `gpt6_luna_only` | `gpt-6-luna` | `max` | Not projected to other hosts |
| `deepseek41_flash_only` | `deepseek-v4.1-flash` | `xhigh` | Requested `max` where the host exposes DeepSeek; no verified writer |
| `glm53_flash_only` | `glm-5.3-flash` | `xhigh` | ZCode `max`; WorkBuddy requested `max`, no verified writer |
| `gemini38_flash_only` | `gemini-3.8-flash-high` | `high` | Antigravity stays within its own model choices; no exact-effort writer |

Codex's Gemini slug includes `-high`; the bare family name is not an alias. DeepSeek/GLM `max` is rejected on Codex. ZCode accepts only its existing GLM/max facet. A requested host policy does not prove that host exposes the model, effort or a child-agent API. Do not project cross-vendor models into hosts restricted to their own family.

The executable enforces the closed per-host tuple allowlist. Adding arbitrary JSON entries cannot expand it. `-Preset` pins a preset; `-AvailablePreset` restricts the pool. `default_preset` selects a default parent preset; it does not require every child to use that model. `-SubagentsOnly` preserves parent and review selections.

## Nine execution slots

Slots describe responsibility, not a fixed agent count, concurrency quota or measured model ranking. `presets.json` owns the exact defaults and ordered alternate tuples; inspect `-Action Resolve` for current values.

| Slot | Task boundary | Access intent |
| --- | --- | --- |
| `quick_triage` | Concrete lookup, known error classification | Read only |
| `routine_maintenance` | Small fix with an understood cause | Bounded writes |
| `standard_review` | Review an existing bounded change | Read only |
| `bounded_implementation` | Specified change with explicit files and proof | Bounded writes |
| `deep_investigation` | Unresolved root cause across modules | Read only; return proposed write set |
| `deep_implementation` | Complex implementation after scope is established | Bounded writes |
| `test_execution` | Scoped test command and concrete failure diagnosis | Bounded writes when assigned |
| `documentation_review` | Documentation and contract consistency | Read only |
| `architecture_review` | Interacting constraints and security boundaries | Read only |

Keep the nine slots; there is no demonstrated need for more. Classify the task first, then select a supported tuple. Shared writes stay serial. Every delegation supplies scope, exact write set, minimum proof and stop. Read-only wording does not create a sandbox; child permissions follow the parent.

The route defaults are editable policy hypotheses. The earlier [108-call evaluation](https://github.com/sciman-top/skills-manager/pull/143) used three short questions per slot, one run per candidate, and grading adjusted after inspection; most candidates tied. It did not evaluate the restored DeepSeek tuple or long-horizon native child tasks. It cannot establish a universal ordering among these four models. Vendor descriptions also do not establish endpoint latency, tool reliability or project acceptance quality. Luna is positioned by OpenAI for focused, efficient subagent work; selecting max does not make it universally strongest. DeepSeek/GLM/Gemini task fit should be refined from ordinary accepted project outcomes, with identical scope and acceptance, rather than a new broad synthetic sweep. Higher effort may increase time and token use; `xhigh` and `max` are not proven equivalent across hosts.

## Native subagents and the Luna-only incident

Before this revision, all nine native slots and the shared default were projected to Luna; GLM/Gemini were launcher-only and DeepSeek was removed. Selecting a fixed semantic role therefore kept using Luna regardless of the launcher `auto_routes`. A model in the Desktop picker did not alter these files.

All four exact tuples remain available to the controlled launcher after target catalog preflight. Native roles expose Luna and DeepSeek; GLM/Gemini remain launcher-only because the deployed gateway rejects their encrypted agent tasks. Native slot selection uses the eligible pool rather than forcing every slot to Luna. Both model and effort must be pinned. An exact custom agent file can override spawn parameters; inspect the effective role rather than assuming an explicit model argument wins. Unpinned bridges may inherit the selected defaults.

Compatibility remains a separate boundary: on 2026-10-25, both the gateway repository source and the checked BWG deployment `D:/CODE/vps-ssh-launcher/scripts/remote/cpa-admission.py` still rejects nonempty `agent_message.encrypted_content` for GLM/Gemini with `422 encrypted_agent_payload_unsupported` and `upstream_contacted=false`. DeepSeek is not covered by that predicate. BWG runs CPA v8.0.42; strict doctor passed and the deployed predicate returned true for encrypted GLM/Gemini, false for DeepSeek/Luna. This is deployed code and predicate evidence, not a model generation request. The host catalog and user Desktop availability evidence support the requested pool; neither proves successful encrypted native delegation. If that error occurs, stop for compatibility diagnosis. Do not replay the task, remove the guard or silently substitute models. One-shot CLI execution sends a different request shape and is not native subagent acceptance.

Fresh host loading is required after projection. An existing chat may retain its old role definitions. Do not restart or stop the app to force loading. Local Codex files do not configure hosted ChatGPT Work.

## Failure handling

Preset fallbacks are candidate data, not an automatic failover engine. The launcher starts one `codex exec` process and never automatically retries, replays or launches an alternate. `max_explicit_reselections=1` is a parent-managed budget; `-ReselectionCount 1` blocks another controlled launch for that bounded task. The parent records failure, inspected partial work, selected supported tuple and remaining scope.

| Failure | Action |
| --- | --- |
| Unsupported tuple, encrypted payload or incompatible tools | Stop and diagnose capability; do not treat as overload |
| Confirmed overload/unavailable | At most one explicit parent reselection for reviewed remaining scope |
| 429/quota | Honor Retry-After/reset; no model switching to evade limits |
| Auth/permission/account risk | Stop for operator review |
| Timeout or unknown error | Inspect existing process result and partial writes before new dispatch |

There is no proven cross-vendor automatic failover contract for ordinary Desktop, ZCode, Antigravity or WorkBuddy in this tool. Native hosts own their retry behavior. A pinned child does not automatically consult JSON fallbacks. A different model may share the same quota or gateway.

## Projection, proof and rollback

```powershell
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Resolve
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Plan -SubagentsOnly
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Apply -SubagentsOnly
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Verify
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Rollback -ReceiptPath <receipt.json>
pwsh -NoProfile -File ./Test-ModelPreset.ps1
```

Plan before Apply. Generated role files live in ignored `.generated/`; ignored `.state/` stores backups and receipts. Preserve unrelated configuration, concurrency, hooks, auth and provider fields. Ownership markers prevent adopting user-owned files. Rollback checks current hashes; restore later dependent mutations first. Backups may contain sensitive pre-existing host data and must not be published.

ZCode supports Plan/Apply with `-SubagentsOnly -ExecutionHost zcode`, using the exact selector in its existing `~/.zcode/agents/glm-max.md`. It creates only marked namespaced slot definitions at max and leaves the source definition intact. Antigravity/WorkBuddy have no verified exact-tuple writer. Claude has no active facet after the prior user retirement decision and fails closed.

Resolve is offline policy evidence. Plan/Apply use `codex debug models` for the target `CODEX_HOME` with a 30-second deadline. Bound catalog snapshots require `source`, absolute `codex_root`, and a current validity window of at most five minutes. Catalog evidence proves tuple visibility, not generation success. Verify inspects effective configuration; repository tests use disposable host roots.

## Controlled launcher

```powershell
pwsh -NoProfile -File ./Start-ModelSlot.ps1 -Slot bounded_implementation -Model deepseek-v4.1-flash -Effort xhigh -Plan
pwsh -NoProfile -File ./Start-ModelSlot.ps1 -Slot standard_review -Model gemini-3.8-flash-high -Effort high -Plan
```

Real execution requires a declared custom provider and exact tuple capability. Native mode checks the catalog. `provider_override` requires a current unexpired receipt binding exact model/effort, provider ID, surface, timestamps and source; the provider must match the effective profile/base configuration. Static historical matrix entries are insufficient. Per-invocation request and stream retry caps are zero; those do not control relay retries or internal model requests.

The launcher disables nested delegation and accepts explicit scope through `-Prompt`, with `-WorkingDirectory` and optional `-ReadOnly`. A strict one-shot child cannot fulfill an interactive design-griller or cold-runner lifecycle. Default execution timeout is 900 seconds (1-3600); probe timeout is 30 seconds (1-120). A timeout attempts to terminate only the launched process tree, without proving upstream cancellation or rollback. Failure classification uses structured JSON fields with precedence risk > auth > rate limit > tool/environment > overload; free text alone remains unknown.

Repository proof uses `Test-ModelPreset.ps1` (also wrapped by `tests/Unit/ModelPreset.Tests.ps1`); this independent tool is outside the main CLI build. `repo_verified -> filesystem_projected -> host_loaded -> live_accepted` remain separate claims. Stop once the requested boundary is proven.

Official OpenAI documentation checked 2026-10-25: [subagents and custom-model precedence](https://learn.chatgpt.com/docs/agent-configuration/subagents). Current [Gemini Flash documentation](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash) positions it for long-horizon software engineering; [DeepSeek's release](https://www.deepseek.com/en/news/deepseek-v4-1-flash/) confirms WorkBuddy integration. WorkBuddy's host catalog can therefore include partner models; own-host availability is not the same as vendor-only manufacture. A [community Codex report](https://github.com/openai/codex/issues/37237) documents encrypted-task loss on custom providers, but is historical supporting evidence, not proof for every current client. Other hosts' exact lifecycle and failure behavior require current host evidence.
