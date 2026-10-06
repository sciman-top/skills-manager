# Model Presets

This independent PowerShell 7 tool projects the joint model pool defined in `presets.json` (schema v4). It does not select gateways, inspect credentials, retry tasks or run background monitors.

Both model menus are jointly enabled by default: GPT-6-luna max and GLM-5.3-Flash max. DeepSeek is removed. Each child task may select any exact supported tuple from this pool, including different models on simultaneous tasks. `default_preset=gpt6_luna_only` supplies defaults when no exact tuple is chosen; it does not constrain all tasks to Luna. Menu ordering describes effort within one model and does not claim performance rankings across models.

| Preset | Model | Quick triage | Routine / review / bounded implementation | Deep investigation / implementation |
| --- | --- | --- | --- | --- |
| `gpt6_luna_only` | `gpt-6-luna` | max | max | max |
| `glm53_flash_only` | `glm-5.3-flash` | max | max | max |

Only `gpt56_luna_only` remains a legacy alias. Sol presets and aliases are rejected; the subagent pool excludes Sol without changing the parent model. `-Preset` selects fallback defaults; `-AvailablePreset` limits the jointly enabled pool to all supplied menus rather than selecting one winner. The omitted available set means both menus. Resolve returns `active_presets`, `enabled_routes`, `slots` and fallback `routes`. These are declared configuration, not automatic availability probes. Historical profile and custom role files remain outside the active managed block; launching an old profile directly does not invoke the aliases or the current pool.

The initial eight semantic slots are `quick_triage`, `routine_maintenance`, `standard_review`, `bounded_implementation`, `deep_investigation_or_implementation`, `test_execution`, `documentation_review` and `architecture_review`. They describe task scope, not a fixed child count or concurrency allocation. Extend `slots` and every menu's `slot_map` together; include read-only additions in `read_only_slots`. The launcher validates these fields dynamically. Each configured slot can select any pool tuple using `-Model` and `-Effort` together.

Two exact tuple roles coexist in the ordinary Codex host: `luna_max` and `glm_max`. The parent selects a tuple role and supplies the semantic slot, scope, write set, proof and stop in its assignment. Semantic roles retain fallback routes and read-only descriptions. A fixed custom role's model/effort cannot be overridden: choose the matching tuple role or a supported native explicit tuple route instead. Specialist bridges retain their own execution contracts.

## Task selection and effort changes

### Host capability and policy boundary

| Host | Native decomposition / delegation | Model and effort projection from this tool |
| --- | --- | --- |
| ChatGPT Work / local Codex | Official subagent workflows; local custom agents can pin different model/effort pairs. Hosted Work uses its available tools and hosted environment. | Local Codex only: config, profiles and exact tuple roles. Local files do not configure hosted Work. |
| ZCode | Official general-purpose, Explore and user-defined subagents; native definitions can pin model and thought level. | This tool remains Resolve only; it does not yet project ZCode agent definitions. |
| Antigravity | Agent-manager capabilities depend on the installed host; multiple conversations alone do not prove parent-dispatched children. | No verified adapter; this pool cannot promise GPT/GLM child selection. |
| WorkBuddy | Child support requires current native tools and lifecycle evidence. | No verified adapter; rule projection alone does not select a child's model or effort. |

The shared rules require explicit delegation authorization. Asking for a deep review or saying "continue" does not grant it. Once authorized, the parent can split independent tasks and select supported tuples without asking again for each child. The strict `Start-ModelSlot.ps1` entrypoint disables nested delegation; ordinary host orchestration is a separate entrypoint. Fixed Luna/GLM max means that complexity changes select scope or another supported model, rather than lowering either model's effort.

