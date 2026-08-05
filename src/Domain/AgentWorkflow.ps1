function Copy-AgentWorkflowValue($Value) {
    if ($null -eq $Value) { return $null }
    return (($Value | ConvertTo-Json -Depth 50 -Compress) | ConvertFrom-Json)
}

function New-AgentTaskGraph {
    param(
        [Parameter(Mandatory = $true)][string]$GraphId,
        [Parameter(Mandatory = $true)][string]$BaseRevision,
        [Parameter(Mandatory = $true)][string]$IntegrationOwner,
        [object[]]$Tasks = @()
    )
    $normalizedTasks = @($Tasks | ForEach-Object { Copy-AgentWorkflowValue $_ } | Sort-Object { [int](Get-OperationObjectProperty $_ 'integration_order') }, { [string](Get-OperationObjectProperty $_ 'task_id') })
    return [pscustomobject][ordered]@{
        schema_version = 1
        graph_id = $GraphId.Trim()
        base_revision = $BaseRevision.Trim()
        integration_owner = $IntegrationOwner.Trim()
        tasks = $normalizedTasks
    }
}

function Test-AgentTaskGraphContract($TaskGraph) {
    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $TaskGraph) { return New-OperationValidationResult @((New-OperationFinding 'task_graph_missing' 'error' '$' 'TaskGraph is required.')) }
    if ((Get-OperationObjectProperty $TaskGraph 'schema_version') -ne 1) { $findings.Add((New-OperationFinding 'schema_version_invalid' 'error' '$.schema_version' 'Only TaskGraph schema version 1 is supported.')) | Out-Null }
    foreach ($field in @('graph_id', 'base_revision', 'integration_owner')) {
        if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $TaskGraph $field))) { $findings.Add((New-OperationFinding 'required_field_missing' 'error' ('$.{0}' -f $field) 'Required TaskGraph field is missing.')) | Out-Null }
    }
    $tasks = Get-OperationObjectProperty $TaskGraph 'tasks'
    if (-not (Test-OperationArray $tasks)) { $findings.Add((New-OperationFinding 'tasks_type_invalid' 'error' '$.tasks' 'TaskGraph tasks must be an array.')) | Out-Null; $tasks = @() }
    if (@($tasks).Count -eq 0) { $findings.Add((New-OperationFinding 'tasks_required' 'error' '$.tasks' 'TaskGraph requires at least one task.')) | Out-Null }

    $taskIndex = @{}
    $integrationOrders = @{}
    for ($i = 0; $i -lt @($tasks).Count; $i++) {
        $task = @($tasks)[$i]
        $taskId = ([string](Get-OperationObjectProperty $task 'task_id')).Trim()
        $path = '$.tasks[{0}]' -f $i
        if ([string]::IsNullOrWhiteSpace($taskId) -or $taskId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { $findings.Add((New-OperationFinding 'task_id_invalid' 'error' ($path + '.task_id') 'Task ID is missing or invalid.')) | Out-Null }
        elseif ($taskIndex.ContainsKey($taskId.ToLowerInvariant())) { $findings.Add((New-OperationFinding 'task_id_duplicate' 'error' ($path + '.task_id') 'Task ID is duplicated.')) | Out-Null }
        else { $taskIndex[$taskId.ToLowerInvariant()] = $task }
        foreach ($field in @('goal', 'result_owner', 'stop_condition')) {
            if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $task $field))) { $findings.Add((New-OperationFinding ('{0}_required' -f $field) 'error' ($path + '.' + $field) ('Task {0} is required.' -f $field))) | Out-Null }
        }
        foreach ($field in @('inputs', 'outputs', 'depends_on', 'exact_write_set', 'coordination_keys', 'external_state', 'verification')) {
            if (-not (Test-OperationArray (Get-OperationObjectProperty $task $field))) { $findings.Add((New-OperationFinding 'array_type_invalid' 'error' ($path + '.' + $field) 'Task field must be an array.')) | Out-Null }
        }
        if (@((Get-OperationObjectProperty $task 'verification')).Count -eq 0) { $findings.Add((New-OperationFinding 'verification_required' 'error' ($path + '.verification') 'Every task requires explicit verification.')) | Out-Null }
        if ([string](Get-OperationObjectProperty $task 'risk') -notin @('low', 'medium', 'high')) { $findings.Add((New-OperationFinding 'risk_invalid' 'error' ($path + '.risk') 'Task risk is invalid.')) | Out-Null }
        if ([string](Get-OperationObjectProperty $task 'ambiguity') -notin @('low', 'medium', 'high')) { $findings.Add((New-OperationFinding 'ambiguity_invalid' 'error' ($path + '.ambiguity') 'Task ambiguity is invalid.')) | Out-Null }
        if ((Get-OperationObjectProperty $task 'parallelizable') -isnot [bool]) { $findings.Add((New-OperationFinding 'parallelizable_invalid' 'error' ($path + '.parallelizable') 'parallelizable must be a boolean.')) | Out-Null }
        $order = Get-OperationObjectProperty $task 'integration_order'
        $parsedOrder = 0
        if ($null -eq $order -or -not [int]::TryParse([string]$order, [ref]$parsedOrder) -or $parsedOrder -lt 1) { $findings.Add((New-OperationFinding 'integration_order_invalid' 'error' ($path + '.integration_order') 'integration_order must be a positive integer.')) | Out-Null }
        elseif ($integrationOrders.ContainsKey($parsedOrder)) { $findings.Add((New-OperationFinding 'integration_order_duplicate' 'error' ($path + '.integration_order') 'integration_order must be unique.')) | Out-Null }
        else { $integrationOrders[$parsedOrder] = $taskId }
        foreach ($writePath in @((Get-OperationObjectProperty $task 'exact_write_set'))) {
            if ([string]::IsNullOrWhiteSpace([string]$writePath) -or [string]$writePath -match '[*?\[\]]') { $findings.Add((New-OperationFinding 'write_set_not_exact' 'error' ($path + '.exact_write_set') 'Write-set entries must be non-empty exact paths without wildcards.')) | Out-Null }
        }
        foreach ($key in @((Get-OperationObjectProperty $task 'coordination_keys'))) {
            if ([string]$key -notmatch '^(read|write):.+$') { $findings.Add((New-OperationFinding 'coordination_key_invalid' 'error' ($path + '.coordination_keys') 'Coordination keys must use read:<resource> or write:<resource>.')) | Out-Null }
        }
        foreach ($state in @((Get-OperationObjectProperty $task 'external_state'))) {
            if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $state 'resource')) -or [string](Get-OperationObjectProperty $state 'mode') -notin @('read', 'write')) { $findings.Add((New-OperationFinding 'external_state_invalid' 'error' ($path + '.external_state') 'External state requires resource and read/write mode.')) | Out-Null }
        }
    }

    foreach ($taskKey in @($taskIndex.Keys)) {
        $task = $taskIndex[$taskKey]
        foreach ($dependency in @((Get-OperationObjectProperty $task 'depends_on'))) {
            $dependencyId = ([string]$dependency).Trim().ToLowerInvariant()
            if (-not $taskIndex.ContainsKey($dependencyId)) { $findings.Add((New-OperationFinding 'dependency_unknown' 'error' ('$.tasks[{0}].depends_on' -f [string](Get-OperationObjectProperty $task 'task_id')) 'Task dependency is not declared.')) | Out-Null }
            elseif ($dependencyId -eq $taskKey) { $findings.Add((New-OperationFinding 'dependency_self_reference' 'error' ('$.tasks[{0}].depends_on' -f [string](Get-OperationObjectProperty $task 'task_id')) 'Task cannot depend on itself.')) | Out-Null }
        }
    }

    if ($taskIndex.Count -gt 0) {
        $inDegree = @{}
        $dependents = @{}
        foreach ($taskKey in @($taskIndex.Keys)) { $inDegree[$taskKey] = 0; $dependents[$taskKey] = New-Object System.Collections.Generic.List[string] }
        foreach ($taskKey in @($taskIndex.Keys)) {
            foreach ($dependency in @((Get-OperationObjectProperty $taskIndex[$taskKey] 'depends_on'))) {
                $dependencyId = ([string]$dependency).Trim().ToLowerInvariant()
                if (-not $taskIndex.ContainsKey($dependencyId) -or $dependencyId -eq $taskKey) { continue }
                $inDegree[$taskKey] = [int]$inDegree[$taskKey] + 1
                $dependents[$dependencyId].Add($taskKey) | Out-Null
            }
        }
        $queue = New-Object System.Collections.Generic.Queue[string]
        foreach ($taskKey in @($inDegree.Keys | Where-Object { $inDegree[$_] -eq 0 } | Sort-Object)) { $queue.Enqueue($taskKey) }
        $visited = 0
        while ($queue.Count -gt 0) {
            $current = $queue.Dequeue(); $visited++
            foreach ($dependent in @($dependents[$current] | Sort-Object)) { $inDegree[$dependent] = [int]$inDegree[$dependent] - 1; if ($inDegree[$dependent] -eq 0) { $queue.Enqueue($dependent) } }
        }
        if ($visited -ne $taskIndex.Count) { $findings.Add((New-OperationFinding 'task_graph_cycle' 'error' '$.tasks' 'TaskGraph contains a dependency cycle.')) | Out-Null }
    }
    return New-OperationValidationResult $findings.ToArray()
}

