# Keep LF bytes stable because Codex hook trust hashes the installed definition.
[CmdletBinding()]
param(
    [ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$ExpectedScriptSha256,
    [ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$ExpectedPolicySha256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Stop-CrossThreadGuard {
    param([Parameter(Mandatory = $true)][string]$Message)
    [Console]::Error.WriteLine($Message)
    exit 2
}

function Get-CrossThreadGuardSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

if (-not [string]::IsNullOrWhiteSpace($ExpectedScriptSha256) -and
    (Get-CrossThreadGuardSha256 $PSCommandPath) -cne $ExpectedScriptSha256.ToLowerInvariant()) {
    Stop-CrossThreadGuard 'Cross-thread guard script hash differs from the trusted command definition; blocking fail-closed.'
}

$policyPath = Join-Path $PSScriptRoot 'CrossThreadGuardPolicy.ps1'
if (-not (Test-Path -LiteralPath $policyPath -PathType Leaf)) {
    Stop-CrossThreadGuard 'Cross-thread guard policy core is missing; blocking fail-closed.'
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedPolicySha256) -and
    (Get-CrossThreadGuardSha256 $policyPath) -cne $ExpectedPolicySha256.ToLowerInvariant()) {
    Stop-CrossThreadGuard 'Cross-thread guard policy hash differs from the trusted command definition; blocking fail-closed.'
}
. $policyPath

$rawInput = [Console]::In.ReadToEnd()
try { $payload = $rawInput | ConvertFrom-Json -Depth 60 -ErrorAction Stop }
catch { Stop-CrossThreadGuard 'Cross-thread guard could not parse PreToolUse input; blocking fail-closed.' }

$decision = Get-CrossThreadGuardDecision -Payload $payload

if ([int]$decision.exit_code -ne 0) { Stop-CrossThreadGuard ([string]$decision.reason) }
if ([string]$decision.permission_decision -ceq 'deny') {
    [ordered]@{ hookSpecificOutput=[ordered]@{ hookEventName='PreToolUse'; permissionDecision='deny'; permissionDecisionReason=[string]$decision.reason } } |
        ConvertTo-Json -Depth 5 -Compress
}
