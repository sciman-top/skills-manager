[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RepoRoot)
$findings = [System.Collections.Generic.List[object]]::new()

function Add-Finding([string]$Code, [string]$Path, [string]$Message) {
    $findings.Add([pscustomobject][ordered]@{ code = $Code; severity = 'error'; path = $Path; message = $Message }) | Out-Null
}

function Read-Required([string]$RelativePath) {
    $path = Join-Path $root $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Finding 'required_file_missing' $RelativePath 'Required typed-core planning file is missing.'
        return ''
    }
    return Get-Content -LiteralPath $path -Raw
}

function Require-Literal([string]$Text, [string]$Literal, [string]$Path, [string]$Code) {
    if ([string]::IsNullOrWhiteSpace($Text) -or -not $Text.Contains($Literal, [System.StringComparison]::Ordinal)) {
        Add-Finding $Code $Path ("Required literal is missing: {0}" -f $Literal)
    }
}

$paths = [ordered]@{
    manifest = 'tasks/skills-manager-vnext-typed-core-pilot.tasks.json'
    spec = 'docs/superpowers/specs/2026-08-05-typed-core-operation-contract-shadow-poc.md'
    evidence = 'docs/change-evidence/20260805-typed-core-operation-contract-shadow-poc.md'
    prd = 'docs/product/skills-manager-vnext-prd.md'
    architecture = 'docs/product/skills-manager-vnext-architecture.md'
    roadmap = 'docs/product/skills-manager-vnext-roadmap.md'
    plan = 'tasks/plan.md'
    todo = 'tasks/todo.md'
    agents = 'AGENTS.md'
    project = 'typed-core/SkillsManager.TypedCore/SkillsManager.TypedCore.csproj'
    program = 'typed-core/SkillsManager.TypedCore/Program.cs'
    validator = 'typed-core/SkillsManager.TypedCore/OperationContractValidator.cs'
    shadow = 'scripts/verify-typed-core-shadow.ps1'
    test = 'tests/Unit/TypedCoreShadow.Tests.ps1'
    global = 'global.json'
    pilot = 'tasks/skills-manager-vnext-lean-delivery-pilot.json'
}

$content = @{}
foreach ($key in @($paths.Keys)) { $content[$key] = Read-Required $paths[$key] }

$manifest = $null
if (-not [string]::IsNullOrWhiteSpace($content.manifest)) {
    try { $manifest = $content.manifest | ConvertFrom-Json }
    catch { Add-Finding 'manifest_parse_failed' $paths.manifest $_.Exception.Message }
}

$expectedTaskIds = @('SMV-TC-001', 'SMV-TC-002', 'SMV-TC-003')
$doneCount = 0
if ($null -ne $manifest) {
    if ([int]$manifest.schema_version -ne 1 -or [string]$manifest.program_id -ne 'skills-manager-vnext' -or [string]$manifest.track -ne 'typed_core_shadow_poc' -or [string]$manifest.base_phase -ne 'P5') {
        Add-Finding 'manifest_identity_invalid' $paths.manifest 'Manifest identity must remain schema 1 / skills-manager-vnext / typed_core_shadow_poc / P5.'
    }
    foreach ($check in @(
        @{ property='track_status'; value='repo_verified'; code='track_status_invalid' },
        @{ property='tc0_status'; value='repo_verified'; code='tc0_status_invalid' },
        @{ property='tc1_status'; value='repo_verified'; code='tc1_status_invalid' },
        @{ property='tc2_status'; value='not_started'; code='tc2_status_invalid' },
        @{ property='tc3_status'; value='conditional'; code='tc3_status_invalid' },
        @{ property='powershell_runtime_status'; value='authoritative'; code='powershell_runtime_status_invalid' },
        @{ property='typed_core_mode'; value='shadow_only'; code='typed_core_mode_invalid' },
        @{ property='production_integration_status'; value='not_started'; code='production_integration_status_invalid' },
        @{ property='p6_admission_status'; value='hold'; code='p6_status_invalid' },
        @{ property='live_acceptance_status'; value='not_run'; code='live_status_invalid' },
        @{ property='seam'; value='operation_contract_validation_v1'; code='seam_invalid' }
    )) {
        if ([string]$manifest.($check.property) -ne $check.value) { Add-Finding $check.code $paths.manifest ("{0} must be {1}." -f $check.property, $check.value) }
    }
    if ([int]$manifest.protocol_version -ne 1) { Add-Finding 'protocol_version_invalid' $paths.manifest 'protocol_version must be 1.' }

    $tasks = @($manifest.tasks)
    $declaredIds = @($tasks | ForEach-Object { [string]$_.id })
    $declaredTaskSet = (($declaredIds | Sort-Object) -join ',')
    $expectedTaskSet = (($expectedTaskIds | Sort-Object) -join ',')
    if ($declaredTaskSet -ne $expectedTaskSet) {
        Add-Finding 'task_set_invalid' $paths.manifest 'Manifest must contain exactly SMV-TC-001 through SMV-TC-003.'
    }
    foreach ($task in $tasks) {
        if ([string]$task.status -eq 'done') { $doneCount++ } else { Add-Finding 'task_not_done' $paths.manifest ("Task is not done: {0}" -f [string]$task.id) }
        if ([string]$task.evidence_group -ne 'typed_core_operation_contract_tc0_tc1') { Add-Finding 'evidence_group_invalid' $paths.manifest ("Task evidence group drifted: {0}" -f [string]$task.id) }
        foreach ($writePath in @($task.write_set | ForEach-Object { [string]$_ })) {
            if ($writePath -match '(?i)^(src[\\/]|skills\.ps1$|skills\.json$|agent[\\/]|vendor[\\/]|reports[\\/]|[A-Za-z]:[\\/]|\.codex[\\/])') {
                Add-Finding 'forbidden_write_set' $paths.manifest ("Typed-core shadow task cannot write production/runtime/host path: {0}" -f $writePath)
            }
        }
    }
}

