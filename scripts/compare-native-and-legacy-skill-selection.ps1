[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$CorpusPath = 'config/native-skill-activation-corpus.json',
    [Parameter(Mandatory = $true)][string]$NativeResultsPath,
    [Parameter(Mandatory = $true)][string]$LegacyResultsPath,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RepoRoot)
$findings = [Collections.Generic.List[object]]::new()

$operationPlanPath = Join-Path $root 'src\Domain\OperationPlan.ps1'
if ((Test-Path -LiteralPath $operationPlanPath -PathType Leaf) -and $null -eq (Get-Command Get-OperationObjectProperty -ErrorAction SilentlyContinue)) { . $operationPlanPath }
$tracePath = Join-Path $root 'src\Domain\NativeInvocationTrace.ps1'
if ((Test-Path -LiteralPath $tracePath -PathType Leaf) -and $null -eq (Get-Command Test-NativeInvocationTraceContract -ErrorAction SilentlyContinue)) { . $tracePath }

function Add-ShadowFinding {
    param([string]$Code, [string]$Severity, [string]$Path, [string]$Message)
    $findings.Add([pscustomobject][ordered]@{ code = $Code; severity = $Severity; path = $Path; message = $Message }) | Out-Null
}

function Resolve-ShadowInput([string]$Path) {
    $full = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $root $Path)) }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw ('Input file is missing: {0}' -f $Path) }
    return $full
}

