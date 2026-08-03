# GPT-5.6 skill invocation policy and draft-only routing

## Scope

This slice separates useful design assistance from skills that scan broadly,
modify repository configuration, or publish external tracker objects. It is
implemented in `overrides/`, `skills.json`, the routing policy, and the
generated projection; vendor/import sources remain unchanged.

## Policy

| Skill | Invocation | Reason / side-effect boundary |
| --- | --- | --- |
| `grill-with-docs` | implicit allowed, explicit `$grill-with-docs` still supported | Narrow description matches design grilling only; interview writes `CONTEXT.md`/glossary/ADR only after a durable decision is confirmed. |
| `draft-spec` | implicit allowed | New engineering-profile skill; returns a Markdown draft in the response and does not write files, call a tracker, or invoke `to-spec`. |
| `draft-tickets` | implicit allowed | New engineering-profile skill; returns a dependency-aware vertical-slice draft and does not create tickets, links, labels, or files. |
| `improve-codebase-architecture` | explicit only | Performs a broad scan, calls Explore, and creates a visual HTML report before grilling. |
| `to-spec` | explicit only | Publishes a spec to the configured issue tracker. |
| `to-tickets` | explicit only | Publishes tickets and blocking relationships to the configured tracker. |
| `setup-matt-pocock-skills` | explicit only | Writes repository tracker/domain configuration; its Codex policy is now explicit in the same-name override. |

`draft-spec` and `draft-tickets` are routed only through `engineering`; they
are not added to `default` or `coding`. The new
`engineering-design-and-delivery` group documents the lower-side-effect draft
path and the explicit publication/setup/architecture boundaries.

## Generated projection evidence

- `skills.ps1 构建生效` exit `0`; `agent/` rebuilt with 106 local skills.
- The setup override retains all five upstream resource files (`domain.md`,
  both GitHub/GitLab tracker references, local tracker reference, and
  `triage-labels.md`) so `/MIR` cannot silently remove its runtime inputs.
- Default projection: `active=11`, metadata `6729/7500`, `entries=110`,
  `unique=110`, `disabled=99`, conflicts `0`.
- Engineering projection: `active=16`, metadata `7980/10000`; all seven
  invocation-policy skills are present in the projection manifest.
- Fresh Codex profile probe: all `16/16` configured profiles passed. The
  engineering probe checks draft skills and the seven policy skills in the
  projection; explicit-only setup is not required to appear in the initial
  prompt metadata list.

## Cache correctness fix

Clean builds recreate mapping destinations before applying same-name
overrides. A cache hit based only on the source fingerprint could therefore
skip the override and leave the imported skill in `agent/`. `Mirror-SkillWithCache`
now accepts `-ForceMirror`, and the override phase always uses it for this
clean-build replacement step. The regression test
`Forces an override mirror when a clean build recreated the target` proves the
cache hit cannot bypass the override.

## Verification

Commands were run in the repository fixed order:

```text
pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1                 # exit 0
pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1             # exit 0; Unit 503/0, E2E 12/0
pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict --threshold-ms 8000  # exit 0
python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline # exit 0
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree # exit 0
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-codex-skill-profiles.ps1 # exit 0; 16/16 profiles
```

The full gate reported generated-sync, skill-integrity, routing (`findings=0`),
dependency baseline, doctor contract, Unit/E2E success, and
`Local quality gates passed (full)`.

`draft-spec`, `draft-tickets`, and `grill-with-docs` were validated with the
skill-creator `quick_validate.py` under Python UTF-8 mode and returned
`Skill is valid!`. The setup override intentionally retains the upstream
Claude-compatible `disable-model-invocation: true` field; the current Codex
validator rejects that cross-host field even though Codex reads the explicit
policy from `agents/openai.yaml`, so setup is verified by repository integrity,
projection, and the explicit-policy assertion instead.

## Rollback

Remove the four new/changed override directories, restore the previous
`engineering.enabled_names`, remove the engineering routing group and the
`ForceMirror` test/code change, rebuild, and rerun the fixed gate. Do not
revert unrelated existing dirty files or imported gitlinks.
