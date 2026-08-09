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

function Test-AgentCompletionVerificationReceipt {
    param($Evidence, $EvaluationTime)

    if ($null -eq $Evidence -or $Evidence -is [string]) { return $false }
    if ((Get-OperationObjectProperty $Evidence 'schema_version') -ne 1) { return $false }
    if ([string](Get-OperationObjectProperty $Evidence 'receipt_id') -notmatch '^verify-[A-Za-z0-9][A-Za-z0-9._-]{1,127}$') { return $false }
    if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $Evidence 'verifier'))) { return $false }
    if ([string](Get-OperationObjectProperty $Evidence 'evidence_sha256') -notmatch '^[a-fA-F0-9]{64}$') { return $false }
    $commands = Get-OperationObjectProperty $Evidence 'commands'
    if (-not (Test-OperationArray $commands) -or @($commands).Count -eq 0 -or @($commands | Where-Object { $_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) { return $false }
    $verifiedAt = ConvertTo-AgentWorkflowRfc3339Value (Get-OperationObjectProperty $Evidence 'verified_at')
    $evaluatedAt = ConvertTo-AgentWorkflowRfc3339Value $EvaluationTime
    if ($null -eq $verifiedAt -or $null -eq $evaluatedAt -or $verifiedAt -gt $evaluatedAt.AddMinutes(5)) { return $false }
    if (Test-OperationSerializedSensitiveValue ($Evidence | ConvertTo-Json -Depth 20 -Compress)) { return $false }
    return $true
}

function Test-AgentParallelAdmission {
    param($TaskGraph, [string[]]$TaskIds = @(), [string[]]$CompletedTaskIds = @(), [object[]]$CompletedTaskReceipts = @(), $EvaluationTime, [switch]$PlanningOnly)
    $findings = New-Object System.Collections.Generic.List[object]
    $graphValidation = Test-AgentTaskGraphContract $TaskGraph
    foreach ($finding in @($graphValidation.findings)) { $findings.Add($finding) | Out-Null }
    $taskIndex = Get-AgentTaskIndex $TaskGraph
    $completed = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    foreach ($taskId in @($CompletedTaskIds)) {
        $completedId = ([string]$taskId).Trim()
        if (-not $completed.Add($completedId)) { $findings.Add((New-OperationFinding 'completed_task_duplicate' 'error' '$.completed_task_ids' 'Completed task ID is duplicated.')) | Out-Null }
        if (-not $taskIndex.ContainsKey($completedId.ToLowerInvariant())) { $findings.Add((New-OperationFinding 'completed_task_unknown' 'error' '$.completed_task_ids' 'Completed task is not declared in this TaskGraph.')) | Out-Null }
    }
    $receiptIndex = @{}
    if (-not $PlanningOnly) {
        $receiptEvaluationTime = $null
        if (@($CompletedTaskReceipts).Count -gt 0) {
            $receiptEvaluationTime = ConvertTo-AgentWorkflowRfc3339Value $EvaluationTime
            if ($null -eq $receiptEvaluationTime) { $findings.Add((New-OperationFinding 'completion_evaluation_time_invalid' 'error' '$.now' 'Completion receipt validation requires an explicit RFC3339 evaluation time.')) | Out-Null }
        }
        foreach ($receipt in @($CompletedTaskReceipts)) {
            $receiptTaskId = ([string](Get-OperationObjectProperty $receipt 'task_id')).Trim()
            $receiptKey = $receiptTaskId.ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($receiptTaskId) -or -not $taskIndex.ContainsKey($receiptKey)) { $findings.Add((New-OperationFinding 'completion_receipt_task_invalid' 'error' '$.completion_receipts' 'Completion receipt task_id must belong to the TaskGraph.')) | Out-Null; continue }
            if ($receiptIndex.ContainsKey($receiptKey)) { $findings.Add((New-OperationFinding 'completion_receipt_duplicate' 'error' '$.completion_receipts' 'Completion receipt is duplicated.')) | Out-Null; continue }
            $receiptIndex[$receiptKey] = $receipt
            if ([string](Get-OperationObjectProperty $receipt 'base_revision') -cne [string](Get-OperationObjectProperty $TaskGraph 'base_revision')) { $findings.Add((New-OperationFinding 'completion_receipt_revision_mismatch' 'error' '$.completion_receipts' 'Completion receipt base_revision does not match the TaskGraph.')) | Out-Null }
            if ([string](Get-OperationObjectProperty $receipt 'status') -cne 'verified') { $findings.Add((New-OperationFinding 'completion_receipt_unverified' 'error' '$.completion_receipts' 'Completion receipt status must be verified.')) | Out-Null }
            $evidence = Get-OperationObjectProperty $receipt 'verification_receipt'
            if ($null -eq $evidence) { $findings.Add((New-OperationFinding 'completion_receipt_evidence_missing' 'error' '$.completion_receipts' 'Completion receipt requires verification evidence.')) | Out-Null }
            elseif (-not (Test-AgentCompletionVerificationReceipt -Evidence $evidence -EvaluationTime $receiptEvaluationTime)) { $findings.Add((New-OperationFinding 'completion_receipt_evidence_invalid' 'error' '$.completion_receipts' 'Completion verification evidence must be a structured, hashed, command-backed receipt evaluated against the request time.')) | Out-Null }
        }
        foreach ($completedId in @($completed)) { if (-not $receiptIndex.ContainsKey($completedId.ToLowerInvariant())) { $findings.Add((New-OperationFinding 'completion_receipt_missing' 'error' '$.completion_receipts' ('Verified completion receipt is missing for task: {0}' -f $completedId))) | Out-Null } }
        foreach ($receiptTaskId in @($receiptIndex.Keys)) { if (-not $completed.Contains($receiptTaskId)) { $findings.Add((New-OperationFinding 'completion_receipt_unclaimed' 'error' '$.completion_receipts' ('Completion receipt is not declared in completed_task_ids: {0}' -f $receiptTaskId))) | Out-Null } }
    }
    foreach ($completedId in @($completed)) {
        $completedKey = $completedId.ToLowerInvariant()
        if (-not $taskIndex.ContainsKey($completedKey)) { continue }
        foreach ($dependency in @((Get-OperationObjectProperty $taskIndex[$completedKey] 'depends_on'))) {
            if (-not $completed.Contains([string]$dependency)) { $findings.Add((New-OperationFinding 'completed_dependency_not_closed' 'error' '$.completed_task_ids' ('Completed task dependency is not also completed: {0} -> {1}' -f $completedId, [string]$dependency))) | Out-Null }
        }
    }
    $selected = New-Object System.Collections.Generic.List[object]
    $seen = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    foreach ($taskId in @($TaskIds)) {
        if (-not $seen.Add([string]$taskId)) { $findings.Add((New-OperationFinding 'parallel_task_duplicate' 'error' '$.requested_parallel_task_ids' 'Parallel task ID is duplicated.')) | Out-Null; continue }
        $key = ([string]$taskId).ToLowerInvariant()
        if (-not $taskIndex.ContainsKey($key)) { $findings.Add((New-OperationFinding 'parallel_task_unknown' 'error' '$.requested_parallel_task_ids' 'Parallel task is not declared.')) | Out-Null; continue }
        $task = $taskIndex[$key]; $selected.Add($task) | Out-Null
        if ($completed.Contains([string]$taskId)) { $findings.Add((New-OperationFinding 'selected_task_already_completed' 'error' '$.requested_parallel_task_ids' 'A task cannot be selected and completed in the same admission request.')) | Out-Null }
        if (-not [bool](Get-OperationObjectProperty $task 'parallelizable')) { $findings.Add((New-OperationFinding 'task_not_parallelizable' 'error' ('$.tasks[{0}]' -f $taskId) 'Task is explicitly serial.')) | Out-Null }
        if ([string](Get-OperationObjectProperty $task 'risk') -eq 'high') { $findings.Add((New-OperationFinding 'high_risk_parallel_forbidden' 'error' ('$.tasks[{0}].risk' -f $taskId) 'High-risk work requires supervisor-owned serial execution.')) | Out-Null }
        if ([string](Get-OperationObjectProperty $task 'ambiguity') -eq 'high') { $findings.Add((New-OperationFinding 'high_ambiguity_parallel_forbidden' 'error' ('$.tasks[{0}].ambiguity' -f $taskId) 'Highly ambiguous work requires clarification before parallel execution.')) | Out-Null }
        foreach ($dependency in @((Get-OperationObjectProperty $task 'depends_on'))) { if (-not $completed.Contains([string]$dependency)) { $findings.Add((New-OperationFinding 'dependency_not_completed' 'error' ('$.tasks[{0}].depends_on' -f $taskId) 'Dependency is not completed.')) | Out-Null } }
        if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $task 'result_owner'))) { $findings.Add((New-OperationFinding 'result_owner_required' 'error' ('$.tasks[{0}].result_owner' -f $taskId) 'Parallel tasks require a result owner.')) | Out-Null }
        if (@((Get-OperationObjectProperty $task 'verification')).Count -eq 0) { $findings.Add((New-OperationFinding 'verification_required' 'error' ('$.tasks[{0}].verification' -f $taskId) 'Parallel tasks require independent verification.')) | Out-Null }
    }
    if ($selected.Count -eq 1) { $findings.Add((New-OperationFinding 'parallel_batch_too_small' 'error' '$.requested_parallel_task_ids' 'Parallel admission requires at least two tasks.')) | Out-Null }
    $writeDeclarations = New-Object System.Collections.Generic.List[object]
    foreach ($task in @($selected.ToArray())) {
        foreach ($writePath in @((Get-OperationObjectProperty $task 'exact_write_set'))) {
            $normalized = Get-AgentCanonicalWritePath ([string]$writePath)
            if ($null -ne $normalized) { $writeDeclarations.Add([pscustomobject]@{ task_id = [string](Get-OperationObjectProperty $task 'task_id'); path = $normalized }) | Out-Null }
        }
    }
    for ($i = 0; $i -lt $writeDeclarations.Count; $i++) {
        for ($j = $i + 1; $j -lt $writeDeclarations.Count; $j++) {
            $left = $writeDeclarations[$i]; $right = $writeDeclarations[$j]
            if ($left.task_id -eq $right.task_id) { continue }
            if ($left.path -eq $right.path -or $left.path.StartsWith($right.path + '/', [StringComparison]::OrdinalIgnoreCase) -or $right.path.StartsWith($left.path + '/', [StringComparison]::OrdinalIgnoreCase)) {
                $findings.Add((New-OperationFinding 'write_set_conflict' 'error' '$.tasks.exact_write_set' ('Parallel write paths overlap: {0} <> {1}' -f $left.path, $right.path))) | Out-Null
            }
        }
    }
    $coordination = New-Object System.Collections.Generic.List[object]
    $external = New-Object System.Collections.Generic.List[object]
    foreach ($task in @($selected.ToArray())) {
        foreach ($key in @((Get-OperationObjectProperty $task 'coordination_keys'))) { $parsed = Get-AgentAccessKey ([string]$key); if ($null -ne $parsed) { $coordination.Add($parsed) | Out-Null } }
        foreach ($state in @((Get-OperationObjectProperty $task 'external_state'))) { $external.Add([pscustomobject]@{ resource = [string](Get-OperationObjectProperty $state 'resource'); mode = [string](Get-OperationObjectProperty $state 'mode') }) | Out-Null }
    }
    Add-AgentAccessConflictFindings $findings $coordination.ToArray() 'coordination_key_conflict' '$.tasks.coordination_keys' 'Parallel tasks share an exclusive coordination seam'
    Add-AgentAccessConflictFindings $findings $external.ToArray() 'external_state_conflict' '$.tasks.external_state' 'Parallel tasks conflict on external state'
    $result = New-OperationValidationResult $findings.ToArray()
    $result | Add-Member -NotePropertyName mode -NotePropertyValue $(if ($result.pass -and $selected.Count -eq 0) { 'not_requested' } elseif ($result.pass) { 'isolated_parallel' } else { 'sequential_required' })
    $result | Add-Member -NotePropertyName task_ids -NotePropertyValue @($selected.ToArray() | ForEach-Object { [string](Get-OperationObjectProperty $_ 'task_id') })
    $result | Add-Member -NotePropertyName completion_evidence_semantics -NotePropertyValue $(if ($PlanningOnly) { 'planned_dependency_order_only' } else { 'verified_receipts_required' })
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
        $mustRunSerial = @($ready | Where-Object { -not [bool](Get-OperationObjectProperty $_ 'parallelizable') -or [string](Get-OperationObjectProperty $_ 'risk') -eq 'high' -or [string](Get-OperationObjectProperty $_ 'ambiguity') -eq 'high' } | Select-Object -First 1)
        $selectedTasks = New-Object System.Collections.Generic.List[object]
        if ($mustRunSerial.Count -gt 0) { $selectedTasks.Add($mustRunSerial[0]) | Out-Null }
        else {
            foreach ($task in @($ready)) {
                if ($selectedTasks.Count -eq 0) { $selectedTasks.Add($task) | Out-Null; continue }
                $candidateIds = @($selectedTasks.ToArray() | ForEach-Object { [string](Get-OperationObjectProperty $_ 'task_id') }) + [string](Get-OperationObjectProperty $task 'task_id')
                if ((Test-AgentParallelAdmission -TaskGraph $TaskGraph -TaskIds $candidateIds -CompletedTaskIds @($completed) -PlanningOnly).pass) { $selectedTasks.Add($task) | Out-Null }
            }
        }
        $selectedIds = @($selectedTasks.ToArray() | ForEach-Object { [string](Get-OperationObjectProperty $_ 'task_id') })
        $mode = if ($selectedIds.Count -gt 1) { 'isolated_parallel' } else { 'sequential' }
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
        $waves.Add([pscustomobject][ordered]@{ wave = $waveNumber; groups = @([pscustomobject][ordered]@{ mode = $mode; task_ids = $selectedIds; admission = @($admission) }) }) | Out-Null
        foreach ($taskId in @($selectedIds)) { $remaining.Remove($taskId.ToLowerInvariant()) | Out-Null; $completed.Add($taskId) | Out-Null }
    }
    return [pscustomobject][ordered]@{ schema_version = 1; pass = ($remaining.Count -eq 0); decision_owner = 'host_ai'; executor = 'host_native_runtime'; waves = @($waves.ToArray()); findings = @(); provider_calls = 0; native_mutations = 0; writes = 0 }
}

