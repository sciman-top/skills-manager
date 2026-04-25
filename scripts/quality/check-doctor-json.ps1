[CmdletBinding()]
param(
    [int]$SyncMcpThresholdMs = 0,
    [switch]$WarnOnly
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

function Assert-SyncMcpThreshold($report, [int]$thresholdMs, [bool]$warnOnly) {
    if ($thresholdMs -le 0) { return }

    if ($null -eq $report.performance -or $null -eq $report.performance.summary) {
        $msg = "doctor --json report misses performance.summary required for sync_mcp threshold check."
        if ($warnOnly) { Write-Warning $msg; return }
        throw $msg
    }

    $summary = @($report.performance.summary)
    $syncMetric = @($summary | Where-Object { $_ -and [string]$_.metric -eq "sync_mcp" } | Select-Object -First 1)
    if ($syncMetric.Count -eq 0 -or $null -eq $syncMetric[0]) {
        $msg = "doctor --json report misses sync_mcp metric in performance.summary."
        if ($warnOnly) { Write-Warning $msg; return }
        throw $msg
    }

    $metric = $syncMetric[0]
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

    if ($last -le $thresholdMs -and $avg -le $thresholdMs) { return }

    $perfMessage = ("sync_mcp performance regression: last={0}ms avg={1}ms threshold={2}ms" -f $last, $avg, $thresholdMs)
    if ($warnOnly) {
        Write-Warning $perfMessage
        return
    }

    throw $perfMessage
}

Push-Location $root
try {
    $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'skills.ps1') doctor --json 2>&1)
    $exitCode = $LASTEXITCODE
    $text = (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()

    if ($exitCode -ne 0) {
        throw ("doctor --json exited with {0}: {1}" -f $exitCode, $text)
    }
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
    if ($null -eq $report.summary) { throw 'doctor --json report misses summary.' }

    $effectiveSyncThreshold = Resolve-SyncMcpThresholdMs $SyncMcpThresholdMs
    Assert-SyncMcpThreshold $report $effectiveSyncThreshold ([bool]$WarnOnly)

    if ($effectiveSyncThreshold -gt 0) {
        Write-Host ("doctor JSON contract check passed (sync_mcp threshold={0}ms)." -f $effectiveSyncThreshold)
    }
    else {
        Write-Host 'doctor JSON contract check passed.'
    }
}
finally {
    Pop-Location
}
