---
name: capability-router
description: Global local-skill dispatcher. Before responding to any non-trivial user request that could benefit from a local skill, run this dispatcher once—even when a visible skill appears to match—so the host AI can choose from the complete portable catalog without a profile switch. Skip only trivial factual, translation, or math requests with no skill workflow; host AI owns semantic selection.
---

# Global local-skill dispatch

This is the resident dispatch boundary for the local skill inventory. It is part of the normal start-of-task path, not an optional fallback and not a profile selector. The script is deterministic and read-only; the host AI remains the only semantic selector.

## Start every non-trivial task with the complete catalog

1. Unless the request is a trivial factual, translation, or math answer with no skill workflow, call the script once with the complete request and the full portable catalog. Do not ask the user to choose a profile and do not omit this call merely because a resident skill looks like a match.

   ```powershell
   $result = pwsh -NoProfile -ExecutionPolicy Bypass -File <skill-dir>/scripts/route-capability.ps1 -Query '<complete request>' -AutoDiscover -MaxCandidates 256 | ConvertFrom-Json
   $result | Select-Object retrieval,excluded,automatic_dispatch,writes_performed | ConvertTo-Json -Depth 12
   ```

   `retrieval.candidates` is the complete catalog index (name, description, path, domains, availability, and side-effect metadata). Use the complete user request and its negative constraints to select the smallest sufficient set, normally one skill and never more than three. Do not infer a profile name and do not modify `active_profile`.

2. If the catalog reports `retrieval.truncated=true`, select at most two domains from `discovery_domains.name,purpose` and narrow the read-only index:

   ```powershell
   $result = pwsh -NoProfile -ExecutionPolicy Bypass -File <skill-dir>/scripts/route-capability.ps1 -Query '<complete request>' -DomainHint 'engineering,review' | ConvertFrom-Json
   [pscustomobject]@{ retrieval = $result.retrieval; excluded = $result.excluded } | ConvertTo-Json -Depth 8
   ```

   Use domain purpose only to reduce a truncated response; never treat a domain as an active profile or switch the profile. Respect negation such as “不要使用…”, “不要改代码”, and “only explain”. If every requested domain is unknown or no candidate directly advances the goal, continue with native reasoning.

3. Re-run the script with the host decision so deterministic policy can validate availability, containment, side effects, and activation. A domain hint is optional after `-AutoDiscover`; it is not a profile mutation:

   ```powershell
   $result = pwsh -NoProfile -ExecutionPolicy Bypass -File <skill-dir>/scripts/route-capability.ps1 -Query '<complete request>' -AutoDiscover -Candidate 'skill|codebase-design' -ExcludeCapability 'skill|test-driven-development' | ConvertFrom-Json
   $result | Select-Object selection_mode,selected,activation_plan,excluded,session_plan,preheat_recommendation,writes_performed | ConvertTo-Json -Depth 8
   ```

4. Follow `activation_plan`:
   - `use_active_skill` or `load_skill`: `load_allowed` authorizes only reading the selected `SKILL.md`; then apply its ordinary trigger and safety rules. It never pre-authorizes repository writes, external actions, publication, or configuration changes.
   - `use_available_mcp` or `use_available_capability`: use only the surfaced callable capability.
   - `execution_policy=approval_required`, `request_approval`, `request_mcp_activation`, or `request_activation`: keep the actual operation behind the required authorization or host activation step.
5. Reuse only items in `session_plan.reuse` whose `session_snapshot.status=current`. Verified reuse requires the caller to pass `-SessionIdentity` and a schema-v2, fresh, read-only session snapshot with the same `session_id`; every loaded skill must retain the current `SKILL.md` SHA-256. Legacy, foreign, stale, or mismatched snapshots fall back to `session_plan.load`. Domain hints are read-only index partitions, not active-profile changes. Treat `preheat_recommendation` as advice for a future task boundary; never hot-switch a profile or restart the current task.

Explicit `$skill`/`@skill` mentions may go directly to policy validation, but a normal natural-language request still goes through the complete-catalog dispatch first. An unsigiled capability name remains ordinary natural language—even when hyphenated or namespaced—because it may appear inside a negation. The script reports `decision_owner=host_ai`, `semantic_routing_performed=false`, and never assigns semantic confidence.

## Boundaries

- Do not edit skill/MCP profiles, Codex config, plugin state, authentication, or session state.
- Do not start another model or provider call for routing; reuse the host AI already processing the request.
- Treat returned paths as local data. Only contained, existing `SKILL.md` files are eligible.
- Auto-load only skill instructions whose `load_side_effect` is `read_only`. Evaluate every action described by the loaded skill separately; only already-available `read_only`/`external_read` capabilities may execute automatically.
- Semantic judgment may narrow, exclude, or abstain, but cannot upgrade availability, auth, approval, freshness, containment, or side-effect permissions.
- If discovery fails, fall back to native reasoning without blocking an otherwise clear task.
