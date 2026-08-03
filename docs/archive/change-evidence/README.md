# Historical change-evidence archive

This directory preserves immutable historical evidence that is no longer part of the active reviewed change ledger.

## Audit runtime receipts

- Location: `audit-runtime-receipts/`
- Preserved files: 115
- Date range: 2026-04-23 through 2026-07-17
- Source: legacy `docs/change-evidence/*-audit-runtime-*.md`
- Disposition: moved without content changes; file names and Git history remain the lookup index

These files are machine-generated scan, dry-run, discovery, candidate, and apply receipts. They remain historical truth, but they must not be used as current logical-slice closeout evidence or copied back into `docs/change-evidence/`.

Current runtime receipts belong beside their ignored audit bundle under `reports/skill-audit/<run-id>/runtime-evidence-*.md`. Current reviewed logical-slice evidence remains under `docs/change-evidence/`.

## Reviewed historical slices

- Location: `reviewed-slices/`
- Preserved files: 113
- Selection rule: the exact evidence file name is no longer referenced by current source, task manifests, product documentation, or operational documentation
- Disposition: moved without content changes; file names and Git history remain the lookup index

These records remain reviewed historical truth, but they are no longer part of the current working evidence set. The active ledger retains 40 evidence files that are still referenced by current repository truth or are required for the current remediation slice. Archiving is reversible and does not weaken any declared task-to-evidence link.
