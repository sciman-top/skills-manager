#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position=0)][string]$Query,
    [string]$CatalogPath = '',
    [string[]]$DomainHint = @(),
    [Alias('SelectedCapability')][string[]]$Candidate = @(),
    [string[]]$ExcludeCapability = @(),
    [ValidateRange(1,256)][int]$MaxCandidates = 128,
    [switch]$AutoDiscover
)

$ErrorActionPreference = 'Stop'

function New-RouterFinding([string]$Code, [string]$Path, [string]$Message) {
    [pscustomobject][ordered]@{ code = $Code; path = $Path; message = $Message }
}

function Get-TextSha256([string]$Value) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $sha.Dispose() }
}

function Test-Within([string]$Path, [string]$Root) {
    $full = [IO.Path]::GetFullPath($Path)
    $boundary = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    return $full.Equals($boundary, [StringComparison]::OrdinalIgnoreCase) -or
        $full.StartsWith(($boundary + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)
}

function Test-ReparsePathWithinRoot([string]$Path, [string]$Root) {
    $boundary = [IO.Path]::GetFullPath($Root)
    $full = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Within $full $boundary)) { return $true }
    $relative = [IO.Path]::GetRelativePath($boundary, $full)
    $currentPath = $boundary
    foreach ($segment in @($relative -split '[\\/]+' | Where-Object { $_ -and $_ -ne '.' })) {
        $currentPath = Join-Path $currentPath $segment
        $item = Get-Item -LiteralPath $currentPath -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) { return $false }
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $true }
    }
    return $false
}

function Test-ObjectProperty($Object, [string]$Name) {
    return $null -ne $Object -and $Object.PSObject.Properties.Match($Name).Count -gt 0
}

function Get-NormalizedNames([string[]]$Values) {
    return @($Values | ForEach-Object { ([string]$_ -split '\|')[-1].Trim() } | Where-Object { $_ })
}

function Get-DependencyClosure([string]$RootName, [System.Collections.IDictionary]$DependencyMap) {
    $ordered = [System.Collections.Generic.List[string]]::new()
    $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $visiting = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $missing = [System.Collections.Generic.List[string]]::new()
    $state = [pscustomobject]@{ has_cycle = $false }
    $walk = $null
    $walk = {
        param([string]$Name)
        if ($state.has_cycle -or $visited.Contains($Name)) { return }
        if (-not $DependencyMap.Contains($Name)) {
            if (-not $missing.Contains($Name)) { $missing.Add($Name) | Out-Null }
            return
        }
        if (-not $visiting.Add($Name)) {
            $state.has_cycle = $true
            return
        }
        $ordered.Add($Name) | Out-Null
        foreach ($dependency in @($DependencyMap[$Name])) { & $walk ([string]$dependency) }
        $visiting.Remove($Name) | Out-Null
        $visited.Add($Name) | Out-Null
    }
    & $walk $RootName
    return [pscustomobject][ordered]@{
        names = @($ordered.ToArray())
        has_cycle = [bool]$state.has_cycle
        missing = @($missing.ToArray())
    }
}

function Get-CatalogPayload($Catalog) {
    $payload = [ordered]@{}
    foreach ($property in @($Catalog.PSObject.Properties)) {
        if ($property.Name -ne 'catalog_fingerprint') { $payload[$property.Name] = $property.Value }
    }
    return $payload
}

