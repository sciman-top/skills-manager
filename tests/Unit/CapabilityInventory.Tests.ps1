BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
    . (Join-Path $repoRoot 'src\Infrastructure\CodexCli.ps1')
    . (Join-Path $repoRoot 'src\Application\CapabilityInventory.ps1')

    function Write-CapabilityProjectionManifestFixture($ProjectionConfig, [string]$Path) {
        $plan = New-SkillProjectionPlan $ProjectionConfig $repoRoot -OmitExternalInventory
        $manifest = [ordered]@{
            schema_version = 2
            projection_fingerprint = Get-SkillProjectionPlanFingerprint $plan
            source_revision = ('0' * 40)
            enabled = [bool]$plan.enabled
            source_count = @($ProjectionConfig.sources).Count
            skill_entry_count = @($plan.skills).Count
            unique_name_count = @($plan.unique_names).Count
            active_name_count = @($plan.active_names).Count
            duplicate_name_groups = [int]$plan.duplicate_name_groups
            disabled_path_count = @($plan.disabled).Count
            conflict_count = @($plan.conflicts).Count
            skills = @($plan.skills)
            canonical = @($plan.canonical)
            active = @($plan.active)
            disabled = @($plan.disabled)
            conflicts = @($plan.conflicts)
        }
        [IO.File]::WriteAllText($Path, ($manifest | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    }
}
Describe 'Read-only skill surface inventory' {
    It 'reports six explained skill surfaces even when their counts differ' {
        $fixture = Join-Path ([IO.Path]::GetTempPath()) ('skill-surfaces-' + [guid]::NewGuid().ToString('N'))
        $oldCodexHome = $env:CODEX_HOME
        try {
            $agentRoot = Join-Path $fixture 'agent'; $userRoot = Join-Path $fixture 'user-skills'; $pluginRoot = Join-Path $fixture 'plugin'; $env:CODEX_HOME = Join-Path $fixture 'codex'
            foreach ($path in @((Join-Path $agentRoot 'managed-stale'), (Join-Path $agentRoot 'managed-current'), (Join-Path $userRoot 'unknown-skill'), (Join-Path $env:CODEX_HOME 'skills\.system\system-skill'), (Join-Path $pluginRoot 'skills\plugin-skill'))) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
            foreach ($path in @((Join-Path $agentRoot 'managed-stale\SKILL.md'), (Join-Path $agentRoot 'managed-current\SKILL.md'), (Join-Path $userRoot 'unknown-skill\SKILL.md'), (Join-Path $env:CODEX_HOME 'skills\.system\system-skill\SKILL.md'), (Join-Path $pluginRoot 'skills\plugin-skill\SKILL.md'))) { [IO.File]::WriteAllText($path, "---`nname: $([IO.Path]::GetFileName((Split-Path $path -Parent)))`ndescription: fixture`n---`n", [Text.UTF8Encoding]::new($false)) }
            Mock Invoke-CodexCliJson { [pscustomobject]@{ installed = @([pscustomobject]@{ pluginId='plugin@fixture'; name='plugin'; marketplaceName='fixture'; version='1'; installed=$true; enabled=$true; source=[pscustomobject]@{ path=$pluginRoot } }) } }
            New-Item -ItemType Junction -Path (Join-Path $userRoot 'managed-current') -Target (Join-Path $agentRoot 'managed-current') -Force | Out-Null
            New-Item -ItemType Junction -Path (Join-Path $userRoot 'managed-stale') -Target (Join-Path $agentRoot 'managed-stale') -Force | Out-Null
            $externalRoot = Join-Path $fixture 'external\external-skill'; New-Item -ItemType Directory -Force -Path $externalRoot | Out-Null; [IO.File]::WriteAllText((Join-Path $externalRoot 'SKILL.md'), "---`nname: external-skill`ndescription: fixture`n---`n", [Text.UTF8Encoding]::new($false)); New-Item -ItemType Junction -Path (Join-Path $userRoot 'external-skill') -Target $externalRoot -Force | Out-Null
            $snapshotPath = Join-Path $fixture 'host.json'; [IO.File]::WriteAllText($snapshotPath, (([pscustomobject]@{ captured_at = [datetimeoffset]::UtcNow.ToString('o'); coverage = 'complete'; skills = @([pscustomobject]@{ name = 'host-only'; path = 'host://skill'; entrypoint_hash = ('a' * 64); description_hash = ('b' * 64) }) }) | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
            $config = [pscustomobject]@{ skill_projection = [pscustomobject]@{ manifest_path = 'reports/current.json'; managed_source_path = 'agent'; user_skill_root = $userRoot; managed_link_includes = @('managed-current'); external_skill_inventory = [pscustomobject]@{ enabled = $true } } }
            $view = New-SkillSurfaceView -RepoRoot $fixture -Config $config -HostSnapshotPath $snapshotPath
            $view.pass | Should -BeTrue
            $view.surface_count | Should -Be 6
            $view.host_observation.truth_boundary | Should -Be 'read_only_cli_observation_not_host_loaded'
            $view.host_observation.writes | Should -Be 0
            @($view.surfaces.name) | Should -Be @('repo_supply', 'canonical_projection', 'user_skill_root', 'system', 'plugins', 'host_visible')
            foreach ($surface in $view.surfaces) { $surface.authority | Should -Not -BeNullOrEmpty; $surface.source | Should -Not -BeNullOrEmpty; $surface.fingerprint | Should -Match '^[a-f0-9]{64}$'; $surface.freshness | Should -Not -BeNullOrEmpty; $surface.coverage | Should -Not -BeNullOrEmpty }
            @($view.stale_links.projection_state) | Should -Contain 'managed_stale'
            @($view.stale_links.projection_state) | Should -Contain 'external_owned'
            @($view.stale_links.projection_state) | Should -Contain 'ownership_unknown'
        }
        finally { $env:CODEX_HOME = $oldCodexHome; if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force } }
    }

    It 'fails closed when a host-visible skill lacks fingerprints' {
        $fixture = Join-Path ([IO.Path]::GetTempPath()) ('skill-surfaces-' + [guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Force -Path $fixture | Out-Null
            $snapshotPath = Join-Path $fixture 'host.json'; [IO.File]::WriteAllText($snapshotPath, (([pscustomobject]@{ captured_at = [datetimeoffset]::UtcNow.ToString('o'); coverage = 'partial'; skills = @([pscustomobject]@{ name = 'incomplete'; path = 'host://incomplete' }) }) | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
            Mock Invoke-CodexCliJson { [pscustomobject]@{ installed = @() } }
            $config = [pscustomobject]@{ skill_projection = [pscustomobject]@{ manifest_path = 'reports/current.json'; managed_source_path = 'agent'; user_skill_root = 'user'; managed_link_includes = @(); external_skill_inventory = [pscustomobject]@{ enabled = $true } } }
            $view = New-SkillSurfaceView -RepoRoot $fixture -Config $config -HostSnapshotPath $snapshotPath
            $view.pass | Should -BeFalse
            @($view.findings.code) | Should -Contain 'host_skill_identity_incomplete'
        }
        finally { if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force } }
    }

    It 'reports a missing user skill root as not observed and not materialized' {
        $fixture = Join-Path ([IO.Path]::GetTempPath()) ('skill-surfaces-' + [guid]::NewGuid().ToString('N'))
        $oldCodexHome = $env:CODEX_HOME
        try {
            New-Item -ItemType Directory -Force -Path $fixture | Out-Null
            $env:CODEX_HOME = Join-Path $fixture 'codex'
            Mock Get-CodexPluginSkillInventory { [pscustomobject]@{ authority = 'fixture'; freshness = 'fresh'; coverage = 'complete'; skills = @(); warnings = @() } }
            Mock Get-CodexHostObservation { [pscustomobject]@{ mcp = [pscustomobject]@{ warnings = @() }; doctor = [pscustomobject]@{ warnings = @() } } }
            $config = [pscustomobject]@{ skill_projection = [pscustomobject]@{ manifest_path = 'reports/current.json'; managed_source_path = 'agent'; user_skill_root = 'missing-user-skills'; managed_link_includes = @(); sources = @() }; mcp_servers = @() }

            $view = New-SkillSurfaceView -RepoRoot $fixture -Config $config
            $surface = $view.surfaces | Where-Object name -eq 'user_skill_root'

            $surface.count | Should -Be 0
            $surface.freshness | Should -Be 'not_observed'
            $surface.coverage | Should -Be 'not_materialized'
        }
        finally { $env:CODEX_HOME = $oldCodexHome; if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force } }
    }

    It 'uses canonical content identity instead of unrelated Git revisions for projection freshness' {
        $fixture = Join-Path ([IO.Path]::GetTempPath()) ('skill-surfaces-' + [guid]::NewGuid().ToString('N'))
        $oldCodexHome = $env:CODEX_HOME
        try {
            $skillRoot = Join-Path $fixture 'canonical\demo'
            $manifestPath = Join-Path $fixture 'reports\current.json'
            $env:CODEX_HOME = Join-Path $fixture 'codex'
            New-Item -ItemType Directory -Force -Path $skillRoot, (Split-Path $manifestPath -Parent) | Out-Null
            $skillPath = Join-Path $skillRoot 'SKILL.md'
            $assetPath = Join-Path $skillRoot 'asset.txt'
            [IO.File]::WriteAllText($skillPath, "---`nname: demo`ndescription: fixture`n---`n", [Text.UTF8Encoding]::new($false))
            [IO.File]::WriteAllText($assetPath, 'asset-v1', [Text.UTF8Encoding]::new($false))
            $projection = [pscustomobject]@{ manifest_path = $manifestPath; managed_source_path = 'agent'; user_skill_root = 'user'; managed_link_includes = @(); sources = @([pscustomobject]@{ id = 'fixture'; path = (Split-Path $skillRoot -Parent); priority = 1; platforms = @('codex') }); external_skill_inventory = [pscustomobject]@{ enabled = $true } }
            $config = [pscustomobject]@{ skill_projection = $projection; mcp_servers = @() }
            Write-CapabilityProjectionManifestFixture $projection $manifestPath
            Mock Get-CodexPluginSkillInventory { [pscustomobject]@{ authority = 'fixture'; freshness = 'fresh'; coverage = 'complete'; skills = @(); warnings = @() } }
            Mock Get-CodexHostObservation { [pscustomobject]@{ mcp = [pscustomobject]@{ warnings = @() }; doctor = [pscustomobject]@{ warnings = @() } } }

            $freshView = New-SkillSurfaceView -RepoRoot $fixture -Config $config
            ($freshView.surfaces | Where-Object name -eq 'canonical_projection').freshness | Should -Be 'fresh'
            $freshView.pass | Should -BeTrue
            [IO.File]::WriteAllText($assetPath, 'asset-v2', [Text.UTF8Encoding]::new($false))
            $assetStaleView = New-SkillSurfaceView -RepoRoot $fixture -Config $config
            ($assetStaleView.surfaces | Where-Object name -eq 'canonical_projection').freshness | Should -Be 'stale'
            $assetStaleView.pass | Should -BeFalse
            @($assetStaleView.findings.code) | Should -Contain 'projection_manifest_stale'
            [IO.File]::WriteAllText($assetPath, 'asset-v1', [Text.UTF8Encoding]::new($false))
            [IO.File]::WriteAllText($skillPath, "---`nname: demo`ndescription: changed`n---`n", [Text.UTF8Encoding]::new($false))
            $skillStaleView = New-SkillSurfaceView -RepoRoot $fixture -Config $config
            ($skillStaleView.surfaces | Where-Object name -eq 'canonical_projection').freshness | Should -Be 'stale'
            $skillStaleView.pass | Should -BeFalse
        }
        finally { $env:CODEX_HOME = $oldCodexHome; if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force } }
    }

    It 'fails closed when the current source inventory adds a skill absent from the manifest' {
        $fixture = Join-Path ([IO.Path]::GetTempPath()) ('skill-surfaces-' + [guid]::NewGuid().ToString('N'))
        try {
            $sourceRoot = Join-Path $fixture 'source'; $demoRoot = Join-Path $sourceRoot 'demo'; $manifestPath = Join-Path $fixture 'reports\current.json'
            New-Item -ItemType Directory -Force -Path $demoRoot, (Split-Path $manifestPath -Parent) | Out-Null
            [IO.File]::WriteAllText((Join-Path $demoRoot 'SKILL.md'), "---`nname: demo`ndescription: fixture`n---`n", [Text.UTF8Encoding]::new($false))
            $projection = [pscustomobject]@{ manifest_path = $manifestPath; managed_source_path = 'agent'; user_skill_root = 'user'; managed_link_includes = @(); sources = @([pscustomobject]@{ id = 'fixture'; path = $sourceRoot; priority = 1; platforms = @('codex') }) }
            Write-CapabilityProjectionManifestFixture $projection $manifestPath
            $newRoot = Join-Path $sourceRoot 'new-skill'; New-Item -ItemType Directory -Force -Path $newRoot | Out-Null
            [IO.File]::WriteAllText((Join-Path $newRoot 'SKILL.md'), "---`nname: new-skill`ndescription: fixture`n---`n", [Text.UTF8Encoding]::new($false))
            Mock Get-CodexPluginSkillInventory { [pscustomobject]@{ authority = 'fixture'; freshness = 'fresh'; coverage = 'complete'; skills = @(); warnings = @() } }
            Mock Get-CodexHostObservation { [pscustomobject]@{ mcp = [pscustomobject]@{ warnings = @() }; doctor = [pscustomobject]@{ warnings = @() } } }

            $view = New-SkillSurfaceView -RepoRoot $fixture -Config ([pscustomobject]@{ skill_projection = $projection; mcp_servers = @() })
            ($view.surfaces | Where-Object name -eq 'canonical_projection').freshness | Should -Be 'stale'
            $view.pass | Should -BeFalse
            @($view.findings.code) | Should -Contain 'projection_manifest_stale'
        }
        finally { if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force } }
    }

    It 'rejects an invalid manifest contract instead of vacuously reporting fresh' {
        $fixture = Join-Path ([IO.Path]::GetTempPath()) ('skill-surfaces-' + [guid]::NewGuid().ToString('N'))
        try {
            $manifestPath = Join-Path $fixture 'reports\current.json'; New-Item -ItemType Directory -Force -Path (Split-Path $manifestPath -Parent) | Out-Null
            [IO.File]::WriteAllText($manifestPath, '{"canonical":[]}', [Text.UTF8Encoding]::new($false))
            $projection = [pscustomobject]@{ manifest_path = $manifestPath; managed_source_path = 'agent'; user_skill_root = 'user'; managed_link_includes = @(); sources = @() }
            Mock Get-CodexPluginSkillInventory { [pscustomobject]@{ authority = 'fixture'; freshness = 'fresh'; coverage = 'complete'; skills = @(); warnings = @() } }
            Mock Get-CodexHostObservation { [pscustomobject]@{ mcp = [pscustomobject]@{ warnings = @() }; doctor = [pscustomobject]@{ warnings = @() } } }

            $view = New-SkillSurfaceView -RepoRoot $fixture -Config ([pscustomobject]@{ skill_projection = $projection; mcp_servers = @() })
            $surface = $view.surfaces | Where-Object name -eq 'canonical_projection'
            $surface.freshness | Should -Be 'invalid'
            $surface.coverage | Should -Be 'invalid'
            $view.pass | Should -BeFalse
            @($view.findings.code) | Should -Contain 'projection_manifest_field_missing'
        }
        finally { if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force } }
    }

    It 'rejects manifest skill paths outside the currently configured source roots' {
        $fixture = Join-Path ([IO.Path]::GetTempPath()) ('skill-surfaces-' + [guid]::NewGuid().ToString('N'))
        try {
            $sourceRoot = Join-Path $fixture 'source'; $skillRoot = Join-Path $sourceRoot 'demo'; $outsideRoot = Join-Path $fixture 'outside'; $manifestPath = Join-Path $fixture 'reports\current.json'
            New-Item -ItemType Directory -Force -Path $skillRoot, $outsideRoot, (Split-Path $manifestPath -Parent) | Out-Null
            $skillPath = Join-Path $skillRoot 'SKILL.md'; $outsidePath = Join-Path $outsideRoot 'SKILL.md'
            [IO.File]::WriteAllText($skillPath, "---`nname: demo`ndescription: fixture`n---`n", [Text.UTF8Encoding]::new($false)); [IO.File]::WriteAllText($outsidePath, "---`nname: outside`ndescription: fixture`n---`n", [Text.UTF8Encoding]::new($false))
            $projection = [pscustomobject]@{ manifest_path = $manifestPath; managed_source_path = 'agent'; user_skill_root = 'user'; managed_link_includes = @(); sources = @([pscustomobject]@{ id = 'fixture'; path = $sourceRoot; priority = 1; platforms = @('codex') }) }
            Write-CapabilityProjectionManifestFixture $projection $manifestPath
            $manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json; $manifest.skills[0].path = $outsidePath; $manifest.canonical[0].path = $outsidePath; $manifest.active[0].path = $outsidePath
            [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
            Mock Get-CodexPluginSkillInventory { [pscustomobject]@{ authority = 'fixture'; freshness = 'fresh'; coverage = 'complete'; skills = @(); warnings = @() } }
            Mock Get-CodexHostObservation { [pscustomobject]@{ mcp = [pscustomobject]@{ warnings = @() }; doctor = [pscustomobject]@{ warnings = @() } } }

            $view = New-SkillSurfaceView -RepoRoot $fixture -Config ([pscustomobject]@{ skill_projection = $projection; mcp_servers = @() })
            ($view.surfaces | Where-Object name -eq 'canonical_projection').freshness | Should -Be 'invalid'
            $view.pass | Should -BeFalse
            @($view.findings.code) | Should -Contain 'projection_manifest_path_outside_source'
        }
        finally { if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force } }
    }

    It 'fails closed when a managed include is an ordinary directory' {
        $fixture = Join-Path ([IO.Path]::GetTempPath()) ('skill-surfaces-' + [guid]::NewGuid().ToString('N'))
        $oldCodexHome = $env:CODEX_HOME
        try {
            $env:CODEX_HOME = Join-Path $fixture 'codex'
            $ordinary = Join-Path $fixture 'user\managed-current'
            $prefixSource = Join-Path $fixture 'agent-other\prefix-skill'
            New-Item -ItemType Directory -Path $ordinary -Force | Out-Null
            New-Item -ItemType Directory -Path $prefixSource -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $ordinary 'SKILL.md'), "---`nname: managed-current`ndescription: fixture`n---`n", [Text.UTF8Encoding]::new($false))
            [IO.File]::WriteAllText((Join-Path $prefixSource 'SKILL.md'), "---`nname: prefix-skill`ndescription: fixture`n---`n", [Text.UTF8Encoding]::new($false))
            New-Item -ItemType Junction -Path (Join-Path $fixture 'user\prefix-skill') -Target $prefixSource | Out-Null
            Mock Invoke-CodexCliJson { [pscustomobject]@{ installed = @() } }
            $config = [pscustomobject]@{ skill_projection = [pscustomobject]@{ manifest_path = 'missing.json'; managed_source_path = 'agent'; user_skill_root = (Join-Path $fixture 'user'); managed_link_includes = @('managed-current') }; mcp_servers = @() }

            $view = New-SkillSurfaceView -RepoRoot $fixture -Config $config
            $record = @($view.surfaces | Where-Object name -eq 'user_skill_root')[0].items[0]
            $prefixRecord = @(@($view.surfaces | Where-Object name -eq 'user_skill_root')[0].items | Where-Object name -eq 'prefix-skill')[0]

            $view.pass | Should -BeFalse
            $record.projection_state | Should -Be 'ownership_drift'
            $record.owner | Should -Be 'unknown'
            $record.resident | Should -BeFalse
            @($view.findings.code) | Should -Contain 'managed_link_ownership_drift'
            $prefixRecord.projection_state | Should -Be 'external_owned'
        }
        finally {
            $env:CODEX_HOME = $oldCodexHome
            if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
        }
    }
}
