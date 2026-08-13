$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $repoRoot 'scripts\verify-capability-routing.ps1'
$corpusPath = Join-Path $repoRoot 'config\capability-routing-golden.json'

Describe 'Native-first capability routing verifier' {
    It 'invokes the pure policy script in-process' {
        $source = Get-Content -LiteralPath $scriptPath -Raw
        $source | Should Not Match '& pwsh @args'
        $source | Should Match '& \$routerFile @routerArgs'
        $source | Should Not Match 'reports/skill-projection/current\.json'
        $source | Should Not Match 'agent/capability-router'
    }

    function Invoke-RoutingVerifier([string]$Corpus) {
        $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -RepoRoot $repoRoot -CorpusPath $Corpus -Json 2>&1)
        return [pscustomobject]@{ exit_code = $LASTEXITCODE; data = (($output -join "`n") | ConvertFrom-Json) }
    }

    function Copy-RoutingCase($Case) {
        return (($Case | ConvertTo-Json -Depth 20) | ConvertFrom-Json)
    }

    It 'passes the natural-language corpus without semantic auto-selection or side-effect violations' {
        $result = Invoke-RoutingVerifier $corpusPath
        $result.exit_code | Should Be 0
        $result.data.pass | Should Be $true
        $result.data.decision_owner | Should Be 'host_ai'
        $result.data.case_count | Should BeGreaterThan 20
        $result.data.candidate_recall_passed_count | Should Be $result.data.case_count
        $result.data.policy_passed_count | Should Be $result.data.case_count
        $result.data.semantic_auto_selection_count | Should Be 0
        $result.data.negative_constraint_violation_count | Should Be 0
        $result.data.side_effect_violation_count | Should Be 0
        $result.data.writes_performed | Should Be $false
    }

    It 'validates inventory provenance and host-only declarations in one verifier run' {
        $path = Join-Path $TestDrive 'inventory-contract-corpus.json'
        $sourceCorpus = Get-Content -LiteralPath $corpusPath -Raw | ConvertFrom-Json

        $missingHostSelection = Copy-RoutingCase $sourceCorpus.cases[0]
        $missingHostSelection.id = 'missing-host-selected-skill'
        $missingHostSelection.host_selected[0].name = 'missing-skill'

        $inventedExplicitSkill = Copy-RoutingCase $sourceCorpus.cases[0]
        $inventedExplicitSkill.id = 'invented-explicit-skill'
        $inventedExplicitSkill.query = '请使用 $definitely-nonexistent-routing-skill'
        $inventedExplicitSkill.domain_hints = @()
        $inventedExplicitSkill.expected_candidates = @([pscustomobject]@{ kind = 'skill'; name = 'definitely-nonexistent-routing-skill' })
        $inventedExplicitSkill.host_selected = @([pscustomobject]@{ kind = 'skill'; name = 'definitely-nonexistent-routing-skill'; action = 'load_skill' })
        $inventedExplicitSkill.forbidden_candidates = @()

        $missingMcp = Copy-RoutingCase (@($sourceCorpus.cases | Where-Object id -eq 'official-docs')[0])
        $missingMcp.id = 'missing-mcp'
        $missingMcp.expected_candidates[0].name = 'definitely-nonexistent-routing-mcp'
        $missingMcp.host_selected = @()

        $declaredHostCapability = Copy-RoutingCase (@($sourceCorpus.cases | Where-Object id -eq 'mcp-read')[0])
        $declaredHostCapability.id = 'declared-host-capability'

        $undeclaredHostCapability = Copy-RoutingCase $declaredHostCapability
        $undeclaredHostCapability.id = 'undeclared-host-capability'
        $undeclaredHostCapability.PSObject.Properties.Remove('snapshot_path')

        $sourceCorpus.cases = @($missingHostSelection, $inventedExplicitSkill, $missingMcp, $declaredHostCapability, $undeclaredHostCapability)
        $sourceCorpus | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8

        $result = Invoke-RoutingVerifier $path

        $result.exit_code | Should Be 2
        $result.data.case_count | Should Be 5
        $result.data.passed_case_count | Should Be 1
        @($result.data.findings | Where-Object code -eq 'unknown_skill_reference').Count | Should Be 3
        @($result.data.findings.case_id) | Should Contain 'missing-host-selected-skill'
        @($result.data.findings.case_id) | Should Contain 'invented-explicit-skill'
        @($result.data.findings.code) | Should Contain 'unknown_mcp_reference'
        @($result.data.findings.code) | Should Contain 'undeclared_host_capability'
        @($result.data.findings.case_id) | Should Not Contain 'declared-host-capability'
        $result.data.writes_performed | Should Be $false
    }
}
