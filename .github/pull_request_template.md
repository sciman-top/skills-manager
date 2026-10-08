## Goal
- <what this PR changes>
- New surface: no
- Set this to `yes` when adding an independent feature/module, gate/workflow, test suite, persistent documentation/policy surface, or reusable abstraction. Routine fixes and regression cases within existing surfaces use `no`.

## Charter admission (complete only when New surface is yes)
- CI rejects unresolved placeholders in this section; the fields must describe the actual change.
- Current caller: <who calls this today; "may be useful later" is not a caller>
- Replaces / deletes: <what this removes or supersedes; "none" = net-new surface, justify it>
- Minimum proof: <smallest check that proves the change; does it escalate the gate to full?>

## Verification
- [ ] Build passed
- [ ] Tests passed
- [ ] Contract/invariant unchanged or updated with migration notes

## Deletion delta
- Removed: N/A unless New surface is yes; then list tests, gates, and docs removed or merged.

## Evidence
- Command output:
- Screenshots or logs:

## Risks and Rollback
- Risk:
- Rollback:
