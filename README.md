# skills-manager

> Skill lifecycle and governance manager for Codex agent repositories.

## Why this project
- Pain: Skill files drift across repos and lifecycle state becomes hard to audit.
- Result: Skill promotion, verification, and lifecycle review become repeatable.
- Differentiator: Governance scripts enforce skill quality and cross-repo consistency.

## Who it is for
- Agent platform maintainers and automation engineers
- Managing shared skills, trigger evaluation, and promotion workflows
- Use this when skill updates are frequent and manual sync becomes error-prone

## Quick Start (5 Minutes)
### Prerequisites
- PowerShell 7+
- Repository with governance scripts and policy files

### Run
```bash
powershell -File scripts/doctor.ps1
```

### Expected Output
- HEALTH=GREEN in doctor output
- Skill governance checks report PASS

## What you can try first
- Run verify before promoting skill candidates
- Use lifecycle review to inspect merge/retire candidates
- Distribute shared policies through install flow

## FAQ
- Q: Promotion is blocked
- A: Check trigger-eval status and required policy fields, then rerun promotion

## Limitations
- Focuses on governance/lifecycle, not runtime model behavior
- Relies on configured skill registry and policy files

## Next steps
- docs/
- RELEASE_TEMPLATE.md
- issues/
