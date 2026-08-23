#Requires -Version 7
<#
.SYNOPSIS
Deterministic verifier for cold-skill-routing receipt v2 records (CSR-130).

.DESCRIPTION
Validates the expected / observed / assertion split of one receipt (or a
legacy-migrated records wrapper) against the tracked scenario matrix and
fail-closed truth-boundary rules. The verifier is read-only in normal mode;
with -AllowLegacyMigration it writes only the migrated receipt.v2.json target
and never touches the legacy original.

Evidence references must be source-tagged ("router:", "host:", "child:",
"filesystem:", "fixture:") so that router output can never be upgraded into a
host or native-child event. Stable finding codes:

  E001_SCHEMA_INVALID                 missing or malformed receipt fields
  E002_ENUM_INVALID                   value drift outside declared enums
  E003_FORBIDDEN_DISCOVERY_OBSERVED   expected forbidden, discovery observed
  E004_SCENARIO_NOT_IN_MATRIX         scenario id unknown to the matrix
  E005_MATRIX_INVALID                 matrix unreadable, duplicate, or empty
  E006_VERBATIM_MISMATCH              request text differs from the matrix
  E007_SKILL_LOAD_OVERCLAIM           SKILL.md loading claimed on router-only evidence
  E008_NATIVE_CHILD_OVERCLAIM         child lifecycle claimed without child evidence
  E009_LIVE_ACCEPTANCE_OVERCLAIM      live acceptance without child/model/effort evidence
  E010_MULTI_TURN_VIA_RUNNER          interactive contract routed to the one-shot runner
  E011_TARGET_BOUND_WITHOUT_TARGET    target-bound pass without a present target object
  E012_CONTROLLED_WRITE_INCOMPLETE    writes without exact write set/proof/stop/actual list
  E013_CEILING_VIOLATED               writes under a read-only/planning-only ceiling
  E014_EVIDENCE_INVALID               empty, blank, or untagged evidence reference
  E015_REQUIRED_EVENT_NOT_OBSERVED    pass asserted while a required event stayed unobserved
  E016_MIGRATION_OVERCLAIM            migrated record claims live acceptance or loading
  E017_MIGRATION_TARGET_CONFLICT      migration output path would overwrite the original
  E018_CONTRACT_MISMATCH              effective contract contradicts the expected contract
  E019_LEGACY_SCHEMA_REQUIRES_MIGRATION

.EXAMPLE
pwsh -NoProfile -File scripts/quality/verify-cold-skill-routing-receipt.ps1 -ReceiptPath reports/cold-skill-eval/<run>/receipt.v2.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ReceiptPath,
    [string]$ScenarioMatrixPath,
    [switch]$AllowLegacyMigration,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
if ([string]::IsNullOrWhiteSpace($ScenarioMatrixPath)) {
    $ScenarioMatrixPath = Join-Path $repoRoot 'tests\fixtures\cold-skill-routing\scenarios.json'
}

$script:Findings = New-Object System.Collections.Generic.List[string]
function Add-Finding([string]$Code, [string]$Message) {
    $script:Findings.Add(('{0}: {1}' -f $Code, $Message))
}

$RouteClassEnum = @('visible_direct', 'cold_candidate', 'discovery_only', 'ordinary_no_skill', 'write_plan_only', 'target_bound', 'artifact_workflow_deferred')
$ExpectedDiscoveryEnum = @('required', 'forbidden', 'conditional')
$ExpectedContractEnum = @('none', 'one_shot', 'parent_user_input', 'multi_turn_user_decision')
$ExpectedNativeChildEnum = @('required', 'forbidden', 'not_supported', 'conditional')
$ObservedFlagEnum = @('observed', 'not_observed', 'not_observable')
$HostVisibleEnum = @('visible', 'not_visible', 'not_observable')
$NativeChildStateEnum = @('started', 'awaiting_user_answer', 'completed', 'not_started', 'not_supported', 'not_observable')
$NativeChildLifecycleEnum = @('started', 'awaiting_user_answer', 'completed')
$AssertionStatusEnum = @('pass', 'fail', 'not_observable')
$BoundaryEnum = @('repo_verified', 'filesystem_projected', 'host_loaded', 'candidate_discovery_only', 'candidate_load_validated', 'host_specific_live_accepted', 'observed', 'platform_na')
$ExecutionSurfaceEnum = @('codex', 'zcode', 'other', 'not_recorded')
$TargetPresentEnum = @('present', 'absent', 'not_observable')
$EvidenceTagPattern = '^\s*(router|host|child|filesystem|fixture)\s*:'

