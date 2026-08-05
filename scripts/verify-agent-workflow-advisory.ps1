#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RepoRoot)
$findings = [System.Collections.Generic.List[object]]::new()

function Add-Finding([string]$Code, [string]$Path, [string]$Message) {
    $findings.Add([pscustomobject][ordered]@{
        code = $Code
        severity = 'error'
        path = $Path
        message = $Message
    }) | Out-Null
}

function Read-Required([string]$RelativePath) {
    $path = Join-Path $root $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Finding 'required_file_missing' $RelativePath 'Required agent workflow advisory file is missing.'
        return ''
    }
    return Get-Content -LiteralPath $path -Raw
}

function Require-Literal([string]$Text, [string]$Literal, [string]$Path, [string]$Code) {
    if ([string]::IsNullOrWhiteSpace($Text) -or $Text.IndexOf($Literal, [StringComparison]::Ordinal) -lt 0) {
        Add-Finding $Code $Path ("Required literal is missing: {0}" -f $Literal)
    }
}

function Reject-Pattern([string]$Text, [string]$Pattern, [string]$Path, [string]$Code, [string]$Message) {
    if (-not [string]::IsNullOrWhiteSpace($Text) -and $Text -match $Pattern) {
        Add-Finding $Code $Path $Message
    }
}

$paths = [ordered]@{
    manifest = 'tasks/skills-manager-vnext-agent-workflow-advisory.tasks.json'
    spec = 'docs/superpowers/specs/2026-08-05-agent-workflow-advisory-runtime.md'
    evidence = 'docs/change-evidence/20260805-agent-workflow-advisory-runtime.md'
    prd = 'docs/product/skills-manager-vnext-prd.md'
    architecture = 'docs/product/skills-manager-vnext-architecture.md'
    roadmap = 'docs/product/skills-manager-vnext-roadmap.md'
    productIndex = 'docs/product/README.md'
    plan = 'tasks/plan.md'
    todo = 'tasks/todo.md'
    agents = 'AGENTS.md'
    readme = 'README.md'
    readmeEn = 'README.en.md'
    domain = 'src/Domain/AgentWorkflow.ps1'
    application = 'src/Application/ModelAndAgentPolicy.ps1'
    command = 'src/Commands/AgentWorkflow.ps1'
    main = 'src/Main.ps1'
    version = 'src/Version.ps1'
    build = 'build.ps1'
    quality = 'scripts/quality/run-local-quality-gates.ps1'
    contractTests = 'tests/Unit/AgentWorkflowContracts.Tests.ps1'
    validFixture = 'tests/fixtures/agent-workflow/valid-request.json'
    invalidFixture = 'tests/fixtures/agent-workflow/invalid-request.json'
}

$content = @{}
foreach ($key in @($paths.Keys)) { $content[$key] = Read-Required $paths[$key] }

$manifest = $null
if (-not [string]::IsNullOrWhiteSpace($content.manifest)) {
    try { $manifest = $content.manifest | ConvertFrom-Json }
    catch { Add-Finding 'manifest_parse_failed' $paths.manifest $_.Exception.Message }
}

