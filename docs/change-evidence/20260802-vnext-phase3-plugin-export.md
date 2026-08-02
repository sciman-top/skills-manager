# Phase 3 bounded skills-only exporter

## Result

- `SMV-P3-004 = done` at fixture-only scope.
- Export requires `.skills-manager-fixture`, exact token, root-contained source/output, new output, no reparse tree, at most 8 skills/256 files/2 MiB, repeated distribution evidence and completed official-equivalent review.
- It builds a sibling staging directory, validates/hash-checks it, then renames once; failure removes only its staging directory.

## Evidence

- Two teaching skills exported with byte/hash-equivalent `SKILL.md` files.
- Wrong token, missing marker, outside/existing output, nested Junction and 9-skill candidate all blocked before durable output.
- Generated CLI `plugin-export`: exit 0, pass=true, skills=2 in a `%TEMP%` fixture.

## Boundary and rollback

No real plugin folder, marketplace or host cache was changed. Delete only a receipt-identified fixture output to roll back an export; removing source/tests/route and rebuilding rolls back code.
