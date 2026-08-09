. $PSScriptRoot\..\..\skills.ps1

function New-ProfileOptimizationConfig([string]$root) {
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    foreach ($name in @("active", "elsewhere", "orphan", "large")) {
        $dir = Join-Path $root $name
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-ContentUtf8 (Join-Path $dir "SKILL.md") ("---`nname: {0}`ndescription: {0} workflow`n---`n" -f $name)
    }
    return [pscustomobject]@{
        schema_version = 1
        skill_projection = [pscustomobject]@{
            enabled = $true
            active_profile = "default"
            budget_limit_chars = 8000
            external_metadata_reserve_chars = 0
            profiles = [pscustomobject]@{
                default = [pscustomobject]@{ enabled_names = @("active") }
                coding = [pscustomobject]@{ enabled_names = @("elsewhere") }
            }
            sources = @([pscustomobject]@{ id = "fixture"; path = $root; priority = 1; platforms = @("codex") })
        }
    }
}

function New-ProfileScriptSandbox([string]$root) {
    $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot "skills.ps1") -Destination (Join-Path $root "skills.ps1")
    $config = New-ProfileOptimizationConfig (Join-Path $root "skills")
    $configPath = Join-Path $root "skills.json"
    Set-ContentUtf8 $configPath ($config | ConvertTo-Json -Depth 50)
    return [pscustomobject]@{ root = $root; config_path = $configPath; config = $config; repo_root = $repoRoot }
}