Official sources checked 2026-10-07: [OpenAI subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents), [ZCode Agent](https://zcode.z.ai/cn/docs/agents), [ZCode subagents](https://zcode.z.ai/cn/docs/subagents). OpenAI documents custom-file precedence over spawn values and defaults; configure both model and effort. ZCode documents `~/.zcode/agents/<name>.md` frontmatter with `model` and case-sensitive `thoughtLevel`; `reasoningEffort` is silently ignored. Effort applies only with a concrete model; `inherit` follows the parent's complete reasoning configuration. New sessions load changed definitions. This is documented support, not current local host acceptance. Antigravity/WorkBuddy model adapters remain unverified; do not infer their support from these two other hosts.

Menus must contain one model in strictly increasing effort order: failure re-selection interprets earlier entries as lower effort. Resolve rejects reversed or mixed-model menus. Luna and GLM each contain only max, so availability fallback has no within-model downgrade for either.

An ordinary host AI can classify a task, split its dependencies and choose a named slot before dispatch. Delegate only when the user or applicable instructions explicitly authorize delegation. Parallel dispatch additionally needs independently verifiable slices, disjoint write sets, positive benefit and the host's native concurrency budget. These presets supply model/effort routes; they do not install a scheduler, grant delegation permission or guarantee that an AI will choose to delegate.

- Choose `quick_triage` for a small read-only lookup, known error classification or concrete evidence check.
- Choose `routine_maintenance`, `standard_review` or `bounded_implementation` for ordinary work with clear inputs, a bounded scope and local proof. Review remains read-only. Use `test_execution` for scoped test commands, `documentation_review` for read-only contract checks and `architecture_review` for read-only architecture or security analysis.
- Choose `deep_investigation_or_implementation` when unresolved cross-module behavior, interacting constraints, architecture or security boundaries require deeper reasoning. For a deep review, pass an explicit read-only scope.
- Choose the appropriate scope and model before a new bounded task; both available models remain at max. If a child returns unresolved uncertainty, the parent reviews its evidence and remaining scope before re-selection; completed writes are not replayed.
- Return to a smaller scope for the next independent task once the remaining question is concrete. Luna and GLM stay max; this pool has no within-model effort changes. Choose the model independently by task fit and current support; there is no measured universal ranking between these models.
- Missing input requires clarification. Authentication, provider, tool and 429 failures require their own diagnosis; they do not justify increasing effort or blindly repeating a task.

When a tuple is unavailable, the parent may choose another supported pool tuple for the remaining or next bounded task and record the reason. Whole-preset switching is not required. Preserve scope, proof and prior work; do not replay completed writes or silently substitute effort. A runtime failure is not itself evidence that another model is entitled or that higher effort will fix it.

A 429 or other confirmed availability failure triggers explicit parent re-selection for the next bounded task following the fixed deterministic chain that Apply projects into the profile instructions and the shared config block (`# availability-rules:`). For 429/quota/rate-limit/auth/billing failures the chain is: nearest lower effort within the same preset, then the next active preset in declared order, then stop for operator re-selection; the cross-preset list does not wrap around to presets that precede the failed one. A higher effort is never part of this chain because it spends more tokens against the same limit. Only a confirmed service overload/unavailability may also try the nearest higher effort. The launcher additionally prints a structured `slot_failure` document (failed tuple, within-preset lower efforts, cross-preset options, overload-only higher efforts, prohibition text) and never retries or substitutes a route itself. Record the failed tuple, failure, selected tuple and remaining scope. Inspect any partial writes before continuation; a failed read-only request may be repeated with the newly selected route. Each child launch remains frozen. Higher effort under overload is an availability choice only when that tuple is supported; it does not establish that rate limiting was caused by insufficient reasoning.

The parent must verify the exact model/effort tuple on the current execution surface before spawning: eligible tuples are the declared pool intersected with host-supported tuples. `AvailablePreset` and offline Resolve describe operator-declared routes, not model entitlements. Verify both the exact model name and its supported reasoning levels; a model entry alone does not establish support for every configured effort. Retain requested tuples without current support evidence as configuration only. Do not infer aliases from display names or replace max with xhigh. Catalog observations do not establish provider request success.

Each menu declares host facets (`hosts`). A `codex` facet projects a complete native profile and shared defaults in `~/.codex/config.toml`. Full Apply updates parent/review/subagent selections. For daily subagent orchestration use `-SubagentsOnly`: it updates subagent defaults and the managed semantic/tuple roles, preserving parent/review selections. All current menus have a Codex facet. A `zcode` facet remains resolve-only; Antigravity and WorkBuddy have no verified model preset write adapter in this tool.

Use the controlled slot entrypoint for one bounded child task. It freezes one exact route selected from the joint pool and disables nested native delegation. Separate tasks may select different routes. It accepts the validated `-Model/-Effort` pair, not arbitrary configuration flags, and does not replay a failed task:

This is an opt-in execution constraint. Use the ordinary host entrypoint for parent orchestration or a named specialist bridge. A strict slot cannot satisfy a skill contract requiring `design-griller` or `cold-capability-runner`: report the incompatibility before preparing admission files. Managed bridge templates do not pin model/effort; the parent selects a supported tuple from the joint pool or inherits subagent defaults. Availability must come from the current execution surface.

```powershell
pwsh -NoProfile -File ./Start-ModelSlot.ps1 -Slot bounded_implementation -WorkingDirectory D:/CODE/skills-manager -Prompt 'Your bounded task'
pwsh -NoProfile -File ./Start-ModelSlot.ps1 -Slot standard_review -Model gpt-6-luna -Effort max -Plan
pwsh -NoProfile -File ./Start-ModelSlot.ps1 -Slot test_execution -Model glm-5.3-flash -Effort max -Plan
```

The restriction applies to this controlled entrypoint. It is not an operating-system security boundary against deliberately launching other AI programs from an unrestricted shell. Ordinary Desktop sessions and manually launched CLI sessions remain separate entrypoints.

```powershell
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Plan -SubagentsOnly
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Apply -SubagentsOnly
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Resolve -AvailablePreset gpt6_luna_only,glm53_flash_only
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Resolve
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Rollback -ReceiptPath <receipt.json>
```

`AvailablePreset` is explicitly declared. The two-menu example keeps both Luna and GLM available while retaining Luna fallback defaults. New projections affect future host loads; an existing child's route stays fixed for its bounded task.

Codex projections create two native profiles (`gpt6-luna-only`, `glm53-flash-only`), eight semantic role files per profile and two shared tuple role files. Each profile and the active root expose the tuple pool. A profile's fallback defaults use `routine_maintenance`: Luna max or GLM max. `-SubagentsOnly` preserves parent/review fields. Provider, auth, permissions, concurrency, hooks and unrelated roles remain intact. DeepSeek historical files are not deleted and are not managed or selected by this policy.

Codex 0.153.4's specialized delegation path bypassed a trusted hook in two controlled live tests. That ineffective hook was retired. The chosen entrypoint disables native delegation instead; no global `code_mode_host` change is required.

No current menu declares a Claude facet after removing DeepSeek, so this pool does not project Claude settings.

This tool currently supports offline Resolve only for ZCode. Its documented native agent-definition interface has no adapter here, and local UI loading and invocation remain unverified. Internal application stores are not treated as supported configuration APIs.

Backups may contain pre-existing sensitive host configuration. `.state/` and `.generated/` are ignored and must not be published. Receipts record paths and hashes, not credentials. Later host changes cause earlier exact-hash rollback to block; review dependent changes before attempting rollback.

```powershell
pwsh -NoProfile -File ./Test-ModelPreset.ps1
codex --profile gpt6-luna-only --strict-config --version
```

Configuration parsing, fresh host loading, controlled requests, and natural user acceptance are separate evidence layers. The source tests do not establish live model availability or hard isolation.

The shared local/CI classifier maps changes to the four preset source/config/test files to `tests/Unit/ModelPreset.Tests.ps1`, which invokes the existing disposable-host test script. Preset-only proof skips the unrelated main CLI build and locked skill materialization. Mixed changes retain their applicable checks; full tests also include this suite. The optional `-Verifier mor` checks the design tuple matrix and is not a substitute for preset behavior tests.
