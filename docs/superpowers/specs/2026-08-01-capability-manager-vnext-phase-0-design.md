# Capability Manager vNext Phase 0 Foundation Design

**program_id**: `skills-manager-vnext`
**phase**: `P0`
**status**: accepted-for-planning
**task_manifest**: `tasks/skills-manager-vnext-phase0.tasks.json`
**最后更新**: 2026-08-01

## 1. Goal

在保持现有 `skills.ps1`、`skills.json`、skill projection、MCP sync、target audit 和 CLI 行为兼容的前提下，为 vNext 建立足够的工程基础，使后续 read-only capability inventory 和 rule advisor 不再继续挤入现有大文件。

Phase 0 只建立经过真实调用点证明的 seam 和 contracts，不实现完整终态目录，不增加规则写入、plugin 安装或中央控制面。

## 2. Current facts

- 发行物由 `build.ps1` 拼装 22 个 PowerShell 源文件为根 `skills.ps1`。
- `skills.json` 没有根 schema/version contract，当前校验主要依赖 `ConvertFrom-Json` 和命令内 validator。
- MCP 已有日志型 dry-run 分支和多宿主写入，但没有稳定、可持久比较的 machine-readable plan contract。
- Audit apply 已有 dry-run、stale snapshot、confirmation 和 rollback 文本，可作为行为参考，但不能直接复制为所有领域基类。
- skill projection manifest 已有 schema/version/hash cache，可作为 fail-safe cache 参考。
- `openai/skills` 当前 reference clone 已 deprecated，官方指向 `openai/plugins`；reference shelf 需要更新 source disposition。

## 3. Phase boundary

### In scope

- Planning assets and verifier。
- Official plugin reference shelf correction。
- `skills.json` schema/version policy with observe-first validation。
- Minimal domain/infrastructure/application module seams。
- Versioned OperationPlan and Receipt validators。
- MCP machine-readable planning with zero-write contract。
- Host capability/verification-level matrix。
- PowerShell 7 primary + Windows PowerShell 5.1 compatibility window documentation/tests。
- Full gate and change evidence closeout。

### Out of scope

- Rule discovery、rule doctor、rule patch/apply。
- Plugin install/uninstall/enable、OAuth、connector auth。
- New hosted service、daemon、database、GUI、App Server client。
- Moving all existing functions into the target directory in one change。
- Changing current active profiles or host-local configuration as part of Phase 0 implementation。
- Claiming ChatGPT/Codex live acceptance from repo tests。

## 4. Compatibility contract

Phase 0 implementation must preserve:

1. Existing positional and bilingual CLI command names。
2. Current `skills.json` without requiring immediate manual migration。
3. Existing lock file and projection manifest readers。
4. Generated `skills.ps1` as the portable product entrypoint。
5. Current MCP target payload semantics unless a task explicitly adds an additive plan output。
6. PowerShell 5.1 parsing/execution for the supported bootstrap/smoke paths until a later evidence-backed migration removes them。
7. Existing `DryRun` behavior; new structured plan is additive before it becomes enforceable。

Any output change requires a golden/compatibility fixture and an explicit migration note.

## 5. Source and module rules

### 5.1 Dependency direction

```text
Commands -> Application -> Domain
Commands -> Adapters -> Infrastructure -> Domain
Application must not call Write-Host, exit, or read global CLI variables.
Domain must not read files, environment variables, Git, network, or native processes.
```

### 5.2 Incremental extraction

- A new module is added only when the same slice has a real caller and tests。
- Existing function names remain wrappers while callers migrate。
- A wrapper may translate legacy objects to a new domain object, but must not duplicate decision logic。
- `build.ps1` remains a deterministic ordered bundle list; missing modules fail build。
- `skills.ps1` is regenerated, never hand edited。

### 5.3 Plain object validation

Use PSCustomObject/hashtable plus `Test-*Contract` functions. Do not introduce a PowerShell inheritance framework or custom DI container.

Validator result shape:

```text
pass: bool
findings[]:
  code
  severity: error | warning | observation
  path
  message
```

Validators do not print or exit. Command/verifier layers decide formatting and exit code.

