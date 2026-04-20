param(
    [switch]$StrictNoGit,
    [switch]$AllowDirtyWorktree
)
$ErrorActionPreference = "Stop"

$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    $isGitWorkTree = $false
    try {
        $insideOutput = @(& git rev-parse --is-inside-work-tree 2>$null)
        $gitExitCode = $LASTEXITCODE
        $inside = $insideOutput | Select-Object -First 1
        if ($gitExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($inside) -and $inside.ToString().Trim().ToLowerInvariant() -eq "true") {
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
    $beforeHash = $null
    if (Test-Path -LiteralPath ".\skills.ps1" -PathType Leaf) {
        $beforeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath ".\skills.ps1").Hash
    }
    .\build.ps1
    $afterHash = $null
    if (Test-Path -LiteralPath ".\skills.ps1" -PathType Leaf) {
        $afterHash = (Get-FileHash -Algorithm SHA256 -LiteralPath ".\skills.ps1").Hash
    }
    $status = git status --porcelain -- skills.ps1 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ("执行 git status 失败：{0}" -f ($status | Out-String))
    }
    if (-not [string]::IsNullOrWhiteSpace($status)) {
        if ($AllowDirtyWorktree) {
            if ($beforeHash -ne $afterHash) {
                Write-Host "已在当前工作树中刷新生成产物；skills.ps1 相对 HEAD 仍有未提交变更（开发态已放行）。"
            }
            else {
                Write-Host "生成产物与当前 src 一致；skills.ps1 相对 HEAD 仍有未提交变更（开发态已放行）。"
            }
            $global:LASTEXITCODE = 0
            return
        }
        Write-Error "检测到生成产物漂移：skills.ps1 与 src/ 不一致，请先运行 build.ps1 并提交变更。"
    }
    Write-Host "生成产物一致性校验通过。"
    $global:LASTEXITCODE = 0
}
finally {
    Pop-Location
}
