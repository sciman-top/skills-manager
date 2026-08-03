$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $repoRoot 'scripts\verify-vnext-phase4-entry-gate.ps1'
$decisionSource = Join-Path $repoRoot 'config\vnext-phase4-entry-gate.json'

Describe 'Conditional P4 entry gate' {
    function Invoke-P4Verifier([string]$Root, [string]$Path) {
        $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -RepoRoot $Root -DecisionPath $Path -Json 2>&1)
        return [pscustomobject]@{ exit_code = $LASTEXITCODE; data = (($output -join "`n") | ConvertFrom-Json) }
    }

    It 'accepts the current machine-verifiable started decision' {
        $result = Invoke-P4Verifier $repoRoot $decisionSource
        $result.exit_code | Should Be 0
        $result.data.pass | Should Be $true
        $result.data.decision | Should Be 'started'
        $result.data.status | Should Be 'in_progress'
        $result.data.all_required_met | Should Be $true
    }

    It 'fails closed when P4 is marked started with unmet gates' {
        $path = Join-Path $TestDrive 'started.json'
        $decision = Get-Content -Raw $decisionSource | ConvertFrom-Json
        $decision.gates[0].state = 'not_met'; $decision.all_required_met = $false
        $decision | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
        $result = Invoke-P4Verifier $TestDrive $path
        $result.exit_code | Should Be 2
        @($result.data.findings.code) | Should Contain 'p4_started_without_entry'
    }

    It 'fails closed when the aggregate flag contradicts gate states' {
        $path = Join-Path $TestDrive 'aggregate.json'
        $decision = Get-Content -Raw $decisionSource | ConvertFrom-Json
        $decision.all_required_met = $false
        $decision | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
        $result = Invoke-P4Verifier $TestDrive $path
        $result.exit_code | Should Be 2
        @($result.data.findings.code) | Should Contain 'p4_all_required_mismatch'
    }

    It 'fails closed when gate evidence does not resolve to a repository file' {
        $root = Join-Path $TestDrive 'missing-evidence-root'; New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'decision.json'
        $decision = Get-Content -Raw $decisionSource | ConvertFrom-Json
        $decision.gates[0].evidence = @('missing.md')
        $decision | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
        $result = Invoke-P4Verifier $root $path
        $result.exit_code | Should Be 2
        @($result.data.findings.code) | Should Contain 'p4_gate_evidence_invalid'
    }
}
