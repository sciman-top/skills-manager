function Get-AgentTaskIndex($TaskGraph) {
    $index = @{}
    foreach ($task in @((Get-OperationObjectProperty $TaskGraph 'tasks'))) { $index[([string](Get-OperationObjectProperty $task 'task_id')).ToLowerInvariant()] = $task }
    return $index
}

function Get-AgentAccessKey([string]$Key) {
    $match = [regex]::Match($Key, '^(?<mode>read|write):(?<resource>.+)$', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { return $null }
    return [pscustomobject]@{ mode = $match.Groups['mode'].Value.ToLowerInvariant(); resource = $match.Groups['resource'].Value.Trim().ToLowerInvariant() }
}

function Add-AgentAccessConflictFindings($Findings, [object[]]$Items, [string]$Code, [string]$Path, [string]$Message) {
    $byResource = @{}
    foreach ($item in @($Items)) {
        $resource = ([string](Get-OperationObjectProperty $item 'resource')).Trim().ToLowerInvariant()
        $mode = ([string](Get-OperationObjectProperty $item 'mode')).Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($resource)) { continue }
        if (-not $byResource.ContainsKey($resource)) { $byResource[$resource] = New-Object System.Collections.Generic.List[string] }
        $byResource[$resource].Add($mode) | Out-Null
    }
    foreach ($resource in @($byResource.Keys)) { if ($byResource[$resource].Count -gt 1 -and @($byResource[$resource] | Where-Object { $_ -eq 'write' }).Count -gt 0) { $Findings.Add((New-OperationFinding $Code 'error' $Path ($Message + ': ' + $resource))) | Out-Null } }
}

function Test-AgentParallelAdmission {
    param($TaskGraph, [string[]]$TaskIds = @(), [string[]]$CompletedTaskIds = @())
    $findings = New-Object System.Collections.Generic.List[object]
    $graphValidation = Test-AgentTaskGraphContract $TaskGraph
    foreach ($finding in @($graphValidation.findings)) { $findings.Add($finding) | Out-Null }
    $taskIndex = Get-AgentTaskIndex $TaskGraph
    $completed = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    foreach ($taskId in @($CompletedTaskIds)) { $completed.Add([string]$taskId) | Out-Null }
    $selected = New-Object System.Collections.Generic.List[object]
    $seen = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    foreach ($taskId in @($TaskIds)) {
        if (-not $seen.Add([string]$taskId)) { $findings.Add((New-OperationFinding 'parallel_task_duplicate' 'error' '$.requested_parallel_task_ids' 'Parallel task ID is duplicated.')) | Out-Null; continue }
        $key = ([string]$taskId).ToLowerInvariant()
        if (-not $taskIndex.ContainsKey($key)) { $findings.Add((New-OperationFinding 'parallel_task_unknown' 'error' '$.requested_parallel_task_ids' 'Parallel task is not declared.')) | Out-Null; continue }
        $task = $taskIndex[$key]; $selected.Add($task) | Out-Null
        if (-not [bool](Get-OperationObjectProperty $task 'parallelizable')) { $findings.Add((New-OperationFinding 'task_not_parallelizable' 'error' ('$.tasks[{0}]' -f $taskId) 'Task is explicitly serial.')) | Out-Null }
        foreach ($dependency in @((Get-OperationObjectProperty $task 'depends_on'))) { if (-not $completed.Contains([string]$dependency)) { $findings.Add((New-OperationFinding 'dependency_not_completed' 'error' ('$.tasks[{0}].depends_on' -f $taskId) 'Dependency is not completed.')) | Out-Null } }
        if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $task 'result_owner'))) { $findings.Add((New-OperationFinding 'result_owner_required' 'error' ('$.tasks[{0}].result_owner' -f $taskId) 'Parallel tasks require a result owner.')) | Out-Null }
        if (@((Get-OperationObjectProperty $task 'verification')).Count -eq 0) { $findings.Add((New-OperationFinding 'verification_required' 'error' ('$.tasks[{0}].verification' -f $taskId) 'Parallel tasks require independent verification.')) | Out-Null }
    }
    if ($selected.Count -lt 2) { $findings.Add((New-OperationFinding 'parallel_batch_too_small' 'error' '$.requested_parallel_task_ids' 'Parallel admission requires at least two tasks.')) | Out-Null }
    $writeOwners = @{}
    foreach ($task in @($selected.ToArray())) {
        foreach ($writePath in @((Get-OperationObjectProperty $task 'exact_write_set'))) {
            $normalized = ([string]$writePath).Replace('\', '/').Trim().ToLowerInvariant()
            if (-not $writeOwners.ContainsKey($normalized)) { $writeOwners[$normalized] = New-Object System.Collections.Generic.List[string] }
            $writeOwners[$normalized].Add([string](Get-OperationObjectProperty $task 'task_id')) | Out-Null
        }
    }
    foreach ($writePath in @($writeOwners.Keys)) { if ($writeOwners[$writePath].Count -gt 1) { $findings.Add((New-OperationFinding 'write_set_conflict' 'error' '$.tasks.exact_write_set' ('Parallel tasks share an exact write path: {0}' -f $writePath))) | Out-Null } }
    $coordination = New-Object System.Collections.Generic.List[object]
    $external = New-Object System.Collections.Generic.List[object]
    foreach ($task in @($selected.ToArray())) {
        foreach ($key in @((Get-OperationObjectProperty $task 'coordination_keys'))) { $parsed = Get-AgentAccessKey ([string]$key); if ($null -ne $parsed) { $coordination.Add($parsed) | Out-Null } }
        foreach ($state in @((Get-OperationObjectProperty $task 'external_state'))) { $external.Add([pscustomobject]@{ resource = [string](Get-OperationObjectProperty $state 'resource'); mode = [string](Get-OperationObjectProperty $state 'mode') }) | Out-Null }
    }
    Add-AgentAccessConflictFindings $findings $coordination.ToArray() 'coordination_key_conflict' '$.tasks.coordination_keys' 'Parallel tasks share an exclusive coordination seam'
    Add-AgentAccessConflictFindings $findings $external.ToArray() 'external_state_conflict' '$.tasks.external_state' 'Parallel tasks conflict on external state'
    $result = New-OperationValidationResult $findings.ToArray()
    $result | Add-Member -NotePropertyName mode -NotePropertyValue $(if ($result.pass) { 'isolated_parallel' } else { 'sequential_required' })
    $result | Add-Member -NotePropertyName task_ids -NotePropertyValue @($selected.ToArray() | ForEach-Object { [string](Get-OperationObjectProperty $_ 'task_id') })
    return $result
}

