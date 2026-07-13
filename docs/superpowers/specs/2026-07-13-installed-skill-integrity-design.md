# Installed Skill Integrity Design

## Goal

Every retained managed skill must be discoverable in an intended profile, load
valid instructions, resolve required local resources and cross-skill calls, and
fail with an actionable prerequisite message before a workflow reaches an
unavailable external runtime. Generated `agent/` content remains rebuildable
from `skills.json`, vendor/manual inputs, and `overrides/`.

## Integrity model

The verifier evaluates four layers:

1. Package: `SKILL.md` has valid frontmatter and every required relative
   Markdown resource exists.
2. Skill closure: explicit skill calls resolve to a unique installed skill and,
   when the caller is profile-enabled, the dependency is enabled in that
   profile too.
3. Tool declaration: `agents/openai.yaml` MCP dependencies are structurally
   valid and refer to a configured MCP server when they are required.
4. Runtime boundary: external CLIs, credentials, paid APIs, Office GUI, and
   project packages are not treated as globally installable skill packages.
   Smoke tests verify only safe prerequisites and no-side-effect entry points.

## Repair policy

- Repair projection-induced paths in the generator when the referenced source
  resource exists and has a mapped destination.
- Use a maintained override only when a small stable correction makes a useful
  skill self-contained.
- Remove a skill when its upstream package is structurally incomplete, the
  missing content is material, and a stronger retained skill covers the same
  user workflow.
- Do not synthesize missing third-party tutorials or install every runtime
  dependency globally.

## Verification command

Add a repository command/script that emits a machine-readable report and exits
non-zero for blocking package, closure, profile, or declared-tool failures.
Wire it into the full local quality gate after generated-sync and before tests.
Known optional links may be classified only through explicit repository policy;
the default is blocking.

## Acceptance

- Zero blocking integrity findings for retained skills.
- Zero duplicate projected skill names and zero profile budget failures.
- Every repaired or retained composite skill has a focused smoke assertion.
- Active profile is restored to `default` after profile tests.
- Build, unit/E2E, strict doctor, dependency baseline, and full quality gate pass.

## Safety and rollback

Smoke tests do not publish content, send messages, create remote issues, invoke
paid generation, or automate Office GUI. Rollback removes only this change's
config entries, overrides, tests, verifier, and generated output, then rebuilds
the managed projections.
