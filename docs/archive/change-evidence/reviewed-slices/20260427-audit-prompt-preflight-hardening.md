# 20260427 audit prompt preflight hardening

## Scope
- Rule IDs: R1, R2, R6, R8, E4
- Risk: low-to-medium; prompt contract and generated command guidance changed, no schema change.
- Landing: `src/Commands/AuditTargets.ps1`, generated `skills.ps1`, prompt assertions in `tests/Unit/AuditTargets.Tests.ps1`.
- Target disposition: improve built-in AI-agent prompts while preserving dry-run-only apply boundary.

## Changes
- Strengthened the built-in outer AI prompt with explicit write boundaries: only `recommendations.json` plus structured profile repair when needed; generated prompt/brief/snapshot/template/source files remain read-only.
- Added explicit `self-check -> preflight -> dry-run` sequence to the default prompt, `ai-brief.md`, and runtime `outer-ai-prompt.md`.
- Made `source_observations`, `keyword_trace`, evidence policy, decision-quality policy, duplicate checks, and empty-category summary requirements harder to miss.
- Bumped prompt contract version to `audit-prompt-v20260427.1` so stale run bundles are blocked by preflight.
- Updated prompt-focused unit assertions to cover the new preflight and write-boundary wording.

## Commands
- `.\build.ps1`
  - exit_code: 0
  - key_output: `Build success: D:\CODE\skills-manager\skills.ps1`
- direct prompt marker check by dot-sourcing `.\skills.ps1`
  - exit_code: 0
  - key_output: `prompt contract checks passed`
- `.\skills.ps1 发现`
  - exit_code: 0
  - key_output: listed 96 skills; no command failure
- `.\skills.ps1 doctor --strict --threshold-ms 8000`
  - exit_code: 0
  - key_output: `Your system is ready for skills-manager.`
- `.\skills.ps1 构建生效`
  - exit_code: 0
  - key_output: `构建完成：agent/ (共 91 项技能)` and `=== 构建生效流程完成 ===`

## Additional Notes
- `Invoke-Pester .\tests\Unit\AuditTargets.Tests.ps1` and `.\tests\run.ps1` were not available in this host session because the PowerShell `Pester` module is missing.
- Alternative verification used direct function calls for `Get-AuditOuterAiPromptContent`, `Write-AuditAiBrief`, and `Write-AuditOuterAiPromptFile`.

## Rollback
- `git checkout -- src/Commands/AuditTargets.ps1 tests/Unit/AuditTargets.Tests.ps1 skills.ps1 docs/change-evidence/20260427-audit-prompt-preflight-hardening.md`
- Then rerun `.\build.ps1` and the C.2 gate sequence if rollback is needed.
