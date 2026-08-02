# Default `grill-with-docs` projection closeout

## Scope and decision

- Source of truth: `skills.json.skill_projection.profiles.default.enabled_names`.
- Goal: make `grill-with-docs` available for explicit invocation and narrow
  design-grilling implicit invocation in the default Codex profile.
- Dependency closure: keep `grilling` and `domain-modeling` resident with the
  wrapper so the workflow does not degrade after activation.
- Host write boundary: update only the skills-manager-managed projection block
  in `~/.codex/config.toml`; do not restart or stop Codex.

## Changed files

- `skills.json`
- `README.md`
- `scripts/verify-codex-skill-profiles.ps1`
- generated `skills.ps1` through `build.ps1`

The pre-existing rule-estate worktree changes are outside this slice and are
not part of its rollback.

## Verification

| Gate | Result |
| --- | --- |
| `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` | exit 0 |
| `Invoke-Pester tests/Unit/ConfigUpdate.Tests.ps1` | 46 passed, 0 failed |
| `scripts/verify-codex-skill-profiles.ps1` | 15 profiles passed; default restored |
| `skills.ps1 技能配置 使用 default` | `active=14`, `metadata=7485/8000`, `persisted=True` |
| fresh `codex debug prompt-input` | `grill-with-docs`, `grilling`, and `domain-modeling` present |
| `skills.ps1 doctor --strict --threshold-ms 8000` | exit 0 |
| explicit ephemeral read-only Codex probe | loaded and followed `$grill-with-docs` |
| implicit grill-only probe | selected the narrower `grilling` primitive |
| implicit ADR/glossary probe | loaded `grill-with-docs`, then its two dependencies |

The full repository test wrapper is not green in the current dirty worktree:
Unit reported `670 passed, 1 failed`, and E2E reported `17 passed, 1 failed`.
The visible E2E failure is the pre-existing rule-estate reviewed multi-target
CLI test parsing a timestamp-prefixed stream as JSON. Isolated
`RuleEstate.Tests.ps1` and `RuleEstateMutation.Tests.ps1` subsequently passed
6/6 each, but that does not erase the full-run failure. Contract/hotspot
closeout therefore remains blocked for the combined worktree, while the
profile slice has targeted, fresh-process, host-projection, and live invocation
acceptance.

## Risks and rollback

- Default profile metadata is `7485/8000`, leaving 515 characters under the
  effective ceiling. System/plugin metadata remains a live input, so the
  budget verifier must remain mandatory.
- Host backup:
  `C:\Users\sciman\.codex\config.toml.bak-20260802-211554-before-default-grill-closeout`.
- Roll back only this slice by removing the three default profile names and the
  corresponding README/verifier assertions, rebuilding `skills.ps1`, then
  running `skills.ps1 技能配置 使用 default`. The host backup is an emergency
  rollback reference, not a substitute for the managed projection command.
