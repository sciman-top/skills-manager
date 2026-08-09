# Host-native-first Self-retiring Engineering Constitution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `host-native-first / main-chain-first / anti-overdesign / self-retiring / no-second-governance-plane` 固化为唯一产品原则、仓库动作映射和兼容的确定性 admission 合同。

**Architecture:** PRD 保存唯一规范性正文，`AGENTS.md` 只保存项目动作入口；现有 `verify-vnext-planning.ps1` 和 `verify-agent-workflow-advisory.ps1` 承担机械检查。现有 `TaskGraph` 以 schema v2 承接最小 delivery admission，schema v1 保留只读兼容；宿主 AI 继续拥有语义判断和执行决策，仓库只校验声明并输出零副作用投影。

**Tech Stack:** PowerShell 7、Pester 4.10.1、JSON fixtures、Markdown 产品真源、现有 build/full-quality-gate 链路。

## Global Constraints

- 不修改 Codex/Claude 宿主配置、active profile、provider、auth、session、permissions 或 hooks。
- 不修改 GitHub branch protection、required checks 或远端管理策略。
- 不创建 constitution registry、workflow runtime、scheduler、daemon、ledger、database、telemetry service、dashboard 或新总 verifier。
- 不创建 P7，不改写已完成的 P6/AWA/maintenance 历史任务状态；当前 P6 的 `host_evaluation_partial / host_invocation_observed=not_observed / live_accepted=not_accepted` 保持不变。
- `docs/product/skills-manager-vnext-prd.md` 是顶层原则唯一规范性正文；设计 spec 和 change evidence 不是第二真源。
- `TaskGraph` schema v2 是新的标准输入；schema v1 仅保留兼容校验，不自动提升为 v2 admission 已通过。
- simple/direct-fix 不要求 `native_baseline` 或 `complexity_admission`；AI capability、治理或长期维护面才要求原生基线，长期维护面还要求复杂度依据和 retirement trigger。
- 现有 `verification[]` 直接承接 `minimum_sufficient_verification` 语义，不增加第二个同义数组。
- 语义判断仍属于 host AI；确定性代码只校验字段、枚举、依赖顺序、条件字段和零副作用，不使用脆弱的文件数/行数/关键词复杂度评分。
- 迭代只运行 focused Pester、planning/advisory verifier 和 build；所有 tracked source 稳定并提交 candidate 后只运行一次 full gate，再运行 current receipt verifier。

## File Structure

- Modify: `docs/product/skills-manager-vnext-prd.md` — 保存 `PP-000` 唯一顶层原则和 TaskGraph v2 当前合同。
- Modify: `AGENTS.md` — 增加一条指向 `PP-000`、现有 manifest/verifier/full gate 的项目动作映射。
- Modify: `scripts/verify-vnext-planning.ps1` — 检查 PRD 唯一原则和 AGENTS 窄映射，不增加新 verifier。
- Modify: `tests/Unit/ProductPlanning.Tests.ps1` — 覆盖原则正文或映射缺失时的 fail-closed 行为。
- Modify: `src/Domain/AgentWorkflow.ps1` — 支持 TaskGraph v2 delivery admission，并保留 v1 compatibility。
- Modify: `src/Application/ModelAndAgentPolicy.ps1` — 将已验证的 stage/checkpoint 投影进 advisory plan，不调度或执行任务。
- Modify: `tests/fixtures/agent-workflow/valid-request.json` — 将 canonical fixture 升级为 schema v2。
- Modify: `tests/Unit/AgentWorkflowContracts.Tests.ps1` — 覆盖 direct-fix、条件基线、复杂度 admission、stage 顺序和 v1 compatibility。
- Modify: `scripts/verify-agent-workflow-advisory.ps1` — 固化 v2 canonical/v1 compatibility、admission markers 与零副作用边界。
- Modify: `tests/Unit/AgentWorkflowAdvisoryPlanning.Tests.ps1` — 验证 advisory verifier 能阻断 v2 合同漂移。
- Modify: `docs/product/skills-manager-vnext-architecture.md` — 记录 v2 标准路径与 v1 兼容边界。
- Modify: `docs/product/skills-manager-vnext-roadmap.md` — 更新当前 AWA 能力摘要，不重写历史验收。
- Modify: `README.md` — 同步中文用户入口的 TaskGraph v2/v1 compatibility 当前事实。
- Modify: `README.en.md` — 同步英文用户入口的 TaskGraph v2/v1 compatibility 当前事实。
- Modify: `skills.ps1` — 仅由 `build.ps1` 从 `src/*` 重新生成。
- Create: `docs/change-evidence/20260809-host-native-first-self-retiring-engineering-constitution.md` — 记录依据、命令、truth boundary、回滚和 runtime receipt 指针。

