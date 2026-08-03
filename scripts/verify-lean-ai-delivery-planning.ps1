[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [switch]$Json,
    [switch]$NoExit
)

$ErrorActionPreference = 'Stop'

function Add-LeanPlanningFinding([ref]$FindingList, [string]$Code, [string]$Path, [string]$Message) {
    $FindingList.Value += [pscustomobject]@{
        code = $Code
        severity = 'error'
        path = $Path
        message = $Message
    }
}

function Get-LeanRequiredText([string]$Root, [string]$RelativePath, [ref]$FindingList) {
    $fullPath = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        Add-LeanPlanningFinding $FindingList 'missing_required_file' $RelativePath `
            ('Missing required maintenance planning file: {0}' -f $RelativePath)
        return $null
    }
    return [System.IO.File]::ReadAllText($fullPath)
}

function Test-LeanContainsLiteral([string]$Text, [string]$Literal) {
    return (-not [string]::IsNullOrWhiteSpace($Text) -and
        $Text.IndexOf($Literal, [System.StringComparison]::Ordinal) -ge 0)
}

function Get-LeanLiteralCount([string]$Text, [string]$Literal) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return 0 }
    return [regex]::Matches($Text, [regex]::Escape($Literal)).Count
}

function Test-LeanTaskDependencyCycles($TasksById, [string]$ManifestPath, [ref]$FindingList) {
    $state = @{}

    function Visit-LeanTask([string]$TaskId, [string[]]$Stack) {
        if ($state.ContainsKey($TaskId)) {
            if ($state[$TaskId] -eq 'visiting') {
                Add-LeanPlanningFinding $FindingList 'task_dependency_cycle' $ManifestPath `
                    ('Dependency cycle detected: {0}' -f ((@($Stack) + $TaskId) -join ' -> '))
            }
            return
        }

        $state[$TaskId] = 'visiting'
        $task = $TasksById[$TaskId]
        foreach ($dependency in @($task.depends_on)) {
            $dependencyId = [string]$dependency
            if ($TasksById.ContainsKey($dependencyId)) {
                Visit-LeanTask $dependencyId (@($Stack) + $TaskId)
            }
        }
        $state[$TaskId] = 'visited'
    }

    foreach ($taskId in @($TasksById.Keys)) {
        Visit-LeanTask ([string]$taskId) @()
    }
}

