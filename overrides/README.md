# overrides/

`overrides/` is the local customization layer for `skills-manager`. Use it for changes that should survive upstream updates without patching `vendor/` caches or generated `agent/` output directly.

## What Belongs Here

- fully custom skills
- local patch variants of upstream skills
- intentional same-name replacements of generated output
- repo-local prompt overrides such as `audit-outer-ai-prompt.md`

## Naming Convention

- `custom-*`: fully custom skills
- `patch-*`: locally patched variants of upstream skills
- `<skill-name>`: direct same-name replacement when override semantics must replace the generated output

Prefer `custom-*` and `patch-*` for readability. Use same-name replacement only when you intentionally want the override to win over the generated artifact with the same target name.

## Reserved / Common Override Points

- `audit-outer-ai-prompt.md`
  Overrides the default outer-AI audit prompt source used to generate runtime `reports/skill-audit/<run-id>/outer-ai-prompt.md`.

## What Does Not Belong Here

- edits to `vendor/` caches
- manual fixes to generated `agent/` output
- runtime audit artifacts under `reports/skill-audit/<run-id>/`
- host-local CLI state such as `.codex/`, `.claude/`, `.gemini/`, `.trae/`
