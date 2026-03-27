[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$msg) {
    Write-Host ("[fix-git-acl] " + $msg)
}

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "Please run this script from an elevated PowerShell (Run as Administrator)."
    }
}

function Invoke-Native([string]$exe, [string[]]$args) {
    Write-Step ($exe + " " + ($args -join " "))
    & $exe @args
    if ($LASTEXITCODE -ne 0) {
        throw ("Command failed (exit=" + $LASTEXITCODE + "): " + $exe + " " + ($args -join " "))
    }
}

function Get-DenyIdentities([string]$path) {
    $lines = & icacls $path 2>$null
    $idents = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in @($lines)) {
        $text = [string]$line
        if ($text -notmatch "\(DENY\)") { continue }
        $m = [regex]::Match($text, "^\s*([^:]+):")
        if (-not $m.Success) { continue }
        $id = $m.Groups[1].Value.Trim()
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $idents.Add($id) | Out-Null
    }
    return @($idents)
}

Assert-Admin

$gitDir = Join-Path $RepoRoot ".git"
if (-not (Test-Path -LiteralPath $gitDir -PathType Container)) {
    throw (".git directory not found: " + $gitDir)
}

$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$backupPath = Join-Path $RepoRoot ("acl-backup-git-" + $ts + ".txt")

Write-Step ("RepoRoot: " + $RepoRoot)
Write-Step ("GitDir  : " + $gitDir)
Write-Step ("Backup ACL to: " + $backupPath)
& icacls $gitDir /save $backupPath /T /C | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Failed to back up ACL."
}

$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$grantCurrentUser = ($currentUser + ":(OI)(CI)F")
$grantAdmins = "*S-1-5-32-544:(OI)(CI)F"
$grantSystem = "*S-1-5-18:(OI)(CI)F"

Invoke-Native "takeown" @("/F", $gitDir, "/R", "/D", "Y")
Invoke-Native "icacls" @($gitDir, "/inheritance:e")
Invoke-Native "icacls" @($gitDir, "/reset", "/T", "/C")
Invoke-Native "icacls" @($gitDir, "/grant:r", $grantCurrentUser, $grantAdmins, $grantSystem, "/T", "/C")

$denyIds = Get-DenyIdentities $gitDir
if ($denyIds.Count -gt 0) {
    Write-Step ("Found DENY entries, removing: " + ($denyIds -join ", "))
    foreach ($id in $denyIds) {
        & icacls $gitDir /remove:d $id /T /C | Out-Null
    }
}
else {
    Write-Step "No DENY entries found."
}

$finalDeny = Get-DenyIdentities $gitDir
if ($finalDeny.Count -gt 0) {
    Write-Host ("[fix-git-acl] DENY entries still present: " + ($finalDeny -join ", ")) -ForegroundColor Yellow
    Write-Host "[fix-git-acl] Check whether these entries are inherited from parent folders." -ForegroundColor Yellow
    exit 2
}

Write-Host "[fix-git-acl] PASS: .git ACL repaired and no DENY entries found." -ForegroundColor Green
