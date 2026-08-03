[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$ManifestPath,
    [string]$SpecPath,
    [switch]$Json,
    [switch]$NoExit
)

$ErrorActionPreference = 'Stop'

function Get-RequiredText([string]$Root, [string]$RelativePath, [ref]$FindingList) {
    $path = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $FindingList.Value += [pscustomobject]@{
            code = 'missing_required_file'
            severity = 'error'
            path = $RelativePath
            message = ('Missing required planning file: {0}' -f $RelativePath)
        }
        return $null
    }
    return [System.IO.File]::ReadAllText($path)
}

function Add-PlanningFinding([ref]$FindingList, [string]$Code, [string]$Path, [string]$Message) {
    $FindingList.Value += [pscustomobject]@{
        code = $Code
        severity = 'error'
        path = $Path
        message = $Message
    }
}

function Test-ContainsLiteral([string]$Text, [string]$Literal) {
    return (-not [string]::IsNullOrWhiteSpace($Text) -and $Text.IndexOf($Literal, [System.StringComparison]::Ordinal) -ge 0)
}

function Get-LiteralCount([string]$Text, [string]$Literal) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return 0 }
    return [regex]::Matches($Text, [regex]::Escape($Literal)).Count
}

function Test-TaskDependencyCycles($TasksById, [string]$CurrentManifestPath, [ref]$FindingList) {
    $state = @{}

    function Visit-PlanningTask([string]$TaskId, [string[]]$Stack) {
        if ($state.ContainsKey($TaskId)) {
            if ($state[$TaskId] -eq 'visiting') {
                Add-PlanningFinding $FindingList 'task_dependency_cycle' $CurrentManifestPath `
                    ('Dependency cycle detected: {0}' -f ((@($Stack) + $TaskId) -join ' -> '))
            }
            return
        }

        $state[$TaskId] = 'visiting'
        $task = $TasksById[$TaskId]
        foreach ($dependencyId in @($task.depends_on)) {
            $dependencyText = [string]$dependencyId
            if ($TasksById.ContainsKey($dependencyText)) {
                Visit-PlanningTask $dependencyText (@($Stack) + $TaskId)
            }
        }
        $state[$TaskId] = 'visited'
    }

    foreach ($taskId in @($TasksById.Keys)) {
        Visit-PlanningTask ([string]$taskId) @()
    }
}

$root = [System.IO.Path]::GetFullPath($RepoRoot)
$findings = @()

$planRelativePath = 'tasks/plan.md'
$planText = Get-RequiredText $root $planRelativePath ([ref]$findings)
$planPhase = $null
if (-not [string]::IsNullOrWhiteSpace($planText) -and $planText -match '\*\*current_phase\*\*:\s*`?(P[0-9]+)`?') {
    $planPhase = [string]$Matches[1]
}
else {
    Add-PlanningFinding ([ref]$findings) 'missing_current_phase' $planRelativePath 'Plan must declare **current_phase**: Pn.'
}

$explicitHistoricalMode = (-not [string]::IsNullOrWhiteSpace($ManifestPath) -or -not [string]::IsNullOrWhiteSpace($SpecPath))
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $phaseNumber = if ($planPhase -match '^P([0-9]+)$') { [string]$Matches[1] } else { '' }
    $ManifestPath = 'tasks/skills-manager-vnext-phase{0}.tasks.json' -f $phaseNumber
}
if ([string]::IsNullOrWhiteSpace($SpecPath)) {
    $phaseNumber = if ($planPhase -match '^P([0-9]+)$') { [string]$Matches[1] } else { '' }
    $specCandidates = @(Get-ChildItem -LiteralPath (Join-Path $root 'docs/superpowers/specs') -Filter ('*-phase-{0}-design.md' -f $phaseNumber) -File -ErrorAction SilentlyContinue)
    if ($specCandidates.Count -eq 1) {
        $SpecPath = $specCandidates[0].FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
    }
    elseif ($specCandidates.Count -eq 0) {
        $SpecPath = 'docs/superpowers/specs/missing-current-phase-spec.md'
    }
    else {
        Add-PlanningFinding ([ref]$findings) 'ambiguous_current_phase_spec' 'docs/superpowers/specs' ('Multiple specs found for {0}; pass -SpecPath explicitly.' -f $planPhase)
        $SpecPath = $specCandidates[0].FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
    }
}

$ManifestPath = $ManifestPath.Replace('\', '/')
$SpecPath = $SpecPath.Replace('\', '/')

$paths = [ordered]@{
    index = 'docs/product/README.md'
    prd = 'docs/product/skills-manager-vnext-prd.md'
    architecture = 'docs/product/skills-manager-vnext-architecture.md'
    roadmap = 'docs/product/skills-manager-vnext-roadmap.md'
    spec = $SpecPath
    manifest = $ManifestPath
    plan = $planRelativePath
    todo = 'tasks/todo.md'
    readme = 'README.md'
    agents = 'AGENTS.md'
}

$content = @{ plan = $planText }
foreach ($key in @($paths.Keys)) {
    if ($key -eq 'plan') { continue }
    $content[$key] = Get-RequiredText $root $paths[$key] ([ref]$findings)
}

$requiredMarkers = [ordered]@{
    index = @('## 2. 文档职责', '## 4. 状态词汇', 'planning verifier')
    prd = @('## 6. 功能需求', '## 7. 非功能需求', '## 8. 产品级验收', 'implementation_status', 'common | platform_delta | project_action')
    architecture = @('## 3. Bounded contexts', '## 5. OperationPlan contract', '## 10. 技术栈决策', '## 14. 反过度设计守卫', 'RuleResponsibility')
    roadmap = @('## 3. P0 Foundation and contracts', '## 4. P1 Read-only inventory and rule advisor', '## 7. P4 Unified capability selection and activation planning', '## 8. P5 Adaptive Capability Fabric')
    spec = @('## 3. Phase boundary', '## 10. Task design', '## 12. Ordered verification', '## 14. Done definition')
}

$adoptionMatrixPath = Join-Path $root 'docs\product\rule-governance-adoption-matrix.md'
if (-not (Test-Path -LiteralPath $adoptionMatrixPath -PathType Leaf)) {
    Add-PlanningFinding ([ref]$findings) 'missing_required_file' 'docs/product/rule-governance-adoption-matrix.md' 'Missing rule-governance adoption matrix.'
}

foreach ($key in @($requiredMarkers.Keys)) {
    foreach ($marker in @($requiredMarkers[$key])) {
        if (-not (Test-ContainsLiteral $content[$key] $marker)) {
            Add-PlanningFinding ([ref]$findings) 'missing_required_marker' $paths[$key] ('Missing required marker: {0}' -f $marker)
        }
    }
}

$manifest = $null
if (-not [string]::IsNullOrWhiteSpace($content['manifest'])) {
    try {
        $manifest = $content['manifest'] | ConvertFrom-Json
    }
    catch {
        Add-PlanningFinding ([ref]$findings) 'manifest_parse_failed' $paths['manifest'] $_.Exception.Message
    }
}

$tasksById = @{}
$taskCount = 0
$doneCount = 0
$pendingCount = 0

if ($null -ne $manifest) {
    if ([int]$manifest.schema_version -ne 1) {
        Add-PlanningFinding ([ref]$findings) 'unsupported_manifest_schema' $paths['manifest'] 'schema_version must be 1.'
    }
    if ([string]$manifest.program_id -ne 'skills-manager-vnext') {
        Add-PlanningFinding ([ref]$findings) 'unexpected_program_id' $paths['manifest'] 'program_id must be skills-manager-vnext.'
    }

    $phaseSequence = @($manifest.phase_sequence | ForEach-Object { [string]$_ })
    $allowedStatuses = @($manifest.allowed_statuses | ForEach-Object { [string]$_ })
    $allowedRisks = @('low', 'medium', 'high')
    $requiredArrayFields = @(
        'requirement_ids',
        'architecture_decision_ids',
        'preconditions',
        'write_set',
        'implementation_steps',
        'tests',
        'verification',
        'rollback',
        'done_when',
        'out_of_scope'
    )

    if ($phaseSequence -notcontains [string]$manifest.current_phase) {
        Add-PlanningFinding ([ref]$findings) 'current_phase_not_declared' $paths['manifest'] 'current_phase must appear in phase_sequence.'
    }

    foreach ($task in @($manifest.tasks)) {
        $taskCount++
        $taskId = [string]$task.id
        $taskPath = ('{0}#{1}' -f $paths['manifest'], $taskId)

        if ([string]::IsNullOrWhiteSpace($taskId) -or $taskId -notmatch '^SMV-P[0-9]+-[0-9]{3}$') {
            Add-PlanningFinding ([ref]$findings) 'invalid_task_id' $taskPath ('Invalid task id: {0}' -f $taskId)
            continue
        }
        if ($tasksById.ContainsKey($taskId)) {
            Add-PlanningFinding ([ref]$findings) 'duplicate_task_id' $taskPath ('Duplicate task id: {0}' -f $taskId)
            continue
        }
        $tasksById[$taskId] = $task

        $phase = [string]$task.phase
        $status = [string]$task.status
        $risk = [string]$task.risk
        if ($phaseSequence -notcontains $phase) {
            Add-PlanningFinding ([ref]$findings) 'unknown_task_phase' $taskPath ('Unknown phase: {0}' -f $phase)
        }
        elseif ($taskId -notmatch ('^SMV-' + [regex]::Escape($phase) + '-')) {
            Add-PlanningFinding ([ref]$findings) 'task_phase_id_mismatch' $taskPath ('Task id does not match phase {0}.' -f $phase)
        }
        if ($allowedStatuses -notcontains $status) {
            Add-PlanningFinding ([ref]$findings) 'unknown_task_status' $taskPath ('Unknown status: {0}' -f $status)
        }
        if ($allowedRisks -notcontains $risk) {
            Add-PlanningFinding ([ref]$findings) 'unknown_task_risk' $taskPath ('Unknown risk: {0}' -f $risk)
        }
        if ($status -eq 'done') { $doneCount++ } else { $pendingCount++ }
        if ([string]::IsNullOrWhiteSpace([string]$task.title) -or [string]::IsNullOrWhiteSpace([string]$task.goal)) {
            Add-PlanningFinding ([ref]$findings) 'missing_task_summary' $taskPath 'Task title and goal are required.'
        }

        foreach ($field in $requiredArrayFields) {
            if (@($task.$field).Count -eq 0) {
                Add-PlanningFinding ([ref]$findings) 'missing_task_field_values' $taskPath ('Task field must be non-empty: {0}' -f $field)
            }
        }

        foreach ($writePath in @($task.write_set | ForEach-Object { [string]$_ })) {
            $normalized = $writePath.Replace('\', '/').TrimStart('./')
            if ($normalized -match '^(agent|vendor|reports/skill-audit)(/|$)') {
                Add-PlanningFinding ([ref]$findings) 'forbidden_task_write_set' $taskPath ('Generated/cache/runtime path is forbidden in write_set: {0}' -f $writePath)
            }
        }
    }

    foreach ($taskId in @($tasksById.Keys)) {
        $task = $tasksById[$taskId]
        foreach ($dependency in @($task.depends_on)) {
            $dependencyId = [string]$dependency
            if ($dependencyId -eq $taskId) {
                Add-PlanningFinding ([ref]$findings) 'self_task_dependency' $paths['manifest'] ('Task {0} depends on itself.' -f $taskId)
            }
            elseif (-not $tasksById.ContainsKey($dependencyId)) {
                Add-PlanningFinding ([ref]$findings) 'unknown_task_dependency' $paths['manifest'] ('Task {0} has unknown dependency {1}.' -f $taskId, $dependencyId)
            }
            elseif ([string]$task.status -eq 'done' -and [string]$tasksById[$dependencyId].status -ne 'done') {
                Add-PlanningFinding ([ref]$findings) 'done_task_dependency_not_done' $paths['manifest'] ('Done task {0} depends on non-done task {1}.' -f $taskId, $dependencyId)
            }
        }

        foreach ($requirementId in @($task.requirement_ids | ForEach-Object { [string]$_ })) {
            if (-not (Test-ContainsLiteral $content['prd'] $requirementId)) {
                Add-PlanningFinding ([ref]$findings) 'unknown_requirement_reference' $paths['manifest'] ('Task {0} references requirement missing from PRD: {1}' -f $taskId, $requirementId)
            }
        }
        foreach ($decisionId in @($task.architecture_decision_ids | ForEach-Object { [string]$_ })) {
            if (-not (Test-ContainsLiteral $content['architecture'] $decisionId)) {
                Add-PlanningFinding ([ref]$findings) 'unknown_architecture_decision_reference' $paths['manifest'] ('Task {0} references decision missing from architecture: {1}' -f $taskId, $decisionId)
            }
        }

        if ((Get-LiteralCount $content['spec'] $taskId) -lt 1) {
            Add-PlanningFinding ([ref]$findings) 'task_missing_from_spec' $paths['spec'] ('Task missing from current phase spec: {0}' -f $taskId)
        }
        if (-not $explicitHistoricalMode) {
            if ((Get-LiteralCount $content['plan'] $taskId) -ne 1) {
                Add-PlanningFinding ([ref]$findings) 'task_plan_coverage_mismatch' $paths['plan'] ('Task must appear exactly once in plan: {0}' -f $taskId)
            }
            if ((Get-LiteralCount $content['todo'] $taskId) -ne 1) {
                Add-PlanningFinding ([ref]$findings) 'task_todo_coverage_mismatch' $paths['todo'] ('Task must appear exactly once in todo: {0}' -f $taskId)
            }
            else {
                $todoLine = @($content['todo'] -split "`r?`n" | Where-Object { Test-ContainsLiteral $_ $taskId })[0]
                $todoDone = $todoLine -match '^\s*-\s+\[[xX]\]'
                $manifestDone = ([string]$task.status -eq 'done')
                if ($todoDone -ne $manifestDone) {
                    Add-PlanningFinding ([ref]$findings) 'task_todo_status_mismatch' $paths['todo'] `
                        ('Task {0} status is {1}, but todo marker is {2}.' -f $taskId, [string]$task.status, $(if ($todoDone) { 'done' } else { 'open' }))
                }
            }
        }

        if ([string]$task.status -eq 'done') {
            $verificationText = @($task.verification | ForEach-Object { [string]$_ }) -join "`n"
            $hasStandaloneSuite = $verificationText -match '(?i)(^|[\\/\s])tests/run\.ps1(?:\s|$)'
            $hasFullGate = $verificationText -match '(?i)run-local-quality-gates\.ps1[^\r\n]*-Profile\s+full'
            if (-not $explicitHistoricalMode -and $hasStandaloneSuite -and $hasFullGate) {
                Add-PlanningFinding ([ref]$findings) 'redundant_full_test_invocation' $taskPath `
                    'Verification must not invoke tests/run.ps1 separately when the full quality gate already invokes the full suite.'
            }
            $exactEvidencePaths = @($task.write_set | ForEach-Object { [string]$_ } | Where-Object {
                $normalized = $_.Replace('\', '/')
                $normalized.StartsWith('docs/change-evidence/', [System.StringComparison]::OrdinalIgnoreCase) -and
                    $normalized.IndexOfAny([char[]]'<>*?') -lt 0
            })
            if ($exactEvidencePaths.Count -eq 0) {
                Add-PlanningFinding ([ref]$findings) 'done_task_missing_evidence_path' $taskPath `
                    ('Done task must declare an exact change-evidence path: {0}' -f $taskId)
            }
            foreach ($evidencePath in $exactEvidencePaths) {
                $fullEvidencePath = Join-Path $root $evidencePath
                if (-not (Test-Path -LiteralPath $fullEvidencePath -PathType Leaf)) {
                    Add-PlanningFinding ([ref]$findings) 'done_task_evidence_missing' $evidencePath `
                        ('Done task evidence file is missing: {0}' -f $taskId)
                }
            }
        }
    }

    Test-TaskDependencyCycles $tasksById $paths['manifest'] ([ref]$findings)

    foreach ($phase in $phaseSequence) {
        if (-not (Test-ContainsLiteral $content['roadmap'] $phase)) {
            Add-PlanningFinding ([ref]$findings) 'phase_missing_from_roadmap' $paths['roadmap'] ('Phase missing from roadmap: {0}' -f $phase)
        }
    }
}

if ($null -ne $manifest -and -not $explicitHistoricalMode -and $planPhase -ne [string]$manifest.current_phase) {
    Add-PlanningFinding ([ref]$findings) 'plan_manifest_phase_mismatch' $paths['plan'] `
        ('Plan current_phase {0} does not match manifest current_phase {1}.' -f $planPhase, [string]$manifest.current_phase)
}

if (-not (Test-ContainsLiteral $content['readme'] 'docs/product/README.md')) {
    Add-PlanningFinding ([ref]$findings) 'readme_missing_product_docs_link' $paths['readme'] 'README must link to docs/product/README.md.'
}
if (-not (Test-ContainsLiteral $content['agents'] 'verify-vnext-planning.ps1')) {
    Add-PlanningFinding ([ref]$findings) 'agents_missing_planning_gate' $paths['agents'] 'AGENTS.md must include the planning verifier in contract/invariant gates.'
}

$result = [ordered]@{
    schema_version = 1
    program_id = 'skills-manager-vnext'
    current_phase = if ($null -ne $manifest) { [string]$manifest.current_phase } else { $planPhase }
    historical_mode = $explicitHistoricalMode
    pass = ($findings.Count -eq 0)
    task_count = $taskCount
    done_count = $doneCount
    open_count = $pendingCount
    finding_count = $findings.Count
    findings = @($findings)
}

if ($Json) {
    Write-Output ($result | ConvertTo-Json -Depth 8)
}
else {
    foreach ($finding in $findings) {
        Write-Host ('[{0}] {1}: {2}' -f $finding.code, $finding.path, $finding.message) -ForegroundColor Red
    }
    if ($result.pass) {
        Write-Host ('vNext planning contract passed: tasks={0}, done={1}, open={2}' -f $taskCount, $doneCount, $pendingCount) -ForegroundColor Green
    }
    else {
        Write-Host ('vNext planning contract failed: findings={0}' -f $findings.Count) -ForegroundColor Red
    }
}

$exitCode = if ($result.pass) { 0 } else { 2 }
if ($NoExit) { $global:LASTEXITCODE = $exitCode; return }
exit $exitCode
