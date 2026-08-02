# skills-manager vNext Phase 3 Design: Plugin-aware distribution and evaluation

**program_id**: `skills-manager-vnext`
**phase**: `P3`
**status**: implementation_ready
**date**: 2026-08-02

## 1. Goal

在不接管宿主 plugin runtime、安装、认证或 session 的前提下，消费 official/personal/workspace plugin inventory 快照，校验 personal plugin package，并为已证明存在重复分发需求的自维护 workflow 提供单一、受限、fixture-first 的 Codex skills-only plugin exporter 和分层评测。

## 2. Existing basis

- P0/P1/P2 已分别 9/9、9/9、7/7 `repo_verified`；P2 executor 仍严格 fixture-only。
- 四个 custom domain workflow 已在多个 profile 中重复路由，并投影到标准用户技能根。
- 当前官方 inventory 未发现等价的“初中课堂课件 + 物理动画”组合；`presentations`、`remotion` 等是互补执行器。
- Codex CLI 0.145.0 提供 `plugin list --json/--available` 与 `plugin marketplace list --json` 只读快照；官方 manifest 入口是 `.codex-plugin/plugin.json`。
- 官方 `plugin-creator` 已承担 scaffold、marketplace entry 和安装路径，本项目不得重复建设。

## 3. Phase boundary

### In scope

- official/personal/workspace 三类快照 adapter；scope 由调用方显式声明。
- plugin shape advisor：`skills_only | mcp_only | skill_mcp | mcp_ui`。
- manifest lint：name/version/description、component path、source/repository、license、skill structure 和 sensitive-key。
- 一个 `codex-plugin skills-only` exporter：只接受带 `.skills-manager-fixture` 的 root、显式 token、受限文件数/字节数和 root 内 source/output。
- static lint + deterministic behavior fixture + optional model-eval snapshot 的分层报告；model score 不参与 blocker。
- P4 entry gate 的独立机器可验证决策。

### Out of scope

- plugin install/remove/enable、marketplace mutation、OAuth/token、host config/profile、provider call 或 process restart。
- 公共 marketplace、plugin directory 镜像、账号/RBAC、connector runtime、MCP/UI exporter。
- Claude/Gemini 等未经当前官方 schema/help 与 fixture 证明的 exporter。
- 在线 model eval；本阶段只接收可选离线 snapshot，默认 `not_run`。
- 把 repo fixture 写成 `host_loaded` 或 `live_accepted`。

## 4. Product invariants

1. inventory/lint/eval 默认 zero-write、provider-calls=0、native-mutations=0。
2. inventory scope 必须由调用方声明，adapter 不从 marketplace 名称或路径猜测 ownership。
3. exporter 只支持 `codex-plugin` + `skills_only`，source/output 都在 marked fixture root 内。
4. exporter 拒绝 reparse、existing output、path traversal、超过 8 skills/256 files/2 MiB、缺 source/version/license 或 sensitive key。
5. component path 必须以 `./` 开头并保持在 plugin root 内。
6. static/behavior 是 deterministic blocker；model eval 只能补充 evidence。
7. official equivalent 存在时 candidate 默认 deferred；当前只允许已有重复采用和明确受众的 teaching workflow candidate。
8. report 最高只投影实际执行层；本阶段 `host_loaded/live_accepted=not_run`。

## 5. Inventory adapter

输入兼容当前 Codex JSON envelope：

```text
{ installed: PluginItem[], available: PluginItem[] }
PluginItem { pluginId, name, marketplaceName, version, installed, enabled,
             source, marketplaceSource, installPolicy, authPolicy }
```

adapter 将 item 转为 `CapabilityDescriptor(kind=plugin)`，在 component 中保留 `distribution_scope`、安装/启用状态和 marketplace 身份。不读取 plugin 内容，不执行 native command。

## 6. Manifest and supply-chain lint

