Describe 'Lean AI delivery maintenance planning contract' {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    $scriptPath = Join-Path $repoRoot 'scripts\verify-lean-ai-delivery-planning.ps1'
    $maintenanceManifestRelative = 'tasks\skills-manager-vnext-maintenance-design.tasks.json'
    $maintenanceSpecRelative = 'docs\superpowers\specs\2026-08-03-lean-ai-delivery-maintenance-design.md'
    $maintenanceEvidenceRelative = 'docs\change-evidence\20260803-lean-ai-delivery-maintenance-design.md'
    $baseRequiredFiles = @(
        'docs\product\README.md',
        'docs\product\skills-manager-vnext-prd.md',
        'docs\product\skills-manager-vnext-architecture.md',
        'docs\product\skills-manager-vnext-roadmap.md',
        'docs\product\rule-governance-adoption-matrix.md',
        'docs\superpowers\specs\2026-08-01-capability-manager-vnext-phase-0-design.md',
        'docs\superpowers\specs\2026-08-02-capability-manager-vnext-phase-1-design.md',
        'docs\superpowers\specs\2026-08-02-capability-manager-vnext-phase-2-design.md',
        'docs\superpowers\specs\2026-08-02-capability-manager-vnext-phase-3-design.md',
        'docs\superpowers\specs\2026-08-02-capability-manager-vnext-phase-4-design.md',
        'docs\superpowers\specs\2026-08-03-capability-manager-vnext-phase-5-design.md',
        'tasks\skills-manager-vnext-phase0.tasks.json',
        'tasks\skills-manager-vnext-phase1.tasks.json',
        'tasks\skills-manager-vnext-phase2.tasks.json',
        'tasks\skills-manager-vnext-phase3.tasks.json',
        'tasks\skills-manager-vnext-phase4.tasks.json',
        'tasks\skills-manager-vnext-phase5.tasks.json',
        'tasks\plan.md',
        'tasks\todo.md',
        'config\vnext-phase4-entry-gate.json',
        'scripts\verify-vnext-planning.ps1',
        'AGENTS.md'
    )
    $maintenanceRequiredFiles = @(
        $maintenanceSpecRelative,
        $maintenanceManifestRelative,
        $maintenanceEvidenceRelative
    )

    function Invoke-LeanPlanningVerifier([string]$Root, [switch]$External) {
        $output = if ($External) {
            @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -RepoRoot $Root -Json 2>&1)
        }
        else {
            $global:LASTEXITCODE = 0
            @(& $scriptPath -RepoRoot $Root -Json -NoExit 2>&1)
        }
        return [pscustomobject]@{ exit_code = $LASTEXITCODE; output = ($output -join "`n") }
    }

    function Save-LeanManifest([string]$FixtureRoot, $Manifest) {
        $Manifest | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $FixtureRoot $maintenanceManifestRelative) -Encoding UTF8
    }

    function New-LeanPlanningFixture([string]$Name) {
        $fixtureRoot = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null

        $historicalEvidence = @(0, 1, 2, 3, 4, 5) | ForEach-Object {
            $manifest = Get-Content -LiteralPath (Join-Path $repoRoot ('tasks\skills-manager-vnext-phase{0}.tasks.json' -f $_)) -Raw | ConvertFrom-Json
            @($manifest.tasks | Where-Object status -eq 'done' | ForEach-Object write_set | Where-Object {
                $_ -like 'docs/change-evidence/*' -and $_ -notmatch '[*?<>]'
            })
        }

        foreach ($relativePath in @($baseRequiredFiles) + @($maintenanceRequiredFiles) + @($historicalEvidence) | Sort-Object -Unique) {
            $source = Join-Path $repoRoot $relativePath
            $destination = Join-Path $fixtureRoot $relativePath
            New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
        return $fixtureRoot
    }

    It 'accepts the current repository maintenance planning contract' {
        $result = Invoke-LeanPlanningVerifier $repoRoot -External
        $parsed = $result.output | ConvertFrom-Json
        $result.exit_code | Should Be 0
        $parsed.pass | Should Be $true
        $parsed.finding_count | Should Be 0
        $parsed.task_count | Should Be 4
        $parsed.done_count | Should Be 4
        $parsed.open_count | Should Be 0
    }

    It 'fails closed when the maintenance spec manifest or evidence is missing' {
        foreach ($case in @(
            @{ name = 'missing-spec'; path = $maintenanceSpecRelative },
            @{ name = 'missing-manifest'; path = $maintenanceManifestRelative },
            @{ name = 'missing-evidence'; path = $maintenanceEvidenceRelative }
        )) {
            $fixtureRoot = New-LeanPlanningFixture $case.name
            Remove-Item -LiteralPath (Join-Path $fixtureRoot $case.path) -Force
            $parsed = (Invoke-LeanPlanningVerifier $fixtureRoot).output | ConvertFrom-Json
            $parsed.pass | Should Be $false
            @($parsed.findings | Where-Object code -eq 'missing_required_file').Count | Should BeGreaterThan 0
        }
    }

    It 'rejects manifest parse schema track and base-phase drift' {
        $parseRoot = New-LeanPlanningFixture 'manifest-parse'
        Set-Content -LiteralPath (Join-Path $parseRoot $maintenanceManifestRelative) -Value '{not-json' -Encoding UTF8
        @(((Invoke-LeanPlanningVerifier $parseRoot).output | ConvertFrom-Json).findings | Where-Object code -eq 'manifest_parse_failed').Count | Should Be 1

        foreach ($case in @(
            @{ name = 'manifest-schema'; property = 'schema_version'; value = 2; code = 'unsupported_manifest_schema' },
            @{ name = 'manifest-track'; property = 'track'; value = 'P6'; code = 'unexpected_track' },
            @{ name = 'manifest-base'; property = 'base_phase'; value = 'P6'; code = 'unexpected_base_phase' },
            @{ name = 'manifest-admission'; property = 'p6_admission_status'; value = 'admitted'; code = 'unexpected_p6_admission_status' }
        )) {
            $fixtureRoot = New-LeanPlanningFixture $case.name
            $manifest = Get-Content -LiteralPath (Join-Path $fixtureRoot $maintenanceManifestRelative) -Raw | ConvertFrom-Json
            $manifest.($case.property) = $case.value
            Save-LeanManifest $fixtureRoot $manifest
            $parsed = (Invoke-LeanPlanningVerifier $fixtureRoot).output | ConvertFrom-Json
            @($parsed.findings | Where-Object code -eq $case.code).Count | Should Be 1
        }
    }

    It 'rejects duplicate and malformed task ids' {
        $duplicateRoot = New-LeanPlanningFixture 'duplicate-id'
        $manifest = Get-Content -LiteralPath (Join-Path $duplicateRoot $maintenanceManifestRelative) -Raw | ConvertFrom-Json
        $manifest.tasks = @($manifest.tasks) + @($manifest.tasks[0])
        Save-LeanManifest $duplicateRoot $manifest
        @(((Invoke-LeanPlanningVerifier $duplicateRoot).output | ConvertFrom-Json).findings | Where-Object code -eq 'duplicate_task_id').Count | Should Be 1

        $invalidRoot = New-LeanPlanningFixture 'invalid-id'
        $manifest = Get-Content -LiteralPath (Join-Path $invalidRoot $maintenanceManifestRelative) -Raw | ConvertFrom-Json
        $manifest.tasks[0].id = 'SMV-P6-001'
        Save-LeanManifest $invalidRoot $manifest
        @(((Invoke-LeanPlanningVerifier $invalidRoot).output | ConvertFrom-Json).findings | Where-Object code -eq 'invalid_task_id').Count | Should Be 1
    }

    It 'rejects unknown self and cyclic dependencies' {
        foreach ($case in @(
            @{ name = 'unknown-dependency'; dependency = @('SMV-MD-999'); code = 'unknown_task_dependency' },
            @{ name = 'self-dependency'; dependency = @('SMV-MD-001'); code = 'self_task_dependency' },
            @{ name = 'dependency-cycle'; dependency = @('SMV-MD-004'); code = 'task_dependency_cycle' }
        )) {
            $fixtureRoot = New-LeanPlanningFixture $case.name
            $manifest = Get-Content -LiteralPath (Join-Path $fixtureRoot $maintenanceManifestRelative) -Raw | ConvertFrom-Json
            $manifest.tasks[0].depends_on = $case.dependency
            Save-LeanManifest $fixtureRoot $manifest
            $parsed = (Invoke-LeanPlanningVerifier $fixtureRoot).output | ConvertFrom-Json
            @($parsed.findings | Where-Object code -eq $case.code).Count | Should BeGreaterThan 0
        }
    }

    It 'rejects missing PRD requirement and architecture decision references' {
        $fixtureRoot = New-LeanPlanningFixture 'unknown-references'
        $manifest = Get-Content -LiteralPath (Join-Path $fixtureRoot $maintenanceManifestRelative) -Raw | ConvertFrom-Json
        $manifest.tasks[0].requirement_ids = @('FR-LDL-999')
        $manifest.tasks[0].architecture_decision_ids = @('ADR-SMV-999')
        Save-LeanManifest $fixtureRoot $manifest
        $findings = @(((Invoke-LeanPlanningVerifier $fixtureRoot).output | ConvertFrom-Json).findings)
        @($findings | Where-Object code -eq 'unknown_requirement_reference').Count | Should Be 1
        @($findings | Where-Object code -eq 'unknown_architecture_decision_reference').Count | Should Be 1
    }

    It 'rejects spec plan and todo task coverage drift' {
        $fixtureRoot = New-LeanPlanningFixture 'coverage-drift'
        foreach ($relativePath in @($maintenanceSpecRelative, 'tasks\plan.md', 'tasks\todo.md')) {
            $path = Join-Path $fixtureRoot $relativePath
            Set-Content -LiteralPath $path -Value ((Get-Content -LiteralPath $path -Raw).Replace('SMV-MD-002', 'SMV-MD-X02')) -Encoding UTF8
        }
        $findings = @(((Invoke-LeanPlanningVerifier $fixtureRoot).output | ConvertFrom-Json).findings)
        @($findings | Where-Object code -eq 'task_spec_coverage_mismatch').Count | Should Be 1
        @($findings | Where-Object code -eq 'task_plan_coverage_mismatch').Count | Should Be 1
        @($findings | Where-Object code -eq 'task_todo_coverage_mismatch').Count | Should Be 1
    }

    It 'rejects todo completion status drift' {
        $fixtureRoot = New-LeanPlanningFixture 'todo-status'
        $todoPath = Join-Path $fixtureRoot 'tasks\todo.md'
        $todo = (Get-Content -LiteralPath $todoPath -Raw).Replace('- [x] `SMV-MD-003`', '- [ ] `SMV-MD-003`')
        Set-Content -LiteralPath $todoPath -Value $todo -Encoding UTF8
        $parsed = (Invoke-LeanPlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq 'task_todo_status_mismatch').Count | Should Be 1
    }

    It 'rejects runtime generated report and host paths in the maintenance write set' {
        $fixtureRoot = New-LeanPlanningFixture 'runtime-write-set'
        $manifest = Get-Content -LiteralPath (Join-Path $fixtureRoot $maintenanceManifestRelative) -Raw | ConvertFrom-Json
        $manifest.tasks[0].write_set = @($manifest.tasks[0].write_set) + @('src/NewRuntime.ps1', 'reports/runtime.json', 'C:/Users/example/.codex/config.toml')
        Save-LeanManifest $fixtureRoot $manifest
        $parsed = (Invoke-LeanPlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq 'forbidden_maintenance_write_set').Count | Should Be 3
    }

    It 'rejects a missing shared evidence file for done tasks' {
        $fixtureRoot = New-LeanPlanningFixture 'done-evidence-missing'
        Remove-Item -LiteralPath (Join-Path $fixtureRoot $maintenanceEvidenceRelative) -Force
        $parsed = (Invoke-LeanPlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq 'done_task_evidence_missing').Count | Should Be 1
    }

    It 'blocks a P6 manifest while admission is on hold' {
        $fixtureRoot = New-LeanPlanningFixture 'p6-manifest'
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'tasks\skills-manager-vnext-phase6.tasks.json') -Value '{"schema_version":1}' -Encoding UTF8
        $parsed = (Invoke-LeanPlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq 'p6_manifest_created_while_on_hold').Count | Should Be 1
    }

    It 'rejects claims that the pilot ran or maintenance reached live acceptance' {
        $fixtureRoot = New-LeanPlanningFixture 'pilot-live-claims'
        $specPath = Join-Path $fixtureRoot $maintenanceSpecRelative
        $spec = (Get-Content -LiteralPath $specPath -Raw).
            Replace('PILOT_STATUS: pilot_not_executed', 'PILOT_STATUS: pilot_executed').
            Replace('LIVE_ACCEPTANCE_STATUS: not_run', 'LIVE_ACCEPTANCE_STATUS: live_accepted')
        Set-Content -LiteralPath $specPath -Value $spec -Encoding UTF8
        $findings = @(((Invoke-LeanPlanningVerifier $fixtureRoot).output | ConvertFrom-Json).findings)
        @($findings | Where-Object code -eq 'pilot_status_not_unexecuted').Count | Should Be 1
        @($findings | Where-Object code -eq 'live_acceptance_claimed').Count | Should Be 1
    }

    It 'rejects observe-only delivery metrics promoted to a completion gate' {
        $fixtureRoot = New-LeanPlanningFixture 'metrics-hard-gate'
        $specPath = Join-Path $fixtureRoot $maintenanceSpecRelative
        $spec = (Get-Content -LiteralPath $specPath -Raw).Replace('METRICS_COMPLETION_GATE: false', 'METRICS_COMPLETION_GATE: true')
        Set-Content -LiteralPath $specPath -Value $spec -Encoding UTF8
        $parsed = (Invoke-LeanPlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq 'observe_only_metrics_became_gate').Count | Should Be 1
    }

    It 'rejects duplicate standalone full-suite and full-gate declarations' {
        $fixtureRoot = New-LeanPlanningFixture 'duplicate-full-suite'
        $manifest = Get-Content -LiteralPath (Join-Path $fixtureRoot $maintenanceManifestRelative) -Raw | ConvertFrom-Json
        $manifest.tasks[3].verification = @('tests/run.ps1', 'scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree')
        Save-LeanManifest $fixtureRoot $manifest
        $specPath = Join-Path $fixtureRoot $maintenanceSpecRelative
        $verificationMarker = '`VERIFICATION_DECLARATION_START`'
        $duplicateDeclaration = $verificationMarker + [Environment]::NewLine + '`tests/run.ps1`'
        $spec = (Get-Content -LiteralPath $specPath -Raw).Replace($verificationMarker, $duplicateDeclaration)
        Set-Content -LiteralPath $specPath -Value $spec -Encoding UTF8
        $findings = @(((Invoke-LeanPlanningVerifier $fixtureRoot).output | ConvertFrom-Json).findings)
        @($findings | Where-Object code -eq 'redundant_full_test_invocation').Count | Should Be 1
        @($findings | Where-Object code -eq 'redundant_full_test_spec').Count | Should Be 1
    }

    It 'propagates a failure from the existing P5 planning verifier' {
        $fixtureRoot = New-LeanPlanningFixture 'base-p5-failure'
        Remove-Item -LiteralPath (Join-Path $fixtureRoot 'config\vnext-phase4-entry-gate.json') -Force
        $parsed = (Invoke-LeanPlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq 'base_p5_planning_failed').Count | Should Be 1
    }

    It 'keeps JSON fields counts and process exit code stable' {
        $result = Invoke-LeanPlanningVerifier $repoRoot -External
        $parsed = $result.output | ConvertFrom-Json
        $result.exit_code | Should Be 0
        $parsed.schema_version | Should Be 1
        $parsed.program_id | Should Be 'skills-manager-vnext'
        $parsed.track | Should Be 'maintenance_design'
        $parsed.base_phase | Should Be 'P5'
        $parsed.p6_admission_status | Should Be 'hold'
        $parsed.task_count | Should Be 4
        $parsed.done_count | Should Be 4
        $parsed.open_count | Should Be 0
    }
}
