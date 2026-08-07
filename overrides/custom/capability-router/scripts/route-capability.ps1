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
    [string]$SessionIdentity = '',
    [ValidateRange(1, 10080)][int]$MaxSnapshotAgeMinutes = 60,
    [string[]]$SkillRoot = @(),
    [string[]]$DomainHint = @(),
    [string[]]$ProfileHint = @(),
    [Alias('SelectedCapability')][string[]]$Candidate = @(),
    [string[]]$ExcludeCapability = @(),
    [ValidateRange(1, 256)][int]$MaxCandidates = 128,
    [switch]$AutoDiscover,
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

function Get-TextSha256([string]$Value) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)) | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally { $sha.Dispose() }
}

function Get-FileSha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::OpenRead($Path)
        try { return (($sha.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) -join '') }
        finally { $stream.Dispose() }
    }
    finally { $sha.Dispose() }
}

function Get-CatalogFingerprint($Catalog) {
    $copy = $Catalog | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $copy.PSObject.Properties.Remove('catalog_fingerprint')
    return Get-TextSha256 ($copy | ConvertTo-Json -Depth 20 -Compress)
}

function Test-TrueProperty($Value, [string]$Name) {
    if ($null -eq $Value -or $Value.PSObject.Properties.Match($Name).Count -eq 0) { return $false }
    return ($Value.$Name -is [bool]) -and [bool]$Value.$Name
}

function Test-SnapshotCapabilityCoverage($Coverage, [string]$Kind) {
    switch ($Kind) {
        'skill' { return Test-TrueProperty $Coverage 'skills' }
        'mcp' { return Test-TrueProperty $Coverage 'mcp_servers' }
        'app' { return (Test-TrueProperty $Coverage 'installed_apps') -or (Test-TrueProperty $Coverage 'app_catalog') }
        'plugin' { return Test-TrueProperty $Coverage 'plugins' }
        'connector' { return Test-TrueProperty $Coverage 'connectors' }
        'native_tool' { return Test-TrueProperty $Coverage 'native_tools' }
        'tool' { return Test-TrueProperty $Coverage 'tools' }
        default { return $false }
    }
}

