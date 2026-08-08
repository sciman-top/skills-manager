$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path

function Get-CloseoutRepoText {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    return Get-Content -LiteralPath (Join-Path $repoRoot $RelativePath) -Raw -Encoding UTF8
}

. (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
. (Join-Path $repoRoot 'src\Domain\SkillCatalog.ps1')
. (Join-Path $repoRoot 'src\Application\SkillCatalogCompiler.ps1')
. (Join-Path $repoRoot 'src\Application\SkillEligibilityPolicy.ps1')
. (Join-Path $repoRoot 'src\Application\NativeMetadataPlanner.ps1')
. (Join-Path $repoRoot 'src\Application\SkillProjection.ps1')
. (Join-Path $repoRoot 'src\Application\NativeSkillProjection.ps1')

function New-CloseoutSkillEntry {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Description = 'A complete native metadata fixture.'
    )

    $directory = Join-Path $Root $Name
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    @(
        '---'
        ('name: {0}' -f $Name)
        ('description: {0}' -f $Description)
        '---'
        ('# {0}' -f $Name)
    ) | Set-Content -LiteralPath (Join-Path $directory 'SKILL.md') -Encoding UTF8
    return [pscustomobject][ordered]@{
        kind = 'skill'
        name = $Name
        description = $Description
        path = Join-Path $directory 'SKILL.md'
        source_root = $Root
        enabled = $true
        availability = 'available'
        freshness = 'fresh'
        load_side_effect = 'read_only'
        side_effect = 'read_only'
        dependencies = @()
        surfaces = @('native_discovery')
    }
}

function New-CloseoutSnapshot {
    return [pscustomobject][ordered]@{
        schema_version = 1
        snapshot_id = 'hcs-closeout-fixture'
        surface = 'cli'
        captured_at = '2026-08-07T06:00:00Z'
        capabilities = [pscustomobject][ordered]@{
            model = [pscustomobject]@{ value = 'gpt-5.6'; source = 'model_catalog'; freshness = 'fresh'; unknown_reason = $null }
            context_window = [pscustomobject]@{ value = 272000; source = 'turn_override'; freshness = 'fresh'; unknown_reason = $null }
            metadata_budget = [pscustomobject]@{ value = $null; source = 'unknown_fallback'; freshness = 'unknown'; unknown_reason = 'metadata_budget_unknown' }
            skills_inventory = [pscustomobject]@{ value = @(); source = 'model_catalog'; freshness = 'fresh'; unknown_reason = $null }
        }
    }
}