function New-RadarSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$SnapshotId,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$CapturedAt,
        [Parameter(Mandatory = $true)][string]$ExpiresAt,
        [Parameter(Mandatory = $true)][string]$RawHash,
        [object[]]$Entries = @()
    )
    return [pscustomobject][ordered]@{
        schema_version = 1
        snapshot_id = $SnapshotId.Trim()
        source = $Source.Trim()
        captured_at = $CapturedAt
        expires_at = $ExpiresAt
        raw_hash = $RawHash.ToLowerInvariant()
        entries = @($Entries | ForEach-Object { Copy-AgentWorkflowValue $_ } | Sort-Object model_family, reasoning_effort)
    }
}

function Test-RadarSnapshotContract {
    param($Snapshot, [string]$Now)
    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Snapshot) { return New-OperationValidationResult @((New-OperationFinding 'radar_snapshot_missing' 'error' '$' 'Radar snapshot is required.')) }
    if ((Get-OperationObjectProperty $Snapshot 'schema_version') -ne 1) { $findings.Add((New-OperationFinding 'schema_version_invalid' 'error' '$.schema_version' 'Only Radar snapshot schema version 1 is supported.')) | Out-Null }
    foreach ($field in @('snapshot_id', 'source', 'captured_at', 'expires_at', 'raw_hash')) { if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $Snapshot $field))) { $findings.Add((New-OperationFinding 'required_field_missing' 'error' ('$.{0}' -f $field) 'Required Radar snapshot field is missing.')) | Out-Null } }
    $sourceUri = $null
    if (-not [uri]::TryCreate([string](Get-OperationObjectProperty $Snapshot 'source'), [UriKind]::Absolute, [ref]$sourceUri) -or $sourceUri.Scheme -notin @('http', 'https')) { $findings.Add((New-OperationFinding 'radar_source_invalid' 'error' '$.source' 'Radar source must be an absolute HTTP(S) URI.')) | Out-Null }
    if ([string](Get-OperationObjectProperty $Snapshot 'raw_hash') -notmatch '^[a-fA-F0-9]{64}$') { $findings.Add((New-OperationFinding 'radar_raw_hash_invalid' 'error' '$.raw_hash' 'Radar raw_hash must be SHA-256.')) | Out-Null }
    $captured = [datetimeoffset]::MinValue; $expires = [datetimeoffset]::MinValue; $nowValue = [datetimeoffset]::MinValue
    $capturedValid = [datetimeoffset]::TryParse([string](Get-OperationObjectProperty $Snapshot 'captured_at'), [ref]$captured)
    $expiresValid = [datetimeoffset]::TryParse([string](Get-OperationObjectProperty $Snapshot 'expires_at'), [ref]$expires)
    if (-not $capturedValid) { $findings.Add((New-OperationFinding 'radar_captured_at_invalid' 'error' '$.captured_at' 'captured_at must be ISO-8601.')) | Out-Null }
    if (-not $expiresValid) { $findings.Add((New-OperationFinding 'radar_expires_at_invalid' 'error' '$.expires_at' 'expires_at must be ISO-8601.')) | Out-Null }
    if ($capturedValid -and $expiresValid -and $expires -le $captured) { $findings.Add((New-OperationFinding 'radar_expiry_invalid' 'error' '$.expires_at' 'expires_at must be later than captured_at.')) | Out-Null }
    if (-not [string]::IsNullOrWhiteSpace($Now)) {
        if (-not [datetimeoffset]::TryParse($Now, [ref]$nowValue)) { $findings.Add((New-OperationFinding 'evaluation_time_invalid' 'error' '$.now' 'Evaluation time must be ISO-8601.')) | Out-Null }
        elseif ($expiresValid -and $nowValue -ge $expires) { $findings.Add((New-OperationFinding 'radar_snapshot_stale' 'error' '$.expires_at' 'Radar snapshot is expired and cannot drive a model proposal.')) | Out-Null }
    }
    $entries = Get-OperationObjectProperty $Snapshot 'entries'
    if (-not (Test-OperationArray $entries)) { $findings.Add((New-OperationFinding 'radar_entries_invalid' 'error' '$.entries' 'Radar entries must be an array.')) | Out-Null; $entries = @() }
    for ($i = 0; $i -lt @($entries).Count; $i++) {
        $entry = @($entries)[$i]; $path = '$.entries[{0}]' -f $i
        foreach ($field in @('model_label', 'model_family', 'reasoning_effort', 'confidence')) { if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $entry $field))) { $findings.Add((New-OperationFinding 'radar_entry_field_missing' 'error' ($path + '.' + $field) 'Radar entry field is required.')) | Out-Null } }
        if ([string](Get-OperationObjectProperty $entry 'reasoning_effort') -notin @('low', 'medium', 'high', 'xhigh', 'max', 'ultra')) { $findings.Add((New-OperationFinding 'reasoning_effort_invalid' 'error' ($path + '.reasoning_effort') 'Radar reasoning effort is invalid.')) | Out-Null }
        foreach ($field in @('score', 'estimated_cost', 'estimated_duration_seconds', 'sample_count')) { $number = 0.0; if (-not [double]::TryParse([string](Get-OperationObjectProperty $entry $field), [ref]$number) -or $number -lt 0) { $findings.Add((New-OperationFinding 'radar_metric_invalid' 'error' ($path + '.' + $field) 'Radar metric must be a non-negative number.')) | Out-Null } }
    }
    return New-OperationValidationResult $findings.ToArray()
}