$expectedTasks = @('SMV-AWA-001', 'SMV-AWA-002', 'SMV-AWA-003', 'SMV-AWA-004', 'SMV-AWA-005')
$doneCount = 0
$modelTierCount = 0
if ($null -ne $manifest) {
    if ([int]$manifest.schema_version -ne 1 -or [string]$manifest.program_id -ne 'skills-manager-vnext' -or [string]$manifest.track -ne 'agent_workflow_advisory_runtime' -or [string]$manifest.base_phase -ne 'P5') {
        Add-Finding 'manifest_identity_invalid' $paths.manifest 'Manifest identity must remain schema 1 / skills-manager-vnext / agent_workflow_advisory_runtime / P5.'
    }
    foreach ($boundary in @(
            @{ property='track_status'; value='repo_verified'; code='track_status_invalid' },
            @{ property='truth_boundary'; value='repo_advisory_only'; code='truth_boundary_invalid' },
            @{ property='decision_owner'; value='host_ai'; code='decision_owner_boundary_invalid' },
            @{ property='executor'; value='host_native_runtime'; code='executor_boundary_invalid' },
            @{ property='p6_admission_status'; value='hold'; code='p6_boundary_invalid' },
            @{ property='runtime_scheduler_status'; value='not_introduced'; code='runtime_scheduler_boundary_invalid' },
            @{ property='provider_call_status'; value='none'; code='provider_call_boundary_invalid' },
            @{ property='native_mutation_status'; value='none'; code='native_mutation_boundary_invalid' },
            @{ property='radar_fetch_status'; value='not_implemented'; code='radar_fetch_boundary_invalid' },
            @{ property='host_loaded_status'; value='host_evaluation_partial_pass'; code='host_loaded_boundary_invalid' },
            @{ property='host_orchestration_status'; value='native_spawn_observed'; code='host_orchestration_boundary_invalid' },
            @{ property='host_radar_refresh_status'; value='scheduled_run_pass'; code='host_radar_boundary_invalid' },
            @{ property='live_acceptance_status'; value='not_run'; code='live_acceptance_boundary_invalid' }
        )) {
        if ([string]$manifest.($boundary.property) -ne $boundary.value) {
            Add-Finding $boundary.code $paths.manifest ("{0} must remain {1}." -f $boundary.property, $boundary.value)
        }
    }

    $tasks = @($manifest.tasks)
    $actualTaskSet = @($tasks | ForEach-Object { [string]$_.id } | Sort-Object) -join ','
    $expectedTaskSet = @($expectedTasks | Sort-Object) -join ','
    if ($actualTaskSet -ne $expectedTaskSet) { Add-Finding 'task_set_invalid' $paths.manifest 'Manifest must contain exactly SMV-AWA-001 through SMV-AWA-005.' }
    $taskIds = @{}
    foreach ($task in $tasks) {
        $taskId = [string]$task.id
        if ($taskIds.ContainsKey($taskId)) { Add-Finding 'duplicate_task_id' $paths.manifest ("Duplicate task ID: {0}" -f $taskId) }
        else { $taskIds[$taskId] = $true }
        if ([string]$task.status -eq 'done') { $doneCount++ }
        else { Add-Finding 'task_not_done' $paths.manifest ("Task is not done: {0}" -f $taskId) }
        if ([string]$task.evidence_group -ne 'agent_workflow_advisory') { Add-Finding 'evidence_group_invalid' $paths.manifest ("Task evidence group drifted: {0}" -f $taskId) }
        foreach ($field in @('write_set', 'implementation_steps', 'verification', 'stop_conditions', 'rollback')) {
            if ($null -eq $task.$field -or @($task.$field).Count -eq 0) { Add-Finding 'task_execution_field_missing' $paths.manifest ("{0} requires non-empty {1}." -f $taskId, $field) }
        }
    }
    foreach ($task in $tasks) {
        foreach ($dependency in @($task.depends_on)) {
            if (-not $taskIds.ContainsKey([string]$dependency)) { Add-Finding 'unknown_task_dependency' $paths.manifest ("{0} depends on unknown task {1}." -f $task.id, $dependency) }
            elseif ([string]$dependency -eq [string]$task.id) { Add-Finding 'self_task_dependency' $paths.manifest ("{0} depends on itself." -f $task.id) }
        }
    }

    $expectedTiers = [ordered]@{
        sol_xhigh = 'gpt-5.6-sol|xhigh|soft_anchor'
        sol_medium = 'gpt-5.6-sol|medium|soft_anchor'
        terra_high = 'gpt-5.6-terra|high|user_preferred_soft_anchor'
        luna_max = 'gpt-5.6-luna|max|soft_anchor'
    }
    $tiers = @($manifest.model_tiers)
    $modelTierCount = $tiers.Count
    foreach ($tierName in @($expectedTiers.Keys)) {
        $matches = @($tiers | Where-Object { [string]$_.tier -eq $tierName })
        if ($matches.Count -ne 1) { Add-Finding 'model_tier_anchor_invalid' $paths.manifest ("Missing or duplicate model tier: {0}" -f $tierName); continue }
        $actual = '{0}|{1}|{2}' -f [string]$matches[0].model_family, [string]$matches[0].reasoning_effort, [string]$matches[0].mode
        if ($actual -ne $expectedTiers[$tierName]) { Add-Finding 'model_tier_anchor_invalid' $paths.manifest ("Model tier anchor drifted: {0}" -f $tierName) }
    }
    foreach ($tier in $tiers) {
        if ([string]$tier.tier -notin @($expectedTiers.Keys)) { Add-Finding 'model_tier_anchor_invalid' $paths.manifest ("Unknown model tier: {0}" -f [string]$tier.tier) }
    }
}

