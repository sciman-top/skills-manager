[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Query,
    [string]$CatalogPath = '',
    [string]$ManifestPath = '',
    [string]$PolicyPath = '',
    [string]$ConfigPath = '',
    [string]$CapabilitySnapshotPath = '',
    [string]$HostSnapshotPath = '',
    [string]$SessionSnapshotPath = '',
    [ValidateRange(1, 10080)][int]$MaxSnapshotAgeMinutes = 60,
    [string[]]$SkillRoot = @(),
    [string[]]$DomainHint = @(),
    [string[]]$ProfileHint = @(),
    [Alias('SelectedCapability')][string[]]$Candidate = @(),
    [string[]]$ExcludeCapability = @(),
    [ValidateRange(1, 100)][int]$MaxCandidates = 24,
    [hashtable]$MetadataCache = $null
)

$ErrorActionPreference = 'Stop'

function Resolve-ExistingFile([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if ($expanded.StartsWith('~/') -or $expanded.StartsWith('~\')) { $expanded = Join-Path $HOME $expanded.Substring(2) }
    if (Test-Path -LiteralPath $expanded -PathType Leaf) { return [IO.Path]::GetFullPath($expanded) }
    return ''
}

function Find-Catalog {
    $explicit = Resolve-ExistingFile $CatalogPath
    if ($explicit) { return $explicit }
    $fromEnv = Resolve-ExistingFile $env:SKILLS_MANAGER_CAPABILITY_CATALOG
    if ($fromEnv) { return $fromEnv }
    return (Resolve-ExistingFile (Join-Path (Split-Path $PSScriptRoot -Parent) 'catalog.json'))
}

function Find-Manifest {
    $explicit = Resolve-ExistingFile $ManifestPath
    if ($explicit) { return $explicit }
    $fromEnv = Resolve-ExistingFile $env:SKILLS_MANAGER_PROJECTION_MANIFEST
    if ($fromEnv) { return $fromEnv }
    if ($catalogFile) { return '' }
    foreach ($start in @($PSScriptRoot, (Get-Location).Path)) {
        $cursor = [IO.DirectoryInfo]::new([IO.Path]::GetFullPath($start))
        while ($null -ne $cursor) {
            $candidatePath = Join-Path $cursor.FullName 'reports\skill-projection\current.json'
            if (Test-Path -LiteralPath $candidatePath -PathType Leaf) { return $candidatePath }
            $cursor = $cursor.Parent
        }
    }
    return ''
}

function Test-Contained([string]$Path, [string]$Root) {
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)
}

function Read-SkillMetadata([string]$Path, [string]$Root, [bool]$Active) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or -not (Test-Contained $Path $Root)) { return $null }
    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root)
    $file = Get-Item -LiteralPath $fullPath
    $cacheKey = '{0}|{1}|{2}|{3}' -f $fullPath, $fullRoot, $file.Length, $file.LastWriteTimeUtc.Ticks
    $metadata = if ($null -ne $MetadataCache -and $MetadataCache.ContainsKey($cacheKey)) {
        $MetadataCache[$cacheKey]
    }
    else {
        $text = Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8
        $frontmatter = [regex]::Match($text, '(?s)\A---\s*\r?\n(?<yaml>.*?)\r?\n---')
        if (-not $frontmatter.Success) { return $null }
        $yaml = $frontmatter.Groups['yaml'].Value
        $nameMatch = [regex]::Match($yaml, '(?m)^name:\s*["'']?(?<value>[^\r\n"'']+)')
        $descriptionMatch = [regex]::Match($yaml, '(?m)^description:\s*["'']?(?<value>[^\r\n]+)')
        if (-not $nameMatch.Success -or -not $descriptionMatch.Success) { return $null }
        $parsed = [pscustomobject]@{
            name = $nameMatch.Groups['value'].Value.Trim()
            description = $descriptionMatch.Groups['value'].Value.Trim().Trim('"', "'")
        }
        if ($null -ne $MetadataCache) { $MetadataCache[$cacheKey] = $parsed }
        $parsed
    }
    return [pscustomobject]@{
        kind = 'skill'
        name = [string]$metadata.name
        description = [string]$metadata.description
        path = $fullPath
        source_root = $fullRoot
        active = $Active
        availability = if ($Active) { 'available' } else { 'cold_load' }
        load_side_effect = 'read_only'
        side_effect = 'unknown'
    }
}

