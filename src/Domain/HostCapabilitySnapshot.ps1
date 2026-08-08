function Copy-HostCapabilitySnapshotValue($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        $copy = [ordered]@{}
        foreach ($key in @($Value.Keys)) { $copy[[string]$key] = Copy-HostCapabilitySnapshotValue $Value[$key] }
        return [pscustomobject]$copy
    }
    if ($Value -is [pscustomobject]) {
        $copy = [ordered]@{}
        foreach ($property in @($Value.PSObject.Properties)) { $copy[$property.Name] = Copy-HostCapabilitySnapshotValue $property.Value }
        return [pscustomobject]$copy
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        return @($Value | ForEach-Object { Copy-HostCapabilitySnapshotValue $_ })
    }
    return $Value
}

function Get-HostCapabilitySnapshotSourcePrecedence {
    return @('turn_override', 'thread_runtime', 'config_layered', 'model_catalog', 'unknown_fallback')
}

function Get-HostCapabilitySnapshotCapabilityNames {
    return @('model', 'context_window', 'metadata_budget', 'skills_inventory')
}

function New-HostCapabilityFact {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        $Value,
        [Parameter(Mandatory = $true)][string]$Source,
        [string]$CapturedAt,
        [ValidateSet('fresh', 'stale', 'unknown')][string]$Freshness = 'unknown',
        [string]$UnknownReason
    )

    return [pscustomobject][ordered]@{
        name = $Name
        value = Copy-HostCapabilitySnapshotValue $Value
        source = $Source
        captured_at = if ([string]::IsNullOrWhiteSpace($CapturedAt)) { $null } else { $CapturedAt }
        freshness = $Freshness
        unknown_reason = if ([string]::IsNullOrWhiteSpace($UnknownReason)) { $null } else { $UnknownReason.Trim() }
    }
}

function New-HostCapabilitySnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Surface,
        [Parameter(Mandatory = $true)][string]$CapturedAt,
        [string]$ThreadId,
        [string]$TurnId,
        [Parameter(Mandatory = $true)]$Capabilities,
        [string[]]$SourcePrecedence = (Get-HostCapabilitySnapshotSourcePrecedence),
        [string[]]$UnknownReasons = @()
    )

    $normalizedCapabilities = [ordered]@{}
    foreach ($name in Get-HostCapabilitySnapshotCapabilityNames) {
        $fact = Get-OperationObjectProperty $Capabilities $name
        $normalizedCapabilities[$name] = $fact
    }

    $identity = [ordered]@{
        surface = $Surface.Trim()
        thread_id = if ([string]::IsNullOrWhiteSpace($ThreadId)) { $null } else { $ThreadId.Trim() }
        turn_id = if ([string]::IsNullOrWhiteSpace($TurnId)) { $null } else { $TurnId.Trim() }
        captured_at = $CapturedAt
        capabilities = $normalizedCapabilities
        source_precedence = @($SourcePrecedence)
    }
    $snapshotId = 'hcs-{0}' -f (Get-OperationSha256 ($identity | ConvertTo-Json -Depth 30 -Compress)).Substring(0, 16)

    return [pscustomobject][ordered]@{
        schema_version = 1
        snapshot_id = $snapshotId
        surface = $identity.surface
        thread_id = $identity.thread_id
        turn_id = $identity.turn_id
        captured_at = $CapturedAt
        source_precedence = @($SourcePrecedence)
        capabilities = [pscustomobject]$normalizedCapabilities
        unknown_reasons = @($UnknownReasons | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    }
}

