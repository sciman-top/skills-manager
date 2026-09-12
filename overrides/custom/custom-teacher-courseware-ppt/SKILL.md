---
name: custom-teacher-courseware-ppt
description: Use when creating or revising PPT/PPTX courseware for junior middle school teaching, especially physics lessons, experiment explanations, exercise walkthroughs, lesson summaries, teacher handouts, formative exit checks, or classroom-ready slide decks with accessible differentiation. Do not use for marketing decks or format-only slide conversion.
---

# Teacher Courseware PPT

Use this skill for classroom-ready courseware, not marketing decks.

## Workflow

1. Identify the teaching scenario: new lesson, review lesson, experiment lesson, exercise analysis, unit summary, or open-class presentation.
2. Produce a slide outline before generating files. For each slide, state the teaching purpose, teacher action, expected student response or evidence, and approximate pacing. Select only the components the scenario needs from prerequisites, learning goals, concept conflict, demonstration, student activity, worked examples, misconception repair, summary, exit ticket, and homework. Add a scaffold and an extension when the class range or access needs call for them.
3. Prefer dense but readable teacher utility over decorative pages. Use large diagrams, clear labels, and one main teaching action per slide.
4. For junior physics, include the physical situation, idealized model, variable relationship, unit discipline, and common misconception.
5. Keep the lesson arc and assessment aligned: state what students must already know, what they will be able to do, and what the exit ticket will reveal. If a textbook, curriculum, or standard is not supplied, label the basis as an assumption rather than inventing an alignment claim.
6. Keep student-visible content, teacher prompts, and answer/reveal notes distinct. Do not make a teaching decision depend on speaker notes when the delivery mode will not expose them.
7. When creating PPTX, select the available presentation capability by its actual metadata rather than assuming a skill name or COM support. Preserve the requested format; web slides require a matching delivery request. If generation is blocked, identify the missing capability and report the file as pending.

## Deliverable Boundary

- For a design-only request, return the slide outline and the assumptions that still need teacher review.
- For a deck creation or revision request, continue through editable PPTX generation, render/preview, and focused correction. Do not present the outline as the completed deck.
- Preserve editable text, diagrams, tables, charts, and speaker notes when they carry teaching meaning; use flattened images only when the visual cannot reasonably remain native.

## Slide Patterns

- Concept intro: everyday phenomenon -> question -> simplified model -> key term.
- Experiment: apparatus -> procedure -> observation table -> conclusion -> error discussion.
- Exercise walkthrough: knowns/unknowns -> diagram -> formula choice -> substitution -> unit check -> answer meaning.
- Misconception repair: wrong intuition -> counterexample -> corrected rule -> quick check.
- Review page: concept map + 3 representative questions.
- Differentiation: one concrete scaffold tied to the hardest task plus one extension that increases reasoning, not page count.

## Verification

- Check that each substantive teaching beat fits the stated pace, allocating separate time for title, demonstration, student work, transitions, and the exit ticket.
- Verify formulas, units, and diagrams against the target textbook/standard.
- Check prerequisite knowledge, learning targets, activities, and the formative exit ticket for alignment. Keep the stated period realistic, including transitions.
- Render every slide from the final saved deck; inspect Chinese font substitution,
  overflow, clipped equations, diagram labels, and answer/reveal order. Recheck
  changed slides after corrections. An earlier preview does not verify a later file.
- Recalculate worked examples and answer keys independently, including units and
  rounding. Keep answers in the intended reveal or teacher-facing location.
- For required animations, embedded media, or offline playback, test them in the
  target player when available. Static renders cannot verify playback; report
  untested PowerPoint/WPS behavior separately from successful PPTX generation.
- After content and layout stabilize, hand the deck to `custom-powerpoint-accessibility` when it is available for titles, alternative text, reading order, contrast, captions, and motion review. If that validator or live PowerPoint is unavailable, keep the manual checklist and report structural or assistive-technology checks as `not_verified`.
