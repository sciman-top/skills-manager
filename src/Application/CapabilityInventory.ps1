$capabilityInventoryRepoRoot = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'skills.json') -PathType Leaf) { $PSScriptRoot } else { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
if ($null -eq (Get-Command Get-CodexPluginSkillInventory -ErrorAction SilentlyContinue)) { . (Join-Path $capabilityInventoryRepoRoot 'src\Infrastructure\CodexCli.ps1') }
if ($null -eq (Get-Command Read-SkillMetadata -ErrorAction SilentlyContinue)) { . (Join-Path $capabilityInventoryRepoRoot 'src\Domain\SkillMetadata.ps1') }

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
    $metadata = Read-SkillMetadata $SkillPath -Observation
    $text = [string]$metadata.text
    $name = if ([string]::IsNullOrWhiteSpace([string]$metadata.name)) { Split-Path (Split-Path $SkillPath -Parent) -Leaf } else { [string]$metadata.name }
    $description = [string]$metadata.description
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

    $pluginInventory = Get-CodexPluginSkillInventory
    $pluginItems = @($pluginInventory.skills | ForEach-Object { Get-CapabilitySurfaceSkillMetadata ([string]$_.path) 'codex_plugin' 'installed_enabled_plugin' $true })
    $surfaces.Add((New-CapabilitySurfaceRecord 'plugins' 'codex_plugin_list_json' 'codex plugin list --json' ([string]$pluginInventory.freshness) ([string]$pluginInventory.coverage) $pluginItems)) | Out-Null
    foreach ($warning in @($pluginInventory.warnings)) { $findings.Add([pscustomobject]@{ code = [string]$warning.code; severity = 'warning'; surface = 'plugins'; path = [string]$warning.subject; message = [string]$warning.message }) | Out-Null }
    $hostObservation = Get-CodexHostObservation -PluginInventory $pluginInventory -ExpectedMcpServers @($Config.mcp_servers)
    foreach ($warning in @($hostObservation.mcp.warnings) + @($hostObservation.doctor.warnings)) { $findings.Add([pscustomobject]@{ code = [string]$warning.code; severity = 'warning'; surface = 'host_observation'; path = [string]$warning.subject; message = [string]$warning.message }) | Out-Null }

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
    return [pscustomobject][ordered]@{ schema_version = 1; view = 'SkillSurfaceView'; generated_at = $GeneratedAt; read_only = $true; pass = (@($findings | Where-Object severity -eq 'error').Count -eq 0); surfaces = $surfaces.ToArray(); surface_count = $surfaces.Count; host_observation = $hostObservation; stale_links = @($userItems | Where-Object projection_state -in @('managed_stale', 'external_owned', 'ownership_unknown')); findings = $findings.ToArray(); provider_calls = 0; native_mutations = 0; writes = 0 }
}