function Get-StringArray($Value) {
    $result = [Collections.Generic.List[string]]::new()
    foreach ($item in @($Value)) {
        $text = ([string]$item).Trim()
        if (-not [string]::IsNullOrWhiteSpace($text) -and -not $result.Contains($text)) { $result.Add($text) | Out-Null }
    }
    return @($result.ToArray())
}

function Get-ProfileHintArray($Value) {
    $result = [Collections.Generic.List[string]]::new()
    foreach ($item in @($Value)) {
        foreach ($part in @(([string]$item) -split ',')) {
            $text = $part.Trim()
            if (-not [string]::IsNullOrWhiteSpace($text) -and -not $result.Contains($text)) {
                $result.Add($text) | Out-Null
                if ($result.Count -eq 2) { return @($result.ToArray()) }
            }
        }
    }
    return @($result.ToArray())
}

function Get-CapabilityReference([string]$Text) {
    $value = $Text.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    $match = [regex]::Match($value, '^(?<kind>skill|mcp|plugin|app|connector|native_tool|tool)[|/](?<name>.+)$', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
        return [pscustomobject]@{ kind = $match.Groups['kind'].Value.ToLowerInvariant(); name = $match.Groups['name'].Value.Trim() }
    }
    return [pscustomobject]@{ kind = ''; name = $value }
}

function Get-Key([string]$Kind, [string]$Name) { return ('{0}|{1}' -f $Kind.ToLowerInvariant(), $Name.ToLowerInvariant()) }

