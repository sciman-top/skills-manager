# Model Presets

This independent, local PowerShell 7 tool projects the six model-family presets defined in `presets.json`. It does not select gateways, inspect credentials, retry tasks, or run background monitors.

The default is `gpt6_astra_only`. Five semantic execution slots map to `light / standard / standard / standard / deep`. Astra/Sol use low/medium/high, Terra/Luna use high/xhigh/max, GLM uses low/high/max, and DeepSeek Flash uses high/high/max.

Use the controlled slot entrypoint for single-family execution. It freezes the selected preset and exact slot route, disables native subagent delegation, accepts no extra model/config flags, and never retries under another preset:

```powershell
pwsh -NoProfile -File ./Start-ModelSlot.ps1 -Slot bounded_implementation -WorkingDirectory D:/CODE/skills-manager -Prompt 'Your bounded task'
pwsh -NoProfile -File ./Start-ModelSlot.ps1 -Preset deepseek_flash_only -Slot standard_review -WorkingDirectory D:/CODE/skills-manager -Prompt 'Your review task'
```

The restriction applies to this controlled entrypoint. It is not an operating-system security boundary against deliberately launching other AI programs from an unrestricted shell. Ordinary Desktop sessions and manually launched CLI sessions remain separate entrypoints.

```powershell
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Plan
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Apply
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Resolve -AvailablePreset gpt56_luna_only,gpt56_sol_only
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Apply -Preset deepseek_flash_only
pwsh -NoProfile -File ./Set-ModelPreset.ps1 -Action Rollback -ReceiptPath <receipt.json>
```

`AvailablePreset` is an explicitly declared available set, not an automatic model or gateway probe. The example selects Sol despite input ordering. Running tasks do not switch presets; only future sessions use a newly projected default.

Codex projections create four complete native profiles (`gpt6-astra-only`, `gpt56-sol-only`, `gpt56-terra-only`, `gpt56-luna-only`), five role definitions per profile, and matching parent/review/subagent defaults. Existing provider, auth, permissions, concurrency limits, hooks, and unrelated roles remain intact.

Codex 0.153.4's specialized delegation path bypassed a trusted hook in two controlled live tests. That ineffective hook was retired. The chosen entrypoint disables native delegation instead; no global `code_mode_host` change is required.

Claude projections set the exact `deepseek-flash` model, alias mappings, high default effort, five named subagent files, and the native `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` setting. High and max remain distinct slot efforts. This requires Claude Code 2.1.257 or later. External configuration managers can overwrite user settings; rerun Plan to detect model-field drift rather than changing their provider databases.

ZCode currently supports offline Resolve only. Its local native projection interface and UI acceptance have not been verified. Internal application stores are not treated as supported configuration APIs.

Backups may contain pre-existing sensitive host configuration. `.state/` and `.generated/` are ignored and must not be published. Receipts record paths and hashes, not credentials. Later host changes cause earlier exact-hash rollback to block; review dependent changes before attempting rollback.

```powershell
pwsh -NoProfile -File ./Test-ModelPreset.ps1
codex --profile gpt6-astra-only --strict-config --version
claude plugin validate "$env:USERPROFILE/.claude/agents"
```

Configuration parsing, fresh host loading, controlled requests, and natural user acceptance are separate evidence layers. The source tests do not establish live model availability or hard isolation.
