. $PSScriptRoot\..\..\skills.ps1

function New-ProjectionSkill([string]$root, [string]$dir, [string]$name, [string]$description = "fixture") {
    $skillDir = Join-Path $root $dir
    New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
    Set-ContentUtf8 (Join-Path $skillDir "SKILL.md") ("---`nname: {0}`ndescription: {1}`n---`n" -f $name, $description)
    return $skillDir
}

Describe "Skill projection" {
    Context "New-SkillProjectionPlan" {
        It "Keeps the higher-priority path for same-content duplicates" {
            $managed = Join-Path $TestDrive "managed-same"
            $legacy = Join-Path $TestDrive "legacy-same"
            New-ProjectionSkill $managed "shared" "shared-skill" | Out-Null
            New-ProjectionSkill $legacy "shared-copy" "shared-skill" | Out-Null

            $cfg = [pscustomobject]@{
                enabled = $true
                sources = @(
                    [pscustomobject]@{ id = "managed"; path = $managed; priority = 200; platforms = @("codex") }
                    [pscustomobject]@{ id = "legacy"; path = $legacy; priority = 100; platforms = @("codex") }
                )
            }

            $plan = New-SkillProjectionPlan $cfg

            @($plan.skills).Count | Should Be 2
            @($plan.disabled).Count | Should Be 1
            $plan.disabled[0].source_id | Should Be "legacy"
            $plan.disabled[0].decision | Should Be "duplicate_same_content"
            @($plan.unique_names).Count | Should Be 1
        }

        It "Keeps the higher-priority path and records different-content conflicts" {
            $managed = Join-Path $TestDrive "managed-conflict"
            $legacy = Join-Path $TestDrive "legacy-conflict"
            New-ProjectionSkill $managed "shared" "shared-skill" "managed version" | Out-Null
            New-ProjectionSkill $legacy "shared-copy" "shared-skill" "legacy version" | Out-Null

            $cfg = [pscustomobject]@{
                enabled = $true
                sources = @(
                    [pscustomobject]@{ id = "managed"; path = $managed; priority = 200; platforms = @("codex") }
                    [pscustomobject]@{ id = "legacy"; path = $legacy; priority = 100; platforms = @("codex") }
                )
            }

            $plan = New-SkillProjectionPlan $cfg

            @($plan.conflicts).Count | Should Be 1
            $plan.conflicts[0].name | Should Be "shared-skill"
            $plan.disabled[0].source_id | Should Be "legacy"
            $plan.disabled[0].decision | Should Be "conflict_priority_winner"
        }

        It "Leaves skills that only exist in a lower-priority source enabled" {
            $managed = Join-Path $TestDrive "managed-unique"
            $legacy = Join-Path $TestDrive "legacy-unique"
            New-ProjectionSkill $managed "managed-only" "managed-only" | Out-Null
            New-ProjectionSkill $legacy "legacy-only" "legacy-only" | Out-Null

            $cfg = [pscustomobject]@{
                enabled = $true
                sources = @(
                    [pscustomobject]@{ id = "managed"; path = $managed; priority = 200; platforms = @("codex") }
                    [pscustomobject]@{ id = "legacy"; path = $legacy; priority = 100; platforms = @("codex") }
                )
            }

            $plan = New-SkillProjectionPlan $cfg

            @($plan.disabled).Count | Should Be 0
            @($plan.unique_names | Sort-Object) -join "," | Should Be "legacy-only,managed-only"
        }

        It "Prefers the .system copy inside the same root" {
            $root = Join-Path $TestDrive "managed-system"
            New-ProjectionSkill $root "ordinary" "openai-docs" "ordinary" | Out-Null
            New-ProjectionSkill (Join-Path $root ".system") "openai-docs" "openai-docs" "system" | Out-Null

            $cfg = [pscustomobject]@{
                enabled = $true
                sources = @([pscustomobject]@{ id = "managed"; path = $root; priority = 200; platforms = @("codex") })
            }

            $plan = New-SkillProjectionPlan $cfg

            @($plan.disabled).Count | Should Be 1
            $plan.disabled[0].path | Should Match "ordinary\\SKILL\.md$"
            $plan.canonical[0].path | Should Match "\.system\\openai-docs\\SKILL\.md$"
        }

        It "Disables migrated aliases and points them at the replacement" {
            $managed = Join-Path $TestDrive "managed-alias"
            $legacy = Join-Path $TestDrive "legacy-alias"
            New-ProjectionSkill $managed "social" "social" "current" | Out-Null
            New-ProjectionSkill $legacy "social-content" "social-content" "legacy" | Out-Null

            $cfg = [pscustomobject]@{
                enabled = $true
                aliases = @([pscustomobject]@{ name = "social-content"; replacement = "social" })
                sources = @(
                    [pscustomobject]@{ id = "managed"; path = $managed; priority = 200; platforms = @("codex") }
                    [pscustomobject]@{ id = "legacy"; path = $legacy; priority = 100; platforms = @("codex") }
                )
            }

            $plan = New-SkillProjectionPlan $cfg

            @($plan.active).Count | Should Be 1
            $plan.active[0].name | Should Be "social"
            $alias = @($plan.disabled | Where-Object decision -eq "alias_replaced")[0]
            $alias.name | Should Be "social-content"
            $alias.replacement | Should Be "social"
            $alias.canonical_path | Should Match "social\\SKILL\.md$"
        }

        It "Keeps system skills and only profile-enabled canonical skills active" {
            $root = Join-Path $TestDrive "profile"
            New-ProjectionSkill $root "always" "always" | Out-Null
            New-ProjectionSkill $root "optional" "optional" | Out-Null
            New-ProjectionSkill (Join-Path $root ".system") "system" "system" | Out-Null
            $cfg = [pscustomobject]@{
                enabled = $true
                active_profile = "default"
                profiles = [pscustomobject]@{
                    default = [pscustomobject]@{ enabled_names = @("always") }
                }
                sources = @([pscustomobject]@{ id = "managed"; path = $root; priority = 200; platforms = @("codex") })
            }

            $plan = New-SkillProjectionPlan $cfg

            @($plan.active | ForEach-Object name | Sort-Object) -join "," | Should Be "always,system"
            @($plan.disabled | Where-Object decision -eq "profile_excluded" | ForEach-Object name) | Should Be @("optional")
            $plan.active_profile | Should Be "default"
        }

        It "Includes the external reserve in the metadata budget verdict" {
            $root = Join-Path $TestDrive "budget"
            New-ProjectionSkill $root "large" "large" ("x" * 90) | Out-Null
            $cfg = [pscustomobject]@{
                enabled = $true
                budget_limit_chars = 100
                external_metadata_reserve_chars = 10
                sources = @([pscustomobject]@{ id = "managed"; path = $root; priority = 200; platforms = @("codex") })
            }

            $plan = New-SkillProjectionPlan $cfg

            $plan.skill_metadata_chars | Should Be 95
            $plan.estimated_metadata_chars | Should Be 105
            $plan.budget_pass | Should Be $false
        }

        It "Reports every profile budget even when the active profile passes" {
            $root = Join-Path $TestDrive "all-profile-budgets"
            New-ProjectionSkill $root "small" "small" "small" | Out-Null
            New-ProjectionSkill $root "large" "large" ("x" * 90) | Out-Null
            $cfg = [pscustomobject]@{
                enabled = $true
                active_profile = "default"
                budget_limit_chars = 100
                external_metadata_reserve_chars = 0
                profiles = [pscustomobject]@{
                    default = [pscustomobject]@{ enabled_names = @("small") }
                    oversized = [pscustomobject]@{ enabled_names = @("small", "large") }
                }
                sources = @([pscustomobject]@{ id = "managed"; path = $root; priority = 200; platforms = @("codex") })
            }

            $plan = New-SkillProjectionPlan $cfg

            @($plan.profile_budgets).Count | Should Be 2
            ($plan.profile_budgets | Where-Object profile -eq "default").budget_pass | Should Be $true
            ($plan.profile_budgets | Where-Object profile -eq "oversized").budget_pass | Should Be $false
            $plan.all_profiles_budget_pass | Should Be $false
            $plan.budget_pass | Should Be $true
        }
    }

    Context "Build-CodexSkillsProjectionToml" {
        It "Replaces only the managed block and preserves user config" {
            $existing = @'
model = "gpt-5.6-sol"

# BEGIN skills-manager:skills-projection
[[skills.config]]
path = "C:\\old\\SKILL.md"
enabled = false
# END skills-manager:skills-projection

[windows]
sandbox = "elevated"
'@
            $disabled = @([pscustomobject]@{ path = "C:\new\SKILL.md" })

            $toml = Build-CodexSkillsProjectionToml $existing $disabled

            $toml | Should Match 'model = "gpt-5\.6-sol"'
            $toml | Should Match '\[windows\]'
            $toml | Should Not Match 'C:\\\\old'
            $toml | Should Match 'C:\\\\new\\\\SKILL\.md'
            ([regex]::Matches($toml, 'BEGIN skills-manager:skills-projection')).Count | Should Be 1
        }
    }

    Context "Sync-CodexSkillProjection" {
        It "Fails closed when an inactive profile exceeds the metadata budget" {
            $oldDryRun = $script:DryRun
            try {
                $profileRoot = Join-Path $TestDrive "inactive-profile-budget"
                New-ProjectionSkill $profileRoot "small" "small" "small" | Out-Null
                New-ProjectionSkill $profileRoot "large" "large" ("x" * 90) | Out-Null
                $script:DryRun = $true
                $projection = [pscustomobject]@{
                    enabled = $true
                    active_profile = "default"
                    budget_limit_chars = 100
                    external_metadata_reserve_chars = 0
                    profiles = [pscustomobject]@{
                        default = [pscustomobject]@{ enabled_names = @("small") }
                        oversized = [pscustomobject]@{ enabled_names = @("small", "large") }
                    }
                    sources = @([pscustomobject]@{ id = "managed"; path = $profileRoot; priority = 200; platforms = @("codex") })
                }

                (Test-Path -LiteralPath (Join-Path $profileRoot "small\SKILL.md") -PathType Leaf) | Should Be $true
                @((Get-SkillProjectionSourceEntries $projection.sources[0] 0) | ForEach-Object name | Sort-Object) -join "," | Should Be "large,small"
                $preflightPlan = New-SkillProjectionPlan $projection
                @($preflightPlan.canonical).Count | Should Be 2
                { Sync-CodexSkillProjection $projection } | Should Throw
            }
            finally {
                $script:DryRun = $oldDryRun
            }
        }

        It "Does not write config or manifest during dry-run" {
            $oldDryRun = $script:DryRun
            try {
                $script:DryRun = $true
                $source = Join-Path $TestDrive "dry-source"
                New-ProjectionSkill $source "a" "same" "a" | Out-Null
                New-ProjectionSkill $source "b" "same" "b" | Out-Null
                $configPath = Join-Path $TestDrive "codex\config.toml"
                $manifestPath = Join-Path $TestDrive "reports\projection.json"
                $projection = [pscustomobject]@{
                    enabled = $true
                    codex_config_path = $configPath
                    manifest_path = $manifestPath
                    sources = @([pscustomobject]@{ id = "managed"; path = $source; priority = 200; platforms = @("codex") })
                }

                $result = Sync-CodexSkillProjection $projection

                $result.success | Should Be $true
                $result.persisted | Should Be $false
                (Test-Path -LiteralPath $configPath) | Should Be $false
                (Test-Path -LiteralPath $manifestPath) | Should Be $false
            }
            finally {
                $script:DryRun = $oldDryRun
            }
        }

        It "Removes the managed block and refreshes the manifest when projection is disabled" {
            $oldDryRun = $script:DryRun
            try {
                $script:DryRun = $false
                $configPath = Join-Path $TestDrive "disabled\config.toml"
                $manifestPath = Join-Path $TestDrive "disabled\projection.json"
                EnsureDir (Split-Path $configPath -Parent)
                Set-ContentUtf8 $configPath @'
model = "gpt-5.6-sol"

# BEGIN skills-manager:skills-projection
[[skills.config]]
path = "C:\\old\\SKILL.md"
enabled = false
# END skills-manager:skills-projection
'@
                $projection = [pscustomobject]@{
                    enabled = $false
                    codex_config_path = $configPath
                    manifest_path = $manifestPath
                }

                $result = Sync-CodexSkillProjection $projection
                $config = Get-ContentUtf8 $configPath
                $manifest = Get-ContentUtf8 $manifestPath | ConvertFrom-Json

                $result.success | Should Be $true
                $result.persisted | Should Be $true
                $result.changed | Should Be $true
                $config | Should Match 'model = "gpt-5\.6-sol"'
                $config | Should Not Match 'skills-manager:skills-projection'
                $manifest.enabled | Should Be $false
                $manifest.disabled_path_count | Should Be 0
            }
            finally {
                $script:DryRun = $oldDryRun
            }
        }
    }
}
