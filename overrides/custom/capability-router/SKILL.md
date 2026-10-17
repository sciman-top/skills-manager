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

Prefer PowerShell 7 with `-File` from either shell. Under `cmd.exe /c`, the
`-File` form breaks on quoting when `-Query` contains spaces or non-ASCII
text. If the host shell is `cmd.exe`, pass the whole invocation through
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
`animation`, `mcp`, `dotnet`, `python`, `browser`, `database`, `review`, or
`skill-management`. Existing specialist domains such as `ppt`, `physics`, and
`coding-strict` remain available. The default maximum is 12. If the unscoped
discovery candidate set exceeds that limit, the router returns
`domain_hint_required` with no arbitrary alphabetical subset; an explicit
candidate may still be validated
without a domain hint. Do not retry as middleware. Refine the host's
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

Catalog staleness is scoped, not a global outage: when `catalog.status=stale`, the drifted or missing skill is named in `excluded[]` (`catalog_stale`, `package_stale`, or `entrypoint_unavailable`), and any other candidate whose own entrypoint/package hashes validate still discovers and validates normally. Only drift of the selected candidate or inside its dependency closure blocks that candidate. A structurally invalid catalog (`catalog.status=invalid`, e.g. fingerprint mismatch or unsupported schema) blocks all discovery and validation until the catalog is regenerated. If every catalog entrypoint is unavailable, the response adds `catalog.diagnostics[].code=catalog_projection_incomplete`, sets the routing receipt to `status=blocked` and `truth_boundary=candidate_discovery_blocked`, and points recovery to rebuilding the managed projection or pinning the managed catalog with `SKILLS_MANAGER_CAPABILITY_CATALOG`/`-CatalogPath`. This is the expected result for a copied router package without its catalog-referenced sibling skills.

## Native cold-capability handoff

Before constructing admission/plan or handoff files, compare the selected
execution contract with this session's actual delegation permissions and
available agent types. An explicit no-delegation mode or pinned-slot policy
that excludes the required specialist is a concrete incompatibility: report
it without preparing artifacts, spawning a substitute, changing models, or
weakening an interactive contract. This is distinct from a host lacking a
native spawn tool. A configured role or old projection receipt does not prove
its model is currently available; after an explicit model-unavailable error,
do not retry the same role. Use parent execution only when the selected
contract and current instructions permit it; otherwise report the blocker.

For `host_admission_required`, loading and execution are separate decisions.
Read only the validated closure first. The catalog's `unknown` describes an
unclassified workflow, not missing user permission. Inspect the actual skill
instructions, identify the concrete operation, and apply the current user's
scope, permissions, exact write set, proof and stop. If those already authorize
the operation, continue in the parent; do not ask again merely because the
catalog lacks a specialist bridge contract. If the operation remains unknown,
the target is missing, or a needed external action is unauthorized, stop for
that specific missing input. Do not relabel the catalog or fabricate a runner
admission. Report this path as `parent_mediated`; it is not native runner
execution. A skill requiring a multi-turn decision must preserve its questions
and wait points; never replace it with a one-shot summary.

For a multi-turn decision, the parent persists the admission and plan objects
(for example with `ConvertTo-Json -Depth 60`) into a run directory such as
`artifacts/work/cold-routing/<run-id>/` before the first child spawn. That path
is git-ignored; never use `%TEMP%` or a tracked path, because a run file outside
the repository cannot be named in an admission read set. Persist each successor
the same way. `New-ExecutionAdmissionSuccessor` reuses the predecessor's
allowed_read_set, and a successor file cannot be hashed into the admission it
produces, so the child cannot check a successor's content by reading the file.
Send the child the complete successor bridge payload inline (the canonical
`New-ExecutionAdmissionBridgePayload` output, with the successor admission and
plan), not identifiers alone: a live child rejected an ID-only continuation
because it could not check the constraints that still bind the successor. The
child checks those constraints in the payload it was given and cannot recompute
hashes without a shell; the parent's revalidation remains the content check
for the file. Each later answer needs
`New-ExecutionAdmissionSuccessor` built from the exact persisted predecessor,
with a new attempt identity and a later `issued_at`. Pass `-AnswerProvenance`
as `human_verbatim_answer`. `authorized_ai_delegate_answer` is not accepted for a
multi-turn interview: a delegate answer may only test the continuation mechanism
and never counts as a user answer. The successor records the provenance and the
evidence hash; a child refuses an answer whose provenance is absent. A predecessor that existed
only in a finished PowerShell process cannot be rebuilt, so do not forward an
answer to the same child without a successor; restart with a new root admission
and say so in the report, rather than forging a continuation.

