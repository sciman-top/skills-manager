# Three-tier model policy and pwsh7 worktree closeout

## Goal and truth boundary

The user explicitly removed `Terra high` from the active Agent model policy and retained exactly three soft anchors: `Luna max`, `Sol medium`, and `Sol xhigh`. This slice updates the runtime-independent repository advisory contract, the host default subagent settings, and the existing daily Radar automation. It does not add a repository scheduler, call a model provider, restart Codex, or claim a successful Luna inference.

The user had already removed the `codex/pwsh7-only` linked worktree. This slice verifies that result rather than repeating destructive cleanup.

## Decision and implementation

- Active tier order: `Luna max -> Sol medium -> Sol xhigh` for model-capacity escalation only.
- Default tier: `Luna max` for clear, bounded, repeatable routine subagent work.
- Removed tier behavior: `terra_high` no longer resolves to an anchor. A legacy FailurePacket carrying it returns control to the supervisor instead of silently routing or escalating.
- Radar boundary: Radar snapshots may continue to contain Terra or other external observations, but observations do not create project tiers or override the user-owned three-tier policy.
- Host ownership: explicit spawn model/effort still overrides `[agents]` defaults. The repository continues to return advisory-only plans with zero provider calls, native mutations, or writes.

## Worktree verification

- Target path `D:\CODE\skills-manager-worktrees\pwsh7\skills-manager`: absent.
- `git worktree list --porcelain`: only the main worktree and the unrelated detached Codex worktree remain.
- Branch `codex/pwsh7-only`: absent.
- No additional delete, force, prune, or branch command was required in this slice.
- `C:\Users\sciman\.codex\worktrees\25fa\skills-manager` was not modified.

## Host projection

- `C:\Users\sciman\.codex\config.toml` now sets `agents.default_subagent_model = "gpt-5.6-luna"` and `agents.default_subagent_reasoning_effort = "max"`.
- Pre-change backup: `C:\Users\sciman\.codex\config.toml.bak-20260805-before-three-tier-luna-default`; source and backup SHA-256 matched before editing.
- `codex debug models` lists `gpt-5.6-luna`, reports `supported_in_api = true`, and includes `max` in its supported reasoning efforts.
- Existing automation `codex-radar` remains ACTIVE at daily 21:00 local execution with failed-runs-only notification. Its execution model is now `gpt-5.6-luna + max`, and its prompt enforces the three-tier user policy while retaining fail-closed Radar validation.
- No Codex process was restarted. File projection is verified; fresh-task loading and a billable Luna inference remain separate host acceptance steps.

## Repository verification contract

- Focused Pester must prove exactly three manifest tiers, Luna-default override selection, Terra-tier rejection, `Luna max -> Sol medium -> Sol xhigh`, and unknown-tier supervisor review.
- `scripts/verify-agent-workflow-advisory.ps1 -Json` must report three tiers and zero findings/effects.
- `build.ps1` must regenerate `skills.ps1`; generated drift is not hand-edited.
- The sole closeout gate is `scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree` because unrelated user changes pre-existed in the shared checkout.

Pre-full receipts:

- RED: focused contracts ran 13 cases against the old implementation; 11 passed and the two expected failures proved that Terra still resolved and Luna still escalated to Terra.
- GREEN: focused contract/planning suites passed 20/20 after the implementation change.
- Build: `build.ps1` exited 0 and regenerated `skills.ps1`.
- Advisory verifier: `status=pass`, tasks `5/5`, model tiers `3`, findings `0`, effects `0/0/0`.
- CLI fixture replay: both `agent-validate` and `agent-plan` exited 0; the plan selected `gpt-5.6-luna + max`, emitted the expected three dependency waves, and retained zero side effects.
- The full-gate result is intentionally not predeclared here; it is the final no-more-edits closeout command and must be reported from fresh command output.

## Rollback

- Repository: revert only this three-tier slice, rebuild `skills.ps1`, and rerun the same gates; do not touch unrelated reference/override/watch changes.
- Host config: restore the named backup only after confirming the active config still matches this slice; no automatic restart.
- Automation: restore the prior automation model/prompt only through the Codex automation surface. Do not create a duplicate scheduled task.
- Worktree: there is no rollback action because the user had already removed it and the branch had no unique commit at the prior verification boundary.
