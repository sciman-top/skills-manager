function Get-AgentTaskIndex($TaskGraph) {
    $index = @{}
    foreach ($task in @((Get-OperationObjectProperty $TaskGraph 'tasks'))) {
        $taskId = Get-AgentCanonicalTaskId ([string](Get-OperationObjectProperty $task 'task_id'))
        if ($null -ne $taskId) { $index[$taskId] = $task }
    }
    return $index
}

function Get-AgentTaskExecutionMode($Task) {
    $mode = [string](Get-OperationObjectProperty $Task 'execution_mode')
    if ($mode -eq 'delegate') { return 'delegate' }
    return 'root'
}

function Get-AgentProposalIndex([object[]]$ModelProposals = @()) {
    $index = @{}
    foreach ($proposal in @($ModelProposals)) {
        $taskId = Get-AgentCanonicalTaskId ([string](Get-OperationObjectProperty $proposal 'task_id'))
        if ($null -ne $taskId -and -not $index.ContainsKey($taskId)) { $index[$taskId] = $proposal }
    }
    return $index
}

function Get-AgentProposalAnchor($Proposal) {
    if ($null -eq $Proposal) { return $null }
    $overrideTier = [string](Get-OperationObjectProperty $Proposal 'user_override_tier')
    $tier = if ([string]::IsNullOrWhiteSpace($overrideTier)) { [string](Get-OperationObjectProperty $Proposal 'requested_tier') } else { $overrideTier }
    return Get-AgentModelTierAnchor $tier
}

