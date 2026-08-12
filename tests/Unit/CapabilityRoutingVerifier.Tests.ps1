$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $repoRoot 'scripts\verify-capability-routing.ps1'
$corpusPath = Join-Path $repoRoot 'config\capability-routing-golden.json'

Describe 'Capability routing golden verifier' {
    function Invoke-RoutingVerifier([string]$Corpus, [string]$Snapshot = '') {
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath, '-RepoRoot', $repoRoot, '-CorpusPath', $Corpus, '-Json')
        if (-not [string]::IsNullOrWhiteSpace($Snapshot)) { $arguments += @('-HostSnapshotPath', $Snapshot) }
        $output = @(& pwsh @arguments 2>&1)
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
        $corpus.cases[0].expected[0].name = 'missing-skill'
        $corpus | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
        $result = Invoke-RoutingVerifier $path
        $result.exit_code | Should Be 2
        @($result.data.findings.code) | Should Contain 'expected_selection_missing'
    }

    It 'audits every capability in a caller-provided host snapshot dynamically' {
        $snapshot = Join-Path $repoRoot 'tests\fixtures\capability-routing\runtime-capabilities.json'
        $result = Invoke-RoutingVerifier $corpusPath $snapshot
        $result.exit_code | Should Be 0
        $result.data.dynamic_audit.performed | Should Be $true
        $result.data.dynamic_audit.snapshot_count | Should Be 3
        $result.data.dynamic_audit.routed_count | Should Be 3
        $result.data.dynamic_audit.missing_count | Should Be 0
        $result.data.dynamic_audit.selection_probe_count | Should Be 3
        $result.data.dynamic_audit.selection_probe_passed_count | Should Be 3
        $result.data.dynamic_audit.selection_probe_missing_count | Should Be 0
        $result.data.dynamic_audit.unsafe_tool_gate_violation_count | Should Be 0
    }
}
