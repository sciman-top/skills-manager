#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [switch]$AutoApply
)

$ErrorActionPreference = 'Stop'
$rootPath = [IO.Path]::GetFullPath($Root)
$entry = Join-Path $rootPath 'skills.ps1'
if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { throw "skills.ps1 is missing: $entry" }
$reportDirectory = Join-Path $rootPath 'reports\release-update'
New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null

function Show-ReleaseUpdateNotification([string]$Text) {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [void][System.Windows.Forms.MessageBox]::Show($Text, 'skills-manager update', 'OK', 'Information')
    }
    catch { Write-Host $Text }
}

$pwsh = (Get-Command pwsh -ErrorAction Stop | Select-Object -First 1).Source
$raw = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $entry release-update --check --json
if ($LASTEXITCODE -ne 0) { throw "release-update check failed: exit=$LASTEXITCODE" }
$check = ($raw | Out-String | ConvertFrom-Json)
$result = [ordered]@{ schema_version = 1; command = 'release-update-scheduled-runner'; checked_at = (Get-Date).ToUniversalTime().ToString('o'); update_available = [bool]$check.update_available; auto_apply = [bool]$AutoApply; action = 'none'; detail = [string]$check.status }
if ($result.update_available) {
    $message = "skills-manager 有新版本：$($check.current_version) -> $($check.latest_version)"
    if ($AutoApply) {
        $applyArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$entry,'release-update','--apply','--yes','--json')
        $applyRaw = & $pwsh @applyArgs
        if ($LASTEXITCODE -ne 0) { throw "release-update apply failed: exit=$LASTEXITCODE" }
        $apply = ($applyRaw | Out-String | ConvertFrom-Json)
        $result.action = [string]$apply.status
        $message += '；已启动受校验的后台更新和可回滚目录切换。'
    }
    else {
        $result.action = 'notified'
        $message += '；请运行 release-update --apply --yes 安装。'
    }
    Show-ReleaseUpdateNotification $message
}
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $reportDirectory 'scheduled-last.json') -Encoding utf8
$result | ConvertTo-Json -Compress | Write-Output
