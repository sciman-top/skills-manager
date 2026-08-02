$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'src\Infrastructure\AtomicFile.ps1')
. (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
. (Join-Path $repoRoot 'src\Domain\CapabilityDescriptor.ps1')
. (Join-Path $repoRoot 'src\Domain\RuleDocument.ps1')
. (Join-Path $repoRoot 'src\Domain\RuleResponsibility.ps1')
. (Join-Path $repoRoot 'src\Application\CapabilityInventory.ps1')
. (Join-Path $repoRoot 'src\Application\RuleDiscovery.ps1')
. (Join-Path $repoRoot 'src\Application\RuleDiagnostics.ps1')
. (Join-Path $repoRoot 'src\Application\RuleAdvisor.ps1')
. (Join-Path $repoRoot 'src\Application\RuleAudit.ps1')
. (Join-Path $repoRoot 'src\Commands\Capability.ps1')
. (Join-Path $repoRoot 'src\Commands\RuleAudit.ps1')

Describe 'Read-only capability and rule CLI' {
    BeforeEach {
        $script:Root = $repoRoot
        $script:CfgPath = Join-Path $repoRoot 'skills.json'
        function global:New-AuditRepoScan([string]$targetName, [string]$resolvedPath, [string]$inputPath) {
            return [pscustomobject]@{ scanned_at = 'fixture'; detected = [pscustomobject]@{ build_commands = @('pwsh -File build.ps1'); test_commands = @('pwsh -File tests/run.ps1') } }
        }
    }

    It 'returns one parseable capability JSON envelope with no write by default' {
        $before = (Get-FileHash -LiteralPath $script:CfgPath -Algorithm SHA256).Hash
        $result = Invoke-CapabilityInventoryCommand @('--json')
        $parsed = $result.output | ConvertFrom-Json

        $result.exit_code | Should Be 0
        $parsed.command | Should Be 'capability-inventory'
        $parsed.data.writes | Should Be 0
        $parsed.data.provider_calls | Should Be 0
        @($parsed.data.descriptors | Where-Object truth_origin -eq runtime).Count | Should BeGreaterThan 0
        (Get-FileHash -LiteralPath $script:CfgPath -Algorithm SHA256).Hash | Should Be $before
    }

    It 'writes exactly the explicit capability report path' {
        $out = Join-Path $TestDrive 'capability.json'
        $result = Invoke-CapabilityInventoryCommand @('--json', '--out', $out)

        Test-Path -LiteralPath $out | Should Be $true
        (Get-Content -LiteralPath $out -Raw | ConvertFrom-Json).data.writes | Should Be 1
        @((Get-ChildItem -LiteralPath $TestDrive -File)).Count | Should Be 1
    }

    It 'returns one rule-audit envelope and preserves the scanned rule hash' {
        $repo = Join-Path $TestDrive 'repo'; New-Item -ItemType Directory -Path $repo -Force | Out-Null; Set-Content -LiteralPath (Join-Path $repo 'AGENTS.md') -Value '# fixture' -Encoding UTF8
        $before = (Get-FileHash -LiteralPath (Join-Path $repo 'AGENTS.md') -Algorithm SHA256).Hash
        $result = Invoke-RuleAuditCommand @('--repo', $repo, '--host', 'codex', '--json')
        $parsed = $result.output | ConvertFrom-Json

        $result.exit_code | Should Be 0
        $parsed.command | Should Be 'rule-audit'
        $parsed.writes | Should Be 0
        $parsed.provider_calls | Should Be 0
        $parsed.native_mutations | Should Be 0
        (Get-FileHash -LiteralPath (Join-Path $repo 'AGENTS.md') -Algorithm SHA256).Hash | Should Be $before
    }

    It 'connects explicit responsibility mappings to repository reference checks' {
        $repo = Join-Path $TestDrive 'rule-truth'
        New-Item -ItemType Directory -Path (Join-Path $repo 'scripts') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'scripts\verify.ps1') -Value 'exit 0' -Encoding UTF8
        @'
# Fixture rules

## D. Global Rule -> Repo Action

- `R6`: run `pwsh -File tests/run.ps1`; verifier path is `scripts/verify.ps1`.
'@ | Set-Content -LiteralPath (Join-Path $repo 'AGENTS.md') -Encoding UTF8

        $result = Invoke-RuleAuditCommand @('--repo', $repo, '--host', 'codex', '--json')
        $parsed = $result.output | ConvertFrom-Json

        @($parsed.advisor.coverage).Count | Should Be 1
        $parsed.advisor.coverage[0].constraint_id | Should Be 'R6'
        @($parsed.repo_reference_checks.references | Where-Object state -eq verified).Count | Should Be 2
        $parsed.repo_reference_checks.commands_executed | Should Be 0
    }

    It 'refuses to overwrite a discovered rule through report out' {
        $repo = Join-Path $TestDrive 'overwrite'; New-Item -ItemType Directory -Path $repo -Force | Out-Null; $rule = Join-Path $repo 'AGENTS.md'; Set-Content $rule '# fixture' -Encoding UTF8
        { Invoke-RuleAuditCommand @('--repo', $repo, '--json', '--out', $rule) } | Should Throw
    }

    AfterEach { Remove-Item function:\New-AuditRepoScan -ErrorAction SilentlyContinue }
}
