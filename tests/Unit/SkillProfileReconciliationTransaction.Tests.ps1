. $PSScriptRoot\..\..\skills.ps1

function New-TransactionSkill([string]$root, [string]$name, [string]$description = "short") {
    $dir = Join-Path $root $name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Set-ContentUtf8 (Join-Path $dir "SKILL.md") ("---`nname: {0}`ndescription: {1}`n---`n" -f $name, $description)
}

function New-TransactionConfig([string]$root) {
    New-TransactionSkill $root "resident"
    New-TransactionSkill $root "active"
    New-TransactionSkill $root "elsewhere"
    New-TransactionSkill $root "orphan"
    return [pscustomobject]@{
        skill_projection = [pscustomobject]@{
            enabled = $true
            active_profile = "default"
            budget_limit_chars = 8000
            external_metadata_reserve_chars = 0
            resident_names = @("resident")
            aliases = @()
            profiles = [pscustomobject]@{
                default = [pscustomobject]@{ enabled_names = @("active") }
                coding = [pscustomobject]@{ enabled_names = @("elsewhere") }
                review = [pscustomobject]@{ enabled_names = @("active") }
            }
            sources = @([pscustomobject]@{ id = "fixture"; path = $root; priority = 1; platforms = @("codex") })
        }
    }
}

function Write-TransactionConfig([string]$path, $cfg) {
    Set-ContentUtf8 $path ($cfg | ConvertTo-Json -Depth 50)
}

function New-TransactionProposal([string]$hash, [string]$profile = "coding") {
    return [pscustomobject]@{
        schema_version = 1
        decision_owner = "host_ai"
        base_config_sha256 = $hash
        changes = @(
            [pscustomobject]@{
                skill = "orphan"
                add_profiles = @($profile)
                remove_profiles = @()
                reason = "The host matched the complete skill description to this profile."
            }
        )
    }
}

function New-TransactionReplayFixture([string]$corpusPath, [string]$reportPath, [bool]$pass = $true) {
    @'
{
  "schema_version": 1,
  "profiles": ["coding"],
  "cases": [
    {"id":"direct","request":"Use the orphan workflow.","expectations":{"coding":{"required":["orphan"],"forbidden":[]}}},
    {"id":"indirect","request":"Perform the narrow job this workflow owns.","expectations":{"coding":{"required":["orphan"],"forbidden":[]}}},
    {"id":"negative","request":"Explain unrelated code without that workflow.","expectations":{"coding":{"required":[],"forbidden":["orphan"]}}},
    {"id":"edge","request":"Do not invoke orphan.","expectations":{"coding":{"required":[],"forbidden":["orphan"]}}}
  ]
}
'@ | Set-Content -LiteralPath $corpusPath -Encoding utf8
    $results = @("direct", "indirect", "negative", "edge" | ForEach-Object {
            [pscustomobject]@{
                profile = "coding"
                case_id = $_
                iteration = 1
                exit_code = 0
                parse_ok = $true
                expectation_pass = if ($_ -eq "edge") { $pass } else { $true }
                selected_skills = if ($_ -in @("direct", "indirect")) { @("orphan") } else { @() }
                missing_required = @()
                selected_forbidden = @()
            }
        })
    [pscustomobject]@{
        schema_version = 1
        run_id = "fixture-run"
        model = "fixture-model"
        execution_boundary = "fresh_ephemeral_task"
        original_profile = "default"
        restored_profile = "default"
        summary = @([pscustomobject]@{ profile = "coding"; calls = 4; expectation_passed = if ($pass) { 4 } else { 3 } })
        results = $results
    } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $reportPath -Encoding utf8
}