For independently bounded work, prefer an available host-native subagent when
the user or applicable instructions authorize delegation. Pass the exact
validated closure and task scope. Do not assume a named custom agent exists
on another host: use that host's available native agent under the same task
contract, or execute in the parent and report the actual surface. Model and
effort choices use only the current host's supported tool/schema values;
inherit defaults when no task-specific choice is justified.

When a matching native skill/tool is already visible, use it directly and do
not involve this router or a bridge. Otherwise, the host may hand one exact
candidate to the native `cold-capability-runner` subagent only when this
router has returned all of the following for the same request:

- `load_validation.pass=true`;
- `routing_receipt.truth_boundary=candidate_load_validated`;
- one selected candidate plus its `validated_closure`, with validated paths and
  declared side effects for every member.

Start the named specialist without inherited parent history. On Codex, set
`fork_turns="none"` (or a positive number only when that specific history is
necessary); never omit `fork_turns` or use `"all"` with a nondefault
`agent_type`, because full-history forks inherit the parent model and context.
On Claude, dispatch through the Agent tool with `subagent_type` set to the
contract's `native_agent`; a fresh Agent call carries no parent history. A child
that reports no `spawn_agent` tool on Claude is looking for the Codex name:
use the Agent tool instead. In both hosts, put the complete admission and
validated closure in the child message so isolation does not discard required
inputs. Verify the actual spawn arguments and child events; a receipt alone
cannot prove isolation or the model and effort that executed the task.

For a supported specialist bridge contract, pass the complete validation result, original request, exact selected name, and
an admission contract to the child. Once those conditions hold, dispatching to
the contract's `native_agent` is the execution path, not an option: construct
the admission (original request, complete validation result, the single
selected name, `requested_operation`, an empty or exact write set, minimum
proof, and stop condition) and hand it to the child. The router's `not_granted`
is permanent by design and is upgraded only by this parent-side admission,
never by the router. When the host has no compatible native spawn tool, fall back to
parent-mediated execution and record it as parent-mediated - never as a runner
execution. The child must not treat validation as execution authorization. The
result and receipt carry the effective `execution_contract` of the **selected
root**. A dependency entry is a supporting read-only input in that admission;
its own contract is not priority-merged into the root and cannot silently
select a second adapter. To execute a dependency independently, select it as
a new root and create a separate admission. The host must preserve the root
contract: `one_shot` may use `cold-capability-runner`;
`parent_user_input` must stop for parent-mediated user input; and
`multi_turn_user_decision` must use `design-griller`, relay exactly one
question to the user, and wait for that answer before resuming the same child.
Never send an interactive contract to `cold-capability-runner` with a request
for a summary or final conclusion. A read-only admission may execute a bounded
read-only subset even when a skill's maximum declared side effect is
`controlled_write`; it must never write. A `controlled_write` admission
additionally records the user's implementation request, exact write set,
minimum proof, and stop condition. For `external_read`, `unknown`, ambiguity,
a missing execution contract, or any request to alter host/session/profile state, return an admission request to the parent instead. Never use the bridge as automatic middleware or make every natural-language request cold-discover skills.

The specialist bridge uses the generated `scripts/execution-admission.ps1`
beside this router script. Dot-source that file after router package validation;
it contains the deterministic helpers and needs no repository source import.
Keep `RepoRoot` set to the current
task repository and `SkillRoot` set to the reviewed physical skill supply root
for creation, revalidation and continuation. `AllowedReadSet` lists exact task
inputs under `RepoRoot`; the validated closure separately carries the skill
files under `SkillRoot`. A consumer project does not need `skills.json`.