function Test-LeanForbiddenWritePath([string]$WritePath) {
    $normalized = $WritePath.Replace('\', '/').Trim()
    while ($normalized.StartsWith('./', [System.StringComparison]::Ordinal)) {
        $normalized = $normalized.Substring(2)
    }

    if ($normalized -match '^(?i)(agent|vendor|reports|src|overrides)(/|$)') { return $true }
    if ($normalized -match '^(?i)skills\.json$') { return $true }
    if ($normalized -match '^(?i)config/skills[^/]*\.json$') { return $true }
    if ($normalized -match '^(?i)(\.codex|\.claude|~)(/|$)') { return $true }
    if ($normalized -match '^(?i)[A-Z]:/' -or $normalized.StartsWith('/')) { return $true }
    return $false
}

$root = [System.IO.Path]::GetFullPath($RepoRoot)
$findings = @()
$paths = [ordered]@{
    index = 'docs/product/README.md'
    prd = 'docs/product/skills-manager-vnext-prd.md'
    architecture = 'docs/product/skills-manager-vnext-architecture.md'
    roadmap = 'docs/product/skills-manager-vnext-roadmap.md'
    spec = 'docs/superpowers/specs/2026-08-03-lean-ai-delivery-maintenance-design.md'
    manifest = 'tasks/skills-manager-vnext-maintenance-design.tasks.json'
    plan = 'tasks/plan.md'
    todo = 'tasks/todo.md'
    agents = 'AGENTS.md'
    evidence = 'docs/change-evidence/20260803-lean-ai-delivery-maintenance-design.md'
}

$content = @{}
foreach ($key in @($paths.Keys)) {
    $content[$key] = Get-LeanRequiredText $root $paths[$key] ([ref]$findings)
}

$baseVerifierRelativePath = 'scripts/verify-vnext-planning.ps1'
$baseVerifierPath = Join-Path $root $baseVerifierRelativePath
if (-not (Test-Path -LiteralPath $baseVerifierPath -PathType Leaf)) {
    Add-LeanPlanningFinding ([ref]$findings) 'base_p5_planning_verifier_missing' $baseVerifierRelativePath `
        'The existing P5 planning verifier must exist and pass before the maintenance track is evaluated.'
}
else {
    try {
        $baseOutput = @(& $baseVerifierPath -RepoRoot $root -Json -NoExit 2>&1)
        $baseExitCode = $global:LASTEXITCODE
        $baseResult = ($baseOutput -join "`n") | ConvertFrom-Json
        if ($baseExitCode -ne 0 -or -not [bool]$baseResult.pass) {
            Add-LeanPlanningFinding ([ref]$findings) 'base_p5_planning_failed' $baseVerifierRelativePath `
                ('Existing P5 planning contract failed: exit={0}, findings={1}.' -f $baseExitCode, [int]$baseResult.finding_count)
        }
    }
    catch {
        Add-LeanPlanningFinding ([ref]$findings) 'base_p5_planning_invalid_output' $baseVerifierRelativePath $_.Exception.Message
    }
}

$manifest = $null
if (-not [string]::IsNullOrWhiteSpace($content['manifest'])) {
    try {
        $manifest = $content['manifest'] | ConvertFrom-Json
    }
    catch {
        Add-LeanPlanningFinding ([ref]$findings) 'manifest_parse_failed' $paths['manifest'] $_.Exception.Message
    }
}

$taskCount = 0
$doneCount = 0
$openCount = 0
$tasksById = @{}
$doneEvidenceSets = @()

if ($null -ne $manifest) {
    if ([int]$manifest.schema_version -ne 1) {
        Add-LeanPlanningFinding ([ref]$findings) 'unsupported_manifest_schema' $paths['manifest'] 'schema_version must be 1.'
    }
    if ([string]$manifest.program_id -ne 'skills-manager-vnext') {
        Add-LeanPlanningFinding ([ref]$findings) 'unexpected_program_id' $paths['manifest'] 'program_id must be skills-manager-vnext.'
    }
    if ([string]$manifest.track -ne 'maintenance_design') {
        Add-LeanPlanningFinding ([ref]$findings) 'unexpected_track' $paths['manifest'] 'track must be maintenance_design.'
    }
    if ([string]$manifest.base_phase -ne 'P5') {
        Add-LeanPlanningFinding ([ref]$findings) 'unexpected_base_phase' $paths['manifest'] 'base_phase must remain P5.'
    }
    if ([string]$manifest.p6_admission_status -ne 'hold') {
        Add-LeanPlanningFinding ([ref]$findings) 'unexpected_p6_admission_status' $paths['manifest'] 'p6_admission_status must remain hold.'
    }

    $allowedStatuses = @('pending', 'in_progress', 'blocked', 'deferred', 'done')
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

    foreach ($task in @($manifest.tasks)) {
        $taskCount++
        $taskId = [string]$task.id
        $taskPath = ('{0}#{1}' -f $paths['manifest'], $taskId)

        if ([string]::IsNullOrWhiteSpace($taskId) -or $taskId -notmatch '^SMV-MD-[0-9]{3}$') {
            Add-LeanPlanningFinding ([ref]$findings) 'invalid_task_id' $taskPath ('Invalid maintenance task id: {0}' -f $taskId)
            continue
        }
        if ($tasksById.ContainsKey($taskId)) {
            Add-LeanPlanningFinding ([ref]$findings) 'duplicate_task_id' $taskPath ('Duplicate maintenance task id: {0}' -f $taskId)
            continue
        }
        $tasksById[$taskId] = $task

        $status = [string]$task.status
        $risk = [string]$task.risk
        if ($allowedStatuses -notcontains $status) {
            Add-LeanPlanningFinding ([ref]$findings) 'unknown_task_status' $taskPath ('Unknown status: {0}' -f $status)
        }
        if ($allowedRisks -notcontains $risk) {
            Add-LeanPlanningFinding ([ref]$findings) 'unknown_task_risk' $taskPath ('Unknown risk: {0}' -f $risk)
        }
        if ($status -eq 'done') { $doneCount++ } else { $openCount++ }
        if ([string]::IsNullOrWhiteSpace([string]$task.title) -or [string]::IsNullOrWhiteSpace([string]$task.goal)) {
            Add-LeanPlanningFinding ([ref]$findings) 'missing_task_summary' $taskPath 'Task title and goal are required.'
        }

        foreach ($field in $requiredArrayFields) {
            if (@($task.$field).Count -eq 0) {
                Add-LeanPlanningFinding ([ref]$findings) 'missing_task_field_values' $taskPath `
                    ('Task field must be non-empty: {0}' -f $field)
            }
        }

        foreach ($writePath in @($task.write_set | ForEach-Object { [string]$_ })) {
            if (Test-LeanForbiddenWritePath $writePath) {
                Add-LeanPlanningFinding ([ref]$findings) 'forbidden_maintenance_write_set' $taskPath `
                    ('Runtime/generated/cache/host path is forbidden in maintenance write_set: {0}' -f $writePath)
            }
        }

        if ($status -eq 'done') {
            $exactEvidencePaths = @($task.write_set | ForEach-Object { [string]$_ } | Where-Object {
                $normalized = $_.Replace('\', '/')
                $normalized.StartsWith('docs/change-evidence/', [System.StringComparison]::OrdinalIgnoreCase) -and
                    $normalized.IndexOfAny([char[]]'<>*?') -lt 0
            } | ForEach-Object { $_.Replace('\', '/') } | Sort-Object -Unique)
            if ($exactEvidencePaths.Count -eq 0) {
                Add-LeanPlanningFinding ([ref]$findings) 'done_task_missing_evidence_path' $taskPath `
                    'Every done maintenance task must declare an exact reviewed evidence path.'
            }
            $doneEvidenceSets += ,$exactEvidencePaths

            $verificationText = @($task.verification | ForEach-Object { [string]$_ }) -join "`n"
            $hasStandaloneSuite = $verificationText -match '(?i)(^|[\\/\s])tests/run\.ps1(?:\s|$)'
            $hasFullGate = $verificationText -match '(?i)run-local-quality-gates\.ps1[^\r\n]*-Profile\s+full'
            if ($hasStandaloneSuite -and $hasFullGate) {
                Add-LeanPlanningFinding ([ref]$findings) 'redundant_full_test_invocation' $taskPath `
                    'Do not invoke the standalone full suite when the full quality gate already owns it.'
            }
        }
    }

    foreach ($taskId in @($tasksById.Keys)) {
        $task = $tasksById[$taskId]
        foreach ($dependency in @($task.depends_on)) {
            $dependencyId = [string]$dependency
            if ($dependencyId -eq $taskId) {
                Add-LeanPlanningFinding ([ref]$findings) 'self_task_dependency' $paths['manifest'] `
                    ('Task {0} depends on itself.' -f $taskId)
            }
            elseif (-not $tasksById.ContainsKey($dependencyId)) {
                Add-LeanPlanningFinding ([ref]$findings) 'unknown_task_dependency' $paths['manifest'] `
                    ('Task {0} has unknown dependency {1}.' -f $taskId, $dependencyId)
            }
            elseif ([string]$task.status -eq 'done' -and [string]$tasksById[$dependencyId].status -ne 'done') {
                Add-LeanPlanningFinding ([ref]$findings) 'done_task_dependency_not_done' $paths['manifest'] `
                    ('Done task {0} depends on non-done task {1}.' -f $taskId, $dependencyId)
            }
        }

        foreach ($requirementId in @($task.requirement_ids | ForEach-Object { [string]$_ })) {
            if (-not (Test-LeanContainsLiteral $content['prd'] $requirementId)) {
                Add-LeanPlanningFinding ([ref]$findings) 'unknown_requirement_reference' $paths['manifest'] `
                    ('Task {0} references requirement missing from PRD: {1}' -f $taskId, $requirementId)
            }
        }
        foreach ($decisionId in @($task.architecture_decision_ids | ForEach-Object { [string]$_ })) {
            if (-not (Test-LeanContainsLiteral $content['architecture'] $decisionId)) {
                Add-LeanPlanningFinding ([ref]$findings) 'unknown_architecture_decision_reference' $paths['manifest'] `
                    ('Task {0} references decision missing from architecture: {1}' -f $taskId, $decisionId)
            }
        }

        foreach ($coverageKey in @('spec', 'plan', 'todo')) {
            if ((Get-LeanLiteralCount $content[$coverageKey] $taskId) -ne 1) {
                Add-LeanPlanningFinding ([ref]$findings) ('task_{0}_coverage_mismatch' -f $coverageKey) $paths[$coverageKey] `
                    ('Task must appear exactly once in {0}: {1}' -f $coverageKey, $taskId)
            }
        }

        if ((Get-LeanLiteralCount $content['todo'] $taskId) -eq 1) {
            $todoLine = @($content['todo'] -split "`r?`n" | Where-Object { Test-LeanContainsLiteral $_ $taskId })[0]
            $todoDone = $todoLine -match '^\s*-\s+\[[xX]\]'
            $manifestDone = ([string]$task.status -eq 'done')
            if ($todoDone -ne $manifestDone) {
                Add-LeanPlanningFinding ([ref]$findings) 'task_todo_status_mismatch' $paths['todo'] `
                    ('Task {0} status is {1}, but todo marker is {2}.' -f $taskId, [string]$task.status, $(if ($todoDone) { 'done' } else { 'open' }))
            }
        }
    }

    Test-LeanTaskDependencyCycles $tasksById $paths['manifest'] ([ref]$findings)

    if ($doneEvidenceSets.Count -gt 0) {
        $sharedEvidence = @($doneEvidenceSets[0])
        foreach ($evidenceSet in @($doneEvidenceSets | Select-Object -Skip 1)) {
            $sharedEvidence = @($sharedEvidence | Where-Object { $evidenceSet -contains $_ })
        }
        if ($sharedEvidence.Count -eq 0) {
            Add-LeanPlanningFinding ([ref]$findings) 'done_tasks_missing_shared_evidence' $paths['manifest'] `
                'All done maintenance tasks must share at least one exact reviewed evidence file.'
        }
        else {
            foreach ($evidencePath in $sharedEvidence) {
                if (-not (Test-Path -LiteralPath (Join-Path $root $evidencePath) -PathType Leaf)) {
                    Add-LeanPlanningFinding ([ref]$findings) 'done_task_evidence_missing' $evidencePath `
                        'The shared reviewed evidence file for done maintenance tasks is missing.'
                }
            }
        }
    }
}

