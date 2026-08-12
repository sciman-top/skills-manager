[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$CorpusPath = 'config/capability-routing-golden.json',
    [string]$RouterPath = 'overrides/capability-router/scripts/route-capability.ps1',
    [string]$HostSnapshotPath = '',
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RepoRoot)
function Resolve-RepoFile([string]$Path) {
    $full = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $root $Path)) }
    if (-not $full.StartsWith(($root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) { throw ('Path escapes repository root: {0}' -f $Path) }
    return $full
}

$corpusFile = if ([IO.Path]::IsPathRooted($CorpusPath)) { [IO.Path]::GetFullPath($CorpusPath) } else { Resolve-RepoFile $CorpusPath }
$routerFile = Resolve-RepoFile $RouterPath
$manifestFile = Resolve-RepoFile 'reports/skill-projection/current.json'
$policyFile = Resolve-RepoFile 'config/skill-routing-policy.json'
$configFile = Resolve-RepoFile 'skills.json'
foreach ($file in @($corpusFile, $routerFile, $policyFile, $configFile)) { if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw ('Required routing file is missing: {0}' -f $file) } }
$manifestAvailable = Test-Path -LiteralPath $manifestFile -PathType Leaf
$corpus = Get-Content -LiteralPath $corpusFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$corpus.schema_version -ne 1 -or @($corpus.cases).Count -eq 0) { throw 'Routing corpus must use schema_version=1 and contain cases.' }

$findings = [Collections.Generic.List[object]]::new()
$passedCases = 0
$dynamicAudit = [ordered]@{ performed = $false; snapshot_count = 0; routed_count = 0; missing_count = 0; selection_probe_count = 0; selection_probe_passed_count = 0; selection_probe_missing_count = 0; selection_probe_shadowed_count = 0; tool_count = 0; unsafe_tool_gate_violation_count = 0; annotation_policy_violation_count = 0; protocol_annotation_count = 0; protocol_default_count = 0 }
function Add-Finding([string]$CaseId, [string]$Code, [string]$Message) {
    $findings.Add([pscustomobject]@{ case_id = $CaseId; code = $Code; message = $Message }) | Out-Null
}

foreach ($case in @($corpus.cases)) {
    $caseId = [string]$case.id
    if ([string]::IsNullOrWhiteSpace($caseId) -or [string]::IsNullOrWhiteSpace([string]$case.query)) { Add-Finding $caseId 'case_invalid' 'Case id and query are required.'; continue }
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $routerFile, '-Query', [string]$case.query, '-PolicyPath', $policyFile, '-ConfigPath', $configFile)
    if ($manifestAvailable) { $args += @('-ManifestPath', $manifestFile) }
    if (-not [string]::IsNullOrWhiteSpace([string]$case.snapshot_path)) { $args += @('-CapabilitySnapshotPath', (Resolve-RepoFile ([string]$case.snapshot_path))) }
    $raw = @(& pwsh @args 2>&1)
    if ($LASTEXITCODE -ne 0) { Add-Finding $caseId 'router_failed' ($raw -join "`n"); continue }
    try { $result = ($raw -join "`n") | ConvertFrom-Json }
    catch { Add-Finding $caseId 'router_output_invalid' $_.Exception.Message; continue }
    $before = $findings.Count
    if ([int]$result.schema_version -ne 3) { Add-Finding $caseId 'schema_mismatch' 'Router must emit schema_version=3.' }
    if ($null -ne $case.expected_task) {
        foreach ($field in @('task_type', 'domain', 'goal')) {
            $expectedValue = [string]$case.expected_task.$field
            if (-not [string]::IsNullOrWhiteSpace($expectedValue) -and [string]$result.task_model.$field -ne $expectedValue) {
                Add-Finding $caseId 'task_model_mismatch' ('Expected {0}={1}, actual={2}.' -f $field, $expectedValue, [string]$result.task_model.$field)
            }
        }
    }
    if ([bool]$result.writes_performed) { Add-Finding $caseId 'unexpected_write' 'Router reported a write.' }
    if ([bool]$case.expect_abstain -ne [bool]$result.abstained) { Add-Finding $caseId 'abstain_mismatch' ('Expected abstain={0}, actual={1}.' -f [bool]$case.expect_abstain, [bool]$result.abstained) }
    foreach ($expected in @($case.expected)) {
        $selected = @($result.selected | Where-Object { [string]$_.kind -eq [string]$expected.kind -and [string]$_.name -eq [string]$expected.name })
        if ($selected.Count -ne 1) { Add-Finding $caseId 'expected_selection_missing' ('Missing {0}/{1}.' -f [string]$expected.kind, [string]$expected.name); continue }
        if (-not [string]::IsNullOrWhiteSpace([string]$expected.action)) {
            $plan = @($result.activation_plan | Where-Object { [string]$_.kind -eq [string]$expected.kind -and [string]$_.name -eq [string]$expected.name -and [string]$_.action -eq [string]$expected.action })
            if ($plan.Count -ne 1) { Add-Finding $caseId 'expected_action_missing' ('Missing action {0} for {1}/{2}.' -f [string]$expected.action, [string]$expected.kind, [string]$expected.name) }
        }
    }
    foreach ($forbidden in @($case.forbidden)) {
        if (@($result.selected | Where-Object { [string]$_.kind -eq [string]$forbidden.kind -and [string]$_.name -eq [string]$forbidden.name }).Count -gt 0) { Add-Finding $caseId 'forbidden_selection' ('Selected forbidden {0}/{1}.' -f [string]$forbidden.kind, [string]$forbidden.name) }
    }
    foreach ($plan in @($result.activation_plan)) {
        if ([bool]$plan.auto_allowed -and [string]$plan.side_effect -notin @('read_only', 'external_read')) { Add-Finding $caseId 'side_effect_violation' ('Auto-allowed {0}/{1} with side_effect={2}.' -f [string]$plan.kind, [string]$plan.name, [string]$plan.side_effect) }
    }
    if ($findings.Count -eq $before) { $passedCases++ }
}

