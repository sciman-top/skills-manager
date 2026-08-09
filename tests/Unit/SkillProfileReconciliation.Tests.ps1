. $PSScriptRoot\..\..\skills.ps1

function New-LegacyProfileConfig {
    return [pscustomobject]@{
        schema_version = 1
        skill_projection = [pscustomobject]@{
            enabled = $true
            active_profile = "default"
            budget_limit_chars = 8000
            external_metadata_reserve_chars = 0
            resident_names = @()
            aliases = @()
            profiles = [pscustomobject]@{
                default = [pscustomobject]@{ enabled_names = @("verification-before-completion", "active") }
                coding = [pscustomobject]@{ enabled_names = @("elsewhere") }
            }
            sources = @()
        }
    }
}

Describe "Skill profile migration compatibility" {
    It "Reads legacy profile fields as a read-only compatibility view" {
        $cfg = New-LegacyProfileConfig

        $view = Get-SkillProfileCompatibilityView $cfg.skill_projection

        $view.schema_version | Should Be 1
        $view.kind | Should Be "ProfileCompatibilityView"
        $view.status | Should Be "read_only"
        $view.reachability_authority | Should Be "none"
        $view.active_profile | Should Be "default"
        @($view.profiles.default.enabled_names) | Should Be @("verification-before-completion", "active")
        $view.writes_performed | Should Be $false
    }

    It "Plans a versioned migration without writing or changing the active profile value" {
        $cfg = New-LegacyProfileConfig
        $configPath = Join-Path $TestDrive "migration-plan.json"
        Set-ContentUtf8 $configPath ($cfg | ConvertTo-Json -Depth 50)

        $plan = New-SkillProfileMigrationPlan -Config $cfg -ConfigPath $configPath

        $plan.pass | Should Be $true
        $plan.status | Should Be "ready"
        $plan.migration_required | Should Be $true
        $plan.writes_performed | Should Be $false
        $plan.active_profile | Should Be "default"
        $plan.migrated_config.skill_projection.PSObject.Properties["active_profile"] | Should Be $null
        $plan.migrated_config.skill_projection.PSObject.Properties["profiles"] | Should Be $null
        $plan.migrated_config.skill_projection.profile_compatibility.status | Should Be "read_only"
        $plan.migrated_config.skill_projection.profile_compatibility.active_profile | Should Be "default"
    }

    It "Keeps the retired host-proposal planner fail-closed and zero-write" {
        $cfg = New-LegacyProfileConfig

        $result = New-SkillProfileReconciliationPlan $cfg.skill_projection ("a" * 64)

        $result.status | Should Be "deprecated"
        $result.pass | Should Be $false
        $result.apply_allowed | Should Be $false
        $result.writes_performed | Should Be $false
        @($result.actions).Count | Should Be 0
        $result.findings[0].code | Should Be "profile_reconciliation_retired"
    }

    It "Returns the retirement contract without parsing a legacy proposal file" {
        $proposalPath = Join-Path $TestDrive "malformed.json"
        Set-ContentUtf8 $proposalPath "{ not-json"
        $scriptPath = Join-Path $PSScriptRoot "..\..\scripts\plan-skill-profile-reconciliation.ps1"

        $raw = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -ProposalPath $proposalPath -Json -NoExit)
        $result = ($raw -join "`n") | ConvertFrom-Json

        $result.status | Should Be "deprecated"
        $result.pass | Should Be $false
        $result.findings[0].code | Should Be "profile_reconciliation_retired"
        $result.writes_performed | Should Be $false
        $result.apply_allowed | Should Be $false
    }
}
