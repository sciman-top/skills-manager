---
name: test-driven-development
description: Use only when the user explicitly requests strict TDD or Red-Green-Refactor, or a task contract requires test-first development; do not use for ordinary implementation, configuration, documentation, generated files, or broad test expansion.
---

# Focused Test-Driven Development

Apply a test-first loop only to the behavior seam named by the request or task
contract:

1. Write the smallest test that would fail for the missing behavior.
2. Run that focused test and confirm the expected failure.
3. Implement the minimum change that makes it pass.
4. Re-run the focused test, then refactor only if the passing behavior is
   preserved.

Do not require TDD for routine implementation merely because code changes are
involved. Configuration, documentation, generated files, exploratory work, and
already-characterized mechanical changes remain outside this skill unless the
user explicitly opts in.

Do not add unrelated fixtures, coverage thresholds, CI jobs, full-suite runs,
review gates, or one-test-per-file rules. Use the repository's existing
risk-based closeout gate once at the repository-defined closeout point.
