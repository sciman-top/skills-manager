# 20260424 test runner diagnostics

## Scope
- Rule: R6 hard gate, R8 traceability.
- Risk: low.
- Landing: `tests/run.ps1`.
- Target: make the Pester test gate fail with an actionable diagnostic when the local module is missing.

## Commands
- `codex --version` / `codex --help`
  - Result: platform_na, Node initialization failed with `Assertion failed: ncrypto::CSPRNG(nullptr, 0)`.
- `.\build.ps1`
  - Result: passed.
- `.\skills.ps1 发现`
  - Result: passed, listed 96 skills.
- `.\skills.ps1 doctor --strict --threshold-ms 8000`
  - Result: passed.
- `.\skills.ps1 构建生效`
  - Result: failed closed with exit 1 because current `agent/` cannot be cleaned: `Access to the path 'D:\CODE\skills-manager\agent\.system\imagegen\agents\openai.yaml' is denied.`
- `.\tests\run.ps1`
  - Result: gate blocked with clear Pester requirement message.
- `.\scripts\quality\run-local-quality-gates.ps1 -Profile quick -AllowDirtyWorktree`
  - Result: passed.

## Rollback
- Revert the guard added to `tests/run.ps1` if the older raw `Import-Module Pester` failure is preferred.