function Get-AgentModelTierAnchor([string]$Tier) {
    switch ($Tier.ToLowerInvariant()) {
        'sol_xhigh' { return [pscustomobject]@{ tier = 'sol_xhigh'; label = 'Sol xhigh'; model_family = 'gpt-5.6-sol'; reasoning_effort = 'xhigh' } }
        'sol_medium' { return [pscustomobject]@{ tier = 'sol_medium'; label = 'Sol medium'; model_family = 'gpt-5.6-sol'; reasoning_effort = 'medium' } }
        'sol_low' { return [pscustomobject]@{ tier = 'sol_low'; label = 'Sol low'; model_family = 'gpt-5.6-sol'; reasoning_effort = 'low' } }
        default { return $null }
    }
}

function Test-AgentLocalOutcomeContract {
    param($Outcome, $Anchor, $Now)
    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Outcome) { return New-OperationValidationResult @((New-OperationFinding 'local_outcome_missing' 'error' '$.local_outcomes' 'Local outcome is required.')) }
    foreach ($field in @('task_class', 'model_family', 'reasoning_effort', 'base_revision', 'sampled_at')) {
        if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $Outcome $field))) { $findings.Add((New-OperationFinding 'local_outcome_field_missing' 'error' ('$.local_outcomes.{0}' -f $field) 'Comparable local outcome field is required.')) | Out-Null }
    }
    if ($null -ne $Anchor -and ([string](Get-OperationObjectProperty $Outcome 'model_family') -cne $Anchor.model_family -or [string](Get-OperationObjectProperty $Outcome 'reasoning_effort') -cne $Anchor.reasoning_effort)) { $findings.Add((New-OperationFinding 'local_outcome_pair_mismatch' 'error' '$.local_outcomes' 'Local outcome must describe the proposed model and reasoning pair.')) | Out-Null }
    if ((Get-OperationObjectProperty $Outcome 'gate_passed') -isnot [bool]) { $findings.Add((New-OperationFinding 'local_outcome_gate_invalid' 'error' '$.local_outcomes.gate_passed' 'gate_passed must be a boolean.')) | Out-Null }
    $rework = 0
    if (-not [int]::TryParse([string](Get-OperationObjectProperty $Outcome 'rework_count'), [ref]$rework) -or $rework -lt 0) { $findings.Add((New-OperationFinding 'local_outcome_rework_invalid' 'error' '$.local_outcomes.rework_count' 'rework_count must be a non-negative integer.')) | Out-Null }
    foreach ($field in @('actual_cost', 'actual_duration_seconds')) { if (-not (Test-AgentWorkflowNonNegativeFiniteNumber (Get-OperationObjectProperty $Outcome $field))) { $findings.Add((New-OperationFinding 'local_outcome_metric_invalid' 'error' ('$.local_outcomes.{0}' -f $field) 'Local outcome metric must be a finite non-negative number.')) | Out-Null } }
    $sampled = ConvertTo-AgentWorkflowRfc3339Value (Get-OperationObjectProperty $Outcome 'sampled_at')
    $nowValue = ConvertTo-AgentWorkflowRfc3339Value $Now
    if ($null -eq $nowValue) { $findings.Add((New-OperationFinding 'local_outcome_evaluation_time_invalid' 'error' '$.now' 'Local outcome freshness requires a valid RFC3339 evaluation time.')) | Out-Null }
    if ($null -eq $sampled) { $findings.Add((New-OperationFinding 'local_outcome_sampled_at_invalid' 'error' '$.local_outcomes.sampled_at' 'sampled_at must be RFC3339.')) | Out-Null }
    elseif ($null -ne $nowValue -and ($sampled -gt $nowValue.AddMinutes(5) -or $sampled -lt $nowValue.AddDays(-90))) { $findings.Add((New-OperationFinding 'local_outcome_stale' 'error' '$.local_outcomes.sampled_at' 'Local outcome must be within the 90-day comparison window.')) | Out-Null }
    return New-OperationValidationResult $findings.ToArray()
}

