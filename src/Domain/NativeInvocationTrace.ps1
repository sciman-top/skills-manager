$script:NativeInvocationTraceStages = @('listed', 'selected', 'injected', 'executed', 'abstained')
$script:NativeInvocationTraceSources = @('app_server', 'cli', 'native_host', 'fixture', 'unknown')
$script:NativeInvocationTraceFreshness = @('fresh', 'stale', 'unknown')
$script:NativeInvocationTraceTruthLevels = @('unknown', 'host_inventory_loaded', 'host_evaluation_partial', 'host_invocation_observed')

function Get-NativeInvocationTraceProperty($Object, [string[]]$Names) {
    foreach ($name in @($Names)) {
        if (Get-Command Get-OperationObjectProperty -ErrorAction SilentlyContinue) {
            if (Test-OperationObjectProperty $Object $name) { return Get-OperationObjectProperty $Object $name }
        }
        elseif ($null -ne $Object -and $null -ne ($Object.PSObject.Properties | Where-Object Name -eq $name | Select-Object -First 1)) {
            return $Object.$name
        }
    }
    return $null
}

function Get-NativeInvocationTraceHash([string]$Value) {
    if (Get-Command Get-OperationSha256 -ErrorAction SilentlyContinue) { return Get-OperationSha256 ([string]$Value) }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([string]$Value)) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $sha.Dispose() }
}

function New-NativeInvocationTraceRedactedId([string]$Prefix, [string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return ('{0}-unknown' -f $Prefix) }
    return ('{0}-{1}' -f $Prefix, (Get-NativeInvocationTraceHash $Value).Substring(0, 16))
}

function New-NativeInvocationTraceStage([string]$Name, [object[]]$Events) {
    $items = @($Events)
    return [pscustomobject][ordered]@{
        name = $Name
        observed = $items.Count -gt 0
        event_count = $items.Count
        event_ids = [string[]]@($items | ForEach-Object { [string]$_.event_id })
        first_observed_at = if ($items.Count -gt 0) { [string]$items[0].occurred_at } else { $null }
    }
}

function Get-NativeInvocationTraceEventChainKey($Event) {
    return ('{0}|{1}' -f ([string]$Event.skill_name).Trim().ToLowerInvariant(), [string]$Event.correlation_id)
}

