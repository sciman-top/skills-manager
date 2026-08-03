$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $repoRoot 'scripts\verify-capability-routing.ps1'
$corpusPath = Join-Path $repoRoot 'config\capability-routing-golden.json'

Describe 'Capability routing golden verifier' {
    It 'invokes the pure router in-process instead of spawning one PowerShell per case' {
        $source = Get-Content -LiteralPath $scriptPath -Raw
        $source | Should Not Match "& pwsh @args"
        $source | Should Match '& \$routerFile @routerArgs'
    }

    function Invoke-RoutingVerifier([string]$Corpus) {
        $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -RepoRoot $repoRoot -CorpusPath $Corpus -Json 2>&1)
        return [pscustomobject]@{ exit_code = $LASTEXITCODE; data = (($output -join "`n") | ConvertFrom-Json) }
    }

    It 'passes the repository golden corpus with zero side-effect violations' {
        $result = Invoke-RoutingVerifier $corpusPath
        $result.exit_code | Should Be 0
        $result.data.pass | Should Be $true
        $result.data.case_count | Should Be 11
        $result.data.side_effect_violation_count | Should Be 0
        $result.data.writes_performed | Should Be $false
    }

    It 'fails closed when an expected selection drifts' {
        $path = Join-Path $TestDrive 'bad-corpus.json'
        $corpus = Get-Content -LiteralPath $corpusPath -Raw | ConvertFrom-Json
        $corpus.cases = @($corpus.cases[0])
        $corpus.cases[0].expected[0].name = 'missing-skill'
        $corpus | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
        $result = Invoke-RoutingVerifier $path
        $result.exit_code | Should Be 2
        @($result.data.findings.code) | Should Contain 'expected_selection_missing'
    }
}
