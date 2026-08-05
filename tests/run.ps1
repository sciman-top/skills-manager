[CmdletBinding()]
param(
    [ValidateRange(1, 50)]
    [int]$TopSlowFiles = 10,
    [ValidateRange(1, 100)]
    [int]$TopSlowCases = 15,
    [string]$TimingReportPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'reports\test-timings\current.json'),
    [string]$UnitTestPath = (Join-Path $PSScriptRoot 'Unit'),
    [string]$E2ETestPath = (Join-Path $PSScriptRoot 'E2E')
)

$ErrorActionPreference = "Stop"

function Get-PesterDescribeFileMap([string]$TestRoot) {
    $map = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $TestRoot -Recurse -Filter '*.Tests.ps1' -File)) {
        foreach ($line in @(Get-Content -LiteralPath $file.FullName)) {
            if ($line -match '^\s*Describe\s+([''"])(?<name>.+?)\1') {
                $name = [string]$Matches['name']
                $relative = $file.FullName.Substring($TestRoot.Length).TrimStart('\', '/')
                if ($map.ContainsKey($name) -and [string]$map[$name] -ne $relative) { $map[$name] = 'ambiguous' }
                else { $map[$name] = $relative }
            }
        }
    }
    return $map
}

function Get-PesterTimingProfile($PesterResult, [string]$Stage, [string]$TestRoot) {
    $describeMap = Get-PesterDescribeFileMap $TestRoot
    $files = @{}
    $cases = @()
    foreach ($test in @($PesterResult.TestResult)) {
        $describe = [string]$test.Describe
        $file = if ($describeMap.ContainsKey($describe) -and [string]$describeMap[$describe] -ne 'ambiguous') { [string]$describeMap[$describe] } else { '<unmapped>' }
        $elapsed = [math]::Round([double]$test.Time.TotalMilliseconds, 3)
        if (-not $files.ContainsKey($file)) { $files[$file] = [pscustomobject]@{ path = $file; elapsed_ms = 0.0; test_count = 0 } }
        $files[$file].elapsed_ms = [double]$files[$file].elapsed_ms + $elapsed
        $files[$file].test_count = [int]$files[$file].test_count + 1
        $cases += [pscustomobject]@{ stage = $Stage; path = $file; describe = $describe; name = [string]$test.Name; result = [string]$test.Result; elapsed_ms = $elapsed }
    }
    return [pscustomobject]@{
        stage = $Stage
        files = @($files.Values | ForEach-Object { $_.elapsed_ms = [math]::Round([double]$_.elapsed_ms, 3); $_ } | Sort-Object elapsed_ms -Descending)
        cases = @($cases | Sort-Object elapsed_ms -Descending)
    }
}

function Write-PesterTimingConsole($Profile, [int]$FileLimit, [int]$CaseLimit) {
    $rank = 0
    foreach ($row in @($Profile.files | Select-Object -First $FileLimit)) {
        $rank++
        Write-Host ('slow_test_file stage={0} rank={1} elapsed_ms={2} tests={3} path={4}' -f $Profile.stage, $rank, $row.elapsed_ms, $row.test_count, $row.path)
    }
    $rank = 0
    foreach ($row in @($Profile.cases | Select-Object -First $CaseLimit)) {
        $rank++
        Write-Host ('slow_test_case stage={0} rank={1} elapsed_ms={2} result={3} path={4} describe={5} name={6}' -f $Profile.stage, $rank, $row.elapsed_ms, $row.result, $row.path, $row.describe, $row.name)
    }
}

function Assert-PesterStageDiscovered($PesterResult, [string]$Stage) {
    $total = if ($null -ne $PesterResult) { [int]$PesterResult.TotalCount } else { 0 }
    if ($total -le 0) {
        throw ("{0} test discovery returned zero tests" -f $Stage)
    }
}
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
$suiteTimer = [Diagnostics.Stopwatch]::StartNew()
$stageTimer = [Diagnostics.Stopwatch]::StartNew()
$unit = Invoke-Pester -Script $UnitTestPath -PassThru -Show Failed,Summary
Assert-PesterStageDiscovered $unit 'unit'
$stageTimer.Stop()
Write-Host ("unit_elapsed_ms={0}" -f $stageTimer.ElapsedMilliseconds)
$stageTimer.Restart()
$e2e = Invoke-Pester -Script $E2ETestPath -PassThru -Show Failed,Summary
Assert-PesterStageDiscovered $e2e 'e2e'
$stageTimer.Stop()
Write-Host ("e2e_elapsed_ms={0}" -f $stageTimer.ElapsedMilliseconds)
$suiteTimer.Stop()
Write-Host ("test_suite_elapsed_ms={0}" -f $suiteTimer.ElapsedMilliseconds)
$unitTiming = Get-PesterTimingProfile $unit 'unit' ([System.IO.Path]::GetFullPath($UnitTestPath))
$e2eTiming = Get-PesterTimingProfile $e2e 'e2e' ([System.IO.Path]::GetFullPath($E2ETestPath))
Write-PesterTimingConsole $unitTiming $TopSlowFiles $TopSlowCases
Write-PesterTimingConsole $e2eTiming $TopSlowFiles $TopSlowCases
$timingReport = [pscustomobject][ordered]@{
    schema_version = 1
    generated_at = [datetimeoffset]::UtcNow.ToString('o')
    pester_version = [string]$pesterVersion
    suite_elapsed_ms = $suiteTimer.ElapsedMilliseconds
    stages = @($unitTiming, $e2eTiming)
}
$timingDirectory = Split-Path $TimingReportPath -Parent
if (-not [string]::IsNullOrWhiteSpace($timingDirectory)) { New-Item -ItemType Directory -Path $timingDirectory -Force | Out-Null }
[System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($TimingReportPath), ($timingReport | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("test_timing_report={0}" -f ([System.IO.Path]::GetFullPath($TimingReportPath)))
$failed = 0
if ($unit -and $unit.FailedCount) { $failed += [int]$unit.FailedCount }
if ($e2e -and $e2e.FailedCount) { $failed += [int]$e2e.FailedCount }
if ($failed -gt 0) {
    $global:LASTEXITCODE = 1
    throw ("Pester failures: {0}" -f $failed)
}

# Ensure callers receive a deterministic success exit code.
$global:LASTEXITCODE = 0
