# skills-manager 加固实施计划与任务清单（2026-08 审计共识）

**文档角色**：versioned design input；动态执行状态与 receipt 只存于 ignored `reports/` 或其所属 POC 仓，本文件只保留稳定的任务合同与可复核指针，不充当状态库。本文件合并后冻结，未出现新的真实失败前不追加任务。
**来源**：2026-08-23 两份独立审计（GLM-5.3 / GPT-5.6）经五轮对抗性交叉评审收敛的 P0–P3 共识；裁决证据见各任务卡 Current evidence。
**执行原则**：沿用 [Hermes 实施计划](skills-manager-hermes-implementation-plan.md) 的执行合同、执行类别（`auto_evidence` / `auto_stop` / `human_decision`）与授权域划分；每个任务是独立授权单元；LOC 统计不作为任何裁剪决定依据；不新增第二套治理系统、任务数据库或候选清单。

## 1. 执行合同

每张任务卡沿用既有七字段合同（`Goal / Current evidence / Exact write set / Out-of-scope assets / Minimum verification / Stop condition / Rollback / Truth boundary / Execution class`）。授权域沿用仓库既有划分：仓库（`src/`、tests、config、tracked docs、generated seam）、宿主（`~/.codex`、`~/.claude`、`~/.zcode`、hooks、投影目标）、Git/发布（push/release）互不推导授权。代码类任务的执行类别按 auto 处理，但其触发仍需当前会话内明确指派；涉及宿主写入一律 `human_decision`。

## 2. 任务总表

| ID | 优先级 | 准入方式 | 依赖 | 目标 | 主要 owner | 写入域 |
| --- | --- | --- | --- | --- | --- | --- |
| HSM-PRJ-001 | P0 | 用户意图确认 | 无 | 投影档位决策：core（8 技能）vs 维持 full-compatible（当前受管集合须 fresh-read） | user | host projection（显式授权） |
| HSM-GAT-100 | P1 | 仓库授权 | 无 | 新建共享 gate 分类器 `scripts/quality/resolve-gate-profile.ps1` | maintainer + AI | scripts/quality + tests/Unit |
| HSM-GAT-110 | P1 | HSM-GAT-100 合并 | GAT-100 | `run-local-quality-gates.ps1` 增加 `-Profile auto` | maintainer + AI | scripts/quality + tests/Unit + README + AGENTS.md |
| HSM-GAT-120 | P1 | HSM-GAT-100 合并 | GAT-100（可与 110 并行） | `ci.yml` 改用共享分类器并迁移 `CiWorkflow.Tests.ps1` 断言 | maintainer + AI | .github/workflows + tests/Unit |
| HSM-GRD-200 | P1 | 当前宿主授权 | 无 | 单宿主静态 guard 能力 POC（observe-only，不改 WatchRuntime） | operator + AI | 宿主观察 + ignored reports |
| HSM-CFG-300 | P2 | 仓库授权 | 无 | `skills.json` schema v3 顶层 allowlist 支持（observe 模式，配置仍为 v2） | maintainer + AI | src/Config.ps1 + config/skills.schema.json + tests/fixtures |
| HSM-CFG-310 | P2 | HSM-CFG-300 合并 + 用户确认 | CFG-300 | `skills.json` 迁移到 v3（enforce）+ 一次 full gate | maintainer + user 确认 | skills.json + tests |
| HSM-RUL-400 | P2 | 用户授权（规则投影） | 无 | 全局规则减法实验（代表性任务复测，无行数硬指标） | user + AI | rules/global + host projection（显式授权） |
| HSM-CLN-500 | P3 | 只读 | 无 | 工作区 ownership inventory（只产出清单，不删除） | AI | ignored reports 一份清单 |
| HSM-CLN-510 | P3 | HSM-CLN-500 + 逐项人工确认 | CLN-500 | 逐项清理：`_commit_repo`、build.log、`.worktrees`、空 docs 树、`.gitignore` stale 条目等 | user 逐项 | 磁盘目录 + `.gitignore`（tracked） |
| HSM-PRJ-600 | P3 | 用户确认 pdf 工作流 | 无 | 条件任务：codex profile 排除 standalone `pdf`（仅当原生 PDF 插件满足工作流） | user + AI | skills.json + tests |

typed-core 不设删除任务卡：`docs/runbooks/powershell-runtime-compatibility.md` 已登记其为 shadow-only PoC，是否保留属 owner 决策；若 CLN-500 inventory 后 owner 决定退役，再按该 runbook 同步删除登记句（docs gate）。

## 3. 原子任务卡

### HSM-PRJ-001：投影档位决策（human_decision）

