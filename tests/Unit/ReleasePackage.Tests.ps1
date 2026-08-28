BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}

Describe 'Release packaging' {
    It 'ships the documented public delivery entrypoints' {
        $readme = Get-Content -LiteralPath (Join-Path $repoRoot 'README.md') -Raw
        $readme | Should -Match 'bootstrap\.zip'
        $readme | Should -Match 'portable\.zip'
        $readme | Should -Match 'source'
    }

    It 'builds the three public forms under one version directory without skills or MCP state' {
        $output = Join-Path $TestDrive 'delivery-output'
        $script = Join-Path $repoRoot 'scripts\release\build-release.ps1'
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $script -Version 'test.1' -Package Both -OutputDirectory $output -AllowDirtyWorktree | Out-Null
        $LASTEXITCODE | Should -Be 0

        $versionRoot = Join-Path $output 'test.1'
        Test-Path -LiteralPath (Join-Path $versionRoot 'standard-install\skills-manager-test.1-bootstrap.zip') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $versionRoot 'portable\skills-manager-test.1-portable.zip') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $versionRoot 'source\skills-manager-test.1-source.zip') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $versionRoot 'skills-manager-test.1-SHA256SUMS.txt') | Should -BeTrue

        foreach ($item in @(
                @{ archive = 'standard-install\skills-manager-test.1-bootstrap.zip'; root = 'skills-manager-test.1-bootstrap' },
                @{ archive = 'portable\skills-manager-test.1-portable.zip'; root = 'skills-manager-test.1-portable' },
                @{ archive = 'source\skills-manager-test.1-source.zip'; root = 'skills-manager-test.1-source' }
            )) {
            $extract = Join-Path $TestDrive ([IO.Path]::GetFileNameWithoutExtension($item.root))
            Expand-Archive -LiteralPath (Join-Path $versionRoot $item.archive) -DestinationPath $extract
            $packageRoot = Join-Path $extract $item.root
            Test-Path -LiteralPath (Join-Path $packageRoot 'agent') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $packageRoot 'vendor') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $packageRoot 'imports') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $packageRoot 'overrides') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $packageRoot 'skills.lock.json') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $packageRoot 'THIRD-PARTY-NOTICES.json') | Should -BeFalse
            $config = Get-Content -LiteralPath (Join-Path $packageRoot 'skills.json') -Raw | ConvertFrom-Json
            @($config.mappings).Count | Should -Be 0
            @($config.mcp_servers).Count | Should -Be 0
        }
    }

    It 'rejects repository artifact-root output that bypasses the delivery contract' {
        $script = Join-Path $repoRoot 'scripts\release\build-release.ps1'
        $result = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $script -Version 'test.root' -Package Bootstrap -OutputDirectory (Join-Path $repoRoot 'artifacts') -AllowDirtyWorktree 2>&1)
        $LASTEXITCODE | Should -Not -Be 0
        $result -join "`n" | Should -Match 'Release output directory must be artifacts\\deliveries'
    }
}
