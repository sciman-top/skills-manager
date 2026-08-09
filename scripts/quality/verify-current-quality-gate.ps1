[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$ReceiptRoot = '',
    [ValidateSet('quick', 'full')][string]$RequiredProfile = 'full',
    [ValidateSet('passed', 'failed', 'source_drift', 'terminal_evidence_unavailable')][string]$RequiredStatus = 'passed',
    [switch]$Json,
    [switch]$NoExit
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RepoRoot)
if ([string]::IsNullOrWhiteSpace($ReceiptRoot)) { $ReceiptRoot = Join-Path $root 'reports\quality-gates' }
. (Join-Path $PSScriptRoot 'QualityGateIntegrity.ps1')

$result = Test-QualityGateCurrentReceipt -ReceiptRoot $ReceiptRoot -RepoRoot $root -RequiredProfile $RequiredProfile -RequiredStatus $RequiredStatus
if ($Json) {
    Write-Output ($result | ConvertTo-Json -Depth 30)
}
else {
    foreach ($finding in @($result.findings)) { Write-Host ('[{0}] {1}' -f $finding.code, $finding.message) -ForegroundColor Red }
    if ($result.pass) { Write-Host ('Current quality gate receipt is valid: profile={0}, status={1}' -f $RequiredProfile, $RequiredStatus) -ForegroundColor Green }
}

$exitCode = if ($result.pass) { 0 } else { 2 }
if ($NoExit) { $global:LASTEXITCODE = $exitCode; return $result }
exit $exitCode