Describe 'P6 host-native skill lifecycle closeout' {
    It 'removes profile reachability authority while retaining a read-only compatibility view' {
        $config = Get-CloseoutRepoText 'skills.json' | ConvertFrom-Json
        $projection = $config.skill_projection

        @($projection.resident_names) | Should Not Contain 'capability-router'
        @($projection.PSObject.Properties.Name) | Should Not Contain 'active_profile'
        @($projection.PSObject.Properties.Name) | Should Not Contain 'profiles'
        $projection.profile_compatibility.status | Should Be 'read_only'
        $projection.profile_compatibility.reachability_authority | Should Be 'none'
    }

    It 'removes profile/router runtime dispatch from the generated entrypoint and quality gate' {
        $main = Get-CloseoutRepoText 'src/Main.ps1'
        $version = Get-CloseoutRepoText 'src/Version.ps1'
        $help = Get-CloseoutRepoText 'src/Commands/Utils.ps1'
        $build = Get-CloseoutRepoText 'build.ps1'
        $bundle = Get-CloseoutRepoText 'skills.ps1'
        $quality = Get-CloseoutRepoText 'scripts/quality/run-local-quality-gates.ps1'

        $main | Should Not Match '"技能配置"\s*\{'
        $main | Should Not Match '"skill-profile"\s*\{'
        $version | Should Not Match '技能配置|skill-profile'
        $help | Should Not Match '技能配置'
        $build | Should Not Match 'Commands/SkillRouting\.ps1'
        $build | Should Match 'Application/NativeMetadataPlanner\.ps1'
        $build | Should Match 'Application/NativeSkillProjection\.ps1'
        $build | Should Match 'Application/NativeSkillProjectionCoordinator\.ps1'
        $bundle | Should Not Match 'function\s+Invoke-SkillProfileCommand'
        $bundle | Should Not Match 'function\s+New-SkillRoutingReport'
        $bundle | Should Match 'function\s+Plan-NativeMetadata'
        $bundle | Should Match 'function\s+New-NativeSkillProjectionPlan'
        $quality | Should Not Match "Invoke-QualityGate\s+'skill-routing'"
        $quality | Should Match 'verify-native-skill-metadata\.ps1'
    }

    It 'keeps compatibility profile data from excluding any eligible native projection entry' {
        $sourceRoot = Join-Path $TestDrive 'p6-closeout-source'
        $targetRoot = Join-Path $TestDrive 'p6-closeout-target'
        $receiptPath = Join-Path $TestDrive 'p6-closeout-receipt.json'
        $first = New-CloseoutSkillEntry -Root $sourceRoot -Name 'formerly-profile-excluded'
        $second = New-CloseoutSkillEntry -Root $sourceRoot -Name 'ordinary-native-skill'
        $compatibility = [pscustomobject][ordered]@{
            active_profile = 'default'
            profiles = [pscustomobject]@{
                default = [pscustomobject]@{ enabled_names = @('ordinary-native-skill') }
            }
        }

        $catalog = Compile-SkillCatalog -Entries @($first, $second) -Projection $compatibility -GeneratedAt '2026-08-07T06:00:00Z'
        $catalog.profile_filter_applied | Should Be $false
        @($catalog.entries).Count | Should Be 2
        $eligibility = @($catalog.entries | ForEach-Object { Evaluate-SkillEligibility -Skill $_ -Surface 'native_discovery' -AllowedRoots @($sourceRoot) })
        $metadata = Plan-NativeMetadata -Inventory $catalog -Snapshot (New-CloseoutSnapshot)
        $config = [pscustomobject][ordered]@{
            skill_projection = [pscustomobject][ordered]@{
                native_projection = [pscustomobject][ordered]@{
                    enabled = $true
                    owner = 'skills-manager'
                    target_root = $targetRoot
                    receipt_path = $receiptPath
                    apply_requires_token = $true
                    notification_method = 'skills/changed'
                    notification_mode = 'plan_only'
                }
            }
        }
        $plan = New-NativeSkillProjectionPlan -Catalog $catalog -Eligibility $eligibility -MetadataPlan $metadata -Config $config

        $plan.status | Should Be 'ready'
        $plan.enabled_total | Should Be 2
        $plan.kept_total | Should Be 2
        $plan.omitted_total | Should Be 0
        $plan.truncated | Should Be $false
        @($plan.skills | ForEach-Object name) | Should Be @('formerly-profile-excluded', 'ordinary-native-skill')
    }

    It 'makes the native plan authoritative before compatibility link reconciliation' {
        $projectionCommand = Get-CloseoutRepoText 'src/Commands/SkillProjection.ps1'

        $projectionCommand | Should Match 'New-NativeSkillProjectionRuntimePlan'
        $projectionCommand | Should Match 'Apply-NativeSkillProjection'
        $projectionCommand | Should Match '\$nativeProjectionAuthoritative'
        $projectionCommand | Should Match 'if \(-not \$nativeProjectionAuthoritative\)'
        $syncStart = $projectionCommand.IndexOf('function Sync-CodexSkillProjection')
        $applyIndex = $projectionCommand.IndexOf('Apply-NativeSkillProjection', $syncStart)
        $linkIndex = $projectionCommand.IndexOf('Sync-CodexManagedSkillLinks', $applyIndex)
        $applyIndex | Should BeLessThan $linkIndex
    }
}
