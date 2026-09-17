# Model Orchestration

- Source: `presets.json`, `Set-ModelPreset.ps1`, `Start-ModelSlot.ps1`.
- Strict entrypoint: `Start-ModelSlot.ps1`; freeze one route and disable native delegation. Do not substitute a profile-only launch as strict acceptance.
- Runtime: PowerShell 7; no gateway selection, credential changes, daemon, or task replay.
- Default: `gpt56_sol_terra`; select one whole preset from an explicitly supplied available set, in Sol-Terra/Luna order. Only one preset is active at a time.
- Five semantic slots are independent of native concurrency limits. Each preset pins an ordered `(model, effort)` menu (`presets.json` schema v3) and declares host facets (`hosts`); slots map to menu indexes with duplicates allowed, and a preset may mix model families, as `gpt56_sol_terra` does. The codex facet projects a native profile plus the shared root/agent defaults that ChatGPT Desktop also reads; the launcher uses the first declared facet with a verified native interface, so a `zcode` facet stays resolve-only. Slot-map shape violations fail closed at load. Level unavailability degrades by explicit re-selection: nearest lighter level, then nearest heavier level, another whole preset last; never an in-task replay.
- Native projections preserve unrelated host configuration. Backups and receipts belong in ignored `.state/`; generated role files belong in `.generated/`.
- Verify: `pwsh -NoProfile -File Test-ModelPreset.ps1`, followed by the affected host's fresh config and request checks.
- Rollback: `Set-ModelPreset.ps1 -Action Rollback -ReceiptPath <receipt>`. Restore later dependent mutations first; hash drift must block rollback.
- Codex specialized delegation can bypass native hooks. Do not claim hard isolation from hook trust, unit tests, or ordinary config load.
- ZCode projection remains blocked until its native model/effort write interface is verified.
