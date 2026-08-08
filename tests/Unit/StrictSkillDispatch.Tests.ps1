$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
. (Join-Path $repoRoot 'src\Domain\SkillCatalog.ps1')
. (Join-Path $repoRoot 'src\Application\SkillEligibilityPolicy.ps1')
. (Join-Path $repoRoot 'src\Domain\NativeInvocationTrace.ps1')
. (Join-Path $repoRoot 'src\Infrastructure\NativeInvocationTraceAdapters.ps1')

$strictDispatchPath = Join-Path $repoRoot 'src\Application\StrictSkillDispatch.ps1'
$appServerAdapterPath = Join-Path $repoRoot 'src\Infrastructure\AppServerSkillDispatchAdapter.ps1'
if (Test-Path -LiteralPath $strictDispatchPath -PathType Leaf) { . $strictDispatchPath }
if (Test-Path -LiteralPath $appServerAdapterPath -PathType Leaf) { . $appServerAdapterPath }

function Assert-StrictDispatchCommandsAvailable {
    $dispatch = Get-Command Invoke-StrictSkillDispatch -ErrorAction SilentlyContinue
    $adapter = Get-Command New-AppServerSkillDispatchAdapter -ErrorAction SilentlyContinue
    $dispatch | Should Not BeNullOrEmpty
    $adapter | Should Not BeNullOrEmpty
    return ($null -ne $dispatch -and $null -ne $adapter)
}

function New-StrictDispatchTestSkill {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $sourceRoot = Join-Path $Root $Name
    New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null
    return [pscustomobject][ordered]@{
        schema_version = 1
        kind = 'skill'
        name = $Name
        description = "Use $Name for the requested task."
        path = Join-Path $sourceRoot 'SKILL.md'
        source_root = $sourceRoot
        availability = 'available'
        freshness = 'fresh'
        side_effect = 'read_only'
        load_side_effect = 'read_only'
        dependencies = @()
        surfaces = @('app_server')
    }
}

function New-StrictDispatchTestEligibility {
    param(
        [Parameter(Mandatory = $true)]$Skill,
        [string]$AllowedRoot,
        [bool]$ApprovalGranted = $false
    )

    return Evaluate-SkillEligibility -Skill $Skill -Surface 'app_server' -AllowedRoots @($AllowedRoot) -ApprovalGranted $ApprovalGranted
}

function New-StrictDispatchTestReceipt {
    param(
        [Parameter(Mandatory = $true)][string[]]$CandidateNames,
        [Parameter(Mandatory = $true)][string[]]$SelectedNames,
        [string]$Status = 'accepted'
    )

    return [pscustomobject][ordered]@{
        schema_version = 1
        receipt_id = 'har-test-001'
        status = $Status
        decision_owner = 'host_ai'
        request_id = 'strict-request-001'
        candidate_names = @($CandidateNames)
        selected_names = @($SelectedNames)
        captured_at = '2026-08-07T06:00:00Z'
        freshness = 'fresh'
        provider_calls = 0
        native_mutations = 0
        writes = 0
    }
}

function New-StrictDispatchTestRequest {
    param([bool]$StrictDispatch = $true)

    return [pscustomobject][ordered]@{
        request_id = 'strict-request-001'
        strict_dispatch = $StrictDispatch
        surface = 'app_server'
        correlation_id = 'thread-strict-test'
    }
}

