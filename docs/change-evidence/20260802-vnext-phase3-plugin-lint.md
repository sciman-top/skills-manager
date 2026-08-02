# Phase 3 plugin manifest and supply-chain lint

## Result

- `SMV-P3-003 = done` at static/fixture scope.
- Lint validates kebab-case identity, SemVer, description, repository, SPDX-like/LicenseRef license, bounded component paths, skill structure, reparse points and sensitive property names.
- Shape advisor selects the smallest declared shape without inventing MCP/UI.

## Evidence

- Official-compatible skills-only fixture passed.
- Missing license, path traversal, invalid SemVer and sensitive-key fixtures failed with stable finding codes.
- Generated CLI `plugin-lint`: exit 0 and pass=true for the valid fixture.

## Boundary and rollback

The validator does not claim public submission compliance or online SPDX validation. Remove the domain/schema/tests and rebuild to roll back this slice.
