$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
. (Join-Path $repoRoot 'src\Domain\SkillCatalog.ps1')
. (Join-Path $repoRoot 'src\Application\SkillCatalogCompiler.ps1')
. (Join-Path $repoRoot 'src\Application\SkillEligibilityPolicy.ps1')
. (Join-Path $repoRoot 'src\Application\NativeMetadataPlanner.ps1')

$projectionPath = Join-Path $repoRoot 'src\Application\SkillProjection.ps1'
$nativeProjectionPath = Join-Path $repoRoot 'src\Application\NativeSkillProjection.ps1'
$runtimeCoordinatorPath = Join-Path $repoRoot 'src\Application\NativeSkillProjectionCoordinator.ps1'
if (Test-Path -LiteralPath $projectionPath -PathType Leaf) { . $projectionPath }
if (Test-Path -LiteralPath $nativeProjectionPath -PathType Leaf) { . $nativeProjectionPath }
if (Test-Path -LiteralPath $runtimeCoordinatorPath -PathType Leaf) { . $runtimeCoordinatorPath }

function New-ProjectionSkill {
    param(
        [string]$Root,
        [string]$Directory,
        [string]$Name,
        [string]$Description = 'Projection fixture.',
        [bool]$Enabled = $true
    )

    $skillDirectory = Join-Path $Root $Directory
    New-Item -ItemType Directory -Path $skillDirectory -Force | Out-Null
    @(
        '---'
        ('name: {0}' -f $Name)
        ('description: {0}' -f $Description)
        '---'
        ('# {0}' -f $Name)
    ) | Set-Content -LiteralPath (Join-Path $skillDirectory 'SKILL.md') -Encoding utf8
    return [pscustomobject]@{
        name = $Name
        path = Join-Path $skillDirectory 'SKILL.md'
        source_root = $Root
        enabled = $Enabled
    }
}

function New-ProjectionSnapshot {
    param([int]$ContextWindow = 272000)

    return [pscustomobject]@{
        capabilities = [pscustomobject]@{
            context_window = [pscustomobject]@{ value = $ContextWindow; source = 'app_server'; freshness = 'fresh' }
            metadata_budget = [pscustomobject]@{ value = $null; source = 'unknown_fallback'; freshness = 'unknown'; unknown_reason = 'metadata_budget_unknown' }
        }
    }
}

function New-ProjectionFixture {
    $suffix = [guid]::NewGuid().ToString('N')
    $sourceRoot = Join-Path $TestDrive ('native-source-{0}' -f $suffix)
    $targetRoot = Join-Path $TestDrive ('native-target-{0}' -f $suffix)
    $receiptPath = Join-Path $repoRoot ('reports\skill-projection\test-native-receipt-{0}.json' -f $suffix)
    $enabled = New-ProjectionSkill $sourceRoot 'enabled' 'enabled' 'Enabled capability.'
    $resident = New-ProjectionSkill $sourceRoot 'resident' 'resident' 'Resident capability.'
    $disabled = New-ProjectionSkill $sourceRoot 'disabled' 'disabled' 'Disabled capability.' $false
    $entries = @(
        [pscustomobject]@{ name = $enabled.Name; description = 'Enabled capability.'; path = $enabled.path; source_root = $sourceRoot; enabled = $true; availability = 'available'; freshness = 'fresh'; side_effect = 'read_only'; load_side_effect = 'read_only' }
        [pscustomobject]@{ name = $resident.Name; description = 'Resident capability.'; path = $resident.path; source_root = $sourceRoot; enabled = $true; availability = 'available'; freshness = 'fresh'; side_effect = 'read_only'; load_side_effect = 'read_only' }
        [pscustomobject]@{ name = $disabled.Name; description = 'Disabled capability.'; path = $disabled.path; source_root = $sourceRoot; enabled = $false; availability = 'available'; freshness = 'fresh'; side_effect = 'read_only'; load_side_effect = 'read_only' }
    )
    $catalog = Compile-SkillCatalog -Entries $entries -GeneratedAt '2026-08-07T06:00:00Z'
    $eligibility = @($catalog.entries | ForEach-Object {
            Evaluate-SkillEligibility -Skill $_ -Surface 'native_discovery' -AllowedRoots @($sourceRoot)
        })
    $metadata = Plan-NativeMetadata -Inventory $catalog -Snapshot (New-ProjectionSnapshot)
    $config = [pscustomobject]@{
        skill_projection = [pscustomobject]@{
            user_skill_root = $targetRoot
            native_projection = [pscustomobject]@{
                enabled = $true
                owner = 'skills-manager'
                target_root = $targetRoot
                receipt_path = $receiptPath
                notification_method = 'skills/changed'
            }
        }
    }
    return [pscustomobject]@{
        source_root = $sourceRoot
        target_root = $targetRoot
        receipt_path = $receiptPath
        catalog = $catalog
        eligibility = $eligibility
        metadata = $metadata
        config = $config
    }
}

