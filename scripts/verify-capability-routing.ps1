[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$CorpusPath = 'config/capability-routing-golden.json',
    [string]$RouterPath = 'overrides/custom/capability-router/scripts/route-capability.ps1',
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
$policyFile = Resolve-RepoFile 'config/skill-routing-policy.json'
$configFile = Resolve-RepoFile 'skills.json'
foreach ($file in @($corpusFile, $routerFile, $policyFile, $configFile)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw ('Required routing file is missing: {0}' -f $file) }
}
$corpus = Get-Content -LiteralPath $corpusFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$corpus.schema_version -ne 2 -or [string]$corpus.decision_owner -ne 'host_ai' -or @($corpus.cases).Count -eq 0) {
    throw 'Routing corpus must use schema_version=2, decision_owner=host_ai, and contain cases.'
}
$config = Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('skills-manager-routing-contract-{0}' -f [Guid]::NewGuid().ToString('N'))
$manifestFile = Join-Path $fixtureRoot 'manifest.json'
$findings = [Collections.Generic.List[object]]::new()
$invalidInventoryCases = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

function Add-Finding([string]$CaseId, [string]$Code, [string]$Message) {
    $findings.Add([pscustomobject]@{ case_id = $CaseId; code = $Code; message = $Message }) | Out-Null
}

function Add-InventoryNames([Collections.Generic.HashSet[string]]$Set, $Values) {
    foreach ($value in @($Values)) {
        $name = ([string]$value).Trim()
        if (-not [string]::IsNullOrWhiteSpace($name)) { $Set.Add($name) | Out-Null }
    }
}

# The routing corpus is an expectation source, never an existence source. Build the
# portable inventory from tracked configuration declarations before synthesizing files.
$availableSkillNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($property in @($config.skill_projection.discovery_catalog.domain_memberships.PSObject.Properties)) {
    Add-InventoryNames $availableSkillNames $property.Value
}
Add-InventoryNames $availableSkillNames @($config.imports | ForEach-Object { [string]$_.name })

$availableMcpNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
Add-InventoryNames $availableMcpNames @($config.mcp_servers | ForEach-Object { [string]$_.name })
$hostOnlyKinds = @('plugin', 'app', 'connector', 'native_tool', 'tool')

foreach ($case in @($corpus.cases)) {
    $caseId = [string]$case.id
    $externalRefs = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if (-not [string]::IsNullOrWhiteSpace([string]$case.snapshot_path)) {
        $snapshotFile = Resolve-RepoFile ([string]$case.snapshot_path)
        if (Test-Path -LiteralPath $snapshotFile -PathType Leaf) {
            $snapshot = Get-Content -LiteralPath $snapshotFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($capability in @($snapshot.capabilities)) {
                $externalRefs.Add(('{0}|{1}' -f ([string]$capability.kind).ToLowerInvariant(), [string]$capability.name)) | Out-Null
            }
        }
    }
    foreach ($field in @('expected_candidates', 'host_selected')) {
        foreach ($item in @($case.$field)) {
            $kind = ([string]$item.kind).Trim().ToLowerInvariant()
            $name = ([string]$item.name).Trim()
            $code = ''
            $message = ''
            if ($kind -eq 'skill' -and -not $availableSkillNames.Contains($name)) {
                $code = 'unknown_skill_reference'
                $message = ("{0} references skill '{1}', which is absent from the tracked portable skill inventory." -f $field, $name)
            }
            elseif ($kind -eq 'mcp' -and -not $availableMcpNames.Contains($name)) {
                $code = 'unknown_mcp_reference'
                $message = ("{0} references MCP '{1}', which is absent from skills.json.mcp_servers." -f $field, $name)
            }
            elseif ($kind -in $hostOnlyKinds -and -not $externalRefs.Contains(('{0}|{1}' -f $kind, $name))) {
                $code = 'undeclared_host_capability'
                $message = ("{0} references host-only capability '{1}|{2}' without an explicit runtime snapshot declaration." -f $field, $kind, $name)
            }
            elseif ($kind -notin @('skill', 'mcp') -and $kind -notin $hostOnlyKinds) {
                $code = 'unsupported_capability_kind'
                $message = ("{0} uses unsupported capability kind '{1}'." -f $field, $kind)
            }
            if (-not [string]::IsNullOrWhiteSpace($code)) {
                Add-Finding $caseId $code $message
                $invalidInventoryCases.Add($caseId) | Out-Null
            }
        }
    }
}

