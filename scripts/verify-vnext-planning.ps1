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
    p4_entry = 'config/vnext-phase4-entry-gate.json'
}

$content = @{ plan = $planText }
foreach ($key in @($paths.Keys)) {
    if ($key -eq 'plan') { continue }
    $content[$key] = Get-RequiredText $root $paths[$key] ([ref]$findings)
}

$adoptionMatrixPath = Join-Path $root 'docs\product\rule-governance-adoption-matrix.md'
if (-not (Test-Path -LiteralPath $adoptionMatrixPath -PathType Leaf)) {
    Add-PlanningFinding ([ref]$findings) 'missing_required_file' 'docs/product/rule-governance-adoption-matrix.md' 'Missing rule-governance adoption matrix.'
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
$phaseEvidencePaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

if ($null -ne $manifest) {
    if ([int]$manifest.schema_version -ne 1) {
        Add-PlanningFinding ([ref]$findings) 'unsupported_manifest_schema' $paths['manifest'] 'schema_version must be 1.'
    }
    if ([string]$manifest.program_id -ne 'skills-manager-vnext') {
        Add-PlanningFinding ([ref]$findings) 'unexpected_program_id' $paths['manifest'] 'program_id must be skills-manager-vnext.'
    }

    if (-not $explicitHistoricalMode) {
        $requiredTruthFields = @('truth_level', 'full_gate', 'runtime_migration', 'host_evaluation', 'host_loaded', 'live_accepted', 'latest_evidence', 'main_chain', 'stop_conditions', 'first_open_task', 'next_milestone')
        foreach ($field in $requiredTruthFields) {
            if ($manifest.PSObject.Properties.Match($field).Count -eq 0) {
                Add-PlanningFinding ([ref]$findings) 'phase_truth_field_missing' $paths['manifest'] ('Current phase truth field is missing: {0}' -f $field)
            }
        }
        foreach ($contract in @(
                @{ field = 'truth_level'; allowed = @('design_only', 'repo_verified', 'host_evaluation_partial', 'host_loaded', 'live_accepted') },
                @{ field = 'full_gate'; allowed = @('not_run', 'passed', 'failed', 'stale') },
                @{ field = 'runtime_migration'; allowed = @('not_started', 'in_progress', 'completed', 'blocked') },
                @{ field = 'host_evaluation'; allowed = @('not_run', 'host_evaluation_partial', 'passed', 'failed') },
                @{ field = 'host_loaded'; allowed = @('not_run', 'passed', 'failed') },
                @{ field = 'live_accepted'; allowed = @('not_run', 'passed', 'failed') }
            )) {
            if ($manifest.PSObject.Properties.Match([string]$contract.field).Count -gt 0 -and [string]$manifest.($contract.field) -notin @($contract.allowed)) {
                Add-PlanningFinding ([ref]$findings) 'phase_truth_value_invalid' $paths['manifest'] ('Unsupported {0}: {1}' -f $contract.field, [string]$manifest.($contract.field))
            }
        }
        foreach ($field in @('main_chain', 'stop_conditions')) {
            if ($manifest.PSObject.Properties.Match($field).Count -gt 0 -and @($manifest.$field | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -eq 0) {
                Add-PlanningFinding ([ref]$findings) 'phase_truth_array_empty' $paths['manifest'] ('Current phase truth array must not be empty: {0}' -f $field)
            }
        }
        if ($manifest.PSObject.Properties.Match('latest_evidence').Count -gt 0) {
            $latestEvidence = [string]$manifest.latest_evidence
            if ([string]::IsNullOrWhiteSpace($latestEvidence) -or -not (Test-Path -LiteralPath (Join-Path $root $latestEvidence) -PathType Leaf)) {
                Add-PlanningFinding ([ref]$findings) 'phase_truth_evidence_missing' $paths['manifest'] ('latest_evidence does not resolve to a file: {0}' -f $latestEvidence)
            }
        }
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
            foreach ($evidencePath in $exactEvidencePaths) {
                $phaseEvidencePaths.Add($evidencePath.Replace('\', '/')) | Out-Null
                $fullEvidencePath = Join-Path $root $evidencePath
                if (-not (Test-Path -LiteralPath $fullEvidencePath -PathType Leaf)) {
                    Add-PlanningFinding ([ref]$findings) 'done_task_evidence_missing' $evidencePath `
                        ('Done task evidence file is missing: {0}' -f $taskId)
                }
            }
        }
    }

    if ($doneCount -gt 0 -and $phaseEvidencePaths.Count -eq 0) {
        Add-PlanningFinding ([ref]$findings) 'phase_missing_evidence_path' $paths['manifest'] `
            'A phase with done tasks must declare at least one exact logical-slice evidence path.'
    }

    Test-TaskDependencyCycles $tasksById $paths['manifest'] ([ref]$findings)

    if (-not $explicitHistoricalMode -and $manifest.PSObject.Properties.Match('first_open_task').Count -gt 0) {
        $derivedFirstOpen = @($manifest.tasks | Where-Object { [string]$_.status -ne 'done' } | Select-Object -First 1)
        $derivedFirstOpenId = if ($derivedFirstOpen.Count -eq 0) { $null } else { [string]$derivedFirstOpen[0].id }
        $declaredFirstOpenId = if ($null -eq $manifest.first_open_task) { $null } else { [string]$manifest.first_open_task }
        if ($declaredFirstOpenId -ne $derivedFirstOpenId) {
            Add-PlanningFinding ([ref]$findings) 'first_open_task_mismatch' $paths['manifest'] ('first_open_task is {0}; derived value is {1}.' -f $declaredFirstOpenId, $derivedFirstOpenId)
        }
    }

    foreach ($phase in $phaseSequence) {
        if (-not (Test-ContainsLiteral $content['roadmap'] $phase)) {
            Add-PlanningFinding ([ref]$findings) 'phase_missing_from_roadmap' $paths['roadmap'] ('Phase missing from roadmap: {0}' -f $phase)
        }
    }
}

if (-not $explicitHistoricalMode) {
    $currentPhaseNumber = if ($planPhase -match '^P([0-9]+)$') { [int]$Matches[1] } else { -1 }
    if ($currentPhaseNumber -gt 4 -and -not [string]::IsNullOrWhiteSpace($content['p4_entry'])) {
        try {
            $p4Entry = $content['p4_entry'] | ConvertFrom-Json
            if ([string]$p4Entry.status -ne 'completed') {
                Add-PlanningFinding ([ref]$findings) 'historical_phase_not_closed' $paths['p4_entry'] `
                    ('Current phase {0} requires P4 entry lifecycle status completed, found {1}.' -f $planPhase, [string]$p4Entry.status)
            }
        }
        catch { Add-PlanningFinding ([ref]$findings) 'historical_phase_gate_parse_failed' $paths['p4_entry'] $_.Exception.Message }
    }

    $orderedVerification = ''
    if (-not [string]::IsNullOrWhiteSpace($content['spec']) -and $content['spec'] -match '(?is)## 12\. Ordered verification(?<section>.*?)(?:\r?\n## 13\.|\z)') {
        $orderedVerification = [string]$Matches['section']
    }
    $specHasStandaloneSuite = $orderedVerification -match '(?i)tests/run\.ps1'
    $specHasFullGate = $orderedVerification -match '(?i)(run-local-quality-gates\.ps1[^\r\n]*-Profile\s+full|full local quality gate)'
    if ($specHasStandaloneSuite -and $specHasFullGate) {
        Add-PlanningFinding ([ref]$findings) 'redundant_full_test_spec' $paths['spec'] `
            'Ordered verification must run affected tests during iteration and the full suite exactly once through the full quality gate.'
    }

    $p6ManifestPath = Join-Path $root 'tasks\skills-manager-vnext-phase6.tasks.json'
    if ((Test-ContainsLiteral $content['roadmap'] 'P6_ADMISSION_STATUS: hold') -and (Test-Path -LiteralPath $p6ManifestPath -PathType Leaf)) {
        Add-PlanningFinding ([ref]$findings) 'next_phase_started_while_on_hold' 'tasks/skills-manager-vnext-phase6.tasks.json' `
            'P6 is on maintenance hold; admission evidence and an explicit roadmap status transition are required before creating a P6 manifest.'
    }
}

if ($null -ne $manifest -and -not $explicitHistoricalMode -and $planPhase -ne [string]$manifest.current_phase) {
    Add-PlanningFinding ([ref]$findings) 'plan_manifest_phase_mismatch' $paths['plan'] `
        ('Plan current_phase {0} does not match manifest current_phase {1}.' -f $planPhase, [string]$manifest.current_phase)
}

$result = [ordered]@{
    schema_version = 1
    program_id = 'skills-manager-vnext'
    current_phase = if ($null -ne $manifest) { [string]$manifest.current_phase } else { $planPhase }
    historical_mode = $explicitHistoricalMode
    truth_level = if ($null -ne $manifest -and -not $explicitHistoricalMode) { [string]$manifest.truth_level } else { 'historical' }
    full_gate = if ($null -ne $manifest -and -not $explicitHistoricalMode) { [string]$manifest.full_gate } else { 'not_applicable' }
    runtime_migration = if ($null -ne $manifest -and -not $explicitHistoricalMode) { [string]$manifest.runtime_migration } else { 'not_applicable' }
    host_evaluation = if ($null -ne $manifest -and -not $explicitHistoricalMode) { [string]$manifest.host_evaluation } else { 'not_applicable' }
    host_loaded = if ($null -ne $manifest -and -not $explicitHistoricalMode) { [string]$manifest.host_loaded } else { 'not_applicable' }
    live_accepted = if ($null -ne $manifest -and -not $explicitHistoricalMode) { [string]$manifest.live_accepted } else { 'not_applicable' }
    pass = ($findings.Count -eq 0)
    task_count = $taskCount
    done_count = $doneCount
    open_count = $pendingCount
    evidence_count = $phaseEvidencePaths.Count
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