# --- scenario matrix ---------------------------------------------------------

$matrixIndex = $null
try {
    if (-not (Test-Path -LiteralPath $ScenarioMatrixPath -PathType Leaf)) { throw 'matrix file is missing' }
    $matrix = Get-Content -LiteralPath $ScenarioMatrixPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $entries = @($matrix.scenarios)
    if ($entries.Count -eq 0) { throw 'matrix has no scenarios' }
    $matrixIndex = @{}
    foreach ($entry in $entries) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.id)) { throw 'matrix entry lacks id' }
        if ($matrixIndex.ContainsKey([string]$entry.id)) { throw ("duplicate matrix scenario id: {0}" -f $entry.id) }
        $matrixIndex[[string]$entry.id] = $entry
    }
}
catch {
    Add-Finding 'E005_MATRIX_INVALID' ("scenario matrix rejected: {0} ({1})" -f $ScenarioMatrixPath, $_.Exception.Message)
}

# --- receipt loading and legacy migration ------------------------------------

if (-not (Test-Path -LiteralPath $ReceiptPath -PathType Leaf)) {
    Write-Output ("FINDING E001_SCHEMA_INVALID: receipt file is missing: {0}" -f $ReceiptPath)
    Write-Output 'verify-cold-skill-routing-receipt: fail findings=1'
    exit 1
}

$receiptRaw = Get-Content -LiteralPath $ReceiptPath -Raw -Encoding UTF8
try {
    $receipt = $receiptRaw | ConvertFrom-Json
}
catch {
    Add-Finding 'E001_SCHEMA_INVALID' ("receipt is not valid JSON: {0}" -f $_.Exception.Message)
}

