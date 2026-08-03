# GPT-5.6 Skill Routing Simplification

## Scope

- Source of truth: `skills.json.skill_projection`,
  `config/skill-routing-policy.json`, and the profile benchmark corpus.
- Goal: keep the useful specialist capabilities while removing the remaining
  always-on methodology chain from the `coding-strict` profile.
- Existing dirty files (`AGENTS.md`, `CLAUDE.md`, and four import gitlinks) are
  outside this change and must not be reverted by this slice.

## Evidence And Decision

- OpenAI's current Codex documentation says skills should be focused on one
  repeatable job, use progressive disclosure, and prefer instructions over
  scripts unless deterministic behavior is required. Codex native Plan, Goal,
  Review, worktree, and subagent controls remain the ordinary orchestration
  layer.
- `mindfold-ai/trellis` documents a task-state/PRD/verification system with
  auto-invoked skills and subagents. This repository already has project
  rules, task documents, change evidence, tests, locks, and quality gates, so
  installing Trellis would create a competing control plane without a proven
  gap.
- `obra/superpowers` explicitly defines a mandatory multi-stage bootstrap.
  Its narrow debugging and completion-verification skills remain useful, but
  the umbrella bootstrap, mandatory plans, automatic delegation, and forced
  worktrees are not retained in any resident profile.
- `mattpocock/skills` presents small, composable skills. Its
  `grill-with-docs` remains reachable in `engineering` and is now added to
  `coding-strict` for explicit, high-stakes design or current-documentation
  work.

## Changes

- `coding-strict` is now an evidence-focused profile. It contains the lean
  coding safeguards plus TDD, domain modeling, `grill-with-docs`, and the
  latter's declared `grilling` dependency.
- Removed `using-superpowers`, brainstorming, plan execution, finish/commit
  workflow, automatic delegation, code-review request, and worktree skills
  from `coding-strict`.
- Updated prompt probes and the 12-case benchmark corpus to prove that no
  strict scenario requires `using-superpowers`; `grill-with-docs` remains
  available for explicit invocation in that profile rather than being treated
  as an implicit model-selection expectation.
- No Trellis package was installed. No vendor, imported skill directory,
  system skill, plugin cache, model/provider/auth setting, or non-MCP host
  configuration was deleted or edited.
- The fixed dependency gate exposed a pre-existing repository contradiction:
  commit `3e2edc7e` removed the old governed-runtime baseline while AGENTS, CI,
  the verifier, and the full gate still require it. A repo-owned baseline with
  `owner_runtime=skills-manager-local-quality-gates` restores the contract
  without restoring the retired prompt/recommendation assets or the former
  central-runtime ownership.

## Verification And Rollback

- Focused projection and benchmark tests, profile dry-run, managed projection,
  fresh-profile probes, and the repository full gate must pass before closeout.
- Focused projection/benchmark tests: `31/31` passed.
- Full quality gate: exit `0`; skill integrity `103`, routing
  `profile=default, active=11, external=12, findings=0`, Unit/E2E all passed,
  and `Local quality gates passed (full)`.
- Managed projection: exit `0`; `entries=107`, `unique=107`,
  `disabled=96`, `conflicts=0`, active profile restored to `default`.
- Fresh profile probes: all 16 profiles passed. `coding-strict` passed with
  `active=14`, `metadata=7121/10000`; `grill-with-docs` and `grilling` were
  verified through the projection manifest because Codex may omit them from
  the initial 2% skill metadata list under progressive disclosure.
- Read-only GPT-5.6 benchmark report:
  `artifacts/skill-profile-benchmark/20260801-120514-809/report.json`.
  Both profiles passed `12/12` expectations. `coding` used 281284 input and
  2446 output tokens in 150675 ms; `coding-strict` used 283604 input and 2058
  output tokens in 135664 ms. Both used one delegation and one worktree.
- Rollback: restore the previous `coding-strict.enabled_names`, benchmark
  expectations, prompt probes, and documentation; rebuild and run
  `构建生效`. Do not revert the pre-existing AGENTS/CLAUDE/import changes.

## Sources

- OpenAI Codex manual, `Best practices` and `Build skills`, refreshed on
  2026-08-01.
- `https://github.com/mindfold-ai/trellis` README, read 2026-08-01.
- `https://github.com/obra/superpowers` README, read 2026-08-01.
- `https://github.com/mattpocock/skills` README, read 2026-08-01.
