. $PSScriptRoot\..\..\skills.ps1

function New-ReconciliationSkill([string]$root, [string]$name, [string]$description = "short", [bool]$system = $false) {
    $parent = if ($system) { Join-Path $root ".system" } else { $root }
    $dir = Join-Path $parent $name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Set-ContentUtf8 (Join-Path $dir "SKILL.md") ("---`nname: {0}`ndescription: {1}`n---`n" -f $name, $description)
}

function New-ReconciliationFixture([string]$root, [int]$budget = 8000) {
    New-ReconciliationSkill $root "resident"
    New-ReconciliationSkill $root "active"
    New-ReconciliationSkill $root "elsewhere"
    New-ReconciliationSkill $root "orphan"
    New-ReconciliationSkill $root "alias-old"
    New-ReconciliationSkill $root "large" ("x" * 100)
    New-ReconciliationSkill $root "system" "system" $true
    return [pscustomobject]@{
        enabled = $true
        active_profile = "default"
        budget_limit_chars = $budget
        external_metadata_reserve_chars = 0
        resident_names = @("resident")
        aliases = @([pscustomobject]@{ name = "alias-old"; replacement = "active" })
        profiles = [pscustomobject]@{
            default = [pscustomobject]@{ enabled_names = @("active") }
            coding = [pscustomobject]@{ enabled_names = @("elsewhere") }
            review = [pscustomobject]@{ enabled_names = @("active") }
        }
        sources = @([pscustomobject]@{ id = "fixture"; path = $root; priority = 1; platforms = @("codex") })
    }
}

function New-HostProposal([string]$hash, $changes) {
    return [pscustomobject]@{
        schema_version = 1
        decision_owner = "host_ai"
        base_config_sha256 = $hash
        changes = @($changes)
    }
}

