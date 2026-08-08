Describe 'Host-native skill lifecycle planning contract' {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    $scriptPath = Join-Path $repoRoot 'scripts\verify-host-native-skill-lifecycle-planning.ps1'
    $required = @(
        'docs/product/skills-manager-vnext-prd.md',
        'docs/product/skills-manager-vnext-architecture.md',
        'docs/product/skills-manager-vnext-roadmap.md',
        'docs/superpowers/specs/2026-08-07-capability-manager-vnext-phase-6-design.md',
        'docs/superpowers/plans/2026-08-07-host-native-skill-lifecycle-reset.md',
        'tasks/skills-manager-vnext-phase6.tasks.json',
        'tasks/plan.md',
        'tasks/todo.md',
        'docs/change-evidence/20260807-host-native-skill-lifecycle-reset-planning.md',
        'AGENTS.md',
        'overrides/custom/capability-router/SKILL.md',
        'overrides/custom/capability-router/agents/openai.yaml'
    )

    function Invoke-Verifier([string]$Root, [switch]$External) {
        $output = if ($External) {
            @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -RepoRoot $Root -Json 2>&1)
        } else {
            @(& $scriptPath -RepoRoot $Root -Json -NoExit 2>&1)
        }
        [pscustomobject]@{ exit_code = $LASTEXITCODE; parsed = (($output -join "`n") | ConvertFrom-Json) }
    }

    function New-Fixture([string]$Name) {
        $root = Join-Path $TestDrive $Name
        foreach ($relative in $required) {
            $source = Join-Path $repoRoot $relative
            $target = Join-Path $root $relative
            New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $target -Force
        }
        $root
    }

    It 'accepts the current P6 planning contract through CLI and composable mode' {
        $external = Invoke-Verifier $repoRoot -External
        $external.exit_code | Should Be 0
        $external.parsed.pass | Should Be $true
        $external.parsed.task_count | Should Be 12
        $external.parsed.truth_level | Should Be 'planning_contract'

        $composable = Invoke-Verifier $repoRoot
        $composable.exit_code | Should Be 0
        $composable.parsed.finding_count | Should Be 0
    }

    It 'rejects a roadmap that returns P6 to hold' {
        $root = New-Fixture 'hold'
        $path = Join-Path $root 'docs/product/skills-manager-vnext-roadmap.md'
        (Get-Content $path -Raw).Replace('P6_ADMISSION_STATUS: admitted', 'P6_ADMISSION_STATUS: hold') | Set-Content $path -Encoding UTF8
        $result = Invoke-Verifier $root
        @($result.parsed.findings | Where-Object code -eq 'p6_not_admitted').Count | Should Be 1
    }

    It 'rejects unknown task status' {
        $root = New-Fixture 'unknown-status'
        $path = Join-Path $root 'tasks/skills-manager-vnext-phase6.tasks.json'
        $manifest = Get-Content $path -Raw | ConvertFrom-Json
        $manifest.tasks[0].status = 'complete'
        $manifest | ConvertTo-Json -Depth 100 | Set-Content $path -Encoding UTF8
        $result = Invoke-Verifier $root
        @($result.parsed.findings | Where-Object code -eq 'unknown_task_status').Count | Should Be 1
    }

    It 'rejects task coverage drift' {
        $root = New-Fixture 'coverage'
        $path = Join-Path $root 'tasks/todo.md'
        (Get-Content $path -Raw).Replace('SMV-P6-008', 'SMV-P6-X08') | Set-Content $path -Encoding UTF8
        $result = Invoke-Verifier $root
        @($result.parsed.findings | Where-Object code -eq 'todo_task_coverage_mismatch').Count | Should Be 1
    }

    It 'rejects planning evidence that claims host loading' {
        $root = New-Fixture 'host-loaded'
        $path = Join-Path $root 'docs/change-evidence/20260807-host-native-skill-lifecycle-reset-planning.md'
        (Get-Content $path -Raw).Replace('**host_loaded**: `not_run`', '**host_loaded**: `repo_verified`') | Set-Content $path -Encoding UTF8
        $result = Invoke-Verifier $root
        @($result.parsed.findings | Where-Object code -eq 'planning_truth_boundary_violation').Count | Should Be 1
    }

    It 'requires complete native projection and strict fallback decisions' {
        $root = New-Fixture 'invariants'
        $specPath = Join-Path $root 'docs/superpowers/specs/2026-08-07-capability-manager-vnext-phase-6-design.md'
        $archPath = Join-Path $root 'docs/product/skills-manager-vnext-architecture.md'
        (Get-Content $specPath -Raw).Replace('enabled_total == kept_total', 'enabled total approximately matches kept total') | Set-Content $specPath -Encoding UTF8
        (Get-Content $archPath -Raw).Replace('ADR-SMV-038', 'ADR-SMV-X38') | Set-Content $archPath -Encoding UTF8
        $result = Invoke-Verifier $root
        @($result.parsed.findings | Where-Object code -eq 'complete_projection_invariant_missing').Count | Should Be 1
        @($result.parsed.findings | Where-Object code -eq 'strict_fallback_decision_missing').Count | Should Be 1
    }

    It 'rejects mandatory or implicit capability-router control surfaces' {
        $root = New-Fixture 'mandatory-router'
        $agentsPath = Join-Path $root 'AGENTS.md'
        $skillPath = Join-Path $root 'overrides/custom/capability-router/SKILL.md'
        $metadataPath = Join-Path $root 'overrides/custom/capability-router/agents/openai.yaml'
        Add-Content -LiteralPath $agentsPath -Value "`n- Every non-trivial task must first execute capability-router."
        Add-Content -LiteralPath $skillPath -Value "`nStart every non-trivial task with this normal start-of-task path, not an optional fallback."
        (Get-Content $metadataPath -Raw).Replace('allow_implicit_invocation: false', 'allow_implicit_invocation: true') | Set-Content $metadataPath -Encoding UTF8

        $result = Invoke-Verifier $root
        @($result.parsed.findings | Where-Object code -eq 'legacy_router_restored_as_primary').Count | Should Be 2
        @($result.parsed.findings | Where-Object code -eq 'legacy_router_implicit_invocation_enabled').Count | Should Be 1
    }
}
