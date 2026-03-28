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

function Invoke-Cmd {
    param([string]$CommandLine)

    cmd /c $CommandLine
    return $LASTEXITCODE
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

function Get-DenySids {
    param([string[]]$Lines)

    $sidRegex = 'S-\d-(?:\d+-){1,14}\d+'
    $all = @()
    foreach ($line in $Lines) {
        $all += ([regex]::Matches($line, $sidRegex) | ForEach-Object { $_.Value })
    }
    return @($all | Sort-Object -Unique)
}

function Remove-DenyRulesBySid {
    param(
        [string]$Target,
        [string]$Sid
    )

    # icacls needs '*' prefix for unresolved/orphan SID.
    $removeCode = Invoke-Cmd "icacls \"$Target\" /remove:d *$Sid /T /C"
    if ($removeCode -ne 0) {
        Write-Status WARN "icacls /remove:d returned $removeCode for SID: $Sid"
    }

    # Some explicit deny ACEs on root folder survive icacls; clear via ACL API.
    $rootAcl = Get-Acl -LiteralPath $Target
    $rootDeny = @($rootAcl.Access | Where-Object {
        $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny -and
        $_.IdentityReference.Value -eq $Sid
    })

    if ($rootDeny.Count -gt 0) {
        foreach ($rule in $rootDeny) {
            [void]$rootAcl.RemoveAccessRuleSpecific($rule)
        }
        Set-Acl -LiteralPath $Target -AclObject $rootAcl
    }
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
$saveCode = Invoke-Cmd "icacls \"$gitPath\" /save \"$BackupPath\" /T /C"
if ($saveCode -ne 0) {
    Write-Status FAIL 'Failed to backup ACL.'
    exit 4
}

Write-Status INFO 'Take ownership recursively (best effort)...'
$takeownCode = Invoke-Cmd "takeown /F \"$gitPath\" /R /D Y"
if ($takeownCode -ne 0) {
    Write-Status WARN 'takeown returned non-zero; continuing with ACL repair.'
}

Write-Status INFO 'Reset ACL recursively...'
$resetCode = Invoke-Cmd "icacls \"$gitPath\" /reset /T /C"
if ($resetCode -ne 0) {
    Write-Status FAIL 'ACL reset failed.'
    exit 5
}

Write-Status INFO 'Enable inheritance recursively...'
$inheritCode = Invoke-Cmd "icacls \"$gitPath\" /inheritance:e /T /C"
if ($inheritCode -ne 0) {
    Write-Status FAIL 'Enabling inheritance failed.'
    exit 6
}

Write-Status INFO 'Grant current user full control recursively...'
$currentPrincipal = "{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME
$grantCode = Invoke-Cmd "icacls \"$gitPath\" /grant:r \"${currentPrincipal}:(OI)(CI)F\" /T /C"
if ($grantCode -ne 0) {
    Write-Status FAIL 'Granting current user full control failed.'
    exit 7
}

$remainingDeny = Get-DenyLines -Target $gitPath
if ($remainingDeny.Count -gt 0) {
    $sids = Get-DenySids -Lines $remainingDeny
    Write-Status WARN ("Residual DENY SIDs detected: {0}" -f ($sids -join ', '))

    foreach ($sid in $sids) {
        Write-Status INFO "Removing DENY rules for SID: $sid"
        Remove-DenyRulesBySid -Target $gitPath -Sid $sid
    }
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
