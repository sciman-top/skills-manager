---
name: code-review-and-quality
description: Review existing code for correctness, maintainability, security, performance, and missing tests. Use for code-review or quality-audit requests; do not modify code unless the user also asks for fixes.
---

# Code review and quality

Review the smallest relevant change set and report evidence-backed findings before summaries.

## Workflow

1. Establish the intended behavior, changed files, compatibility boundary, and available verification evidence.
2. Trace affected control flow and data flow. Prioritize defects that can change behavior, lose data, weaken authorization, leak secrets, or break compatibility.
3. Check error handling, lifecycle/resource cleanup, concurrency, input validation, and boundary conditions only where the changed path makes them relevant.
4. Check tests for the highest-risk behavior and failure modes. Do not request duplicate test layers when one sufficient layer proves the risk.
5. Report findings by severity with a tight file/line location, concrete failure scenario, and the smallest defensible correction.
6. If no actionable finding remains, say so and list material residual risks or verification gaps.

## Boundaries

- Review does not authorize edits, commits, publication, deployment, or external writes.
- Do not invent defects from style preferences or hypothetical scale.
- Prefer deletion and simplification over speculative abstractions.
- Use `$security-and-hardening` only when the review contains a material security boundary.
- Use `$performance-optimization` only when measurements or a hot path justify performance analysis.
- Use `$verification-before-completion` before claiming a requested fix is complete.

## Output

For each actionable finding provide severity, location, impact, evidence, and minimal fix direction. Keep the overview after the findings.
