---
name: capability-router
description: Deterministic local-skill discovery and policy fallback. Invoke explicitly only when host-native visible skill metadata is insufficient, cross-directory discovery is needed, or a host-selected candidate needs policy validation. Host AI owns semantic selection; this skill never mutates host state.
---

# Global local-skill dispatch

This is an explicit discovery and policy fallback for the local skill inventory, not a normal start-of-task path. The script is deterministic and read-only; the host AI remains the only semantic selector.

## Use complete-catalog discovery only after native selection needs fallback

1. Call the script with the complete request only after the host has determined that directly visible native skill/tool metadata is insufficient, cross-directory discovery is required, or deterministic policy validation is needed. Do not invoke this fallback when a directly visible skill or native tool already matches.

   ```powershell
   $result = pwsh -NoProfile -ExecutionPolicy Bypass -File <skill-dir>/scripts/route-capability.ps1 -Query '<complete request>' -AutoDiscover -MaxCandidates 256 | ConvertFrom-Json
   $result | Select-Object retrieval,excluded,automatic_dispatch,writes_performed | ConvertTo-Json -Depth 12
   ```

   `retrieval.candidates` is the complete catalog index (name, description, path, domains, availability, and side-effect metadata). Use the complete user request and its negative constraints to select the smallest sufficient set, normally one skill and never more than three.

2. If the catalog reports `retrieval.truncated=true`, select at most two domains from `discovery_domains.name,purpose` and narrow the read-only index:

   ```powershell
   $result = pwsh -NoProfile -ExecutionPolicy Bypass -File <skill-dir>/scripts/route-capability.ps1 -Query '<complete request>' -DomainHint 'engineering,review' | ConvertFrom-Json
   [pscustomobject]@{ retrieval = $result.retrieval; excluded = $result.excluded } | ConvertTo-Json -Depth 8
   ```

   Use domain purpose only to reduce a truncated response. Respect negation such as “不要使用…”, “不要改代码”, and “only explain”. If every requested domain is unknown or no candidate directly advances the goal, continue with native reasoning.

3. Re-run the script with the host decision so deterministic policy can validate availability, containment, side effects, and activation. A domain hint is optional after `-AutoDiscover`:

   ```powershell
   $result = pwsh -NoProfile -ExecutionPolicy Bypass -File <skill-dir>/scripts/route-capability.ps1 -Query '<complete request>' -AutoDiscover -Candidate 'skill|codebase-design' -ExcludeCapability 'skill|test-driven-development' | ConvertFrom-Json
   $result | Select-Object selection_mode,selected,activation_plan,excluded,session_plan,preheat_recommendation,writes_performed | ConvertTo-Json -Depth 8
   ```

4. Follow `activation_plan`:
   - `use_active_skill` or `load_skill`: `load_allowed` authorizes only reading the selected `SKILL.md`; then apply its ordinary trigger and safety rules. It never pre-authorizes repository writes, external actions, publication, or configuration changes.
   - `use_available_mcp` or `use_available_capability`: use only the surfaced callable capability.
   - `execution_policy=approval_required`, `request_approval`, `request_mcp_activation`, or `request_activation`: keep the actual operation behind the required authorization or host activation step.
5. Reuse only items in `session_plan.reuse` whose `session_snapshot.status=current`. Verified reuse requires the caller to pass `-SessionIdentity` and a schema-v2, fresh, read-only session snapshot with the same `session_id`; every loaded skill must retain the current `SKILL.md` SHA-256. Legacy, foreign, stale, or mismatched snapshots fall back to `session_plan.load`.

Explicit `$skill`/`@skill` mentions may go directly to the named visible skill or to policy validation when needed. A normal natural-language request remains on the host-native selection path and does not automatically invoke this router. An unsigiled capability name remains ordinary natural language—even when hyphenated or namespaced—because it may appear inside a negation. The script reports `decision_owner=host_ai`, `semantic_routing_performed=false`, and never assigns semantic confidence.

## Boundaries

- Do not edit skill/MCP configuration, Codex config, plugin state, authentication, or session state.
- Do not start another model or provider call for routing; reuse the host AI already processing the request.
- Treat returned paths as local data. Only contained, existing `SKILL.md` files are eligible.
- Auto-load only skill instructions whose `load_side_effect` is `read_only`. Evaluate every action described by the loaded skill separately; only already-available `read_only`/`external_read` capabilities may execute automatically.
- Semantic judgment may narrow, exclude, or abstain, but cannot upgrade availability, auth, approval, freshness, containment, or side-effect permissions.
- If discovery fails, fall back to native reasoning without blocking an otherwise clear task.