foreach ($required in @(
        @{ key='spec'; literal='**IMPLEMENTATION_STATUS**: `repo_advisory_only`'; code='implementation_boundary_missing' },
        @{ key='spec'; literal='**RUNTIME_SCHEDULER_STATUS**: `not_introduced`'; code='runtime_boundary_missing' },
        @{ key='spec'; literal='**RADAR_FETCH_STATUS**: `not_implemented`'; code='radar_boundary_missing' },
        @{ key='spec'; literal='**HOST_LOADED_STATUS**: `host_evaluation_partial_pass`'; code='host_boundary_missing' },
        @{ key='spec'; literal='**HOST_ORCHESTRATION_STATUS**: `native_spawn_observed`'; code='host_boundary_missing' },
        @{ key='spec'; literal='**HOST_RADAR_REFRESH_STATUS**: `scheduled_run_pass`'; code='host_boundary_missing' },
        @{ key='spec'; literal='**LIVE_ACCEPTANCE_STATUS**: `not_run`'; code='live_boundary_missing' },
        @{ key='prd'; literal='FR-EWF-018'; code='product_requirement_missing' },
        @{ key='architecture'; literal='ADR-SMV-029'; code='architecture_decision_missing' },
        @{ key='roadmap'; literal='agent_workflow_advisory_runtime'; code='roadmap_track_missing' },
        @{ key='productIndex'; literal='Agent workflow advisory runtime'; code='product_index_missing' },
        @{ key='plan'; literal='SMV-AWA-005'; code='plan_coverage_missing' },
        @{ key='todo'; literal='SMV-AWA-005'; code='todo_coverage_missing' },
        @{ key='agents'; literal='agent workflow advisory'; code='root_contract_missing' },
        @{ key='readme'; literal='agent-plan'; code='readme_command_missing' },
        @{ key='readmeEn'; literal='agent-plan'; code='readme_command_missing' },
        @{ key='evidence'; literal='Maximum claim: `repo_verified / repo_advisory_only`'; code='evidence_boundary_missing' },
        @{ key='quality'; literal="Invoke-QualityGate 'agent-workflow-advisory' { & .\scripts\verify-agent-workflow-advisory.ps1 }"; code='full_gate_integration_missing' }
    )) { Require-Literal $content[$required.key] $required.literal $paths[$required.key] $required.code }

foreach ($required in @(
        @{ key='domain'; literal='function New-AgentTaskGraph'; code='domain_contract_missing' },
        @{ key='domain'; literal='function Test-AgentTaskGraphContract'; code='domain_contract_missing' },
        @{ key='domain'; literal='function New-RadarSnapshot'; code='domain_contract_missing' },
        @{ key='domain'; literal='function Test-RadarSnapshotContract'; code='domain_contract_missing' },
        @{ key='domain'; literal='function New-AgentFailurePacket'; code='domain_contract_missing' },
        @{ key='domain'; literal='function Test-AgentFailurePacketContract'; code='domain_contract_missing' },
        @{ key='application'; literal='function Test-AgentParallelAdmission'; code='application_contract_missing' },
        @{ key='application'; literal='function New-AgentExecutionPlan'; code='application_contract_missing' },
        @{ key='application'; literal='function New-ModelPolicyProposal'; code='application_contract_missing' },
        @{ key='application'; literal='function Get-AgentEscalationDecision'; code='application_contract_missing' },
        @{ key='application'; literal='Test-AgentFailurePacketContract $FailurePacket'; code='failure_packet_gate_missing' },
        @{ key='application'; literal='if (-not $radarValidation.pass -and -not $hasLocal)'; code='stale_radar_fallback_missing' },
        @{ key='command'; literal='function Invoke-AgentPlanCommand'; code='cli_command_wiring_missing' },
        @{ key='command'; literal='function Invoke-AgentValidateCommand'; code='cli_command_wiring_missing' },
        @{ key='command'; literal="decision_owner = 'host_ai'"; code='host_decision_owner_missing' },
        @{ key='command'; literal='provider_calls = 0; native_mutations = 0; writes = 0'; code='zero_side_effect_contract_missing' },
        @{ key='version'; literal='"agent-plan"'; code='cli_command_wiring_missing' },
        @{ key='version'; literal='"agent-validate"'; code='cli_command_wiring_missing' },
        @{ key='main'; literal='"agent-plan" { $result = Invoke-AgentPlanCommand'; code='cli_command_wiring_missing' },
        @{ key='main'; literal='"agent-validate" { $result = Invoke-AgentValidateCommand'; code='cli_command_wiring_missing' },
        @{ key='build'; literal='"Domain/AgentWorkflow.ps1"'; code='build_source_wiring_missing' },
        @{ key='build'; literal='"Application/ModelAndAgentPolicy.ps1"'; code='build_source_wiring_missing' },
        @{ key='build'; literal='"Commands/AgentWorkflow.ps1"'; code='build_source_wiring_missing' },
        @{ key='contractTests'; literal="Describe 'Agent workflow advisory contracts'"; code='focused_test_missing' },
        @{ key='validFixture'; literal='"graph_id": "graph-demo-001"'; code='fixture_contract_missing' },
        @{ key='invalidFixture'; literal='"graph_id": "graph-invalid-001"'; code='fixture_contract_missing' }
    )) { Require-Literal $content[$required.key] $required.literal $paths[$required.key] $required.code }

