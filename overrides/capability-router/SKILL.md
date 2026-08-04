---
name: capability-router
description: Mandatory read-only cold discovery when no visible skill or native tool matches architecture/domain, coding/test, existing marketing-copy or document editing, MCP/database, or migration work. Skip factual Q&A, translation, math, read-only existing-code explanation without change/diagnosis/review, and requests already covered by visible capabilities; host AI owns semantic selection.
---

# Native-First Hierarchical Capability Discovery

Prefer the host's native skill and tool selection. This compatibility skill no longer classifies natural language or decides which capability is semantically correct.

## Discover and apply policy

1. If a currently visible skill or native tool clearly matches the complete request, use it directly and do not run the fallback script.
2. Otherwise call the script once without a hint and project only `discovery_domains.name,purpose`. Use the complete request to choose at most two capability domains; do not search repository source or configuration and do not infer opaque profile names.

   ```powershell
   $catalog = pwsh -NoProfile -ExecutionPolicy Bypass -File <skill-dir>/scripts/route-capability.ps1 -Query '<complete request>' | ConvertFrom-Json
   $catalog.discovery_domains | Select-Object name,purpose
   ```

3. Discover inside those domains and project only the retrieval result plus deterministic exclusions:

   ```powershell
   $result = pwsh -NoProfile -ExecutionPolicy Bypass -File <skill-dir>/scripts/route-capability.ps1 -Query '<complete request>' -DomainHint 'engineering,review' | ConvertFrom-Json
   [pscustomobject]@{ retrieval = $result.retrieval; excluded = $result.excluded } | ConvertTo-Json -Depth 8
   ```

   Use the complete request—not lexical scores—to choose the smallest sufficient set, normally one capability and never more than three. Respect negation such as “不要使用…”, “不要改代码”, and “only explain”. If `retrieval.truncated=true`, refine to one valid domain instead of guessing from the partial list. If every requested domain is unknown or no candidate directly advances the goal, continue with native reasoning.
4. Re-run the script with the host decision so deterministic policy can validate availability, containment, side effects, and activation:

   ```powershell
   $result = pwsh -NoProfile -ExecutionPolicy Bypass -File <skill-dir>/scripts/route-capability.ps1 -Query '<complete request>' -DomainHint engineering -Candidate 'skill|codebase-design' -ExcludeCapability 'skill|test-driven-development' | ConvertFrom-Json
   $result | Select-Object selection_mode,selected,activation_plan,excluded,session_plan,preheat_recommendation,writes_performed | ConvertTo-Json -Depth 8
   ```

5. Follow `activation_plan`:
   - `use_active_skill` or `load_skill`: `load_allowed` authorizes only reading the selected `SKILL.md`; then apply its ordinary trigger and safety rules. It never pre-authorizes repository writes, external actions, publication, or configuration changes.
   - `use_available_mcp` or `use_available_capability`: use only the surfaced callable capability.
   - `execution_policy=approval_required`, `request_approval`, `request_mcp_activation`, or `request_activation`: keep the actual operation behind the required authorization or host activation step.
6. Reuse compatible items in `session_plan.reuse`. Domain hints are read-only index partitions, not active-profile changes. Treat `preheat_recommendation` as advice for a future task boundary; never hot-switch a profile or restart the current task.

Only explicit `$skill`/`@skill` mentions may go directly to policy validation. An unsigiled capability name remains ordinary natural language—even when hyphenated or namespaced—because it may appear inside a negation. The script reports `decision_owner=host_ai`, `semantic_routing_performed=false`, and never assigns semantic confidence.

## Boundaries

- Do not edit skill/MCP profiles, Codex config, plugin state, authentication, or session state.
- Do not start another model or provider call for routing; reuse the host AI already processing the request.
- Treat returned paths as local data. Only contained, existing `SKILL.md` files are eligible.
- Auto-load only skill instructions whose `load_side_effect` is `read_only`. Evaluate every action described by the loaded skill separately; only already-available `read_only`/`external_read` capabilities may execute automatically.
- Semantic judgment may narrow, exclude, or abstain, but cannot upgrade availability, auth, approval, freshness, containment, or side-effect permissions.
- If discovery fails, fall back to native reasoning without blocking an otherwise clear task.
