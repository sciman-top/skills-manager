[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$CorpusPath = 'config/capability-routing-golden.json',
    [string]$RouterPath = 'overrides/capability-router/scripts/route-capability.ps1',
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
foreach ($file in @($corpusFile, $routerFile, $manifestFile, $policyFile, $configFile)) { if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw ('Required routing file is missing: {0}' -f $file) } }
$corpus = Get-Content -LiteralPath $corpusFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$corpus.schema_version -ne 1 -or @($corpus.cases).Count -eq 0) { throw 'Routing corpus must use schema_version=1 and contain cases.' }

$findings = [Collections.Generic.List[object]]::new()
$passedCases = 0
function Add-Finding([string]$CaseId, [string]$Code, [string]$Message) {
    $findings.Add([pscustomobject]@{ case_id = $CaseId; code = $Code; message = $Message }) | Out-Null
}

foreach ($case in @($corpus.cases)) {
    $caseId = [string]$case.id
    if ([string]::IsNullOrWhiteSpace($caseId) -or [string]::IsNullOrWhiteSpace([string]$case.query)) { Add-Finding $caseId 'case_invalid' 'Case id and query are required.'; continue }
    $routerArgs = @{
        Query = [string]$case.query
        ManifestPath = $manifestFile
        PolicyPath = $policyFile
        ConfigPath = $configFile
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$case.snapshot_path)) { $routerArgs.CapabilitySnapshotPath = Resolve-RepoFile ([string]$case.snapshot_path) }
    # The router is a pure read-only script. Invoke it in-process so a golden
    # corpus does not pay for a fresh PowerShell startup for every case.
    $global:LASTEXITCODE = 0
    $raw = @(& $routerFile @routerArgs 2>&1)
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
    findings = @($findings.ToArray())
}
if ($Json) { $resultEnvelope | ConvertTo-Json -Depth 10 }
elseif ($resultEnvelope.pass) { Write-Host ('Capability routing verified: cases={0}, findings=0' -f $resultEnvelope.case_count) -ForegroundColor Green }
else { foreach ($finding in $findings) { Write-Host ('[{0}] {1}: {2}' -f $finding.code, $finding.case_id, $finding.message) -ForegroundColor Red } }
if (-not $resultEnvelope.pass) { exit 2 }
