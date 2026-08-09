# Governance Deweight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove duplicated planning state and implementation-literal audits from the default quality chain while preserving source binding, receipts, rollback, runtime ownership, and truth-boundary protections.

**Architecture:** Structured manifests remain the only dynamic task/status truth. `tasks/plan.md` and `tasks/todo.md` become stable navigation indexes, the completed P6-specific verifier becomes an explicit historical/migration check outside the default gate, and the agent-workflow verifier checks public wiring and safety boundaries instead of mirroring behavior-test internals.

**Tech Stack:** PowerShell 7, Pester 4.10.1, JSON task manifests, Markdown governance documents, repository-local quality receipts.

## Global Constraints

- Fixed verification order remains `build -> test -> contract/invariant -> hotspot`.
- Preserve exact-source fingerprints, immutable per-run receipts, hash-bound `current.json`, repository-scoped mutex, generated sync, workspace-lock parity, dependency/config integrity, rollback receipts, reference provenance, and the `repo_verified != host_loaded != live_accepted` ladder.
- Do not add a verifier, schema, wrapper, scheduler, daemon, or second control plane.
- Do not modify generated `agent/`, runtime `reports/`, or the primary worktree's concurrent `tests/run.ps1` slice.
- The full gate runs once only after a candidate commit; afterward run only `scripts/quality/verify-current-quality-gate.ps1` and do not modify tracked source.

---

### Task 1: Replace mirrored planning state with stable indexes

**Files:**
- Modify: `tests/Unit/ProductPlanning.Tests.ps1`
- Modify: `tests/Unit/HostNativeSkillLifecyclePlanning.Tests.ps1`
- Modify: `tests/Unit/LeanAiDeliveryPlanning.Tests.ps1`
- Modify: `tests/Unit/TypedCoreShadow.Tests.ps1`
- Modify: `tests/Unit/PowerShellRuntimePolicy.Tests.ps1`
- Modify: `scripts/verify-vnext-planning.ps1`
- Modify: `scripts/verify-host-native-skill-lifecycle-planning.ps1`
- Modify: `scripts/verify-lean-ai-delivery-planning.ps1`
- Modify: `scripts/verify-typed-core-pilot-planning.ps1`
- Modify: `scripts/verify-powershell-runtime-policy.ps1`
- Modify: `tasks/plan.md`
- Modify: `tasks/todo.md`

**Interfaces:**
- Consumes: manifest fields, task DAGs, truth ladders, write sets, evidence paths, and the stable `current_phase=P6` pointer.
- Produces: plan/todo documents containing manifest links without copied task IDs, checkboxes, counts, or mutable status values.

- [ ] **Step 1: Write the failing index-only planning tests**

```powershell
$plan = Get-Content -LiteralPath (Join-Path $fixtureRoot 'tasks\plan.md') -Raw
$todo = Get-Content -LiteralPath (Join-Path $fixtureRoot 'tasks\todo.md') -Raw
$plan = $plan -replace '(?m)^.*SMV-P6-\d{3}.*(?:\r?\n)?', ''
$todo = $todo -replace '(?m)^.*SMV-P6-\d{3}.*(?:\r?\n)?', ''
$parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json
$parsed.pass | Should Be $true
```

- [ ] **Step 2: Run the focused RED tests**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Script @('tests/Unit/ProductPlanning.Tests.ps1','tests/Unit/HostNativeSkillLifecyclePlanning.Tests.ps1') -PassThru -Show Failed,Summary"`

Expected: FAIL because current verifiers require each task ID/status to be duplicated in plan/todo.

- [ ] **Step 3: Remove plan/todo coverage and status mirroring from the five verifiers**

Keep manifest identity, DAG, required execution fields, evidence, truth boundary, and runtime-policy checks. Remove only `task_plan_coverage_mismatch`, `task_todo_coverage_mismatch`, `task_todo_status_mismatch`, and equivalent plan/todo status literals.

- [ ] **Step 4: Replace plan/todo with stable manifest indexes**

The index must name the current phase and link the current P6, maintenance, pilot, typed-core, PS7, agent-workflow, routing-correction, discovery, reconciliation, and canary truth files. It must state that task IDs, counts, checkboxes, and mutable statuses are intentionally not copied.

- [ ] **Step 5: Run the focused GREEN tests**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Script @('tests/Unit/ProductPlanning.Tests.ps1','tests/Unit/HostNativeSkillLifecyclePlanning.Tests.ps1','tests/Unit/LeanAiDeliveryPlanning.Tests.ps1','tests/Unit/TypedCoreShadow.Tests.ps1','tests/Unit/PowerShellRuntimePolicy.Tests.ps1') -PassThru -Show Failed,Summary"`

Expected: all discovered tests pass and each verifier accepts the repository through manifest truth alone.

### Task 2: Retire the completed P6 verifier from the default gate

**Files:**
- Modify: `tests/Unit/QualityGateScripts.Tests.ps1`
- Modify: `scripts/quality/run-local-quality-gates.ps1`
- Modify: `docs/product/README.md`

**Interfaces:**
- Consumes: the general `planning-contract` gate and explicit historical `verify-host-native-skill-lifecycle-planning.ps1` command.
- Produces: default quick/full gate receipts with no `host-native-lifecycle-planning` stage.

