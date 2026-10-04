[CmdletBinding()]
param(
    [string]$UnitTestPath = (Join-Path $PSScriptRoot 'Unit'),
    [string]$E2ETestPath = (Join-Path $PSScriptRoot 'E2E'),
    [Alias('Path')][string[]]$TestPath = @(),
    [Alias('Name')][string[]]$TestName = @(),
    [string[]]$Tag = @(),
    [string[]]$ExcludeTag = @(),
    # Unfiltered full-suite runs are split across isolated shard processes.
    # Targeted runs (explicit -TestPath/-TestName) keep the single-process path
    # so their output contract stays exactly one summary line.
    [ValidateRange(1, 16)][int]$MaxParallel = [Math]::Max(1, [Math]::Min(4, [Environment]::ProcessorCount)),
    [ValidateRange(1, 7200)][int]$ShardTimeoutSeconds = 3600,
    [string]$ShardReportRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'reports\test-shards'),
    # Internal: set only by the parent process when spawning a shard worker.
    [string]$ShardJobPath = ''
)

$ErrorActionPreference = 'Stop'
$bootstrap = Join-Path $PSScriptRoot '..\scripts\quality\ensure-test-runtime.ps1'
$manifest = & $bootstrap

function Invoke-RepositoryPester {
    param(
        [string[]]$Paths,
        [string[]]$Names,
        [string[]]$Tags,
        [string[]]$ExcludeTags
    )
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $configuration = New-PesterConfiguration
    $configuration.Run.Path = $Paths
    $configuration.Run.PassThru = $true
    $configuration.Output.Verbosity = 'None'
    if ($Names.Count -gt 0) { $configuration.Filter.FullName = $Names }
    if ($Tags.Count -gt 0) { $configuration.Filter.Tag = $Tags }
    if ($ExcludeTags.Count -gt 0) { $configuration.Filter.ExcludeTag = $ExcludeTags }
    $result = Invoke-Pester -Configuration $configuration 3>$null 4>$null 5>$null 6>$null
    $stopwatch.Stop()
    return [pscustomobject]@{ result = $result; seconds = $stopwatch.Elapsed.TotalSeconds }
}

function Get-FailedTestDetail {
    param($Result)
    $failedTests = if ($Result.PSObject.Properties.Match('Failed').Count -gt 0) {
        @($Result.Failed)
    }
    else {
        @($Result.TestResult | Where-Object Result -eq 'Failed')
    }
    return @($failedTests | ForEach-Object {
            $message = if ($_.PSObject.Properties.Match('ErrorRecord').Count -gt 0) {
                [string]$_.ErrorRecord
            }
            else {
                [string]$_.FailureMessage
            }
            [pscustomobject]@{ name = [string]$_.Name; message = $message }
        })
}