- **Goal**：消除"配置默认 core、实态 full-compatible"的偏差，让宿主能力面回到用户真实意图。
- **Current evidence**：`skills.json` `projection_profiles.default_profile=core`（8 技能）。2026-08-22 的 ignored `reports/skill-projection/current.json` 曾记录 Codex `profile=full-compatible`、`include_all=true`、80 技能、约 32.5k 字符元数据；这是历史快照，不可替代执行当日的 receipt、受管清单和 external 目录盘点。full-compatible 需显式 `-SkillProfile full-compatible`，属"滞留的显式选择"，非静默漂移。
- **决策问题**：日常是否需要全量技能常驻元数据？core 8 技能 + 冷发现（`capability-router`/`find-skills`）是否覆盖真实工作流？
- **执行前 fresh-read**：只读核对 `skills.json` 的 profile/default、最新 projection receipt 的 selection、受管 manifest/link 集合与 external 目录集合；若任一项与上述历史快照不符，先向用户报告当前差异并重新确认，不写宿主。
- **Exact write set**：分支 A（恢复 core）：在 fresh-read 和当前明确授权后，执行一次 `构建生效`（无参，默认 core）+ 新会话 host probe；分支 B（维持 full）：不写任何文件，仅把用户当前决策保留在授权会话中。
- **Out-of-scope assets**：不改 `skills.json` profile 配置、不改 `agent/`、不动 external skills、不删任何技能。
- **Minimum verification**：分支 A 后 `reports/skill-projection/current.json` 的 `projection_selection.profile=core`；由投影 manifest 的受管集合证明为 8 个 core skills，并以 pre/post 集合比较证明 external 目录未变（不使用用户技能根的总目录数作为断言）。新会话确认预期技能可见。仅证明 `filesystem_projected`；`host_loaded` 需新会话事实，`live_accepted` 需真实任务。
- **Stop condition**：投影或 probe 出现非预期写入（external skills、`~/.codex` 配置变化）即停止并回滚。
- **Rollback**：`构建生效 -SkillProfile full-compatible` 恢复原能力面。
- **Truth boundary**：用户决策 + 一次受控投影；不证明宿主语义改善，后者由后续真实任务观察。
- **Execution class**：`human_decision`。

### HSM-GAT-100：共享 gate 分类器脚本

- **Goal**：把 CI 内联的 docs/focused/full 路径分类逻辑提取为唯一分类器，供 CI 与本地共用，消灭"模型本地选档"的重复判断。
- **Current evidence**：分类正则当前只存在于 `.github/workflows/ci.yml` "Select proportional quality gate profile" 步骤；`scripts/quality/run-local-quality-gates.ps1` 的 `-Profile` 仅接受 `docs/quick/focused/full`，无 auto。
- **Exact write set**：新建 `scripts/quality/resolve-gate-profile.ps1`；新建 `tests/Unit/ResolveGateProfile.Tests.ps1`。不改 CI、不改本地 gate（归 GAT-110/120）。
- **接口契约**：

```powershell
scripts/quality/resolve-gate-profile.ps1
[CmdletBinding()]
param(
    [string]$BaseSha = '',          # 显式 base commit；空则按 origin/main -> @{u} 推导
    [string]$HeadSha = 'HEAD',
    [ValidateSet('local','ci')][string]$Mode = 'local',  # local: git diff <base> --（含工作区）；ci: git diff <base> <head> --
    [switch]$Json
)
```

输出对象字段：`profile`（docs|quick|focused|full）、`reason`（docs_only|risk_path|source_path|default|empty_diff|untracked_file|untracked_scan_failed|no_base|unresolvable_base|diff_failed）、`base_sha`、`head_sha`、`docs_only`（bool）、`focused_test_paths`（string[]）、`changed_count`（int）、`untracked_count`（int）。本地模式把 `git diff --name-only <base>` 的路径与 `git ls-files --others --exclude-standard` 合并分类；为避免新建源码、配置或治理文件漏判，任一 non-ignored untracked file 一律 `profile=full, reason=untracked_file`。分类失败以 `profile=full` + 对应 reason 表达，退出码仍为 0；仅参数用法错误退出 1。脚本只读（仅 `git rev-parse` / `git diff` / `git symbolic-ref` / `git ls-files`），不 fetch、不写任何状态。

- **行为矩阵**：

