function New-CapabilityInventory {
    param([object[]]$Descriptors = @(), [string]$GeneratedAt = 'not_recorded')
    $valid = New-Object System.Collections.Generic.List[object]
    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($descriptor in @($Descriptors)) {
        $validation = Test-CapabilityDescriptorContract $descriptor
        if ($validation.pass) { $valid.Add($descriptor) | Out-Null }
        else { foreach ($finding in @($validation.findings)) { $findings.Add($finding) | Out-Null } }
    }
    $decisions = New-Object System.Collections.Generic.List[object]
    foreach ($group in @($valid.ToArray() | Group-Object { '{0}|{1}' -f ([string]$_.kind).ToLowerInvariant(), ([string]$_.name).ToLowerInvariant() })) {
        $items = @($group.Group | Sort-Object id)
        if ($items.Count -eq 1) {
            $decisions.Add([pscustomobject][ordered]@{ key = $group.Name; descriptor_ids = @($items.id); disposition = 'canonical'; reason = 'single_descriptor' }) | Out-Null
            continue
        }
        $sourceKeys = @($items | ForEach-Object { '{0}|{1}|{2}' -f $_.truth_origin, $_.source.type, $_.source.path_or_url } | Sort-Object -Unique)
        $activeCount = @($items | Where-Object lifecycle -eq 'active').Count
        $inactiveCount = @($items | Where-Object { $_.lifecycle -in @('deprecated', 'historical') }).Count
        $disposition = if ($sourceKeys.Count -eq 1) { 'duplicate' } elseif ($activeCount -gt 0 -and $inactiveCount -gt 0) { 'conflict' } else { 'alternative' }
        $reason = if ($disposition -eq 'conflict') { 'lifecycle_truth_must_remain_separate' } else { 'multiple_truth_origins_or_sources' }
        $decisions.Add([pscustomobject][ordered]@{ key = $group.Name; descriptor_ids = @($items.id); disposition = $disposition; reason = $reason }) | Out-Null
    }
    return [pscustomobject][ordered]@{
        schema_version = 1; read_only = $true; generated_at = $GeneratedAt
        descriptors = @($valid.ToArray() | Sort-Object kind, name, truth_origin, id)
        decisions = @($decisions.ToArray() | Sort-Object key)
        findings = @($findings.ToArray()); provider_calls = 0; native_mutations = 0; writes = 0; profile_changed = $false
    }
}

function Get-CapabilitySurfaceFileHash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-CapabilitySurfaceTextHash([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([string]$Text)) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $sha.Dispose() }
}

