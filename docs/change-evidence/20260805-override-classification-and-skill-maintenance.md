# Change Evidence — Override Classification and Skill Maintenance

## Result

- Scope: `overrides/` ownership classification, stable output discovery, selected skill maintenance, generated projection, and host skill links.
- Repository status: `repo_verified`.
- Host projection: `projected` with 111 unique names, 0 conflicts, and all profile budgets passing.
- Current-task hot load: `not_claimed`; persisted projection does not rewrite the skill context already loaded by an active task.
- Live task-quality acceptance: `not_run`.
- Skill deletion: none. Six file-empty directory shells were removed; the final tree has no empty override directory.

## Classification and compatibility contract

| Category | Count | Meaning | Output |
|---|---:|---|---|
| `overrides/custom/` | 10 | Repository-authored skills and local operational capabilities | `agent/<leaf>` |
| `overrides/patches/` | 3 | Reviewed replacements or corrections for upstream content | `agent/<leaf>` |
| `overrides/resources/` | 1 | Compatibility resource without `SKILL.md` | `agent/<leaf>` |

Root-level files remain reserved for named single-file extension points such as `audit-outer-ai-prompt.md` and `audit-source-strategy.json`. Legacy non-empty `overrides/<leaf>/` directories remain readable during a migration window, but new flat inputs are forbidden. Duplicate leaf names across categories and legacy input fail closed before generation. Removed classified inputs back up under `.bak/<category>/`.

The discovery seam is `Get-OverridesDirs`; `Resolve-OverrideDir` supplies stable-name resolution to backup and audit paths. Tests cover categorized discovery, legacy compatibility, duplicate rejection, category-preserving backup, and audit metadata/hash resolution.

## Inventory and disposition

| Category | Leaf | Role | Disposition |
|---|---|---|---|
| custom | `capability-router` | Native-first cold capability discovery plus deterministic policy validation | keep; narrow fallback with host-owned semantic choice |
| custom | `custom-creator-publishing` | Chinese long-form drafting and repurposing | keep after repair; publication is now an explicit external-write boundary |
| custom | `custom-junior-physics-animation` | Physics animation and interactive teaching visuals | keep after repair; added textbook/standard basis, static/reduced-motion fallback, keyboard and caption checks |
| custom | `custom-powerpoint-accessibility` | Fail-closed PPTX accessibility validator | keep; clear separation from authoring and live PowerPoint operation |
| custom | `custom-powershell-windows-automation` | Durable Windows-first PowerShell 7 automation | keep; matches the repository PS7-only contract |
| custom | `custom-teacher-courseware-ppt` | Classroom courseware structure and teaching workflow | keep after repair; removed nonexistent `python-pptx` skill reference and added accessibility handoff |
| custom | `custom-windows-wpf-teacher-app` | WPF classroom product and UI-observation guidance | keep; narrow trigger and concrete desktop verification boundaries |
| custom | `draft-spec` | Draft-only specification preparation | keep; explicit no-publication/no-file-write boundary |
| custom | `draft-tickets` | Draft-only tracer-bullet ticket decomposition | keep; explicit no-tracker-write boundary |
| custom | `watch-interrupted-task` | Desktop heartbeat lifecycle in fail-closed monitor-only mode | keep after refactor; main contract reduced from 190 to 154 lines, inactive recovery design moved to one-level reference, UI metadata corrected |
| patches | `agent-skills-2-skills-code-review-and-quality` | Stricter local code-review replacement | keep; review remains read-only unless fixes are requested |
| patches | `grill-with-docs` | Focused design interrogation replacement | keep; durable docs only after a confirmed decision |
| patches | `setup-matt-pocock-skills` | Upstream engineering-skill setup compatibility | keep after repair; shared `AGENTS.md` is preferred, `CLAUDE.md` wrapper/import semantics are preserved, and obsolete frontmatter was removed in favor of `agents/openai.yaml` invocation policy |
| resources | `requesting-code-review` | Relative-path bridge for the upstream review prompt | keep as resource, not a skill; intentionally has no `SKILL.md` |

These inputs are versioned repository source, not runtime-generated skills. The generated surface is `agent/`; the host projection is `$HOME/.agents/skills`. Some source was likely created or revised with AI assistance in earlier repository work, but Git history—not a runtime generator—owns it.

## External benchmark review (2026-08-05)