function New-RoutingContractManifest {
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($case in @($corpus.cases)) {
        foreach ($field in @('expected_candidates', 'forbidden_candidates', 'host_exclude')) {
            if ($case.PSObject.Properties.Match($field).Count -eq 0) { continue }
            foreach ($item in @($case.$field)) {
                if ([string]$item.kind -eq 'skill' -and $availableSkillNames.Contains([string]$item.name)) {
                    $names.Add([string]$item.name) | Out-Null
                }
            }
        }
    }

    $entries = [Collections.Generic.List[object]]::new()
    $index = 0
    foreach ($name in @($names | Sort-Object)) {
        $index++
        $skillDirectory = Join-Path $fixtureRoot ('skill-{0:d3}' -f $index)
        New-Item -ItemType Directory -Path $skillDirectory -Force | Out-Null
        $skillPath = Join-Path $skillDirectory 'SKILL.md'
        $skillBody = "---`nname: '$name'`ndescription: Routing contract fixture for $name.`n---`n`n# $name"
        Set-Content -LiteralPath $skillPath -Value $skillBody -Encoding UTF8
        $entries.Add([pscustomobject]@{ name = $name; path = $skillPath; source_root = $fixtureRoot }) | Out-Null
    }

    [ordered]@{
        schema_version = 2
        active = @($entries.ToArray())
        canonical = @($entries.ToArray())
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestFile -Encoding UTF8
}

New-RoutingContractManifest

$passedCases = 0
$candidateRecallPassed = 0
$policyPassed = 0
$negativeConstraintViolations = 0
$semanticAutoSelections = 0
$routerMetadataCache = @{}
$routerCatalogPolicyCache = @{}
$routerCallCount = 0
$catalogPolicyCacheHitCount = 0

function Get-CapabilityRef($Item) {
    return ('{0}|{1}' -f ([string]$Item.kind).ToLowerInvariant(), [string]$Item.name)
}

function Invoke-RouterCase($Case, [string[]]$Candidate = @()) {
    $script:routerCallCount++
    $cacheCountBefore = $routerCatalogPolicyCache.Count
    $routerArgs = @{
        Query = [string]$Case.query
        ManifestPath = $manifestFile
        PolicyPath = $policyFile
        ConfigPath = $configFile
        DomainHint = @($Case.profile_hints | ForEach-Object { [string]$_ })
        Candidate = @($Candidate)
        ExcludeCapability = @($Case.host_exclude | ForEach-Object { Get-CapabilityRef $_ })
        MetadataCache = $routerMetadataCache
        CatalogPolicyCache = $routerCatalogPolicyCache
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Case.snapshot_path)) {
        $snapshotSourcePath = Resolve-RepoFile ([string]$Case.snapshot_path)
        $snapshot = Get-Content -LiteralPath $snapshotSourcePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$snapshot.captured_at -eq '__CURRENT__') {
            $snapshot.captured_at = [DateTimeOffset]::UtcNow.ToString('o')
            $snapshotFixturePath = Join-Path $fixtureRoot (Split-Path $snapshotSourcePath -Leaf)
            $snapshot | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $snapshotFixturePath -Encoding UTF8
            $routerArgs.HostSnapshotPath = $snapshotFixturePath
        }
        else { $routerArgs.HostSnapshotPath = $snapshotSourcePath }
    }
    $global:LASTEXITCODE = 0
    $raw = @(& $routerFile @routerArgs 2>&1)
    if ($routerCatalogPolicyCache.Count -eq $cacheCountBefore -and $cacheCountBefore -gt 0) { $script:catalogPolicyCacheHitCount++ }
    if ($LASTEXITCODE -ne 0) { return [pscustomobject]@{ error = ($raw -join "`n"); data = $null } }
    try { return [pscustomobject]@{ error = ''; data = (($raw -join "`n") | ConvertFrom-Json) } }
    catch { return [pscustomobject]@{ error = $_.Exception.Message; data = $null } }
}

