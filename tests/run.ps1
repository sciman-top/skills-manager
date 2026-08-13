[CmdletBinding()]
param(
    [string]$UnitTestPath = (Join-Path $PSScriptRoot 'Unit'),
    [string]$E2ETestPath = (Join-Path $PSScriptRoot 'E2E')
)

$ErrorActionPreference = 'Stop'
$requiredVersion = [version]'4.10.1'
$required = Get-Module -ListAvailable -Name Pester |
    Where-Object Version -eq $requiredVersion |
    Select-Object -First 1
if (-not $required) { throw 'Pester 4.10.1 is required to run the test suite.' }
Import-Module Pester -RequiredVersion $requiredVersion -Force | Out-Null

$paths = @($UnitTestPath, $E2ETestPath)
foreach ($path in $paths) {
    if (@(Get-ChildItem -LiteralPath $path -Recurse -Filter '*.Tests.ps1' -File).Count -eq 0) {
        throw ("Test discovery returned zero files: {0}" -f $path)
    }
}

$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$captured = @(Invoke-Pester -Script $paths -PassThru -Show None *>&1)
$stopwatch.Stop()
$result = @($captured | Where-Object {
        $null -ne $_ -and
        $_.PSObject.Properties.Match('TotalCount').Count -gt 0 -and
        $_.PSObject.Properties.Match('FailedCount').Count -gt 0
    } | Select-Object -Last 1)
if ($result.Count -eq 1) { $result = $result[0] }
else {
    foreach ($line in @($captured | Select-Object -Last 20)) { Write-Host ([string]$line) }
}
if (-not $result -or [int]$result.TotalCount -le 0) { throw 'Test discovery returned zero tests.' }
Write-Host ("Tests: total={0} passed={1} failed={2} skipped={3} duration={4:n1}s" -f [int]$result.TotalCount, [int]$result.PassedCount, [int]$result.FailedCount, [int]$result.SkippedCount, $stopwatch.Elapsed.TotalSeconds)
if ([int]$result.FailedCount -gt 0) {
    foreach ($test in @($result.TestResult | Where-Object Result -eq 'Failed')) {
        Write-Host ("FAILED: {0}" -f [string]$test.Name)
        if (-not [string]::IsNullOrWhiteSpace([string]$test.FailureMessage)) { Write-Host ([string]$test.FailureMessage) }
    }
    $global:LASTEXITCODE = 1
    throw ("Pester failures: {0}" -f $result.FailedCount)
}

$global:LASTEXITCODE = 0