$isMigratedWrapper = $false
if ($receipt -and $null -ne ($receipt.PSObject.Properties['records'])) {
    $isMigratedWrapper = $true
    $migration = $receipt.migrated_from
    if ($null -eq $migration -or [string]::IsNullOrWhiteSpace([string]$migration.legacy_receipt_path) -or
        [string]::IsNullOrWhiteSpace([string]$migration.legacy_receipt_sha256)) {
        Add-Finding 'E001_SCHEMA_INVALID' 'migration wrapper must bind legacy_receipt_path and legacy_receipt_sha256'
    }
}
elseif ($receipt -and [int]$receipt.schema_version -ne 2 -and $null -ne ($receipt.PSObject.Properties['scenarios'])) {
    if (-not $AllowLegacyMigration) {
        Add-Finding 'E019_LEGACY_SCHEMA_REQUIRES_MIGRATION' 'legacy receipt requires -AllowLegacyMigration; rerun with the migration flag to emit receipt.v2.json'
    }
    else {
        $targetPath = if ([string]::IsNullOrWhiteSpace($OutputPath)) { Join-Path (Split-Path -Parent (Resolve-Path -LiteralPath $ReceiptPath).Path) 'receipt.v2.json' } else { [IO.Path]::GetFullPath($OutputPath) }
        $sourcePath = (Resolve-Path -LiteralPath $ReceiptPath).Path
        if ([string]::Equals($targetPath, $sourcePath, [StringComparison]::OrdinalIgnoreCase)) {
            Add-Finding 'E017_MIGRATION_TARGET_CONFLICT' 'migration output path must differ from the legacy original'
        }
        else {
            $legacySha256 = ([string](Get-FileHash -LiteralPath $ReceiptPath -Algorithm SHA256).Hash).ToLowerInvariant()
            $legacyHost = ([string]$receipt.host).ToLowerInvariant()
            $records = New-Object System.Collections.Generic.List[object]
            foreach ($legacy in @($receipt.scenarios)) {
                $validated = ([string]$legacy.candidate_load_validated) -eq 'pass'
                $legacyContract = [string]$legacy.execution_contract
                $contract = 'none'
                foreach ($known in @('one_shot', 'parent_user_input', 'multi_turn_user_decision')) {
                    if ($legacyContract.StartsWith($known, [StringComparison]::Ordinal)) { $contract = $known }
                }
                $boundary = if ($validated) { 'candidate_load_validated' } else { 'observed' }
                $status = if (([string]$legacy.live_result_accepted) -eq 'pass') { 'pass' } elseif (([string]$legacy.live_result_accepted) -eq 'fail') { 'fail' } else { 'not_observable' }
                $eventRef = [string]$legacy.evidence.event_ref
                $records.Add([ordered]@{
                    scenario_id = [string]$legacy.scenario
                    request_verbatim = [string]$legacy.request_verbatim
                    expected = [ordered]@{
                        route_class = if ($validated) { 'cold_candidate' } elseif (([string]$legacy.host_visible) -eq 'pass') { 'visible_direct' } else { 'discovery_only' }
                        cold_discovery = 'conditional'
                        execution_contract = $contract
                        native_child = if ($legacyHost -eq 'zcode') { 'not_supported' } else { 'conditional' }
                    }
                    observed = [ordered]@{
                        host_visible = if (([string]$legacy.host_visible) -eq 'pass') { 'visible' } else { 'not_observable' }
                        cold_discovery = if ($validated) { 'observed' } else { 'not_observable' }
                        candidate_load_validation = if ($validated) { 'observed' } else { 'not_observable' }
                        skill_md_loading = 'not_observable'
                        native_child = if ($legacyHost -eq 'zcode') { 'not_supported' } else { 'not_observable' }
                        child_id_or_reason = [string]$legacy.child_id_or_reason
                        execution_surface = if ($ExecutionSurfaceEnum -contains $legacyHost) { $legacyHost } else { 'other' }
                        writes_or_external_calls = @($legacy.writes_or_external_calls)
                    }
                    assertion = [ordered]@{
                        status = $status
                        achieved_boundary = $boundary
                        evidence_refs = if ([string]::IsNullOrWhiteSpace($eventRef)) { @() } else { @('filesystem: ' + $eventRef) }
                    }
                })
            }
            $migrated = [ordered]@{
                schema_version = 2
                run_id = [string]$receipt.run_id
                migrated_from = [ordered]@{
                    legacy_receipt_path = $sourcePath
                    legacy_receipt_sha256 = $legacySha256
                    legacy_host = if ([string]::IsNullOrWhiteSpace($legacyHost)) { 'not_recorded' } else { $legacyHost }
                    migrated_at = [DateTimeOffset]::UtcNow.ToString('o')
                    migration_notes = @(
                        'native child lifecycle was not observable in the source host',
                        'skill_md_loading downgraded to not_observable: the legacy record has no host read event',
                        'assertion capped below host_specific_live_accepted',
                        'legacy pass retained only for router-observable boundaries'
                    )
                }
                records = @($records.ToArray())
            }
            $json = $migrated | ConvertTo-Json -Depth 12
            [IO.File]::WriteAllText($targetPath, $json, [Text.UTF8Encoding]::new($false))
            Write-Output ("migration written: {0}" -f $targetPath)
            $receipt = Get-Content -LiteralPath $targetPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $isMigratedWrapper = $true
        }
    }
}

# --- record verification ------------------------------------------------------

function Assert-Enum([object]$Value, [string[]]$Allowed, [string]$Label, [string]$ScenarioId) {
    if ($Allowed -notcontains [string]$Value) {
        Add-Finding 'E002_ENUM_INVALID' ("{0}: {1} has invalid value '{2}'" -f $ScenarioId, $Label, [string]$Value)
    }
}