function Get-AgentExpectedTypeForEffort([string]$Effort) {
    switch ($Effort.ToLowerInvariant()) {
        'low' { return 'sol_low_worker' }
        'medium' { return 'sol_medium_worker' }
        'xhigh' { return 'sol_xhigh_supervisor' }
        default { return $null }
    }
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

function Test-AgentExecutionReceipt {
    param($Receipt, $EvaluationTime, [string]$ExpectedModelFamily, [string]$ExpectedReasoningEffort)

    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Receipt -or $Receipt -is [string]) { return New-OperationValidationResult @((New-OperationFinding 'execution_receipt_invalid' 'error' '$.completion_receipts.execution_receipt' 'Delegated completion requires a structured execution receipt.')) }
    $agentType = ([string](Get-OperationObjectProperty $Receipt 'agent_type')).Trim().ToLowerInvariant()
    $modelFamily = ([string](Get-OperationObjectProperty $Receipt 'model_family')).Trim().ToLowerInvariant()
    $effort = ([string](Get-OperationObjectProperty $Receipt 'reasoning_effort')).Trim().ToLowerInvariant()
    $expectedType = Get-AgentExpectedTypeForEffort $effort
    if ($agentType -notmatch '^sol_(low_worker|medium_worker|xhigh_supervisor)$' -or $null -eq $expectedType) { $findings.Add((New-OperationFinding 'execution_receipt_agent_type_invalid' 'error' '$.completion_receipts.execution_receipt.agent_type' 'Execution receipt must name one of the governed three-tier custom agents.')) | Out-Null }
    elseif ($agentType -cne $expectedType) { $findings.Add((New-OperationFinding 'execution_receipt_agent_pair_mismatch' 'error' '$.completion_receipts.execution_receipt' 'Execution agent type must match its recorded reasoning effort.')) | Out-Null }
    if ($modelFamily -cne 'gpt-5.6-sol' -or $effort -notin @('low', 'medium', 'xhigh')) { $findings.Add((New-OperationFinding 'execution_receipt_model_pair_invalid' 'error' '$.completion_receipts.execution_receipt' 'Execution receipt must use one of the governed GPT-5.6-Sol model pairs.')) | Out-Null }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedModelFamily) -and ($modelFamily -cne $ExpectedModelFamily.Trim().ToLowerInvariant() -or $effort -cne $ExpectedReasoningEffort.Trim().ToLowerInvariant())) { $findings.Add((New-OperationFinding 'execution_receipt_proposal_mismatch' 'error' '$.completion_receipts.execution_receipt' 'Actual execution model and effort must match the accepted model proposal.')) | Out-Null }

    $startedAt = ConvertTo-AgentWorkflowRfc3339Value (Get-OperationObjectProperty $Receipt 'started_at')
    $endedAt = ConvertTo-AgentWorkflowRfc3339Value (Get-OperationObjectProperty $Receipt 'ended_at')
    $evaluatedAt = ConvertTo-AgentWorkflowRfc3339Value $EvaluationTime
    if ($null -eq $startedAt -or $null -eq $endedAt -or $null -eq $evaluatedAt -or $endedAt -lt $startedAt -or $endedAt -gt $evaluatedAt.AddMinutes(5)) { $findings.Add((New-OperationFinding 'execution_receipt_time_invalid' 'error' '$.completion_receipts.execution_receipt' 'Execution receipt times must be ordered RFC3339 values bounded by the request evaluation time.')) | Out-Null }
    if ([string](Get-OperationObjectProperty $Receipt 'terminal_state') -cne 'completed') { $findings.Add((New-OperationFinding 'execution_receipt_terminal_state_invalid' 'error' '$.completion_receipts.execution_receipt.terminal_state' 'Verified delegated completion requires terminal_state=completed.')) | Out-Null }

    $usage = Get-OperationObjectProperty $Receipt 'token_usage'
    $parsedUsage = @{}
    if ($null -eq $usage -or $usage -is [string]) { $findings.Add((New-OperationFinding 'execution_receipt_token_usage_invalid' 'error' '$.completion_receipts.execution_receipt.token_usage' 'Token usage must be a structured observational receipt.')) | Out-Null }
    else {
        foreach ($field in @('input_tokens', 'output_tokens', 'total_tokens')) {
            $value = 0L
            if (-not [long]::TryParse([string](Get-OperationObjectProperty $usage $field), [ref]$value) -or $value -lt 0) { $findings.Add((New-OperationFinding 'execution_receipt_token_usage_invalid' 'error' ('$.completion_receipts.execution_receipt.token_usage.{0}' -f $field) 'Token usage fields must be non-negative integers.')) | Out-Null }
            else { $parsedUsage[$field] = $value }
        }
        if ($parsedUsage.Count -eq 3 -and $parsedUsage.total_tokens -ne ($parsedUsage.input_tokens + $parsedUsage.output_tokens)) { $findings.Add((New-OperationFinding 'execution_receipt_token_total_mismatch' 'error' '$.completion_receipts.execution_receipt.token_usage.total_tokens' 'total_tokens must equal input_tokens plus output_tokens.')) | Out-Null }
    }
    if (Test-OperationSerializedSensitiveValue ($Receipt | ConvertTo-Json -Depth 20 -Compress)) { $findings.Add((New-OperationFinding 'sensitive_value_present' 'error' '$.completion_receipts.execution_receipt' 'Execution receipt contains a sensitive value.')) | Out-Null }
    return New-OperationValidationResult $findings.ToArray()
}

