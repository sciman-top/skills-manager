[CmdletBinding()]
param(
    [string]$UnitTestPath = (Join-Path $PSScriptRoot 'Unit'),
    [string]$E2ETestPath = (Join-Path $PSScriptRoot 'E2E'),
    [Alias('Path')][string[]]$TestPath = @(),
    [Alias('Name')][string[]]$TestName = @(),
    [string[]]$Tag = @(),
    [string[]]$ExcludeTag = @()
)

$ErrorActionPreference = 'Stop'
$bootstrap = Join-Path $PSScriptRoot '..\scripts\quality\ensure-test-runtime.ps1'
$manifest = & $bootstrap
Import-Module -Name $manifest -Force | Out-Null

$paths = if ($TestPath.Count -eq 0) { @($UnitTestPath, $E2ETestPath) } else { @($TestPath) }
foreach ($path in $paths) {
    $testFiles = if (Test-Path -LiteralPath $path -PathType Leaf) { @(Get-Item -LiteralPath $path | Where-Object Name -Like '*.Tests.ps1') } else { @(Get-ChildItem -LiteralPath $path -Recurse -Filter '*.Tests.ps1' -File) }
    if ($testFiles.Count -eq 0) {
        throw ("Test discovery returned zero files: {0}" -f $path)
    }
}

$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$configuration = New-PesterConfiguration
$configuration.Run.Path = $paths
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'None'
if ($TestName.Count -gt 0) { $configuration.Filter.FullName = $TestName }
if ($Tag.Count -gt 0) { $configuration.Filter.Tag = $Tag }
if ($ExcludeTag.Count -gt 0) { $configuration.Filter.ExcludeTag = $ExcludeTag }
$result = Invoke-Pester -Configuration $configuration 3>$null 4>$null 5>$null 6>$null
$stopwatch.Stop()
if (-not $result -or [int]$result.TotalCount -le 0) { throw 'Test discovery returned zero tests.' }
Write-Host ("Tests: total={0} passed={1} failed={2} skipped={3} duration={4:n1}s" -f [int]$result.TotalCount, [int]$result.PassedCount, [int]$result.FailedCount, [int]$result.SkippedCount, $stopwatch.Elapsed.TotalSeconds)
if ([int]$result.FailedContainersCount -gt 0) {
    foreach ($container in @($result.FailedContainers)) {
        Write-Host ("CONTAINER FAILED: {0}" -f [string]$container.Item)
        if ($container.ErrorRecord) { Write-Host ([string]$container.ErrorRecord) }
    }
    $global:LASTEXITCODE = 1
    throw ("Pester container failures: {0}" -f $result.FailedContainersCount)
}
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
