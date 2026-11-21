# Model Presets

Independent PowerShell 7 tooling for explicit subagent model presets. `presets.json` is the policy source; `Set-ModelPreset.ps1` resolves, plans, projects and rolls back; `Start-ModelSlot.ps1` is a separate bounded one-shot CLI launcher. This tool does not manage credentials, providers, gateways or host processes.

## Model pool and host boundaries

The Codex pool contains the three tuples selected for this orchestration policy. Effort names belong to each host/model catalog; they are not a shared intelligence scale. `max` is a setting within one model, not a claim that it is stronger than another model or effort.

| Preset | Codex model ID | Codex effort | Other verified facet in this repository |
| --- | --- | --- | --- |
| `gpt6_luna_only` | `gpt-6-luna` | `max` | None |
| `glm53_flash_only` | `glm-5.3-flash` | `xhigh` | ZCode `max` |
| `gemini38_flash_only` | `gemini-3.8-flash-high` | `high` | None |

These are capability boundaries of this repository's writers, not a complete
list of models that each product can call. As of 2026-11-21, official
documentation describes third-party or custom model connections in ZCode,
WorkBuddy CN/Enterprise, WorkBuddy AI international, and DeepSeek Harness.
Antigravity also lists selected partner-provider models, such as Claude and
GPT-OSS, with availability depending on plan and client; that is not an
arbitrary custom-provider API. DeepSeek also lists WorkBuddy (including
CodeBuddy) as an official V4.1-Flash partner. Therefore, “this host only uses
its maker's models” is not a reliable general rule. Availability still depends
on the specific product surface, version, account, plan, region, provider
configuration, and child-agent API.

This repository's executable allowlist is narrower: Codex supports the three
selected tuples after target-catalog preflight; the ZCode writer supports only
its reviewed GLM/max facet. DeepSeek V4.1-Flash is intentionally excluded from
this preset pool and its routes, even if a host separately offers it. There is no verified model-preset writer or
subagent adapter here for WorkBuddy CN/INTL, DeepSeek Harness, or Antigravity.
The tool accepts those host names to fail closed with a capability message; it
does not write their host configuration or treat another host's model list as
a proven local adapter. A DSH rules receipt is not model or subagent acceptance.

The Codex slug `gemini-3.8-flash-high` is the exact local catalog name; the bare
family name is not an alias. Codex GLM remains `xhigh`, while ZCode's GLM facet
is `max`. These are host-specific settings. OpenAI positions Luna for frequent,
bounded tasks and gives low effort as an example for small edits; this policy
keeps the selected `max` tuple, so it does not optimize effort cost or latency.
Google positions Gemini 3.8 Flash for long-horizon software engineering and
agent workflows. Those descriptions motivate task-fit hypotheses, not a
cross-vendor strength ranking or proof of local acceptance quality.

The executable enforces the closed per-host tuple allowlist. Adding arbitrary JSON entries cannot expand it. `-Preset` pins a preset; `-AvailablePreset` restricts the pool. `default_preset` selects a default parent preset; it does not require every child to use that model. `-SubagentsOnly` preserves parent and review selections.

## Nine execution slots

Slots describe responsibility, not a fixed agent count, concurrency quota or measured model ranking. `presets.json` owns the exact defaults and ordered alternate tuples; inspect `-Action Resolve` for current values.

| Slot | Task boundary | Access intent | Codex route |
| --- | --- | --- | --- |
| `quick_triage` | Concrete lookup, known error classification | Read only | `gpt-6-luna/max` |
| `routine_maintenance` | Small fix with an understood cause | Bounded writes | `glm-5.3-flash/xhigh` |
| `standard_review` | Review an existing bounded change | Read only | `gemini-3.8-flash-high/high` |
| `bounded_implementation` | Specified change with explicit files and proof | Bounded writes | `glm-5.3-flash/xhigh` |
| `deep_investigation` | Unresolved root cause across modules | Read only; return proposed write set | `gemini-3.8-flash-high/high` |
| `deep_implementation` | Complex implementation after scope is established | Bounded writes | `gemini-3.8-flash-high/high` |
| `test_execution` | Scoped test command and concrete failure diagnosis | Bounded writes when assigned | `glm-5.3-flash/xhigh` |
| `documentation_review` | Documentation and contract consistency | Read only | `gpt-6-luna/max` |
| `architecture_review` | Interacting constraints and security boundaries | Read only | `gemini-3.8-flash-high/high` |

