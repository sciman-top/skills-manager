$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
$tracePath = Join-Path $repoRoot 'src\Domain\NativeInvocationTrace.ps1'
$adapterPath = Join-Path $repoRoot 'src\Infrastructure\NativeInvocationTraceAdapters.ps1'
if (Test-Path -LiteralPath $tracePath -PathType Leaf) { . $tracePath }
if (Test-Path -LiteralPath $adapterPath -PathType Leaf) { . $adapterPath }

function New-TraceEvent {
    param([string]$Kind, [string]$Name = 'grill-with-docs', [string]$EventId = 'evt-1')
    return [pscustomobject][ordered]@{
        event_id = $EventId
        kind = $Kind
        skill_name = $Name
        occurred_at = '2026-08-07T06:00:00Z'
        correlation_id = 'thread-secret-123'
        reason = $null
        payload = $null
    }
}

Describe 'Native invocation trace' {
    It 'keeps listed visibility separate from invocation' {
        $trace = New-NativeInvocationTrace -TraceId 'trace-listed' -Surface 'cli' -Source 'cli' -Freshness 'fresh' -CapturedAt '2026-08-07T06:00:01Z' -Events @((New-TraceEvent 'listed'))

        $trace.truth_level | Should Be 'host_evaluation_partial'
        $trace.stages.listed.observed | Should Be $true
        $trace.stages.selected.observed | Should Be $false
        $trace.stages.injected.observed | Should Be $false
        $trace.stages.executed.observed | Should Be $false
        $trace.invocation_observable | Should Be $false
        (Test-NativeInvocationTraceContract $trace).pass | Should Be $true
    }

    It 'keeps injection without execution at a partial truth level' {
        $events = @((New-TraceEvent 'listed' -EventId 'evt-listed'), (New-TraceEvent 'selected' -EventId 'evt-selected'), (New-TraceEvent 'injected' -EventId 'evt-injected'))
        $trace = New-NativeInvocationTrace -TraceId 'trace-injected' -Surface 'app_server' -Source 'app_server' -Freshness 'fresh' -CapturedAt '2026-08-07T06:00:01Z' -Events $events

        $trace.stages.injected.observed | Should Be $true
        $trace.stages.executed.observed | Should Be $false
        $trace.body_injection_observable | Should Be $true
        $trace.invocation_observable | Should Be $false
        $trace.truth_level | Should Be 'host_evaluation_partial'
        (Test-NativeInvocationTraceContract $trace).pass | Should Be $true
    }

    It 'records abstention explicitly without promoting it to execution' {
        $event = New-TraceEvent 'abstained'
        $event.reason = 'negative_constraint'
        $trace = New-NativeInvocationTrace -TraceId 'trace-abstained' -Surface 'cli' -Source 'cli' -Freshness 'fresh' -CapturedAt '2026-08-07T06:00:01Z' -Events @($event)

        $trace.outcome | Should Be 'abstained'
        $trace.stages.abstained.observed | Should Be $true
        $trace.stages.executed.observed | Should Be $false
        $trace.invocation_observable | Should Be $false
        $trace.truth_level | Should Be 'host_evaluation_partial'
        (Test-NativeInvocationTraceContract $trace).pass | Should Be $true
    }

    It 'fails closed on unknown events and redacts correlation and payload secrets' {
        $event = New-TraceEvent 'skill_loaded'
        $event.payload = [pscustomobject]@{ authorization = 'Bearer trace-secret'; args = @('api_key=trace-secret') }
        $trace = ConvertTo-NativeInvocationTrace -Events @($event) -TraceId 'trace-unknown' -Surface 'app_server' -Source 'app_server' -Freshness 'fresh' -CapturedAt '2026-08-07T06:00:01Z'
        $serialized = $trace | ConvertTo-Json -Depth 30 -Compress

        $trace.truth_level | Should Be 'unknown'
        $trace.status | Should Be 'unknown'
        $trace.invocation_observable | Should Be $false
        $serialized | Should Not Match 'trace-secret|thread-secret-123'
        $trace.redaction.applied | Should Be $true
        @($trace.findings | Where-Object code -eq 'unknown_event_type').Count | Should Be 1
        (Test-NativeInvocationTraceContract $trace).pass | Should Be $false
    }
}
