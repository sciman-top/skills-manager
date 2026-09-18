# Model Presets

This independent, local PowerShell 7 tool projects the four orchestration presets defined in `presets.json` (schema v3). It does not select gateways, inspect credentials, retry tasks, or run background monitors.

One preset is active at a time. Each preset pins an ordered menu of `(model, effort)` levels, lightest first, and may mix model families: in the default `gpt56_sol_terra`, routine work runs on Terra while the deepest slot gets Sol/medium — the strongest level of the preset (operator-declared 2026-09-15: Sol/medium > Terra/xhigh > Terra/high). The five semantic execution slots map onto menu indexes with duplicates allowed — `quick_triage` takes the lightest level, `routine_maintenance` / `standard_review` / `bounded_implementation` share the standard level, and `deep_investigation_or_implementation` takes the deepest level. Current menus: Sol-Terra = Terra/high, Terra/xhigh, Sol/medium; Luna-only = high, xhigh; GLM-5.3-Flash = high, max; DeepSeek Flash = high, max. The fallback order inside an active preset is fixed: when a pinned level is unavailable, re-select the nearest lighter level first, then the nearest heavier level, and only then another whole preset — always as an explicit operator decision between launches, never as an in-task replay or silent re-route.

Each preset declares host facets (`hosts`). A `codex` facet projects a complete native profile plus, when the preset is active, the shared root defaults in `~/.codex/config.toml` (`model`, `model_reasoning_effort`, `[agents]` subagent defaults) — the same surface ChatGPT Desktop reads for new-chat defaults, where `glm-5.3-flash` / `deepseek-flash` are selectable through the local provider channel. The Desktop app may rewrite model/effort selections in that file between applies; both sides are explicit user actions and the next Apply re-pins the active preset. Per-chat model/effort picking in Desktop should follow the active preset's menu order (lightest slot → lightest level, deep work → strongest level). A `zcode` facet remains resolve-only: ZCode's native model/effort write interface is unverified, so its effort menu (低/高/最高) is set manually per session.

Use the controlled slot entrypoint for single-preset execution. It freezes the selected preset and exact slot route, disables native subagent delegation, accepts no extra model/config flags, and never retries under another preset:

This is an opt-in execution constraint, not the default engineering workflow. Use the ordinary host entrypoint for tasks needing native delegation or a named specialist bridge. A strict slot cannot satisfy a skill contract that requires `design-griller` or `cold-capability-runner`: report that incompatibility before preparing admission files; do not weaken the skill contract, re-enable delegation, or silently change the preset. Existing bridge model pins are separate from preset slots and are not overridden by this tool. Model availability must come from the current execution surface, not a previously successful projection.

```powershell
pwsh -NoProfile -File ./Start-ModelSlot.ps1 -Slot bounded_implementation -WorkingDirectory D:/CODE/skills-manager -Prompt 'Your bounded task'
pwsh -NoProfile -File ./Start-ModelSlot.ps1 -Preset deepseek_flash_only -Slot standard_review -WorkingDirectory D:/CODE/skills-manager -Prompt 'Your review task'
```

The restriction applies to this controlled entrypoint. It is not an operating-system security boundary against deliberately launching other AI programs from an unrestricted shell. Ordinary Desktop sessions and manually launched CLI sessions remain separate entrypoints.

```powershell
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Plan
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Apply
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Resolve -AvailablePreset gpt56_luna_only,gpt56_sol_terra
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Apply -Preset deepseek_flash_only
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Rollback -ReceiptPath <receipt.json>
```

`AvailablePreset` is an explicitly declared available set, not an automatic model or gateway probe. The example selects Sol-Terra despite input ordering. Running tasks do not switch presets; only future sessions use a newly projected default.

Codex projections create four complete native profiles (`gpt56-sol-terra`, `gpt56-luna-only`, `glm53-flash-only`, `deepseek-flash-only`), five role definitions per profile, and matching parent/review/subagent defaults. A profile's parent/review/subagent defaults are pinned to the preset's standard route (the `routine_maintenance` slot entry): Sol-Terra therefore defaults to Terra/xhigh while its deep role stays on Sol/medium. Existing provider, auth, permissions, concurrency limits, hooks, and unrelated roles remain intact.

Codex 0.153.4's specialized delegation path bypassed a trusted hook in two controlled live tests. That ineffective hook was retired. The chosen entrypoint disables native delegation instead; no global `code_mode_host` change is required.

Claude projections set the exact `deepseek-flash` model, alias mappings, high default effort, five named subagent files, and the native `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` setting. High and max remain distinct slot efforts. This requires Claude Code 2.1.257 or later. External configuration managers can overwrite user settings; rerun Plan to detect model-field drift rather than changing their provider databases.

ZCode currently supports offline Resolve only. Its local native projection interface and UI acceptance have not been verified. Internal application stores are not treated as supported configuration APIs.

Backups may contain pre-existing sensitive host configuration. `.state/` and `.generated/` are ignored and must not be published. Receipts record paths and hashes, not credentials. Later host changes cause earlier exact-hash rollback to block; review dependent changes before attempting rollback.

```powershell
pwsh -NoProfile -File ./Test-ModelPreset.ps1
codex --profile gpt56-sol-terra --strict-config --version
claude plugin validate "$env:USERPROFILE/.claude/agents"
```

Configuration parsing, fresh host loading, controlled requests, and natural user acceptance are separate evidence layers. The source tests do not establish live model availability or hard isolation.

The shared local/CI classifier maps changes to the four preset source/config/test files to `tests/Unit/ModelPreset.Tests.ps1`, which invokes the existing disposable-host test script. Preset-only proof skips the unrelated main CLI build and locked skill materialization. Mixed changes retain their applicable checks; full tests also include this suite. The optional `-Verifier mor` checks the design tuple matrix and is not a substitute for preset behavior tests.
