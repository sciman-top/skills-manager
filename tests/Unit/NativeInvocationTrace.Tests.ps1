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

        $trace.truth_level | Should Be 'host_inventory_loaded'
        $trace.stages.listed.observed | Should Be $true
        $trace.stages.selected.observed | Should Be $false
        $trace.stages.injected.observed | Should Be $false
        $trace.stages.executed.observed | Should Be $false
        $trace.invocation_observable | Should Be $false
        (Test-NativeInvocationTraceContract $trace).pass | Should Be $true
    }

    It 'promotes only fresh injected and executed evidence to invocation observed' {
        $events = @(
            (New-TraceEvent 'listed' -EventId 'evt-listed'),
            (New-TraceEvent 'selected' -EventId 'evt-selected'),
            (New-TraceEvent 'injected' -EventId 'evt-injected'),
            (New-TraceEvent 'executed' -EventId 'evt-executed')
        )
        $trace = New-NativeInvocationTrace -TraceId 'trace-executed' -Surface 'app_server' -Source 'app_server' -Freshness 'fresh' -CapturedAt '2026-08-07T06:00:01Z' -Events $events

        $trace.truth_level | Should Be 'host_invocation_observed'
        $trace.stages.injected.observed | Should Be $true
        $trace.stages.executed.observed | Should Be $true
        $trace.invocation_observable | Should Be $true
        $trace.receipt.complete | Should Be $true
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

    It 'does not combine injection and execution from different skills or correlations' {
        $events = @(
            [pscustomobject]@{ event_id = 'evt-injected-a'; kind = 'injected'; skill_name = 'skill-a'; occurred_at = '2026-08-07T06:00:02Z'; correlation_id = 'corr-a' }
            [pscustomobject]@{ event_id = 'evt-executed-b'; kind = 'executed'; skill_name = 'skill-b'; occurred_at = '2026-08-07T06:00:01Z'; correlation_id = 'corr-b' }
        )
        $trace = New-NativeInvocationTrace -TraceId 'trace-mixed-chain' -Surface 'app_server' -Source 'fixture' -Freshness 'fresh' -CapturedAt '2026-08-07T06:00:03Z' -Events $events

        $trace.truth_level | Should Be 'unknown'
        $trace.invocation_observable | Should Be $false
        @($trace.findings | Where-Object code -eq 'invocation_chain_missing').Count | Should Be 1
        (Test-NativeInvocationTraceContract $trace).pass | Should Be $false
    }

    It 'does not promote execution that occurs before injection in the same chain' {
        $events = @(
            [pscustomobject]@{ event_id = 'evt-executed'; kind = 'executed'; skill_name = 'skill-a'; occurred_at = '2026-08-07T06:00:01Z'; correlation_id = 'corr-a' }
            [pscustomobject]@{ event_id = 'evt-injected'; kind = 'injected'; skill_name = 'skill-a'; occurred_at = '2026-08-07T06:00:02Z'; correlation_id = 'corr-a' }
        )
        $trace = New-NativeInvocationTrace -TraceId 'trace-out-of-order' -Surface 'app_server' -Source 'fixture' -Freshness 'fresh' -CapturedAt '2026-08-07T06:00:03Z' -Events $events

        $trace.truth_level | Should Be 'unknown'
        $trace.invocation_observable | Should Be $false
        @($trace.findings | Where-Object code -eq 'invocation_stage_order_invalid').Count | Should Be 1
        (Test-NativeInvocationTraceContract $trace).pass | Should Be $false
    }

    It 'does not treat another skill abstaining as a conflict with a valid execution chain' {
        $events = @(
            [pscustomobject]@{ event_id = 'evt-injected-a'; kind = 'injected'; skill_name = 'skill-a'; occurred_at = '2026-08-07T06:00:01Z'; correlation_id = 'corr-a' }
            [pscustomobject]@{ event_id = 'evt-executed-a'; kind = 'executed'; skill_name = 'skill-a'; occurred_at = '2026-08-07T06:00:02Z'; correlation_id = 'corr-a' }
            [pscustomobject]@{ event_id = 'evt-abstained-b'; kind = 'abstained'; skill_name = 'skill-b'; occurred_at = '2026-08-07T06:00:02Z'; correlation_id = 'corr-b' }
        )
        $trace = New-NativeInvocationTrace -TraceId 'trace-mixed-outcomes' -Surface 'app_server' -Source 'fixture' -Freshness 'fresh' -CapturedAt '2026-08-07T06:00:03Z' -Events $events

        $trace.truth_level | Should Be 'host_invocation_observed'
        $trace.invocation_observable | Should Be $true
        @($trace.findings | Where-Object code -eq 'outcome_conflict').Count | Should Be 0
        (Test-NativeInvocationTraceContract $trace).pass | Should Be $true
    }

    It 'does not promote a valid invocation chain when the same trace contains an unknown event' {
        $events = @(
            [pscustomobject]@{ event_id = 'evt-injected'; kind = 'injected'; skill_name = 'skill-a'; occurred_at = '2026-08-07T06:00:01Z'; correlation_id = 'corr-a' }
            [pscustomobject]@{ event_id = 'evt-executed'; kind = 'executed'; skill_name = 'skill-a'; occurred_at = '2026-08-07T06:00:02Z'; correlation_id = 'corr-a' }
            [pscustomobject]@{ event_id = 'evt-unknown'; kind = 'host-internal-unknown'; skill_name = 'skill-a'; occurred_at = '2026-08-07T06:00:03Z'; correlation_id = 'corr-a' }
        )
        $trace = New-NativeInvocationTrace -TraceId 'trace-mixed-unknown' -Surface 'app_server' -Source 'fixture' -Freshness 'fresh' -CapturedAt '2026-08-07T06:00:04Z' -Events $events

        $trace.truth_level | Should Be 'unknown'
        $trace.invocation_observable | Should Be $false
        @($trace.findings | Where-Object code -eq 'unknown_event_type').Count | Should Be 1
        (Test-NativeInvocationTraceContract $trace).pass | Should Be $false
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

    It 'keeps self-report and file-read heuristics at partial truth' {
        $events = @((New-TraceEvent 'injected' -EventId 'evt-injected'), (New-TraceEvent 'executed' -EventId 'evt-executed'))
        foreach ($mode in @('self_report', 'read_heuristic')) {
            $trace = New-NativeInvocationTrace -TraceId ('trace-' + $mode) -Surface 'cli' -Source 'cli' -Freshness 'fresh' -CapturedAt '2026-08-07T06:00:01Z' -InvocationMode $mode -Events $events
            $trace.truth_level | Should Be 'host_evaluation_partial'
            $trace.invocation_observable | Should Be $false
            @($trace.findings.code) | Should -Contain 'invocation_mode_partial'
            (Test-NativeInvocationTraceContract $trace).pass | Should Be $true
        }
    }

    It 'does not promote stale native events' {
        $events = @((New-TraceEvent 'injected' -EventId 'evt-injected'), (New-TraceEvent 'executed' -EventId 'evt-executed'))
        $trace = New-NativeInvocationTrace -TraceId 'trace-stale' -Surface 'cli' -Source 'cli' -Freshness 'stale' -CapturedAt '2026-08-07T06:00:01Z' -InvocationMode native_events -Events $events
        $trace.truth_level | Should Be 'unknown'
        $trace.invocation_observable | Should Be $false
    }

    It 'requires an explicit correlation on both injected and executed events' {
        $events = @(
            [pscustomobject]@{ event_id = 'evt-injected'; kind = 'injected'; skill_name = 'skill-a'; occurred_at = '2026-08-07T06:00:01Z'; correlation_id = '' }
            [pscustomobject]@{ event_id = 'evt-executed'; kind = 'executed'; skill_name = 'skill-a'; occurred_at = '2026-08-07T06:00:02Z'; correlation_id = '' }
        )
        $trace = New-NativeInvocationTrace -TraceId 'trace-no-correlation' -Surface 'app_server' -Source 'native_host' -Freshness 'fresh' -CapturedAt '2026-08-07T06:00:03Z' -InvocationMode native_events -Events $events
        $trace.truth_level | Should Be 'unknown'
        @($trace.findings.code) | Should -Contain 'invocation_correlation_missing'
        (Test-NativeInvocationTraceContract $trace).pass | Should Be $false
    }
}