function New-ModelPolicyProposal {
    param(
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)][string]$RequestedTier,
        [Parameter(Mandatory = $true)][string]$Rationale,
        $RadarSnapshot,
        [string]$HostSurface,
        [string[]]$HostAvailablePairs = @(),
        [object[]]$LocalOutcomes = @(),
        [Parameter(Mandatory = $true)]$Now,
        [string]$UserOverrideTier
    )
    $effectiveTier = if ([string]::IsNullOrWhiteSpace($UserOverrideTier)) { $RequestedTier } else { $UserOverrideTier }
    $anchor = Get-AgentModelTierAnchor $effectiveTier
    $fallbackReasons = New-Object System.Collections.Generic.List[string]
    $validLocalOutcomes = New-Object System.Collections.Generic.List[object]
    $localFindings = New-Object System.Collections.Generic.List[object]
    foreach ($outcome in @($LocalOutcomes)) {
        $validation = Test-AgentLocalOutcomeContract -Outcome $outcome -Anchor $anchor -Now $Now
        if ($validation.pass) { $validLocalOutcomes.Add($outcome) | Out-Null } else { foreach ($finding in @($validation.findings)) { $localFindings.Add($finding) | Out-Null } }
    }
    $hasLocal = $validLocalOutcomes.Count -gt 0
    if ($null -eq $anchor) { $fallbackReasons.Add('tier_unknown') | Out-Null }
    if ([string]::IsNullOrWhiteSpace($Rationale)) { $fallbackReasons.Add('rationale_missing') | Out-Null }
    if (@($LocalOutcomes).Count -gt 0 -and -not $hasLocal) { $fallbackReasons.Add('local_outcome_invalid') | Out-Null }
    $hostConfirmed = $false
    $hostAvailabilityState = 'unknown'
    $hostSurfaceKnown = -not [string]::IsNullOrWhiteSpace($HostSurface) -and $HostSurface -match '^[a-z][a-z0-9_]{1,63}$'
    if (-not $hostSurfaceKnown) { $fallbackReasons.Add('host_surface_unknown') | Out-Null }
    if ($null -ne $anchor) {
        $pair = '{0}|{1}' -f $anchor.model_family, $anchor.reasoning_effort
        if ($hostSurfaceKnown -and @($HostAvailablePairs).Count -eq 0) {
            $fallbackReasons.Add('host_pair_availability_unknown') | Out-Null
        }
        elseif ($hostSurfaceKnown -and $pair -in @($HostAvailablePairs)) {
            $hostConfirmed = $true
            $hostAvailabilityState = 'confirmed_available'
        }
        elseif ($hostSurfaceKnown) {
            $hostAvailabilityState = 'confirmed_unavailable'
            $fallbackReasons.Add('host_pair_unavailable') | Out-Null
        }
    }
    $fallback = $fallbackReasons.Count -gt 0
    return [pscustomobject][ordered]@{
        schema_version = 1; task_id = $TaskId; decision_owner = 'host_ai'; advisory_only = $true
        requested_tier = $RequestedTier; selected_tier = $(if ($fallback) { 'host_default' } else { $anchor.tier })
        model_family = $(if ($fallback) { $null } else { $anchor.model_family }); reasoning_effort = $(if ($fallback) { $null } else { $anchor.reasoning_effort })
        rationale = $Rationale; user_override = (-not [string]::IsNullOrWhiteSpace($UserOverrideTier)); fallback_reason = $(if ($fallback) { @($fallbackReasons) -join ',' } else { $null })
        evidence_priority = 'user_override_then_local_outcomes_then_host_availability_then_host_default'; selection_semantics = 'host_proposal_validation_only'
        local_outcomes = @(Copy-AgentWorkflowValue $validLocalOutcomes.ToArray())
        evidence_sources = [pscustomobject][ordered]@{ local = [pscustomobject]@{ valid = $hasLocal; supplied = @($LocalOutcomes).Count; accepted = $validLocalOutcomes.Count; rejected_findings = @($localFindings.ToArray()) }; host_availability = [pscustomobject]@{ surface = $(if ($hostSurfaceKnown) { $HostSurface } else { $null }); state = $hostAvailabilityState; declared = ($hostSurfaceKnown -and @($HostAvailablePairs).Count -gt 0); pair_confirmed = $hostConfirmed } }
        provider_calls = 0; native_mutations = 0; writes = 0
    }
}

