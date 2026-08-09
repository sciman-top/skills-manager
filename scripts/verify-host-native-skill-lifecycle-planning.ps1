[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [switch]$Json,
    [switch]$NoExit
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RepoRoot)
$findings = @()

function Add-Finding([string]$Code, [string]$Path, [string]$Message) {
    $script:findings += [pscustomobject]@{ code = $Code; severity = 'error'; path = $Path; message = $Message }
}

function Read-Required([string]$RelativePath) {
    $path = Join-Path $root $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Finding 'missing_required_file' $RelativePath "Missing required P6 planning file: $RelativePath"
        return ''
    }
    return [IO.File]::ReadAllText($path)
}

function Require-Literal([string]$Text, [string]$Literal, [string]$Path, [string]$Code) {
    if ($Text.IndexOf($Literal, [StringComparison]::Ordinal) -lt 0) {
        Add-Finding $Code $Path "Required literal is missing: $Literal"
    }
}

function Require-TruthMarker([string]$Text, [string]$Name, [string]$Expected, [string]$Path) {
    $literal = '**{0}**: `{1}`' -f $Name, $Expected
    if ($Text.IndexOf($literal, [StringComparison]::Ordinal) -lt 0) {
        Add-Finding 'planning_truth_boundary_violation' $Path `
            "Planning evidence must keep $Name=$Expected; required marker is missing: $literal"
    }
}

$paths = [ordered]@{
    prd = 'docs/product/skills-manager-vnext-prd.md'
    architecture = 'docs/product/skills-manager-vnext-architecture.md'
    roadmap = 'docs/product/skills-manager-vnext-roadmap.md'
    spec = 'docs/superpowers/specs/2026-08-07-capability-manager-vnext-phase-6-design.md'
    implementation_plan = 'docs/superpowers/plans/2026-08-07-host-native-skill-lifecycle-reset.md'
    manifest = 'tasks/skills-manager-vnext-phase6.tasks.json'
    plan = 'tasks/plan.md'
    evidence = 'docs/change-evidence/20260807-host-native-skill-lifecycle-reset-planning.md'
    project_agents = 'AGENTS.md'
    router_skill = 'overrides/custom/capability-router/SKILL.md'
    router_metadata = 'overrides/custom/capability-router/agents/openai.yaml'
}

$content = @{}
foreach ($entry in $paths.GetEnumerator()) { $content[$entry.Key] = Read-Required $entry.Value }

$manifest = $null
try { if ($content.manifest) { $manifest = $content.manifest | ConvertFrom-Json } }
catch { Add-Finding 'manifest_parse_failed' $paths.manifest $_.Exception.Message }

if ($null -ne $manifest) {
    if ([string]$manifest.current_phase -ne 'P6') { Add-Finding 'current_phase_mismatch' $paths.manifest 'P6 manifest current_phase must be P6.' }
    $tasks = @($manifest.tasks)
    $allowedStatuses = @($manifest.allowed_statuses | ForEach-Object { [string]$_ })
    if ($tasks.Count -ne 12) { Add-Finding 'task_count_mismatch' $paths.manifest "P6 must declare exactly 12 tasks; found $($tasks.Count)." }
    $expected = 1..12 | ForEach-Object { 'SMV-P6-{0:d3}' -f $_ }
    foreach ($id in $expected) {
        $matches = @($tasks | Where-Object { [string]$_.id -eq $id })
        if ($matches.Count -ne 1) { Add-Finding 'task_identity_mismatch' $paths.manifest "Task must appear exactly once: $id" }
    }
    foreach ($task in $tasks) {
        if ($allowedStatuses -notcontains [string]$task.status) {
            Add-Finding 'unknown_task_status' "$($paths.manifest)#$($task.id)" "Unknown task status: $($task.status)"
        }
        foreach ($required in @('preconditions','write_set','implementation_steps','tests','verification','rollback','done_when','out_of_scope')) {
            if (@($task.$required).Count -eq 0) { Add-Finding 'empty_execution_contract' "$($paths.manifest)#$($task.id)" "Missing values: $required" }
        }
    }
}

Require-Literal $content.roadmap 'P6_ADMISSION_STATUS: admitted' $paths.roadmap 'p6_not_admitted'
Require-Literal $content.plan '**current_phase**: `P6`' $paths.plan 'plan_not_current_p6'
Require-Literal $content.spec 'HostCapabilitySnapshot' $paths.spec 'snapshot_contract_missing'
Require-Literal $content.spec 'enabled_total == kept_total' $paths.spec 'complete_projection_invariant_missing'
Require-Literal $content.architecture 'ADR-SMV-031' $paths.architecture 'native_ownership_decision_missing'
Require-Literal $content.architecture 'ADR-SMV-038' $paths.architecture 'strict_fallback_decision_missing'
Require-Literal $content.prd 'FR-HNS-013' $paths.prd 'p6_requirements_incomplete'
Require-Literal $content.implementation_plan 'SMV-P6-012' $paths.implementation_plan 'implementation_plan_incomplete'
Require-TruthMarker $content.evidence 'truth_level' 'planning_contract' $paths.evidence
Require-TruthMarker $content.evidence 'runtime_migration' 'not_started' $paths.evidence
Require-TruthMarker $content.evidence 'host_loaded' 'not_run' $paths.evidence
Require-TruthMarker $content.evidence 'live_accepted' 'not_run' $paths.evidence
Require-TruthMarker $content.evidence 'full_gate' 'not_passed' $paths.evidence

foreach ($pair in @(
    @{ Text = $content.spec; Path = $paths.spec },
    @{ Text = $content.architecture; Path = $paths.architecture },
    @{ Text = $content.prd; Path = $paths.prd }
)) {
    if ($pair.Text -match '(?i)(mandatory resident|default runtime)[^\r\n]{0,120}capability-router[^\r\n]{0,120}(required|primary|must)') {
        Add-Finding 'legacy_router_restored_as_primary' $pair.Path 'P6 must not restore capability-router as the default semantic entry.'
    }
    if ($pair.Text -match '(?i)profile[^\r\n]{0,100}(reachability boundary|semantic routing boundary)[^\r\n]{0,100}(remain|is required|must remain)') {
        Add-Finding 'profile_reachability_restored' $pair.Path 'P6 must not keep profile as a reachability or semantic routing boundary.'
    }
}

if ($content.project_agents -match '(?i)(?:every|每个)[^\r\n]{0,160}(?:non-trivial|非平凡)[^\r\n]{0,160}(?:(?:must|shall)[^\r\n]{0,40}(?:first|before)?|先)[^\r\n]{0,80}(?:execute|invoke|执行)?[^\r\n]{0,40}capability-router') {
    Add-Finding 'legacy_router_restored_as_primary' $paths.project_agents 'Project instructions must keep capability-router fallback-only under P6.'
}
if ($content.router_skill -match '(?i)(?:part of the normal start-of-task path[^\r\n]{0,80}not an optional fallback|start every non-trivial task|每个非平凡任务[^\r\n]{0,80}(?:必须|先执行))') {
    Add-Finding 'legacy_router_restored_as_primary' $paths.router_skill 'Router skill instructions must describe explicit fallback or policy validation, not mandatory task startup.'
}
if ($content.router_metadata -match '(?im)^\s*allow_implicit_invocation\s*:\s*true\s*$') {
    Add-Finding 'legacy_router_implicit_invocation_enabled' $paths.router_metadata 'Retired router fallback must not permit implicit invocation.'
}

$result = [ordered]@{
    schema_version = 1
    program_id = 'skills-manager-vnext'
    track = 'host_native_skill_lifecycle_reset'
    current_phase = 'P6'
    truth_level = 'planning_contract'
    pass = ($findings.Count -eq 0)
    task_count = if ($null -ne $manifest) { @($manifest.tasks).Count } else { 0 }
    finding_count = $findings.Count
    findings = @($findings)
}

if ($Json) { $result | ConvertTo-Json -Depth 8 }
else {
    foreach ($finding in $findings) { Write-Host "[$($finding.code)] $($finding.path): $($finding.message)" -ForegroundColor Red }
    if ($result.pass) { Write-Host "Host-native lifecycle planning contract passed: tasks=$($result.task_count)" -ForegroundColor Green }
    else { Write-Host "Host-native lifecycle planning contract failed: findings=$($findings.Count)" -ForegroundColor Red }
}

$exitCode = if ($result.pass) { 0 } else { 2 }
if ($NoExit) { $global:LASTEXITCODE = $exitCode; return }
exit $exitCode
