#Requires -Version 7
<#
.SYNOPSIS
Read-only aggregation of observable skill/MCP invocation evidence from host session artifacts.

.DESCRIPTION
Scans ZCode model-io rollout files (~/.zcode/cli/rollout/model-io-sess_*.jsonl) for
Skill tool calls (with the requested skill name) and mcp__<server>__<tool> tool_use
calls, then writes a summary under reports/invocation-evidence/<run-id>/.

TRUTH BOUNDARY: this is a filesystem observation, not host_loaded and not a usage
ledger. Short sessions (<= 1 tool call) are not persisted, host logs rotate, and
Codex rollout surfaces are not scanned yet. An absent record is NOT evidence of
non-use; it can only confirm that a call WAS observed.
#>
[CmdletBinding()]
param(
    [string]$OutDir = "",
    [int]$MaxFiles = 400,
    [string[]]$RolloutRoots = @()
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ($RolloutRoots.Count -eq 0) { $RolloutRoots = @((Join-Path $HOME '.zcode\cli\rollout')) }

$skillCalls = @{}
$mcpCalls = @{}
$filesScanned = 0
$filesWithEvidence = 0

foreach ($root in $RolloutRoots) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
    $files = @(Get-ChildItem -LiteralPath $root -Filter 'model-io-*.jsonl' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First $MaxFiles)
    foreach ($file in $files) {
        $filesScanned++
        $fileHadEvidence = $false
        $lineReader = [IO.StreamReader]::new($file.FullName)
        try {
            while ($null -ne ($line = $lineReader.ReadLine())) {
                if ($line -notmatch '"type":"tool-call"') { continue }
                foreach ($match in [regex]::Matches($line, '"type":"tool-call","toolCallId":"[^"]*","toolName":"Skill","input":\{[^{}]*?"skill"\s*:\s*"([^"]+)"')) {
                    $skill = [string]$match.Groups[1].Value
                    if (-not $skillCalls.ContainsKey($skill)) { $skillCalls[$skill] = 0 }
                    $skillCalls[$skill]++
                    $fileHadEvidence = $true
                }
                foreach ($match in [regex]::Matches($line, '"type":"tool-call","toolCallId":"[^"]*","toolName":"mcp__([a-zA-Z0-9_-]+)__[a-zA-Z0-9_-]+"')) {
                    $server = [string]$match.Groups[1].Value
                    if (-not $mcpCalls.ContainsKey($server)) { $mcpCalls[$server] = 0 }
                    $mcpCalls[$server]++
                    $fileHadEvidence = $true
                }
            }
        }
        finally { $lineReader.Dispose() }
        if ($fileHadEvidence) { $filesWithEvidence++ }
    }
}

$runId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$reportDir = if ([string]::IsNullOrWhiteSpace($OutDir)) { Join-Path $repoRoot (Join-Path 'reports\invocation-evidence' $runId) } else { $OutDir }
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

$summary = [ordered]@{
    schema_version = 1
    generated_at = (Get-Date).ToString('o')
    truth_boundary = 'filesystem_observation_not_host_loaded_not_usage_ledger'
    interpretation = 'Observed calls prove use; absence of records proves nothing. Short sessions are not persisted and host logs rotate, so this report can never justify removal by itself.'
    scanned = [ordered]@{ roots = $RolloutRoots; files_scanned = $filesScanned; files_with_evidence = $filesWithEvidence }
    skill_invocations = @($skillCalls.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { [ordered]@{ skill = [string]$_.Key; observed_calls = [int]$_.Value } })
    mcp_invocations = @($mcpCalls.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { [ordered]@{ server = [string]$_.Key; observed_calls = [int]$_.Value } })
}
$path = Join-Path $reportDir 'summary.json'
[IO.File]::WriteAllText($path, ($summary | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))

Write-Host ("调用可达性证据汇总（只读）：{0}" -f $path) -ForegroundColor Cyan
Write-Host ("扫描文件={0}  含证据文件={1}  观测到 Skill 调用={2}  观测到 MCP 调用={3}" -f $filesScanned, $filesWithEvidence, $skillCalls.Count, $mcpCalls.Count)
foreach ($entry in $skillCalls.GetEnumerator() | Sort-Object Value -Descending) { Write-Host ("  skill {0}: {1}" -f $entry.Key, $entry.Value) }
foreach ($entry in $mcpCalls.GetEnumerator() | Sort-Object Value -Descending) { Write-Host ("  mcp   {0}: {1}" -f $entry.Key, $entry.Value) }
Write-Host "边界：只能证明\"已观测到调用\"，不能证明\"未调用\"；不得单独据此退役任何技能/MCP。" -ForegroundColor Yellow
