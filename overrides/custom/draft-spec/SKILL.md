---
name: draft-spec
description: Draft a review-ready Markdown product or implementation specification from the current conversation and repository context without publishing it. Use when the user asks to draft a spec, PRD, requirements summary, or design document for review; do not use for issue-tracker publication.
---

# Draft Spec

Turn the context already available into a concise, reviewable Markdown draft.
Ground the draft in the current conversation and repository evidence. Label
facts, user decisions, assumptions, and open questions; if a required target or
payload is absent, ask for it rather than filling the gap with a guessed
"latest" choice.

## Output

Return the draft in the response. Follow a supplied template; otherwise use
the sections below, combining or omitting sections that add no useful decision:

1. Problem statement
2. Goals and non-goals
3. User stories or user-visible outcomes
4. Requirements and implementation decisions
5. Acceptance criteria and test strategy
6. Risks, assumptions, and open questions
7. Publication handoff, only when publication is part of the requested outcome

Use repository terminology and existing ADRs when they are available. Make
acceptance criteria observable and testable, and prefer behavior and seams over
speculative file-by-file plans. Do not turn an assumption into a requirement
without labeling the decision that would resolve it.

Separate required outcomes from proposed implementation choices. For each
material requirement, identify the user-visible result and an observable
acceptance check; include failure or recovery behavior where it affects that
result. Link repository claims to inspected paths or symbols. When evidence is
missing, keep the choice open rather than inventing APIs, files, or estimates.

## Side-effect boundary

This is a draft-only skill. Do not call an issue tracker, create labels or
links, or create or modify repository files. If the user later asks to
publish the draft, treat publication as a separate, explicitly authorized
task with its own workflow; this skill implies no publishing command.
