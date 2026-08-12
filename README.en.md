# skills-manager

[中文](README.md) | English

`skills-manager` is a Windows-first PowerShell manager for collecting AI agent skills from multiple sources into one controlled workspace, generating stable output, and syncing it to local CLI targets such as Claude, Codex, Gemini, and Trae.

Use it when you need to:

- keep several agent skill directories in sync without manual copying
- mix full-vendor repos, targeted imports, and local overrides in one flow
- separate editable input layers from generated output layers
- manage MCP inventory, target-repo audit bundles, portable packaging, and new-machine install from one entry point

## Current State and Boundaries

- Single command entry point: `skills.ps1`
- Single configuration source of truth: `skills.json`
- Source modules live in `src/`; run `./build.ps1` to regenerate root `skills.ps1`
- Default skills sync targets: `~/.claude/skills`, `~/.codex/skills`, `~/.gemini/skills`, `~/.gemini/antigravity/skills/`, `~/.trae/skills/`
- MCP ownership source of truth: `skills.json` `mcp_servers`; rendered by `.\skills.ps1 同步MCP`
- Non-MCP host settings are out of scope for this repo, such as Codex `windows.sandbox`, approval/model/context, and Claude/Gemini auth/provider/model/context/sandbox

## Product Direction (vNext)

The repository now has an executable planning contract for evolving into a Windows-first, local-first AI capability curator and rule advisor. It will continue to manage skills and MCP while adding official plugin awareness, a typed capability inventory, read-only global/project rule diagnostics, and managed writes protected by plan, diff, explicit apply, receipt, and rollback semantics.

It will not become an agent runtime, plugin marketplace, provider/model/auth/session manager, central target-repository registry, or cross-repository rule synchronizer. Rule capabilities remain advisory-first, and host loading or live acceptance require separate native or real-workflow evidence.

### Default collaboration surface

The personal default is ChatGPT Desktop App (including its Codex/Work interaction surface) for requirement clarification, product and architecture design, interactive coding, review, and user decisions; Codex CLI for scripted, batch, CI, machine-readable, and terminal-recovery work; and Claude Code for Claude-specific capabilities or independent review. This is a collaboration preference, not a mandatory router or gate, and it does not choose the product technology stack or core architecture. Task shape and currently available host-native capability take precedence; the product core remains host-neutral.

- [Product documentation index](docs/product/README.md)
- [vNext PRD](docs/product/skills-manager-vnext-prd.md)
- [vNext architecture](docs/product/skills-manager-vnext-architecture.md)
- [vNext roadmap](docs/product/skills-manager-vnext-roadmap.md)
- [Rule-governance adoption matrix](docs/product/rule-governance-adoption-matrix.md)
- [Current Phase 6 task manifest](tasks/skills-manager-vnext-phase6.tasks.json)
- [Historical Agent workflow advisory spec](docs/superpowers/specs/2026-08-05-agent-workflow-advisory-runtime.md) / [historical manifest](tasks/skills-manager-vnext-agent-workflow-advisory.tasks.json)
- [Historical Phase 5 task manifest](tasks/skills-manager-vnext-phase5.tasks.json)
- [Historical Phase 4 task manifest](tasks/skills-manager-vnext-phase4.tasks.json)
- [Historical Phase 3 task manifest](tasks/skills-manager-vnext-phase3.tasks.json)
- [Historical Phase 2 task manifest](tasks/skills-manager-vnext-phase2.tasks.json)
- [Historical Phase 1 task manifest](tasks/skills-manager-vnext-phase1.tasks.json)
- [Historical Phase 0 task manifest](tasks/skills-manager-vnext-phase0.tasks.json)

The P6 manifest is the current dynamic truth source. The repository implementation has closed out the P6 host-native lifecycle reset and completed one explicitly scoped representative Codex Desktop acceptance workflow. Desktop acceptance evaluates discoverability, reuse, and behavioral consistency; it does not depend on CLI injected/executed telemetry and is not a universal claim across every task or model. P0-P5 counts remain historical contract truth; plugin/MCP installation, OAuth, host/profile/session writes, and restart remain outside the automatic boundary.

