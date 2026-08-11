Describe "Quality gate scripts" {
    It "parses the complete generated bundle before replacing skills.ps1" {
        $root = Join-Path $PSScriptRoot "..\.."
        $build = Get-Content -LiteralPath (Join-Path $root 'build.ps1') -Raw

        $build | Should Match 'Parser\]::ParseInput'
        $build | Should Match 'bundle_parse_failed'
        $build.IndexOf('Parser]::ParseInput') | Should BeLessThan $build.IndexOf('WriteAllBytes')
    }

    It "exposes a standalone current full receipt verifier for post-commit closeout" {
        $root = Join-Path $PSScriptRoot "..\.."
        $verifierPath = Join-Path $root 'scripts\quality\verify-current-quality-gate.ps1'

        Test-Path -LiteralPath $verifierPath -PathType Leaf | Should Be $true
        if (Test-Path -LiteralPath $verifierPath -PathType Leaf) {
            $verifier = Get-Content -LiteralPath $verifierPath -Raw
            $verifier | Should Match 'Test-QualityGateCurrentReceipt'
            $verifier | Should Match 'RequiredProfile'
            $verifier | Should Match 'RequiredStatus'
        }
    }

    It "reuses only an exact current full receipt unless a fresh run is forced" {
        $root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
        $integrityPath = Join-Path $root 'scripts\quality\QualityGateIntegrity.ps1'
        . $integrityPath

        $fixtureRoot = Join-Path $TestDrive 'quality-gate-reuse-current'
        $qualityRoot = Join-Path $fixtureRoot 'scripts\quality'
        New-Item -ItemType Directory -Path $qualityRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'scripts\quality\run-local-quality-gates.ps1') -Destination $qualityRoot
        Copy-Item -LiteralPath $integrityPath -Destination $qualityRoot
        Set-Content -LiteralPath (Join-Path $fixtureRoot '.gitignore') -Value 'reports/' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'build.ps1') -Encoding UTF8 -Value @'