try {
foreach ($case in @($corpus.cases)) {
    $caseId = [string]$case.id
    if ($invalidInventoryCases.Contains($caseId)) { continue }
    if ([string]::IsNullOrWhiteSpace($caseId) -or [string]::IsNullOrWhiteSpace([string]$case.query)) {
        Add-Finding $caseId 'case_invalid' 'Case id and query are required.'
        continue
    }
    $before = $findings.Count
    $discoveryCall = Invoke-RouterCase $case
    if (-not [string]::IsNullOrWhiteSpace($discoveryCall.error)) {
        Add-Finding $caseId 'router_failed' $discoveryCall.error
        continue
    }
    $discovery = $discoveryCall.data
    if ([int]$discovery.schema_version -ne 3) { Add-Finding $caseId 'schema_mismatch' 'Router must emit schema_version=3.' }
    if ([string]$discovery.decision_owner -ne 'host_ai' -or [bool]$discovery.semantic_routing_performed) {
        Add-Finding $caseId 'semantic_owner_mismatch' 'Host AI must own semantic selection and the script must report semantic_routing_performed=false.'
    }
    $architecturePair = '{0}|{1}' -f [string]$discovery.discovery_architecture, [string]$discovery.retrieval.strategy
    $supportedArchitecturePairs = @(
        'global_catalog_then_policy_v1|global_catalog_discovery',
        'global_catalog_then_policy_v1|hierarchical_domain_discovery'
    )
    if ($architecturePair -notin $supportedArchitecturePairs) {
        Add-Finding $caseId 'discovery_architecture_mismatch' 'Router must expose global_catalog_then_policy_v1 with global_catalog_discovery (no hint) or hierarchical_domain_discovery (explicit domain hint).'
    }
    if (@($discovery.discovery_domains).Count -eq 0 -or @($discovery.discovery_domains | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.purpose) }).Count -gt 0) {
        Add-Finding $caseId 'discovery_domain_invalid' 'Every discovery domain must have a non-empty purpose.'
    }
    if ([bool]$discovery.writes_performed) { Add-Finding $caseId 'unexpected_write' 'Router reported a write.' }

    $discoveredRefs = @($discovery.retrieval.candidates | ForEach-Object { Get-CapabilityRef $_ })
    $expectedRefs = @($case.expected_candidates | ForEach-Object { Get-CapabilityRef $_ })
    $recallOk = $expectedRefs.Count -eq 0 -or @($expectedRefs | Where-Object { $_ -in $discoveredRefs }).Count -gt 0
    if (-not $recallOk) {
        Add-Finding $caseId 'candidate_recall_miss' ('Expected at least one candidate from [{0}], actual [{1}].' -f ($expectedRefs -join ', '), ($discoveredRefs -join ', '))
    }
    else { $candidateRecallPassed++ }

    foreach ($forbidden in @($case.forbidden_candidates)) {
        $ref = Get-CapabilityRef $forbidden
        if ($ref -in $discoveredRefs) {
            Add-Finding $caseId 'forbidden_candidate' ('Discovery exposed forbidden candidate {0}.' -f $ref)
        }
    }
    foreach ($excluded in @($case.host_exclude)) {
        $ref = Get-CapabilityRef $excluded
        if ($ref -in $discoveredRefs) {
            $negativeConstraintViolations++
            Add-Finding $caseId 'negative_constraint_violation' ('Host-excluded capability remained discoverable: {0}.' -f $ref)
        }
    }

    $queryLower = ([string]$case.query).ToLowerInvariant()
    $explicitExpected = @($case.host_selected).Count -gt 0 -and @($case.host_selected | Where-Object {
        $nameLower = ([string]$_.name).ToLowerInvariant()
        $queryLower.Contains(('$' + $nameLower)) -or $queryLower.Contains(('@' + $nameLower))
    }).Count -gt 0
    if (-not $explicitExpected -and @($discovery.selected).Count -gt 0) {
        $semanticAutoSelections += @($discovery.selected).Count
        Add-Finding $caseId 'semantic_auto_selection' 'Discovery selected a capability before host adjudication.'
    }

    $selectionRefs = @($case.host_selected | ForEach-Object { Get-CapabilityRef $_ })
    if ($selectionRefs.Count -gt 0) {
        $policyCall = Invoke-RouterCase $case $selectionRefs
        if (-not [string]::IsNullOrWhiteSpace($policyCall.error)) {
            Add-Finding $caseId 'policy_router_failed' $policyCall.error
        }
        else {
            $policy = $policyCall.data
            $policyBefore = $findings.Count
            foreach ($expected in @($case.host_selected)) {
                $selected = @($policy.selected | Where-Object { [string]$_.kind -eq [string]$expected.kind -and [string]$_.name -eq [string]$expected.name })
                if ($selected.Count -ne 1) {
                    Add-Finding $caseId 'host_selection_missing' ('Missing host-selected {0}.' -f (Get-CapabilityRef $expected))
                    continue
                }
                $plan = @($policy.activation_plan | Where-Object { [string]$_.kind -eq [string]$expected.kind -and [string]$_.name -eq [string]$expected.name -and [string]$_.action -eq [string]$expected.action })
                if ($plan.Count -ne 1) { Add-Finding $caseId 'expected_action_missing' ('Missing action {0} for {1}.' -f [string]$expected.action, (Get-CapabilityRef $expected)) }
            }
            foreach ($plan in @($policy.activation_plan)) {
                if ([bool]$plan.load_allowed -and [string]$plan.load_side_effect -ne 'read_only') {
                    Add-Finding $caseId 'side_effect_violation' ('Auto-loaded {0}/{1} with load_side_effect={2}.' -f [string]$plan.kind, [string]$plan.name, [string]$plan.load_side_effect)
                }
                if ([string]$plan.workflow_side_effect -eq 'controlled_write' -and [string]$plan.execution_policy -ne 'approval_required') {
                    Add-Finding $caseId 'side_effect_violation' ('Write-capable workflow {0}/{1} lacks execution approval.' -f [string]$plan.kind, [string]$plan.name)
                }
            }
            if ($findings.Count -eq $policyBefore) { $policyPassed++ }
        }
    }
    else { $policyPassed++ }

    if ($findings.Count -eq $before) { $passedCases++ }
}
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