function New-AgentExecutionPlan {
    param($TaskGraph)
    $validation = Test-AgentTaskGraphContract $TaskGraph
    if (-not $validation.pass) { return [pscustomobject][ordered]@{ schema_version = 1; pass = $false; decision_owner = 'host_ai'; executor = 'host_native_runtime'; waves = @(); findings = @($validation.findings); provider_calls = 0; native_mutations = 0; writes = 0 } }
    $taskIndex = Get-AgentTaskIndex $TaskGraph
    $remaining = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    foreach ($taskId in @($taskIndex.Keys)) { $remaining.Add($taskId) | Out-Null }
    $completed = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    $waves = New-Object System.Collections.Generic.List[object]
    $waveNumber = 0
    while ($remaining.Count -gt 0) {
        $ready = @($remaining | Where-Object { $task = $taskIndex[$_]; @((Get-OperationObjectProperty $task 'depends_on') | Where-Object { -not $completed.Contains([string]$_) }).Count -eq 0 } | ForEach-Object { $taskIndex[$_] } | Sort-Object { [int](Get-OperationObjectProperty $_ 'integration_order') }, { [string](Get-OperationObjectProperty $_ 'task_id') })
        if ($ready.Count -eq 0) { break }
        $waveNumber++
        $groups = New-Object System.Collections.Generic.List[object]
        $parallelGroups = New-Object System.Collections.Generic.List[object]
        foreach ($task in @($ready)) {
            $taskId = [string](Get-OperationObjectProperty $task 'task_id')
            if (-not [bool](Get-OperationObjectProperty $task 'parallelizable')) { $groups.Add([pscustomobject][ordered]@{ mode = 'sequential'; task_ids = @($taskId) }) | Out-Null; continue }
            $placed = $false
            foreach ($group in @($parallelGroups.ToArray())) {
                $candidateIds = @($group.task_ids) + $taskId
                if ((Test-AgentParallelAdmission -TaskGraph $TaskGraph -TaskIds $candidateIds -CompletedTaskIds @($completed)).pass) { $group.task_ids = $candidateIds; $placed = $true; break }
            }
            if (-not $placed) { $parallelGroups.Add([pscustomobject][ordered]@{ mode = 'single_agent'; task_ids = @($taskId) }) | Out-Null }
        }
        foreach ($group in @($parallelGroups.ToArray())) { if (@($group.task_ids).Count -gt 1) { $group.mode = 'isolated_parallel' }; $groups.Add($group) | Out-Null }
        $waves.Add([pscustomobject][ordered]@{ wave = $waveNumber; groups = @($groups.ToArray()) }) | Out-Null
        foreach ($task in @($ready)) { $taskId = [string](Get-OperationObjectProperty $task 'task_id'); $remaining.Remove($taskId) | Out-Null; $completed.Add($taskId) | Out-Null }
    }
    return [pscustomobject][ordered]@{ schema_version = 1; pass = ($remaining.Count -eq 0); decision_owner = 'host_ai'; executor = 'host_native_runtime'; waves = @($waves.ToArray()); findings = @(); provider_calls = 0; native_mutations = 0; writes = 0 }
}

