$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $repoRoot 'scripts\quality\QualityGateIntegrity.ps1')

function New-QualityGateIntegrityFixture([string]$Name) {
    $root = Join-Path $TestDrive $Name
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    & git -C $root init -q
    & git -C $root config user.email 'quality-gate@example.invalid'
    & git -C $root config user.name 'Quality Gate Test'
    [IO.File]::WriteAllText((Join-Path $root 'tracked.txt'), 'fixture', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $root '.gitignore'), "reports/`n", [Text.UTF8Encoding]::new($false))
    & git -C $root add tracked.txt .gitignore
    & git -C $root commit -qm fixture
    return [pscustomobject]@{
        root = $root
        receipt_root = Join-Path $root 'reports\quality-gates'
        timing_path = Join-Path $root 'reports\test-timings\qgr-fixture.json'
    }
}

function Write-QualityGateTimingFixture($Fixture, [string]$RunId, $Source) {
    $directory = Split-Path -Parent $Fixture.timing_path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $timing = [ordered]@{
        schema_version = 3
        generated_at = [DateTimeOffset]::UtcNow.ToString('o')
        quality_gate_run_id = $RunId
        quality_gate_source_start = $Source
        suite_elapsed_ms = 10
        stages = @(
            [ordered]@{ stage = 'unit'; files = @([ordered]@{ path = 'Unit.Tests.ps1'; elapsed_ms = 5; test_count = 1; status = 'passed' }); cases = @() },
            [ordered]@{ stage = 'e2e'; files = @([ordered]@{ path = 'E2E.Tests.ps1'; elapsed_ms = 5; test_count = 1; status = 'passed' }); cases = @() }
        )
    }
    [IO.File]::WriteAllText($Fixture.timing_path, ($timing | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
}

function New-QualityGateRows([string]$Profile = 'full') {
    return @(Get-QualityGateRequiredRoster $Profile | ForEach-Object { [pscustomobject]@{ name = $_; passed = $true; elapsed_ms = 1 } })
}

Describe 'Quality gate receipt integrity' {
    It 'orders ordinary workers by historical duration while preserving in-process and serial barriers' {
        $schedulerPath = Join-Path $repoRoot 'scripts\quality\TestFileScheduling.ps1'
        Test-Path -LiteralPath $schedulerPath -PathType Leaf | Should Be $true
        if (-not (Test-Path -LiteralPath $schedulerPath -PathType Leaf)) { return }
        . $schedulerPath

        $testRoot = Join-Path $TestDrive 'scheduler-order'
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        foreach ($name in @('Fast.Tests.ps1', 'InProcess.Tests.ps1', 'Serial.Tests.ps1', 'Slow.Tests.ps1', 'Unknown.Tests.ps1')) {
            [IO.File]::WriteAllText((Join-Path $testRoot $name), '# fixture', [Text.UTF8Encoding]::new($false))
        }
        $historyPath = Join-Path $TestDrive 'scheduler-history.json'
        $history = [ordered]@{
            schema_version = 3
            stages = @([ordered]@{
                stage = 'unit'
                files = @(
                    [ordered]@{ path = 'Fast.Tests.ps1'; elapsed_ms = 10 },
                    [ordered]@{ path = 'Slow.Tests.ps1'; elapsed_ms = 900 }
                )
            })
        }
        [IO.File]::WriteAllText($historyPath, ($history | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))

        $timing = Import-TestFileSchedulingTiming -Path $historyPath
        $schedule = Get-TestFileSchedule -Files @(Get-ChildItem -LiteralPath $testRoot -Filter '*.Tests.ps1' -File) `
            -Stage unit -RootPath $testRoot -Timing $timing -InProcessTestFiles @('InProcess.Tests.ps1') -SerialTestFiles @('Serial.Tests.ps1')

        @($schedule.files | ForEach-Object Name) | Should Be @(
            'InProcess.Tests.ps1',
            'Serial.Tests.ps1',
            'Slow.Tests.ps1',
            'Fast.Tests.ps1',
            'Unknown.Tests.ps1'
        )
        $timing.status | Should Be 'loaded'
        $schedule.matched_file_count | Should Be 2
    }

    It 'falls back to deterministic name ordering when historical timing is unavailable' {
        $schedulerPath = Join-Path $repoRoot 'scripts\quality\TestFileScheduling.ps1'
        Test-Path -LiteralPath $schedulerPath -PathType Leaf | Should Be $true
        if (-not (Test-Path -LiteralPath $schedulerPath -PathType Leaf)) { return }
        . $schedulerPath

        $testRoot = Join-Path $TestDrive 'scheduler-fallback'
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        foreach ($name in @('Zulu.Tests.ps1', 'Alpha.Tests.ps1')) {
            [IO.File]::WriteAllText((Join-Path $testRoot $name), '# fixture', [Text.UTF8Encoding]::new($false))
        }

        $timing = Import-TestFileSchedulingTiming -Path (Join-Path $TestDrive 'missing-history.json')
        $schedule = Get-TestFileSchedule -Files @(Get-ChildItem -LiteralPath $testRoot -Filter '*.Tests.ps1' -File) `
            -Stage unit -RootPath $testRoot -Timing $timing -InProcessTestFiles @() -SerialTestFiles @()

        @($schedule.files | ForEach-Object Name) | Should Be @('Alpha.Tests.ps1', 'Zulu.Tests.ps1')
        $timing.status | Should Be 'missing'
        $schedule.matched_file_count | Should Be 0
    }

    It 'emits a test timing report bound to the supplied quality gate run and source' {
        $fixture = New-QualityGateIntegrityFixture 'timing-runner-binding'
        $unitRoot = Join-Path $fixture.root 'unit'
        $e2eRoot = Join-Path $fixture.root 'e2e'
        New-Item -ItemType Directory -Path $unitRoot, $e2eRoot -Force | Out-Null
        foreach ($path in @((Join-Path $unitRoot 'Passing.Tests.ps1'), (Join-Path $e2eRoot 'Passing.Tests.ps1'))) {
            [IO.File]::WriteAllText($path, "Describe 'fixture' { It 'passes' { `$true | Should Be `$true } }", [Text.UTF8Encoding]::new($false))
        }
        $source = Get-QualityGateSourceFingerprint -RepoRoot $fixture.root
        $sourceJson = $source | ConvertTo-Json -Depth 10 -Compress
        $timingPath = Join-Path $fixture.root 'reports\test-timings\qgr-runner-fixture.json'
        $schedulingTimingPath = Join-Path $fixture.root 'reports\test-timings\history.json'
        $shardRoot = Join-Path $fixture.root 'reports\test-shards'
        New-Item -ItemType Directory -Path (Split-Path -Parent $schedulingTimingPath) -Force | Out-Null
        $schedulingTiming = [ordered]@{
            schema_version = 3
            stages = @([ordered]@{
                stage = 'unit'
                files = @([ordered]@{ path = 'Passing.Tests.ps1'; elapsed_ms = 900 })
            })
        }
        [IO.File]::WriteAllText($schedulingTimingPath, ($schedulingTiming | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))

        $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'tests\run.ps1') `
                -UnitTestPath $unitRoot -E2ETestPath $e2eRoot -TimingReportPath $timingPath -ShardReportRoot $shardRoot `
                -SchedulingTimingPath $schedulingTimingPath -MaxParallel 1 `
                -QualityGateRunId 'qgr-runner-fixture' -QualityGateSourceFingerprintJson $sourceJson 2>&1)

        $LASTEXITCODE | Should Be 0
        Test-Path -LiteralPath $timingPath -PathType Leaf | Should Be $true
        $timing = Get-Content -LiteralPath $timingPath -Raw | ConvertFrom-Json
        $timing.schema_version | Should Be 3
        $timing.quality_gate_run_id | Should Be 'qgr-runner-fixture'
        (Get-QualityGateSourceBindingSha256 $timing.quality_gate_source_start) | Should Be (Get-QualityGateSourceBindingSha256 $source)
        $timing.scheduling.strategy | Should Be 'historical_lpt'
        $timing.scheduling.source_status | Should Be 'loaded'
        ($output -join "`n") | Should Match 'Tests Passed: 2, Failed: 0'
    }

    It 'rejects unsafe or contradictory passed receipts before publishing current.json' {
        $fixture = New-QualityGateIntegrityFixture 'writer-fail-closed'
        $source = Get-QualityGateSourceFingerprint -RepoRoot $fixture.root

        { Write-QualityGateImmutableReceipt -ReceiptRoot $fixture.receipt_root -RunId 'qgr-contradictory' -Profile quick -Status passed -SourceStart $source -SourceEnd $source -GateResults @([pscustomobject]@{ name='tests'; passed=$false; elapsed_ms=1 }) } | Should Throw
        (Test-Path -LiteralPath (Join-Path $fixture.receipt_root 'current.json')) | Should Be $false

        [IO.File]::WriteAllText((Join-Path $fixture.root 'tracked.txt'), 'drift', [Text.UTF8Encoding]::new($false))
        $drifted = Get-QualityGateSourceFingerprint -RepoRoot $fixture.root
        { Write-QualityGateImmutableReceipt -ReceiptRoot $fixture.receipt_root -RunId 'qgr-source-drift-as-pass' -Profile quick -Status passed -SourceStart $source -SourceEnd $drifted -GateResults @([pscustomobject]@{ name='build'; passed=$true; elapsed_ms=1 }) } | Should Throw
        { Write-QualityGateImmutableReceipt -ReceiptRoot $fixture.receipt_root -RunId '..\escape' -Profile quick -Status failed -SourceStart $drifted -SourceEnd $drifted -GateResults @([pscustomobject]@{ name='build'; passed=$false; elapsed_ms=1 }) } | Should Throw
        (Test-Path -LiteralPath (Join-Path $fixture.receipt_root 'current.json')) | Should Be $false
    }

    It 'rejects a passed receipt with a truncated gate roster' {
        $fixture = New-QualityGateIntegrityFixture 'truncated-roster'
        $source = Get-QualityGateSourceFingerprint -RepoRoot $fixture.root

        { Write-QualityGateImmutableReceipt -ReceiptRoot $fixture.receipt_root -RunId 'qgr-truncated' -Profile quick -Status passed -SourceStart $source -SourceEnd $source -GateResults @([pscustomobject]@{ name='build'; passed=$true; elapsed_ms=1 }) } | Should Throw
        (Test-Path -LiteralPath (Join-Path $fixture.receipt_root 'current.json')) | Should Be $false
    }

    It 'rejects a rehashed current receipt whose passed status contradicts its gate rows' {
        $fixture = New-QualityGateIntegrityFixture 'current-rehashed-contradiction'
        $runId = 'qgr-rehashed-contradiction'
        $source = Get-QualityGateSourceFingerprint -RepoRoot $fixture.root
        Write-QualityGateTimingFixture $fixture $runId $source
        $written = Write-QualityGateImmutableReceipt -ReceiptRoot $fixture.receipt_root -RunId $runId -Profile full -Status passed -SourceStart $source -SourceEnd $source -GateResults (New-QualityGateRows full) -TimingReportPath $fixture.timing_path

        $receipt = Get-Content -LiteralPath $written.receipt_path -Raw | ConvertFrom-Json
        $receipt.gates[0].passed = $false
        [IO.File]::WriteAllText($written.receipt_path, ($receipt | ConvertTo-Json -Depth 40), [Text.UTF8Encoding]::new($false))
        $pointer = Get-Content -LiteralPath $written.pointer_path -Raw | ConvertFrom-Json
        $pointer.receipt_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $written.receipt_path).Hash.ToLowerInvariant()
        [IO.File]::WriteAllText($written.pointer_path, ($pointer | ConvertTo-Json -Depth 40), [Text.UTF8Encoding]::new($false))

        $result = Test-QualityGateCurrentReceipt -ReceiptRoot $fixture.receipt_root -RepoRoot $fixture.root -RequiredProfile full -RequiredStatus passed

        $result.pass | Should Be $false
        @($result.findings.code) | Should Contain 'quality_gate_receipt_semantics_invalid'
    }

    It 'binds current full receipt to timing and source, then detects timing tamper and later source drift' {
        $fixture = New-QualityGateIntegrityFixture 'current-validator'
        $runId = 'qgr-fixture'
        $source = Get-QualityGateSourceFingerprint -RepoRoot $fixture.root
        Write-QualityGateTimingFixture $fixture $runId $source
        $timingBytes = [IO.File]::ReadAllBytes($fixture.timing_path)
        $written = Write-QualityGateImmutableReceipt -ReceiptRoot $fixture.receipt_root -RunId $runId -Profile full -Status passed -SourceStart $source -SourceEnd $source -GateResults (New-QualityGateRows full) -TimingReportPath $fixture.timing_path

        $valid = Test-QualityGateCurrentReceipt -ReceiptRoot $fixture.receipt_root -RepoRoot $fixture.root -RequiredProfile full -RequiredStatus passed
        $valid.pass | Should Be $true
        $valid.code | Should Be 'quality_gate_current_valid'
        $written.receipt.test_timing.run_id | Should Be $runId
        $written.receipt.test_timing.sha256 | Should Be ((Get-FileHash -Algorithm SHA256 -LiteralPath $fixture.timing_path).Hash.ToLowerInvariant())

        [IO.File]::WriteAllText($fixture.timing_path, '{}', [Text.UTF8Encoding]::new($false))
        $tampered = Test-QualityGateCurrentReceipt -ReceiptRoot $fixture.receipt_root -RepoRoot $fixture.root -RequiredProfile full -RequiredStatus passed
        $tampered.pass | Should Be $false
        @($tampered.findings.code) | Should Contain 'quality_gate_timing_hash_mismatch'

        [IO.File]::WriteAllBytes($fixture.timing_path, $timingBytes)
        [IO.File]::WriteAllText((Join-Path $fixture.root 'tracked.txt'), 'after-full', [Text.UTF8Encoding]::new($false))
        $stale = Test-QualityGateCurrentReceipt -ReceiptRoot $fixture.receipt_root -RepoRoot $fixture.root -RequiredProfile full -RequiredStatus passed
        $stale.pass | Should Be $false
        @($stale.findings.code) | Should Contain 'quality_gate_current_source_stale'
    }

    It 'ignores Git conversion warnings when tracked file content is unchanged' {
        $fixture = New-QualityGateIntegrityFixture 'stderr-warning-fingerprint'
        & git -C $fixture.root config core.autocrlf true
        $trackedPath = Join-Path $fixture.root 'tracked.txt'
        [IO.File]::WriteAllText($trackedPath, "fixture`n", [Text.UTF8Encoding]::new($false))
        & git -C $fixture.root add tracked.txt
        & git -C $fixture.root commit -qm 'normalize fixture'
        [IO.File]::WriteAllText($trackedPath, "fixture`r`n", [Text.UTF8Encoding]::new($false))
        & git -C $fixture.root update-index --refresh
        $cleanGitOutput = @(& git -C $fixture.root diff --binary --no-ext-diff --no-color --no-renames HEAD -- 2>&1)
        $start = Get-QualityGateSourceFingerprint -RepoRoot $fixture.root

        Start-Sleep -Milliseconds 1100
        [IO.File]::WriteAllText($trackedPath, "fixture`n", [Text.UTF8Encoding]::new($false))
        $indexBlob = ([string](& git -C $fixture.root ls-files -s -- tracked.txt)).Split()[1]
        $worktreeBlob = [string](& git -C $fixture.root hash-object -- tracked.txt)
        $end = Get-QualityGateSourceFingerprint -RepoRoot $fixture.root

        ($cleanGitOutput -join "`n") | Should Not Match 'will be replaced by CRLF'
        $worktreeBlob | Should Be $indexBlob
        (Compare-QualityGateSourceFingerprint -Start $start -End $end).pass | Should Be $true
    }

    It 'retries bounded transient index lock contention when capturing a source fingerprint' {
        $fixture = New-QualityGateIntegrityFixture 'transient-index-lock'
        $lockPath = Join-Path $fixture.root '.git\index.lock'
        [IO.File]::WriteAllText($lockPath, 'fixture lock', [Text.UTF8Encoding]::new($false))
        $escapedLockPath = $lockPath.Replace("'", "''")
        $releaseScript = "Start-Sleep -Milliseconds 350; Remove-Item -LiteralPath '$escapedLockPath' -Force"
        $encodedReleaseScript = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($releaseScript))
        $releaseProcess = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-EncodedCommand', $encodedReleaseScript) -PassThru -WindowStyle Hidden

        try {
            $fingerprint = Get-QualityGateSourceFingerprint -RepoRoot $fixture.root
            $fingerprint.index_fingerprint | Should Not BeNullOrEmpty
        }
        finally {
            $releaseProcess.WaitForExit(5000) | Out-Null
            $releaseProcess.Dispose()
            Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
        }
    }
}
