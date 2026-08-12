. $PSScriptRoot\..\..\skills.ps1

function New-RoutingSkillEntry([string]$root, [string]$name, [string]$description, [string]$body = '') {
    $dir = Join-Path $root $name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $path = Join-Path $dir 'SKILL.md'
    Set-ContentUtf8 $path ("---`nname: {0}`ndescription: {1}`n---`n{2}" -f $name, $description, $body)
    return [pscustomobject]@{ name = $name; description = $description; path = $path; is_system = $false }
}

function New-RoutingPolicyFile([string]$path, $groups, $rules = @(), $conflicts = @(), [int]$schemaVersion = 1) {
    $policy = [ordered]@{
        schema_version = $schemaVersion
        mode = 'observe'
        trigger_rules = @($rules)
        groups = @($groups)
        conflicts = @($conflicts)
    }
    Set-ContentUtf8 $path ($policy | ConvertTo-Json -Depth 12)
}

Describe 'Skill routing governance' {
    It 'verifies tracked routing declarations when generated agent output is not materialized' {
        $configPath = Join-Path $TestDrive 'source-only-skills.json'
        $policyPath = Join-Path $TestDrive 'source-only-policy.json'
        $emptyUserRoot = Join-Path $TestDrive 'empty-user-root'
        New-Item -ItemType Directory -Path $emptyUserRoot -Force | Out-Null
        New-RoutingPolicyFile $policyPath @(
            [ordered]@{
                id = 'source-flow'
                purpose = 'source-only fixture'
                router = 'router'
                selection_policy = 'router then worker'
                members = @(
                    [ordered]@{ name = 'router'; role = 'router'; activation = 'entry' }
                    [ordered]@{ name = 'worker'; role = 'workflow'; activation = 'implementation' }
                )
                external_members = @()
            }
        )
        $fixtureConfig = [ordered]@{
            schema_version = 1
            vendors = @()
            mappings = @(
                [ordered]@{ vendor = 'fixture'; from = 'router-source'; to = 'router' }
                [ordered]@{ vendor = 'fixture'; from = 'worker-source'; to = 'worker' }
            )
            imports = @()
            targets = @()
            mcp_servers = @()
            skill_projection = [ordered]@{
                enabled = $true
                active_profile = 'default'
                user_skill_root = $emptyUserRoot
                routing_policy_path = $policyPath
                external_skill_inventory = [ordered]@{ enabled = $false }
                resident_names = @('router')
                profiles = [ordered]@{ default = [ordered]@{ enabled_names = @('worker') } }
            }
        }
        Set-ContentUtf8 $configPath ($fixtureConfig | ConvertTo-Json -Depth 12)

        $scriptPath = Join-Path $PSScriptRoot '..\..\scripts\verify-skill-routing.ps1'
        $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -ConfigPath $configPath -PolicyPath $policyPath -Json 2>&1)
        $exitCode = $LASTEXITCODE
        $report = ($output -join "`n") | ConvertFrom-Json

        $report.error | Should BeNullOrEmpty
        $exitCode | Should Be 0
        $report.ok | Should Be $true
        $report.materialization_status | Should Be 'source_only'
        $report.source_declared_skill_count | Should Be 2
        $report.active_skill_count | Should Be 2
    }

    It 'Accepts routing policy schema v2 and rejects unknown future versions' {
        $v2 = Join-Path $TestDrive 'policy-v2.json'
        New-RoutingPolicyFile $v2 @() @() @() 2
        (Get-SkillRoutingPolicy $v2).schema_version | Should Be 2

        $future = Join-Path $TestDrive 'policy-v3.json'
        New-RoutingPolicyFile $future @() @() @() 3
        { Get-SkillRoutingPolicy $future } | Should Throw
    }

    It 'Reads only enabled plugin ids from Codex TOML' {
        $config = Join-Path $TestDrive 'config.toml'
        Set-ContentUtf8 $config @'
[plugins."presentations@openai-primary-runtime"]
enabled = true

[plugins."github@openai-curated"]
enabled = false

[plugins.chrome@openai-bundled]
enabled = true # current browser state
'@

        @(Get-CodexEnabledPluginIds $config) -join ',' | Should Be 'chrome@openai-bundled,presentations@openai-primary-runtime'
    }

    It 'Inventories the newest usable enabled plugin version' {
        $config = Join-Path $TestDrive 'config.toml'
        $cache = Join-Path $TestDrive 'cache'
        Set-ContentUtf8 $config "[plugins.`"demo@market`"]`nenabled = true`n"
        $old = Join-Path $cache 'market\demo\1.0.0\skills\old'
        $new = Join-Path $cache 'market\demo\2.0.0\skills\current'
        New-Item -ItemType Directory -Path $old, $new -Force | Out-Null
        Set-ContentUtf8 (Join-Path $old 'SKILL.md') "---`nname: old`ndescription: old`n---`n"
        Set-ContentUtf8 (Join-Path $new 'SKILL.md') "---`nname: current`ndescription: current description`n---`n"
        (Get-Item (Join-Path $old '..\..')).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-10)
        (Get-Item (Join-Path $new '..\..')).LastWriteTimeUtc = [DateTime]::UtcNow
        $projection = [pscustomobject]@{
            codex_config_path = $config
            external_skill_inventory = [pscustomobject]@{ enabled = $true; plugin_cache_path = $cache }
        }

        $inventory = Get-CodexExternalSkillInventory $projection

        $inventory.skill_count | Should Be 1
        $inventory.skills[0].name | Should Be 'current'
        $inventory.skills[0].qualified_name | Should Be 'demo@market::current'
        $inventory.metadata_chars | Should Be ('current'.Length + 'current description'.Length)
    }

    It 'Rejects plugin ids that could escape the cache root' {
        $config = Join-Path $TestDrive 'unsafe-config.toml'
        $cache = Join-Path $TestDrive 'unsafe-cache'
        New-Item -ItemType Directory -Path $cache -Force | Out-Null
        Set-ContentUtf8 $config "[plugins.`"../outside@market`"]`nenabled = true`n`n[plugins.`"C:@market`"]`nenabled = true`n"
        $projection = [pscustomobject]@{
            codex_config_path = $config
            external_skill_inventory = [pscustomobject]@{ enabled = $true; plugin_cache_path = $cache }
        }

        $inventory = Get-CodexExternalSkillInventory $projection

        $inventory.skill_count | Should Be 0
        @($inventory.warnings | Where-Object code -eq 'unsafe_plugin_id').Count | Should Be 2
    }

    It 'Supports a hashtable external inventory config' {
        $config = Join-Path $TestDrive 'hashtable-config.toml'
        $cache = Join-Path $TestDrive 'hashtable-cache'
        Set-ContentUtf8 $config "[plugins.`"demo@market`"]`nenabled = true`n"
        $skillDir = Join-Path $cache 'market\demo\1.0.0\skills\demo-skill'
        New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
        Set-ContentUtf8 (Join-Path $skillDir 'SKILL.md') "---`nname: demo-skill`ndescription: Demo.`n---`n"
        $projection = [pscustomobject]@{
            codex_config_path = $config
            external_skill_inventory = @{ enabled = $true; plugin_cache_path = $cache }
        }

        $inventory = Get-CodexExternalSkillInventory $projection

        $inventory.skill_count | Should Be 1
        $inventory.skills[0].qualified_name | Should Be 'demo@market::demo-skill'
    }

    It 'Reports strong triggers and coactive workflow conflicts without blocking observe mode' {
        $root = Join-Path $TestDrive 'skills'
        $router = New-RoutingSkillEntry $root 'router' 'You MUST use this before any change.'
        $worker = New-RoutingSkillEntry $root 'worker' 'Worker.' 'Each successful increment gets its own commit.'
        $policyPath = Join-Path $TestDrive 'policy.json'
        New-RoutingPolicyFile $policyPath @(
            [ordered]@{
                id = 'flow'
                purpose = 'fixture flow'
                router = 'router'
                selection_policy = 'router then worker'
                members = @(
                    [ordered]@{ name = 'router'; role = 'router'; activation = 'entry' }
                    [ordered]@{ name = 'worker'; role = 'workflow'; activation = 'implementation' }
                )
                external_members = @()
            }
        ) @(
            [ordered]@{ id = 'mandatory'; severity = 'warning'; scan_scope = 'description'; pattern = '\bMUST\b'; resolution = 'route narrowly' }
            [ordered]@{ id = 'commit'; severity = 'warning'; scan_scope = 'full'; pattern = 'gets its own commit'; resolution = 'require authorization' }
        ) @(
            [ordered]@{ id = 'coactive'; severity = 'warning'; members = @('router', 'worker'); resolution = 'select by stage' }
        )
        $projection = [pscustomobject]@{ routing_policy_path = $policyPath }

        $report = New-SkillRoutingReport $projection @($router, $worker) @($router, $worker) @()

        $report.enabled | Should Be $true
        $report.blocking | Should Be $false
        @($report.findings | Where-Object code -eq 'strong_trigger_signal').Count | Should Be 2
        @($report.findings | Where-Object code -eq 'coactive_contract_conflict').Count | Should Be 1
        @($report.findings | Where-Object code -eq 'unrouted_strong_trigger').Count | Should Be 0
    }

    It 'Rejects routing policy members that are not installed' {
        $root = Join-Path $TestDrive 'unknown-member'
        $router = New-RoutingSkillEntry $root 'router' 'Router.'
        $policyPath = Join-Path $TestDrive 'unknown-policy.json'
        New-RoutingPolicyFile $policyPath @(
            [ordered]@{
                id = 'flow'
                purpose = 'fixture flow'
                router = 'router'
                selection_policy = 'fixture'
                members = @(
                    [ordered]@{ name = 'router'; role = 'router'; activation = 'entry' }
                    [ordered]@{ name = 'missing'; role = 'executor'; activation = 'work' }
                )
                external_members = @()
            }
        )
        $projection = [pscustomobject]@{ routing_policy_path = $policyPath }

        { New-SkillRoutingReport $projection @($router) @($router) @() } | Should Throw
    }

    It 'Rejects a router member whose role is not router' {
        $root = Join-Path $TestDrive 'invalid-router-role'
        $worker = New-RoutingSkillEntry $root 'worker' 'Worker.'
        $policyPath = Join-Path $TestDrive 'invalid-router-role-policy.json'
        New-RoutingPolicyFile $policyPath @(
            [ordered]@{
                id = 'flow'
                purpose = 'fixture flow'
                router = 'worker'
                selection_policy = 'fixture'
                members = @([ordered]@{ name = 'worker'; role = 'executor'; activation = 'work' })
                external_members = @()
            }
        )
        $projection = [pscustomobject]@{ routing_policy_path = $policyPath }

        { New-SkillRoutingReport $projection @($worker) @($worker) @() } | Should Throw
    }

    It 'Uses actual external metadata when it exceeds the configured reserve' {
        $source = Join-Path $TestDrive 'budget-skills'
        New-RoutingSkillEntry $source 'local' 'local' | Out-Null
        $config = Join-Path $TestDrive 'budget-config.toml'
        $cache = Join-Path $TestDrive 'budget-cache'
        Set-ContentUtf8 $config "[plugins.`"demo@market`"]`nenabled = true`n"
        $externalDir = Join-Path $cache 'market\demo\1.0.0\skills\external'
        New-Item -ItemType Directory -Path $externalDir -Force | Out-Null
        Set-ContentUtf8 (Join-Path $externalDir 'SKILL.md') "---`nname: external`ndescription: a much longer external description`n---`n"
        $projection = [pscustomobject]@{
            enabled = $true
            codex_config_path = $config
            external_metadata_reserve_chars = 5
            external_skill_inventory = [pscustomobject]@{ enabled = $true; plugin_cache_path = $cache }
            sources = @([pscustomobject]@{ id = 'fixture'; path = $source; priority = 1; platforms = @('codex') })
        }

        $projectionPlan = New-SkillProjectionPlan $projection

        $projectionPlan.external_skill_count | Should Be 1
        $projectionPlan.external_skill_metadata_chars | Should BeGreaterThan 5
        $projectionPlan.effective_external_metadata_chars | Should Be $projectionPlan.external_skill_metadata_chars
        $projectionPlan.estimated_metadata_chars | Should Be ($projectionPlan.skill_metadata_chars + $projectionPlan.external_skill_metadata_chars)
    }
}