## 6. `skills.json` schema design

### 6.1 Versioning

- Add an additive top-level `schema_version` only after the reader accepts missing version as legacy v1。
- The initial schema describes current live configuration before enforcing new restrictions。
- Unknown additive fields remain allowed during observe mode unless they collide with a reserved/unsafe field。
- Invalid known field types, impossible enum values and unsafe paths are errors。

### 6.2 Observe to enforce

The standalone verifier supports:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-skills-config.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-skills-config.ps1 -Mode observe -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-skills-config.ps1 -Mode enforce
```

Phase 0 starts quality-gate integration in `observe` only if current legitimate config cannot yet satisfy enforce. Exit gate requires current config pass enforce or a versioned waiver with owner/expiry/recovery.

### 6.3 Schema invariants

- `vendors`, `mappings`, `imports`, `targets`, `mcp_servers`, `mcp_profiles`, `mcp_targets` retain current shapes。
- `skill_projection` path and profile budgets are typed and bounded。
- Secret-like values are not introduced into the schema as persisted fields。
- Rule documents and plugin OAuth/install state are not added to `skills.json`。

## 7. Operation contracts

### 7.1 Domain functions

Expected minimal functions:

```text
New-OperationPlan
Test-OperationPlanContract
Test-OperationPlanFreshness
New-OperationReceipt
Test-OperationReceiptContract
Merge-OperationVerificationState
Protect-OperationSensitiveValue
```

Names may change only if the same behavior and discoverability are preserved in the task evidence.

### 7.2 Action identity

`action_id` must be deterministic within a plan. Reordering input enumeration cannot change action IDs or target set. Paths use normalized comparison while receipts retain a human-readable path.

### 7.3 No secret persistence

Redact at object construction, not only output formatting. Tests must cover:

- `*_TOKEN`, `*_API_KEY` and authorization header values。
- URL userinfo/query secrets。
- PostgreSQL/Npgsql connection strings。
- MCP env dictionaries and native argv。

### 7.4 Verification state monotonicity

Verification level values do not automatically cascade. In particular:

- `repo_gates_passed=pass` leaves `host_loaded` and `live_accepted` unchanged。
- `host_loaded=pass` leaves `live_accepted` unchanged。
- A later failure at a higher level does not erase lower-level evidence but makes overall result scoped/failed for that level。

## 8. MCP structured plan

### 8.1 Command behavior

Phase 0 adds an explicit structured planning path without changing current sync default. Candidate command contract:

```powershell
./skills.ps1 mcp-sync --plan --json
./skills.ps1 同步MCP --plan --out <ignored-path>
```

Final spelling is selected in `SMV-P0-006` after existing parser tests are read. Requirements are stable regardless of spelling:

- zero file writes、zero native add/remove calls、zero profile mutation。
- output contains all managed targets that apply would consider。
- actions are deterministic and redacted。
- unchanged targets produce no update action but remain visible in summary。
- unsupported/unavailable host is explicit, not silently omitted。

### 8.2 Plan/apply parity

Use a shared function to calculate desired payloads and target actions. Plan and apply must not independently rebuild payloads. Fixture comparison asserts the target/action set is identical for the same inputs.

### 8.3 Existing dry-run migration

Legacy `-DryRun` remains supported. It may call the new planner and render human logs, but Phase 0 does not require every old dry-run call site to emit a receipt.

## 9. Host truth matrix

The Phase 0 matrix is a versioned repository fact about adapter support, not live host state. Minimum fields:

```json
{
  "schema_version": 1,
  "hosts": [
    {
      "host_id": "codex",
      "surfaces": {
        "skills": "managed",
        "plugins": "native_only",
        "mcp": "managed_or_native",
        "rules": "read_only_planned"
      },
      "highest_automated_verification": "host_loaded",
      "activation_boundary": "fresh_session",
      "evidence_sources": []
    }
  ]
}
```

Allowed support values and evidence source requirements are verified. `live_accepted` cannot be a declared automated maximum.

## 10. Task design

### `SMV-P0-001 Planning contract and verifier`

Land the product index, PRD, architecture, roadmap, Phase 0 spec, task manifest, current plan/todo and planning verifier. The verifier must keep task IDs and todo status aligned, and a done task must reference an existing exact change-evidence file. This task changes planning truth only, not product runtime behavior.

### `SMV-P0-002 Official plugin reference realignment`

Add `openai/plugins` as current official core reference. Preserve the deprecated `openai-skills` entry as historical/compatibility evidence until runtime imports are separately reviewed. Update tier docs, refresh routing and portable whitelist/tests if required. Do not delete installed skills.

### `SMV-P0-003 skills.json schema and validator`

Describe the current configuration, add legacy version compatibility, deterministic validation and quality-gate integration. Do not mix rule/plugin state into the config.

### `SMV-P0-004 OperationPlan and Receipt contracts`

Implement pure constructors/validators, schema files, redaction and verification-state tests. No existing write path is migrated in this task.

### `SMV-P0-005 Infrastructure seam extraction`

Move one proven cluster of JSON/hash/atomic file helpers behind thin legacy wrappers. Select the cluster only after call-site and test coverage review. Preserve output/encoding/exception behavior.

### `SMV-P0-006 MCP machine-readable plan`

Create one shared desired-state calculation path and expose a zero-write structured plan. Keep existing apply behavior and CLI aliases compatible.

### `SMV-P0-007 Host capability and truth-state contract`

Add the repository host matrix, validator and tests. It records supported product surfaces and maximum automatable evidence; it does not scan or change live hosts by default.

The matrix is also the Phase 0 vocabulary source for later rule discovery: it may identify whether a host has global/project/nested rules and the highest verification level an adapter could prove. It must not parse rule semantics, create patch plans, enforce a universal document shape, or promote repository evidence to `host_loaded`/`live_accepted`.

### `SMV-P0-008 Runtime compatibility contract`

Make PS7-primary/PS5.1-window explicit in help/docs/tests/CI without prematurely removing compatibility. Verify generated encoding and supported smoke paths.

### `SMV-P0-009 Phase 0 acceptance closeout`

Run the ordered gates, execute targeted parity/fault/redaction tests, update evidence and only then advance roadmap/task status. Native probes are separate and must declare actual scope.

## 11. Test strategy

### Contract tests

- Schema known-good/current config and invalid field fixtures。
- Operation plan/receipt missing/unknown/invalid field fixtures。
- Task and host matrix dependency/enum/version validation。

### Compatibility tests

- Existing command aliases and representative output/payload golden fixtures。
- Generated `skills.ps1` sync and encoding。
- Current `skills.json` parses as legacy/current without destructive normalization。

### Safety tests

- Plan mode writes zero files and starts zero native mutation commands。
- Stale hash and out-of-root path fail before first action。
- Redaction fixtures do not expose secret values in object JSON or logs。
- Fault injection rollback touches only operation-owned outputs。

### Truth-state tests

- Repo pass does not set host/live pass。
- Missing CLI is platform_na/not_run, not pass。
- Static config detection does not set host_loaded。

## 12. Ordered verification

Per executable task and Phase closeout:

1. `pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1`
2. `pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1`
3. `pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict --threshold-ms 8000`
4. `python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline`
5. `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-vnext-planning.ps1`
6. Phase/task-specific schema/parity/redaction/fault probes。
7. `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full [-AllowDirtyWorktree]`

Native host probes run after repo gates when applicable and are reported separately.

## 13. Rollback

- Each task rolls back only its manifest `write_set` and generated `skills.ps1` if applicable。
- Schema observe/enforce change must be reversible independently of config data。
- New module extraction retains legacy wrappers until the next verified cleanup slice。
- MCP planner can be disabled without reverting existing sync behavior。
- Reference shelf rollback does not delete external clones or installed runtime sources。
- Phase closeout must not use destructive whole-worktree commands。

## 14. Done definition

Phase 0 is complete only when `SMV-P0-001` through `SMV-P0-009` are done or explicitly deferred by versioned waiver, planning verifier has zero findings, full gate passes, and evidence states which native/live levels were actually executed.

Planning documents alone satisfy only `SMV-P0-001`; they do not close Phase 0.
