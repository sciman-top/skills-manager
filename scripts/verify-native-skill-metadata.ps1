[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$CorpusPath = 'config/native-skill-activation-corpus.json',
    [string]$MetadataPath = '',
    [string]$HostInventoryPath = '',
    [string]$ProjectionReceiptPath = '',
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RepoRoot)
$findings = [Collections.Generic.List[object]]::new()

function Add-MetadataFinding {
    param([string]$Code, [string]$Path, [string]$Message)
    $findings.Add([pscustomobject][ordered]@{ code = $Code; path = $Path; message = $Message }) | Out-Null
}

function Resolve-RepoFile([string]$Path) {
    $full = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $root $Path)) }
    $rootPrefix = $root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -and $full -ne $root) {
        throw ('Path escapes repository root: {0}' -f $Path)
    }
    return $full
}

function Resolve-MetadataSource([string]$Source, [string]$TargetName) {
    if ($TargetName -eq 'capability-router' -and -not [string]::IsNullOrWhiteSpace($MetadataPath)) {
        return [IO.Path]::GetFullPath($MetadataPath)
    }
    return Resolve-RepoFile $Source
}

function Resolve-ReadOnlyInput([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $full = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $root $Path)) }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw ('Read-only input file is missing: {0}' -f $Path) }
    return $full
}

function Read-JsonInput([string]$Path) {
    return Get-Content -LiteralPath (Resolve-ReadOnlyInput $Path) -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-ObjectProperty($Object, [string[]]$Names) {
    foreach ($name in @($Names)) {
        if ($null -ne $Object -and $null -ne ($Object.PSObject.Properties | Where-Object Name -eq $name | Select-Object -First 1)) { return $Object.$name }
    }
    return $null
}

function Remove-QuotedValue([string]$Value) {
    $text = ([string]$Value).Trim()
    if ($text.Length -ge 2) {
        if (($text.StartsWith('"') -and $text.EndsWith('"')) -or ($text.StartsWith("'") -and $text.EndsWith("'"))) {
            return $text.Substring(1, $text.Length - 2)
        }
    }
    return $text
}

function Read-NativeMetadataDescription([string]$Path, [string]$Field) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ valid = $false; code = 'metadata_source_missing'; description = ''; message = 'Metadata source file is missing.' }
    }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $lines = @($text -split '\r?\n')
    $line = $null
    if ($Field -eq 'interface.short_description') {
        $line = @($lines | Where-Object { $_ -match '^\s*short_description:\s*(?<value>.+?)\s*$' } | Select-Object -First 1)
    }
    elseif ($Field -eq 'frontmatter.description') {
        $frontmatterEnd = [Array]::IndexOf($lines, '---', 1)
        $searchLines = if ($frontmatterEnd -gt 0) { $lines[0..$frontmatterEnd] } else { $lines | Select-Object -First 16 }
        $line = @($searchLines | Where-Object { $_ -match '^\s*description:\s*(?<value>.+?)\s*$' } | Select-Object -First 1)
    }
    else {
        return [pscustomobject]@{ valid = $false; code = 'metadata_field_unsupported'; description = ''; message = ('Unsupported metadata field: {0}' -f $Field) }
    }
    if ($line.Count -ne 1) {
        return [pscustomobject]@{ valid = $false; code = 'metadata_description_missing'; description = ''; message = ('Metadata description field is missing: {0}' -f $Field) }
    }
    $match = [regex]::Match([string]$line[0], ':(?<value>.+?)\s*$')
    return [pscustomobject]@{ valid = $true; code = ''; description = Remove-QuotedValue $match.Groups['value'].Value; message = '' }
}

