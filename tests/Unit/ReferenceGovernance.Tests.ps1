BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'skills.ps1')
}

Describe "Reference shelf governance" {
    BeforeAll {
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$manifestPath = Join-Path $repoRoot "references\reference-shelf.manifest.json"
$refreshScript = Join-Path $repoRoot "scripts\refresh-reference-repos.ps1"
$governanceScript = Join-Path $repoRoot "scripts\verify-reference-governance.ps1"
}

    It "Limits reference portfolio mutations to the project-owned external root" {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.references_root | Should -Be "D:\CODE\external\skills-manager-references"
    }

    It "Enforces reference portfolio tier and status lifecycle pairs" {
        . $governanceScript

        Test-ReferenceLifecycleState "core-mainline" "active" | Should -Be $true
        Test-ReferenceLifecycleState "secondary" "active" | Should -Be $true
        Test-ReferenceLifecycleState "conditional" "active" | Should -Be $true
        Test-ReferenceLifecycleState "core-mainline" "deprecated" | Should -Be $false
        Test-ReferenceLifecycleState "secondary" "not-cloned" | Should -Be $false
    }

    It 'requires a named consumer and retirement trigger for conditional references' {
        . $governanceScript

        Test-ConditionalReferenceContract ([pscustomobject]@{ tier='conditional'; consumer='watch-runtime'; retirement_trigger='remove when unused' }) | Should -BeTrue
        Test-ConditionalReferenceContract ([pscustomobject]@{ tier='conditional'; consumer=''; retirement_trigger='remove when unused' }) | Should -BeFalse
        Test-ConditionalReferenceContract ([pscustomobject]@{ tier='conditional'; consumer='watch-runtime'; retirement_trigger='' }) | Should -BeFalse
        Test-ConditionalReferenceContract ([pscustomobject]@{ tier='secondary' }) | Should -BeTrue
    }

    It "Rejects rooted and traversal reference paths before normalization" {
        . $governanceScript

        Test-ContainedReferenceRelativePath "/absolute/path" | Should -Be $false
        Test-ContainedReferenceRelativePath "C:\absolute\path" | Should -Be $false
        Test-ContainedReferenceRelativePath "nested/../../escape" | Should -Be $false
        Test-ContainedReferenceRelativePath "safe/./repo" | Should -Be $false
        Test-ContainedReferenceRelativePath "safe/repo" | Should -Be $true
    }

    It "Fails closed on manifest path traversal before reference refresh operations" {
        $fixtureManifest = Join-Path $TestDrive "traversal-reference-manifest.json"
        $fixture = [ordered]@{
            schema_version = 1
            references_root = (Join-Path $TestDrive "reference-root")
            default_refresh_set = @("escape")
            repos = @([ordered]@{
                    name = "escape"
                    tier = "core-mainline"
                    status = "active"
                    upstream_url = "https://example.invalid/escape.git"
                    relative_path = "nested/../../escape"
                })
        }
        [System.IO.File]::WriteAllText($fixtureManifest, ($fixture | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))

        { & $refreshScript -ManifestPath $fixtureManifest -ReferencesRoot $fixture.references_root -RepoNames escape -FetchOnly } | Should -Throw
        Test-Path -LiteralPath (Join-Path $TestDrive "escape") | Should -Be $false
    }

    It "Tracks the current official OpenAI plugin source and retires the deprecated skills repository" {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $plugins = @($manifest.repos | Where-Object name -eq "openai-plugins")
        $skills = @($manifest.repos | Where-Object name -eq "openai-skills")

        $plugins.Count | Should -Be 1
        $plugins[0].tier | Should -Be "core-mainline"
        $plugins[0].status | Should -Be "active"
        $plugins[0].source_disposition | Should -Be "current-official"
        $plugins[0].upstream_url | Should -Be "https://github.com/openai/plugins.git"
        $plugins[0].relative_path | Should -Be "core/openai-plugins"

        $skills.Count | Should -Be 0
        @($manifest.default_refresh_set) -contains "openai-plugins" | Should -Be $true
        @($manifest.default_refresh_set) -contains "openai-skills" | Should -Be $false
    }

    It 'retains conditional references only for a named current consumer' {
        . $governanceScript
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $conditional = @($manifest.repos | Where-Object tier -eq 'conditional')
        foreach ($entry in $conditional) {
            (Test-ConditionalReferenceContract $entry) | Should -BeTrue
        }

        $hermes = @($conditional | Where-Object name -eq 'hermes-agent')
        $hermes.Count | Should -Be 1
        $hermes[0].consumer | Should -Match 'HSM POC'
        $hermes[0].license | Should -Be 'MIT'
        $hermes[0].reviewed_revision | Should -Match '^[0-9a-f]{40}$'
        @($manifest.default_refresh_set) | Should -Not -Contain 'hermes-agent'
    }

    It "Selects a governed conditional reference only when explicitly requested" {
        $referencesRoot = Join-Path $TestDrive "conditional-reference-shelf"
        $outputDirectory = Join-Path $TestDrive "conditional-updates"
        $conditionalManifest = Join-Path $TestDrive 'conditional-manifest.json'
        [ordered]@{
            schema_version = 1
            references_root = $referencesRoot
            default_refresh_set = @()
            repos = @([ordered]@{
                    name = 'fixture-conditional'
                    tier = 'conditional'
                    status = 'active'
                    upstream_url = 'https://example.invalid/fixture.git'
                    relative_path = 'conditional/fixture/fixture-conditional'
                    branch = 'main'
                    policy = 'floating'
                    consumer = 'fixture-current-consumer'
                    retirement_trigger = 'remove when fixture consumer is retired'
                })
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $conditionalManifest -Encoding UTF8

        $result = & $refreshScript -ManifestPath $conditionalManifest -ReferencesRoot $referencesRoot -OutputDirectory $outputDirectory -Tier conditional -FetchOnly

        $result.repo_set | Should -Be "tier-conditional"
        @($result.repo_names) | Should -Be @('fixture-conditional')
        @($result.results | Where-Object status -ne "missing").Count | Should -Be 0
    }

    It "Routes the default set to plugins and writes a runtime receipt" {
        $referencesRoot = Join-Path $TestDrive "reference-shelf"
        $outputDirectory = Join-Path $TestDrive "updates"

        $defaultResult = & $refreshScript -ManifestPath $manifestPath -ReferencesRoot $referencesRoot -OutputDirectory $outputDirectory -FetchOnly
        $defaultResult.repo_set | Should -Be "core-default"
        @($defaultResult.repo_names) -contains "openai-plugins" | Should -Be $true
        @($defaultResult.repo_names) -contains "openai-skills" | Should -Be $false

        $defaultResult.output_path | Should -Be (Join-Path $outputDirectory "receipt.md")
        Test-Path -LiteralPath $defaultResult.output_path | Should -Be $true
    }

    It "Distinguishes fetched remote refs from the consumable local checkout revision" {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Host "git not found, skipping reference refresh provenance test."
            return
        }
        $remote = Join-Path $TestDrive "reference-remote.git"
        $publisher = Join-Path $TestDrive "reference-publisher"
        $referencesRoot = Join-Path $TestDrive "reference-consumer"
        $consumer = Join-Path $referencesRoot "core\demo"
        $outputDirectory = Join-Path $TestDrive "reference-reports"
        $fixtureManifest = Join-Path $TestDrive "reference-manifest.json"
        & git init --bare -q $remote
        & git clone -q $remote $publisher
        & git -C $publisher config user.name fixture
        & git -C $publisher config user.email fixture@example.invalid
        Set-Content -LiteralPath (Join-Path $publisher "README.md") -Value "one" -Encoding UTF8
        & git -C $publisher add README.md
        & git -C $publisher commit -q -m one
        & git -C $publisher push -q origin HEAD
        New-Item -ItemType Directory -Path (Split-Path $consumer -Parent) -Force | Out-Null
        & git clone -q $remote $consumer
        $manifest = [ordered]@{
            schema_version = 1
            references_root = $referencesRoot
            default_refresh_set = @("demo")
            repos = @([ordered]@{
                    name = "demo"
                    tier = "core-mainline"
                    status = "active"
                    upstream_url = $remote
                    relative_path = "core/demo"
                })
        }
        [System.IO.File]::WriteAllText($fixtureManifest, ($manifest | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))

        $current = & $refreshScript -ManifestPath $fixtureManifest -OutputDirectory $outputDirectory -FetchOnly
        $current.results[0].remote_refs_current | Should -Be $true
        $current.results[0].working_tree_matches_upstream | Should -Be $true
        [string]$current.results[0].consumable_revision | Should -Match '^[0-9a-f]{40}$'
        $current.results[0].consumable_revision | Should -Be $current.results[0].upstream_revision

        Set-Content -LiteralPath (Join-Path $publisher "README.md") -Value "two" -Encoding UTF8
        & git -C $publisher add README.md
        & git -C $publisher commit -q -m two
        & git -C $publisher push -q origin HEAD
        $behind = & $refreshScript -ManifestPath $fixtureManifest -OutputDirectory $outputDirectory -FetchOnly
        $behind.results[0].remote_refs_current | Should -Be $true
        $behind.results[0].working_tree_matches_upstream | Should -Be $false
        $behind.results[0].consumable_revision | Should -Not -Be $behind.results[0].upstream_revision
        $report = Get-Content -LiteralPath $behind.output_path -Raw -Encoding UTF8
        $report | Should -Match 'remote refs current：`true`'
        $report | Should -Match 'working tree matches upstream：`false`'
        $report | Should -Match 'consumable revision：`[0-9a-f]{40}`'
    }
}
