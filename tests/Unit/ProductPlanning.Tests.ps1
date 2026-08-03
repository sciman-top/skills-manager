Describe 'vNext product planning contract' {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    $scriptPath = Join-Path $repoRoot 'scripts\verify-vnext-planning.ps1'
    $currentPhase = 'P5'
    $currentManifestRelative = 'tasks\skills-manager-vnext-phase5.tasks.json'
    $currentSpecRelative = 'docs\superpowers\specs\2026-08-03-capability-manager-vnext-phase-5-design.md'
    $requiredFiles = @(
        'docs\product\README.md', 'docs\product\skills-manager-vnext-prd.md', 'docs\product\skills-manager-vnext-architecture.md',
        'docs\product\skills-manager-vnext-roadmap.md', 'docs\product\rule-governance-adoption-matrix.md',
        'docs\superpowers\specs\2026-08-01-capability-manager-vnext-phase-0-design.md',
        'docs\superpowers\specs\2026-08-02-capability-manager-vnext-phase-1-design.md',
        'docs\superpowers\specs\2026-08-02-capability-manager-vnext-phase-2-design.md',
        'docs\superpowers\specs\2026-08-02-capability-manager-vnext-phase-3-design.md',
        'docs\superpowers\specs\2026-08-02-capability-manager-vnext-phase-4-design.md', $currentSpecRelative,
        'tasks\skills-manager-vnext-phase0.tasks.json', 'tasks\skills-manager-vnext-phase1.tasks.json',
        'tasks\skills-manager-vnext-phase2.tasks.json', 'tasks\skills-manager-vnext-phase3.tasks.json',
        'tasks\skills-manager-vnext-phase4.tasks.json', $currentManifestRelative,
        'tasks\plan.md', 'tasks\todo.md', 'README.md', 'AGENTS.md'
    )

    function Invoke-PlanningVerifier([string]$Root, [string]$ManifestPath = '', [string]$SpecPath = '', [switch]$External) {
        $params = @{ RepoRoot = $Root; Json = $true }
        if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) { $params.ManifestPath = $ManifestPath }
        if (-not [string]::IsNullOrWhiteSpace($SpecPath)) { $params.SpecPath = $SpecPath }
        $output = if ($External) {
            @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -RepoRoot $Root -Json 2>&1)
        }
        else {
            @(& $scriptPath @params -NoExit 2>&1)
        }
        return [pscustomobject]@{ exit_code = $LASTEXITCODE; output = ($output -join "`n") }
    }

    function New-PlanningFixture([string]$Name) {
        $fixtureRoot = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
        $currentManifest = Get-Content -LiteralPath (Join-Path $repoRoot $currentManifestRelative) -Raw | ConvertFrom-Json
        $historicalEvidence = @('phase0', 'phase1', 'phase2', 'phase3', 'phase4') | ForEach-Object {
            $manifest = Get-Content -LiteralPath (Join-Path $repoRoot ('tasks\skills-manager-vnext-{0}.tasks.json' -f $_)) -Raw | ConvertFrom-Json
            @($manifest.tasks | Where-Object status -eq 'done' | ForEach-Object write_set | Where-Object { $_ -like 'docs/change-evidence/*' -and $_ -notmatch '[*?<>]' })
        }
        $currentEvidence = @($currentManifest.tasks | Where-Object status -eq 'done' | ForEach-Object write_set | Where-Object { $_ -like 'docs/change-evidence/*' -and $_ -notmatch '[*?<>]' })
        foreach ($relativePath in @($requiredFiles) + @($historicalEvidence) + @($currentEvidence) | Sort-Object -Unique) {
            $source = Join-Path $repoRoot $relativePath
            $destination = Join-Path $fixtureRoot $relativePath
            New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
        return $fixtureRoot
    }

    function Get-FirstOpenTask([string]$FixtureRoot) {
        $manifestPath = Join-Path $FixtureRoot $currentManifestRelative
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        return @($manifest.tasks | Where-Object { [string]$_.status -ne 'done' } | Select-Object -First 1)
    }

    It 'accepts the current repository planning contract' {
        $result = Invoke-PlanningVerifier $repoRoot -External
        $parsed = $result.output | ConvertFrom-Json
        $result.exit_code | Should Be 0
        $parsed.pass | Should Be $true
        $parsed.finding_count | Should Be 0
        $parsed.task_count | Should Be 5
        $parsed.current_phase | Should Be $currentPhase
        $parsed.historical_mode | Should Be $false
    }

    It 'fails closed on duplicate task ids' {
        $fixtureRoot = New-PlanningFixture 'duplicate-task'; $path = Join-Path $fixtureRoot $currentManifestRelative
        $manifest = Get-Content $path -Raw | ConvertFrom-Json; $manifest.tasks = @($manifest.tasks) + @($manifest.tasks[0]); $manifest | ConvertTo-Json -Depth 100 | Set-Content $path -Encoding UTF8
        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq duplicate_task_id).Count | Should Be 1
    }

    It 'rejects redundant standalone full-suite verification' {
        $fixtureRoot = New-PlanningFixture 'redundant-full-suite'; $path = Join-Path $fixtureRoot $currentManifestRelative
        $manifest = Get-Content $path -Raw | ConvertFrom-Json
        $manifest.tasks[0].verification = @('tests/run.ps1', 'scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree')
        $manifest | ConvertTo-Json -Depth 100 | Set-Content $path -Encoding UTF8
        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq redundant_full_test_invocation).Count | Should Be 1
    }

    It 'fails closed on unknown dependencies' {
        $fixtureRoot = New-PlanningFixture 'unknown-dependency'; $path = Join-Path $fixtureRoot $currentManifestRelative
        $manifest = Get-Content $path -Raw | ConvertFrom-Json; $manifest.tasks[1].depends_on = @('SMV-P2-999'); $manifest | ConvertTo-Json -Depth 100 | Set-Content $path -Encoding UTF8
        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq unknown_task_dependency).Count | Should Be 1
    }

    It 'fails closed when todo coverage or completion status drifts' {
        $fixtureRoot = New-PlanningFixture 'todo-drift'; $todoPath = Join-Path $fixtureRoot 'tasks\todo.md'
        $tasks = @((Get-Content (Join-Path $fixtureRoot $currentManifestRelative) -Raw | ConvertFrom-Json).tasks)
        $coverageTaskId = [string]$tasks[1].id
        $statusTaskId = [string]$tasks[0].id
        $todo = (Get-Content $todoPath -Raw).Replace($coverageTaskId, 'SMV-P2-X99').Replace(('- [x] `{0}`' -f $statusTaskId), ('- [ ] `{0}`' -f $statusTaskId)); Set-Content $todoPath $todo -Encoding UTF8
        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq task_todo_coverage_mismatch).Count | Should BeGreaterThan 0
        @($parsed.findings | Where-Object code -eq task_todo_status_mismatch).Count | Should Be 1
    }

    It 'fails closed when a done task evidence file is missing' {
        $fixtureRoot = New-PlanningFixture 'missing-evidence'; $path = Join-Path $fixtureRoot $currentManifestRelative
        $manifest = Get-Content $path -Raw | ConvertFrom-Json
        $doneTask = @($manifest.tasks | Where-Object { [string]$_.status -eq 'done' -and @($_.write_set | Where-Object { $_ -like 'docs/change-evidence/*' -and $_ -notmatch '[*?<>]' }).Count -gt 0 } | Select-Object -Last 1)
        $doneTask | Should Not BeNullOrEmpty
        $evidencePath = @($doneTask.write_set | Where-Object { $_ -like 'docs/change-evidence/*' -and $_ -notmatch '[*?<>]' } | Select-Object -Last 1)
        Remove-Item -LiteralPath (Join-Path $fixtureRoot $evidencePath) -Force
        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq done_task_evidence_missing).Count | Should BeGreaterThan 0
    }

    It 'fails closed when plan and current manifest phases differ' {
        $fixtureRoot = New-PlanningFixture 'phase-mismatch'; $path = Join-Path $fixtureRoot $currentManifestRelative
        $manifest = Get-Content $path -Raw | ConvertFrom-Json; $manifest.current_phase = 'P1'; $manifest | ConvertTo-Json -Depth 100 | Set-Content $path -Encoding UTF8
        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq plan_manifest_phase_mismatch).Count | Should Be 1
    }

    It 'validates P0 through P4 through explicit historical routing' {
        foreach ($phase in @(0, 1, 2, 3, 4)) {
            $date = if ($phase -eq 0) { '2026-08-01' } else { '2026-08-02' }
            $result = Invoke-PlanningVerifier $repoRoot ('tasks/skills-manager-vnext-phase{0}.tasks.json' -f $phase) ('docs/superpowers/specs/{0}-capability-manager-vnext-phase-{1}-design.md' -f $date, $phase)
            $result.exit_code | Should Be 0
            ($result.output | ConvertFrom-Json).current_phase | Should Be ('P{0}' -f $phase)
        }
    }
}
