# Model Presets

This independent PowerShell 7 tool projects the joint model pool defined in `presets.json` (schema v4). It does not select gateways, inspect credentials, retry tasks or run background monitors.

All three model menus are jointly enabled by default: GPT-6.1-Sol low/medium/high, GPT-6-luna max and GLM-5.3-Flash high/max. DeepSeek is removed. Each child task may select any exact supported tuple from this pool, including different models on simultaneous tasks. `default_preset=gpt61_sol_only` supplies defaults when no exact tuple is chosen; it does not constrain all tasks to Sol. Menu ordering describes effort within one model and does not claim performance rankings across models.

| Preset | Model | Quick triage | Routine / review / bounded implementation | Deep investigation / implementation |
| --- | --- | --- | --- | --- |
| `gpt61_sol_only` | `gpt-6.1-sol` | low | medium | high |
| `gpt6_luna_only` | `gpt-6-luna` | max | max | max |
| `glm53_flash_only` | `glm-5.3-flash` | high | high | max |

The old `gpt56_sol_terra` and `gpt56_luna_only` script arguments remain aliases for the canonical GPT IDs. `-Preset` selects fallback defaults; `-AvailablePreset` limits the jointly enabled pool to all supplied menus rather than selecting one winner. The omitted available set means all three menus. Resolve returns `active_presets`, `enabled_routes`, `slots` and fallback `routes`. These are declared configuration, not automatic availability probes. Historical profile and custom role files remain outside the active managed block; launching an old profile directly does not invoke the aliases or the current pool.

The initial eight semantic slots are `quick_triage`, `routine_maintenance`, `standard_review`, `bounded_implementation`, `deep_investigation_or_implementation`, `test_execution`, `documentation_review` and `architecture_review`. They describe task scope, not a fixed child count or concurrency allocation. Extend `slots` and every menu's `slot_map` together; include read-only additions in `read_only_slots`. The launcher validates these fields dynamically. Each configured slot can select any pool tuple using `-Model` and `-Effort` together.

Six exact tuple roles coexist in the ordinary Codex host: `sol_low`, `sol_medium`, `sol_high`, `luna_max`, `glm_high` and `glm_max`. The parent selects a tuple role and supplies the semantic slot, scope, write set, proof and stop in its assignment. Semantic roles retain fallback routes and read-only descriptions. A fixed custom role's model/effort cannot be overridden: choose the matching tuple role or a supported native explicit tuple route instead. Specialist bridges retain their own execution contracts.

## Task selection and effort changes

An ordinary host AI can classify a task, split its dependencies and choose a named slot before dispatch. Delegate only when the user or applicable instructions explicitly authorize delegation. Parallel dispatch additionally needs independently verifiable slices, disjoint write sets, positive benefit and the host's native concurrency budget. These presets supply model/effort routes; they do not install a scheduler, grant delegation permission or guarantee that an AI will choose to delegate.

- Choose `quick_triage` for a small read-only lookup, known error classification or concrete evidence check.
- Choose `routine_maintenance`, `standard_review` or `bounded_implementation` for ordinary work with clear inputs, a bounded scope and local proof. Review remains read-only. Use `test_execution` for scoped test commands, `documentation_review` for read-only contract checks and `architecture_review` for read-only architecture or security analysis.
- Choose `deep_investigation_or_implementation` when unresolved cross-module behavior, interacting constraints, architecture or security boundaries require deeper reasoning. For a deep review, pass an explicit read-only scope.
- Increase effort by choosing the appropriate slot before a new bounded task. If a child returns unresolved uncertainty, the parent reviews its evidence and remaining scope before re-selection; completed writes are not replayed.
- Decrease effort for the next independent task once the remaining question is concrete. Sol follows low -> medium -> high; GLM high -> max; Luna stays max. Choose the model independently by task fit and current support; there is no measured universal ranking between these models.
- Missing input requires clarification. Authentication, provider, tool and 429 failures require their own diagnosis; they do not justify increasing effort or blindly repeating a task.

When a tuple is unavailable, the parent may choose another supported pool tuple for the remaining or next bounded task and record the reason. Whole-preset switching is not required. Preserve scope, proof and prior work; do not replay completed writes or silently substitute effort. A runtime failure is not itself evidence that another model is entitled or that higher effort will fix it.

A 429 or other confirmed availability failure may trigger explicit parent re-selection to a supported lower effort, higher effort or another model, provided the remaining task still meets its proof requirements. Record the failed tuple, failure, selected tuple and remaining scope. Inspect any partial writes before continuation; a failed read-only request may be repeated with the newly selected route. Each child launch remains frozen, and the launcher returns failures without automatically substituting a route. Higher effort is an availability choice only when that tuple is supported; it does not establish that rate limiting was caused by insufficient reasoning.

