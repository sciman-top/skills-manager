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

$result = Invoke-Pester -Script $paths -PassThru -Show Failed,Summary
if (-not $result -or [int]$result.TotalCount -le 0) { throw 'Test discovery returned zero tests.' }
if ([int]$result.FailedCount -gt 0) {
    $global:LASTEXITCODE = 1
    throw ("Pester failures: {0}" -f $result.FailedCount)
}

$global:LASTEXITCODE = 0
