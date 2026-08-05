---
name: draft-spec
description: Draft a review-ready Markdown product or implementation specification from the current conversation and repository context without publishing it. Use when the user asks to draft a spec, PRD, requirements summary, or design document for review; do not use for issue-tracker publication.
---

# Draft Spec

Turn the context already available into a concise, reviewable Markdown draft.

## Output

Return the draft in the response with these sections:

1. Problem statement
2. Goals and non-goals
3. User stories or user-visible outcomes
4. Requirements and implementation decisions
5. Acceptance criteria and test strategy
6. Risks, assumptions, and open questions
7. Publication handoff (what still needs approval or tracker configuration)

Use repository terminology and existing ADRs when they are available. Separate
facts, decisions, assumptions, and unanswered questions. Prefer observable
behavior and seams over speculative file-by-file plans.

## Side-effect boundary

This is a draft-only skill. Do not call an issue tracker, create labels or
links, invoke `to-spec`/`to-tickets`, or create or modify repository files.
If the user later asks to publish the draft, hand off to an explicit
`$to-spec` invocation after the user has reviewed it.