PowerShell 7 (`pwsh`) is the only supported runtime; PowerShell 7.6 LTS is the recommended baseline. Windows PowerShell 5.1 has no installer fallback, CI job, or smoke-support path, and entry points fail closed when `pwsh` is missing. See [`docs/runbooks/powershell-runtime-compatibility.md`](docs/runbooks/powershell-runtime-compatibility.md) for migration, encoding, and rollback boundaries.

PowerShell 7 remains the only runtime truth. New domain logic first contracts into narrow, pure, versioned JSON/protocol seams; a typed implementation is reconsidered only when a current failure cannot be fixed more simply and real consumers, comparative benefit, distribution, and rollback evidence all exist. The 2026-08-05 C#/.NET TC1 `shadow_only` PoC achieved fixed-corpus parity but never gained a production or repository-external consumer, did not prove lower AI rework, and kept imposing an SDK pin and full-gate cost. Its implementation, verifier, and tests are retired; the spec, manifest, and evidence remain historical records.

Long-chain decomposition, model selection, subagent/worktree orchestration, failure recovery, and integration are owned entirely by host-native AI capabilities. The repository's former general TaskGraph/model-policy advisory had no repository-external consumer and overlapped native Plan, Goal, and subagent controls, so it has been retired from the build, CLI, default gate, and current test surface. Its spec, manifest, and evidence remain historical records. This project now provides only the plan, receipt, and rollback contracts required by its own capability, rule, and projection domains; it no longer provides a general AI-engineering orchestrator or second governance plane.

The resident `capability-router` is now a compatibility fallback, not a lexical semantic router. Codex/ChatGPT first match visible skill metadata natively; when no visible capability fits, the fallback exposes domain names and purposes, the host chooses at most two domains, and only then receives bounded candidates. The host supplies its semantic choice to deterministic policy, which alone decides containment, availability, reuse, activation, and approval. The script reports `decision_owner=host_ai`, never assigns semantic confidence, and performs no host mutation. Run `scripts/verify-capability-routing.ps1` for the deterministic discovery/policy corpus and `scripts/evaluate-host-skill-selection.ps1` for opt-in fresh host selection/cold-load evaluation.

Skill profile data is now migration-only. `skills.ps1 skill-profile` has been removed from the runtime entrypoint; legacy fields are retained under `skill_projection.profile_compatibility` with `status=read_only` and `reachability_authority=none`. `scripts/plan-skill-profile-reconciliation.ps1 -Json` remains a compatibility report, while `scripts/verify-skill-routing.ps1 -Json` is compatibility-only and is not a quality gate or semantic selector. No current request may hot-switch a profile or mutate host/session state.

Native projection compiles the canonical inventory, admits the bounded resident set, and uses the host snapshot plus deterministic eligibility/metadata planning; profile membership cannot control reachability. Real host acceptance is evaluated through representative Desktop tasks for discovery, reuse, and behavior. CLI/App Server events are optional diagnostics, not a second invocation truth source.

Phase 1 read-only entry points (no file writes without `--out`):

```powershell
.\skills.ps1 capability-inventory --json
.\skills.ps1 rule-audit --repo . --host codex --json
.\skills.ps1 rule-estate-audit --workspace-root D:\CODE --json
```

`rule-estate-audit` excludes `external` and `文档` by default, dynamically discovers direct Git roots, and reports textual mappings separately from semantic gaps; grouped, unknown, and duplicate mappings do not pass semantic coverage. It also verifies the Codex/Claude global `1/A/B/C/D` structure, A/C/D parity, distinct B deltas, release and hard budgets, plus the project `1/A/B/C/D` profile, the Claude wrapper, individual R/S/E mappings, N/A evidence and expiry, Git baseline/upstream truth, and concrete-file S5 enforcement references. Optional `--registry <snapshot.json>` only compares a supplied snapshot with dynamic discovery for drift; it neither changes the target set nor becomes a central source of truth. Root rules retain stable entry points; volatile task/gate/host/live state is read fresh from manifests, specs, and evidence. `--out <report.json>` writes one report inside the workspace root, cannot cross a reparse/junction or overwrite inputs; plan/apply uses the same boundary.

Reviewed global/project rule change-sets use the controlled multi-target flow:

```powershell
.\skills.ps1 rule-estate-plan --review <reviewed-change-set.json> --workspace-root D:\CODE --out <estate-plan.json> --json
.\skills.ps1 rule-estate-apply --plan <estate-plan.json> --workspace-root D:\CODE --token APPLY_RULE_ESTATE_PATCH --out <estate-receipt.json> --json
.\skills.ps1 rule-estate-rollback --receipt <estate-receipt.json> --action-id <action-id> --workspace-root D:\CODE --token ROLLBACK_RULE_ESTATE_PATCH --json
```

The executor preflights every target, then writes one target at a time with a durable receipt. It fails fast, supports receipt-based resume and per-target rollback, rejects AI self-review, stale target-rule hashes, target-set drift, locks, and out-of-scope files. Unrelated dirty paths are recorded and preserved; target repositories are never auto-committed or pushed.

P2 transaction entry points support explicit fixture, single-repository, and reviewed rule-estate boundaries:

```powershell
.\skills.ps1 rule-plan --target <fixture-rule> --desired-file <reviewed-file> --fixture-root <fixture-root> --json --out <fixture-plan.json>
.\skills.ps1 rule-apply --plan <fixture-plan.json> --fixture-root <fixture-root> --token APPLY_RULE_PATCH --json
.\skills.ps1 rule-plan --target <repo-rule> --desired-file <reviewed-file> --repo-root <git-root> [--allow-create] --json --out <repo-plan.json>
.\skills.ps1 rule-apply --plan <repo-plan.json> --repo-root <git-root> --token APPLY_RULE_REPO_PATCH --json
```

Repository mode only accepts `AGENTS.md`, `AGENTS.override.md`, or `CLAUDE.md` inside the exact Git root and enforces freshness hashes, reparse guards, atomic writes, and rollback. It does not authorize user-global rules, host configuration, or unreviewed bulk cross-repository writes.

For P3 plugin-aware commands, inventory/lint/eval are read-only and export remains strictly fixture-only:

```powershell
.\skills.ps1 plugin-inventory --official <snapshot.json> [--personal <snapshot.json>] [--workspace <snapshot.json>] --json
.\skills.ps1 plugin-lint --path <plugin-root> --json
.\skills.ps1 plugin-export --candidate <candidate.json> --fixture-root <fixture-root> --out <new-folder> --token EXPORT_PLUGIN_FIXTURE --json
.\skills.ps1 plugin-eval --path <plugin-root> --json
```

This Phase only supports the verified Codex skills-only package. These commands do not install or enable plugins, mutate marketplaces or host profiles, call providers, or use a model snapshot as a deterministic blocker.

## Paths and Edit Policy

| Path / key | Role | Edit policy |
| --- | --- | --- |
| `skills.json` | Single configuration source for `vendors / mappings / imports / targets / sync_mode / mcp_servers` | Edit directly; validate read-only with `scripts/verify-skills-config.ps1 -Mode enforce` |
| `config/skills.schema.json` | v1 structure, compatibility, and sensitive-output policy for `skills.json` | Maintain as a versioned contract; missing `schema_version` is read as a legacy v1 observation |
| `config/host-capability-matrix.json` | Read-only contract for host surfaces, ownership, activation, and maximum automated verification | Validate with `scripts/verify-host-capability-matrix.ps1`; never present it as live inventory |
| `src/` | Source modules | Change here, then run `./build.ps1` |
| `skills.ps1` | Generated entry script | Do not edit directly; regenerate from `build.ps1` |
| `vendor/` | Upstream full-repo cache | Do not patch by hand; rebuild through `更新` or lock replay |
| `imports/` | Materialized targeted imports | Treat as an input layer, not a generated patch sink |
| `overrides/` | Reviewed local input layer | Use `custom/` for repository-owned capabilities, `patches/` for upstream replacements, `resources/` for non-skill resource bridges, and the root only for named file overrides |
| `agent/` | Generated output and sync source | Do not edit directly; rebuild through `构建生效` |
| `reports/skill-audit/<run-id>/ai-brief.md` | Audit runtime summary | Runtime artifact; do not hand-edit |
| `reports/skill-audit/<run-id>/outer-ai-prompt.md` | Outer-AI execution prompt | Runtime artifact; change the default in `src/Commands/AuditTargets.ps1` or `overrides/audit-outer-ai-prompt.md` |

