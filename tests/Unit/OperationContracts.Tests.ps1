BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
    . (Join-Path $repoRoot 'src\Domain\Receipt.ps1')

}
Describe 'OperationPlan and Receipt v1 contracts' {
    BeforeAll {
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
}

    It 'accepts the valid plan fixture and constructs a receipt' {
        $plan = Get-Content -LiteralPath (Join-Path $fixtureRoot 'valid-plan.json') -Raw | ConvertFrom-Json
        $receipt = New-OperationReceipt -OperationId 'op-test-001' -Status dry_run -StartedAt '2026-08-01T08:00:00Z' -CompletedAt '2026-08-01T08:00:01Z'

        (Test-OperationPlanContract $plan).pass | Should -Be $true
        $receipt.schema_version | Should -Be 1
        $receipt.status | Should -Be 'dry_run'
    }

    It 'rejects invalid receipt timestamps at construction time' {
        { New-OperationReceipt -OperationId 'op-test-001' -Status dry_run -StartedAt 'not-a-timestamp' -CompletedAt '2026-08-01T08:00:01Z' } | Should -Throw '*RFC3339*'
    }

    It 'rejects invalid receipt status at parameter binding' {
        { New-OperationReceipt -OperationId 'op-test-001' -Status unknown -StartedAt '2026-08-01T08:00:00Z' -CompletedAt '2026-08-01T08:00:01Z' } | Should -Throw
    }

    It 'fails closed with structured findings for an invalid plan fixture' {
        $plan = Get-Content -LiteralPath (Join-Path $fixtureRoot 'invalid-plan.json') -Raw | ConvertFrom-Json
        $planResult = Test-OperationPlanContract $plan

        $planResult.pass | Should -Be $false
        @($planResult.findings | Where-Object code -eq 'created_at_invalid').Count | Should -Be 1
        @($planResult.findings | Where-Object code -eq 'action_target_unknown').Count | Should -Be 1
        @($planResult.findings | Where-Object code -eq 'sensitive_value_present').Count | Should -Be 1
        foreach ($finding in @($planResult.findings)) {
            [string]::IsNullOrWhiteSpace([string]$finding.code) | Should -Be $false
            [string]::IsNullOrWhiteSpace([string]$finding.severity) | Should -Be $false
            [string]::IsNullOrWhiteSpace([string]$finding.path) | Should -Be $false
            [string]::IsNullOrWhiteSpace([string]$finding.message) | Should -Be $false
        }
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

        (@($first.actions.action_id) -join ',') | Should -Be (@($second.actions.action_id) -join ',')
        (@($first.targets.target_ref) -join ',') | Should -Be 'target-a,target-b'
        ($first | ConvertTo-Json -Depth 20 -Compress) | Should -Be ($second | ConvertTo-Json -Depth 20 -Compress)
    }

    It 'does not mutate constructor input objects' {
        $target = [pscustomobject]@{ target_ref = 'target-a'; path = 'C:/repo/a.json'; before_hash = $hashA; desired_hash = $hashB; owner = 'adapter' }
        $action = [pscustomobject]@{ type = 'update'; target_ref = 'target-a'; summary = 'Update A'; risk = 'low'; metadata = @{ env = @{ TOKEN = 'fixture-token' } } }
        $before = @($target, $action) | ConvertTo-Json -Depth 20 -Compress

        $null = New-TestPlan @($target) @($action)

        (@($target, $action) | ConvertTo-Json -Depth 20 -Compress) | Should -Be $before
    }

    It 'keeps path containment segment aware' {
        (Test-OperationPathWithinRoot 'C:\repo2\file.json' 'C:\repo') | Should -Be $false
        (Test-OperationPathWithinRoot 'C:\repo\sub\..\file.json' 'C:\repo') | Should -Be $true
        (Test-OperationPathWithinRoot 'C:\repo\..\outside\file.json' 'C:\repo') | Should -Be $false
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
            $serialized | Should -Not -Match ([regex]::Escape($secret))
        }
        $serialized | Should -Match '<redacted>'
        (Test-OperationPlanContract $plan).pass | Should -Be $true
        $receipt.schema_version | Should -Be 1
        $receipt.verification.host_loaded | Should -Be 'not_run'
    }

    It 'keeps domain modules free of IO environment clock and terminal side effects' {
        $source = (Get-Content -LiteralPath (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1') -Raw) + "`n" + (Get-Content -LiteralPath (Join-Path $repoRoot 'src\Domain\Receipt.ps1') -Raw)
        $source | Should -Not -Match '(?im)^\s*(Get-Content|Set-Content|Add-Content|Remove-Item|Copy-Item|Move-Item|Test-Path|Resolve-Path|Get-Date|Write-Host|Write-Output|Start-Process|Invoke-WebRequest|exit)\b'
        $source | Should -Not -Match '(?i)\$env:'
    }

    It 'parses and constructs plain objects in the PowerShell 7 runtime' {
        $operationPath = (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1').Replace("'", "''")
        $receiptPath = (Join-Path $repoRoot 'src\Domain\Receipt.ps1').Replace("'", "''")
        $scriptText = ". '$operationPath'; . '$receiptPath'; `$p = New-OperationPlan -OperationId op-smoke -Domain mcp -Mode dry_run -CreatedAt 2026-08-01T08:00:00Z; `$r = New-OperationReceipt -OperationId op-smoke -Status dry_run -StartedAt 2026-08-01T08:00:00Z -CompletedAt 2026-08-01T08:00:01Z; [pscustomobject]@{ plan = `$p.schema_version; receipt = `$r.schema_version } | ConvertTo-Json -Compress"

        $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -Command $scriptText 2>&1)
        $exitCode = $LASTEXITCODE
        $result = ($output -join "`n") | ConvertFrom-Json

        $exitCode | Should -Be 0
        $result.plan | Should -Be 1
        $result.receipt | Should -Be 1
    }
}
