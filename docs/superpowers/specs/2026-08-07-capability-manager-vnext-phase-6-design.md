# skills-manager vNext Phase 6: Host-Native Skill Lifecycle Reset

**program_id**: `skills-manager-vnext`
**current_phase**: `P6`
**status**: `repo_verified; host_evaluation_partial`
**admission_date**: `2026-08-07`

## 1. Problem

P5 证明了 catalog、projection、profile、cold discovery 和 deterministic policy 可以在仓库内工作，却没有解决“宿主是否会在请求开始时看见并调用正确技能”。47 个历史未路由技能、`grill-with-docs` 等 profile 外技能和多次 fresh-task 回放共同暴露了同一个结构性问题：仓库可发现性、宿主初始 metadata、宿主语义选择和完整 skill body 注入没有形成一条宿主拥有的闭环。

把 `capability-router` 常驻、让所有非平凡请求展开完整 catalog、继续切 profile 或增加 cold-load 层，只会建立第二套语义路由真源，并把 token、延迟、trace 和热加载缺口继续留给用户。

## 2. Goal

将产品重构为 host-native skill lifecycle manager：宿主 AI 依据原生 progressive disclosure 自动选择技能；skills-manager 只编译完整 inventory、保证所有 enabled skill 都进入宿主可发现面、计算有效 metadata 预算、执行 eligibility/safety policy、验证 projection 和记录 invocation trace。App Server strict dispatch 只为明确要求强制分发或宿主原生选择不可用的 surface 提供窄 fallback。

## 3. Domain language

- `HostCapabilitySnapshot`：某个 surface/thread/turn 的有效模型、上下文窗、skill metadata budget、宿主 skills inventory 和 capability 来源快照。
- `CanonicalSkillInventory`：由 skill roots、projection config 和 package metadata 编译出的完整技能集合。
- `NativeDiscoverySet`：本 turn 允许宿主原生看到并语义选择的 enabled skill metadata 集合。
- `SkillEligibilityDecision`：对 containment、freshness、availability、dependency、side effect、approval 和 surface compatibility 的确定性判决。
- `NativeInvocationTrace`：宿主列举、选择、注入、执行或 abstain 的可观测事件；缺少某层时必须标记 partial。
- `StrictDispatchRequest`：显式要求 pre-turn 强制判决的请求，不是普通请求默认入口。
- `ProfileCompatibilityView`：迁移期只读兼容输出，不再决定技能可达性。

## 4. Target flow

```text
effective host capability
  -> canonical inventory compiler
  -> deterministic eligibility policy
  -> token-aware native metadata projection
  -> host AI semantic selection
  -> host-native full SKILL.md injection
  -> ordinary tool/auth/approval execution
  -> invocation trace + evaluation

strict/fallback only:
pre-turn dispatch -> small candidate set -> host adjudication -> App Server type=skill injection -> trace
```

## 5. Architecture reset

Retire from the default runtime path:

- mandatory resident `capability-router` dispatch;
- full portable catalog expansion for every non-trivial request;
- profile membership as reachability or semantic routing boundary;
- `active_profile`, profile switch, reconciliation and canary as normal operations;
- `current_profile` fallback and domain cold-discovery as primary selection;
- script-owned lexical, embedding or second-model semantic ranking.

Retain and deepen:

- inventory/catalog compiler and source provenance;
- projection transactions, rollback, supply-chain and generated-sync contracts;
- path containment, hash/freshness, availability, dependency and side-effect policy;
- concise metadata linting and positive/negative/indirect activation evaluation;
- host adapters, effective capability snapshot and invocation trace;
- historical profile/router artifacts as read-only migration inputs until removal gates pass.

## 6. Host capability source precedence

`HostCapabilitySnapshot` resolves facts in this order:

1. explicit turn override;
2. thread effective model and runtime capability;
3. effective layered host configuration;
4. model catalog/provider capability;
5. conservative unknown-context fallback.

Adapters:

- App Server: `config/read`, `model/list`, `modelProvider/capabilities/read`, `skills/list`, `skills/changed` and supported skill item injection.
- CLI: fresh `codex debug prompt-input` probe.
- Offline: direct `config.toml` read marked `source=config_fallback`; it is never promoted to current runtime truth by itself.

For a known context window, the host metadata ceiling is `floor(model_context_window * 0.02)` tokens unless the current host reports a stricter value. The planner reserves configurable headroom (initial policy: 20%) and optimizes description compactness before omitting any enabled skill. Acceptance is based on `enabled_total == kept_total`, `truncated=false`, and `omitted=0`, not on a fixed character budget.

## 7. Technology stack

- PowerShell 7 modular monolith remains the authoritative orchestration, compatibility CLI, filesystem adapter and generated single-file distribution path during P6.
- Pure contracts use plain ordered objects plus JSON Schema-compatible validation; no database, daemon, embedding service or provider call is added.
- Existing package-free C#/.NET typed-core remains `shadow_only`; P6 may define a future seam but does not couple this reset to TC2.
- Pester provides unit/contract/fixture tests; native App Server/CLI probes provide separate host evidence.
- Git, content hashes, atomic replace, receipts and the existing full quality gate remain the transaction/evidence substrate.