$catalogFile = Find-Catalog
$catalog = if ($catalogFile) { Get-Content -LiteralPath $catalogFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
if ($null -ne $catalog -and [int]$catalog.schema_version -ne 1) { throw "unsupported capability catalog schema_version: $($catalog.schema_version)" }
$catalogSkillRoot = if ($catalogFile) { [IO.Path]::GetFullPath((Split-Path (Split-Path $catalogFile -Parent) -Parent)) } else { '' }
$manifestFile = Find-Manifest
$manifest = if ($manifestFile) { Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$repoRoot = ''
if ($manifestFile) { $repoRoot = Split-Path (Split-Path (Split-Path $manifestFile -Parent) -Parent) -Parent }

$policyFile = Resolve-ExistingFile $PolicyPath
if (-not $policyFile -and $repoRoot) { $policyFile = Resolve-ExistingFile (Join-Path $repoRoot 'config\skill-routing-policy.json') }
$configFile = Resolve-ExistingFile $ConfigPath
if (-not $configFile -and $repoRoot) { $configFile = Resolve-ExistingFile (Join-Path $repoRoot 'skills.json') }
$snapshotFile = Resolve-ExistingFile $(if ([string]::IsNullOrWhiteSpace($HostSnapshotPath)) { $CapabilitySnapshotPath } else { $HostSnapshotPath })
$sessionFile = Resolve-ExistingFile $SessionSnapshotPath

$policy = if ($policyFile) { Get-Content -LiteralPath $policyFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$config = if ($configFile) { Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }

$routing = @{}
function Add-RoutingRule([string]$Kind, [string]$Name, $Rule) {
    if ([string]::IsNullOrWhiteSpace($Name) -or $null -eq $Rule) { return }
    $key = Get-Key $Kind $Name
    if (-not $routing.ContainsKey($key)) { $routing[$key] = [Collections.Generic.List[object]]::new() }
    $routing[$key].Add([pscustomobject]@{
            activation = [string]$Rule.activation
            negative_activation = [string]$Rule.negative_activation
            role = [string]$Rule.role
            group = [string]$Rule.group
            context = [string]$Rule.context
        }) | Out-Null
}
if ($null -ne $policy) {
    foreach ($group in @($policy.groups)) {
        foreach ($member in @($group.members)) {
            Add-RoutingRule 'skill' ([string]$member.name) ([pscustomobject]@{
                activation = [string]$member.activation
                negative_activation = [string]$member.negative_activation
                role = [string]$member.role
                group = [string]$group.id
                context = ('{0} {1}' -f [string]$group.purpose, [string]$group.selection_policy).Trim()
            })
        }
    }
}
if ($null -ne $catalog) {
    foreach ($skill in @($catalog.skills)) {
        foreach ($rule in @($skill.routing_rules)) { Add-RoutingRule 'skill' ([string]$skill.name) $rule }
    }
}

$entries = [Collections.Generic.List[object]]::new()
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$activeNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
if ($null -ne $catalog) {
    foreach ($item in @($catalog.skills)) {
        $relativePath = [string]$item.relative_path
        if ([string]::IsNullOrWhiteSpace($relativePath) -or [IO.Path]::IsPathRooted($relativePath)) { continue }
        $skillPath = [IO.Path]::GetFullPath((Join-Path (Split-Path $catalogFile -Parent) $relativePath))
        $entry = Read-SkillMetadata $skillPath $catalogSkillRoot $false
        if ($null -eq $entry -or -not [string]::Equals([string]$entry.name, [string]$item.name, [StringComparison]::OrdinalIgnoreCase)) { continue }
        if (-not [string]::IsNullOrWhiteSpace([string]$item.description)) { $entry.description = [string]$item.description }
        $entry | Add-Member -NotePropertyName load_side_effect -NotePropertyValue $(if ([string]::IsNullOrWhiteSpace([string]$item.load_side_effect)) { 'read_only' } else { [string]$item.load_side_effect }) -Force
        if ($entry.name -ne 'capability-router' -and $seen.Add((Get-Key 'skill' $entry.name))) { $entries.Add($entry) }
    }
}
elseif ($null -ne $manifest) {
    foreach ($name in @($manifest.active | ForEach-Object name)) { $activeNames.Add([string]$name) | Out-Null }
    foreach ($item in @($manifest.canonical)) {
        $entry = Read-SkillMetadata ([string]$item.path) ([string]$item.source_root) ($activeNames.Contains([string]$item.name))
        if ($null -ne $entry -and $entry.name -ne 'capability-router' -and $seen.Add((Get-Key 'skill' $entry.name))) { $entries.Add($entry) }
    }
}
else {
    $roots = [Collections.Generic.List[string]]::new()
    foreach ($root in @($SkillRoot + @((Join-Path $HOME '.agents\skills'), (Join-Path $HOME '.codex\skills')))) {
        if (-not [string]::IsNullOrWhiteSpace($root) -and (Test-Path -LiteralPath $root -PathType Container)) { $roots.Add([IO.Path]::GetFullPath($root)) }
    }
    foreach ($root in $roots) {
        foreach ($file in @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'SKILL.md' } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })) {
            $entry = Read-SkillMetadata $file $root $false
            if ($null -ne $entry -and $entry.name -ne 'capability-router' -and $seen.Add((Get-Key 'skill' $entry.name))) { $entries.Add($entry) }
        }
    }
}

$mcpEnabled = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$currentMcpProfile = ''
if ($null -ne $config -and $config.PSObject.Properties.Match('mcp_profiles').Count -gt 0 -and $null -ne $config.mcp_profiles) {
    $currentMcpProfile = [string]$config.mcp_profiles.active
    $profileProperty = @($config.mcp_profiles.profiles.PSObject.Properties | Where-Object { $_.Name -eq $currentMcpProfile } | Select-Object -First 1)
    if ($profileProperty.Count -eq 1) { foreach ($name in @($profileProperty[0].Value.enabled)) { $mcpEnabled.Add([string]$name) | Out-Null } }
}

