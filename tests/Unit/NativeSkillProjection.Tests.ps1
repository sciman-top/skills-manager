BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
    . (Join-Path $repoRoot 'src\Domain\SkillCatalog.ps1')
    . (Join-Path $repoRoot 'src\Application\SkillCatalogCompiler.ps1')
    . (Join-Path $repoRoot 'src\Application\SkillEligibilityPolicy.ps1')
    . (Join-Path $repoRoot 'src\Application\SkillProjection.ps1')
    . (Join-Path $repoRoot 'src\Application\NativeSkillProjection.ps1')
    . (Join-Path $repoRoot 'src\Application\NativeSkillProjectionCoordinator.ps1')

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
        $config = [pscustomobject]@{ skill_projection = [pscustomobject]@{ user_skill_root=$target; native_projection=[pscustomobject]@{ enabled=$true; owner='skills-manager'; target_root=$target; receipt_path=$receipt; notification_method='skills/changed' } } }
        return [pscustomobject]@{ source=$source; target=$target; receipt=$receipt; config=$config }
    }
}

Describe 'Native skill projection' {
    It 'projects complete managed packages without a repository metadata budget planner' {
        $f = New-ProjectionFixture
        $plan = New-NativeSkillProjectionRuntimePlan -ManagedRoot $f.source -Config $f.config

        $plan.status | Should -Be 'ready'
        $plan.kept_total | Should -Be 2
        @($plan.PSObject.Properties.Name) | Should -Not -Contain 'metadata_plan_id'
        @($plan.skills | ForEach-Object name) | Should -Be @('enabled','resident')
        (Test-NativeSkillProjectionPlanContract $plan).pass | Should -Be $true

        $applied = Apply-NativeSkillProjection -Plan $plan -ApplyToken $plan.apply_token -ReceiptPath $f.receipt
        $applied.status | Should -Be 'applied'
        Test-Path -LiteralPath (Join-Path $f.target 'enabled\SKILL.md') | Should -Be $true
        (Test-NativeSkillProjectionReceiptContract $applied.receipt).pass | Should -Be $true

        $rolledBack = Rollback-NativeSkillProjection -ReceiptPath $f.receipt
        $rolledBack.status | Should -Be 'rolled_back'
    }

    It 'keeps include filtering and target containment fail closed' {
        $f = New-ProjectionFixture
        $plan = New-NativeSkillProjectionRuntimePlan -ManagedRoot $f.source -Config $f.config -IncludedNames @('resident')
        @($plan.skills | ForEach-Object name) | Should -Be @('resident')
        { New-NativeSkillProjectionRuntimePlan -ManagedRoot $f.source -Config $f.config -IncludedNames @('missing') } | Should -Throw

        $f.config.skill_projection.native_projection.target_root = Join-Path $TestDrive 'other'
        { New-NativeSkillProjectionRuntimePlan -ManagedRoot $f.source -Config $f.config } | Should -Throw
    }

    It 'requires the plan token and rolls back a partial apply' {
        $f = New-ProjectionFixture
        $plan = New-NativeSkillProjectionRuntimePlan -ManagedRoot $f.source -Config $f.config
        { Apply-NativeSkillProjection -Plan $plan -ApplyToken 'wrong' -ReceiptPath $f.receipt } | Should -Throw
        Remove-Item -LiteralPath (Join-Path $f.source 'resident\SKILL.md') -Force
        { Apply-NativeSkillProjection -Plan $plan -ApplyToken $plan.apply_token -ReceiptPath $f.receipt } | Should -Throw
        Test-Path -LiteralPath (Join-Path $f.target 'enabled') | Should -Be $false
    }
}
