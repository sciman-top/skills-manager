Describe 'Resolve-QualityGateProfile shared classifier' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $script:resolverPath = Join-Path $repoRoot 'scripts\quality\resolve-gate-profile.ps1'
        $script:repos = [System.Collections.Generic.List[string]]::new()

        function New-ResolveGateFixture {
            $dir = Join-Path ([IO.Path]::GetTempPath()) ('resolve-gate-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $dir | Out-Null
            $script:repos.Add($dir) | Out-Null
            & git -C $dir init -b main *> $null
            if ($LASTEXITCODE -ne 0) { throw "git init failed for fixture" }
            & git -C $dir config user.email 'fixture@example.invalid'
            & git -C $dir config user.name 'Fixture'
            New-Item -ItemType Directory -Path (Join-Path $dir 'docs'), (Join-Path $dir 'src'), (Join-Path $dir 'tests\Unit'), (Join-Path $dir 'scripts\quality'), (Join-Path $dir 'config') | Out-Null
            Set-Content -LiteralPath (Join-Path $dir 'README.md') -Value '# fixture'
            Set-Content -LiteralPath (Join-Path $dir 'docs\x.md') -Value 'doc'
            Set-Content -LiteralPath (Join-Path $dir 'src\Core.ps1') -Value '# source'
            Set-Content -LiteralPath (Join-Path $dir 'tests\Unit\Core.Tests.ps1') -Value '# test'
            Set-Content -LiteralPath (Join-Path $dir 'skills.json') -Value '{}'
            Set-Content -LiteralPath (Join-Path $dir 'scripts\quality\x.ps1') -Value '# q'
            Set-Content -LiteralPath (Join-Path $dir 'scripts\weekly-skills-update.ps1') -Value '# w'
            Set-Content -LiteralPath (Join-Path $dir 'AGENTS.md') -Value '# agents'
            Set-Content -LiteralPath (Join-Path $dir 'CLAUDE.md') -Value '# claude'
            Set-Content -LiteralPath (Join-Path $dir 'GEMINI.md') -Value '# gemini'
            Set-Content -LiteralPath (Join-Path $dir 'config\skills.schema.json') -Value '{}'
            Set-Content -LiteralPath (Join-Path $dir 'config\skill-dependency-closure.json') -Value '{}'
            & git -C $dir add -A
            & git -C $dir commit -m baseline *> $null
            if ($LASTEXITCODE -ne 0) { throw "fixture commit failed" }
            return $dir
        }

        function Invoke-Resolver([string]$Repo, [hashtable]$Params = @{}) {
            Push-Location $Repo
            try {
                # Hashtable splat is required: array splat passes elements
                # positionally and would never bind parameter names.
                $all = @{ Json = $true }
                foreach ($key in @($Params.Keys)) { $all[$key] = $Params[$key] }
                $json = & $script:resolverPath @all
                return [pscustomobject]@{ result = ($json | ConvertFrom-Json); exit_code = $LASTEXITCODE }
            }
            finally { Pop-Location }
        }
    }

    AfterAll {
        foreach ($dir in @($script:repos)) {
            if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
        }
    }

    It 'classifies docs-only tracked changes as docs' {
        $repo = New-ResolveGateFixture
        $base = (& git -C $repo rev-parse HEAD).Trim()
        Add-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'change'
        Add-Content -LiteralPath (Join-Path $repo 'docs\x.md') -Value 'change'
        $r = Invoke-Resolver $repo @{ BaseSha = $base }
        $r.result.profile | Should -Be 'docs'
        $r.result.reason | Should -Be 'docs_only'
        $r.result.docs_only | Should -BeTrue
        $r.exit_code | Should -Be 0
    }

    It 'classifies pure MOR decision-doc changes as full, not docs' {
        $repo = New-ResolveGateFixture
        New-Item -ItemType Directory -Path (Join-Path $repo 'docs\decision') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'docs\decision\MOR-090-static-adapter-evidence.md') -Value '# mor'
        & git -C $repo add docs/decision/MOR-090-static-adapter-evidence.md
        & git -C $repo commit -m 'add mor doc' *> $null
        $base = (& git -C $repo rev-parse HEAD).Trim()
        Add-Content -LiteralPath (Join-Path $repo 'docs\decision\MOR-090-static-adapter-evidence.md') -Value 'change'
        $r = Invoke-Resolver $repo @{ BaseSha = $base }
        $r.result.profile | Should -Be 'full'
        $r.result.reason | Should -Be 'risk_path'
    }

    It 'classifies risk-path changes as full' {
        $repo = New-ResolveGateFixture
        $base = (& git -C $repo rev-parse HEAD).Trim()
        Add-Content -LiteralPath (Join-Path $repo 'skills.json') -Value '{"touched":true}'
        $r = Invoke-Resolver $repo @{ BaseSha = $base }
        $r.result.profile | Should -Be 'full'
        $r.result.reason | Should -Be 'risk_path'
    }

    It 'classifies projection-only skills.json changes as focused' {
        $repo = New-ResolveGateFixture
        Set-Content -LiteralPath (Join-Path $repo 'skills.json') -Value '{"schema_version":1,"skill_projection":{"projection_profiles":{"default_profile":"core"}},"stable":"same"}'
        & git -C $repo add skills.json
        & git -C $repo commit -m 'projection baseline' *> $null
        $base = (& git -C $repo rev-parse HEAD).Trim()
        Set-Content -LiteralPath (Join-Path $repo 'skills.json') -Value '{"schema_version":1,"skill_projection":{"projection_profiles":{"default_profile":"design"}},"stable":"same"}'
        $r = Invoke-Resolver $repo @{ BaseSha = $base }
        $r.result.profile | Should -Be 'focused'
        $r.result.reason | Should -Be 'config_projection_path'
        @($r.result.focused_test_paths) | Should -Contain 'tests/Unit/SkillProjection.Tests.ps1'
        @($r.result.focused_test_paths) | Should -Contain 'tests/Unit/SkillProjectionProfiles.Tests.ps1'
    }

    It 'keeps MCP skills.json changes on the full path' {
        $repo = New-ResolveGateFixture
        Set-Content -LiteralPath (Join-Path $repo 'skills.json') -Value '{"schema_version":1,"mcp_servers":[]}'
        & git -C $repo add skills.json
        & git -C $repo commit -m 'mcp baseline' *> $null
        $base = (& git -C $repo rev-parse HEAD).Trim()
        Set-Content -LiteralPath (Join-Path $repo 'skills.json') -Value '{"schema_version":1,"mcp_servers":[{"name":"demo"}]}'
        $r = Invoke-Resolver $repo @{ BaseSha = $base }
        $r.result.profile | Should -Be 'full'
        $r.result.reason | Should -Be 'risk_path'
    }

    It 'classifies skill markdown and OpenAI metadata changes as focused' {
        $repo = New-ResolveGateFixture
        $skillDir = Join-Path $repo 'overrides\custom\demo'
        New-Item -ItemType Directory -Path (Join-Path $skillDir 'agents') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $skillDir 'SKILL.md') -Value '# demo'
        Set-Content -LiteralPath (Join-Path $skillDir 'agents\openai.yaml') -Value 'name: demo'
        & git -C $repo add overrides
        & git -C $repo commit -m 'skill baseline' *> $null
        $base = (& git -C $repo rev-parse HEAD).Trim()
        Add-Content -LiteralPath (Join-Path $skillDir 'SKILL.md') -Value 'change'
        Add-Content -LiteralPath (Join-Path $skillDir 'agents\openai.yaml') -Value 'description: changed'
        $r = Invoke-Resolver $repo @{ BaseSha = $base }
        $r.result.profile | Should -Be 'focused'
        $r.result.reason | Should -Be 'skill_path'
        @($r.result.focused_test_paths) | Should -Contain 'tests/Unit/SkillProjection.Tests.ps1'
        @($r.result.focused_test_paths) | Should -Contain 'tests/Unit/SkillProjectionProfiles.Tests.ps1'
    }

    It 'fails safe to full for an unknown override file shape' {
        $repo = New-ResolveGateFixture
        $unknownPath = Join-Path $repo 'overrides\custom\demo\notes.txt'
        New-Item -ItemType Directory -Path (Split-Path -Parent $unknownPath) -Force | Out-Null
        Set-Content -LiteralPath $unknownPath -Value 'baseline'
        & git -C $repo add overrides
        & git -C $repo commit -m 'unknown override baseline' *> $null
        $base = (& git -C $repo rev-parse HEAD).Trim()
        Add-Content -LiteralPath $unknownPath -Value 'changed'
        $r = Invoke-Resolver $repo @{ BaseSha = $base }
        $r.result.profile | Should -Be 'full'
        $r.result.reason | Should -Be 'risk_path'
    }

    It 'classifies scripts/quality changes as full' {
        $repo = New-ResolveGateFixture
        $base = (& git -C $repo rev-parse HEAD).Trim()
        Add-Content -LiteralPath (Join-Path $repo 'scripts\quality\x.ps1') -Value '# touched'
        $r = Invoke-Resolver $repo @{ BaseSha = $base }
        $r.result.profile | Should -Be 'full'
        $r.result.reason | Should -Be 'risk_path'
    }

    It 'classifies governance and integrity contract changes as full' {
        foreach ($relativePath in @(
            'AGENTS.md',
            'CLAUDE.md',
            'GEMINI.md',
            'config/skills.schema.json',
            'config/skill-dependency-closure.json'
        )) {
            $repo = New-ResolveGateFixture
            $base = (& git -C $repo rev-parse HEAD).Trim()
            Add-Content -LiteralPath (Join-Path $repo ($relativePath -replace '/', '\\')) -Value '# touched'
            $r = Invoke-Resolver $repo @{ BaseSha = $base }
            $r.result.profile | Should -Be 'full'
            $r.result.reason | Should -Be 'risk_path'
        }
    }

    It 'classifies src changes as focused with the fixed smoke tests' {
        $repo = New-ResolveGateFixture
        $base = (& git -C $repo rev-parse HEAD).Trim()
        Add-Content -LiteralPath (Join-Path $repo 'src\Core.ps1') -Value '# touched'
        $r = Invoke-Resolver $repo @{ BaseSha = $base }
        $r.result.profile | Should -Be 'focused'
        $r.result.reason | Should -Be 'source_path'
        foreach ($fixed in @('tests/Unit/CiWorkflow.Tests.ps1', 'tests/Unit/InfrastructureSeam.Tests.ps1', 'tests/Unit/ReadOnlyCli.Tests.ps1', 'tests/Unit/BuildScript.Tests.ps1')) {
            $r.result.focused_test_paths | Should -Contain $fixed
        }
    }

    It 'adds changed unit test files to the focused set without duplicates' {
        $repo = New-ResolveGateFixture
        $base = (& git -C $repo rev-parse HEAD).Trim()
        Set-Content -LiteralPath (Join-Path $repo 'tests\Unit\Foo.Tests.ps1') -Value '# new tracked test'
        & git -C $repo add tests/Unit/Foo.Tests.ps1
        Add-Content -LiteralPath (Join-Path $repo 'src\Core.ps1') -Value '# touched'
        $r = Invoke-Resolver $repo @{ BaseSha = $base }
        $r.result.profile | Should -Be 'focused'
        $paths = @($r.result.focused_test_paths)
        $paths | Should -Contain 'tests/Unit/Foo.Tests.ps1'
        $paths.Count | Should -Be ($paths | Select-Object -Unique).Count
    }

    It 'classifies non-risk script changes as quick default' {
        $repo = New-ResolveGateFixture
        $base = (& git -C $repo rev-parse HEAD).Trim()
        Add-Content -LiteralPath (Join-Path $repo 'scripts\weekly-skills-update.ps1') -Value '# touched'
        $r = Invoke-Resolver $repo @{ BaseSha = $base }
        $r.result.profile | Should -Be 'quick'
        $r.result.reason | Should -Be 'default'
    }

    It 'classifies an empty diff as docs empty_diff' {
        $repo = New-ResolveGateFixture
        $base = (& git -C $repo rev-parse HEAD).Trim()
        $r = Invoke-Resolver $repo @{ BaseSha = $base }
        $r.result.profile | Should -Be 'docs'
        $r.result.reason | Should -Be 'empty_diff'
    }

    It 'fails safe to full for non-ignored untracked source files' {
        $repo = New-ResolveGateFixture
        $base = (& git -C $repo rev-parse HEAD).Trim()
        Set-Content -LiteralPath (Join-Path $repo 'src\New.ps1') -Value '# untracked'
        $r = Invoke-Resolver $repo @{ BaseSha = $base }
        $r.result.profile | Should -Be 'full'
        $r.result.reason | Should -Be 'untracked_file'
        $r.result.untracked_count | Should -Be 1
    }

    It 'fails safe to full even for untracked docs files' {
        $repo = New-ResolveGateFixture
        $base = (& git -C $repo rev-parse HEAD).Trim()
        Set-Content -LiteralPath (Join-Path $repo 'docs\new.md') -Value 'untracked'
        $r = Invoke-Resolver $repo @{ BaseSha = $base }
        $r.result.profile | Should -Be 'full'
        $r.result.reason | Should -Be 'untracked_file'
    }

    It 'fails safe to full when the untracked scan fails' {
        $repo = New-ResolveGateFixture
        $base = (& git -C $repo rev-parse HEAD).Trim()
        # A missing index is treated by git as an empty index (no error), so the
        # fixture must point at a corrupt index file to make ls-files fail.
        $corruptIndex = Join-Path $repo '..resolve-gate-corrupt-index'
        Set-Content -LiteralPath $corruptIndex -Value 'not a git index'
        $previous = $env:GIT_INDEX_FILE
        $env:GIT_INDEX_FILE = $corruptIndex
        try {
            $r = Invoke-Resolver $repo @{ BaseSha = $base }
            $r.result.profile | Should -Be 'full'
            $r.result.reason | Should -Be 'untracked_scan_failed'
        }
        finally {
            if ($null -eq $previous) { Remove-Item Env:\GIT_INDEX_FILE -ErrorAction SilentlyContinue } else { $env:GIT_INDEX_FILE = $previous }
            Remove-Item -LiteralPath $corruptIndex -Force -ErrorAction SilentlyContinue
        }
    }

    It 'fails safe to full when no base can be derived' {
        $repo = New-ResolveGateFixture
        $r = Invoke-Resolver $repo @{}
        $r.result.profile | Should -Be 'full'
        $r.result.reason | Should -Be 'no_base'
    }

    It 'fails safe to full for an unresolvable explicit base' {
        $repo = New-ResolveGateFixture
        $r = Invoke-Resolver $repo @{ BaseSha = '0000000000000000000000000000000000000000' }
        $r.result.profile | Should -Be 'full'
        $r.result.reason | Should -Be 'unresolvable_base'
    }

    It 'fails safe to full when the diff command fails in ci mode' {
        $repo = New-ResolveGateFixture
        $base = (& git -C $repo rev-parse HEAD).Trim()
        $r = Invoke-Resolver $repo @{ BaseSha = $base; Mode = 'ci'; HeadSha = '0000000000000000000000000000000000000000' }
        $r.result.profile | Should -Be 'full'
        $r.result.reason | Should -Be 'diff_failed'
    }

    It 'local mode includes the worktree while ci mode compares base to head only' {
        $repo = New-ResolveGateFixture
        $base = (& git -C $repo rev-parse HEAD).Trim()
        Add-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'uncommitted change'
        $local = Invoke-Resolver $repo @{ BaseSha = $base; Mode = 'local' }
        $local.result.profile | Should -Be 'docs'
        $local.result.reason | Should -Be 'docs_only'
        $ci = Invoke-Resolver $repo @{ BaseSha = $base; Mode = 'ci' }
        $ci.result.profile | Should -Be 'docs'
        $ci.result.reason | Should -Be 'empty_diff'
    }

    It 'keeps the shared classifier boundaries visible in the script' {
        $content = Get-Content -LiteralPath $script:resolverPath -Raw
        $content | Should -Match 'overrides/\(README\\\.md\|resources/'
        $content | Should -Match 'overrides/patches/provenance'
        $content | Should -Match 'skills\\\.lock\\\.json'
        $content | Should -Match '\$skillFocusedPath'
        $content | Should -Match '\$skillsConfigPath'
        $content | Should -Match ([regex]::Escape('^(src/|tests/Unit/)'))
        $content | Should -Match ([regex]::Escape('^(README(?:\.zh-CN|\.en)?\.md$|CONTRIBUTING\.md$|docs/.*\.md$)'))
        $content | Should -Match ([regex]::Escape('tests/Unit/CiWorkflow.Tests.ps1'))
        $content | Should -Match 'tests/Unit/SkillProjection.Tests.ps1'
    }
}