- required core：`name`、`version`、`description`，且至少声明 skills/apps/mcpServers/hooks 之一。
- distribution gate additionally requires：`repository`、`license`。
- name 使用 kebab-case；version 使用 SemVer；license 接受 SPDX-like 或 `LicenseRef-*` 文本，不伪装在线 registry 校验。
- component path 必须相对、`./` 前缀、无 `..`，且在给出 root 时实际存在。
- skills 目录中的直接子目录必须含 `SKILL.md`；递归 reparse point 和 sensitive property names fail-closed。

## 7. Bounded exporter

candidate fixture 声明 schema/name/version/description/repository/license/audiences/source_skills/evidence_refs。exporter 先完整验证，再在 output sibling staging 目录构建 `.codex-plugin/plugin.json` 与 `skills/<name>/...`，执行 structural/round-trip 校验后一次 rename。失败清理 staging，既有 output 永不覆盖。

## 8. Evaluation layers

| Layer | Gate | Meaning |
| --- | --- | --- |
| `static` | blocking | manifest、path、supply-chain、sensitive/reparse checks |
| `behavior_fixture` | blocking | exported file set/hash round-trip 与结构 fixture |
| `model_snapshot` | non-blocking | 可选离线结果；默认 `not_run`，不得调用 provider |
| `host_load` | separate | 本任务不安装，固定 `not_run` |
| `live_workflow` | separate | 本任务不执行，固定 `not_run` |

## 9. CLI contract

```powershell
.\skills.ps1 plugin-inventory --official <snapshot.json> [--personal <snapshot.json>] [--workspace <snapshot.json>] --json
.\skills.ps1 plugin-lint --path <plugin-root> --json
.\skills.ps1 plugin-export --candidate <candidate.json> --fixture-root <root> --out <new-folder> --token EXPORT_PLUGIN_FIXTURE --json
.\skills.ps1 plugin-eval --path <plugin-root> --json
```

deterministic contract block 返回 exit 2；runtime/input parse failure 返回 exit 1；成功返回 exit 0。JSON stdout 为单一 compressed envelope。

## 10. Task design

1. `SMV-P3-001`：P3 entry evidence、spec、manifest 与 verifier routing。
2. `SMV-P3-002`：三 scope inventory snapshot adapter。
3. `SMV-P3-003`：manifest、shape 与 supply-chain lint。
4. `SMV-P3-004`：fixture-only skills-only exporter 与 rollback guard。
5. `SMV-P3-005`：static/behavior/model-snapshot 分层 eval。
6. `SMV-P3-006`：CLI、acceptance fixture 与兼容验证。
7. `SMV-P3-007`：P3 closeout、P4 entry decision 与文档同步。

## 11. Representative fixtures

- inventory：official、personal、workspace 项保持 scope 与 truth 分离。
- valid：skills-only manifest + one skill。
- invalid：bad SemVer、missing license/source、path escape、missing SKILL、sensitive key。
- export：两个 teaching workflow source，round-trip hash 一致。
- guards：marker missing、wrong token、outside root、existing output、reparse/limit rejection。

## 12. Ordered verification

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-vnext-planning.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-vnext-phase4-entry-gate.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File skills.ps1 doctor --strict --threshold-ms 8000
python scripts/verify-dependency-baseline.py --target-repo-root . --require-target-repo-baseline
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-host-capability-matrix.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree
```

## 13. Failure routing

- CLI snapshot schema drift：输出 bounded finding，不猜字段。
- manifest/path/supply-chain failure：exit 2，export zero-write。
- staging/copy/hash failure：清理本 operation staging；不覆盖 output/source。
- model snapshot 缺失：记录 `not_run`，不调用 provider。
- P4 evidence 不足：写 `not_started/deferred` 决策并停止扩张，不创建 P4 manifest。

## 14. Done definition

- 七个 P3 task 全部 done；planning 和 P4 decision verifier 均 0 finding。
- inventory/lint/export/eval fixture 和 CLI acceptance 通过；生成物同步。
- `skills.json`、host config/profile/plugin state 和只读参考 hash 不变。
- 未创建公共 marketplace，未安装 plugin，未调用 provider/native mutation。
- 最高状态仅 `repo_verified`；`host_loaded/live_accepted=not_run`。
