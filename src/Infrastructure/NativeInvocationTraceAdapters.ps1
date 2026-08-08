if ($null -eq (Get-Command New-NativeInvocationTrace -ErrorAction SilentlyContinue)) {
    $tracePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Domain\NativeInvocationTrace.ps1'
    . $tracePath
}

function Get-NativeInvocationAdapterProperty($Object, [string[]]$Names) {
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

function Resolve-NativeInvocationEventKind($Event) {
    $raw = ([string](Get-NativeInvocationAdapterProperty $Event @('kind', 'stage', 'event_type', 'type'))).Trim().ToLowerInvariant()
    switch -Regex ($raw) {
        '^(listed|list|skills/list|skill_list|skill_listed)$' { return 'listed' }
        '^(selected|select|skill_selected|skill/selected|selection)$' { return 'selected' }
        '^(injected|skill_injected|skill/injected|skills/injected)$' { return 'injected' }
        '^(executed|execute|skill_executed|skill/invoked|skill_invoked|invocation)$' { return 'executed' }
        '^(abstained|abstain|skill_abstained|skill/abstained|selection_abstained)$' { return 'abstained' }
        default { return $raw }
    }
}

function ConvertTo-NativeInvocationTrace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Events,
        [Parameter(Mandatory = $true)][string]$TraceId,
        [Parameter(Mandatory = $true)][string]$Surface,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][ValidateSet('fresh', 'stale', 'unknown')][string]$Freshness,
        [Parameter(Mandatory = $true)][string]$CapturedAt
    )

    $normalized = New-Object System.Collections.Generic.List[object]
    foreach ($event in @($Events)) {
        $capability = Get-NativeInvocationAdapterProperty $event @('capability', 'skill_item')
        $name = [string](Get-NativeInvocationAdapterProperty $event @('skill_name', 'name', 'skill'))
        if ([string]::IsNullOrWhiteSpace($name) -and $null -ne $capability) { $name = [string](Get-NativeInvocationAdapterProperty $capability @('name', 'id', 'skill')) }
        $normalized.Add([pscustomobject][ordered]@{
                event_id = [string](Get-NativeInvocationAdapterProperty $event @('event_id', 'id'))
                kind = Resolve-NativeInvocationEventKind $event
                skill_name = $name
                occurred_at = [string](Get-NativeInvocationAdapterProperty $event @('occurred_at', 'timestamp', 'captured_at'))
                correlation_id = [string](Get-NativeInvocationAdapterProperty $event @('correlation_id', 'correlation', 'turn_id', 'thread_id'))
                reason = [string](Get-NativeInvocationAdapterProperty $event @('reason', 'abstention_reason'))
            }) | Out-Null
    }
    return New-NativeInvocationTrace -TraceId $TraceId -Surface $Surface -Source $Source -Freshness $Freshness -CapturedAt $CapturedAt -Events $normalized.ToArray()
}

function New-NativeInvocationTraceFromHostEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Events,
        [Parameter(Mandatory = $true)][string]$TraceId,
        [Parameter(Mandatory = $true)][string]$Surface,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][ValidateSet('fresh', 'stale', 'unknown')][string]$Freshness,
        [Parameter(Mandatory = $true)][string]$CapturedAt
    )
    return ConvertTo-NativeInvocationTrace -Events $Events -TraceId $TraceId -Surface $Surface -Source $Source -Freshness $Freshness -CapturedAt $CapturedAt
}
