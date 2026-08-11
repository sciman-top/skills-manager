function Parse-ReadOnlyCapabilityOptions([object[]]$Tokens) {
    $result = [ordered]@{ json = $false; out_path = $null; view = $null; host_snapshot = $null }
    for ($i = 0; $i -lt @($Tokens).Count; $i++) {
        $token = [string]$Tokens[$i]
        switch ($token.ToLowerInvariant()) {
            '--json' { $result.json = $true }
            '--out' { if ($i + 1 -ge @($Tokens).Count) { throw '--out requires a report file path.' }; $i++; $result.out_path = [string]$Tokens[$i] }
            '--view' { if ($i + 1 -ge @($Tokens).Count) { throw '--view requires a view name.' }; $i++; $result.view = [string]$Tokens[$i] }
            '--host-snapshot' { if ($i + 1 -ge @($Tokens).Count) { throw '--host-snapshot requires a snapshot file path.' }; $i++; $result.host_snapshot = [string]$Tokens[$i] }
            default { throw ('Unknown capability-inventory option: {0}' -f $token) }
        }
    }
    return [pscustomobject]$result
}

function Get-ReferenceCapabilityDescriptors([string]$ManifestPath) {
    if (-not [System.IO.File]::Exists($ManifestPath)) { return @() }
    $manifest = [System.IO.File]::ReadAllText($ManifestPath) | ConvertFrom-Json
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($repo in @($manifest.repos)) {
        $name = [string]$repo.name
        $kind = if ($name -match 'plugin') { 'plugin' } elseif ($name -in @('modelcontextprotocol', 'servers', 'registry')) { 'mcp' } else { 'skill' }
        $lifecycle = if ([string]$repo.status -eq 'deprecated') { 'historical' } else { 'unknown' }
        $source = [pscustomobject]@{ type = 'reference_shelf'; path_or_url = [string]$repo.upstream_url; revision = $null; checksum = $null; license = $null; trust_tier = [string]$repo.tier }
        $items.Add((New-CapabilityDescriptor -Kind $kind -Name $name -TruthOrigin reference -Source $source -Lifecycle $lifecycle -Components @([pscustomobject]@{ kind = 'reference_repo'; disposition = [string]$repo.source_disposition }) -VerificationState static_validated)) | Out-Null
    }
    return $items.ToArray()
}

function Invoke-CapabilityInventoryCommand([object[]]$Tokens = @()) {
    $options = Parse-ReadOnlyCapabilityOptions $Tokens
    $configRaw = [System.IO.File]::ReadAllText($CfgPath) -replace '(?m)^\s*//.*$', ''
    $config = $configRaw | ConvertFrom-Json
    if (-not [string]::IsNullOrWhiteSpace([string]$options.view)) {
        if ([string]$options.view -ne 'skill-surfaces') { throw ('Unknown capability inventory view: {0}' -f $options.view) }
        $view = New-SkillSurfaceView -RepoRoot $Root -Config $config -HostSnapshotPath ([string]$options.host_snapshot)
        if (-not [string]::IsNullOrWhiteSpace([string]$options.out_path)) { $view.writes = 1 }
        $surfaceEnvelope = [pscustomobject][ordered]@{ schema_version = 1; command = 'capability-inventory'; view = 'skill-surfaces'; pass = [bool]$view.pass; truth_boundary = 'read_only_skill_surface_snapshot'; data = $view }
        $surfaceJson = $surfaceEnvelope | ConvertTo-Json -Depth 40 -Compress
        if (-not [string]::IsNullOrWhiteSpace([string]$options.out_path)) { Write-Utf8FileAtomic -Path ([System.IO.Path]::GetFullPath([string]$options.out_path)) -Content $surfaceJson }
        return [pscustomobject]@{ exit_code = $(if ($surfaceEnvelope.pass) { 0 } else { 1 }); output = $(if ($options.json) { $surfaceJson } else { 'Skill surfaces: surfaces={0}, findings={1}' -f $view.surface_count, @($view.findings).Count }); json = [bool]$options.json; envelope = $surfaceEnvelope }
    }
    $descriptors = @(ConvertTo-CapabilityDescriptorsFromSkillsConfig $config $CfgPath 'working-tree')
    $descriptors += @(Get-ReferenceCapabilityDescriptors (Join-Path $Root 'references\reference-shelf.manifest.json'))
    $inventory = New-CapabilityInventory $descriptors
    if (-not [string]::IsNullOrWhiteSpace([string]$options.out_path)) { $inventory.writes = 1 }
    $envelope = [pscustomobject][ordered]@{ schema_version = 1; command = 'capability-inventory'; pass = (@($inventory.findings).Count -eq 0); truth_boundary = 'repo_static_inventory'; data = $inventory }
    $json = $envelope | ConvertTo-Json -Depth 30 -Compress
    if (-not [string]::IsNullOrWhiteSpace([string]$options.out_path)) {
        $outPath = [System.IO.Path]::GetFullPath([string]$options.out_path)
        Write-Utf8FileAtomic -Path $outPath -Content $json
    }
    return [pscustomobject]@{ exit_code = $(if ($envelope.pass) { 0 } else { 1 }); output = $(if ($options.json) { $json } else { 'Capability inventory: descriptors={0}, findings={1}' -f @($inventory.descriptors).Count, @($inventory.findings).Count }); json = [bool]$options.json; envelope = $envelope }
}