function Get-AgentEscalationDecision {
    param([Parameter(Mandatory = $true)]$FailurePacket)
    $validation = Test-AgentFailurePacketContract $FailurePacket
    if (-not $validation.pass) { return [pscustomobject][ordered]@{ action = 'supervisor_review'; next_tier = $null; parallel_allowed = $false; requires_parallel_readmission = $false; requires_new_task_graph = $false; findings = @($validation.findings) } }
    $kind = [string](Get-OperationObjectProperty $FailurePacket 'failure_kind')
    $attempt = [int](Get-OperationObjectProperty $FailurePacket 'attempt_count')
    $escalations = [int](Get-OperationObjectProperty $FailurePacket 'escalation_count')
    $tier = [string](Get-OperationObjectProperty $FailurePacket 'attempted_tier')
    $action = 'supervisor_review'; $nextTier = $null; $requiresGraph = $false
    if ($kind -in @('permission', 'credential', 'production_authorization', 'user_decision')) { $action = 'fail_closed' }
    elseif ($kind -in @('task', 'context')) { $action = $(if ($attempt -ge 2) { 'supervisor_takeover' } else { 'rescope_task_graph' }); $requiresGraph = $true }
    elseif ($kind -eq 'tool') { $action = $(if ($attempt -ge 2) { 'supervisor_takeover' } else { 'repair_tool_or_reassign' }); $requiresGraph = ($attempt -ge 2) }
    elseif ($kind -eq 'capacity') {
        if ($tier -notin @('sol_low', 'sol_medium', 'sol_xhigh')) { $action = 'supervisor_review' }
        elseif ($escalations -ge 2 -or ($tier -eq 'sol_xhigh' -and $attempt -gt 1)) { $action = 'supervisor_takeover'; $requiresGraph = $true }
        elseif ($attempt -le 1) { $action = 'corrected_retry' }
        else {
            $action = 'replan_and_escalate'; $requiresGraph = $true
            $nextTier = switch ($tier) {
                'sol_low' { 'sol_medium' }
                'sol_medium' { 'sol_xhigh' }
            }
        }
    }
    return [pscustomobject][ordered]@{ action = $action; next_tier = $nextTier; parallel_allowed = $false; requires_parallel_readmission = ($action -in @('corrected_retry', 'repair_tool_or_reassign')); requires_new_task_graph = $requiresGraph; issue_id = [string](Get-OperationObjectProperty $FailurePacket 'issue_id'); findings = @() }
}