function Read-ShadowJson([string]$Path, [string]$Label) {
    try { return Get-Content -LiteralPath (Resolve-ShadowInput $Path) -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { Add-ShadowFinding ('{0}_invalid' -f $Label) 'error' $Path $_.Exception.Message; return $null }
}

function Get-ShadowProperty($Object, [string[]]$Names) {
    foreach ($name in @($Names)) {
        if ($null -eq $Object) { continue }
        if (Get-Command Get-OperationObjectProperty -ErrorAction SilentlyContinue) {
            if (Test-OperationObjectProperty $Object $name) { return Get-OperationObjectProperty $Object $name }
        }
        elseif ($null -ne ($Object.PSObject.Properties | Where-Object Name -eq $name | Select-Object -First 1)) { return $Object.$name }
    }
    return $null
}

function Get-ShadowStringArray($Value) {
    return [string[]]@($Value | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
}

function Get-ShadowNullableNumber($Value) {
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    $number = 0.0
    if ([double]::TryParse([string]$Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -and $number -ge 0) { return $number }
    return $null
}

function Get-ShadowTraceFacts($Trace, $Case, [string]$Side) {
    if ($null -eq $Trace) {
        return [pscustomobject][ordered]@{ present = $false; truth_level = 'host_evaluation_partial'; selection_observable = $false; body_injection_observable = $false; invocation_observable = $false; evaluated = $false; ttfv_ms = Get-ShadowNullableNumber (Get-ShadowProperty $Case @('ttfv_ms', 'time_to_first_value_ms')); tool_rounds = Get-ShadowNullableNumber (Get-ShadowProperty $Case @('tool_rounds')); }
    }
    $stages = Get-ShadowProperty $Trace @('stages')
    $selectedStage = Get-ShadowProperty $stages @('selected')
    $injectedStage = Get-ShadowProperty $stages @('injected')
    $executedStage = Get-ShadowProperty $stages @('executed')
    $truth = [string](Get-ShadowProperty $Trace @('truth_level'))
    if ([string]::IsNullOrWhiteSpace($truth)) { $truth = 'host_evaluation_partial' }
    $selectionObservableValue = Get-ShadowProperty $Trace @('selection_observable')
    $selectionObservable = if ($selectionObservableValue -is [bool]) { [bool]$selectionObservableValue } elseif ($null -ne $selectedStage -and (Get-ShadowProperty $selectedStage @('observed')) -is [bool]) { [bool](Get-ShadowProperty $selectedStage @('observed')) } else { $false }
    $bodyObservableValue = Get-ShadowProperty $Trace @('body_injection_observable')
    $bodyObservable = if ($bodyObservableValue -is [bool]) { [bool]$bodyObservableValue } elseif ($null -ne $injectedStage -and (Get-ShadowProperty $injectedStage @('observed')) -is [bool]) { [bool](Get-ShadowProperty $injectedStage @('observed')) } else { $false }
    $invocationValue = Get-ShadowProperty $Trace @('invocation_observable')
    $invocationObservable = ($invocationValue -is [bool] -and [bool]$invocationValue) -and ($null -ne $executedStage -and (Get-ShadowProperty $executedStage @('observed')) -eq $true)
    $evaluated = $selectionObservable -and $truth -notin @('unknown', 'not_observed')
    return [pscustomobject][ordered]@{
        present = $true
        truth_level = $truth
        selection_observable = $selectionObservable
        body_injection_observable = $bodyObservable
        invocation_observable = $invocationObservable
        evaluated = $evaluated
        ttfv_ms = Get-ShadowNullableNumber (Get-ShadowProperty $Trace @('ttfv_ms', 'time_to_first_value_ms'))
        tool_rounds = Get-ShadowNullableNumber (Get-ShadowProperty $Trace @('tool_rounds'))
    }
}

function Get-ShadowResultCase($Results, [string]$Id) {
    if ($null -eq $Results) { return $null }
    return @($Results.cases | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1)
}

function Get-ShadowMetricBoolean($Selected, $Expected, [bool]$Observable, [bool]$Positive) {
    if (-not $Observable) { return $null }
    $selectedSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @(Get-ShadowStringArray $Selected)) { $selectedSet.Add($name) | Out-Null }
    $expectedNames = @(Get-ShadowStringArray $Expected)
    if ($Positive) { return (@($expectedNames | Where-Object { $selectedSet.Contains($_) }).Count -gt 0) }
    return (@($expectedNames | Where-Object { -not $selectedSet.Contains($_) }).Count -gt 0)
}

$corpus = Read-ShadowJson $CorpusPath 'corpus'
$nativeResults = Read-ShadowJson $NativeResultsPath 'native_results'
$legacyResults = Read-ShadowJson $LegacyResultsPath 'legacy_results'
foreach ($pair in @(@{ value = $corpus; label = 'corpus' }, @{ value = $nativeResults; label = 'native_results' }, @{ value = $legacyResults; label = 'legacy_results' })) {
    if ($null -ne $pair.value -and [int]$pair.value.schema_version -ne 1) { Add-ShadowFinding 'schema_version_invalid' 'error' ('$.' + $pair.label + '.schema_version') 'Shadow inputs must use schema_version=1.' }
}

$nativeIndex = @{}
$legacyIndex = @{}
if ($null -ne $nativeResults) { foreach ($item in @($nativeResults.cases)) { $nativeIndex[[string]$item.id] = $item } }
if ($null -ne $legacyResults) { foreach ($item in @($legacyResults.cases)) { $legacyIndex[[string]$item.id] = $item } }

$caseReports = New-Object System.Collections.Generic.List[object]
$disagreements = New-Object System.Collections.Generic.List[object]
$nativeFalsePositive = 0
$nativeFalseNegative = 0
$legacyFalsePositive = 0
$legacyFalseNegative = 0
$nativeEvaluatedCount = 0
$legacyEvaluatedCount = 0
$nativePartialCount = 0
$legacyPartialCount = 0
$correctionCount = 0
$nativeTtfv = New-Object System.Collections.Generic.List[double]
$legacyTtfv = New-Object System.Collections.Generic.List[double]
$nativeToolRounds = 0.0
$legacyToolRounds = 0.0

foreach ($expected in @($corpus.cases)) {
    $caseId = [string]$expected.id
    $nativeCase = if ($nativeIndex.ContainsKey($caseId)) { $nativeIndex[$caseId] } else { $null }
    $legacyCase = if ($legacyIndex.ContainsKey($caseId)) { $legacyIndex[$caseId] } else { $null }
    if ($null -eq $nativeCase) { Add-ShadowFinding 'native_case_missing' 'error' ('$.cases[{0}].native' -f $caseId) 'Native result is missing for a paired case.' }
    if ($null -eq $legacyCase) { Add-ShadowFinding 'legacy_case_missing' 'error' ('$.cases[{0}].legacy' -f $caseId) 'Legacy result is missing for a paired case.' }
    $nativeSelected = if ($null -ne $nativeCase) { Get-ShadowStringArray $nativeCase.selected_skills } else { [string[]]@() }
    $legacySelected = if ($null -ne $legacyCase) { Get-ShadowStringArray $legacyCase.selected_skills } else { [string[]]@() }
    $nativeTrace = if ($null -ne $nativeCase) { Get-ShadowProperty $nativeCase @('trace') } else { $null }
    $legacyTrace = if ($null -ne $legacyCase) { Get-ShadowProperty $legacyCase @('trace') } else { $null }
    $nativeFacts = Get-ShadowTraceFacts $nativeTrace $nativeCase 'native'
    $legacyFacts = if ($null -ne $legacyTrace) { Get-ShadowTraceFacts $legacyTrace $legacyCase 'legacy' } else {
        [pscustomobject][ordered]@{ present = ($null -ne $legacyCase); truth_level = if ($null -ne $legacyCase -and -not [string]::IsNullOrWhiteSpace([string]$legacyCase.truth_level)) { [string]$legacyCase.truth_level } else { 'host_evaluation_partial' }; selection_observable = ($null -ne $legacyCase -and $legacyCase.PSObject.Properties.Match('selected_skills').Count -gt 0); body_injection_observable = $false; invocation_observable = $false; evaluated = ($null -ne $legacyCase -and $legacyCase.PSObject.Properties.Match('selected_skills').Count -gt 0); ttfv_ms = if ($null -ne $legacyCase) { Get-ShadowNullableNumber $legacyCase.ttfv_ms } else { $null }; tool_rounds = if ($null -ne $legacyCase) { Get-ShadowNullableNumber $legacyCase.tool_rounds } else { $null } }
    }
    if (-not $nativeFacts.present) { Add-ShadowFinding 'native_trace_missing' 'warning' ('$.cases[{0}].native.trace' -f $caseId) 'Native trace is missing; comparison remains partial and no native error is inferred.'; $nativePartialCount++ }
    elseif (-not $nativeFacts.evaluated) { $nativePartialCount++ } else { $nativeEvaluatedCount++ }
    if ($legacyFacts.evaluated) { $legacyEvaluatedCount++ } else { $legacyPartialCount++ }
    $nativeFp = Get-ShadowMetricBoolean $nativeSelected $expected.forbidden_skills $nativeFacts.evaluated $true
    $nativeFn = Get-ShadowMetricBoolean $nativeSelected $expected.required_skills $nativeFacts.evaluated $false
    $legacyFp = Get-ShadowMetricBoolean $legacySelected $expected.forbidden_skills $legacyFacts.evaluated $true
    $legacyFn = Get-ShadowMetricBoolean $legacySelected $expected.required_skills $legacyFacts.evaluated $false
    if ($nativeFp -eq $true) { $nativeFalsePositive++ }
    if ($nativeFn -eq $true) { $nativeFalseNegative++ }
    if ($legacyFp -eq $true) { $legacyFalsePositive++ }
    if ($legacyFn -eq $true) { $legacyFalseNegative++ }
    $nativeKey = $nativeSelected -join '|'
    $legacyKey = $legacySelected -join '|'
    $disagreement = $nativeKey -ne $legacyKey
    $correction = if ($disagreement -and $nativeFacts.evaluated -and $nativeFp -ne $true -and $nativeFn -ne $true) { $true } elseif ($disagreement -and $nativeFacts.evaluated) { $false } else { $null }
    if ($correction -eq $true) { $correctionCount++ }
    if ($disagreement) { $disagreements.Add([pscustomobject][ordered]@{ id = $caseId; native_selected = $nativeSelected; legacy_selected = $legacySelected; native_truth_level = $nativeFacts.truth_level; legacy_truth_level = $legacyFacts.truth_level; runtime_effect = 'none' }) | Out-Null }
    if ($null -ne $nativeFacts.ttfv_ms) { $nativeTtfv.Add([double]$nativeFacts.ttfv_ms) | Out-Null }
    if ($null -ne $legacyFacts.ttfv_ms) { $legacyTtfv.Add([double]$legacyFacts.ttfv_ms) | Out-Null }
    if ($null -ne $nativeFacts.tool_rounds) { $nativeToolRounds += [double]$nativeFacts.tool_rounds }
    if ($null -ne $legacyFacts.tool_rounds) { $legacyToolRounds += [double]$legacyFacts.tool_rounds }
    $caseReports.Add([pscustomobject][ordered]@{
            id = $caseId
            native = [pscustomobject][ordered]@{ selected_skills = $nativeSelected; truth_level = $nativeFacts.truth_level; selection_observable = $nativeFacts.selection_observable; evaluated = $nativeFacts.evaluated; body_injection_observable = $nativeFacts.body_injection_observable; invocation_observable = $nativeFacts.invocation_observable; ttfv_ms = $nativeFacts.ttfv_ms; tool_rounds = $nativeFacts.tool_rounds }
            legacy = [pscustomobject][ordered]@{ selected_skills = $legacySelected; truth_level = $legacyFacts.truth_level; selection_observable = $legacyFacts.selection_observable; evaluated = $legacyFacts.evaluated; body_injection_observable = $legacyFacts.body_injection_observable; invocation_observable = $legacyFacts.invocation_observable; ttfv_ms = $legacyFacts.ttfv_ms; tool_rounds = $legacyFacts.tool_rounds }
            metrics = [pscustomobject][ordered]@{ native_false_positive = $nativeFp; native_false_negative = $nativeFn; legacy_false_positive = $legacyFp; legacy_false_negative = $legacyFn; correction = $correction }
        }) | Out-Null
}

function Get-ShadowAverage([System.Collections.Generic.List[double]]$Values) {
    if ($null -eq $Values -or $Values.Count -eq 0) { return $null }
    return [math]::Round(($Values | Measure-Object -Average).Average, 2)
}

$nativeRegressionPass = $nativeFalsePositive -eq 0 -and $nativeFalseNegative -eq 0
if (-not $nativeRegressionPass) {
    Add-ShadowFinding 'native_regression_threshold_exceeded' 'error' '$.regression' ('Native evaluated cases exceeded the zero-regression threshold: false_positive={0}, false_negative={1}.' -f $nativeFalsePositive, $nativeFalseNegative)
}
$retirementDecision = if (-not $nativeRegressionPass) {
    'retain_legacy_shadow_and_block_retirement'
}
elseif ($nativeEvaluatedCount -eq 0) {
    'defer_retirement_no_native_evidence'
}
else {
    'retire_legacy_semantic_authority_keep_compatibility_shadow'
}

$errorCount = @($findings | Where-Object severity -eq 'error').Count
$report = [ordered]@{
    schema_version = 1
    shadow_id = 'native-legacy-shadow-v1'
    pass = ($errorCount -eq 0)
    decision_owner = 'host_ai'
    truth_boundary = 'repo_verified_only'
    runtime_affected = $false
    paired_case_count = $caseReports.Count
    disagreement_count = $disagreements.Count
    disagreements = [object[]]@($disagreements.ToArray())
    cases = [object[]]@($caseReports.ToArray())
    metrics = [ordered]@{
        native = [ordered]@{ evaluated_case_count = $nativeEvaluatedCount; partial_case_count = $nativePartialCount; false_positive_count = $nativeFalsePositive; false_negative_count = $nativeFalseNegative; mean_ttfv_ms = Get-ShadowAverage $nativeTtfv; total_tool_rounds = $nativeToolRounds }
        legacy = [ordered]@{ evaluated_case_count = $legacyEvaluatedCount; partial_case_count = $legacyPartialCount; false_positive_count = $legacyFalsePositive; false_negative_count = $legacyFalseNegative; mean_ttfv_ms = Get-ShadowAverage $legacyTtfv; total_tool_rounds = $legacyToolRounds }
        correction_count = $correctionCount
        correction_rate = if ($disagreements.Count -eq 0) { $null } else { [math]::Round($correctionCount / $disagreements.Count, 4) }
    }
    regression = [ordered]@{
        native_false_positive_count = $nativeFalsePositive
        native_false_negative_count = $nativeFalseNegative
        max_native_false_positive_count = 0
        max_native_false_negative_count = 0
        evaluated_case_count = $nativeEvaluatedCount
        partial_case_count = $nativePartialCount
        partial_cases_excluded = $true
        pass = $nativeRegressionPass
    }
    retirement = [ordered]@{
        decision = $retirementDecision
        runtime_mode = 'shadow_only'
        native_authoritative = $true
        legacy_override_applied = $false
        full_removal_gate = 'P6-010_and_P6-012'
        fresh_host_evidence_required = $true
    }
    runtime = [ordered]@{ native_authoritative = $true; legacy_override_applied = $false; legacy_used_for_runtime = $false; writes_performed = $false }
    provider_calls = 0
    native_mutations = 0
    writes = 0
    finding_count = $findings.Count
    findings = [object[]]@($findings.ToArray())
}

if ($Json) { $report | ConvertTo-Json -Depth 30 }
else {
    if ($report.pass) { Write-Host ('Native/legacy shadow comparison passed: cases={0}, disagreements={1}' -f $report.paired_case_count, $report.disagreement_count) -ForegroundColor Green }
    else { foreach ($finding in @($report.findings)) { Write-Host ('[{0}] {1}: {2}' -f $finding.code, $finding.path, $finding.message) -ForegroundColor Red }; Write-Host ('Native/legacy shadow comparison failed: findings={0}' -f $report.finding_count) -ForegroundColor Red }
}

if (-not $report.pass) { exit 1 }
exit 0
