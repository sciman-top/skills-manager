[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Query,
    [string]$ManifestPath = '',
    [string]$PolicyPath = '',
    [string]$ConfigPath = '',
    [string]$CapabilitySnapshotPath = '',
    [string]$HostSnapshotPath = '',
    [string]$SessionSnapshotPath = '',
    [ValidateRange(1, 10080)][int]$MaxSnapshotAgeMinutes = 60,
    [string[]]$SkillRoot = @(),
    [string[]]$ProfileHint = @(),
    [Alias('SelectedCapability')][string[]]$Candidate = @(),
    [string[]]$ExcludeCapability = @(),
    [ValidateRange(1, 100)][int]$MaxCandidates = 24
)

$ErrorActionPreference = 'Stop'

function Resolve-ExistingFile([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if ($expanded.StartsWith('~/') -or $expanded.StartsWith('~\')) { $expanded = Join-Path $HOME $expanded.Substring(2) }
    if (Test-Path -LiteralPath $expanded -PathType Leaf) { return [IO.Path]::GetFullPath($expanded) }
    return ''
}

function Find-Manifest {
    $explicit = Resolve-ExistingFile $ManifestPath
    if ($explicit) { return $explicit }
    $fromEnv = Resolve-ExistingFile $env:SKILLS_MANAGER_PROJECTION_MANIFEST
    if ($fromEnv) { return $fromEnv }
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
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $frontmatter = [regex]::Match($text, '(?s)\A---\s*\r?\n(?<yaml>.*?)\r?\n---')
    if (-not $frontmatter.Success) { return $null }
    $yaml = $frontmatter.Groups['yaml'].Value
    $nameMatch = [regex]::Match($yaml, '(?m)^name:\s*["'']?(?<value>[^\r\n"'']+)')
    $descriptionMatch = [regex]::Match($yaml, '(?m)^description:\s*["'']?(?<value>[^\r\n]+)')
    if (-not $nameMatch.Success -or -not $descriptionMatch.Success) { return $null }
    return [pscustomobject]@{
        kind = 'skill'
        name = $nameMatch.Groups['value'].Value.Trim()
        description = $descriptionMatch.Groups['value'].Value.Trim().Trim('"', "'")
        path = [IO.Path]::GetFullPath($Path)
        source_root = [IO.Path]::GetFullPath($Root)
        active = $Active
        availability = if ($Active) { 'available' } else { 'cold_load' }
        side_effect = 'read_only'
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
if ($null -ne $policy) {
    foreach ($group in @($policy.groups)) {
        foreach ($member in @($group.members)) {
            $routing[(Get-Key 'skill' ([string]$member.name))] = [pscustomobject]@{
                activation = [string]$member.activation
                negative_activation = [string]$member.negative_activation
                role = [string]$member.role
                group = [string]$group.id
                context = ('{0} {1}' -f [string]$group.purpose, [string]$group.selection_policy).Trim()
            }
        }
    }
}

$entries = [Collections.Generic.List[object]]::new()
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$activeNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
if ($null -ne $manifest) {
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

if ($null -ne $policy) {
    foreach ($capability in @($policy.capabilities)) {
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
        $routing[$key] = [pscustomobject]@{
            activation = [string]$capability.activation; negative_activation = [string]$capability.negative_activation
            role = 'capability'; group = 'unified-capabilities'; context = 'Declared host capability; the host model decides relevance.'
        }
    }
}

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
        if ($kind -notin @('plugin', 'app', 'connector', 'native_tool', 'tool') -or [string]::IsNullOrWhiteSpace($name)) { continue }
        if ($snapshotStatus -eq 'stale') {
            $excludedResults.Add([pscustomobject]@{ kind = $kind; name = $name; reason = 'stale_snapshot' }) | Out-Null
            continue
        }
        $key = Get-Key $kind $name
        if (-not $seen.Add($key)) { continue }
        $availability = if ([string]::IsNullOrWhiteSpace([string]$capability.availability)) { 'unknown' } else { [string]$capability.availability }
        if ($capability.PSObject.Properties.Match('callable').Count -gt 0 -and -not [bool]$capability.callable) { $availability = 'not_callable' }
        if ($capability.PSObject.Properties.Match('accessible').Count -gt 0 -and -not [bool]$capability.accessible) { $availability = 'inaccessible' }
        $entries.Add([pscustomobject]@{
            kind = $kind; name = $name; description = [string]$capability.description; path = ''; source_root = ''
            active = ($availability -eq 'available'); availability = $availability
            side_effect = if ([string]::IsNullOrWhiteSpace([string]$capability.side_effect)) { 'unknown' } else { [string]$capability.side_effect }
        })
        $routing[$key] = [pscustomobject]@{
            activation = [string]$capability.activation; negative_activation = [string]$capability.negative_activation
            role = 'external'; group = 'runtime-snapshot'; context = 'Caller-provided current runtime capability snapshot.'
        }
    }
}

$profiles = @{}
$profileCatalog = [Collections.Generic.List[object]]::new()
$currentProfile = if ($null -ne $manifest) { [string]$manifest.active_profile } elseif ($null -ne $config) { [string]$config.skill_projection.active_profile } else { '' }
if ($null -ne $config -and $config.PSObject.Properties.Match('skill_projection').Count -gt 0 -and $null -ne $config.skill_projection.profiles) {
    foreach ($property in @($config.skill_projection.profiles.PSObject.Properties)) {
        $names = @(Get-StringArray $property.Value.enabled_names)
        $set = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($name in $names) { $set.Add($name) | Out-Null }
        $profiles[$property.Name] = $set
        $profileCatalog.Add([pscustomobject]@{ name = $property.Name; enabled_name_count = $set.Count; active = ($property.Name -eq $currentProfile) }) | Out-Null
    }
}

$validHints = [Collections.Generic.List[string]]::new()
foreach ($hint in @(Get-StringArray $ProfileHint)) {
    if ($profiles.ContainsKey($hint)) { $validHints.Add($hint) | Out-Null }
    else { $excludedResults.Add([pscustomobject]@{ kind = 'profile'; name = $hint; reason = 'unknown_profile' }) | Out-Null }
}
if ($validHints.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($currentProfile) -and $profiles.ContainsKey($currentProfile)) { $validHints.Add($currentProfile) | Out-Null }

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
    $route = if ($routing.ContainsKey($key)) { $routing[$key] } else { $null }
    $sideEffect = if ($null -ne $route -and [string]$route.role -eq 'operator') { 'controlled_write' } else { [string]$Entry.side_effect }
    return [pscustomobject]@{
        kind = [string]$Entry.kind; name = [string]$Entry.name; description = [string]$Entry.description
        path = [string]$Entry.path; active = [bool]$Entry.active; availability = [string]$Entry.availability
        side_effect = $sideEffect; role = if ($null -eq $route) { '' } else { [string]$route.role }
        group = if ($null -eq $route) { '' } else { [string]$route.group }
        activation = if ($null -eq $route) { '' } else { [string]$route.activation }
        negative_activation = if ($null -eq $route) { '' } else { [string]$route.negative_activation }
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
$discovery = @($discovery | Sort-Object @{ Expression = 'active'; Descending = $true }, kind, name | Select-Object -First $MaxCandidates)

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
    if ($item.kind -eq 'skill' -and $item.side_effect -eq 'read_only') {
        $action = if ($item.active) { 'use_active_skill' } else { 'load_skill' }
        $autoAllowed = $true
        $policyDecision = 'allow'
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
    }
    elseif ($item.kind -eq 'mcp') { $action = 'request_mcp_activation' }
    [pscustomobject]@{
        kind = $item.kind; name = $item.name; action = $action; auto_allowed = $autoAllowed
        policy_decision = $policyDecision; side_effect = $item.side_effect; path = $item.path
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
        [ordered]@{ id = 'discover'; capability_refs = @($discovery | ForEach-Object { Get-Key $_.kind $_.name }) },
        [ordered]@{ id = 'host_adjudication'; capability_refs = @() },
        [ordered]@{ id = 'policy'; capability_refs = $capabilityRefs },
        [ordered]@{ id = 'activate'; capability_refs = $capabilityRefs }
    )
    edges = @(
        [ordered]@{ from = 'discover'; to = 'host_adjudication' },
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
    policy_path = $policyFile
    config_path = $configFile
    current_profile = $currentProfile
    current_mcp_profile = $currentMcpProfile
    profile_catalog = @($profileCatalog | Sort-Object name)
    host_snapshot = [ordered]@{ status = $snapshotStatus; source = $snapshotSource; captured_at = $snapshotCapturedAt; path = $snapshotFile }
    retrieval = [ordered]@{
        strategy = 'profile_native_discovery'
        profile_hints = @($validHints)
        candidate_count = $discovery.Count
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
