BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
    $plannerPath = Join-Path $repoRoot 'src\Application\NativeMetadataPlanner.ps1'
    if (Test-Path -LiteralPath $plannerPath -PathType Leaf) { . $plannerPath }

    function New-TestMetadataPolicy {
        return [pscustomobject][ordered]@{
            schema_version = 1
            context_ratio = 0.02
            headroom_ratio = 0.20
            unknown_context_character_ceiling = 8000
            estimated_tokens_per_utf8_byte = 0.25
            max_compacted_description_characters = 160
            min_compacted_description_characters = 24
        }
    }

    function New-TestMetadataSnapshot {
        param(
            [Nullable[int64]]$ContextWindow,
            [Nullable[int64]]$MetadataBudget,
            [string]$ContextSource = 'turn_override',
            [string]$ContextFreshness = 'fresh'
        )

        $contextValue = if ($null -eq $ContextWindow) { $null } else { [int64]$ContextWindow }
        $contextReason = if ($null -eq $contextValue) { 'context_window_unknown' } else { $null }
        $budgetValue = if ($null -eq $MetadataBudget) { $null } else { [int64]$MetadataBudget }
        return [pscustomobject][ordered]@{
            schema_version = 1
            snapshot_id = 'hcs-test-metadata'
            surface = 'cli'
            captured_at = '2026-08-07T05:00:00Z'
            capabilities = [pscustomobject][ordered]@{
                context_window = [pscustomobject]@{ value = $contextValue; source = $ContextSource; freshness = $ContextFreshness; unknown_reason = $contextReason }
                metadata_budget = [pscustomobject]@{ value = $budgetValue; source = if ($null -eq $budgetValue) { 'unknown_fallback' } else { 'model_catalog' }; freshness = if ($null -eq $budgetValue) { 'unknown' } else { 'fresh' }; unknown_reason = if ($null -eq $budgetValue) { 'metadata_budget_unknown' } else { $null } }
                model = [pscustomobject]@{ value = 'gpt-5.6'; source = 'model_catalog'; freshness = 'fresh'; unknown_reason = $null }
                skills_inventory = [pscustomobject]@{ value = @(); source = 'model_catalog'; freshness = 'fresh'; unknown_reason = $null }
            }
        }
    }

    function New-TestMetadataEntry {
        param([string]$Name, [int64]$TokenEstimate, [int]$DescriptionLength = 40, [bool]$Enabled = $true)

        return [pscustomobject][ordered]@{
            kind = 'skill'
            name = $Name
            description = ('d' * $DescriptionLength)
            path = "D:\managed\$Name\SKILL.md"
            enabled = $Enabled
            availability = 'available'
            freshness = 'fresh'
            load_side_effect = 'read_only'
            side_effect = 'read_only'
            token_estimate = $TokenEstimate
        }
    }

}
Describe 'Native metadata planner' {
    It 'uses floor(context_window * 0.02) and preserves the 20 percent headroom provenance' {
        $planner = Get-Command Plan-NativeMetadata -ErrorAction SilentlyContinue
        $planner | Should -Not -BeNullOrEmpty
        if ($null -eq $planner) { return }

        $result = Plan-NativeMetadata -Inventory ([pscustomobject]@{ entries = @((New-TestMetadataEntry 'known-context' 12)) }) -Snapshot (New-TestMetadataSnapshot 272000 $null) -Policy (New-TestMetadataPolicy)

        $result.budget.ceiling_tokens | Should -Be 5440
        $result.budget.headroom_ratio | Should -Be 0.2
        $result.budget.usable_tokens | Should -Be 4352
        $result.budget.source | Should -Be 'turn_override'
        $result.enabled_total | Should -Be 1
        $result.kept_total | Should -Be 1
        $result.truncated | Should -Be $false
        $result.omitted_total | Should -Be 0
        (Test-NativeMetadataPlanContract $result).pass | Should -Be $true
    }

    It 'uses an explicit unknown-context character fallback without conflating it with tokens' {
        $planner = Get-Command Plan-NativeMetadata -ErrorAction SilentlyContinue
        $planner | Should -Not -BeNullOrEmpty
        if ($null -eq $planner) { return }

        $result = Plan-NativeMetadata -Inventory ([pscustomobject]@{ entries = @((New-TestMetadataEntry 'unknown-context' 17 4000)) }) -Snapshot (New-TestMetadataSnapshot $null $null) -Policy (New-TestMetadataPolicy)

        $result.budget.mode | Should -Be 'character_fallback'
        $result.budget.character_ceiling | Should -Be 8000
        $result.budget.usable_characters | Should -Be 6400
        $result.budget.token_ceiling | Should -Be $null
        $result.budget.source | Should -Be 'unknown_fallback'
        $result.measurement.unit | Should -Be 'characters'
        $result.measurement.token_estimate_used | Should -Be $false
        $result.projection_effect | Should -Be 'plan_only'
        $result.budget.host_budget_status | Should -Be 'unknown'
        $result.budget.host_budget_pass | Should -Be $null
        $result.metadata[0].planned_description | Should -Not -BeNullOrEmpty
        @($result.metadata[0].PSObject.Properties.Name) | Should -Not -Contain 'description'
        $result.truncated | Should -Be $false
        (Test-NativeMetadataPlanContract $result).pass | Should -Be $true
    }

    It 'uses an explicit token estimate instead of treating description characters as tokens' {
        $planner = Get-Command Plan-NativeMetadata -ErrorAction SilentlyContinue
        $planner | Should -Not -BeNullOrEmpty
        if ($null -eq $planner) { return }

        $result = Plan-NativeMetadata -Inventory ([pscustomobject]@{ entries = @((New-TestMetadataEntry 'token-measured' 17 4000)) }) -Snapshot (New-TestMetadataSnapshot 10000 $null) -Policy (New-TestMetadataPolicy)

        $result.measurement.unit | Should -Be 'tokens'
        $result.measurement.token_estimate_used | Should -Be $true
        $result.token_estimate | Should -Be 17
        $result.metadata[0].character_count | Should -BeGreaterThan 1000
        $result.metadata[0].token_estimate | Should -Be 17
        $result.truncated | Should -Be $false
    }

    It 'adaptively compacts toward the declared minimum before failing closed' {
        $inventory = [pscustomobject]@{ entries = @(
                [pscustomobject]@{ kind = 'skill'; name = 'adaptive-a'; description = ('a' * 300); path = 'D:\managed\adaptive-a\SKILL.md'; enabled = $true; availability = 'available'; freshness = 'fresh'; load_side_effect = 'read_only'; side_effect = 'read_only' },
                [pscustomobject]@{ kind = 'skill'; name = 'adaptive-b'; description = ('b' * 300); path = 'D:\managed\adaptive-b\SKILL.md'; enabled = $true; availability = 'available'; freshness = 'fresh'; load_side_effect = 'read_only'; side_effect = 'read_only' }
            ) }

        $result = Plan-NativeMetadata -Inventory $inventory -Snapshot (New-TestMetadataSnapshot 5000 $null) -Policy (New-TestMetadataPolicy)

        $result.pass | Should -Be $true
        $result.enabled_total | Should -Be 2
        $result.kept_total | Should -Be 2
        $result.omitted_total | Should -Be 0
        $result.compaction.final_maximum_description_characters | Should -BeLessThan 160
        $result.compaction.final_maximum_description_characters | Should -Not -BeLessThan 24
        $result.compaction.after_cost | Should -Not -BeGreaterThan $result.budget.usable_tokens
    }

    It 'reports exact budget offenders without truncating advisory metadata' {
        $planner = Get-Command Plan-NativeMetadata -ErrorAction SilentlyContinue
        $planner | Should -Not -BeNullOrEmpty
        if ($null -eq $planner) { return }

        $inventory = [pscustomobject]@{ entries = @(
                (New-TestMetadataEntry 'overflow-a' 10 100),
                (New-TestMetadataEntry 'overflow-b' 10 100),
                (New-TestMetadataEntry 'disabled' 10 100 $false)
            ) }
        $result = Plan-NativeMetadata -Inventory $inventory -Snapshot (New-TestMetadataSnapshot 100 $null) -Policy (New-TestMetadataPolicy)

        $result.pass | Should -Be $true
        $result.status | Should -Be 'ready'
        $result.budget_fit | Should -Be $false
        $result.truncated | Should -Be $false
        $result.block_reason | Should -Be $null
        $result.enabled_total | Should -Be 2
        $result.kept_total | Should -Be 2
        $result.omitted_total | Should -Be 0
        @($result.kept) | Should -Be @('overflow-a', 'overflow-b')
        @($result.overflow.offenders.name) | Should -Be @('overflow-a', 'overflow-b')
        $result.compaction.attempted | Should -Be $true
        (Test-NativeMetadataPlanContract $result).pass | Should -Be $true
    }
}
