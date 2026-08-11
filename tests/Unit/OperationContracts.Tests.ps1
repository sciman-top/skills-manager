$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
. (Join-Path $repoRoot 'src\Domain\Receipt.ps1')

Describe 'OperationPlan and Receipt v1 contracts' {
    $fixtureRoot = Join-Path $repoRoot 'tests\fixtures\operation-contracts'
    $hashA = 'a' * 64
    $hashB = 'b' * 64

    function New-TestPlan([object[]]$Targets, [object[]]$Actions) {
        return New-OperationPlan `
            -OperationId 'op-test-001' `
            -Domain 'mcp' `
            -Mode 'dry_run' `
            -CreatedAt '2026-08-01T08:00:00Z' `
            -SourceRevision 'rev-1' `
            -Targets $Targets `
            -Actions $Actions
    }

    It 'keeps both declarative schemas parseable and versioned' {
        $planSchema = Get-Content -LiteralPath (Join-Path $repoRoot 'config\operation-plan.schema.json') -Raw | ConvertFrom-Json
        $receiptSchema = Get-Content -LiteralPath (Join-Path $repoRoot 'config\operation-receipt.schema.json') -Raw | ConvertFrom-Json

        $planSchema.'$schema' | Should Be 'https://json-schema.org/draft/2020-12/schema'
        $planSchema.properties.schema_version.const | Should Be 1
        $receiptSchema.properties.schema_version.const | Should Be 1
        @($receiptSchema.'$defs'.verification.required).Count | Should Be 4
    }

    It 'accepts the valid plan and receipt fixtures' {
        $plan = Get-Content -LiteralPath (Join-Path $fixtureRoot 'valid-plan.json') -Raw | ConvertFrom-Json
        $receipt = Get-Content -LiteralPath (Join-Path $fixtureRoot 'valid-receipt.json') -Raw | ConvertFrom-Json

        (Test-OperationPlanContract $plan).pass | Should Be $true
        (Test-OperationReceiptContract $receipt).pass | Should Be $true
    }

    It 'fails closed with structured findings for invalid fixtures' {
        $plan = Get-Content -LiteralPath (Join-Path $fixtureRoot 'invalid-plan.json') -Raw | ConvertFrom-Json
        $receipt = Get-Content -LiteralPath (Join-Path $fixtureRoot 'invalid-receipt.json') -Raw | ConvertFrom-Json
        $planResult = Test-OperationPlanContract $plan
        $receiptResult = Test-OperationReceiptContract $receipt

        $planResult.pass | Should Be $false
        @($planResult.findings | Where-Object code -eq 'created_at_invalid').Count | Should Be 1
        @($planResult.findings | Where-Object code -eq 'action_target_unknown').Count | Should Be 1
        @($planResult.findings | Where-Object code -eq 'sensitive_value_present').Count | Should Be 1
        $receiptResult.pass | Should Be $false
        @($receiptResult.findings | Where-Object code -eq 'timestamp_invalid').Count | Should Be 2
        @($receiptResult.findings | Where-Object code -eq 'verification_state_invalid').Count | Should Be 1
        foreach ($finding in @($planResult.findings) + @($receiptResult.findings)) {
            [string]::IsNullOrWhiteSpace([string]$finding.code) | Should Be $false
            [string]::IsNullOrWhiteSpace([string]$finding.severity) | Should Be $false
            [string]::IsNullOrWhiteSpace([string]$finding.path) | Should Be $false
            [string]::IsNullOrWhiteSpace([string]$finding.message) | Should Be $false
        }
    }

    It 'requires the domain-specific lifecycle binding for skill promotion plans' {
        $plan = New-OperationPlan -OperationId 'skill-lifecycle-fixture' -Domain skill_lifecycle -Mode apply -CreatedAt '2026-08-01T08:00:00Z' -SourceRevision $hashA -Targets @([pscustomobject]@{ target_ref = 'demo-skill'; path = 'C:\repo\overrides\custom\demo-skill'; before_hash = $null; desired_hash = $hashB; owner = 'skills-manager' }) -Actions @([pscustomobject]@{ type = 'create'; target_ref = 'demo-skill'; summary = 'Promote candidate'; risk = 'medium'; metadata = [pscustomobject]@{ allowed_paths = @('SKILL.md') } })
        $missing = Test-OperationPlanContract $plan
        $missing.pass | Should Be $false
        @($missing.findings.code) | Should Contain 'skill_lifecycle_missing'

        $plan | Add-Member -NotePropertyName lifecycle -NotePropertyValue ([pscustomobject]@{ skill_name = 'demo-skill'; candidate_directory = 'C:\repo\reports\skill-evolution\candidate\demo-skill'; candidate_fingerprint = $hashB; baseline_fingerprint = $hashA; catalog_fingerprint = $hashA; evaluation_path = 'C:\repo\reports\skill-evolution\evaluation.json'; evaluation_hash = $hashA; review_path = 'C:\repo\reports\skill-evolution\review.json'; review_hash = $hashB; review_expires_at = '2026-08-02T08:00:00Z'; allowed_paths = @('SKILL.md'); projection_disposition = 'cold_catalog_only'; host_mutation = $false })
        (Test-OperationPlanContract $plan).pass | Should Be $true
        $plan.lifecycle.allowed_paths = @('SKILL.md', 'references\..\..\skills.json')
        @((Test-OperationPlanContract $plan).findings.code) | Should Contain 'skill_lifecycle_paths_invalid'
    }

    It 'accepts activation only when it binds staged config and later controlled projection' {
        $plan = New-OperationPlan -OperationId 'skill-activation-fixture' -Domain skill_lifecycle -Mode apply -CreatedAt '2026-08-01T08:00:00Z' -SourceRevision $hashA -Targets @([pscustomobject]@{ target_ref = 'skills.json'; path = 'C:\repo\skills.json'; before_hash = $hashA; desired_hash = $hashB; owner = 'skills-manager' }) -Actions @([pscustomobject]@{ type = 'update'; target_ref = 'skills.json'; summary = 'Stage activation'; risk = 'high'; metadata = [pscustomobject]@{ allowed_paths = @('skills.json') } })
        $plan | Add-Member -NotePropertyName lifecycle -NotePropertyValue ([pscustomobject]@{ operation_kind = 'activation'; skill_name = 'demo-skill'; activation_action = 'enable'; package_fingerprint = $hashA; catalog_fingerprint = $hashA; config_path = 'C:\repo\skills.json'; config_before_hash = $hashA; config_after_hash = $hashB; desired_managed_link_includes = @('core-skill', 'demo-skill'); request_path = 'C:\repo\reports\skill-evolution\request.json'; request_hash = $hashA; review_path = 'C:\repo\reports\skill-evolution\decision.json'; review_hash = $hashB; review_expires_at = '2026-08-02T08:00:00Z'; allowed_paths = @('skills.json'); projection_disposition = 'staged_then_project_after_clean_gate'; host_mutation = $true; projection_token = 'PROJECT_SKILL_TO_HOST' })
        (Test-OperationPlanContract $plan).pass | Should Be $true
        $plan.lifecycle.projection_token = 'wrong'
        @((Test-OperationPlanContract $plan).findings.code) | Should Contain 'skill_activation_boundary_invalid'
    }

    It 'produces stable action ids and target ordering when input enumeration is reordered' {
        $targets = @(
            [pscustomobject]@{ target_ref = 'target-b'; path = 'C:\repo\b.json'; before_hash = $hashA; desired_hash = $hashB; owner = 'adapter' },
            [pscustomobject]@{ target_ref = 'target-a'; path = 'C:/repo/a.json'; before_hash = $hashA; desired_hash = $hashB; owner = 'adapter' }
        )
        $actions = @(
            [pscustomobject]@{ type = 'update'; target_ref = 'target-b'; summary = 'Update B'; risk = 'low' },
            [pscustomobject]@{ type = 'update'; target_ref = 'target-a'; summary = 'Update A'; risk = 'low' }
        )

        $first = New-TestPlan $targets $actions
        $second = New-TestPlan @($targets[1], $targets[0]) @($actions[1], $actions[0])

        (@($first.actions.action_id) -join ',') | Should Be (@($second.actions.action_id) -join ',')
        (@($first.targets.target_ref) -join ',') | Should Be 'target-a,target-b'
        ($first | ConvertTo-Json -Depth 20 -Compress) | Should Be ($second | ConvertTo-Json -Depth 20 -Compress)
    }

    It 'does not mutate constructor input objects' {
        $target = [pscustomobject]@{ target_ref = 'target-a'; path = 'C:/repo/a.json'; before_hash = $hashA; desired_hash = $hashB; owner = 'adapter' }
        $action = [pscustomobject]@{ type = 'update'; target_ref = 'target-a'; summary = 'Update A'; risk = 'low'; metadata = @{ env = @{ TOKEN = 'fixture-token' } } }
        $before = @($target, $action) | ConvertTo-Json -Depth 20 -Compress

        $null = New-TestPlan @($target) @($action)

        (@($target, $action) | ConvertTo-Json -Depth 20 -Compress) | Should Be $before
    }

    It 'detects out-of-root owner hash creation and source revision drift' {
        $targets = @(
            [pscustomobject]@{ target_ref = 'existing'; path = 'C:\repo\config.json'; before_hash = $hashA; desired_hash = $hashB; owner = 'adapter-a' },
            [pscustomobject]@{ target_ref = 'new'; path = 'C:\outside\new.json'; before_hash = $null; desired_hash = $hashB; owner = 'adapter-a' }
        )
        $actions = @(
            [pscustomobject]@{ type = 'update'; target_ref = 'existing'; summary = 'Update existing'; risk = 'low' },
            [pscustomobject]@{ type = 'create'; target_ref = 'new'; summary = 'Create new'; risk = 'low' }
        )
        $plan = New-TestPlan $targets $actions
        $current = @(
            [pscustomobject]@{ target_ref = 'existing'; exists = $true; current_hash = $hashB; owner = 'adapter-b' },
            [pscustomobject]@{ target_ref = 'new'; exists = $true; current_hash = $hashA; owner = 'adapter-a' }
        )

        $result = Test-OperationPlanFreshness -Plan $plan -CurrentTargets $current -AuthorizedRoots @('C:\repo') -CurrentSourceRevision 'rev-2'

        $result.pass | Should Be $false
        foreach ($code in @('target_out_of_root', 'target_owner_changed', 'target_hash_stale', 'target_created_since_plan', 'source_revision_stale')) {
            @($result.findings | Where-Object code -eq $code).Count | Should Be 1
        }
        (Test-OperationPathWithinRoot 'C:\repo2\file.json' 'C:\repo') | Should Be $false
        (Test-OperationPathWithinRoot 'C:\repo\sub\..\file.json' 'C:\repo') | Should Be $true
        (Test-OperationPathWithinRoot 'C:\repo\..\outside\file.json' 'C:\repo') | Should Be $false
    }

    It 'updates only the explicitly requested verification level' {
        $repoPass = Merge-OperationVerificationState -Current $null -Level repo_gates_passed -State pass
        $repoPass.repo_gates_passed | Should Be 'pass'
        $repoPass.host_loaded | Should Be 'not_run'
        $repoPass.live_accepted | Should Be 'not_run'

        $hostFail = Merge-OperationVerificationState -Current $repoPass -Level host_loaded -State fail
        $hostFail.repo_gates_passed | Should Be 'pass'
        $hostFail.host_loaded | Should Be 'fail'
        $hostFail.live_accepted | Should Be 'not_run'
    }

    It 'redacts tokens url credentials connection strings env headers and argv during construction' {
        $secrets = [pscustomobject]@{
            token = 'fixture-token-value'
            authorization = 'Bearer fixture-bearer-value'
            url = 'https://fixture-user:fixture-pass@example.invalid/path?api_key=fixture-query-value'
            connection = 'Host=db.invalid;Username=fixture-user;Password=fixture-db-password'
            npgsql = 'Password=fixture-npgsql-password;Host=db.invalid;Username=fixture-user'
            env = @{ SAFE_VALUE = 'fixture-env-value'; API_KEY = 'fixture-env-secret' }
            headers = @{ Accept = 'fixture-header-value'; Authorization = 'Bearer fixture-header-secret' }
            argv = @('--token', 'fixture-argv-secret')
        }
        $target = [pscustomobject]@{ target_ref = 'target-a'; path = 'C:\repo\a.json'; before_hash = $hashA; desired_hash = $hashB; owner = 'adapter' }
        $action = [pscustomobject]@{ type = 'native_command'; target_ref = 'target-a'; summary = 'Use sk-fixture12345678'; risk = 'medium'; metadata = $secrets }
        $plan = New-TestPlan @($target) @($action)
        $receipt = New-OperationReceipt -OperationId 'op-test-001' -Status dry_run -StartedAt '2026-08-01T08:00:00Z' -CompletedAt '2026-08-01T08:00:01Z' -Actions @($action) -Backups @($secrets)
        $serialized = @($plan, $receipt) | ConvertTo-Json -Depth 30 -Compress

        foreach ($secret in @('fixture-token-value', 'fixture-bearer-value', 'fixture-user', 'fixture-pass', 'fixture-query-value', 'fixture-db-password', 'fixture-npgsql-password', 'fixture-env-value', 'fixture-env-secret', 'fixture-header-value', 'fixture-header-secret', 'fixture-argv-secret', 'sk-fixture12345678')) {
            $serialized | Should Not Match ([regex]::Escape($secret))
        }
        $serialized | Should Match '<redacted>'
        (Test-OperationPlanContract $plan).pass | Should Be $true
        (Test-OperationReceiptContract $receipt).pass | Should Be $true
    }

    It 'keeps domain modules free of IO environment clock and terminal side effects' {
        $source = (Get-Content -LiteralPath (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1') -Raw) + "`n" + (Get-Content -LiteralPath (Join-Path $repoRoot 'src\Domain\Receipt.ps1') -Raw)
        $source | Should Not Match '(?im)^\s*(Get-Content|Set-Content|Add-Content|Remove-Item|Copy-Item|Move-Item|Test-Path|Resolve-Path|Get-Date|Write-Host|Write-Output|Start-Process|Invoke-WebRequest|exit)\b'
        $source | Should Not Match '(?i)\$env:'
    }

    It 'parses and constructs plain objects in the PowerShell 7 runtime' {
        $operationPath = (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1').Replace("'", "''")
        $receiptPath = (Join-Path $repoRoot 'src\Domain\Receipt.ps1').Replace("'", "''")
        $scriptText = ". '$operationPath'; . '$receiptPath'; `$p = New-OperationPlan -OperationId op-smoke -Domain mcp -Mode dry_run -CreatedAt 2026-08-01T08:00:00Z; `$r = New-OperationReceipt -OperationId op-smoke -Status dry_run -StartedAt 2026-08-01T08:00:00Z -CompletedAt 2026-08-01T08:00:01Z; [pscustomobject]@{ plan = `$p.schema_version; receipt = `$r.schema_version } | ConvertTo-Json -Compress"

        $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -Command $scriptText 2>&1)
        $exitCode = $LASTEXITCODE
        $result = ($output -join "`n") | ConvertFrom-Json

        $exitCode | Should Be 0
        $result.plan | Should Be 1
        $result.receipt | Should Be 1
    }
}
