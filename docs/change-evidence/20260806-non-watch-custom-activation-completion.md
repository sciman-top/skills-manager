# Non-watch custom activation completion

## Goal and boundary

- Complete deterministic activation-boundary coverage for the two non-watch custom skills that lacked direct, indirect, negative, and edge examples.
- Keep `watch-interrupted-task` and all of its source, generated output, hooks, tests, and runtime state outside the write set.
- Do not change either skill body: their current descriptions already state the positive trigger and the important exclusion boundary.

## Changes

- Extended `config/override-skill-activation-corpus.json` from 8 targets / 32 cases to 10 targets / 40 cases.
- Added four cases for `custom-windows-wpf-teacher-app`, separating Windows-first classroom product design from generic WPF explanation and `.NET` debugging.
- Added four cases for `draft-spec`, separating review-only Markdown drafting from tracker publication and implementation.
- Added no scripts, references, or assets because no repeated deterministic operation or missing domain reference was demonstrated.

## Verification

- Corpus JSON: declared 40, actual 40, targets 10.
- `scripts/verify-override-skill-activation.ps1`: pass; targets=10, cases=40, watch=excluded.
- System `skill-creator/scripts/quick_validate.py`: both target skills valid.
- `scripts/verify-skill-integrity.ps1`: 107 skills verified.
- Focused `QualityGateScripts.Tests.ps1`: 25 passed, 0 failed.
- Full local quality gate: exit 0; Unit 968/968, E2E 18/18, suite 582944 ms, total 597018 ms; generated sync, hygiene, skill integrity, reference governance, routing, dependency, config, host, planning, PS7, advisory, and doctor JSON contracts passed.

The full gate ran on a dirty combined worktree because a separate task wrote unrelated reference-governance files during the run. Those paths are excluded from this change set and were neither reverted nor staged. The focused corpus, skill validation, and integrity checks are the authoritative evidence for this isolated slice. This evidence file is a post-gate documentation receipt (`gate_na`); alternative verification is exact diff review plus the focused commands above. Any executable or generated change would require another full gate.

## Truth boundary and rollback

- The corpus is a deterministic expectation and coverage contract; it does not prove universal live model selection or skill-body execution.
- No host projection, active-profile switch, MCP/plugin installation, provider call, auth change, or restart was performed.
- Roll back only this evidence file and the eight added corpus cases. Do not modify concurrent reference-governance or watch work.
