function Copy-AgentWorkflowValue($Value) {
    if ($null -eq $Value) { return $null }
    return (($Value | ConvertTo-Json -Depth 50 -Compress) | ConvertFrom-Json)
}

function Get-AgentCanonicalWritePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match '[\x00-\x1F<>:"|*?\[\]]') { return $null }
    if ($Path -cne $Path.Trim()) { return $null }
    $normalized = $Path.Replace('\', '/')
    if ($normalized -match '^(?:[A-Za-z]:|/|//)') { return $null }
    $segments = $normalized.Split([char]'/', [StringSplitOptions]::None)
    if ($segments.Count -eq 0 -or @($segments | Where-Object { [string]::IsNullOrWhiteSpace($_) -or $_ -in @('.', '..') }).Count -gt 0) { return $null }
    $canonicalSegments = New-Object System.Collections.Generic.List[string]
    foreach ($segment in @($segments)) {
        if ($segment -cne $segment.TrimEnd(' ', '.')) { return $null }
        if ($segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { return $null }
        $canonicalSegments.Add($segment.Normalize([Text.NormalizationForm]::FormC).ToLowerInvariant()) | Out-Null
    }
    return ($canonicalSegments.ToArray() -join '/')
}

function New-AgentTaskGraph {
    param(
        [Parameter(Mandatory = $true)][string]$GraphId,
        [Parameter(Mandatory = $true)][string]$BaseRevision,
        [Parameter(Mandatory = $true)][string]$IntegrationOwner,
        [ValidateSet(1, 2)][int]$SchemaVersion = 2,
        [object[]]$Tasks = @()
    )
    $normalizedTasks = @($Tasks | ForEach-Object { Copy-AgentWorkflowValue $_ } | Sort-Object { [int](Get-OperationObjectProperty $_ 'integration_order') }, { [string](Get-OperationObjectProperty $_ 'task_id') })
    return [pscustomobject][ordered]@{
        schema_version = $SchemaVersion
        graph_id = $GraphId.Trim()
        base_revision = $BaseRevision.Trim()
        integration_owner = $IntegrationOwner.Trim()
        tasks = $normalizedTasks
    }
}

function Test-AgentTaskGraphContract($TaskGraph) {
    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $TaskGraph) { return New-OperationValidationResult @((New-OperationFinding 'task_graph_missing' 'error' '$' 'TaskGraph is required.')) }
    $schemaVersion = 0
    if (-not [int]::TryParse([string](Get-OperationObjectProperty $TaskGraph 'schema_version'), [ref]$schemaVersion) -or $schemaVersion -notin @(1, 2)) {
        $findings.Add((New-OperationFinding 'schema_version_invalid' 'error' '$.schema_version' 'Only TaskGraph schema versions 1 and 2 are supported.')) | Out-Null
    }
    foreach ($field in @('graph_id', 'base_revision', 'integration_owner')) {
        if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $TaskGraph $field))) { $findings.Add((New-OperationFinding 'required_field_missing' 'error' ('$.{0}' -f $field) 'Required TaskGraph field is missing.')) | Out-Null }
    }
    $tasks = Get-OperationObjectProperty $TaskGraph 'tasks'
    if (-not (Test-OperationArray $tasks)) { $findings.Add((New-OperationFinding 'tasks_type_invalid' 'error' '$.tasks' 'TaskGraph tasks must be an array.')) | Out-Null; $tasks = @() }
    if (@($tasks).Count -eq 0) { $findings.Add((New-OperationFinding 'tasks_required' 'error' '$.tasks' 'TaskGraph requires at least one task.')) | Out-Null }

    $taskIndex = @{}
    $integrationOrders = @{}
    $allowedDeliveryStages = @('discovery', 'main_chain', 'stabilize', 'refactor', 'release', 'operate')
    $allowedAdmissionScopes = @('direct_fix', 'product_delivery', 'ai_capability', 'governance', 'long_lived_surface')
    $allowedReuseDecisions = @('adopt', 'adapt', 'defer', 'reject')
    $allowedComplexityKinds = @('two_real_repetitions', 'stable_external_protocol', 'proven_safety_or_data_seam', 'measured_hotspot')
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
        if ($schemaVersion -eq 2) {
            $deliveryStage = [string](Get-OperationObjectProperty $task 'delivery_stage')
            $admissionScope = [string](Get-OperationObjectProperty $task 'admission_scope')
            $reuseDecision = [string](Get-OperationObjectProperty $task 'reuse_decision')
            if ($deliveryStage -notin $allowedDeliveryStages) { $findings.Add((New-OperationFinding 'delivery_stage_invalid' 'error' ($path + '.delivery_stage') 'Task delivery_stage is invalid.')) | Out-Null }
            if ($admissionScope -notin $allowedAdmissionScopes) { $findings.Add((New-OperationFinding 'admission_scope_invalid' 'error' ($path + '.admission_scope') 'Task admission_scope is invalid.')) | Out-Null }
            foreach ($field in @('user_outcome', 'entrypoint', 'main_chain_checkpoint')) {
                if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $task $field))) {
                    $findings.Add((New-OperationFinding ('{0}_required' -f $field) 'error' ($path + '.' + $field) ('Task {0} is required for TaskGraph v2.' -f $field))) | Out-Null
                }
            }
            if ($reuseDecision -notin $allowedReuseDecisions) { $findings.Add((New-OperationFinding 'reuse_decision_invalid' 'error' ($path + '.reuse_decision') 'Task reuse_decision is invalid.')) | Out-Null }

            $nativeBaseline = Get-OperationObjectProperty $task 'native_baseline'
            if ($admissionScope -in @('ai_capability', 'governance', 'long_lived_surface') -and $null -eq $nativeBaseline) {
                $findings.Add((New-OperationFinding 'native_baseline_required' 'error' ($path + '.native_baseline') 'Capability, governance, and long-lived surface tasks require a native baseline.')) | Out-Null
            }
            elseif ($null -ne $nativeBaseline) {
                $nativeEvidence = Get-OperationObjectProperty $nativeBaseline 'evidence'
                if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $nativeBaseline 'equivalent')) -or
                    [string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $nativeBaseline 'observed_gap')) -or
                    -not (Test-OperationArray $nativeEvidence) -or @($nativeEvidence).Count -eq 0) {
                    $findings.Add((New-OperationFinding 'native_baseline_invalid' 'error' ($path + '.native_baseline') 'Native baseline requires equivalent, observed_gap, and non-empty evidence.')) | Out-Null
                }
            }

            $complexityAdmission = Get-OperationObjectProperty $task 'complexity_admission'
            if ($admissionScope -eq 'long_lived_surface' -and $null -eq $complexityAdmission) {
                $findings.Add((New-OperationFinding 'complexity_admission_required' 'error' ($path + '.complexity_admission') 'Long-lived surfaces require bounded complexity and retirement evidence.')) | Out-Null
            }
            elseif ($null -ne $complexityAdmission) {
                $complexityKind = [string](Get-OperationObjectProperty $complexityAdmission 'kind')
                $evidenceRefs = Get-OperationObjectProperty $complexityAdmission 'evidence_refs'
                $realConsumers = Get-OperationObjectProperty $complexityAdmission 'real_consumers'
                if ($complexityKind -notin $allowedComplexityKinds -or
                    -not (Test-OperationArray $evidenceRefs) -or @($evidenceRefs).Count -eq 0 -or
                    -not (Test-OperationArray $realConsumers) -or @($realConsumers).Count -eq 0 -or
                    [string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $complexityAdmission 'maintenance_cost')) -or
                    [string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $complexityAdmission 'retirement_trigger'))) {
                    $findings.Add((New-OperationFinding 'complexity_admission_invalid' 'error' ($path + '.complexity_admission') 'Complexity admission requires a supported kind, evidence, consumers, maintenance cost, and retirement trigger.')) | Out-Null
                }
            }
        }
        if ([string](Get-OperationObjectProperty $task 'risk') -notin @('low', 'medium', 'high')) { $findings.Add((New-OperationFinding 'risk_invalid' 'error' ($path + '.risk') 'Task risk is invalid.')) | Out-Null }
        if ([string](Get-OperationObjectProperty $task 'ambiguity') -notin @('low', 'medium', 'high')) { $findings.Add((New-OperationFinding 'ambiguity_invalid' 'error' ($path + '.ambiguity') 'Task ambiguity is invalid.')) | Out-Null }
        if ((Get-OperationObjectProperty $task 'parallelizable') -isnot [bool]) { $findings.Add((New-OperationFinding 'parallelizable_invalid' 'error' ($path + '.parallelizable') 'parallelizable must be a boolean.')) | Out-Null }
        $order = Get-OperationObjectProperty $task 'integration_order'
        $parsedOrder = 0
        if ($null -eq $order -or -not [int]::TryParse([string]$order, [ref]$parsedOrder) -or $parsedOrder -lt 1) { $findings.Add((New-OperationFinding 'integration_order_invalid' 'error' ($path + '.integration_order') 'integration_order must be a positive integer.')) | Out-Null }
        elseif ($integrationOrders.ContainsKey($parsedOrder)) { $findings.Add((New-OperationFinding 'integration_order_duplicate' 'error' ($path + '.integration_order') 'integration_order must be unique.')) | Out-Null }
        else { $integrationOrders[$parsedOrder] = $taskId }
        foreach ($writePath in @((Get-OperationObjectProperty $task 'exact_write_set'))) {
            if ($null -eq (Get-AgentCanonicalWritePath ([string]$writePath))) { $findings.Add((New-OperationFinding 'write_set_path_invalid' 'error' ($path + '.exact_write_set') 'Write-set entries must be canonical repository-relative paths without wildcards, empty segments, dot segments, or roots.')) | Out-Null }
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

    if ($schemaVersion -eq 2) {
        $deliveryStageRanks = @{ discovery = 0; main_chain = 1; stabilize = 2; refactor = 3; release = 4; operate = 5 }
        foreach ($taskKey in @($taskIndex.Keys)) {
            $task = $taskIndex[$taskKey]
            $taskStage = [string](Get-OperationObjectProperty $task 'delivery_stage')
            if (-not $deliveryStageRanks.ContainsKey($taskStage)) { continue }
            $ancestorStages = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $visitedAncestors = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $pendingAncestors = New-Object System.Collections.Generic.Queue[string]
            foreach ($dependency in @((Get-OperationObjectProperty $task 'depends_on'))) { $pendingAncestors.Enqueue(([string]$dependency).ToLowerInvariant()) }
            while ($pendingAncestors.Count -gt 0) {
                $dependencyKey = $pendingAncestors.Dequeue()
                if (-not $taskIndex.ContainsKey($dependencyKey) -or -not $visitedAncestors.Add($dependencyKey)) { continue }
                $dependencyTask = $taskIndex[$dependencyKey]
                $dependencyStage = [string](Get-OperationObjectProperty $dependencyTask 'delivery_stage')
                if ($deliveryStageRanks.ContainsKey($dependencyStage)) {
                    $ancestorStages.Add($dependencyStage) | Out-Null
                    if ([int]$deliveryStageRanks[$taskStage] -lt [int]$deliveryStageRanks[$dependencyStage]) {
                        $findings.Add((New-OperationFinding 'delivery_stage_dependency_invalid' 'error' ('$.tasks[{0}].depends_on' -f [string](Get-OperationObjectProperty $task 'task_id')) 'A task cannot depend on a later delivery stage.')) | Out-Null
                    }
                }
                foreach ($ancestorDependency in @((Get-OperationObjectProperty $dependencyTask 'depends_on'))) { $pendingAncestors.Enqueue(([string]$ancestorDependency).ToLowerInvariant()) }
            }
            if ($taskStage -in @('stabilize', 'refactor', 'release') -and -not $ancestorStages.Contains('main_chain')) {
                $findings.Add((New-OperationFinding 'delivery_stage_ancestor_missing' 'error' ('$.tasks[{0}].delivery_stage' -f [string](Get-OperationObjectProperty $task 'task_id')) 'This delivery stage requires a main_chain ancestor.')) | Out-Null
            }
            if ($taskStage -eq 'operate' -and -not $ancestorStages.Contains('release')) {
                $findings.Add((New-OperationFinding 'delivery_stage_ancestor_missing' 'error' ('$.tasks[{0}].delivery_stage' -f [string](Get-OperationObjectProperty $task 'task_id')) 'Operate requires a release ancestor.')) | Out-Null
            }
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

# Legacy read-only compatibility for historical Radar v2 receipts. Active model
# proposals must not call these functions or use their output as evidence.
function New-RadarSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$SnapshotId,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)]$CapturedAt,
        [Parameter(Mandatory = $true)]$SourceUpdatedAt,
        [Parameter(Mandatory = $true)]$ExpiresAt,
        [Parameter(Mandatory = $true)][string]$RawHash,
        [object[]]$Entries = @()
    )
    return [pscustomobject][ordered]@{
        schema_version = 2
        snapshot_id = $SnapshotId.Trim()
        source = $Source.Trim()
        captured_at = $CapturedAt
        source_updated_at = $SourceUpdatedAt
        expires_at = $ExpiresAt
        raw_hash = $RawHash.ToLowerInvariant()
        entries = @($Entries | ForEach-Object { Copy-AgentWorkflowValue $_ } | Sort-Object model_family, reasoning_effort)
    }
}

