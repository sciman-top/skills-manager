[CmdletBinding()]
param(
    [ValidateRange(1, 50)]
    [int]$TopSlowFiles = 10,
    [ValidateRange(1, 100)]
    [int]$TopSlowCases = 15,
    [string]$TimingReportPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'reports\test-timings\current.json'),
    [string]$UnitTestPath = (Join-Path $PSScriptRoot 'Unit'),
    [string]$E2ETestPath = (Join-Path $PSScriptRoot 'E2E'),
    [ValidateRange(1, 16)]
    [int]$MaxParallel = 4,
    [ValidateRange(1, 1800)]
    [int]$TestFileTimeoutSeconds = 180,
    [string]$ShardReportRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'reports\test-shards'),
    [string]$SchedulingTimingPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'reports\test-timings\current.json'),
    [string[]]$SerialTestFiles = @(),
    [string]$QualityGateRunId = '',
    [string]$QualityGateSourceFingerprintJson = ''
)

$ErrorActionPreference = 'Stop'
$workerPath = Join-Path $PSScriptRoot 'run-pester-test-file.ps1'
$schedulingScriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\quality\TestFileScheduling.ps1'
. $schedulingScriptPath
$qualityGateSourceStart = $null
if (-not [string]::IsNullOrWhiteSpace($QualityGateRunId) -or -not [string]::IsNullOrWhiteSpace($QualityGateSourceFingerprintJson)) {
    if ($QualityGateRunId -notmatch '^qgr-[A-Za-z0-9][A-Za-z0-9._-]{0,95}$' -or [string]::IsNullOrWhiteSpace($QualityGateSourceFingerprintJson)) {
        throw 'Quality gate timing binding requires a safe run id and source fingerprint JSON.'
    }
    try { $qualityGateSourceStart = $QualityGateSourceFingerprintJson | ConvertFrom-Json -ErrorAction Stop }
    catch { throw ("Quality gate source fingerprint JSON is invalid: {0}" -f $_.Exception.Message) }
    foreach ($field in @('repo_root', 'head', 'index_fingerprint', 'tracked_worktree_fingerprint', 'untracked_worktree_fingerprint')) {
        if ([string]::IsNullOrWhiteSpace([string]$qualityGateSourceStart.$field)) { throw ("Quality gate source fingerprint is missing {0}." -f $field) }
    }
}

function Get-TestFiles([string]$Path, [string]$Stage) {
    $files = @(Get-ChildItem -LiteralPath $Path -Recurse -Filter '*.Tests.ps1' -File |
        Sort-Object FullName)
    if ($files.Count -le 0) {
        throw ("{0} test discovery returned zero tests" -f $Stage)
    }
    return $files
}

function Stop-TestWorkerTree([int]$ProcessId) {
    $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $descendants = [Collections.Generic.List[int]]::new()
    $frontier = @($ProcessId)
    while ($frontier.Count -gt 0) {
        $parents = @($frontier)
        $frontier = @($all | Where-Object { [int]$_.ParentProcessId -in $parents } | Select-Object -ExpandProperty ProcessId)
        foreach ($id in $frontier) { $descendants.Add([int]$id) | Out-Null }
    }
    foreach ($id in @($descendants | Sort-Object -Descending)) {
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
    }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

function New-WorkerArguments($Item) {
    return @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $workerPath),
        '-TestFile', ('"{0}"' -f $Item.file.FullName),
        '-Stage', $Item.stage,
        '-ReceiptPath', ('"{0}"' -f $Item.receipt_path)
    )
}

function Write-FailureTail([string]$Path, [string]$Label) {
    if (Test-Path -LiteralPath $Path) {
        Write-Host ("{0}:" -f $Label)
        Get-Content -LiteralPath $Path -Tail 80 | ForEach-Object { Write-Host $_ }
    }
}

