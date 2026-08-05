Describe "Quality gate scripts" {
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

        $runner | Should Match '-Show Failed,Summary'
        $runner | Should Match 'unit_elapsed_ms'
        $runner | Should Match 'e2e_elapsed_ms'
        $runner | Should Match 'test_suite_elapsed_ms'
        $runner | Should Match 'slow_test_file'
        $runner | Should Match 'slow_test_case'
        $runner | Should Match 'reports.test-timings.current.json'
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

    It "keeps the routing gate on its lightweight inventory instead of audit hashes" {
        $root = Join-Path $PSScriptRoot "..\.."
        $routingVerifier = Get-Content -LiteralPath (Join-Path $root 'scripts\verify-skill-routing.ps1') -Raw

        $routingVerifier | Should Match 'Get-SkillRoutingLocalInventory'
        $routingVerifier | Should Not Match 'Get-InstalledSkillFacts'
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
        $skillRoutingIndex = $raw.IndexOf("skill-routing")
        $dependencyBaselineIndex = $raw.IndexOf("dependency-baseline")

        $generatedSyncIndex -ge 0 | Should Be $true
        $skillIntegrityIndex -ge 0 | Should Be $true
        $referenceGovernanceIndex -ge 0 | Should Be $true
        $overrideActivationIndex -ge 0 | Should Be $true
        $skillRoutingIndex -ge 0 | Should Be $true
        $dependencyBaselineIndex -ge 0 | Should Be $true
        $generatedSyncIndex -lt $skillIntegrityIndex | Should Be $true
        $skillIntegrityIndex -lt $referenceGovernanceIndex | Should Be $true
        $referenceGovernanceIndex -lt $overrideActivationIndex | Should Be $true
        $overrideActivationIndex -lt $skillRoutingIndex | Should Be $true
        $skillRoutingIndex -lt $dependencyBaselineIndex | Should Be $true
        $raw | Should Match "verify-skill-integrity\.ps1"
        $raw | Should Match "verify-reference-governance\.ps1"
        $raw | Should Match "verify-override-skill-activation\.ps1"
        $raw | Should Match "verify-skill-routing\.ps1"
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
        $raw | Should Match "scripts\\verify-skill-routing\.ps1"
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
