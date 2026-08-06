# Keep LF bytes stable because Codex hook trust hashes the installed definition.
[CmdletBinding()]
param(
    [ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$ExpectedScriptSha256,
    [ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$ExpectedPolicySha256,
    [ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$ExpectedTargetPromptSha256,
    [ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$ExpectedShutdownTargetPromptSha256,
    [ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$ExpectedFleetPromptSha256,
    [ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$ExpectedFleetShutdownPromptSha256,
    [ValidatePattern('^watch-runtime-generation:[0-9a-f]{64}$')][string]$ExpectedRuntimeGenerationId,
    [string]$AutomationRoot = '',
    [string]$WatchFleetStateRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Stop-WatchGuard {
    param([Parameter(Mandatory = $true)][string]$Message)
    [Console]::Error.WriteLine($Message)
    exit 2
}

function Get-WatchSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

if (-not [string]::IsNullOrWhiteSpace($ExpectedScriptSha256) -and
    (Get-WatchSha256 $PSCommandPath) -cne $ExpectedScriptSha256.ToLowerInvariant()) {
    Stop-WatchGuard 'Cross-thread guard script hash differs from the trusted command definition; blocking fail-closed.'
}

$policyPath = Join-Path $PSScriptRoot 'CrossThreadGuardPolicy.ps1'
if (-not (Test-Path -LiteralPath $policyPath -PathType Leaf)) {
    Stop-WatchGuard 'Cross-thread guard policy core is missing; blocking fail-closed.'
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedPolicySha256) -and
    (Get-WatchSha256 $policyPath) -cne $ExpectedPolicySha256.ToLowerInvariant()) {
    Stop-WatchGuard 'Cross-thread guard policy hash differs from the trusted command definition; blocking fail-closed.'
}
. $policyPath

function Get-WatchTranscriptTurnText {
    param([Parameter(Mandatory = $true)][object]$Payload)
    $sessionId = [string](Get-InputProperty -InputObject $Payload -Names @('session_id','sessionId'))
    $turnId = [string](Get-InputProperty -InputObject $Payload -Names @('turn_id','turnId'))
    $transcriptPath = [string](Get-InputProperty -InputObject $Payload -Names @('transcript_path','transcriptPath'))
    if ([string]::IsNullOrWhiteSpace($sessionId) -or [string]::IsNullOrWhiteSpace($turnId) -or
        [string]::IsNullOrWhiteSpace($transcriptPath) -or -not (Test-Path -LiteralPath $transcriptPath -PathType Leaf)) { return $null }

    $messages = [Collections.Generic.List[string]]::new()
    try {
        foreach ($line in @(Get-Content -LiteralPath $transcriptPath -Tail 2500)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $record = $line | ConvertFrom-Json -Depth 60 -ErrorAction Stop } catch { continue }
            if ([string]$record.type -cne 'response_item' -or [string]$record.payload.type -cne 'message' -or
                [string]$record.payload.role -cne 'user') { continue }
            $recordTurn = [string](Get-InputProperty -InputObject $record.payload.internal_chat_message_metadata_passthrough -Names @('turn_id','turnId'))
            if ($recordTurn -cne $turnId) { continue }
            foreach ($content in @($record.payload.content)) {
                $text = [string](Get-InputProperty -InputObject $content -Names @('text'))
                if (-not [string]::IsNullOrWhiteSpace($text)) { $messages.Add($text) }
            }
        }
    }
    catch { return $null }
    if ($messages.Count -eq 0) { return $null }
    return [string]::Join("`n", $messages.ToArray())
}

function Get-WatchEnvelopeAutomationId {
    param([AllowEmptyString()][string]$TurnText)
    if ($TurnText -match '(?s)^\s*<heartbeat>\s*<automation_id>(?<id>[^<]+)</automation_id>') {
        $id = $Matches.id.Trim()
        if ($id -match '^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$') { return $id }
    }
    return ''
}

function Get-WatchToolAutomationId {
    param([Parameter(Mandatory = $true)][object]$Payload)
    $toolInput = Get-InputProperty -InputObject $Payload -Names @('tool_input')
    $id = [string](Get-InputProperty -InputObject $toolInput -Names @('id'))
    if ([string]::IsNullOrWhiteSpace($id)) {
        $source = Get-ToolInputText -InputObject $toolInput
        $id = [string](Get-JavaScriptPropertyString -Source $source -Name 'id')
    }
    if ($id -match '^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$') { return $id }
    return ''
}

function ConvertFrom-WatchTomlString {
    param([AllowEmptyString()][string]$Literal)
    if ([string]::IsNullOrWhiteSpace($Literal)) { return '' }
    try { return [string]($Literal | ConvertFrom-Json -ErrorAction Stop) } catch { return '' }
}

function Read-WatchAutomationMetadata {
    param([AllowEmptyString()][string]$AutomationId)
    if ([string]::IsNullOrWhiteSpace($AutomationId) -or [string]::IsNullOrWhiteSpace($AutomationRoot)) { return $null }
    $root = [IO.Path]::GetFullPath($AutomationRoot)
    $path = [IO.Path]::GetFullPath((Join-Path (Join-Path $root $AutomationId) 'automation.toml'))
    if (-not $path.StartsWith($root.TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase) -or
        -not [IO.File]::Exists($path)) { return $null }
    try { $raw = [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8) } catch { return $null }
    $fields = [ordered]@{ id=''; kind=''; name=''; prompt=''; status=''; rrule=''; notification_policy=''; target_thread_id=''; path=$path }
    foreach ($name in @('id','kind','name','prompt','status','rrule','notification_policy','target_thread_id')) {
        $match = [regex]::Match($raw,('(?m)^' + [regex]::Escape($name) + '\s*=\s*(?<value>"(?:\\.|[^"\\])*")\s*$'))
        if ($match.Success) { $fields[$name] = ConvertFrom-WatchTomlString $match.Groups['value'].Value }
    }
    if ($fields.id -cne $AutomationId) { return $null }
    return [pscustomobject]$fields
}

function Read-WatchFleetState {
    param([AllowEmptyString()][string]$SupervisorAutomationId)
    if ([string]::IsNullOrWhiteSpace($SupervisorAutomationId) -or [string]::IsNullOrWhiteSpace($WatchFleetStateRoot)) { return $null }
    $root = [IO.Path]::GetFullPath($WatchFleetStateRoot)
    $path = [IO.Path]::GetFullPath((Join-Path $root ($SupervisorAutomationId + '.json')))
    if (-not $path.StartsWith($root.TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase) -or -not [IO.File]::Exists($path)) { return $null }
    try { return ([IO.File]::ReadAllText($path,[Text.Encoding]::UTF8) | ConvertFrom-Json -Depth 30 -ErrorAction Stop) } catch { return $null }
}

$rawInput = [Console]::In.ReadToEnd()
try { $payload = $rawInput | ConvertFrom-Json -Depth 60 -ErrorAction Stop }
catch { Stop-WatchGuard 'Cross-thread guard could not parse PreToolUse input; blocking fail-closed.' }

$turnText = Get-WatchTranscriptTurnText $payload
$payload | Add-Member -NotePropertyName '__watch_turn_text' -NotePropertyValue $turnText -Force
$toolAutomationId = Get-WatchToolAutomationId $payload
$payload | Add-Member -NotePropertyName '__watch_automation_metadata' -NotePropertyValue (Read-WatchAutomationMetadata $toolAutomationId) -Force
$envelopeAutomationId = Get-WatchEnvelopeAutomationId $turnText
$payload | Add-Member -NotePropertyName '__watch_envelope_automation_id' -NotePropertyValue $envelopeAutomationId -Force
$payload | Add-Member -NotePropertyName '__watch_fleet_state' -NotePropertyValue (Read-WatchFleetState $envelopeAutomationId) -Force

$decision = Get-CrossThreadGuardDecision -Payload $payload `
    -ExpectedTargetPromptSha256 $ExpectedTargetPromptSha256 `
    -ExpectedShutdownTargetPromptSha256 $ExpectedShutdownTargetPromptSha256 `
    -ExpectedFleetPromptSha256 $ExpectedFleetPromptSha256 `
    -ExpectedFleetShutdownPromptSha256 $ExpectedFleetShutdownPromptSha256 `
    -ExpectedRuntimeGenerationId $ExpectedRuntimeGenerationId

if ([int]$decision.exit_code -ne 0) { Stop-WatchGuard ([string]$decision.reason) }
if ([string]$decision.permission_decision -ceq 'deny') {
    [ordered]@{ hookSpecificOutput=[ordered]@{ hookEventName='PreToolUse'; permissionDecision='deny'; permissionDecisionReason=[string]$decision.reason } } |
        ConvertTo-Json -Depth 5 -Compress
}
