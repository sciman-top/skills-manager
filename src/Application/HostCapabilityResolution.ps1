function Get-HostCapabilityCandidate {
    param(
        $Payload,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Source
    )

    if ($null -eq $Payload -or -not (Test-OperationObjectProperty $Payload $Name)) {
        return [pscustomobject]@{ present = $false; source = $Source; value = $null; captured_at = $null; freshness = 'unknown'; unknown_reason = $null }
    }

    $raw = Get-OperationObjectProperty $Payload $Name
    $value = $raw
    $capturedAt = $null
    $freshness = 'unknown'
    $unknownReason = $null
    if ($null -ne $raw -and (Test-OperationObjectProperty $raw 'value')) {
        $value = Get-OperationObjectProperty $raw 'value'
        $capturedAt = [string](Get-OperationObjectProperty $raw 'captured_at')
        $freshness = [string](Get-OperationObjectProperty $raw 'freshness')
        $unknownReason = [string](Get-OperationObjectProperty $raw 'unknown_reason')
    }
    if ($freshness -notin @('fresh', 'stale', 'unknown')) { $freshness = 'unknown' }
    if ($Source -eq 'unknown_fallback' -and [string]::IsNullOrWhiteSpace($unknownReason) -and $freshness -eq 'unknown') { $unknownReason = '{0}_unknown' -f $Name }
    return [pscustomobject]@{
        present = $true
        source = $Source
        value = $value
        captured_at = if ([string]::IsNullOrWhiteSpace($capturedAt)) { $null } else { $capturedAt }
        freshness = $freshness
        unknown_reason = if ([string]::IsNullOrWhiteSpace($unknownReason)) { $null } else { $unknownReason.Trim() }
    }
}

function Test-HostCapabilityCandidateValue {
    param([Parameter(Mandatory = $true)][string]$Name, $Value)

    if ($Name -eq 'model') {
        if ($null -eq $Value) { return $false }
        if ($Value -is [pscustomobject] -or $Value -is [System.Collections.IDictionary]) { return @($Value.PSObject.Properties).Count -gt 0 -or @($Value.Keys).Count -gt 0 }
        return -not [string]::IsNullOrWhiteSpace([string]$Value)
    }
    if ($Name -eq 'context_window') {
        $number = 0L
        return $null -ne $Value -and [long]::TryParse([string]$Value, [ref]$number) -and $number -gt 0
    }
    if ($Name -eq 'metadata_budget') {
        $number = 0L
        return $null -ne $Value -and [long]::TryParse([string]$Value, [ref]$number) -and $number -ge 0
    }
    if ($Name -eq 'skills_inventory') { return $null -ne $Value -and (Test-OperationArray $Value) }
    return $false
}

function Resolve-HostCapabilityFact {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [object[]]$Sources = @(),
        $UnknownFallback,
        [System.Collections.Generic.List[string]]$UnknownReasons
    )

    foreach ($source in @($Sources)) {
        $candidate = Get-HostCapabilityCandidate -Payload (Get-OperationObjectProperty $source 'payload') -Name $Name -Source ([string](Get-OperationObjectProperty $source 'source'))
        if (-not [bool]$candidate.present) { continue }
        if (Test-HostCapabilityCandidateValue -Name $Name -Value $candidate.value) {
            return New-HostCapabilityFact -Name $Name -Value $candidate.value -Source $candidate.source -CapturedAt $candidate.captured_at -Freshness $candidate.freshness -UnknownReason $candidate.unknown_reason
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate.unknown_reason) -and $null -ne $UnknownReasons) { $UnknownReasons.Add(('{0}:{1}' -f $candidate.source, $candidate.unknown_reason)) | Out-Null }
    }

    $fallback = Get-HostCapabilityCandidate -Payload $UnknownFallback -Name $Name -Source 'unknown_fallback'
    if (Test-HostCapabilityCandidateValue -Name $Name -Value $fallback.value) {
        return New-HostCapabilityFact -Name $Name -Value $fallback.value -Source 'unknown_fallback' -CapturedAt $fallback.captured_at -Freshness 'unknown' -UnknownReason $fallback.unknown_reason
    }
    $reason = if ([string]::IsNullOrWhiteSpace([string]$fallback.unknown_reason)) { '{0}_unknown' -f $Name } else { [string]$fallback.unknown_reason }
    if ($null -ne $UnknownReasons) { $UnknownReasons.Add($reason) | Out-Null }
    return New-HostCapabilityFact -Name $Name -Value $null -Source 'unknown_fallback' -CapturedAt $fallback.captured_at -Freshness 'unknown' -UnknownReason $reason
}

function Resolve-HostCapabilitySnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Surface,
        [Parameter(Mandatory = $true)][string]$CapturedAt,
        [string]$ThreadId,
        [string]$TurnId,
        $TurnOverride,
        $ThreadRuntime,
        $ConfigLayered,
        $ModelCatalog,
        $UnknownFallback
    )

    if ($null -eq $UnknownFallback) {
        $UnknownFallback = [pscustomobject]@{
            model = [pscustomobject]@{ value = $null; freshness = 'unknown'; unknown_reason = 'effective_model_unknown' }
            context_window = [pscustomobject]@{ value = $null; freshness = 'unknown'; unknown_reason = 'context_window_unknown' }
            metadata_budget = [pscustomobject]@{ value = $null; freshness = 'unknown'; unknown_reason = 'metadata_budget_unknown' }
            skills_inventory = [pscustomobject]@{ value = $null; freshness = 'unknown'; unknown_reason = 'skills_inventory_unknown' }
        }
    }

    $sources = @(
        [pscustomobject]@{ source = 'turn_override'; payload = $TurnOverride },
        [pscustomobject]@{ source = 'thread_runtime'; payload = $ThreadRuntime },
        [pscustomobject]@{ source = 'config_layered'; payload = $ConfigLayered },
        [pscustomobject]@{ source = 'model_catalog'; payload = $ModelCatalog }
    )
    $unknownReasons = New-Object System.Collections.Generic.List[string]
    $capabilities = [ordered]@{}
    foreach ($name in Get-HostCapabilitySnapshotCapabilityNames) {
        $capabilities[$name] = Resolve-HostCapabilityFact -Name $name -Sources $sources -UnknownFallback $UnknownFallback -UnknownReasons $unknownReasons
    }

    return New-HostCapabilitySnapshot -Surface $Surface -ThreadId $ThreadId -TurnId $TurnId -CapturedAt $CapturedAt -Capabilities $capabilities -UnknownReasons $unknownReasons.ToArray()
}
