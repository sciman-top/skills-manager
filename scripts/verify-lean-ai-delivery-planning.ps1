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

function Test-LeanObjectProperty($Object, [string]$Name) {
    return ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name])
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
    pilot = 'tasks/skills-manager-vnext-lean-delivery-pilot.json'
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
$doneEvidenceSetsByGroup = @{}
$pilotRegistry = $null
$pilotStatus = 'unknown'
$pilotSampleTarget = 0
$pilotSampleCount = 0
$countedPilotSamples = @()
$pilotCategoriesCovered = @()

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
        $evidenceGroup = [string]$task.evidence_group
        if ($allowedStatuses -notcontains $status) {
            Add-LeanPlanningFinding ([ref]$findings) 'unknown_task_status' $taskPath ('Unknown status: {0}' -f $status)
        }
        if ($allowedRisks -notcontains $risk) {
            Add-LeanPlanningFinding ([ref]$findings) 'unknown_task_risk' $taskPath ('Unknown risk: {0}' -f $risk)
        }
        if ([string]::IsNullOrWhiteSpace($evidenceGroup) -or $evidenceGroup -notmatch '^[a-z0-9][a-z0-9_-]*$') {
            Add-LeanPlanningFinding ([ref]$findings) 'invalid_task_evidence_group' $taskPath `
                ('Task evidence_group is required and must be a stable lowercase identifier: {0}' -f $evidenceGroup)
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
            if (-not [string]::IsNullOrWhiteSpace($evidenceGroup)) {
                if (-not $doneEvidenceSetsByGroup.ContainsKey($evidenceGroup)) {
                    $doneEvidenceSetsByGroup[$evidenceGroup] = @()
                }
                $doneEvidenceSetsByGroup[$evidenceGroup] += ,$exactEvidencePaths
            }

            $verificationText = @($task.verification | ForEach-Object { [string]$_ }) -join "`n"
            $hasStandaloneSuite = $verificationText -match '(?i)(^|[\\/\s])tests/run\.ps1(?:\s|$)'
            $hasFullGate = $verificationText -match '(?i)run-local-quality-gates\.ps1[^\r\n]*-Profile\s+full'
            if ($hasStandaloneSuite -and $hasFullGate) {
                Add-LeanPlanningFinding ([ref]$findings) 'redundant_full_test_invocation' $taskPath `
                    'Do not invoke the standalone full suite when the full quality gate already owns it.'
            }
        }
    }

    foreach ($expectedTaskId in @(1..11 | ForEach-Object { 'SMV-MD-{0:d3}' -f $_ })) {
        if (-not $tasksById.ContainsKey($expectedTaskId)) {
            Add-LeanPlanningFinding ([ref]$findings) 'missing_required_maintenance_task' $paths['manifest'] `
                ('Required M0/M0.2/M0.3 maintenance task is missing: {0}' -f $expectedTaskId)
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

    foreach ($evidenceGroup in @($doneEvidenceSetsByGroup.Keys | Sort-Object)) {
        $groupEvidenceSets = @($doneEvidenceSetsByGroup[$evidenceGroup])
        if ($groupEvidenceSets.Count -gt 0) {
            $sharedEvidence = @($groupEvidenceSets[0])
            foreach ($evidenceSet in @($groupEvidenceSets | Select-Object -Skip 1)) {
                $sharedEvidence = @($sharedEvidence | Where-Object { $evidenceSet -contains $_ })
            }
            if ($sharedEvidence.Count -eq 0) {
                Add-LeanPlanningFinding ([ref]$findings) 'done_tasks_missing_shared_evidence' $paths['manifest'] `
                    ('Done maintenance tasks in evidence_group {0} must share at least one exact reviewed evidence file.' -f $evidenceGroup)
            }
            else {
                foreach ($evidencePath in $sharedEvidence) {
                    if (-not (Test-Path -LiteralPath (Join-Path $root $evidencePath) -PathType Leaf)) {
                        Add-LeanPlanningFinding ([ref]$findings) 'done_task_evidence_missing' $evidencePath `
                            ('The shared reviewed evidence file for evidence_group {0} is missing.' -f $evidenceGroup)
                    }
                }
            }
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($content['pilot'])) {
    try {
        $pilotRegistry = $content['pilot'] | ConvertFrom-Json
    }
    catch {
        Add-LeanPlanningFinding ([ref]$findings) 'pilot_registry_parse_failed' $paths['pilot'] $_.Exception.Message
    }
}

if ($null -ne $pilotRegistry) {
    $pilotStatus = [string]$pilotRegistry.pilot_status
    $pilotSampleTarget = [int]$pilotRegistry.sample_target
    $pilotSamples = @($pilotRegistry.samples)
    $pilotSampleCount = $pilotSamples.Count
    $expectedPilotCategories = @(
        'ambiguous_requirement',
        'greenfield_main_chain',
        'existing_defect',
        'behavior_preserving_refactor',
        'cross_seam_implementation',
        'test_strategy',
        'release_readiness',
        'operations_incident',
        'capability_selection',
        'simple_task_negative_control'
    )
    $expectedObservationDimensions = @(
        'coordination_mode',
        'shared_write_set_policy',
        'tool_dispositions',
        'context_adapter',
        'skill_lifecycle_action'
    )
    $allowedPilotStatuses = @('pilot_not_executed', 'collecting', 'review_ready', 'reviewed')
    $allowedSampleStatuses = @('observed', 'reviewed')
    $allowedComparisonModes = @('matched_historical_native_only', 'alternating_matched_task', 'descriptive_only')
    $allowedTruthLevels = @('not_verified', 'designed', 'implemented', 'repo_verified', 'host_loaded', 'live_accepted')
    $allowedAcceptanceStatuses = @('pending', 'not_requested', 'accepted', 'partial', 'rejected')
    $allowedCoordinationModes = @('single_agent', 'read_only_panel', 'isolated_parallel', 'sequential_shared_write')
    $allowedSharedWritePolicies = @('single_writer', 'not_applicable')
    $allowedToolDispositions = @('adopt', 'adapt', 'defer', 'reject')
    $allowedContextAdapters = @('none', 'repo_native', 'external_read_only')
    $allowedSkillLifecycleActions = @('none', 'candidate', 'replay', 'shadow', 'canary', 'promote', 'revise', 'retire')
    $requiredSampleFields = @(
        'id', 'category', 'task_reference', 'source_type', 'synthetic', 'self_referential',
        'status', 'comparison_mode', 'evidence_refs', 'final_truth_level', 'user_acceptance_status',
        'observed_at', 'metrics', 'observations'
    )
    $requiredMetricFields = @(
        'time_to_first_value_minutes', 'rework_slices', 'unexpected_human_interruptions',
        'non_product_artifacts', 'focused_gate_seconds', 'full_gate_seconds'
    )

    if ([int]$pilotRegistry.schema_version -ne 1) {
        Add-LeanPlanningFinding ([ref]$findings) 'unsupported_pilot_registry_schema' $paths['pilot'] 'schema_version must be 1.'
    }
    if ([string]$pilotRegistry.program_id -ne 'skills-manager-vnext' -or [string]$pilotRegistry.track -ne 'lean_delivery_pilot' -or
        [string]$pilotRegistry.base_phase -ne 'P5') {
        Add-LeanPlanningFinding ([ref]$findings) 'unexpected_pilot_registry_identity' $paths['pilot'] `
            'Pilot registry identity must remain skills-manager-vnext/lean_delivery_pilot/P5.'
    }
    if ($allowedPilotStatuses -notcontains $pilotStatus) {
        Add-LeanPlanningFinding ([ref]$findings) 'unsupported_pilot_status' $paths['pilot'] ('Unsupported pilot status: {0}' -f $pilotStatus)
    }
    if ($pilotSampleTarget -ne 10) {
        Add-LeanPlanningFinding ([ref]$findings) 'unexpected_pilot_sample_target' $paths['pilot'] 'sample_target must remain 10.'
    }
    if ([string]$pilotRegistry.metrics_mode -ne 'observe_only' -or [bool]$pilotRegistry.metrics_completion_gate) {
        Add-LeanPlanningFinding ([ref]$findings) 'pilot_metrics_became_gate' $paths['pilot'] `
            'Pilot metrics must remain observe_only and metrics_completion_gate must remain false.'
    }
    if ([string]$pilotRegistry.p6_admission_status -ne 'hold') {
        Add-LeanPlanningFinding ([ref]$findings) 'pilot_p6_admission_not_hold' $paths['pilot'] 'Pilot registry must keep P6 admission on hold.'
    }
    if ([string]$pilotRegistry.runtime_implementation_status -ne 'no_runtime_implementation') {
        Add-LeanPlanningFinding ([ref]$findings) 'pilot_runtime_implementation_claimed' $paths['pilot'] `
            'Pilot registry must not claim a runtime implementation.'
    }
    if ([string]$pilotRegistry.live_acceptance_status -ne 'not_run') {
        Add-LeanPlanningFinding ([ref]$findings) 'pilot_live_acceptance_claimed' $paths['pilot'] `
            'Pilot registry must keep live acceptance at not_run.'
    }

    $declaredCategories = @($pilotRegistry.required_categories | ForEach-Object { [string]$_ })
    $missingCategories = @($expectedPilotCategories | Where-Object { $declaredCategories -notcontains $_ })
    $extraCategories = @($declaredCategories | Where-Object { $expectedPilotCategories -notcontains $_ })
    if ($declaredCategories.Count -ne $expectedPilotCategories.Count -or $missingCategories.Count -gt 0 -or $extraCategories.Count -gt 0) {
        Add-LeanPlanningFinding ([ref]$findings) 'pilot_category_contract_drift' $paths['pilot'] `
            'required_categories must contain the exact ten real-task categories.'
    }

    $declaredObservationDimensions = @($pilotRegistry.observation_dimensions | ForEach-Object { [string]$_ })
    $missingObservationDimensions = @($expectedObservationDimensions | Where-Object { $declaredObservationDimensions -notcontains $_ })
    $extraObservationDimensions = @($declaredObservationDimensions | Where-Object { $expectedObservationDimensions -notcontains $_ })
    if ($declaredObservationDimensions.Count -ne $expectedObservationDimensions.Count -or
        $missingObservationDimensions.Count -gt 0 -or $extraObservationDimensions.Count -gt 0) {
        Add-LeanPlanningFinding ([ref]$findings) 'pilot_observation_dimensions_drift' $paths['pilot'] `
            'observation_dimensions must contain the exact M0.2 coordination/tool observation fields.'
    }

    $countingPolicy = $pilotRegistry.counting_policy
    if (-not [bool]$countingPolicy.real_tasks_only -or [bool]$countingPolicy.synthetic_samples_count -or
        [bool]$countingPolicy.self_referential_tasks_count) {
        Add-LeanPlanningFinding ([ref]$findings) 'pilot_counting_policy_weakened' $paths['pilot'] `
            'Only real, non-synthetic, non-self-referential tasks may count toward the pilot.'
    }
    $baselinePolicy = $pilotRegistry.baseline_policy
    if ([string]$baselinePolicy.unmatched_mode -ne 'descriptive_only' -or [bool]$baselinePolicy.duplicate_execution_required -or
        [bool]$baselinePolicy.causal_claims_allowed) {
        Add-LeanPlanningFinding ([ref]$findings) 'pilot_baseline_policy_weakened' $paths['pilot'] `
            'Unmatched tasks must remain descriptive-only without duplicate execution or causal claims.'
    }

    $sampleIds = @{}
    foreach ($sample in $pilotSamples) {
        $sampleId = [string]$sample.id
        $samplePath = ('{0}#{1}' -f $paths['pilot'], $sampleId)
        if ([string]::IsNullOrWhiteSpace($sampleId) -or $sampleId -notmatch '^SMV-M1-[0-9]{3}$') {
            Add-LeanPlanningFinding ([ref]$findings) 'invalid_pilot_sample_id' $samplePath ('Invalid pilot sample id: {0}' -f $sampleId)
        }
        elseif ($sampleIds.ContainsKey($sampleId)) {
            Add-LeanPlanningFinding ([ref]$findings) 'duplicate_pilot_sample_id' $samplePath ('Duplicate pilot sample id: {0}' -f $sampleId)
        }
        else {
            $sampleIds[$sampleId] = $true
        }

        foreach ($field in $requiredSampleFields) {
            if (-not (Test-LeanObjectProperty $sample $field)) {
                Add-LeanPlanningFinding ([ref]$findings) 'missing_pilot_sample_field' $samplePath `
                    ('Pilot sample field is required: {0}' -f $field)
            }
        }
        foreach ($field in @('task_reference', 'status', 'comparison_mode', 'final_truth_level', 'user_acceptance_status', 'observed_at')) {
            if ([string]::IsNullOrWhiteSpace([string]$sample.$field)) {
                Add-LeanPlanningFinding ([ref]$findings) 'empty_pilot_sample_field' $samplePath `
                    ('Pilot sample field must be non-empty: {0}' -f $field)
            }
        }
        if (@($sample.evidence_refs).Count -eq 0) {
            Add-LeanPlanningFinding ([ref]$findings) 'missing_pilot_sample_evidence' $samplePath `
                'Pilot samples require at least one evidence reference.'
        }
        if ($expectedPilotCategories -notcontains [string]$sample.category) {
            Add-LeanPlanningFinding ([ref]$findings) 'unknown_pilot_sample_category' $samplePath `
                ('Unknown pilot category: {0}' -f [string]$sample.category)
        }
        if ($allowedSampleStatuses -notcontains [string]$sample.status) {
            Add-LeanPlanningFinding ([ref]$findings) 'unknown_pilot_sample_status' $samplePath ('Unknown sample status: {0}' -f [string]$sample.status)
        }
        if ($allowedComparisonModes -notcontains [string]$sample.comparison_mode) {
            Add-LeanPlanningFinding ([ref]$findings) 'unknown_pilot_comparison_mode' $samplePath `
                ('Unknown comparison mode: {0}' -f [string]$sample.comparison_mode)
        }
        if ($allowedTruthLevels -notcontains [string]$sample.final_truth_level) {
            Add-LeanPlanningFinding ([ref]$findings) 'unknown_pilot_truth_level' $samplePath `
                ('Unknown truth level: {0}' -f [string]$sample.final_truth_level)
        }
        if ($allowedAcceptanceStatuses -notcontains [string]$sample.user_acceptance_status) {
            Add-LeanPlanningFinding ([ref]$findings) 'unknown_pilot_acceptance_status' $samplePath `
                ('Unknown user acceptance status: {0}' -f [string]$sample.user_acceptance_status)
        }
        foreach ($metricField in $requiredMetricFields) {
            if (-not (Test-LeanObjectProperty $sample.metrics $metricField)) {
                Add-LeanPlanningFinding ([ref]$findings) 'missing_pilot_metric_field' $samplePath `
                    ('Pilot metric field is required: {0}' -f $metricField)
            }
        }

        foreach ($observationField in $expectedObservationDimensions) {
            if (-not (Test-LeanObjectProperty $sample.observations $observationField)) {
                Add-LeanPlanningFinding ([ref]$findings) 'missing_pilot_observation_field' $samplePath `
                    ('Pilot observation field is required: {0}' -f $observationField)
            }
        }
        if ($null -ne $sample.observations) {
            if ($allowedCoordinationModes -notcontains [string]$sample.observations.coordination_mode) {
                Add-LeanPlanningFinding ([ref]$findings) 'unknown_pilot_coordination_mode' $samplePath `
                    ('Unknown coordination_mode: {0}' -f [string]$sample.observations.coordination_mode)
            }
            if ($allowedSharedWritePolicies -notcontains [string]$sample.observations.shared_write_set_policy) {
                Add-LeanPlanningFinding ([ref]$findings) 'unknown_pilot_shared_write_policy' $samplePath `
                    ('Unknown shared_write_set_policy: {0}' -f [string]$sample.observations.shared_write_set_policy)
            }
            foreach ($toolDisposition in @($sample.observations.tool_dispositions | ForEach-Object { [string]$_ })) {
                if ($allowedToolDispositions -notcontains $toolDisposition) {
                    Add-LeanPlanningFinding ([ref]$findings) 'unknown_pilot_tool_disposition' $samplePath `
                        ('Unknown tool disposition: {0}' -f $toolDisposition)
                }
            }
            if ($allowedContextAdapters -notcontains [string]$sample.observations.context_adapter) {
                Add-LeanPlanningFinding ([ref]$findings) 'unknown_pilot_context_adapter' $samplePath `
                    ('Unknown context_adapter: {0}' -f [string]$sample.observations.context_adapter)
            }
            if ($allowedSkillLifecycleActions -notcontains [string]$sample.observations.skill_lifecycle_action) {
                Add-LeanPlanningFinding ([ref]$findings) 'unknown_pilot_skill_lifecycle_action' $samplePath `
                    ('Unknown skill_lifecycle_action: {0}' -f [string]$sample.observations.skill_lifecycle_action)
            }
        }

        $isRealCountableSample = ([string]$sample.source_type -eq 'real_task' -and -not [bool]$sample.synthetic -and
            -not [bool]$sample.self_referential)
        if (-not $isRealCountableSample) {
            Add-LeanPlanningFinding ([ref]$findings) 'non_real_pilot_sample' $samplePath `
                'Synthetic or self-referential observations cannot be registered as pilot samples.'
        }
        else {
            $countedPilotSamples += $sample
        }
    }

    $pilotCategoriesCovered = @($countedPilotSamples | ForEach-Object { [string]$_.category } | Where-Object {
        $expectedPilotCategories -contains $_
    } | Sort-Object -Unique)
    if ($pilotSampleCount -gt $pilotSampleTarget) {
        Add-LeanPlanningFinding ([ref]$findings) 'pilot_sample_limit_exceeded' $paths['pilot'] `
            ('Pilot contains {0} samples, above target {1}.' -f $pilotSampleCount, $pilotSampleTarget)
    }
    if ($pilotStatus -eq 'pilot_not_executed' -and $pilotSampleCount -ne 0) {
        Add-LeanPlanningFinding ([ref]$findings) 'unexecuted_pilot_has_samples' $paths['pilot'] `
            'pilot_not_executed cannot contain samples.'
    }
    if ($pilotStatus -in @('review_ready', 'reviewed')) {
        if ($countedPilotSamples.Count -ne $pilotSampleTarget) {
            Add-LeanPlanningFinding ([ref]$findings) 'pilot_review_sample_count_incomplete' $paths['pilot'] `
                ('{0} requires exactly {1} countable real samples.' -f $pilotStatus, $pilotSampleTarget)
        }
        $missingCoverage = @($expectedPilotCategories | Where-Object { $pilotCategoriesCovered -notcontains $_ })
        if ($missingCoverage.Count -gt 0) {
            Add-LeanPlanningFinding ([ref]$findings) 'pilot_review_category_coverage_incomplete' $paths['pilot'] `
                ('Pilot review is missing categories: {0}' -f ($missingCoverage -join ', '))
        }
    }
    if ($pilotStatus -eq 'reviewed' -and @($pilotSamples | Where-Object { [string]$_.status -ne 'reviewed' }).Count -gt 0) {
        Add-LeanPlanningFinding ([ref]$findings) 'reviewed_pilot_has_unreviewed_samples' $paths['pilot'] `
            'A reviewed pilot requires every sample status to be reviewed.'
    }
}