$resultEnvelope = [ordered]@{
    schema_version = 2
    command = 'verify-capability-routing'
    decision_owner = 'host_ai'
    pass = ($findings.Count -eq 0)
    case_count = @($corpus.cases).Count
    passed_case_count = $passedCases
    failed_case_count = @($corpus.cases).Count - $passedCases
    candidate_recall_passed_count = $candidateRecallPassed
    policy_passed_count = $policyPassed
    semantic_auto_selection_count = $semanticAutoSelections
    negative_constraint_violation_count = $negativeConstraintViolations
    finding_count = $findings.Count
    side_effect_violation_count = @($findings | Where-Object code -eq 'side_effect_violation').Count
    router_call_count = $routerCallCount
    catalog_policy_cache_hit_count = $catalogPolicyCacheHitCount
    writes_performed = $false
    findings = @($findings.ToArray())
}
if ($Json) { $resultEnvelope | ConvertTo-Json -Depth 10 }
elseif ($resultEnvelope.pass) { Write-Host ('Native-first capability contract verified: cases={0}, findings=0' -f $resultEnvelope.case_count) -ForegroundColor Green }
else { foreach ($finding in $findings) { Write-Host ('[{0}] {1}: {2}' -f $finding.code, $finding.case_id, $finding.message) -ForegroundColor Red } }
if (-not $resultEnvelope.pass) { exit 2 }