$marker = Join-Path $PSScriptRoot 'reports\forced-fresh-build.marker'
New-Item -ItemType Directory -Path (Split-Path -Parent $marker) -Force | Out-Null
Set-Content -LiteralPath $marker -Value 'executed' -Encoding UTF8
'@

        git -C $fixtureRoot init -q
        git -C $fixtureRoot config user.email 'quality-gate@example.invalid'
        git -C $fixtureRoot config user.name 'Quality Gate Test'
        git -C $fixtureRoot add .
        git -C $fixtureRoot commit -qm 'fixture'

        $runId = 'qgr-reuse-fixture'
        $source = Get-QualityGateSourceFingerprint -RepoRoot $fixtureRoot
        $timingPath = Join-Path $fixtureRoot ('reports\test-timings\{0}.json' -f $runId)
        New-Item -ItemType Directory -Path (Split-Path -Parent $timingPath) -Force | Out-Null
        [IO.File]::WriteAllText($timingPath, ([ordered]@{
                    schema_version = 3
                    quality_gate_run_id = $runId
                    quality_gate_source_start = $source
                } | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
        $receiptRoot = Join-Path $fixtureRoot 'reports\quality-gates'
        $written = Write-QualityGateImmutableReceipt -ReceiptRoot $receiptRoot -RunId $runId -Profile full -Status passed `
            -SourceStart $source -SourceEnd $source -GateResults @([pscustomobject]@{ name = 'fixture'; passed = $true; elapsed_ms = 1 }) `
            -TimingReportPath $timingPath
        $runner = Join-Path $qualityRoot 'run-local-quality-gates.ps1'
        $markerPath = Join-Path $fixtureRoot 'reports\forced-fresh-build.marker'

        $reuseOutput = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $runner -Profile full -ReuseCurrentReceipt 2>&1)
        $reuseExit = $LASTEXITCODE

        $reuseExit | Should Be 0
        ($reuseOutput -join "`n") | Should Match 'quality_gate_receipt_reused='
        ($reuseOutput -join "`n") | Should Match $runId
        Test-Path -LiteralPath $markerPath | Should Be $false
        (Get-Content -LiteralPath (Join-Path $receiptRoot 'current.json') -Raw | ConvertFrom-Json).run_id | Should Be $runId

        $dirtyMismatchOutput = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $runner -Profile full -ReuseCurrentReceipt -AllowDirtyWorktree 2>&1)
        $dirtyMismatchExit = $LASTEXITCODE

        $dirtyMismatchExit | Should Not Be 0
        ($dirtyMismatchOutput -join "`n") | Should Match 'quality_gate_receipt_reuse_miss=quality_gate_allow_dirty_worktree_mismatch'
        Test-Path -LiteralPath $markerPath | Should Be $true

        Write-QualityGateJsonAtomic -Path (Join-Path $receiptRoot 'current.json') -Value $written.pointer
        Remove-Item -LiteralPath $markerPath -Force
        $freshOutput = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $runner -Profile full -ForceFresh 2>&1)
        $freshExit = $LASTEXITCODE

        $freshExit | Should Not Be 0
        ($freshOutput -join "`n") | Should Not Match 'quality_gate_receipt_reused='
        Test-Path -LiteralPath $markerPath | Should Be $true

        $conflictOutput = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $runner -Profile full -ReuseCurrentReceipt -ForceFresh 2>&1)
        $LASTEXITCODE | Should Not Be 0
        ($conflictOutput -join "`n") | Should Match 'mutually exclusive'
    }

    It "Keeps full-gate execution in build, test, then contract order with timings" {
        $root = Join-Path $PSScriptRoot "..\.."
        $scriptPath = Join-Path $root "scripts\quality\run-local-quality-gates.ps1"
        $raw = Get-Content -LiteralPath $scriptPath -Raw

        $buildIndex = $raw.IndexOf("Invoke-QualityGate 'build'")
        $testsIndex = $raw.IndexOf("Invoke-QualityGate 'tests'")
        $firstContractIndex = $raw.IndexOf("Invoke-QualityGate 'repo-hygiene'")
        $buildIndex -ge 0 | Should Be $true
        $testsIndex -gt $buildIndex | Should Be $true
        $firstContractIndex -gt $testsIndex | Should Be $true
        $raw | Should Match 'gate_elapsed_ms'
        $raw | Should Match 'total_elapsed_ms'
    }

    It "uses the general planning contract without a retired P6-specific gate" {
        $root = Join-Path $PSScriptRoot "..\.."
        $scriptPath = Join-Path $root "scripts\quality\run-local-quality-gates.ps1"
        $raw = Get-Content -LiteralPath $scriptPath -Raw

        $raw | Should Match "Invoke-QualityGate 'planning-contract'"
        $raw | Should Not Match "Invoke-QualityGate 'host-native-lifecycle-planning'"
        Test-Path -LiteralPath (Join-Path $root 'scripts\verify-host-native-skill-lifecycle-planning.ps1') | Should Be $false
        Test-Path -LiteralPath (Join-Path $root 'scripts\verify-lean-ai-delivery-planning.ps1') | Should Be $false
    }

    It "keeps successful metadata gate output concise while preserving the verifier" {
        $root = Join-Path $PSScriptRoot "..\.."
        $gate = Get-Content -LiteralPath (Join-Path $root 'scripts\quality\run-local-quality-gates.ps1') -Raw

        $gate | Should Match "Invoke-QualityGate 'native-skill-metadata'"
        $gate | Should Match "verify-native-skill-metadata\.ps1\s*}"
        $gate | Should Not Match "verify-native-skill-metadata\.ps1\s+-Json"
    }

    It "fails closed when tracked source drifts during a run and keeps an immutable receipt behind a pointer" {
        $root = Join-Path $PSScriptRoot "..\.."
        $integrityPath = Join-Path $root 'scripts\quality\QualityGateIntegrity.ps1'
        Test-Path -LiteralPath $integrityPath -PathType Leaf | Should Be $true
        . $integrityPath

        $fixtureRoot = Join-Path $TestDrive 'quality-gate-integrity-fixture'
        New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
        Push-Location $fixtureRoot
        try {
            git init -q
            git config user.email 'quality-gate@example.invalid'
            git config user.name 'Quality Gate Test'
            Set-Content -LiteralPath (Join-Path $fixtureRoot 'tracked.txt') -Value 'before' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $fixtureRoot '.gitignore') -Value 'reports/' -Encoding UTF8
            git add tracked.txt .gitignore
            git commit -qm 'fixture'

            $start = Get-QualityGateSourceFingerprint -RepoRoot $fixtureRoot
            Set-Content -LiteralPath (Join-Path $fixtureRoot 'tracked.txt') -Value 'during-run-drift' -Encoding UTF8
            $end = Get-QualityGateSourceFingerprint -RepoRoot $fixtureRoot
            $comparison = Compare-QualityGateSourceFingerprint -Start $start -End $end

            $comparison.pass | Should Be $false
            $comparison.code | Should Be 'quality_gate_source_drift'
            @($comparison.changed_fields) | Should Contain 'tracked_worktree_fingerprint'

            Set-Content -LiteralPath (Join-Path $fixtureRoot 'tracked.txt') -Value 'before' -Encoding UTF8
            $untrackedStart = Get-QualityGateSourceFingerprint -RepoRoot $fixtureRoot
            Set-Content -LiteralPath (Join-Path $fixtureRoot 'new-source.ps1') -Value '# new source' -Encoding UTF8
            $untrackedEnd = Get-QualityGateSourceFingerprint -RepoRoot $fixtureRoot
            $untrackedComparison = Compare-QualityGateSourceFingerprint -Start $untrackedStart -End $untrackedEnd
            $untrackedComparison.pass | Should Be $false
            @($untrackedComparison.changed_fields) | Should Contain 'untracked_worktree_fingerprint'

            $ignoredStart = Get-QualityGateSourceFingerprint -RepoRoot $fixtureRoot
            New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'reports') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $fixtureRoot 'reports\runtime.json') -Value '{}' -Encoding UTF8
            $ignoredEnd = Get-QualityGateSourceFingerprint -RepoRoot $fixtureRoot
            (Compare-QualityGateSourceFingerprint -Start $ignoredStart -End $ignoredEnd).pass | Should Be $true

            $receiptRoot = Join-Path $fixtureRoot 'reports\quality-gates'
            $written = Write-QualityGateImmutableReceipt -ReceiptRoot $receiptRoot -RunId 'qgr-fixture-001' -Profile 'full' -Status 'source_drift' -SourceStart $start -SourceEnd $end -GateResults @() -AllowDirtyWorktree $true
            Test-Path -LiteralPath $written.receipt_path -PathType Leaf | Should Be $true
            Test-Path -LiteralPath $written.pointer_path -PathType Leaf | Should Be $true
            $written.receipt_path | Should Not Be $written.pointer_path
            $pointer = Get-Content -LiteralPath $written.pointer_path -Raw | ConvertFrom-Json
            $pointer.receipt_path | Should Be $written.receipt_path
            $pointer.receipt_sha256 | Should Be ((Get-FileHash -Algorithm SHA256 -LiteralPath $written.receipt_path).Hash.ToLowerInvariant())
            $written.receipt.immutable | Should Be $true
            $written.receipt.allow_dirty_worktree | Should Be $true
            { Write-QualityGateImmutableReceipt -ReceiptRoot $receiptRoot -RunId 'qgr-fixture-001' -Profile 'full' -Status 'source_drift' -SourceStart $start -SourceEnd $end -GateResults @() -AllowDirtyWorktree $true } | Should Throw
        }
        finally {
            Pop-Location
        }
    }

    It "stops before the next gate when source drifts after a successful gate" {
        $root = Join-Path $PSScriptRoot "..\.."
        $fixtureRoot = Join-Path $TestDrive 'quality-gate-early-drift'
        $qualityRoot = Join-Path $fixtureRoot 'scripts\quality'
        New-Item -ItemType Directory -Path $qualityRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'scripts\quality\run-local-quality-gates.ps1') -Destination $qualityRoot
        Copy-Item -LiteralPath (Join-Path $root 'scripts\quality\QualityGateIntegrity.ps1') -Destination $qualityRoot
        Set-Content -LiteralPath (Join-Path $fixtureRoot '.gitignore') -Value 'reports/' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'tracked.txt') -Value 'before-build' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'build.ps1') -Value "Set-Content -LiteralPath (Join-Path `$PSScriptRoot 'tracked.txt') -Value 'after-build' -Encoding UTF8" -Encoding UTF8

        Push-Location $fixtureRoot
        try {
            git init -q
            git config user.email 'quality-gate@example.invalid'
            git config user.name 'Quality Gate Test'
            git add .
            git commit -qm 'fixture'

            $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File '.\scripts\quality\run-local-quality-gates.ps1' -Profile quick 2>&1)
            $exitCode = $LASTEXITCODE
            $pointer = Get-Content -LiteralPath (Join-Path $fixtureRoot 'reports\quality-gates\current.json') -Raw | ConvertFrom-Json
            $receipt = Get-Content -LiteralPath $pointer.receipt_path -Raw | ConvertFrom-Json

            $exitCode | Should Be 78
            $receipt.status | Should Be 'source_drift'
            @($receipt.gates).Count | Should Be 1
            $receipt.gates[0].name | Should Be 'build'
            ($output -join "`n") | Should Not Match '== repo-hygiene =='
        }
        finally {
            Pop-Location
        }
    }

    It "fails closed on workspace-to-lock commit drift during full gate" {
        $root = Join-Path $PSScriptRoot "..\.."
        $gate = Get-Content -LiteralPath (Join-Path $root 'scripts\quality\run-local-quality-gates.ps1') -Raw
        $main = Get-Content -LiteralPath (Join-Path $root 'src\Main.ps1') -Raw
        $config = Get-Content -LiteralPath (Join-Path $root 'src\Config.ps1') -Raw

        $gate | Should Match "Invoke-QualityGate 'workspace-lock-parity'"
        $gate | Should Match "skills\.ps1 verify-lock"
        $main | Should Match '"verify-lock"\s*\{\s*验证锁定\s*\}'
        $config | Should Match '(?m)^function 验证锁定\b'
        $config | Should Match 'Ensure-LockedState'
    }

    It "keeps closeout on one full-gate entry plus the explicit live Doctor probe" {
        $root = Join-Path $PSScriptRoot "..\.."
        $agents = Get-Content -LiteralPath (Join-Path $root 'AGENTS.md') -Raw
        $gateSection = [regex]::Match($agents, '(?s)## C\. 门禁、证据与回滚(?<body>.*?)(?:\r?\n## D\.|\z)').Groups['body'].Value

        $gateSection | Should Match 'run-local-quality-gates\.ps1 -Profile full'
        $gateSection | Should Match 'ReuseCurrentReceipt'
        $gateSection | Should Match 'ForceFresh'
        $gateSection | Should Match 'doctor --strict --threshold-ms 8000'
        $gateSection | Should Not Match 'tests/run\.ps1'
        $gateSection | Should Not Match 'verify-dependency-baseline\.py'
        $gateSection | Should Not Match 'verify-host-capability-matrix\.ps1'
        $gateSection | Should Not Match 'verify-vnext-planning\.ps1'
    }

    It "removes confirmed definition-only compatibility leftovers" {
        $root = Join-Path $PSScriptRoot "..\.."
        $sources = @(
            'src\Commands\AuditTargets.ps1',
            'src\Commands\Install.ps1',
            'src\Commands\Mcp.ps1'
        ) | ForEach-Object { Get-Content -LiteralPath (Join-Path $root $_) -Raw }
        $joined = $sources -join "`n"

        $joined | Should Not Match '(?m)^function Get-AuditKnownRunIds\b'
        $joined | Should Not Match '(?m)^function 单技能安装\b'
        $joined | Should Not Match '(?m)^function Get-McpServerNameSet\b'
        $joined | Should Not Match '(?m)^function Merge-McpConfigMaps\b'
    }

    It "separates dry-run presentation and apply selection from the audit apply coordinator" {
        $root = Join-Path $PSScriptRoot "..\.."
        $source = Get-Content -LiteralPath (Join-Path $root 'src\Commands\AuditTargets.Apply.ps1') -Raw

        $source | Should Match '(?m)^function Complete-AuditRecommendationsDryRun\b'
        $source | Should Match '(?m)^function Resolve-AuditApplySelections\b'
        $source | Should Match 'Complete-AuditRecommendationsDryRun\s+-Plan'
        $source | Should Match 'Resolve-AuditApplySelections\s+-Plan'
    }

    It "keeps full-suite output failure-focused and reports actionable timing profiles" {
        $root = Join-Path $PSScriptRoot "..\.."
        $runner = Get-Content -LiteralPath (Join-Path $root 'tests\run.ps1') -Raw
        $worker = Get-Content -LiteralPath (Join-Path $root 'tests\run-pester-test-file.ps1') -Raw

        ($runner + "`n" + $worker) | Should Match '-Show Failed,Summary'
        $runner | Should Match 'unit_elapsed_ms'
        $runner | Should Match 'e2e_elapsed_ms'
        $runner | Should Match 'test_suite_elapsed_ms'
        $runner | Should Match 'slow_test_file'
        $runner | Should Match 'slow_test_case'
        $runner | Should Match 'reports.test-timings.current.json'
        $runner | Should Match 'QualityGateRunId'
        $runner | Should Match 'QualityGateSourceFingerprintJson'
        $runner | Should Match 'quality_gate_source_start'
        $gate = Get-Content -LiteralPath (Join-Path $root 'scripts\quality\run-local-quality-gates.ps1') -Raw
        $gate | Should Match 'QualityGateRunId'
        $gate | Should Match 'TimingReportPath'
    }

    It "isolates test files in bounded workers with timeout logs and terminal receipts" {
        $root = Join-Path $PSScriptRoot "..\.."
        $runner = Get-Content -LiteralPath (Join-Path $root 'tests\run.ps1') -Raw
        $workerPath = Join-Path $root 'tests\run-pester-test-file.ps1'

        Test-Path -LiteralPath $workerPath | Should Be $true
        $runner | Should Match '\[int\]\$MaxParallel'
        $runner | Should Match '\[int\]\$TestFileTimeoutSeconds'
        $runner | Should Match '\[int\]\$TestFileTimeoutSeconds\s*=\s*180'
        $runner | Should Match 'Start-Process'
        $runner | Should Match '-NoNewWindow'
        $runner | Should Not Match '-WindowStyle\s+Hidden'
        $runner | Should Match 'test-shards'
        $runner | Should Match 'SerialTestFiles'
        $runner | Should Match '\[string\[\]\]\$SerialTestFiles\s*=\s*@\(''SelectionCancellation\.Tests\.ps1''\)'
        $runner | Should Not Match 'HostNativeSkillLifecyclePlanning\.Tests\.ps1'
        $runner | Should Not Match 'LeanAiDeliveryPlanning\.Tests\.ps1'
        $runner | Should Not Match '\$historicalDiagnosticTestFiles'
        $runner | Should Not Match 'WatchRuntimeArming\.Tests\.ps1'
        $runner | Should Match '\$orderedFiles'
        $runner | Should Match '\.Dispose\(\)'
        $runner | Should Match 'timed_out'
        $runner | Should Match 'receipt\.json'
        $runner | Should Not Match 'Invoke-Pester -Script \$UnitTestPath'

        if (Test-Path -LiteralPath $workerPath) {
            $worker = Get-Content -LiteralPath $workerPath -Raw
            $worker | Should Match 'Invoke-Pester'
            $worker | Should Match '-PassThru'
            $worker | Should Match 'receipt'
            $worker | Should Match 'TotalCount'
            $worker | Should Match 'FailedCount'
        }
    }

    It "times out the selection cancellation test through the bounded worker path" {
        $root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
        $runner = Join-Path $root 'tests\run.ps1'
        $unitRoot = Join-Path $TestDrive 'bounded-selection-unit'
        $e2eRoot = Join-Path $TestDrive 'bounded-selection-e2e'
        $shardRoot = Join-Path $TestDrive 'bounded-selection-shards'
        $stdoutPath = Join-Path $TestDrive 'bounded-selection.out.log'
        $stderrPath = Join-Path $TestDrive 'bounded-selection.err.log'
        New-Item -ItemType Directory -Path $unitRoot, $e2eRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $unitRoot 'SelectionCancellation.Tests.ps1') -Encoding UTF8 -Value @'