| # | 输入情形 | profile | reason | focused_test_paths |
| -- | -- | -- | -- | -- |
| 1 | 变更非空且全部匹配 docsOnlyPath | docs | docs_only | `@()` |
| 2 | 任一变更匹配 riskPath | full | risk_path | `@()` |
| 3 | 否则任一变更匹配 sourcePath | focused | source_path | 4 个固定项 + 变更内 `tests/Unit/*.Tests.ps1`，Sort-Object -Unique |
| 4 | 其余非空变更（如仅 `scripts/weekly-skills-update.ps1`） | quick | default | `@()` |
| 5 | tracked 变更为空，且无 non-ignored untracked file | docs | empty_diff | `@()` |
| 6 | 任一 non-ignored untracked file | full | untracked_file | `@()` |
| 7 | untracked 枚举失败 | full | untracked_scan_failed | `@()` |
| 8 | BaseSha 为空且 origin/main、`@{u}` 均不可解析 | full | no_base | `@()` |
| 9 | BaseSha 无法 `git rev-parse --verify <sha>^{commit}` | full | unresolvable_base | `@()` |
| 10 | `git diff --name-only` 非零退出 | full | diff_failed | `@()` |

- **分类正则（唯一权威副本迁入本脚本，逐字保留 CI 现值）**：

```powershell
$riskPath     = '^(tests/E2E/|rules/|overrides/|vendor/|imports/|\.github/workflows/|scripts/(quality/|release/|hooks/|verify-)|build\.ps1$|install\.ps1$|skills\.json$|skills\.lock\.json$|audit-targets\.json$)'
$sourcePath   = '^(src/|tests/Unit/)'
$docsOnlyPath = '^(README(?:\.zh-CN|\.en)?\.md$|CONTRIBUTING\.md$|docs/.*\.md$)'
$fixedFocusedTests = @(
    'tests/Unit/CiWorkflow.Tests.ps1'
    'tests/Unit/InfrastructureSeam.Tests.ps1'
    'tests/Unit/ReadOnlyCli.Tests.ps1'
    'tests/Unit/BuildScript.Tests.ps1'
)
```

- **测试用例（Pester，fixture 为 temp git repo：init -b main、config user、提交含 README.md/src/Core.ps1/tests/Unit/Core.Tests.ps1/skills.json/scripts/quality/x.ps1 的基线提交，每个 It 基于独立 temp repo 修改后以显式 `-BaseSha <基线>` 调用）**：矩阵 #1–#10 各一例；新增 non-ignored untracked `src/New.ps1` 与 `docs/new.md` 均应选 full；focused 组成断言（改 `tests/Unit/Foo.Tests.ps1` → 结果含 Foo + 4 固定项且无重复）；`-Mode ci` 与 `-Mode local` 的 diff 语义各一例（ci 不含未提交变更、local 含）；脚本内容自检（`riskPath` 正则与上述字面量一致，防止漂移）。
- **Out-of-scope assets**：不改 `.github/workflows/ci.yml`、`run-local-quality-gates.ps1`、`src/`（不进 bundle）、既有测试。
- **Minimum verification**：`build.ps1`（确认无生成漂移）+ `tests/run.ps1 -TestPath tests/Unit/ResolveGateProfile.Tests.ps1` + `git diff --check`。
- **Stop condition**：需要 fetch 才能工作、需要读写状态、或与 CI 现行为出现语义差异（矩阵 #4 CI 现状即 quick，保持）。CI 模式不得扫描本地 untracked files；其任务提交内容已由 `<base>..<head>` 定义。
- **Rollback**：删除两个新文件（git revert 单提交）。
- **Truth boundary**：仓库工具；不证明宿主行为。
- **Execution class**：auto（代码）。

### HSM-GAT-110：本地门禁 `-Profile auto`

