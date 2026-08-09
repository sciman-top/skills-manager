Describe "Dependency baseline verifier script" {
    $scriptPath = Join-Path $PSScriptRoot "..\..\scripts\verify-dependency-baseline.py"

    function New-DependencyBaselineFixture([string]$repoRoot, [string]$verifyCommand = "python scripts/verify-dependency-baseline.py --target-repo-root <target-repo-root> --require-target-repo-baseline") {
        $baselineDir = Join-Path $repoRoot ".governed-ai"
        New-Item -ItemType Directory -Path $baselineDir -Force | Out-Null
        $repoId = Split-Path $repoRoot -Leaf
        $payload = [ordered]@{
            baseline_kind = "target_repo_dependency_baseline"
            generated_at = "2026-04-23T00:00:00+00:00"
            owner_runtime = "unit-test-runtime"
            repo_id = $repoId
            schema_version = "1.0"
            verify_command = $verifyCommand
        }
        ($payload | ConvertTo-Json -Depth 6) | Set-Content -Path (Join-Path $baselineDir "dependency-baseline.json") -Encoding UTF8
    }

    It "passes when target repo baseline exists and fields are valid" {
        if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
            Write-Host "python not found, skipping dependency baseline verifier test."
            return
        }

        $repoRoot = Join-Path $TestDrive "repo-valid"
        New-Item -ItemType Directory -Path $repoRoot -Force | Out-Null
        New-DependencyBaselineFixture $repoRoot

        $output = @(& python $scriptPath --target-repo-root $repoRoot --require-target-repo-baseline 2>&1)
        $exitCode = $LASTEXITCODE

        $exitCode | Should Be 0
        (($output -join "`n") -like "*verified*") | Should Be $true
    }

    It "uses the canonical Git common root name for a linked worktree" {
        if (-not (Get-Command python -ErrorAction SilentlyContinue) -or -not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Host "python or git not found, skipping linked worktree dependency baseline verifier test."
            return
        }

        $canonicalRepo = Join-Path $TestDrive "canonical-repo"
        $linkedRoot = Join-Path $TestDrive "renamed-linked-worktree"
        New-Item -ItemType Directory -Path $canonicalRepo -Force | Out-Null
        & git -C $canonicalRepo init --quiet
        $LASTEXITCODE | Should Be 0
        New-DependencyBaselineFixture $canonicalRepo
        & git -C $canonicalRepo add .governed-ai/dependency-baseline.json
        $LASTEXITCODE | Should Be 0
        & git -C $canonicalRepo -c user.name=fixture -c user.email=fixture@example.invalid commit --quiet -m "Add dependency baseline fixture"
        $LASTEXITCODE | Should Be 0

        try {
            & git -C $canonicalRepo worktree add --quiet -b fixture-linked-worktree $linkedRoot HEAD
            $LASTEXITCODE | Should Be 0

            $output = @(& python $scriptPath --target-repo-root $linkedRoot --require-target-repo-baseline 2>&1)
            $exitCode = $LASTEXITCODE

            $exitCode | Should Be 0
            (($output -join "`n") -like "*verified*") | Should Be $true
        }
        finally {
            if (Test-Path -LiteralPath $linkedRoot) {
                & git -C $canonicalRepo worktree remove $linkedRoot
            }
            & git -C $canonicalRepo branch -d fixture-linked-worktree 2>$null | Out-Null
        }
    }

    It "fails when baseline is required but missing" {
        if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
            Write-Host "python not found, skipping dependency baseline verifier test."
            return
        }

        $repoRoot = Join-Path $TestDrive "repo-missing"
        New-Item -ItemType Directory -Path $repoRoot -Force | Out-Null

        $null = @(& python $scriptPath --target-repo-root $repoRoot --require-target-repo-baseline 2>&1)
        $exitCode = $LASTEXITCODE

        $exitCode | Should Be 2
    }

    It "fails when verify_command does not reference verifier script" {
        if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
            Write-Host "python not found, skipping dependency baseline verifier test."
            return
        }

        $repoRoot = Join-Path $TestDrive "repo-invalid"
        New-Item -ItemType Directory -Path $repoRoot -Force | Out-Null
        New-DependencyBaselineFixture $repoRoot "python scripts/other.py --target-repo-root <target-repo-root>"

        $output = @(& python $scriptPath --target-repo-root $repoRoot --require-target-repo-baseline 2>&1)
        $exitCode = $LASTEXITCODE

        $exitCode | Should Be 1
        (($output -join "`n") -like "*verification failed*") | Should Be $true
    }
}