function Get-AgentModelTierAnchor([string]$Tier) {
    switch ($Tier.ToLowerInvariant()) {
        'sol_xhigh' { return [pscustomobject]@{ tier = 'sol_xhigh'; label = 'Sol xhigh'; model_family = 'gpt-5.6-sol'; reasoning_effort = 'xhigh' } }
        'sol_medium' { return [pscustomobject]@{ tier = 'sol_medium'; label = 'Sol medium'; model_family = 'gpt-5.6-sol'; reasoning_effort = 'medium' } }
        'luna_max' { return [pscustomobject]@{ tier = 'luna_max'; label = 'Luna max'; model_family = 'gpt-5.6-luna'; reasoning_effort = 'max' } }
        default { return $null }
    }
}

function New-ModelPolicyProposal {
    param(
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)][string]$RequestedTier,
        [Parameter(Mandatory = $true)][string]$Rationale,
        $RadarSnapshot,
        [string[]]$HostAvailablePairs = @(),
        [object[]]$LocalOutcomes = @(),
        [Parameter(Mandatory = $true)][string]$Now,
        [string]$UserOverrideTier
    )
    $effectiveTier = if ([string]::IsNullOrWhiteSpace($UserOverrideTier)) { $RequestedTier } else { $UserOverrideTier }
    $anchor = Get-AgentModelTierAnchor $effectiveTier
    $fallbackReasons = New-Object System.Collections.Generic.List[string]
    $radarValidation = Test-RadarSnapshotContract -Snapshot $RadarSnapshot -Now $Now
    $hasLocal = @($LocalOutcomes).Count -gt 0
    if ($null -eq $anchor) { $fallbackReasons.Add('tier_unknown') | Out-Null }
    if (-not $radarValidation.pass -and -not $hasLocal) { foreach ($code in @($radarValidation.findings.code | Sort-Object -Unique)) { $fallbackReasons.Add([string]$code) | Out-Null } }
    if ($null -ne $anchor) {
        $pair = '{0}|{1}' -f $anchor.model_family, $anchor.reasoning_effort
        if (@($HostAvailablePairs).Count -gt 0 -and $pair -notin @($HostAvailablePairs)) { $fallbackReasons.Add('host_pair_unavailable') | Out-Null }
    }
    $fallback = $fallbackReasons.Count -gt 0
    $radarEntry = $null
    if (-not $fallback -and $null -ne $anchor -and $radarValidation.pass) { $radarEntry = @((Get-OperationObjectProperty $RadarSnapshot 'entries') | Where-Object { [string](Get-OperationObjectProperty $_ 'model_family') -eq $anchor.model_family -and [string](Get-OperationObjectProperty $_ 'reasoning_effort') -eq $anchor.reasoning_effort } | Select-Object -First 1) }
    if ($radarEntry -is [array]) { $radarEntry = if ($radarEntry.Count -gt 0) { $radarEntry[0] } else { $null } }
    return [pscustomobject][ordered]@{
        schema_version = 1; task_id = $TaskId; decision_owner = 'host_ai'; advisory_only = $true
        requested_tier = $RequestedTier; selected_tier = $(if ($fallback) { 'host_default' } else { $anchor.tier })
        model_family = $(if ($fallback) { $null } else { $anchor.model_family }); reasoning_effort = $(if ($fallback) { $null } else { $anchor.reasoning_effort })
        rationale = $Rationale; user_override = (-not [string]::IsNullOrWhiteSpace($UserOverrideTier)); fallback_reason = $(if ($fallback) { @($fallbackReasons) -join ',' } else { $null })
        evidence_priority = 'user_override_then_local_outcomes_then_host_availability_then_radar_then_host_default'; local_outcomes = @(Copy-AgentWorkflowValue $LocalOutcomes); radar_snapshot_id = Get-OperationObjectProperty $RadarSnapshot 'snapshot_id'; radar_entry = Copy-AgentWorkflowValue $radarEntry
        provider_calls = 0; native_mutations = 0; writes = 0
    }
}

