$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $repoRoot "skills.ps1"

if (-not (Test-Path $entry)) {
    throw ("缺少入口脚本：{0}" -f $entry)
}

& $entry 更新
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

& $entry 同步MCP
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
