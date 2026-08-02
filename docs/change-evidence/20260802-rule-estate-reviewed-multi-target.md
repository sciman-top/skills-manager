# Rule estate reviewed multi-target follow-through

## Goal and boundary

- Goal: make global Codex/Claude user rules and `D:\CODE` direct Git repositories first-class rule-estate targets while preserving target ownership and explicit review.
- Target selection: dynamic direct Git roots; default exclusions are `external` and `文档`.
- A real apply was executed only after the workspace owner explicitly authorized autonomous continuation; the reviewed change-set records `reviewed_by_type=human` and `authorization_source=user_supplied`.
- Excluded surfaces: plugin/native host mutation, provider, auth, model, sandbox, daemon, database, GUI, team console, auto commit/push, and unreviewed bulk overwrite.

## Design disposition

- Adopted from `D:\CODE-other\governed-ai-coding-runtime@bbf5aba4b221ecf5ac0279ad41c9c51c104b4191`: common/platform_delta/project_action, progressive disclosure, rule budgets, prose/enforcement separation, and anti-overdesign constraints.
- Rejected from the retired archive boundary: “no cross-repo management” is specific to that retired repository and is not inherited by this product.
- Execution uses `preflight-all -> apply-one-by-one -> receipt-after-each -> fail-fast`, not cross-repository all-or-rollback.

## Implementation

- Added reviewed change-set validation; AI self-review is not apply authority.
- Added exact global/project rule filename allowlists and dynamic target-set hash.
- Added stale review/target-file hash, target-set drift, lock, duplicate/no-op, action-count and path guards; drive roots and reparse paths are rejected. Unrelated dirty paths are observed and preserved instead of blocking the scoped rule transaction.
- Added per-target atomic writes, durable backups/receipts, resume, fail-fast and per-action rollback.
- Bound rollback to the caller-supplied workspace/Codex/Claude roots and the receipt's exact target, authorized root, operation/action identifiers and backup location; tampered receipts fail closed.
- Added CLI commands `rule-estate-plan`, `rule-estate-apply`, and `rule-estate-rollback` plus product/architecture/usage contracts.

## Real defect found and repaired

The real read-only estate audit initially returned `project_actions=[""]` and `evidence=[null]` as covered. Root cause: a local `$matches` action array was overwritten by PowerShell's case-insensitive automatic `$Matches` variable after `-match`. The fix renames the action collection and uses `[regex]::IsMatch`, with regression assertions that every covered item has a non-empty project action and non-null evidence.

After the `$Matches` repair, the intermediate live read-only summary was:

```json
{"target_count":9,"covered_count":97,"gap_count":2,"empty_covered_actions":0,"null_covered_evidence":0,"writes":0,"provider_calls":0,"host_loaded":"not_run","live_accepted":"not_run"}
```

The two apparent gaps were then traced to a second parser defect: a valid project mapping bullet with separate ``E4``, ``E5`` and ``E6`` labels only emitted its first label. A red/green regression test now covers this shape. The generated-entry audit after that fix is 9 targets, 99 covered, 0 gaps, 0 findings and 0 patch candidates.

The reapproved plan `rule-estate-17cefe38446a8f6e` dynamically snapshotted 9 targets and 11 actions. Apply returned `status=applied`, `writes=11`; the receipt contains 2 global and 9 repository actions, all 11 current files match their desired hashes, and unrelated dirty paths were preserved. Codex fresh-process prompt inspection loaded complete global and project texts in all 9 repositories. Claude remains `platform_na`; `live_accepted` remains `not_run`.

The generated CLI E2E also exposed a PowerShell parameter-binding defect: `--plan` was consumed by the script-level `$Plan` switch before `rule-estate-apply` parsed its tokens. The estate apply dispatch now forwards that switch using the same compatibility pattern as the existing single-target `rule-apply`, restoring the one-JSON-envelope contract.

The final full-suite run found one unrelated stale assertion in the concurrent profile slice: `skills.json` and README had already changed `default` from 7500/6 entries to 8000/9 entries, while `SkillProjection.Tests.ps1` still asserted the old contract. Only those two expected values were synchronized; the profile configuration and routing changes were preserved.

## Verification

- `Invoke-Pester tests/Unit/RuleEstate.Tests.ps1,tests/Unit/RuleEstateMutation.Tests.ps1,tests/Unit/RuleAdvisor.Tests.ps1`: 16 passed, 0 failed.
- Generated-entry `tests/E2E/Workflow.Tests.ps1`: 15 passed, 0 failed, including plan/apply/rollback with single-JSON stdout.
- `tests/run.ps1`: exit 0 in 176.9 seconds after the final source/test changes; E2E summary 18 passed, 0 failed.
- doctor/dependency/host/planning contracts: all exit 0; P4 entry verifier also exits 0 with `decision=not_started`, `status=deferred`, `all_required_met=False`.
- Final `scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree`: exit 0 in 180.7 seconds; build, hygiene, generated-sync, all tests, skill integrity/routing, dependency/config/host/planning/doctor contracts passed.
- After adding the multi-label responsibility parser regression, `RuleAudit.Tests.ps1` and `RuleEstate.Tests.ps1` each passed 6/6; `tests/run.ps1` exited 0 in 184.3 seconds and a fresh full quality gate exited 0 in 184.2 seconds.

## Truth boundary and rollback

- `filesystem_applied` and `repo_verified` do not prove `live_accepted`; Codex `host_loaded=9/9` is limited to fresh-process prompt inspection.
- Roll back a deployed rule only by exact receipt action id; control-repo source/docs rollback is separate. Never reset or clean whole target worktrees.
- This final evidence-only edit is `gate_na`: `reason=records already executed closeout output`, `alternative_verification=git diff --check plus read-only estate audit`, `evidence_link=this file`, `expires_at=commit_closeout`, `recovery_condition=any source/generated/test change`.