Describe 'hung selection cancellation fixture' {
    It 'does not complete' { Start-Sleep -Seconds 60 }
}
'@
        Set-Content -LiteralPath (Join-Path $e2eRoot 'Passing.Tests.ps1') -Encoding UTF8 -Value @'
Describe 'fixture e2e' {
    It 'passes' { $true | Should Be $true }
}
'@

        $process = Start-Process -FilePath 'pwsh' -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $runner),
            '-UnitTestPath', ('"{0}"' -f $unitRoot), '-E2ETestPath', ('"{0}"' -f $e2eRoot),
            '-TimingReportPath', ('"{0}"' -f (Join-Path $TestDrive 'bounded-selection-timing.json')),
            '-ShardReportRoot', ('"{0}"' -f $shardRoot), '-SchedulingTimingPath', ('"{0}"' -f (Join-Path $TestDrive 'missing-timing.json')),
            '-MaxParallel', '1', '-TestFileTimeoutSeconds', '1'
        ) -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $completed = $false
        $exitCode = $null
        try {
            $completed = $process.WaitForExit(30000)
            if ($completed) { $exitCode = $process.ExitCode }
        }
        finally {
            if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
            $process.Dispose()
        }

        $output = @(
            Get-Content -LiteralPath $stdoutPath -ErrorAction SilentlyContinue
            Get-Content -LiteralPath $stderrPath -ErrorAction SilentlyContinue
        ) -join "`n"
        $completed | Should Be $true
        $exitCode | Should Not Be 0
        $output | Should Match 'status=timed_out'
        $output | Should Match 'path=SelectionCancellation\.Tests\.ps1'
    }

    It "serializes one repository without blocking a different repository" {
        $root = Join-Path $PSScriptRoot "..\.."
        function New-GatePeerFixture([string]$Name, [switch]$WaitForRelease) {
            $fixtureRoot = Join-Path $TestDrive $Name
            $qualityRoot = Join-Path $fixtureRoot 'scripts\quality'
            New-Item -ItemType Directory -Path $qualityRoot -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $root 'scripts\quality\run-local-quality-gates.ps1') -Destination $qualityRoot
            Copy-Item -LiteralPath (Join-Path $root 'scripts\quality\QualityGateIntegrity.ps1') -Destination $qualityRoot
            Set-Content -LiteralPath (Join-Path $fixtureRoot '.gitignore') -Value 'reports/' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $fixtureRoot 'tracked.txt') -Value 'fixture' -Encoding UTF8
            $build = if ($WaitForRelease) {
                @'
$ready = Join-Path $PSScriptRoot 'reports\gate-ready.marker'
$release = Join-Path $PSScriptRoot 'reports\gate-release.marker'
New-Item -ItemType Directory -Path (Split-Path -Parent $ready) -Force | Out-Null
Set-Content -LiteralPath $ready -Value 'ready' -Encoding UTF8
$deadline = [DateTimeOffset]::UtcNow.AddSeconds(10)
while (-not (Test-Path -LiteralPath $release)) {
    if ([DateTimeOffset]::UtcNow -gt $deadline) { throw 'fixture release handshake timed out' }
    Start-Sleep -Milliseconds 20
}
'@
            }
            else { '$true | Out-Null' }
            Set-Content -LiteralPath (Join-Path $fixtureRoot 'build.ps1') -Value $build -Encoding UTF8
            git -C $fixtureRoot init -q
            git -C $fixtureRoot config user.email 'quality-gate@example.invalid'
            git -C $fixtureRoot config user.name 'Quality Gate Test'
            git -C $fixtureRoot add .
            git -C $fixtureRoot commit -qm 'fixture'
            return $fixtureRoot
        }

        $ownedRoot = New-GatePeerFixture 'quality-gate-owned' -WaitForRelease
        $otherRoot = New-GatePeerFixture 'quality-gate-other'
        $ownedRunner = Join-Path $ownedRoot 'scripts\quality\run-local-quality-gates.ps1'
        $readyPath = Join-Path $ownedRoot 'reports\gate-ready.marker'
        $releasePath = Join-Path $ownedRoot 'reports\gate-release.marker'
        $ownerOut = Join-Path $TestDrive 'owner.out.log'
        $ownerErr = Join-Path $TestDrive 'owner.err.log'
        $owner = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $ownedRunner), '-Profile', 'quick') -PassThru -WindowStyle Hidden -RedirectStandardOutput $ownerOut -RedirectStandardError $ownerErr
        try {
            $readyDeadline = [DateTimeOffset]::UtcNow.AddSeconds(10)
            while (-not (Test-Path -LiteralPath $readyPath)) {
                if ($owner.HasExited) { throw 'quality gate owner exited before acquiring the fixture mutex' }
                if ([DateTimeOffset]::UtcNow -gt $readyDeadline) { throw 'quality gate owner readiness timed out' }
                Start-Sleep -Milliseconds 20
            }
            $sameOutput = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $ownedRunner -Profile quick 2>&1)
            $sameExit = $LASTEXITCODE
            $otherOutput = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $otherRoot 'scripts\quality\run-local-quality-gates.ps1') -Profile quick 2>&1)
            $otherExit = $LASTEXITCODE

            $sameExit | Should Be 75
            ($sameOutput -join "`n") | Should Match 'quality_gate_peer_busy'
            $otherExit | Should Not Be 75
            ($otherOutput -join "`n") | Should Not Match 'quality_gate_peer_busy'
        }
        finally {
            New-Item -ItemType Directory -Path (Split-Path -Parent $releasePath) -Force | Out-Null
            Set-Content -LiteralPath $releasePath -Value 'release' -Encoding UTF8
            if (-not $owner.HasExited) { $owner.WaitForExit(10000) | Out-Null }
            $owner.Dispose()
        }
    }

    It "fails closed when either Pester stage discovers zero tests" {
        $root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
        $runner = Join-Path $root 'tests\run.ps1'
        $passingRoot = Join-Path $TestDrive 'runner-passing'
        $emptyRoot = Join-Path $TestDrive 'runner-empty'
        New-Item -ItemType Directory -Path $passingRoot, $emptyRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $passingRoot 'Passing.Tests.ps1') -Encoding UTF8 -Value @'
