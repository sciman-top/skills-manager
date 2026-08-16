BeforeAll {
    . $PSScriptRoot\..\..\skills.ps1

    function New-ProjectionSkill([string]$RootPath, [string]$Folder, [string]$Name, [string]$Description = 'fixture') {
        $dir = Join-Path $RootPath $Folder
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-ContentUtf8 (Join-Path $dir 'SKILL.md') ("---`nname: {0}`ndescription: {1}`n---`n" -f $Name, $Description)
        return $dir
    }

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

        @($plan.canonical).Count | Should -Be 1
        $plan.canonical[0].source_id | Should -Be 'high'
        $plan.disabled[0].decision | Should -Be 'conflict_priority_winner'
        @($plan.conflicts).Count | Should -Be 1
    }

    It 'reports inventory size without enforcing a second host metadata budget' {
        $root = Join-Path $TestDrive 'budget'
        New-ProjectionSkill $root 'large' 'large' ('x' * 80) | Out-Null
        $plan = New-SkillProjectionPlan ([pscustomobject]@{
                sources = @([pscustomobject]@{ id = 'source'; path = $root; priority = 1; platforms = @('codex') })
            })

        $plan.estimated_metadata_chars | Should -BeGreaterThan 80
        $plan.PSObject.Properties.Match('budget_pass').Count | Should -Be 0
        $plan.PSObject.Properties.Match('budget_limit_chars').Count | Should -Be 0
    }

    It 'keeps projection fingerprints stable across native execution ids' {
        $root = Join-Path $TestDrive 'fingerprint'
        $skillDir = New-ProjectionSkill $root 'demo' 'demo'
        $plan = New-SkillProjectionPlan ([pscustomobject]@{
                sources = @([pscustomobject]@{ id = 'source'; path = $root; priority = 1; platforms = @('codex') })
            })
        $targetRoot = Join-Path $TestDrive 'native-target'
        $nativeSkill = [pscustomobject]@{
            name = 'demo'; source_path = (Join-Path $skillDir 'SKILL.md'); target_path = (Join-Path $targetRoot 'demo\SKILL.md')
            content_hash = 'content-a'; metadata_hash = 'metadata-a'
        }
        $first = [pscustomobject]@{ plan_id = 'nsp-first'; target_root = $targetRoot; skills = @($nativeSkill); removals = @() }
        $secondSkill = [pscustomobject]@{
            name = 'demo'; source_path = (Join-Path $skillDir 'SKILL.md'); target_path = (Join-Path $targetRoot 'demo\SKILL.md')
            content_hash = 'content-a'; metadata_hash = 'metadata-a'
        }
        $second = [pscustomobject]@{ plan_id = 'nsp-second'; target_root = $targetRoot; skills = @($secondSkill); removals = @() }

        (Get-SkillProjectionPlanFingerprint $plan $first) | Should -Be (Get-SkillProjectionPlanFingerprint $plan $second)
        $second.skills[0].content_hash = 'content-b'
        (Get-SkillProjectionPlanFingerprint $plan $first) | Should -Not -Be (Get-SkillProjectionPlanFingerprint $plan $second)
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

        $toml | Should -Match 'model = "gpt-5\.6-sol"'
        $toml | Should -Match '\[features\]'
        $toml | Should -Not -Match 'C:\\\\old'
        $toml | Should -Match ([regex]::Escape('C:\\new\\SKILL.md'))
        ([regex]::Matches($toml, 'BEGIN skills-manager:skills-projection')).Count | Should -Be 1
    }

    It 'does not write config or manifest during dry-run' {
        $oldDryRun = $DryRun
        try {
            $DryRun = $true
            $root = Join-Path $TestDrive 'dry-source'
            New-ProjectionSkill $root 'demo' 'demo' | Out-Null
            $configPath = Join-Path $TestDrive 'dry\config.toml'
            $manifestPath = Join-Path $TestDrive 'dry\manifest.json'
            $result = Sync-CodexSkillProjection ([pscustomobject]@{
                    codex_config_path = $configPath
                    manifest_path = $manifestPath
                    sources = @([pscustomobject]@{ id = 'source'; path = $root; priority = 1; platforms = @('codex') })
                })

            $result.persisted | Should -Be $false
            Test-Path -LiteralPath $configPath | Should -Be $false
            Test-Path -LiteralPath $manifestPath | Should -Be $false
        }
        finally { $DryRun = $oldDryRun }
    }

    It 'projects the neutral catalog beside the portable capability router' {
        $oldDryRun = $DryRun
        try {
            $DryRun = $false
            $managed = Join-Path $TestDrive 'portable-catalog-managed'
            New-ProjectionSkill $managed 'capability-router' 'capability-router' | Out-Null
            New-ProjectionSkill $managed 'demo' 'demo' | Out-Null
            $policy = [pscustomobject]@{
                groups = @([pscustomobject]@{
                        id = 'ambient-policy'
                        purpose = 'must not leak'
                        selection_policy = 'must not leak'
                        members = @([pscustomobject]@{ name = 'demo'; role = 'ambient'; activation = 'ambient'; negative_activation = 'ambient' })
                    })
            }
            $catalogPath = Join-Path $managed '.skills-manager\catalog.json'
            $projection = [pscustomobject]@{ managed_source_path = $managed; discovery_catalog = [pscustomobject]@{ catalog_path = $catalogPath } }

            $result = Sync-SkillDiscoveryCatalog $projection
            $portablePath = Join-Path $managed 'capability-router\catalog.json'

            $result.changed | Should -BeTrue
            $result.portable_path | Should -Be ([IO.Path]::GetFullPath($portablePath))
            Test-Path -LiteralPath $catalogPath -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath $portablePath -PathType Leaf | Should -BeTrue
            (Get-ContentUtf8 $portablePath) | Should -Be (Get-ContentUtf8 $catalogPath)
            $catalog = Get-ContentUtf8 $catalogPath | ConvertFrom-Json
            $catalog.skills[0].load_side_effect | Should -Be 'read_only'
            $catalog.skills[0].side_effect | Should -Be 'unknown'
            @($catalog.skills | Where-Object name -eq 'demo')[0].routing_rules.Count | Should -Be 0
            $catalog.catalog_fingerprint | Should -Match '^[0-9a-f]{64}$'
        }
        finally { $DryRun = $oldDryRun }
    }

    It 'rejects a discovery domain membership that is absent from the canonical inventory' {
        $managed = Join-Path $TestDrive 'dangling-membership-managed'
        New-ProjectionSkill $managed 'demo' 'demo' | Out-Null
        $projection = [pscustomobject]@{
            managed_source_path = $managed
            discovery_catalog = [pscustomobject]@{
                domain_memberships = [pscustomobject]@{ engineering = @('demo', 'missing-canonical-skill') }
            }
        }

        { New-SkillDiscoveryCatalogDocument $projection } | Should -Throw '*missing-canonical-skill*'
    }

    It 'rolls back links, config, neutral catalog, and manifest after an aggregate write failure' {
        $oldDryRun = $DryRun
        try {
            $DryRun = $false
            $managed = Join-Path $TestDrive 'rollback-managed'
            $target = Join-Path $TestDrive 'rollback-target'
            New-ProjectionSkill $managed 'capability-router' 'capability-router' | Out-Null
            New-ProjectionSkill $managed 'demo' 'demo' | Out-Null
            $configPath = Join-Path $TestDrive 'rollback\config.toml'
            $manifestPath = Join-Path $TestDrive 'rollback\manifest.json'
            $catalogPath = Join-Path $managed '.skills-manager\catalog.json'
            Set-ContentUtf8 $catalogPath 'catalog-before'
            Set-ContentUtf8 $configPath 'model = "fixture"'
            Set-ContentUtf8 $manifestPath 'manifest-before'
            $projection = [pscustomobject]@{
                managed_source_path = $managed
                user_skill_root = $target
                codex_config_path = $configPath
                manifest_path = $manifestPath
                sources = @([pscustomobject]@{ id = 'managed'; path = $target; priority = 1; platforms = @('codex') })
                discovery_catalog = [pscustomobject]@{ catalog_path = $catalogPath }
            }
            Mock Set-ContentUtf8 { throw 'injected manifest write failure' } -ParameterFilter {
                [string]::Equals([IO.Path]::GetFullPath($path), [IO.Path]::GetFullPath($manifestPath), [StringComparison]::OrdinalIgnoreCase)
            }

            { Sync-CodexSkillProjection $projection } | Should -Throw
            Get-ContentUtf8 $catalogPath | Should -Be 'catalog-before'
            Test-Path -LiteralPath (Join-Path $managed 'capability-router\catalog.json') | Should -BeFalse
            Get-ContentUtf8 $configPath | Should -Be 'model = "fixture"'
            Get-ContentUtf8 $manifestPath | Should -Be 'manifest-before'
            Test-Path -LiteralPath (Join-Path $target 'demo') | Should -Be $false
        }
        finally { $DryRun = $oldDryRun }
    }
}