function Get-AgentEscalationDecision {
    param([Parameter(Mandatory = $true)]$FailurePacket)
    $validation = Test-AgentFailurePacketContract $FailurePacket
    if (-not $validation.pass) { return [pscustomobject][ordered]@{ action = 'supervisor_review'; next_tier = $null; parallel_allowed = $false; requires_new_task_graph = $false; findings = @($validation.findings) } }
    $kind = [string](Get-OperationObjectProperty $FailurePacket 'failure_kind')
    $attempt = [int](Get-OperationObjectProperty $FailurePacket 'attempt_count')
    $escalations = [int](Get-OperationObjectProperty $FailurePacket 'escalation_count')
    $tier = [string](Get-OperationObjectProperty $FailurePacket 'attempted_tier')
    $action = 'supervisor_review'; $nextTier = $null; $requiresGraph = $false
    if ($kind -in @('permission', 'credential', 'production_authorization', 'user_decision')) { $action = 'fail_closed' }
    elseif ($kind -in @('task', 'context')) { $action = 'rescope_task_graph'; $requiresGraph = $true }
    elseif ($kind -eq 'tool') { $action = 'repair_tool_or_reassign' }
    elseif ($kind -eq 'capacity') {
        if ($tier -notin @('luna_max', 'sol_medium', 'sol_xhigh')) { $action = 'supervisor_review' }
        elseif ($attempt -le 1) { $action = 'corrected_retry' }
        elseif ($escalations -ge 2 -or $tier -eq 'sol_xhigh') { $action = 'supervisor_takeover'; $requiresGraph = $true }
        else {
            $action = 'replan_and_escalate'; $requiresGraph = $true
            $nextTier = switch ($tier) {
                'luna_max' { 'sol_medium' }
                'sol_medium' { 'sol_xhigh' }
            }
        }
    }
    return [pscustomobject][ordered]@{ action = $action; next_tier = $nextTier; parallel_allowed = ($action -in @('corrected_retry', 'repair_tool_or_reassign')); requires_new_task_graph = $requiresGraph; issue_id = [string](Get-OperationObjectProperty $FailurePacket 'issue_id'); findings = @() }
}

function Test-AgentWorkflowRequest($Request) {
    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Request) { return New-OperationValidationResult @((New-OperationFinding 'request_missing' 'error' '$' 'Agent workflow request is required.')) }
    foreach ($result in @(
            (Test-AgentTaskGraphContract (Get-OperationObjectProperty $Request 'task_graph')),
            (Test-RadarSnapshotContract -Snapshot (Get-OperationObjectProperty $Request 'radar_snapshot') -Now ([string](Get-OperationObjectProperty $Request 'now'))),
            (Test-AgentParallelAdmission -TaskGraph (Get-OperationObjectProperty $Request 'task_graph') -TaskIds @((Get-OperationObjectProperty $Request 'requested_parallel_task_ids')) -CompletedTaskIds @((Get-OperationObjectProperty $Request 'completed_task_ids')))
        )) { foreach ($finding in @($result.findings)) { $findings.Add($finding) | Out-Null } }
    $failurePacket = Get-OperationObjectProperty $Request 'failure_packet'
    if ($null -ne $failurePacket) { foreach ($finding in @((Test-AgentFailurePacketContract $failurePacket).findings)) { $findings.Add($finding) | Out-Null } }
    return New-OperationValidationResult $findings.ToArray()
}

function New-AgentWorkflowAdvisoryPlan($Request) {
    $requestValidation = Test-AgentWorkflowRequest $Request
    $graph = Get-OperationObjectProperty $Request 'task_graph'
    $proposals = New-Object System.Collections.Generic.List[object]
    foreach ($proposal in @((Get-OperationObjectProperty $Request 'model_proposals'))) {
        $proposals.Add((New-ModelPolicyProposal -TaskId ([string](Get-OperationObjectProperty $proposal 'task_id')) -RequestedTier ([string](Get-OperationObjectProperty $proposal 'requested_tier')) -Rationale ([string](Get-OperationObjectProperty $proposal 'rationale')) -RadarSnapshot (Get-OperationObjectProperty $Request 'radar_snapshot') -HostAvailablePairs @((Get-OperationObjectProperty $proposal 'host_available_pairs')) -LocalOutcomes @((Get-OperationObjectProperty $proposal 'local_outcomes')) -Now ([string](Get-OperationObjectProperty $Request 'now')) -UserOverrideTier ([string](Get-OperationObjectProperty $proposal 'user_override_tier')))) | Out-Null
    }
    return [pscustomobject][ordered]@{
        schema_version = 1; pass = $requestValidation.pass; decision_owner = 'host_ai'; executor = 'host_native_runtime'; advisory_only = $true
        execution_plan = New-AgentExecutionPlan -TaskGraph $graph
        current_parallel_admission = Test-AgentParallelAdmission -TaskGraph $graph -TaskIds @((Get-OperationObjectProperty $Request 'requested_parallel_task_ids')) -CompletedTaskIds @((Get-OperationObjectProperty $Request 'completed_task_ids'))
        model_proposals = @($proposals.ToArray()); findings = @($requestValidation.findings); provider_calls = 0; native_mutations = 0; writes = 0
    }
}