if (-not [string]::IsNullOrWhiteSpace($HostSnapshotPath)) {
    $snapshotFile = if ([IO.Path]::IsPathRooted($HostSnapshotPath)) { [IO.Path]::GetFullPath($HostSnapshotPath) } else { Resolve-RepoFile $HostSnapshotPath }
    if (-not (Test-Path -LiteralPath $snapshotFile -PathType Leaf)) { throw ('Host snapshot is missing: {0}' -f $snapshotFile) }
    $snapshot = Get-Content -LiteralPath $snapshotFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $snapshotItems = @($snapshot.capabilities)
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $routerFile, '-Query', 'dynamic host capability inventory coverage audit', '-PolicyPath', $policyFile, '-ConfigPath', $configFile, '-HostSnapshotPath', $snapshotFile)
    if ($manifestAvailable) { $args += @('-ManifestPath', $manifestFile) }
    $raw = @(& pwsh @args 2>&1)
    if ($LASTEXITCODE -ne 0) { Add-Finding 'dynamic-host-audit' 'router_failed' ($raw -join "`n") }
    else {
        try { $routed = ($raw -join "`n") | ConvertFrom-Json }
        catch { Add-Finding 'dynamic-host-audit' 'router_output_invalid' $_.Exception.Message; $routed = $null }
        if ($null -ne $routed) {
            foreach ($capability in $snapshotItems) {
                $matches = @($routed.inventory | Where-Object { [string]$_.kind -eq [string]$capability.kind -and [string]$_.name -eq [string]$capability.name })
                if ($matches.Count -ne 1) { Add-Finding 'dynamic-host-audit' 'snapshot_capability_missing' ('Missing {0}/{1} from unified inventory.' -f [string]$capability.kind, [string]$capability.name); continue }
                $descriptor = $matches[0]
                if ([string]$capability.availability -and [string]$descriptor.availability -ne [string]$capability.availability -and -not ([string]$capability.availability -eq 'available' -and [string]$descriptor.availability -eq 'not_callable')) {
                    Add-Finding 'dynamic-host-audit' 'runtime_truth_drift' ('Availability drift for {0}/{1}: snapshot={2}, routed={3}.' -f [string]$capability.kind, [string]$capability.name, [string]$capability.availability, [string]$descriptor.availability)
                }
                foreach ($tool in @($descriptor.tools)) {
                    $dynamicAudit.tool_count++
                    $effect = [string]$tool.side_effect
                    $approval = [string]$tool.approval
                    $classification = [string]$tool.classification
                    if ($classification -eq 'protocol_annotation') { $dynamicAudit.protocol_annotation_count++ }
                    elseif ($classification -eq 'protocol_default') { $dynamicAudit.protocol_default_count++ }
                    if ($classification -in @('protocol_annotation', 'protocol_default') -and $tool.read_only_hint -eq $false -and $effect -in @('read_only', 'external_read')) {
                        $dynamicAudit.annotation_policy_violation_count++
                        Add-Finding 'dynamic-host-audit' 'annotation_policy_violation' ('Non-read-only protocol tool {0}/{1}/{2} was classified as {3}.' -f [string]$descriptor.kind, [string]$descriptor.name, [string]$tool.name, $effect)
                    }
                    if ($effect -in @('read_only', 'external_read')) {
                        if ($approval -ne 'none') { Add-Finding 'dynamic-host-audit' 'safe_tool_policy_drift' ('Safe tool {0}/{1}/{2} has approval={3}.' -f [string]$descriptor.kind, [string]$descriptor.name, [string]$tool.name, $approval) }
                    }
                    elseif ($approval -eq 'none') {
                        $dynamicAudit.unsafe_tool_gate_violation_count++
                        Add-Finding 'dynamic-host-audit' 'unsafe_tool_gate_violation' ('Unsafe or unknown tool {0}/{1}/{2} is ungated.' -f [string]$descriptor.kind, [string]$descriptor.name, [string]$tool.name)
                    }
                }
            }
            $dynamicAudit.performed = $true
            $dynamicAudit.snapshot_count = $snapshotItems.Count
            $dynamicAudit.routed_count = @($snapshotItems | Where-Object { $item = $_; @($routed.inventory | Where-Object { [string]$_.kind -eq [string]$item.kind -and [string]$_.name -eq [string]$item.name }).Count -eq 1 }).Count
            $dynamicAudit.missing_count = $dynamicAudit.snapshot_count - $dynamicAudit.routed_count
            foreach ($capability in $snapshotItems) {
                $probeName = [string]$capability.display_name
                if ([string]::IsNullOrWhiteSpace($probeName)) { $probeName = [string]$capability.runtime_name }
                if ([string]::IsNullOrWhiteSpace($probeName)) { $probeName = [string]$capability.name }
                $dynamicAudit.selection_probe_count++
                $probeArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $routerFile, '-Query', ('使用 {0} 能力' -f $probeName), '-PolicyPath', $policyFile, '-ConfigPath', $configFile, '-HostSnapshotPath', $snapshotFile)
                if ($manifestAvailable) { $probeArgs += @('-ManifestPath', $manifestFile) }
                $probeRaw = @(& pwsh @probeArgs 2>&1)
                if ($LASTEXITCODE -ne 0) {
                    $dynamicAudit.selection_probe_missing_count++
                    Add-Finding 'dynamic-host-audit' 'selection_probe_failed' ('Router failed while probing {0}/{1}: {2}' -f [string]$capability.kind, [string]$capability.name, ($probeRaw -join "`n"))
                    continue
                }
                try { $probe = ($probeRaw -join "`n") | ConvertFrom-Json }
                catch {
                    $dynamicAudit.selection_probe_missing_count++
                    Add-Finding 'dynamic-host-audit' 'selection_probe_invalid' ('Router output was invalid while probing {0}/{1}: {2}' -f [string]$capability.kind, [string]$capability.name, $_.Exception.Message)
                    continue
                }
                if (@($probe.selected | Where-Object { [string]$_.kind -eq [string]$capability.kind -and [string]$_.name -eq [string]$capability.name }).Count -gt 0) {
                    $dynamicAudit.selection_probe_passed_count++
                    continue
                }
                $sameNameSelections = @($probe.selected | Where-Object { [string]$_.name -eq [string]$capability.name })
                $sameNameInventory = @($snapshotItems | Where-Object { [string]$_.name -eq [string]$capability.name })
                if ($sameNameSelections.Count -gt 0 -and $sameNameInventory.Count -gt 1) {
                    $dynamicAudit.selection_probe_shadowed_count++
                    continue
                }
                $dynamicAudit.selection_probe_missing_count++
                Add-Finding 'dynamic-host-audit' 'snapshot_capability_unroutable' ('Explicit identity probe did not select {0}/{1} (display={2}).' -f [string]$capability.kind, [string]$capability.name, $probeName)
            }
        }
    }
}

$resultEnvelope = [ordered]@{
    schema_version = 1
    command = 'verify-capability-routing'
    pass = ($findings.Count -eq 0)
    case_count = @($corpus.cases).Count
    passed_case_count = $passedCases
    failed_case_count = @($corpus.cases).Count - $passedCases
    finding_count = $findings.Count
    side_effect_violation_count = @($findings | Where-Object code -eq 'side_effect_violation').Count
    writes_performed = $false
    dynamic_audit = $dynamicAudit
    findings = @($findings.ToArray())
}
if ($Json) { $resultEnvelope | ConvertTo-Json -Depth 10 }
elseif ($resultEnvelope.pass) { Write-Host ('Capability routing verified: cases={0}, findings=0' -f $resultEnvelope.case_count) -ForegroundColor Green }
else { foreach ($finding in $findings) { Write-Host ('[{0}] {1}: {2}' -f $finding.code, $finding.case_id, $finding.message) -ForegroundColor Red } }
if (-not $resultEnvelope.pass) { exit 2 }
