# `custom-powerpoint-accessibility` activation and real business workflow

**Date**: 2026-08-11
**Scope**: one explicitly authorized custom skill lifecycle pilot and one real PPTX accessibility audit
**Input**: `D:\CODE\physicist_chinese_poster_batch_tool\outputs\final-delivery\courseware\person\person-courseware.pptx`

## Authorization and boundaries

The user explicitly approved activation of `custom-powerpoint-accessibility` after
the promotion review. The operation was limited to the repository-managed skill
projection. It did not modify provider, auth, model, sandbox, notification, MCP,
plugin or Desktop/Codex configuration, and it did not restart Desktop or Codex.

The historical read-only P6 probe in
[`20260811-p6-host-acceptance.md`](20260811-p6-host-acceptance.md) remains a
point-in-time record of the state before this approval. This document is the
current follow-up receipt and does not rewrite that historical observation.

## Activation, projection and repository gate

- Activation receipt: `reports/skill-evolution/pilot-20260811-141301/approval/activation-receipt.json` (`status=applied`).
- Projection receipt: `reports/skill-evolution/pilot-20260811-141301/approval/projection-receipt.json` (`status=projected`).
- Managed projection: `C:\Users\sciman\.agents\skills\custom-powerpoint-accessibility` Junction -> `D:\CODE\skills-manager\agent\custom-powerpoint-accessibility`.
- The projected `SKILL.md` hash is `09a41780c88b87e26e0c9f03188a8325ef228914bb624a01f99043aed1b6207e`.
- The projection receipt records 7 enabled skills and a plan-only `skills/changed` notification (`status=not_sent`, `host_mutation=false`).
- Exact-current full gate: `reports/quality-gates/qgr-20260811-143707-01782d16.json`, `15/15` gates passed, `986` test cases passed, source HEAD `879ae48cf2fb62a571d59645f0630f5149697c4f`.

## Fresh surface view

The saved read-only snapshot is
`reports/skill-evolution/pilot-20260811-141301/approval/surface-snapshot.json`.
It reports zero findings and zero stale links with these source-explained counts:

| Surface | Count | State |
| --- | ---: | --- |
| `repo_supply` | 89 | fresh/complete |
| `canonical_projection` | 12 | fresh/managed projection |
| `user_skill_root` | 7 | fresh/filesystem observation |
| `system` | 6 | fresh |
| `plugin_cache` | 45 | fresh |
| `host_visible` | 0 | not observed |

This proves a managed filesystem projection, not that a new Desktop task loaded
the skill or that the host invoked it.

## Real PPTX workflow

The complete workflow receipt is
`reports/skill-evolution/pilot-20260811-141301/business-workflow/business-workflow-receipt.json`.
The agent used the projected skill body to perform a read-only OOXML audit,
converted the 571-slide deck with LibreOffice 26.2.4.2, rendered all 571 pages
with Poppler, and visually inspected a representative montage plus slides 1 and
571. The source PPTX was not modified.

Observed results:

- No structured title placeholders were found across 571 slides.
- All 556 picture descriptions were filename-like (`*.jpg`/similar), so they
  cannot be treated as verified semantic alt text.
- There were no speaker-note slides, hyperlink objects, tables, or audio/video
  objects; four text nodes contained raw URLs.
- The OOXML package exposed no section metadata groups, so reading/navigation
  structure remains unverified for a 571-slide sequence.
- Slide 1 has visible overlap in the orange contact block; slide 571 has dense
  text at the page boundaries with clipping/overflow risk.

The business result is therefore `accessibility_status=needs_fixes`. Microsoft
PowerPoint (`powerpnt.exe`) is not installed, so the native Accessibility
Checker, Selection Pane/reading-order review, and screen-reader verification
remain `not_run`/`not_verified`. LibreOffice rendering is useful visual evidence
but is not a substitute for those native checks.

## Truth boundary after this pilot

| Layer | Current truth |
| --- | --- |
| Repository source and gates | `repo_verified` |
| Activation | `applied` |
| Managed filesystem projection | `projected` |
| Host inventory/visible surface | `not_observed` |
| Host skill selection | `host_evaluation_partial` only |
| Authoritative host invocation | `host_invocation_observed=not_observed` |
| Real PPTX workflow | executed; result `needs_fixes` |
| Live acceptance | `not_accepted` |

No model self-report, ordinary output, or reading of `SKILL.md` is promoted to
an authoritative `injected -> executed` host event chain. A future fresh
ChatGPT Desktop task must provide a schema-v1 `native_host_events` receipt before
the invocation truth can change.