Keep the nine slots; there is no demonstrated need for more. The defaults are task-fit hypotheses, not a universal ranking. Luna is routed to short, bounded read-only work; GLM to routine fixes, bounded implementation and test diagnosis; Gemini to broad review, cross-module investigation and complex implementation. Vendor benchmarks and model descriptions do not prove these routes win on this repository.

`bounded_implementation` and `deep_implementation` use different default models because their scope differs: GLM handles a specified change with known boundaries; Gemini handles complex implementation after investigation has established the scope. A supported alternative can be selected explicitly when the task's actual needs differ. For a known test command, the parent can run it directly. Use `test_execution` when a scoped verification task can run independently. Shared writes stay serial. Every delegation supplies scope, exact write set, minimum proof and stop. Read-only wording does not create a sandbox; child permissions follow the parent.

## Routing receipt

`presets.json.routing_receipt` is the v1 contract for explaining which route was chosen. A receipt records the requested slot, preset, model, effort, read-only state and fallback candidates. It separately records the host-reported actual model and effort, with `actual_model_observed=false` when the client does not expose them. Do not infer the child tuple from the parent model pill or the Desktop picker.

The effective child selection follows this order: a custom agent file's model/effort, then an explicit spawn value, then the `[agents]` default, then parent inheritance. A custom agent file also inherits the parent provider; it cannot switch to another provider. `Start-ModelSlot.ps1 -Plan` emits the requested portion of this receipt and leaves the observed fields unset.