function Resolve-Catalog([string]$Explicit, [bool]$AllowAutoDiscovery) {
    if (-not [string]::IsNullOrWhiteSpace($Explicit)) {
        if (Test-Path -LiteralPath $Explicit -PathType Leaf) {
            return [pscustomobject]@{ path = [IO.Path]::GetFullPath($Explicit); mode = 'explicit'; finding = $null }
        }
        return [pscustomobject]@{ path = ''; mode = 'explicit'; finding = (New-RouterFinding 'catalog_not_found' '$.catalog_path' 'The explicit capability catalog does not exist.') }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:SKILLS_MANAGER_CAPABILITY_CATALOG)) {
        if (Test-Path -LiteralPath $env:SKILLS_MANAGER_CAPABILITY_CATALOG -PathType Leaf) {
            return [pscustomobject]@{ path = [IO.Path]::GetFullPath($env:SKILLS_MANAGER_CAPABILITY_CATALOG); mode = 'environment'; finding = $null }
        }
        return [pscustomobject]@{ path = ''; mode = 'environment'; finding = (New-RouterFinding 'catalog_not_found' '$.catalog_path' 'The environment capability catalog does not exist.') }
    }

    if (-not $AllowAutoDiscovery) {
        return [pscustomobject]@{ path = ''; mode = 'none'; finding = (New-RouterFinding 'catalog_path_required' '$.catalog_path' 'Pass -CatalogPath, set SKILLS_MANAGER_CAPABILITY_CATALOG, or explicitly opt in with -AutoDiscover.') }
    }

    $routerRoot = Split-Path $PSScriptRoot -Parent
    $managedRoot = Split-Path $routerRoot -Parent
    $routerItem = Get-Item -LiteralPath $routerRoot -Force
    $portableRouterRoot = if (($routerItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -and $routerItem.Target) {
        [IO.Path]::GetFullPath([string]$routerItem.Target)
    }
    else { $routerRoot }
    foreach ($path in @(
            (Join-Path $managedRoot '.skills-manager\catalog.json'),
            (Join-Path $portableRouterRoot 'catalog.json'),
            (Join-Path $routerRoot 'catalog.json')
        )) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            return [pscustomobject]@{ path = [IO.Path]::GetFullPath($path); mode = 'auto'; finding = $null }
        }
    }
    return [pscustomobject]@{ path = ''; mode = 'auto'; finding = (New-RouterFinding 'catalog_not_found' '$.catalog_path' 'No auto-discoverable capability catalog is available.') }
}

$catalogFindings = [Collections.Generic.List[object]]::new()
$excluded = [Collections.Generic.List[object]]::new()
$rows = [Collections.Generic.List[object]]::new()
$selected = [Collections.Generic.List[object]]::new()
$catalog = $null
$catalogStatus = 'invalid'
$catalogSkillCount = 0
$catalogFile = ''
$catalogRoot = ''
$managedRoot = ''
$catalogDependencies = @{}
$allAvailableRows = @()
$requestValid = $true
$stale = $false