---

### Task 1: 固化唯一顶层原则和 planning 映射

**Files:**

- Modify: `docs/product/skills-manager-vnext-prd.md`
- Modify: `AGENTS.md`
- Modify: `scripts/verify-vnext-planning.ps1`
- Test: `tests/Unit/ProductPlanning.Tests.ps1`

**Interfaces:**

- Consumes: 当前 `PP-001..PP-013`、P6 manifest truth、`Get-RequiredText` 与 `Add-PlanningFinding`。
- Produces: `PP-000 Host-native-first main-chain-first self-retiring`、`TOP_LEVEL_ENGINEERING_PRINCIPLE: PP-000` 和 findings `engineering_constitution_missing` / `engineering_constitution_mapping_missing`。

- [ ] **Step 1: 写入 planning verifier 的失败测试**

在 `tests/Unit/ProductPlanning.Tests.ps1` 增加两个 fixture mutation 用例：

```powershell
It 'requires the unique top-level engineering constitution in the PRD' {
    $fixtureRoot = New-PlanningFixture 'missing-engineering-constitution'
    $path = Join-Path $fixtureRoot 'docs\product\skills-manager-vnext-prd.md'
    $content = (Get-Content -LiteralPath $path -Raw).Replace('### PP-000 Host-native-first main-chain-first self-retiring', '### PP-000 removed')
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8

    $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json
    @($parsed.findings | Where-Object code -eq 'engineering_constitution_missing').Count | Should Be 1
}

It 'requires the repository action mapping without duplicating the constitution' {
    $fixtureRoot = New-PlanningFixture 'missing-engineering-constitution-mapping'
    $path = Join-Path $fixtureRoot 'AGENTS.md'
    $content = (Get-Content -LiteralPath $path -Raw).Replace('TOP_LEVEL_ENGINEERING_PRINCIPLE: PP-000', 'TOP_LEVEL_ENGINEERING_PRINCIPLE: missing')
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8

    $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json
    @($parsed.findings | Where-Object code -eq 'engineering_constitution_mapping_missing').Count | Should Be 1
}
```

- [ ] **Step 2: 运行 RED 测试**

Run:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -RequiredVersion 4.10.1; Invoke-Pester -Script tests/Unit/ProductPlanning.Tests.ps1 -EnableExit"
```

Expected: 新增两个用例失败，因为 verifier 尚未产生对应 finding。

- [ ] **Step 3: 增加唯一规范性正文和窄项目映射**

在 `PP-001` 前增加：

```markdown
### PP-000 Host-native-first main-chain-first self-retiring