The review used current Codex skill guidance plus fixed-revision, read-only checks of public repositories discovered through `skills.sh`/`find-skills` and GitHub Trending. Install counts and stars were treated as discovery signals only. The reviewed candidates are registered as `conditional-not-cloned` in `references/reference-shelf.manifest.json`.

| Candidate | Evidence and license | Adoption decision |
|---|---|---|
| `anthropics/k12-teacher-skills@7c03c83d` | K-12 planning skill and science reference; Apache-2.0 | Extract prerequisite, exit-ticket, differentiation, and source-consistency guardrails into the local PPT skill; do not import the renderer/Knowledge Graph pipeline. |
| `Community-Access/accessibility-agents@161c60c7` | PowerPoint accessibility skill; MIT | Add metadata, section navigation, and notes/transcript fallback checks; preserve local `not_verified` boundaries. |
| `iOfficeAI/OfficeCLI@459b1a47` | Office workflow inventory; Apache-2.0 | Keep as conditional comparison only; no host integration or runtime install. |
| `emilkowalski/skills@de33dbed` | Animation-purpose and reduced-motion guidance; MIT | No direct import; the existing junior-physics animation skill already has an equivalent teaching-benefit gate. |
| `tirth8205/code-review-graph@1a010dee` | Graph-assisted review workflow; MIT | Defer because it requires graph-specific tools and is not a drop-in review instruction set. |

Repositories without a clearly declared license were not copied; examples rejected for reuse in this pass include `charon-fan/agent-playbook` and `jcurbelo/skills`. No external candidate is allowed to override `skills.json`, generated output, host projection, or the repository's fail-closed evidence rules.

## Verification

- `build.ps1`: passed.
- Focused Pester: `UninstallCleanup` 8/8; `AuditTargets` 90/90; watch contract 20/20; projection/packaging/vendor display 39/39; capability router 26/26; watch fleet/cross-thread 43/43; PS7/watch guards 12/12.
- `scripts/verify-skill-integrity.ps1`: 107 skills verified.
- System `skill-creator/scripts/quick_validate.py`: 13/13 actual skills passed under Python UTF-8 mode with user-level `PyYAML 6.0.3`.
- `scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree`: Unit 862/862, E2E 18/18, generated sync, hygiene, skill integrity, routing, dependency, config, host capability, planning, PS7, workflow advisory, and doctor JSON contract passed.
- `skills.ps1 构建生效`: 14 override leaves applied; generated `agent/` count 108; projection persisted with 111 unique names and 0 conflicts.
- Source-to-agent check: 14/14 categorized leaves have identical relative file/hash manifests. `agent/capability-router/catalog.json` is excluded because it is the documented post-generation catalog.
- Host link check: 14/14 `$HOME/.agents/skills/<leaf>` paths are Junctions targeting the matching `agent/<leaf>`.
- Legacy-path search outside archived/history evidence: no old flat override path remains.

### Skill-creator validator supply chain

- Source: Python Package Index package `PyYAML`; version discovery reported `6.0.3` as current.
- Install: `python -m pip install --user --disable-pip-version-check PyYAML==6.0.3` into the user's Python 3.11 environment.
- Scope: host-side skill authoring validator only; it is not a repository runtime dependency and no requirements/lock file changed.
- Encoding: invoke the validator with `python -X utf8` on Windows because its unqualified `Path.read_text()` otherwise inherits GBK and rejects valid UTF-8 skill text.
- Rollback: `python -m pip uninstall PyYAML`; this does not affect generated skills or repository runtime behavior.

### Benchmark-driven maintenance delta

- `custom-powerpoint-accessibility`: added title/language metadata, long-deck section names, and speaker-notes/transcript fallback checks, while explicitly separating artifact evidence from player or assistive-technology behavior.
- `custom-teacher-courseware-ppt`: added prerequisite/target/exit-ticket alignment, one concrete scaffold plus extension guidance, and an explicit no-invented-alignment rule when the textbook or standard is absent.
- No skill was deleted, no vendor/import was changed, and no runtime or host dependency was added.
- Current validation: system `quick_validate.py` 13/13; Core 189/189; override/audit/projection contracts 130/130; skill integrity 107.

## Rollback

Revert this slice's source, docs, tests, and classified moves; rebuild `skills.ps1`; run `skills.ps1 构建生效` to restore `agent/` and managed Junction targets. Do not delete vendor/import sources or unrelated host state. The ignored profile-reconciliation handoff is advisory only and did not change `active_profile`.