function Resolve-CapabilitySurfacePath([string]$Path, [string]$RepoRoot) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $value = [Environment]::ExpandEnvironmentVariables($Path.Trim())
    if ($value.StartsWith('~/') -or $value.StartsWith('~\')) { $value = Join-Path $HOME $value.Substring(2) }
    if (-not [IO.Path]::IsPathRooted($value)) { $value = Join-Path $RepoRoot $value }
    return [IO.Path]::GetFullPath($value)
}

function Get-CapabilitySurfaceSkillMetadata([string]$SkillPath, [string]$Owner, [string]$ProjectionState, [bool]$Resident) {
    $text = if (Test-Path -LiteralPath $SkillPath -PathType Leaf) { [IO.File]::ReadAllText($SkillPath) } else { '' }
    $name = Split-Path (Split-Path $SkillPath -Parent) -Leaf
    $description = ''
    if ($text -match '(?m)^name\s*:\s*["'']?([^\r\n"'']+)') { $name = $matches[1].Trim() }
    if ($text -match '(?m)^description\s*:\s*["'']?([^\r\n"'']+)') { $description = $matches[1].Trim() }
    return [pscustomobject][ordered]@{ name = $name; path = [IO.Path]::GetFullPath($SkillPath); entrypoint_hash = if ($text) { Get-CapabilitySurfaceFileHash $SkillPath } else { $null }; description_hash = if ($description) { Get-CapabilitySurfaceTextHash $description } else { $null }; owner = $Owner; resident = $Resident; projection_state = $ProjectionState }
}

function New-CapabilitySurfaceRecord([string]$Name, [string]$Authority, [string]$Source, [string]$Freshness, [string]$Coverage, [object[]]$Items) {
    $ordered = @($Items | Sort-Object name, path)
    $canonical = @($ordered | ForEach-Object { '{0}|{1}|{2}|{3}|{4}' -f $_.name, $_.entrypoint_hash, $_.description_hash, $_.owner, $_.projection_state }) -join "`n"
    return [pscustomobject][ordered]@{ name = $Name; authority = $Authority; source = $Source; fingerprint = Get-CapabilitySurfaceTextHash $canonical; freshness = $Freshness; coverage = $Coverage; count = $ordered.Count; items = $ordered }
}

function New-SkillSurfaceView {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$RepoRoot, [Parameter(Mandatory = $true)]$Config, [string]$HostSnapshotPath, [string]$GeneratedAt = ([datetimeoffset]::UtcNow.ToString('o')))
    $root = [IO.Path]::GetFullPath($RepoRoot)
    $projection = $Config.skill_projection
    $surfaces = [Collections.Generic.List[object]]::new()
    $findings = [Collections.Generic.List[object]]::new()

    $repoSupplyRoot = Join-Path $root 'agent'
    $repoItems = if (Test-Path -LiteralPath $repoSupplyRoot) { @(Get-ChildItem -LiteralPath $repoSupplyRoot -Recurse -File -Filter 'SKILL.md' -Force | ForEach-Object { Get-CapabilitySurfaceSkillMetadata $_.FullName 'repo_generated' 'repo_supply' $false }) } else { @() }
    $surfaces.Add((New-CapabilitySurfaceRecord 'repo_supply' 'repository_generated_supply' $repoSupplyRoot 'fresh' $(if ($repoItems.Count) { 'complete' } else { 'not_materialized' }) $repoItems)) | Out-Null

    $projectionPath = Resolve-CapabilitySurfacePath ([string]$projection.manifest_path) $root
    $projectionItems = @(); $projectionFreshness = 'unknown'; $projectionCoverage = 'not_observed'
    if ($projectionPath -and (Test-Path -LiteralPath $projectionPath -PathType Leaf)) {
        $manifest = [IO.File]::ReadAllText($projectionPath) | ConvertFrom-Json
        $projectionItems = @($manifest.canonical | ForEach-Object { $path = [string]$_.path; $entry = if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) { $path } elseif ($path -and (Test-Path -LiteralPath (Join-Path $path 'SKILL.md'))) { Join-Path $path 'SKILL.md' } else { Join-Path $repoSupplyRoot ('{0}\SKILL.md' -f $_.name) }; Get-CapabilitySurfaceSkillMetadata $entry 'canonical_projection' 'canonical' $false })
        $head = @(& git -C $root rev-parse HEAD 2>$null)
        $projectionFreshness = if ($head.Count -and [string]$manifest.source_revision -eq ([string]$head[0]).Trim()) { 'fresh' } else { 'stale' }
        $projectionCoverage = 'complete'
    }
    $surfaces.Add((New-CapabilitySurfaceRecord 'canonical_projection' 'projection_manifest' $projectionPath $projectionFreshness $projectionCoverage $projectionItems)) | Out-Null

    $userRoot = Resolve-CapabilitySurfacePath ([string]$projection.user_skill_root) $root
    $managedSource = Resolve-CapabilitySurfacePath ([string]$projection.managed_source_path) $root
    $managedIncludes = @($projection.managed_link_includes | ForEach-Object { [string]$_ })
    $userItems = [Collections.Generic.List[object]]::new()
    if ($userRoot -and (Test-Path -LiteralPath $userRoot -PathType Container)) {
        foreach ($directory in @(Get-ChildItem -LiteralPath $userRoot -Directory -Force)) {
            $entry = Join-Path $directory.FullName 'SKILL.md'; if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { continue }
            $targetText = @($directory.Target | ForEach-Object { [string]$_ }) -join ';'
            $state = if ($managedIncludes -contains $directory.Name) { 'managed_current' } elseif ($targetText -and $managedSource -and $targetText.StartsWith($managedSource, [StringComparison]::OrdinalIgnoreCase)) { 'managed_stale' } elseif ($targetText) { 'external_owned' } else { 'ownership_unknown' }
            $owner = if ($state -in @('managed_current', 'managed_stale')) { 'skills_manager' } elseif ($state -eq 'external_owned') { 'external' } else { 'unknown' }
            $userItems.Add((Get-CapabilitySurfaceSkillMetadata $entry $owner $state ($state -eq 'managed_current'))) | Out-Null
        }
    }
    $surfaces.Add((New-CapabilitySurfaceRecord 'user_skill_root' 'filesystem_observation' $userRoot 'fresh' 'complete' $userItems.ToArray())) | Out-Null

    $codexHome = if ($env:CODEX_HOME) { [IO.Path]::GetFullPath($env:CODEX_HOME) } else { Join-Path $HOME '.codex' }
    $systemRoot = Join-Path $codexHome 'skills\.system'
    $systemItems = if (Test-Path -LiteralPath $systemRoot) { @(Get-ChildItem -LiteralPath $systemRoot -Recurse -File -Filter 'SKILL.md' -Force | ForEach-Object { Get-CapabilitySurfaceSkillMetadata $_.FullName 'host_system' 'system' $true }) } else { @() }
    $surfaces.Add((New-CapabilitySurfaceRecord 'system' 'host_filesystem' $systemRoot 'fresh' $(if ($systemItems.Count) { 'complete' } else { 'not_observed' }) $systemItems)) | Out-Null

    $pluginRoot = Resolve-CapabilitySurfacePath ([string]$projection.external_skill_inventory.plugin_cache_path) $root
    $pluginItems = if ($pluginRoot -and (Test-Path -LiteralPath $pluginRoot)) { @(Get-ChildItem -LiteralPath $pluginRoot -Recurse -File -Filter 'SKILL.md' -Force | ForEach-Object { Get-CapabilitySurfaceSkillMetadata $_.FullName 'plugin_cache' 'plugin_cache' $true }) } else { @() }
    $surfaces.Add((New-CapabilitySurfaceRecord 'plugin_cache' 'host_plugin_cache' $pluginRoot 'fresh' $(if ($pluginItems.Count) { 'complete' } else { 'not_observed' }) $pluginItems)) | Out-Null

    $hostItems = @(); $hostFreshness = 'unknown'; $hostCoverage = 'not_observed'; $hostSource = if ($HostSnapshotPath) { [IO.Path]::GetFullPath($HostSnapshotPath) } else { 'not_provided' }
    if ($HostSnapshotPath) {
        if (-not (Test-Path -LiteralPath $hostSource -PathType Leaf)) { throw ('Host snapshot not found: {0}' -f $hostSource) }
        $snapshot = [IO.File]::ReadAllText($hostSource) | ConvertFrom-Json
        $snapshotSkills = if ($null -ne $snapshot.skills) { @($snapshot.skills) } elseif ($null -ne $snapshot.visible_skills) { @($snapshot.visible_skills) } elseif ($null -ne $snapshot.data.skills) { @($snapshot.data.skills) } else { @() }
        $hostItems = @($snapshotSkills | ForEach-Object { [pscustomobject][ordered]@{ name = [string]$_.name; path = [string]$_.path; entrypoint_hash = [string]$_.entrypoint_hash; description_hash = [string]$_.description_hash; owner = 'host_snapshot'; resident = $true; projection_state = 'host_visible' } })
        $captured = [datetimeoffset]::MinValue
        $hostFreshness = if ([datetimeoffset]::TryParse([string]$snapshot.captured_at, [ref]$captured) -and ([datetimeoffset]::UtcNow - $captured).TotalHours -ge 0 -and ([datetimeoffset]::UtcNow - $captured).TotalHours -le 24) { 'fresh' } else { 'stale' }
        $hostCoverage = if ([string]$snapshot.coverage) { [string]$snapshot.coverage } else { 'partial' }
        foreach ($item in $hostItems) { if ([string]::IsNullOrWhiteSpace($item.name) -or [string]::IsNullOrWhiteSpace($item.entrypoint_hash) -or [string]::IsNullOrWhiteSpace($item.description_hash)) { $findings.Add([pscustomobject]@{ code = 'host_skill_identity_incomplete'; severity = 'error'; surface = 'host_visible'; path = $item.path; message = 'Host-visible skills require name and entrypoint/description fingerprints.' }) | Out-Null } }
    }
    $surfaces.Add((New-CapabilitySurfaceRecord 'host_visible' 'host_snapshot' $hostSource $hostFreshness $hostCoverage $hostItems)) | Out-Null
    foreach ($surface in $surfaces) {
        foreach ($field in @('authority', 'source', 'fingerprint', 'freshness', 'coverage')) { if ([string]::IsNullOrWhiteSpace([string]$surface.$field)) { $findings.Add([pscustomobject]@{ code = 'surface_field_missing'; severity = 'error'; surface = $surface.name; path = $field; message = 'Skill surface identity is incomplete.' }) | Out-Null } }
        foreach ($item in @($surface.items)) {
            $identityValid = -not [string]::IsNullOrWhiteSpace([string]$item.name) -and -not [string]::IsNullOrWhiteSpace([string]$item.path) -and [string]$item.entrypoint_hash -match '^[a-f0-9]{64}$' -and [string]$item.description_hash -match '^[a-f0-9]{64}$' -and -not [string]::IsNullOrWhiteSpace([string]$item.owner) -and -not [string]::IsNullOrWhiteSpace([string]$item.projection_state) -and $item.resident -is [bool]
            if (-not $identityValid) { $findings.Add([pscustomobject]@{ code = 'surface_skill_identity_incomplete'; severity = 'error'; surface = $surface.name; path = [string]$item.path; message = 'Skill surface items require name/path/entrypoint/description/owner/resident/projection identity.' }) | Out-Null }
        }
    }
    return [pscustomobject][ordered]@{ schema_version = 1; view = 'SkillSurfaceView'; generated_at = $GeneratedAt; read_only = $true; pass = (@($findings | Where-Object severity -eq 'error').Count -eq 0); surfaces = $surfaces.ToArray(); surface_count = $surfaces.Count; stale_links = @($userItems | Where-Object projection_state -in @('managed_stale', 'external_owned', 'ownership_unknown')); findings = $findings.ToArray(); provider_calls = 0; native_mutations = 0; writes = 0; profile_changed = $false }
}