function New-AgentFailurePacket {
    param(
        [Parameter(Mandatory = $true)][string]$IssueId,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)][string]$BaseRevision,
        [Parameter(Mandatory = $true)][ValidateSet('task', 'context', 'tool', 'capacity', 'permission', 'credential', 'production_authorization', 'user_decision', 'unknown')][string]$FailureKind,
        [Parameter(Mandatory = $true)][int]$AttemptCount,
        [int]$EscalationCount = 0,
        [Parameter(Mandatory = $true)][string]$AttemptedTier,
        [string]$AttemptedModel,
        [string]$AttemptedEffort,
        [string[]]$Commands = @(), [string[]]$Failures = @(), [string[]]$VerifiedFacts = @(), [string[]]$UnresolvedQuestions = @(), [string[]]$Artifacts = @(), [string[]]$ExactWriteSet = @(),
        [string]$CorrectionSummary, [string]$NextRecommendation
    )
    return [pscustomobject][ordered]@{
        schema_version = 1; issue_id = $IssueId.Trim(); task_id = $TaskId.Trim(); base_revision = $BaseRevision.Trim(); failure_kind = $FailureKind
        attempt_count = $AttemptCount; escalation_count = $EscalationCount; attempted_tier = $AttemptedTier; attempted_model = $AttemptedModel; attempted_effort = $AttemptedEffort
        commands = @($Commands); failures = @($Failures); verified_facts = @($VerifiedFacts); unresolved_questions = @($UnresolvedQuestions); artifacts = @($Artifacts); exact_write_set = @($ExactWriteSet)
        correction_summary = $CorrectionSummary; next_recommendation = $NextRecommendation
    }
}

