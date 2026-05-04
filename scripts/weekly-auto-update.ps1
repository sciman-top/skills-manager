$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $repoRoot "skills.ps1"

if (-not (Test-Path $entry)) {
    throw ("缺少入口脚本：{0}" -f $entry)
}

function Invoke-AutoUpdateStep([string]$commandName) {
    $global:LASTEXITCODE = 0
    try {
        & $entry $commandName
    }
    catch {
        Write-Error ("自动更新步骤失败 [{0}]：{1}" -f $commandName, $_.Exception.Message)
        exit 1
    }
    if (-not $?) {
        Write-Error ("自动更新步骤失败 [{0}]：命令未成功完成。" -f $commandName)
        exit 1
    }
    $global:LASTEXITCODE = 0
}

Invoke-AutoUpdateStep "更新"
Invoke-AutoUpdateStep "同步MCP"
exit 0