function Test-AgentWorkflowRequest($Request) {
    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Request) { return New-OperationValidationResult @((New-OperationFinding 'request_missing' 'error' '$' 'Agent workflow request is required.')) }
    foreach ($result in @(
            (Test-AgentTaskGraphContract (Get-OperationObjectProperty $Request 'task_graph')),
            (Test-AgentParallelAdmission -TaskGraph (Get-OperationObjectProperty $Request 'task_graph') -TaskIds @((Get-OperationObjectProperty $Request 'requested_parallel_task_ids')) -CompletedTaskIds @((Get-OperationObjectProperty $Request 'completed_task_ids')) -CompletedTaskReceipts @((Get-OperationObjectProperty $Request 'completion_receipts')) -EvaluationTime (Get-OperationObjectProperty $Request 'now'))
        )) { foreach ($finding in @($result.findings)) { $findings.Add($finding) | Out-Null } }
    $taskIndex = Get-AgentTaskIndex (Get-OperationObjectProperty $Request 'task_graph')
    $proposalSeen = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    foreach ($proposal in @((Get-OperationObjectProperty $Request 'model_proposals'))) {
        $taskId = ([string](Get-OperationObjectProperty $proposal 'task_id')).Trim()
        if (-not $taskIndex.ContainsKey($taskId.ToLowerInvariant())) { $findings.Add((New-OperationFinding 'model_proposal_task_unknown' 'error' '$.model_proposals.task_id' 'Model proposal task_id must belong to the TaskGraph.')) | Out-Null }
        if (-not $proposalSeen.Add($taskId)) { $findings.Add((New-OperationFinding 'model_proposal_duplicate' 'error' '$.model_proposals.task_id' 'Only one model proposal is allowed per task.')) | Out-Null }
        $rationale = [string](Get-OperationObjectProperty $proposal 'rationale')
        if ([string]::IsNullOrWhiteSpace($rationale)) { $findings.Add((New-OperationFinding 'model_proposal_rationale_required' 'error' '$.model_proposals.rationale' 'Model proposal rationale is required.')) | Out-Null; continue }
        $evaluated = New-ModelPolicyProposal -TaskId $taskId -RequestedTier ([string](Get-OperationObjectProperty $proposal 'requested_tier')) -Rationale $rationale -RadarSnapshot (Get-OperationObjectProperty $Request 'radar_snapshot') -HostSurface ([string](Get-OperationObjectProperty $proposal 'host_surface')) -HostAvailablePairs @((Get-OperationObjectProperty $proposal 'host_available_pairs')) -LocalOutcomes @((Get-OperationObjectProperty $proposal 'local_outcomes')) -Now (Get-OperationObjectProperty $Request 'now') -UserOverrideTier ([string](Get-OperationObjectProperty $proposal 'user_override_tier'))
        if ($evaluated.selected_tier -eq 'host_default') { $findings.Add((New-OperationFinding 'model_proposal_unusable' 'error' '$.model_proposals' ('Model proposal failed closed: {0}' -f $evaluated.fallback_reason))) | Out-Null }
    }
    $failurePacket = Get-OperationObjectProperty $Request 'failure_packet'
    if ($null -ne $failurePacket) { foreach ($finding in @((Test-AgentFailurePacketContract $failurePacket).findings)) { $findings.Add($finding) | Out-Null } }
    return New-OperationValidationResult $findings.ToArray()
}

