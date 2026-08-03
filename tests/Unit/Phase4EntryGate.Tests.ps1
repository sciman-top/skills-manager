$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $repoRoot 'scripts\verify-vnext-phase4-entry-gate.ps1'
$decisionSource = Join-Path $repoRoot 'config\vnext-phase4-entry-gate.json'

Describe 'Conditional P4 entry gate' {
    function Invoke-P4Verifier([string]$Root, [string]$Path) {
        $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -RepoRoot $Root -DecisionPath $Path -Json 2>&1)
        return [pscustomobject]@{ exit_code = $LASTEXITCODE; data = (($output -join "`n") | ConvertFrom-Json) }
    }

    It 'accepts the current machine-verifiable completed decision' {
        $result = Invoke-P4Verifier $repoRoot $decisionSource
        $result.exit_code | Should Be 0
        $result.data.pass | Should Be $true
        $result.data.decision | Should Be 'started'
        $result.data.status | Should Be 'completed'
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

    It 'fails closed when completed P4 still has an open manifest task' {
        $root = Join-Path $TestDrive 'open-task-root'
        New-Item -ItemType Directory -Path (Join-Path $root 'tasks') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'docs\change-evidence') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'docs\superpowers\specs') -Force | Out-Null
        Copy-Item -LiteralPath $decisionSource -Destination (Join-Path $root 'decision.json')
        $sourceManifest = Get-Content -Raw (Join-Path $repoRoot 'tasks\skills-manager-vnext-phase4.tasks.json') | ConvertFrom-Json
        $sourceManifest.tasks[0].status = 'in_progress'
        $sourceManifest | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $root 'tasks\skills-manager-vnext-phase4.tasks.json') -Encoding UTF8
        $decision = Get-Content -Raw (Join-Path $root 'decision.json') | ConvertFrom-Json
        foreach ($gate in @($decision.gates)) {
            $gate.evidence = @('tasks/skills-manager-vnext-phase4.tasks.json')
        }
        $decision | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $root 'decision.json') -Encoding UTF8

        $result = Invoke-P4Verifier $root (Join-Path $root 'decision.json')
        $result.exit_code | Should Be 2
        @($result.data.findings.code) | Should Contain 'p4_completed_with_open_tasks'
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
