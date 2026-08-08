[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$CorpusPath = 'config/native-skill-activation-corpus.json',
    [string]$MetadataPath = '',
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

if ($null -ne $corpus) {
    if ([int]$corpus.schema_version -ne 1) { Add-MetadataFinding 'schema_version_invalid' '$.schema_version' 'Native metadata corpus schema_version must be 1.' }
    if ([string]$corpus.decision_owner -ne 'host_ai') { Add-MetadataFinding 'decision_owner_invalid' '$.decision_owner' 'Semantic selection ownership must remain host_ai.' }
    if ($corpus.semantic_selection_applied -ne $false) { Add-MetadataFinding 'semantic_selection_forbidden' '$.semantic_selection_applied' 'The corpus cannot apply semantic selection.' }
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
            $metadataResults.Add([pscustomobject][ordered]@{ name = $targetName; source = $sourcePath; field = [string]$target.field; description = $description; character_count = $length; formerly_unreachable = [bool]$target.formerly_unreachable }) | Out-Null
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
    foreach ($category in $requiredCategories) { if (-not $caseCategories.ContainsKey($category)) { Add-MetadataFinding 'category_case_missing' '$.cases' ('No cases exist for category: {0}' -f $category) } }
}

$report = [ordered]@{
    schema_version = 1
    verifier_id = 'native-skill-metadata'
    pass = ($findings.Count -eq 0)
    decision_owner = 'host_ai'
    semantic_selection_applied = $false
    metadata = [ordered]@{
        target_count = @($metadataResults).Count
        valid_count = @($metadataResults).Count
        max_description_characters = if ($null -ne $corpus) { [int]$corpus.metadata_limits.max_description_characters } else { 0 }
        formerly_unreachable_skill_count = @($metadataResults | Where-Object formerly_unreachable).Count
        entries = [object[]]@($metadataResults)
    }
    corpus = [ordered]@{
        evaluation_id = if ($null -ne $corpus) { [string]$corpus.evaluation_id } else { '' }
        case_count = if ($null -ne $corpus) { @($corpus.cases).Count } else { 0 }
        categories = if ($null -ne $corpus) { [string[]]@(Get-StringArray $corpus.categories) } else { [string[]]@() }
        formerly_unreachable_skill_count = if ($null -ne $corpus) { [int]$corpus.formerly_unreachable_skill_count } else { 0 }
        metrics = if ($null -ne $corpus) { $corpus.metrics } else { $null }
        cases = if ($null -ne $corpus) { [object[]]@($corpus.cases) } else { [object[]]@() }
    }
    failure_taxonomy = [ordered]@{
        metadata = @('metadata_source_missing', 'metadata_description_too_short', 'metadata_description_too_long', 'metadata_trigger_overlap', 'metadata_trigger_not_observable')
        corpus = @('case_category_invalid', 'negative_case_invalid', 'ambiguous_case_invalid', 'no_skill_case_invalid')
        host = @('host_selection_not_observable', 'full_body_invocation_not_observable')
    }
    provider_calls = 0
    native_mutations = 0
    writes = 0
    finding_count = $findings.Count
    findings = [object[]]@($findings.ToArray())
}

if ($Json) { $report | ConvertTo-Json -Depth 20 }
else {
    if ($report.pass) { Write-Host ('Native skill metadata verification passed: targets={0}, cases={1}' -f $report.metadata.target_count, $report.corpus.case_count) -ForegroundColor Green }
    else { foreach ($finding in @($report.findings)) { Write-Host ('[{0}] {1}: {2}' -f $finding.code, $finding.path, $finding.message) -ForegroundColor Red }; Write-Host ('Native skill metadata verification failed: findings={0}' -f $report.finding_count) -ForegroundColor Red }
}

if (-not $report.pass) { exit 1 }
exit 0