function New-NativeInvocationTrace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TraceId,
        [Parameter(Mandatory = $true)][string]$Surface,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][ValidateSet('fresh', 'stale', 'unknown')][string]$Freshness,
        [Parameter(Mandatory = $true)][string]$CapturedAt,
        [object[]]$Events = @()
    )

    $findings = New-Object System.Collections.Generic.List[object]
    $normalizedEvents = New-Object System.Collections.Generic.List[object]
    $allowedStages = @($script:NativeInvocationTraceStages)
    if ($Source -notin @($script:NativeInvocationTraceSources)) { $findings.Add((New-OperationFinding 'trace_source_invalid' 'error' '$.source' 'Trace source is not supported.')) | Out-Null }
    if (-not (Test-OperationRfc3339 $CapturedAt)) { $findings.Add((New-OperationFinding 'captured_at_invalid' 'error' '$.captured_at' 'Trace captured_at must be RFC3339.')) | Out-Null }

    $eventIndex = 0
    foreach ($event in @($Events)) {
        $path = '$.events[{0}]' -f $eventIndex
        $rawKind = ([string](Get-NativeInvocationTraceProperty $event @('kind', 'stage', 'event_type', 'type'))).Trim().ToLowerInvariant()
        $kind = $rawKind
        if ($allowedStages -notcontains $kind) {
            $findings.Add((New-OperationFinding 'unknown_event_type' 'error' ($path + '.kind') ('Unknown invocation event type: {0}' -f $rawKind))) | Out-Null
            $kind = 'unknown'
        }
        $skillName = ([string](Get-NativeInvocationTraceProperty $event @('skill_name', 'name', 'skill', 'capability_name'))).Trim()
        if ([string]::IsNullOrWhiteSpace($skillName)) { $findings.Add((New-OperationFinding 'event_skill_missing' 'error' ($path + '.skill_name') 'Invocation events require a skill name.')) | Out-Null }
        $occurredAt = [string](Get-NativeInvocationTraceProperty $event @('occurred_at', 'timestamp', 'captured_at'))
        if (-not (Test-OperationRfc3339 $occurredAt)) { $findings.Add((New-OperationFinding 'event_timestamp_invalid' 'error' ($path + '.occurred_at') 'Invocation event occurred_at must be RFC3339.')) | Out-Null }
        $rawEventId = [string](Get-NativeInvocationTraceProperty $event @('event_id', 'id'))
        $rawCorrelation = [string](Get-NativeInvocationTraceProperty $event @('correlation_id', 'correlation', 'turn_id', 'thread_id'))
        $reason = [string](Get-NativeInvocationTraceProperty $event @('reason', 'abstention_reason'))
        $eventIdentity = if ([string]::IsNullOrWhiteSpace($rawEventId)) { '{0}|{1}|{2}' -f $TraceId, $eventIndex, $skillName } else { $rawEventId }
        $normalizedEvents.Add([pscustomobject][ordered]@{
                event_id = New-NativeInvocationTraceRedactedId 'evt' $eventIdentity
                kind = $kind
                skill_name = $skillName
                occurred_at = if ([string]::IsNullOrWhiteSpace($occurredAt)) { $null } else { $occurredAt }
                correlation_id = New-NativeInvocationTraceRedactedId 'corr' $rawCorrelation
                reason = if ([string]::IsNullOrWhiteSpace($reason)) { $null } else { Protect-OperationSensitiveString $reason }
            }) | Out-Null
        $eventIndex++
    }

    $stageObjects = [ordered]@{}
    foreach ($stageName in $allowedStages) {
        $stageObjects[$stageName] = New-NativeInvocationTraceStage $stageName @($normalizedEvents | Where-Object kind -eq $stageName)
    }
    $stages = [pscustomobject]$stageObjects
    $hasListed = [bool]$stages.listed.observed
    $hasSelected = [bool]$stages.selected.observed
    $hasInjected = [bool]$stages.injected.observed
    $hasExecuted = [bool]$stages.executed.observed
    $hasAbstained = [bool]$stages.abstained.observed
    $truthLevel = 'unknown'
    $status = 'unknown'
    $outcome = 'not_observed'
    $bodyInjectionObservable = $hasInjected
    $invocationObservable = $false
    $validInvocationObserved = $false
    $invocationChainInvalid = $false
    $outcomeConflictObserved = $false

    $eventArray = @($normalizedEvents.ToArray())
    for ($executionIndex = 0; $executionIndex -lt $eventArray.Count; $executionIndex++) {
        $executionEvent = $eventArray[$executionIndex]
        if ([string]$executionEvent.kind -ne 'executed') { continue }

        $chainKey = Get-NativeInvocationTraceEventChainKey $executionEvent
        $sameChainInjections = @($eventArray | Where-Object { [string]$_.kind -eq 'injected' -and (Get-NativeInvocationTraceEventChainKey $_) -eq $chainKey })
        if ($sameChainInjections.Count -eq 0) {
            $code = if ($hasInjected) { 'invocation_chain_missing' } else { 'executed_without_injection' }
            $message = if ($hasInjected) { 'Execution cannot be promoted without injection evidence for the same skill and correlation.' } else { 'Execution cannot be promoted without an observed injection event.' }
            $findings.Add((New-OperationFinding $code 'error' '$.stages.executed' $message)) | Out-Null
            $invocationChainInvalid = $true
            continue
        }

        $executionTime = [DateTimeOffset]::MinValue
        $executionTimeValid = [DateTimeOffset]::TryParse([string]$executionEvent.occurred_at, [ref]$executionTime)
        $orderedInjectionObserved = $false
        for ($injectionIndex = 0; $injectionIndex -lt $executionIndex; $injectionIndex++) {
            $injectionEvent = $eventArray[$injectionIndex]
            if ([string]$injectionEvent.kind -ne 'injected' -or (Get-NativeInvocationTraceEventChainKey $injectionEvent) -ne $chainKey) { continue }
            $injectionTime = [DateTimeOffset]::MinValue
            if ($executionTimeValid -and [DateTimeOffset]::TryParse([string]$injectionEvent.occurred_at, [ref]$injectionTime) -and $injectionTime -le $executionTime) {
                $orderedInjectionObserved = $true
                break
            }
        }
        if (-not $orderedInjectionObserved) {
            $findings.Add((New-OperationFinding 'invocation_stage_order_invalid' 'error' '$.stages.executed' 'Execution must follow injection for the same skill and correlation.')) | Out-Null
            $invocationChainInvalid = $true
            continue
        }

        $validInvocationObserved = $true
        if (@($eventArray | Where-Object { [string]$_.kind -eq 'abstained' -and (Get-NativeInvocationTraceEventChainKey $_) -eq $chainKey }).Count -gt 0) {
            $outcomeConflictObserved = $true
        }
    }

    if ($normalizedEvents.Count -eq 0) {
        $findings.Add((New-OperationFinding 'trace_events_missing' 'error' '$.events' 'At least one host event is required to establish trace truth.')) | Out-Null
    }
    if ($hasSelected -and -not $hasListed) { $findings.Add((New-OperationFinding 'listing_not_observable' 'warning' '$.stages.listed' 'Selection was observed without a listed event; visibility coverage is partial.')) | Out-Null }
    if ($hasInjected -and -not $hasSelected) { $findings.Add((New-OperationFinding 'selection_not_observable' 'warning' '$.stages.selected' 'Injection was observed without a selected event; selection coverage is partial.')) | Out-Null }
    if ($outcomeConflictObserved) {
        $findings.Add((New-OperationFinding 'outcome_conflict' 'error' '$.stages' 'A trace cannot be both abstained and executed.')) | Out-Null
    }
    $blockingFindingObserved = @($findings | Where-Object severity -eq 'error').Count -gt 0
    if ($blockingFindingObserved) {
        $truthLevel = 'unknown'
        $status = 'unknown'
    }
    elseif ($validInvocationObserved) {
        $truthLevel = if ($Freshness -eq 'fresh') { 'host_invocation_observed' } else { 'unknown' }
        $status = if ($Freshness -eq 'fresh') { 'complete' } else { 'unknown' }
        $outcome = 'executed'
        $invocationObservable = ($Freshness -eq 'fresh')
    }
    elseif ($hasAbstained) {
        $outcome = 'abstained'
        $truthLevel = if ($Freshness -eq 'fresh') { 'host_evaluation_partial' } else { 'unknown' }
        $status = if ($Freshness -eq 'fresh') { 'partial' } else { 'unknown' }
    }
    elseif ($hasInjected) {
        $outcome = 'injected'
        $truthLevel = if ($Freshness -eq 'fresh') { 'host_evaluation_partial' } else { 'unknown' }
        $status = if ($Freshness -eq 'fresh') { 'partial' } else { 'unknown' }
    }
    elseif ($hasSelected) {
        $outcome = 'selected'
        $truthLevel = if ($Freshness -eq 'fresh') { 'host_evaluation_partial' } else { 'unknown' }
        $status = if ($Freshness -eq 'fresh') { 'partial' } else { 'unknown' }
    }
    elseif ($hasListed) {
        $outcome = 'listed'
        $truthLevel = if ($Freshness -eq 'fresh') { 'host_inventory_loaded' } else { 'unknown' }
        $status = if ($Freshness -eq 'fresh') { 'inventory_loaded' } else { 'unknown' }
    }

    $correlationSource = [string](@($normalizedEvents | Where-Object { $_.correlation_id -ne 'corr-unknown' } | Select-Object -First 1).correlation_id)
    if ([string]::IsNullOrWhiteSpace($correlationSource)) { $correlationSource = 'corr-unknown' }
    $redaction = [pscustomobject][ordered]@{
        applied = $true
        strategy = 'allowlist-normalized-events-and-hashed-identifiers'
        dropped_fields = @('payload', 'args', 'argv', 'headers', 'authorization', 'token', 'secret')
    }
    $trace = [pscustomobject][ordered]@{
        schema_version = 1
        trace_id = New-NativeInvocationTraceRedactedId 'nit' $TraceId
        surface = $Surface
        source = $Source
        freshness = $Freshness
        captured_at = $CapturedAt
        correlation_id = $correlationSource
        status = $status
        truth_level = $truthLevel
        outcome = $outcome
        body_injection_observable = $bodyInjectionObservable
        invocation_observable = $invocationObservable
        stages = $stages
        events = [object[]]@($normalizedEvents.ToArray())
        redaction = $redaction
        receipt = [pscustomobject][ordered]@{ schema_version = 1; status = $status; truth_level = $truthLevel; complete = ($truthLevel -eq 'host_invocation_observed') }
        provider_calls = 0
        native_mutations = 0
        writes = 0
        findings = [object[]]@($findings.ToArray())
        pass = (@($findings | Where-Object severity -eq 'error').Count -eq 0)
    }
    return $trace
}