function Test-HostCapabilitySnapshotContract {
    param([Parameter(Mandatory = $false)]$Snapshot)

    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Snapshot) {
        return New-OperationValidationResult @((New-OperationFinding 'host_snapshot_missing' 'error' '$' 'Host capability snapshot is required.'))
    }
    if ((Get-OperationObjectProperty $Snapshot 'schema_version') -ne 1) { $findings.Add((New-OperationFinding 'schema_version_invalid' 'error' '$.schema_version' 'Only HostCapabilitySnapshot schema version 1 is supported.')) | Out-Null }
    foreach ($field in @('snapshot_id', 'surface', 'captured_at')) {
        if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $Snapshot $field))) { $findings.Add((New-OperationFinding 'required_field_missing' 'error' ('$.{0}' -f $field) 'Required snapshot field is missing.')) | Out-Null }
    }
    if ([string](Get-OperationObjectProperty $Snapshot 'snapshot_id') -notmatch '^hcs-[a-f0-9]{16}$') { $findings.Add((New-OperationFinding 'snapshot_id_invalid' 'error' '$.snapshot_id' 'Snapshot id must be a deterministic hcs hash.')) | Out-Null }
    if (-not (Test-OperationRfc3339 (Get-OperationObjectProperty $Snapshot 'captured_at'))) { $findings.Add((New-OperationFinding 'captured_at_invalid' 'error' '$.captured_at' 'Snapshot captured_at must be RFC3339.')) | Out-Null }

    $expectedPrecedence = @(Get-HostCapabilitySnapshotSourcePrecedence)
    $actualPrecedence = @((Get-OperationObjectProperty $Snapshot 'source_precedence') | ForEach-Object { [string]$_ })
    if (-not (Test-OperationArray (Get-OperationObjectProperty $Snapshot 'source_precedence')) -or ($actualPrecedence -join '|') -ne ($expectedPrecedence -join '|')) {
        $findings.Add((New-OperationFinding 'source_precedence_invalid' 'error' '$.source_precedence' 'Snapshot source precedence must be turn, thread, config, catalog, then unknown fallback.')) | Out-Null
    }

    $capabilities = Get-OperationObjectProperty $Snapshot 'capabilities'
    if ($null -eq $capabilities) {
        $findings.Add((New-OperationFinding 'capabilities_missing' 'error' '$.capabilities' 'Snapshot capabilities are required.')) | Out-Null
    }
    else {
        foreach ($name in Get-HostCapabilitySnapshotCapabilityNames) {
            $path = '$.capabilities.{0}' -f $name
            $fact = Get-OperationObjectProperty $capabilities $name
            if ($null -eq $fact) { $findings.Add((New-OperationFinding 'capability_fact_missing' 'error' $path 'Every capability fact is required.')); continue }
            foreach ($field in @('source', 'freshness')) {
                if ([string]::IsNullOrWhiteSpace([string](Get-OperationObjectProperty $fact $field))) { $findings.Add((New-OperationFinding 'fact_field_missing' 'error' ($path + '.' + $field) 'Capability fact field is required.')) | Out-Null }
            }
            if ([string](Get-OperationObjectProperty $fact 'source') -notin $expectedPrecedence) { $findings.Add((New-OperationFinding 'fact_source_invalid' 'error' ($path + '.source') 'Capability fact source is not in the declared precedence.')) | Out-Null }
            if ([string](Get-OperationObjectProperty $fact 'freshness') -notin @('fresh', 'stale', 'unknown')) { $findings.Add((New-OperationFinding 'fact_freshness_invalid' 'error' ($path + '.freshness') 'Capability fact freshness is invalid.')) | Out-Null }
            $factCapturedAt = Get-OperationObjectProperty $fact 'captured_at'
            if ($null -ne $factCapturedAt -and -not (Test-OperationRfc3339 $factCapturedAt)) { $findings.Add((New-OperationFinding 'fact_captured_at_invalid' 'error' ($path + '.captured_at') 'Capability fact captured_at must be RFC3339 when present.')) | Out-Null }
            $unknownReason = [string](Get-OperationObjectProperty $fact 'unknown_reason')
            if ([string](Get-OperationObjectProperty $fact 'freshness') -eq 'unknown' -and [string]::IsNullOrWhiteSpace($unknownReason)) { $findings.Add((New-OperationFinding 'unknown_reason_missing' 'error' ($path + '.unknown_reason') 'Unknown facts must expose an unknown reason.')) | Out-Null }
            $value = Get-OperationObjectProperty $fact 'value'
            if ($name -eq 'context_window' -and $null -ne $value) {
                $number = 0L
                if (-not [long]::TryParse([string]$value, [ref]$number) -or $number -le 0) { $findings.Add((New-OperationFinding 'context_window_invalid' 'error' ($path + '.value') 'Context window must be a positive integer when known.')) | Out-Null }
            }
            if ($name -eq 'metadata_budget' -and $null -ne $value) {
                $number = 0L
                if (-not [long]::TryParse([string]$value, [ref]$number) -or $number -lt 0) { $findings.Add((New-OperationFinding 'metadata_budget_invalid' 'error' ($path + '.value') 'Metadata budget must be a non-negative integer when known.')) | Out-Null }
            }
            if ($name -eq 'skills_inventory' -and $null -ne $value -and -not (Test-OperationArray $value)) { $findings.Add((New-OperationFinding 'skills_inventory_invalid' 'error' ($path + '.value') 'Skills inventory must be an array when known.')) | Out-Null }
            if ($name -eq 'model' -and $null -ne $value -and [string]::IsNullOrWhiteSpace([string]$value)) { $findings.Add((New-OperationFinding 'model_invalid' 'error' ($path + '.value') 'Model must be non-empty when known.')) | Out-Null }
        }
    }
    if (-not (Test-OperationArray (Get-OperationObjectProperty $Snapshot 'unknown_reasons'))) { $findings.Add((New-OperationFinding 'unknown_reasons_invalid' 'error' '$.unknown_reasons' 'unknown_reasons must be an array.')) | Out-Null }
    return New-OperationValidationResult $findings.ToArray()
}