Describe "P6 profile reachability retirement" {
    It "Does not bundle retired canary apply or acceptance functions" {
        foreach ($name in @("New-SkillProfileReconciliationApplyPlan", "Invoke-SkillProfileReconciliationApply", "Test-SkillProfileReconciliationReplay", "Complete-SkillProfileReconciliationCanary")) {
            Get-Command $name -ErrorAction SilentlyContinue | Should Be $null
        }
    }

    It "Does not let legacy profile membership exclude an enabled native skill after migration" {
        $cfg = New-ProfileOptimizationConfig (Join-Path $TestDrive "reachability")
        $configPath = Join-Path $TestDrive "reachability.json"
        Set-ContentUtf8 $configPath ($cfg | ConvertTo-Json -Depth 50)

        $plan = New-SkillProfileMigrationPlan -Config $cfg -ConfigPath $configPath
        $projection = New-SkillProjectionPlan $plan.migrated_config.skill_projection

        @($projection.disabled | Where-Object decision -eq "profile_excluded") | Should Be @()
        @($projection.active_names) | Should Contain "elsewhere"
        @($projection.active_names) | Should Contain "orphan"
        $projection.active_profile | Should Be ""
    }

    It "Migrates and rolls back the complete legacy config with a receipt" {
        $cfg = New-ProfileOptimizationConfig (Join-Path $TestDrive "round-trip")
        $configPath = Join-Path $TestDrive "round-trip.json"
        $receiptPath = Join-Path $TestDrive "reports\profile-migration.json"
        Set-ContentUtf8 $configPath ($cfg | ConvertTo-Json -Depth 50)
        $beforeHash = Get-FileContentHash $configPath

        $migrated = Invoke-SkillProfileMigration -ConfigPath $configPath -ReceiptPath $receiptPath -Token "MIGRATE_SKILL_PROFILE_CONFIG"

        $migrated.pass | Should Be $true
        $migrated.status | Should Be "migrated"
        $migrated.writes_performed | Should Be 1
        Test-Path -LiteralPath $receiptPath | Should Be $true
        Test-Path -LiteralPath $migrated.receipt.backup_path | Should Be $true
        $after = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $after.skill_projection.profile_compatibility.active_profile | Should Be "default"
        $after.skill_projection.PSObject.Properties["active_profile"] | Should Be $null
        $after.skill_projection.PSObject.Properties["profiles"] | Should Be $null

        $rolledBack = Invoke-SkillProfileMigrationRollback -ConfigPath $configPath -ReceiptPath $receiptPath -Token "ROLLBACK_SKILL_PROFILE_CONFIG"

        $rolledBack.pass | Should Be $true
        $rolledBack.status | Should Be "rolled_back"
        (Get-FileContentHash $configPath) | Should Be $beforeHash
        $restored = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $restored.skill_projection.active_profile | Should Be "default"
        $restored.skill_projection.profiles.default.enabled_names | Should Be @("active")
    }

    It "Keeps migration planning and execution host-local and provider-free" {
        $cfg = New-ProfileOptimizationConfig (Join-Path $TestDrive "side-effects")
        $configPath = Join-Path $TestDrive "side-effects.json"
        Set-ContentUtf8 $configPath ($cfg | ConvertTo-Json -Depth 50)

        $plan = New-SkillProfileMigrationPlan -Config $cfg -ConfigPath $configPath

        $plan.provider_calls | Should Be 0
        $plan.native_mutations | Should Be 0
        $plan.writes_performed | Should Be $false
        $plan.host_mutation | Should Be $false
    }

    It "Exposes compatibility migration through the standalone planner without writing" {
        $sandbox = New-ProfileScriptSandbox (Join-Path $TestDrive "planner-script")
        $scriptPath = Join-Path $sandbox.repo_root "scripts\plan-skill-profile-reconciliation.ps1"

        $raw = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -RepoRoot $sandbox.root -Json -NoExit)
        $result = ($raw -join "`n") | ConvertFrom-Json

        $result.pass | Should Be $true
        $result.status | Should Be "ready"
        $result.migration_required | Should Be $true
        $result.writes_performed | Should Be $false
        (Get-Content -LiteralPath $sandbox.config_path -Raw | ConvertFrom-Json).skill_projection.active_profile | Should Be "default"
    }

    It "Requires an explicit token for standalone migration and returns a receipt" {
        $sandbox = New-ProfileScriptSandbox (Join-Path $TestDrive "manager-script")
        $scriptPath = Join-Path $sandbox.repo_root "scripts\manage-skill-profile-reconciliation.ps1"
        $receiptPath = Join-Path $sandbox.root "reports\migration.json"

        $raw = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Mode Migrate -RepoRoot $sandbox.root -ReceiptPath $receiptPath -Token "MIGRATE_SKILL_PROFILE_CONFIG" -Json -NoExit)
        $result = ($raw -join "`n") | ConvertFrom-Json

        $result.pass | Should Be $true
        $result.status | Should Be "migrated"
        $result.writes_performed | Should Be 1
        Test-Path -LiteralPath $receiptPath | Should Be $true
    }

    It "Blocks retired profile canary planning, apply, and acceptance without writes" {
        $sandbox = New-ProfileScriptSandbox (Join-Path $TestDrive "deprecated-canary")
        $scriptPath = Join-Path $sandbox.repo_root "scripts\manage-skill-profile-reconciliation.ps1"
        $proposalPath = Join-Path $sandbox.root "proposal.json"
        Set-ContentUtf8 $proposalPath '{}'
        $beforeHash = Get-FileContentHash $sandbox.config_path

        foreach ($case in @(
                [pscustomobject]@{ mode = "Plan"; extra = @("-ProposalPath", $proposalPath) },
                [pscustomobject]@{ mode = "Apply"; extra = @() },
                [pscustomobject]@{ mode = "Accept"; extra = @() }
            )) {
            $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath, "-Mode", $case.mode, "-RepoRoot", $sandbox.root, "-Json", "-NoExit") + @($case.extra)
            $raw = @(& pwsh @arguments)
            $result = ($raw -join "`n") | ConvertFrom-Json

            $result.pass | Should Be $false
            $result.status | Should Be "deprecated"
            $result.writes_performed | Should Be 0
            @($result.findings.code) | Should Contain "profile_reconciliation_retired"
            (Get-FileContentHash $sandbox.config_path) | Should Be $beforeHash
        }
    }

    It "Keeps rollback available for an existing canary receipt" {
        $sandbox = New-ProfileScriptSandbox (Join-Path $TestDrive "legacy-canary-rollback")
        $scriptPath = Join-Path $sandbox.repo_root "scripts\manage-skill-profile-reconciliation.ps1"
        $receiptPath = Join-Path $sandbox.root "reports\legacy-canary.json"
        $operationId = "legacy-canary-fixture"
        $backupPath = Join-Path (Split-Path $receiptPath -Parent) (".skill-profile-backups\{0}.skills.json.bak" -f $operationId)
        New-Item -ItemType Directory -Path (Split-Path $backupPath -Parent) -Force | Out-Null
        $beforeBytes = [IO.File]::ReadAllBytes($sandbox.config_path)
        [IO.File]::WriteAllBytes($backupPath, $beforeBytes)
        $beforeHash = Get-FileContentHash $sandbox.config_path

        $changed = Get-Content -LiteralPath $sandbox.config_path -Raw | ConvertFrom-Json
        $changed.skill_projection.external_metadata_reserve_chars = 1
        Set-ContentUtf8 $sandbox.config_path ($changed | ConvertTo-Json -Depth 50)
        $afterHash = Get-FileContentHash $sandbox.config_path
        $receipt = [pscustomobject]@{
            schema_version = 1
            domain = "skill_profile_reconciliation"
            operation_id = $operationId
            status = "canary_applied"
            config_path = $sandbox.config_path
            before_config_sha256 = $beforeHash
            after_config_sha256 = $afterHash
            backup_path = $backupPath
        }
        Set-ContentUtf8 $receiptPath ($receipt | ConvertTo-Json -Depth 20)

        $raw = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Mode Rollback -RepoRoot $sandbox.root -ReceiptPath $receiptPath -Token "ROLLBACK_PROFILE_RECONCILIATION_CANARY" -Json -NoExit)
        $result = ($raw -join "`n") | ConvertFrom-Json

        $result.pass | Should Be $true
        $result.status | Should Be "rolled_back"
        $result.writes_performed | Should Be 1
        (Get-FileContentHash $sandbox.config_path) | Should Be $beforeHash
        (Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json).status | Should Be "rolled_back"
    }
}
