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

    It 'runs preset-only proof without the main bundle and propagates failure' {
        $repo = New-AutoGateFixture
        New-Item -ItemType Directory -Path (Join-Path $repo 'src/model-orchestration'), (Join-Path $repo 'tests') | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'tests/run.ps1') -Value @'
param([string[]]$TestPath)
if ($TestPath.Count -ne 1 -or $TestPath[0] -ne 'tests/Unit/ModelPreset.Tests.ps1') { throw 'Wrong preset proof' }
Write-Host 'preset-proof-executed'
$global:LASTEXITCODE = 0
'@
        & git -C $repo add .
        & git -C $repo commit -m 'runner fixture' *> $null
        Set-Content -LiteralPath (Join-Path $repo 'src/model-orchestration/presets.json') -Value '{}'
        $out = Invoke-TempGate $repo @{}
        ($out | Out-String) | Should -Match 'preset-proof-executed'
        ($out | Out-String) | Should -Not -Match '== build =='
        Set-Content -LiteralPath (Join-Path $repo 'tests/run.ps1') -Value '$global:LASTEXITCODE = 9'
        { Invoke-TempGate $repo @{ Profile = 'focused'; TestPath = @('tests/Unit/ModelPreset.Tests.ps1') } *> $null } | Should -Throw '*exit=9*'
    }

    It 'rejects invalid resolver output before resolve-only success: <case>' -ForEach @(
        @{ case = 'missing profile'; resolverText = "'{}'; exit 0" }
        @{ case = 'unknown profile'; resolverText = "'{`"profile`":`"skip`"}'; exit 0" }
        @{ case = 'recursive auto'; resolverText = "'{`"profile`":`"auto`"}'; exit 0" }
        @{ case = 'array profile'; resolverText = "'{`"profile`":[`"docs`"]}'; exit 0" }
        @{ case = 'failed resolver with valid output'; resolverText = "'{`"profile`":`"docs`",`"reason`":`"empty_diff`",`"docs_only`":false,`"requires_locked_sources`":false,`"focused_test_paths`":[]}'; exit 9" }
        @{ case = 'focused without tests'; resolverText = "'{`"profile`":`"focused`",`"reason`":`"source_path`",`"docs_only`":false,`"requires_locked_sources`":false,`"focused_test_paths`":[]}'; exit 0" }
        @{ case = 'malformed JSON'; resolverText = "'{'; exit 0" }
        @{ case = 'resolver exception'; resolverText = "throw 'resolver crashed'" }
        @{ case = 'array result'; resolverText = "'[{`"profile`":`"docs`",`"reason`":`"docs_only`",`"docs_only`":true,`"requires_locked_sources`":false,`"focused_test_paths`":[]}]'; exit 0" }
        @{ case = 'non-boolean setup'; resolverText = "'{`"profile`":`"docs`",`"reason`":`"docs_only`",`"docs_only`":true,`"requires_locked_sources`":`"false`",`"focused_test_paths`":[]}'; exit 0" }
        @{ case = 'scalar test path'; resolverText = "'{`"profile`":`"focused`",`"reason`":`"source_path`",`"docs_only`":false,`"requires_locked_sources`":false,`"focused_test_paths`":`"tests/Unit/Core.Tests.ps1`"}'; exit 0" }
        @{ case = 'null test path'; resolverText = "'{`"profile`":`"focused`",`"reason`":`"source_path`",`"docs_only`":false,`"requires_locked_sources`":false,`"focused_test_paths`":[null]}'; exit 0" }
    ) {
        $repo = New-AutoGateFixture
        Set-Content -LiteralPath (Join-Path $repo 'scripts/quality/resolve-gate-profile.ps1') -Value $resolverText
        { Invoke-TempGate $repo @{ Profile = 'auto'; ResolveOnly = $true } *> $null } | Should -Throw '*Gate profile resolver*'
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

    It 'uses HEAD without requiring a remote for local checks' {
        $repo = New-AutoGateFixture
        Push-Location $repo
        try { $out = Invoke-TempGate $repo @{ Profile = 'auto'; ResolveOnly = $true } } finally { Pop-Location }
        ($out | Out-String) | Should -Match 'auto -> docs \(reason=empty_diff'
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

    It 'the default profile checks untracked and staged docs whitespace' {
        $repo = New-AutoGateFixture
        $base = (& git -C $repo rev-parse HEAD).Trim()
        Set-Content -LiteralPath (Join-Path $repo 'docs.md') -Value 'new document   '
        # Use a recognized documentation path while leaving it untracked.
        New-Item -ItemType Directory -Path (Join-Path $repo 'docs') | Out-Null
        Move-Item -LiteralPath (Join-Path $repo 'docs.md') -Destination (Join-Path $repo 'docs/new.md')
        Push-Location $repo
        try {
            { Invoke-TempGate $repo @{ DiffBase = $base } *> $null } | Should -Throw '*Untracked whitespace*'
            & git add docs/new.md
            { Invoke-TempGate $repo @{ DiffBase = $base } *> $null } | Should -Throw '*Tracked whitespace*'
        }
        finally { Pop-Location }
    }

    It 'the docs gate passes for a whitespace-clean untracked docs file' {
        $repo = New-AutoGateFixture
        $base = (& git -C $repo rev-parse HEAD).Trim()
        # --no-index 对“与 /dev/null 有差异”的干净新文件返回 1；只有 >1 才是
        # 空白/git 失败。新增干净文档不应触发 Untracked whitespace 失败。
        New-Item -ItemType Directory -Path (Join-Path $repo 'docs') | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'docs/clean.md') -Value 'clean notes'
        Push-Location $repo
        try {
            Invoke-TempGate $repo @{ Profile = 'auto'; DiffBase = $base } *> $null
            $LASTEXITCODE | Should -Be 0
        }
        finally { Pop-Location }
    }

    It 'auto preserves the explicit base when docs whitespace is already committed' {
        $repo = New-AutoGateFixture
        $base = (& git -C $repo rev-parse HEAD).Trim()
        Add-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'committed whitespace   '
        & git -C $repo add README.md
        & git -C $repo commit -m 'docs change' *> $null
        if ($LASTEXITCODE -ne 0) { throw 'fixture commit failed' }
        { Invoke-TempGate $repo @{ Profile = 'auto'; DiffBase = $base } *> $null } | Should -Throw
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

    It 'regenerates an uncommitted local bundle and rejects submitted drift before tests' {
        $repo = New-AutoGateFixture
        $sourceRoot = Split-Path (Split-Path (Split-Path $script:gateSource -Parent) -Parent) -Parent
        Copy-Item -LiteralPath (Join-Path $sourceRoot 'build.ps1') -Destination $repo
        Copy-Item -LiteralPath (Join-Path $sourceRoot 'src') -Destination $repo -Recurse -Force
        Copy-Item -LiteralPath (Join-Path $sourceRoot 'rules') -Destination $repo -Recurse -Force
        New-Item -ItemType Directory -Path (Join-Path $repo 'tests') | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'tests/run.ps1') -Value @'
param([string[]]$TestPath)
Set-Content -LiteralPath (Join-Path $PSScriptRoot 'ran.txt') -Value 'ran'
$global:LASTEXITCODE = 0
'@
        Push-Location $repo
        try {
            Invoke-TempGate $repo @{ Profile = 'focused'; TestPath = @('fixture') } *> $null
            $bundle = Join-Path $repo 'skills.ps1'
            $hash = (Get-FileHash -LiteralPath $bundle).Hash
            Invoke-TempGate $repo @{ Profile = 'focused'; TestPath = @('fixture'); CheckGenerated = $true } *> $null
            Remove-Item -LiteralPath (Join-Path $repo 'tests/ran.txt')
            Add-Content -LiteralPath (Join-Path $repo 'src/Version.ps1') -Value '# source changed'
            { Invoke-TempGate $repo @{ Profile = 'focused'; TestPath = @('fixture'); CheckGenerated = $true } *> $null } | Should -Throw '*generated_bundle_drift*'
            (Get-FileHash -LiteralPath $bundle).Hash | Should -Be $hash
            Test-Path -LiteralPath (Join-Path $repo 'tests/ran.txt') | Should -BeFalse
            Invoke-TempGate $repo @{ Profile = 'focused'; TestPath = @('fixture') } *> $null
            (Get-FileHash -LiteralPath $bundle).Hash | Should -Not -Be $hash
            Test-Path -LiteralPath (Join-Path $repo 'tests/ran.txt') | Should -BeTrue
        }
        finally { Pop-Location }
    }

    It 'honors explicit regression tests after a docs-only auto classification' {
        $repo = New-AutoGateFixture
        New-Item -ItemType Directory -Path (Join-Path $repo 'tests') | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'build.ps1') -Value '$global:LASTEXITCODE = 0'
        Set-Content -LiteralPath (Join-Path $repo 'tests/run.ps1') -Value @'
param([string[]]$TestPath, [string[]]$TestName)
if ($TestPath -notcontains 'regression' -or $TestName -notcontains '*chosen') { throw 'Lost explicit filters' }
Write-Host 'explicit-regression-executed'
$global:LASTEXITCODE = 0
'@
        & git -C $repo add .
        & git -C $repo commit -m 'runner fixture' *> $null
        Add-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'docs change'
        $out = Invoke-TempGate $repo @{ TestPath = @('regression'); TestName = @('*chosen') }
        ($out | Out-String) | Should -Match 'explicit-regression-executed'
        ($out | Out-String) | Should -Match '== diff-check =='
        ($out | Out-String) | Should -Match 'Local quality gates passed \(focused\)'
    }

    It 'blocks a non-CI full run when sandbox shim fingerprints are present' {
        $repo = New-AutoGateFixture
        # CI runners set CI=true, which disables the block under test; clear it
        # for the duration so the assertion does not depend on the host.
        $env:CODEBUDDY_SAFE_DELETE_SANDBOX = '1'
        $ciBefore = $env:CI
        Remove-Item Env:\CI -ErrorAction SilentlyContinue
        try {
            # The block must fire before any build/test gate starts, so the
            # fixture needs no runnable tests: the throw itself is the proof.
            { Invoke-TempGate $repo @{ Profile = 'full' } *> $null } | Should -Throw '*blocked inside an instrumented sandbox*'
        }
        finally {
            Remove-Item Env:\CODEBUDDY_SAFE_DELETE_SANDBOX -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace($ciBefore)) { $env:CI = $ciBefore }
        }
    }
}