$pureLayers = $content.domain + "`n" + $content.application
Reject-Pattern $pureLayers '(?im)^\s*(Get-Content|Set-Content|Add-Content|Remove-Item|Copy-Item|Move-Item|Test-Path|Resolve-Path|Get-Date|Write-Host|Write-Output|Start-Process|Invoke-WebRequest|Invoke-RestMethod|exit)\b' 'src/Domain/AgentWorkflow.ps1;src/Application/ModelAndAgentPolicy.ps1' 'pure_layer_side_effect_detected' 'Domain/application advisory code must remain free of IO, clock, network, terminal and process effects.'
Reject-Pattern $pureLayers '(?i)\$env:' 'src/Domain/AgentWorkflow.ps1;src/Application/ModelAndAgentPolicy.ps1' 'pure_layer_side_effect_detected' 'Domain/application advisory code must not read environment variables.'
$allRuntime = $content.domain + "`n" + $content.application + "`n" + $content.command
Reject-Pattern $allRuntime '(?i)spawn[_-]?agent|send_message_to_thread|model_provider\s*=|\.codex[/\\]config\.toml|Invoke-WebRequest|Invoke-RestMethod' 'src/Domain/AgentWorkflow.ps1;src/Application/ModelAndAgentPolicy.ps1;src/Commands/AgentWorkflow.ps1' 'forbidden_runtime_control_detected' 'Advisory code must not implement agent scheduling, provider/config mutation or Radar/network fetching.'

foreach ($fixtureKey in @('validFixture', 'invalidFixture')) {
    if (-not [string]::IsNullOrWhiteSpace($content[$fixtureKey])) {
        try { $null = $content[$fixtureKey] | ConvertFrom-Json }
        catch { Add-Finding 'fixture_parse_failed' $paths[$fixtureKey] $_.Exception.Message }
    }
}

$status = if ($findings.Count -eq 0) { 'pass' } else { 'fail' }
$result = [pscustomobject][ordered]@{
    schema_version = 1
    status = $status
    track = 'agent_workflow_advisory_runtime'
    truth_boundary = 'repo_advisory_only'
    tasks = $expectedTasks.Count
    done = $doneCount
    model_tiers = $modelTierCount
    decision_owner = 'host_ai'
    executor = 'host_native_runtime'
    provider_calls = 0
    native_mutations = 0
    writes = 0
    findings = @($findings.ToArray())
}

if ($Json) { $result | ConvertTo-Json -Depth 20 -Compress }
else {
    Write-Host ("Agent workflow advisory verifier: {0}; tasks={1}/{2}; tiers={3}; findings={4}; effects=0/0/0" -f $status, $doneCount, $expectedTasks.Count, $modelTierCount, $findings.Count)
    foreach ($finding in $findings) { Write-Host ("[{0}] {1}: {2}" -f $finding.code, $finding.path, $finding.message) }
}

if ($findings.Count -gt 0) { exit 1 }