function ConvertTo-CapabilityDescriptorsFromSkillsConfig {
    param($Config, [string]$SourcePath = 'skills.json', [string]$SourceRevision = 'working-tree')
    $items = New-Object System.Collections.Generic.List[object]

    $domains = @(
        [pscustomobject]@{ field = 'vendors'; kind = 'skill'; component = 'vendor'; name_fields = @('name') },
        [pscustomobject]@{ field = 'imports'; kind = 'skill'; component = 'import'; name_fields = @('name', 'skill') },
        [pscustomobject]@{ field = 'mappings'; kind = 'skill'; component = 'mapping'; name_fields = @('to', 'from') },
        [pscustomobject]@{ field = 'mcp_servers'; kind = 'mcp'; component = 'mcp_server'; name_fields = @('name') }
    )

    foreach ($domain in $domains) {
        $value = Get-OperationObjectProperty $Config $domain.field
        $entries = New-Object System.Collections.Generic.List[object]
        if ($value -is [System.Collections.IDictionary]) {
            foreach ($key in @($value.Keys)) { $entries.Add([pscustomobject]@{ name = [string]$key; value = $value[$key] }) | Out-Null }
        }
        elseif ($value -is [array] -or $value -is [System.Collections.IList]) {
            $index = 0
            foreach ($entry in @($value)) {
                $name = $null
                foreach ($field in @($domain.name_fields)) {
                    $candidate = [string](Get-OperationObjectProperty $entry $field)
                    if (-not [string]::IsNullOrWhiteSpace($candidate)) { $name = $candidate; break }
                }
                if ([string]::IsNullOrWhiteSpace($name)) { $name = '{0}-{1}' -f $domain.component, $index }
                if ($domain.field -eq 'imports') {
                    $skillPath = [string](Get-OperationObjectProperty $entry 'skill')
                    if (-not [string]::IsNullOrWhiteSpace($skillPath)) { $name = '{0}/{1}' -f $name, $skillPath.Replace('\', '/') }
                }
                $entries.Add([pscustomobject]@{ name = $name; value = $entry }) | Out-Null
                $index++
            }
        }
        elseif ($value -is [pscustomobject]) {
            $explicitName = $null
            foreach ($field in @($domain.name_fields)) {
                $candidate = [string](Get-OperationObjectProperty $value $field)
                if (-not [string]::IsNullOrWhiteSpace($candidate)) { $explicitName = $candidate; break }
            }
            if (-not [string]::IsNullOrWhiteSpace($explicitName)) {
                $entries.Add([pscustomobject]@{ name = $explicitName; value = $value }) | Out-Null
            }
            else {
                foreach ($property in @($value.PSObject.Properties)) { $entries.Add([pscustomobject]@{ name = [string]$property.Name; value = $property.Value }) | Out-Null }
            }
        }

        foreach ($entry in @($entries.ToArray())) {
            $source = [pscustomobject]@{ type = 'repo_config'; path_or_url = ('{0}#{1}' -f $SourcePath, $domain.field); revision = $SourceRevision; checksum = $null; license = $null; trust_tier = 'runtime' }
            $component = [pscustomobject]@{ kind = $domain.component; config = Protect-OperationSensitiveValue $entry.value 'config' }
            $items.Add((New-CapabilityDescriptor -Kind $domain.kind -Name $entry.name -TruthOrigin runtime -Source $source -Lifecycle active -Components @($component) -VerificationState static_validated)) | Out-Null
        }
    }
    return $items.ToArray()
}
