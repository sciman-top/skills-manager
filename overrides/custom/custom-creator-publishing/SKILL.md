---
name: custom-creator-publishing
description: "Use when Chinese long-form content needs a source-backed publishing workflow: draft or restructure the canonical Markdown, adapt it for WeChat Official Account, Zhihu, blogs, or teaching newsletters, plan visuals, or repurpose it into courseware. Do not use for a one-line copy edit, generic marketing-page copy, or a direct publication-only request."
---

# Creator Publishing

Use this skill for Chinese article workflows where structure, credibility, images, and platform formatting matter.

## Workflow

1. Identify the audience, platform, purpose, source material, and requested artifact. Ask only when a missing answer would materially change the result; otherwise state the assumption.
2. Choose the article shape: explanation, opinion, tutorial, review, lesson reflection, product note, or case study.
3. Build a source-backed outline before polishing prose. Prefer supplied or first-party sources for factual and current claims, record the URL and access date when verification is needed, and distinguish verified facts, opinions, inferences, and claims that remain open.
4. Use Markdown as the default canonical source, preserving a user-specified source format. Keep editorial notes and unresolved placeholders separate from publishable copy; do not leave them embedded in a claimed final export.
5. Adapt from the canonical draft instead of maintaining unrelated copies. For WeChat, shape the title, cover, lead, section rhythm, pull quotes, and end CTA. For Zhihu, emphasize searchable question framing, concise claims, examples, and defensible reasoning.
6. Treat actual publication, scheduling, account changes, and audience notifications as external writes. Draft and export locally by default. Publish only after the user explicitly authorizes the exact platform, account, and final payload in the current task; verify the resulting receipt before retrying a failed submission.

## Content integrity

- Keep attribution and usage notes for quoted text, supplied material, and visual assets. Paraphrase rather than reproduce long passages, and never invent sources, citations, data, or publication analytics.
- Keep the canonical draft, platform adaptation notes, and source register distinct so a platform edit cannot silently change the factual basis.

## Conditional Capabilities

- Do not load every adjacent skill. Use an available writing, editing, or content-strategy skill only when that narrower task needs specialist guidance.
- Use an available image-generation or cover/infographic capability (for example `baoyu-cover-image` or `baoyu-infographic`) only when the user requests actual visual assets; otherwise provide a concrete image brief and placeholder.
- Use conversion or platform-specific tooling only after the canonical Markdown is stable.

## Deliverable

Return the requested draft or local artifact plus the assumptions/source gaps, source register, platform-specific changes, and any visual asset list. Keep publication state explicit as `draft_only`, `authorized_not_sent`, or `published` with a receipt; never imply publication from a platform-ready draft.

## Verification

- Check that citations resolve to the supplied or verified sources, along with unsupported claims, broken image references, title/body mismatch, and platform-inappropriate formatting.
- Check that each citation supports its nearby claim, not merely that the URL
  loads. Retain necessary dates, qualifications, and attribution when shortening
  or adapting the article for another platform.
- Preview the actual export at the target reading width when producing HTML or
  platform-ready files. Verify Chinese typography, image captions, code blocks,
  tables, and links after conversion; source Markdown alone does not prove the
  exported layout. Do not claim a platform preview unless that platform was used.
- Keep credentials, cookies, and publication tokens out of article source and logs.
- Do not interpret a request to write, format, illustrate, or convert an article as permission to publish it.