Describe "Skill profile reconciliation transaction" {
    BeforeEach {
        $script:skillRoot = Join-Path $TestDrive "skills"
        $script:configPath = Join-Path $TestDrive "skills.json"
        $script:receiptPath = Join-Path $TestDrive "reports\receipt.json"
        foreach ($path in @($script:skillRoot, (Join-Path $TestDrive "reports"))) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
        }
        $script:cfg = New-TransactionConfig $script:skillRoot
        Write-TransactionConfig $script:configPath $script:cfg
        $script:proposal = New-TransactionProposal (Get-FileContentHash $script:configPath)
    }

    It "Allows a bounded non-active profile canary and rejects active-profile membership changes" {
        $allowed = New-SkillProfileReconciliationApplyPlan $script:cfg $script:configPath $script:proposal
        $blockedProposal = New-TransactionProposal (Get-FileContentHash $script:configPath) "default"
        $blocked = New-SkillProfileReconciliationApplyPlan $script:cfg $script:configPath $blockedProposal

        $allowed.pass | Should Be $true
        $allowed.apply_allowed | Should Be $true
        $allowed.activation_boundary | Should Be "fresh_task"
        $blocked.pass | Should Be $false
        @($blocked.findings.code) | Should Contain "active_profile_membership_change_forbidden"
    }

    It "Applies one atomic config write with a receipt and leaves active_profile unchanged" {
        $result = Invoke-SkillProfileReconciliationApply -Config $script:cfg -ConfigPath $script:configPath `
            -Proposal $script:proposal -ReceiptPath $script:receiptPath -Token "APPLY_PROFILE_RECONCILIATION_CANARY"

        $result.pass | Should Be $true
        $result.status | Should Be "canary_applied"
        $result.writes_performed | Should Be 1
        Test-Path -LiteralPath $script:receiptPath | Should Be $true
        Test-Path -LiteralPath $result.receipt.backup_path | Should Be $true
        $after = Get-Content -LiteralPath $script:configPath -Raw | ConvertFrom-Json
        $after.skill_projection.active_profile | Should Be "default"
        @($after.skill_projection.profiles.coding.enabled_names) | Should Contain "orphan"
        $result.receipt.replay.status | Should Be "not_run"
        $result.receipt.live_accepted | Should Be "not_run"
    }

    It "Fails closed when the proposal hash is stale or an action targets the active profile" {
        $changed = Get-Content -LiteralPath $script:configPath -Raw | ConvertFrom-Json
        $changed.skill_projection.external_metadata_reserve_chars = 1
        Write-TransactionConfig $script:configPath $changed

        $stale = Invoke-SkillProfileReconciliationApply -Config $changed -ConfigPath $script:configPath `
            -Proposal $script:proposal -ReceiptPath $script:receiptPath -Token "APPLY_PROFILE_RECONCILIATION_CANARY"

        $stale.pass | Should Be $false
        $stale.writes_performed | Should Be 0
        @($stale.findings.code) | Should Contain "stale_config_hash"
        Test-Path -LiteralPath $script:receiptPath | Should Be $false
    }

    It "Rejects an automatic canary that leaves less than the minimum metadata headroom" {
        $initial = New-SkillProfileReconciliationPlan $script:cfg.skill_projection (Get-FileContentHash $script:configPath) $script:proposal
        $codingBudget = @($initial.proposed.profile_budgets | Where-Object profile -eq "coding")[0]
        $script:cfg.skill_projection.profiles.coding | Add-Member -NotePropertyName budget_limit_chars -NotePropertyValue ([int]$codingBudget.estimated_metadata_chars + 100) -Force
        Write-TransactionConfig $script:configPath $script:cfg
        $proposal = New-TransactionProposal (Get-FileContentHash $script:configPath)

        $result = New-SkillProfileReconciliationApplyPlan $script:cfg $script:configPath $proposal

        $result.pass | Should Be $false
        $result.apply_allowed | Should Be $false
        @($result.findings.code) | Should Contain "proposed_budget_headroom_insufficient"
    }

    It "Accepts only fresh-task replay with direct and negative coverage for every added skill" {
        $apply = Invoke-SkillProfileReconciliationApply -Config $script:cfg -ConfigPath $script:configPath `
            -Proposal $script:proposal -ReceiptPath $script:receiptPath -Token "APPLY_PROFILE_RECONCILIATION_CANARY"
        $corpusPath = Join-Path $TestDrive "corpus.json"
        $reportPath = Join-Path $TestDrive "report.json"
        New-TransactionReplayFixture $corpusPath $reportPath $true

        $accepted = Complete-SkillProfileReconciliationCanary -ConfigPath $script:configPath -ReceiptPath $script:receiptPath `
            -ReplayReportPath $reportPath -CorpusPath $corpusPath -Token "ACCEPT_PROFILE_RECONCILIATION_CANARY"

        $apply.pass | Should Be $true
        $accepted.pass | Should Be $true
        $accepted.status | Should Be "accepted"
        $accepted.replay_status | Should Be "host_evaluation_partial_pass"
        (Get-Content -LiteralPath $script:receiptPath -Raw | ConvertFrom-Json).live_accepted | Should Be "not_run"
    }

    It "Automatically rolls back a failed canary replay without touching active_profile" {
        $beforeHash = Get-FileContentHash $script:configPath
        $apply = Invoke-SkillProfileReconciliationApply -Config $script:cfg -ConfigPath $script:configPath `
            -Proposal $script:proposal -ReceiptPath $script:receiptPath -Token "APPLY_PROFILE_RECONCILIATION_CANARY"
        $corpusPath = Join-Path $TestDrive "corpus-fail.json"
        $reportPath = Join-Path $TestDrive "report-fail.json"
        New-TransactionReplayFixture $corpusPath $reportPath $false

        $result = Complete-SkillProfileReconciliationCanary -ConfigPath $script:configPath -ReceiptPath $script:receiptPath `
            -ReplayReportPath $reportPath -CorpusPath $corpusPath -Token "ACCEPT_PROFILE_RECONCILIATION_CANARY" -RollbackOnFailure

        $apply.pass | Should Be $true
        $result.pass | Should Be $false
        $result.status | Should Be "rolled_back"
        $result.rollback_performed | Should Be $true
        (Get-FileContentHash $script:configPath) | Should Be $beforeHash
        (Get-Content -LiteralPath $script:configPath -Raw | ConvertFrom-Json).skill_projection.active_profile | Should Be "default"
    }

    It "Blocks rollback when skills.json changed after canary apply" {
        $apply = Invoke-SkillProfileReconciliationApply -Config $script:cfg -ConfigPath $script:configPath `
            -Proposal $script:proposal -ReceiptPath $script:receiptPath -Token "APPLY_PROFILE_RECONCILIATION_CANARY"
        Add-Content -LiteralPath $script:configPath -Value " "

        $rollback = Invoke-SkillProfileReconciliationRollback -ConfigPath $script:configPath -ReceiptPath $script:receiptPath `
            -Token "ROLLBACK_PROFILE_RECONCILIATION_CANARY"

        $apply.pass | Should Be $true
        $rollback.pass | Should Be $false
        $rollback.status | Should Be "blocked"
        @($rollback.findings.code) | Should Contain "rollback_target_stale"
    }

    It "Preserves another writer's lock when canary lock acquisition fails" {
        $lockPath = "{0}.profile-reconciliation.lock" -f $script:configPath
        Set-Content -LiteralPath $lockPath -Value "other-writer" -Encoding utf8
        $beforeHash = Get-FileContentHash $script:configPath

        $result = Invoke-SkillProfileReconciliationApply -Config $script:cfg -ConfigPath $script:configPath `
            -Proposal $script:proposal -ReceiptPath $script:receiptPath -Token "APPLY_PROFILE_RECONCILIATION_CANARY"

        $result.pass | Should Be $false
        $result.writes_performed | Should Be 0
        (Test-Path -LiteralPath $lockPath) | Should Be $true
        (Get-Content -LiteralPath $lockPath -Raw).Trim() | Should Be "other-writer"
        (Get-FileContentHash $script:configPath) | Should Be $beforeHash
    }

    It "Exposes the bounded apply plan through the standalone manager JSON contract" {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
        $sandboxRoot = Join-Path $TestDrive "manager"
        New-Item -ItemType Directory -Path $sandboxRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repoRoot "skills.ps1") -Destination (Join-Path $sandboxRoot "skills.ps1")
        $managerConfig = New-TransactionConfig (Join-Path $sandboxRoot "skills")
        $managerConfigPath = Join-Path $sandboxRoot "skills.json"
        Write-TransactionConfig $managerConfigPath $managerConfig
        $proposalPath = Join-Path $sandboxRoot "proposal.json"
        New-TransactionProposal (Get-FileContentHash $managerConfigPath) | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $proposalPath -Encoding utf8

        $raw = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\manage-skill-profile-reconciliation.ps1") `
                -Mode Plan -RepoRoot $sandboxRoot -ProposalPath $proposalPath -Json -NoExit)
        $result = ($raw -join "`n") | ConvertFrom-Json

        $result.pass | Should Be $true
        $result.apply_allowed | Should Be $true
        $result.writes_performed | Should Be $false
        $result.activation_boundary | Should Be "fresh_task"
    }
}
