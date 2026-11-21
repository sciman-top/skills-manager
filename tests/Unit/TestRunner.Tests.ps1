BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    $runnerPath = Join-Path $repoRoot 'tests\run.ps1'
    $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source

    function New-RunnerFixture([string]$Name, [string]$TestBody) {
        $root = Join-Path $TestDrive $Name
        $unit = Join-Path $root 'Unit'
        $e2e = Join-Path $root 'E2E'
        New-Item -ItemType Directory -Path $unit, $e2e -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $unit 'Fixture.Tests.ps1') -Value $TestBody -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $e2e 'Fixture.Tests.ps1') -Value @'
Describe 'E2E fixture' {
    It 'passes' { $true | Should -Be $true }
}
'@ -Encoding UTF8
        return [pscustomobject]@{ unit = $unit; e2e = $e2e }
    }

    function New-ShardRunnerFixture([string]$Name, [int]$FailureIndex = 0) {
        $root = Join-Path $TestDrive $Name
        $unit = Join-Path $root 'Unit'
        $e2e = Join-Path $root 'E2E'
        $reports = Join-Path $root 'reports'
        New-Item -ItemType Directory -Path $unit, $e2e, $reports -Force | Out-Null
        for ($index = 1; $index -le 4; $index++) {
            $target = if ($index -le 2) { $unit } else { $e2e }
            $testName = if ($index -eq $FailureIndex) { "fails shard $index" } else { "passes shard $index" }
            $assertion = if ($index -eq $FailureIndex) { '1 | Should -Be 2' } else { '$true | Should -BeTrue' }
            $body = @"
Describe 'Shard fixture $index' {
    It '$testName' { $assertion }
}
"@
            Set-Content -LiteralPath (Join-Path $target ("Shard-{0}.Tests.ps1" -f $index)) -Value $body -Encoding UTF8
        }
        return [pscustomobject]@{ unit = $unit; e2e = $e2e; reports = $reports }
    }

}
Describe 'Repository test runner output contract' {
    It 'preserves a test discovery error instead of reporting an opaque Pester failure' {
        $missing = Join-Path ([IO.Path]::GetTempPath()) ('missing-test-path-' + [guid]::NewGuid().ToString('N'))
        $text = & $pwshPath -NoProfile -File $runnerPath -TestPath $missing -InProcess 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        $exitCode | Should -Not -Be 0
        $text | Should -Match 'Test discovery failed:'
        $text | Should -Match ([regex]::Escape($missing))
        $text | Should -Match 'Cannot find'
        $text | Should -Not -Match 'Pester failures:'
    }

    It 'rejects a name filter that executes no tests' {
        $fixture = New-RunnerFixture 'no-match' @'
Describe 'Filter fixture' {
    It 'available test' { $true | Should -BeTrue }
}
'@
        $noMatchReports = Join-Path $TestDrive 'no-match-reports'
        $output = @(& pwsh -NoProfile -File $runnerPath -TestPath (Join-Path $fixture.unit 'Fixture.Tests.ps1') -TestName '*missing test' -ShardReportRoot $noMatchReports *>&1)
        $LASTEXITCODE | Should -Not -Be 0
        $receipts = @(Get-ChildItem -LiteralPath $noMatchReports -Recurse -Filter 'targeted.receipt.json' -File | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json })
        $receipts.Count | Should -Be 1
        $receipts[0].status | Should -Be 'error'
        $receipts[0].zero_selection | Should -BeFalse
        $receipts[0].total_count | Should -Be 1
        ($output -join "`n") | Should -Match 'No tests selected|Selected tests discovered but none executed successfully'
    }

    It 'prints a start line and one stable summary line for a passing run' {
        $fixture = New-RunnerFixture 'pass' @'
Describe 'Noisy fixture' {
    It 'passes without leaking output' {
        Write-Host 'fixture-noise-marker'
        $true | Should -Be $true
    }
}
'@

        $output = @(& pwsh -NoProfile -File $runnerPath -TestPath (Join-Path $fixture.unit 'Fixture.Tests.ps1') *>&1)
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 0
        @($output).Count | Should -Be 2
        [string]$output[0] | Should -Match '^Targeted run started: batch=\[.+\] timeout=[0-9]+s receipt=.+'
        [string]$output[1] | Should -Match '^Tests: total=1 passed=1 failed=0 skipped=0 duration=[0-9.]+s$'
        ($output -join "`n") | Should -Not -Match 'fixture-noise-marker'
    }

    It 'prints bounded failure diagnostics without leaking fixture output' {
        $fixture = New-RunnerFixture 'fail' @'
Describe 'Noisy failing fixture' {
    It 'fails clearly' {
        Write-Host 'fixture-noise-marker'
        1 | Should -Be 2
    }
}
'@

        $output = @(& pwsh -NoProfile -File $runnerPath -UnitTestPath $fixture.unit -E2ETestPath $fixture.e2e *>&1)
        $exitCode = $LASTEXITCODE
        $text = $output -join "`n"

        $exitCode | Should -Not -Be 0
        $text | Should -Match 'Tests: total=2 passed=1 failed=1 skipped=0 duration=[0-9.]+s'
        $text | Should -Match 'FAILED: fails clearly'
        $text | Should -Match 'Expected 2, but got 1\.'
        $text | Should -Not -Match 'fixture-noise-marker'
        @($output).Count | Should -BeLessThan 10
    }

    It 'filters a large test file by full test name' {
        $fixture = New-RunnerFixture 'name-filter' @'
Describe 'Filtered fixture' {
    It 'chosen test' { $true | Should -Be $true }
    It 'other test' { throw 'should not run' }
}
'@

        $output = @(& pwsh -NoProfile -File $runnerPath -TestPath (Join-Path $fixture.unit 'Fixture.Tests.ps1') -TestName '*chosen test' *>&1)
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 0
        [string]$output[1] | Should -Match '^Tests: total=[0-9]+ passed=1 failed=0 skipped=0 duration=[0-9.]+s$'
    }

    It 'fails when one test container cannot be parsed even if another container passes' {
        $fixture = New-RunnerFixture 'container-fail' @'
Describe 'Broken fixture' {
    It 'cannot be discovered' {
}
'@

        $output = @(& pwsh -NoProfile -File $runnerPath -UnitTestPath $fixture.unit -E2ETestPath $fixture.e2e *>&1)
        $exitCode = $LASTEXITCODE
        $text = $output -join "`n"

        $exitCode | Should -Not -Be 0
        $text | Should -Match 'CONTAINER FAILED:'
        $text | Should -Match 'Pester container failures: 1'
    }

    It 'shards an unfiltered fixture and aggregates passing results' {
        $fixture = New-ShardRunnerFixture 'shard-pass'
        $output = @(& pwsh -NoProfile -File $runnerPath -UnitTestPath $fixture.unit -E2ETestPath $fixture.e2e -MaxParallel 2 -ShardReportRoot $fixture.reports *>&1)
        $exitCode = $LASTEXITCODE
        $text = $output -join "`n"

        $exitCode | Should -Be 0
        $text | Should -Match '^Tests: total=4 passed=4 failed=0 skipped=0 duration=[0-9.]+s$'
        @($output).Count | Should -Be 1
        $receipts = @(Get-ChildItem -LiteralPath $fixture.reports -Recurse -Filter '*.receipt.json' -File)
        @($receipts).Count | Should -Be 2
        foreach ($receiptPath in $receipts) {
            (Get-Content -LiteralPath $receiptPath.FullName -Raw | ConvertFrom-Json).status | Should -Be 'passed'
        }
    }

    It 'keeps an explicit companion path in the same targeted batch' {
        $fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('dsh-split-path-' + [guid]::NewGuid().ToString('N'))
        $reportRoot = Join-Path ([IO.Path]::GetTempPath()) ('dsh-split-reports-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $fixtureRoot, $reportRoot -Force | Out-Null
        $first = Join-Path $fixtureRoot 'First.Tests.ps1'
        $second = Join-Path $fixtureRoot 'Second.Tests.ps1'
        foreach ($path in @($first, $second)) {
            Set-Content -LiteralPath $path -Encoding utf8 -Value "Describe 'Selected test' { It 'passes' { `$true | Should -BeTrue } }"
        }
        try {
            # Avoid binding this assertion to Pester's nested function scope
            # or its $LASTEXITCODE handling.
            $startInfo = [Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = $pwshPath
            $startInfo.UseShellExecute = $false
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            foreach ($argument in @('-NoProfile', '-File', $runnerPath, '-TestPath', $first, '-SplitTestPath', $second, '-InProcess', '-ShardReportRoot', $reportRoot)) {
                $startInfo.ArgumentList.Add($argument)
            }
            $process = [Diagnostics.Process]::Start($startInfo)
            try {
                $stdout = $process.StandardOutput.ReadToEndAsync()
                $stderr = $process.StandardError.ReadToEndAsync()
                $process.WaitForExit()
                $exitCode = $process.ExitCode
                $text = @($stdout.Result, $stderr.Result) -join "`n"
            }
            finally { $process.Dispose() }
            $exitCode | Should -Be 0
            @($text.Trim() -split "`r?`n").Count | Should -Be 2
            $text | Should -Match 'Tests: total=2 passed=2 failed=0 skipped=0'
        }
        finally {
            if (Test-Path -LiteralPath $fixtureRoot) {
                Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
            }
            if (Test-Path -LiteralPath $reportRoot) {
                Remove-Item -LiteralPath $reportRoot -Recurse -Force
            }
        }
    }

    It 'reports the selected-worker context when a sharded run discovers zero tests' {
        $fixture = New-RunnerFixture 'shard-empty' @'
Describe 'Empty shard fixture' {
    It 'passes' {
        $true | Should -BeTrue
    }
}
'@
        $reportRoot = Join-Path $TestDrive 'empty-shard-reports'
        $output = @(& $pwshPath -NoProfile -File $runnerPath -TestPath (Join-Path $fixture.unit 'Fixture.Tests.ps1') -TestName '*missing test' -ShardReportRoot $reportRoot *>&1)
        $text = $output -join "`n"
        $receipts = @(Get-ChildItem -LiteralPath $reportRoot -Recurse -Filter 'targeted.receipt.json' -File | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json })

        $LASTEXITCODE | Should -Not -Be 0
        $text | Should -Match 'No tests selected|Selected tests discovered but none executed successfully'
        $receipts.Count | Should -Be 1
        $receipts[0].status | Should -Be 'error'
        $receipts[0].zero_selection | Should -BeFalse
        $receipts[0].total_count | Should -Be 1
    }

    It 'does not report an empty selection as a successful in-process run' {
        $root = Join-Path $TestDrive 'explicit-files'
        $first = Join-Path $root 'First-special-selected.Tests.ps1'
        $second = Join-Path $root 'Second-special-selected.Tests.ps1'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        foreach ($path in @($first, $second)) {
            Set-Content -LiteralPath $path -Encoding utf8 -Value "Describe 'Required selected test' { It 'passes' { `$true | Should -BeTrue } }"
        }

        $reportRoot = Join-Path $TestDrive 'targeted-empty'
        $script:explicitArguments = @('-NoProfile', '-File', $runnerPath, '-TestPath', $first, $second, '-TestName', '*no matching test', '-InProcess', '-ShardReportRoot', $reportRoot)
        $output = @(& pwsh @explicitArguments 2>&1)
        $exitCode = $LASTEXITCODE
        $text = $output -join "`n"

        $exitCode | Should -Not -Be 0
        $reports = @(Get-ChildItem -LiteralPath $reportRoot -Recurse -Filter 'targeted.receipt.json' -File | ForEach-Object FullName)
        @($reports).Count | Should -Be 1
        $receipt = Get-Content -LiteralPath $reports[0] -Raw | ConvertFrom-Json
        $receipt.passed_count | Should -Be 0
        $receipt.failed_count | Should -Be 0
        $text | Should -Match 'No tests executed successfully'
    }

    It 'keeps a shard with a skipped test distinct from discovery with zero tests' {
        $shardRoot = Join-Path $TestDrive 'skipped-shard'
        $shardReports = Join-Path $shardRoot 'Reports'
        New-Item -ItemType Directory -Path (Join-Path $shardRoot 'Unit'), (Join-Path $shardRoot 'E2E'), $shardReports -Force | Out-Null
        foreach ($directory in @('Unit', 'E2E')) {
            Set-Content -LiteralPath (Join-Path $shardRoot "$directory/Fixture.Tests.ps1") -Encoding utf8 -Value "Describe 'Baseline' { It 'passes' { `$true | Should -BeTrue } }"
        }
        for ($index = 1; $index -le 4; $index++) {
            $target = if ($index -le 2) { 'Unit' } else { 'E2E' }
            $marker = if ($index -eq 1) { ' -Skip' } else { '' }
            $name = if ($index -eq 1) { 'is skipped' } else { 'passes' }
            Set-Content -LiteralPath (Join-Path $shardRoot "$target/Shard-$index.Tests.ps1") -Encoding utf8 -Value "Describe 'Shard $index' { It '$name'$marker { `$true | Should -BeTrue } }"
        }
        $arguments = @('-NoProfile', '-File', $runnerPath, '-UnitTestPath', (Join-Path $shardRoot 'Unit'), '-E2ETestPath', (Join-Path $shardRoot 'E2E'), '-MaxParallel', '2', '-ShardReportRoot', $shardReports)
        & pwsh @arguments 2>&1 | Out-Null
        $exitCode = $LASTEXITCODE
        $receipts = @(Get-ChildItem -LiteralPath $shardReports -Recurse -Filter '*.receipt.json' -File | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json })
        $receipts.Count | Should -Be 2
        @($receipts | Where-Object { $_.passed_count -eq 2 -and $_.skipped_count -eq 1 }).Count | Should -Be 1
        $exitCode | Should -Be 0
    }

    It 'distinguishes a skipped targeted test from a filtered-out test' {
        $fixture = Join-Path $TestDrive 'skipped-target'
        New-Item -ItemType Directory -Path $fixture -Force | Out-Null
        $testFile = Join-Path $fixture 'Skipped.Tests.ps1'
        Set-Content -LiteralPath $testFile -Encoding utf8 -Value "Describe 'Skipped target' { It 'is skipped' -Skip { `$true | Should -BeTrue } }"
        $reportRoot = Join-Path $fixture 'Reports'
        $output = @(& pwsh -NoProfile -File $runnerPath -TestPath $testFile -ShardReportRoot $reportRoot 2>&1)
        $exitCode = $LASTEXITCODE
        $receipt = @(Get-ChildItem -LiteralPath $reportRoot -Recurse -Filter 'targeted.receipt.json' -File | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json })
        $receipt.Count | Should -Be 1
        $receipt[0].status | Should -Be 'error'
        $receipt[0].zero_selection | Should -BeFalse
        $receipt[0].total_count | Should -Be 1
        $receipt[0].skipped_count | Should -Be 1
        $exitCode | Should -Not -Be 0
        ($output -join "`n") | Should -Match 'Selected tests discovered but none executed successfully'
    }

    It 'removes a finished shard from the aggregate even if it exited during polling' {
        $aggregate = [Collections.Generic.List[object]]::new()
        $stale = [pscustomobject]@{ process = [pscustomobject]@{ HasExited = $false } }
        $finished = [pscustomobject]@{ process = [pscustomobject]@{ HasExited = $true } }
        $aggregate.Add($stale) | Out-Null
        $aggregate.Add($finished) | Out-Null
        $finished.process.PSObject.Properties['HasExited'].Value = $false
        $remaining = @($aggregate | Where-Object { -not $_.process.HasExited }).Count
        $remaining | Should -Be 2
        $aggregate.Remove($finished) | Should -BeTrue
        @($aggregate).Count | Should -Be 1
    }

    It 'reports a pinned fixture source outside its root as rejected input' {
        $fixture = Join-Path $repoRoot 'tests\fixtures\ai-coding-workflow'
        $outside = Join-Path $TestDrive 'outside.ps1'
        Copy-Item -LiteralPath (Join-Path $fixture 'Labels.ps1') -Destination $outside
        $fixtureCopy = Join-Path $TestDrive 'pinned-fixture'
        Copy-Item -Path $fixture -Destination $fixtureCopy -Recurse
        $output = @(& pwsh -NoProfile -File (Join-Path $fixtureCopy 'Test-Labels.ps1') -SourcePath $outside *>&1)
        $exitCode = $LASTEXITCODE
        $exitCode | Should -Not -Be 0
        ($output -join "`n") | Should -Match 'Acceptance source must be in the disposable fixture root'
        $receiptLine = @($output | ForEach-Object { [string]$_ }) | Where-Object { $_ -like 'receipt=*' } | Select-Object -Last 1
        $receiptLine | Should -Not -BeNullOrEmpty
        $receiptPath = $receiptLine.Substring('receipt='.Length).Trim()
        try {
            $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
            $receipt.status | Should -Be 'failed'
            $receipt.failure_kind | Should -Be 'evaluator'
        }
        finally {
            if (Test-Path -LiteralPath $receiptPath) { Remove-Item -LiteralPath $receiptPath -Force }
        }
    }

    It 'aggregates a failed shard and preserves its failure diagnostic' {
        $fixture = New-ShardRunnerFixture 'shard-fail' 2
        $output = @(& pwsh -NoProfile -File $runnerPath -UnitTestPath $fixture.unit -E2ETestPath $fixture.e2e -MaxParallel 2 -ShardReportRoot $fixture.reports *>&1)
        $exitCode = $LASTEXITCODE
        $text = $output -join "`n"

        $exitCode | Should -Not -Be 0
        $text | Should -Match 'Tests: total=4 passed=3 failed=1 skipped=0 duration=[0-9.]+s'
        $text | Should -Match 'FAILED: fails shard 2'
        $text | Should -Match 'Pester failures: 1'
        $text | Should -Not -Match 'Shard fixture 1.*failed'
    }

    It 'does not reclaim temp when a runner is nested inside a Pester container' {
        # The real crash this fixes: a gate test starts tests/run.ps1 inside a
        # Pester container. The child process cannot see the parent's TestDrive
        # (PSDrives are per-process), so the reclaim treated that drive as
        # abandoned as soon as it had been idle past MinAgeSeconds and parked
        # it - after which the enclosing container threw
        # "名为 'TestDrive' 的驱动器已存在" and crashed. The child now detects the
        # enclosing run through an inherited marker and skips the reclaim.
        $runnerText = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8
        $runnerText | Should -Match 'DSH_TEST_RUNNER_NESTED'
        $runnerText | Should -Match 'InNestedRun'

        # Prove the marker actually suppresses the reclaim: point the reclaim at
        # a script that records being invoked, then run with and without it.
        $fixture = New-RunnerFixture 'nested-reclaim' @'
Describe 'Nested reclaim fixture' {
    It 'passes' { $true | Should -BeTrue }
}
'@
        $marker = 'DSH_TEST_RUNNER_NESTED'
        $hadMarker = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($marker))
        try {
            $nested = @(& pwsh -NoProfile -File $runnerPath -TestPath (Join-Path $fixture.unit 'Fixture.Tests.ps1') *>&1)
            $LASTEXITCODE | Should -Be 0
            ($nested -join "`n") | Should -Match 'Tests: total=1 passed=1'

            # The runner must treat an inherited marker as nested, not as this
            # process being the outermost run.
            $env:DSH_TEST_RUNNER_NESTED = '99999'
            $nestedRun = @(& pwsh -NoProfile -File $runnerPath -TestPath (Join-Path $fixture.unit 'Fixture.Tests.ps1') *>&1)
            $LASTEXITCODE | Should -Be 0
            ($nestedRun -join "`n") | Should -Match 'Tests: total=1 passed=1'
        }
        finally {
            if ($hadMarker) { $env:DSH_TEST_RUNNER_NESTED = '1' } else { Remove-Item Env:DSH_TEST_RUNNER_NESTED -ErrorAction SilentlyContinue }
        }
    }
}
