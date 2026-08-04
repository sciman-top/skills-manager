Describe 'Lean AI delivery maintenance planning contract' {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    $scriptPath = Join-Path $repoRoot 'scripts\verify-lean-ai-delivery-planning.ps1'
    $maintenanceManifestRelative = 'tasks\skills-manager-vnext-maintenance-design.tasks.json'
    $pilotRegistryRelative = 'tasks\skills-manager-vnext-lean-delivery-pilot.json'
    $maintenanceSpecRelative = 'docs\superpowers\specs\2026-08-03-lean-ai-delivery-maintenance-design.md'
    $maintenanceEvidenceRelative = 'docs\change-evidence\20260803-lean-ai-delivery-maintenance-design.md'
    $engineeredWorkflowEvidenceRelative = 'docs\change-evidence\20260805-engineered-agent-workflow-maintenance-design.md'
    $fixtureRequiredFiles = @(
        'docs\product\README.md',
        'docs\product\skills-manager-vnext-prd.md',
        'docs\product\skills-manager-vnext-architecture.md',
        'docs\product\skills-manager-vnext-roadmap.md',
        'tasks\plan.md',
        'tasks\todo.md',
        'AGENTS.md'
    )
    $maintenanceRequiredFiles = @(
        $maintenanceSpecRelative,
        $maintenanceManifestRelative,
        $pilotRegistryRelative,
        $maintenanceEvidenceRelative,
        $engineeredWorkflowEvidenceRelative
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

    function Save-LeanPilotRegistry([string]$FixtureRoot, $Registry) {
        $Registry | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $FixtureRoot $pilotRegistryRelative) -Encoding UTF8
    }

    function New-LeanPilotSample([int]$Number, [string]$Category) {
        return [pscustomobject]@{
            id = ('SMV-M1-{0:d3}' -f $Number)
            category = $Category
            task_reference = ('task://real/{0:d3}' -f $Number)
            source_type = 'real_task'
            synthetic = $false
            self_referential = $false
            status = 'observed'
            comparison_mode = 'descriptive_only'
            evidence_refs = @('git:0123456789abcdef')
            final_truth_level = 'repo_verified'
            user_acceptance_status = 'not_requested'
            observed_at = '2026-08-04T00:00:00Z'
            metrics = [pscustomobject]@{
                time_to_first_value_minutes = $null
                rework_slices = 0
                unexpected_human_interruptions = 0
                non_product_artifacts = 0
                focused_gate_seconds = $null
                full_gate_seconds = $null
            }
            observations = [pscustomobject]@{
                coordination_mode = 'single_agent'
                shared_write_set_policy = 'not_applicable'
                tool_dispositions = @()
                context_adapter = 'repo_native'
                skill_lifecycle_action = 'none'
            }
        }
    }

    function Set-BasePlanningVerifierStub([string]$FixtureRoot, [switch]$Fail) {
        $path = Join-Path $FixtureRoot 'scripts\verify-vnext-planning.ps1'
        New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
        $source = if ($Fail) {
@'
[CmdletBinding()]
param([string]$RepoRoot, [switch]$Json, [switch]$NoExit)
$result = [ordered]@{ pass = $false; finding_count = 1 }
if ($Json) { $result | ConvertTo-Json }
if ($NoExit) { $global:LASTEXITCODE = 2; return }
exit 2
'@
        }
        else {
@'
[CmdletBinding()]
param([string]$RepoRoot, [switch]$Json, [switch]$NoExit)
$result = [ordered]@{ pass = $true; finding_count = 0 }
if ($Json) { $result | ConvertTo-Json }
if ($NoExit) { $global:LASTEXITCODE = 0; return }
exit 0
'@
        }
        Set-Content -LiteralPath $path -Value $source -Encoding UTF8
    }

    function New-LeanPlanningFixture([string]$Name) {
        $fixtureRoot = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null

        foreach ($relativePath in @($fixtureRequiredFiles) + @($maintenanceRequiredFiles) | Sort-Object -Unique) {
            $source = Join-Path $repoRoot $relativePath
            $destination = Join-Path $fixtureRoot $relativePath
            New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
        Set-BasePlanningVerifierStub $fixtureRoot
        return $fixtureRoot
    }

    It 'accepts the current repository maintenance planning contract' {
        $result = Invoke-LeanPlanningVerifier $repoRoot -External
        $parsed = $result.output | ConvertFrom-Json
        $result.exit_code | Should Be 0
        $parsed.schema_version | Should Be 1
        $parsed.program_id | Should Be 'skills-manager-vnext'
        $parsed.track | Should Be 'maintenance_design'
        $parsed.base_phase | Should Be 'P5'
        $parsed.p6_admission_status | Should Be 'hold'
        $parsed.pass | Should Be $true
        $parsed.finding_count | Should Be 0
        $parsed.task_count | Should Be 8
        $parsed.done_count | Should Be 8
        $parsed.open_count | Should Be 0
        @($parsed.evidence_groups).Count | Should Be 2
        $parsed.pilot_status | Should Be 'collecting'
        $parsed.pilot_sample_target | Should Be 10
        $parsed.pilot_sample_count | Should Be 0
        $parsed.counted_pilot_sample_count | Should Be 0
        @($parsed.pilot_observation_dimensions).Count | Should Be 5
    }

    It 'fails closed when the maintenance spec manifest or evidence is missing' {
        foreach ($case in @(
            @{ name = 'missing-spec'; path = $maintenanceSpecRelative },
            @{ name = 'missing-manifest'; path = $maintenanceManifestRelative },
            @{ name = 'missing-pilot-registry'; path = $pilotRegistryRelative },
            @{ name = 'missing-evidence'; path = $maintenanceEvidenceRelative }
        )) {
            $fixtureRoot = New-LeanPlanningFixture $case.name
            Remove-Item -LiteralPath (Join-Path $fixtureRoot $case.path) -Force
            $parsed = (Invoke-LeanPlanningVerifier $fixtureRoot).output | ConvertFrom-Json
            $parsed.pass | Should Be $false
            @($parsed.findings | Where-Object code -eq 'missing_required_file').Count | Should BeGreaterThan 0
        }
    }

    It 'rejects pilot registry parse schema identity and status drift' {
        $parseRoot = New-LeanPlanningFixture 'pilot-parse'
        Set-Content -LiteralPath (Join-Path $parseRoot $pilotRegistryRelative) -Value '{not-json' -Encoding UTF8
        @(((Invoke-LeanPlanningVerifier $parseRoot).output | ConvertFrom-Json).findings | Where-Object code -eq 'pilot_registry_parse_failed').Count | Should Be 1

        foreach ($case in @(
            @{ name = 'pilot-schema'; property = 'schema_version'; value = 2; code = 'unsupported_pilot_registry_schema' },
            @{ name = 'pilot-track'; property = 'track'; value = 'agent_runtime'; code = 'unexpected_pilot_registry_identity' },
            @{ name = 'pilot-status'; property = 'pilot_status'; value = 'completed'; code = 'unsupported_pilot_status' }
        )) {
            $fixtureRoot = New-LeanPlanningFixture $case.name
            $registry = Get-Content -LiteralPath (Join-Path $fixtureRoot $pilotRegistryRelative) -Raw | ConvertFrom-Json
            $registry.($case.property) = $case.value
            Save-LeanPilotRegistry $fixtureRoot $registry
            $parsed = (Invoke-LeanPlanningVerifier $fixtureRoot).output | ConvertFrom-Json
            @($parsed.findings | Where-Object code -eq $case.code).Count | Should Be 1
        }
    }

    It 'rejects fake duplicate invalid and excess pilot samples' {
        $fixtureRoot = New-LeanPlanningFixture 'pilot-invalid-samples'
        $registry = Get-Content -LiteralPath (Join-Path $fixtureRoot $pilotRegistryRelative) -Raw | ConvertFrom-Json
        $categories = @($registry.required_categories)
        $samples = @(1..11 | ForEach-Object { New-LeanPilotSample $_ $categories[($_ - 1) % $categories.Count] })
        $samples[1].id = $samples[0].id
        $samples[2].category = 'invented_category'
        $samples[3].synthetic = $true
        $samples[4].self_referential = $true
        $registry.samples = $samples
        Save-LeanPilotRegistry $fixtureRoot $registry

        $parsed = (Invoke-LeanPlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq 'duplicate_pilot_sample_id').Count | Should Be 1
        @($parsed.findings | Where-Object code -eq 'unknown_pilot_sample_category').Count | Should Be 1
        @($parsed.findings | Where-Object code -eq 'non_real_pilot_sample').Count | Should Be 2
        @($parsed.findings | Where-Object code -eq 'pilot_sample_limit_exceeded').Count | Should Be 1
    }

    It 'fails closed when review-ready pilot count or category coverage is incomplete' {
        $countRoot = New-LeanPlanningFixture 'pilot-review-count'
        $registry = Get-Content -LiteralPath (Join-Path $countRoot $pilotRegistryRelative) -Raw | ConvertFrom-Json
        $registry.pilot_status = 'review_ready'
        $registry.samples = @(1..9 | ForEach-Object { New-LeanPilotSample $_ $registry.required_categories[$_ - 1] })
        Save-LeanPilotRegistry $countRoot $registry
        $specPath = Join-Path $countRoot $maintenanceSpecRelative
        Set-Content -LiteralPath $specPath -Value ((Get-Content -LiteralPath $specPath -Raw).Replace('PILOT_STATUS: collecting', 'PILOT_STATUS: review_ready')) -Encoding UTF8
        $countFindings = @(((Invoke-LeanPlanningVerifier $countRoot).output | ConvertFrom-Json).findings)
        @($countFindings | Where-Object code -eq 'pilot_review_sample_count_incomplete').Count | Should Be 1

        $coverageRoot = New-LeanPlanningFixture 'pilot-review-coverage'
        $registry = Get-Content -LiteralPath (Join-Path $coverageRoot $pilotRegistryRelative) -Raw | ConvertFrom-Json
        $registry.pilot_status = 'review_ready'
        $registry.samples = @(1..10 | ForEach-Object { New-LeanPilotSample $_ 'ambiguous_requirement' })
        Save-LeanPilotRegistry $coverageRoot $registry
        $specPath = Join-Path $coverageRoot $maintenanceSpecRelative
        Set-Content -LiteralPath $specPath -Value ((Get-Content -LiteralPath $specPath -Raw).Replace('PILOT_STATUS: collecting', 'PILOT_STATUS: review_ready')) -Encoding UTF8
        $coverageFindings = @(((Invoke-LeanPlanningVerifier $coverageRoot).output | ConvertFrom-Json).findings)
        @($coverageFindings | Where-Object code -eq 'pilot_review_category_coverage_incomplete').Count | Should Be 1
    }

    It 'keeps pilot metrics P6 runtime and live claims fail closed' {
        $fixtureRoot = New-LeanPlanningFixture 'pilot-truth-boundaries'
        $registry = Get-Content -LiteralPath (Join-Path $fixtureRoot $pilotRegistryRelative) -Raw | ConvertFrom-Json
        $registry.metrics_mode = 'completion_gate'
        $registry.metrics_completion_gate = $true
        $registry.p6_admission_status = 'admitted'
        $registry.runtime_implementation_status = 'runtime_implemented'
        $registry.live_acceptance_status = 'live_accepted'
        Save-LeanPilotRegistry $fixtureRoot $registry
        $findings = @(((Invoke-LeanPlanningVerifier $fixtureRoot).output | ConvertFrom-Json).findings)
        @($findings | Where-Object code -eq 'pilot_metrics_became_gate').Count | Should Be 1
        @($findings | Where-Object code -eq 'pilot_p6_admission_not_hold').Count | Should Be 1
        @($findings | Where-Object code -eq 'pilot_runtime_implementation_claimed').Count | Should Be 1
        @($findings | Where-Object code -eq 'pilot_live_acceptance_claimed').Count | Should Be 1
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

    It 'requires the exact M0 and M0.2 task set and stable evidence groups' {
        $missingTaskRoot = New-LeanPlanningFixture 'missing-m0-2-task'
        $manifest = Get-Content -LiteralPath (Join-Path $missingTaskRoot $maintenanceManifestRelative) -Raw | ConvertFrom-Json
        $manifest.tasks = @($manifest.tasks | Where-Object { $_.id -ne 'SMV-MD-008' })
        Save-LeanManifest $missingTaskRoot $manifest
        $missingTaskFindings = @(((Invoke-LeanPlanningVerifier $missingTaskRoot).output | ConvertFrom-Json).findings)
        @($missingTaskFindings | Where-Object code -eq 'missing_required_maintenance_task').Count | Should Be 1

        $evidenceGroupRoot = New-LeanPlanningFixture 'invalid-evidence-group'
        $manifest = Get-Content -LiteralPath (Join-Path $evidenceGroupRoot $maintenanceManifestRelative) -Raw | ConvertFrom-Json
        $manifest.tasks[4].evidence_group = 'Invalid Group'
        Save-LeanManifest $evidenceGroupRoot $manifest
        $evidenceGroupFindings = @(((Invoke-LeanPlanningVerifier $evidenceGroupRoot).output | ConvertFrom-Json).findings)
        @($evidenceGroupFindings | Where-Object code -eq 'invalid_task_evidence_group').Count | Should Be 1
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

    It 'requires the M0.2 evidence file independently from historical M0 evidence' {
        $fixtureRoot = New-LeanPlanningFixture 'm0-2-evidence-missing'
        Remove-Item -LiteralPath (Join-Path $fixtureRoot $engineeredWorkflowEvidenceRelative) -Force
        $parsed = (Invoke-LeanPlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq 'done_task_evidence_missing').Count | Should Be 1
    }

    It 'fails closed when engineered-workflow policy literals drift' {
        $fixtureRoot = New-LeanPlanningFixture 'm0-2-policy-drift'
        $specPath = Join-Path $fixtureRoot $maintenanceSpecRelative
        $spec = (Get-Content -LiteralPath $specPath -Raw).
            Replace('CONTROL_PLANE_STATUS: not_introduced', 'CONTROL_PLANE_STATUS: introduced').
            Replace('GIT_CAS_SEMANTICS: ref_freshness_not_file_queue', 'GIT_CAS_SEMANTICS: file_queue')
        Set-Content -LiteralPath $specPath -Value $spec -Encoding UTF8
        $architecturePath = Join-Path $fixtureRoot 'docs\product\skills-manager-vnext-architecture.md'
        $architecture = (Get-Content -LiteralPath $architecturePath -Raw).Replace(
            'Git CAS is not a file lock or task queue',
            'Git CAS queues file writers'
        )
        Set-Content -LiteralPath $architecturePath -Value $architecture -Encoding UTF8
        $findings = @(((Invoke-LeanPlanningVerifier $fixtureRoot).output | ConvertFrom-Json).findings)
        @($findings | Where-Object code -eq 'control_plane_status_missing').Count | Should Be 1
        @($findings | Where-Object code -eq 'git_cas_semantics_missing').Count | Should Be 1
        @($findings | Where-Object code -eq 'git_cas_negative_boundary_missing').Count | Should Be 1
    }

    It 'validates pilot observation dimensions and values' {
        $dimensionRoot = New-LeanPlanningFixture 'pilot-observation-dimensions'
        $registry = Get-Content -LiteralPath (Join-Path $dimensionRoot $pilotRegistryRelative) -Raw | ConvertFrom-Json
        $registry.observation_dimensions = @($registry.observation_dimensions | Where-Object { $_ -ne 'context_adapter' })
        Save-LeanPilotRegistry $dimensionRoot $registry
        $dimensionFindings = @(((Invoke-LeanPlanningVerifier $dimensionRoot).output | ConvertFrom-Json).findings)
        @($dimensionFindings | Where-Object code -eq 'pilot_observation_dimensions_drift').Count | Should Be 1

        $valueRoot = New-LeanPlanningFixture 'pilot-observation-values'
        $registry = Get-Content -LiteralPath (Join-Path $valueRoot $pilotRegistryRelative) -Raw | ConvertFrom-Json
        $sample = New-LeanPilotSample 1 $registry.required_categories[0]
        $sample.observations.coordination_mode = 'unbounded_swarm'
        $sample.observations.shared_write_set_policy = 'last_writer_wins'
        $sample.observations.tool_dispositions = @('install_everything')
        $sample.observations.context_adapter = 'authoritative_graph'
        $sample.observations.skill_lifecycle_action = 'auto_promote'
        $registry.samples = @($sample)
        Save-LeanPilotRegistry $valueRoot $registry
        $valueFindings = @(((Invoke-LeanPlanningVerifier $valueRoot).output | ConvertFrom-Json).findings)
        @($valueFindings | Where-Object code -eq 'unknown_pilot_coordination_mode').Count | Should Be 1
        @($valueFindings | Where-Object code -eq 'unknown_pilot_shared_write_policy').Count | Should Be 1
        @($valueFindings | Where-Object code -eq 'unknown_pilot_tool_disposition').Count | Should Be 1
        @($valueFindings | Where-Object code -eq 'unknown_pilot_context_adapter').Count | Should Be 1
        @($valueFindings | Where-Object code -eq 'unknown_pilot_skill_lifecycle_action').Count | Should Be 1
    }

    It 'blocks a P6 manifest while admission is on hold' {
        $fixtureRoot = New-LeanPlanningFixture 'p6-manifest'
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'tasks\skills-manager-vnext-phase6.tasks.json') -Value '{"schema_version":1}' -Encoding UTF8
        $parsed = (Invoke-LeanPlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq 'p6_manifest_created_while_on_hold').Count | Should Be 1
    }

    It 'rejects spec pilot status drift or maintenance live acceptance claims' {
        $fixtureRoot = New-LeanPlanningFixture 'pilot-live-claims'
        $specPath = Join-Path $fixtureRoot $maintenanceSpecRelative
        $spec = (Get-Content -LiteralPath $specPath -Raw).
            Replace('PILOT_STATUS: collecting', 'PILOT_STATUS: reviewed').
            Replace('LIVE_ACCEPTANCE_STATUS: not_run', 'LIVE_ACCEPTANCE_STATUS: live_accepted')
        Set-Content -LiteralPath $specPath -Value $spec -Encoding UTF8
        $findings = @(((Invoke-LeanPlanningVerifier $fixtureRoot).output | ConvertFrom-Json).findings)
        @($findings | Where-Object code -eq 'pilot_status_mismatch').Count | Should Be 1
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
        Set-BasePlanningVerifierStub $fixtureRoot -Fail
        $parsed = (Invoke-LeanPlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq 'base_p5_planning_failed').Count | Should Be 1
    }
}
