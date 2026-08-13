BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
    . (Join-Path $repoRoot 'src\Application\RuleDiscovery.ps1')
    . (Join-Path $repoRoot 'src\Application\RuleAudit.ps1')

}
Describe 'Rule audit repository truth integration' {
    It 'maps path and supplied TargetAudit command facts without executing commands' {
        $root = Join-Path $TestDrive 'repo'; New-Item -ItemType Directory -Path (Join-Path $root 'scripts') -Force | Out-Null; Set-Content -LiteralPath (Join-Path $root 'scripts\verify.ps1') -Value 'exit 0' -Encoding UTF8
        $scan = [pscustomobject]@{ scanned_at = '2026-08-02T00:00:00Z'; detected = [pscustomobject]@{ build_commands = @('pwsh -File build.ps1'); test_commands = @('pwsh -File tests/run.ps1') } }
        $truth = New-RuleRepoTruthIndex -RepoRoot $root -RepoScan $scan
        $result = Test-RuleRepoReferences $truth @(
            [pscustomobject]@{ kind = 'path'; value = 'scripts/verify.ps1'; source_type = 'rule' },
            [pscustomobject]@{ kind = 'command'; value = 'pwsh -File tests/run.ps1'; source_type = 'rule' }
        )

        @($result.references | Where-Object state -eq verified).Count | Should -Be 2
        $result.commands_executed | Should -Be 0
    }

    It 'keeps absent unknown and out-of-root facts distinct' {
        $root = Join-Path $TestDrive 'bounded'; New-Item -ItemType Directory -Path $root -Force | Out-Null
        $truth = New-RuleRepoTruthIndex -RepoRoot $root
        $result = Test-RuleRepoReferences $truth @(
            [pscustomobject]@{ kind = 'path'; value = 'missing.txt'; source_type = 'rule' },
            [pscustomobject]@{ kind = 'path'; value = '..\outside.txt'; source_type = 'rule' },
            [pscustomobject]@{ kind = 'command'; value = 'unknown command'; source_type = 'rule' }
        )

        (@($result.references.state | Sort-Object) -join ',') | Should -Be 'absent,not_observed,out_of_root'
    }

    It 'never treats a recommendation as evidence' {
        $root = Join-Path $TestDrive 'recommendation'; New-Item -ItemType Directory -Path $root -Force | Out-Null; Set-Content (Join-Path $root 'exists.txt') 'x'
        $result = Test-RuleRepoReferences (New-RuleRepoTruthIndex $root) @([pscustomobject]@{ kind = 'path'; value = 'exists.txt'; source_type = 'recommendation' })

        $result.references[0].state | Should -Be 'not_checked'
        $result.references[0].evidence[0].reason | Should -Be 'recommendation_not_evidence'
        $result.recommendations_used_as_evidence | Should -Be 0
    }

    It 'verifies a command entrypoint without executing an unobserved command' {
        $root = Join-Path $TestDrive 'entrypoint'; New-Item -ItemType Directory -Path (Join-Path $root 'scripts') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'scripts\verify.ps1') -Value 'exit 0' -Encoding UTF8
        $truth = New-RuleRepoTruthIndex -RepoRoot $root

        $result = Test-RuleRepoReferences $truth @([pscustomobject]@{ kind = 'command'; value = 'pwsh -NoProfile -File scripts/verify.ps1'; source_type = 'rule' })

        $result.references[0].state | Should -Be 'verified'
        $result.references[0].executed | Should -Be $false
        $result.commands_executed | Should -Be 0
    }

    It 'does not classify slash-delimited labels or wildcard examples as paths' {
        $root = Join-Path $TestDrive 'tokens'; New-Item -ItemType Directory -Path (Join-Path $root 'scripts') -Force | Out-Null
        $rule = Join-Path $root 'AGENTS.md'
        Set-Content -LiteralPath $rule -Value 'Use `E4/E5/E6`, `not_started/deferred`, `src/*`, and `scripts/verify.ps1`.' -Encoding UTF8
        $document = [pscustomobject]@{ path = $rule }

        $references = @(Get-RuleAuditReferences -Documents @($document))

        $references.Count | Should -Be 1
        $references[0].value | Should -Be 'scripts/verify.ps1'
    }

    It 'parses multiple semicolon-delimited rule mappings from one bullet' {
        $root = Join-Path $TestDrive 'multi-mapping'; New-Item -ItemType Directory -Path $root -Force | Out-Null
        $rule = Join-Path $root 'AGENTS.md'
        @'
## D. Global Rule -> Repo Action

- `E4`: health gates; `E5`: supply-chain review; `E6`: migration and rollback.
'@ | Set-Content -LiteralPath $rule -Encoding UTF8
        $document = [pscustomobject]@{ path = $rule }

        $constraints = @(Get-RuleAuditResponsibilityConstraints -Documents @($document))

        @($constraints.constraint_id | Sort-Object) -join ',' | Should -Be 'E4,E5,E6'
        @($constraints | Where-Object constraint_id -eq 'E5')[0].common_intent | Should -Be 'supply-chain review'
    }
}