Describe 'Strict App Server skill dispatch fallback' {
    BeforeEach {
        $script:testRoot = Join-Path $TestDrive 'managed-skills'
        New-Item -ItemType Directory -Path $script:testRoot -Force | Out-Null
    }

    It 'never enters fallback for an ordinary request' {
        if (-not (Assert-StrictDispatchCommandsAvailable)) { return }

        $skill = New-StrictDispatchTestSkill -Root $script:testRoot -Name 'safe-skill'
        $eligibility = New-StrictDispatchTestEligibility -Skill $skill -AllowedRoot $script:testRoot
        $receipt = New-StrictDispatchTestReceipt -CandidateNames @('safe-skill') -SelectedNames @('safe-skill')
        $adapter = New-AppServerSkillDispatchAdapter -CapturedAt '2026-08-07T06:00:00Z' -SupportedItemTypes @('skill')

        $result = Invoke-StrictSkillDispatch -Request (New-StrictDispatchTestRequest -StrictDispatch $false) -Candidates @($skill) -EligibilityResults @($eligibility) -HostAdjudicationReceipt $receipt -Adapter $adapter -MaxCandidates 2 -CapturedAt '2026-08-07T06:00:01Z'

        $result.status | Should Be 'not_requested'
        $result.fallback_entered | Should Be $false
        $result.injection | Should BeNullOrEmpty
        $result.writes | Should Be 0
    }

    It 'requires an explicit strict request before fallback can start' {
        if (-not (Assert-StrictDispatchCommandsAvailable)) { return }

        $skill = New-StrictDispatchTestSkill -Root $script:testRoot -Name 'safe-skill'
        $eligibility = New-StrictDispatchTestEligibility -Skill $skill -AllowedRoot $script:testRoot
        $receipt = New-StrictDispatchTestReceipt -CandidateNames @('safe-skill') -SelectedNames @('safe-skill')
        $adapter = New-AppServerSkillDispatchAdapter -CapturedAt '2026-08-07T06:00:00Z' -SupportedItemTypes @('skill')

        $result = Invoke-StrictSkillDispatch -Request ([pscustomobject]@{ request_id = 'ordinary'; surface = 'app_server' }) -Candidates @($skill) -EligibilityResults @($eligibility) -HostAdjudicationReceipt $receipt -Adapter $adapter -MaxCandidates 2 -CapturedAt '2026-08-07T06:00:01Z'

        $result.status | Should Be 'not_requested'
        $result.fallback_entered | Should Be $false
        $result.injection | Should BeNullOrEmpty
    }

    It 'creates a bounded type=skill injection only after policy allow and host adjudication' {
        if (-not (Assert-StrictDispatchCommandsAvailable)) { return }

        $skill = New-StrictDispatchTestSkill -Root $script:testRoot -Name 'safe-skill'
        $eligibility = New-StrictDispatchTestEligibility -Skill $skill -AllowedRoot $script:testRoot
        $receipt = New-StrictDispatchTestReceipt -CandidateNames @('safe-skill') -SelectedNames @('safe-skill')
        $adapter = New-AppServerSkillDispatchAdapter -CapturedAt '2026-08-07T06:00:00Z' -SupportedItemTypes @('skill')

        $result = Invoke-StrictSkillDispatch -Request (New-StrictDispatchTestRequest) -Candidates @($skill) -EligibilityResults @($eligibility) -HostAdjudicationReceipt $receipt -Adapter $adapter -MaxCandidates 2 -CapturedAt '2026-08-07T06:00:01Z'

        $result.status | Should Be 'planned'
        $result.fallback_entered | Should Be $true
        @($result.candidates).Count | Should Be 1
        @($result.injection.items).Count | Should Be 1
        $result.injection.items[0].type | Should Be 'skill'
        $result.injection.items[0].name | Should Be 'safe-skill'
        $result.writes | Should Be 0
        $result.native_mutations | Should Be 0
        $result.provider_calls | Should Be 0
        (Test-AppServerSkillInjectionRequestContract $result.injection).pass | Should Be $true
        (Test-StrictSkillDispatchResultContract $result).pass | Should Be $true
    }

    It 'fails closed instead of accepting an oversized candidate set' {
        if (-not (Assert-StrictDispatchCommandsAvailable)) { return }

        $skills = @(
            (New-StrictDispatchTestSkill -Root $script:testRoot -Name 'skill-one'),
            (New-StrictDispatchTestSkill -Root $script:testRoot -Name 'skill-two'),
            (New-StrictDispatchTestSkill -Root $script:testRoot -Name 'skill-three')
        )
        $eligibility = @($skills | ForEach-Object { New-StrictDispatchTestEligibility -Skill $_ -AllowedRoot $script:testRoot })
        $receipt = New-StrictDispatchTestReceipt -CandidateNames @('skill-one', 'skill-two', 'skill-three') -SelectedNames @('skill-one')
        $adapter = New-AppServerSkillDispatchAdapter -CapturedAt '2026-08-07T06:00:00Z' -SupportedItemTypes @('skill')

        $result = Invoke-StrictSkillDispatch -Request (New-StrictDispatchTestRequest) -Candidates $skills -EligibilityResults $eligibility -HostAdjudicationReceipt $receipt -Adapter $adapter -MaxCandidates 2 -CapturedAt '2026-08-07T06:00:01Z'

        $result.status | Should Be 'candidate_set_too_large'
        $result.fallback_entered | Should Be $true
        $result.injection | Should BeNullOrEmpty
        $result.trace.outcome | Should Be 'abstained'
    }

    It 'does not inject denied skills even when the host receipt selects them' {
        if (-not (Assert-StrictDispatchCommandsAvailable)) { return }

        $safe = New-StrictDispatchTestSkill -Root $script:testRoot -Name 'safe-skill'
        $denied = New-StrictDispatchTestSkill -Root $script:testRoot -Name 'denied-skill'
        $denied.path = Join-Path $TestDrive 'outside\SKILL.md'
        $eligibility = @(
            (New-StrictDispatchTestEligibility -Skill $safe -AllowedRoot $script:testRoot),
            (New-StrictDispatchTestEligibility -Skill $denied -AllowedRoot $script:testRoot)
        )
        $receipt = New-StrictDispatchTestReceipt -CandidateNames @('safe-skill') -SelectedNames @('denied-skill')
        $adapter = New-AppServerSkillDispatchAdapter -CapturedAt '2026-08-07T06:00:00Z' -SupportedItemTypes @('skill')

        $result = Invoke-StrictSkillDispatch -Request (New-StrictDispatchTestRequest) -Candidates @($safe, $denied) -EligibilityResults $eligibility -HostAdjudicationReceipt $receipt -Adapter $adapter -MaxCandidates 2 -CapturedAt '2026-08-07T06:00:01Z'

        $result.status | Should Be 'adjudication_invalid'
        $result.injection | Should BeNullOrEmpty
        @($result.candidates | Where-Object name -eq 'denied-skill').Count | Should Be 0
    }

    It 'does not inject a candidate without an allow decision' {
        if (-not (Assert-StrictDispatchCommandsAvailable)) { return }

        $skill = New-StrictDispatchTestSkill -Root $script:testRoot -Name 'unadjudicated-skill'
        $receipt = New-StrictDispatchTestReceipt -CandidateNames @('unadjudicated-skill') -SelectedNames @('unadjudicated-skill')
        $adapter = New-AppServerSkillDispatchAdapter -CapturedAt '2026-08-07T06:00:00Z' -SupportedItemTypes @('skill')

        $result = Invoke-StrictSkillDispatch -Request (New-StrictDispatchTestRequest) -Candidates @($skill) -EligibilityResults @() -HostAdjudicationReceipt $receipt -Adapter $adapter -MaxCandidates 2 -CapturedAt '2026-08-07T06:00:01Z'

        $result.status | Should Be 'no_eligible_candidates'
        $result.injection | Should BeNullOrEmpty
    }

    It 'requires a valid host adjudication receipt before injection' {
        if (-not (Assert-StrictDispatchCommandsAvailable)) { return }

        $skill = New-StrictDispatchTestSkill -Root $script:testRoot -Name 'safe-skill'
        $eligibility = New-StrictDispatchTestEligibility -Skill $skill -AllowedRoot $script:testRoot
        $adapter = New-AppServerSkillDispatchAdapter -CapturedAt '2026-08-07T06:00:00Z' -SupportedItemTypes @('skill')

        $result = Invoke-StrictSkillDispatch -Request (New-StrictDispatchTestRequest) -Candidates @($skill) -EligibilityResults @($eligibility) -Adapter $adapter -MaxCandidates 2 -CapturedAt '2026-08-07T06:00:01Z'

        $result.status | Should Be 'adjudication_required'
        $result.injection | Should BeNullOrEmpty
        $result.trace.outcome | Should Be 'abstained'
    }

    It 'reports platform_na when App Server skill injection is unsupported' {
        if (-not (Assert-StrictDispatchCommandsAvailable)) { return }

        $skill = New-StrictDispatchTestSkill -Root $script:testRoot -Name 'safe-skill'
        $eligibility = New-StrictDispatchTestEligibility -Skill $skill -AllowedRoot $script:testRoot
        $receipt = New-StrictDispatchTestReceipt -CandidateNames @('safe-skill') -SelectedNames @('safe-skill')
        $adapter = New-AppServerSkillDispatchAdapter -CapturedAt '2026-08-07T06:00:00Z' -SupportedItemTypes @('mcp')

        $result = Invoke-StrictSkillDispatch -Request (New-StrictDispatchTestRequest) -Candidates @($skill) -EligibilityResults @($eligibility) -HostAdjudicationReceipt $receipt -Adapter $adapter -MaxCandidates 2 -CapturedAt '2026-08-07T06:00:01Z'

        $result.status | Should Be 'platform_na'
        $result.platform_na | Should Be $true
        $result.injection | Should BeNullOrEmpty
        $result.trace.outcome | Should Be 'abstained'
        $result.writes | Should Be 0
        $result.native_mutations | Should Be 0
        $result.provider_calls | Should Be 0
    }

    It 'shares the NativeInvocationTrace truth boundary for planned injection' {
        if (-not (Assert-StrictDispatchCommandsAvailable)) { return }

        $skill = New-StrictDispatchTestSkill -Root $script:testRoot -Name 'safe-skill'
        $eligibility = New-StrictDispatchTestEligibility -Skill $skill -AllowedRoot $script:testRoot
        $receipt = New-StrictDispatchTestReceipt -CandidateNames @('safe-skill') -SelectedNames @('safe-skill')
        $adapter = New-AppServerSkillDispatchAdapter -CapturedAt '2026-08-07T06:00:00Z' -SupportedItemTypes @('skill')

        $result = Invoke-StrictSkillDispatch -Request (New-StrictDispatchTestRequest) -Candidates @($skill) -EligibilityResults @($eligibility) -HostAdjudicationReceipt $receipt -Adapter $adapter -MaxCandidates 2 -CapturedAt '2026-08-07T06:00:01Z'

        $result.trace.stages.listed.observed | Should Be $true
        $result.trace.stages.selected.observed | Should Be $true
        $result.trace.stages.injected.observed | Should Be $true
        $result.trace.stages.executed.observed | Should Be $false
        $result.trace.truth_level | Should Be 'host_evaluation_partial'
        $result.trace.invocation_observable | Should Be $false
        (Test-NativeInvocationTraceContract $result.trace).pass | Should Be $true
    }

    It 'keeps adapter and dispatch contracts zero-side-effect' {
        if (-not (Assert-StrictDispatchCommandsAvailable)) { return }

        $adapter = New-AppServerSkillDispatchAdapter -CapturedAt '2026-08-07T06:00:00Z' -SupportedItemTypes @('skill')
        $adapter.provider_calls | Should Be 0
        $adapter.native_mutations | Should Be 0
        $adapter.writes | Should Be 0
        (Test-AppServerSkillDispatchAdapterContract $adapter).pass | Should Be $true
    }
}
