param(
    [switch]$Strict
)

$ErrorActionPreference = "Stop"

function Write-Check {
    param(
        [string]$Status,
        [string]$Message
    )
    switch ($Status) {
        "PASS" { Write-Host ("[PASS] {0}" -f $Message) -ForegroundColor Green }
        "WARN" { Write-Host ("[WARN] {0}" -f $Message) -ForegroundColor Yellow }
        "FAIL" { Write-Host ("[FAIL] {0}" -f $Message) -ForegroundColor Red }
        default { Write-Host ("[{0}] {1}" -f $Status, $Message) }
    }
}

function Get-CurrentPrincipalSids {
    $ids = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        if ($identity -and $identity.User) {
            [void]$ids.Add($identity.User.Value)
        }
        if ($identity -and $identity.Groups) {
            foreach ($g in $identity.Groups) {
                if ($g) { [void]$ids.Add($g.Value) }
            }
        }
    }
    catch {}

    $wellKnown = @(
        [System.Security.Principal.WellKnownSidType]::WorldSid,
        [System.Security.Principal.WellKnownSidType]::AuthenticatedUserSid,
        [System.Security.Principal.WellKnownSidType]::BuiltinUsersSid,
        [System.Security.Principal.WellKnownSidType]::InteractiveSid
    )
    foreach ($wk in $wellKnown) {
        try {
            $sid = New-Object System.Security.Principal.SecurityIdentifier($wk, $null)
            [void]$ids.Add($sid.Value)
        }
        catch {}
    }
    return $ids
}

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$failed = $false
$warned = $false

Write-Host "== Skills Manager Prebuild Check ==" -ForegroundColor Cyan

# 1) git working tree check
$statusLines = @(git status --short 2>$null)
if ($LASTEXITCODE -ne 0) {
    Write-Check "WARN" "Cannot read git status (permission may be restricted)."
    $warned = $true
}
elseif ($statusLines.Count -eq 0) {
    Write-Check "PASS" "git working tree is clean."
}
else {
    Write-Check "WARN" ("git working tree is not clean ({0} changed entries)." -f $statusLines.Count)
    $warned = $true
}

# 2) .git ACL recursive deny guard
$aclGuardScript = Join-Path $PSScriptRoot "git-acl-guard.ps1"
if (Test-Path -LiteralPath $aclGuardScript) {
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $aclGuardScript -Quiet | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Check "PASS" ".git ACL recursive DENY check passed."
        }
        else {
            Write-Check "FAIL" ".git ACL recursive DENY detected (run scripts\\git-acl-guard.ps1 -Fix)."
            $failed = $true
        }
    }
    catch {
        Write-Check "WARN" ("Failed to run ACL guard script: {0}" -f $_.Exception.Message)
        $warned = $true
    }
}
else {
    Write-Check "WARN" "ACL guard script missing: scripts\\git-acl-guard.ps1"
    $warned = $true
}

# 3) common process occupation check
$watchPatterns = @("codex", "claude", "gemini", "trae", "cursor", "code")
$running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $name = $_.ProcessName.ToLowerInvariant()
    foreach ($p in $watchPatterns) {
        if ($name -like ("*{0}*" -f $p)) { return $true }
    }
    return $false
} | Select-Object -ExpandProperty ProcessName -Unique)

if ($running.Count -gt 0) {
    Write-Check "WARN" ("Potential skill-consuming processes are running: {0}" -f ($running -join ", "))
    $warned = $true
}
else {
    Write-Check "PASS" "No common occupying process found."
}

if ($failed) {
    Write-Host "Result: FAILED. Fix FAIL items before build." -ForegroundColor Red
    exit 2
}

if ($Strict -and $warned) {
    Write-Host "Result: FAILED in strict mode (WARN exists)." -ForegroundColor Yellow
    exit 3
}

if ($warned) {
    Write-Host "Result: PASS with WARN." -ForegroundColor Yellow
}
else {
    Write-Host "Result: PASS." -ForegroundColor Green
}

exit 0
