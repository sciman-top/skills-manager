param(
    [switch]$StrictNoGit
)
$ErrorActionPreference = "Stop"

$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    $isGitWorkTree = $false
    try {
        $inside = (& git rev-parse --is-inside-work-tree 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($inside) -and $inside.ToString().Trim().ToLowerInvariant() -eq "true") {
            $isGitWorkTree = $true
        }
    }
    catch {
        $isGitWorkTree = $false
    }

    if (-not $isGitWorkTree) {
        $msg = "未检测到 Git 工作树，跳过生成产物一致性校验。"
        if ($StrictNoGit) {
            throw $msg
        }
        Write-Host $msg
        $global:LASTEXITCODE = 0
        return
    }
    .\build.ps1
    $status = git status --porcelain -- skills.ps1 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ("执行 git status 失败：{0}" -f ($status | Out-String))
    }
    if (-not [string]::IsNullOrWhiteSpace($status)) {
        Write-Error "检测到生成产物漂移：skills.ps1 与 src/ 不一致，请先运行 build.ps1 并提交变更。"
    }
    Write-Host "生成产物一致性校验通过。"
    $global:LASTEXITCODE = 0
}
finally {
    Pop-Location
}
