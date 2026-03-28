param(
    [switch]$Fix,
    [string]$GitDir = '.git',
    [string]$BackupPath,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Write-Status {
    param(
        [ValidateSet('INFO','PASS','WARN','FAIL')]
        [string]$Level,
        [string]$Message
    )

    if ($Quiet -and $Level -eq 'INFO') { return }

    $prefix = "[$Level]"
    switch ($Level) {
        'PASS' { Write-Host "$prefix $Message" -ForegroundColor Green }
        'WARN' { Write-Host "$prefix $Message" -ForegroundColor Yellow }
        'FAIL' { Write-Host "$prefix $Message" -ForegroundColor Red }
        default { Write-Host "$prefix $Message" -ForegroundColor Cyan }
    }
}

function Get-DenyLines {
    param([string]$Target)

    $cmd = 'icacls "{0}" /T /C | findstr /I "(DENY)"' -f $Target
    $lines = @(cmd /c $cmd 2>$null)
    if ($LASTEXITCODE -eq 0) {
        return $lines
    }
    return @()
}

function Invoke-IcaclsQuiet {
    param(
        [string]$Target,
        [string]$Args
    )
    $cmd = ('icacls "{0}" {1} >nul 2>nul' -f $Target, $Args)
    cmd /c $cmd | Out-Null
    return $LASTEXITCODE
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $repoRoot

$gitPath = Join-Path $repoRoot $GitDir
if (-not (Test-Path -LiteralPath $gitPath)) {
    Write-Status FAIL "Git directory not found: $gitPath"
    exit 2
}

Write-Status INFO "Repo root: $repoRoot"
Write-Status INFO "Target: $gitPath"

$beforeDeny = Get-DenyLines -Target $gitPath
if ($beforeDeny.Count -eq 0) {
    Write-Status PASS '.git ACL is clean (no DENY found).'
    exit 0
}

Write-Status WARN ("Found DENY entries: {0}" -f $beforeDeny.Count)
$beforeDeny | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }

if (-not $Fix) {
    Write-Status FAIL 'DENY detected. Re-run with -Fix to auto-repair.'
    exit 3
}

if ([string]::IsNullOrWhiteSpace($BackupPath)) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $BackupPath = Join-Path $repoRoot ("acl-backup-git-{0}.txt" -f $timestamp)
}

Write-Status INFO "Backup ACL to: $BackupPath"
$saveCode = Invoke-IcaclsQuiet -Target $gitPath -Args ('/save "{0}" /T /C' -f $BackupPath)
if ($saveCode -ne 0) {
    Write-Status FAIL 'Failed to backup ACL.'
    exit 4
}

Write-Status INFO 'Reset ACL recursively...'
$resetCode = Invoke-IcaclsQuiet -Target $gitPath -Args '/reset /T /C'
if ($resetCode -ne 0) {
    Write-Status FAIL 'ACL reset failed.'
    exit 5
}

Write-Status INFO 'Enable inheritance recursively...'
$inheritCode = Invoke-IcaclsQuiet -Target $gitPath -Args '/inheritance:e /T /C'
if ($inheritCode -ne 0) {
    Write-Status FAIL 'Enabling inheritance failed.'
    exit 6
}

Write-Status INFO 'Grant current user full control recursively...'
$grantSpec = ("{0}:(OI)(CI)F" -f $env:USERNAME)
$grantCode = Invoke-IcaclsQuiet -Target $gitPath -Args ('/grant:r "{0}" /T /C' -f $grantSpec)
if ($grantCode -ne 0) {
    Write-Status FAIL 'Granting current user full control failed.'
    exit 7
}

$afterDeny = Get-DenyLines -Target $gitPath
if ($afterDeny.Count -gt 0) {
    Write-Status FAIL ("Repair attempted but DENY still exists: {0}" -f $afterDeny.Count)
    $afterDeny | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }
    exit 8
}

Write-Status PASS '.git ACL repaired successfully (DENY cleared).'
Write-Status INFO ("Rollback command: icacls . /restore `"{0}`"" -f $BackupPath)
exit 0
