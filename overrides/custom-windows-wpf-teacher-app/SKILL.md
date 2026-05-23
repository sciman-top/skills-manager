---
name: custom-windows-wpf-teacher-app
description: Use when designing, reviewing, implementing, observing, or operating Windows-first desktop software, especially WPF/.NET teacher tools with touch, pen, PDF/image/PPT presentation, dual-screen, startup, recovery, local data workflows, screenshots, and UI Automation probes.
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

## Desktop UI Observation

- First identify the real running entrypoint, process name, window title, config/state path, and whether the app is single-instance.
- Prefer non-invasive evidence first: screenshot, window bounds, logs, current config, and command output.
- For WPF/.NET apps, prefer Microsoft UI Automation based probes, then FlaUI for .NET test code, or pywinauto for ad-hoc Python inspection when a repo already supports Python.
- WinAppDriver/Appium-style routes are acceptable only when the project already carries that dependency or the user explicitly wants a broader desktop E2E harness.
- Do not treat Playwright browser success as proof that a native Windows desktop surface works. Browser automation only verifies web/Electron/webview surfaces.
- Ask before starting, stopping, rebuilding, or replacing a long-running desktop app when that could interrupt the user's current session.

## Desktop UI Operation

- Use stable automation identifiers, accessible names, and window handles before image-coordinate clicks.
- If coordinate/pixel actions are unavoidable, record the screenshot, region, DPI/scaling assumptions, and rollback path.
- For touch-first classroom flows, verify tap targets, drag/ink gestures, full-screen mode, projector/secondary display behavior, and recovery after window focus changes.
- For visible app changes, capture before/after screenshots or a short manual probe transcript with the exact commands and observed result.

## UI Checks

- Touch targets must be large enough for classroom use.
- Avoid tiny toolbar-only affordances for core teaching actions.
- Support presenter view, navigation/search/bookmarks, richer ink tools, and accessible labels where relevant.

## Verification

- Run `dotnet build` and focused tests.
- Use `-p:UseSharedCompilation=false` when compiler server locks cause noisy local failures.
- For UI changes, capture before/after screenshots or run a manual classroom-flow probe.
