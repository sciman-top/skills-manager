$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$verifier = Join-Path $repoRoot 'scripts\verify-agent-workflow-advisory.ps1'

function Invoke-AgentWorkflowAdvisoryVerifier([string]$RootPath) {
    $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $verifier -RepoRoot $RootPath -Json 2>&1)
    return [pscustomobject]@{
        exit_code = $LASTEXITCODE
        output = ($output -join "`n")
    }
}

function New-AgentWorkflowAdvisoryFixture([string]$Name) {
    $fixtureRoot = Join-Path $TestDrive ("agent-workflow-advisory-{0}-{1}" -f $Name, [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    foreach ($relativePath in @(
            'tasks/skills-manager-vnext-agent-workflow-advisory.tasks.json',
            'docs/superpowers/specs/2026-08-05-agent-workflow-advisory-runtime.md',
            'docs/change-evidence/20260806-agent-workflow-and-watch-safety-hardening.md',
            'docs/product/skills-manager-vnext-prd.md',
            'docs/product/skills-manager-vnext-architecture.md',
            'docs/product/skills-manager-vnext-roadmap.md',
            'docs/product/README.md',
            'tasks/plan.md',
            'tasks/todo.md',
            'AGENTS.md',
            'README.md',
            'README.en.md',
            'src/Domain/AgentWorkflow.ps1',
            'src/Application/ModelAndAgentPolicy.ps1',
            'src/Commands/AgentWorkflow.ps1',
            'src/Main.ps1',
            'src/Version.ps1',
            'build.ps1',
            'tests/Unit/AgentWorkflowContracts.Tests.ps1',
            'tests/fixtures/agent-workflow/valid-request.json',
            'tests/fixtures/agent-workflow/invalid-request.json'
        )) {
        $source = Join-Path $repoRoot $relativePath
        $destination = Join-Path $fixtureRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        if (Test-Path -LiteralPath $source -PathType Leaf) { Copy-Item -LiteralPath $source -Destination $destination -Force }
        else { Set-Content -LiteralPath $destination -Value '' -Encoding UTF8 }
    }
    return $fixtureRoot
}

Describe 'Agent workflow advisory planning verifier' {
    It 'accepts the current repository contract' {
        $result = Invoke-AgentWorkflowAdvisoryVerifier $repoRoot
        if ($result.exit_code -ne 0) { Write-Host $result.output }
        $parsed = $result.output | ConvertFrom-Json

        $result.exit_code | Should Be 0
        $parsed.status | Should Be 'pass'
        $parsed.track | Should Be 'agent_workflow_advisory_runtime'
        $parsed.truth_boundary | Should Be 'repo_advisory_only'
        $parsed.tasks | Should Be 5
        $parsed.done | Should Be 5
        $parsed.model_tiers | Should Be 3
        $parsed.provider_calls | Should Be 0
        $parsed.native_mutations | Should Be 0
        $parsed.writes | Should Be 0
        @($parsed.findings).Count | Should Be 0
    }

    It 'rejects runtime scheduler provider and host mutation claims' {
        $fixtureRoot = New-AgentWorkflowAdvisoryFixture 'runtime-boundary'
        $path = Join-Path $fixtureRoot 'tasks\skills-manager-vnext-agent-workflow-advisory.tasks.json'
        $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $manifest.runtime_scheduler_status = 'implemented'
        $manifest.provider_call_status = 'enabled'
        $manifest.native_mutation_status = 'enabled'
        $manifest.host_loaded_status = 'loaded'
        $manifest.host_orchestration_status = 'unbounded_runtime'
        $manifest.host_radar_refresh_status = 'repo_scheduler'
        $manifest.live_acceptance_status = 'live_accepted'
        $manifest | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $path -Encoding UTF8

        $parsed = (Invoke-AgentWorkflowAdvisoryVerifier $fixtureRoot).output | ConvertFrom-Json
        foreach ($code in @('runtime_scheduler_boundary_invalid', 'provider_call_boundary_invalid', 'native_mutation_boundary_invalid', 'host_loaded_boundary_invalid', 'host_orchestration_boundary_invalid', 'host_radar_boundary_invalid', 'live_acceptance_boundary_invalid')) {
            @($parsed.findings | Where-Object code -eq $code).Count | Should Be 1
        }
    }

    It 'rejects command and build wiring drift' {
        $fixtureRoot = New-AgentWorkflowAdvisoryFixture 'command-wiring'
        $versionPath = Join-Path $fixtureRoot 'src\Version.ps1'
        $version = (Get-Content -LiteralPath $versionPath -Raw).Replace(', "agent-plan", "agent-validate"', '')
        Set-Content -LiteralPath $versionPath -Value $version -Encoding UTF8
        $buildPath = Join-Path $fixtureRoot 'build.ps1'
        $build = (Get-Content -LiteralPath $buildPath -Raw).Replace('    "Domain/AgentWorkflow.ps1",', '')
        Set-Content -LiteralPath $buildPath -Value $build -Encoding UTF8

        $parsed = (Invoke-AgentWorkflowAdvisoryVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq 'cli_command_wiring_missing').Count | Should BeGreaterThan 0
        @($parsed.findings | Where-Object code -eq 'build_source_wiring_missing').Count | Should Be 1
    }

    It 'rejects hard routing and mutated model anchors' {
        $fixtureRoot = New-AgentWorkflowAdvisoryFixture 'model-policy'
        $path = Join-Path $fixtureRoot 'tasks\skills-manager-vnext-agent-workflow-advisory.tasks.json'
        $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $manifest.model_tiers[0].mode = 'hard_route'
        $manifest.model_tiers[1].reasoning_effort = 'xhigh'
        $manifest | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $path -Encoding UTF8

        $parsed = (Invoke-AgentWorkflowAdvisoryVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq 'model_tier_anchor_invalid').Count | Should Be 2
    }

    It 'rejects reactivating Radar receipts' {
        $fixtureRoot = New-AgentWorkflowAdvisoryFixture 'host-receipt'
        $manifestPath = Join-Path $fixtureRoot 'tasks\skills-manager-vnext-agent-workflow-advisory.tasks.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.host_radar_refresh_status = 'pending_revalidation'
        $manifest | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

        $parsed = (Invoke-AgentWorkflowAdvisoryVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq 'radar_active_contract_detected').Count | Should BeGreaterThan 0
    }

    It 'rejects zero-side-effect and ownership drift' {
        $fixtureRoot = New-AgentWorkflowAdvisoryFixture 'effects-owner'
        $commandPath = Join-Path $fixtureRoot 'src\Commands\AgentWorkflow.ps1'
        $command = (Get-Content -LiteralPath $commandPath -Raw).Replace("decision_owner = 'host_ai'", "decision_owner = 'repository_router'").Replace('provider_calls = 0; native_mutations = 0; writes = 0', 'provider_calls = 1; native_mutations = 1; writes = 1')
        Set-Content -LiteralPath $commandPath -Value $command -Encoding UTF8

        $parsed = (Invoke-AgentWorkflowAdvisoryVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq 'host_decision_owner_missing').Count | Should Be 1
        @($parsed.findings | Where-Object code -eq 'zero_side_effect_contract_missing').Count | Should Be 1
    }

    It 'rejects an active Radar decision path' {
        $fixtureRoot = New-AgentWorkflowAdvisoryFixture 'active-radar-decision'
        $applicationPath = Join-Path $fixtureRoot 'src\Application\ModelAndAgentPolicy.ps1'
        $application = (Get-Content -LiteralPath $applicationPath -Raw).Replace('$validLocalOutcomes = New-Object', '$radarValidation = Test-RadarSnapshotContract -Snapshot $RadarSnapshot -Now $Now`r`n    $validLocalOutcomes = New-Object')
        Set-Content -LiteralPath $applicationPath -Value $application -Encoding UTF8

        $parsed = (Invoke-AgentWorkflowAdvisoryVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq 'active_radar_decision_path_detected').Count | Should BeGreaterThan 0
    }

    It 'does not lock the advisory verifier to behavior-test implementation literals' {
        $fixtureRoot = New-AgentWorkflowAdvisoryFixture 'implementation-literal-refactor'
        $domainPath = Join-Path $fixtureRoot 'src\Domain\AgentWorkflow.ps1'
        $domain = (Get-Content -LiteralPath $domainPath -Raw).Replace('native_baseline_required', 'native_admission_required').Replace('radar_source_untrusted', 'radar_source_not_trusted')
        Set-Content -LiteralPath $domainPath -Value $domain -Encoding UTF8
        $applicationPath = Join-Path $fixtureRoot 'src\Application\ModelAndAgentPolicy.ps1'
        $application = (Get-Content -LiteralPath $applicationPath -Raw).Replace('completion_receipt_unclaimed', 'completion_receipt_not_claimed').Replace('completed_dependency_not_closed', 'completed_dependency_open')
        Set-Content -LiteralPath $applicationPath -Value $application -Encoding UTF8
        $contractTestPath = Join-Path $fixtureRoot 'tests\Unit\AgentWorkflowContracts.Tests.ps1'
        $contractTests = (Get-Content -LiteralPath $contractTestPath -Raw).Replace("Describe 'Agent workflow advisory contracts'", "Describe 'Agent workflow behavior contracts'")
        Set-Content -LiteralPath $contractTestPath -Value $contractTests -Encoding UTF8
        $validFixturePath = Join-Path $fixtureRoot 'tests\fixtures\agent-workflow\valid-request.json'
        $validFixture = Get-Content -LiteralPath $validFixturePath -Raw | ConvertFrom-Json
        $validFixture.task_graph.graph_id = 'graph-fixture-refactor-001'
        $validFixture | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $validFixturePath -Encoding UTF8

        $parsed = (Invoke-AgentWorkflowAdvisoryVerifier $fixtureRoot).output | ConvertFrom-Json

        $parsed.status | Should Be 'pass'
        @($parsed.findings).Count | Should Be 0
    }
}