Describe 'fixture unit' {
    It 'passes' { $true | Should Be $true }
}
'@

        $cases = @(
            @{ name = 'unit'; unit = $emptyRoot; e2e = $passingRoot },
            @{ name = 'e2e'; unit = $passingRoot; e2e = $emptyRoot }
        )
        foreach ($case in $cases) {
            $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $runner -UnitTestPath $case.unit -E2ETestPath $case.e2e -TimingReportPath (Join-Path $TestDrive ("timings-{0}.json" -f $case.name)) 2>&1)

            $LASTEXITCODE | Should Not Be 0
            ($output -join "`n") | Should Match ("{0} test discovery returned zero tests" -f $case.name)
        }
    }

    It "reports sync_mcp performance as gate_na when no current sample is supplied" {
        $root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
        $checker = Join-Path $root 'scripts\quality\check-doctor-json.ps1'

        $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $checker -SyncMcpThresholdMs 12000 2>&1)

        $LASTEXITCODE | Should Be 0
        ($output -join "`n") | Should Match 'gate_na gate=sync_mcp-performance'
        ($output -join "`n") | Should Match 'reason=no_current_sample'
        ($output -join "`n") | Should Match 'recovery_condition=provide_current_sync_mcp_sample'
    }

    It "enforces the sync_mcp threshold when an explicit current sample is supplied" {
        $root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
        $checker = Join-Path $root 'scripts\quality\check-doctor-json.ps1'
        $samplePath = Join-Path $TestDrive 'current-sync-sample.json'
        @{ metric = 'sync_mcp'; last_ms = 13000; avg_ms = 10000 } |
            ConvertTo-Json | Set-Content -LiteralPath $samplePath -Encoding UTF8

        $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $checker -SyncMcpThresholdMs 12000 -CurrentSyncMcpSamplePath $samplePath 2>&1)

        $LASTEXITCODE | Should Not Be 0
        ($output -join "`n") | Should Match 'sync_mcp performance regression: last=13000ms avg=10000ms threshold=12000ms'
    }

    It "keeps clean-runner acceptance tests independent from host paths and materialized imports" {
        $root = Join-Path $PSScriptRoot '..\..'
        $phase1 = Get-Content -LiteralPath (Join-Path $root 'tests\Unit\Phase1Acceptance.Tests.ps1') -Raw
        $projection = Get-Content -LiteralPath (Join-Path $root 'tests\Unit\SkillProjection.Tests.ps1') -Raw

        $phase1 | Should Not Match '(?i)[A-Z]:\\CODE'
        $projection | Should Not Match 'Get-ChildItem[^\r\n]+Join-Path \$repoRoot ["'']imports["'']'
    }

    It "forbids tests from reading or writing User-scope environment variables" {
        $root = Join-Path $PSScriptRoot "..\.."
        $testSources = Get-ChildItem -LiteralPath (Join-Path $root 'tests') -Recurse -Filter '*.ps1' |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
        ($testSources -join "`n") | Should Not Match 'Environment\]::(?:Get|Set)EnvironmentVariable\([^\r\n]*["'']User["'']'
    }

    It "keeps fixture-heavy verifiers composable while retaining CLI exit behavior" {
        $root = Join-Path $PSScriptRoot "..\.."
        $contracts = @(
            @{ Script = 'scripts\verify-vnext-planning.ps1'; Test = 'tests\Unit\ProductPlanning.Tests.ps1' },
            @{ Script = 'scripts\verify-skill-integrity.ps1'; Test = 'tests\Unit\SkillIntegrityScript.Tests.ps1' },
            @{ Script = 'scripts\verify-skills-config.ps1'; Test = 'tests\Unit\ConfigSchema.Tests.ps1' }
        )

        foreach ($contract in $contracts) {
            $scriptText = Get-Content -LiteralPath (Join-Path $root $contract.Script) -Raw
            $testText = Get-Content -LiteralPath (Join-Path $root $contract.Test) -Raw
            $scriptText | Should Match '\[switch\]\$NoExit'
            $scriptText | Should Match 'if \(\$NoExit\)'
            $scriptText | Should Match 'exit \$exitCode'
            $testText | Should Match '-File'
            $testText | Should Match '-NoExit'
        }
    }

    It "uses deterministic offline Doctor JSON mode without weakening strict health checks" {
        $root = Join-Path $PSScriptRoot "..\.."
        $contractText = Get-Content -LiteralPath (Join-Path $root 'scripts\quality\check-doctor-json.ps1') -Raw
        $doctorText = Get-Content -LiteralPath (Join-Path $root 'src\Commands\Doctor.ps1') -Raw

        $contractText | Should Match '--offline-contract'
        $contractText | Should Match 'Invoke-Doctor'
        $contractText | Should Not Match '& pwsh'
        $doctorText | Should Match '--offline-contract 不能与 --strict 组合'
        $doctorText | Should Match 'Test-DoctorGitHubConnection'
    }

    It "keeps audit runtime receipts out of curated change evidence" {
        $root = Join-Path $PSScriptRoot "..\.."
        $bundleText = Get-Content -LiteralPath (Join-Path $root 'src\Commands\AuditTargets.Bundle.ps1') -Raw
        $applyText = Get-Content -LiteralPath (Join-Path $root 'src\Commands\AuditTargets.Apply.ps1') -Raw
        $hygieneText = Get-Content -LiteralPath (Join-Path $root 'scripts\quality\check-repo-hygiene.ps1') -Raw

        $bundleText | Should Match 'runtime-evidence-'
        $applyText | Should Match 'runtime-evidence-'
        $bundleText | Should Not Match 'Join-Path \$script:Root "docs\\change-evidence"'
        $applyText | Should Not Match 'Join-Path \$script:Root "docs\\change-evidence"'
        $hygieneText | Should Match '\^docs/change-evidence/\\d\{8\}-audit-runtime-'
        @(Get-ChildItem -LiteralPath (Join-Path $root 'docs\change-evidence') -File -Filter '*-audit-runtime-*.md').Count | Should Be 0
        Test-Path -LiteralPath (Join-Path $root 'docs\archive\change-evidence\README.md') | Should Be $true
    }

    It "keeps the retired routing verifier compatibility-only" {
        $root = Join-Path $PSScriptRoot "..\.."
        $routingVerifier = Get-Content -LiteralPath (Join-Path $root 'scripts\verify-skill-routing.ps1') -Raw

        $routingVerifier | Should Match 'skill-routing-compatibility'
        $routingVerifier | Should Match 'compatibility_only'
        $routingVerifier | Should Match 'profile_reachability_authority'
        $routingVerifier | Should Not Match 'Get-SkillRoutingLocalInventory'
        $routingVerifier | Should Not Match 'New-SkillRoutingReport'
    }

    It "owns the complete quality-gate stage sequence and verifier wiring centrally" {
        $root = Join-Path $PSScriptRoot "..\.."
        $scriptPath = Join-Path $root "scripts\quality\run-local-quality-gates.ps1"
        $raw = Get-Content -LiteralPath $scriptPath -Raw

        $actualStages = @([regex]::Matches($raw, "Invoke-QualityGate '([^']+)'\s*\{") | ForEach-Object { $_.Groups[1].Value })
        $actualStages | Should Be @(
            'build',
            'tests',
            'repo-hygiene',
            'generated-sync',
            'generated-sync',
            'workspace-lock-parity',
            'skill-integrity',
            'reference-governance',
            'override-activation-corpus',
            'native-skill-metadata',
            'dependency-baseline',
            'skills-config-contract',
            'host-capability-contract',
            'planning-contract',
            'powershell-runtime-policy',
            'doctor-json-contract'
        )
        foreach ($literal in @(
                'check-repo-hygiene.ps1 -ReportUntrackedRuntimeArtifacts',
                'verify-skill-integrity.ps1',
                'verify-reference-governance.ps1',
                'verify-override-skill-activation.ps1',
                'verify-native-skill-metadata.ps1',
                'verify-skills-config.ps1 -Mode enforce',
                'verify-host-capability-matrix.ps1',
                'verify-vnext-planning.ps1',
                'verify-powershell-runtime-policy.ps1'
            )) {
            $raw | Should Match ([regex]::Escape($literal))
        }
        $raw | Should Not Match 'agent-workflow-advisory|verify-agent-workflow-advisory\.ps1'
    }

    It "keeps retired auxiliary control planes out of active runtime surfaces" {
        $root = Join-Path $PSScriptRoot "..\.."
        foreach ($relativePath in @(
                'src\Domain\AgentWorkflow.ps1',
                'src\Application\ModelAndAgentPolicy.ps1',
                'src\Commands\AgentWorkflow.ps1',
                'scripts\verify-agent-workflow-advisory.ps1',
                'global.json',
                'typed-core\SkillsManager.TypedCore\SkillsManager.TypedCore.csproj',
                'typed-core\SkillsManager.TypedCore\Program.cs',
                'typed-core\SkillsManager.TypedCore\OperationContractValidator.cs',
                'scripts\verify-typed-core-shadow.ps1',
                'scripts\verify-typed-core-pilot-planning.ps1',
                'tests\Unit\TypedCoreShadow.Tests.ps1'
            )) {
            Test-Path -LiteralPath (Join-Path $root $relativePath) | Should Be $false
        }

        foreach ($relativePath in @('build.ps1', 'src\Main.ps1', 'src\Version.ps1', 'skills.ps1')) {
            $raw = Get-Content -LiteralPath (Join-Path $root $relativePath) -Raw
            $raw | Should Not Match 'agent-plan|agent-validate|AgentWorkflow|ModelAndAgentPolicy|typed-core|SkillsManager\.TypedCore|verify-typed-core'
        }
    }

    It "Documents the standalone skill integrity verifier in CLI help" {
        $root = Join-Path $PSScriptRoot "..\.."
        $helpSourcePath = Join-Path $root "src\Commands\Utils.ps1"
        $raw = Get-Content -LiteralPath $helpSourcePath -Raw

        $raw | Should Match "scripts\\verify-skill-integrity\.ps1"
        $raw | Should Match "scripts\\verify-native-skill-metadata\.ps1"
    }

    It "Uses the repo-owned full quality gate in GitHub CI" {
        $root = Join-Path $PSScriptRoot "..\.."
        $workflowPath = Join-Path $root ".github\workflows\ci.yml"
        $raw = Get-Content -LiteralPath $workflowPath -Raw

        $pesterIndex = $raw.IndexOf("Install pinned Pester test runtime")
        $fullGateIndex = $raw.IndexOf("run-local-quality-gates.ps1 -Profile full")

        $pesterIndex -ge 0 | Should Be $true
        $fullGateIndex -ge 0 | Should Be $true
        $pesterIndex -lt $fullGateIndex | Should Be $true
        $raw | Should Not Match "No supply-chain script found, skip"
    }

    It "keeps GitHub as the single formal CI surface" {
        $root = Join-Path $PSScriptRoot "..\.."
        Test-Path -LiteralPath (Join-Path $root '.github\workflows\ci.yml') -PathType Leaf | Should Be $true
        Test-Path -LiteralPath (Join-Path $root 'azure-pipelines.yml') | Should Be $false
        Test-Path -LiteralPath (Join-Path $root '.gitlab-ci.yml') | Should Be $false
    }

    It "Reports untracked runtime artifacts without failing by default" {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Host "git not found, skipping repository hygiene runtime artifact test."
            return
        }

        $root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
        $scriptPath = Join-Path $root "scripts\quality\check-repo-hygiene.ps1"
        $repo = Join-Path $TestDrive "repo-hygiene-untracked"
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        Push-Location $repo
        try {
            git init | Out-Null
            git config user.email "test@example.invalid" | Out-Null
            git config user.name "Test User" | Out-Null
            Set-Content -LiteralPath (Join-Path $repo "README.md") -Value "fixture" -Encoding UTF8
            git add README.md | Out-Null
            git commit -m "init" | Out-Null

            $evidenceDir = Join-Path $repo "docs\change-evidence"
            New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $evidenceDir "20260427-audit-runtime-dry-run-r-dry-123456.md") -Value "runtime evidence" -Encoding UTF8

            $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -ReportUntrackedRuntimeArtifacts 2>&1)
            $exitCode = $LASTEXITCODE

            $exitCode | Should Be 0
            (($output -join "`n") | Should Match "untracked runtime artifacts")
            (($output -join "`n") | Should Match "20260427-audit-runtime-dry-run-r-dry-123456\.md")
        }
        finally {
            Pop-Location
        }
    }

    It "Can fail on untracked runtime artifacts when explicitly requested" {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Host "git not found, skipping repository hygiene runtime artifact fail test."
            return
        }

        $root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
        $scriptPath = Join-Path $root "scripts\quality\check-repo-hygiene.ps1"
        $repo = Join-Path $TestDrive "repo-hygiene-untracked-fail"
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        Push-Location $repo
        try {
            git init | Out-Null
            git config user.email "test@example.invalid" | Out-Null
            git config user.name "Test User" | Out-Null
            Set-Content -LiteralPath (Join-Path $repo "README.md") -Value "fixture" -Encoding UTF8
            git add README.md | Out-Null
            git commit -m "init" | Out-Null

            $txnDir = Join-Path $repo ".txn\leftover"
            New-Item -ItemType Directory -Path $txnDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $txnDir "marker.txt") -Value "runtime" -Encoding UTF8

            $null = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -FailOnUntrackedRuntimeArtifacts 2>&1)
            $LASTEXITCODE | Should Be 1
        }
        finally {
            Pop-Location
        }
    }

    It "Evaluates tracked hygiene violations against worktree deletions without requiring staging" {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Host "git not found, skipping repository hygiene worktree deletion test."
            return
        }

        $root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
        $scriptPath = Join-Path $root "scripts\quality\check-repo-hygiene.ps1"
        $repo = Join-Path $TestDrive "repo-hygiene-worktree-deletion"
        New-Item -ItemType Directory -Path (Join-Path $repo "docs\change-evidence") -Force | Out-Null
        Push-Location $repo
        try {
            git init | Out-Null
            git config user.email "test@example.invalid" | Out-Null
            git config user.name "Test User" | Out-Null
            $receipt = Join-Path $repo "docs\change-evidence\20260427-audit-runtime-dry-run-r-dry-123456.md"
            Set-Content -LiteralPath $receipt -Value "runtime evidence" -Encoding UTF8
            git add . | Out-Null
            git commit -m "fixture with legacy receipt" | Out-Null

            $null = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath 2>&1)
            $LASTEXITCODE | Should Be 1

            Remove-Item -LiteralPath $receipt
            $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath 2>&1)
            $LASTEXITCODE | Should Be 0
            (($output -join "`n") | Should Match "Repository hygiene check passed")
            @(git diff --cached --name-only).Count | Should Be 0
        }
        finally {
            Pop-Location
        }
    }
}