$declaredCapabilities = if ($null -ne $catalog) { @($catalog.capabilities) } elseif ($null -ne $policy) { @($policy.capabilities) } else { @() }
foreach ($capability in $declaredCapabilities) {
        $kind = ([string]$capability.kind).Trim().ToLowerInvariant()
        $name = ([string]$capability.name).Trim()
        if ([string]::IsNullOrWhiteSpace($kind) -or [string]::IsNullOrWhiteSpace($name)) { continue }
        $key = Get-Key $kind $name
        if (-not $seen.Add($key)) { continue }
        $available = if ($kind -eq 'mcp') { $mcpEnabled.Contains($name) } else { [bool]$capability.available }
        $entries.Add([pscustomobject]@{
            kind = $kind; name = $name; description = [string]$capability.description; path = ''; source_root = ''
            active = $available; availability = if ($available) { 'available' } else { 'needs_activation' }
            side_effect = if ([string]::IsNullOrWhiteSpace([string]$capability.side_effect)) { 'unknown' } else { [string]$capability.side_effect }
        })
        Add-RoutingRule $kind $name ([pscustomobject]@{
            activation = [string]$capability.activation; negative_activation = [string]$capability.negative_activation
            role = 'capability'; group = 'unified-capabilities'; context = 'Declared host capability; the host model decides relevance.'
        })
}

$entryByKey = @{}
foreach ($entry in $entries) { $entryByKey[(Get-Key ([string]$entry.kind) ([string]$entry.name))] = $entry }

$snapshotStatus = 'not_provided'
$snapshotSource = ''
$snapshotCapturedAt = $null
$excludedResults = [Collections.Generic.List[object]]::new()
if ($snapshotFile) {
    $snapshot = Get-Content -LiteralPath $snapshotFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $snapshotItems = if ($snapshot.PSObject.Properties.Match('capabilities').Count -gt 0) { @($snapshot.capabilities) } else { @($snapshot) }
    $snapshotSource = if ($snapshot.PSObject.Properties.Match('source').Count -gt 0) { [string]$snapshot.source } else { 'caller-provided' }
    $snapshotStatus = 'current'
    if ($snapshot.PSObject.Properties.Match('captured_at').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$snapshot.captured_at)) {
        $snapshotCapturedAt = [DateTimeOffset]::Parse([string]$snapshot.captured_at)
        if (([DateTimeOffset]::UtcNow - $snapshotCapturedAt).TotalMinutes -gt $MaxSnapshotAgeMinutes) { $snapshotStatus = 'stale' }
    }
    foreach ($capability in $snapshotItems) {
        $kind = ([string]$capability.kind).Trim().ToLowerInvariant()
        $name = ([string]$capability.name).Trim()
        if ($kind -notin @('skill', 'mcp', 'plugin', 'app', 'connector', 'native_tool', 'tool') -or [string]::IsNullOrWhiteSpace($name)) { continue }
        if ($snapshotStatus -eq 'stale') {
            $excludedResults.Add([pscustomobject]@{ kind = $kind; name = $name; reason = 'stale_snapshot' }) | Out-Null
            continue
        }
        $key = Get-Key $kind $name
        $availability = if ([string]::IsNullOrWhiteSpace([string]$capability.availability)) { 'unknown' } else { [string]$capability.availability }
        if ($capability.PSObject.Properties.Match('callable').Count -gt 0 -and -not [bool]$capability.callable) { $availability = 'not_callable' }
        if ($capability.PSObject.Properties.Match('accessible').Count -gt 0 -and -not [bool]$capability.accessible) { $availability = 'inaccessible' }
        if ($entryByKey.ContainsKey($key)) {
            $existing = $entryByKey[$key]
            if (-not [string]::IsNullOrWhiteSpace([string]$capability.description)) { $existing.description = [string]$capability.description }
            if (-not [string]::IsNullOrWhiteSpace([string]$capability.side_effect)) { $existing.side_effect = [string]$capability.side_effect }
            $existing.availability = $availability
            $existing.active = ($availability -eq 'available')
            continue
        }
        $entry = [pscustomobject]@{
            kind = $kind; name = $name; description = [string]$capability.description; path = ''; source_root = ''
            active = ($availability -eq 'available'); availability = $availability
            side_effect = if ([string]::IsNullOrWhiteSpace([string]$capability.side_effect)) { 'unknown' } else { [string]$capability.side_effect }
        }
        $entries.Add($entry)
        $seen.Add($key) | Out-Null
        $entryByKey[$key] = $entry
        Add-RoutingRule $kind $name ([pscustomobject]@{
            activation = [string]$capability.activation; negative_activation = [string]$capability.negative_activation
            role = 'external'; group = 'runtime-snapshot'; context = 'Caller-provided current runtime capability snapshot.'
        })
    }
}