if (-not (Test-LeanContainsLiteral $content['spec'] 'P6_ADMISSION_STATUS: hold')) {
    Add-LeanPlanningFinding ([ref]$findings) 'spec_p6_hold_missing' $paths['spec'] 'Spec must keep P6_ADMISSION_STATUS: hold.'
}
if (-not (Test-LeanContainsLiteral $content['spec'] 'PILOT_STATUS: pilot_not_executed')) {
    Add-LeanPlanningFinding ([ref]$findings) 'pilot_status_not_unexecuted' $paths['spec'] 'Spec must explicitly declare pilot_not_executed.'
}
if (-not (Test-LeanContainsLiteral $content['spec'] 'RUNTIME_IMPLEMENTATION_STATUS: no_runtime_implementation')) {
    Add-LeanPlanningFinding ([ref]$findings) 'runtime_implementation_claimed' $paths['spec'] 'Spec must explicitly declare no_runtime_implementation.'
}
if (-not (Test-LeanContainsLiteral $content['spec'] 'LIVE_ACCEPTANCE_STATUS: not_run')) {
    Add-LeanPlanningFinding ([ref]$findings) 'live_acceptance_claimed' $paths['spec'] 'Maintenance design must keep LIVE_ACCEPTANCE_STATUS: not_run.'
}
if (-not (Test-LeanContainsLiteral $content['spec'] 'METRICS_MODE: observe_only') -or
    -not (Test-LeanContainsLiteral $content['spec'] 'METRICS_COMPLETION_GATE: false')) {
    Add-LeanPlanningFinding ([ref]$findings) 'observe_only_metrics_became_gate' $paths['spec'] `
        'Delivery metrics must remain observe_only and must not become a completion gate.'
}
if (-not (Test-LeanContainsLiteral $content['roadmap'] 'P6_ADMISSION_STATUS: hold')) {
    Add-LeanPlanningFinding ([ref]$findings) 'roadmap_p6_hold_missing' $paths['roadmap'] 'Roadmap must keep P6_ADMISSION_STATUS: hold.'
}

$p6ManifestRelativePath = 'tasks/skills-manager-vnext-phase6.tasks.json'
if (Test-Path -LiteralPath (Join-Path $root $p6ManifestRelativePath) -PathType Leaf) {
    Add-LeanPlanningFinding ([ref]$findings) 'p6_manifest_created_while_on_hold' $p6ManifestRelativePath `
        'A P6 manifest is forbidden while admission remains on hold.'
}

