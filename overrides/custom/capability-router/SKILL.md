---
name: capability-router
description: Find an explicitly named skill missing from visible skills, or a specialist workflow absent from them; validate its exact dependency closure before loading. Use for implicit specialist requests too, including evidence-based design interviews. Not a routine preflight.
---

# Capability router

This is a narrow fallback, not a normal task preflight and not a second semantic router.
Do not use as a normal preflight. Treat metadata as insufficient when a request combines an interactive workflow verb with evidence grounding that no single visible skill covers.

## Cold discovery

Use only in either of these cases:

- the user explicitly names a local skill that is absent from the current visible
  metadata; or
- the host has determined that no visible native skill is a sufficient semantic
  match for the complete request.

The second case is a bounded fallback, not a blanket preflight. Pass the
complete request and one or two host-chosen domain hints whenever the request
is not an exact invisible skill name. The router retrieves descriptions; the
host still makes the semantic choice from that small candidate set. For an
explicitly named invisible skill, validate that exact candidate instead of
declaring it unavailable before checking the cold catalog.

Do not pretend that ordinary language has a reliable binary “skill request”
classifier. A quoted name, a discussion of a skill, or an ambiguous task is
not an invocation. If the host is uncertain and can complete the request with
ordinary reasoning or a visible skill, do that instead of cold discovery. The
only permitted implicit trigger is a high-confidence conclusion that visible
capabilities are insufficient and a specialized workflow is materially needed.
The router's read-only retrieval is deliberately separated from semantic
selection so a false positive cannot load or execute a cold skill.

A request that anchors on unstated content ("this plan", “这个方案”, “这个请求”)
has no actionable target when neither the conversation nor the repository
context supplies one. Stop and ask the user for the target (the
`parent_user_input` branch) before any discovery, validation, or skill
loading. Inventing a substitute task to route around the missing payload is
fail-open on an unknown target, not routing.

A subagent's Skill tool can report a same-name skill from the dual user roots
(`~/.zcode/skills` and `~/.agents/skills`) as ambiguous, and the namespaced
form may not be subagent-callable (observed on ZCode 2026-10-24). That is a
known host-surface shape, not an unavailable router: read this SKILL.md and
invoke the script form below directly.

Bash tool (Git Bash on Windows, the usual Claude shell). Pass one or two
functional domains as a literal comma-separated token, and single-quote the
request so a `$skill-name` inside it is not expanded:

```bash
pwsh -NoProfile -File <skill-dir>/scripts/route-capability.ps1 -Query '<complete request>' -AutoDiscover -DomainHint decision,engineering
```

PowerShell (one or two functional domains, not task keywords):

```powershell
$result = pwsh -NoProfile -File <skill-dir>/scripts/route-capability.ps1 -Query '<complete request>' -AutoDiscover -DomainHint decision,engineering | ConvertFrom-Json
$result.retrieval.candidates
```

Do not paste a PowerShell `$variable` into a Bash command. An unset
`$domainHints` leaves `-DomainHint` without a value, so `pwsh` exits with a
parameter-binding error before the router runs (exit 1, no JSON). That is a
binding failure, not a semantic miss and not an empty catalog: correct the
argument and run the same single discovery once. Do not treat it as
"cold discovery unavailable".

Prefer PowerShell 7 with `-File` from either shell. An interactive `cmd.exe`
session can still break `-File` quoting when `-Query` contains spaces or
non-ASCII text under a legacy console code page; a `cmd.exe /c` child spawned
from pwsh passes Unicode arguments through intact (observed 2026-10-24). If
the host shell is an interactive `cmd.exe`, pass the whole invocation through
`pwsh -NoProfile -Command "& { ... }"` or `-EncodedCommand`, and treat a
non-zero exit as "the router did not run" rather than as an empty catalog.

The router writes a pure-ASCII JSON document: every non-ASCII character in a
skill description is emitted as a `\uXXXX` escape. Keep the plain
`| ConvertFrom-Json` form. A host decodes a child process's stdout with its own
console code page (gb2312/GBK on a zh-CN Windows host), so a raw UTF-8 body
containing a non-ASCII description was mis-decoded and made `ConvertFrom-Json`
throw; the host then silently concluded cold discovery was unavailable. ASCII
output survives any code page and `ConvertFrom-Json` reconstructs the original
text. Do not "fix" a parse error by pre-setting `[Console]::OutputEncoding` in
the parent or by re-encoding the payload — a parse error now means the router
did not run, not that the transport is broken.

Use functional domains, not arbitrary task keywords: `decision`, `engineering`,
`coding`, `frontend`, `design`, `writing`, `content`, `presentation`, `diagram`,
`animation`, `mcp`, `dotnet`, `python`, `browser`, `database`, `review`, `general`,
or `skill-management`. Existing specialist domains such as `ppt`, `physics`, and
`coding-strict` remain available. The default maximum is 12 and applies only to
unscoped discovery: if that candidate set exceeds the limit, the router returns
`domain_hint_required` with no arbitrary alphabetical subset. A hinted set is
returned whole, never truncated, even when one or two hinted domains together
exceed 12 (for example `coding,engineering`); the host's hints bound it by
catalog membership. An explicit candidate may still be validated without a
domain hint. Do not retry as middleware. Refine the host's
single discovery decision only when its original semantic conclusion supports
a narrower domain; otherwise return to ordinary reasoning. The host AI selects
the smallest sufficient candidate set from names, descriptions, and the
complete user request.

