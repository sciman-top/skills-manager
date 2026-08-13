$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
. (Join-Path $repoRoot 'src\Application\CapabilityInventory.ps1')

Describe 'Read-only skill surface inventory' {
    It 'reports six explained skill surfaces even when their counts differ' {
        $fixture = Join-Path ([IO.Path]::GetTempPath()) ('skill-surfaces-' + [guid]::NewGuid().ToString('N'))
        $oldCodexHome = $env:CODEX_HOME
        try {
            $agentRoot = Join-Path $fixture 'agent'; $userRoot = Join-Path $fixture 'user-skills'; $pluginRoot = Join-Path $fixture 'plugins'; $env:CODEX_HOME = Join-Path $fixture 'codex'
            foreach ($path in @((Join-Path $agentRoot 'managed-stale'), (Join-Path $userRoot 'managed-current'), (Join-Path $userRoot 'unknown-skill'), (Join-Path $env:CODEX_HOME 'skills\.system\system-skill'), (Join-Path $pluginRoot 'plugin-skill'))) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
            foreach ($path in @((Join-Path $agentRoot 'managed-stale\SKILL.md'), (Join-Path $userRoot 'managed-current\SKILL.md'), (Join-Path $userRoot 'unknown-skill\SKILL.md'), (Join-Path $env:CODEX_HOME 'skills\.system\system-skill\SKILL.md'), (Join-Path $pluginRoot 'plugin-skill\SKILL.md'))) { [IO.File]::WriteAllText($path, "---`nname: $([IO.Path]::GetFileName((Split-Path $path -Parent)))`ndescription: fixture`n---`n", [Text.UTF8Encoding]::new($false)) }
            New-Item -ItemType Junction -Path (Join-Path $userRoot 'managed-stale') -Target (Join-Path $agentRoot 'managed-stale') -Force | Out-Null
            $externalRoot = Join-Path $fixture 'external\external-skill'; New-Item -ItemType Directory -Force -Path $externalRoot | Out-Null; [IO.File]::WriteAllText((Join-Path $externalRoot 'SKILL.md'), "---`nname: external-skill`ndescription: fixture`n---`n", [Text.UTF8Encoding]::new($false)); New-Item -ItemType Junction -Path (Join-Path $userRoot 'external-skill') -Target $externalRoot -Force | Out-Null
            $snapshotPath = Join-Path $fixture 'host.json'; [IO.File]::WriteAllText($snapshotPath, (([pscustomobject]@{ captured_at = [datetimeoffset]::UtcNow.ToString('o'); coverage = 'complete'; skills = @([pscustomobject]@{ name = 'host-only'; path = 'host://skill'; entrypoint_hash = ('a' * 64); description_hash = ('b' * 64) }) }) | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
            $config = [pscustomobject]@{ skill_projection = [pscustomobject]@{ manifest_path = 'reports/current.json'; managed_source_path = 'agent'; user_skill_root = $userRoot; managed_link_includes = @('managed-current'); external_skill_inventory = [pscustomobject]@{ plugin_cache_path = $pluginRoot } } }
            $view = New-SkillSurfaceView -RepoRoot $fixture -Config $config -HostSnapshotPath $snapshotPath
            $view.pass | Should -BeTrue
            $view.surface_count | Should -Be 6
            @($view.surfaces.name) | Should -Be @('repo_supply', 'canonical_projection', 'user_skill_root', 'system', 'plugin_cache', 'host_visible')
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
            $config = [pscustomobject]@{ skill_projection = [pscustomobject]@{ manifest_path = 'reports/current.json'; managed_source_path = 'agent'; user_skill_root = 'user'; managed_link_includes = @(); external_skill_inventory = [pscustomobject]@{ plugin_cache_path = 'plugins' } } }
            $view = New-SkillSurfaceView -RepoRoot $fixture -Config $config -HostSnapshotPath $snapshotPath
            $view.pass | Should -BeFalse
            @($view.findings.code) | Should -Contain 'host_skill_identity_incomplete'
        }
        finally { if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force } }
    }
}
