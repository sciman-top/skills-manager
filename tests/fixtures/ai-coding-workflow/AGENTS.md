# AI Coding Acceptance Fixture

This is a disposable PowerShell 7 project when copied to its own workspace.
Do not repair the checked-in fixture inside skills-manager/tests/fixtures.
Source of truth: Labels.ps1. Check: pwsh -NoProfile -File Test-Labels.ps1.

Get-NormalizedLabels must skip null/blank inputs, trim labels, remove duplicates
using ordinal case-insensitive comparison, and preserve first occurrence order
and the first trimmed spelling. Internal whitespace remains significant.
Its caller collects output using @(...) for empty, single and multiple labels.
Do not mutate caller inputs; repeated normalization must give the same result.

Only Labels.ps1 may be edited. Do not change tests, rules or external files.
Do not commit, push, install packages, modify host configuration or spawn agents.
Rollback uses the isolated fixture baseline, never the surrounding repository.
Report actual commands, exit codes and results. Include acceptance_probe=labels-v1.
