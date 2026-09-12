---
name: custom-junior-physics-animation
description: "Use when junior-middle-school physics pedagogy is the hard part: establish the lesson goal and misconception, validate the physics, choose among web/SVG, Manim, PPT, or static media, and define classroom verification. Do not use merely to create an interactive visualization, image, video, or slide artifact when a native artifact capability directly handles the request."
---

# Junior Physics Animation

Use this skill when the goal is teaching a concept through motion or interaction.

## Choose The Medium

- Choose from delivery constraints first: offline or online use, editable source,
  runtime and file-size limits, projector conditions, and the required level of
  interaction. Preserve a requested format. If its toolchain is unavailable,
  check supported generation routes before reporting the exact blocker; an
  implementation request remains incomplete until the artifact is delivered.
- SVG/HTML/CSS/JS: best for lightweight classroom web demos, force diagrams, ray diagrams, circuit toggles, graphs, and drag interactions.
- D3: best for data, graphs, coordinate systems, and variable relationships.
- Manim: best for formula derivation, geometry, vector decomposition, and exported short videos.
- PPT animation: best when the teacher needs simple step-by-step reveal without running a browser.

## Design Rules

1. Establish the target grade, textbook/standard, lesson objective, and the misconception or phenomenon the visual should resolve. If the curriculum basis is not supplied, identify the assumption instead of inventing alignment.
2. Use animation only when change over time, causality, or interaction adds teaching value; prefer a static annotated diagram for a state that does not need motion.
3. Keep variables visible: value, unit, direction, and sign convention.
4. Use color consistently, but never make color the only carrier of force/vector, path/ray, measured quantity, or result.
5. Provide pause/replay/step controls for classroom pacing, plus a reduced-motion or static fallback.
6. Use physically meaningful scales or clearly label schematic/not-to-scale scenes.
7. Before animating, write the minimal model: variables and units, assumptions,
   coordinate/sign convention, initial or boundary conditions, and the expected
   relationship or invariant.
8. Check the model with dimensional analysis, a hand-worked expected observation,
   and simple or limiting cases before trusting a visually plausible render.

## Deliverable Boundary

- For a design request, return the teaching objective and misconception, medium decision, storyboard or interaction states, variables/units/scales, accessibility controls, physics assumptions, and verification plan.
- For an implementation request, create or modify the requested artifact with the native presentation, browser, image, or video capability and run the relevant checks below. Do not stop at a storyboard when the user asked for a working artifact.
- Keep narration, captions, teacher prompts, or a static fallback sufficient to preserve the teaching point when motion is unavailable.

## Physics Coverage

- Mechanics: motion graphs, force balance, pressure, buoyancy, simple machines.
- Optics: reflection, refraction, lens imaging, ray tracing.
- Electricity: circuit state, current/voltage relationship, series/parallel comparison.
- Heat and sound: particle model, heat transfer, wave propagation.

## Verification

- Check physics correctness before visual polish.
- Verify claims, symbols, sign conventions, and expected observations against the named textbook/standard or another identified authoritative teaching source.
- Verify initial and final states, labels, and any numerical approximation against the model; disclose idealizations and not-to-scale choices.
- For interactive models, check representative parameter changes and boundary
  values against independent expected results. For example, with fixed nonzero
  resistance, doubling voltage should double current; zero resistance needs an
  explicit domain rule rather than an infinite or invalid displayed value.
- For time-based models, derive state from simulation time rather than frame
  count. Check pause/resume, stepping, and reset: pause must freeze the model and
  reset must restore parameters, time, and traces consistently.
- Run in desktop and classroom projector aspect ratios.
- For web/SVG output, verify the real entrypoint loads, the animation is nonblank, keyboard controls are reachable, focus is visible, motion can be paused, and Chinese labels fit. Exercise touch or pen input when the interaction contract requires it.
- If offline delivery is required, open the delivered artifact without network
  access and verify that fonts, media, libraries, and controls still work.
- Provide a short textual explanation or caption that preserves the teaching point when motion is unavailable.
