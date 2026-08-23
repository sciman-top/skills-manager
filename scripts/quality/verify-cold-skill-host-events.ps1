#Requires -Version 7
<#
.SYNOPSIS
Fail-closed verifier for raw Codex JSONL host events in cold-skill acceptance.

.DESCRIPTION
The router receipt proves only candidate validation. This verifier consumes the
raw event stream emitted by a fresh host run and rejects a multi-turn receipt
unless the stream contains an actual native spawn with a child identifier. It
also rejects bare waits, forbidden discovery, and more than one discovery
attempt. It never starts a host, calls a provider, or writes files.

Stable finding codes:
  H001_EVENTS_SCHEMA_INVALID
  H002_SCENARIO_NOT_IN_MATRIX
  H003_FORBIDDEN_DISCOVERY_OBSERVED
  H004_MULTIPLE_DISCOVERY_ATTEMPTS
  H005_NATIVE_CHILD_SPAWN_MISSING
  H006_BARE_WAIT_WITHOUT_CHILD
  H007_SPAWN_IDENTIFIER_MISSING
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$EventsPath,
    [Parameter(Mandatory = $true)][string]$ScenarioId,
    [string]$ScenarioMatrixPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
if ([string]::IsNullOrWhiteSpace($ScenarioMatrixPath)) {
    $ScenarioMatrixPath = Join-Path $repoRoot 'tests\fixtures\cold-skill-routing\scenarios.json'
}

$findings = New-Object System.Collections.Generic.List[string]
function Add-Finding([string]$Code, [string]$Message) {
    $findings.Add(('{0}: {1}' -f $Code, $Message)) | Out-Null
}

$scenario = $null
try {
    $matrix = Get-Content -LiteralPath $ScenarioMatrixPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $matches = @($matrix.scenarios | Where-Object { [string]$_.id -eq $ScenarioId })
    if ($matches.Count -ne 1) { throw 'scenario id is absent or duplicated' }
    $scenario = $matches[0]
}
catch {
    Add-Finding 'H002_SCENARIO_NOT_IN_MATRIX' ("{0}: {1}" -f $ScenarioId, $_.Exception.Message)
}

$events = New-Object System.Collections.Generic.List[object]
try {
    if (-not (Test-Path -LiteralPath $EventsPath -PathType Leaf)) { throw 'events file is missing' }
    foreach ($line in @(Get-Content -LiteralPath $EventsPath -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $event = $line | ConvertFrom-Json
            if ($null -ne $event -and -not [string]::IsNullOrWhiteSpace([string]$event.type)) { $events.Add($event) | Out-Null }
        }
        catch {
            # Codex may emit a non-JSON stdin notice before JSONL. It has no
            # evidentiary value and is deliberately ignored.
        }
    }
    if ($events.Count -eq 0) { throw 'no JSONL event with a type field was found' }
}
catch {
    Add-Finding 'H001_EVENTS_SCHEMA_INVALID' $_.Exception.Message
}

if ($null -ne $scenario -and $events.Count -gt 0) {
    $completedItems = @($events | Where-Object {
        $_.type -eq 'item.completed' -and $null -ne $_.item
    } | ForEach-Object { $_.item })
    $terminalCommands = @($completedItems | Where-Object {
        $_.type -eq 'command_execution' -and [string]$_.status -in @('completed', 'failed')
    })
    $routerCommands = @($terminalCommands | Where-Object {
        [string]$_.command -match '(?i)route-capability\.ps1' -and [string]$_.command -match '(?i)-AutoDiscover'
    })
    $discoveryCommands = @($routerCommands | Where-Object { [string]$_.command -notmatch '(?i)-Candidate' })

    if ([string]$scenario.cold_discovery -eq 'forbidden' -and $routerCommands.Count -gt 0) {
        Add-Finding 'H003_FORBIDDEN_DISCOVERY_OBSERVED' ("{0}: {1} router invocation(s) occurred in a discovery-forbidden scenario" -f $ScenarioId, $routerCommands.Count)
    }
    if ($discoveryCommands.Count -gt 1) {
        Add-Finding 'H004_MULTIPLE_DISCOVERY_ATTEMPTS' ("{0}: observed {1} AutoDiscover calls without a selected candidate" -f $ScenarioId, $discoveryCommands.Count)
    }

    $requiresNativeChild = ([string]$scenario.execution_contract -eq 'multi_turn_user_decision') -or
        (-not [string]::IsNullOrWhiteSpace([string]$scenario.expected_native_agent))
    if ($requiresNativeChild) {
        $collaborationEvents = @($completedItems | Where-Object { $_.type -eq 'collab_tool_call' })
        $spawnEvents = @($collaborationEvents | Where-Object { [string]$_.tool -eq 'spawn_agent' })
        $spawnWithChildId = @($spawnEvents | Where-Object { @($_.receiver_thread_ids | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0 })
        $bareWaits = @($collaborationEvents | Where-Object {
            [string]$_.tool -eq 'wait' -and @($_.receiver_thread_ids | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -eq 0
        })

        if ($spawnEvents.Count -eq 0) {
            Add-Finding 'H005_NATIVE_CHILD_SPAWN_MISSING' ("{0}: native-child contract has no completed spawn_agent event" -f $ScenarioId)
        }
        elseif ($spawnWithChildId.Count -eq 0) {
            Add-Finding 'H007_SPAWN_IDENTIFIER_MISSING' ("{0}: spawn_agent event has no child identifier" -f $ScenarioId)
        }
        if ($bareWaits.Count -gt 0) {
            Add-Finding 'H006_BARE_WAIT_WITHOUT_CHILD' ("{0}: observed {1} wait event(s) without a child identifier" -f $ScenarioId, $bareWaits.Count)
        }
    }
}

if ($findings.Count -gt 0) {
    foreach ($finding in @($findings)) { Write-Output ("FINDING {0}" -f $finding) }
    Write-Output ("verify-cold-skill-host-events: fail findings={0}" -f $findings.Count)
    exit 1
}

Write-Output 'verify-cold-skill-host-events: pass findings=0'
exit 0
