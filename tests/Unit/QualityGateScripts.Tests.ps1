Describe "Quality gate scripts" {
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

    It "Runs repository hygiene in GitHub CI before other checks" {
        $root = Join-Path $PSScriptRoot "..\.."
        $workflowPath = Join-Path $root ".github\workflows\ci.yml"
        $raw = Get-Content -LiteralPath $workflowPath -Raw

        $hygieneIndex = $raw.IndexOf("Check repository hygiene")
        $generatedSyncIndex = $raw.IndexOf("Verify generated script sync")

        $hygieneIndex -ge 0 | Should Be $true
        $generatedSyncIndex -ge 0 | Should Be $true
        $hygieneIndex -lt $generatedSyncIndex | Should Be $true
        $raw | Should Match "check-repo-hygiene\.ps1"
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