function Test-ReceiptRecord($Record, [bool]$FromMigration) {
    $scenarioId = [string]$Record.scenario_id
    if ([string]::IsNullOrWhiteSpace($scenarioId)) {
        $scenarioId = '<missing scenario_id>'
        Add-Finding 'E001_SCHEMA_INVALID' 'record lacks scenario_id'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Record.request_verbatim)) {
        Add-Finding 'E001_SCHEMA_INVALID' ("{0}: request_verbatim is empty" -f $scenarioId)
    }

    $expected = $Record.expected
    $observed = $Record.observed
    $assertion = $Record.assertion
    $missingStructure = $false
    if ($null -eq $expected -or $null -eq $observed -or $null -eq $assertion) {
        Add-Finding 'E001_SCHEMA_INVALID' ("{0}: expected/observed/assertion block missing" -f $scenarioId)
        return
    }
    foreach ($field in @('route_class', 'cold_discovery', 'execution_contract', 'native_child')) {
        if ($null -eq ($expected.PSObject.Properties[$field])) { Add-Finding 'E001_SCHEMA_INVALID' ("{0}: expected.{1} is missing" -f $scenarioId, $field); $missingStructure = $true }
    }
    foreach ($field in @('host_visible', 'cold_discovery', 'candidate_load_validation', 'skill_md_loading', 'native_child')) {
        if ($null -eq ($observed.PSObject.Properties[$field])) { Add-Finding 'E001_SCHEMA_INVALID' ("{0}: observed.{1} is missing" -f $scenarioId, $field); $missingStructure = $true }
    }
    if ($null -eq ($observed.PSObject.Properties['writes_or_external_calls'])) { Add-Finding 'E001_SCHEMA_INVALID' ("{0}: observed.writes_or_external_calls is missing" -f $scenarioId); $missingStructure = $true }
    foreach ($field in @('status', 'achieved_boundary')) {
        if ($null -eq ($assertion.PSObject.Properties[$field])) { Add-Finding 'E001_SCHEMA_INVALID' ("{0}: assertion.{1} is missing" -f $scenarioId, $field); $missingStructure = $true }
    }
    if ($null -eq ($assertion.PSObject.Properties['evidence_refs'])) { Add-Finding 'E001_SCHEMA_INVALID' ("{0}: assertion.evidence_refs is missing" -f $scenarioId); $missingStructure = $true }
    if ($missingStructure) { return }

    Assert-Enum $expected.route_class $RouteClassEnum 'expected.route_class' $scenarioId
    Assert-Enum $expected.cold_discovery $ExpectedDiscoveryEnum 'expected.cold_discovery' $scenarioId
    Assert-Enum $expected.execution_contract $ExpectedContractEnum 'expected.execution_contract' $scenarioId
    Assert-Enum $expected.native_child $ExpectedNativeChildEnum 'expected.native_child' $scenarioId
    Assert-Enum $observed.host_visible $HostVisibleEnum 'observed.host_visible' $scenarioId
    Assert-Enum $observed.cold_discovery $ObservedFlagEnum 'observed.cold_discovery' $scenarioId
    Assert-Enum $observed.candidate_load_validation $ObservedFlagEnum 'observed.candidate_load_validation' $scenarioId
    Assert-Enum $observed.skill_md_loading $ObservedFlagEnum 'observed.skill_md_loading' $scenarioId
    Assert-Enum $observed.native_child $NativeChildStateEnum 'observed.native_child' $scenarioId
    Assert-Enum $assertion.status $AssertionStatusEnum 'assertion.status' $scenarioId
    Assert-Enum $assertion.achieved_boundary $BoundaryEnum 'assertion.achieved_boundary' $scenarioId
    if ($null -ne ($observed.PSObject.Properties['execution_surface'])) { Assert-Enum $observed.execution_surface $ExecutionSurfaceEnum 'observed.execution_surface' $scenarioId }
    if ($null -ne ($observed.PSObject.Properties['target_object_present'])) { Assert-Enum $observed.target_object_present $TargetPresentEnum 'observed.target_object_present' $scenarioId }

    # Matrix cross-check is the oracle for fresh receipts; migrated records keep
    # their legacy ids and are exempt from matrix membership and verbatim match.
    $matrixEntry = $null
    if (-not $FromMigration -and $null -ne $script:MatrixIndex) {
        $matrixEntry = $script:MatrixIndex[$scenarioId]
        if ($null -eq $matrixEntry) {
            Add-Finding 'E004_SCENARIO_NOT_IN_MATRIX' ("{0}: scenario id is not present in the tracked matrix" -f $scenarioId)
        }
        elseif (-not [string]::Equals([string]$Record.request_verbatim, [string]$matrixEntry.request_verbatim, [StringComparison]::Ordinal)) {
            Add-Finding 'E006_VERBATIM_MISMATCH' ("{0}: request_verbatim differs from the tracked matrix entry" -f $scenarioId)
        }
    }

    # Evidence integrity: references must be tagged by source and non-empty for
    # concluded assertions, so router output can never masquerade as host evidence.
    $evidenceRefs = @($assertion.evidence_refs)
    foreach ($ref in @($evidenceRefs)) {
        if ([string]::IsNullOrWhiteSpace([string]$ref)) {
            Add-Finding 'E014_EVIDENCE_INVALID' ("{0}: evidence_refs contains an empty reference" -f $scenarioId)
        }
        elseif ([string]$ref -notmatch $EvidenceTagPattern) {
            Add-Finding 'E014_EVIDENCE_INVALID' ("{0}: evidence reference is not source-tagged (router|host|child|filesystem|fixture): {1}" -f $scenarioId, $ref)
        }
    }
    if ([string]$assertion.status -in @('pass', 'fail') -and @($evidenceRefs | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -eq 0) {
        Add-Finding 'E014_EVIDENCE_INVALID' ("{0}: assertion.status={1} requires at least one non-empty evidence reference" -f $scenarioId, $assertion.status)
    }
    $childEvidence = @($evidenceRefs | Where-Object { ([string]$_) -match '^\s*child\s*:' })
    $hostEvidence = @($evidenceRefs | Where-Object { ([string]$_) -match '^\s*(host|child)\s*:' })

    # Forbidden events must not have happened.
    if ([string]$expected.cold_discovery -eq 'forbidden' -and [string]$observed.cold_discovery -eq 'observed') {
        Add-Finding 'E003_FORBIDDEN_DISCOVERY_OBSERVED' ("{0}: cold discovery was expected forbidden but observed" -f $scenarioId)
    }

    # Router validation is not a SKILL.md load and a parent is not a native child.
    if ([string]$observed.skill_md_loading -eq 'observed' -and $hostEvidence.Count -eq 0) {
        Add-Finding 'E007_SKILL_LOAD_OVERCLAIM' ("{0}: skill_md_loading=observed without host:/child: evidence" -f $scenarioId)
    }
    if ([string]$observed.native_child -in $NativeChildLifecycleEnum) {
        if ($childEvidence.Count -eq 0) {
            Add-Finding 'E008_NATIVE_CHILD_OVERCLAIM' ("{0}: native_child={1} without child: evidence" -f $scenarioId, $observed.native_child)
        }
        if ([string]::IsNullOrWhiteSpace([string]$observed.child_id_or_reason)) {
            Add-Finding 'E008_NATIVE_CHILD_OVERCLAIM' ("{0}: native_child={1} without child_id_or_reason" -f $scenarioId, $observed.native_child)
        }
    }

    # Live acceptance is the highest boundary and needs the full event chain.
    if ([string]$assertion.achieved_boundary -eq 'host_specific_live_accepted') {
        if ([string]$observed.native_child -notin $NativeChildLifecycleEnum) {
            Add-Finding 'E009_LIVE_ACCEPTANCE_OVERCLAIM' ("{0}: live acceptance with native_child={1}" -f $scenarioId, $observed.native_child)
        }
        if ([string]$observed.model -ne 'gpt-5.6-terra') {
            Add-Finding 'E009_LIVE_ACCEPTANCE_OVERCLAIM' ("{0}: live acceptance with model='{1}'" -f $scenarioId, [string]$observed.model)
        }
        if ([string]$observed.model_reasoning_effort -ne 'high') {
            Add-Finding 'E009_LIVE_ACCEPTANCE_OVERCLAIM' ("{0}: live acceptance with model_reasoning_effort='{1}'" -f $scenarioId, [string]$observed.model_reasoning_effort)
        }
        if ([string]$observed.execution_surface -eq 'zcode') {
            Add-Finding 'E009_LIVE_ACCEPTANCE_OVERCLAIM' ("{0}: ZCode parent mediation cannot reach host_specific_live_accepted" -f $scenarioId)
        }
        if ($childEvidence.Count -eq 0) {
            Add-Finding 'E009_LIVE_ACCEPTANCE_OVERCLAIM' ("{0}: live acceptance without child: evidence" -f $scenarioId)
        }
    }

    # The one-shot runner never owns an interactive contract.
    $effective = $observed.effective_execution_contract
    if ($null -ne $effective) {
        $agent = [string]$effective.native_agent
        $mode = [string]$effective.mode
        if ($agent -eq 'cold-capability-runner' -and ($mode -ne 'one_shot' -or [string]$expected.execution_contract -eq 'multi_turn_user_decision' -or $mode -eq 'multi_turn_user_decision')) {
            Add-Finding 'E010_MULTI_TURN_VIA_RUNNER' ("{0}: cold-capability-runner cannot execute mode={1} (expected {2})" -f $scenarioId, $mode, $expected.execution_contract)
        }
        if ($mode -in $ExpectedContractEnum -and $mode -ne 'none' -and [string]$expected.execution_contract -in @('one_shot', 'parent_user_input', 'multi_turn_user_decision') -and $mode -ne [string]$expected.execution_contract) {
            Add-Finding 'E018_CONTRACT_MISMATCH' ("{0}: effective contract mode={1} contradicts expected {2}" -f $scenarioId, $mode, $expected.execution_contract)
        }
    }

    # Target-bound scenarios pass only against a present target object.
    if ($null -ne $matrixEntry -and [string]$matrixEntry.route_class -eq 'target_bound') {
        if ([string]$observed.target_object_present -ne 'present' -and [string]$assertion.status -eq 'pass') {
            Add-Finding 'E011_TARGET_BOUND_WITHOUT_TARGET' ("{0}: target_bound pass with target_object_present='{1}'" -f $scenarioId, [string]$observed.target_object_present)
        }
    }

    # Any write or external call requires the full controlled-write admission.
    $effects = @($observed.writes_or_external_calls | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($effects.Count -gt 0) {
        $admission = $observed.controlled_write_admission
        $incomplete = $null -eq $admission
        if (-not $incomplete) {
            if (@($admission.exact_write_set).Count -eq 0) { $incomplete = $true }
            if ([string]::IsNullOrWhiteSpace([string]$admission.minimum_proof)) { $incomplete = $true }
            if ([string]::IsNullOrWhiteSpace([string]$admission.stop_condition)) { $incomplete = $true }
            if ($null -eq ($admission.PSObject.Properties['actual_writes'])) { $incomplete = $true }
        }
        if ($incomplete) {
            Add-Finding 'E012_CONTROLLED_WRITE_INCOMPLETE' ("{0}: {1} write/external effect(s) without exact write set, minimum proof, stop condition, and actual writes" -f $scenarioId, $effects.Count)
        }
        if ($null -ne $matrixEntry -and @('none', 'read_only', 'planning_only') -contains [string]$matrixEntry.side_effect_ceiling) {
            Add-Finding 'E013_CEILING_VIOLATED' ("{0}: writes/external calls under matrix side_effect_ceiling={1}" -f $scenarioId, $matrixEntry.side_effect_ceiling)
        }
    }

    # A pass cannot rest on events that were never observed.
    if ([string]$assertion.status -eq 'pass') {
        if ([string]$expected.cold_discovery -eq 'required' -and [string]$observed.cold_discovery -ne 'observed') {
            Add-Finding 'E015_REQUIRED_EVENT_NOT_OBSERVED' ("{0}: pass with required cold discovery recorded as {1}" -f $scenarioId, $observed.cold_discovery)
        }
        if ([string]$expected.native_child -eq 'required' -and [string]$observed.native_child -notin $NativeChildLifecycleEnum) {
            Add-Finding 'E015_REQUIRED_EVENT_NOT_OBSERVED' ("{0}: pass with required native child recorded as {1}" -f $scenarioId, $observed.native_child)
        }
    }

    # Migration output may never out-climb its missing host events.
    if ($FromMigration) {
        if ([string]$assertion.achieved_boundary -eq 'host_specific_live_accepted') {
            Add-Finding 'E016_MIGRATION_OVERCLAIM' ("{0}: migrated record cannot claim host_specific_live_accepted" -f $scenarioId)
        }
        if ([string]$observed.skill_md_loading -eq 'observed') {
            Add-Finding 'E016_MIGRATION_OVERCLAIM' ("{0}: migrated record cannot claim observed SKILL.md loading" -f $scenarioId)
        }
        if ([string]$observed.native_child -in $NativeChildLifecycleEnum) {
            Add-Finding 'E016_MIGRATION_OVERCLAIM' ("{0}: migrated record cannot claim native child lifecycle state {1}" -f $scenarioId, $observed.native_child)
        }
    }
}

$script:MatrixIndex = $matrixIndex
if ($null -ne $receipt) {
    if ($isMigratedWrapper) {
        $wrapped = @($receipt.records)
        if ($wrapped.Count -eq 0) { Add-Finding 'E001_SCHEMA_INVALID' 'migration wrapper has no records' }
        foreach ($record in $wrapped) { Test-ReceiptRecord $record $true }
    }
    elseif ([int]$receipt.schema_version -ne 2) {
        Add-Finding 'E001_SCHEMA_INVALID' ("unsupported receipt schema_version: {0}" -f [string]$receipt.schema_version)
    }
    else {
        Test-ReceiptRecord $receipt $false
    }
}

if ($script:Findings.Count -gt 0) {
    foreach ($finding in $script:Findings) { Write-Output ("FINDING {0}" -f $finding) }
    Write-Output ("verify-cold-skill-routing-receipt: fail findings={0}" -f $script:Findings.Count)
    exit 1
}
Write-Output 'verify-cold-skill-routing-receipt: pass findings=0'
exit 0
