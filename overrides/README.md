# overrides/

Local override layer for skills. Put custom skills and local patches here instead of editing upstream caches.

Naming convention:

- `custom-*`: fully custom skills
- `patch-*`: patched variants based on upstream skills
- `<skill-name>`: direct same-name override (replaces the built output with the same name)

Notes:

- Prefer `custom-*` / `patch-*` for readability and maintenance.
- Use same-name override only when replacement semantics are required.
- Keep source imports in `vendors/` or `imports/`; treat `overrides/` as the local customization layer.
