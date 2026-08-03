# 2026-08-02 Rule Estate Governance Follow-through

## Goal and boundary

- Goal: derive all direct Git repositories under `D:\CODE` except `external` and `文档`, audit Codex/Claude global plus project rules as one estate, and execute only a human-reviewed, hash-guarded rule change-set.
- Non-goals: central authoritative registry, unreviewed synchronization, provider/auth/model/sandbox mutation, plugin/native host mutation, auto commit/push, or live acceptance claims.
- Existing dirty worktrees were preserved. The authorized rollout changed exactly 2 global user rule files and 9 project `AGENTS.md` files; unrelated target-repository paths were only recorded in the plan/receipt.

## Sources and decisions

- Current Codex manual helper: `C:\Users\sciman\AppData\Local\Temp\openai-docs-cache\codex-manual.md`, status `local manual was already current`.
- Official AGENTS guidance: global first-non-empty file, root-to-cwd project chain, nearest rule later in the prompt, and default 32 KiB combined project budget. Decision: adopt discovery/precedence; keep native loading separate.
- Official Rules guidance: `.rules` controls command decisions outside the sandbox and remains experimental. Decision: keep deterministic enforcement separate from prose rules.
- Local retired reference: `D:\CODE-other\governed-ai-coding-runtime@bbf5aba4b221ecf5ac0279ad41c9c51c104b4191`. Decision: adapt common/platform_delta/project_action and thin-wrapper patterns; reject restoration of its retired registry/runtime.
- Community workflow reference: `obra/superpowers@3dcbd5c4b48e02263fbf4a3c01e3fe4f81d584d9`. Decision: retain evidence-before-claims and fault testing; do not import an always-on workflow runtime.

## Changes

- Added `rule-estate-audit` with bounded direct-Git discovery, exclusions, registry drift, common-section alignment, platform delta presence, rule release drift, responsibility coverage, and reviewed patch candidates.
- Extended rule plans from fixture-only/single-repository scope to reviewed global/project multi-target change-sets with dynamic target snapshots, exact roots and filenames, before hashes, explicit apply token, atomic writes, durable receipt, resume and per-target rollback.
- Reconciled `audit-targets.json`: removed absent `local-ai-dev-orchestrator` and added current `physicist_chinese_poster_batch_tool`.
- Updated the physicist poster repository to project contract 2.0/global review 9.60, current pytest/validator gates, and a one-line `CLAUDE.md` adapter.
- Replaced that repository's stale implicit final-delivery validator default with the explicit current `outputs/final-delivery/images` and supporting manifest paths.
- Fixed responsibility parsing so one mapping bullet can carry separate semicolon-delimited labels such as `E4`, `E5`, and `E6`; the regression test first reproduced the 97/99 false gap and then passed after the parser fix.

## Evidence

- Focused transaction and estate tests: 37 passed, 0 failed.
- Target repository gates: all Python scripts compiled; pytest 62 passed; `validate_project: OK`; final-delivery validation reported 0 errors and 0 warnings.
- Full quality gate passed with the contract-approved `-AllowDirtyWorktree` switch; generated sync rebuilt `skills.ps1` and confirmed it matched current `src/`. The strict clean-tree form correctly blocked because this development slice is not committed relative to `HEAD`.
- Final estate audit: 9 targets, 99 covered responsibility mappings, 0 gaps, 0 findings, 0 patch candidates, global common sections aligned, registry in sync.
- Correction chain (same-day): repairing a PowerShell `$Matches` collision first exposed 97/99 coverage; root-cause analysis then showed the remaining E5/E6 gaps were parser false negatives for multiple labels in one bullet. After the multi-label parser fix, the current generated-entry audit is again 99/99 with non-empty actions/evidence and 0 findings.
- Codex 0.145.0 fresh-process load probe: `codex debug prompt-input` verified the complete on-disk global and project `AGENTS.md` texts in model-visible input for all 9 targets; 9 passed, 0 failed, provider calls 0.
- Authorized rollout receipt: `reports/rule-estate/20260802-reapproved/estate-receipt.json`; status `applied`, 11/11 actions applied, all current target hashes equal their reviewed desired hashes, provider/native mutations 0.
- Final verification after the parser/source changes: `tests/run.ps1` exit 0 in 184.3 seconds; doctor, dependency baseline, host capability, planning and P4 entry contracts all exit 0; full quality gate with `-AllowDirtyWorktree` exit 0 in 184.2 seconds and reported `Local quality gates passed (full)`.
- Report: `reports/rule-estate/current.json` (runtime report, ignored from Git).

## Truth boundary and rollback

- `filesystem_applied`: 11/11 reviewed actions, exact desired hashes verified.
- `repo_verified`: yes for focused parser/estate tests, the 99/99 generated-entry audit, the full test runner and the full local quality gate.
- `host_loaded.codex`: `verified_9_of_9` by fresh-process model-visible prompt rendering.
- `host_loaded.claude`: `platform_na`; `reason=Claude Code 2.1.206 exposes no provider-free prompt renderer`, `alternative_verification=global common/delta static audit + one-line no-BOM project wrappers`, `evidence_link=this document and reports/rule-estate/current.json`, `expires_at=next Claude CLI upgrade`, `recovery_condition=a provider-free local prompt inspection command becomes available or provider execution is explicitly authorized`.
- `live_accepted`: `not_run`.
- Roll back a deployed rule only with `rule-estate-rollback`, the exact receipt action id and `ROLLBACK_RULE_ESTATE_PATCH`; roll back control-repo source/docs/tests as a separate slice and rebuild `skills.ps1`. Do not touch unrelated target output, audit, PDF or courseware changes.
