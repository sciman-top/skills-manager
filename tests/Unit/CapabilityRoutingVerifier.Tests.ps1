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

    It 'fails closed when the labelled host selection drifts' {
        $path = Join-Path $TestDrive 'bad-corpus.json'
        $corpus = Get-Content -LiteralPath $corpusPath -Raw | ConvertFrom-Json
        $corpus.cases = @($corpus.cases[0])
        $corpus.cases[0].host_selected[0].name = 'missing-skill'
        $corpus | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
        $result = Invoke-RoutingVerifier $path
        $result.exit_code | Should Be 2
        @($result.data.findings.code) | Should Contain 'unknown_skill_reference'
    }

    It 'rejects an explicitly mentioned skill that exists only in the corpus' {
        $path = Join-Path $TestDrive 'invented-skill-corpus.json'
        $corpus = Get-Content -LiteralPath $corpusPath -Raw | ConvertFrom-Json
        $corpus.cases = @($corpus.cases[0])
        $corpus.cases[0].query = '请使用 $definitely-nonexistent-routing-skill'
        $corpus.cases[0].profile_hints = @()
        $corpus.cases[0].expected_candidates = @([pscustomobject]@{ kind = 'skill'; name = 'definitely-nonexistent-routing-skill' })
        $corpus.cases[0].host_selected = @([pscustomobject]@{ kind = 'skill'; name = 'definitely-nonexistent-routing-skill'; action = 'load_skill' })
        $corpus.cases[0].forbidden_candidates = @()
        $corpus | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8

        $result = Invoke-RoutingVerifier $path

        $result.exit_code | Should Be 2
        @($result.data.findings.code) | Should Contain 'unknown_skill_reference'
    }

    It 'rejects an MCP reference that is absent from skills.json' {
        $path = Join-Path $TestDrive 'invented-mcp-corpus.json'
        $corpus = Get-Content -LiteralPath $corpusPath -Raw | ConvertFrom-Json
        $corpus.cases = @($corpus.cases | Where-Object id -eq 'official-docs')
        $corpus.cases[0].expected_candidates[0].name = 'definitely-nonexistent-routing-mcp'
        $corpus.cases[0].host_selected = @()
        $corpus | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8

        $result = Invoke-RoutingVerifier $path

        $result.exit_code | Should Be 2
        @($result.data.findings.code) | Should Contain 'unknown_mcp_reference'
    }

    It 'accepts host-only capabilities declared by the case runtime snapshot' {
        $path = Join-Path $TestDrive 'declared-host-capability-corpus.json'
        $corpus = Get-Content -LiteralPath $corpusPath -Raw | ConvertFrom-Json
        $corpus.cases = @($corpus.cases | Where-Object id -eq 'mcp-read')
        $corpus | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8

        $result = Invoke-RoutingVerifier $path

        $result.exit_code | Should Be 0
        $result.data.pass | Should Be $true
    }

    It 'rejects host-only capabilities without an explicit runtime snapshot declaration' {
        $path = Join-Path $TestDrive 'undeclared-host-capability-corpus.json'
        $corpus = Get-Content -LiteralPath $corpusPath -Raw | ConvertFrom-Json
        $corpus.cases = @($corpus.cases | Where-Object id -eq 'mcp-read')
        $corpus.cases[0].PSObject.Properties.Remove('snapshot_path')
        $corpus | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8

        $result = Invoke-RoutingVerifier $path

        $result.exit_code | Should Be 2
        @($result.data.findings.code) | Should Contain 'undeclared_host_capability'
    }
}