Describe 'Native skill projection plan and transaction' {
    AfterEach {
        Get-ChildItem -LiteralPath (Join-Path $repoRoot 'reports\skill-projection') -Filter 'test-*.json' -File -ErrorAction SilentlyContinue | Remove-Item -Force
    }

    It 'rejects native targets that differ from the configured user root' {
        $fixture = New-ProjectionFixture
        $fixture.config.skill_projection.user_skill_root = Join-Path $TestDrive 'different-user-root'

        { New-NativeSkillProjectionPlan -Catalog $fixture.catalog -Eligibility $fixture.eligibility -MetadataPlan $fixture.metadata -Config $fixture.config } | Should Throw
    }

    It 'rejects receipt paths outside the repository managed receipt root' {
        $fixture = New-ProjectionFixture
        $fixture.config.skill_projection.native_projection.receipt_path = Join-Path $TestDrive 'escaped-receipt.json'

        { New-NativeSkillProjectionPlan -Catalog $fixture.catalog -Eligibility $fixture.eligibility -MetadataPlan $fixture.metadata -Config $fixture.config } | Should Throw
    }
    It 'builds a complete runtime plan from managed top-level skill packages' {
        (Get-Command New-NativeSkillProjectionRuntimePlan -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        $fixture = New-ProjectionFixture

        $plan = New-NativeSkillProjectionRuntimePlan `
            -ManagedRoot $fixture.source_root `
            -Config $fixture.config `
            -Snapshot (New-ProjectionSnapshot)

        $plan.status | Should Be 'ready'
        $plan.enabled_total | Should Be 3
        $plan.kept_total | Should Be 3
        $plan.omitted_total | Should Be 0
        $plan.truncated | Should Be $false
    }

    It 'limits the runtime plan to explicitly included package directories' {
        $fixture = New-ProjectionFixture

        $plan = New-NativeSkillProjectionRuntimePlan `
            -ManagedRoot $fixture.source_root `
            -Config $fixture.config `
            -Snapshot (New-ProjectionSnapshot) `
            -IncludedNames @('resident')

        $plan.status | Should Be 'ready'
        $plan.enabled_total | Should Be 1
        $plan.kept_total | Should Be 1
        @($plan.skills | ForEach-Object name) | Should Be @('resident')
        { New-NativeSkillProjectionRuntimePlan -ManagedRoot $fixture.source_root -Config $fixture.config -Snapshot (New-ProjectionSnapshot) -IncludedNames @('missing') } | Should Throw
    }

    It 'keeps namespaced semantic names while using the safe package directory leaf' {
        $sourceRoot = Join-Path $TestDrive 'namespaced-source'
        $targetRoot = Join-Path $TestDrive 'namespaced-target'
        $skill = New-ProjectionSkill $sourceRoot 'debug-dotnet' 'debug:dotnet' 'Debug .NET applications.'
        $catalog = Compile-SkillCatalog -Entries @([pscustomobject]@{ name = $skill.Name; description = 'Debug .NET applications.'; path = $skill.path; source_root = $sourceRoot; enabled = $true; availability = 'available'; freshness = 'fresh'; side_effect = 'read_only'; load_side_effect = 'read_only' })
        $eligibility = @($catalog.entries | ForEach-Object { Evaluate-SkillEligibility -Skill $_ -Surface 'native_discovery' -AllowedRoots @($sourceRoot) })
        $metadata = Plan-NativeMetadata -Inventory $catalog -Snapshot (New-ProjectionSnapshot)
        $config = [pscustomobject]@{ skill_projection = [pscustomobject]@{ user_skill_root = $targetRoot; native_projection = [pscustomobject]@{ enabled = $true; owner = 'skills-manager'; target_root = $targetRoot; receipt_path = (Join-Path $repoRoot 'reports\skill-projection\test-namespaced-receipt.json'); notification_method = 'skills/changed' } } }

        $plan = New-NativeSkillProjectionPlan -Catalog $catalog -Eligibility $eligibility -MetadataPlan $metadata -Config $config

        $plan.status | Should Be 'ready'
        $plan.skills[0].name | Should Be 'debug:dotnet'
        (Split-Path $plan.skills[0].target_directory -Leaf) | Should Be 'debug-dotnet'
    }


    It 'projects enabled skills while keeping advisory metadata plan-only' {
        $fixture = New-ProjectionFixture

        $plan = New-NativeSkillProjectionPlan -Catalog $fixture.catalog -Eligibility $fixture.eligibility -MetadataPlan $fixture.metadata -Config $fixture.config

        $plan.status | Should Be 'ready'
        $plan.enabled_total | Should Be 2
        $plan.kept_total | Should Be 2
        $plan.omitted_total | Should Be 0
        $plan.truncated | Should Be $false
        @($plan.omitted).Count | Should Be 0
        @($plan.skills | ForEach-Object name) | Should Be @('enabled', 'resident')
        @($plan.skills | Where-Object name -eq 'disabled').Count | Should Be 0
        foreach ($skill in @($plan.skills)) {
            (Test-Path -LiteralPath $skill.source_path -PathType Leaf) | Should Be $true
            [string]$skill.target_path | Should Match ([regex]::Escape($fixture.target_root))
            [string]$skill.content_hash | Should Match '^[0-9a-f]{64}$'
            [string]$skill.metadata_hash | Should Match '^[0-9a-f]{64}$'
            $skill.metadata.name | Should Be $skill.name
            [string]$skill.metadata.observed_source_description | Should Not BeNullOrEmpty
            [string]$skill.metadata.planned_description | Should Not BeNullOrEmpty
            $skill.metadata.projection_effect | Should Be 'plan_only'
            $skill.metadata.materialization | Should Be 'source_package_junction'
            @($skill.metadata.PSObject.Properties.Name) | Should Not Contain 'description'
        }
        $plan.apply_token | Should Match '^nsp-token-[0-9a-f]{16}$'
        $plan.notification.method | Should Be 'skills/changed'
        $plan.notification.status | Should Be 'planned_only'
        @($plan.notification.changed_names) | Should Be @('enabled', 'resident')
        (Test-NativeSkillProjectionPlanContract $plan).pass | Should Be $true
    }

    It 'keeps a compacted advisory description separate from the junction materialized source description' {
        $sourceRoot = Join-Path $TestDrive 'plan-only-source'
        $targetRoot = Join-Path $TestDrive 'plan-only-target'
        $sourceDescription = ('Use this capability when ' + ('the original host-visible trigger context must remain intact. ' * 8)).TrimEnd()
        $skill = New-ProjectionSkill $sourceRoot 'plan-only' 'plan-only' $sourceDescription
        $catalog = Compile-SkillCatalog -Entries @([pscustomobject]@{ name = $skill.Name; description = $sourceDescription; path = $skill.path; source_root = $sourceRoot; enabled = $true; availability = 'available'; freshness = 'fresh'; side_effect = 'read_only'; load_side_effect = 'read_only' })
        $eligibility = @($catalog.entries | ForEach-Object { Evaluate-SkillEligibility -Skill $_ -Surface 'native_discovery' -AllowedRoots @($sourceRoot) })
        $snapshot = [pscustomobject]@{ capabilities = [pscustomobject]@{
                context_window = [pscustomobject]@{ value = 20000; source = 'app_server'; freshness = 'fresh' }
                metadata_budget = [pscustomobject]@{ value = 60; source = 'app_server'; freshness = 'fresh' }
            } }
        $metadata = Plan-NativeMetadata -Inventory $catalog -Snapshot $snapshot
        $config = [pscustomobject]@{ skill_projection = [pscustomobject]@{ user_skill_root = $targetRoot; native_projection = [pscustomobject]@{ enabled = $true; owner = 'skills-manager'; target_root = $targetRoot; receipt_path = (Join-Path $repoRoot 'reports\skill-projection\test-plan-only-receipt.json'); notification_method = 'skills/changed' } } }

        $metadata.pass | Should Be $true
        $metadata.compaction.applied | Should Be $true
        $plan = New-NativeSkillProjectionPlan -Catalog $catalog -Eligibility $eligibility -MetadataPlan $metadata -Config $config

        $plan.skills[0].metadata.projection_effect | Should Be 'plan_only'
        $plan.skills[0].metadata.planned_description.Length | Should BeLessThan $sourceDescription.Length
        $plan.skills[0].metadata.observed_source_description | Should Be $sourceDescription
        @($plan.skills[0].metadata.PSObject.Properties.Name) | Should Not Contain 'description'

        Apply-NativeSkillProjection -Plan $plan -ApplyToken $plan.apply_token -ReceiptPath $config.skill_projection.native_projection.receipt_path | Out-Null
        $materialized = Get-Content -LiteralPath (Join-Path $targetRoot 'plan-only\SKILL.md') -Raw
        $materialized | Should Match ([regex]::Escape($sourceDescription))
        $materialized | Should Not Match ([regex]::Escape([string]$plan.skills[0].metadata.planned_description) + '\r?\n---')
    }

    It 'requires the explicit apply token and rolls back a partial apply atomically' {
        $fixture = New-ProjectionFixture
        $plan = New-NativeSkillProjectionPlan -Catalog $fixture.catalog -Eligibility $fixture.eligibility -MetadataPlan $fixture.metadata -Config $fixture.config

        { Apply-NativeSkillProjection -Plan $plan -ApplyToken 'wrong-token' -ReceiptPath $fixture.receipt_path } | Should Throw

        Remove-Item -LiteralPath (Join-Path $fixture.source_root 'resident\SKILL.md') -Force
        { Apply-NativeSkillProjection -Plan $plan -ApplyToken $plan.apply_token -ReceiptPath $fixture.receipt_path } | Should Throw

        (Test-Path -LiteralPath (Join-Path $fixture.target_root 'enabled')) | Should Be $false
        (Test-Path -LiteralPath (Join-Path $fixture.target_root 'resident')) | Should Be $false
        (Test-Path -LiteralPath $fixture.receipt_path -PathType Leaf) | Should Be $false
    }

    It 'writes a receipt, blocks rollback after target drift, and rolls back an unchanged target' {
        $fixture = New-ProjectionFixture
        $plan = New-NativeSkillProjectionPlan -Catalog $fixture.catalog -Eligibility $fixture.eligibility -MetadataPlan $fixture.metadata -Config $fixture.config
        $applied = Apply-NativeSkillProjection -Plan $plan -ApplyToken $plan.apply_token -ReceiptPath $fixture.receipt_path

        $applied.status | Should Be 'applied'
        $applied.receipt_id | Should Match '^nsr-[0-9a-f]{16}$'
        (Test-Path -LiteralPath $fixture.receipt_path -PathType Leaf) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $fixture.target_root 'enabled\SKILL.md') -PathType Leaf) | Should Be $true
        (Test-NativeSkillProjectionReceiptContract ($applied.receipt)).pass | Should Be $true

        Remove-Item -LiteralPath (Join-Path $fixture.target_root 'enabled') -Recurse -Force
        New-Item -ItemType Directory -Path (Join-Path $fixture.target_root 'enabled') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $fixture.target_root 'enabled\SKILL.md') -Value 'drifted' -Encoding utf8
        { Rollback-NativeSkillProjection -ReceiptPath $fixture.receipt_path } | Should Throw
        (Test-Path -LiteralPath (Join-Path $fixture.target_root 'enabled\SKILL.md') -PathType Leaf) | Should Be $true

        $cleanFixture = New-ProjectionFixture
        $cleanPlan = New-NativeSkillProjectionPlan -Catalog $cleanFixture.catalog -Eligibility $cleanFixture.eligibility -MetadataPlan $cleanFixture.metadata -Config $cleanFixture.config
        Apply-NativeSkillProjection -Plan $cleanPlan -ApplyToken $cleanPlan.apply_token -ReceiptPath $cleanFixture.receipt_path | Out-Null
        $rolledBack = Rollback-NativeSkillProjection -ReceiptPath $cleanFixture.receipt_path
        $rolledBack.status | Should Be 'rolled_back'
        (Test-Path -LiteralPath (Join-Path $cleanFixture.target_root 'enabled')) | Should Be $false
        (Test-Path -LiteralPath (Join-Path $cleanFixture.target_root 'resident')) | Should Be $false
    }
}