$excludedResults = [Collections.Generic.List[object]]::new()
$catalogStaleNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$catalogFile = Find-Catalog
$catalog = if ($catalogFile) { Get-Content -LiteralPath $catalogFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
if ($null -ne $catalog -and [int]$catalog.schema_version -ne 1) { throw "unsupported capability catalog schema_version: $($catalog.schema_version)" }
$catalogStatus = if ($catalogFile) { 'legacy_unverified' } else { 'not_provided' }
$catalogFingerprint = ''
if ($null -ne $catalog -and $catalog.PSObject.Properties.Match('catalog_fingerprint').Count -gt 0) {
    $catalogFingerprint = ([string]$catalog.catalog_fingerprint).Trim().ToLowerInvariant()
    $actualCatalogFingerprint = Get-CatalogFingerprint $catalog
    if ($catalogFingerprint -notmatch '^[0-9a-f]{64}$' -or $actualCatalogFingerprint -ne $catalogFingerprint) {
        $catalogStatus = 'stale'
        foreach ($item in @($catalog.skills)) {
            $name = ([string]$item.name).Trim()
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $catalogStaleNames.Add($name) | Out-Null
            $excludedResults.Add([pscustomobject]@{ kind = 'skill'; name = $name; reason = 'catalog_stale' }) | Out-Null
        }
        $catalog = $null
    }
    else { $catalogStatus = 'current' }
}
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
        $catalogName = ([string]$item.name).Trim()
        if ([string]::IsNullOrWhiteSpace($relativePath) -or [IO.Path]::IsPathRooted($relativePath)) {
            if (-not [string]::IsNullOrWhiteSpace($catalogName)) {
                $catalogStaleNames.Add($catalogName) | Out-Null
                $excludedResults.Add([pscustomobject]@{ kind = 'skill'; name = $catalogName; reason = 'catalog_stale' }) | Out-Null
                $catalogStatus = 'stale'
            }
            continue
        }
        $skillPath = [IO.Path]::GetFullPath((Join-Path (Split-Path $catalogFile -Parent) $relativePath))
        $expectedEntrypointHash = ([string]$item.entrypoint_sha256).Trim().ToLowerInvariant()
        $actualEntrypointHash = if (Test-Contained $skillPath $catalogSkillRoot) { Get-FileSha256 $skillPath } else { '' }
        if ($expectedEntrypointHash -notmatch '^[0-9a-f]{64}$' -or $actualEntrypointHash -ne $expectedEntrypointHash) {
            if (-not [string]::IsNullOrWhiteSpace($catalogName)) {
                $catalogStaleNames.Add($catalogName) | Out-Null
                $excludedResults.Add([pscustomobject]@{ kind = 'skill'; name = $catalogName; reason = 'catalog_stale' }) | Out-Null
                $catalogStatus = 'stale'
            }
            continue
        }
        $entry = Read-SkillMetadata $skillPath $catalogSkillRoot $false
        if ($null -eq $entry -or -not [string]::Equals([string]$entry.name, $catalogName, [StringComparison]::OrdinalIgnoreCase)) {
            if (-not [string]::IsNullOrWhiteSpace($catalogName)) {
                $catalogStaleNames.Add($catalogName) | Out-Null
                $excludedResults.Add([pscustomobject]@{ kind = 'skill'; name = $catalogName; reason = 'catalog_stale' }) | Out-Null
                $catalogStatus = 'stale'
            }
            continue
        }
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
$snapshotProducerStatus = ''
$snapshotCoverage = $null
$snapshotSourceErrors = @()
$snapshotReason = ''
$runtimeExcluded = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
if ($snapshotFile) {
    $snapshot = Get-Content -LiteralPath $snapshotFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $snapshotItems = if ($snapshot.PSObject.Properties.Match('capabilities').Count -gt 0) { @($snapshot.capabilities) } else { @($snapshot) }
    $snapshotSource = if ($snapshot.PSObject.Properties.Match('source').Count -gt 0) { [string]$snapshot.source } else { 'caller-provided' }
    $snapshotProducerStatus = if ($snapshot.PSObject.Properties.Match('status').Count -gt 0) { ([string]$snapshot.status).Trim() } else { '' }
    $snapshotCoverage = if ($snapshot.PSObject.Properties.Match('coverage').Count -gt 0) { $snapshot.coverage } else { $null }
    $snapshotSourceErrors = if ($snapshot.PSObject.Properties.Match('source_errors').Count -gt 0) { @($snapshot.source_errors) } else { @() }
    $snapshotStatus = 'invalid'
    if ($snapshot.PSObject.Properties.Match('schema_version').Count -eq 0 -or [string]$snapshot.schema_version -ne '2') {
        $snapshotReason = 'unsupported_schema'
    }
    elseif ($snapshot.PSObject.Properties.Match('read_only').Count -eq 0 -or -not ($snapshot.read_only -is [bool]) -or -not [bool]$snapshot.read_only) {
        $snapshotReason = 'read_only_required'
    }
    elseif ($snapshotProducerStatus -notin @('complete', 'runtime_complete_catalog_partial', 'partial')) {
        $snapshotReason = 'invalid_producer_status'
    }
    elseif ($null -eq $snapshotCoverage) {
        $snapshotReason = 'coverage_required'
    }
    elseif ($snapshot.PSObject.Properties.Match('source_errors').Count -eq 0) {
        $snapshotReason = 'source_errors_required'
    }
    elseif ($snapshot.PSObject.Properties.Match('captured_at').Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$snapshot.captured_at)) {
        $snapshotReason = 'missing_captured_at'
    }
    else {
        try { $snapshotCapturedAt = [DateTimeOffset]::Parse([string]$snapshot.captured_at) }
        catch { $snapshotReason = 'invalid_captured_at' }
        if ([string]::IsNullOrWhiteSpace($snapshotReason)) {
            $now = [DateTimeOffset]::UtcNow
            if ($snapshotCapturedAt -gt $now.AddMinutes(5)) {
                $snapshotReason = 'future_captured_at'
            }
            elseif (($now - $snapshotCapturedAt).TotalMinutes -gt $MaxSnapshotAgeMinutes) {
                $snapshotStatus = 'stale'
                $snapshotReason = 'expired'
            }
            else {
                $completeCoverage = $true
                foreach ($coverageName in @('skills', 'installed_apps', 'app_catalog', 'mcp_servers')) {
                    if (-not (Test-TrueProperty $snapshotCoverage $coverageName)) { $completeCoverage = $false; break }
                }
                $snapshotStatus = if ($snapshotProducerStatus -eq 'complete' -and $completeCoverage -and $snapshotSourceErrors.Count -eq 0) { 'current_complete' } else { 'current_partial' }
            }
        }
    }
    foreach ($capability in $snapshotItems) {
        $kind = ([string]$capability.kind).Trim().ToLowerInvariant()
        $name = ([string]$capability.name).Trim()
        if ($kind -notin @('skill', 'mcp', 'plugin', 'app', 'connector', 'native_tool', 'tool') -or [string]::IsNullOrWhiteSpace($name)) { continue }
        $key = Get-Key $kind $name
        $snapshotExclusionReason = if ($snapshotStatus -eq 'invalid') { 'invalid_snapshot' } elseif ($snapshotStatus -eq 'stale') { 'stale_snapshot' } elseif (-not (Test-SnapshotCapabilityCoverage $snapshotCoverage $kind)) { 'snapshot_coverage_missing' } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($snapshotExclusionReason)) {
            $runtimeExcluded.Add($key) | Out-Null
            $excludedResults.Add([pscustomobject]@{ kind = $kind; name = $name; reason = $snapshotExclusionReason }) | Out-Null
            continue
        }
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
        foreach ($name in @(Get-StringArray $domain.skill_names)) {
            if (-not $catalogStaleNames.Contains($name)) { $set.Add($name) | Out-Null }
        }
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
$globalCatalogDiscovery = -not $hasRequestedDomainHints
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
    if ($hostExcluded.Contains($key) -or $runtimeExcluded.Contains($key)) { continue }
    $include = $false
    if ($entry.kind -eq 'skill') {
        if ($globalCatalogDiscovery) {
            $include = $true
        }
        else {
            foreach ($hint in $validHints) { if ($profiles[$hint].Contains([string]$entry.name)) { $include = $true; break } }
        }
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
        if (-not $hostExcluded.Contains($key) -and -not $runtimeExcluded.Contains($key) -and $discoverySeen.Add($key)) { $discovery.Add((Convert-ToPublicEntry $entry)) | Out-Null }
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
        if ($hostExcluded.Contains($key) -or $runtimeExcluded.Contains($key)) { continue }
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

$session = $null
$sessionStatus = 'not_provided'
$sessionReason = ''
$sessionCapturedAt = $null
$sessionSnapshotIdentity = ''
if ($sessionFile) {
    $sessionCandidate = Get-Content -LiteralPath $sessionFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $sessionStatus = 'invalid'
    $sessionSnapshotIdentity = if ($sessionCandidate.PSObject.Properties.Match('session_id').Count -gt 0) { [string]$sessionCandidate.session_id } else { '' }
    if ($sessionCandidate.PSObject.Properties.Match('schema_version').Count -eq 0 -or [string]$sessionCandidate.schema_version -ne '2') {
        $sessionStatus = 'legacy_unverified'
        $sessionReason = 'unsupported_schema'
    }
    elseif ($sessionCandidate.PSObject.Properties.Match('read_only').Count -eq 0 -or -not ($sessionCandidate.read_only -is [bool]) -or -not [bool]$sessionCandidate.read_only) {
        $sessionReason = 'read_only_required'
    }
    elseif ([string]::IsNullOrWhiteSpace($SessionIdentity) -or [string]::IsNullOrWhiteSpace($sessionSnapshotIdentity)) {
        $sessionReason = 'session_identity_required'
    }
    elseif (-not [string]::Equals($SessionIdentity, $sessionSnapshotIdentity, [StringComparison]::Ordinal)) {
        $sessionStatus = 'foreign_session'
        $sessionReason = 'session_identity_mismatch'
    }
    elseif ($sessionCandidate.PSObject.Properties.Match('loaded').Count -eq 0) {
        $sessionReason = 'loaded_inventory_required'
    }
    elseif ($sessionCandidate.PSObject.Properties.Match('captured_at').Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$sessionCandidate.captured_at)) {
        $sessionReason = 'missing_captured_at'
    }
    else {
        try { $sessionCapturedAt = [DateTimeOffset]::Parse([string]$sessionCandidate.captured_at) }
        catch { $sessionReason = 'invalid_captured_at' }
        if ([string]::IsNullOrWhiteSpace($sessionReason)) {
            $now = [DateTimeOffset]::UtcNow
            if ($sessionCapturedAt -gt $now.AddMinutes(5)) {
                $sessionReason = 'future_captured_at'
            }
            elseif (($now - $sessionCapturedAt).TotalMinutes -gt $MaxSnapshotAgeMinutes) {
                $sessionStatus = 'stale'
                $sessionReason = 'expired'
            }
            else {
                $sessionStatus = 'current'
                foreach ($loadedItem in @($sessionCandidate.loaded | Where-Object { [string]$_.kind -eq 'skill' })) {
                    $loadedKey = Get-Key 'skill' ([string]$loadedItem.name)
                    $expectedHash = ([string]$loadedItem.entrypoint_sha256).Trim().ToLowerInvariant()
                    $currentEntry = if ($entryByKey.ContainsKey($loadedKey)) { $entryByKey[$loadedKey] } else { $null }
                    $currentHash = if ($null -ne $currentEntry -and -not [string]::IsNullOrWhiteSpace([string]$currentEntry.path)) { Get-FileSha256 ([string]$currentEntry.path) } else { '' }
                    if ($expectedHash -notmatch '^[0-9a-f]{64}$' -or $currentHash -ne $expectedHash) {
                        $sessionStatus = 'stale'
                        $sessionReason = 'entrypoint_mismatch'
                        break
                    }
                }
                if ($sessionStatus -eq 'current') { $session = $sessionCandidate }
            }
        }
    }
}
$reuse = [Collections.Generic.List[object]]::new()
$load = [Collections.Generic.List[object]]::new()
foreach ($item in $selected) {
    $loadedMatch = if ($null -eq $session -or [string]$item.kind -ne 'skill') { @() } else { @($session.loaded | Where-Object { [string]$_.kind -eq [string]$item.kind -and [string]$_.name -eq [string]$item.name }) }
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
    catalog = [ordered]@{ status = $catalogStatus; fingerprint = $catalogFingerprint; path = $catalogFile }
    policy_path = $policyFile
    config_path = $configFile
    current_profile = $currentProfile
    current_mcp_profile = $currentMcpProfile
    discovery_architecture = 'global_catalog_then_policy_v1'
    automatic_dispatch = [ordered]@{
        requested = ([bool]$AutoDiscover -or $globalCatalogDiscovery)
        scope = if ($globalCatalogDiscovery) { 'all_catalog_skills' } else { 'explicit_domains' }
        profile_switch_required = $false
        profile_mutation_allowed = $false
    }
    discovery_domains = @($profileCatalog | Sort-Object name)
    profile_catalog = @($profileCatalog | Sort-Object name)
    host_snapshot = [ordered]@{
        status = $snapshotStatus
        reason = $snapshotReason
        producer_status = $snapshotProducerStatus
        source = $snapshotSource
        captured_at = $snapshotCapturedAt
        coverage = $snapshotCoverage
        source_errors = @($snapshotSourceErrors)
        path = $snapshotFile
    }
    retrieval = [ordered]@{
        strategy = if ($globalCatalogDiscovery) { 'global_catalog_discovery' } else { 'hierarchical_domain_discovery' }
        scope = if ($globalCatalogDiscovery) { 'all_catalog_skills' } else { 'domain_hints' }
        domain_hints = @($validHints)
        profile_hints = @($validHints)
        candidate_count = $discovery.Count
        available_candidate_count = $availableCandidateCount
        truncated = $candidateTruncated
        candidates = @($discovery)
        top_candidates = @()
    }
    capability_graph = $capabilityGraph
    session_snapshot = [ordered]@{ status = $sessionStatus; reason = $sessionReason; session_id = $sessionSnapshotIdentity; captured_at = $sessionCapturedAt; path = $sessionFile }
    session_plan = [ordered]@{ reuse = @($reuse); load = @($load); release = @(); state_update = [ordered]@{ semantic_owner = 'host_ai'; reuse_verified = ($sessionStatus -eq 'current') } }
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
