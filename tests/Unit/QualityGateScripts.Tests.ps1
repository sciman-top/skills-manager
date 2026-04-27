Describe "Quality gate scripts" {
    It "Runs repository hygiene in the reusable local quality gate" {
        $root = Join-Path $PSScriptRoot "..\.."
        $scriptPath = Join-Path $root "scripts\quality\run-local-quality-gates.ps1"
        $raw = Get-Content -LiteralPath $scriptPath -Raw

        $raw | Should Match "repo-hygiene"
        $raw | Should Match "check-repo-hygiene\.ps1"
        $raw | Should Match "ReportUntrackedRuntimeArtifacts"
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
