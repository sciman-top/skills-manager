BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
    . (Join-Path $repoRoot 'src\Domain\SkillCatalog.ps1')
    . (Join-Path $repoRoot 'src\Core.ps1')
    . (Join-Path $repoRoot 'src\Application\SkillCatalogCompiler.ps1')
    . (Join-Path $repoRoot 'src\Application\SkillEligibilityPolicy.ps1')
    . (Join-Path $repoRoot 'src\Application\SkillProjection.ps1')
    . (Join-Path $repoRoot 'src\Application\NativeSkillProjection.ps1')
    . (Join-Path $repoRoot 'src\Application\NativeSkillProjectionCoordinator.ps1')
    $script:nativeProjectionReceipts = [Collections.Generic.List[string]]::new()

    function New-ProjectionFixture {
        $id = [guid]::NewGuid().ToString('N')
        $source = Join-Path $TestDrive "source-$id"
        $target = Join-Path $TestDrive "target-$id"
        foreach ($name in @('enabled','resident')) {
            $root = Join-Path $source $name
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            "---`nname: $name`ndescription: $name capability.`n---`n# $name" | Set-Content -LiteralPath (Join-Path $root 'SKILL.md') -Encoding utf8
        }
        $receipt = Join-Path $repoRoot "reports\skill-projection\test-$id.json"
        $script:nativeProjectionReceipts.Add($receipt) | Out-Null
        $config = [pscustomobject]@{ skill_projection = [pscustomobject]@{ user_skill_root=$target; native_projection=[pscustomobject]@{ enabled=$true; owner='skills-manager'; target_root=$target; receipt_path=$receipt } } }
        return [pscustomobject]@{ source=$source; target=$target; receipt=$receipt; config=$config }
    }
}