function Test-AgentFailurePacketContract($FailurePacket) {
    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $FailurePacket) { return New-OperationValidationResult @((New-OperationFinding 'failure_packet_missing' 'error' '$' 'FailurePacket is required before retry or escalation.')) }
    if ((Get-OperationObjectProperty $FailurePacket 'schema_version') -ne 1) { $findings.Add((New-OperationFinding 'schema_version_invalid' 'error' '$.schema_version' 'Only FailurePacket schema version 1 is supported.')) | Out-Null }
    foreach ($field in @('issue_id', 'task_id', 'base_revision', 'failure_kind', 'attempted_tier')) { if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $FailurePacket $field))) { $findings.Add((New-OperationFinding 'required_field_missing' 'error' ('$.{0}' -f $field) 'FailurePacket field is required.')) | Out-Null } }
    if ([string](Get-OperationObjectProperty $FailurePacket 'failure_kind') -notin @('task', 'context', 'tool', 'capacity', 'permission', 'credential', 'production_authorization', 'user_decision', 'unknown')) { $findings.Add((New-OperationFinding 'failure_kind_invalid' 'error' '$.failure_kind' 'Failure kind is invalid.')) | Out-Null }
    $attemptCount = 0; $escalationCount = 0
    if (-not [int]::TryParse([string](Get-OperationObjectProperty $FailurePacket 'attempt_count'), [ref]$attemptCount) -or $attemptCount -lt 1) { $findings.Add((New-OperationFinding 'attempt_count_invalid' 'error' '$.attempt_count' 'attempt_count must be at least one.')) | Out-Null }
    if (-not [int]::TryParse([string](Get-OperationObjectProperty $FailurePacket 'escalation_count'), [ref]$escalationCount) -or $escalationCount -lt 0) { $findings.Add((New-OperationFinding 'escalation_count_invalid' 'error' '$.escalation_count' 'escalation_count must be non-negative.')) | Out-Null }
    foreach ($field in @('commands', 'failures', 'verified_facts', 'unresolved_questions', 'artifacts', 'exact_write_set')) { if (-not (Test-OperationArray (Get-OperationObjectProperty $FailurePacket $field))) { $findings.Add((New-OperationFinding 'array_type_invalid' 'error' ('$.{0}' -f $field) 'FailurePacket field must be an array.')) | Out-Null } }
    if (@((Get-OperationObjectProperty $FailurePacket 'failures')).Count -eq 0) { $findings.Add((New-OperationFinding 'failures_required' 'error' '$.failures' 'FailurePacket must contain at least one observed failure.')) | Out-Null }
    $serialized = $FailurePacket | ConvertTo-Json -Depth 20 -Compress
    if (Test-OperationSerializedSensitiveValue $serialized) { $findings.Add((New-OperationFinding 'sensitive_value_present' 'error' '$' 'FailurePacket contains a sensitive value.')) | Out-Null }
    return New-OperationValidationResult $findings.ToArray()
}
