# Capability router seamless routing

## Goal and boundary

- Problem: profile-only routing makes installed skills unreachable in a running Codex task and cannot hot-reload the initial skills list.
- Target: keep one portable metadata router resident, select cold skills, and read the selected `SKILL.md` in the current task.
- Non-goals: no Codex restart, task creation, profile mutation during routing, provider call, plugin mutation, or direct edit under `agent/`.

## Basis and decisions

- Official Codex manual: the initial list contains skill name, description, and path; the full body loads after selection. The initial list uses at most 2% of context or 8,000 characters when context is unknown.
- Community reference: `legendtkl/agentic-skill-router` at `160b30f0b67c923077f886376fdfae1016a70702` (MIT) informed metadata corpus, abstention, and selected-path output. Its `SKILL.md` rename/disable mechanism was rejected because this repository already has a fail-closed projection contract.
- Adaptation: `resident_names` is a projection-level union; profiles remain explicit preheat bundles. `capability-router` reads the existing projection manifest and routing policy, validates path containment, selects at most three leaves, and performs no writes.

## Write set and rollback

- Sources: `overrides/capability-router/`, `src/Commands/SkillProjection.ps1`, `src/Config.ps1`, `config/skills.schema.json`, `config/skill-routing-policy.json`, `skills.json`.
- Generated: `skills.ps1`, `agent/capability-router`, `reports/skill-projection/current.json`, and the managed skills projection block in Codex config.
- Tests/docs: `tests/Unit/CapabilityRouter.Tests.ps1`, `tests/Unit/SkillProjection.Tests.ps1`, `scripts/verify-codex-skill-profiles.ps1`, `README.md`.
- Rollback only these source changes, run `build.ps1`, then `skills.ps1 构建生效`; restore the projection backup recorded by the successful sync only if the generated rollback cannot run.

## Verification record

- `python .../skill-creator/scripts/quick_validate.py overrides/capability-router`: pass.
- Targeted Pester (`CapabilityRouter.Tests.ps1`, `SkillProjection.Tests.ps1`): 35 passed, 0 failed before final closeout rerun.
- First `skills.ps1 构建生效`: fail-closed because seven profiles exceeded 8,000; transaction restored `agent/`.
- Profile slimming moved low-frequency executors to cold loading.
- Second `skills.ps1 构建生效`: pass; 110 unique skills, 95 disabled from initial injection, projection persisted.
- Final targeted Pester: 43 passed, 0 failed.
- Full profile verifier: all 16 profiles passed fresh `codex debug prompt-input` probes and restored `default`.
- Final projection: `default`, resident `capability-router`, 110 unique, 8 initially active, `6050/8000`; all profiles pass and the largest is `marketing=7728/8000`.
- Fresh default prompt: router visible; `grill-with-docs` and `debug:dotnet` absent. Runtime router selected `grill-with-docs` with `selection_mode=cold_load`, `writes_performed=false`.
- Full tests: Unit 679 passed; E2E 18 passed.
- Contract order passed: strict doctor, dependency baseline, host capability matrix, vNext planning, P4 entry gate.
- First full quality run stopped at generated-sync because the new generated `skills.ps1` was intentionally uncommitted relative to HEAD. Rerun with the repository-supported `-AllowDirtyWorktree` flag passed build, repo hygiene, generated hash stability, full tests, skill integrity, skill routing, dependency/config/host/planning contracts, and doctor JSON.