The leaf name remains the stable output name: `overrides/<category>/<leaf>` generates `agent/<leaf>`. Flat `overrides/<leaf>` directories are read only during the migration window; do not add new flat inputs, and duplicate leaf names across categories fail the build. See [overrides/README.md](overrides/README.md).

## Quick Start

For first-time use, start from the interactive menu:

```powershell
.\skills.ps1
```

Minimal happy path:

```powershell
.\skills.ps1 发现
.\skills.ps1 安装
.\skills.ps1 构建生效
.\skills.ps1 doctor --strict --threshold-ms 8000
```

The interactive menu uses direct frequent actions plus domain submenus.

- Browse Skills
- Pick Install
- Paste Command Import
- Remove Skills
- Rebuild and Sync (CLI command remains `构建生效`)
- Update Upstream (CLI command remains `更新`)
- Target Repo Audit
- MCP Services
- Skill Library Admin
- More

## One-Click Workflows

```powershell
.\skills.ps1 一键 --list
.\skills.ps1 一键 新手
.\skills.ps1 一键 维护 --continue-on-error
.\skills.ps1 一键 审查 --no-prompt
.\skills.ps1 workflow all --no-prompt
```

Built-in profiles:

- `新手` / `quickstart` / `start` / `onboarding`
  Browse Skills -> Pick Install -> Rebuild and Sync -> `doctor --strict --threshold-ms 8000`
- `维护` / `maintenance` / `maintain`
  Update Upstream -> Rebuild and Sync -> Sync MCP -> `doctor --strict --threshold-ms 8000`
- `审查` / `audit`
  View requirements -> Target repo list -> Generate audit bundle -> View latest status
- `全流程` / `all` / `full`
  Update Upstream -> Browse Skills -> Rebuild and Sync -> Sync MCP -> `doctor --strict --threshold-ms 8000`

If no profile is given together with `--no-prompt`, the script defaults to `all`.

The `Target Repo Audit` submenu follows the workflow:

- View requirements
- Edit requirements
- Target repo list
- Generate audit bundle
- Preflight recommendations
- Apply recommendations (dry-run first)
- View latest status

## Common Commands

### Discover, import, install, uninstall

```powershell
.\skills.ps1 发现
.\skills.ps1 安装
.\skills.ps1 命令导入安装
.\skills.ps1 add <repo> [--skill <name>] [--ref <branch/tag>] [--mode manual|vendor] [--sparse]
.\skills.ps1 npx "skills add <repo> --skill <name>"
.\skills.ps1 卸载 [<skill-name>|<index>|all] [--yes] [--filter <keyword>]
.\skills.ps1 清理无效映射 [--yes] [--no-build]
```

Notes:

