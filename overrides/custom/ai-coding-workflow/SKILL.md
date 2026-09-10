---
name: ai-coding-workflow
description: Run a compact, evidence-driven coding loop for normal implementation, maintenance, debugging, and review tasks. Freeze the goal and write set, use current repository facts, make the smallest source change, run the lowest sufficient proof, and stop at the proven boundary; route concrete failures, reviews, PowerShell automation, and cold-skill discovery to their dedicated skills.
---

# AI coding workflow

Use this as the default operating method for a normal coding task. It is a
compact execution contract, not a replacement for the repository's
`AGENTS.md`, project rules, host policy, or a dedicated specialist skill. It
does not change provider, model, auth, MCP, session, plugin, or host
configuration.

## 1. Freeze the task before touching code

Write or infer a short contract from the current request:

```text
Goal: the user-visible or repository outcome
Context: current repo/cwd, entrypoint, source of truth, and observed evidence
Constraints: exact write set, compatibility, secrets, dirty worktree, and side-effect limits
Success: observable behavior and the minimum command that proves it
Stop: the boundary after which no additional work is required
```

Use fresh repository evidence for facts: read the applicable `AGENTS.md`,
`git status`/diff, the real entrypoint and source/config seam, and the nearest
test or verifier. Treat old chat context, generated output, health checks, and
model claims as hints until they are current and bound to this task. If the
target is genuinely ambiguous, stop for the parent task's input; do not choose
"latest", a convenient file, or a broad repository-wide substitute.

## 2. Run the bounded closure

1. **Inspect and diagnose.** Identify the actual caller and causal seam. For an
   observed failure, bind the error, trace, and current behavior before editing.
2. **Plan narrowly.** State the smallest change, exact files, minimum proof,
   and rollback point. Skip ceremony for a trivial one-file change, but do not
   skip the contract or evidence boundary.
3. **Implement at the source.** Edit source/config/override inputs, not
   generated `skills.ps1`, `agent/`, vendor, import, or runtime receipt files.
   Preserve unrelated dirty work, secrets, and concurrent changes. Do not add a
   new abstraction, runtime state store, router, telemetry, or compatibility
   layer without a current failure, stable caller, exact write set, proof, and
   rollback.
4. **Prove the change.** Use the lowest sufficient fresh gate in this order:
   `build -> focused test -> contract/invariant -> hotspot`. For source,
   config, generated, shared projection, security, data, packaging, or public
   contract changes, include the repository-required broader gate. Always run
   `git diff --check` when files changed and inspect the final status/diff.
5. **Review and stop.** Check behavior, compatibility, security, test intent,
   generated drift, and the exact write set. Stop when the declared proof is
   green; extra cleanup, refactoring, or a new audit is not part of completion.

For the final report, distinguish these boundaries instead of compressing
them into "done": `repo_verified`, `filesystem_projected`, `host_loaded`, and
`live_accepted`. A passing test, HTTP 200, health result, synthetic replay,
static projection, or historical log cannot prove a higher boundary by itself.

## 3. Prevent the common failures

- **Scope drift / over-design:** keep Goal, exact write set, and Stop visible;
  report gaps, not style preferences. Defer work without a current failure or
  measurable acceptance need.
- **Stale context / repeated correction:** re-read the current seam after a
  meaningful change. After the same issue fails twice, use a fresh context and
  rewrite the contract; only then consider a durable rule or skill candidate.
- **Hallucinated APIs or "best" claims:** inspect the actual source and tests;
  use authoritative current documentation for unstable facts; label inference
  and do not invent parameters, model support, or tool behavior.
- **Dirty-tree and concurrency damage:** separate pre-existing and new diff;
  never reset, clean, stash, overwrite, or absorb unrelated work. Do not claim
  a clean baseline from a partial status read.
- **Generated-file edits:** make the source/config/override change, rebuild,
  then verify generated drift. A hand-edited generated file is not a fix.
- **False-green tests:** preserve the behavior contract; do not weaken a test,
  delete a failing case, or treat a test-only fixture as production acceptance.
- **Secrets and external side effects:** never print or invent credentials;
  do not mutate host/provider/auth/MCP/session state, deploy, send messages,
  or call live services unless the current request explicitly includes that
  scope and the required rollback/evidence path.

## 4. Choose the model and specialist path by task fit

GPT and GLM are complementary, not an automatic failover or routing mandate:

- Prefer GPT's stronger reasoning/review context for architecture decisions,
  ambiguous root-cause analysis, security/data boundaries, and independent
  final review.
- Prefer GLM for a clearly bounded batch, mechanical transformation, or long
  multi-step implementation after the contract and acceptance checks are
  explicit. Keep the change narrow and obtain a fresh independent review for
  consequential work.
- Do not force a provider/model, assume a current model feature, or change
  host configuration to make the split happen. Use the current host/model
  documentation and actual CLI/config evidence when a capability matters.

Route rather than duplicating procedures:

- concrete observed failure → `systematic-debugging`
- review-only request → `code-review-and-quality`
- completion/pass claim → `verification-before-completion`
- PowerShell 7 Windows automation → `custom-powershell-windows-automation`
- invisible specialized skill with no sufficient visible match →
  `capability-router` once, as its narrow read-only fallback

Detailed mappings, budget observations, and the GPT/GLM rationale live in
`docs/product/ai-coding-playbook.md`; load only the relevant section when
needed rather than copying the entire reference into every task.
