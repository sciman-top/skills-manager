---
name: custom-powerpoint-accessibility
description: Use when auditing or validating PowerPoint/PPTX classroom presentations for accessibility, including titles, alt text, reading order, tables, links, captions, contrast, color cues, motion, and native Accessibility Checker evidence.
---

# PowerPoint Accessibility

Audit accessibility after the deck content and layout are stable. This skill is a validator: use Presentations to create or edit PPTX files and `powerpoint-automation` only when live Windows PowerPoint or COM operation is required.

## Workflow

1. Establish the audience, PowerPoint version, delivery mode, and whether the deck includes narration, video, tables, charts, equations, or interactive links.
2. Inspect the editable slide structure before relying on rendered images. Record blockers when only a PDF, screenshot, or flattened deck is available.
3. Audit every slide against the checklist below and classify findings as `blocker`, `major`, `minor`, or `verified`.
4. Run PowerPoint's native Accessibility Checker when live PowerPoint is available. Preserve its warnings and errors as evidence; do not treat an empty checker result as proof of full accessibility.
5. Render or preview the final deck and inspect visual contrast, clipping, captions, focus cues, and non-color communication.
6. Report the inspected artifact, tools used, unresolved limitations, and the exact evidence supporting each verified claim.

## Audit Checklist

- Give every content slide a meaningful title. Titles should be unique when they identify distinct topics; repeated section titles need a distinguishing phrase.
- Provide concise alt text for informative images, diagrams, charts, equations, and grouped visual explanations. Mark purely decorative objects as decorative.
- Verify reading order in the Selection Pane or an equivalent structure view. The sequence must make sense without visual position, including grouped objects and off-slide elements.
- Use real tables with a header row. Avoid merged cells, blank spacer cells, and tables used only for layout when they impede navigation.
- Use hyperlink text that describes the destination or action without surrounding context. Avoid bare URLs and repeated `click here` labels.
- Provide synchronized captions for meaningful video and transcripts for audio or narration. Identify any media whose accessibility depends on external playback controls.
- Check text and essential graphics for sufficient contrast. Never encode meaning by color alone; add labels, patterns, shapes, or text cues.
- Remove non-essential animation, rapid flashing, and motion that obscures reading. Prefer simple, user-controlled sequences and a usable reduced-motion/static path.
- Confirm that text remains readable at the intended classroom scale and that zoom, high contrast, or enlarged text does not hide critical content.
- Run the native Accessibility Checker and triage every error, warning, and intelligent-service suggestion relevant to the deck.

## Evidence And Fail-Closed Rules

- Treat rendered previews as visual evidence only. They cannot prove object semantics, reading order, alt text, table headers, or assistive-technology behavior.
- Do not claim reading order is verified unless the editable object sequence was inspected in PowerPoint or an equivalent structural representation.
- Do not claim screen-reader or assistive-technology compatibility unless it was exercised with the named technology and version. Otherwise report `not_verified` and the required manual check.
- If PowerPoint's Accessibility Checker cannot be run, report it as an open validation gap rather than inferring a pass from file inspection.
- A deck passes this audit only when no blockers remain, all major findings are resolved or explicitly accepted, and the evidence identifies both the editable-structure review and rendered-preview review.

## Output

Return a compact table with `slide`, `severity`, `criterion`, `finding`, `recommended fix`, and `evidence`. End with:

- `accessibility_status`: `passed`, `needs_fixes`, or `not_verifiable`
- `native_checker`: version and result, or `not_run` with reason
- `reading_order`: `verified` or `not_verified`
- `assistive_technology`: tested tool/version, or `not_verified`
- `residual_risks`: remaining manual, live, or audience-specific checks

Read [references/research-basis.md](references/research-basis.md) when standards provenance or upstream comparison matters.
