# Native-first runtime truth hardening

- Date: 2026-08-05
- Scope: capability-router caller snapshots, portable catalog freshness, verified session reuse, trigger terminology, deterministic routing corpus
- Truth boundary: repository implementation and local projection are in scope; provider/model/auth/profile switching, plugin/MCP installation, host restart, paid-model replay, and `live_accepted` are not.

## Decision

The target architecture is:

```text
visible matching skill or callable native tool -> direct host use
otherwise portable domain catalog -> host semantic adjudication
-> current catalog/runtime/session truth -> deterministic safety policy
-> full SKILL.md cold load or native call -> ordinary authorization and side-effect gates
```

“Seamless switching” means the host can select and cold-load a matching capability without changing the active profile. It does not mean hot-switching profiles, models, providers, authentication, sandbox, session ownership, or approval policy.

## Basis and adoption record

| Source | Current guidance used | Decision |
| --- | --- | --- |
| [OpenAI Build skills](https://learn.chatgpt.com/docs/build-skills.md) | The host first sees skill name/description, implicitly or explicitly selects a skill, and then loads the full `SKILL.md`; initial metadata has a bounded budget. | Preserve host-native semantic selection and progressive disclosure; keep the router as a fallback discovery/policy module. |
| [OpenAI Skills](https://developers.openai.com/plugins/concepts/skills) | Skills provide reusable workflow instructions; MCP provides live information, authorization, and controlled actions. | Do not make the router a second runtime, auth layer, or MCP action executor. |
| [OpenAI Agent approvals and security](https://learn.chatgpt.com/docs/agent-approvals-security.md) | Sandbox and approvals remain separate enforcement layers; side-effecting app/MCP calls retain their own gates. | `load_allowed` authorizes only instruction loading and never upgrades action permission. |
| [OpenAI Codex App Server](https://learn.chatgpt.com/docs/app-server.md) | App Server is a JSON-RPC integration surface for current client/runtime state. | Keep the adapter read-only and caller-provided; validate its envelope and freshness before consuming capability facts. |

No community source code was copied. No embedding index, lexical semantic ranker, second model call, daemon, database, schema-major migration, or current-task profile mutation was introduced.

## Changes

1. Host snapshot truth is fail-closed.
   - Require schema v2, boolean `read_only=true`, a supported producer status, coverage, source errors, and a parseable capture time.
   - Reject missing/invalid timestamps, timestamps over five minutes in the future, and snapshots older than `MaxSnapshotAgeMinutes`.
   - Report `current_complete`, `current_partial`, `stale`, `invalid`, or `not_provided`; preserve producer status, coverage, and source errors.
   - Consume coverage per capability kind. An uncovered item cannot override static truth or enter discovery/selection.
2. Portable catalog freshness is content-addressed.
   - `SkillProjection` remains the only catalog-generation seam.
   - Catalog schema v1 gains additive `catalog_fingerprint`; every skill gains `entrypoint_sha256`.
   - The portable router validates the catalog fingerprint and each live `SKILL.md` hash before reading catalog metadata. Drifted entries are excluded as `catalog_stale`.
3. Session reuse is verified instead of inferred.
   - Reuse requires schema v2, `read_only=true`, a fresh capture time, an explicit matching `SessionIdentity`, and a matching entrypoint hash for every loaded skill.
   - Legacy, foreign, stale, or drifted snapshots fall back to `session_plan.load`; they never mutate session state.
4. Active trigger text now says `portable domain-scoped cold discovery`; `cross-profile` and `profile-scoped` wording was removed from the router skill, OpenAI UI metadata, and routing policy.
5. The deterministic corpus fixture now materializes a fresh schema-v2 snapshot instead of relying on a timeless schema-v1 file.

## Verification evidence

| Stage | Evidence |
| --- | --- |
| Regression RED | Initial router/projection run: `49/57` passed and eight new runtime/catalog assertions failed. Session hardening RED: `22/24` passed; legacy reuse remained trusted and `SessionIdentity` was unsupported. Routing corpus after envelope enforcement: `26/30`, with exactly four old-fixture runtime cases rejected. |
| Focused GREEN | Router session suite `24/24`; combined router/cross-repo/projection suite `58/58`; zero skipped. |
| Routing contract | `30/30`; semantic auto-selection `0`, negative-constraint violation `0`, side-effect violation `0`, findings `0`, writes `false`. |
| Routing/integrity/config | Skill routing pass with findings `0`; skill integrity `107`, errors/warnings `0/0`; config enforce pass with the existing legacy-schema observation only. |
| Real portable probe | From `D:\`, the generated router resolved its adjacent catalog as `current`, exposed 18 engineering candidates, and reported `writes_performed=false`; catalog contains 106 entrypoint hashes. |
| Generated-state check | Agent build transaction completed with 108 skills; build-cache output fingerprint matched the current `agent/` fingerprint exactly. |
| Full local quality gate | Exit `0` in `232.1s`; Unit `833/833`, E2E `18/18`; build, repo hygiene, generated sync, skill integrity/routing, dependency baseline, skills config, host capability, planning, and doctor JSON contracts all passed. |

Git closeout is recorded in the task handoff; the full gate was not repeated after this evidence-only result update.

## Rollback

Revert only this slice's source, override, policy, fixture, verifier, tests, generated `skills.ps1`, and this evidence file; then run `build.ps1` and the normal agent build/projection transaction. Do not roll back typed-core, watch-interrupted-task, product-document, or other pre-existing/concurrent worktree changes.
