[CmdletBinding()]
param(
    [string]$UnitTestPath = (Join-Path $PSScriptRoot 'Unit'),
    [string]$E2ETestPath = (Join-Path $PSScriptRoot 'E2E'),
    [Alias('Path')][string[]]$TestPath = @(),
    [Alias('Name')][string[]]$TestName = @(),
    [string[]]$Tag = @(),
    [string[]]$ExcludeTag = @(),
    # Unfiltered full-suite runs are split across isolated shard processes.
    # Targeted runs (explicit -TestPath/-TestName) run in one isolated worker
    # process so the parent's output contract is a start line (batch, wall-clock
    # bound, receipt path) followed by one summary line.
    [ValidateRange(1, 16)][int]$MaxParallel = [Math]::Max(1, [Math]::Min(4, [Environment]::ProcessorCount)),
    [ValidateRange(1, 7200)][int]$ShardTimeoutSeconds = 3600,
    # Bounds the isolated worker that runs an explicit targeted selection
    # (-TestPath/-TestName/-Tag) or an unsharded default run. The 900s default
    # keeps the bound meaningful for targeted batches (seconds in a healthy
    # terminal, minutes on a slow first run that still bootstraps Pester);
    # passing 0 falls back to ShardTimeoutSeconds instead. Every path through
    # this runner has a wall-clock bound: a wedged test file must fail with a
    # diagnostic, not hang forever.
    [ValidateRange(0, 7200)][int]$TargetedTimeoutSeconds = 900,
    [string]$ShardReportRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'reports\test-shards'),
    # Internal: set only by the parent process when spawning a shard worker.
    [string]$ShardJobPath = '',
    # Internal: set only by the parent process when spawning a targeted worker.
    [string]$TargetedJobPath = ''
)

$ErrorActionPreference = 'Stop'
$bootstrap = Join-Path $PSScriptRoot '..\scripts\quality\ensure-test-runtime.ps1'
$manifest = & $bootstrap

