---
name: custom-windows-wpf-teacher-app
description: Use when designing, reviewing, or implementing Windows-first teacher desktop software, especially WPF/.NET classroom tools with touch, pen, PDF/image/PPT presentation, dual-screen, startup, recovery, and local data workflows.
---

# Windows WPF Teacher App

Use this skill for practical classroom software on Windows machines.

## Product Priorities

1. Teacher workflow speed beats decorative novelty.
2. Touch, pen, projector, and low-friction file handling are first-class.
3. Offline/local-first behavior should remain usable without cloud services.
4. Recovery and export matter: a teacher should not lose classroom state after a crash or power issue.

## Engineering Checks

- Keep domain/application logic away from WPF views and interop.
- Use explicit dispatcher boundaries for UI thread work.
- Treat second-screen, full-screen, topmost, slideshow control, and overlay behavior as contracts with tests or probes.
- For settings and startup, verify load latency and corrupt-config fallback.
- For file workflows, test Chinese paths, OneDrive paths, locked files, and removable media.

## UI Checks

- Touch targets must be large enough for classroom use.
- Avoid tiny toolbar-only affordances for core teaching actions.
- Support presenter view, navigation/search/bookmarks, richer ink tools, and accessible labels where relevant.

## Verification

- Run `dotnet build` and focused tests.
- Use `-p:UseSharedCompilation=false` when compiler server locks cause noisy local failures.
- For UI changes, capture before/after screenshots or run a manual classroom-flow probe.