function Test-AgentParallelAdmission {
    param($TaskGraph, [string[]]$TaskIds = @(), [string[]]$CompletedTaskIds = @(), [object[]]$CompletedTaskReceipts = @(), [object[]]$ModelProposals = @(), $EvaluationTime, [switch]$PlanningOnly)
    $findings = New-Object System.Collections.Generic.List[object]
    $graphValidation = Test-AgentTaskGraphContract $TaskGraph
    foreach ($finding in @($graphValidation.findings)) { $findings.Add($finding) | Out-Null }
    $taskIndex = Get-AgentTaskIndex $TaskGraph
    $proposalIndex = Get-AgentProposalIndex $ModelProposals
    $completed = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    foreach ($taskId in @($CompletedTaskIds)) {
        $completedId = Get-AgentCanonicalTaskId ([string]$taskId)
        if ($null -eq $completedId) { $findings.Add((New-OperationFinding 'completed_task_id_not_canonical' 'error' '$.completed_task_ids' 'Completed task IDs must be canonical.')) | Out-Null; continue }
        if (-not $completed.Add($completedId)) { $findings.Add((New-OperationFinding 'completed_task_duplicate' 'error' '$.completed_task_ids' 'Completed task ID is duplicated.')) | Out-Null }
        if (-not $taskIndex.ContainsKey($completedId)) { $findings.Add((New-OperationFinding 'completed_task_unknown' 'error' '$.completed_task_ids' 'Completed task is not declared in this TaskGraph.')) | Out-Null }
    }
    $receiptIndex = @{}
    if (-not $PlanningOnly) {
        $receiptEvaluationTime = $null
        if (@($CompletedTaskReceipts).Count -gt 0) {
            $receiptEvaluationTime = ConvertTo-AgentWorkflowRfc3339Value $EvaluationTime
            if ($null -eq $receiptEvaluationTime) { $findings.Add((New-OperationFinding 'completion_evaluation_time_invalid' 'error' '$.now' 'Completion receipt validation requires an explicit RFC3339 evaluation time.')) | Out-Null }
        }
        foreach ($receipt in @($CompletedTaskReceipts)) {
            $receiptTaskId = [string](Get-OperationObjectProperty $receipt 'task_id')
            $receiptKey = Get-AgentCanonicalTaskId $receiptTaskId
            if ($null -eq $receiptKey -or -not $taskIndex.ContainsKey($receiptKey)) { $findings.Add((New-OperationFinding 'completion_receipt_task_invalid' 'error' '$.completion_receipts' 'Completion receipt task_id must be canonical and belong to the TaskGraph.')) | Out-Null; continue }
            if ($receiptIndex.ContainsKey($receiptKey)) { $findings.Add((New-OperationFinding 'completion_receipt_duplicate' 'error' '$.completion_receipts' 'Completion receipt is duplicated.')) | Out-Null; continue }
            $receiptIndex[$receiptKey] = $receipt
            if ([string](Get-OperationObjectProperty $receipt 'base_revision') -cne [string](Get-OperationObjectProperty $TaskGraph 'base_revision')) { $findings.Add((New-OperationFinding 'completion_receipt_revision_mismatch' 'error' '$.completion_receipts' 'Completion receipt base_revision does not match the TaskGraph.')) | Out-Null }
            if ([string](Get-OperationObjectProperty $receipt 'status') -cne 'verified') { $findings.Add((New-OperationFinding 'completion_receipt_unverified' 'error' '$.completion_receipts' 'Completion receipt status must be verified.')) | Out-Null }
            $evidence = Get-OperationObjectProperty $receipt 'verification_receipt'
            if ($null -eq $evidence) { $findings.Add((New-OperationFinding 'completion_receipt_evidence_missing' 'error' '$.completion_receipts' 'Completion receipt requires verification evidence.')) | Out-Null }
            elseif (-not (Test-AgentCompletionVerificationReceipt -Evidence $evidence -EvaluationTime $receiptEvaluationTime)) { $findings.Add((New-OperationFinding 'completion_receipt_evidence_invalid' 'error' '$.completion_receipts' 'Completion verification evidence must be a structured, hashed, command-backed receipt evaluated against the request time.')) | Out-Null }
            if ((Get-AgentTaskExecutionMode $taskIndex[$receiptKey]) -eq 'delegate') {
                $executionReceipt = Get-OperationObjectProperty $receipt 'execution_receipt'
                if ($null -eq $executionReceipt) { $findings.Add((New-OperationFinding 'execution_receipt_missing' 'error' '$.completion_receipts.execution_receipt' 'Delegated completion requires an execution receipt.')) | Out-Null }
                else { foreach ($finding in @((Test-AgentExecutionReceipt -Receipt $executionReceipt -EvaluationTime $receiptEvaluationTime).findings)) { $findings.Add($finding) | Out-Null } }
            }
        }
        foreach ($completedId in @($completed)) { if (-not $receiptIndex.ContainsKey($completedId)) { $findings.Add((New-OperationFinding 'completion_receipt_missing' 'error' '$.completion_receipts' ('Verified completion receipt is missing for task: {0}' -f $completedId))) | Out-Null } }
        foreach ($receiptTaskId in @($receiptIndex.Keys)) { if (-not $completed.Contains($receiptTaskId)) { $findings.Add((New-OperationFinding 'completion_receipt_unclaimed' 'error' '$.completion_receipts' ('Completion receipt is not declared in completed_task_ids: {0}' -f $receiptTaskId))) | Out-Null } }
    }
    foreach ($completedId in @($completed)) {
        $completedKey = $completedId
        if (-not $taskIndex.ContainsKey($completedKey)) { continue }
        foreach ($dependency in @((Get-OperationObjectProperty $taskIndex[$completedKey] 'depends_on'))) {
            $dependencyId = Get-AgentCanonicalTaskId ([string]$dependency)
            if ($null -ne $dependencyId -and -not $completed.Contains($dependencyId)) { $findings.Add((New-OperationFinding 'completed_dependency_not_closed' 'error' '$.completed_task_ids' ('Completed task dependency is not also completed: {0} -> {1}' -f $completedId, [string]$dependency))) | Out-Null }
        }
    }
    $selected = New-Object System.Collections.Generic.List[object]
    $seen = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    foreach ($taskId in @($TaskIds)) {
        $key = Get-AgentCanonicalTaskId ([string]$taskId)
        if ($null -eq $key) { $findings.Add((New-OperationFinding 'parallel_task_id_not_canonical' 'error' '$.requested_parallel_task_ids' 'Parallel task IDs must be canonical.')) | Out-Null; continue }
        if (-not $seen.Add($key)) { $findings.Add((New-OperationFinding 'parallel_task_duplicate' 'error' '$.requested_parallel_task_ids' 'Parallel task ID is duplicated.')) | Out-Null; continue }
        if (-not $taskIndex.ContainsKey($key)) { $findings.Add((New-OperationFinding 'parallel_task_unknown' 'error' '$.requested_parallel_task_ids' 'Parallel task is not declared.')) | Out-Null; continue }
        $task = $taskIndex[$key]; $selected.Add($task) | Out-Null
        if ($completed.Contains($key)) { $findings.Add((New-OperationFinding 'selected_task_already_completed' 'error' '$.requested_parallel_task_ids' 'A task cannot be selected and completed in the same admission request.')) | Out-Null }
        if ((Get-AgentTaskExecutionMode $task) -ne 'delegate') { $findings.Add((New-OperationFinding 'parallel_task_not_delegated' 'error' ('$.tasks[{0}].execution_mode' -f $taskId) 'Only delegated tasks may enter a spawned-agent parallel batch.')) | Out-Null }
        if (-not [bool](Get-OperationObjectProperty $task 'parallelizable')) { $findings.Add((New-OperationFinding 'task_not_parallelizable' 'error' ('$.tasks[{0}]' -f $taskId) 'Task is explicitly serial.')) | Out-Null }
        if ([string](Get-OperationObjectProperty $task 'risk') -eq 'high') { $findings.Add((New-OperationFinding 'high_risk_parallel_forbidden' 'error' ('$.tasks[{0}].risk' -f $taskId) 'High-risk work requires supervisor-owned serial execution.')) | Out-Null }
        if ([string](Get-OperationObjectProperty $task 'ambiguity') -eq 'high') { $findings.Add((New-OperationFinding 'high_ambiguity_parallel_forbidden' 'error' ('$.tasks[{0}].ambiguity' -f $taskId) 'Highly ambiguous work requires clarification before parallel execution.')) | Out-Null }
        foreach ($dependency in @((Get-OperationObjectProperty $task 'depends_on'))) { $dependencyId = Get-AgentCanonicalTaskId ([string]$dependency); if ($null -ne $dependencyId -and -not $completed.Contains($dependencyId)) { $findings.Add((New-OperationFinding 'dependency_not_completed' 'error' ('$.tasks[{0}].depends_on' -f $taskId) 'Dependency is not completed.')) | Out-Null } }
        if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $task 'result_owner'))) { $findings.Add((New-OperationFinding 'result_owner_required' 'error' ('$.tasks[{0}].result_owner' -f $taskId) 'Parallel tasks require a result owner.')) | Out-Null }
        if (@((Get-OperationObjectProperty $task 'verification')).Count -eq 0) { $findings.Add((New-OperationFinding 'verification_required' 'error' ('$.tasks[{0}].verification' -f $taskId) 'Parallel tasks require independent verification.')) | Out-Null }
    }
    if ($selected.Count -eq 1) { $findings.Add((New-OperationFinding 'parallel_batch_too_small' 'error' '$.requested_parallel_task_ids' 'Parallel admission requires at least two tasks.')) | Out-Null }
    if ($selected.Count -gt 2) { $findings.Add((New-OperationFinding 'parallel_batch_too_large' 'error' '$.requested_parallel_task_ids' 'A delegated wave may contain at most two tasks.')) | Out-Null }
    $xhighCount = @($selected.ToArray() | Where-Object {
            $taskKey = Get-AgentCanonicalTaskId ([string](Get-OperationObjectProperty $_ 'task_id'))
            $proposalIndex.ContainsKey($taskKey) -and (Get-AgentProposalAnchor $proposalIndex[$taskKey]).reasoning_effort -eq 'xhigh'
        }).Count
    if ($xhighCount -gt 1) { $findings.Add((New-OperationFinding 'xhigh_parallel_limit_exceeded' 'error' '$.model_proposals' 'A parallel wave may contain at most one Sol xhigh delegate.')) | Out-Null }
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
    param($TaskGraph, [object[]]$ModelProposals = @())
    $validation = Test-AgentTaskGraphContract $TaskGraph
    $limits = [pscustomobject][ordered]@{ max_parallel = 2; max_delegations = 4; max_xhigh_per_wave = 1 }
    if (-not $validation.pass) { return [pscustomobject][ordered]@{ schema_version = 1; pass = $false; decision_owner = 'host_ai'; executor = 'host_native_runtime'; limits = $limits; waves = @(); findings = @($validation.findings); provider_calls = 0; native_mutations = 0; writes = 0 } }
    $taskIndex = Get-AgentTaskIndex $TaskGraph
    $delegatedCount = @($taskIndex.Values | Where-Object { (Get-AgentTaskExecutionMode $_) -eq 'delegate' }).Count
    if ($delegatedCount -gt $limits.max_delegations) {
        $finding = New-OperationFinding 'delegation_budget_exceeded' 'error' '$.task_graph.tasks' 'A task graph may delegate at most four tasks across all waves.'
        return [pscustomobject][ordered]@{ schema_version = 1; pass = $false; decision_owner = 'host_ai'; executor = 'host_native_runtime'; limits = $limits; waves = @(); findings = @($finding); provider_calls = 0; native_mutations = 0; writes = 0 }
    }
    $remaining = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    foreach ($taskId in @($taskIndex.Keys)) { $remaining.Add($taskId) | Out-Null }
    $completed = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    $waves = New-Object System.Collections.Generic.List[object]
    $waveNumber = 0
    while ($remaining.Count -gt 0) {
        $ready = @($remaining | Where-Object { $task = $taskIndex[$_]; @((Get-OperationObjectProperty $task 'depends_on') | Where-Object { $dependencyId = Get-AgentCanonicalTaskId ([string]$_); $null -eq $dependencyId -or -not $completed.Contains($dependencyId) }).Count -eq 0 } | ForEach-Object { $taskIndex[$_] } | Sort-Object { [int](Get-OperationObjectProperty $_ 'integration_order') }, { [string](Get-OperationObjectProperty $_ 'task_id') })
        if ($ready.Count -eq 0) { break }
        $waveNumber++
        $mustRunSerial = @($ready | Where-Object { (Get-AgentTaskExecutionMode $_) -ne 'delegate' -or -not [bool](Get-OperationObjectProperty $_ 'parallelizable') -or [string](Get-OperationObjectProperty $_ 'risk') -eq 'high' -or [string](Get-OperationObjectProperty $_ 'ambiguity') -eq 'high' } | Select-Object -First 1)
        $selectedTasks = New-Object System.Collections.Generic.List[object]
        if ($mustRunSerial.Count -gt 0) { $selectedTasks.Add($mustRunSerial[0]) | Out-Null }
        else {
            foreach ($task in @($ready)) {
                if ($selectedTasks.Count -eq 0) { $selectedTasks.Add($task) | Out-Null; continue }
                if ($selectedTasks.Count -ge $limits.max_parallel) { continue }
                $candidateIds = @($selectedTasks.ToArray() | ForEach-Object { [string](Get-OperationObjectProperty $_ 'task_id') }) + [string](Get-OperationObjectProperty $task 'task_id')
                if ((Test-AgentParallelAdmission -TaskGraph $TaskGraph -TaskIds $candidateIds -CompletedTaskIds @($completed) -ModelProposals $ModelProposals -PlanningOnly).pass) { $selectedTasks.Add($task) | Out-Null }
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
        foreach ($taskId in @($selectedIds)) {
            $canonicalId = Get-AgentCanonicalTaskId $taskId
            $remaining.Remove($canonicalId) | Out-Null
            $completed.Add($canonicalId) | Out-Null
        }
    }
    return [pscustomobject][ordered]@{ schema_version = 1; pass = ($remaining.Count -eq 0); decision_owner = 'host_ai'; executor = 'host_native_runtime'; limits = $limits; waves = @($waves.ToArray()); findings = @(); provider_calls = 0; native_mutations = 0; writes = 0 }
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
    $normalizedHostPairs = @($HostAvailablePairs | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (-not $hostSurfaceKnown) { $fallbackReasons.Add('host_surface_unknown') | Out-Null }
    if ($null -ne $anchor) {
        $pair = ('{0}|{1}' -f $anchor.model_family, $anchor.reasoning_effort).ToLowerInvariant()
        if ($hostSurfaceKnown -and @($normalizedHostPairs).Count -eq 0) {
            $fallbackReasons.Add('host_pair_availability_unknown') | Out-Null
        }
        elseif ($hostSurfaceKnown -and $pair -in @($normalizedHostPairs)) {
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
        evidence_sources = [pscustomobject][ordered]@{ local = [pscustomobject]@{ valid = $hasLocal; supplied = @($LocalOutcomes).Count; accepted = $validLocalOutcomes.Count; rejected_findings = @($localFindings.ToArray()) }; host_availability = [pscustomobject]@{ surface = $(if ($hostSurfaceKnown) { $HostSurface } else { $null }); state = $hostAvailabilityState; declared = ($hostSurfaceKnown -and @($normalizedHostPairs).Count -gt 0); pair_confirmed = $hostConfirmed } }
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
    $taskGraph = Get-OperationObjectProperty $Request 'task_graph'
    $modelProposals = @((Get-OperationObjectProperty $Request 'model_proposals'))
    foreach ($result in @(
            (Test-AgentTaskGraphContract $taskGraph),
            (New-AgentExecutionPlan -TaskGraph $taskGraph -ModelProposals $modelProposals),
            (Test-AgentParallelAdmission -TaskGraph $taskGraph -TaskIds @((Get-OperationObjectProperty $Request 'requested_parallel_task_ids')) -CompletedTaskIds @((Get-OperationObjectProperty $Request 'completed_task_ids')) -CompletedTaskReceipts @((Get-OperationObjectProperty $Request 'completion_receipts')) -ModelProposals $modelProposals -EvaluationTime (Get-OperationObjectProperty $Request 'now'))
        )) { foreach ($finding in @($result.findings)) { $findings.Add($finding) | Out-Null } }
    $taskIndex = Get-AgentTaskIndex $taskGraph
    $proposalSeen = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    $evaluatedProposalIndex = @{}
    foreach ($proposal in @($modelProposals)) {
        $taskId = Get-AgentCanonicalTaskId ([string](Get-OperationObjectProperty $proposal 'task_id'))
        if ($null -eq $taskId -or -not $taskIndex.ContainsKey($taskId)) { $findings.Add((New-OperationFinding 'model_proposal_task_unknown' 'error' '$.model_proposals.task_id' 'Model proposal task_id must be canonical and belong to the TaskGraph.')) | Out-Null }
        if ($null -ne $taskId -and -not $proposalSeen.Add($taskId)) { $findings.Add((New-OperationFinding 'model_proposal_duplicate' 'error' '$.model_proposals.task_id' 'Only one model proposal is allowed per task.')) | Out-Null }
        $rationale = [string](Get-OperationObjectProperty $proposal 'rationale')
        if ([string]::IsNullOrWhiteSpace($rationale)) { $findings.Add((New-OperationFinding 'model_proposal_rationale_required' 'error' '$.model_proposals.rationale' 'Model proposal rationale is required.')) | Out-Null; continue }
        $evaluated = New-ModelPolicyProposal -TaskId ([string](Get-OperationObjectProperty $proposal 'task_id')) -RequestedTier ([string](Get-OperationObjectProperty $proposal 'requested_tier')) -Rationale $rationale -RadarSnapshot (Get-OperationObjectProperty $Request 'radar_snapshot') -HostSurface ([string](Get-OperationObjectProperty $proposal 'host_surface')) -HostAvailablePairs @((Get-OperationObjectProperty $proposal 'host_available_pairs')) -LocalOutcomes @((Get-OperationObjectProperty $proposal 'local_outcomes')) -Now (Get-OperationObjectProperty $Request 'now') -UserOverrideTier ([string](Get-OperationObjectProperty $proposal 'user_override_tier'))
        if ($evaluated.selected_tier -eq 'host_default') { $findings.Add((New-OperationFinding 'model_proposal_unusable' 'error' '$.model_proposals' ('Model proposal failed closed: {0}' -f $evaluated.fallback_reason))) | Out-Null }
        elseif ($null -ne $taskId -and -not $evaluatedProposalIndex.ContainsKey($taskId)) { $evaluatedProposalIndex[$taskId] = $evaluated }
    }
    foreach ($taskKey in @($taskIndex.Keys)) {
        $task = $taskIndex[$taskKey]
        if ((Get-AgentTaskExecutionMode $task) -ne 'delegate') { continue }
        $hostDefaultAccepted = (Get-OperationObjectProperty $task 'host_default_accepted') -eq $true
        if (-not $proposalSeen.Contains($taskKey) -and -not $hostDefaultAccepted) { $findings.Add((New-OperationFinding 'delegated_task_model_proposal_missing' 'error' ('$.task_graph.tasks[{0}]' -f [string](Get-OperationObjectProperty $task 'task_id')) 'Every delegated task requires exactly one usable model proposal or explicit host_default_accepted=true.')) | Out-Null }
    }
    $completionReceiptIndex = @{}
    foreach ($receipt in @((Get-OperationObjectProperty $Request 'completion_receipts'))) {
        $receiptKey = Get-AgentCanonicalTaskId ([string](Get-OperationObjectProperty $receipt 'task_id'))
        if ($null -ne $receiptKey -and -not $completionReceiptIndex.ContainsKey($receiptKey)) { $completionReceiptIndex[$receiptKey] = $receipt }
    }
    foreach ($taskKey in @($evaluatedProposalIndex.Keys)) {
        if (-not $completionReceiptIndex.ContainsKey($taskKey)) { continue }
        $executionReceipt = Get-OperationObjectProperty $completionReceiptIndex[$taskKey] 'execution_receipt'
        if ($null -eq $executionReceipt) { continue }
        $evaluated = $evaluatedProposalIndex[$taskKey]
        foreach ($finding in @((Test-AgentExecutionReceipt -Receipt $executionReceipt -EvaluationTime (Get-OperationObjectProperty $Request 'now') -ExpectedModelFamily $evaluated.model_family -ExpectedReasoningEffort $evaluated.reasoning_effort).findings | Where-Object code -eq 'execution_receipt_proposal_mismatch')) { $findings.Add($finding) | Out-Null }
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
        execution_plan = New-AgentExecutionPlan -TaskGraph $graph -ModelProposals @((Get-OperationObjectProperty $Request 'model_proposals'))
        current_parallel_admission = Test-AgentParallelAdmission -TaskGraph $graph -TaskIds @((Get-OperationObjectProperty $Request 'requested_parallel_task_ids')) -CompletedTaskIds @((Get-OperationObjectProperty $Request 'completed_task_ids')) -CompletedTaskReceipts @((Get-OperationObjectProperty $Request 'completion_receipts')) -ModelProposals @((Get-OperationObjectProperty $Request 'model_proposals')) -EvaluationTime (Get-OperationObjectProperty $Request 'now')
        model_proposals = @($proposals.ToArray()); findings = @($requestValidation.findings); provider_calls = 0; native_mutations = 0; writes = 0
    }
}
