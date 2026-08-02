[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$DecisionPath = 'config/vnext-phase4-entry-gate.json',
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($RepoRoot)
$path = if ([System.IO.Path]::IsPathRooted($DecisionPath)) { [System.IO.Path]::GetFullPath($DecisionPath) } else { [System.IO.Path]::GetFullPath((Join-Path $root $DecisionPath)) }
$findings = New-Object System.Collections.Generic.List[object]

function Add-P4Finding([string]$Code, [string]$Path, [string]$Message) {
    $findings.Add([pscustomobject]@{ code = $Code; severity = 'error'; path = $Path; message = $Message }) | Out-Null
}

if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    Add-P4Finding 'p4_decision_missing' $DecisionPath 'P4 entry decision file is missing.'
    $decision = $null
}
else {
    try { $decision = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json }
    catch { Add-P4Finding 'p4_decision_parse_failed' $DecisionPath $_.Exception.Message; $decision = $null }
}

if ($null -ne $decision) {
    if ([int]$decision.schema_version -ne 1) { Add-P4Finding 'p4_schema_invalid' '$.schema_version' 'schema_version must be 1.' }
    if ([string]$decision.program_id -ne 'skills-manager-vnext' -or [string]$decision.phase -ne 'P4') { Add-P4Finding 'p4_identity_invalid' '$' 'program_id and phase must identify skills-manager-vnext P4.' }
    if ([string]$decision.decision -notin @('not_started', 'started')) { Add-P4Finding 'p4_decision_invalid' '$.decision' 'decision must be not_started or started.' }
    if ([string]$decision.status -notin @('deferred', 'in_progress')) { Add-P4Finding 'p4_status_invalid' '$.status' 'status must be deferred or in_progress.' }
    $evaluatedAt = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$decision.evaluated_at, [ref]$evaluatedAt)) { Add-P4Finding 'p4_evaluated_at_invalid' '$.evaluated_at' 'evaluated_at must be a parseable timestamp.' }

    $requiredGateIds = @('independent_product_evidence', 'repeated_adoption', 'explicit_scale_surface_and_audience', 'safety_and_operating_boundary')
    $gates = @($decision.gates)
    foreach ($id in $requiredGateIds) {
        $matches = @($gates | Where-Object { [string]$_.id -eq $id })
        if ($matches.Count -ne 1) { Add-P4Finding 'p4_gate_coverage_invalid' '$.gates' ('Required gate must appear exactly once: {0}' -f $id); continue }
        $gate = $matches[0]
        if (-not [bool]$gate.required) { Add-P4Finding 'p4_gate_not_required' ('$.gates.{0}' -f $id) 'All P4 entry gates are required.' }
        if ([string]$gate.state -notin @('met', 'not_met')) { Add-P4Finding 'p4_gate_state_invalid' ('$.gates.{0}.state' -f $id) 'Gate state must be met or not_met.' }
        foreach ($field in @('reason', 'recovery_condition')) { if ([string]::IsNullOrWhiteSpace([string]$gate.$field)) { Add-P4Finding 'p4_gate_explanation_missing' ('$.gates.{0}.{1}' -f $id, $field) 'Gate reason and recovery condition are required.' } }
        if (@($gate.evidence).Count -eq 0) { Add-P4Finding 'p4_gate_evidence_missing' ('$.gates.{0}.evidence' -f $id) 'Gate evidence must be non-empty.' }
        foreach ($evidencePath in @($gate.evidence)) {
            $evidenceText = [string]$evidencePath
            $evidenceFull = if ([System.IO.Path]::IsPathRooted($evidenceText)) { [System.IO.Path]::GetFullPath($evidenceText) } else { [System.IO.Path]::GetFullPath((Join-Path $root $evidenceText)) }
            if (-not $evidenceFull.StartsWith(($root.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $evidenceFull -PathType Leaf)) { Add-P4Finding 'p4_gate_evidence_invalid' ('$.gates.{0}.evidence' -f $id) ('Evidence must resolve to a repository file: {0}' -f $evidenceText) }
        }
    }
    $allMet = (@($gates | Where-Object { [bool]$_.required -and [string]$_.state -ne 'met' }).Count -eq 0)
    if ([bool]$decision.all_required_met -ne $allMet) { Add-P4Finding 'p4_all_required_mismatch' '$.all_required_met' 'all_required_met must equal the evaluated required gate states.' }

    $defaultP4Manifest = Join-Path $root 'tasks\skills-manager-vnext-phase4.tasks.json'
    if ([string]$decision.decision -eq 'started') {
        if (-not $allMet -or [string]$decision.status -ne 'in_progress') { Add-P4Finding 'p4_started_without_entry' '$.decision' 'P4 can start only when every required gate is met and status is in_progress.' }
        if ([string]::IsNullOrWhiteSpace([string]$decision.p4_manifest_path)) { Add-P4Finding 'p4_started_manifest_missing' '$.p4_manifest_path' 'Started P4 requires an explicit manifest path.' }
        else {
            $manifestFull = if ([System.IO.Path]::IsPathRooted([string]$decision.p4_manifest_path)) { [System.IO.Path]::GetFullPath([string]$decision.p4_manifest_path) } else { [System.IO.Path]::GetFullPath((Join-Path $root ([string]$decision.p4_manifest_path))) }
            if (-not $manifestFull.Equals($defaultP4Manifest, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $manifestFull -PathType Leaf)) { Add-P4Finding 'p4_started_manifest_invalid' '$.p4_manifest_path' 'Started P4 requires the repository Phase 4 task manifest.' }
        }
    }
    else {
        if ($allMet -or [string]$decision.status -ne 'deferred') { Add-P4Finding 'p4_deferred_inconsistent' '$.decision' 'not_started requires at least one unmet gate and deferred status.' }
        if (-not [string]::IsNullOrWhiteSpace([string]$decision.p4_manifest_path) -or (Test-Path -LiteralPath $defaultP4Manifest)) { Add-P4Finding 'p4_manifest_forbidden_while_deferred' '$.p4_manifest_path' 'Deferred P4 must not have a task manifest.' }
    }
}

$result = [pscustomobject][ordered]@{
    schema_version = 1
    program_id = 'skills-manager-vnext'
    phase = 'P4'
    pass = ($findings.Count -eq 0)
    decision = if ($null -eq $decision) { 'unknown' } else { [string]$decision.decision }
    status = if ($null -eq $decision) { 'unknown' } else { [string]$decision.status }
    all_required_met = if ($null -eq $decision) { $false } else { [bool]$decision.all_required_met }
    finding_count = $findings.Count
    findings = $findings.ToArray()
}

if ($Json) { $result | ConvertTo-Json -Depth 10 }
elseif ($result.pass) { Write-Host ('P4 entry decision verified: decision={0}, status={1}, all_required_met={2}' -f $result.decision, $result.status, $result.all_required_met) -ForegroundColor Green }
else { foreach ($finding in $findings) { Write-Host ('[{0}] {1}: {2}' -f $finding.code, $finding.path, $finding.message) -ForegroundColor Red } }
if (-not $result.pass) { exit 2 }
exit 0