The route defaults are editable policy hypotheses. The earlier [108-call evaluation](https://github.com/sciman-top/skills-manager/pull/143) used three short questions per slot, one run per candidate, and grading adjusted after inspection; most candidates tied. It did not establish which of the three current tuples performs best on long-horizon native child tasks. Vendor descriptions also do not establish endpoint latency, tool reliability or project acceptance quality. OpenAI's small-edit example uses low effort; this repository keeps Luna at `max`, so that route does not optimize effort cost. Refine routes only from ordinary accepted project outcomes with comparable scope and acceptance, not a broad synthetic sweep. Higher effort may increase time and token use; `xhigh` and `max` are not proven equivalent across hosts.

## Native subagents and the Luna-only incident

Before this revision, all nine native slots and the shared default were projected to Luna; GLM/Gemini were launcher-only. Selecting a fixed semantic role therefore kept using Luna regardless of the launcher `auto_routes`. A model in the Desktop picker did not alter these files.

All three exact tuples remain available to the controlled launcher after target catalog preflight and to native roles after the 2026-10-25 BWG admission deployment. That deployment maps only the exact known Codex task envelope to standard Responses user text before forwarding; unknown envelope shapes remain rejected. Native slot selection now follows the eligible pool rather than forcing every slot to Luna. Both model and effort must be pinned. An exact custom agent file can override spawn parameters; inspect the effective role rather than assuming an explicit model argument wins. Unpinned bridges may inherit the selected defaults.

Compatibility remains a separate boundary. BWG runs CPA v8.0.42 and the deployed admission code has strict-doctor and pin evidence for the exact-envelope conversion. This is deployment evidence, not a model generation request. The host catalog and user Desktop availability evidence support the requested pool; neither proves that every provider accepts a native delegation or completes it successfully. If `encrypted_agent_payload_unsupported` occurs, stop for compatibility diagnosis. Do not replay the task, remove the guard or silently substitute models. One-shot CLI execution sends a different request shape and is not native subagent acceptance.

### Codex native compatibility observation (2026-11-20)

One local Desktop-bundled Codex CLI build (`0.171.0-alpha.13`) completed one native `standard_review` delegation through a `gpt-5.6-luna` parent using V1. A separate V2 session failed to deliver readable task content and an ephemeral child failed initialization. This is one historical build-specific observation, not a current routing or model-support guarantee; inspect the active model catalog and child output for each new acceptance check.

`Start-ModelSlot.ps1` is a direct single-model task and does not exercise native delegation. A parent summary alone does not establish the upstream child model or effort. Keep work from a failed task intact and inspect it before dispatching remaining work.

Fresh host loading is required after projection. An existing chat may retain its old role definitions. Do not restart or stop the app to force loading. Local Codex files do not configure hosted ChatGPT Work.

## Failure handling

The JSON `fallbacks` are ordered candidates for a parent decision; they are not an automatic failover engine. The controlled launcher starts one `codex exec` process and never automatically retries, replays or launches an alternate. In this launcher, only a confirmed upstream unavailable/overload failure can permit one explicit reselection for reviewed remaining scope. A 429/quota/rate-limit stops and waits for a fresh parent selection; authentication, account risk, timeout, unknown, tool and compatibility failures do not trigger model switching. `-ReselectionCount 1` blocks another controlled launch for that bounded task. The parent records failure, inspected partial work, selected supported tuple and remaining scope.

| Failure | Action |
| --- | --- |
| Unsupported tuple, encrypted payload or incompatible tools | Stop and diagnose capability; do not treat as overload |
| Confirmed upstream unavailable/overload (structured 502/503/504) | At most one explicit parent reselection for reviewed remaining scope |
| 429/quota | Honor Retry-After/reset; no model switching to evade limits |
| Auth/permission/account risk | Stop for operator review |
| Timeout or unknown error | Inspect existing process result and partial writes before new dispatch |

Automatic failure behavior is product- and request-layer-specific. It is important to separate a same-model API retry, an `Auto` task router, a model-retirement migration, and a cross-model child-agent failover:

| Host surface | Product behavior documented by its vendor | What this repository guarantees |
| --- | --- | --- |
| Codex Desktop / `Start-ModelSlot.ps1` | This launcher sends one `codex exec` call and does not retry, replay or choose another model. The parent may explicitly reselect once for a structured upstream-unavailable error; 429/quota waits. Native subagent retry behavior is outside this JSON policy. | Three selected Codex tuples after target-catalog preflight; pinned child routes do not read `fallbacks` at runtime. |
| ZCode | v3.18.2 says sending prompts the user to reselect a model when the selected model is unavailable. It does not document automatic cross-model child-agent failover. | The only writer-verified tuple is GLM-5.3-Flash/max; no automatic fallback implemented here. |
| DeepSeek Harness | Third-party providers are supported. Its optional `dsh-llm-retry` policy retries eligible failed model requests on the configured provider route; this is request retry, not evidence of cross-model child failover. | No model writer or child-agent adapter. |
| WorkBuddy CN / WorkBuddy Enterprise | Custom models and task-routed `Auto` are documented. Enterprise/CodeBuddy Code subagent `fallback-main` handles a configured model that is disabled or unknown locally by using the main conversation model; the docs do not describe transient service errors as a cross-model retry. Treat that as model-resolution fallback for the documented client, not proof for every WorkBuddy Desktop surface. | No verified writer or child-agent adapter. |
| WorkBuddy AI international | Custom model services are supported. `Auto` allocates models by the service routing policy, and custom models do not necessarily participate in `Auto`; troubleshooting asks users to switch models for model-side errors. Public docs do not establish pinned-child failover. | No verified writer or child-agent adapter; CN and INTL are separate product surfaces. |
| CodeBuddy CLI | v2.134.0 documents retries before generation for selected failures and direct fallback-model switching on quota exhaustion; v2.148.0 narrows which 429 conditions retry versus switch. This versioned CLI behavior does not establish WorkBuddy Desktop or every subagent's behavior. | Not controlled by this repository. |
| Antigravity | Its Orchestrator can automatically pair planner and executor models and return control to the planner when execution hits friction; this is task orchestration, not model-unavailable failover. The CLI also retries selected transient API errors. A `/swarm` worker that exhausts quota pauses instead of retrying and needs a new board post, model switch or message to resume. | No exact-tuple writer or model failover adapter. |

So a host may retry a request, route a request in `Auto`, or resume a quota-paused worker after an explicit event; these behaviors do not imply a universal cross-model fallback. In this repository, `fallbacks` are parent-readable reselection candidates and never auto-run. During planning, `-AvailablePreset` can exclude an unavailable model before dispatch. Restricted-pool resolution selects the first eligible preset in the active pool if a slot default is excluded. To select a specific alternate for remaining work, choose its exact tuple role. A different model may share the same quota or gateway.

## Projection, proof and rollback

```powershell
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Resolve
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Plan -SubagentsOnly
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Apply -SubagentsOnly
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Verify
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Rollback -ReceiptPath <receipt.json>
pwsh -NoProfile -File ./Test-ModelPreset.ps1
```

Plan before Apply. Generated role files live in ignored `.generated/`; active Codex task slots and tuple roles are additionally projected as marked standalone files under `<CODEX_HOME>\agents\`, and Apply retires stale managed files left by renamed pool tuples (unmarked files are never touched). The shared `config.toml` therefore carries only the global subagent defaults, availability rules and a managed-agent manifest, while profile files pin their default tuple and inherit the shared named slots and exact-tuple roles. A named slot uses its shared route even when a profile is selected. To pin a child to the profile tuple, select its exact-tuple role. This keeps each role registered once. Ignored `.state/` stores backups and receipts. Preserve unrelated configuration, concurrency, hooks, auth and provider fields. Ownership markers prevent adopting user-owned files. Rollback checks current hashes; restore later dependent mutations first. Backups may contain sensitive pre-existing host data and must not be published.

ZCode supports Plan/Apply with `-SubagentsOnly -ExecutionHost zcode`, using the exact selector in its existing `~/.zcode/agents/glm-max.md`. It creates only marked namespaced slot definitions at max and leaves the source definition intact. Antigravity/WorkBuddy have no verified exact-tuple writer. Claude has no active facet after the prior user retirement decision and fails closed.

Resolve is offline policy evidence. Plan/Apply use `codex debug models` for the target `CODEX_HOME` with a 30-second deadline. Bound catalog snapshots require `source`, absolute `codex_root`, and a current validity window of at most five minutes. Catalog evidence proves tuple visibility, not generation success. Verify inspects effective configuration; repository tests use disposable host roots.

## Controlled launcher

```powershell
pwsh -NoProfile -File ./Start-ModelSlot.ps1 -Slot bounded_implementation -Model glm-5.3-flash -Effort xhigh -Plan
pwsh -NoProfile -File ./Start-ModelSlot.ps1 -Slot standard_review -Model gemini-3.8-flash-high -Effort high -Plan
```

Real execution requires a declared custom provider and exact tuple capability. Native mode checks the catalog. `provider_override` requires a current unexpired receipt binding exact model/effort, provider ID, surface, timestamps and source; the provider must match the effective profile/base configuration. Static historical matrix entries are insufficient. Per-invocation request and stream retry caps are zero; those do not control relay retries or internal model requests.

The launcher disables nested delegation and accepts explicit scope through `-Prompt`, with `-WorkingDirectory` and optional `-ReadOnly`. A strict one-shot child cannot fulfill an interactive design-griller or cold-runner lifecycle. Default execution timeout is 900 seconds (1-3600); probe timeout is 30 seconds (1-120). A timeout attempts to terminate only the launched process tree, without proving upstream cancellation or rollback. Failure classification uses structured JSON fields with precedence risk > auth > rate limit > tool/environment > overload; free text alone remains unknown.

Repository proof uses `Test-ModelPreset.ps1` (also wrapped by `tests/Unit/ModelPreset.Tests.ps1`); this independent tool is outside the main CLI build. `repo_verified -> filesystem_projected -> host_loaded -> live_accepted` remain separate claims. Stop once the requested boundary is proven.

Official sources checked 2026-11-21: [OpenAI model selection](https://developers.openai.com/api/docs/guides/model-selection), [Z.ai GLM-5.3-Flash release](https://z.ai/blog/glm-5.3-flash), [Gemini 3.8 Flash](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash), [ZCode model configuration](https://zcode.z.ai/en/docs/configuration) and [release notes](https://zcode.z.ai/en/changelog), [WorkBuddy CN custom-model configuration](https://cloud.tencent.com/document/product/1831/134445) and [subagent configuration](https://cloud.tencent.com/document/product/1831/137015), [WorkBuddy AI international model configuration](https://intl.cloud.tencent.com/document/product/1316/84496), [CodeBuddy CLI v2.134.0](https://www.codebuddy.ai/docs/cli/release-notes/v2.134.0) and [v2.148.0 release notes](https://www.codebuddy.ai/docs/cli/release-notes/v2.148.0), [DeepSeek Harness provider guide](https://deepseek-harness.github.io/deepseek-harness/en/guide/providers) and [retry policy source](https://github.com/deepseek-ai/deepseek-harness/blob/master/packages/llm/llm/src/retry-policy.ts), [Antigravity model selection and plan availability](https://antigravity.google/docs/models/), [retry changelog](https://antigravity.google/changelog), and [Swarm quota behavior](https://antigravity.google/docs/swarm/). These links describe product guidance and implementation surfaces; they do not prove this repository has an adapter or live acceptance for those hosts.