function ConvertTo-AgentWorkflowRfc3339Value($Value) {
    if (-not (Test-OperationRfc3339 $Value)) { return $null }
    if ($Value -is [datetimeoffset]) { return $Value }
    if ($Value -is [datetime]) { return [datetimeoffset]$Value }
    $parsed = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse(
            [string]$Value,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind,
            [ref]$parsed
        )) { return $null }
    return $parsed
}

function Test-AgentWorkflowNonNegativeFiniteNumber($Value) {
    if ($null -eq $Value -or $Value -is [bool]) { return $false }
    $number = 0.0
    $text = [System.Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture)
    if (-not [double]::TryParse(
            $text,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$number
        )) { return $false }
    return -not [double]::IsNaN($number) -and -not [double]::IsInfinity($number) -and $number -ge 0
}

function Test-AgentWorkflowNonNegativeInteger($Value) {
    if ($null -eq $Value -or $Value -is [bool]) { return $false }
    $number = 0L
    $text = [System.Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture)
    return [long]::TryParse(
        $text,
        [System.Globalization.NumberStyles]::Integer,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$number
    ) -and $number -ge 0
}

function Test-RadarSnapshotContract {
    param($Snapshot, $Now)
    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Snapshot) { return New-OperationValidationResult @((New-OperationFinding 'radar_snapshot_missing' 'error' '$' 'Radar snapshot is required.')) }
    if ((Get-OperationObjectProperty $Snapshot 'schema_version') -ne 2) { $findings.Add((New-OperationFinding 'schema_version_invalid' 'error' '$.schema_version' 'Only Radar snapshot schema version 2 is supported.')) | Out-Null }
    foreach ($field in @('snapshot_id', 'source', 'captured_at', 'source_updated_at', 'expires_at', 'raw_hash')) { if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $Snapshot $field))) { $findings.Add((New-OperationFinding 'required_field_missing' 'error' ('$.{0}' -f $field) 'Required Radar snapshot field is missing.')) | Out-Null } }
    if (Test-OperationObjectProperty $Snapshot 'policy_overrides') { $findings.Add((New-OperationFinding 'radar_decision_field_forbidden' 'error' '$.policy_overrides' 'Radar snapshots are observational evidence and cannot carry user or host policy decisions.')) | Out-Null }
    $sourceUri = $null
    $sourceUriValid = [uri]::TryCreate([string](Get-OperationObjectProperty $Snapshot 'source'), [UriKind]::Absolute, [ref]$sourceUri)
    if (-not $sourceUriValid -or $sourceUri.Scheme -cne 'https') {
        $findings.Add((New-OperationFinding 'radar_source_invalid' 'error' '$.source' 'Radar source must be an absolute HTTPS URI.')) | Out-Null
    }
    elseif ($sourceUri.Host -notin @('codexradar.com', 'www.codexradar.com')) {
        $findings.Add((New-OperationFinding 'radar_source_untrusted' 'error' '$.source' 'Radar source host is not allowlisted.')) | Out-Null
    }
    if ([string](Get-OperationObjectProperty $Snapshot 'raw_hash') -notmatch '^[a-fA-F0-9]{64}$') { $findings.Add((New-OperationFinding 'radar_raw_hash_invalid' 'error' '$.raw_hash' 'Radar raw_hash must be SHA-256.')) | Out-Null }
    $captured = ConvertTo-AgentWorkflowRfc3339Value (Get-OperationObjectProperty $Snapshot 'captured_at')
    $sourceUpdated = ConvertTo-AgentWorkflowRfc3339Value (Get-OperationObjectProperty $Snapshot 'source_updated_at')
    $expires = ConvertTo-AgentWorkflowRfc3339Value (Get-OperationObjectProperty $Snapshot 'expires_at')
    $capturedValid = $null -ne $captured
    $sourceUpdatedValid = $null -ne $sourceUpdated
    $expiresValid = $null -ne $expires
    if (-not $capturedValid) { $findings.Add((New-OperationFinding 'radar_captured_at_invalid' 'error' '$.captured_at' 'captured_at must be RFC3339.')) | Out-Null }
    if (-not $sourceUpdatedValid) { $findings.Add((New-OperationFinding 'radar_source_updated_at_invalid' 'error' '$.source_updated_at' 'source_updated_at must be RFC3339.')) | Out-Null }
    if (-not $expiresValid) { $findings.Add((New-OperationFinding 'radar_expires_at_invalid' 'error' '$.expires_at' 'expires_at must be RFC3339.')) | Out-Null }
    if ($capturedValid -and $expiresValid -and $expires -le $captured) { $findings.Add((New-OperationFinding 'radar_expiry_invalid' 'error' '$.expires_at' 'expires_at must be later than captured_at.')) | Out-Null }
    if ($capturedValid -and $sourceUpdatedValid) {
        if ($sourceUpdated -gt $captured.AddMinutes(5)) { $findings.Add((New-OperationFinding 'radar_source_future' 'error' '$.source_updated_at' 'source_updated_at cannot be materially later than captured_at.')) | Out-Null }
        elseif (($captured - $sourceUpdated).TotalHours -gt 36) { $findings.Add((New-OperationFinding 'radar_source_stale' 'error' '$.source_updated_at' 'Upstream Radar data is older than the 36-hour source freshness limit.')) | Out-Null }
    }
    if (-not [string]::IsNullOrWhiteSpace($Now)) {
        $nowValue = ConvertTo-AgentWorkflowRfc3339Value $Now
        if ($null -eq $nowValue) { $findings.Add((New-OperationFinding 'evaluation_time_invalid' 'error' '$.now' 'Evaluation time must be RFC3339.')) | Out-Null }
        elseif ($expiresValid -and $nowValue -ge $expires) { $findings.Add((New-OperationFinding 'radar_snapshot_stale' 'error' '$.expires_at' 'Radar snapshot is expired and cannot drive a model proposal.')) | Out-Null }
    }
    $entries = Get-OperationObjectProperty $Snapshot 'entries'
    if (-not (Test-OperationArray $entries)) { $findings.Add((New-OperationFinding 'radar_entries_invalid' 'error' '$.entries' 'Radar entries must be an array.')) | Out-Null; $entries = @() }
    if (@($entries).Count -eq 0) { $findings.Add((New-OperationFinding 'radar_entries_empty' 'error' '$.entries' 'Radar snapshots require at least one observation.')) | Out-Null }
    $allowedPairs = @('gpt-5.6-sol|xhigh', 'gpt-5.6-sol|medium', 'gpt-5.6-luna|max')
    $canonicalLabels = @{
        'gpt-5.6-sol|xhigh' = 'Sol xhigh'
        'gpt-5.6-sol|medium' = 'Sol medium'
        'gpt-5.6-luna|max' = 'Luna max'
    }
    $observedPairs = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
    for ($i = 0; $i -lt @($entries).Count; $i++) {
        $entry = @($entries)[$i]; $path = '$.entries[{0}]' -f $i
        foreach ($field in @('model_label', 'model_family', 'reasoning_effort', 'confidence')) { if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $entry $field))) { $findings.Add((New-OperationFinding 'radar_entry_field_missing' 'error' ($path + '.' + $field) 'Radar entry field is required.')) | Out-Null } }
        if ([string](Get-OperationObjectProperty $entry 'reasoning_effort') -notin @('low', 'medium', 'high', 'xhigh', 'max', 'ultra')) { $findings.Add((New-OperationFinding 'reasoning_effort_invalid' 'error' ($path + '.reasoning_effort') 'Radar reasoning effort is invalid.')) | Out-Null }
        $pair = '{0}|{1}' -f [string](Get-OperationObjectProperty $entry 'model_family'), [string](Get-OperationObjectProperty $entry 'reasoning_effort')
        if ($pair -notin $allowedPairs) { $findings.Add((New-OperationFinding 'radar_pair_not_allowlisted' 'error' $path 'Radar observation is outside the three policy model pairs.')) | Out-Null }
        else {
            if ([string](Get-OperationObjectProperty $entry 'model_label') -cne $canonicalLabels[$pair]) { $findings.Add((New-OperationFinding 'radar_model_label_mismatch' 'error' ($path + '.model_label') 'Radar model_label must match the canonical policy pair label.')) | Out-Null }
            if (-not $observedPairs.Add($pair)) { $findings.Add((New-OperationFinding 'radar_pair_duplicate' 'error' $path 'Radar snapshot contains a duplicate model and effort pair.')) | Out-Null }
        }
        foreach ($field in @('score', 'estimated_cost', 'estimated_duration_seconds')) {
            if (-not (Test-AgentWorkflowNonNegativeFiniteNumber (Get-OperationObjectProperty $entry $field))) { $findings.Add((New-OperationFinding 'radar_metric_invalid' 'error' ($path + '.' + $field) 'Radar metric must be a finite non-negative number.')) | Out-Null }
        }
        if (-not (Test-AgentWorkflowNonNegativeInteger (Get-OperationObjectProperty $entry 'sample_count'))) { $findings.Add((New-OperationFinding 'radar_sample_count_invalid' 'error' ($path + '.sample_count') 'Radar sample_count must be a non-negative integer.')) | Out-Null }
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
    if ($attemptCount -ge 1 -and $escalationCount -gt ($attemptCount - 1)) { $findings.Add((New-OperationFinding 'escalation_count_inconsistent' 'error' '$.escalation_count' 'escalation_count cannot exceed attempt_count minus one.')) | Out-Null }
    foreach ($field in @('commands', 'failures', 'verified_facts', 'unresolved_questions', 'artifacts', 'exact_write_set')) { if (-not (Test-OperationArray (Get-OperationObjectProperty $FailurePacket $field))) { $findings.Add((New-OperationFinding 'array_type_invalid' 'error' ('$.{0}' -f $field) 'FailurePacket field must be an array.')) | Out-Null } }
    if (@((Get-OperationObjectProperty $FailurePacket 'failures')).Count -eq 0) { $findings.Add((New-OperationFinding 'failures_required' 'error' '$.failures' 'FailurePacket must contain at least one observed failure.')) | Out-Null }
    if ([string](Get-OperationObjectProperty $FailurePacket 'failure_kind') -eq 'capacity' -and $attemptCount -eq 1 -and
        ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $FailurePacket 'correction_summary')) -or
            @((Get-OperationObjectProperty $FailurePacket 'commands')).Count -eq 0 -or
            @((Get-OperationObjectProperty $FailurePacket 'verified_facts')).Count -eq 0)) {
        $findings.Add((New-OperationFinding 'correction_evidence_required' 'error' '$.correction_summary' 'A first capacity retry requires a correction summary, a verified command, and a verified fact.')) | Out-Null
    }
    $serialized = $FailurePacket | ConvertTo-Json -Depth 20 -Compress
    if (Test-OperationSerializedSensitiveValue $serialized) { $findings.Add((New-OperationFinding 'sensitive_value_present' 'error' '$' 'FailurePacket contains a sensitive value.')) | Out-Null }
    return New-OperationValidationResult $findings.ToArray()
}