function Test-NativeInvocationTraceContract {
    param($Trace)

    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Trace) { return New-OperationValidationResult @((New-OperationFinding 'trace_missing' 'error' '$' 'Native invocation trace is required.')) }
    if ((Get-NativeInvocationTraceProperty $Trace @('schema_version')) -ne 1) { $findings.Add((New-OperationFinding 'schema_version_invalid' 'error' '$.schema_version' 'Only NativeInvocationTrace schema version 1 is supported.')) | Out-Null }
    foreach ($field in @('trace_id', 'surface', 'source', 'freshness', 'captured_at', 'truth_level', 'status', 'outcome')) {
        if ([string]::IsNullOrWhiteSpace([string](Get-NativeInvocationTraceProperty $Trace @($field)))) { $findings.Add((New-OperationFinding 'required_field_missing' 'error' ('$.{0}' -f $field) 'Required trace field is missing.')) | Out-Null }
    }
    if ([string](Get-NativeInvocationTraceProperty $Trace @('source')) -notin @($script:NativeInvocationTraceSources)) { $findings.Add((New-OperationFinding 'trace_source_invalid' 'error' '$.source' 'Trace source is not supported.')) | Out-Null }
    if ([string](Get-NativeInvocationTraceProperty $Trace @('freshness')) -notin @($script:NativeInvocationTraceFreshness)) { $findings.Add((New-OperationFinding 'trace_freshness_invalid' 'error' '$.freshness' 'Trace freshness is not supported.')) | Out-Null }
    if ([string](Get-NativeInvocationTraceProperty $Trace @('truth_level')) -notin @($script:NativeInvocationTraceTruthLevels)) { $findings.Add((New-OperationFinding 'truth_level_invalid' 'error' '$.truth_level' 'Trace truth level is not supported.')) | Out-Null }
    if (-not (Test-OperationRfc3339 (Get-NativeInvocationTraceProperty $Trace @('captured_at')))) { $findings.Add((New-OperationFinding 'captured_at_invalid' 'error' '$.captured_at' 'Trace captured_at must be RFC3339.')) | Out-Null }
    if (-not (Test-OperationArray (Get-NativeInvocationTraceProperty $Trace @('events')))) { $findings.Add((New-OperationFinding 'events_type_invalid' 'error' '$.events' 'Trace events must be an array.')) | Out-Null }
    $stages = Get-NativeInvocationTraceProperty $Trace @('stages')
    foreach ($stageName in @($script:NativeInvocationTraceStages)) {
        $stage = Get-NativeInvocationTraceProperty $stages @($stageName)
        if ($null -eq $stage -or (Get-NativeInvocationTraceProperty $stage @('observed')) -isnot [bool]) { $findings.Add((New-OperationFinding 'stage_invalid' 'error' ('$.stages.{0}' -f $stageName) 'Every trace stage must declare boolean observed.')) | Out-Null }
    }
    $redaction = Get-NativeInvocationTraceProperty $Trace @('redaction')
    if ((Get-NativeInvocationTraceProperty $redaction @('applied')) -ne $true) { $findings.Add((New-OperationFinding 'redaction_required' 'error' '$.redaction.applied' 'Trace redaction must be applied.')) | Out-Null }
    if ((Get-NativeInvocationTraceProperty $Trace @('invocation_observable')) -eq $true -and (Get-NativeInvocationTraceProperty $Trace @('stages')).executed.observed -ne $true) { $findings.Add((New-OperationFinding 'invocation_promotion_invalid' 'error' '$.invocation_observable' 'Invocation cannot be observable without executed evidence.')) | Out-Null }
    if ([string](Get-NativeInvocationTraceProperty $Trace @('truth_level')) -eq 'host_invocation_observed') {
        if ((Get-NativeInvocationTraceProperty $stages @('injected')).observed -ne $true -or (Get-NativeInvocationTraceProperty $stages @('executed')).observed -ne $true) { $findings.Add((New-OperationFinding 'host_invocation_evidence_missing' 'error' '$.truth_level' 'host_invocation_observed requires injected and executed evidence.')) | Out-Null }
    }
    foreach ($field in @('provider_calls', 'native_mutations', 'writes')) {
        $value = Get-NativeInvocationTraceProperty $Trace @($field)
        if ($null -eq $value -or [long]$value -ne 0) { $findings.Add((New-OperationFinding 'side_effect_forbidden' 'error' ('$.{0}' -f $field) 'Trace normalization must be zero-side-effect.')) | Out-Null }
    }
    $serialized = $Trace | ConvertTo-Json -Depth 40 -Compress
    if (Get-Command Test-OperationSerializedSensitiveValue -ErrorAction SilentlyContinue) {
        if (Test-OperationSerializedSensitiveValue $serialized) { $findings.Add((New-OperationFinding 'sensitive_value_present' 'error' '$' 'Trace contains an unredacted sensitive value.')) | Out-Null }
    }
    foreach ($finding in @((Get-NativeInvocationTraceProperty $Trace @('findings')))) {
        if ([string](Get-NativeInvocationTraceProperty $finding @('severity')) -eq 'error') { $findings.Add($finding) | Out-Null }
    }
    return New-OperationValidationResult $findings.ToArray()
}