$profiles = @{}
$profileCatalog = [Collections.Generic.List[object]]::new()
$currentProfile = if ($null -ne $manifest) { [string]$manifest.active_profile } elseif ($null -ne $config) { [string]$config.skill_projection.active_profile } else { '' }
if ($null -ne $catalog) {
    foreach ($domain in @($catalog.domains)) {
        $set = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($name in @(Get-StringArray $domain.skill_names)) { $set.Add($name) | Out-Null }
        $profiles[[string]$domain.name] = $set
        $profileCatalog.Add([pscustomobject]@{ name = [string]$domain.name; purpose = [string]$domain.purpose; enabled_name_count = $set.Count; active = $false }) | Out-Null
    }
}
elseif ($null -ne $config -and $config.PSObject.Properties.Match('skill_projection').Count -gt 0 -and $null -ne $config.skill_projection.profiles) {
    foreach ($property in @($config.skill_projection.profiles.PSObject.Properties)) {
        $names = @(Get-StringArray $property.Value.enabled_names)
        $set = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($name in $names) { $set.Add($name) | Out-Null }
        $profiles[$property.Name] = $set
        $purpose = if ($property.Value.PSObject.Properties.Match('purpose').Count -gt 0) { [string]$property.Value.purpose } else { '' }
        if ([string]::IsNullOrWhiteSpace($purpose)) { $purpose = ("Capabilities grouped under the '{0}' compatibility domain." -f $property.Name) }
        $profileCatalog.Add([pscustomobject]@{ name = $property.Name; purpose = $purpose; enabled_name_count = $set.Count; active = ($property.Name -eq $currentProfile) }) | Out-Null
    }
}

$validHints = [Collections.Generic.List[string]]::new()
$requestedDomainHints = @(Get-ProfileHintArray @($DomainHint + $ProfileHint))
$hasRequestedDomainHints = $requestedDomainHints.Count -gt 0
foreach ($hint in $requestedDomainHints) {
    if ($profiles.ContainsKey($hint)) { $validHints.Add($hint) | Out-Null }
    else {
        $legacyOnly = @($DomainHint).Count -eq 0 -and @($ProfileHint).Count -gt 0
        $excludedResults.Add([pscustomobject]@{ kind = if ($legacyOnly) { 'profile' } else { 'domain' }; name = $hint; reason = if ($legacyOnly) { 'unknown_profile' } else { 'unknown_domain' } }) | Out-Null
    }
}
if (-not $hasRequestedDomainHints -and $validHints.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($currentProfile) -and $profiles.ContainsKey($currentProfile)) { $validHints.Add($currentProfile) | Out-Null }
$domainResolutionFailed = $hasRequestedDomainHints -and $validHints.Count -eq 0

$hostExcluded = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($text in @($ExcludeCapability)) {
    $ref = Get-CapabilityReference $text
    if ($null -eq $ref) { continue }
    if ([string]::IsNullOrWhiteSpace($ref.kind)) {
        foreach ($entry in @($entries | Where-Object { $_.name -eq $ref.name })) { $hostExcluded.Add((Get-Key $entry.kind $entry.name)) | Out-Null }
    }
    else { $hostExcluded.Add((Get-Key $ref.kind $ref.name)) | Out-Null }
}
foreach ($key in $hostExcluded) {
    $parts = $key.Split('|', 2)
    $excludedResults.Add([pscustomobject]@{ kind = $parts[0]; name = $parts[1]; reason = 'host_excluded' }) | Out-Null
}

