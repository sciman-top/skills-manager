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
        $runner | Should Match 'Start-Process'
        $runner | Should Match '-NoNewWindow'
        $runner | Should Not Match '-WindowStyle\s+Hidden'
        $runner | Should Match 'test-shards'
        $runner | Should Match 'SerialTestFiles'
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
            '-MaxParallel', '1', '-TestFileTimeoutSeconds', '10'
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
        function New-GatePeerFixture([string]$Name, [int]$BuildDelaySeconds) {
            $fixtureRoot = Join-Path $TestDrive $Name
            $qualityRoot = Join-Path $fixtureRoot 'scripts\quality'
            New-Item -ItemType Directory -Path $qualityRoot -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $root 'scripts\quality\run-local-quality-gates.ps1') -Destination $qualityRoot
            Copy-Item -LiteralPath (Join-Path $root 'scripts\quality\QualityGateIntegrity.ps1') -Destination $qualityRoot
            Set-Content -LiteralPath (Join-Path $fixtureRoot '.gitignore') -Value 'reports/' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $fixtureRoot 'tracked.txt') -Value 'fixture' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $fixtureRoot 'build.ps1') -Value ("Start-Sleep -Seconds {0}" -f $BuildDelaySeconds) -Encoding UTF8
            git -C $fixtureRoot init -q
            git -C $fixtureRoot config user.email 'quality-gate@example.invalid'
            git -C $fixtureRoot config user.name 'Quality Gate Test'
            git -C $fixtureRoot add .
            git -C $fixtureRoot commit -qm 'fixture'
            return $fixtureRoot
        }

        $ownedRoot = New-GatePeerFixture 'quality-gate-owned' 5
        $otherRoot = New-GatePeerFixture 'quality-gate-other' 0
        $ownedRunner = Join-Path $ownedRoot 'scripts\quality\run-local-quality-gates.ps1'
        $ownerOut = Join-Path $TestDrive 'owner.out.log'
        $ownerErr = Join-Path $TestDrive 'owner.err.log'
        $owner = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $ownedRunner), '-Profile', 'quick') -PassThru -WindowStyle Hidden -RedirectStandardOutput $ownerOut -RedirectStandardError $ownerErr
        try {
            Start-Sleep -Milliseconds 750
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

    It "Runs repository hygiene in the reusable local quality gate" {
        $root = Join-Path $PSScriptRoot "..\.."
        $scriptPath = Join-Path $root "scripts\quality\run-local-quality-gates.ps1"
        $raw = Get-Content -LiteralPath $scriptPath -Raw

        $raw | Should Match "repo-hygiene"
        $raw | Should Match "check-repo-hygiene\.ps1"
        $raw | Should Match "ReportUntrackedRuntimeArtifacts"
    }

    It "Runs override governance between skill integrity and routing before dependency baseline" {
        $root = Join-Path $PSScriptRoot "..\.."
        $scriptPath = Join-Path $root "scripts\quality\run-local-quality-gates.ps1"
        $raw = Get-Content -LiteralPath $scriptPath -Raw

        $generatedSyncIndex = $raw.IndexOf("generated-sync")
        $skillIntegrityIndex = $raw.IndexOf("skill-integrity")
        $referenceGovernanceIndex = $raw.IndexOf("reference-governance")
        $overrideActivationIndex = $raw.IndexOf("override-activation-corpus")
        $nativeMetadataIndex = $raw.IndexOf("native-skill-metadata")
        $dependencyBaselineIndex = $raw.IndexOf("dependency-baseline")

        $generatedSyncIndex -ge 0 | Should Be $true
        $skillIntegrityIndex -ge 0 | Should Be $true
        $referenceGovernanceIndex -ge 0 | Should Be $true
        $overrideActivationIndex -ge 0 | Should Be $true
        $nativeMetadataIndex -ge 0 | Should Be $true
        $dependencyBaselineIndex -ge 0 | Should Be $true
        $generatedSyncIndex -lt $skillIntegrityIndex | Should Be $true
        $skillIntegrityIndex -lt $referenceGovernanceIndex | Should Be $true
        $referenceGovernanceIndex -lt $overrideActivationIndex | Should Be $true
        $overrideActivationIndex -lt $nativeMetadataIndex | Should Be $true
        $nativeMetadataIndex -lt $dependencyBaselineIndex | Should Be $true
        $raw | Should Match "verify-skill-integrity\.ps1"
        $raw | Should Match "verify-reference-governance\.ps1"
        $raw | Should Match "verify-override-skill-activation\.ps1"
        $raw | Should Match "verify-native-skill-metadata\.ps1"
    }

    It "Runs the vNext planning contract after dependency baseline and before doctor contract" {
        $root = Join-Path $PSScriptRoot "..\.."
        $scriptPath = Join-Path $root "scripts\quality\run-local-quality-gates.ps1"
        $raw = Get-Content -LiteralPath $scriptPath -Raw

        $dependencyBaselineIndex = $raw.IndexOf("dependency-baseline")
        $planningContractIndex = $raw.IndexOf("planning-contract")
        $doctorContractIndex = $raw.IndexOf("doctor-json-contract")

        $dependencyBaselineIndex -ge 0 | Should Be $true
        $planningContractIndex -ge 0 | Should Be $true
        $doctorContractIndex -ge 0 | Should Be $true
        $dependencyBaselineIndex -lt $planningContractIndex | Should Be $true
        $planningContractIndex -lt $doctorContractIndex | Should Be $true
        $raw | Should Match "verify-vnext-planning\.ps1"
    }

    It "Runs the skills config contract after dependency baseline and before planning" {
        $root = Join-Path $PSScriptRoot "..\.."
        $scriptPath = Join-Path $root "scripts\quality\run-local-quality-gates.ps1"
        $raw = Get-Content -LiteralPath $scriptPath -Raw

        $dependencyBaselineIndex = $raw.IndexOf("dependency-baseline")
        $configContractIndex = $raw.IndexOf("skills-config-contract")
        $planningContractIndex = $raw.IndexOf("planning-contract")

        $dependencyBaselineIndex -ge 0 | Should Be $true
        $configContractIndex -ge 0 | Should Be $true
        $planningContractIndex -ge 0 | Should Be $true
        $dependencyBaselineIndex -lt $configContractIndex | Should Be $true
        $configContractIndex -lt $planningContractIndex | Should Be $true
        $raw | Should Match "verify-skills-config\.ps1"
        $raw | Should Match "-Mode enforce"
    }

    It "Runs the host capability contract after config and before planning" {
        $root = Join-Path $PSScriptRoot "..\.."
        $scriptPath = Join-Path $root "scripts\quality\run-local-quality-gates.ps1"
        $raw = Get-Content -LiteralPath $scriptPath -Raw

        $configContractIndex = $raw.IndexOf("skills-config-contract")
        $hostContractIndex = $raw.IndexOf("host-capability-contract")
        $planningContractIndex = $raw.IndexOf("planning-contract")

        $configContractIndex -ge 0 | Should Be $true
        $hostContractIndex -ge 0 | Should Be $true
        $planningContractIndex -ge 0 | Should Be $true
        $configContractIndex -lt $hostContractIndex | Should Be $true
        $hostContractIndex -lt $planningContractIndex | Should Be $true
        $raw | Should Match "verify-host-capability-matrix\.ps1"
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

    It "keeps every formal CI surface on the authoritative full quality gate" {
        $root = Join-Path $PSScriptRoot "..\.."
        $contracts = @(
            @{ Path = 'azure-pipelines.yml'; Label = 'Azure Pipelines' },
            @{ Path = '.gitlab-ci.yml'; Label = 'GitLab CI' }
        )

        foreach ($contract in $contracts) {
            $raw = Get-Content -LiteralPath (Join-Path $root $contract.Path) -Raw
            $raw | Should Match 'run-local-quality-gates\.ps1 -Profile full'
            $raw | Should Not Match 'run-local-quality-gates\.ps1 -Profile quick'
        }
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
