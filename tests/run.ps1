$ErrorActionPreference = "Stop"
$requiredPesterVersion = [version]"4.10.1"
$requiredPester = Get-Module -ListAvailable -Name Pester |
    Where-Object { $_.Version -eq $requiredPesterVersion } |
    Select-Object -First 1
if (-not $requiredPester) {
    Write-Error "Pester 4.10.1 is required to run the test suite. Install it with: Install-Module Pester -RequiredVersion 4.10.1 -Scope CurrentUser"
}
Import-Module Pester -RequiredVersion $requiredPesterVersion -Force | Out-Null
$pesterVersion = (Get-Module Pester | Select-Object -First 1 -ExpandProperty Version)
Write-Host ("Pester Version: {0}" -f $pesterVersion)
$unit = Invoke-Pester -Script "$PSScriptRoot\Unit" -PassThru
$e2e = Invoke-Pester -Script "$PSScriptRoot\E2E" -PassThru
$failed = 0
if ($unit -and $unit.FailedCount) { $failed += [int]$unit.FailedCount }
if ($e2e -and $e2e.FailedCount) { $failed += [int]$e2e.FailedCount }
if ($failed -gt 0) {
    $global:LASTEXITCODE = 1
    throw ("Pester failures: {0}" -f $failed)
}

# Ensure callers receive a deterministic success exit code.
$global:LASTEXITCODE = 0