function Convert-ToPublicEntry($Entry) {
    $key = Get-Key ([string]$Entry.kind) ([string]$Entry.name)
    $rules = if ($routing.ContainsKey($key)) { @($routing[$key].ToArray()) } else { @() }
    $operatorRule = @($rules | Where-Object role -eq 'operator' | Select-Object -First 1)
    $primaryRule = @($rules | Sort-Object group, role | Select-Object -First 1)
    $role = if ($operatorRule.Count -gt 0) { 'operator' } elseif ($primaryRule.Count -gt 0) { [string]$primaryRule[0].role } else { '' }
    $sideEffect = if ($role -eq 'operator') { 'controlled_write' } else { [string]$Entry.side_effect }
    $loadSideEffect = if ($Entry.PSObject.Properties.Match('load_side_effect').Count -gt 0) { [string]$Entry.load_side_effect } else { 'read_only' }
    $domains = if ([string]$Entry.kind -eq 'skill') { @($profiles.Keys | Where-Object { $profiles[$_].Contains([string]$Entry.name) } | Sort-Object) } else { @() }
    return [pscustomobject]@{
        kind = [string]$Entry.kind; name = [string]$Entry.name; description = [string]$Entry.description
        path = [string]$Entry.path; active = [bool]$Entry.active; availability = [string]$Entry.availability
        domains = @($domains)
        load_side_effect = $loadSideEffect; side_effect = $sideEffect; role = $role
        groups = @($rules.group | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
        routing_rules = @($rules)
        group = if ($primaryRule.Count -eq 1) { [string]$primaryRule[0].group } else { '' }
        activation = if ($primaryRule.Count -eq 1) { [string]$primaryRule[0].activation } else { '' }
        negative_activation = if ($primaryRule.Count -eq 1) { [string]$primaryRule[0].negative_activation } else { '' }
    }
}

$requestedRefs = [Collections.Generic.List[object]]::new()
$requestedSeen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($text in @($Candidate)) {
    $ref = Get-CapabilityReference $text
    if ($null -eq $ref) { continue }
    $key = if ([string]::IsNullOrWhiteSpace($ref.kind)) { $ref.name.ToLowerInvariant() } else { Get-Key $ref.kind $ref.name }
    if ($requestedSeen.Add($key)) { $requestedRefs.Add($ref) | Out-Null }
}

$explicitRefs = [Collections.Generic.List[object]]::new()
$queryLower = $Query.ToLowerInvariant()
foreach ($entry in $entries) {
    $nameLower = ([string]$entry.name).ToLowerInvariant()
    $explicitMention = $queryLower.Contains(('$' + $nameLower)) -or $queryLower.Contains(('@' + $nameLower))
    if ($explicitMention) {
        $key = Get-Key $entry.kind $entry.name
        if ($requestedSeen.Add($key)) {
            $ref = [pscustomobject]@{ kind = [string]$entry.kind; name = [string]$entry.name }
            $requestedRefs.Add($ref) | Out-Null
            $explicitRefs.Add($ref) | Out-Null
        }
    }
}

$discovery = [Collections.Generic.List[object]]::new()
$discoverySeen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $entries) {
    if ($domainResolutionFailed) { continue }
    $key = Get-Key $entry.kind $entry.name
    if ($hostExcluded.Contains($key)) { continue }
    $include = $false
    if ($entry.kind -eq 'skill') {
        foreach ($hint in $validHints) { if ($profiles[$hint].Contains([string]$entry.name)) { $include = $true; break } }
    }
    elseif ($entry.kind -eq 'mcp') {
        $mcpNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        if ($null -ne $config -and $null -ne $config.mcp_profiles) {
            foreach ($hint in $validHints) {
                $mcpProperty = @($config.mcp_profiles.profiles.PSObject.Properties | Where-Object { $_.Name -eq $hint } | Select-Object -First 1)
                if ($mcpProperty.Count -eq 1) { foreach ($name in @($mcpProperty[0].Value.enabled)) { $mcpNames.Add([string]$name) | Out-Null } }
            }
            if ($mcpNames.Count -eq 0) {
                $currentMcpProperty = @($config.mcp_profiles.profiles.PSObject.Properties | Where-Object { $_.Name -eq $currentMcpProfile } | Select-Object -First 1)
                if ($currentMcpProperty.Count -eq 1) { foreach ($name in @($currentMcpProperty[0].Value.enabled)) { $mcpNames.Add([string]$name) | Out-Null } }
            }
        }
        $include = $mcpNames.Contains([string]$entry.name)
    }
    else { $include = $true }
    if ($include -and $discoverySeen.Add($key)) { $discovery.Add((Convert-ToPublicEntry $entry)) | Out-Null }
}
foreach ($ref in @($requestedRefs)) {
    $matches = if ([string]::IsNullOrWhiteSpace([string]$ref.kind)) { @($entries | Where-Object { $_.name -eq $ref.name }) } else { @($entries | Where-Object { $_.kind -eq $ref.kind -and $_.name -eq $ref.name }) }
    foreach ($entry in $matches) {
        $key = Get-Key $entry.kind $entry.name
        if (-not $hostExcluded.Contains($key) -and $discoverySeen.Add($key)) { $discovery.Add((Convert-ToPublicEntry $entry)) | Out-Null }
    }
}
$availableCandidateCount = $discovery.Count
$discovery = @($discovery | Sort-Object @{ Expression = 'active'; Descending = $true }, kind, name | Select-Object -First $MaxCandidates)
$candidateTruncated = $availableCandidateCount -gt $discovery.Count

