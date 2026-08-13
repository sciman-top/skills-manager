BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src\Infrastructure\CodexCli.ps1')
}

Describe 'Codex CLI plugin inventory' {
    It 'includes only installed enabled plugins and reads their reported source paths' {
        $enabledRoot = Join-Path $TestDrive 'enabled'; $disabledRoot = Join-Path $TestDrive 'disabled'
        foreach ($root in @($enabledRoot, $disabledRoot)) { New-Item -ItemType Directory -Path (Join-Path $root 'skills\demo') -Force | Out-Null; "---`nname: demo`ndescription: fixture`n---" | Set-Content -LiteralPath (Join-Path $root 'skills\demo\SKILL.md') }
        Mock Invoke-CodexCliJson { [pscustomobject]@{ installed = @(
                    [pscustomobject]@{ pluginId='enabled@market'; name='enabled'; marketplaceName='market'; version='2'; installed=$true; enabled=$true; source=[pscustomobject]@{ path=$enabledRoot } },
                    [pscustomobject]@{ pluginId='disabled@market'; name='disabled'; marketplaceName='market'; version='3'; installed=$true; enabled=$false; source=[pscustomobject]@{ path=$disabledRoot } }) } }

        $result = Get-CodexPluginSkillInventory
        $result.coverage | Should -Be 'complete'
        $result.enabled_plugin_ids | Should -Be @('enabled@market')
        @($result.skills.plugin_id) | Should -Be @('enabled@market')
    }

    It 'reports platform_na instead of guessing from cache when CLI JSON is unavailable' {
        Mock Invoke-CodexCliJson { throw 'codex_cli_unavailable' }
        $result = Get-CodexPluginSkillInventory
        $result.coverage | Should -Be 'platform_na'
        @($result.warnings.code) | Should -Contain 'codex_plugin_inventory_unavailable'
    }
}