在授权、安全、数据、兼容和真值边界内，本项目最大化宿主 AI 原生能力并优先交付最短真实主链；无真实重复、稳定协议、已证实风险或量化热点，不新增抽象、治理或优化层。本项目仅补宿主原生能力的真实缺口；当原生能力覆盖、功能重叠、消费者消失或维护成本超过净收益时，相关能力必须依据可复核证据进入弱化或退役处置，有兼容义务时先转为 compatibility-only/deprecated，义务结束后最终 retired。仅仅缺少遥测或使用记录不能单独证明消费者消失。不得为执行本条款建立第二套治理或运行控制面。
```

在 `AGENTS.md` B.1 增加且只增加一条动作映射：

```markdown
- `TOP_LEVEL_ENGINEERING_PRINCIPLE: PP-000`：唯一正文在 PRD；任务以当前 manifest/TaskGraph 声明主链、原生复用、最低验证和退役条件，`verify-vnext-planning.ps1`/`verify-agent-workflow-advisory.ps1` 机械阻断，closeout 仍只走 full gate；不得另建治理或运行控制面。
```

- [ ] **Step 4: 扩展现有 planning verifier**

将 `AGENTS.md` 加入 `$paths`，并在 current/historical 共用区执行稳定 literal 检查：

```powershell
foreach ($required in @(
        @{ key = 'prd'; literal = '### PP-000 Host-native-first main-chain-first self-retiring'; code = 'engineering_constitution_missing' },
        @{ key = 'prd'; literal = '不得为执行本条款建立第二套治理或运行控制面'; code = 'engineering_constitution_missing' },
        @{ key = 'agents'; literal = 'TOP_LEVEL_ENGINEERING_PRINCIPLE: PP-000'; code = 'engineering_constitution_mapping_missing' },
        @{ key = 'agents'; literal = 'verify-agent-workflow-advisory.ps1'; code = 'engineering_constitution_mapping_missing' }
    )) {
    if (-not (Test-ContainsLiteral $content[$required.key] $required.literal)) {
        Add-PlanningFinding ([ref]$findings) $required.code $paths[$required.key] ('Required engineering constitution marker is missing: {0}' -f $required.literal)
    }
}
```

- [ ] **Step 5: 运行 GREEN 和 planning contract**

Run:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -RequiredVersion 4.10.1; Invoke-Pester -Script tests/Unit/ProductPlanning.Tests.ps1 -EnableExit"
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-vnext-planning.ps1 -Json
```

Expected: focused Pester 全部通过；verifier 返回 `pass=true`，P6 truth level 不变化。

- [ ] **Step 6: 精确提交 Task 1**

```powershell
git add -- docs/product/skills-manager-vnext-prd.md AGENTS.md scripts/verify-vnext-planning.ps1 tests/Unit/ProductPlanning.Tests.ps1
git diff --cached --check
git commit -m "docs: 固化宿主原生优先顶层原则"
```

---

### Task 2: 将最小 delivery admission 接入 TaskGraph v2

**Files:**

- Modify: `src/Domain/AgentWorkflow.ps1`
- Modify: `tests/fixtures/agent-workflow/valid-request.json`
- Test: `tests/Unit/AgentWorkflowContracts.Tests.ps1`
- Modify: `docs/product/skills-manager-vnext-prd.md`

**Interfaces:**

- Consumes: `TaskGraph` v1 fields、`Get-OperationObjectProperty`、`New-OperationFinding`、现有 `verification[]`。
- Produces: TaskGraph schema v2；v2 task fields `delivery_stage / admission_scope / user_outcome / entrypoint / main_chain_checkpoint / reuse_decision`；conditional `native_baseline / complexity_admission`；v1 compatibility validation。

- [ ] **Step 1: 写 v2 positive/negative 和 v1 compatibility 测试**

在 `tests/Unit/AgentWorkflowContracts.Tests.ps1` 增加以下行为：

