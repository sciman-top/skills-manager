# overrides/

`overrides/` is the reviewed local input layer for content that must survive upstream refreshes. The first directory level classifies ownership and maintenance intent; the leaf directory name remains the stable output name under `agent/<leaf>`.

## Classified directories

| Source path | Use | Typical contents |
|---|---|---|
| `custom/<leaf>/` | Content authored and owned by this repository | Custom skills, capability routers, draft workflows, and local operational skills |
| `patches/<leaf>/` | A locally maintained replacement or correction for upstream content | Same-name upstream replacements and compatibility patches |
| `resources/<leaf>/` | A resource bridge that is copied into the generated tree but is not itself an installed skill | Prompt fragments or reviewer resources without `SKILL.md` |

Every non-empty leaf is projected to `agent/<leaf>` regardless of category. Leaf names must therefore be unique across `custom/`, `patches/`, `resources/`, and the legacy flat layout. Discovery fails closed when two inputs claim the same output name.

The generator backs up removed classified inputs under `.bak/<category>/`. Do not add `.bak/` content to normal discovery.

## Root-level file overrides

Keep only explicitly named, single-file extension points at the root. These files are optional and may be absent until needed:

- `audit-outer-ai-prompt.md` overrides the default outer-AI audit prompt copied to a runtime audit bundle.
- `audit-source-strategy.json` overrides the default audit source-strategy template.

Do not put general skills or resource directories at the root.

## Legacy compatibility

Non-empty flat directories such as `overrides/<leaf>/` remain readable during the migration window so existing portable packages do not break. They are legacy inputs only: do not create new flat directories, and move any maintained legacy directory into the appropriate classified directory when it is next changed.

## What does not belong here

- edits to `vendor/` caches or third-party import snapshots
- manual fixes to generated `agent/` output
- runtime artifacts under `reports/`
- empty placeholder directory shells
- host-local state such as `.codex/`, `.claude/`, `.gemini/`, or `.trae/`

## Maintenance gates

- Validate every changed `SKILL.md` with the repository's skill-creator-compatible validation and keep `agents/openai.yaml` aligned when present.
- Record every `patches/<leaf>` source, fixed revisions, license, and local delta in `patches/provenance.json`.
- Keep a named repository consumer for every `resources/<leaf>` bridge; a resource bridge without a consumer is a deletion candidate.
- Run `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-skill-integrity.ps1` for the projected estate.