function New-AgentWorkflowAdvisoryPlan($Request) {
    $requestValidation = Test-AgentWorkflowRequest $Request
    $graph = Get-OperationObjectProperty $Request 'task_graph'
    $proposals = New-Object System.Collections.Generic.List[object]
    foreach ($proposal in @((Get-OperationObjectProperty $Request 'model_proposals'))) {
        $proposals.Add((New-ModelPolicyProposal -TaskId ([string](Get-OperationObjectProperty $proposal 'task_id')) -RequestedTier ([string](Get-OperationObjectProperty $proposal 'requested_tier')) -Rationale ([string](Get-OperationObjectProperty $proposal 'rationale')) -RadarSnapshot (Get-OperationObjectProperty $Request 'radar_snapshot') -HostSurface ([string](Get-OperationObjectProperty $proposal 'host_surface')) -HostAvailablePairs @((Get-OperationObjectProperty $proposal 'host_available_pairs')) -LocalOutcomes @((Get-OperationObjectProperty $proposal 'local_outcomes')) -Now (Get-OperationObjectProperty $Request 'now') -UserOverrideTier ([string](Get-OperationObjectProperty $proposal 'user_override_tier')))) | Out-Null
    }
    return [pscustomobject][ordered]@{
        schema_version = 1; pass = $requestValidation.pass; decision_owner = 'host_ai'; executor = 'host_native_runtime'; advisory_only = $true
        execution_plan = New-AgentExecutionPlan -TaskGraph $graph
        current_parallel_admission = Test-AgentParallelAdmission -TaskGraph $graph -TaskIds @((Get-OperationObjectProperty $Request 'requested_parallel_task_ids')) -CompletedTaskIds @((Get-OperationObjectProperty $Request 'completed_task_ids')) -CompletedTaskReceipts @((Get-OperationObjectProperty $Request 'completion_receipts')) -EvaluationTime (Get-OperationObjectProperty $Request 'now')
        model_proposals = @($proposals.ToArray()); findings = @($requestValidation.findings); provider_calls = 0; native_mutations = 0; writes = 0
    }
}
