BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src\Infrastructure\AtomicFile.ps1')
    . (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
    . (Join-Path $repoRoot 'src\Domain\RuleDocument.ps1')
    . (Join-Path $repoRoot 'src\Domain\RuleResponsibility.ps1')
    . (Join-Path $repoRoot 'src\Domain\RulePatchPlan.ps1')
    . (Join-Path $repoRoot 'src\Application\RuleDiscovery.ps1')
    . (Join-Path $repoRoot 'src\Application\RuleDiagnostics.ps1')
    . (Join-Path $repoRoot 'src\Application\RuleAdvisor.ps1')
    . (Join-Path $repoRoot 'src\Application\RuleAudit.ps1')
    . (Join-Path $repoRoot 'src\Application\RuleEstate.ps1')
    . (Join-Path $repoRoot 'src\Application\RuleEstateMutation.ps1')
    . (Join-Path $repoRoot 'src\Commands\RuleEstate.ps1')

}
Describe 'Workspace rule estate audit' {
    BeforeAll {
function New-RuleEstateFixture {
        $workspace = Join-Path $TestDrive ('workspace-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $workspace -Force | Out-Null
        foreach ($name in @('repo-a', 'repo-b', 'external', '文档')) {
            $path = Join-Path $workspace $name; New-Item -ItemType Directory -Path $path -Force | Out-Null
            & git -C $path init -q -b main
            if ($LASTEXITCODE -ne 0) { throw ('git fixture initialization failed: {0}' -f $path) }
            if ($name -notin @('external', '文档')) {
                @'
# Project
**全局规则复核**: 9.60

## 1. Scope

Fixture source of truth is AGENTS.md; skills.ps1 is the repository entrypoint.

## A. Repository facts

Fixture boundaries, safety, supply chain, data and recovery invariants.

## B. Execution boundaries

Fail closed on contract drift and keep dynamic state outside the root rule.

## C. Gates and rollback

Build, test, contract and hotspot evidence use the repository verifier; rollback only this slice.

## D. Global Rule -> Repo Action

- Git baseline=`main`; upstream=`none`; closeout=`local_only`.
- `gate_na`: reason=`fixture has no configured Git remote`; alternative_verification=`git symbolic-ref --short HEAD`; evidence_link=`docs/change-evidence/rule-contract.md`; expires_at=`2099-12-31`; recovery_condition=`a remote is configured`.
- `R1`: declare the repository destination; evidence=`AGENTS.md`; rollback=revert this slice.
- `R2`: close the smallest executable step; evidence=`scripts/verify-contract.ps1`; rollback=revert this slice.
- `E4`: publish health evidence; evidence=`scripts/verify-contract.ps1`; rollback=revert this slice.
- `E5`: verify supply-chain inputs; evidence=`scripts/verify-contract.ps1`; rollback=revert this slice.
- `E6`: verify migration and rollback; evidence=`scripts/verify-contract.ps1`; rollback=revert this slice.
- `S1`: enforce stable semantics with `scripts/verify-contract.ps1`; evidence=`scripts/verify-contract.ps1`; rollback=revert this slice.
- `S2`: enforce deterministic behavior with `scripts/verify-contract.ps1`; evidence=`scripts/verify-contract.ps1`; rollback=revert this slice.
- `S3`: enforce project actions with `scripts/verify-contract.ps1`; evidence=`scripts/verify-contract.ps1`; rollback=revert this slice.
- `S4`: enforce repository evidence with `scripts/verify-contract.ps1`; evidence=`scripts/verify-contract.ps1`; rollback=revert this slice.
- `S5`: enforce bounded rollback with `scripts/verify-contract.ps1`; evidence=`scripts/verify-contract.ps1`; rollback=revert this slice.
'@ | Set-Content -LiteralPath (Join-Path $path 'AGENTS.md') -Encoding UTF8
                New-Item -ItemType Directory -Path (Join-Path $path 'scripts') -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $path 'scripts\verify-contract.ps1') -Value '# fixture' -Encoding UTF8
                New-Item -ItemType Directory -Path (Join-Path $path 'docs\change-evidence') -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $path 'docs\change-evidence\rule-contract.md') -Value '# fixture evidence' -Encoding UTF8
            }
        }
        foreach ($name in @('repo-a', 'repo-b')) {
            Set-Content -LiteralPath (Join-Path $workspace "$name\CLAUDE.md") -Value '@AGENTS.md' -Encoding UTF8
        }
        $fixtureId = [guid]::NewGuid().ToString('N')
        $codex = Join-Path $TestDrive ('codex-' + $fixtureId); $claude = Join-Path $TestDrive ('claude-' + $fixtureId); New-Item -ItemType Directory -Path $codex,$claude -Force | Out-Null
        $common = @'
**版本**: 9.60

## 1. Reading guide

Keep common intent, host delta, project contract and maintenance checks distinct.

## A. Common

R1 R2 S1 S2 S3 S4 S5

## B. Platform

host delta

## C. Project contract

Map R1-R2, E4/E5/E6, and S1-S5.

## D. Maintenance

verify drift
'@
        Set-Content -LiteralPath (Join-Path $codex 'AGENTS.md') -Value ($common.Replace('host delta', 'codex host delta')) -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $claude 'CLAUDE.md') -Value ($common.Replace('host delta', 'claude host delta')) -Encoding UTF8
        return [pscustomobject]@{ workspace=$workspace; codex=$codex; claude=$claude }
    }
}

    It 'discovers direct Git roots, applies exclusions, and reports registry drift' {
        $f = New-RuleEstateFixture
        $registry = @([pscustomobject]@{ path = (Join-Path $f.workspace 'repo-a'); enabled = $true }, [pscustomobject]@{ path = (Join-Path $f.workspace 'gone'); enabled = $true })
        $result = Get-RuleEstateTargets -WorkspaceRoot $f.workspace -RegistryTargets $registry

        $result.target_count | Should -Be 2
        @($result.targets.name) | Should -Contain 'repo-a'
        @($result.targets.name) | Should -Not -Contain 'external'
        @($result.registry.unregistered_paths).Count | Should -Be 1
        @($result.registry.missing_paths).Count | Should -Be 1
        $result.registry.in_sync | Should -Be $false
    }

    It 'separates aligned common sections from platform deltas' {
        $f = New-RuleEstateFixture
        $result = Get-RuleEstateGlobalAlignment $f.codex $f.claude

        $result.common_aligned | Should -Be $true
        $result.codex_delta_present | Should -Be $true
        $result.claude_delta_present | Should -Be $true
        $result.platform_deltas_distinct | Should -Be $true
        $result.releases.aligned | Should -Be $true
        @($result.budgets | Where-Object { -not $_.within_budget }).Count | Should -Be 0
        @($result.findings).Count | Should -Be 0
    }

    It 'fails when a global rule omits a required top-level contract section' {
        $f = New-RuleEstateFixture
        $codexPath = Join-Path $f.codex 'AGENTS.md'
        $text = [regex]::Replace([IO.File]::ReadAllText($codexPath), '(?ms)^## 1\..*?(?=^## A\.)', '')
        [IO.File]::WriteAllText($codexPath, $text)

        $result = Invoke-RuleEstateAuditCommand @('--workspace-root',$f.workspace,'--codex-user-root',$f.codex,'--claude-user-root',$f.claude,'--json')
        $parsed = $result.output | ConvertFrom-Json

        $result.exit_code | Should -Be 2
        @($parsed.report.findings | Where-Object { $_.code -eq 'global_contract_section_missing' -and $_.host -eq 'codex' -and $_.section -eq '1' }).Count | Should -Be 1
        $parsed.report.structural_pass | Should -Be $false
    }

    It 'uses official references without machine-local paths' {
        $f = New-RuleEstateFixture

        $report = Invoke-RuleEstateAudit -WorkspaceRoot $f.workspace -ExcludeNames @('external','文档') -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude

        @($report.reference_basis | Where-Object authority -eq 'official').Count | Should -Be 3
        @($report.reference_basis | Where-Object source -eq 'https://agents.md/').Count | Should -Be 1
        @($report.reference_basis | Where-Object source -match '^[A-Za-z]:\\').Count | Should -Be 0
    }

    It 'uses active Codex and Claude profile roots for audit and mutation defaults' {
        $f = New-RuleEstateFixture
        $oldCodex = $env:CODEX_HOME; $oldClaude = $env:CLAUDE_CONFIG_DIR
        try {
            $env:CODEX_HOME = $f.codex; $env:CLAUDE_CONFIG_DIR = $f.claude
            $audit = Parse-RuleEstateAuditOptions @('--workspace-root',$f.workspace)
            $plan = Parse-RuleEstateMutationOptions @('--review','review.json','--workspace-root',$f.workspace,'--out','plan.json') plan
            $audit.codex_user_root | Should -Be $f.codex
            $audit.claude_user_root | Should -Be $f.claude
            $plan.codex_user_root | Should -Be $f.codex
            $plan.claude_user_root | Should -Be $f.claude
        }
        finally {
            $env:CODEX_HOME = $oldCodex; $env:CLAUDE_CONFIG_DIR = $oldClaude
        }
    }

    It 'skips an empty Codex override and reads the first non-empty global rule' {
        $f = New-RuleEstateFixture
        [IO.File]::WriteAllText((Join-Path $f.codex 'AGENTS.override.md'), '')

        $document = Get-RuleEstateGlobalDocument $f.codex codex

        $document.path | Should -Be (Join-Path $f.codex 'AGENTS.md')
        $document.text | Should -Match 'codex host delta'
    }

    It 'reports flattened platform deltas and global budget overflow' {
        $f = New-RuleEstateFixture
        $codexPath = Join-Path $f.codex 'AGENTS.md'
        $claudePath = Join-Path $f.claude 'CLAUDE.md'
        $claudeText = [IO.File]::ReadAllText($claudePath).Replace('claude host delta', 'codex host delta')
        [IO.File]::WriteAllText($claudePath, $claudeText)
        [IO.File]::AppendAllText($codexPath, ('x' * 17000))

        $result = Get-RuleEstateGlobalAlignment $f.codex $f.claude

        $result.platform_deltas_distinct | Should -Be $false
        @($result.findings.code) | Should -Contain 'platform_delta_not_distinct'
        @($result.findings.code) | Should -Contain 'global_rule_budget_exceeded'
    }

    It 'fails the estate audit on hard global alignment and budget violations' {
        $f = New-RuleEstateFixture
        $codexPath = Join-Path $f.codex 'AGENTS.md'
        $claudePath = Join-Path $f.claude 'CLAUDE.md'
        [IO.File]::WriteAllText($claudePath, ([IO.File]::ReadAllText($claudePath).Replace('claude host delta', 'codex host delta')))
        [IO.File]::AppendAllText($codexPath, ('x' * 17000))

        $result = Invoke-RuleEstateAuditCommand @('--workspace-root',$f.workspace,'--codex-user-root',$f.codex,'--claude-user-root',$f.claude,'--json')
        $parsed = $result.output | ConvertFrom-Json

        $result.exit_code | Should -Be 2
        $parsed.pass | Should -Be $false
        $parsed.report.structural_pass | Should -Be $false
    }

    It 'reports soft budget warning and addition-blocked states before the hard limit' {
        $f = New-RuleEstateFixture
        [IO.File]::AppendAllText((Join-Path $f.codex 'AGENTS.md'), ('x' * 14000))
        [IO.File]::AppendAllText((Join-Path $f.claude 'CLAUDE.md'), ('x' * 15700))

        $result = Get-RuleEstateGlobalAlignment $f.codex $f.claude
        $codexBudget = @($result.budgets | Where-Object host -eq codex)[0]
        $claudeBudget = @($result.budgets | Where-Object host -eq claude)[0]

        $codexBudget.state | Should -Be 'warning'
        $claudeBudget.state | Should -Be 'addition_blocked'
        @($result.findings.code) | Should -Contain 'global_rule_budget_warning'
        @($result.findings.code) | Should -Contain 'global_rule_budget_addition_blocked'
        @($result.findings.code) | Should -Not -Contain 'global_rule_budget_exceeded'
    }

    It 'warns before a global rule exhausts its byte budget' {
        $f = New-RuleEstateFixture
        $codexPath = Join-Path $f.codex 'AGENTS.md'
        [IO.File]::AppendAllText($codexPath, ('x' * 14200))

        $result = Get-RuleEstateGlobalAlignment $f.codex $f.claude

        @($result.budgets | Where-Object host -eq 'codex')[0].within_budget | Should -Be $true
        @($result.findings.code) | Should -Contain 'global_rule_budget_low_headroom'
    }

    It 'reports host-specific implementation details in common sections' {
        $f = New-RuleEstateFixture
        foreach ($path in @((Join-Path $f.codex 'AGENTS.md'), (Join-Path $f.claude 'CLAUDE.md'))) {
            $text = [IO.File]::ReadAllText($path).Replace('R1 R2 S1 S2 S3 S4 S5', 'R1 R2 S1 S2 S3 S4 S5 send_message_to_thread')
            [IO.File]::WriteAllText($path, $text)
        }

        $result = Get-RuleEstateGlobalAlignment $f.codex $f.claude

        $result.common_aligned | Should -Be $true
        @($result.findings.code) | Should -Contain 'global_common_platform_leak'
    }

    It 'does not report registry drift when no registry comparison was requested' {
        $f = New-RuleEstateFixture
        $result = Get-RuleEstateTargets -WorkspaceRoot $f.workspace

        $result.registry.supplied | Should -Be $false
        $result.registry.in_sync | Should -Be $true
        @($result.registry.unregistered_paths).Count | Should -Be 0
    }

    It 'builds cross-host responsibility coverage and bounded patch candidates' {
        $f = New-RuleEstateFixture
        Remove-Item -LiteralPath (Join-Path $f.workspace 'repo-b\CLAUDE.md')
        $report = Invoke-RuleEstateAudit -WorkspaceRoot $f.workspace -ExcludeNames @('external','文档') -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude

        $report.summary.target_count | Should -Be 2
        $report.inventory.registry.supplied | Should -Be $false
        @($report.findings.code) | Should -Not -Contain 'target_registry_drift'
        $report.summary.covered_count | Should -BeGreaterThan 0
        $report.summary.patch_candidate_count | Should -Be 1
        $report.patch_candidates[0].target_path | Should -Match 'repo-b\\CLAUDE\.md$'
        foreach ($covered in @($report.targets[0].responsibility.coverage | Where-Object coverage -eq 'covered')) {
            @($covered.project_actions | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count | Should -BeGreaterThan 0
            @($covered.evidence | Where-Object { $null -ne $_ }).Count | Should -BeGreaterThan 0
        }
        $report.writes | Should -Be 0
        $report.provider_calls | Should -Be 0
        $report.host_loaded | Should -Be 'not_run'
    }

    It 'uses five required project facts when the legacy mapping set is empty' {
        $f = New-RuleEstateFixture
        foreach ($path in @((Join-Path $f.codex 'AGENTS.md'), (Join-Path $f.claude 'CLAUDE.md'))) {
            $text = [regex]::Replace([IO.File]::ReadAllText($path), '(?ms)^## C\..*?(?=^## D\.)', "## C. Project contract`n`nDeclare repository facts.`n`n")
            [IO.File]::WriteAllText($path, $text)
        }
        foreach ($path in @((Join-Path $f.workspace 'repo-a\AGENTS.md'), (Join-Path $f.workspace 'repo-b\AGENTS.md'))) {
            $text = [regex]::Replace([IO.File]::ReadAllText($path), '(?m)^- `[RES]\d+`:.*(?:\r?\n|$)', '')
            [IO.File]::WriteAllText($path, $text)
        }

        $report = Invoke-RuleEstateAudit -WorkspaceRoot $f.workspace -ExcludeNames @('external','文档') -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude

        $report.summary.legacy_textual_mapping_expected_rows | Should -Be 0
        $report.summary.expected_coverage_rows | Should -Be 10
        $report.summary.contract_fact_covered_count | Should -Be 10
        $report.summary.contract_fact_gap_count | Should -Be 0
        $report.semantic_coverage_pass | Should -Be $true
        $report.coverage_kind | Should -Be 'required_project_facts_presence'
    }

    It 'fails closed when a required project fact is missing' {
        $f = New-RuleEstateFixture
        $agents = Join-Path $f.workspace 'repo-a\AGENTS.md'
        $text = [IO.File]::ReadAllText($agents).Replace('Fixture source of truth is AGENTS.md; skills.ps1 is the repository entrypoint.', 'Fixture repository description.')
        [IO.File]::WriteAllText($agents, $text)

        $report = Invoke-RuleEstateAudit -WorkspaceRoot $f.workspace -ExcludeNames @('external','文档') -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude
        $repo = @($report.targets | Where-Object name -eq 'repo-a')[0]

        @($repo.contract_facts | Where-Object id -eq 'source_of_truth')[0].covered | Should -Be $false
        @($repo.contract_facts | Where-Object id -eq 'entrypoint')[0].covered | Should -Be $false
        @($repo.findings | Where-Object code -eq 'project_contract_fact_missing').Count | Should -Be 2
        $report.semantic_coverage_pass | Should -Be $false
    }

    It 'recognizes the tracked production global sources and project contract facts' {
        $codexText = [IO.File]::ReadAllText((Join-Path $repoRoot 'rules\global\codex\AGENTS.md'))
        $claudeText = [IO.File]::ReadAllText((Join-Path $repoRoot 'rules\global\claude\CLAUDE.md'))
        $facts = @(Get-RuleEstateProjectContractFacts (Join-Path $repoRoot 'AGENTS.md'))

        @(Get-RuleEstateExpectedConstraintIds $codexText $claudeText).Count | Should -Be 0
        $facts.Count | Should -Be 5
        @($facts | Where-Object { -not $_.covered }).Count | Should -Be 0
        foreach ($fact in $facts) { @($fact.evidence).Count | Should -Be 1; $fact.evidence[0].line | Should -BeGreaterThan 0 }
    }

    It 'returns a single JSON envelope and only writes an explicit report' {
        $f = New-RuleEstateFixture; $out = Join-Path $f.workspace 'estate.json'
        $result = Invoke-RuleEstateAuditCommand @('--workspace-root',$f.workspace,'--codex-user-root',$f.codex,'--claude-user-root',$f.claude,'--out',$out,'--json')
        $parsed = $result.output | ConvertFrom-Json

        $result.exit_code | Should -Be 0
        $parsed.command | Should -Be 'rule-estate-audit'
        $parsed.writes | Should -Be 1
        $parsed.report.writes | Should -Be 0
        Test-Path -LiteralPath $out | Should -Be $true
    }

    It 'fails the command when a global stable constraint has no repository action' {
        $f = New-RuleEstateFixture
        $agents = Join-Path $f.workspace 'repo-a\AGENTS.md'
        $text = [regex]::Replace([IO.File]::ReadAllText($agents), '(?m)^- `S1`:.*(?:\r?\n|$)', '')
        [IO.File]::WriteAllText($agents, $text)

        $result = Invoke-RuleEstateAuditCommand @('--workspace-root',$f.workspace,'--codex-user-root',$f.codex,'--claude-user-root',$f.claude,'--json')
        $parsed = $result.output | ConvertFrom-Json

        $result.exit_code | Should -Be 2
        $parsed.pass | Should -Be $false
        $parsed.report.semantic_coverage_pass | Should -Be $false
        @($parsed.report.findings | Where-Object { $_.code -eq 'global_repo_action_gap' -and $_.constraint_id -eq 'S1' }).Count | Should -Be 1
    }

    It 'fails deterministic enforcement verification when a mapped path is absent' {
        $f = New-RuleEstateFixture
        $agents = Join-Path $f.workspace 'repo-a\AGENTS.md'
        $text = [IO.File]::ReadAllText($agents).Replace('`scripts/verify-contract.ps1`', '`scripts/missing-contract.ps1`')
        [IO.File]::WriteAllText($agents, $text)

        $result = Invoke-RuleEstateAuditCommand @('--workspace-root',$f.workspace,'--codex-user-root',$f.codex,'--claude-user-root',$f.claude,'--json')
        $parsed = $result.output | ConvertFrom-Json

        $result.exit_code | Should -Be 2
        $parsed.pass | Should -Be $false
        $parsed.report.enforcement_verified | Should -Be $false
        @($parsed.report.findings | Where-Object code -eq 'enforcement_reference_missing').Count | Should -BeGreaterThan 0
    }

    It 'does not treat slash-separated destination categories as an enforcement path' {
        $f = New-RuleEstateFixture
        $checks = @(Get-RuleEstateEnforcementChecks -RepoRoot (Join-Path $f.workspace 'repo-a') -ActionMatches @(
            [pscustomobject]@{ action = 'choose `src/config/overrides/rules/docs` as the destination category' }
        ))

        $checks | Should -BeNullOrEmpty
    }

    It 'requires S5 to map to a concrete deterministic enforcement reference' {
        $f = New-RuleEstateFixture
        $agents = Join-Path $f.workspace 'repo-a\AGENTS.md'
        $text = [IO.File]::ReadAllText($agents).Replace('`scripts/verify-contract.ps1`', 'a repository gate')
        [IO.File]::WriteAllText($agents, $text)

        $result = Invoke-RuleEstateAuditCommand @('--workspace-root',$f.workspace,'--codex-user-root',$f.codex,'--claude-user-root',$f.claude,'--json')
        $parsed = $result.output | ConvertFrom-Json

        $result.exit_code | Should -Be 2
        @($parsed.report.findings | Where-Object { $_.code -eq 'enforcement_reference_required' -and $_.constraint_id -eq 'S5' }).Count | Should -Be 1
    }

    It 'rejects an enforcement directory as a concrete S5 reference' {
        $f = New-RuleEstateFixture
        $agents = Join-Path $f.workspace 'repo-a\AGENTS.md'
        $text = [IO.File]::ReadAllText($agents).Replace('`S5`: enforce bounded rollback with `scripts/verify-contract.ps1`', '`S5`: enforce bounded rollback with `scripts`')
        [IO.File]::WriteAllText($agents, $text)

        $result = Invoke-RuleEstateAuditCommand @('--workspace-root',$f.workspace,'--codex-user-root',$f.codex,'--claude-user-root',$f.claude,'--json')
        $parsed = $result.output | ConvertFrom-Json

        $result.exit_code | Should -Be 2
        $parsed.report.enforcement_verified | Should -Be $false
        @($parsed.report.findings | Where-Object code -eq 'enforcement_reference_not_file').Count | Should -Be 1
    }

    It 'does not leak a prior directory kind into an invalid enforcement path' {
        $f = New-RuleEstateFixture
        $invalidValue = 'scripts/' + [char]0 + '.ps1'
        $actions = @(
            [pscustomobject]@{ action = '`scripts`' },
            [pscustomobject]@{ action = ('`' + $invalidValue + '`') }
        )

        $checks = @(Get-RuleEstateEnforcementChecks -RepoRoot (Join-Path $f.workspace 'repo-a') -ActionMatches $actions)
        $invalid = @($checks | Where-Object kind -eq 'invalid')

        $invalid.Count | Should -Be 1
        $invalid[0].exists | Should -Be $false
        $invalid[0].is_file | Should -Be $false
        $invalid[0].is_directory | Should -Be $false
    }

    It 'reports grouped project mappings as textual coverage only' {
        $f = New-RuleEstateFixture
        $agents = Join-Path $f.workspace 'repo-a\AGENTS.md'
        $text = [IO.File]::ReadAllText($agents)
        $text = [regex]::Replace($text, '(?m)^- `R1`:.*\r?\n- `R2`:.*$', '- `R1-R2`: grouped action; evidence=`AGENTS.md`; rollback=revert this slice.')
        [IO.File]::WriteAllText($agents, $text)

        $report = Invoke-RuleEstateAudit -WorkspaceRoot $f.workspace -ExcludeNames @('external','文档') -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude

        @($report.findings | Where-Object code -eq 'project_mapping_grouped').Count | Should -Be 1
        $report.semantic_coverage_pass | Should -Be $false
        $report.summary.textual_mapping_covered_count | Should -BeGreaterThan 0
        $report.summary.covered_count | Should -Be $report.summary.textual_mapping_covered_count
        $report.summary.gap_count | Should -Be 0
        $report.summary.semantic_gap_count | Should -Be 1
    }

    It 'rejects project constraint ids not declared by the global contract' {
        $f = New-RuleEstateFixture
        $agents = Join-Path $f.workspace 'repo-a\AGENTS.md'
        [IO.File]::AppendAllText($agents, [Environment]::NewLine + '- `R9`: undeclared action; evidence=`AGENTS.md`; rollback=revert this slice.' + [Environment]::NewLine)

        $report = Invoke-RuleEstateAudit -WorkspaceRoot $f.workspace -ExcludeNames @('external','文档') -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude

        @($report.findings | Where-Object { $_.code -eq 'project_mapping_unknown' -and $_.constraint_id -eq 'R9' }).Count | Should -Be 1
        $report.semantic_coverage_pass | Should -Be $false
    }

    It 'rejects duplicate mappings for one global constraint' {
        $f = New-RuleEstateFixture
        $agents = Join-Path $f.workspace 'repo-a\AGENTS.md'
        [IO.File]::AppendAllText($agents, [Environment]::NewLine + '- `R1`: duplicate action; evidence=`AGENTS.md`; rollback=revert this slice.' + [Environment]::NewLine)

        $report = Invoke-RuleEstateAudit -WorkspaceRoot $f.workspace -ExcludeNames @('external','文档') -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude
        $actions = @(Get-RuleEstateProjectActions $agents | Where-Object constraint_id -eq 'R1')

        $actions.Count | Should -Be 2
        @($report.findings | Where-Object { $_.code -eq 'project_mapping_duplicate' -and $_.constraint_id -eq 'R1' }).Count | Should -Be 1
        $report.semantic_coverage_pass | Should -Be $false
    }

    It 'reports incomplete and non-expiring N/A records' {
        $f = New-RuleEstateFixture
        $agents = Join-Path $f.workspace 'repo-a\AGENTS.md'
        [IO.File]::AppendAllText($agents, [Environment]::NewLine + '- `gate_na`: reason=fixture; evidence_link=docs/change-evidence/; expires_at=next_change; recovery_condition=code changes.' + [Environment]::NewLine)

        $report = Invoke-RuleEstateAudit -WorkspaceRoot $f.workspace -ExcludeNames @('external','文档') -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude

        @($report.findings | Where-Object code -eq 'project_na_invalid').Count | Should -BeGreaterThan 0
        $report.structural_pass | Should -Be $false
    }

    It 'blocks an expired N/A record' {
        $f = New-RuleEstateFixture
        $agents = Join-Path $f.workspace 'repo-a\AGENTS.md'
        $text = [IO.File]::ReadAllText($agents).Replace('expires_at=`2099-12-31`', 'expires_at=`2000-01-01`')
        [IO.File]::WriteAllText($agents, $text)

        $report = Invoke-RuleEstateAudit -WorkspaceRoot $f.workspace -ExcludeNames @('external','文档') -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude

        @($report.findings | Where-Object code -eq 'project_na_expired').Count | Should -Be 1
        $report.structural_pass | Should -Be $false
    }

    It 'blocks a project rule that exceeds the hard root budget' {
        $f = New-RuleEstateFixture
        [IO.File]::AppendAllText((Join-Path $f.workspace 'repo-a\AGENTS.md'), ('x' * 11000))

        $report = Invoke-RuleEstateAudit -WorkspaceRoot $f.workspace -ExcludeNames @('external','文档') -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude

        @($report.findings | Where-Object code -eq 'project_rule_budget_exceeded').Count | Should -Be 1
        $report.structural_pass | Should -Be $false
    }

    It 'reports an N/A evidence link whose repository file is absent' {
        $f = New-RuleEstateFixture
        $agents = Join-Path $f.workspace 'repo-a\AGENTS.md'
        $text = [IO.File]::ReadAllText($agents).Replace('docs/change-evidence/rule-contract.md', 'docs/change-evidence/missing.md')
        [IO.File]::WriteAllText($agents, $text)

        $report = Invoke-RuleEstateAudit -WorkspaceRoot $f.workspace -ExcludeNames @('external','文档') -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude

        @($report.findings | Where-Object code -eq 'project_na_evidence_missing').Count | Should -BeGreaterThan 0
        $report.structural_pass | Should -Be $false
    }

    It 'reports a Git profile that disagrees with repository truth' {
        $f = New-RuleEstateFixture
        $agents = Join-Path $f.workspace 'repo-a\AGENTS.md'
        $text = [IO.File]::ReadAllText($agents).Replace('baseline=`main`; upstream=`none`', 'baseline=`release`; upstream=`origin/main`')
        [IO.File]::WriteAllText($agents, $text)

        $report = Invoke-RuleEstateAudit -WorkspaceRoot $f.workspace -ExcludeNames @('external','文档') -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude

        @($report.findings | Where-Object code -eq 'project_git_baseline_mismatch').Count | Should -Be 1
        @($report.findings | Where-Object code -eq 'project_git_upstream_mismatch').Count | Should -Be 1
        $report.structural_pass | Should -Be $false
    }

    It 'continues to accept the legacy Git profile label' {
        $f = New-RuleEstateFixture
        $agents = Join-Path $f.workspace 'repo-a\AGENTS.md'
        $text = [IO.File]::ReadAllText($agents).Replace('Git baseline=', 'Git profile: baseline=')
        [IO.File]::WriteAllText($agents, $text)

        $report = Invoke-RuleEstateAudit -WorkspaceRoot $f.workspace -ExcludeNames @('external','文档') -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude

        @($report.findings | Where-Object code -like 'project_git_*').Count | Should -Be 0
    }

    It 'rejects an audit output reached through a workspace junction' {
        $f = New-RuleEstateFixture
        $outside = Join-Path $TestDrive ('audit-outside-' + [guid]::NewGuid().ToString('N'))
        $link = Join-Path $f.workspace 'linked-output'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        cmd /c "mklink /J `"$link`" `"$outside`"" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'junction fixture creation failed' }

        $out = Join-Path $link 'estate.json'
        { Invoke-RuleEstateAuditCommand @('--workspace-root',$f.workspace,'--codex-user-root',$f.codex,'--claude-user-root',$f.claude,'--out',$out,'--json') } | Should -Throw
        Test-Path -LiteralPath (Join-Path $outside 'estate.json') | Should -Be $false
    }

    It 'rejects an audit output that overwrites its registry input' {
        $f = New-RuleEstateFixture
        $registryPath = Join-Path $f.workspace 'registry.json'
        $registryText = '{"targets":[]}'
        [IO.File]::WriteAllText($registryPath, $registryText)

        { Invoke-RuleEstateAuditCommand @('--workspace-root',$f.workspace,'--codex-user-root',$f.codex,'--claude-user-root',$f.claude,'--registry',$registryPath,'--out',$registryPath,'--json') } | Should -Throw
        [IO.File]::ReadAllText($registryPath) | Should -Be $registryText
    }

    It 'reports stale project global-rule review releases' {
        $f = New-RuleEstateFixture
        $agents = Join-Path $f.workspace 'repo-a\AGENTS.md'
        $text = [IO.File]::ReadAllText($agents).Replace('**全局规则复核**: 9.60', '**全局规则复核**: 9.53')
        [IO.File]::WriteAllText($agents, $text)

        $report = Invoke-RuleEstateAudit -WorkspaceRoot $f.workspace -ExcludeNames @('external','文档') -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude

        @($report.targets | Where-Object name -eq 'repo-a')[0].release.aligned | Should -Be $false
        @($report.findings.code) | Should -Contain 'project_global_release_mismatch'
    }

    It 'reports missing project contract sections and an invalid Claude wrapper' {
        $f = New-RuleEstateFixture
        $agents = Join-Path $f.workspace 'repo-a\AGENTS.md'
        $text = [regex]::Replace([IO.File]::ReadAllText($agents), '(?ms)^## C\..*?(?=^## D\.)', '')
        [IO.File]::WriteAllText($agents, $text)
        Set-Content -LiteralPath (Join-Path $f.workspace 'repo-a\CLAUDE.md') -Value '# host-only rules' -Encoding UTF8

        $report = Invoke-RuleEstateAudit -WorkspaceRoot $f.workspace -ExcludeNames @('external','文档') -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude
        $repo = @($report.targets | Where-Object name -eq 'repo-a')[0]

        @($repo.findings.code) | Should -Contain 'project_contract_section_missing'
        @($repo.findings.code) | Should -Contain 'project_claude_wrapper_first_line_mismatch'
        $report.structural_pass | Should -Be $false
    }
}
