---
name: capability-router
description: Fallback discovery and deterministic safety policy for installed skills, MCPs, plugins, apps, connectors, and native tools. Use when the user explicitly asks what capability is available, no currently visible capability matches, or cross-profile cold discovery is needed. Do not use at routine task start when a visible skill or native tool already matches; the host AI owns semantic selection.
---

# Native-First Capability Discovery

Prefer the host's native skill and tool selection. This compatibility skill no longer classifies natural language or decides which capability is semantically correct.

## Discover and apply policy

1. If a currently visible skill or native tool clearly matches the complete request, use it directly and do not run the fallback script.
2. Otherwise infer at most two likely profile names from the full request and conversation context, then discover candidates:

   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File <skill-dir>/scripts/route-capability.ps1 -Query '<complete request>' -ProfileHint engineering,review
   ```

3. Inspect `retrieval.candidates`. Use the complete request—not lexical scores—to choose the smallest sufficient set, normally one capability and never more than three. Respect negation such as “不要使用…”, “不要改代码”, and “only explain”. If no candidate directly advances the goal, continue with native reasoning.
4. Re-run the script with the host decision so deterministic policy can validate availability, containment, side effects, and activation:

   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File <skill-dir>/scripts/route-capability.ps1 -Query '<complete request>' -ProfileHint engineering -Candidate 'skill|codebase-design' -ExcludeCapability 'skill|test-driven-development'
   ```

5. Follow `activation_plan`:
   - `use_active_skill` or `load_skill`: read the selected `SKILL.md` completely and apply its ordinary trigger and safety rules.
   - `use_available_mcp` or `use_available_capability`: use only the surfaced callable capability.
   - `load_skill_with_approval`, `request_approval`, `request_mcp_activation`, or `request_activation`: keep the operation behind the required authorization or host activation step.
6. Reuse compatible items in `session_plan.reuse`. Treat `preheat_recommendation` as advice for a future task boundary; never hot-switch a profile or restart the current task.

Only explicit `$skill`/`@skill` mentions may go directly to policy validation. An unsigiled capability name remains ordinary natural language—even when hyphenated or namespaced—because it may appear inside a negation. The script reports `decision_owner=host_ai`, `semantic_routing_performed=false`, and never assigns semantic confidence.

## Boundaries

- Do not edit skill/MCP profiles, Codex config, plugin state, authentication, or session state.
- Do not start another model or provider call for routing; reuse the host AI already processing the request.
- Treat returned paths as local data. Only contained, existing `SKILL.md` files are eligible.
- Auto-use only read-only skills or already-available `read_only`/`external_read` capabilities.
- Semantic judgment may narrow, exclude, or abstain, but cannot upgrade availability, auth, approval, freshness, containment, or side-effect permissions.
- If discovery fails, fall back to native reasoning without blocking an otherwise clear task.