```powershell
. <skill-dir>/scripts/execution-admission.ps1
$admission = New-ExecutionAdmission -OriginalRequest $request -AdmittedGoal $goal -Validation $result -AllowedReadSet $taskFiles -AuthorityBasis 'current_user_request' -IssuedAt ([datetimeoffset]::UtcNow.ToString('o')) -RepoRoot $taskRoot -SkillRoot $supplyRoot
$plan = New-ExecutionPlan -Admission $admission
$check = Test-ExecutionAdmissionRevalidation -Admission $admission -Plan $plan -Validation $result -RepoRoot $taskRoot -SkillRoot $supplyRoot
```

For an authorized one-shot implementation, creation additionally takes
`-RequestedOperation controlled_write -ExactWriteSet $files -MinimumProof $proof`.
Revalidation checks existing-file hashes and absence of new files before spawn.
For controlled writes, include this generated helper's exact physical path and
SHA-256 in the child handoff as an additional read-only input. The child must
verify that helper hash and execute `Test-ExecutionAdmissionRevalidation` with
the original admission, plan, validation and roots immediately before writing.
The parent check does not replace this child check. Record its actual tool
result bound to the admission id; never infer it from the child's final prose.
Create one canonical bridge payload with
`New-ExecutionAdmissionBridgePayload -OriginalRequest $request -Admission $admission -Plan $plan -Validation $result -RepoRoot $taskRoot -SkillRoot $supplyRoot`.
This helper revalidates the admission and returns the original request,
`validated_skill_name`, validated path, complete validation and dependency
closure, effective root execution contract, admission, plan and both roots.
Do not hand-build parallel child fields or rename `validated_skill_name`.

For file transport, deliver that payload with `Export-ExecutionAdmissionHandoff`
into a unique file in the authorized run directory (create that directory
before admission), passing the same `-OriginalRequest`, `-RepoRoot` and
`-SkillRoot` used above. The handoff path must be a new file inside `RepoRoot`
that is outside the task's read and write sets; a path outside `RepoRoot` fails
closed as a write-set violation. This parent-owned transport file is separate
from the child's task write set. Pass the returned path, SHA-256 and admission
id, plus helper path/hash and both roots, explicitly in the child message, with
no inherited history (Codex `fork_turns="none"`; on Claude, a fresh Agent call).
If inline transport is required, serialize the returned
object with `ConvertTo-Json -Depth 60 -Compress` and place the complete JSON
under one `bridge_payload` field in the child message; never abbreviate, omit,
or hand-reconstruct fields. Do not rely on history inheritance or truncated
terminal output. With file transport, the child verifies the helper hash,
dot-sources it and calls `Import-ExecutionAdmissionHandoff -Path $path -Sha256
$hash -AdmissionId $id -RepoRoot $root`; Import verifies exact bytes, identity
and current snapshots. With inline transport, the child binds the fields from
`bridge_payload` directly. Both paths bind every execution field, including
`$validatedSkillName = $bridgePayload.validated_skill_name`; an absent or
mismatched field stops before reading or invoking the skill. The child must
still execute the explicit write-time revalidation immediately before mutation.
Never dispatch when `$check.pass` is false. These are parent-side checks, not
an OS sandbox; actual tools must still enforce the task's write boundary.

## Boundaries

- Do not invoke when a visible native skill/tool already matches.
- Do not rank semantics, switch profiles, preheat capabilities, manage sessions, or edit host/plugin/MCP/config state.
- Treat stale, missing, or escaping paths as unavailable.
- Treat malformed catalogs, unsupported schemas, duplicate identities, unknown domains, dangling memberships, and invalid hashes as structured fail-closed results.
- If discovery fails and the task is otherwise clear, continue with native reasoning.
- `decision_owner=host_ai`, `semantic_routing_performed=false`, and all router operations remain read-only.
