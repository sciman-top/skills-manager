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

    It "keeps full-suite output failure-focused and reports stage timings" {
        $root = Join-Path $PSScriptRoot "..\.."
        $runner = Get-Content -LiteralPath (Join-Path $root 'tests\run.ps1') -Raw

        $runner | Should Match '-Show Failed,Summary'
        $runner | Should Match 'unit_elapsed_ms'
        $runner | Should Match 'e2e_elapsed_ms'
        $runner | Should Match 'test_suite_elapsed_ms'
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

        $bundleText | Should Match 'runtime-evidence-'
        $applyText | Should Match 'runtime-evidence-'
        $bundleText | Should Not Match 'Join-Path \$script:Root "docs\\change-evidence"'
        $applyText | Should Not Match 'Join-Path \$script:Root "docs\\change-evidence"'
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

    It "Runs skill integrity and routing after generated sync and before dependency baseline" {
        $root = Join-Path $PSScriptRoot "..\.."
        $scriptPath = Join-Path $root "scripts\quality\run-local-quality-gates.ps1"
        $raw = Get-Content -LiteralPath $scriptPath -Raw

        $generatedSyncIndex = $raw.IndexOf("generated-sync")
        $skillIntegrityIndex = $raw.IndexOf("skill-integrity")
        $skillRoutingIndex = $raw.IndexOf("skill-routing")
        $dependencyBaselineIndex = $raw.IndexOf("dependency-baseline")

        $generatedSyncIndex -ge 0 | Should Be $true
        $skillIntegrityIndex -ge 0 | Should Be $true
        $skillRoutingIndex -ge 0 | Should Be $true
        $dependencyBaselineIndex -ge 0 | Should Be $true
        $generatedSyncIndex -lt $skillIntegrityIndex | Should Be $true
        $skillIntegrityIndex -lt $skillRoutingIndex | Should Be $true
        $skillRoutingIndex -lt $dependencyBaselineIndex | Should Be $true
        $raw | Should Match "verify-skill-integrity\.ps1"
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
}