The parent must verify the exact model/effort tuple on the current execution surface before spawning: eligible tuples are the declared pool intersected with host-supported tuples. `AvailablePreset` and offline Resolve describe operator-declared routes, not model entitlements. Verify both the exact model name and its supported reasoning levels; a model entry alone does not establish support for every configured effort. Retain requested tuples without current support evidence as configuration only. Do not infer aliases from display names or replace max with xhigh. Catalog observations do not establish provider request success.

Each menu declares host facets (`hosts`). A `codex` facet projects a complete native profile and shared defaults in `~/.codex/config.toml`. Full Apply updates parent/review/subagent selections. For daily subagent orchestration use `-SubagentsOnly`: it updates subagent defaults and the managed semantic/tuple roles, preserving parent/review selections. All current menus have a Codex facet. A `zcode` facet remains resolve-only; Antigravity and WorkBuddy have no verified model preset write adapter in this tool.

Use the controlled slot entrypoint for one bounded child task. It freezes one exact route selected from the joint pool and disables nested native delegation. Separate tasks may select different routes. It accepts the validated `-Model/-Effort` pair, not arbitrary configuration flags, and does not replay a failed task:

This is an opt-in execution constraint. Use the ordinary host entrypoint for parent orchestration or a named specialist bridge. A strict slot cannot satisfy a skill contract requiring `design-griller` or `cold-capability-runner`: report the incompatibility before preparing admission files. Managed bridge templates do not pin model/effort; the parent selects a supported tuple from the joint pool or inherits subagent defaults. Availability must come from the current execution surface.

```powershell
pwsh -NoProfile -File ./Start-ModelSlot.ps1 -Slot bounded_implementation -WorkingDirectory D:/CODE/skills-manager -Prompt 'Your bounded task'
pwsh -NoProfile -File ./Start-ModelSlot.ps1 -Slot standard_review -Model gpt-6-luna -Effort max -Plan
pwsh -NoProfile -File ./Start-ModelSlot.ps1 -Slot test_execution -Model glm-5.3-flash -Effort high -Plan
pwsh -NoProfile -File ./Start-ModelSlot.ps1 -Slot deep_investigation_or_implementation -Model gpt-6.1-sol -Effort high -ReadOnly -Plan
```

The restriction applies to this controlled entrypoint. It is not an operating-system security boundary against deliberately launching other AI programs from an unrestricted shell. Ordinary Desktop sessions and manually launched CLI sessions remain separate entrypoints.

```powershell
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Plan -SubagentsOnly
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Apply -SubagentsOnly
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Resolve -AvailablePreset gpt6_luna_only,gpt61_sol_only
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Resolve
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Rollback -ReceiptPath <receipt.json>
```

`AvailablePreset` is explicitly declared. The two-menu example keeps both Sol and Luna available while retaining Sol fallback defaults. New projections affect future host loads; an existing child's route stays fixed for its bounded task.

Codex projections create three native profiles (`gpt61-sol-only`, `gpt6-luna-only`, `glm53-flash-only`), eight semantic role files per profile and six shared tuple role files. Each profile and the active root expose the tuple pool. A profile's fallback defaults use `routine_maintenance`: Sol medium, Luna max or GLM high. `-SubagentsOnly` preserves parent/review fields. Provider, auth, permissions, concurrency, hooks and unrelated roles remain intact. DeepSeek historical files are not deleted and are not managed or selected by this policy.

Codex 0.153.4's specialized delegation path bypassed a trusted hook in two controlled live tests. That ineffective hook was retired. The chosen entrypoint disables native delegation instead; no global `code_mode_host` change is required.

No current menu declares a Claude facet after removing DeepSeek, so this pool does not project Claude settings.

ZCode currently supports offline Resolve only. Its local native projection interface and UI acceptance have not been verified. Internal application stores are not treated as supported configuration APIs.

Backups may contain pre-existing sensitive host configuration. `.state/` and `.generated/` are ignored and must not be published. Receipts record paths and hashes, not credentials. Later host changes cause earlier exact-hash rollback to block; review dependent changes before attempting rollback.

```powershell
pwsh -NoProfile -File ./Test-ModelPreset.ps1
codex --profile gpt61-sol-only --strict-config --version
```

Configuration parsing, fresh host loading, controlled requests, and natural user acceptance are separate evidence layers. The source tests do not establish live model availability or hard isolation.

The shared local/CI classifier maps changes to the four preset source/config/test files to `tests/Unit/ModelPreset.Tests.ps1`, which invokes the existing disposable-host test script. Preset-only proof skips the unrelated main CLI build and locked skill materialization. Mixed changes retain their applicable checks; full tests also include this suite. The optional `-Verifier mor` checks the design tuple matrix and is not a substitute for preset behavior tests.