function Stop-TestRunnerProcess([Diagnostics.Process]$Process) {
    if ($null -eq $Process) { return }
    # A timeout boundary is inherently racy: the worker may exit after the
    # HasExited check but before Kill. Swallow that expected race and preserve
    # the caller's timeout/receipt diagnostic instead of replacing it with an
    # InvalidOperationException from Kill().
    try {
        if (-not $Process.HasExited) {
            try { $Process.Kill($true) } catch { }
        }
    }
    catch { }
    try { $null = $Process.WaitForExit(5000) } catch { }
}

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
        $receipt.container_failure_details = @($result.FailedContainers | ForEach-Object {
                [pscustomobject]@{
                    container = [string]$_.Item
                    error     = if ($_.ErrorRecord) { [string]$_.ErrorRecord } else { '' }
                }
            })
        $receipt.status = if ([int]$result.FailedContainersCount -gt 0 -or [int]$result.FailedCount -gt 0) { 'failed' } else { 'passed' }
    }
    catch {
        $receipt.status = 'error'
        $receipt.error = $_.Exception.Message
    }
    [IO.File]::WriteAllText([string]$job.receipt, ($receipt | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
    exit $(if ([string]$receipt.status -eq 'passed') { 0 } else { 1 })
}

# Targeted worker: run the requested selection in an isolated process so a
# wedged test file cannot block the caller forever. Persist a machine-readable
# receipt and print nothing so the parent's output contract is unaffected.
if (-not [string]::IsNullOrWhiteSpace($TargetedJobPath)) {
    $job = Get-Content -LiteralPath $TargetedJobPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $receipt = [ordered]@{
        schema_version            = 1
        status                    = 'error'
        total_count               = 0
        passed_count              = 0
        failed_count              = 0
        skipped_count             = 0
        duration_seconds          = 0.0
        failures                  = @()
        container_failures        = @()
        container_failure_details = @()
        error                     = ''
    }
    try {
        $run = Invoke-RepositoryPester -Paths @($job.paths | ForEach-Object { [string]$_ }) -Names @($job.names | ForEach-Object { [string]$_ }) -Tags @($job.tags | ForEach-Object { [string]$_ }) -ExcludeTags @($job.excludeTags | ForEach-Object { [string]$_ })
        $result = $run.result
        if (-not $result -or [int]$result.TotalCount -le 0) { throw 'Test discovery returned zero tests.' }
        $receipt.duration_seconds = [Math]::Round([double]$run.seconds, 3)
        $receipt.total_count = [int]$result.TotalCount
        $receipt.passed_count = [int]$result.PassedCount
        $receipt.failed_count = [int]$result.FailedCount
        $receipt.skipped_count = [int]$result.SkippedCount
        $receipt.failures = @(Get-FailedTestDetail $result)
        $receipt.container_failures = @($result.FailedContainers | ForEach-Object { [string]$_.Item })
        $receipt.container_failure_details = @($result.FailedContainers | ForEach-Object {
                [pscustomobject]@{
                    container = [string]$_.Item
                    error     = if ($_.ErrorRecord) { [string]$_.ErrorRecord } else { '' }
                }
            })
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

    # Record whether this process tree is sandbox-instrumented. Instrumented
    # runs are slower (deletes are brokered, HTTP is proxied) so their wall
    # clock must not be read as code cost. See
    # docs/runbooks/agent-sandbox-instrumentation.md.
    $shimMarkers = [ordered]@{
        safe_delete_shim = [bool]($env:CODEBUDDY_SAFE_DELETE_ENABLED -or $env:CODEBUDDY_SAFE_DELETE_SANDBOX)
        sandbox_ipc      = [bool](-not [string]::IsNullOrWhiteSpace($env:SANDBOX_CENTER_IPC_ADDRESS))
        node_shim        = [bool](([string]$env:NODE_OPTIONS) -match 'shim')
        python_shim      = [bool](([string]$env:PYTHONPATH) -match 'shim')
    }
    $instrumented = @($shimMarkers.Values | Where-Object { $_ }).Count -gt 0
    $environmentRecord = [ordered]@{
        schema_version = 1
        recorded_at    = [DateTimeOffset]::UtcNow.ToString('o')
        instrumented   = $instrumented
        markers        = $shimMarkers
        http_proxy     = [bool](-not [string]::IsNullOrWhiteSpace($env:HTTP_PROXY))
        max_parallel   = $MaxParallel
        shard_count    = $shardCount
        note           = 'Instrumented runs must not be read as code cost; re-measure outside the sandbox (CI or a plain terminal).'
    }
    [IO.File]::WriteAllText((Join-Path $runRoot 'environment.json'), ($environmentRecord | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))

    # Pester 6.1.0 initializes its TestRegistry fixture by creating the shared
    # HKCU:\Software\Pester parent key on first use. On a fresh profile (CI
    # runner) several shard processes race to create that key and the losers
    # abort their whole container ("A key in this path already exists" —
    # observed as random CONTAINER FAILED runs). Priming the key here removes
    # the race; a profile that already has the key skips straight through.
    $pesterRegistryKey = 'Registry::HKEY_CURRENT_USER\Software\Pester'
    if (-not (Test-Path $pesterRegistryKey)) {
        try { New-Item -Path $pesterRegistryKey -Force -ErrorAction Stop | Out-Null } catch { }
    }

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
        foreach ($job in $jobs) { Stop-TestRunnerProcess $job.process }
        throw ("Test shards exceeded {0}s timeout." -f $ShardTimeoutSeconds)
    }

    $total = 0
    $passed = 0
    $failed = 0
    $skipped = 0
    $failureDetails = [Collections.Generic.List[object]]::new()
    $containerNames = [Collections.Generic.List[string]]::new()
    $containerErrors = [Collections.Generic.List[string]]::new()
    $shardErrors = [Collections.Generic.List[string]]::new()
    foreach ($job in $jobs) {
        # The poll loop above already observed HasExited on every worker, so
        # ExitCode is valid here and no parameterless WaitForExit() is needed.
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
        foreach ($detail in @($receipt.container_failure_details)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$detail.error)) {
                $containerErrors.Add(("[{0}] {1}" -f $detail.container, $detail.error)) | Out-Null
            }
        }
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
        foreach ($message in $containerErrors) { Write-Host ("CONTAINER ERROR: {0}" -f $message) }
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

# Targeted runs execute in an isolated worker process so the wall clock is
# bounded: a wedged test file is killed and reported instead of hanging the
# caller forever. The parent reproduces the original single-process output
# contract (a start line, then one summary line, plus bounded failure
# diagnostics).
$targetedTimeoutSeconds = if ($TargetedTimeoutSeconds -gt 0) { $TargetedTimeoutSeconds } else { $ShardTimeoutSeconds }
$targetedRunId = '{0}-{1}' -f ([DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$targetedRunRoot = Join-Path $ShardReportRoot ('targeted-{0}' -f $targetedRunId)
$null = New-Item -ItemType Directory -Path $targetedRunRoot -Force
$targetedJobPath = Join-Path $targetedRunRoot 'targeted.job.json'
$targetedReceiptPath = Join-Path $targetedRunRoot 'targeted.receipt.json'
$targetedJobSpec = [ordered]@{ paths = @($paths); names = @($TestName); tags = @($Tag); excludeTags = @($ExcludeTag); receipt = $targetedReceiptPath }
[IO.File]::WriteAllText($targetedJobPath, ($targetedJobSpec | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))

# Emit the bound up front so a redirected log is never silently empty: batch,
# wall-clock limit and receipt path are visible from second one, and a quiet
# log means "waiting for the worker", never "nothing is running".
Write-Host ("Targeted run started: batch=[{0}] timeout={1}s receipt={2}" -f (@($paths) -join '; '), $targetedTimeoutSeconds, $targetedReceiptPath)

$selfPath = try { [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { '' }
if ([string]::IsNullOrWhiteSpace($selfPath)) { $selfPath = (Get-Command pwsh -ErrorAction Stop).Source }
$startInfo = [Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $selfPath
$startInfo.UseShellExecute = $false
foreach ($argument in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-TargetedJobPath', $targetedJobPath)) {
    $startInfo.ArgumentList.Add($argument)
}
$process = [Diagnostics.Process]::Start($startInfo)
$targetedTimer = [Diagnostics.Stopwatch]::StartNew()
if (-not $process.WaitForExit($targetedTimeoutSeconds * 1000)) {
    Stop-TestRunnerProcess $process
    $process.Dispose()
    throw ("Targeted tests exceeded {0}s timeout; the worker was killed. Batch: {1}. Job: {2}. Receipt: {3}" -f $targetedTimeoutSeconds, (@($paths) -join '; '), $targetedJobPath, $targetedReceiptPath)
}
$process.Dispose()
$targetedTimer.Stop()

if (-not (Test-Path -LiteralPath $targetedReceiptPath -PathType Leaf)) {
    throw ("Targeted test worker exited without a receipt (batch: {0})." -f (@($paths) -join '; '))
}
$receipt = Get-Content -LiteralPath $targetedReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$receipt.status -eq 'error') { throw [string]$receipt.error }

Write-Host ("Tests: total={0} passed={1} failed={2} skipped={3} duration={4:n1}s" -f [int]$receipt.total_count, [int]$receipt.passed_count, [int]$receipt.failed_count, [int]$receipt.skipped_count, [double]$receipt.duration_seconds)
if (@($receipt.container_failures).Count -gt 0) {
    foreach ($container in @($receipt.container_failures)) { Write-Host ("CONTAINER FAILED: {0}" -f [string]$container) }
    foreach ($detail in @($receipt.container_failure_details)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$detail.error)) { Write-Host ([string]$detail.error) }
    }
    $global:LASTEXITCODE = 1
    throw ("Pester container failures: {0}" -f @($receipt.container_failures).Count)
}
if ([int]$receipt.failed_count -gt 0) {
    foreach ($test in @($receipt.failures)) {
        Write-Host ("FAILED: {0}" -f [string]$test.name)
        if (-not [string]::IsNullOrWhiteSpace([string]$test.message)) { Write-Host ([string]$test.message) }
    }
    $global:LASTEXITCODE = 1
    throw ("Pester failures: {0}" -f [int]$receipt.failed_count)
}

if ([int]$receipt.passed_count -eq 0) {
    $global:LASTEXITCODE = 1
    throw 'No tests executed successfully; check filters and skipped tests.'
}

$global:LASTEXITCODE = 0