- **Goal**：日常收口压缩为单命令，模型不再选择档位。
- **Current evidence**：`run-local-quality-gates.ps1` param `-Profile` ValidateSet 为 `docs/quick/focused/full`；focused 强制要求 `-TestPath`/`-TestName`；已有 `-DiffBase` 参数未被 auto 语义复用。
- **Exact write set**：`scripts/quality/run-local-quality-gates.ps1`；`tests/Unit/` 对应测试（若无 gate 脚本专属测试文件则新增 `tests/Unit/QualityGateAuto.Tests.ps1`）；`README.md` "开发与验证"节新增一行 auto 用法；`AGENTS.md` C 节"最低门禁"新增一行 auto 入口。
- **行为契约**：ValidateSet 增加 `'auto'`；auto 时调用 GAT-100 脚本（`-BaseSha $DiffBase`，空则脚本自推导，`-Mode local`），输出一行 `Gate profile auto -> {profile} (reason={reason}, base={base_sha})` 后按解析结果路由到既有 docs/focused（TestPath 由 `focused_test_paths` 供给，绕过 focused 的参数强制检查）/quick/full 分支；解析为 docs 时不得把 resolver 推导出的 base 传给 docs gate，必须保留 `DiffBase=''` 以运行 `git diff --check` 检查当前工作区。CI 的显式 `docs -DiffBase <base>` 行为不变；显式传参路径行为不变。
- **README 行（建议文案）**：`pwsh -NoProfile -File .\scripts\quality\run-local-quality-gates.ps1 -Profile auto` — 按可解析基线与当前工作区（含 non-ignored untracked files）自动选档，无法判定时 fail-safe 选 full。
- **AGENTS.md 行（建议文案）**：本地收口优先 `run-local-quality-gates.ps1 -Profile auto`（与 CI 共享分类器，fail-safe full）；显式档位仅用于复现或覆盖。
- **Out-of-scope assets**：不改 CI、不改分类器语义、不新增 receipt/耗时持久化（耗时仅控制台输出，遵循既有 `tests/run.ps1` 风格）。
- **Minimum verification**：`build.ps1` + 新测试 + `tests/run.ps1 -TestPath tests/Unit/QualityGateAuto.Tests.ps1`（mock/真实 temp repo 覆盖 docs/focused/full/no_base，且断言 local docs auto 对有 trailing-whitespace 的未提交 docs diff 失败、不会传入推导 base）+ `git diff --check`；本任务修改 `scripts/quality/`，属 risk path，输入冻结后直接跑一次 full，不预跑其内部 gate。
- **Stop condition**：auto 分支需要网络、需要新状态文件、或与显式档位行为不一致。
- **Rollback**：git revert 单提交。
- **Truth boundary**：仓库工具。
- **Execution class**：auto（代码）。

### HSM-GAT-120：CI 接入共享分类器

- **Goal**：CI 与本地唯一分类器副本；删除 CI 内联正则。
- **Current evidence**：`ci.yml` 步骤 "Select proportional quality gate profile" 内联分类；`tests/Unit/CiWorkflow.Tests.ps1` 以正则断言 ci.yml 内容（含从 ci.yml 提取 `$riskPath` 字面量并做路径命中测试）。
- **Exact write set**：`.github/workflows/ci.yml`（仅该步骤 body）；`tests/Unit/CiWorkflow.Tests.ps1`。
- **行为契约**：保留 tag/push → full 短路、PR/push-before 的 baseSha 解析与 `git cat-file -e`/`fetch --depth=1` 前奏（fetch 留 CI）；随后以 `& .\scripts\quality\resolve-gate-profile.ps1 -BaseSha $baseSha -Mode ci -Json | ConvertFrom-Json` 取代内联分类；env 变量名与后续 step 消费方式不变（`CI_GATE_PROFILE`/`CI_DIFF_BASE_SHA`/`CI_FOCUSED_TEST_PATHS`）。
- **CiWorkflow.Tests.ps1 断言迁移清单**：删除对 ci.yml 内 `$riskPath = '...'`、`git diff --name-only \$baseSha HEAD`、`docsOnly` 内联的断言；新增对 ci.yml 的"调用 resolve-gate-profile.ps1 且仅一次"断言；将 `$riskPath` 提取与路径命中/不命中两组断言迁至读取 `scripts/quality/resolve-gate-profile.ps1` 内容（`tests/Unit/CiWorkflow.Tests.ps1` 与 `ResolveGateProfile.Tests.ps1` 各自侧重点：前者保供应链契约，后者保行为矩阵）；`run-local-quality-gates\.ps1 @gateArgs` 与唯一调用次数断言保留。
- **Out-of-scope assets**：不改 release job、不改 bootstrap、不改分类器。
- **Minimum verification**：`build.ps1` + `tests/run.ps1 -TestPath tests/Unit/CiWorkflow.Tests.ps1` + `-TestPath tests/Unit/ResolveGateProfile.Tests.ps1`；`.github/` 属风险路径，合并前跑一次 full gate。
- **Stop condition**：迁移导致 CI 语义变化（矩阵 #4 之外的新 profile 映射）或 env 变量消费方需改动。
- **Rollback**：git revert（恢复内联分类器）。
- **Truth boundary**：CI 契约；由 push 后 CI 运行证明。
- **Execution class**：auto（代码）。

### HSM-GRD-200：单宿主静态 guard 能力 POC（observe-only）

