BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'skills.ps1')
    . (Join-Path $PSScriptRoot '..\Shared\TestHelpers.ps1')
    Initialize-TestGitIdentity
}

Describe "Reference shelf governance" {
    BeforeAll {
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$manifestPath = Join-Path $repoRoot "references\reference-shelf.manifest.json"
$refreshScript = Join-Path $repoRoot "scripts\refresh-reference-repos.ps1"
$governanceScript = Join-Path $repoRoot "scripts\verify-reference-governance.ps1"
    function script:New-ExternalGitFixtureRepo {
        param([Parameter(Mandatory)][string]$Path)
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        & git -C $Path init -q --initial-branch main
        if ($LASTEXITCODE -ne 0) { throw "git init failed for fixture: $Path" }
        [IO.File]::WriteAllText((Join-Path $Path 'README.md'), 'initial')
        & git -C $Path add README.md
        if ($LASTEXITCODE -ne 0) { throw "git add failed for fixture: $Path" }
        & git -C $Path commit -q -m initial
        if ($LASTEXITCODE -ne 0) { throw "git commit failed for fixture: $Path" }
        & git -C $Path remote add origin ("https://example.invalid/{0}.git" -f (Split-Path -Leaf $Path))
        if ($LASTEXITCODE -ne 0) { throw "git remote add failed for fixture: $Path" }
        (& git -C $Path rev-parse HEAD).Trim()
    }
}

    It "Limits reference portfolio mutations to the project-owned external root" {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.references_root | Should -Be "D:\CODE\external\skills-manager-references"
    }

    It "Finds Git repositories nested under external source collection folders" {
        . $governanceScript

        $externalRoot = Join-Path $TestDrive 'external-inventory'
        $nestedRepo = Join-Path $externalRoot 'source-group\nested-repo'
        $directRepo = Join-Path $externalRoot 'direct-repo'
        $brokenRepo = Join-Path $externalRoot 'source-group\broken-repo'
        New-Item -ItemType Directory -Path (Split-Path -Parent $nestedRepo) -Force | Out-Null
        New-Item -ItemType Directory -Path $nestedRepo -Force | Out-Null
        New-Item -ItemType Directory -Path $directRepo -Force | Out-Null
        New-Item -ItemType Directory -Path $brokenRepo -Force | Out-Null
        & git -C $nestedRepo init -q --initial-branch main
        & git -C $directRepo init -q --initial-branch main
        [IO.File]::WriteAllText((Join-Path $brokenRepo '.git'), 'invalid gitdir marker')

        $repositories = @(Get-ExternalGitRepositories -ExternalRoot $externalRoot)

        @($repositories | ForEach-Object { $_.relative_path }) | Should -Be @('direct-repo', 'source-group/broken-repo', 'source-group/nested-repo')
        @($repositories | Where-Object { $_.relative_path -eq 'source-group/broken-repo' })[0].git_root_valid | Should -Be $false
    }

    It "Skips junction aliases and excluded trees but scans the shared canonical repository root" {
        . $governanceScript

        $externalRoot = Join-Path $TestDrive 'external-canonical-inventory'
        $controlRoot = Join-Path $externalRoot '_shared'
        $canonicalRepo = Join-Path $controlRoot 'repos\shared-repo'
        $ownedRepo = Join-Path $externalRoot 'skills-manager-references\owned-repo'
        $directRepo = Join-Path $externalRoot 'source-group\direct-repo'
        $junctionParent = Join-Path $externalRoot 'consumer'
        $junctionPath = Join-Path $junctionParent 'shared-repo'
        New-Item -ItemType Directory -Path $canonicalRepo -Force | Out-Null
        New-Item -ItemType Directory -Path $ownedRepo -Force | Out-Null
        New-Item -ItemType Directory -Path $directRepo -Force | Out-Null
        New-Item -ItemType Directory -Path $junctionParent -Force | Out-Null
        & git -C $controlRoot init -q --initial-branch main
        & git -C $canonicalRepo init -q --initial-branch main
        & git -C $ownedRepo init -q --initial-branch main
        & git -C $directRepo init -q --initial-branch main
        try { New-Item -ItemType Junction -Path $junctionPath -Target $canonicalRepo -ErrorAction Stop | Out-Null }
        catch {
            Set-ItResult -Skipped -Because "junction creation is unavailable: $($_.Exception.Message)"
            return
        }

        try {
            $repositories = @(Get-ExternalGitRepositories -ExternalRoot $externalRoot -ExcludedTreeRoots @((Join-Path $externalRoot 'skills-manager-references'), (Join-Path $controlRoot 'migration-backups')) -ExcludedRepositoryRoots @($controlRoot))
            @($repositories | ForEach-Object { $_.relative_path }) | Should -Be @('_shared/repos/shared-repo', 'source-group/direct-repo')
        }
        finally {
            if (Test-Path -LiteralPath $junctionPath) { Remove-Item -LiteralPath $junctionPath -Force }
        }
    }

    It 'Plans baseline additions, fast-forward updates, and retired paths without writing' {
        Import-Module (Join-Path $repoRoot 'scripts\ExternalGitRepositoryDiscovery.psm1') -Force
        $externalRoot = Join-Path $TestDrive 'external-baseline-plan'
        $existingPath = Join-Path $externalRoot 'existing-repo'
        $newPath = Join-Path $externalRoot 'new-repo'
        $oldHead = New-ExternalGitFixtureRepo -Path $existingPath
        $origin = "https://example.invalid/existing-repo.git"
        [IO.File]::WriteAllText((Join-Path $existingPath 'README.md'), 'fast-forward')
        & git -C $existingPath commit -qam fast-forward
        if ($LASTEXITCODE -ne 0) { throw 'fixture fast-forward commit failed' }
        $null = New-ExternalGitFixtureRepo -Path $newPath
        $baseline = [pscustomobject]@{
            schema_version = 1
            external_root = $externalRoot
            repos = @(
                [pscustomobject]@{ relative_path = 'existing-repo'; head = $oldHead; origin = $origin }
                [pscustomobject]@{ relative_path = 'retired-repo'; head = ('a' * 40); origin = 'https://example.invalid/retired.git' }
            )
        }

        $plan = New-ExternalGitBaselinePlan -ExternalRoot $externalRoot -BaselineDocument $baseline

        $plan.repositories | Should -Be 2
        $plan.added | Should -Be @('new-repo')
        $plan.fast_forward_updated | Should -Be @('existing-repo')
        $plan.retired | Should -Be @('retired-repo')
        $plan.changed | Should -BeTrue
        @($plan.document.repos).Count | Should -Be 2
    }

    It 'Rejects dirty repositories during baseline planning' {
        Import-Module (Join-Path $repoRoot 'scripts\ExternalGitRepositoryDiscovery.psm1') -Force
        $externalRoot = Join-Path $TestDrive 'external-baseline-dirty'
        $repoPath = Join-Path $externalRoot 'dirty-repo'
        $head = New-ExternalGitFixtureRepo -Path $repoPath
        $baseline = [pscustomobject]@{
            schema_version = 1
            external_root = $externalRoot
            repos = @([pscustomobject]@{
                    relative_path = 'dirty-repo'
                    head = $head
                    origin = 'https://example.invalid/dirty-repo.git'
                })
        }
        [IO.File]::WriteAllText((Join-Path $repoPath 'local-change.txt'), 'untracked')

        $plan = New-ExternalGitBaselinePlan -ExternalRoot $externalRoot -BaselineDocument $baseline

        $plan.blocked | Should -Contain 'dirty-repo (dirty working tree)'
        @($plan.document.repos).Count | Should -Be 1
        $plan.document.repos[0].head | Should -Be $head
        $plan.changed | Should -BeFalse
    }

    It 'Rejects divergent heads instead of blessing them as a baseline update' {
        Import-Module (Join-Path $repoRoot 'scripts\ExternalGitRepositoryDiscovery.psm1') -Force
        $externalRoot = Join-Path $TestDrive 'external-baseline-diverged'
        $repoPath = Join-Path $externalRoot 'diverged-repo'
        $null = New-ExternalGitFixtureRepo -Path $repoPath
        & git -C $repoPath checkout -qb baseline
        [IO.File]::WriteAllText((Join-Path $repoPath 'README.md'), 'baseline side')
        & git -C $repoPath commit -qam baseline-side
        if ($LASTEXITCODE -ne 0) { throw 'baseline-side fixture commit failed' }
        $baselineHead = (& git -C $repoPath rev-parse HEAD).Trim()
        & git -C $repoPath checkout -q main
        [IO.File]::WriteAllText((Join-Path $repoPath 'README.md'), 'current side')
        & git -C $repoPath commit -qam current-side
        if ($LASTEXITCODE -ne 0) { throw 'current-side fixture commit failed' }
        $baseline = [pscustomobject]@{
            schema_version = 1
            external_root = $externalRoot
            repos = @([pscustomobject]@{
                    relative_path = 'diverged-repo'
                    head = $baselineHead
                    origin = 'https://example.invalid/diverged-repo.git'
                })
        }

        $plan = New-ExternalGitBaselinePlan -ExternalRoot $externalRoot -BaselineDocument $baseline

        $plan.blocked | Should -Contain 'diverged-repo (HEAD is not a fast-forward from the recorded baseline)'
        @($plan.document.repos).Count | Should -Be 1
        $plan.document.repos[0].head | Should -Be $baselineHead
        $plan.changed | Should -BeFalse
    }

    It "Enforces reference portfolio tier and status lifecycle pairs" {
        . $governanceScript

        Test-ReferenceLifecycleState "core-mainline" "active" | Should -Be $true
        Test-ReferenceLifecycleState "secondary" "active" | Should -Be $true
        Test-ReferenceLifecycleState "conditional" "active" | Should -Be $true
        Test-ReferenceLifecycleState "core-mainline" "deprecated" | Should -Be $false
        Test-ReferenceLifecycleState "secondary" "not-cloned" | Should -Be $false
    }

    It 'requires a named consumer and retirement trigger for every reference tier' {
        . $governanceScript

        foreach ($tier in @('core-mainline', 'secondary', 'conditional')) {
            Test-ReferenceConsumerContract ([pscustomobject]@{ tier=$tier; consumer='skills-manager: source comparison'; retirement_trigger='remove when unused' }) | Should -BeTrue
            Test-ReferenceConsumerContract ([pscustomobject]@{ tier=$tier; consumer=''; retirement_trigger='remove when unused' }) | Should -BeFalse
            Test-ReferenceConsumerContract ([pscustomobject]@{ tier=$tier; consumer='skills-manager: source comparison'; retirement_trigger='' }) | Should -BeFalse
        }
    }

    It 'requires a consumer and retirement trigger for every registered reference' {
        . $governanceScript
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

        foreach ($entry in @($manifest.repos)) {
            (Test-ReferenceConsumerContract $entry) | Should -BeTrue
            $entry.consumer | Should -Match '^skills-manager'
        }
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
                    consumer = "skills-manager: fixture source comparison"
                    retirement_trigger = "remove when fixture source comparison is retired"
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
            (Test-ReferenceConsumerContract $entry) | Should -BeTrue
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
                    consumer = 'skills-manager: fixture source comparison'
                    retirement_trigger = 'remove when fixture source comparison is retired'
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
