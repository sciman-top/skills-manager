# Desktop-native acceptance and governance compression

**scope**: one representative Codex Desktop task in `D:\CODE\skills-manager`
**maximum claim**: `desktop_representative_accepted`; not universal model/task correctness

## Outcome

The active host task `019febba-ed8e-77f3-ba4a-c7840d740db6` identifies its
originator as `Codex Desktop`. The host exposed the existing `openai-docs` and
`codebase-design` skills, loaded their instructions, and reused them in a real
repository decision: official Codex skill semantics established the native
surface, then the deep-module deletion test located the obsolete repository
seam.

- Discoverability: both skills were present with their real paths in the
  Desktop task capability surface.
- Reuse: existing skills handled official-source lookup and architecture
  judgment without a new wrapper, router, profile, or runtime.
- Behavior consistency: the result follows native-first, shortest-main-chain,
  and self-retiring behavior by deleting zero-consumer telemetry/dispatch code
  and keeping the host as semantic owner.

This sample does not claim that every implicit match, model version, repository,
or future task will behave identically. Reopen only after a repeated real
Desktop failure in discovery, reuse, or behavior.

## Simplification

`PP-000` is reduced to three constraints: native first, shortest real main
chain, and lowest-sufficient/self-retiring. The current planning verifier keeps
only those three markers plus the existing project mapping. The repository
removes `NativeInvocationTrace`, strict App Server dispatch, the unused skill
injection adapter, their dedicated tests, and their generated bundle content.

## Verification

- `build.ps1`: passed; generated `skills.ps1` contains no retired Module.
- Affected Pester (`ProductPlanning`, `BuildCache`,
  `HostNativeSkillLifecycleCloseout`): `56 passed / 0 failed`.
- Current planning verifier: `12/12 done`, `0 open`, `0 findings`, truth level
  `desktop_representative_accepted`.
- Generated sync and `git diff --check`: passed.
- Active source/generated/test scan: no remaining invocation-trace or strict
  dispatch references.

The final full-gate status remains owned by the immutable runtime receipt under
`reports/quality-gates/current.json`; it is verified after this tracked input is
frozen rather than copied into this evidence file.
