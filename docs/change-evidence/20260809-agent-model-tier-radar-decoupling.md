# Agent model tiers and Radar decoupling

**Date**: 2026-08-09
**Scope**: active agent-workflow advisory model contract
**Truth boundary**: repository implementation and deterministic verification only; no host restart, spawn acceptance or live acceptance

## Goal

Align the active advisory contract with the host-owned three-tier policy:

- `sol_xhigh = gpt-5.6-sol / xhigh`
- `sol_medium = gpt-5.6-sol / medium`
- `sol_low = gpt-5.6-sol / low`

Radar, external rankings and historical model probes must not influence active
proposal validation, fallback, evidence priority or tier escalation. Historical
Radar v2 receipts remain readable through the existing pure validator.

The host autonomy settings requested by the user, including
`approval_policy = "never"` and
`default_permissions = ":danger-full-access"`, were not changed.

## RED

Focused Pester initially produced `28 passed / 2 failed`:

- `sol_low` returned no anchor;
- a `sol_low` capacity failure returned `supervisor_review` instead of bounded
  escalation to `sol_medium`.

A separate regression proof temporarily restored Radar request validation and
produced `29 passed / 1 failed`: an otherwise valid request with an empty
legacy Radar entry set was rejected. Removing the active validation restored
the intended compatibility boundary.

## Changes

- Replaced the active `luna_max` anchor with `sol_low` and updated the bounded
  capacity escalation chain.
- Kept the `RadarSnapshot` parameter for old named-call compatibility, but the
  proposal and request validators do not validate, read, prioritize or emit
  Radar data.
- Preserved `New-RadarSnapshot` and `Test-RadarSnapshotContract` as legacy
  read-only receipt parsers.
- Updated fixtures, verifier, current product truth, task truth and planning
  documentation. Historical evidence files were not rewritten.
- Moved old Luna/Radar probe facts under manifest
  `legacy_read_only_receipts`; they cannot unlock an active tier.

## Verification

- focused Pester: `39 passed / 0 failed`
- build: exit `0`
- `agent-validate`: pass, findings `0`, effects `0/0/0`
- `agent-plan`: pass; selected `sol_low / gpt-5.6-sol / low`; Radar absent
  from proposal evidence; effects `0/0/0`
- advisory verifier: pass, findings `0`

The authoritative final stable-tree result is the immutable receipt under
`reports/quality-gates/` selected by `reports/quality-gates/current.json`.
Git closeout is verified separately against `origin/main`; this evidence file
is intentionally frozen before the full run so the receipt binds the exact
tracked source tree.

## Rollback

Revert only this logical slice and rebuild `skills.ps1`. Do not restore the
deleted Radar automation or alter host permission/autonomy settings as part of
repository rollback.
