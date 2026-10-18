## Goal
- <what this PR changes>
- New surface: no
- Set this to `yes` when adding an independent feature/module, gate/workflow, test suite, or reusable abstraction. Routine fixes and regression cases within existing surfaces use `no`.
- CI enforces the `new-surface` label, not this text: a PR that adds files under `src/`, `scripts/`, `tests/` (not fixtures) or `.github/` must carry the label, which a human sets. Docs are not gated.

## Admission (complete only when New surface is yes)
- Current caller: <who calls this today; "may be useful later" is not a caller>
- Replaces / deletes: <what this removes or supersedes; "none" = net-new surface, justify it>
- Minimum proof: <smallest check that proves the change; does it escalate the gate to full?>

## Verification
- Complete this section for every PR; direct observation or N/A with a reason is valid when applicable.
- Minimum proof: <checks or direct observations covering this change's behavior and risks>
- Result: <command, exit code and relevant result; identify unverified acceptance>
- N/A: <inapplicable build/test/contract steps and reasons, or none>
- Reuse valid evidence; rerun only invalidated proof. Apply the repository gate profile and explain any escalation.

## Deletion delta
- Removed: N/A unless New surface is yes; then list tests, gates, and docs removed or merged.

## Risks and Rollback
- Risk:
- Rollback:
