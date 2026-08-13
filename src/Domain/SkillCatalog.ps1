if ($null -eq (Get-Command Get-OperationObjectProperty -ErrorAction SilentlyContinue)) {
    $operationPlanPath = Join-Path (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path 'src\Domain\OperationPlan.ps1'
    . $operationPlanPath
}

function Get-SkillCatalogProperty {
    param($Object, [string[]]$Names)

    foreach ($name in @($Names)) {
        if (Test-OperationObjectProperty $Object $name) { return Get-OperationObjectProperty $Object $name }
    }
    return $null
}

function Get-SkillCatalogStringArray {
    param($Value)

    $items = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Value)) {
        $text = ([string]$item).Trim()
        if (-not [string]::IsNullOrWhiteSpace($text) -and -not $items.Contains($text)) { $items.Add($text) | Out-Null }
    }
    return [string[]]@($items.ToArray() | Sort-Object)
}

function Get-SkillCatalogForbiddenSemanticFieldNames {
    return @(
        'semantic_score', 'semantic_rank', 'semantic_confidence', 'query_match',
        'selected_by_router', 'router_selected', 'ranking', 'rank', 'confidence'
    )
}

function New-SkillCatalogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Description,
        [string]$Path = '',
        [string]$SourceRoot = '',
        [string]$ContentHash = '',
        [string]$MetadataHash = '',
        [bool]$Enabled = $true,
        [string]$Availability = 'available',
        [ValidateSet('fresh', 'stale', 'unknown')][string]$Freshness = 'fresh',
        [string]$LoadSideEffect = 'read_only',
        [string]$SideEffect = 'read_only',
        [string[]]$Dependencies = @(),
        [string[]]$Surfaces = @(),
        $Provenance = $null
    )

    return [pscustomobject][ordered]@{
        schema_version = 1
        kind = 'skill'
        name = $Name.Trim()
        description = $Description.Trim()
        path = $Path
        source_root = $SourceRoot
        content_hash = if ([string]::IsNullOrWhiteSpace($ContentHash)) { $null } else { $ContentHash.Trim().ToLowerInvariant() }
        metadata_hash = if ([string]::IsNullOrWhiteSpace($MetadataHash)) { $null } else { $MetadataHash.Trim().ToLowerInvariant() }
        enabled = $Enabled
        availability = $Availability.Trim()
        freshness = $Freshness
        load_side_effect = $LoadSideEffect.Trim()
        side_effect = $SideEffect.Trim()
        dependencies = Get-SkillCatalogStringArray $Dependencies
        surfaces = Get-SkillCatalogStringArray $Surfaces
        provenance = $Provenance
    }
}

function New-SkillCatalog {
    [CmdletBinding()]
    param(
        [object[]]$Entries = @(),
        [object[]]$Decisions = @(),
        [Parameter(Mandatory = $true)][string]$GeneratedAt,
        [string[]]$SourceRoots = @(),
        [bool]$Complete = $true,
        [object[]]$Findings = @()
    )

    $normalizedEntries = @($Entries | Sort-Object @{ Expression = { ([string]$_.name).ToLowerInvariant() } }, path)
    $identity = [ordered]@{
        schema_version = 1
        generated_at = $GeneratedAt
        source_roots = @(Get-SkillCatalogStringArray $SourceRoots)
        entries = @($normalizedEntries | ForEach-Object { [ordered]@{ name = [string]$_.name; path = [string]$_.path; content_hash = [string]$_.content_hash } })
    }
    $catalogId = 'sc-{0}' -f (Get-OperationSha256 ($identity | ConvertTo-Json -Depth 30 -Compress)).Substring(0, 16)
    return [pscustomobject][ordered]@{
        schema_version = 1
        catalog_id = $catalogId
        generated_at = $GeneratedAt
        source_roots = [string[]]@(Get-SkillCatalogStringArray $SourceRoots)
        entries = [object[]]$normalizedEntries
        decisions = [object[]]@($Decisions)
        findings = [object[]]@($Findings)
        complete = $Complete
        semantic_selection_applied = $false
        semantic_routing_performed = $false
        decision_owner = 'host_ai'
        provider_calls = 0
        native_mutations = 0
        writes = 0
    }
}

function Test-SkillCatalogContract {
    param($Catalog)

    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Catalog) { return New-OperationValidationResult @((New-OperationFinding 'skill_catalog_missing' 'error' '$' 'Skill catalog is required.')) }
    if ((Get-SkillCatalogProperty $Catalog @('schema_version')) -ne 1) { $findings.Add((New-OperationFinding 'schema_version_invalid' 'error' '$.schema_version' 'Only SkillCatalog schema version 1 is supported.')) | Out-Null }
    foreach ($field in @('catalog_id', 'generated_at', 'decision_owner')) {
        if ([string]::IsNullOrWhiteSpace([string](Get-SkillCatalogProperty $Catalog @($field)))) { $findings.Add((New-OperationFinding 'required_field_missing' 'error' ('$.{0}' -f $field) 'Required catalog field is missing.')) | Out-Null }
    }
    if ([string](Get-SkillCatalogProperty $Catalog @('catalog_id')) -notmatch '^sc-[a-f0-9]{16}$') { $findings.Add((New-OperationFinding 'catalog_id_invalid' 'error' '$.catalog_id' 'Catalog id must be deterministic.')) | Out-Null }
    if (-not (Test-OperationRfc3339 (Get-SkillCatalogProperty $Catalog @('generated_at')))) { $findings.Add((New-OperationFinding 'generated_at_invalid' 'error' '$.generated_at' 'Catalog generated_at must be RFC3339.')) | Out-Null }
    if ([string](Get-SkillCatalogProperty $Catalog @('decision_owner')) -ne 'host_ai') { $findings.Add((New-OperationFinding 'decision_owner_invalid' 'error' '$.decision_owner' 'Semantic decision ownership must remain host_ai.')) | Out-Null }
    foreach ($field in @('semantic_selection_applied', 'semantic_routing_performed')) {
        if ((Get-SkillCatalogProperty $Catalog @($field)) -ne $false) { $findings.Add((New-OperationFinding 'semantic_boundary_breached' 'error' ('$.{0}' -f $field) 'Catalog core cannot apply semantic selection.')) | Out-Null }
    }
    foreach ($field in @('provider_calls', 'native_mutations', 'writes')) {
        if ([long](Get-SkillCatalogProperty $Catalog @($field)) -ne 0) { $findings.Add((New-OperationFinding 'side_effect_forbidden' 'error' ('$.{0}' -f $field) 'Catalog compilation must be zero-side-effect.')) | Out-Null }
    }
    if (-not (Test-OperationArray (Get-SkillCatalogProperty $Catalog @('entries')))) { $findings.Add((New-OperationFinding 'entries_type_invalid' 'error' '$.entries' 'Catalog entries must be an array.')) | Out-Null }
    if (-not (Test-OperationArray (Get-SkillCatalogProperty $Catalog @('decisions')))) { $findings.Add((New-OperationFinding 'decisions_type_invalid' 'error' '$.decisions' 'Catalog decisions must be an array.')) | Out-Null }
    $forbidden = @(Get-SkillCatalogForbiddenSemanticFieldNames | ForEach-Object { $_.ToLowerInvariant() })
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $index = 0
    foreach ($entry in @((Get-SkillCatalogProperty $Catalog @('entries')))) {
        $path = '$.entries[{0}]' -f $index
        $name = [string](Get-SkillCatalogProperty $entry @('name'))
        if ([string]::IsNullOrWhiteSpace($name) -or -not $seen.Add($name)) { $findings.Add((New-OperationFinding 'entry_identity_invalid' 'error' ($path + '.name') 'Catalog entry name is missing or duplicated.')) | Out-Null }
        foreach ($field in @('description', 'availability', 'freshness', 'load_side_effect', 'side_effect')) {
            if ([string]::IsNullOrWhiteSpace([string](Get-SkillCatalogProperty $entry @($field)))) { $findings.Add((New-OperationFinding 'entry_field_missing' 'error' ($path + '.' + $field) 'Catalog entry field is required.')) | Out-Null }
        }
        if ((Get-SkillCatalogProperty $entry @('kind')) -ne 'skill') { $findings.Add((New-OperationFinding 'entry_kind_invalid' 'error' ($path + '.kind') 'SkillCatalog entries must have kind=skill.')) | Out-Null }
        if ((Get-SkillCatalogProperty $entry @('enabled')) -isnot [bool]) { $findings.Add((New-OperationFinding 'entry_enabled_invalid' 'error' ($path + '.enabled') 'Catalog entry enabled must be boolean.')) | Out-Null }
        if ([string](Get-SkillCatalogProperty $entry @('freshness')) -notin @('fresh', 'stale', 'unknown')) { $findings.Add((New-OperationFinding 'entry_freshness_invalid' 'error' ($path + '.freshness') 'Catalog entry freshness is invalid.')) | Out-Null }
        foreach ($property in @($entry.PSObject.Properties)) {
            if ($forbidden -contains $property.Name.ToLowerInvariant()) { $findings.Add((New-OperationFinding 'semantic_field_forbidden' 'error' ($path + '.' + $property.Name) 'Semantic ranking/profile fields cannot enter the catalog core.')) | Out-Null }
        }
        $index++
    }
    foreach ($decision in @((Get-SkillCatalogProperty $Catalog @('decisions')))) {
    }
    return New-OperationValidationResult $findings.ToArray()
}
