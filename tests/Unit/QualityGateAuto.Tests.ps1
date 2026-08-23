Describe 'Local quality gate -Profile auto routing' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $script:gateSource = Join-Path $repoRoot 'scripts\quality\run-local-quality-gates.ps1'
        $script:resolverSource = Join-Path $repoRoot 'scripts\quality\resolve-gate-profile.ps1'
        $script:repos = [System.Collections.Generic.List[string]]::new()

        function New-AutoGateFixture {
            $dir = Join-Path ([IO.Path]::GetTempPath()) ('gate-auto-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $dir 'scripts\quality'), (Join-Path $dir 'src') | Out-Null
            $script:repos.Add($dir) | Out-Null
            Copy-Item -LiteralPath $script:gateSource -Destination (Join-Path $dir 'scripts\quality\run-local-quality-gates.ps1')
            Copy-Item -LiteralPath $script:resolverSource -Destination (Join-Path $dir 'scripts\quality\resolve-gate-profile.ps1')
            Set-Content -LiteralPath (Join-Path $dir 'README.md') -Value '# fixture'
            Set-Content -LiteralPath (Join-Path $dir 'src\Core.ps1') -Value '# source'
            Set-Content -LiteralPath (Join-Path $dir 'skills.json') -Value '{}'
            & git -C $dir init -b main *> $null
            & git -C $dir config user.email 'fixture@example.invalid'
            & git -C $dir config user.name 'Fixture'
            & git -C $dir add -A
            & git -C $dir commit -m baseline *> $null
            if ($LASTEXITCODE -ne 0) { throw 'fixture commit failed' }
            return $dir
        }

        # Invoke the fixture's own copy of the gate. Calling the repository's
        # script would resolve $root back to skills-manager and recursively
        # run the real quality gates inside the test run.
        function Invoke-TempGate([string]$Repo, [hashtable]$Params = @{}) {
            # 6>&1 merges the Information stream so Write-Host routing lines
            # are captured for assertions.
            & (Join-Path $Repo 'scripts\quality\run-local-quality-gates.ps1') @Params 6>&1
        }
    }

    AfterAll {
        foreach ($dir in @($script:repos)) {
            if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
        }
    }

    It 'resolves a docs-only worktree change to docs via -ResolveOnly' {
        $repo = New-AutoGateFixture
        $base = (& git -C $repo rev-parse HEAD).Trim()
        Add-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'docs change'
        Push-Location $repo
        try { $out = Invoke-TempGate $repo @{ Profile = 'auto'; ResolveOnly = $true; DiffBase = $base } } finally { Pop-Location }
        ($out | Out-String) | Should -Match 'auto -> docs \(reason=docs_only'
    }

    It 'resolves a src change to focused without running the build in ResolveOnly mode' {
        $repo = New-AutoGateFixture
        $base = (& git -C $repo rev-parse HEAD).Trim()
        Add-Content -LiteralPath (Join-Path $repo 'src\Core.ps1') -Value '# touched'
        Push-Location $repo
        try { $out = Invoke-TempGate $repo @{ Profile = 'auto'; ResolveOnly = $true; DiffBase = $base } } finally { Pop-Location }
        ($out | Out-String) | Should -Match 'auto -> focused \(reason=source_path'
        # The fixture has no build.ps1; a routing-only invocation must not run it.
        ($out | Out-String) | Should -Not -Match '== build =='
    }

    It 'resolves a risk-path change to full' {
        $repo = New-AutoGateFixture
        $base = (& git -C $repo rev-parse HEAD).Trim()
        Add-Content -LiteralPath (Join-Path $repo 'skills.json') -Value '{"touched":true}'
        Push-Location $repo
        try { $out = Invoke-TempGate $repo @{ Profile = 'auto'; ResolveOnly = $true; DiffBase = $base } } finally { Pop-Location }
        ($out | Out-String) | Should -Match 'auto -> full \(reason=risk_path'
    }

    It 'fails safe to full when no base can be derived' {
        $repo = New-AutoGateFixture
        Push-Location $repo
        try { $out = Invoke-TempGate $repo @{ Profile = 'auto'; ResolveOnly = $true } } finally { Pop-Location }
        ($out | Out-String) | Should -Match 'auto -> full \(reason=no_base'
    }

    It 'docs auto checks the current worktree, not a derived base' {
        $repo = New-AutoGateFixture
        $base = (& git -C $repo rev-parse HEAD).Trim()
        # Uncommitted docs change with trailing whitespace: must fail the docs
        # gate. If the derived base were forwarded, `git diff --check <base> HEAD`
        # would inspect the clean committed range and wrongly pass.
        Add-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'docs change with trailing ws   '
        Push-Location $repo
        try {
            { Invoke-TempGate $repo @{ Profile = 'auto'; DiffBase = $base } *> $null } | Should -Throw
        }
        finally { Pop-Location }
    }

    It 'docs auto passes for a clean docs-only change end to end' {
        $repo = New-AutoGateFixture
        $base = (& git -C $repo rev-parse HEAD).Trim()
        Add-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'clean docs change'
        Push-Location $repo
        try {
            $out = Invoke-TempGate $repo @{ Profile = 'auto'; DiffBase = $base }
            $LASTEXITCODE | Should -Be 0
            ($out | Out-String) | Should -Match 'Local quality gates passed \(docs\)'
            ($out | Out-String) | Should -Match 'Gate diff-check elapsed=\d+\.\d{3}s'
        }
        finally { Pop-Location }
    }
}