function Get-StringArray($Value) {
    return [string[]]@($Value | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$corpus = $null
$corpusFile = $null
try {
    $corpusFile = Resolve-RepoFile $CorpusPath
    if (-not (Test-Path -LiteralPath $corpusFile -PathType Leaf)) {
        Add-MetadataFinding 'corpus_missing' $CorpusPath 'Activation corpus file is missing.'
    }
    else {
        $corpus = Get-Content -LiteralPath $corpusFile -Raw -Encoding UTF8 | ConvertFrom-Json
    }
}
catch {
    Add-MetadataFinding 'corpus_invalid' $CorpusPath $_.Exception.Message
}

$metadataResults = [Collections.Generic.List[object]]::new()
$knownTargets = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$activationGroups = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$triggerPhrases = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$requiredCategories = @('direct', 'indirect', 'negative', 'ambiguous', 'no_skill')
$requiredPairwiseDimensions = @('artifact_create', 'artifact_read', 'portable_fallback', 'signed_in_session', 'live_control', 'local_testing', 'test_authoring', 'no_browser', 'side_effect_boundary')
$minDescription = 0
$maxDescription = 0
$maxTriggers = 0
$pairwiseTargets = [string[]]@()
$pairwiseGroups = @()
$pairwiseDimensions = [string[]]@()
$pairwiseCaseCount = 0
$pairwiseCoverage = @{}

if ($null -ne $corpus) {
    if ([int]$corpus.schema_version -ne 1) { Add-MetadataFinding 'schema_version_invalid' '$.schema_version' 'Native metadata corpus schema_version must be 1.' }
    if ([string]$corpus.decision_owner -ne 'host_ai') { Add-MetadataFinding 'decision_owner_invalid' '$.decision_owner' 'Semantic selection ownership must remain host_ai.' }
    if ($corpus.semantic_selection_applied -ne $false) { Add-MetadataFinding 'semantic_selection_forbidden' '$.semantic_selection_applied' 'The corpus cannot apply semantic selection.' }
    $pairwiseDimensions = Get-StringArray $corpus.pairwise_dimensions
    foreach ($dimension in $requiredPairwiseDimensions) {
        if ($pairwiseDimensions -notcontains $dimension) { Add-MetadataFinding 'pairwise_dimension_missing' '$.pairwise_dimensions' ('Required pairwise risk dimension is missing: {0}' -f $dimension) }
        else { $pairwiseCoverage[$dimension] = 0 }
    }
    $pairwiseTargets = Get-StringArray $corpus.pairwise_targets
    $pairwiseTargetSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $pairwiseTargets) {
        if (-not $pairwiseTargetSet.Add($name)) { Add-MetadataFinding 'pairwise_target_duplicate' '$.pairwise_targets' ('Pairwise target is duplicated: {0}' -f $name) }
        else { $knownTargets.Add($name) | Out-Null }
    }
    if ([int]$corpus.pairwise_target_count -ne $pairwiseTargets.Count) { Add-MetadataFinding 'pairwise_target_count_invalid' '$.pairwise_target_count' 'pairwise_target_count must match pairwise_targets.' }
    $pairwiseGroups = @($corpus.pairwise_groups)
    $pairwiseGroupIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($group in $pairwiseGroups) {
        $groupId = ([string]$group.id).Trim()
        if ([string]::IsNullOrWhiteSpace($groupId) -or -not $pairwiseGroupIds.Add($groupId)) { Add-MetadataFinding 'pairwise_group_invalid' '$.pairwise_groups' 'Pairwise groups require unique ids.'; continue }
        $groupSkills = Get-StringArray $group.skills
        if ($groupSkills.Count -lt 2) { Add-MetadataFinding 'pairwise_group_too_small' '$.pairwise_groups' ('Pairwise group must contain at least two alternatives: {0}' -f $groupId) }
        foreach ($name in $groupSkills) { if (-not $pairwiseTargetSet.Contains($name)) { Add-MetadataFinding 'pairwise_group_target_unknown' '$.pairwise_groups.skills' ('Pairwise group references an undeclared target: {0}' -f $name) } }
    }
    if ([int]$corpus.pairwise_group_count -ne $pairwiseGroups.Count) { Add-MetadataFinding 'pairwise_group_count_invalid' '$.pairwise_group_count' 'pairwise_group_count must match pairwise_groups.' }
    $categories = Get-StringArray $corpus.categories
    foreach ($category in $requiredCategories) { if ($categories -notcontains $category) { Add-MetadataFinding 'category_missing' '$.categories' ('Required evaluation category is missing: {0}' -f $category) } }
    $limits = $corpus.metadata_limits
    $minDescription = [int]$limits.min_description_characters
    $maxDescription = [int]$limits.max_description_characters
    $maxTriggers = [int]$limits.max_trigger_phrases
    if ($minDescription -lt 1 -or $maxDescription -lt $minDescription -or $maxTriggers -lt 1) { Add-MetadataFinding 'metadata_limits_invalid' '$.metadata_limits' 'Metadata limits must be positive and ordered.' }

    foreach ($target in @($corpus.metadata_targets)) {
        $targetName = ([string]$target.name).Trim()
        $targetPath = '$.metadata_targets[{0}]' -f $metadataResults.Count
        if ([string]::IsNullOrWhiteSpace($targetName) -or -not $knownTargets.Add($targetName)) { Add-MetadataFinding 'metadata_target_duplicate' ($targetPath + '.name') 'Metadata target name is empty or duplicated.'; continue }
        $group = ([string]$target.activation_group).Trim()
        if ([string]::IsNullOrWhiteSpace($group) -or -not $activationGroups.Add($group)) { Add-MetadataFinding 'metadata_activation_overlap' ($targetPath + '.activation_group') 'Each metadata target needs a unique activation group.' }
        try {
            $sourcePath = Resolve-MetadataSource ([string]$target.source) $targetName
            $metadata = Read-NativeMetadataDescription $sourcePath ([string]$target.field)
        }
        catch {
            $metadata = [pscustomobject]@{ valid = $false; code = 'metadata_source_invalid'; description = ''; message = $_.Exception.Message }
            $sourcePath = [string]$target.source
        }
        if (-not [bool]$metadata.valid) {
            Add-MetadataFinding ([string]$metadata.code) ($targetPath + '.source') ([string]$metadata.message)
        }
        else {
            $description = [string]$metadata.description
            $length = $description.Length
            if ($length -lt $minDescription) { Add-MetadataFinding 'metadata_description_too_short' ($targetPath + '.description') ('Metadata description is too short: {0} characters.' -f $length) }
            if ($length -gt $maxDescription) { Add-MetadataFinding 'metadata_description_too_long' ($targetPath + '.description') ('Metadata description is too long: {0} characters; limit is {1}.' -f $length, $maxDescription) }
            $targetTriggers = Get-StringArray $target.trigger_phrases
            if ($targetTriggers.Count -eq 0 -or $targetTriggers.Count -gt $maxTriggers) { Add-MetadataFinding 'metadata_trigger_count_invalid' ($targetPath + '.trigger_phrases') 'Each metadata target must declare a small, non-empty trigger phrase set.' }
            foreach ($phrase in $targetTriggers) {
                if (-not $triggerPhrases.Add($phrase)) { Add-MetadataFinding 'metadata_trigger_overlap' ($targetPath + '.trigger_phrases') ('Trigger phrase is shared by multiple metadata targets: {0}' -f $phrase) }
                if (-not $description.ToLowerInvariant().Contains($phrase.ToLowerInvariant())) { Add-MetadataFinding 'metadata_trigger_not_observable' ($targetPath + '.trigger_phrases') ('Trigger phrase is not represented in metadata description: {0}' -f $phrase) }
            }
            $metadataResults.Add([pscustomobject][ordered]@{ name = $targetName; source = $sourcePath; field = [string]$target.field; source_description = $description; character_count = $length; formerly_unreachable = [bool]$target.formerly_unreachable; projection_effect = 'plan_only' }) | Out-Null
        }
    }
    if ([int]$corpus.metadata_target_count -ne @($corpus.metadata_targets).Count) { Add-MetadataFinding 'metadata_target_count_invalid' '$.metadata_target_count' 'metadata_target_count must match metadata_targets.' }
    $formerlyUnreachable = @($corpus.metadata_targets | Where-Object { [bool]$_.formerly_unreachable }).Count
    if ([int]$corpus.formerly_unreachable_skill_count -ne $formerlyUnreachable) { Add-MetadataFinding 'formerly_unreachable_count_invalid' '$.formerly_unreachable_skill_count' 'Formerly unreachable count must match target metadata.' }

    $caseIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $caseCategories = @{}
    foreach ($case in @($corpus.cases)) {
        $caseId = ([string]$case.id).Trim()
        $casePath = '$.cases[{0}]' -f (@($caseCategories.Keys).Count)
        if ([string]::IsNullOrWhiteSpace($caseId) -or -not $caseIds.Add($caseId)) { Add-MetadataFinding 'case_id_invalid' ($casePath + '.id') 'Case id is empty or duplicated.' }
        $category = ([string]$case.category).Trim()
        if ($requiredCategories -notcontains $category) { Add-MetadataFinding 'case_category_invalid' ($casePath + '.category') ('Unsupported case category: {0}' -f $category) }
        $required = Get-StringArray $case.required_skills
        $forbidden = Get-StringArray $case.forbidden_skills
        foreach ($name in $required) { if (-not $knownTargets.Contains($name)) { Add-MetadataFinding 'case_target_unknown' ($casePath + '.required_skills') ('Case references an unknown metadata target: {0}' -f $name) } }
        foreach ($name in $forbidden) { if (-not $knownTargets.Contains($name)) { Add-MetadataFinding 'case_target_unknown' ($casePath + '.forbidden_skills') ('Case references an unknown metadata target: {0}' -f $name) } }
        $pairwiseGroup = ([string]$case.pairwise_group).Trim()
        if (-not [string]::IsNullOrWhiteSpace($pairwiseGroup)) {
            $pairwiseCaseCount++
            if (-not $pairwiseGroupIds.Contains($pairwiseGroup)) { Add-MetadataFinding 'pairwise_case_group_unknown' ($casePath + '.pairwise_group') ('Case references an unknown pairwise group: {0}' -f $pairwiseGroup) }
            $caseDimensions = Get-StringArray $case.dimensions
            if ($caseDimensions.Count -eq 0) { Add-MetadataFinding 'pairwise_case_dimensions_missing' ($casePath + '.dimensions') 'Pairwise cases require explicit risk dimensions.' }
            foreach ($dimension in $caseDimensions) {
                if (-not $pairwiseDimensions.Contains($dimension)) { Add-MetadataFinding 'pairwise_case_dimension_unknown' ($casePath + '.dimensions') ('Case references an undeclared pairwise dimension: {0}' -f $dimension) }
                elseif ($pairwiseCoverage.ContainsKey($dimension)) { $pairwiseCoverage[$dimension]++ }
            }
        }
        foreach ($name in $required) { if ($forbidden -contains $name) { Add-MetadataFinding 'case_required_forbidden_overlap' $casePath ('Case both requires and forbids: {0}' -f $name) } }
        if ([string]::IsNullOrWhiteSpace([string]$case.request)) { Add-MetadataFinding 'case_request_missing' ($casePath + '.request') 'Case request is required.' }
        switch ($category) {
            'direct' { if ($required.Count -lt 1 -or [string]$case.expected_host_action -ne 'load_or_invoke') { Add-MetadataFinding 'direct_case_invalid' $casePath 'Direct cases need a required target and load_or_invoke expectation.' } }
            'indirect' { if ($required.Count -lt 1 -or [string]$case.expected_host_action -ne 'load_or_invoke') { Add-MetadataFinding 'indirect_case_invalid' $casePath 'Indirect cases need a required target and load_or_invoke expectation.' } }
            'negative' { if ($required.Count -ne 0 -or $forbidden.Count -lt 1 -or [string]$case.expected_host_action -ne 'abstain') { Add-MetadataFinding 'negative_case_invalid' $casePath 'Negative cases must not require a skill and must abstain.' } }
            'ambiguous' { if ($required.Count -lt 1 -or $required.Count -gt 2 -or [string]$case.expected_host_action -ne 'minimal_set') { Add-MetadataFinding 'ambiguous_case_invalid' $casePath 'Ambiguous cases must declare a bounded minimal set.' } }
            'no_skill' { if ($required.Count -ne 0 -or $forbidden.Count -ne 0 -or [string]$case.expected_host_action -ne 'abstain') { Add-MetadataFinding 'no_skill_case_invalid' $casePath 'No-skill controls must abstain without required or forbidden targets.' } }
        }
        if (-not $caseCategories.ContainsKey($category)) { $caseCategories[$category] = 0 }
        $caseCategories[$category]++
    }
    if ([int]$corpus.case_count -ne @($corpus.cases).Count) { Add-MetadataFinding 'case_count_invalid' '$.case_count' 'case_count must match cases.' }
    if ([int]$corpus.pairwise_case_count -ne $pairwiseCaseCount) { Add-MetadataFinding 'pairwise_case_count_invalid' '$.pairwise_case_count' 'pairwise_case_count must match cases with pairwise_group.' }
    foreach ($dimension in $requiredPairwiseDimensions) { if ($pairwiseCoverage.ContainsKey($dimension) -and $pairwiseCoverage[$dimension] -eq 0) { Add-MetadataFinding 'pairwise_dimension_uncovered' '$.cases' ('No pairwise case covers risk dimension: {0}' -f $dimension) } }
    foreach ($category in $requiredCategories) { if (-not $caseCategories.ContainsKey($category)) { Add-MetadataFinding 'category_case_missing' '$.cases' ('No cases exist for category: {0}' -f $category) } }
}

$observedInventory = [ordered]@{
    status = 'not_provided'
    source = ''
    projection_receipt = ''
    snapshot_id = ''
    captured_at = $null
    freshness = 'unknown'
    observed_total = 0
    expected_total = 0
    matched_total = 0
    missing_total = 0
    unexpected_total = 0
    missing_names = [object[]]@()
    entries = [object[]]@()
    description_metrics = [ordered]@{
        scope = 'expected_projected_skills'
        measured_total = 0
        total_characters = 0
        maximum_characters = 0
        average_characters = $null
        advisory_limit_characters = $maxDescription
        over_advisory_limit_total = 0
    }
    budget = [ordered]@{
        value = $null
        source = 'unknown_fallback'
        freshness = 'unknown'
        host_budget_status = 'unknown'
        host_budget_pass = $null
        assessment = 'not_computable_from_observed_character_counts'
    }
}

$hostInputProvided = -not [string]::IsNullOrWhiteSpace($HostInventoryPath)
$receiptInputProvided = -not [string]::IsNullOrWhiteSpace($ProjectionReceiptPath)
if ($hostInputProvided -xor $receiptInputProvided) {
    Add-MetadataFinding 'host_inventory_input_pair_required' '$.observed_inventory' 'Host inventory and projection receipt must be supplied together.'
    $observedInventory.status = 'invalid'
}
elseif ($hostInputProvided -and $receiptInputProvided) {
    $hostFindingStart = $findings.Count
    try {
        $hostFile = Resolve-ReadOnlyInput $HostInventoryPath
        $receiptFile = Resolve-ReadOnlyInput $ProjectionReceiptPath
        $snapshot = Read-JsonInput $hostFile
        $receipt = Read-JsonInput $receiptFile
        $inventoryFact = Get-ObjectProperty (Get-ObjectProperty $snapshot @('capabilities')) @('skills_inventory')
        $inventoryRows = @((Get-ObjectProperty $inventoryFact @('value')))
        $freshness = [string](Get-ObjectProperty $inventoryFact @('freshness'))
        if ($freshness -ne 'fresh') { Add-MetadataFinding 'host_inventory_not_fresh' '$.observed_inventory.freshness' 'Observed host inventory must be fresh.' }
        $expectedNames = @((Get-ObjectProperty $receipt @('after')) | ForEach-Object {
                $directory = [string](Get-ObjectProperty $_ @('directory_path'))
                if (-not [string]::IsNullOrWhiteSpace($directory)) {
                    $leaf = [IO.Path]::GetFileName($directory.TrimEnd('\', '/'))
                    $skillFile = Join-Path $directory 'SKILL.md'
                    if (Test-Path -LiteralPath $skillFile -PathType Leaf) {
                        $nameLine = @(Get-Content -LiteralPath $skillFile -Encoding UTF8 | Where-Object { $_ -match '^\s*name:\s*(?<name>[^#]+?)\s*$' } | Select-Object -First 1)
                        if ($nameLine.Count -eq 1) {
                            $nameMatch = [regex]::Match([string]$nameLine[0], '^\s*name:\s*(?<name>[^#]+?)\s*$')
                            $frontmatterName = $nameMatch.Groups['name'].Value.Trim().Trim('"', "'")
                            if (-not [string]::IsNullOrWhiteSpace($frontmatterName)) { $frontmatterName; return }
                        }
                    }
                    $leaf
                }
            } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        if ($expectedNames.Count -eq 0) { Add-MetadataFinding 'projection_receipt_expected_skills_missing' '$.observed_inventory.expected' 'Projection receipt does not contain expected projected skills.' }

        $inventoryByName = @{}
        foreach ($row in @($inventoryRows)) {
            $name = ([string](Get-ObjectProperty $row @('name', 'id', 'skill'))).Trim()
            if ([string]::IsNullOrWhiteSpace($name)) { Add-MetadataFinding 'host_inventory_name_missing' '$.observed_inventory.entries' 'Observed host inventory entry has no name.'; continue }
            if ($inventoryByName.ContainsKey($name)) { Add-MetadataFinding 'host_inventory_name_duplicate' '$.observed_inventory.entries' ('Observed host inventory contains duplicate skill: {0}' -f $name); continue }
            $inventoryByName[$name] = $row
        }

        $matched = [Collections.Generic.List[object]]::new()
        $missing = [Collections.Generic.List[string]]::new()
        foreach ($name in $expectedNames) {
            if (-not $inventoryByName.ContainsKey($name)) {
                $missing.Add($name) | Out-Null
                Add-MetadataFinding 'host_inventory_expected_skill_missing' '$.observed_inventory.missing_names' ('Expected projected skill is absent from observed host inventory: {0}' -f $name)
                continue
            }
            $row = $inventoryByName[$name]
            $description = [string](Get-ObjectProperty $row @('description', 'summary'))
            if ([string]::IsNullOrWhiteSpace($description)) { Add-MetadataFinding 'host_inventory_description_missing' '$.observed_inventory.entries' ('Observed host description is missing: {0}' -f $name) }
            $matched.Add([pscustomobject][ordered]@{
                    name = $name
                    observed_host_description = $description
                    character_count = $description.Length
                    enabled = if ($null -ne (Get-ObjectProperty $row @('enabled'))) { [bool](Get-ObjectProperty $row @('enabled')) } else { $true }
                }) | Out-Null
        }
        $lengths = @($matched.ToArray() | ForEach-Object { [int]$_.character_count })
        $sum = if ($lengths.Count -gt 0) { [int64](($lengths | Measure-Object -Sum).Sum) } else { 0L }
        $maximum = if ($lengths.Count -gt 0) { [int](($lengths | Measure-Object -Maximum).Maximum) } else { 0 }
        $average = if ($lengths.Count -gt 0) { [Math]::Round([double](($lengths | Measure-Object -Average).Average), 2) } else { $null }
        $budgetFact = Get-ObjectProperty (Get-ObjectProperty $snapshot @('capabilities')) @('metadata_budget')
        $budgetValue = Get-ObjectProperty $budgetFact @('value')
        $budgetFreshness = [string](Get-ObjectProperty $budgetFact @('freshness'))
        $budgetSource = [string](Get-ObjectProperty $budgetFact @('source'))

        $observedInventory.source = $hostFile
        $observedInventory.projection_receipt = $receiptFile
        $observedInventory.snapshot_id = [string](Get-ObjectProperty $snapshot @('snapshot_id'))
        $observedInventory.captured_at = Get-ObjectProperty $snapshot @('captured_at')
        $observedInventory.freshness = $freshness
        $observedInventory.observed_total = $inventoryByName.Count
        $observedInventory.expected_total = $expectedNames.Count
        $observedInventory.matched_total = $matched.Count
        $observedInventory.missing_total = $missing.Count
        $observedInventory.unexpected_total = [Math]::Max(0, $inventoryByName.Count - $matched.Count)
        $observedInventory.missing_names = [object[]]@($missing.ToArray())
        $observedInventory.entries = [object[]]@($matched.ToArray())
        $observedInventory.description_metrics.measured_total = $matched.Count
        $observedInventory.description_metrics.total_characters = $sum
        $observedInventory.description_metrics.maximum_characters = $maximum
        $observedInventory.description_metrics.average_characters = $average
        $observedInventory.description_metrics.advisory_limit_characters = $maxDescription
        $observedInventory.description_metrics.over_advisory_limit_total = @($matched.ToArray() | Where-Object { [int]$_.character_count -gt $maxDescription }).Count
        $observedInventory.budget.value = $budgetValue
        $observedInventory.budget.source = if ([string]::IsNullOrWhiteSpace($budgetSource)) { 'unknown_fallback' } else { $budgetSource }
        $observedInventory.budget.freshness = if ([string]::IsNullOrWhiteSpace($budgetFreshness)) { 'unknown' } else { $budgetFreshness }
        $observedInventory.budget.host_budget_status = if ($budgetFreshness -eq 'fresh' -and $null -ne $budgetValue) { 'observed_not_comparable' } else { 'unknown' }
        $observedInventory.budget.host_budget_pass = $null
        $observedInventory.status = if ($findings.Count -eq $hostFindingStart) { 'verified' } else { 'incomplete' }
    }
    catch {
        Add-MetadataFinding 'host_inventory_input_invalid' '$.observed_inventory' $_.Exception.Message
        $observedInventory.status = 'invalid'
    }
}

$report = [ordered]@{
    schema_version = 2
    verifier_id = 'native-skill-metadata'
    pass = ($findings.Count -eq 0)
    decision_owner = 'host_ai'
    semantic_selection_applied = $false
    repository_samples = [ordered]@{
        projection_effect = 'plan_only'
        materialization_asserted = $false
        target_count = @($metadataResults).Count
        valid_count = @($metadataResults).Count
        max_description_characters = if ($null -ne $corpus) { [int]$corpus.metadata_limits.max_description_characters } else { 0 }
        formerly_unreachable_skill_count = @($metadataResults | Where-Object formerly_unreachable).Count
        entries = [object[]]@($metadataResults)
    }
    observed_inventory = $observedInventory
    corpus = [ordered]@{
        evaluation_id = if ($null -ne $corpus) { [string]$corpus.evaluation_id } else { '' }
        case_count = if ($null -ne $corpus) { @($corpus.cases).Count } else { 0 }
        categories = if ($null -ne $corpus) { [string[]]@(Get-StringArray $corpus.categories) } else { [string[]]@() }
        formerly_unreachable_skill_count = if ($null -ne $corpus) { [int]$corpus.formerly_unreachable_skill_count } else { 0 }
        metrics = if ($null -ne $corpus) { $corpus.metrics } else { $null }
        cases = if ($null -ne $corpus) { [object[]]@($corpus.cases) } else { [object[]]@() }
        pairwise = [ordered]@{
            target_count = @($pairwiseTargets).Count
            group_count = @($pairwiseGroups).Count
            case_count = $pairwiseCaseCount
            dimensions = [string[]]@($pairwiseDimensions)
            coverage = [pscustomobject]$pairwiseCoverage
            groups = [object[]]@($pairwiseGroups)
        }
    }
    failure_taxonomy = [ordered]@{
        repository_samples = @('metadata_source_missing', 'metadata_description_too_short', 'metadata_description_too_long', 'metadata_trigger_overlap', 'metadata_trigger_not_observable')
        corpus = @('case_category_invalid', 'negative_case_invalid', 'ambiguous_case_invalid', 'no_skill_case_invalid')
        host_inventory = @('host_inventory_input_pair_required', 'host_inventory_not_fresh', 'projection_receipt_expected_skills_missing', 'host_inventory_expected_skill_missing', 'host_inventory_description_missing')
        pairwise = @('pairwise_dimension_missing', 'pairwise_dimension_uncovered', 'pairwise_target_duplicate', 'pairwise_target_count_invalid', 'pairwise_group_invalid', 'pairwise_group_too_small', 'pairwise_group_target_unknown', 'pairwise_group_count_invalid', 'pairwise_case_group_unknown', 'pairwise_case_dimensions_missing', 'pairwise_case_dimension_unknown', 'pairwise_case_count_invalid')
        host_evaluation = @('host_selection_not_observable', 'full_body_invocation_not_observable')
    }
    provider_calls = 0
    native_mutations = 0
    writes = 0
    finding_count = $findings.Count
    findings = [object[]]@($findings.ToArray())
}

if ($Json) { $report | ConvertTo-Json -Depth 20 }
else {
    if ($report.pass) { Write-Host ('Native skill metadata verification passed: samples={0}, cases={1}, host_inventory={2}' -f $report.repository_samples.target_count, $report.corpus.case_count, $report.observed_inventory.status) -ForegroundColor Green }
    else { foreach ($finding in @($report.findings)) { Write-Host ('[{0}] {1}: {2}' -f $finding.code, $finding.path, $finding.message) -ForegroundColor Red }; Write-Host ('Native skill metadata verification failed: findings={0}' -f $report.finding_count) -ForegroundColor Red }
}

if (-not $report.pass) { exit 1 }
exit 0
