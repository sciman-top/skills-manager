# Installed skill integrity and dependency closure

## Scope

- Audited every generated top-level skill package under `agent/` and the Codex
  projection produced from the managed source.
- Validated entrypoints, relative resources, duplicate names, composite-skill
  dependencies, profile closure, `agents/openai.yaml` resources, declared MCP
  tools, source locks, projection conflicts, and all profile budgets.
- Kept the final active skill profile as `default`.

## Root causes

The initial fail-closed scan reproduced 36 broken relative resources:

- 35 links came from six upstream packages whose referenced material does not
  exist in their pinned upstream sources: `openpyxl`, `python-docx`,
  `python-pptx`, `ppt-master`, `python-design-patterns`, and
  `web-quality-audit`.
- One link in `subagent-driven-development` targeted
  `../requesting-code-review/code-reviewer.md`. The source file exists, but the
  namespaced generated directory changed where that relative path resolved.

The dependency scan also found these closure gaps:

- `improve-codebase-architecture` requires `codebase-design`.
- `to-spec` and `to-tickets` require `setup-matt-pocock-skills` as their setup
  fallback.
- `subagent-driven-development` requires `requesting-code-review` in the same
  enabled profile.

`grill-with-docs` was already correctly paired with its shared dependencies,
`grilling` and `domain-modeling`; all three remain installed.

## Remediation

- Removed the six incomplete, overlapping skills and their unused source
  entries. The Office workflows remain covered by the primary
  Presentations/Documents/Spreadsheets capabilities; retained architecture,
  Python, and web skills cover the other overlapping workflows.
- Installed `codebase-design` and `setup-matt-pocock-skills` from
  `https://github.com/mattpocock/skills.git`, pinned to
  `391a2701dd948f94f56a39f7533f8eea9a859c87`.
- Added the `engineering` profile with the full Matt Pocock workflow closure and
  added `requesting-code-review` to `coding`.
- Added `overrides/requesting-code-review/code-reviewer.md` as a resource-only
  bridge. It has no `SKILL.md`, so it cannot create a duplicate skill. Its
  SHA-256 matches the pinned Superpowers source exactly.
- Added `config/skill-dependency-closure.json` and
  `scripts/verify-skill-integrity.ps1`; wired the verifier into quick/full local
  quality gates after `generated-sync` and before `dependency-baseline`.

The first two closure apply attempts failed closed and rolled back generated
output: one because the setup skill had not yet been fetched, and one because
putting the entire engineering closure in `coding` exceeded the 8,000-character
metadata budget. The separate `engineering` profile resolves that budget issue.

## Final integrity state

`reports/skill-integrity/current.json` records:

- 108 managed skill entrypoints.
- 0 duplicate skill-name groups.
- 7 explicit composite-skill dependency entries.
- 7 `agents/openai.yaml` manifests; all referenced icons exist.
- 0 declared MCP tool dependencies in managed manifests.
- 0 errors and 0 warnings.

`reports/skill-projection/current.json` records 112 Codex skill entries, 112
unique names, 0 conflicts, and 10/10 profile budgets passing. Estimated metadata
sizes, including the 1,700-character external reserve, are:

| Profile | Estimated / limit |
| --- | ---: |
| browser | 5461 / 8000 |
| coding | 7917 / 8000 |
| content | 7726 / 8000 |
| database | 5533 / 8000 |
| default | 7150 / 8000 |
| design | 5883 / 8000 |
| dotnet | 7588 / 8000 |
| engineering | 6561 / 8000 |
| physics | 6298 / 8000 |
| ppt | 5885 / 8000 |

## Runtime boundary

The retained skills are structurally discoverable and callable: their entry
instructions and declared local resources resolve, explicit skill dependencies
are installed and profile-visible, and declared MCP requirements fail closed if
they are not managed in `skills.json`.

This does not globally install every Python, npm, .NET, Remotion, Manim, Office,
browser, credential, or paid-API prerequisite mentioned by task-specific skills.
Those are project/runtime dependencies and remain installed on demand in the
target project. Safe integrity tests deliberately do not publish content, send
messages, create remote issues, invoke paid APIs, or automate Office GUI.

## Verification

- `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1`: passed.
- Focused integrity tests: 10/10 passed, including missing resource, path
  containment, strict frontmatter, missing skill, profile closure, OpenAI icon,
  MCP declaration failures, and Windows PowerShell 5.1 default-path execution.
- Focused quality-gate tests: 6/6 passed, including stage order and help
  discoverability.
- `pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`: Unit 454/454
  and E2E 12/12 passed.
- `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict
  --threshold-ms 8000`: passed; the existing `apply_targets` performance
  observation remained non-blocking under the strict contract.
- `python scripts/verify-dependency-baseline.py --target-repo-root .
  --require-target-repo-baseline`: passed.
- `pwsh -NoProfile -ExecutionPolicy Bypass -File
  scripts/quality/run-local-quality-gates.ps1 -Profile full
  -AllowDirtyWorktree`: passed, including the new `skill-integrity` stage and the
  full Unit/E2E suites.
- Final projection: active profile `default`, all profile budgets pass, and
  conflicts are zero.

## Rollback

Revert this change's config, verifier, tests, override bridge, evidence, and
removed source directories together. Regenerate `skills.lock.json`, run
`build.ps1`, then run `skills.ps1 构建生效`. A partial rollback must not restore
an incomplete skill without also removing the fail-closed integrity finding,
and must not alter unrelated imports or host configuration.
