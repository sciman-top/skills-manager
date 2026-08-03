# Skill Profile Budget And Routing Evidence

## Scope And Root Cause

- Source of truth: `skills.json.skill_projection`,
  `config/skill-routing-policy.json`, and `src/Commands/SkillProjection.ps1`.
- The original failure was caused by enabled system/plugin Skill metadata growing
  beyond the old 1700-character reserve. With an 8000-character limit, the live
  projection rejected `coding=8255`, `content=8064`, and `physics=8392`.
- This change keeps 10000 as the global hard ceiling, raises the external
  reserve to 3500, and applies a lower 7500 effective ceiling to routine
  `default` and `coding`. It keeps `default` focused and routes high-value
  low-frequency skills through task profiles instead of enabling the complete
  installed catalog.
- The GPT-5.6 follow-up removes the mandatory Superpowers bootstrap and full
  development-methodology chain from routine profiles. Codex native planning,
  goal tracking, review, worktree, and agent controls are now the default.
- No Codex system Skill, Plugin cache, model/auth/provider setting, or non-MCP
  host configuration was modified. No Codex App or CLI process was restarted.

## Changes

- Added `python`, `mcp`, `review`, `marketing`, and `video` profiles.
- Reduced `default` from 16 to 6 configured skills and `coding` from 19 to 5.
- Added opt-in `coding-strict` with the former 19-skill Superpowers workflow;
  no vendor, mapping, generated skill package, or dependency closure was
  deleted.
- Removed `using-superpowers` from every routine engineering profile and made
  the development-flow router native-first instead of conversation-bootstrap
  driven.
- Removed generic `research` from `default` after the full routing gate showed
  its background-delegation workflow still matched a strong-trigger warning;
  research remains available in explicit task profiles.
- Preserved `grill-with-docs`, `grilling`, and `domain-modeling`; they remain
  installed and reachable through suitable profiles.
- Removed unreachable `agent-browser` from routing policy while Browser and
  Chrome Plugin routing remains authoritative.
- Retired the duplicate, unrouted `writing-skills` mapping. Its flattened
  projection could not satisfy upstream cross-skill references and duplicated
  the system `skill-creator` capability.
- Added additive manifest fields that distinguish `routed_elsewhere` from
  `unrouted` while retaining `decision = profile_excluded` and schema version 2.
- Added a schema-validated 12-case benchmark runner for read-only GPT-5.6
  comparisons between `coding` and `coding-strict`; benchmark artifacts remain
  ignored runtime evidence rather than generated repository state.

## Live Projection

- Active profile: `default`.
- Entries / unique names: `111 / 111`.
- Active / disabled paths / conflicts: `11 / 100 / 0`.
- Profile-routed / unrouted names: `81 / 25`.
- External Plugin Skills: `12`, live metadata `2845`, effective reserve `3500`.
- `writing-skills` is absent from both `agent/` and `~/.agents/skills`.

| Profile | Estimated | Headroom |
|---|---:|---:|
| default | 6729/7500 | 771 |
| coding | 6507/7500 | 993 |
| coding-strict | 9112/10000 | 888 |
| engineering | 7150/10000 | 2850 |
| python | 6853/10000 | 3147 |
| mcp | 6901/10000 | 3099 |
| review | 6872/10000 | 3128 |
| dotnet | 8464/10000 | 1536 |
| ppt | 7685/10000 | 2315 |
| content | 9329/10000 | 671 |
| marketing | 9334/10000 | 666 |
| physics | 9146/10000 | 854 |
| video | 8449/10000 | 1551 |
| design | 8377/10000 | 1623 |
| browser | 7261/10000 | 2739 |
| database | 7333/10000 | 2667 |

All profiles pass their effective ceiling with at least 666 characters of
current headroom. The lean `coding` profile stays below its deliberately lower
7500 ceiling; `coding-strict` retains 888 characters under the global 10000
hard ceiling.

## GPT-5.6 Routing Benchmark

The executed report is
`artifacts/skill-profile-benchmark/20260730-224108-517/report.json`. It contains
12 cases per profile, 24 successful ephemeral read-only calls in total, using
`gpt-5.6-sol` with one iteration per case.

| Metric | coding | coding-strict | Strict delta |
|---|---:|---:|---:|
| Expectation pass | 12/12 | 12/12 | same |
| Input tokens | 277907 | 286490 | +3.1% |
| Output tokens | 2330 | 4432 | +90.2% |
| Duration | 176961 ms | 255084 ms | +44.1% |
| Plans | 5 | 2 | behavioral difference |
| Delegations | 1 | 1 | same |
| Worktrees | 1 | 2 | +1 |

Both profiles met the benchmark expectations, so the result is not that strict
is functionally invalid. The measured cost supports keeping lean `coding` as
the routine GPT-5.6 route and retaining `coding-strict` as an explicit
compatibility profile. In the simple explanation case, strict selected
`using-superpowers` while lean selected no skill, demonstrating overhead on a
task that required no methodology workflow.