## 8. Interfaces and seams

1. `IHostCapabilitySnapshotProvider.GetSnapshot(surface, thread, overrides)` returns facts with source, captured time, freshness and unknown reasons.
2. `ISkillCatalogCompiler.Compile(roots, projection)` returns canonical entries and provenance without profile filtering.
3. `ISkillEligibilityPolicy.Evaluate(skill, snapshot)` returns allow/deny/needs-activation plus findings; it never ranks semantics.
4. `INativeMetadataPlanner.Plan(inventory, snapshot, policy)` returns the all-enabled projection, token estimate, headroom and omission evidence.
5. `INativeSkillProjection.Apply(plan, token)` performs explicit atomic projection and rollback receipt.
6. `INativeInvocationTraceReader.Read(scope)` normalizes host events and truth level.
7. `IStrictDispatchAdapter.Dispatch(request, candidates)` is opt-in, bounded and host-adjudicated; it cannot become the default selector.

## 9. Compatibility and migration

- P5 manifests/specs/evidence remain immutable historical truth.
- Existing `skills.json` profile fields are read during migration, but new projection and selection code cannot use them to exclude an enabled skill from native discovery.
- Router scripts first enter shadow comparison, then compatibility-only mode, then deletion after two release cycles or equivalent user-approved evidence.
- Profile advisor/canary commands first warn deprecated, then become read-only migration reports, then are removed with schema migration and rollback notes.
- Generated `agent/` content is changed only through source/config/override and `build.ps1`.

## 10. Evaluation strategy

The corpus must include direct requests, indirect requests, negative mentions, ambiguous multi-skill requests, no-skill controls and formerly unreachable skills. It measures:

- metadata completeness and truncation;
- host selected skill names when observable;
- full body injection/invocation when observable;
- false positive, false negative, abstention and correction rate;
- token estimate, TTFV and tool rounds;
- differences between native-only and strict fallback.

Deterministic repo tests prove contracts only. Fresh App Server/CLI replay is `host_evaluation_partial` unless selection and full body invocation are both observable. Business outcomes remain `live_accepted` only after separate authorized use.

## 11. Tasks

- `SMV-P6-001`: admit P6 and freeze the historical supersession map.
- `SMV-P6-002`: define `HostCapabilitySnapshot` and source precedence.
- `SMV-P6-003`: implement App Server and CLI/offline snapshot adapters.
- `SMV-P6-004`: split catalog compiler and deterministic eligibility policy from router semantics.
- `SMV-P6-005`: implement token-aware all-enabled native metadata planning.
- `SMV-P6-006`: project every eligible skill into the native discovery surface.
- `SMV-P6-007`: build concise metadata linting and activation evaluation corpus.
- `SMV-P6-008`: add normalized native invocation trace and truth levels.
- `SMV-P6-009`: shadow-compare native selection with the legacy router/profile path.
- `SMV-P6-010`: retire profile reachability and migrate configuration/contracts.
- `SMV-P6-011`: provide the opt-in strict App Server dispatch fallback.
- `SMV-P6-012`: execute staged removal, documentation, release and acceptance closeout.

## 12. Ordered verification

1. `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1`
2. affected Pester tests during iteration; do not invoke the full suite separately at closeout
3. `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-host-native-skill-lifecycle-planning.ps1`
4. `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-vnext-planning.ps1`
5. affected inventory/config/projection/routing contracts
6. fresh CLI/App Server probes only for tasks whose exit gate requires host evidence
7. full local quality gate once for phase closeout

## 13. Failure routing

- Unknown effective context or budget: use conservative fallback, expose the source, and block claims of complete native projection.
- Metadata overflow: compact descriptions and report exact offenders; do not silently restore profiles or omit enabled skills.
- Host selection mismatch: repair metadata/corpus first; do not add lexical routing rules.
- Policy failure: fix containment/freshness/dependency/side-effect facts; semantic confidence cannot override denial.
- Missing invocation trace: retain `host_evaluation_partial`; do not infer full body use from visibility.
- App Server surface unavailable: native-only remains primary; strict fallback is `platform_na`, not a reason to add a custom daemon.

## 14. Stop conditions and rollback

Stop on unknown concurrent write overlap, generated drift, schema incompatibility without migration, inability to retain all enabled skills under the effective host contract, or any full-gate failure. Roll back only the current task slice using its receipt/commit; never rewrite P5 evidence or unrelated worktree changes.

## 15. Done definition

P6 is complete only when all 12 tasks are `done`, all eligible enabled skills are present in fresh native metadata without truncation, profile/router membership no longer controls reachability, representative native selection and invocation evidence meets the declared truth level, strict fallback remains opt-in, legacy paths have a tested migration/removal receipt, and the unique full gate passes. This planning package alone is only `planning_contract`, not runtime implementation, host loading or live acceptance.