$orderedVerification = ''
if (-not [string]::IsNullOrWhiteSpace($content['spec']) -and
    $content['spec'] -match '(?is)## 17\. Verification order(?<section>.*?)(?:\r?\n## 18\.|\z)') {
    $orderedVerification = [string]$Matches['section']
}
$specHasStandaloneSuite = $orderedVerification -match '(?i)tests/run\.ps1'
$specHasFullGate = $orderedVerification -match '(?i)run-local-quality-gates\.ps1[^\r\n]*-Profile\s+full'
if ($specHasStandaloneSuite -and $specHasFullGate) {
    Add-LeanPlanningFinding ([ref]$findings) 'redundant_full_test_spec' $paths['spec'] `
        'Verification order must not declare the standalone full suite in addition to the full quality gate.'
}

$result = [ordered]@{
    schema_version = 1
    program_id = 'skills-manager-vnext'
    track = 'maintenance_design'
    base_phase = 'P5'
    p6_admission_status = 'hold'
    pass = ($findings.Count -eq 0)
    task_count = $taskCount
    done_count = $doneCount
    open_count = $openCount
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
        Write-Host ('Lean AI delivery planning contract passed: tasks={0}, done={1}, open={2}' -f $taskCount, $doneCount, $openCount) -ForegroundColor Green
    }
    else {
        Write-Host ('Lean AI delivery planning contract failed: findings={0}' -f $findings.Count) -ForegroundColor Red
    }
}

$exitCode = if ($result.pass) { 0 } else { 2 }
if ($NoExit) { $global:LASTEXITCODE = $exitCode; return }
exit $exitCode
