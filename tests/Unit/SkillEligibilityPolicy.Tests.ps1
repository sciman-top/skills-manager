$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
$catalogDomainPath = Join-Path $repoRoot 'src\Domain\SkillCatalog.ps1'
$policyPath = Join-Path $repoRoot 'src\Application\SkillEligibilityPolicy.ps1'
if (Test-Path -LiteralPath $catalogDomainPath -PathType Leaf) { . $catalogDomainPath }
if (Test-Path -LiteralPath $policyPath -PathType Leaf) { . $policyPath }

Describe 'Skill eligibility policy' {
    It 'denies deterministic safety failures even when semantic input claims selection' {
        $policy = Get-Command Evaluate-SkillEligibility -ErrorAction SilentlyContinue
        $policy | Should Not BeNullOrEmpty
        if ($null -eq $policy) { return }

        $root = Join-Path $TestDrive 'managed'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $skill = [pscustomobject]@{
            name = 'unsafe-skill'
            path = Join-Path $TestDrive 'outside\SKILL.md'
            source_root = $root
            availability = 'available'
            freshness = 'fresh'
            side_effect = 'controlled_write'
            requires_approval = $true
            dependencies = @('missing-dependency')
            surfaces = @('cli')
            semantic_confidence = 1.0
            selected = $true
            profile = 'default'
        }

        $result = Evaluate-SkillEligibility -Skill $skill -Surface 'cli' -AllowedRoots @($root) -ApprovalGranted $false -AvailableDependencies @()

        $result.decision | Should Be 'deny'
        $result.eligible | Should Be $false
        @($result.findings | Where-Object code -eq 'path_outside_allowed_root').Count | Should Be 1
        @($result.findings | Where-Object code -eq 'dependency_missing').Count | Should Be 1
        @($result.findings | Where-Object code -eq 'approval_required').Count | Should Be 1
        $result.decision_owner | Should Be 'deterministic_policy'
        $result.semantic_selection_performed | Should Be $false
        $result.profile_filter_applied | Should Be $false
        $result.provider_calls | Should Be 0
        $result.writes | Should Be 0
        (Test-SkillEligibilityResultContract $result).pass | Should Be $true
    }

    It 'allows a contained fresh read-only skill without consulting profile state' {
        $policy = Get-Command Evaluate-SkillEligibility -ErrorAction SilentlyContinue
        $policy | Should Not BeNullOrEmpty
        if ($null -eq $policy) { return }

        $skill = [pscustomobject]@{
            name = 'safe-skill'
            path = Join-Path $TestDrive 'managed\SKILL.md'
            source_root = Join-Path $TestDrive 'managed'
            availability = 'available'
            freshness = 'fresh'
            side_effect = 'read_only'
            dependencies = @()
            surfaces = @('cli')
            profile = 'non-active-profile'
        }
        New-Item -ItemType Directory -Path $skill.source_root -Force | Out-Null

        $result = Evaluate-SkillEligibility -Skill $skill -Surface 'cli' -AllowedRoots @($skill.source_root) -ApprovalGranted $false

        $result.decision | Should Be 'allow'
        $result.eligible | Should Be $true
        @($result.findings).Count | Should Be 0
        $result.profile_filter_applied | Should Be $false
        (Test-SkillEligibilityResultContract $result).pass | Should Be $true
    }
}
