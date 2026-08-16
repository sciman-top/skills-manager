BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src\Infrastructure\AtomicFile.ps1')
    . (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
    . (Join-Path $repoRoot 'src\Domain\RuleDocument.ps1')
    . (Join-Path $repoRoot 'src\Domain\RuleResponsibility.ps1')
    . (Join-Path $repoRoot 'src\Application\CapabilityInventory.ps1')
    . (Join-Path $repoRoot 'src\Application\RuleDiscovery.ps1')
    . (Join-Path $repoRoot 'src\Application\RuleDiagnostics.ps1')
    . (Join-Path $repoRoot 'src\Application\RuleAdvisor.ps1')
    . (Join-Path $repoRoot 'src\Application\RuleAudit.ps1')
    . (Join-Path $repoRoot 'src\Commands\Capability.ps1')
    . (Join-Path $repoRoot 'src\Commands\RuleAudit.ps1')
    $script:Root = $repoRoot
    $script:CfgPath = Join-Path $repoRoot 'skills.json'

}
Describe 'Read-only capability and rule CLI' {
    BeforeEach {
        $script:Root = $repoRoot
        $script:CfgPath = Join-Path $repoRoot 'skills.json'
        $Root = $script:Root
        $CfgPath = $script:CfgPath
        function global:New-AuditRepoScan([string]$targetName, [string]$resolvedPath, [string]$inputPath) {
            return [pscustomobject]@{ scanned_at = 'fixture'; detected = [pscustomobject]@{ build_commands = @('pwsh -File build.ps1'); test_commands = @('pwsh -File tests/run.ps1') } }
        }
        $capabilityRoot = Join-Path $TestDrive 'capability-repo'
        New-Item -ItemType Directory -Path $capabilityRoot -Force | Out-Null
        $capabilityConfig = [pscustomobject]@{
            skill_projection = [pscustomobject]@{
                manifest_path = 'reports/skill-projection/current.json'
                managed_source_path = 'agent'
                user_skill_root = 'user-skills'
                managed_link_includes = @()
                external_skill_inventory = [pscustomobject]@{ enabled = $true }
            }
        }
        $capabilityCfgPath = Join-Path $capabilityRoot 'skills.json'
        [IO.File]::WriteAllText($capabilityCfgPath, ($capabilityConfig | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
        Mock Get-CodexPluginSkillInventory {
            [pscustomobject]@{
                authority          = 'fixture'
                freshness          = 'fresh'
                coverage           = 'complete'
                enabled_plugin_ids = @()
                skill_count        = 0
                skills             = @()
                warnings           = @()
            }
        }
        Mock Get-CodexHostObservation {
            [pscustomobject]@{
                truth_boundary  = 'read_only_cli_observation_not_host_loaded'
                mcp             = [pscustomobject]@{ warnings = @() }
                doctor          = [pscustomobject]@{ warnings = @() }
                provider_calls  = 0
                native_mutations = 0
                writes          = 0
            }
        }
    }

    It 'returns one parseable skill-surface JSON envelope with no write by default' {
        $script:Root = $capabilityRoot
        $script:CfgPath = $capabilityCfgPath
        $Root = $script:Root
        $CfgPath = $script:CfgPath
        $before = (Get-FileHash -LiteralPath $CfgPath -Algorithm SHA256).Hash
        $result = Invoke-CapabilityInventoryCommand @('--json')
        $parsed = $result.output | ConvertFrom-Json

        $result.exit_code | Should -Be 0
        $parsed.command | Should -Be 'capability-inventory'
        $parsed.data.writes | Should -Be 0
        $parsed.data.provider_calls | Should -Be 0
        $parsed.data.host_observation.truth_boundary | Should -Be 'read_only_cli_observation_not_host_loaded'
        $parsed.view | Should -Be 'skill-surfaces'
        $parsed.data.surface_count | Should -Be 6
        (Get-FileHash -LiteralPath $CfgPath -Algorithm SHA256).Hash | Should -Be $before
    }

    It 'writes exactly the explicit capability report path' {
        $script:Root = $capabilityRoot
        $script:CfgPath = $capabilityCfgPath
        $Root = $script:Root
        $CfgPath = $script:CfgPath
        $out = Join-Path $TestDrive 'capability.json'
        $result = Invoke-CapabilityInventoryCommand @('--view', 'skill-surfaces', '--json', '--out', $out)

        Test-Path -LiteralPath $out | Should -Be $true
        (Get-Content -LiteralPath $out -Raw | ConvertFrom-Json).data.writes | Should -Be 1
        @((Get-ChildItem -LiteralPath $TestDrive -File)).Count | Should -Be 1
    }

    It 'refuses to overwrite an inventory input through report out' {
        $script:Root = $capabilityRoot
        $script:CfgPath = $capabilityCfgPath
        $Root = $script:Root
        $CfgPath = $script:CfgPath
        $before = (Get-FileHash -LiteralPath $CfgPath -Algorithm SHA256).Hash

        { Invoke-CapabilityInventoryCommand @('--json', '--out', $CfgPath) } | Should -Throw '*cannot overwrite a capability inventory input*'

        (Get-FileHash -LiteralPath $CfgPath -Algorithm SHA256).Hash | Should -Be $before
    }

    It 'returns exit 1 when the skill surface view fails closed' {
        $script:Root = $capabilityRoot
        $script:CfgPath = $capabilityCfgPath
        $Root = $script:Root
        $CfgPath = $script:CfgPath
        Mock New-SkillSurfaceView { [pscustomobject]@{ pass = $false; surface_count = 1; findings = @([pscustomobject]@{ code = 'projection_manifest_stale' }); writes = 0 } }

        $result = Invoke-CapabilityInventoryCommand @('--json')

        $result.exit_code | Should -Be 1
        ($result.output | ConvertFrom-Json).pass | Should -BeFalse
    }

    It 'returns one rule-audit envelope and preserves the scanned rule hash' {
        $repo = Join-Path $TestDrive 'repo'; New-Item -ItemType Directory -Path $repo -Force | Out-Null; Set-Content -LiteralPath (Join-Path $repo 'AGENTS.md') -Value '# fixture' -Encoding UTF8
        $before = (Get-FileHash -LiteralPath (Join-Path $repo 'AGENTS.md') -Algorithm SHA256).Hash
        $result = Invoke-RuleAuditCommand @('--repo', $repo, '--host', 'codex', '--json')
        $parsed = $result.output | ConvertFrom-Json

        $result.exit_code | Should -Be 0
        $parsed.command | Should -Be 'rule-audit'
        $parsed.writes | Should -Be 0
        $parsed.provider_calls | Should -Be 0
        $parsed.native_mutations | Should -Be 0
        (Get-FileHash -LiteralPath (Join-Path $repo 'AGENTS.md') -Algorithm SHA256).Hash | Should -Be $before
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

        @($parsed.advisor.coverage).Count | Should -Be 1
        $parsed.advisor.coverage[0].constraint_id | Should -Be 'R6'
        @($parsed.repo_reference_checks.references | Where-Object state -eq verified).Count | Should -Be 2
        $parsed.repo_reference_checks.commands_executed | Should -Be 0
    }

    It 'refuses to overwrite a discovered rule through report out' {
        $repo = Join-Path $TestDrive 'overwrite'; New-Item -ItemType Directory -Path $repo -Force | Out-Null; $rule = Join-Path $repo 'AGENTS.md'; Set-Content $rule '# fixture' -Encoding UTF8
        { Invoke-RuleAuditCommand @('--repo', $repo, '--json', '--out', $rule) } | Should -Throw
    }

    AfterEach { Remove-Item function:\New-AuditRepoScan -ErrorAction SilentlyContinue }
}