- Without `--skill`, `add` only registers a skill library. It does not install every skill in that repository.
- With `--skill`, imports default to `manual` mode under `imports/`; pass `--mode vendor` for vendor-managed installs.
- `命令导入安装` accepts multiple pasted `add` / `npx skills add` / `npx add-skill` commands; line continuations ending in `\` are merged automatically.
- `卸载` enters interactive selection when no argument is given; use a skill name, index, or `all` together with `--yes` for non-interactive runs.
- English alias for `清理无效映射` is `prune-invalid-mappings`.

### Build, update, lock, maintenance

```powershell
.\skills.ps1 构建生效
.\skills.ps1 更新 -Plan
.\skills.ps1 更新 -Upgrade
.\skills.ps1 锁定
.\skills.ps1 新增技能库
.\skills.ps1 删除技能库
.\skills.ps1 自动更新设置
.\skills.ps1 解除关联
.\skills.ps1 清理备份
.\skills.ps1 doctor [--json] [--fix] [--dry-run-fix] [--strict] [--strict-perf] [--threshold-ms <ms>]
```

Notes:

- Use `构建生效` when you only want to re-render current configuration into `agent/` and the target directories.
- Before `构建生效` writes to host skill/config directories outside the repository, the source must be a clean Git commit. The projection manifest records the source revision, dirty state, and promotion mode. `-AllowUnverifiedHostProjection` is an explicit risk exception and is recorded as `unverified_override`; it is never presented as a passing full-gate receipt.
- Use `更新` when you need fresh upstream content. `-Plan` previews only; `-Upgrade` refreshes `skills.lock.json` after update.
- `锁定` creates or refreshes `skills.lock.json` for `更新 -Locked` and portable install replay.
- `doctor --strict` exits non-zero on failure and is suitable for script gates.

### MCP management

```powershell
.\skills.ps1 安装MCP context7 -- npx -y @upstash/context7-mcp
.\skills.ps1 安装MCP filesystem --cmd npx --arg -y --arg @modelcontextprotocol/server-filesystem --arg D:\CODE
.\skills.ps1 安装MCP github --transport http --url https://api.githubcopilot.com/mcp/ --bearer-token-env-var GITHUB_PERSONAL_ACCESS_TOKEN
.\skills.ps1 卸载MCP context7
.\skills.ps1 同步MCP
.\skills.ps1 mcp-sync --plan --json
.\skills.ps1 mcp-sync --plan --json --out .\reports\mcp-plan.json
```

Notes:

- `安装MCP` and `卸载MCP` update `skills.json` and then automatically run one `同步MCP`.
- `同步MCP` renders MCP payloads into target-root `.mcp.json`, Gemini/Trae config, and Codex `[mcp_servers.*]` config blocks.
- `mcp-sync --plan --json` reuses apply's desired-state calculation and emits a deterministic, redacted `OperationPlan v1`. Plan mode does not write managed MCP targets, invoke native add/remove, or change the active profile. Only an explicit `--out` writes the requested plan file.
- Without `--plan`, `同步MCP` / `mcp-sync` retain the existing apply behavior; legacy human-readable `-DryRun` behavior remains compatible.
- `postgres` MCP preflight requires `POSTGRES_CONNECTION_STRING` in `postgresql://...` form; Npgsql/ADO key-value strings are normalized and written back to User scope automatically.
- `github` MCP prefers `gh auth token` and writes the result into User-scope `CODEX_GITHUB_PERSONAL_ACCESS_TOKEN`; Codex config stores only `bearer_token_env_var`, never a literal token.
- The local weekly task `skills-manager-weekly-update-friday-2000` runs `更新 -> 同步MCP`, so durable MCP environment fixes must live in the source chain, not only in live `~/.codex/config.toml`.

### Native skill projection

GPT-5.6 routine work prefers Codex-native Plan, Goal, Review, skill semantic matching, and agent controls. Fixed Superpowers full-workflow chains are no longer in native discovery; `coding-strict` keeps only the explicit strict-TDD entry point. Routine implementation, configuration, documentation, and generated files do not mechanically trigger TDD, full-suite testing, CI, or multi-agent work. `research` activates only when current primary-source facts can change the decision, remains read-only by default, and never writes a research file automatically. Profiles are read-only compatibility/warm-up views; the current task never hot-loads profile changes. Vendor checkouts may remain as references and are not the generated projection.

### Target repository audit

```powershell
.\skills.ps1 审查目标 初始化
.\skills.ps1 审查目标 需求设置
.\skills.ps1 审查目标 需求查看
.\skills.ps1 审查目标 需求结构化 --profile reports\profile.json
.\skills.ps1 审查目标 添加 my-repo ..\my-repo
.\skills.ps1 审查目标 修改 my-repo ..\my-repo
.\skills.ps1 审查目标 删除 my-repo
.\skills.ps1 审查目标 列表
.\skills.ps1 审查目标 目标列表
.\skills.ps1 审查目标 扫描 --target my-repo
.\skills.ps1 审查目标 发现新技能 --query "repo governance and agent workflows"
.\skills.ps1 审查目标 预检 --run-id <run-id>
.\skills.ps1 审查目标 应用确认 --recommendations reports\skill-audit\<run-id>\recommendations.json
.\skills.ps1 审查目标 应用 --recommendations reports\skill-audit\<run-id>\recommendations.json
.\skills.ps1 审查目标 应用 --recommendations reports\skill-audit\<run-id>\recommendations.json --apply --yes --add-indexes "1,3" --remove-indexes "2" --mcp-add-indexes "1" --mcp-remove-indexes "2"
.\skills.ps1 审查目标 状态
```

