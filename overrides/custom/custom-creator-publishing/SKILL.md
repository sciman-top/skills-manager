---
name: custom-creator-publishing
description: Use when writing, polishing, formatting, illustrating, or repurposing Chinese long-form content for WeChat Official Account, Zhihu, blogs, teaching newsletters, or article-to-courseware workflows.
---

# Creator Publishing

Use this skill for Chinese article workflows where structure, credibility, images, and platform formatting matter.

## Workflow

1. Clarify the platform: WeChat Official Account, Zhihu, blog, teaching handout, or multi-platform reuse.
2. Choose the article shape: explanation, opinion, tutorial, review, lesson reflection, product note, or case study.
3. Build a source-backed outline before polishing prose. Mark facts that require current verification.
4. Draft in Markdown as the canonical source. Keep headings, callouts, image placeholders, references, and publication notes explicit.
5. For WeChat, plan title, subtitle, cover image, lead paragraph, section rhythm, pull quotes, and end CTA.
6. For Zhihu, emphasize searchable question framing, concise claims, examples, and defensible reasoning.
7. Treat actual publication, scheduling, account changes, and audience notifications as external writes. Draft and export locally by default. Publish only after the user explicitly authorizes the exact platform/account and final payload in the current task; verify the resulting receipt before retrying a failed submission.

## Tool Priority

- Writing and editing: `copywriting`, `copy-editing`, `content-strategy`, `baoyu-format-markdown`.
- Images: `imagegen`, `baoyu-cover-image`, `baoyu-infographic`, `canvas-design`.
- Conversion: use `markdown-converter` and platform-specific tools only after the Markdown source is clean.

## Verification

- Check for unsupported claims, broken image references, title/body mismatch, and platform-inappropriate formatting.
- Keep credentials, cookies, and publication tokens out of article source and logs.
- Do not interpret a request to write, format, illustrate, or convert an article as permission to publish it.
