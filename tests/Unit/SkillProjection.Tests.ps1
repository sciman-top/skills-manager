. $PSScriptRoot\..\..\skills.ps1

function New-ProjectionSkill([string]$RootPath, [string]$Folder, [string]$Name, [string]$Description = 'fixture') {
    $dir = Join-Path $RootPath $Folder
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Set-ContentUtf8 (Join-Path $dir 'SKILL.md') ("---`nname: {0}`ndescription: {1}`n---`n" -f $Name, $Description)
    return $dir
}

Describe 'Skill projection' {
    It 'selects one canonical path and records a real content conflict' {
        $high = Join-Path $TestDrive 'high'
        $low = Join-Path $TestDrive 'low'
        New-ProjectionSkill $high 'shared' 'shared' 'new' | Out-Null
        New-ProjectionSkill $low 'shared' 'shared' 'old' | Out-Null
        $plan = New-SkillProjectionPlan ([pscustomobject]@{
                sources = @(
                    [pscustomobject]@{ id = 'high'; path = $high; priority = 20; platforms = @('codex') }
                    [pscustomobject]@{ id = 'low'; path = $low; priority = 10; platforms = @('codex') }
                )
            })

        @($plan.canonical).Count | Should Be 1
        $plan.canonical[0].source_id | Should Be 'high'
        $plan.disabled[0].decision | Should Be 'conflict_priority_winner'
        @($plan.conflicts).Count | Should Be 1
    }

    It 'keeps every canonical skill active except an explicit alias' {
        $root = Join-Path $TestDrive 'alias'
        New-ProjectionSkill $root 'social' 'social' | Out-Null
        New-ProjectionSkill $root 'social-content' 'social-content' | Out-Null
        New-ProjectionSkill $root 'cold' 'cold' | Out-Null
        $plan = New-SkillProjectionPlan ([pscustomobject]@{
                aliases = @([pscustomobject]@{ name = 'social-content'; replacement = 'social' })
                sources = @([pscustomobject]@{ id = 'source'; path = $root; priority = 1; platforms = @('codex') })
            })

        @($plan.active.name | Sort-Object) | Should Be @('cold', 'social')
        @($plan.disabled | Where-Object decision -eq 'alias_replaced').name | Should Be 'social-content'
    }

    It 'uses one global metadata budget' {
        $root = Join-Path $TestDrive 'budget'
        New-ProjectionSkill $root 'large' 'large' ('x' * 80) | Out-Null
        $plan = New-SkillProjectionPlan ([pscustomobject]@{
                budget_limit_chars = 20
                external_metadata_reserve_chars = 0
                sources = @([pscustomobject]@{ id = 'source'; path = $root; priority = 1; platforms = @('codex') })
            })

        $plan.budget_pass | Should Be $false
        $plan.effective_budget_limit_chars | Should Be 20
        $plan.PSObject.Properties.Match('profile_budgets').Count | Should Be 0
    }

    It 'replaces only the managed TOML block' {
        $existing = @'
model = "gpt-5.6-sol"
# BEGIN skills-manager:skills-projection
[[skills.config]]
path = "C:\\old\\SKILL.md"
enabled = false
# END skills-manager:skills-projection
[features]
unified_exec = true
'@
        $toml = Build-CodexSkillsProjectionToml $existing @([pscustomobject]@{ path = 'C:\new\SKILL.md' })

        $toml | Should Match 'model = "gpt-5\.6-sol"'
        $toml | Should Match '\[features\]'
        $toml | Should Not Match 'C:\\\\old'
        $toml | Should Match ([regex]::Escape('C:\\new\\SKILL.md'))
        ([regex]::Matches($toml, 'BEGIN skills-manager:skills-projection')).Count | Should Be 1
    }

    It 'projects only explicitly included managed skills' {
        $oldDryRun = $script:DryRun
        try {
            $script:DryRun = $false
            $managed = Join-Path $TestDrive 'managed'
            $target = Join-Path $TestDrive 'target'
            $keep = New-ProjectionSkill $managed 'keep' 'keep'
            New-ProjectionSkill $managed 'cold' 'cold' | Out-Null
            $result = Sync-CodexManagedSkillLinks ([pscustomobject]@{
                    managed_source_path = $managed
                    user_skill_root = $target
                    managed_link_includes = @('keep')
                })

            $result.managed_link_count | Should Be 1
            (Get-ReparsePointTargetFullPath (Join-Path $target 'keep')) | Should Be ([IO.Path]::GetFullPath($keep))
            Test-Path -LiteralPath (Join-Path $target 'cold') | Should Be $false
        }
        finally { $script:DryRun = $oldDryRun }
    }

    It 'does not write config or manifest during dry-run' {
        $oldDryRun = $script:DryRun
        try {
            $script:DryRun = $true
            $root = Join-Path $TestDrive 'dry-source'
            New-ProjectionSkill $root 'demo' 'demo' | Out-Null
            $configPath = Join-Path $TestDrive 'dry\config.toml'
            $manifestPath = Join-Path $TestDrive 'dry\manifest.json'
            $result = Sync-CodexSkillProjection ([pscustomobject]@{
                    codex_config_path = $configPath
                    manifest_path = $manifestPath
                    sources = @([pscustomobject]@{ id = 'source'; path = $root; priority = 1; platforms = @('codex') })
                })

            $result.persisted | Should Be $false
            Test-Path -LiteralPath $configPath | Should Be $false
            Test-Path -LiteralPath $manifestPath | Should Be $false
        }
        finally { $script:DryRun = $oldDryRun }
    }

    It 'rolls back links, config, catalog, and manifest after an aggregate write failure' {
        $oldDryRun = $script:DryRun
        try {
            $script:DryRun = $false
            $managed = Join-Path $TestDrive 'rollback-managed'
            $target = Join-Path $TestDrive 'rollback-target'
            $router = New-ProjectionSkill $managed 'capability-router' 'capability-router'
            New-ProjectionSkill $managed 'demo' 'demo' | Out-Null
            $configPath = Join-Path $TestDrive 'rollback\config.toml'
            $manifestPath = Join-Path $TestDrive 'rollback\manifest.json'
            $catalogPath = Join-Path $router 'catalog.json'
            Set-ContentUtf8 $catalogPath 'catalog-before'
            Set-ContentUtf8 $configPath 'model = "fixture"'
            Set-ContentUtf8 $manifestPath 'manifest-before'
            $projection = [pscustomobject]@{
                managed_source_path = $managed
                user_skill_root = $target
                codex_config_path = $configPath
                manifest_path = $manifestPath
                sources = @([pscustomobject]@{ id = 'managed'; path = $target; priority = 1; platforms = @('codex') })
            }
            Mock Set-ContentUtf8 { throw 'injected manifest write failure' } -ParameterFilter {
                [string]::Equals([IO.Path]::GetFullPath($path), [IO.Path]::GetFullPath($manifestPath), [StringComparison]::OrdinalIgnoreCase)
            }

            { Sync-CodexSkillProjection $projection } | Should Throw
            Get-ContentUtf8 $catalogPath | Should Be 'catalog-before'
            Get-ContentUtf8 $configPath | Should Be 'model = "fixture"'
            Get-ContentUtf8 $manifestPath | Should Be 'manifest-before'
            Test-Path -LiteralPath (Join-Path $target 'demo') | Should Be $false
        }
        finally { $script:DryRun = $oldDryRun }
    }
}