Key rules:

- `发现新技能` is a profile-only mode: it generates the same audit bundle shape, but not `repo-scan.json`.
- Formal audits must use both context layers: global user profile plus target-repo facts.
- `应用` defaults to dry-run; only `--apply --yes` persists changes.
- `应用确认` is the single-entry two-stage flow: dry-run first, then confirmation token `APPLY <run-id>`.
- Dry-run requires explicit ack `我知道未落盘`; for non-interactive runs, pass `--dry-run-ack "我知道未落盘"`.
- `应用` and `应用确认` validate whether sibling `installed-skills.json` is stale against live state; use `--allow-stale-snapshot` plus `--stale-ack "<token>"` only when you intentionally accept that risk.
- `--out` blocks reuse of a non-empty existing directory unless you explicitly pass `--force`.

If the outer AI can execute in the workspace, hand it the run-local `outer-ai-prompt.md` first instead of only `ai-brief.md`.

## English Aliases

English aliases currently focus on scriptable surfaces:

| Chinese entry | English alias |
| --- | --- |
| `帮助` | `help`, `--help`, `-h` |
| `doctor` | `doctor` |
| `审查目标` | `audit-targets` |
| `一键` | `workflow` |
| `安装MCP` | `mcp-install` |
| `卸载MCP` | `mcp-uninstall` |
| `同步MCP` | `mcp-sync` |
| `清理无效映射` | `prune-invalid-mappings` |
| `add` | `add` |
| `npx` | `npx` |

These high-frequency Chinese commands still have no English aliases: `发现`, `安装`, `构建生效`, `更新`, `锁定`, `新增技能库`, `删除技能库`, `自动更新设置`, `解除关联`, `清理备份`.

## Sync Modes

`skills.json` controls skills directory sync through `sync_mode`:

- `link`: Windows default; creates junctions to `agent/`
- `sync`: mirrors `agent/` with `robocopy /MIR`

Prefer `link` for local iteration. Switch to `sync` only when links are restricted. If MCP targets must diverge from skills targets, add `mcp_targets` in `skills.json`.

## Release and New-Machine Migration

Prefer a reproducible portable package instead of copying the entire workspace:

```powershell
.\scripts\release\pack-portable.ps1 -Version vX.Y.Z
```

Common extra switches:

```powershell
.\scripts\release\pack-portable.ps1 -Version vX.Y.Z -AllowDirtyWorktree
.\scripts\release\pack-portable.ps1 -Version vX.Y.Z -SkipVerification
```

The portable package includes reproducible source and config such as `skills.ps1`, `skills.cmd`, `install.ps1`, `skills.json`, `skills.lock.json`, `src/`, `scripts/`, `tests/`, `overrides/`, and governance docs. It excludes `agent/`, `vendor/`, `imports/`, `reports/`, `.codex/`, `.claude/`, `.gemini/`, `.trae/`, logs, caches, release output, and audit runtime evidence.

After extraction on a new machine:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Mode CurrentUser
```

Default behavior:

1. Run `build.ps1`
2. If `skills.lock.json` exists and `-SkipRebuildLocked` was not passed, run `.\skills.ps1 更新 -Locked`
3. Otherwise run `.\skills.ps1 构建生效`
4. If `-SyncMcp` is passed, run `.\skills.ps1 同步MCP`
5. Finish with `.\skills.ps1 doctor --strict --threshold-ms 8000`

Common modes:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Mode CurrentUser -SyncMcp
pwsh -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Mode PortableOnly
pwsh -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Mode CurrentUser -DoctorThresholdMs 12000
```

Notes:

- `PortableOnly` does only `build + doctor`, does not write user skills directories, and ignores `-SyncMcp`.
- The installer and `skills.cmd` resolve only `pwsh`; Windows PowerShell 5.1 is unsupported and has no hidden fallback.
- `-SkipEnvironmentCheck` is for controlled fixtures; do not use it as the normal install path.
- Before syncing MCP on a new machine, prepare machine-local tokens, database connection strings, and other host prerequisites.

