# Skill Profile Budget And Routing Design

## Goal

Keep installed skills as a reusable catalog while ensuring every runtime profile
stays below a realistic metadata budget and every intentionally retained,
high-value skill is reachable through at least one task profile.

## Decisions

- Raise the configured metadata limit from 8000 to 10000 characters. This is a
  repository policy change, not a change to Codex system or plugin files.
- Raise the external metadata reserve from 1700 to 3500 characters. The live
  enabled-plugin inventory currently contributes 2845 characters, so the old
  reserve no longer protected profiles from plugin growth.
- Keep `default` focused and do not bulk-enable installed skills.
- Keep 10000 as the global hard ceiling, but cap `default` and `coding` at
  7500 so routine profiles fail closed before they can silently re-expand.
- Add `python`, `mcp`, `review`, `marketing`, and `video` profiles for useful
  skills that are currently installed but unreachable from every profile.
- Keep redundant artifact skills and broad/conflicting browser skills disabled.
  In particular, do not activate `agent-browser` while its trigger competes
  with the host Browser and Chrome plugins.
- Preserve `decision = profile_excluded` for manifest compatibility. Add
  `profile_reachability` and `available_profiles` so consumers can distinguish
  `routed_elsewhere` from `unrouted` without inferring from `skills.json`.

## Profile Boundaries

- `default`: GPT-5.6 日常入口，仅保留领域 router、故障诊断与完成验证；通用 research 通过明确任务 profile 按需加载。
- `coding`: GPT-5.6 精简编码，仅保留按问题触发的 debugging、verification、review、API 与 security 能力。
- `coding-strict`: 高证据编码档，只在 `coding` 上增加 TDD、领域建模和显式 `grill-with-docs`；不复刻 Superpowers 的 brainstorm/plan/worktree/subagent/review/finish 全链路。
- `python`: Python project setup, testing, performance, security, and review.
- `mcp`: MCP server design and CLI interaction with research and API guards.
- `review`: receiving feedback, simplifying code, migration review, and
  verification without loading the full coding workflow.
- `marketing`: content strategy, persuasive copy, editing, formatting, and
  publication asset compression.
- `video`: storyboard, Manim/Remotion planning, animation, and visualization.

## GPT-5.6 Lean Routing

- Routine profiles do not enable `using-superpowers`; conversation entry no
  longer triggers a mandatory scan-and-cascade workflow.
- Native Codex Plan, Goal, Review, worktree, and multi-agent controls are the
  default orchestration layer. Select a specialized profile before starting a
  new task when its metadata is required; a running task does not hot-load a
  newly selected profile.
- TDD remains available through `coding-strict`; worktree creation, agent
  delegation, planning, and review orchestration stay under native Codex task
  judgment and explicit user direction rather than becoming profile defaults.
- This is a routing change only. It does not delete the Superpowers vendor,
  mappings, generated skill packages, or their dependency-closure contract.

## Budget Contract

Every configured profile must pass its effective limit, where the estimate is
local active skill metadata plus the greater of live external plugin metadata
and the 3500-character reserve. The global limit remains 10000. An optional
profile limit may only lower that ceiling; `default` and `coding` use 7500.
Other profiles target at least 500 characters of headroom at the current
external inventory.

## Behavior Benchmark

- `config/codex-skill-profile-benchmark.json` contains 12 representative
  routing cases for `coding` and `coding-strict`.
- `scripts/benchmark-codex-skill-profiles.ps1` validates the corpus without
  model calls by default. `-Execute` runs ephemeral, read-only GPT-5.6 tasks,
  restores the original profile in `finally`, and writes ignored artifacts.
- The benchmark records exact selected skills, plan/delegation/worktree
  intent, input/output tokens, duration, and expectation results.
- This proves routing behavior and overhead only. It does not prove code
  correctness or regression rates; those require isolated implementation
  fixtures and repeated runs before changing the default policy again.

The 2026-07-30 run `20260730-224108-517` is historical evidence for the former
19-skill compatibility profile and is not a baseline for the current strict
profile. The updated 2026-08-01 run
`20260801-120514-809` passed all 24 expectations after strict was reduced to
the evidence-focused set. `coding` used 281284 input and 2446 output tokens in
150675 ms; `coding-strict` used 283604 input and 2058 output tokens in 135664
ms. Both profiles used one delegation and one worktree. The result supports
lean-by-default while retaining a small explicit evidence profile.

## Reference Basis

- OpenAI Codex best practices and Build Skills docs, checked 2026-07-30:
  use native Plan/Goal/Review controls, keep `AGENTS.md` practical, and create
  focused skills for repeatable workflows with representative activation tests.
- `mindfold-ai/Trellis@c143c260678f5803d4f321a7a5d5099af6acfeb3`: retain as
  a reference for cross-platform repo specs/tasks/journals; do not install
  because this repository already owns equivalent truth surfaces.
- `obra/superpowers@44c9b2d6e889982ac18c27d05a19fefe335194e1`: retain narrow
  validation skills, but reject its mandatory bootstrap and full workflow
  chain from every profile, including `coding-strict`.
- `vercel-labs/agent-skills@7c180d9044c9ae2b442b567aad4e42a28dd5ed62`,
  `mattpocock/skills@2ab958093e83e0ec752e6c1c5932da465bf23e0c`, and
  `trailofbits/skills@ca08fc8a91f64d80b00d48597907c579d0a85c6f`: adopt the
  narrow domain-trigger and progressive-disclosure pattern; do not import
  their complete catalogs into a resident profile.

## Compatibility And Rollback

- The active profile remains `default`.
- Existing profile names remain valid. `coding` is the lean GPT-5.6 path and
  `coding-strict` is the evidence-focused path; callers that need a specific
  workflow must invoke the relevant narrow skill explicitly.
- The projection manifest change is additive and keeps schema version 2.
- Rollback removes the five profiles and additive reachability fields, restores
  the two configured budget values, rebuilds `skills.ps1`, and reapplies the
  projection transactionally.

## Verification

Run the repository gate in fixed order:

1. `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1`
2. `pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`
3. `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict --threshold-ms 8000`
4. `python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline`
5. `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree`
