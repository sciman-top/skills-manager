$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'src\Infrastructure\AtomicFile.ps1')
. (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
. (Join-Path $repoRoot 'src\Domain\CapabilityDescriptor.ps1')
. (Join-Path $repoRoot 'src\Domain\RuleDocument.ps1')
. (Join-Path $repoRoot 'src\Domain\RuleResponsibility.ps1')
. (Join-Path $repoRoot 'src\Domain\RulePatchPlan.ps1')
. (Join-Path $repoRoot 'src\Application\RuleDiscovery.ps1')
. (Join-Path $repoRoot 'src\Application\RuleDiagnostics.ps1')
. (Join-Path $repoRoot 'src\Application\RuleAdvisor.ps1')
. (Join-Path $repoRoot 'src\Application\RuleAudit.ps1')
. (Join-Path $repoRoot 'src\Application\RuleEstate.ps1')
. (Join-Path $repoRoot 'src\Commands\RuleEstate.ps1')

Describe 'Workspace rule estate audit' {
    function New-RuleEstateFixture {
        $workspace = Join-Path $TestDrive 'workspace'; New-Item -ItemType Directory -Path $workspace -Force | Out-Null
        foreach ($name in @('repo-a', 'repo-b', 'external', '文档')) {
            $path = Join-Path $workspace $name; New-Item -ItemType Directory -Path (Join-Path $path '.git') -Force | Out-Null
            if ($name -notin @('external', '文档')) {
                @'
# Project
**全局规则复核**: 9.60

## D. Global Rule -> Repo Action

- `R1-R2`: use repository commands and evidence.
- `E4/E5/E6`: use health, supply-chain, and migration gates.
'@ | Set-Content -LiteralPath (Join-Path $path 'AGENTS.md') -Encoding UTF8
            }
        }
        Set-Content -LiteralPath (Join-Path $workspace 'repo-a\CLAUDE.md') -Value '@AGENTS.md' -Encoding UTF8
        $codex = Join-Path $TestDrive 'codex'; $claude = Join-Path $TestDrive 'claude'; New-Item -ItemType Directory -Path $codex,$claude -Force | Out-Null
        $common = @'
**版本**: 9.60

## A. Common

R1 R2

## B. Platform

host delta

## C. Project contract

Map R1-R2 and E4/E5/E6.

## D. Maintenance

verify drift
'@
        Set-Content -LiteralPath (Join-Path $codex 'AGENTS.md') -Value $common -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $claude 'CLAUDE.md') -Value $common -Encoding UTF8
        return [pscustomobject]@{ workspace=$workspace; codex=$codex; claude=$claude }
    }

    It 'discovers direct Git roots, applies exclusions, and reports registry drift' {
        $f = New-RuleEstateFixture
        $registry = @([pscustomobject]@{ path = (Join-Path $f.workspace 'repo-a'); enabled = $true }, [pscustomobject]@{ path = (Join-Path $f.workspace 'gone'); enabled = $true })
        $result = Get-RuleEstateTargets -WorkspaceRoot $f.workspace -RegistryTargets $registry

        $result.target_count | Should Be 2
        @($result.targets.name) | Should Contain 'repo-a'
        @($result.targets.name) | Should Not Contain 'external'
        @($result.registry.unregistered_paths).Count | Should Be 1
        @($result.registry.missing_paths).Count | Should Be 1
        $result.registry.in_sync | Should Be $false
    }

    It 'separates aligned common sections from platform deltas' {
        $f = New-RuleEstateFixture
        $result = Get-RuleEstateGlobalAlignment $f.codex $f.claude

        $result.common_aligned | Should Be $true
        $result.codex_delta_present | Should Be $true
        $result.claude_delta_present | Should Be $true
        @($result.findings).Count | Should Be 0
    }

    It 'does not report registry drift when no registry comparison was requested' {
        $f = New-RuleEstateFixture
        $result = Get-RuleEstateTargets -WorkspaceRoot $f.workspace

        $result.registry.supplied | Should Be $false
        $result.registry.in_sync | Should Be $true
        @($result.registry.unregistered_paths).Count | Should Be 0
    }

    It 'builds cross-host responsibility coverage and bounded patch candidates' {
        $f = New-RuleEstateFixture
        $report = Invoke-RuleEstateAudit -WorkspaceRoot $f.workspace -ExcludeNames @('external','文档') -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude

        $report.summary.target_count | Should Be 2
        $report.summary.covered_count | Should BeGreaterThan 0
        $report.summary.patch_candidate_count | Should Be 1
        $report.patch_candidates[0].target_path | Should Match 'repo-b\\CLAUDE\.md$'
        $report.writes | Should Be 0
        $report.provider_calls | Should Be 0
        $report.host_loaded | Should Be 'not_run'
    }

    It 'returns a single JSON envelope and only writes an explicit report' {
        $f = New-RuleEstateFixture; $out = Join-Path $TestDrive 'estate.json'
        $result = Invoke-RuleEstateAuditCommand @('--workspace-root',$f.workspace,'--codex-user-root',$f.codex,'--claude-user-root',$f.claude,'--out',$out,'--json')
        $parsed = $result.output | ConvertFrom-Json

        $result.exit_code | Should Be 0
        $parsed.command | Should Be 'rule-estate-audit'
        $parsed.writes | Should Be 1
        $parsed.report.writes | Should Be 0
        Test-Path -LiteralPath $out | Should Be $true
    }

    It 'reports stale project global-rule review releases' {
        $f = New-RuleEstateFixture
        $agents = Join-Path $f.workspace 'repo-a\AGENTS.md'
        $text = [IO.File]::ReadAllText($agents).Replace('**全局规则复核**: 9.60', '**全局规则复核**: 9.53')
        [IO.File]::WriteAllText($agents, $text)

        $report = Invoke-RuleEstateAudit -WorkspaceRoot $f.workspace -ExcludeNames @('external','文档') -CodexUserRoot $f.codex -ClaudeUserRoot $f.claude

        @($report.targets | Where-Object name -eq 'repo-a')[0].release.aligned | Should Be $false
        @($report.findings.code) | Should Contain 'project_global_release_mismatch'
    }
}