```powershell
It 'accepts a direct fix without native or complexity admission' {
    $graph = (Get-AgentWorkflowFixture 'valid-request.json').task_graph | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $task = $graph.tasks[1]
    $task.admission_scope = 'direct_fix'
    $task.PSObject.Properties.Remove('native_baseline')
    $task.PSObject.Properties.Remove('complexity_admission')
    (Test-AgentTaskGraphContract $graph).pass | Should Be $true
}

It 'requires native evidence for capability governance and long-lived surfaces' {
    $graph = (Get-AgentWorkflowFixture 'valid-request.json').task_graph | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $graph.tasks[1].admission_scope = 'ai_capability'
    $graph.tasks[1].PSObject.Properties.Remove('native_baseline')
    @((Test-AgentTaskGraphContract $graph).findings | Where-Object code -eq 'native_baseline_required').Count | Should Be 1

    $graph.tasks[1].admission_scope = 'long_lived_surface'
    $graph.tasks[1] | Add-Member -Force -NotePropertyName native_baseline -NotePropertyValue ([pscustomobject]@{
        equivalent = 'none'; observed_gap = 'verified gap'; evidence = @('official help and repo evidence')
    })
    $graph.tasks[1].PSObject.Properties.Remove('complexity_admission')
    @((Test-AgentTaskGraphContract $graph).findings | Where-Object code -eq 'complexity_admission_required').Count | Should Be 1
}

It 'rejects stage inversion and preserves TaskGraph v1 compatibility' {
    $graph = (Get-AgentWorkflowFixture 'valid-request.json').task_graph | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $graph.tasks[0].delivery_stage = 'release'
    $graph.tasks[1].delivery_stage = 'main_chain'
    @((Test-AgentTaskGraphContract $graph).findings | Where-Object code -eq 'delivery_stage_dependency_invalid').Count | Should BeGreaterThan 0

    $legacy = $graph | ConvertTo-Json -Depth 50 | ConvertFrom-Json
    $legacy.schema_version = 1
    foreach ($task in @($legacy.tasks)) {
        foreach ($field in @('delivery_stage','admission_scope','user_outcome','entrypoint','main_chain_checkpoint','reuse_decision','native_baseline','complexity_admission')) {
            $task.PSObject.Properties.Remove($field)
        }
    }
    (Test-AgentTaskGraphContract $legacy).pass | Should Be $true
}
```

- [ ] **Step 2: 运行 RED contract test**

Run:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -RequiredVersion 4.10.1; Invoke-Pester -Script tests/Unit/AgentWorkflowContracts.Tests.ps1 -EnableExit"
```

Expected: v2 admission tests失败，因为 validator 尚未识别新字段和 stage ordering。

- [ ] **Step 3: 实现 TaskGraph v2 且保留 v1 compatibility**

把构造函数改为显式 schema 参数，默认标准路径为 v2：

```powershell
function New-AgentTaskGraph {
    param(
        [Parameter(Mandatory = $true)][string]$GraphId,
        [Parameter(Mandatory = $true)][string]$BaseRevision,
        [Parameter(Mandatory = $true)][string]$IntegrationOwner,
        [ValidateSet(1, 2)][int]$SchemaVersion = 2,
        [object[]]$Tasks = @()
    )
    # Existing deterministic copy/sort remains unchanged.
}
```

`Test-AgentTaskGraphContract` 接受 schema 1/2。对 schema 2 校验：

```powershell
$allowedStages = @('discovery','main_chain','stabilize','refactor','release','operate')
$allowedScopes = @('direct_fix','product_delivery','ai_capability','governance','long_lived_surface')
$allowedReuse = @('adopt','adapt','defer','reject')
$allowedComplexityKinds = @('two_real_repetitions','stable_external_protocol','proven_safety_or_data_seam','measured_hotspot')
```

每个 v2 task 必须有 `delivery_stage / admission_scope / user_outcome / entrypoint / main_chain_checkpoint / reuse_decision`；既有 `verification[]` 必须非空并直接解释为最低充分验证。`ai_capability / governance / long_lived_surface` 必须有 `native_baseline.equivalent / observed_gap / evidence[]`；`long_lived_surface` 还必须有 `complexity_admission.kind / evidence_refs[] / real_consumers[] / maintenance_cost / retirement_trigger`。

依赖边只允许同 stage 或从较早 stage 指向较晚 stage；`stabilize/refactor/release` 至少有一个 `main_chain` ancestor，`operate` 至少有一个 `release` ancestor。不要强制没有真实失败的任务机械经过 stabilize/refactor。

- [ ] **Step 4: 升级 canonical fixture，不改历史 manifest**

将 `tests/fixtures/agent-workflow/valid-request.json` 的 `task_graph.schema_version` 改为 2。四个 task 分别使用 `discovery / main_chain / main_chain / release`，`admission_scope=product_delivery`，并填入用户结果、真实入口、checkpoint 和 `reuse_decision=adopt`；继续复用现有 `verification[]`，不新增同义数组。

- [ ] **Step 5: 更新当前 PRD contract wording**

只更新当前规范性 requirement，不重写历史 spec/evidence：

```markdown
- `FR-EWF-018`：仓库必须提供 runtime-independent 的 `TaskGraph v2 / FailurePacket v1`；TaskGraph v1 仅保留 compatibility validation，不能证明 v2 delivery admission 已通过。v2 在既有任务字段上增加 delivery stage、admission scope、user outcome、entrypoint、main-chain checkpoint、reuse decision，以及按适用范围要求的 native baseline、complexity evidence 和 retirement trigger。
```

- [ ] **Step 6: 运行 GREEN contract tests**

Run:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -RequiredVersion 4.10.1; Invoke-Pester -Script tests/Unit/AgentWorkflowContracts.Tests.ps1 -EnableExit"
```

