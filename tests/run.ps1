[CmdletBinding()]
param(
    [string]$UnitTestPath = (Join-Path $PSScriptRoot 'Unit'),
    [string]$E2ETestPath = (Join-Path $PSScriptRoot 'E2E')
)

$ErrorActionPreference = 'Stop'
$requiredVersion = [version]'6.1.0'
$required = Get-Module -ListAvailable -Name Pester |
    Where-Object Version -eq $requiredVersion |
    Select-Object -First 1
if (-not $required) { throw 'Pester 6.1.0 is required to run the test suite.' }
Import-Module Pester -RequiredVersion $requiredVersion -Force | Out-Null

$paths = @($UnitTestPath, $E2ETestPath)
foreach ($path in $paths) {
    if (@(Get-ChildItem -LiteralPath $path -Recurse -Filter '*.Tests.ps1' -File).Count -eq 0) {
        throw ("Test discovery returned zero files: {0}" -f $path)
    }
}

$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$configuration = New-PesterConfiguration
$configuration.Run.Path = $paths
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'None'
$captured = @(Invoke-Pester -Configuration $configuration *>&1)
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
    $failedTests = if ($result.PSObject.Properties.Match('Failed').Count -gt 0) {
        @($result.Failed)
    }
    else {
        @($result.TestResult | Where-Object Result -eq 'Failed')
    }
    foreach ($test in $failedTests) {
        Write-Host ("FAILED: {0}" -f [string]$test.Name)
        $failureMessage = if ($test.PSObject.Properties.Match('ErrorRecord').Count -gt 0) {
            [string]$test.ErrorRecord
        }
        else {
            [string]$test.FailureMessage
        }
        if (-not [string]::IsNullOrWhiteSpace($failureMessage)) { Write-Host $failureMessage }
    }
    $global:LASTEXITCODE = 1
    throw ("Pester failures: {0}" -f $result.FailedCount)
}

$global:LASTEXITCODE = 0