Describe "Skill profile reconciliation advisor" {
    BeforeEach { $script:hash = "a" * 64 }

    It "Reports current unrouted skills, budgets, and overlap observations without writes" {
        $cfg = New-ReconciliationFixture (Join-Path $TestDrive "diagnostic")
        $cfg.profiles.coding.enabled_names = @("active", "elsewhere")
        $cfg.profiles.review.enabled_names = @("active")

        $result = New-SkillProfileReconciliationPlan $cfg $script:hash

        $result.pass | Should Be $true
        $result.decision_owner | Should Be "host_ai"
        $result.semantic_routing_performed | Should Be $false
        $result.writes_performed | Should Be $false
        $result.apply_allowed | Should Be $false
        $result.host_handoff.required | Should Be $true
        $result.host_handoff.semantic_owner | Should Be "host_ai"
        $result.host_handoff.next_action | Should Be "inspect_full_skill_descriptions_and_create_minimum_proposal"
        @($result.host_handoff.constraints) | Should Contain "fresh_task_replay_required"
        @($result.current.unrouted_names | Sort-Object) -join "," | Should Be "large,orphan"
        @($result.overlaps | Where-Object skill -eq "active").Count | Should Be 1
        @($result.actions).Count | Should Be 0
    }

    It "Turns a fresh host proposal into an exact add/remove dry-run change-set" {
        $cfg = New-ReconciliationFixture (Join-Path $TestDrive "valid")
        $proposal = New-HostProposal $script:hash @(
            [pscustomobject]@{ skill = "orphan"; add_profiles = @("coding"); remove_profiles = @(); reason = "Host matched the full description to coding work." }
            [pscustomobject]@{ skill = "elsewhere"; add_profiles = @("review"); remove_profiles = @("coding"); reason = "Host classified it as review-only." }
        )

        $result = New-SkillProfileReconciliationPlan $cfg $script:hash $proposal

        $result.pass | Should Be $true
        @($result.actions).Count | Should Be 3
        @($result.actions | Where-Object operation -eq "add").Count | Should Be 2
        @($result.actions | Where-Object operation -eq "remove").Count | Should Be 1
        @($result.proposed.unrouted_names | Sort-Object) -join "," | Should Be "large"
        $result.current.active_profile | Should Be "default"
        $result.proposed.active_profile | Should Be "default"
        $cfg.active_profile | Should Be "default"
        @($cfg.profiles.coding.enabled_names) | Should Be @("elsewhere")
    }

    It "Rejects stale hashes, malformed ownership, and unknown references" {
        $cfg = New-ReconciliationFixture (Join-Path $TestDrive "invalid")
        $proposal = [pscustomobject]@{
            schema_version = 2
            decision_owner = "router"
            base_config_sha256 = ("b" * 64)
            changes = @(
                [pscustomobject]@{ skill = "missing"; add_profiles = @("coding"); remove_profiles = @(); reason = "x" }
                [pscustomobject]@{ skill = "orphan"; add_profiles = @("unknown"); remove_profiles = @(); reason = "x" }
            )
        }

        $result = New-SkillProfileReconciliationPlan $cfg $script:hash $proposal

        $result.pass | Should Be $false
        @($result.findings | ForEach-Object code) | Should Contain "proposal_schema_invalid"
        @($result.findings | ForEach-Object code) | Should Contain "proposal_owner_invalid"
        @($result.findings | ForEach-Object code) | Should Contain "stale_config_hash"
        @($result.findings | ForEach-Object code) | Should Contain "unknown_skill"
        @($result.findings | ForEach-Object code) | Should Contain "unknown_profile"
        @($result.actions).Count | Should Be 0
    }

    It "Rejects system, resident, and alias profile mutations" {
        $cfg = New-ReconciliationFixture (Join-Path $TestDrive "protected")
        $proposal = New-HostProposal $script:hash @(
            [pscustomobject]@{ skill = "system"; add_profiles = @("coding"); remove_profiles = @(); reason = "x" }
            [pscustomobject]@{ skill = "resident"; add_profiles = @("coding"); remove_profiles = @(); reason = "x" }
            [pscustomobject]@{ skill = "alias-old"; add_profiles = @("coding"); remove_profiles = @(); reason = "x" }
        )

        $result = New-SkillProfileReconciliationPlan $cfg $script:hash $proposal

        $result.pass | Should Be $false
        @($result.findings | Where-Object code -eq "protected_skill_mutation").Count | Should Be 3
    }

    It "Rejects conflicting, duplicate, no-op, and unjustified changes" {
        $cfg = New-ReconciliationFixture (Join-Path $TestDrive "operations")
        $proposal = New-HostProposal $script:hash @(
            [pscustomobject]@{ skill = "active"; add_profiles = @("default"); remove_profiles = @("default"); reason = "x" }
            [pscustomobject]@{ skill = "elsewhere"; add_profiles = @(); remove_profiles = @("review"); reason = "x" }
            [pscustomobject]@{ skill = "orphan"; add_profiles = @("coding"); remove_profiles = @(); reason = "" }
            [pscustomobject]@{ skill = "active"; add_profiles = @("coding"); remove_profiles = @(); reason = "duplicate" }
        )

        $result = New-SkillProfileReconciliationPlan $cfg $script:hash $proposal

        $result.pass | Should Be $false
        @($result.findings | ForEach-Object code) | Should Contain "profile_operation_conflict"
        @($result.findings | ForEach-Object code) | Should Contain "add_existing_membership"
        @($result.findings | ForEach-Object code) | Should Contain "remove_missing_membership"
        @($result.findings | ForEach-Object code) | Should Contain "reason_missing"
        @($result.findings | ForEach-Object code) | Should Contain "duplicate_skill_change"
    }

    It "Fails closed when a proposal would exceed a profile metadata budget" {
        $cfg = New-ReconciliationFixture (Join-Path $TestDrive "budget") 30
        $proposal = New-HostProposal $script:hash @(
            [pscustomobject]@{ skill = "large"; add_profiles = @("coding"); remove_profiles = @(); reason = "Host proposal subject to deterministic budget." }
        )

        $result = New-SkillProfileReconciliationPlan $cfg $script:hash $proposal

        $result.pass | Should Be $false
        @($result.findings | ForEach-Object code) | Should Contain "proposed_budget_exceeded"
        $result.writes_performed | Should Be $false
    }

    It "Detects stale profile references before projection planning" {
        $cfg = New-ReconciliationFixture (Join-Path $TestDrive "stale")
        $cfg.profiles.coding.enabled_names = @("removed-skill")

        $result = New-SkillProfileReconciliationPlan $cfg $script:hash

        $result.pass | Should Be $false
        @($result.findings | ForEach-Object code) | Should Contain "stale_profile_reference"
        $null -eq $result.current | Should Be $true
    }

    It "Keeps the JSON envelope and exit behavior stable for malformed proposal files" {
        $proposalPath = Join-Path $TestDrive "malformed.json"
        Set-ContentUtf8 $proposalPath "{ not-json"
        $scriptPath = Join-Path $PSScriptRoot "..\..\scripts\plan-skill-profile-reconciliation.ps1"

        $raw = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -ProposalPath $proposalPath -Json -NoExit)
        $result = ($raw -join "`n") | ConvertFrom-Json

        $result.pass | Should Be $false
        $result.findings[0].code | Should Be "planner_error"
        $result.writes_performed | Should Be $false
        $result.apply_allowed | Should Be $false
    }
}