foreach ($required in @(
    @{ key='spec'; literal='TC1_STATUS**: `repo_verified`'; code='spec_tc1_status_missing' },
    @{ key='spec'; literal='POWERSHELL_RUNTIME_STATUS**: `authoritative`'; code='spec_powershell_status_missing' },
    @{ key='spec'; literal='PRODUCTION_INTEGRATION_STATUS**: `not_started`'; code='spec_production_boundary_missing' },
    @{ key='prd'; literal='FR-TEC-001'; code='prd_typed_core_requirement_missing' },
    @{ key='prd'; literal='NFR-TEC-002'; code='prd_typed_core_nfr_missing' },
    @{ key='architecture'; literal='ADR-SMV-028'; code='architecture_decision_missing' },
    @{ key='roadmap'; literal='| `TC1` | `repo_verified / shadow_only` |'; code='roadmap_tc1_status_missing' },
    @{ key='plan'; literal='typed_core_shadow_poc'; code='plan_track_missing' },
    @{ key='todo'; literal='SMV-TC-003'; code='todo_task_missing' },
    @{ key='agents'; literal='TC1 `shadow_only`'; code='agents_boundary_missing' },
    @{ key='evidence'; literal='TC2: `not_started`'; code='evidence_boundary_missing' }
)) { Require-Literal $content[$required.key] $required.literal $paths[$required.key] $required.code }

try {
    $global = $content.global | ConvertFrom-Json
    if ([string]$global.sdk.version -ne '10.0.302' -or [string]$global.sdk.rollForward -ne 'latestPatch' -or [bool]$global.sdk.allowPrerelease) {
        Add-Finding 'sdk_pin_invalid' $paths.global 'SDK pin must remain 10.0.302/latestPatch/non-prerelease.'
    }
}
catch { Add-Finding 'global_json_invalid' $paths.global $_.Exception.Message }

Require-Literal $content.project '<TargetFramework>net10.0</TargetFramework>' $paths.project 'target_framework_invalid'
Require-Literal $content.project '<TreatWarningsAsErrors>true</TreatWarningsAsErrors>' $paths.project 'warnings_policy_missing'
if ($content.project -match '<PackageReference\b') { Add-Finding 'package_reference_forbidden' $paths.project 'TC1 must remain package-free.' }
foreach ($literal in @('protocol_version', 'validate_plan', 'validate_receipt', 'InvalidRequestExitCode = 64', 'InternalErrorExitCode = 70')) {
    Require-Literal $content.program $literal $paths.program 'protocol_contract_missing'
}

$productionSource = @(Get-ChildItem -LiteralPath (Join-Path $root 'src') -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
if ($productionSource -match '(?i)typed-core|skills-manager-typed-core|verify-typed-core-shadow') {
    Add-Finding 'production_integration_detected' 'src/**/*.ps1' 'TC1 must not be referenced from production PowerShell source.'
}
if (Test-Path -LiteralPath (Join-Path $root 'tasks/skills-manager-vnext-phase6.tasks.json')) {
    Add-Finding 'p6_manifest_forbidden' 'tasks/skills-manager-vnext-phase6.tasks.json' 'P6 manifest is forbidden while admission is hold.'
}

try {
    $pilot = $content.pilot | ConvertFrom-Json
    if ([string]$pilot.pilot_status -ne 'collecting' -or @($pilot.samples).Count -ne 0) {
        Add-Finding 'm1_status_changed' $paths.pilot 'TC0/TC1 self-referential work must not count as an M1 sample.'
    }
}
catch { Add-Finding 'pilot_registry_invalid' $paths.pilot $_.Exception.Message }

$result = [pscustomobject][ordered]@{
    schema_version = 1
    status = if ($findings.Count -eq 0) { 'pass' } else { 'fail' }
    track = 'typed_core_shadow_poc'
    tasks = 3
    done = $doneCount
    tc0_status = if ($null -ne $manifest) { [string]$manifest.tc0_status } else { 'unknown' }
    tc1_status = if ($null -ne $manifest) { [string]$manifest.tc1_status } else { 'unknown' }
    tc2_status = if ($null -ne $manifest) { [string]$manifest.tc2_status } else { 'unknown' }
    powershell_runtime_status = if ($null -ne $manifest) { [string]$manifest.powershell_runtime_status } else { 'unknown' }
    writes_performed = 0
    findings = $findings.ToArray()
}

if ($Json) { $result | ConvertTo-Json -Depth 12 }
else {
    foreach ($finding in $findings) { Write-Host ("[{0}] {1}: {2}" -f $finding.code, $finding.path, $finding.message) }
    if ($findings.Count -eq 0) { Write-Host 'Typed-core pilot planning contract passed: tasks=3, done=3, TC1=shadow_only.' }
}
if ($findings.Count -gt 0) { exit 1 }