function Get-RelativeTestPath([string]$TestFile, [string]$RootPath) {
    $file = [System.IO.Path]::GetFullPath($TestFile)
    $root = [System.IO.Path]::GetFullPath($RootPath)
    if ([System.IO.File]::Exists($root)) { return [System.IO.Path]::GetFileName($file) }
    return $file.Substring($root.Length).TrimStart('\', '/')
}

function Convert-ToTimingStage([string]$Stage, [object[]]$Receipts, [string]$RootPath) {
    $root = [System.IO.Path]::GetFullPath($RootPath)
    $files = @($Receipts | ForEach-Object {
        [pscustomobject][ordered]@{
            path = Get-RelativeTestPath ([string]$_.test_file) $root
            elapsed_ms = [double]$_.elapsed_ms
            test_count = [int]$_.total_count
            status = [string]$_.status
        }
    } | Sort-Object elapsed_ms -Descending)
    $cases = @($Receipts | ForEach-Object {
        $receipt = $_
        @($receipt.cases) | ForEach-Object {
            [pscustomobject][ordered]@{
                stage = $Stage
                path = Get-RelativeTestPath ([string]$receipt.test_file) $root
                describe = [string]$_.describe
                name = [string]$_.name
                result = [string]$_.result
                elapsed_ms = [double]$_.elapsed_ms
            }
        }
    } | Sort-Object elapsed_ms -Descending)
    return [pscustomobject][ordered]@{ stage = $Stage; files = $files; cases = $cases }
}

function Write-PesterTimingConsole($Profile, [int]$FileLimit, [int]$CaseLimit) {
    $rank = 0
    foreach ($row in @($Profile.files | Select-Object -First $FileLimit)) {
        $rank++
        Write-Host ('slow_test_file stage={0} rank={1} elapsed_ms={2} tests={3} status={4} path={5}' -f $Profile.stage, $rank, $row.elapsed_ms, $row.test_count, $row.status, $row.path)
    }
    $rank = 0
    foreach ($row in @($Profile.cases | Select-Object -First $CaseLimit)) {
        $rank++
        Write-Host ('slow_test_case stage={0} rank={1} elapsed_ms={2} result={3} path={4} describe={5} name={6}' -f $Profile.stage, $rank, $row.elapsed_ms, $row.result, $row.path, $row.describe, $row.name)
    }
}

$unitFiles = Get-TestFiles $UnitTestPath 'unit'
$e2eFiles = Get-TestFiles $E2ETestPath 'e2e'
$schedulingTiming = Import-TestFileSchedulingTiming -Path $SchedulingTimingPath
$runId = '{0}-{1}' -f ([datetimeoffset]::UtcNow.ToString('yyyyMMdd-HHmmss')), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$runRoot = Join-Path $ShardReportRoot $runId
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$requiredPester = Get-Module -ListAvailable -Name Pester | Where-Object Version -eq ([version]'4.10.1') | Select-Object -First 1
if (-not $requiredPester) { throw 'Pester 4.10.1 is required to run the test suite.' }
Import-Module Pester -RequiredVersion 4.10.1 -Force | Out-Null

$pending = [Collections.Generic.Queue[object]]::new()
$schedulingStages = [Collections.Generic.List[object]]::new()
foreach ($stageSpec in @(
    @{ stage = 'unit'; files = $unitFiles; root = $UnitTestPath },
    @{ stage = 'e2e'; files = $e2eFiles; root = $E2ETestPath }
)) {
    $schedule = Get-TestFileSchedule -Files @($stageSpec.files) -Stage $stageSpec.stage -RootPath $stageSpec.root -Timing $schedulingTiming `
        -SerialTestFiles $SerialTestFiles
    $orderedFiles = @($schedule.files)
    $schedulingStages.Add([pscustomobject][ordered]@{
        stage = $stageSpec.stage
        file_count = $schedule.file_count
        matched_file_count = $schedule.matched_file_count
    }) | Out-Null
    foreach ($file in $orderedFiles) {
        $safeName = '{0}-{1}' -f $stageSpec.stage, ($file.BaseName -replace '[^A-Za-z0-9_.-]', '_')
        $pending.Enqueue([pscustomobject]@{
            stage = $stageSpec.stage
            file = $file
            serial = $SerialTestFiles -contains $file.Name
            receipt_path = Join-Path $runRoot ($safeName + '.receipt.json')
            stdout_path = Join-Path $runRoot ($safeName + '.out.log')
            stderr_path = Join-Path $runRoot ($safeName + '.err.log')
        })
    }
}
Write-Host ('test_scheduling strategy=historical_lpt source_status={0} matched_files={1} source={2}' -f $schedulingTiming.status, (($schedulingStages | Measure-Object -Property matched_file_count -Sum).Sum), $schedulingTiming.path)

$active = [Collections.Generic.List[object]]::new()
$receipts = [Collections.Generic.List[object]]::new()
$suiteTimer = [Diagnostics.Stopwatch]::StartNew()
while ($pending.Count -gt 0 -or $active.Count -gt 0) {
    while ($pending.Count -gt 0 -and $active.Count -lt $MaxParallel) {
        if ($active.Count -gt 0 -and [string]$pending.Peek().stage -ne [string]$active[0].item.stage) { break }
        if ($active.Count -gt 0 -and ([bool]$pending.Peek().serial -or @($active | Where-Object { $_.item.serial }).Count -gt 0)) { break }
        $item = $pending.Dequeue()
        $process = Start-Process -FilePath 'pwsh' -ArgumentList (New-WorkerArguments $item) -PassThru -NoNewWindow -RedirectStandardOutput $item.stdout_path -RedirectStandardError $item.stderr_path
        $active.Add([pscustomobject]@{ item = $item; process = $process; timer = [Diagnostics.Stopwatch]::StartNew() }) | Out-Null
    }

    foreach ($job in @($active)) {
        $timedOut = $job.timer.Elapsed.TotalSeconds -gt $TestFileTimeoutSeconds
        if (-not $job.process.HasExited -and -not $timedOut) { continue }

        if ($timedOut -and -not $job.process.HasExited) {
            Stop-TestWorkerTree $job.process.Id
            $receipt = [pscustomobject][ordered]@{
                schema_version = 1; stage = $job.item.stage; test_file = $job.item.file.FullName
                status = 'timed_out'; total_count = 0; passed_count = 0; failed_count = 1
                skipped_count = 0; pending_count = 0; inconclusive_count = 0
                started_at = ([datetimeoffset]::UtcNow - $job.timer.Elapsed).ToString('o'); elapsed_ms = [long]$job.timer.ElapsedMilliseconds; cases = @()
                error = ("test file exceeded {0}s timeout" -f $TestFileTimeoutSeconds)
            }
            [System.IO.File]::WriteAllText($job.item.receipt_path, ($receipt | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
        }
        elseif (Test-Path -LiteralPath $job.item.receipt_path) {
            $receipt = Get-Content -LiteralPath $job.item.receipt_path -Raw | ConvertFrom-Json
        }
        else {
            $receipt = [pscustomobject][ordered]@{
                schema_version = 1; stage = $job.item.stage; test_file = $job.item.file.FullName
                status = 'missing_receipt'; total_count = 0; passed_count = 0; failed_count = 1
                skipped_count = 0; pending_count = 0; inconclusive_count = 0
                started_at = ([datetimeoffset]::UtcNow - $job.timer.Elapsed).ToString('o'); elapsed_ms = [long]$job.timer.ElapsedMilliseconds; cases = @()
                error = 'worker exited without a terminal receipt'
            }
        }

        $job.timer.Stop()
        if ($job.process.HasExited -and $job.process.ExitCode -ne 0 -and [string]$receipt.status -eq 'passed') {
            $receipt.status = 'process_failed'
            $receipt.failed_count = 1
            $receipt.error = ("worker exited with code {0}" -f $job.process.ExitCode)
        }
        $receipts.Add($receipt) | Out-Null
        Write-Host ('test_file stage={0} serial={1} status={2} elapsed_ms={3} tests={4} path={5}' -f $receipt.stage, ([bool]$job.item.serial).ToString().ToLowerInvariant(), $receipt.status, $receipt.elapsed_ms, $receipt.total_count, $job.item.file.Name)
        if ([string]$receipt.status -ne 'passed') {
            Write-FailureTail $job.item.stdout_path 'worker_stdout_tail'
            Write-FailureTail $job.item.stderr_path 'worker_stderr_tail'
        }
        $active.Remove($job) | Out-Null
        $job.process.Dispose()
    }
    if ($active.Count -gt 0) { Start-Sleep -Milliseconds 100 }
}
$suiteTimer.Stop()

$unitReceipts = @($receipts | Where-Object stage -eq 'unit')
$e2eReceipts = @($receipts | Where-Object stage -eq 'e2e')
$unitTiming = Convert-ToTimingStage 'unit' $unitReceipts $UnitTestPath
$e2eTiming = Convert-ToTimingStage 'e2e' $e2eReceipts $E2ETestPath
function Get-StageWallElapsed([object[]]$StageReceipts) {
    $starts = @($StageReceipts | ForEach-Object { [datetimeoffset]::Parse([string]$_.started_at) })
    $ends = @($StageReceipts | ForEach-Object { [datetimeoffset]::Parse([string]$_.started_at).AddMilliseconds([double]$_.elapsed_ms) })
    return [long](($ends | Sort-Object -Descending | Select-Object -First 1) - ($starts | Sort-Object | Select-Object -First 1)).TotalMilliseconds
}
$unitElapsed = Get-StageWallElapsed $unitReceipts
$e2eElapsed = Get-StageWallElapsed $e2eReceipts
Write-Host ("unit_elapsed_ms={0}" -f $unitElapsed)
Write-Host ("e2e_elapsed_ms={0}" -f $e2eElapsed)
Write-Host ("test_suite_elapsed_ms={0}" -f $suiteTimer.ElapsedMilliseconds)
Write-PesterTimingConsole $unitTiming $TopSlowFiles $TopSlowCases
Write-PesterTimingConsole $e2eTiming $TopSlowFiles $TopSlowCases
$totals = [pscustomobject]@{
    total = [int](($receipts | Measure-Object -Property total_count -Sum).Sum)
    passed = [int](($receipts | Measure-Object -Property passed_count -Sum).Sum)
    failed = [int](($receipts | Measure-Object -Property failed_count -Sum).Sum)
    skipped = [int](($receipts | Measure-Object -Property skipped_count -Sum).Sum)
    pending = [int](($receipts | Measure-Object -Property pending_count -Sum).Sum)
    inconclusive = [int](($receipts | Measure-Object -Property inconclusive_count -Sum).Sum)
}
Write-Host ('Tests completed in {0}ms' -f $suiteTimer.ElapsedMilliseconds)
Write-Host ('Tests Passed: {0}, Failed: {1}, Skipped: {2}, Pending: {3}, Inconclusive: {4}, Total: {5}' -f $totals.passed, $totals.failed, $totals.skipped, $totals.pending, $totals.inconclusive, $totals.total)

$timingReport = [pscustomobject][ordered]@{
    schema_version = 3
    generated_at = [datetimeoffset]::UtcNow.ToString('o')
    quality_gate_run_id = if ([string]::IsNullOrWhiteSpace($QualityGateRunId)) { $null } else { $QualityGateRunId }
    quality_gate_source_start = $qualityGateSourceStart
    pester_version = '4.10.1'
    execution_model = 'isolated_file_workers'
    scheduling = [pscustomobject][ordered]@{
        strategy = 'historical_lpt'
        source_status = $schedulingTiming.status
        source_path = $schedulingTiming.path
        matched_file_count = [int](($schedulingStages | Measure-Object -Property matched_file_count -Sum).Sum)
        stages = [object[]]@($schedulingStages.ToArray())
    }
    max_parallel = $MaxParallel
    test_file_timeout_seconds = $TestFileTimeoutSeconds
    suite_elapsed_ms = $suiteTimer.ElapsedMilliseconds
    shard_report_root = [System.IO.Path]::GetFullPath($runRoot)
    stages = @($unitTiming, $e2eTiming)
}
$timingDirectory = Split-Path $TimingReportPath -Parent
if (-not [string]::IsNullOrWhiteSpace($timingDirectory)) { New-Item -ItemType Directory -Path $timingDirectory -Force | Out-Null }
[System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($TimingReportPath), ($timingReport | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("test_timing_report={0}" -f ([System.IO.Path]::GetFullPath($TimingReportPath)))
Write-Host ("test_shard_receipts={0}" -f ([System.IO.Path]::GetFullPath($runRoot)))

$failed = @($receipts | Where-Object { [string]$_.status -ne 'passed' -or [int]$_.failed_count -gt 0 })
if ($failed.Count -gt 0) {
    $global:LASTEXITCODE = 1
    throw ("Pester shard failures: {0}" -f $failed.Count)
}

$global:LASTEXITCODE = 0
