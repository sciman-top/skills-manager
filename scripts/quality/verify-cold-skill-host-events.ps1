#Requires -Version 7
<#
.SYNOPSIS
Fail-closed verifier for raw Codex JSONL host events in cold-skill acceptance.

.DESCRIPTION
The router receipt proves only candidate validation. This verifier consumes the
raw event stream emitted by a fresh host run and rejects a multi-turn receipt
unless the stream contains an actual native spawn with a child identifier. Some
`codex exec --json` parent streams omit that spawn event and retain only a bare
wait. For that documented evidence shape, pass one explicit child rollout via
`-ChildRolloutPath`: its session metadata must bind exactly to the host thread
and expected native-agent role before it can witness the spawn. It also rejects
bare waits without either native-child proof, forbidden discovery, and more
than one discovery attempt. It never starts a host, calls a provider, or writes
files.

Stable finding codes:
  H001_EVENTS_SCHEMA_INVALID
  H002_SCENARIO_NOT_IN_MATRIX
  H003_FORBIDDEN_DISCOVERY_OBSERVED
  H004_MULTIPLE_DISCOVERY_ATTEMPTS
  H005_NATIVE_CHILD_SPAWN_MISSING
  H006_BARE_WAIT_WITHOUT_CHILD
  H007_SPAWN_IDENTIFIER_MISSING
  H008_ROLLOUT_CHILD_EVIDENCE_INVALID
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$EventsPath,
    [Parameter(Mandatory = $true)][string]$ScenarioId,
    [string]$ScenarioMatrixPath,
    [string]$ChildRolloutPath
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

function Get-ChildRolloutEvidence {
    param(
        [string]$Path,
        [string]$HostThreadId,
        [string]$ExpectedAgentRole
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }

    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'child rollout file is missing' }
        $sessionMetas = New-Object System.Collections.Generic.List[object]
        foreach ($line in @(Get-Content -LiteralPath $Path -Encoding UTF8)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $record = $line | ConvertFrom-Json
                if ($null -ne $record -and [string]$record.type -eq 'session_meta') { $sessionMetas.Add($record) | Out-Null }
            }
            catch {
                # Non-JSON lines cannot establish rollout provenance.
            }
        }
        if ($sessionMetas.Count -ne 1) { throw ("expected exactly one session_meta record, found {0}" -f $sessionMetas.Count) }

        $payload = $sessionMetas[0].payload
        $childId = [string]$payload.id
        $sessionParent = [string]$payload.session_id
        $declaredParent = [string]$payload.parent_thread_id
        $spawnParent = [string]$payload.source.subagent.thread_spawn.parent_thread_id
        $agentRole = [string]$payload.agent_role
        if ([string]::IsNullOrWhiteSpace($HostThreadId)) { throw 'host event stream has no thread.started thread_id to bind the child rollout' }
        if ([string]::IsNullOrWhiteSpace($childId)) { throw 'child rollout session_meta lacks payload.id' }
        $blankParents = @(@($sessionParent, $declaredParent, $spawnParent) | Where-Object { [string]::IsNullOrWhiteSpace($_) })
        if ($blankParents.Count -gt 0) {
            throw 'child rollout lacks one or more parent-thread bindings'
        }
        $mismatchedParents = @(@($sessionParent, $declaredParent, $spawnParent) | Where-Object { $_ -ne $HostThreadId })
        if ($mismatchedParents.Count -gt 0) {
            throw 'child rollout parent bindings do not all match the host thread.started thread_id'
        }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedAgentRole) -and $agentRole -ne $ExpectedAgentRole) {
            throw ("child rollout agent_role '{0}' does not match expected '{1}'" -f $agentRole, $ExpectedAgentRole)
        }
        return [pscustomobject]@{ ChildId = $childId; AgentRole = $agentRole; Path = $Path }
    }
    catch {
        Add-Finding 'H008_ROLLOUT_CHILD_EVIDENCE_INVALID' ("{0}: {1}" -f $ScenarioId, $_.Exception.Message)
        return $null
    }
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
        $hostThreadIds = @($events | Where-Object { $_.type -eq 'thread.started' } | ForEach-Object { [string]$_.thread_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        if ($hostThreadIds.Count -gt 1) {
            Add-Finding 'H008_ROLLOUT_CHILD_EVIDENCE_INVALID' ("{0}: host event stream has {1} thread.started identifiers" -f $ScenarioId, $hostThreadIds.Count)
        }
        $expectedAgentRole = [string]$scenario.expected_native_agent
        if ([string]::IsNullOrWhiteSpace($expectedAgentRole) -and [string]$scenario.execution_contract -eq 'multi_turn_user_decision') {
            $expectedAgentRole = 'design-griller'
        }
        $rolloutChild = Get-ChildRolloutEvidence -Path $ChildRolloutPath -HostThreadId ($hostThreadIds | Select-Object -First 1) -ExpectedAgentRole $expectedAgentRole
        $collaborationEvents = @($completedItems | Where-Object { $_.type -eq 'collab_tool_call' })
        $spawnEvents = @($collaborationEvents | Where-Object { [string]$_.tool -eq 'spawn_agent' })
        $spawnWithChildId = @($spawnEvents | Where-Object { @($_.receiver_thread_ids | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0 })
        $bareWaits = @($collaborationEvents | Where-Object {
            [string]$_.tool -eq 'wait' -and @($_.receiver_thread_ids | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -eq 0
        })
        $hasNativeChildEvidence = $spawnWithChildId.Count -gt 0 -or $null -ne $rolloutChild

        if (-not $hasNativeChildEvidence) {
            Add-Finding 'H005_NATIVE_CHILD_SPAWN_MISSING' ("{0}: native-child contract has no completed spawn_agent event" -f $ScenarioId)
        }
        elseif ($spawnEvents.Count -gt 0 -and $spawnWithChildId.Count -eq 0 -and $null -eq $rolloutChild) {
            Add-Finding 'H007_SPAWN_IDENTIFIER_MISSING' ("{0}: spawn_agent event has no child identifier" -f $ScenarioId)
        }
        if ($bareWaits.Count -gt 0 -and -not $hasNativeChildEvidence) {
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
