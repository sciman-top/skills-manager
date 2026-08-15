BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src\Infrastructure\CodexCli.ps1')
}

Describe 'Codex CLI plugin inventory' {
    It 'accepts valid JSON from a nonzero exit only when explicitly allowed' {
        $fixtureCodex = Join-Path $TestDrive 'codex-fixture.ps1'
        [IO.File]::WriteAllText($fixtureCodex, "Write-Output '{`"status`":`"degraded`"}'`n`$global:LASTEXITCODE = 1`n", [Text.UTF8Encoding]::new($false))
        Mock Get-Command { [pscustomobject]@{ Source = $fixtureCodex } } -ParameterFilter { $Name -eq 'codex' }

        { Invoke-CodexCliJson -Arguments @('doctor', '--json') } | Should -Throw 'codex_cli_failed*'
        (Invoke-CodexCliJson -Arguments @('doctor', '--json') -AllowNonZeroExitWithJson).status | Should -Be 'degraded'
    }

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

Describe 'Codex CLI host observation' {
    It 'returns redacted MCP and doctor facts without claiming host load' {
        Mock Invoke-CodexCliJson {
            param([string[]]$Arguments, [switch]$AllowNonZeroExitWithJson)
            if ($Arguments[0] -eq 'mcp') { return @([pscustomobject]@{ name='docs'; enabled=$true; disabled_reason=$null; auth_status='unsupported'; transport=[pscustomobject]@{ type='stdio'; command='secret-command'; env=[pscustomobject]@{ TOKEN='secret' } } }) }
            if ($Arguments[0] -eq 'doctor') { return [pscustomobject]@{ schemaVersion=1; codexVersion='1.2.3'; overallStatus='ok'; checks=@([pscustomobject]@{ id='config.load'; category='config'; status='ok'; summary='loaded'; details=[pscustomobject]@{ secret='hidden' } }) } }
            throw 'unexpected command'
        }
        $plugins = [pscustomobject]@{ authority='fixture'; freshness='fresh'; coverage='complete'; enabled_plugin_ids=@('demo@market'); skill_count=1; warnings=@() }
        $result = Get-CodexHostObservation -PluginInventory $plugins -ExpectedMcpServers @([pscustomobject]@{ name='docs' }, [pscustomobject]@{ name='missing' })

        $result.truth_boundary | Should -Be 'read_only_cli_observation_not_host_loaded'
        @($result.configured_not_observed) | Should -Be @('missing')
        $result.mcp.servers[0].PSObject.Properties.Name | Should -Not -Contain 'transport'
        $result.doctor.checks[0].PSObject.Properties.Name | Should -Not -Contain 'details'
        $result.provider_calls | Should -Be 0
        $result.native_mutations | Should -Be 0
        $result.writes | Should -Be 0
        Should -Invoke Invoke-CodexCliJson -ParameterFilter { $Arguments[0] -eq 'doctor' -and $AllowNonZeroExitWithJson }
    }

    It 'keeps unavailable MCP and doctor commands as platform_na observations' {
        Mock Invoke-CodexCliJson { throw 'unavailable' }
        (Get-CodexMcpObservation).coverage | Should -Be 'platform_na'
        (Get-CodexDoctorObservation).coverage | Should -Be 'platform_na'
    }
}