$selected = [Collections.Generic.List[object]]::new()
$selectedSeen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($ref in @($requestedRefs | Select-Object -First 3)) {
    $matches = if ([string]::IsNullOrWhiteSpace([string]$ref.kind)) { @($entries | Where-Object { $_.name -eq $ref.name }) } else { @($entries | Where-Object { $_.kind -eq $ref.kind -and $_.name -eq $ref.name }) }
    if ($matches.Count -eq 0) {
        $excludedResults.Add([pscustomobject]@{ kind = if ([string]::IsNullOrWhiteSpace([string]$ref.kind)) { 'unknown' } else { $ref.kind }; name = $ref.name; reason = 'unknown_capability' }) | Out-Null
        continue
    }
    foreach ($entry in $matches) {
        $key = Get-Key $entry.kind $entry.name
        if ($hostExcluded.Contains($key)) { continue }
        if ($selectedSeen.Add($key)) { $selected.Add((Convert-ToPublicEntry $entry)) | Out-Null }
    }
}

$activationPlan = foreach ($item in $selected) {
    $action = 'request_activation'
    $autoAllowed = $false
    $policyDecision = 'activation_required'
    $loadAllowed = $false
    $executionPolicy = 'host_action_policy_required'
    if ($item.kind -eq 'skill' -and $item.load_side_effect -eq 'read_only') {
        if ($item.availability -eq 'available') {
            $action = 'use_active_skill'
            $autoAllowed = $true
            $loadAllowed = $true
            $policyDecision = 'allow_instruction_load'
        }
        elseif ($item.availability -eq 'cold_load' -and -not [string]::IsNullOrWhiteSpace([string]$item.path)) {
            $action = 'load_skill'
            $autoAllowed = $true
            $loadAllowed = $true
            $policyDecision = 'allow_instruction_load'
        }
        if ($item.side_effect -eq 'controlled_write') { $executionPolicy = 'approval_required' }
    }
    elseif ($item.kind -eq 'skill') {
        $action = 'load_skill_with_approval'
        $policyDecision = 'approval_required'
    }
    elseif ($item.availability -eq 'available' -and $item.side_effect -in @('read_only', 'external_read')) {
        $action = if ($item.kind -eq 'mcp') { 'use_available_mcp' } else { 'use_available_capability' }
        $autoAllowed = $true
        $policyDecision = 'allow'
    }
    elseif ($item.availability -eq 'available') {
        $action = 'request_approval'
        $policyDecision = 'approval_required'
        $executionPolicy = 'approval_required'
    }
    elseif ($item.kind -eq 'mcp') { $action = 'request_mcp_activation' }
    [pscustomobject]@{
        kind = $item.kind; name = $item.name; action = $action; auto_allowed = $autoAllowed
        load_allowed = $loadAllowed; load_side_effect = $item.load_side_effect
        execution_policy = $executionPolicy; policy_decision = $policyDecision
        workflow_side_effect = $item.side_effect; side_effect = $item.side_effect; path = $item.path
    }
}