$resolution = Resolve-Catalog $CatalogPath ([bool]$AutoDiscover)
if ($null -ne $resolution.finding) { $catalogFindings.Add($resolution.finding) | Out-Null }
else {
    $catalogFile = [string]$resolution.path
    $catalogRoot = Split-Path $catalogFile -Parent
    $managedRoot = Split-Path $catalogRoot -Parent
    try { $catalog = Get-Content -LiteralPath $catalogFile -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { $catalogFindings.Add((New-RouterFinding 'catalog_json_invalid' '$' 'The capability catalog is not valid JSON.')) | Out-Null }
}

$skillNameSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$domainNameSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$domainSkills = @{}
if ($null -ne $catalog) {
    if (-not (Test-ObjectProperty $catalog 'schema_version') -or
        $catalog.schema_version -isnot [long] -or $catalog.schema_version -ne 1) {
        $catalogFindings.Add((New-RouterFinding 'catalog_schema_unsupported' '$.schema_version' 'Only capability catalog schema_version 1 is supported.')) | Out-Null
    }
    if (-not (Test-ObjectProperty $catalog 'decision_owner') -or [string]$catalog.decision_owner -ne 'host_ai') {
        $catalogFindings.Add((New-RouterFinding 'decision_owner_invalid' '$.decision_owner' 'Catalog semantic decisions must remain owned by host_ai.')) | Out-Null
    }
    if (-not (Test-ObjectProperty $catalog 'semantic_routing_performed') -or
        $catalog.semantic_routing_performed -isnot [bool] -or $catalog.semantic_routing_performed -ne $false) {
        $catalogFindings.Add((New-RouterFinding 'semantic_boundary_breached' '$.semantic_routing_performed' 'The deterministic catalog cannot perform semantic routing.')) | Out-Null
    }

    $expectedFingerprint = if (Test-ObjectProperty $catalog 'catalog_fingerprint') { ([string]$catalog.catalog_fingerprint).ToLowerInvariant() } else { '' }
    if ($expectedFingerprint -notmatch '^[0-9a-f]{64}$') {
        $catalogFindings.Add((New-RouterFinding 'catalog_fingerprint_invalid' '$.catalog_fingerprint' 'Catalog fingerprint must be a lowercase SHA-256 value.')) | Out-Null
    }
    else {
        $actualFingerprint = Get-TextSha256 ((Get-CatalogPayload $catalog) | ConvertTo-Json -Depth 20 -Compress)
        if ($actualFingerprint -cne $expectedFingerprint) {
            $catalogFindings.Add((New-RouterFinding 'catalog_fingerprint_mismatch' '$.catalog_fingerprint' 'Catalog content does not match its fingerprint.')) | Out-Null
        }
    }

    if (-not (Test-ObjectProperty $catalog 'domains') -or $null -eq $catalog.domains) {
        $catalogFindings.Add((New-RouterFinding 'domains_missing' '$.domains' 'Catalog domains must be present.')) | Out-Null
    }
    else {
        $domainIndex = 0
        foreach ($domain in @($catalog.domains)) {
            $name = ([string]$domain.name).Trim()
            if ([string]::IsNullOrWhiteSpace($name)) {
                $catalogFindings.Add((New-RouterFinding 'domain_name_missing' ("$.domains[{0}].name" -f $domainIndex) 'Domain name is required.')) | Out-Null
            }
            elseif (-not $domainNameSet.Add($name)) {
                $catalogFindings.Add((New-RouterFinding 'domain_name_duplicate' ("$.domains[{0}].name" -f $domainIndex) 'Domain names must be unique.')) | Out-Null
            }
            else {
                $members = @($domain.skill_names | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
                if (@($members | Sort-Object -Unique).Count -ne $members.Count) {
                    $catalogFindings.Add((New-RouterFinding 'domain_membership_duplicate' ("$.domains[{0}].skill_names" -f $domainIndex) 'Domain skill memberships must be unique.')) | Out-Null
                }
                $domainSkills[$name] = @($members)
            }
            $domainIndex++
        }
    }

    if (-not (Test-ObjectProperty $catalog 'skills') -or $null -eq $catalog.skills) {
        $catalogFindings.Add((New-RouterFinding 'skills_missing' '$.skills' 'Catalog skills must be present.')) | Out-Null
    }
    else {
        $catalogSkillCount = @($catalog.skills).Count
        $skillIndex = 0
        foreach ($skill in @($catalog.skills)) {
            $pathPrefix = "$.skills[{0}]" -f $skillIndex
            $name = ([string]$skill.name).Trim()
            $uniqueName = $false
            if ([string]::IsNullOrWhiteSpace($name)) {
                $catalogFindings.Add((New-RouterFinding 'skill_name_missing' ($pathPrefix + '.name') 'Skill name is required.')) | Out-Null
            }
            elseif (-not $skillNameSet.Add($name)) {
                $catalogFindings.Add((New-RouterFinding 'skill_name_duplicate' ($pathPrefix + '.name') 'Skill names must be unique.')) | Out-Null
            }
            else { $uniqueName = $true }
            if ([string]::IsNullOrWhiteSpace([string]$skill.description)) {
                $catalogFindings.Add((New-RouterFinding 'skill_description_missing' ($pathPrefix + '.description') 'Skill description is required for host semantic selection.')) | Out-Null
            }
            if ([string]::IsNullOrWhiteSpace([string]$skill.relative_path)) {
                $catalogFindings.Add((New-RouterFinding 'skill_path_missing' ($pathPrefix + '.relative_path') 'Skill entrypoint path is required.')) | Out-Null
            }
            else {
                try {
                    $resolvedPath = [IO.Path]::GetFullPath((Join-Path $catalogRoot ([string]$skill.relative_path)))
                    if (-not (Test-Within $resolvedPath $managedRoot)) {
                        $catalogFindings.Add((New-RouterFinding 'skill_path_outside_root' ($pathPrefix + '.relative_path') 'Skill entrypoint must stay inside the managed skill root.')) | Out-Null
                    }
                    elseif (Test-ReparsePathWithinRoot $resolvedPath $managedRoot) {
                        $catalogFindings.Add((New-RouterFinding 'skill_path_reparse_point' ($pathPrefix + '.relative_path') 'Skill entrypoint must not traverse a reparse point inside the managed skill root.')) | Out-Null
                    }
                }
                catch { $catalogFindings.Add((New-RouterFinding 'skill_path_invalid' ($pathPrefix + '.relative_path') 'Skill entrypoint path is invalid.')) | Out-Null }
            }
            if ([string]$skill.entrypoint_sha256 -notmatch '^[0-9a-fA-F]{64}$') {
                $catalogFindings.Add((New-RouterFinding 'entrypoint_hash_invalid' ($pathPrefix + '.entrypoint_sha256') 'Skill entrypoint hash must be SHA-256.')) | Out-Null
            }
            if ([string]$skill.load_side_effect -ne 'read_only') {
                $catalogFindings.Add((New-RouterFinding 'load_side_effect_invalid' ($pathPrefix + '.load_side_effect') 'Cold-loading a skill entrypoint must be declared read_only.')) | Out-Null
            }
            if ([string]$skill.side_effect -notin @('read_only', 'external_read', 'controlled_write', 'unknown')) {
                $catalogFindings.Add((New-RouterFinding 'workflow_side_effect_invalid' ($pathPrefix + '.side_effect') 'Workflow side effect must be read_only, external_read, controlled_write, or unknown.')) | Out-Null
            }
            $dependencies = [System.Collections.Generic.List[string]]::new()
            if (Test-ObjectProperty $skill 'dependencies') {
                $rawDependencies = $skill.dependencies
                if ($null -eq $rawDependencies -or $rawDependencies -is [string] -or $rawDependencies -isnot [System.Collections.IEnumerable]) {
                    $catalogFindings.Add((New-RouterFinding 'skill_dependencies_invalid' ($pathPrefix + '.dependencies') 'Skill dependencies must be an array of skill names.')) | Out-Null
                }
                else {
                    $dependencyNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($rawDependency in @($rawDependencies)) {
                        $dependencyName = ([string]$rawDependency).Trim()
                        if ([string]::IsNullOrWhiteSpace($dependencyName)) {
                            $catalogFindings.Add((New-RouterFinding 'skill_dependency_empty' ($pathPrefix + '.dependencies') 'Skill dependencies must not contain empty names.')) | Out-Null
                        }
                        elseif (-not $dependencyNames.Add($dependencyName)) {
                            $catalogFindings.Add((New-RouterFinding 'skill_dependency_duplicate' ($pathPrefix + '.dependencies') 'Skill dependencies must be unique.')) | Out-Null
                        }
                        elseif ($dependencyName.Equals($name, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $catalogFindings.Add((New-RouterFinding 'skill_dependency_self' ($pathPrefix + '.dependencies') 'A skill must not depend on itself.')) | Out-Null
                        }
                        else { $dependencies.Add($dependencyName) | Out-Null }
                    }
                }
            }
            if ($uniqueName) { $catalogDependencies[$name] = @($dependencies.ToArray()) }
            $skillDomains = @($skill.domains | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
            if ($skillDomains.Count -eq 0) {
                $catalogFindings.Add((New-RouterFinding 'skill_domains_missing' ($pathPrefix + '.domains') 'Each skill must belong to at least one discovery domain.')) | Out-Null
            }
            foreach ($domainName in $skillDomains) {
                if (-not $domainNameSet.Contains($domainName)) {
                    $catalogFindings.Add((New-RouterFinding 'skill_domain_unknown' ($pathPrefix + '.domains') 'Skill references an unknown discovery domain.')) | Out-Null
                }
                elseif ([string]$skill.name -notin @($domainSkills[$domainName])) {
                    $catalogFindings.Add((New-RouterFinding 'domain_membership_inconsistent' ($pathPrefix + '.domains') 'Skill and domain membership indexes are inconsistent.')) | Out-Null
                }
            }
            $skillIndex++
        }
        foreach ($domainName in @($domainSkills.Keys)) {
            foreach ($member in @($domainSkills[$domainName])) {
                if (-not $skillNameSet.Contains([string]$member)) {
                    $catalogFindings.Add((New-RouterFinding 'domain_membership_unknown' ("$.domains[{0}].skill_names" -f $domainName) 'Domain references a skill absent from the catalog.')) | Out-Null
                }
            }
        }
        foreach ($caller in @($catalogDependencies.Keys | Sort-Object)) {
            foreach ($dependency in @($catalogDependencies[$caller])) {
                if (-not $skillNameSet.Contains([string]$dependency)) {
                    $catalogFindings.Add((New-RouterFinding 'skill_dependency_unknown' ("$.skills[{0}].dependencies" -f $caller) 'Skill dependency must reference a catalog skill.')) | Out-Null
                }
            }
        }
        if ($catalogFindings.Count -eq 0) {
            foreach ($name in @($catalogDependencies.Keys | Sort-Object)) {
                $closure = Get-DependencyClosure $name $catalogDependencies
                if ($closure.has_cycle) {
                    $catalogFindings.Add((New-RouterFinding 'skill_dependency_cycle' '$.skills.dependencies' 'Skill dependency graph must be acyclic.')) | Out-Null
                    break
                }
            }
        }
    }
}

$domainNames = @($DomainHint | ForEach-Object { $_ -split ',' } | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Sort-Object -Unique)
$excludedNames = @(Get-NormalizedNames $ExcludeCapability | Sort-Object -Unique)
$rawRequestedNames = @(Get-NormalizedNames $Candidate)
$requestedNames = @($rawRequestedNames | Sort-Object -Unique)
if ($rawRequestedNames.Count -ne $requestedNames.Count) {
    $requestValid = $false
    $excluded.Add([pscustomobject][ordered]@{ kind = 'skill'; name = ''; reason = 'duplicate_candidate' }) | Out-Null
}

if ($catalogFindings.Count -eq 0 -and $null -ne $catalog) {
    $unknownDomains = @($domainNames | Where-Object { -not $domainNameSet.Contains($_) })
    if ($unknownDomains.Count -gt 0) {
        $requestValid = $false
        foreach ($domainName in $unknownDomains) {
            $excluded.Add([pscustomobject][ordered]@{ kind = 'domain'; name = $domainName; reason = 'unknown_domain' }) | Out-Null
        }
    }

    if ($requestValid) {
        $availableRows = [System.Collections.Generic.List[object]]::new()
        $allowedByDomain = if ($domainNames.Count -gt 0) {
            @($domainNames | ForEach-Object { @($domainSkills[$_]) } | Sort-Object -Unique)
        }
        else { @() }
        foreach ($skill in @($catalog.skills | Sort-Object name)) {
            $name = [string]$skill.name
            $path = [IO.Path]::GetFullPath((Join-Path $catalogRoot ([string]$skill.relative_path)))
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                $stale = $true
                $excluded.Add([pscustomobject][ordered]@{ kind = 'skill'; name = $name; reason = 'entrypoint_unavailable' }) | Out-Null
                continue
            }
            $expected = ([string]$skill.entrypoint_sha256).ToLowerInvariant()
            $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actual -cne $expected) {
                $stale = $true
                $excluded.Add([pscustomobject][ordered]@{ kind = 'skill'; name = $name; reason = 'catalog_stale' }) | Out-Null
                continue
            }
            $row = [pscustomobject][ordered]@{
                    kind = 'skill'
                    name = $name
                    description = [string]$skill.description
                    path = $path
                    availability = 'available'
                    load_side_effect = 'read_only'
                    side_effect = [string]$skill.side_effect
                    dependencies = @($catalogDependencies[$name])
                    entrypoint_hash_validated = $true
                    contained = $true
                }
            $availableRows.Add($row) | Out-Null
            if ($domainNames.Count -gt 0 -and $name -notin $allowedByDomain) { continue }
            if ($name -in $excludedNames) {
                $excluded.Add([pscustomobject][ordered]@{ kind = 'skill'; name = $name; reason = 'explicitly_excluded' }) | Out-Null
                continue
            }
            $rows.Add($row) | Out-Null
        }
        $allAvailableRows = @($availableRows.ToArray())
    }
    $catalogStatus = if ($stale) { 'stale' } else { 'current' }
}

$allRows = @($rows.ToArray())
$truncated = $allRows.Count -gt $MaxCandidates
$visible = @($allRows | Select-Object -First $MaxCandidates)
if ($catalogStatus -eq 'current' -and $requestValid) {
    foreach ($name in $requestedNames) {
        if ($name -in $excludedNames) {
            if (@($excluded | Where-Object { $_.name -eq $name -and $_.reason -eq 'explicitly_excluded' }).Count -eq 0) {
                $excluded.Add([pscustomobject][ordered]@{ kind = 'skill'; name = $name; reason = 'explicitly_excluded' }) | Out-Null
            }
            continue
        }
        $match = @($allAvailableRows | Where-Object name -eq $name)
        if ($match.Count -eq 1) { $selected.Add($match[0]) | Out-Null }
        elseif (@($excluded | Where-Object name -eq $name).Count -eq 0) {
            $excluded.Add([pscustomobject][ordered]@{ kind = 'skill'; name = $name; reason = 'not_available' }) | Out-Null
        }
    }
}

$selectedRows = @($selected.ToArray())
$rootSelectionPass = $catalogStatus -eq 'current' -and $requestValid -and
    $requestedNames.Count -gt 0 -and $requestedNames.Count -eq $selectedRows.Count
$closurePass = $rootSelectionPass
$validatedClosure = [System.Collections.Generic.List[object]]::new()
if ($rootSelectionPass) {
    $availableByName = @{}
    foreach ($row in $allAvailableRows) { $availableByName[[string]$row.name] = $row }
    $closureNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($selectedRow in $selectedRows) {
        $closure = Get-DependencyClosure ([string]$selectedRow.name) $catalogDependencies
        if ($closure.has_cycle -or @($closure.missing).Count -gt 0) {
            $closurePass = $false
            $excluded.Add([pscustomobject][ordered]@{ kind = 'skill'; name = [string]$selectedRow.name; reason = 'dependency_closure_invalid' }) | Out-Null
            continue
        }
        foreach ($closureName in @($closure.names)) {
            if (-not $availableByName.ContainsKey([string]$closureName)) {
                $closurePass = $false
                $excluded.Add([pscustomobject][ordered]@{ kind = 'skill'; name = [string]$closureName; reason = 'dependency_not_available'; required_by = [string]$selectedRow.name }) | Out-Null
                continue
            }
            if ($closureNames.Add([string]$closureName)) { $validatedClosure.Add($availableByName[[string]$closureName]) | Out-Null }
        }
    }
}
if (-not $closurePass) { $validatedClosure.Clear() }
$validatedClosureRows = @($validatedClosure.ToArray())
$loadPass = $rootSelectionPass -and $closurePass
$sideEffectRows = if ($loadPass) { $validatedClosureRows } else { $selectedRows }
$requiresReview = @($sideEffectRows | Where-Object side_effect -ne 'read_only').Count -gt 0
$authorizationReason = if ($selectedRows.Count -eq 0) { 'no_candidate_selected' }
elseif ($requiresReview) { 'workflow_side_effect_requires_host_review' }
else { 'host_authorization_required' }
$loadValidation = [ordered]@{
    requested = $requestedNames
    pass = $loadPass
    scope = 'skill_dependency_closure_load_only'
    checks = @('catalog_schema', 'catalog_fingerprint', 'catalog_root_containment', 'entrypoint_hash', 'availability', 'dependency_closure')
}
$routingReceiptInput = [ordered]@{
    query_sha256 = Get-TextSha256 $Query
    domain_hints = $domainNames
    requested_candidates = $requestedNames
    excluded_capabilities = $excludedNames
    catalog_fingerprint = if ($null -ne $catalog) { [string]$catalog.catalog_fingerprint } else { '' }
}
$routingReceipt = [ordered]@{
    schema_version = 1
    receipt_id = ('crr-{0}' -f (Get-TextSha256 (($routingReceiptInput | ConvertTo-Json -Depth 10 -Compress))).Substring(0, 16))
    decision_owner = 'host_ai'
    semantic_routing_performed = $false
    query_sha256 = [string]$routingReceiptInput.query_sha256
    catalog_fingerprint = [string]$routingReceiptInput.catalog_fingerprint
    selection_required = $requestedNames.Count -eq 0
    requested_candidates = $requestedNames
    validated_candidates = if ($loadPass) { @($selectedRows | ForEach-Object { [string]$_.name }) } else { @() }
    validated_closure = if ($loadPass) { @($validatedClosureRows | ForEach-Object { [string]$_.name }) } else { @() }
    status = if ($loadPass) { 'validated' } elseif ($catalogStatus -eq 'current' -and $requestValid) { 'candidates_returned' } else { 'blocked' }
    truth_boundary = if ($loadPass) { 'candidate_load_validated' } elseif ($catalogStatus -eq 'current' -and $requestValid) { 'candidate_discovery_only' } else { 'candidate_discovery_blocked' }
    writes_performed = $false
    provider_calls = 0
    native_mutations = 0
}

[pscustomobject][ordered]@{
    schema_version = 1
    decision_owner = 'host_ai'
    semantic_routing_performed = $false
    query_received = (-not [string]::IsNullOrWhiteSpace($Query))
    catalog_path = $catalogFile
    catalog_resolution = [ordered]@{ mode = [string]$resolution.mode; auto_discover_requested = [bool]$AutoDiscover }
    catalog = [ordered]@{ status = $catalogStatus; skill_count = $catalogSkillCount; findings = @($catalogFindings.ToArray()) }
    discovery_domains = if ($null -ne $catalog -and $catalogFindings.Count -eq 0) { @($catalog.domains | Select-Object name, purpose) } else { @() }
    retrieval = [ordered]@{ strategy = 'catalog_discovery'; candidates = $visible; truncated = $truncated }
    selected = $selectedRows
    validated_closure = $validatedClosureRows
    excluded = @($excluded.ToArray())
    load_validation = $loadValidation
    validation = $loadValidation
    routing_receipt = $routingReceipt
    execution_authorization = [ordered]@{ status = 'not_granted'; requires_review = $requiresReview; reason = $authorizationReason }
    writes_performed = $false
    provider_calls = 0
    native_mutations = 0
} | ConvertTo-Json -Depth 20 -Compress