Expected: v2 positive/negative cases和现有 v1 behavior全部通过；无 provider/native/write effect。

- [ ] **Step 7: 精确提交 Task 2**

```powershell
git add -- src/Domain/AgentWorkflow.ps1 tests/fixtures/agent-workflow/valid-request.json tests/Unit/AgentWorkflowContracts.Tests.ps1 docs/product/skills-manager-vnext-prd.md
git diff --cached --check
git commit -m "feat: 增加自退役交付准入合同"
```

---

### Task 3: 投影 admission、强化现有 advisory verifier 并同步当前架构

**Files:**

- Modify: `src/Application/ModelAndAgentPolicy.ps1`
- Modify: `scripts/verify-agent-workflow-advisory.ps1`
- Test: `tests/Unit/AgentWorkflowContracts.Tests.ps1`
- Test: `tests/Unit/AgentWorkflowAdvisoryPlanning.Tests.ps1`
- Modify: `docs/product/skills-manager-vnext-architecture.md`
- Modify: `docs/product/skills-manager-vnext-roadmap.md`
- Modify: `README.md`
- Modify: `README.en.md`
- Modify generated: `skills.ps1`
- Create: `docs/change-evidence/20260809-host-native-first-self-retiring-engineering-constitution.md`

**Interfaces:**

- Consumes: validated TaskGraph v2 tasks、`New-AgentExecutionPlan` one-group waves、existing advisory verifier、`build.ps1`。
- Produces: wave group 的 `admission` read-only projection；advisory verifier markers；exact-current-source full receipt pointer。

- [ ] **Step 1: 写 projection 和 verifier 漂移的失败测试**

在 contract test 中要求 v2 plan group 投影已验证字段：

```powershell
$plan = New-AgentExecutionPlan -TaskGraph (Get-AgentWorkflowFixture 'valid-request.json').task_graph
$plan.waves[0].groups[0].admission[0].task_id | Should Be 'discover'
$plan.waves[0].groups[0].admission[0].delivery_stage | Should Be 'discovery'
$plan.waves[0].groups[0].admission[0].main_chain_checkpoint | Should Not BeNullOrEmpty
```

在 `AgentWorkflowAdvisoryPlanning.Tests.ps1` 的 mutation fixture 中移除 `native_baseline_required` marker，并断言 finding：

```powershell
@($parsed.findings | Where-Object code -eq 'delivery_admission_contract_missing').Count | Should BeGreaterThan 0
```

- [ ] **Step 2: 运行 RED focused tests**