A domain hint filters the catalog; a valid but semantically wrong hint can
return only unrelated candidates and cannot self-correct. Map by capability,
not by the nearest word: domain-driven/domain modeling, bounded contexts,
entities, aggregates, and invariants map to `engineering` (add `decision` only
when the request also evaluates a decision), not `design`. Reserve `design`
for visual, UX, art-direction, and similar presentation work.

## Deterministic validation

Validate a host-selected candidate before loading it:

```powershell
$result = pwsh -NoProfile -File <skill-dir>/scripts/route-capability.ps1 -Query '<complete request>' -AutoDiscover -Candidate 'skill|codebase-design' | ConvertFrom-Json
$result.load_validation
$result.execution_authorization
```

Load validation checks catalog schema/fingerprint, catalog-root containment,
the `SKILL.md` entrypoint hash, the package hash for package-local resources,
availability, and the selected skill's declared dependency closure. A passing
`load_validation` authorizes reading only that validated closure.
`execution_authorization.status` is always `not_granted`; the host
must separately review every closure member's declared workflow side effect and
apply ordinary approval, sandbox, MCP, and external-write controls.

Every response also includes a read-only `routing_receipt`. It contains a SHA-256 of the query rather than the raw request, catalog fingerprint, requested and validated candidate names, status, and `truth_boundary`. Use it to record `candidate_discovery_only`, `candidate_load_validated`, or `candidate_discovery_blocked`; it never proves host loading, invocation, model routing, or live acceptance. An explicitly named candidate that the catalog cannot validate reports `status=blocked` and `truth_boundary=candidate_discovery_blocked` with `excluded[].reason=not_available` — never `candidate_discovery_only`, which would read as success while `selected` is empty.

Receipt schema 2 separates "the router ran" from "what it found", because the historical failure was a host that read an unsuccessful invocation as an empty catalog. `transport_ok` is `true` only in a document the router actually emitted; when the router cannot finish it still writes a document with `transport_ok=false`, `status=router_not_run`, `truth_boundary=router_not_run`, and a `not_run_reason`/`not_run_detail` pair, and exits non-zero. Never treat a missing or unparseable document as "no candidate": that is `router_not_run`, not a semantic miss. `invocation_source` records which trigger the host used (`explicit_named`, `implicit_insufficient`, or `unspecified`) via `-InvocationSource`; the router does not infer it, and the two triggers fail differently, so pass it whenever the reason is known. A binding failure that never reaches the router (an unset variable leaving `-DomainHint` empty, a `cmd.exe` quoting break) emits no document at all and must be retried once with corrected arguments, not reported as unavailable.

Catalog staleness is scoped, not a global outage: when `catalog.status=stale`, the drifted or missing skill is named in `excluded[]` (`catalog_stale`, `package_stale`, or `entrypoint_unavailable`), and any other candidate whose own entrypoint/package hashes validate still discovers and validates normally. Only drift of the selected candidate or inside its dependency closure blocks that candidate. A structurally invalid catalog (`catalog.status=invalid`, e.g. fingerprint mismatch or unsupported schema) blocks all discovery and validation until the catalog is regenerated. If no catalog entrypoint validates beside the running router — the copied-package shape, where the router itself is the only surviving entry, counts here — the response adds `catalog.diagnostics[].code=catalog_projection_incomplete`, sets the routing receipt to `status=blocked` and `truth_boundary=candidate_discovery_blocked`, and points recovery to rebuilding the managed projection or pinning the managed catalog with `SKILLS_MANAGER_CAPABILITY_CATALOG`/`-CatalogPath`. This is the expected result for a copied router package without its catalog-referenced sibling skills.

## Host selection and execution

Loading and execution are separate decisions. A passing `load_validation`
authorizes reading only the exact `validated_closure`; it never authorizes
editing, external writes, or spawning a child. The router does not name,
configure, rank, or select a model, effort, or agent.

The current host owns execution. Continue in the parent, or delegate under the
user's current request and applicable instructions, using only an agent and
model that the host already offers. Do not depend on a repository-defined
agent name or old projection receipt. If a host-native child is used, pass the
complete request and exact validated closure without unrelated parent history,
and verify its actual tool events rather than assuming that a receipt proves
loading. Model and effort inherit the host's current defaults unless the user
explicitly chooses another supported value.

For an interactive or evidence-grounded workflow, preserve every user question
and wait point. A child answer is never an attributable human decision. Apply
the user's exact scope, write set, proof, and stop condition directly; do not
invent an admission engine or delegate missing authority.

When a matching native skill/tool is already visible, use it directly. Never
use the router as automatic middleware or make every natural-language request
cold-discover skills.

## Boundaries

- Do not invoke when a visible native skill/tool already matches.
- Do not rank semantics, switch profiles, preheat capabilities, manage sessions, or edit host/plugin/MCP/config state.
- Treat stale, missing, or escaping paths as unavailable.
- Treat malformed catalogs, unsupported schemas, duplicate identities, unknown domains, dangling memberships, and invalid hashes as structured fail-closed results.
- If discovery fails and the task is otherwise clear, continue with native reasoning.
- `decision_owner=host_ai`, `semantic_routing_performed=false`, and all router operations remain read-only.