- [ ] **Step 1: Write the failing default-gate composition test**

```powershell
$raw = Get-Content -LiteralPath $scriptPath -Raw
$raw | Should Not Match "Invoke-QualityGate 'host-native-lifecycle-planning'"
$raw | Should Match "Invoke-QualityGate 'planning-contract'"
```

- [ ] **Step 2: Run RED**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Script 'tests/Unit/QualityGateScripts.Tests.ps1' -PassThru -Show Failed,Summary"`

Expected: the new composition assertion fails while the completed P6 verifier remains in the default chain.

- [ ] **Step 3: Remove only the default P6 gate invocation**

Leave the verifier and focused P6 tests available for explicit historical/migration diagnostics. Update the product index to label it `historical / explicit`, not a default closeout gate.

- [ ] **Step 4: Run GREEN**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Script 'tests/Unit/QualityGateScripts.Tests.ps1' -PassThru -Show Failed,Summary"`

Expected: all discovered tests pass.

### Task 3: Replace agent-workflow literal mirroring with boundary checks

**Files:**
- Modify: `tests/Unit/AgentWorkflowAdvisoryPlanning.Tests.ps1`
- Modify: `scripts/verify-agent-workflow-advisory.ps1`

**Interfaces:**
- Consumes: manifest/schema boundaries, CLI/build wiring, host ownership, zero-side-effect output, forbidden runtime controls, pure-layer rules, JSON fixtures, and `AgentWorkflowContracts.Tests.ps1` behavioral coverage.
- Produces: a verifier that tolerates internal function/error-code refactors while continuing to reject provider calls, host mutation, runtime scheduling, active Radar decisions, side effects, and broken public wiring.

- [ ] **Step 1: Write the failing non-white-box test**

```powershell
$domain = (Get-Content -LiteralPath $domainPath -Raw).Replace('native_baseline_required', 'native_admission_required')
$application = (Get-Content -LiteralPath $applicationPath -Raw).Replace('completion_receipt_unclaimed', 'completion_receipt_not_claimed')
$parsed = (Invoke-AgentWorkflowAdvisoryVerifier $fixtureRoot).output | ConvertFrom-Json
$parsed.status | Should Be 'pass'
```

- [ ] **Step 2: Run RED**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Script 'tests/Unit/AgentWorkflowAdvisoryPlanning.Tests.ps1' -PassThru -Show Failed,Summary"`

Expected: FAIL because the verifier currently mirrors internal error codes and private functions.

- [ ] **Step 3: Delete behavior-test duplicate literals**

Retain manifest boundaries, task/schema shape, model anchors, public CLI/build wiring, full-gate integration, host ownership, zero side effects, pure-layer scans, forbidden runtime-control scans, active-Radar exclusion, and JSON parsing. Delete private error-code/function/test-description/fixture-content mirrors already exercised by `AgentWorkflowContracts.Tests.ps1`.

- [ ] **Step 4: Run planning and behavior GREEN tests**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Script @('tests/Unit/AgentWorkflowAdvisoryPlanning.Tests.ps1','tests/Unit/AgentWorkflowContracts.Tests.ps1') -PassThru -Show Failed,Summary"`

Expected: verifier and behavior tests pass together.

### Task 4: Record the active/historical governance boundary and close out

**Files:**
- Modify: `AGENTS.md`
- Create: `docs/change-evidence/20260809-governance-deweight.md`

**Interfaces:**
- Consumes: focused test receipts, verifier JSON, candidate commit SHA, full-gate immutable receipt, and current receipt verifier output.
- Produces: one reviewed evidence file for the logical slice; no per-task evidence expansion.

- [ ] **Step 1: Keep the project rule mapping compact**

Update the planning sentence to say manifests own dynamic state and plan/todo are indexes; state that the P6-specific verifier is explicit historical/migration validation while closeout remains the single full gate.

- [ ] **Step 2: Run focused contracts and build**

Run in order:

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Script @('tests/Unit/ProductPlanning.Tests.ps1','tests/Unit/HostNativeSkillLifecyclePlanning.Tests.ps1','tests/Unit/LeanAiDeliveryPlanning.Tests.ps1','tests/Unit/TypedCoreShadow.Tests.ps1','tests/Unit/PowerShellRuntimePolicy.Tests.ps1','tests/Unit/QualityGateScripts.Tests.ps1','tests/Unit/AgentWorkflowAdvisoryPlanning.Tests.ps1','tests/Unit/AgentWorkflowContracts.Tests.ps1') -PassThru -Show Failed,Summary"
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-vnext-planning.ps1 -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-agent-workflow-advisory.ps1 -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1
git diff --check
```

- [ ] **Step 3: Create an exact-write-set candidate commit**

Stage only the files listed in this plan, review `git diff --cached`, scan for high-confidence credentials, and commit with a concise Chinese subject. Do not push.

- [ ] **Step 4: Run the unique exact-source full gate**

Run with an outer timeout above 600 seconds: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full`.

- [ ] **Step 5: Verify the current receipt without changing source**

Run: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/verify-current-quality-gate.ps1 -RequiredProfile full -RequiredStatus passed`.

Expected: schema-v2 current pointer and immutable receipt hashes bind to the candidate source with `status=passed`.