## Reference Basis

- OpenAI GPT-5.6 coding guidance, Codex best practices, and Build Skills
  documentation were checked on 2026-07-30. The adopted direction is native
  task judgment plus narrow, description-routed skills rather than a mandatory
  conversation bootstrap.
- `mindfold-ai/Trellis@c143c260678f5803d4f321a7a5d5099af6acfeb3` remains a
  useful structured planning reference, not a required runtime layer.
- `obra/superpowers@44c9b2d6e889982ac18c27d05a19fefe335194e1` remains
  installed and available through `coding-strict`; its universal bootstrap is
  not adopted for routine GPT-5.6 work.
- `vercel-labs/agent-skills@7c180d9044c9ae2b442b567aad4e42a28dd5ed62`,
  `mattpocock/skills@2ab958093e83e0ec752e6c1c5932da465bf23e0c`, and
  `trailofbits/skills@ca08fc8a91f64d80b00d48597907c579d0a85c6f` support the
  retained pattern: small domain capabilities, selective routing, and
  verifiable scripts instead of an always-on methodology chain.

## Verification

Fixed gate order and results:

1. `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1` -> exit 0.
2. `pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1` -> exit 0;
   Unit `501/501`, E2E `12/12`.
3. `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict --threshold-ms 8000`
   -> exit 0. It reported the non-blocking performance warning
   `apply_targets last=5439ms` against its 5000ms local threshold; `--strict`
   intentionally does not treat performance warnings as blocking.
4. `python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline`
   -> exit 0.
5. `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree`
   -> exit 0, including generated sync, Skill integrity, routing, and profile
   budget checks.
6. Real `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 构建生效`
   -> exit 0; managed projection persisted with `entries=111`, `disabled=100`,
   and `conflicts=0` without restarting Codex App or CLI.
7. `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-codex-skill-profiles.ps1`
   -> exit 0 in 361.5 seconds; fresh prompt probes passed for all 16 configured
   profiles and restored `default` in both `skills.json` and the live manifest.
8. `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/benchmark-codex-skill-profiles.ps1`
   -> exit 0; corpus/schema validation planned 24 calls without model use.
9. `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/benchmark-codex-skill-profiles.ps1 -Execute`
   -> exit 0; all 24 GPT-5.6 calls parsed and met expectations.
10. `git diff --check` -> exit 0.

The reachability regression followed red-green verification: the focused test
failed before `profile_reachability` existed, then passed after plan and
manifest persistence were implemented.

The GPT-5.6 routing regression also followed red-green verification: the two
new repository policy tests first failed against the mandatory bootstrap and
missing strict profile, then the full SkillProjection suite passed `27/27`
after the lean/strict split.

Final five-axis review found and resolved two required benchmark-runner issues:
semantic expectation failures now return exit 1 even when the model process and
JSON parsing succeed, and external corpus profile/case identifiers are checked
as safe unique file-name components before artifact creation. The focused
benchmark suite passes `4/4`, including fixtures for both failure modes. No
additional correctness, readability, architecture, security, performance, or
dead-code blocker remained after the fixes.

## Existing Dirty Worktree Boundary

The following pre-existing changes are outside this task and must not be
included in a task-only rollback: `AGENTS.md`, `imports/**`, `skills.lock.json`,
the July 17 audit evidence files, and
`docs/change-evidence/20260717-skill-profile-budget-and-mcp-refresh.md`.

The task-owned write set is `skills.json`, `config/skill-routing-policy.json`,
the two `config/codex-skill-profile-benchmark*` files,
`src/Commands/SkillProjection.ps1`, `src/Commands/Utils.ps1`, `src/Config.ps1`,
generated `skills.ps1`, `scripts/verify-codex-skill-profiles.ps1`,
`scripts/benchmark-codex-skill-profiles.ps1`,
`tests/Unit/ConfigUpdate.Tests.ps1`, `tests/Unit/SkillProjection.Tests.ps1`,
`tests/Unit/SkillProfileBenchmark.Tests.ps1`, `README.md`, the July 29
design/plan/checklist files, and this evidence file. The unrelated
`playwright-best-practices` source-path correction already present inside
`skills.json` is not part of the profile-budget decision.

## Rollback

Rollback only the task-owned lines/files: restore the two budget values, remove
the five profiles and additive reachability fields, restore routing policy and
mapping entries as required, restore the routine profile memberships, remove
`coding-strict`, rebuild `skills.ps1`, then rerun `构建生效`.
Do not restore or overwrite the existing import, lock, audit, or rule changes.

## Runtime Boundary

The managed files and live projection are updated. Newly started Codex tasks
load the refreshed `default` profile; this already-running task does not hot
reload its Skill inventory. No commit or push is part of this change.