if (-not (Test-LeanContainsLiteral $content['spec'] 'P6_ADMISSION_STATUS: hold')) {
    Add-LeanPlanningFinding ([ref]$findings) 'spec_p6_hold_missing' $paths['spec'] 'Spec must keep P6_ADMISSION_STATUS: hold.'
}
$specPilotStatus = ''
if (-not [string]::IsNullOrWhiteSpace($content['spec']) -and $content['spec'] -match 'PILOT_STATUS:\s*([a-z_]+)') {
    $specPilotStatus = [string]$Matches[1]
}
if ([string]::IsNullOrWhiteSpace($specPilotStatus) -or $specPilotStatus -ne $pilotStatus) {
    Add-LeanPlanningFinding ([ref]$findings) 'pilot_status_mismatch' $paths['spec'] `
        ('Spec PILOT_STATUS must match registry status: spec={0}, registry={1}.' -f $specPilotStatus, $pilotStatus)
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
foreach ($policyContract in @(
    @{ key = 'spec'; literal = 'CONTROL_PLANE_STATUS: not_introduced'; code = 'control_plane_status_missing'; message = 'M0.2 must explicitly keep coordinator/lease control-plane runtime not introduced.' },
    @{ key = 'spec'; literal = 'SHARED_WRITE_SET_POLICY: single_writer'; code = 'shared_write_policy_missing'; message = 'M0.2 must keep shared write sets on the single_writer policy.' },
    @{ key = 'spec'; literal = 'GIT_CAS_SEMANTICS: ref_freshness_not_file_queue'; code = 'git_cas_semantics_missing'; message = 'M0.2 must define Git CAS as ref freshness rather than a file queue.' },
    @{ key = 'spec'; literal = 'TOOL_DISPOSITION_POLICY: adopt_adapt_defer_reject'; code = 'tool_disposition_policy_missing'; message = 'M0.2 must preserve the four-state tool disposition contract.' },
    @{ key = 'prd'; literal = 'FR-EWF-012'; code = 'engineered_workflow_requirement_missing'; message = 'PRD must contain the M1 coordination/tool observation requirement.' },
    @{ key = 'architecture'; literal = 'ADR-SMV-024'; code = 'coordination_architecture_decision_missing'; message = 'Architecture must contain the host-owned coordinator/single-writer ADR.' },
    @{ key = 'architecture'; literal = 'ADR-SMV-025'; code = 'tool_admission_architecture_decision_missing'; message = 'Architecture must contain the evidence-gated tool-adapter ADR.' },
    @{ key = 'architecture'; literal = 'Git CAS is not a file lock or task queue'; code = 'git_cas_negative_boundary_missing'; message = 'Architecture must explicitly reject file-lock/task-queue Git CAS semantics.' },
    @{ key = 'roadmap'; literal = '| `M0.2` | `repo_verified` |'; code = 'm0_2_roadmap_status_missing'; message = 'Roadmap must register the bounded M0.2 clarification as repo_verified planning truth.' },
    @{ key = 'spec'; literal = 'MODEL_POLICY_STATUS: host_advisory_only'; code = 'model_policy_status_missing'; message = 'M0.3 must keep model policy host-owned and advisory-only.' },
    @{ key = 'spec'; literal = 'RADAR_SNAPSHOT_POLICY: advisory_expiring_snapshot'; code = 'radar_snapshot_policy_missing'; message = 'M0.3 must keep Radar data explicit, advisory, and expiring.' },
    @{ key = 'spec'; literal = 'M0_3_TYPED_CORE_STATUS: poc_not_started'; code = 'm0_3_typed_core_status_missing'; message = 'M0.3 historical closeout must remain poc_not_started.' },
    @{ key = 'spec'; literal = 'TYPED_CORE_STATUS: tc1_shadow_repo_verified'; code = 'typed_core_status_missing'; message = 'Current adjacent follow-up must record the repo-verified TC1 shadow state.' },
    @{ key = 'spec'; literal = 'TYPED_CORE_PRODUCTION_STATUS: not_started'; code = 'typed_core_production_status_missing'; message = 'Typed-core production migration must remain not_started.' },
    @{ key = 'spec'; literal = 'POWERSHELL_COMPATIBILITY_STATUS: ps7_primary_ps51_bounded_smoke'; code = 'powershell_compatibility_status_missing'; message = 'M0.3 must preserve PS7 primary and bounded PS5.1 compatibility truth.' },
    @{ key = 'prd'; literal = 'FR-EWF-017'; code = 'model_escalation_requirement_missing'; message = 'PRD must define bounded model escalation and failure routing.' },
    @{ key = 'prd'; literal = 'NFR-TEC-001'; code = 'typed_core_requirement_missing'; message = 'PRD must contain the conditional typed-core technology requirement.' },
    @{ key = 'architecture'; literal = 'ADR-SMV-026'; code = 'model_policy_architecture_decision_missing'; message = 'Architecture must contain the host-owned task/model policy ADR.' },
    @{ key = 'architecture'; literal = 'ADR-SMV-027'; code = 'typed_core_architecture_decision_missing'; message = 'Architecture must contain the protocol-first typed-core ADR.' },
    @{ key = 'architecture'; literal = 'PowerShell remains a compatibility shell, not the domain-policy source of truth'; code = 'typed_core_negative_boundary_missing'; message = 'Architecture must state the PowerShell compatibility-shell target without claiming an implemented migration.' },
    @{ key = 'roadmap'; literal = '| `M0.3` | `repo_verified` |'; code = 'm0_3_roadmap_status_missing'; message = 'Roadmap must register M0.3 as repo-verified planning truth only.' }
)) {
    if (-not (Test-LeanContainsLiteral $content[$policyContract.key] $policyContract.literal)) {
        Add-LeanPlanningFinding ([ref]$findings) $policyContract.code $paths[$policyContract.key] $policyContract.message
    }
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
    model_policy_status = 'host_advisory_only'
    radar_snapshot_policy = 'advisory_expiring_snapshot'
    m0_3_typed_core_status = 'poc_not_started'
    typed_core_status = 'tc1_shadow_repo_verified'
    typed_core_production_status = 'not_started'
    powershell_compatibility_status = 'ps7_primary_ps51_bounded_smoke'
    pilot_status = $pilotStatus
    pilot_sample_target = $pilotSampleTarget
    pilot_sample_count = $pilotSampleCount
    counted_pilot_sample_count = $countedPilotSamples.Count
    pilot_categories_covered = @($pilotCategoriesCovered)
    pilot_observation_dimensions = if ($null -ne $pilotRegistry) { @($pilotRegistry.observation_dimensions) } else { @() }
    pass = ($findings.Count -eq 0)
    task_count = $taskCount
    done_count = $doneCount
    open_count = $openCount
    evidence_groups = @($doneEvidenceSetsByGroup.Keys | Sort-Object)
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
