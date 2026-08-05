# Non-watch override and projection governance

## Goal and scope

This slice audits and hardens the repository-owned `overrides/` estate without changing the concurrently maintained interruption-recovery skill, its generated output, hooks, tests, runtime state, or prior evidence. The source-of-truth write set is limited to non-watch overrides, host-projection code, reference-shelf governance, deterministic corpora/tests, documentation, and this evidence file.

The classification is functional, not a claim about who originally typed each file. Git proves that these packages are repository-maintained; it cannot prove whether an earlier draft was human-written, AI-assisted, or generated.

## Inventory and disposition

| Class | Packages | Role | Decision |
| --- | --- | --- | --- |
| `overrides/custom/` | `capability-router`, `custom-creator-publishing`, `custom-junior-physics-animation`, `custom-powerpoint-accessibility`, `custom-powershell-windows-automation`, `custom-teacher-courseware-ppt`, `custom-windows-wpf-teacher-app`, `draft-spec`, `draft-tickets` | Repository-authored or repository-owned capability contracts | Keep. They cover distinct local-first routing, publishing, teaching, Windows automation/application, accessibility, and low-side-effect drafting seams. |
| frozen concurrent custom package | one separately maintained package | Outside this slice | No read/write promotion or quality decision in this slice. |
| `overrides/patches/` | `agent-skills-2-skills-code-review-and-quality`, `grill-with-docs`, `setup-matt-pocock-skills` | Intentional replacements/adaptations of upstream packages | Keep with fixed provenance and local-delta reasons. |
| `overrides/resources/` | `requesting-code-review` | Resource bridge without its own `SKILL.md` | Keep. `subagent-driven-development/SKILL.md` resolves `../requesting-code-review/code-reviewer.md`; deleting the bridge breaks a verified relative dependency. |

There are 13 projected `SKILL.md` packages across custom and patches. The resource bridge is a fourth storage role, not a hidden fourteenth skill. No package met the deletion threshold: none was both unused/unreachable and fully superseded with dependency closure proved.

## Root causes and changes

### Host projection promotion

`构建生效` previously allowed a dirty, uncommitted repository state to flow directly into repository-external host skill/config paths. The command now:

- permits repository-local builds and fixture targets without Git promotion;
- requires a resolvable clean Git commit before repository-external host projection;
- supports only an explicit `-AllowUnverifiedHostProjection` exception;
- preserves a successful `agent/` staging build when promotion is blocked while performing no host write;
- writes source revision, dirty state, Git state, promotion mode, promoted time, and truthful gate-receipt status into the projection manifest.

`gate_receipt.status=not_provided` is deliberate: the current full gate does not emit a commit-bound receipt, and the build step cannot require a receipt that is produced only after that same build. The manifest must not upgrade this absence into a false pass.

### Skill quality and metadata

- Narrowed `custom-junior-physics-animation` to physics pedagogy, misconception repair, medium selection, correctness, and classroom verification. A direct request for an interactive visualization remains owned by the native visualization capability.
- Changed the WPF teacher-app fallback from unconditional `dotnet build` to the target repository's real gates first.
- Added recommended `agents/openai.yaml` metadata to the six packages that lacked it. All 12 non-frozen override skills now carry parseable OpenAI metadata with a skill-qualified default prompt.
- Rebased the setup patch from `qa`/PRD terminology to the current upstream `to-tickets`, `triage`, `to-spec`, and `specs` language while retaining this repository's `AGENTS.md`/`CLAUDE.md` wrapper rules and explicit-only Codex policy.
- Added `overrides/patches/provenance.json` and a fail-closed validator. Upstream review inputs were:
  - `addyosmani/agent-skills@7829ffd90d973b6325f5f12f1b1226dcace74443` (MIT);
  - `mattpocock/skills` setup base `391a2701dd948f94f56a39f7533f8eea9a859c87`, grill base `2ab958093e83e0ec752e6c1c5932da465bf23e0c`, reviewed remote revision `c553e932f0606df0d52ee207b41a24d57a2beafb` (MIT).

### Activation and reference governance

- Added a 32-case, non-watch activation corpus covering direct, indirect, negative, and edge requests for eight previously under-covered overrides. This is a deterministic expectation/coverage gate; it does not claim live model-selection acceptance.
- Corrected the reference refresh pull-failure tier field and added full local/upstream revisions, `remote refs current`, `working tree matches upstream`, and `consumable revision`.
- Closed a path-containment gap in both the governance validator and the refresh runtime: rooted paths, drive-qualified paths, and `.`/`..` segments are rejected before normalization or any Git operation. The original implementation trimmed a leading slash and only rejected traversal at the beginning of a path, so `/absolute/path` and `nested/../../escape` could pass validation.
- Expanded the README to all 14 conditional candidates and added a deterministic validator for 29 manifest repos, the seven-repo default set, reviewed-candidate provenance, README coverage, and all three patch records.
- Added machine-readable `reviewed_at`, `review_evidence`, and `activation_trigger` to the five fixed-revision community candidates. The validator now keeps these candidates `conditional-not-cloned`, out of the default refresh set, and bound to an existing repository evidence file; no speculative expiry service or scheduled refresh was introduced.
- Kept fetch-only as the safe default. A real default refresh showed that fetched refs can be current while local checkouts remain behind, proving why the two states must not be collapsed.
- Replaced the untestable phrase “high-quality community implementation” in current product guidance with fixed-revision, license, real-consumer, and focused-gate criteria. `skills.sh`, GitHub Trending, and search remain discovery inputs rather than installation authority.

## Verification

Passed evidence:

- skill-creator `quick_validate.py` with UTF-8 mode: 12/12 non-frozen override skills valid;
- PyYAML parse and required OpenAI interface/default-prompt checks: 12/12;
- `verify-reference-governance.ps1`: 29 repos, 7 default repos, 3 patch provenance records;
- `verify-override-skill-activation.ps1`: 8 target skills, 32 cases, frozen package excluded;
- `verify-skill-integrity.ps1`: 107 projected skills;
- focused Pester: SkillProjection 35/35, Core 192/192, BuildCache plus QualityGateScripts 51/51; the Core suite includes behavioral rejection of rooted/traversal manifest paths before refresh operations.

The first full gate did not pass and is not recorded as success. It completed 875/876 Unit and 18/18 E2E cases, then stopped on the concurrently modified `agent workflow advisory` verifier (`stale_radar_fallback_missing`). That source/test set is outside this slice and was neither repaired nor reverted here.

After its owner repaired that verifier, a second combined-worktree full gate returned exit 0 on 2026-08-06: 886/886 Unit and 18/18 E2E cases passed; generated sync, repository hygiene, 107-skill integrity, 29-repository/7-default/3-patch reference governance, and the 8-target/32-case non-watch activation corpus also passed. The gate reported `suite_elapsed_ms=245930` and `total_elapsed_ms=253286`. It remains diagnostic-only because the concurrently owned watch slice changed files during its execution window.

The final stable-snapshot full gate then returned exit 0 with 886/886 Unit and 18/18 E2E cases, `suite_elapsed_ms=246861`, generated sync, 107-skill integrity, reference governance 29/7/3, the 32-case activation corpus, and all routing/dependency/config/host/planning/PS7/Agent/doctor contracts passing. SHA-256 snapshots of all 67 dirty/untracked paths were identical before and after the run, excluding only the expected deterministic `skills.ps1` regeneration, so no concurrent source drift overlapped this final gate. The verified source/generated integration was committed and pushed as `e80b5a6aba796bb377fbde8aea8e5b784367fa77`.

This post-gate evidence correction is receipt-only documentation (`gate_na`): alternative verification is `git diff --check`, exact diff review, and Git/remote parity; any executable, contract, fixture, or generated-file change would require rerunning the full gate.

## Truth boundary and rollback

- This non-watch slice performed no real skill/config host projection, active-profile switch, plugin/MCP install, auth/provider change, restart, or live acceptance.
- Root `build.ps1` verification and the final stable-snapshot full gate were run, but no host-projecting `构建生效` or full `agent/` rebuild was run. `overrides/` remains the source of truth; host promotion must occur later from a clean committed revision.
- The activation corpus proves coverage and consistency, not universal trigger precision or actual skill-body execution.
- The reference refresh fetched remote refs only; behind local checkouts were not pulled or reset.
- Roll back only the files listed by this evidence. Do not reset concurrent interruption-recovery, hook, agent-workflow, generated, or test changes owned by another task.
