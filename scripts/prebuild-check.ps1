param(
    [switch]$Strict,
    [bool]$ScanAllGitInProject = $false
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

# 2) .git ACL recursive deny guard (+ index.lock probe)
$aclGuardScript = Join-Path $PSScriptRoot "git-acl-guard.ps1"
if (Test-Path -LiteralPath $aclGuardScript) {
    try {
        $scanArg = @("-ProbeLockFile")
        if ($ScanAllGitInProject) {
            $scanArg = @('-ScanAllGitUnder', $root)
            $scanArg += @("-ProbeLockFile")
        }

        & powershell -NoProfile -ExecutionPolicy Bypass -File $aclGuardScript -Quiet @scanArg | Out-Null
        if ($LASTEXITCODE -eq 0) {
            if ($ScanAllGitInProject) {
                Write-Check "PASS" ".git ACL recursive DENY check passed (all project .git, with index.lock probe)."
            }
            else {
                Write-Check "PASS" ".git ACL recursive DENY check passed (repo .git, with index.lock probe)."
            }
        }
        else {
            Write-Check "WARN" ".git ACL recursive DENY detected; trying auto-fix (scripts\\git-acl-guard.ps1 -Fix)."
            $warned = $true

            & powershell -NoProfile -ExecutionPolicy Bypass -File $aclGuardScript -Quiet -Fix @scanArg | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Check "PASS" ".git ACL recursive DENY auto-fix succeeded (with index.lock probe)."
            }
            else {
                if ($Strict) {
                    Write-Check "FAIL" ".git ACL recursive DENY still exists after auto-fix (strict mode)."
                    $failed = $true
                }
                else {
                    Write-Check "WARN" ".git ACL recursive DENY still exists; continuing (non-strict mode)."
                    $warned = $true
                }
            }
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
$watchSet = @('codex', 'claude', 'gemini', 'code', 'cursor', 'trae')
function Get-ProcessLineageIds {
    param([int]$StartProcessId)

    $lineage = New-Object 'System.Collections.Generic.HashSet[int]'
    $current = $StartProcessId
    while ($current -gt 0 -and -not $lineage.Contains($current)) {
        $lineage.Add($current) | Out-Null
        try {
            $proc = Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $current) -ErrorAction Stop
        }
        catch {
            break
        }
        if ($null -eq $proc -or $proc.ParentProcessId -le 0) { break }
        $current = [int]$proc.ParentProcessId
    }
    return $lineage
}

$selfLineage = Get-ProcessLineageIds -StartProcessId $PID
$running = @(Get-Process -ErrorAction SilentlyContinue |
    Where-Object {
        $name = $_.ProcessName.ToLowerInvariant()
        $watchSet -contains $name -and -not $selfLineage.Contains($_.Id)
    } |
    Select-Object -ExpandProperty ProcessName -Unique)

if ($running.Count -gt 0) {
    Write-Check "WARN" ("Potential skill-consuming processes are running: {0}" -f ($running -join ", "))
    $warned = $true
}
else {
    Write-Check "PASS" "No common occupying process found outside the current session."
}

# 4) UTF-8 encoding guard (Windows/PowerShell)
$encodingGuardScript = Join-Path $root "overrides\custom-windows-encoding-guard\scripts\bootstrap.ps1"
if (Test-Path -LiteralPath $encodingGuardScript -PathType Leaf) {
    try {
        $resultJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $encodingGuardScript -AsJson
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]($resultJson | Out-String))) {
            $result = ($resultJson | Out-String | ConvertFrom-Json)
            if ($result.compliant_after -eq $true) {
                Write-Check "PASS" "UTF-8 encoding guard is compliant."
            }
            else {
                if ($Strict) {
                    Write-Check "FAIL" "UTF-8 encoding guard is not compliant in strict mode."
                    $failed = $true
                }
                else {
                    Write-Check "WARN" "UTF-8 encoding guard is not compliant."
                    $warned = $true
                }
            }
        }
        else {
            if ($Strict) {
                Write-Check "FAIL" "UTF-8 encoding guard script execution failed in strict mode."
                $failed = $true
            }
            else {
                Write-Check "WARN" "UTF-8 encoding guard script execution failed."
                $warned = $true
            }
        }
    }
    catch {
        if ($Strict) {
            Write-Check "FAIL" ("UTF-8 encoding guard error in strict mode: {0}" -f $_.Exception.Message)
            $failed = $true
        }
        else {
            Write-Check "WARN" ("UTF-8 encoding guard error: {0}" -f $_.Exception.Message)
            $warned = $true
        }
    }
}
else {
    if ($Strict) {
        Write-Check "FAIL" "UTF-8 encoding guard script missing: overrides\\custom-windows-encoding-guard\\scripts\\bootstrap.ps1"
        $failed = $true
    }
    else {
        Write-Check "WARN" "UTF-8 encoding guard script missing: overrides\\custom-windows-encoding-guard\\scripts\\bootstrap.ps1"
        $warned = $true
    }
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