## Local Gates

Project-level hard gate order:

```powershell
./build.ps1
./skills.ps1 发现
./skills.ps1 doctor --strict --threshold-ms 8000
./skills.ps1 构建生效
```

The repo also provides local/CI parity quality gate scripts:

```powershell
./scripts/quality/run-local-quality-gates.ps1 -Profile quick
./scripts/quality/run-local-quality-gates.ps1 -Profile full -ReuseCurrentReceipt
```

Meaning:

- `quick`: `build -> repo-hygiene -> generated-sync -> skill-integrity -> native-skill-metadata -> dependency-baseline -> skills-config-contract -> planning-contract -> doctor-json-contract`
- `full`: `quick + tests`
- `-ReuseCurrentReceipt`: reuses an immutable receipt only when the source fingerprint, `full/passed` status, and dirty-worktree policy match exactly; otherwise it runs a fresh full gate.
- `-ForceFresh`: explicitly ignores a reusable receipt and reruns the gate; it is mutually exclusive with `-ReuseCurrentReceipt`. Add `-AllowDirtyWorktree` separately when the source is intentionally dirty.

Run the planning contract independently with:

```powershell
./scripts/verify-vnext-planning.ps1
./scripts/verify-vnext-planning.ps1 -Json
```

The verifier selects the current spec/manifest from `current_phase` in `tasks/plan.md`; `-SpecPath` and `-ManifestPath` can validate historical phases. It proves only planning-file consistency, not product code, host loading, or live acceptance.

## MCP and Gate Environment Variables

- `POSTGRES_CONNECTION_STRING`: postgres MCP connection string; `postgresql://...` is preferred
- `CODEX_GITHUB_PERSONAL_ACCESS_TOKEN`: User/Process-scope token variable for Codex GitHub MCP
- `SKILLS_MCP_VERIFY_GEMINI_CLI=1|true|yes|on`: enable real Gemini CLI verification (disabled by default)
- `SKILLS_MCP_VERIFY_LIST_TIMEOUT_SECONDS`: global timeout in seconds for `mcp list` verification
- `SKILLS_MCP_VERIFY_LIST_TIMEOUT_SECONDS_<CLI>`: per-CLI timeout override (for example `_CLAUDE`, `_CODEX`, `_GEMINI`)
- `SKILLS_MCP_NATIVE_TIMEOUT_SECONDS`: timeout in seconds for native `claude mcp add/remove`
- `SKILLS_MCP_VERIFY_ATTEMPTS` and `SKILLS_MCP_VERIFY_INTERVAL_SECONDS`: retry count and retry interval for cross-CLI MCP verification
- `SKILLS_SYNC_MCP_THRESHOLD_MS`: `sync_mcp` performance threshold in `check-doctor-json.ps1`; clean CI has no historical sample, so it records an observation with `-WarnOnly`, while only a dedicated performance gate with a real sample may block
- The test suite uses Pester `4.10.1` syntax; CI installs that exact version, and `tests/run.ps1` fails closed when it is unavailable

## Repository Hygiene

Do not commit local agent state, logs, caches, or temporary artifacts, including:

- `.claude/`, `.codex/`, `.gemini/`, `.trae/`, `.txn/`
- `agent/`, `artifacts/`, `reports/*.log`
- `imports/_debug_*`, `imports/_probe_*`, `imports/_tree_*`, `imports/*.zip`
- audit runtime evidence under ignored `reports/skill-audit/<run-id>/runtime-evidence-*.md`; 115 legacy receipts are preserved under [`docs/archive/change-evidence/`](docs/archive/change-evidence/README.md) and must not return to active `docs/change-evidence/`
- backups and temporary files such as `build.log*`, `acl-backup-git-*.txt`, `.tmp_*`

Boundary note:

- Root `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` are tracked project rule documents. They are not disposable local junk.
- Do not commit host-local rule copies, temporary rule snapshots inside imported sources, or downstream tool-generated host-local config.

## Related Docs

- [Product direction and planning contract](docs/product/README.md)
- [Contributing](CONTRIBUTING.md)
- [Security Policy](SECURITY.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [overrides README](overrides/README.md)

## License

MIT