- **Goal**：验证"会话内、调用前、静态路径规则阻断"在本机 Codex 的真实覆盖面与误杀率，为是否 enforce 提供证据；不构建通用 hook 平台。
- **Current evidence**：本机 `~/.codex/config.toml` 已有 trusted+enabled 的用户级 `pre_tool_use` hook 与 `codex-watch-runtime` 插件 hook；当前 `codex --help` 也暴露 hook trust 旁路参数，故只能证明 hook 能力已启用，不能证明新 guard 的配置格式、工具覆盖或执行次序。其载荷属 WatchRuntime 最小权限控制面，不可改写或复用其受信逻辑。
- **待验证问题（即验收清单）**：Q1 `apply_patch`、shell、code-mode 嵌套调用是否都被 pre_tool_use 路径覆盖；Q2 `skills.ps1`/`agent/` 的合法构建写入路径如何与"手改生成物"区分（放行规则）；Q3 静态规则候选（仅两类：生成物直改、`git push`）的精确匹配与例外，验证"新增治理文件"类规则误杀率后再考虑；Q4 fresh session 的实际执行证据（非仅有 hook 定义与 trust hash）。
- **Preflight**：先只读确认当前 Codex 版本、hook 配置的实际载体与 runner 语义，并以 `codex --strict-config --version` 记录 mutation 前后均可解析；若无法从当前 help 与现有受信 hook 精确确定新增 hook 的 script/config 路径，记录 `platform_na` 并结束，不猜测配置形状。
- **Exact write set**：经当前授权后，仅允许在 preflight 已命名的独立 POC hook script、其唯一配置条目、仅供本卡回滚的同目录备份，以及 ignored `reports/host-guard-poc/<run-id>/observations.md` 写入；不得触碰既有 WatchRuntime hook 条目或其 trusted hash。报告只记录 redacted 配置语义、文件 hash、coverage 矩阵和误杀结论，不复制 config 内容、命令参数、环境变量或会话数据。
- **Out-of-scope assets**：不改 WatchRuntime hook、不实施 enforce、不做动态 write-set（需会话状态系统，明确不做）、不做跨宿主推广。
- **Minimum verification**：Q1 覆盖每个已知写入工具路径；Q2 对合法 `build.ps1` 生成路径至少一正例；Q3 对两类候选各一正例及至少一不应命中的反例；Q4 有 fresh-session 实际执行证据。观察期间 `~/.codex/config.toml` 除新增条目外 byte-diff 为零，且 `codex --strict-config --version` 成功；不得以固定操作次数代替覆盖证明。
- **Stop condition**：观察影响 WatchRuntime 行为、hook 需要提权、或任何阻断行为在 observe 模式出现。
- **Rollback**：由 POC 备份恢复唯一配置文件，删除独立 POC script/配置/备份，确认原 WatchRuntime hook hash 未变，并验证 fresh session 无残留。
- **Truth boundary**：单机宿主观测；不外推 Claude/ZCode；enforce 需另一次授权决策。
- **Execution class**：`auto_evidence`（宿主写入部分 `human_decision` 授权后执行）。

### HSM-CFG-300：schema v3 顶层 allowlist（observe 模式）

- **Goal**：封死"未来新增顶层字段偷偷塞入 runtime/任务控制面"的入口；v2 保持只读兼容。
- **Current evidence**：`config/skills.schema.json` 顶层 `additionalProperties: true`；`src/Config.ps1` `Get-CfgForbiddenHostRuntimeFieldNames`（:389）仅拒绝 8 个已知字段名，未知顶层字段放行；`Get-CfgSchemaVersionInfo`（:305）以 `$script:SkillsConfigSchemaVersion` 为唯一当前版本。
- **Exact write set**：`src/Config.ps1`、`config/skills.schema.json`、`scripts/verify-skills-config.ps1`、`tests/fixtures/config-schema/`（新增 3 个 fixture）、`tests/Unit/ConfigSchema.Tests.ps1`。`skills.json` 保持 `schema_version: 2`（迁移归 CFG-310）。注意 `src/` 变更需 `build.ps1` 重建 bundle。
- **实现契约**：
  1. 版本解析：声明版本接受 `@(1,2,3)`，`$script:SkillsConfigSchemaVersion=3`；v1 保留既有 `legacy_schema_v1_deprecated`，v2 输出新 observation `schema_v2_observe`（"v2 readable for migration; new writes must use v3"）。
  2. 新函数 `Get-CfgTopLevelFieldAllowlist` 返回且仅返回 11 个字段：`schema_version, sync_mode, update_force, skill_projection, vendors, mappings, imports, targets, mcp_servers, mcp_profiles, mcp_targets`。
   3. 顶层检查：新建一个返回 errors/observations 的共享 helper，并由 `Get-CfgVersionedContractReport` 与 CLI 路径 `Assert-Cfg` 同时调用；`effective_version -ge 3` 且存在 allowlist 外顶层属性 → error `skills.json 顶层字段未被 schema v3 允许：{name}`（fail closed）；`effective_version -eq 2` → 同情形仅 observation `unknown_top_level_field_v2_observe`（observe，不阻断）。同步更新 v1/v2 的迁移提示，使其指向当前 v3。
  4. `config/skills.schema.json`：先 `grep -rn "skills.schema.json" src scripts tests` 确认全部消费者；按消费者实际情况将 v3 allowlist 形状写入（顶层 `additionalProperties: false` + 11 属性），保留 v2 形状可读（`$defs`/`oneOf` 按 schema_version 区分）。
   5. fixtures：`known-good-v3.json`（现 known-good 结构 + `schema_version:3`）、`v3-unknown-top-level.json`（额外 `"runtime_hub": {}`）、`v2-unknown-top-level.json`（`schema_version:2` + 未知顶层）。
   6. `verify-skills-config.ps1` 将上述 v3 拒绝映射为稳定 finding code `unknown_top_level_field_v3`，避免调用方只能依赖中文错误文案。
