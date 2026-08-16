$skillProjectionPlanningRepoRoot = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'skills.json') -PathType Leaf) { $PSScriptRoot } else { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
if ($null -eq (Get-Command Get-CodexPluginSkillInventory -ErrorAction SilentlyContinue)) { . (Join-Path $skillProjectionPlanningRepoRoot 'src\Infrastructure\CodexCli.ps1') }
if ($null -eq (Get-Command Read-SkillMetadata -ErrorAction SilentlyContinue)) { . (Join-Path $skillProjectionPlanningRepoRoot 'src\Domain\SkillMetadata.ps1') }
if ($null -eq (Get-Command Need -ErrorAction SilentlyContinue)) { . (Join-Path $skillProjectionPlanningRepoRoot 'src\Core.ps1') }

function Get-SkillProjectionObjectProperty($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    if ($Object -is [Collections.IDictionary]) { $value = $Object[$Name] }
    else {
        $property = $Object.PSObject.Properties[$Name]
        if ($null -eq $property) { $value = $null }
        else { $value = $property.Value }
    }
    if ($value -is [Array]) { return ,$value }
    return $value
}

function Test-SkillProjectionObjectProperty($Object, [string]$Name) {
    if ($null -eq $Object) { return $false }
    if ($Object -is [Collections.IDictionary]) { return $Object.Contains($Name) }
    return $null -ne $Object.PSObject.Properties[$Name]
}

function Resolve-SkillProjectionPath([string]$Path, [string]$RepoRoot = '') {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
        $repoRootVariable = Get-Variable -Name Root -Scope Script -ErrorAction SilentlyContinue
        $RepoRoot = if ($null -ne $repoRootVariable -and -not [string]::IsNullOrWhiteSpace([string]$repoRootVariable.Value)) { [string]$repoRootVariable.Value } else { $skillProjectionPlanningRepoRoot }
    }
    $resolved = $Path.Trim()
    if ($resolved.StartsWith('~')) { $resolved = $resolved -replace '^~', [Environment]::GetFolderPath('UserProfile') }
    $resolved = $resolved.Replace('/', '\')
    if (-not [IO.Path]::IsPathRooted($resolved)) { $resolved = Join-Path $RepoRoot $resolved }
    return [IO.Path]::GetFullPath($resolved)
}

function Test-SkillProjectionPathWithinRoot([string]$Path, [string]$Root) {
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
    $candidate = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $boundary = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    return [string]::Equals($candidate, $boundary, [StringComparison]::OrdinalIgnoreCase) -or
        $candidate.StartsWith(($boundary + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)
}

function Get-CodexExternalSkillInventory($ProjectionConfig) {
    $disabled = [pscustomobject]@{ enabled = $false; authority = 'codex_plugin_list_json'; freshness = 'unknown'; coverage = 'not_configured'; enabled_plugin_ids = @(); plugin_count = 0; skill_count = 0; metadata_chars = 0; skills = @(); warnings = @() }
    if ($null -eq $ProjectionConfig) { return $disabled }
    $inventoryConfig = Get-SkillProjectionObjectProperty $ProjectionConfig 'external_skill_inventory'
    if ($null -eq $inventoryConfig) { return $disabled }
    $enabledRaw = Get-SkillProjectionObjectProperty $inventoryConfig 'enabled'
    $enabled = ($null -eq $enabledRaw) -or [bool]$enabledRaw
    if (-not $enabled) { $disabled.coverage = 'disabled'; return $disabled }
    $result = Get-CodexPluginSkillInventory
    $result | Add-Member -NotePropertyName enabled -NotePropertyValue $true -Force
    return $result
}

function Get-SkillProjectionFiles([string]$RootPath) {
    $files = [Collections.Generic.List[object]]::new()
    if ([string]::IsNullOrWhiteSpace($RootPath) -or -not (Test-Path -LiteralPath $RootPath -PathType Container)) { return @() }
    foreach ($directory in @(Get-ChildItem -LiteralPath $RootPath -Directory -Force -ErrorAction Stop | Sort-Object Name)) {
        if ($directory.Name -eq '.system') {
            foreach ($systemDirectory in @(Get-ChildItem -LiteralPath $directory.FullName -Directory -Force -ErrorAction Stop | Sort-Object Name)) {
                $systemFile = Join-Path $systemDirectory.FullName 'SKILL.md'
                if (Test-Path -LiteralPath $systemFile -PathType Leaf) { $files.Add([pscustomobject]@{ file = $systemFile; dir = $systemDirectory.FullName; is_system = $true }) | Out-Null }
            }
            continue
        }
        $skillFile = Join-Path $directory.FullName 'SKILL.md'
        if (Test-Path -LiteralPath $skillFile -PathType Leaf) { $files.Add([pscustomobject]@{ file = $skillFile; dir = $directory.FullName; is_system = $false }) | Out-Null }
    }
    return @($files.ToArray())
}

function Get-SkillPackageContentHash([string]$SkillDirectory) {
    if ([string]::IsNullOrWhiteSpace($SkillDirectory) -or -not (Test-Path -LiteralPath $SkillDirectory -PathType Container)) { return 'missing' }
    $base = [IO.Path]::GetFullPath($SkillDirectory).TrimEnd('\', '/')
    $parts = [Collections.Generic.List[string]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $base -Recurse -File -Force -ErrorAction Stop | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($base.Length).TrimStart('\', '/').Replace('\', '/')
        $parts.Add(('{0}|{1}' -f $relative, (Get-FileContentHash $file.FullName))) | Out-Null
    }
    return Get-SkillProjectionTextHash ($parts.ToArray() -join "`n")
}

function Get-SkillProjectionTextHash([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([string]$Text)) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $sha.Dispose() }
}

function Get-SkillProjectionSourceEntries($Source, [int]$SourceOrder, [string]$RepoRoot = '') {
    $id = [string](Get-SkillProjectionObjectProperty $Source 'id')
    $rootPath = Resolve-SkillProjectionPath ([string](Get-SkillProjectionObjectProperty $Source 'path')) $RepoRoot
    Need (Test-Path -LiteralPath $rootPath -PathType Container) ('skill_projection source root not found: {0}' -f $rootPath)
    $priorityRaw = Get-SkillProjectionObjectProperty $Source 'priority'
    $priority = if ($null -eq $priorityRaw) { 0 } else { [int]$priorityRaw }
    $platformsRaw = Get-SkillProjectionObjectProperty $Source 'platforms'
    $platforms = if ($null -eq $platformsRaw) { @('codex') } else { @($platformsRaw | ForEach-Object { [string]$_ }) }
    $entries = [Collections.Generic.List[object]]::new()
    foreach ($item in @(Get-SkillProjectionFiles $rootPath)) {
        $metadata = Read-SkillMetadata ([string]$item.file) -Observation
        $declaredName = ([string]$metadata.declared_name).Trim()
        if ([string]::IsNullOrWhiteSpace($declaredName)) { $declaredName = Split-Path ([string]$item.dir) -Leaf }
        $effectivePriority = $priority + $(if ([bool]$item.is_system) { 100000 } else { 0 })
        $entries.Add([pscustomobject][ordered]@{
                name = $declaredName
                description = [string]$metadata.description
                source_id = $id
                source_root = $rootPath
                source_order = $SourceOrder
                priority = $effectivePriority
                is_system = [bool]$item.is_system
                path = [IO.Path]::GetFullPath([string]$item.file)
                skill_dir = [IO.Path]::GetFullPath([string]$item.dir)
                content_hash = [string](Get-FileContentHash ([string]$item.file))
                package_hash = [string](Get-SkillPackageContentHash ([string]$item.dir))
                target_platforms = @($platforms)
            }) | Out-Null
    }
    return @($entries.ToArray())
}

function New-SkillProjectionPlan($ProjectionConfig, [string]$RepoRoot = '', [switch]$OmitExternalInventory) {
    Need ($null -ne $ProjectionConfig) 'skill_projection 配置为空'
    $enabledRaw = Get-SkillProjectionObjectProperty $ProjectionConfig 'enabled'
    $enabled = ($null -eq $enabledRaw) -or [bool]$enabledRaw
    if (-not $enabled) {
        return [pscustomobject]@{ schema_version = 2; enabled = $false; skills = @(); canonical = @(); active = @(); disabled = @(); conflicts = @(); unique_names = @(); active_names = @(); duplicate_name_groups = 0; skill_metadata_chars = 0; external_skill_count = 0; external_skill_metadata_chars = 0; estimated_metadata_chars = 0; external_skills = @(); external_inventory_warnings = @() }
    }
    $sources = Get-SkillProjectionObjectProperty $ProjectionConfig 'sources'
    Need ($null -ne $sources) 'skill_projection 缺少 sources'
    $all = [Collections.Generic.List[object]]::new()
    $sourceOrder = 0
    foreach ($source in @($sources)) {
        Need ($null -ne $source) 'skill_projection.sources 不能包含空值'
        Need (-not [string]::IsNullOrWhiteSpace([string](Get-SkillProjectionObjectProperty $source 'id'))) 'skill_projection source 缺少 id'
        Need (-not [string]::IsNullOrWhiteSpace([string](Get-SkillProjectionObjectProperty $source 'path'))) ('skill_projection source 缺少 path：{0}' -f [string](Get-SkillProjectionObjectProperty $source 'id'))
        foreach ($entry in @(Get-SkillProjectionSourceEntries $source $sourceOrder $RepoRoot)) { $all.Add($entry) | Out-Null }
        $sourceOrder++
    }
    $groups = @{}
    foreach ($entry in @($all.ToArray())) {
        $key = ([string]$entry.name).ToLowerInvariant()
        if (-not $groups.ContainsKey($key)) { $groups[$key] = [Collections.Generic.List[object]]::new() }
        $groups[$key].Add($entry) | Out-Null
    }
    $canonical = [Collections.Generic.List[object]]::new()
    $disabled = [Collections.Generic.List[object]]::new()
    $conflicts = [Collections.Generic.List[object]]::new()
    $duplicateGroups = 0
    foreach ($key in @($groups.Keys | Sort-Object)) {
        $candidates = @($groups[$key].ToArray() | Sort-Object @{ Expression = 'priority'; Descending = $true }, @{ Expression = 'source_order'; Ascending = $true }, @{ Expression = 'path'; Ascending = $true })
        if ($candidates.Count -eq 0) { continue }
        $winner = $candidates[0]
        $canonical.Add($winner) | Out-Null
        if ($candidates.Count -le 1) { continue }
        $duplicateGroups++
        $hashes = @($candidates | ForEach-Object { [string]$_.package_hash } | Sort-Object -Unique)
        $isConflict = $hashes.Count -gt 1
        if ($isConflict) {
            $conflicts.Add([pscustomobject][ordered]@{ name = [string]$winner.name; winner_path = [string]$winner.path; winner_source_id = [string]$winner.source_id; candidate_paths = @($candidates | ForEach-Object { [string]$_.path }); package_hashes = @($hashes); resolution = 'priority' }) | Out-Null
        }
        foreach ($loser in @($candidates | Select-Object -Skip 1)) {
            $disabled.Add([pscustomobject][ordered]@{ name = [string]$loser.name; path = [string]$loser.path; source_id = [string]$loser.source_id; source_root = [string]$loser.source_root; content_hash = [string]$loser.content_hash; package_hash = [string]$loser.package_hash; target_platforms = @($loser.target_platforms); canonical_path = [string]$winner.path; canonical_source_id = [string]$winner.source_id; decision = if ($isConflict) { 'conflict_priority_winner' } else { 'duplicate_same_content' } }) | Out-Null
        }
    }
    $active = [Collections.Generic.List[object]]::new()
    foreach ($entry in @($canonical.ToArray() | Sort-Object name)) {
        $active.Add($entry) | Out-Null
    }
    $externalInventory = if ($OmitExternalInventory) { [pscustomobject]@{ skill_count = 0; metadata_chars = 0; skills = @(); warnings = @() } } else { Get-CodexExternalSkillInventory $ProjectionConfig }
    $skillMetadataChars = 0
    foreach ($entry in @($active.ToArray())) { $skillMetadataChars += ([string]$entry.name).Length + ([string]$entry.description).Length }
    return [pscustomobject][ordered]@{
        schema_version = 2; enabled = $true; conflict_policy = 'system_then_priority_then_source_order'
        skills = @($all.ToArray() | Sort-Object name, @{ Expression = 'priority'; Descending = $true }, path)
        canonical = @($canonical.ToArray() | Sort-Object name); active = @($active.ToArray() | Sort-Object name)
        disabled = @($disabled.ToArray() | Sort-Object name, path); conflicts = @($conflicts.ToArray() | Sort-Object name)
        unique_names = @($canonical.ToArray() | ForEach-Object { [string]$_.name } | Sort-Object)
        active_names = @($active.ToArray() | ForEach-Object { [string]$_.name } | Sort-Object)
        duplicate_name_groups = $duplicateGroups; skill_metadata_chars = $skillMetadataChars
        external_skill_count = [int]$externalInventory.skill_count; external_skill_metadata_chars = [int]$externalInventory.metadata_chars
        estimated_metadata_chars = $skillMetadataChars + [int]$externalInventory.metadata_chars
        external_skills = @($externalInventory.skills); external_inventory_warnings = @($externalInventory.warnings)
    }
}

function Get-SkillProjectionPlanFingerprint($Plan, $NativeProjectionPlan = $null) {
    $identity = [ordered]@{
        enabled = [bool]$Plan.enabled
        canonical = @($Plan.canonical | Sort-Object name, path | ForEach-Object { [ordered]@{ name = [string]$_.name; path = [IO.Path]::GetFullPath([string]$_.path); content_hash = [string]$_.content_hash; package_hash = [string]$_.package_hash } })
        disabled = @($Plan.disabled | Sort-Object name, path | ForEach-Object { [ordered]@{ name = [string]$_.name; path = [IO.Path]::GetFullPath([string]$_.path); decision = [string]$_.decision } })
        native = if ($null -eq $NativeProjectionPlan) { $null } else {
            [ordered]@{
                target_root = [IO.Path]::GetFullPath([string]$NativeProjectionPlan.target_root)
                skills = @($NativeProjectionPlan.skills | Sort-Object name, target_path | ForEach-Object { [ordered]@{ name = [string]$_.name; source_path = [IO.Path]::GetFullPath([string]$_.source_path); target_path = [IO.Path]::GetFullPath([string]$_.target_path); content_hash = [string]$_.content_hash; metadata_hash = [string]$_.metadata_hash } })
                removals = @($NativeProjectionPlan.removals | Sort-Object name, target_directory | ForEach-Object { [ordered]@{ name = [string]$_.name; target_directory = [IO.Path]::GetFullPath([string]$_.target_directory); previous_link_target = [string]$_.previous_link_target } })
            }
        }
    }
    return Get-SkillProjectionTextHash ($identity | ConvertTo-Json -Depth 12 -Compress)
}

function Add-SkillProjectionManifestFinding($Findings, [string]$Code, [string]$Path, [string]$Message) {
    $Findings.Add([pscustomobject][ordered]@{ code = $Code; severity = 'error'; path = $Path; message = $Message }) | Out-Null
}

function Test-SkillProjectionManifestCurrent($Manifest, $ProjectionConfig, [string]$RepoRoot) {
    $findings = [Collections.Generic.List[object]]::new()
    $requiredScalars = @('schema_version', 'projection_fingerprint', 'enabled', 'source_count', 'skill_entry_count', 'unique_name_count', 'active_name_count', 'duplicate_name_groups', 'disabled_path_count', 'conflict_count')
    $requiredArrays = @('skills', 'canonical', 'active', 'disabled', 'conflicts')
    foreach ($name in $requiredScalars + $requiredArrays) {
        if (-not (Test-SkillProjectionObjectProperty $Manifest $name)) { Add-SkillProjectionManifestFinding $findings 'projection_manifest_field_missing' ('$.{0}' -f $name) 'Projection manifest field is required.' }
    }
    if ($findings.Count -eq 0) {
        if ([int](Get-SkillProjectionObjectProperty $Manifest 'schema_version') -ne 2) { Add-SkillProjectionManifestFinding $findings 'projection_manifest_schema_invalid' '$.schema_version' 'Only projection manifest schema version 2 is supported.' }
        if ((Get-SkillProjectionObjectProperty $Manifest 'enabled') -isnot [bool]) { Add-SkillProjectionManifestFinding $findings 'projection_manifest_field_invalid' '$.enabled' 'Projection manifest enabled must be boolean.' }
        if ([string](Get-SkillProjectionObjectProperty $Manifest 'projection_fingerprint') -notmatch '^[a-f0-9]{64}$') { Add-SkillProjectionManifestFinding $findings 'projection_manifest_field_invalid' '$.projection_fingerprint' 'Projection fingerprint must be lowercase SHA-256.' }
        foreach ($name in $requiredArrays) {
            $value = Get-SkillProjectionObjectProperty $Manifest $name
            if ($null -eq $value -or $value -is [string] -or $value -isnot [Collections.IEnumerable]) { Add-SkillProjectionManifestFinding $findings 'projection_manifest_field_invalid' ('$.{0}' -f $name) 'Projection manifest field must be an array.' }
        }
    }
    if ($findings.Count -gt 0) { return [pscustomobject]@{ pass = $false; freshness = 'invalid'; coverage = 'invalid'; findings = $findings.ToArray(); plan = $null } }

    $skills = Get-SkillProjectionObjectProperty $Manifest 'skills'; $canonical = Get-SkillProjectionObjectProperty $Manifest 'canonical'
    $active = Get-SkillProjectionObjectProperty $Manifest 'active'; $disabled = Get-SkillProjectionObjectProperty $Manifest 'disabled'; $conflicts = Get-SkillProjectionObjectProperty $Manifest 'conflicts'
    $manifestCounts = [ordered]@{ skill_entry_count = $skills.Count; unique_name_count = $canonical.Count; active_name_count = $active.Count; disabled_path_count = $disabled.Count; conflict_count = $conflicts.Count }
    foreach ($name in $manifestCounts.Keys) {
        if ([int](Get-SkillProjectionObjectProperty $Manifest $name) -ne [int]$manifestCounts[$name]) { Add-SkillProjectionManifestFinding $findings 'projection_manifest_count_invalid' ('$.{0}' -f $name) 'Projection manifest count does not match its array.' }
    }
    $configuredSources = Get-SkillProjectionObjectProperty $ProjectionConfig 'sources'
    $sourceRoots = @($configuredSources | ForEach-Object { Resolve-SkillProjectionPath ([string](Get-SkillProjectionObjectProperty $_ 'path')) $RepoRoot })
    foreach ($collectionName in @('skills', 'canonical', 'active', 'disabled')) {
        $collection = Get-SkillProjectionObjectProperty $Manifest $collectionName
        foreach ($entry in @($collection)) {
            $entryPath = Resolve-SkillProjectionPath ([string](Get-SkillProjectionObjectProperty $entry 'path')) $RepoRoot
            if ([string]::IsNullOrWhiteSpace($entryPath) -or -not @($sourceRoots | Where-Object { Test-SkillProjectionPathWithinRoot $entryPath $_ }).Count) {
                Add-SkillProjectionManifestFinding $findings 'projection_manifest_path_outside_source' ('$.{0}.path' -f $collectionName) 'Projection manifest paths must remain within a currently configured source root.'
            }
        }
    }
    foreach ($entry in $canonical) {
        if ([string](Get-SkillProjectionObjectProperty $entry 'content_hash') -notmatch '^[a-f0-9]{64}$' -or [string](Get-SkillProjectionObjectProperty $entry 'package_hash') -notmatch '^[a-f0-9]{64}$') {
            Add-SkillProjectionManifestFinding $findings 'projection_manifest_hash_invalid' '$.canonical' 'Canonical entries require lowercase SHA-256 content and package hashes.'
        }
    }
    if ($findings.Count -gt 0) { return [pscustomobject]@{ pass = $false; freshness = 'invalid'; coverage = 'invalid'; findings = $findings.ToArray(); plan = $null } }

    try { $plan = New-SkillProjectionPlan $ProjectionConfig $RepoRoot -OmitExternalInventory }
    catch {
        Add-SkillProjectionManifestFinding $findings 'projection_current_plan_invalid' '$.skill_projection' $_.Exception.Message
        return [pscustomobject]@{ pass = $false; freshness = 'invalid'; coverage = 'invalid'; findings = $findings.ToArray(); plan = $null }
    }
    $expectedCounts = [ordered]@{
        source_count = @($configuredSources).Count
        skill_entry_count = @($plan.skills).Count; unique_name_count = @($plan.unique_names).Count; active_name_count = @($plan.active_names).Count
        duplicate_name_groups = [int]$plan.duplicate_name_groups; disabled_path_count = @($plan.disabled).Count; conflict_count = @($plan.conflicts).Count
    }
    $stale = ([bool](Get-SkillProjectionObjectProperty $Manifest 'enabled') -ne [bool]$plan.enabled)
    foreach ($name in $expectedCounts.Keys) { if ([int](Get-SkillProjectionObjectProperty $Manifest $name) -ne [int]$expectedCounts[$name]) { $stale = $true } }
    $manifestPlan = [pscustomobject]@{ enabled = [bool](Get-SkillProjectionObjectProperty $Manifest 'enabled'); canonical = $canonical; disabled = $disabled }
    if ((Get-SkillProjectionPlanFingerprint $manifestPlan) -ne (Get-SkillProjectionPlanFingerprint $plan)) { $stale = $true }

    $nativePlan = $null
    $nativeConfig = Get-SkillProjectionObjectProperty $ProjectionConfig 'native_projection'
    if ($null -ne $nativeConfig -and [bool](Get-SkillProjectionObjectProperty $nativeConfig 'enabled') -and $null -ne (Get-Command New-NativeSkillProjectionRuntimePlan -ErrorAction SilentlyContinue)) {
        try {
            $managedRoot = Resolve-SkillProjectionPath ([string](Get-SkillProjectionObjectProperty $ProjectionConfig 'managed_source_path')) $RepoRoot
            $includedEntries = Get-SkillProjectionObjectProperty $ProjectionConfig 'managed_link_includes'
            $excludedEntries = Get-SkillProjectionObjectProperty $ProjectionConfig 'managed_link_excludes'
            $included = @($includedEntries | ForEach-Object { [string]$_ })
            $excluded = @($excludedEntries | ForEach-Object { [string]$_ })
            $nativePlan = New-NativeSkillProjectionRuntimePlan -ManagedRoot $managedRoot -Config ([pscustomobject]@{ skill_projection = $ProjectionConfig }) -IncludedNames $included -ExcludedNames $excluded
        }
        catch { Add-SkillProjectionManifestFinding $findings 'projection_native_plan_invalid' '$.skill_projection.native_projection' $_.Exception.Message }
    }
    if ($findings.Count -eq 0 -and $null -ne $nativePlan -and [string](Get-SkillProjectionObjectProperty $Manifest 'projection_fingerprint') -ne (Get-SkillProjectionPlanFingerprint $plan $nativePlan)) { $stale = $true }
    if ($findings.Count -gt 0) { return [pscustomobject]@{ pass = $false; freshness = 'invalid'; coverage = 'invalid'; findings = $findings.ToArray(); plan = $plan } }
    if ($stale) { Add-SkillProjectionManifestFinding $findings 'projection_manifest_stale' '$' 'Projection manifest no longer matches the current configuration and source inventory.' }
    return [pscustomobject]@{ pass = (-not $stale); freshness = $(if ($stale) { 'stale' } else { 'fresh' }); coverage = 'complete'; findings = $findings.ToArray(); plan = $plan }
}
