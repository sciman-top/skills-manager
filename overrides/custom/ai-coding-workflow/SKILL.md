---
name: ai-coding-workflow
description: Run a compact, evidence-driven coding loop for implementation and maintenance. Choose a tiny/direct, normal, or failure/high-risk path; freeze the goal and write set, use current repository facts, make the smallest source change, resume from verified stop points, run the lowest sufficient proof, and stop at the proven boundary.
---

# AI coding workflow

Use this as the default operating method for a normal coding task. It is a
compact execution contract, not a replacement for the repository's
`AGENTS.md`, project rules, host policy, or a dedicated specialist skill. It
does not change provider, model, auth, MCP, session, plugin, or host
configuration.

## Operating posture

Treat a direct request for a scoped read-only review, reversible edit, or fix
as authorization to do that work. Ask only when required input would materially
change the result or the next step is an external or irreversible write. User
instructions take precedence over this skill's guidelines; do not turn an
authorized, reversible task into an approval pause.

## 1. Choose the lightest safe path

Classify the request before editing:

- **`tiny/direct`**: one or a few explicit files, no observed failure, no
  security/data/migration/public-contract/packaging/projection risk, and no
  external write. Infer a one-sentence Goal/write set/Stop, inspect the seam,
  make the edit, and run the focused proof. Keep repository rules, dirty-tree
  protection, and required compatibility checks in force.
- **`normal`**: ordinary implementation, maintenance, or bounded refactoring.
  Use the full contract and bounded closure below.
- **`failure/high-risk`**: a concrete failing test/bug, security or data
  boundary, migration, public contract, packaging, host projection, or MCP
  change. Bind the failure or risk first and route to the appropriate
  specialist; do not let the fast path bypass causal evidence or required
  gates.

When the user says **continue** or **resume**, start from the last verified stop
point. Re-read current status, diff, the changed seam, and the latest proof;
rerun an old gate only when its inputs or environment changed. Do not restart
the whole workflow merely because the conversation resumed.

## 2. Freeze the task before touching code

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

## 3. Run the bounded closure

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

## 4. Prevent the common failures

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

## 5. Use task-fit capabilities, not model-name routing

Choose the currently available host, model, and tools by the capability
contract the task requires: reasoning depth, context size, tool/MCP support,
latency or cost, and the need for independent review. Model names and vendor
rankings are advisory and may drift; they are not workflow branches.

Never force a provider, assume a model feature, or automatically fail over to
another model. If a required capability is unavailable, report the boundary or
ask for the smallest decision that materially changes the result.

MCP is optional. Use it when the task needs current authoritative external
documentation or an explicitly authorized integration; do not invoke every
configured server merely because it is available, and do not mutate host MCP
configuration as a side effect of ordinary coding work.

Route rather than duplicating procedures:

- concrete observed failure → `systematic-debugging`
- review-only request → `code-review-and-quality`
- completion/pass claim → `verification-before-completion`
- PowerShell 7 Windows automation → `custom-powershell-windows-automation`
- invisible specialized skill with no sufficient visible match →
  `capability-router` once, as its narrow read-only fallback

When handing a task between GPT/Codex and GLM/ZCode, pass a compact task
capsule instead of the full conversation:

```text
Goal:
Current status/evidence:
Decisions already made:
Exact write set:
Minimum proof:
Stop:
```

The receiving host must re-read the current repository status and changed seam
before acting. Model name, reasoning effort, and host-specific availability
are operator choices and evidence-bound facts; never treat the capsule as
permission to switch provider, widen the write set, or skip verification.

Detailed mappings, budget observations, and the GPT/GLM rationale live in the
skills-manager repository at `docs/product/ai-coding-playbook.md`. Consult it
only when working in that repository, and load only the relevant section
rather than copying the entire reference into every task.
