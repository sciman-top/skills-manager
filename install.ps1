[CmdletBinding()]
param(
    [ValidateSet("CurrentUser", "PortableOnly")]
    [string]$Mode = "CurrentUser",
    [string]$Root = $PSScriptRoot,
    [switch]$SyncMcp,
    [switch]$SkipEnvironmentCheck,
    [switch]$SkipRebuildLocked,
    [int]$DoctorThresholdMs = 8000
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Path 不能为空。"
    }
    return [System.IO.Path]::GetFullPath($Path)
}

function Resolve-PowerShellExecutable {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pwsh) {
        return $pwsh.Source
    }
    $powershell = Get-Command powershell.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($powershell) {
        return $powershell.Source
    }
    throw "未找到 PowerShell 可执行文件。请优先安装 PowerShell 7 (pwsh)。"
}

function Assert-Environment([string]$RootPath, [bool]$NeedsGit) {
    if (-not (Test-Path -LiteralPath (Join-Path $RootPath "skills.ps1") -PathType Leaf)) {
        throw "缺少入口脚本 skills.ps1。"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $RootPath "build.ps1") -PathType Leaf)) {
        throw "缺少构建脚本 build.ps1。"
    }
    if ($NeedsGit -and -not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "未找到 git。CurrentUser 安装需要 git 用于按锁文件重建来源。"
    }
}

function Invoke-PowerShellFile([string]$Name, [string]$FilePath, [string[]]$Arguments = @()) {
    $exe = Resolve-PowerShellExecutable
    Write-Host ("== {0} ==" -f $Name)
    $global:LASTEXITCODE = 0
    & $exe -NoProfile -ExecutionPolicy Bypass -File $FilePath @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw ("步骤失败：{0} (exit={1})" -f $Name, $exitCode)
    }
}

$rootPath = Resolve-FullPath $Root
if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) {
    throw ("Root 不存在：{0}" -f $rootPath)
}

$buildPath = Join-Path $rootPath "build.ps1"
$entryPath = Join-Path $rootPath "skills.ps1"
$lockPath = Join-Path $rootPath "skills.lock.json"
$needsGit = ($Mode -eq "CurrentUser" -and (Test-Path -LiteralPath $lockPath -PathType Leaf) -and -not $SkipRebuildLocked)

if (-not $SkipEnvironmentCheck) {
    Assert-Environment $rootPath $needsGit
}

Invoke-PowerShellFile "build" $buildPath

if ($Mode -eq "CurrentUser") {
    if ((Test-Path -LiteralPath $lockPath -PathType Leaf) -and -not $SkipRebuildLocked) {
        Invoke-PowerShellFile "rebuild locked sources" $entryPath @("更新", "-Locked")
    }
    else {
        Invoke-PowerShellFile "build and apply" $entryPath @("构建生效")
    }

    if ($SyncMcp) {
        Invoke-PowerShellFile "sync MCP" $entryPath @("同步MCP")
    }
}
elseif ($SyncMcp) {
    Write-Host "PortableOnly 模式不会写入 MCP 或 skills 目标目录，已忽略 -SyncMcp。"
}

Invoke-PowerShellFile "doctor" $entryPath @("doctor", "--strict", "--threshold-ms", [string]$DoctorThresholdMs)

Write-Host ("skills-manager install completed: {0}" -f $Mode)
