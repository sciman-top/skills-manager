# Model Orchestration

- Source: `presets.json`, `Set-ModelPreset.ps1`, `Start-ModelSlot.ps1`.
- Strict entrypoint: `Start-ModelSlot.ps1`; freeze one route and disable native delegation. Do not substitute a profile-only launch as strict acceptance.
- Runtime: PowerShell 7; no gateway selection, credential changes, daemon, or task replay.
- Default: Astra-only; select one whole preset from an explicitly supplied available set, in Astra/Sol/Terra/Luna order.
- Five semantic slots are independent of native concurrency limits.
- Native projections preserve unrelated host configuration. Backups and receipts belong in ignored `.state/`; generated role files belong in `.generated/`.
- Verify: `pwsh -NoProfile -File Test-ModelPreset.ps1`, followed by the affected host's fresh config and request checks.
- Rollback: `Set-ModelPreset.ps1 -Action Rollback -ReceiptPath <receipt>`. Restore later dependent mutations first; hash drift must block rollback.
- Codex specialized delegation can bypass native hooks. Do not claim hard isolation from hook trust, unit tests, or ordinary config load.
- ZCode projection remains blocked until its native model/effort write interface is verified.