Describe 'Native skill projection' {
    AfterEach {
        foreach ($receipt in @($script:nativeProjectionReceipts.ToArray())) {
            if ([IO.File]::Exists($receipt)) { [IO.File]::Delete($receipt) }
        }
        $script:nativeProjectionReceipts.Clear()
    }

    It 'projects complete managed packages without a repository metadata budget planner' {
        $f = New-ProjectionFixture
        $plan = New-NativeSkillProjectionRuntimePlan -ManagedRoot $f.source -Config $f.config

        $plan.status | Should -Be 'ready'
        $plan.kept_total | Should -Be 2
        @($plan.PSObject.Properties.Name) | Should -Not -Contain 'metadata_plan_id'
        @($plan.PSObject.Properties.Name) | Should -Not -Contain 'apply_token'
        @($plan.skills | ForEach-Object name) | Should -Be @('enabled','resident')
        @($plan.skills | Where-Object { [string]$_.package_hash -notmatch '^[a-f0-9]{64}$' }).Count | Should -Be 0
        (Test-NativeSkillProjectionPlanContract $plan).pass | Should -Be $true

        $applied = Apply-NativeSkillProjection -Plan $plan -ReceiptPath $f.receipt
        $applied.status | Should -Be 'applied'
        Test-Path -LiteralPath (Join-Path $f.target 'enabled\SKILL.md') | Should -Be $true
        (Test-NativeSkillProjectionReceiptContract $applied.receipt).pass | Should -Be $true
        @($applied.receipt.PSObject.Properties.Name) | Should -Not -Contain 'rollback'
    }

    It 'keeps include filtering and target containment fail closed' {
        $f = New-ProjectionFixture
        $plan = New-NativeSkillProjectionRuntimePlan -ManagedRoot $f.source -Config $f.config -IncludedNames @('resident')
        @($plan.skills | ForEach-Object name) | Should -Be @('resident')
        { New-NativeSkillProjectionRuntimePlan -ManagedRoot $f.source -Config $f.config -IncludedNames @('missing') } | Should -Throw

        $f.config.skill_projection.native_projection.target_root = Join-Path $TestDrive 'other'
        { New-NativeSkillProjectionRuntimePlan -ManagedRoot $f.source -Config $f.config } | Should -Throw
    }

    It 'rolls back a partial apply when a source drifts' {
        $f = New-ProjectionFixture
        $plan = New-NativeSkillProjectionRuntimePlan -ManagedRoot $f.source -Config $f.config
        Remove-Item -LiteralPath (Join-Path $f.source 'resident\SKILL.md') -Force
        { Apply-NativeSkillProjection -Plan $plan -ReceiptPath $f.receipt } | Should -Throw
        Test-Path -LiteralPath (Join-Path $f.target 'enabled') | Should -Be $false
    }

    It 'rejects package asset drift after planning' {
        $f = New-ProjectionFixture
        $scripts = Join-Path $f.source 'enabled\scripts'
        New-Item -ItemType Directory -Path $scripts -Force | Out-Null
        $asset = Join-Path $scripts 'tool.ps1'
        [IO.File]::WriteAllText($asset, 'before', [Text.UTF8Encoding]::new($false))
        $plan = New-NativeSkillProjectionRuntimePlan -ManagedRoot $f.source -Config $f.config

        [IO.File]::WriteAllText($asset, 'after', [Text.UTF8Encoding]::new($false))

        { Apply-NativeSkillProjection -Plan $plan -ReceiptPath $f.receipt } | Should -Throw 'Projection package hash drifted*'
        Test-Path -LiteralPath (Join-Path $f.target 'enabled') | Should -BeFalse
    }

    It 'plans and receipts stale owned junction removal while preserving external entries' {
        $f = New-ProjectionFixture
        New-Item -ItemType Directory -Path $f.target -Force | Out-Null
        $staleSource = Join-Path $f.source 'stale'; New-Item -ItemType Directory -Path $staleSource -Force | Out-Null
        "---`nname: stale`ndescription: stale`n---" | Set-Content -LiteralPath (Join-Path $staleSource 'SKILL.md')
        New-Item -ItemType Junction -Path (Join-Path $f.target 'stale') -Target $staleSource | Out-Null
        $externalSource = Join-Path $TestDrive ('external-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $externalSource -Force | Out-Null
        New-Item -ItemType Junction -Path (Join-Path $f.target 'external') -Target $externalSource | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $f.target 'ordinary') | Out-Null

        $plan = New-NativeSkillProjectionRuntimePlan -ManagedRoot $f.source -Config $f.config -ExcludedNames @('stale')
        @($plan.removals.name) | Should -Be @('stale')
        $applied = Apply-NativeSkillProjection -Plan $plan -ReceiptPath $f.receipt
        Test-Path -LiteralPath (Join-Path $f.target 'stale') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $f.target 'external') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $f.target 'ordinary') | Should -BeTrue
        @($applied.receipt.removed_names) | Should -Be @('stale')
        @($applied.receipt.added_names | Sort-Object) | Should -Be @('enabled','resident')
    }

    It 'plans stale removal without writing during dry-run planning' {
        $f = New-ProjectionFixture
        New-Item -ItemType Directory -Path $f.target -Force | Out-Null
        $staleSource = Join-Path $f.source 'stale'; New-Item -ItemType Directory -Path $staleSource -Force | Out-Null
        "---`nname: stale`ndescription: stale`n---" | Set-Content -LiteralPath (Join-Path $staleSource 'SKILL.md')
        $staleLink = Join-Path $f.target 'stale'; New-Item -ItemType Junction -Path $staleLink -Target $staleSource | Out-Null

        $plan = New-NativeSkillProjectionRuntimePlan -ManagedRoot $f.source -Config $f.config -ExcludedNames @('stale')
        @($plan.removals.name) | Should -Be @('stale')
        Test-Path -LiteralPath $staleLink | Should -BeTrue
        $plan.writes | Should -Be 0
    }

    It 'keeps package hash stable across generated catalog rewrites' {
        $f = New-ProjectionFixture
        $skillDir = Join-Path $f.source 'enabled'
        $baseline = [string](@(New-NativeSkillProjectionRuntimePlan -ManagedRoot $f.source -Config $f.config).skills | Where-Object name -eq 'enabled').package_hash
        $baseline | Should -Match '^[a-f0-9]{64}$'

        '{"catalog":"generated-v1"}' | Set-Content -LiteralPath (Join-Path $skillDir 'catalog.json') -Encoding utf8
        [string](@(New-NativeSkillProjectionRuntimePlan -ManagedRoot $f.source -Config $f.config).skills | Where-Object name -eq 'enabled').package_hash | Should -Be $baseline
        '{"catalog":"generated-v2","domains":[]}' | Set-Content -LiteralPath (Join-Path $skillDir 'catalog.json') -Encoding utf8
        [string](@(New-NativeSkillProjectionRuntimePlan -ManagedRoot $f.source -Config $f.config).skills | Where-Object name -eq 'enabled').package_hash | Should -Be $baseline

        Add-Content -LiteralPath (Join-Path $skillDir 'SKILL.md') -Value 'authored change'
        [string](@(New-NativeSkillProjectionRuntimePlan -ManagedRoot $f.source -Config $f.config).skills | Where-Object name -eq 'enabled').package_hash | Should -Not -Be $baseline
    }

    It 'removes an owned stale junction whose source directory no longer exists' {
        $f = New-ProjectionFixture
        New-Item -ItemType Directory -Path $f.target -Force | Out-Null
        $staleSource = Join-Path $f.source 'legacy-name'
        New-Item -ItemType Directory -Path $staleSource -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $staleSource 'SKILL.md'), "---`nname: legacy-name`ndescription: legacy capability.`n---`n", [Text.UTF8Encoding]::new($false))
        $staleLink = Join-Path $f.target 'legacy-name'
        New-Item -ItemType Junction -Path $staleLink -Target $staleSource | Out-Null
        Remove-Item -LiteralPath $staleSource -Recurse -Force

        $plan = New-NativeSkillProjectionRuntimePlan -ManagedRoot $f.source -Config $f.config

        @($plan.removals.name) | Should -Be @('legacy-name')
        { Apply-NativeSkillProjection -Plan $plan -ReceiptPath $f.receipt } | Should -Not -Throw
        Get-Item -LiteralPath $staleLink -Force -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        @('enabled', 'resident') | ForEach-Object {
            Test-Path -LiteralPath (Join-Path $f.target "$_\SKILL.md") -PathType Leaf | Should -BeTrue
        }
    }

    It 'uses the prior receipt to retire links from a previous managed root' {
        $f = New-ProjectionFixture
        $oldPlan = New-NativeSkillProjectionRuntimePlan -ManagedRoot $f.source -Config $f.config
        Apply-NativeSkillProjection -Plan $oldPlan -ReceiptPath $f.receipt | Out-Null
        $newSource = Join-Path $TestDrive ('new-source-' + [guid]::NewGuid().ToString('N'))
        $current = Join-Path $newSource 'current'
        New-Item -ItemType Directory -Path $current -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $current 'SKILL.md'), "---`nname: current`ndescription: current capability.`n---`n", [Text.UTF8Encoding]::new($false))

        $newPlan = New-NativeSkillProjectionRuntimePlan -ManagedRoot $newSource -Config $f.config

        @($newPlan.removals.name | Sort-Object) | Should -Be @('enabled', 'resident')
        @($newPlan.removals.previous_link_target | Where-Object { $_ -notlike "$($f.source)*" }).Count | Should -Be 0
    }
}
