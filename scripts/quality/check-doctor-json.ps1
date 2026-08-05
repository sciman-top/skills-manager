[CmdletBinding()]
param(
    [int]$SyncMcpThresholdMs = 0,
    [switch]$WarnOnly,
    [string]$CurrentSyncMcpSamplePath = ''
)

$ErrorActionPreference = 'Stop'

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

function Resolve-SyncMcpThresholdMs([int]$explicitValue) {
    if ($explicitValue -gt 0) { return $explicitValue }

    $raw = [System.Environment]::GetEnvironmentVariable("SKILLS_SYNC_MCP_THRESHOLD_MS")
    if ([string]::IsNullOrWhiteSpace([string]$raw)) { return 0 }

    $parsed = 0
    if (-not [int]::TryParse([string]$raw, [ref]$parsed) -or $parsed -le 0) {
        throw ("SKILLS_SYNC_MCP_THRESHOLD_MS 必须是正整数：{0}" -f $raw)
    }

    return $parsed
}

function Get-CurrentSyncMcpSample([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw ("Current sync_mcp sample does not exist: {0}" -f $path)
    }
    try {
        $sample = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    }
    catch {
        throw ("Current sync_mcp sample is not valid JSON: {0}" -f $_.Exception.Message)
    }
    if ([string]$sample.metric -ne 'sync_mcp') {
        throw ("Current sync_mcp sample has unexpected metric: {0}" -f [string]$sample.metric)
    }
    return $sample
}

function Assert-SyncMcpThreshold($metric, [int]$thresholdMs, [bool]$warnOnly) {
    if ($thresholdMs -le 0) { return $true }

    if ($null -eq $metric) {
        Write-Host 'gate_na gate=sync_mcp-performance reason=no_current_sample alternative_verification=doctor_offline_contract evidence_link=doctor_json_contract expires_at=next_sync_mcp_performance_gate recovery_condition=provide_current_sync_mcp_sample'
        return $false
    }

    $last = 0
    $avg = 0
    if (-not [int]::TryParse([string]$metric.last_ms, [ref]$last)) {
        $msg = ("doctor --json sync_mcp.last_ms is not an integer: {0}" -f [string]$metric.last_ms)
        if ($warnOnly) { Write-Warning $msg; return }
        throw $msg
    }
    if (-not [int]::TryParse([string]$metric.avg_ms, [ref]$avg)) {
        $msg = ("doctor --json sync_mcp.avg_ms is not an integer: {0}" -f [string]$metric.avg_ms)
        if ($warnOnly) { Write-Warning $msg; return }
        throw $msg
    }

    if ($last -le $thresholdMs -and $avg -le $thresholdMs) { return $true }

    $perfMessage = ("sync_mcp performance regression: last={0}ms avg={1}ms threshold={2}ms" -f $last, $avg, $thresholdMs)
    if ($warnOnly) {
        Write-Warning $perfMessage
        return $true
    }

    throw $perfMessage
}

Push-Location $root
try {
    # The CLI serialization path has a dedicated smoke test. Reuse Doctor in
    # this gate process so every quick/full gate does not spawn and parse a
    # second 20k-line generated PowerShell entrypoint.
    . (Join-Path $root 'skills.ps1')
    $doctorReport = Invoke-Doctor @('--json', '--offline-contract') 6>$null
    $text = ($doctorReport | ConvertTo-Json -Depth 30).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw 'doctor --json returned empty output.'
    }

    try {
        $report = $text | ConvertFrom-Json
    }
    catch {
        throw ("doctor --json output is not valid JSON: {0}`nOutput:`n{1}" -f $_.Exception.Message, $text)
    }

    if ($null -eq $report.checks) { throw 'doctor --json report misses checks.' }
    if ($null -eq $report.checks.git -or $report.checks.git.ok -ne $true) { throw 'doctor --json report has failing or missing git check.' }
    if ($null -eq $report.checks.config -or $report.checks.config.ok -ne $true) { throw 'doctor --json report has failing or missing config check.' }
    if ($report.offline_contract -ne $true -or $report.checks.network.skipped -ne $true -or $report.checks.network.reason -ne 'offline_contract') {
        throw 'doctor --json offline contract did not report the network check as skipped.'
    }
    if ($null -eq $report.summary) { throw 'doctor --json report misses summary.' }

    $effectiveSyncThreshold = Resolve-SyncMcpThresholdMs $SyncMcpThresholdMs
    $currentSyncSample = Get-CurrentSyncMcpSample $CurrentSyncMcpSamplePath
    $syncThresholdEvaluated = Assert-SyncMcpThreshold $currentSyncSample $effectiveSyncThreshold ([bool]$WarnOnly)

    if ($effectiveSyncThreshold -gt 0 -and $syncThresholdEvaluated) {
        Write-Host ("doctor JSON contract check passed (sync_mcp threshold={0}ms)." -f $effectiveSyncThreshold)
    }
    else {
        Write-Host 'doctor JSON contract check passed.'
    }
}
finally {
    Pop-Location
}
