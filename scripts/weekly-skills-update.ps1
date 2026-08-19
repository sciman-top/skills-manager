#requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$entryPath = Join-Path $repoRoot 'skills.ps1'
$gatePath = Join-Path $repoRoot 'scripts\quality\run-local-quality-gates.ps1'
$lockFile = Join-Path $repoRoot '.txn\weekly-skills-update.lock'
$logDirectory = Join-Path $repoRoot 'reports\weekly-skills-update'
$lockHandle = $null
$transcriptStarted = $false

function Invoke-WeeklyNative {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$Capture
    )

    $global:LASTEXITCODE = 0
    if ($Capture) {
        $output = & $FilePath @Arguments 2>&1 | Out-String
    }
    else {
        & $FilePath @Arguments
        $output = ''
    }
    if ($LASTEXITCODE -ne 0) {
        throw ('Command failed with exit code {0}: {1} {2}' -f $LASTEXITCODE, $FilePath, ($Arguments -join ' '))
    }
    return $output.Trim()
}

function Get-WeeklyTrackedStatus {
    $text = Invoke-WeeklyNative -FilePath 'git' -Arguments @('-C', $repoRoot, 'status', '--porcelain', '--untracked-files=no') -Capture
    return @($text -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Write-WeeklyResult([string]$Status, [int]$Changed, [bool]$Persisted, [string]$Reason = '') {
    [pscustomobject][ordered]@{
        schema_version = 1
        command = 'weekly-skills-update'
        status = $Status
        changed_sources = $Changed
        persisted = $Persisted
        reason = $Reason
        mcp_mutations = 0
        pushed = $false
    } | ConvertTo-Json -Compress | Write-Output
}

try {
    if (-not (Test-Path -LiteralPath $entryPath -PathType Leaf)) { throw "Missing CLI entrypoint: $entryPath" }
    if (-not (Test-Path -LiteralPath $gatePath -PathType Leaf)) { throw "Missing quality gate: $gatePath" }

    New-Item -ItemType Directory -Path (Split-Path -Parent $lockFile) -Force | Out-Null
    try {
        $lockHandle = [IO.File]::Open($lockFile, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    }
    catch {
        throw 'Another weekly skills update is already running.'
    }

    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    $logPath = Join-Path $logDirectory ((Get-Date).ToString('yyyyMMdd-HHmmss') + '.log')
    Start-Transcript -LiteralPath $logPath -Force | Out-Null
    $transcriptStarted = $true

    $branch = Invoke-WeeklyNative -FilePath 'git' -Arguments @('-C', $repoRoot, 'symbolic-ref', '--quiet', '--short', 'HEAD') -Capture
    if ($branch -ne 'main') {
        if ($DryRun) { Write-WeeklyResult 'blocked' 0 $false "baseline_branch_mismatch:$branch"; return }
        throw "Weekly update requires branch main; observed: $branch"
    }

    $dirty = @(Get-WeeklyTrackedStatus)
    if ($dirty.Count -gt 0) {
        if ($DryRun) { Write-WeeklyResult 'blocked' 0 $false 'tracked_worktree_dirty'; return }
        throw ('Weekly update requires a clean tracked worktree: {0}' -f ($dirty -join ', '))
    }

    $checkText = Invoke-WeeklyNative -FilePath 'pwsh' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $entryPath, 'check-updates', '--json') -Capture
    $check = $checkText | ConvertFrom-Json
    $changed = [int]$check.changed
    if ($DryRun) { Write-WeeklyResult 'dry_run' $changed $false; return }
    if ($changed -eq 0) { Write-WeeklyResult 'no_update' 0 $false; return }

    Invoke-WeeklyNative -FilePath 'pwsh' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $entryPath, '更新', '-Upgrade') | Out-Null

    $afterUpdate = @(Get-WeeklyTrackedStatus)
    if ($afterUpdate.Count -ne 1 -or $afterUpdate[0] -notmatch '^\s*M\s+skills\.lock\.json$') {
        throw ('Weekly update produced an unexpected tracked write set: {0}' -f ($afterUpdate -join ', '))
    }

    Invoke-WeeklyNative -FilePath 'pwsh' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $gatePath, '-Profile', 'quick', '-AllowDirtyWorktree') | Out-Null
    Invoke-WeeklyNative -FilePath 'git' -Arguments @('-C', $repoRoot, 'add', '--', 'skills.lock.json') | Out-Null
    Invoke-WeeklyNative -FilePath 'git' -Arguments @('-C', $repoRoot, 'diff', '--cached', '--check') | Out-Null
    Invoke-WeeklyNative -FilePath 'git' -Arguments @('-C', $repoRoot, 'commit', '-m', 'chore: 每周更新技能来源锁定') | Out-Null

    $finalStatus = @(Get-WeeklyTrackedStatus)
    if ($finalStatus.Count -ne 0) { throw ('Weekly update did not leave a clean tracked worktree: {0}' -f ($finalStatus -join ', ')) }
    Write-WeeklyResult 'updated' $changed $true
}
finally {
    if ($transcriptStarted) { Stop-Transcript | Out-Null }
    if ($null -ne $lockHandle) { $lockHandle.Dispose() }
}
