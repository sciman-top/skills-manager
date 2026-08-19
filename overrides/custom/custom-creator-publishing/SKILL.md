---
name: custom-creator-publishing
description: "Use when Chinese long-form content needs a source-backed publishing workflow: draft or restructure the canonical Markdown, adapt it for WeChat Official Account, Zhihu, blogs, or teaching newsletters, plan visuals, or repurpose it into courseware. Do not use for a one-line copy edit, generic marketing-page copy, or a direct publication-only request."
---

# Creator Publishing

Use this skill for Chinese article workflows where structure, credibility, images, and platform formatting matter.

## Workflow

1. Identify the audience, platform, purpose, source material, and requested artifact. Ask only when a missing answer would materially change the result; otherwise state the assumption.
2. Choose the article shape: explanation, opinion, tutorial, review, lesson reflection, product note, or case study.
3. Build a source-backed outline before polishing prose. Distinguish supplied facts, verified facts, opinions, and claims that still need current verification.
4. Draft in Markdown as the canonical source. Keep headings, callouts, image placeholders, references, and publication notes explicit.
5. Adapt from the canonical draft instead of maintaining unrelated copies. For WeChat, shape the title, cover, lead, section rhythm, pull quotes, and end CTA. For Zhihu, emphasize searchable question framing, concise claims, examples, and defensible reasoning.
6. Treat actual publication, scheduling, account changes, and audience notifications as external writes. Draft and export locally by default. Publish only after the user explicitly authorizes the exact platform, account, and final payload in the current task; verify the resulting receipt before retrying a failed submission.

## Conditional Capabilities

- Do not load every adjacent skill. Use an available writing, editing, or content-strategy skill only when that narrower task needs specialist guidance.
- Use `imagegen` or an available cover/infographic capability only when the user requests actual visual assets; otherwise provide a concrete image brief and placeholder.
- Use conversion or platform-specific tooling only after the canonical Markdown is stable.

## Deliverable

Return the requested draft or local artifact plus the assumptions/source gaps, platform-specific changes, and any visual asset list. Keep publication state explicit as `draft_only`, `authorized_not_sent`, or `published` with a receipt; never imply publication from a platform-ready draft.

## Verification

- Check for unsupported claims, broken image references, title/body mismatch, and platform-inappropriate formatting.
- Keep credentials, cookies, and publication tokens out of article source and logs.
- Do not interpret a request to write, format, illustrate, or convert an article as permission to publish it.