- **测试用例**：v3 good → valid；v3 未知顶层 → invalid 且含 `unknown_top_level_field_v3`；v2 未知顶层 → valid + `unknown_top_level_field_v2_observe` observation；声明 `4` → 不支持错误；v3 现有 11 字段逐一在 allowlist 内（防拼写漂移）；直接走 `Assert-Cfg`/CLI 入口的 v3 unknown fixture 也必须失败，防止 verifier-only 加固。
- **Out-of-scope assets**：不改 `skills.json`、不动嵌套字段扩展点、不做候选清单。
- **Minimum verification**：`build.ps1` 无漂移 + `tests/run.ps1 -TestPath tests/Unit/ConfigSchema.Tests.ps1` + `scripts/verify-skills-config.ps1 -Mode enforce`（v2 观察模式不改变现有结果）。
- **Stop condition**：需要写入迁移、或 v2 现有配置在任何 verifier 下由绿转红。
- **Rollback**：git revert 单提交。
- **Truth boundary**：仓库契约层。
- **Execution class**：auto（代码）。

### HSM-CFG-310：skills.json 迁移 v3（enforce）

- **Goal**：配置真源切换到 allowlist 强制。
- **前置**：CFG-300 合并；一次性核对 `skills.json` 顶层恰为 11 个 allowlist 字段（`ConvertFrom-Json` 键集比对），任何多余字段先人工裁决。
- **Exact write set**：`skills.json`（`"schema_version": 2` → `3`）、`tests/Unit/ConfigUpdate.Tests.ps1`（如断言版本字面量则同步）。
- **Minimum verification**：`build.ps1` + `skills.ps1 verify-lock` + `scripts/verify-skills-config.ps1 -Mode enforce` + `scripts/verify-skill-integrity.ps1`；`skills.json` 属风险路径 → 输入冻结后一次 full gate。
- **Rollback**：改回 `2` 即恢复 v2 只读路径（由 CFG-300 设计保证）。
- **Truth boundary**：配置契约变更；不影响宿主。
- **Execution class**：auto（代码，触发前用户确认迁移时机）。

### HSM-RUL-400：全局规则减法实验

- **Goal**：用实验（而非行数指标）确定可删规则组，降低规则稀释；建立"删减必须复测"的方法论。
- **Current evidence**：`rules/global/` v9.77：codex 101 行 / claude 104 行 / zcode 40 行，均低于 A.7 预算（130 行/16KiB）；近期 15 个 commit 中 9 个为边界文案打磨——通胀压力来自频度而非预算超标。
- **探针集 P（固定提示词，每次均在 fresh session 执行，先 codex 宿主）**：P1 扩张探针（诱导"顺手加个通用缓存层/抽象层"，合规=先要证据或拒绝，违规=直接建抽象）；P2 门禁探针（docs-only 修改，合规=仅 diff-check，违规=跑测试/full）；P3 重复审计探针（小修完成后，合规=单次 focused 收口，违规=二次 full/重复 verifier）；P4 停止探针（目标达成后，合规=立即收口，违规=继续"还可以…"）。每次记录宿主、模型、reasoning、skill projection 与 prompt-input hash；这些是可比性元数据，不新建状态库。
- **实验协议**：候选组先通过静态重复性证明（同一判断已被保留的规则或确定性层完整表达）才可准入 → 基线运行 P1–P4 各一次记录违规 → 删除一个候选规则组 → `global-rules-plan/apply` 投影（显式授权 + receipt）→ 同探针复测。任一新增违规立即 `global-rules-rollback`；未观察到新增违规只允许把删减保留到下一次真实任务观察，不构成其安全性的充分证明。每周期最多一组；结果记 ignored `reports/global-rule-projection/` 既有目录。
- **Exact write set**：`rules/global/*.md`（每组一个提交）+ 宿主投影（每次显式授权）。
- **Out-of-scope assets**：不设行数 KPI、不做"一进一出"硬规则、不同时删多组、不改项目级 AGENTS.md。
- **Minimum verification**：每周期基线/复测对照表 + 投影 receipt；`git diff --check`。
- **Stop condition**：任一探针新增违规、投影失败、比较环境无法保持同一宿主/模型/档位，或需要同时改 A/C/D 共享正文（跨宿主一致性风险 → 拆更小步）。
- **Rollback**：`global-rules-rollback --receipt` 逐次恢复；git revert rules/global 提交。
- **Truth boundary**：`filesystem_projected` + 探针观察；探针通过不等于 `host_loaded/live_accepted`。
- **Execution class**：实验（投影步骤 `human_decision` 授权）。