$session = if ($sessionFile) { Get-Content -LiteralPath $sessionFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$reuse = [Collections.Generic.List[object]]::new()
$load = [Collections.Generic.List[object]]::new()
foreach ($item in $selected) {
    $loadedMatch = if ($null -eq $session) { @() } else { @($session.loaded | Where-Object { [string]$_.kind -eq [string]$item.kind -and [string]$_.name -eq [string]$item.name }) }
    if ($loadedMatch.Count -gt 0) { $reuse.Add([pscustomobject]@{ kind = $item.kind; name = $item.name }) | Out-Null }
    else { $load.Add([pscustomobject]@{ kind = $item.kind; name = $item.name }) | Out-Null }
}

$selectionMode = 'discovery'
if ($selected.Count -gt 0) { $selectionMode = if ($explicitRefs.Count -gt 0 -and @($Candidate).Count -eq 0) { 'explicit' } else { 'host_selected' } }
elseif ($discovery.Count -eq 0) { $selectionMode = 'abstain' }
$profileRecommendation = if ($validHints.Count -gt 0) { $validHints[0] } else { $currentProfile }
$taskModel = [ordered]@{
    task_type = 'host_adjudicated'
    domain = 'host_adjudicated'
    goal = 'select_smallest_sufficient_capabilities'
    operations = @()
    requested_kinds = @($requestedRefs | ForEach-Object { [string]$_.kind } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    risk = 'policy_only'
    constraints = @('semantic_selection_not_performed')
    confidence = $null
}
$capabilityRefs = @($selected | ForEach-Object { Get-Key $_.kind $_.name })
$capabilityGraph = [ordered]@{
    stages = @(
        [ordered]@{ id = 'discover_domains'; capability_refs = @() },
        [ordered]@{ id = 'discover_candidates'; capability_refs = @($discovery | ForEach-Object { Get-Key $_.kind $_.name }) },
        [ordered]@{ id = 'host_adjudication'; capability_refs = @() },
        [ordered]@{ id = 'policy'; capability_refs = $capabilityRefs },
        [ordered]@{ id = 'activate'; capability_refs = $capabilityRefs }
    )
    edges = @(
        [ordered]@{ from = 'discover_domains'; to = 'discover_candidates' },
        [ordered]@{ from = 'discover_candidates'; to = 'host_adjudication' },
        [ordered]@{ from = 'host_adjudication'; to = 'policy' },
        [ordered]@{ from = 'policy'; to = 'activate' }
    )
}

[ordered]@{
    schema_version = 3
    query = $Query
    decision_owner = 'host_ai'
    semantic_routing_performed = $false
    requires_host_adjudication = ($selected.Count -eq 0 -and $discovery.Count -gt 0)
    task_model = $taskModel
    intents = @()
    manifest_path = $manifestFile
    catalog_path = $catalogFile
    policy_path = $policyFile
    config_path = $configFile
    current_profile = $currentProfile
    current_mcp_profile = $currentMcpProfile
    discovery_architecture = 'hierarchical_domains_v1'
    discovery_domains = @($profileCatalog | Sort-Object name)
    profile_catalog = @($profileCatalog | Sort-Object name)
    host_snapshot = [ordered]@{ status = $snapshotStatus; source = $snapshotSource; captured_at = $snapshotCapturedAt; path = $snapshotFile }
    retrieval = [ordered]@{
        strategy = 'hierarchical_domain_discovery'
        domain_hints = @($validHints)
        profile_hints = @($validHints)
        candidate_count = $discovery.Count
        available_candidate_count = $availableCandidateCount
        truncated = $candidateTruncated
        candidates = @($discovery)
        top_candidates = @()
    }
    capability_graph = $capabilityGraph
    session_plan = [ordered]@{ reuse = @($reuse); load = @($load); release = @(); state_update = [ordered]@{ semantic_owner = 'host_ai' } }
    preheat_recommendation = [ordered]@{ profile = $profileRecommendation; add = @($load); remove = @(); apply = $false }
    selection_mode = $selectionMode
    selected = @($selected)
    activation_plan = @($activationPlan)
    excluded = @($excludedResults.ToArray())
    abstained = ($selected.Count -eq 0 -and $discovery.Count -eq 0)
    candidate_count = $discovery.Count
    capability_count = $entries.Count
    writes_performed = $false
} | ConvertTo-Json -Depth 12
