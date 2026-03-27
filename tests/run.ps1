$ErrorActionPreference = "Stop"
Import-Module Pester | Out-Null
$pesterVersion = (Get-Module Pester | Select-Object -First 1 -ExpandProperty Version)
Write-Host ("Pester Version: {0}" -f $pesterVersion)
$unit = Invoke-Pester -Script "$PSScriptRoot\Unit"
$e2e = Invoke-Pester -Script "$PSScriptRoot\E2E"
$failed = 0
if ($unit -and $unit.FailedCount) { $failed += [int]$unit.FailedCount }
if ($e2e -and $e2e.FailedCount) { $failed += [int]$e2e.FailedCount }
if ($failed -gt 0) {
    $global:LASTEXITCODE = 1
    throw ("Pester failures: {0}" -f $failed)
}

# Ensure callers receive a deterministic success exit code.
$global:LASTEXITCODE = 0
