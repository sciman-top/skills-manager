---
name: code-review-and-quality
description: Review code, diffs, or pull requests for correctness, regressions, security, maintainability, performance, and missing tests — even when a diff is pasted inline or looks quick to eyeball. Report severity-labeled findings and a clear verdict; do not modify code unless the user also asks for fixes.
---

# Code review and quality

Review the smallest relevant change set and report evidence-backed findings before summaries.

## Workflow

1. Establish the intended behavior, changed files, compatibility boundary, and available verification evidence.
2. Trace affected control flow, data flow, callers, and guards. Prioritize defects that can change behavior, lose data, weaken authorization, leak secrets, or break compatibility.
3. Check error handling, lifecycle/resource cleanup, concurrency, input validation, and boundary conditions only where the changed path makes them relevant.
4. Check tests for the highest-risk behavior and failure modes: confirm they would fail if a changed branch or condition were inverted, rather than mirroring mocks or brittle constants. Do not request duplicate test layers when one sufficient layer proves the risk.
5. Before reporting a candidate finding, verify it against reaching callers, guards, and existing tests — drop it if they rule it out. Separate pre-existing base defects from regressions introduced by the change, and report findings by severity with a tight file/line location, concrete failure scenario, and minimal fix direction.
6. Zero actionable findings is a valid result — do not invent one; state the verdict clearly and list material residual risks or verification gaps.

## Boundaries

- Review does not authorize edits, commits, publication, deployment, or external writes.
- Do not invent defects from style preferences or hypothetical scale.
- Prefer deletion and simplification over speculative abstractions.
- Use `$security-and-hardening` only when the review contains a material security boundary.
- Use `$performance-optimization` only when measurements or a hot path justify performance analysis.
- Use `$verification-before-completion` before claiming a requested fix is complete.

## Output

For each actionable finding provide severity, location, impact, evidence, and minimal fix direction. Keep the overview after the findings.