### HSM-CLN-500：工作区 ownership inventory（只读）

- **Goal**：为清理提供逐项归属证据；不删除任何东西。
- **Exact write set**：ignored `reports/workspace-inventory/<date>/inventory.md` 一份。
- **逐项命令（写入清单）**：

| 候选 | 归属判定命令 | 判定要点 |
| -- | -- | -- |
| `_commit_repo/` | `git -C _commit_repo status --short --branch`、`git -C _commit_repo log --oneline -3` | 是否含未合并提交/未推送资产 |
| `.worktrees/<name>`（3 个） | `git worktree list`（已知无注册）、逐个 `git -C .worktrees/<name> status --porcelain`、`git branch -a --list *<name>*` | 未提交文件先导出再谈删 |
| `build.log`、`build.log.1-5` | `Get-ChildItem -Force -File -Filter 'build.log*'` | 均为 ignored 运行日志 |
| `.pytest_cache/`、`.playwright-mcp/`、`.governance/`、`.governed-ai/` | `Get-ChildItem -Recurse | Measure-Object` + 最后写入时间 | 陈旧且无引用 → 候选 |
| `docs/{archive,change-evidence,governance,plans,research,superpowers}` | `rg -n 'docs/(archive|change-evidence|governance|plans|research|superpowers)' src scripts build.ps1 .github .gitignore` | 6 个零文件目录树；注意 `.gitignore` 的 `/docs/governance/merge-report.md` 为 stale 关联 |
| `.gitignore` stale 条目 | `git check-ignore -v AGENTS.md CLAUDE.md GEMINI.md` | 三文件 tracked，ignore 无效且误导 |

- **Out-of-scope assets**：`typed-core/`（runbook 登记，owner 决策）、`.txn/`（`src/Commands/Install.ps1:1881` 引用，不属清理）、`vendor/`、`imports/`、`agent/`、`reports/`。
- **Minimum verification**：清单覆盖表中全部候选且每项有命令输出引用。
- **Stop condition**：任何命令需要写操作或网络。
- **Rollback**：无（只读）。
- **Truth boundary**：文件系统观察。
- **Execution class**：`auto_evidence`。

### HSM-CLN-510：逐项清理（human_decision per item）

- **Goal**：按 inventory 逐项、可回滚地清理。
- **Exact write set**：逐项确认后的磁盘删除 + `.gitignore`（tracked，一次性小修复：移除 `/AGENTS.md`、`/CLAUDE.md`、`/GEMINI.md` 三行与 `/docs/governance/merge-report.md`（如对应目录树一并删除）；删除前后 `git status --porcelain` 的差异只能是已授权的 `.gitignore` 修改，或 inventory 明确列出的被删除 untracked 项消失，不能出现其他 tracked 写入）。
- **Minimum verification**：`.gitignore` 变更走 docs gate（`git diff --check`）；删除项逐条记录于 inventory 附加节。
- **Stop condition**：任何一项归属存疑 → 保留该项并记录原因，不阻塞其余项。
- **Rollback**：`.gitignore` git revert；磁盘删除不可逆，故每项删除前须用户显式确认（本卡默认全部待确认）。
- **Truth boundary**：本地工作区卫生；不影响仓库合同。
- **Execution class**：`human_decision`（逐项）。

### HSM-PRJ-600：条件任务——codex 排除 standalone pdf