Run:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -RequiredVersion 4.10.1; Invoke-Pester -Script @('tests/Unit/AgentWorkflowContracts.Tests.ps1','tests/Unit/AgentWorkflowAdvisoryPlanning.Tests.ps1') -EnableExit"
```

Expected: projection 和 verifier marker 用例失败。

- [ ] **Step 3: 增加零副作用 admission projection**

在每个 group 增加只读投影，不改变 wave selection：

```powershell
$admission = if ([int](Get-OperationObjectProperty $TaskGraph 'schema_version') -eq 2) {
    @($selectedTasks.ToArray() | ForEach-Object {
        [pscustomobject][ordered]@{
            task_id = [string](Get-OperationObjectProperty $_ 'task_id')
            delivery_stage = [string](Get-OperationObjectProperty $_ 'delivery_stage')
            main_chain_checkpoint = [string](Get-OperationObjectProperty $_ 'main_chain_checkpoint')
        }
    })
}
else { @() }
```

group 保留 `mode/task_ids` 并增加 `admission=$admission`；plan envelope 的 `provider_calls/native_mutations/writes` 继续为 0。

- [ ] **Step 4: 强化现有 advisory verifier**

在 `scripts/verify-agent-workflow-advisory.ps1` 的 literal contracts 中加入：

```powershell
@{ key='domain'; literal='native_baseline_required'; code='delivery_admission_contract_missing' }
@{ key='domain'; literal='complexity_admission_required'; code='delivery_admission_contract_missing' }
@{ key='domain'; literal='delivery_stage_dependency_invalid'; code='delivery_admission_contract_missing' }
@{ key='validFixture'; literal='"schema_version": 2'; code='fixture_contract_missing' }
@{ key='application'; literal='main_chain_checkpoint'; code='delivery_admission_projection_missing' }
```

不添加新的 quality-gate step；full gate 已调用 advisory verifier。

- [ ] **Step 5: 同步当前架构/路线图和单份 evidence**

当前架构、roadmap 和中英文 README 只把现行 canonical contract 改为 `TaskGraph v2 / v1 compatibility / FailurePacket v1`，保留历史 AWA-002 的 repo verification 叙述。evidence 记录：

```markdown
truth_boundary: repo_contract_enforced
host_loaded: not_changed
host_invocation_observed: not_observed
live_accepted: not_accepted
full_gate_authority: reports/quality-gates/current.json
rollback: revert only this slice; keep TaskGraph v1 compatibility
```

不得把本次 fixture/verifier 写成真实效率、host invocation 或 live acceptance。

- [ ] **Step 6: 运行 build 和全部 affected checks**

Run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1
pwsh -NoProfile -Command "Import-Module Pester -RequiredVersion 4.10.1; Invoke-Pester -Script @('tests/Unit/ProductPlanning.Tests.ps1','tests/Unit/AgentWorkflowContracts.Tests.ps1','tests/Unit/AgentWorkflowAdvisoryPlanning.Tests.ps1') -EnableExit"
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-vnext-planning.ps1 -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/verify-agent-workflow-advisory.ps1 -Json
```

Expected: build exit 0；affected Pester 0 failed；两个 verifier `pass=true`；生成 `skills.ps1` 与 source 同步。

- [ ] **Step 7: 创建最终 candidate commit**

```powershell
git add -- src/Application/ModelAndAgentPolicy.ps1 scripts/verify-agent-workflow-advisory.ps1 tests/Unit/AgentWorkflowContracts.Tests.ps1 tests/Unit/AgentWorkflowAdvisoryPlanning.Tests.ps1 docs/product/skills-manager-vnext-architecture.md docs/product/skills-manager-vnext-roadmap.md README.md README.en.md skills.ps1 docs/change-evidence/20260809-host-native-first-self-retiring-engineering-constitution.md
git diff --cached --check
git commit -m "test: 强化宿主原生优先交付门禁"
```

- [ ] **Step 8: 只运行一次 authoritative full gate**

确认 candidate HEAD 后运行：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/run-local-quality-gates.ps1 -Profile full
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/quality/verify-current-quality-gate.ps1 -RequiredProfile full -RequiredStatus passed -Json
```

Expected: full gate exit 0；current verifier `pass=true` 且 source binding 指向 exact current candidate。若失败，先修根因并创建新 candidate，再重新运行 full；不得修改 tracked source 后复用旧 receipt。

- [ ] **Step 9: 最终 Git 与 truth closeout**

```powershell
git status --short --branch
git log -4 --oneline --decorate
git diff main...HEAD --check
```

Expected: 工作树 clean；本任务 commit 可独立回滚；最大 claim 为 `repo_contract_enforced`。`host_loaded/live_accepted` 不升级，且不自动推送或修改远端策略。
