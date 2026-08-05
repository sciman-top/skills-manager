---
name: custom-junior-physics-animation
description: "Use when junior-middle-school physics pedagogy is the hard part: establish the lesson goal and misconception, validate the physics, choose among web/SVG, Manim, PPT, or static media, and define classroom verification. Do not use merely to create an interactive visualization, image, video, or slide artifact when a native artifact capability directly handles the request."
---

# Junior Physics Animation

Use this skill when the goal is teaching a concept through motion or interaction.

## Choose The Medium

- SVG/HTML/CSS/JS: best for lightweight classroom web demos, force diagrams, ray diagrams, circuit toggles, graphs, and drag interactions.
- D3: best for data, graphs, coordinate systems, and variable relationships.
- Manim: best for formula derivation, geometry, vector decomposition, and exported short videos.
- PPT animation: best when the teacher needs simple step-by-step reveal without running a browser.

## Design Rules

1. Establish the target grade, textbook/standard, lesson objective, and the misconception or phenomenon the visual should resolve.
2. Use animation only when change over time, causality, or interaction adds teaching value; prefer a static annotated diagram for a state that does not need motion.
3. Keep variables visible: value, unit, direction, and sign convention.
4. Use color consistently, but never make color the only carrier of force/vector, path/ray, measured quantity, or result.
5. Provide pause/replay/step controls for classroom pacing, plus a reduced-motion or static fallback.
6. Use physically meaningful scales or clearly label schematic/not-to-scale scenes.

## Physics Coverage

- Mechanics: motion graphs, force balance, pressure, buoyancy, simple machines.
- Optics: reflection, refraction, lens imaging, ray tracing.
- Electricity: circuit state, current/voltage relationship, series/parallel comparison.
- Heat and sound: particle model, heat transfer, wave propagation.

## Verification

- Check physics correctness before visual polish.
- Verify claims, symbols, sign conventions, and expected observations against the named textbook/standard or another identified authoritative teaching source.
- Run in desktop and classroom projector aspect ratios.
- For web/SVG output, verify animation is nonblank, keyboard controls are reachable, focus is visible, motion can be paused, and Chinese labels fit.
- Provide a short textual explanation or caption that preserves the teaching point when motion is unavailable.