- **Goal**：消除宿主原生 PDF 插件与 standalone `pdf` 技能的触发竞争（仅当用户确认原生插件满足 Codex 工作流）。
- **Current evidence**：宿主探针曾报告原生 PDF plugin 启用 + 用户技能根存在 standalone `pdf`；工具仅报 `plugin_native_source_preferred`，未自动处理（正确行为）。
- **Exact write set**：`skills.json` `projection_profiles.hosts.codex.exclude` 增加 `"pdf"`；`tests/Unit/SkillProjectionProfiles.Tests.ps1` 同步断言。
- **Out-of-scope assets**：不动 Claude/ZCode 的 pdf 投影、不删技能、不改 vendor。
- **Minimum verification**：`build.ps1` + 受影响测试 + `verify-skills-config.ps1 -Mode enforce`；`skills.json` 属风险路径 → 一次 full gate；投影到宿主需另行授权 `构建生效`。
- **Stop condition**：用户未确认原生插件可替代，或 Claude/ZCode 工作流仍需 standalone pdf（只做 per-host 排除，绝不全局删）。
- **Rollback**：移除 exclude 条目 + 重新 `构建生效`。
- **Execution class**：conditional（用户确认后 auto）。

## 4. 根因与对策映射

五轮评审对"AI 反复过度设计/过度验证/重复审计"的根因结论，与任务卡的对应关系（防止未来只抄对策不记得为什么）：

| 根因（收敛结论） | 对策落点 |
| -- | -- |
| prose 负向约束输给训练先验："不要过度设计"是会话晚期否定句，对手是"多验证更安全"的正向默认 | 原则文本不再加厚；对策全部机制化（GAT/GRD/CFG 系列与本节以下各行） |
| 规则通胀跑步机：违规 → 加规则 → 单条权重稀释 → 违规更多（证据：v9.77 迭代、近期 15 commit 中 9 个边界文案打磨） | HSM-RUL-400 减法实验；本文件 §5 冻结声明；"第二次违规必须用机制修，禁止加 prose" |
| 成本不对称：过度验证浪费的是用户时间，模型无感知、无计量 | HSM-GAT-110 控制台输出 gate 耗时；分类器保证 full 单 slice 单次 |
| 判断 vs 机制：同一选档决策，CI 分类器从不失误、模型选择间歇失败 | HSM-GAT-100/110/120：把档位选择从模型移入确定性代码 |
| 会话重置：行为纠正不持久，唯一通道（改规则文件）反哺跑步机 | 纠正通道改为本文件任务卡 + 机制层；规则文件只减不增 |
| 技能放大：验证类技能天然推高验证倾向 | 已由 `overrides/patches`（lowest-sufficient、do-not-escalate 措辞）对冲；无新行动项 |

## 5. 冻结、明确不做与反膨胀声明

- 本文件是任务合同，不是状态库；任务完成状态由 Git 历史、ignored receipt 与其所属 POC 的 reviewed evidence 承载。
- 未列入本表的想法（新 verifier、新治理层、新登记系统、Hermes adapter）默认 `no_code_needed`；准入必须走"真实失败 + 既有 interface 无法承载 + 净收益 + 可回滚"四问，作为新任务卡追加前需用户显式授权。
- 与 [Hermes 实施计划](skills-manager-hermes-implementation-plan.md) 的边界：本文件不授权任何 Hermes/宿主 runtime 变更；HSM-GRD-200 的宿主写入是独立授权域。

**已裁决"不做/维持现状"清单**（五轮评审的负面决定；未出现新的真实失败前不重新提案）：

- AuditTargets 的 preflight/dry-run/drift/显式 apply/回滚事务语义保留，不按使用频率或 LOC 裁剪（`recommendations.json` 是 AI 可编辑的外部写路径输入）。
- vendor metadata 的 51 条 warning 不清洗、不建转换层或新门禁；仅当某宿主真实误解析时做最小兼容修复。
- 双语命令面维持中文 canonical + 英文互操作，不收敛为英文单 canonical（无当前失败）。
- 不新增重量级 pre-commit 验证门禁；gate 耗时只进控制台输出，不建新 receipt/状态结构。
- 不做动态 write-set hook（需要会话身份/授权/生命周期状态，等于第二治理系统）；"新增治理文件"静态规则在 GRD-200 证明误杀率前不实施；push 阻断优先由宿主审批与远端保护承担。
- 规则减法不设行数 KPI（如 ≤60 行）、不做"一进一出"形式规则；以代表性任务复测为准。
- 非交互终端（TERM=dumb）下 `codex doctor` 的 fail 不修（非本仓产品故障）。
- `.txn/` 不清理（`src/Commands/Install.ps1:1881` 活引用）；`typed-core/` 不设删除卡（runbook 登记的 shadow-only PoC，退役由 owner 决策并同步该 runbook）。
- LOC 统计不作为任何裁剪决定依据（已知陷阱：物理行 vs 非空行两种计数语义在同 HEAD 可产生 6%–14% 差异；任何数字主张必须附 exact glob、计数语义与 commit SHA）。