# Shard worker: run only this shard's files, persist a machine-readable receipt,
# and print nothing so the parent's output contract is unaffected.
if (-not [string]::IsNullOrWhiteSpace($ShardJobPath)) {
    $job = Get-Content -LiteralPath $ShardJobPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $receipt = [ordered]@{
        schema_version     = 1
        status             = 'error'
        total_count        = 0
        passed_count       = 0
        failed_count       = 0
        skipped_count      = 0
        duration_seconds   = 0.0
        failures           = @()
        container_failures = @()
        error              = ''
    }
    try {
        $run = Invoke-RepositoryPester -Paths @($job.files | ForEach-Object { [string]$_ }) -Names @() -Tags @() -ExcludeTags @()
        $result = $run.result
        if (-not $result -or [int]$result.TotalCount -le 0) { throw 'Test discovery returned zero tests.' }
        $receipt.duration_seconds = [Math]::Round([double]$run.seconds, 3)
        $receipt.total_count = [int]$result.TotalCount
        $receipt.passed_count = [int]$result.PassedCount
        $receipt.failed_count = [int]$result.FailedCount
        $receipt.skipped_count = [int]$result.SkippedCount
        $receipt.failures = @(Get-FailedTestDetail $result)
        $receipt.container_failures = @($result.FailedContainers | ForEach-Object { [string]$_.Item })
        $receipt.status = if ([int]$result.FailedContainersCount -gt 0 -or [int]$result.FailedCount -gt 0) { 'failed' } else { 'passed' }
    }
    catch {
        $receipt.status = 'error'
        $receipt.error = $_.Exception.Message
    }
    [IO.File]::WriteAllText([string]$job.receipt, ($receipt | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
    exit $(if ([string]$receipt.status -eq 'passed') { 0 } else { 1 })
}

$paths = if ($TestPath.Count -eq 0) { @($UnitTestPath, $E2ETestPath) } else { @($TestPath) }
foreach ($path in $paths) {
    $testFiles = if (Test-Path -LiteralPath $path -PathType Leaf) { @(Get-Item -LiteralPath $path | Where-Object Name -Like '*.Tests.ps1') } else { @(Get-ChildItem -LiteralPath $path -Recurse -Filter '*.Tests.ps1' -File) }
    if ($testFiles.Count -eq 0) {
        throw ("Test discovery returned zero files: {0}" -f $path)
    }
}

# Sharding applies only to the unfiltered full-suite invocation, and only when
# there are more files than workers; every targeted run keeps the original path.
$shardCandidates = @()
if ($TestPath.Count -eq 0 -and $TestName.Count -eq 0 -and $Tag.Count -eq 0 -and $ExcludeTag.Count -eq 0 -and $MaxParallel -gt 1) {
    $shardCandidates = @(
        @(Get-ChildItem -LiteralPath $UnitTestPath -Recurse -Filter '*.Tests.ps1' -File | Sort-Object FullName)
        @(Get-ChildItem -LiteralPath $E2ETestPath -Recurse -Filter '*.Tests.ps1' -File | Sort-Object FullName)
    )
}

if ($shardCandidates.Count -gt $MaxParallel) {
    $shardCount = [Math]::Min($MaxParallel, $shardCandidates.Count)
    $runId = '{0}-{1}' -f ([DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $runRoot = Join-Path $ShardReportRoot $runId
    $null = New-Item -ItemType Directory -Path $runRoot -Force
    $selfPath = try { [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { '' }
    if ([string]::IsNullOrWhiteSpace($selfPath)) { $selfPath = (Get-Command pwsh -ErrorAction Stop).Source }

    $buckets = @()
    for ($index = 0; $index -lt $shardCount; $index++) { $buckets += , ([Collections.Generic.List[string]]::new()) }
    for ($index = 0; $index -lt $shardCandidates.Count; $index++) {
        $buckets[$index % $shardCount].Add([string]$shardCandidates[$index].FullName)
    }

    $jobs = [Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $shardCount; $index++) {
        $jobPath = Join-Path $runRoot ("shard-{0}.job.json" -f $index)
        $receiptPath = Join-Path $runRoot ("shard-{0}.receipt.json" -f $index)
        $jobSpec = [ordered]@{ files = @($buckets[$index].ToArray()); receipt = $receiptPath }
        [IO.File]::WriteAllText($jobPath, ($jobSpec | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $selfPath
        $startInfo.UseShellExecute = $false
        foreach ($argument in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-ShardJobPath', $jobPath)) {
            $startInfo.ArgumentList.Add($argument)
        }
        $process = [Diagnostics.Process]::Start($startInfo)
        $jobs.Add([pscustomobject]@{ process = $process; receipt = $receiptPath }) | Out-Null
    }

    $suiteTimer = [Diagnostics.Stopwatch]::StartNew()
    $shardTimedOut = $false
    while (@($jobs | Where-Object { -not $_.process.HasExited }).Count -gt 0) {
        if ($suiteTimer.Elapsed.TotalSeconds -gt $ShardTimeoutSeconds) { $shardTimedOut = $true; break }
        Start-Sleep -Milliseconds 200
    }
    if ($shardTimedOut) {
        foreach ($job in $jobs) { if (-not $job.process.HasExited) { $job.process.Kill($true) } }
        throw ("Test shards exceeded {0}s timeout." -f $ShardTimeoutSeconds)
    }

    $total = 0
    $passed = 0
    $failed = 0
    $skipped = 0
    $failureDetails = [Collections.Generic.List[object]]::new()
    $containerNames = [Collections.Generic.List[string]]::new()
    $shardErrors = [Collections.Generic.List[string]]::new()
    foreach ($job in $jobs) {
        $job.process.WaitForExit()
        $exitCode = $job.process.ExitCode
        $job.process.Dispose()
        if (-not (Test-Path -LiteralPath $job.receipt -PathType Leaf)) {
            $shardErrors.Add(("shard exited {0} without a receipt" -f $exitCode)) | Out-Null
            continue
        }
        $receipt = Get-Content -LiteralPath $job.receipt -Raw -Encoding UTF8 | ConvertFrom-Json
        $total += [int]$receipt.total_count
        $passed += [int]$receipt.passed_count
        $failed += [int]$receipt.failed_count
        $skipped += [int]$receipt.skipped_count
        foreach ($detail in @($receipt.failures)) { $failureDetails.Add($detail) | Out-Null }
        foreach ($name in @($receipt.container_failures)) { $containerNames.Add([string]$name) | Out-Null }
        if ([string]$receipt.status -eq 'error') {
            $shardErrors.Add([string]$receipt.error) | Out-Null
        }
        elseif ($exitCode -ne 0 -and [string]$receipt.status -eq 'passed') {
            $shardErrors.Add(("shard exited {0} but reported a pass" -f $exitCode)) | Out-Null
        }
    }
    $suiteTimer.Stop()

    Write-Host ("Tests: total={0} passed={1} failed={2} skipped={3} duration={4:n1}s" -f $total, $passed, $failed, $skipped, $suiteTimer.Elapsed.TotalSeconds)
    foreach ($detail in $failureDetails) {
        Write-Host ("FAILED: {0}" -f $detail.name)
        if (-not [string]::IsNullOrWhiteSpace([string]$detail.message)) { Write-Host ([string]$detail.message) }
    }
    if ($containerNames.Count -gt 0) {
        foreach ($name in $containerNames) { Write-Host ("CONTAINER FAILED: {0}" -f $name) }
        $global:LASTEXITCODE = 1
        throw ("Pester container failures: {0}" -f $containerNames.Count)
    }
    if ($shardErrors.Count -gt 0) {
        foreach ($message in $shardErrors) { Write-Host ("SHARD ERROR: {0}" -f $message) }
        $global:LASTEXITCODE = 1
        throw ("Test shard failures: {0}" -f $shardErrors.Count)
    }
    if ($failed -gt 0) {
        $global:LASTEXITCODE = 1
        throw ("Pester failures: {0}" -f $failed)
    }
    if ($passed -eq 0) {
        $global:LASTEXITCODE = 1
        throw 'No tests executed successfully; check filters and skipped tests.'
    }
    $global:LASTEXITCODE = 0
    exit 0
}

$run = Invoke-RepositoryPester -Paths $paths -Names $TestName -Tags $Tag -ExcludeTags $ExcludeTag
$result = $run.result
if (-not $result -or [int]$result.TotalCount -le 0) { throw 'Test discovery returned zero tests.' }
Write-Host ("Tests: total={0} passed={1} failed={2} skipped={3} duration={4:n1}s" -f [int]$result.TotalCount, [int]$result.PassedCount, [int]$result.FailedCount, [int]$result.SkippedCount, $run.seconds)
if ([int]$result.FailedContainersCount -gt 0) {
    foreach ($container in @($result.FailedContainers)) {
        Write-Host ("CONTAINER FAILED: {0}" -f [string]$container.Item)
        if ($container.ErrorRecord) { Write-Host ([string]$container.ErrorRecord) }
    }
    $global:LASTEXITCODE = 1
    throw ("Pester container failures: {0}" -f $result.FailedContainersCount)
}
if ([int]$result.FailedCount -gt 0) {
    foreach ($test in @(Get-FailedTestDetail $result)) {
        Write-Host ("FAILED: {0}" -f $test.name)
        if (-not [string]::IsNullOrWhiteSpace([string]$test.message)) { Write-Host ([string]$test.message) }
    }
    $global:LASTEXITCODE = 1
    throw ("Pester failures: {0}" -f $result.FailedCount)
}

if ([int]$result.PassedCount -eq 0) {
    $global:LASTEXITCODE = 1
    throw 'No tests executed successfully; check filters and skipped tests.'
}

$global:LASTEXITCODE = 0
