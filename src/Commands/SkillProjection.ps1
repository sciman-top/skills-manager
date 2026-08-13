function Resolve-SkillProjectionPath([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    $resolved = $path.Trim()
    if ($resolved.StartsWith("~")) {
        $resolved = $resolved -replace "^~", [Environment]::GetFolderPath("UserProfile")
    }
    $resolved = $resolved.Replace("/", "\")
    if (-not [System.IO.Path]::IsPathRooted($resolved)) {
        $resolved = Join-Path $Root $resolved
    }
    return [System.IO.Path]::GetFullPath($resolved)
}

function Add-SkillExternalInventoryWarning($warnings, [string]$code, [string]$subject, [string]$message) {
    $warnings.Add([pscustomobject][ordered]@{ code = $code; subject = $subject; message = $message }) | Out-Null
}

function Get-CodexExternalSkillInventory($projectionCfg) {
    $disabled = [pscustomobject]@{ enabled = $false; authority = 'codex_plugin_list_json'; freshness = 'unknown'; coverage = 'not_configured'; enabled_plugin_ids = @(); plugin_count = 0; skill_count = 0; metadata_chars = 0; skills = @(); warnings = @() }
    if ($null -eq $projectionCfg) { return $disabled }
    $inventoryCfg = Get-CfgObjectProperty $projectionCfg 'external_skill_inventory'
    if ($null -eq $inventoryCfg) { return $disabled }
    $enabledRaw = Get-CfgObjectProperty $inventoryCfg 'enabled'
    $enabled = ($null -eq $enabledRaw) -or [bool]$enabledRaw
    if (-not $enabled) { $disabled.coverage = 'disabled'; return $disabled }
    $result = Get-CodexPluginSkillInventory
    $result | Add-Member -NotePropertyName enabled -NotePropertyValue $true
    return $result
}

function Get-SkillProjectionFiles([string]$rootPath) {
    $files = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($rootPath) -or -not (Test-Path -LiteralPath $rootPath -PathType Container)) {
        return @()
    }

    foreach ($dir in @(Get-ChildItem -LiteralPath $rootPath -Directory -Force -ErrorAction SilentlyContinue | Sort-Object Name)) {
        if ($dir.Name -eq ".system") {
            foreach ($systemDir in @(Get-ChildItem -LiteralPath $dir.FullName -Directory -Force -ErrorAction SilentlyContinue | Sort-Object Name)) {
                $systemFile = Join-Path $systemDir.FullName "SKILL.md"
                if (Test-Path -LiteralPath $systemFile -PathType Leaf) {
                    $files.Add([pscustomobject]@{ file = $systemFile; dir = $systemDir.FullName; is_system = $true }) | Out-Null
                }
            }
            continue
        }

        $skillFile = Join-Path $dir.FullName "SKILL.md"
        if (Test-Path -LiteralPath $skillFile -PathType Leaf) {
            $files.Add([pscustomobject]@{ file = $skillFile; dir = $dir.FullName; is_system = $false }) | Out-Null
        }
    }
    return @($files.ToArray())
}

function Get-SkillPackageContentHash([string]$skillDir) {
    if ([string]::IsNullOrWhiteSpace($skillDir) -or -not (Test-Path -LiteralPath $skillDir -PathType Container)) { return "missing" }
    $base = [System.IO.Path]::GetFullPath($skillDir).TrimEnd("\", "/")
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($file in @(Get-ChildItem -LiteralPath $base -Recurse -File -Force -ErrorAction SilentlyContinue | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($base.Length).TrimStart("\", "/").Replace("\", "/")
        $parts.Add(("{0}|{1}" -f $relative, (Get-FileContentHash $file.FullName))) | Out-Null
    }
    return (Get-StringSha256 ($parts.ToArray() -join "`n"))
}

function Get-SkillProjectionSourceEntries($source, [int]$sourceOrder) {
    $id = [string]$source.id
    $rootPath = Resolve-SkillProjectionPath ([string]$source.path)
    $priority = if ($source.PSObject.Properties.Match("priority").Count -gt 0) { [int]$source.priority } else { 0 }
    $platforms = if ($source.PSObject.Properties.Match("platforms").Count -gt 0 -and $null -ne $source.platforms) { @($source.platforms | ForEach-Object { [string]$_ }) } else { @("codex") }
    $entries = New-Object System.Collections.Generic.List[object]

    foreach ($item in @(Get-SkillProjectionFiles $rootPath)) {
        $meta = Read-SkillMetadata ([string]$item.file) -Observation
        $declaredName = ([string]$meta.declared_name).Trim()
        if ([string]::IsNullOrWhiteSpace($declaredName)) {
            $declaredName = Split-Path ([string]$item.dir) -Leaf
        }
        $effectivePriority = $priority
        if ([bool]$item.is_system) { $effectivePriority += 100000 }
        $contentHash = [string](Get-FileContentHash ([string]$item.file))
        $packageHash = Get-SkillPackageContentHash ([string]$item.dir)
        $entries.Add([pscustomobject]([ordered]@{
                    name = $declaredName
                    description = [string]$meta.description
                    source_id = $id
                    source_root = $rootPath
                    source_order = $sourceOrder
                    priority = $effectivePriority
                    is_system = [bool]$item.is_system
                    path = [System.IO.Path]::GetFullPath([string]$item.file)
                    skill_dir = [System.IO.Path]::GetFullPath([string]$item.dir)
                    content_hash = $contentHash
                    package_hash = [string]$packageHash
                    target_platforms = @($platforms)
                })) | Out-Null
    }
    return @($entries.ToArray())
}

function Add-CapabilityCatalogMembership([hashtable]$Membership, [string]$SkillName, [string]$DomainName) {
    if ([string]::IsNullOrWhiteSpace($SkillName) -or [string]::IsNullOrWhiteSpace($DomainName)) { return }
    if (-not $Membership.ContainsKey($SkillName)) {
        $Membership[$SkillName] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }
    $Membership[$SkillName].Add($DomainName) | Out-Null
}

function Get-CapabilityCatalogTextSha256([string]$Value) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally { $sha.Dispose() }
}

function Get-SkillDiscoveryCatalogPath($projectionCfg) {
    Need ($null -ne $projectionCfg) 'skill_projection 配置为空'
    $managedRoot = Resolve-SkillProjectionPath ([string]$projectionCfg.managed_source_path)
    $configuredPath = ''
    if ($projectionCfg.PSObject.Properties.Match('discovery_catalog').Count -gt 0 -and $null -ne $projectionCfg.discovery_catalog -and
        $projectionCfg.discovery_catalog.PSObject.Properties.Match('catalog_path').Count -gt 0) {
        $configuredPath = [string]$projectionCfg.discovery_catalog.catalog_path
    }
    $catalogPath = if ([string]::IsNullOrWhiteSpace($configuredPath)) {
        Join-Path $managedRoot '.skills-manager\catalog.json'
    }
    else { Resolve-SkillProjectionPath $configuredPath }
    Need (Is-PathInsideOrEqual $catalogPath $managedRoot) 'skill_projection.discovery_catalog.catalog_path 必须位于 managed_source_path 内'
    return [IO.Path]::GetFullPath($catalogPath)
}

function New-SkillDiscoveryCatalogDocument($projectionCfg) {
    Need ($null -ne $projectionCfg) 'skill_projection 配置为空'
    Need ($projectionCfg.PSObject.Properties.Match('managed_source_path').Count -gt 0) 'skill_projection 缺少 managed_source_path'
    $managedRoot = Resolve-SkillProjectionPath ([string]$projectionCfg.managed_source_path)
    Need (Test-Path -LiteralPath $managedRoot -PathType Container) ("受管技能源不存在：{0}" -f $managedRoot)

    $domainPurpose = [ordered]@{}
    $membership = @{}
    $fallbackDomain = 'other'
    $fallbackPurpose = 'Installed cold skills not assigned to a narrower domain; inspect only when no specific domain covers the request.'
    if ($projectionCfg.PSObject.Properties.Match('discovery_catalog').Count -gt 0 -and $null -ne $projectionCfg.discovery_catalog) {
        $discoveryCfg = $projectionCfg.discovery_catalog
        if ($discoveryCfg.PSObject.Properties.Match('fallback_domain').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$discoveryCfg.fallback_domain)) { $fallbackDomain = [string]$discoveryCfg.fallback_domain }
        if ($discoveryCfg.PSObject.Properties.Match('fallback_purpose').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$discoveryCfg.fallback_purpose)) { $fallbackPurpose = [string]$discoveryCfg.fallback_purpose }
        if ($discoveryCfg.PSObject.Properties.Match('domain_memberships').Count -gt 0 -and $null -ne $discoveryCfg.domain_memberships) {
            foreach ($property in @($discoveryCfg.domain_memberships.PSObject.Properties | Sort-Object Name)) {
                $domainName = [string]$property.Name
                if (-not $domainPurpose.Contains($domainName)) { $domainPurpose[$domainName] = ("Additional cold-discovery capabilities for the '{0}' domain." -f $domainName) }
                foreach ($skillName in @($property.Value)) { Add-CapabilityCatalogMembership $membership ([string]$skillName) $domainName }
            }
        }
    }

    $rulesByName = @{}
    if ($null -ne $policy) {
        foreach ($group in @($policy.groups)) {
            foreach ($member in @($group.members)) {
                $name = [string]$member.name
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                if (-not $rulesByName.ContainsKey($name)) { $rulesByName[$name] = New-Object System.Collections.Generic.List[object] }
                $rulesByName[$name].Add([ordered]@{
                        group = [string]$group.id
                        role = [string]$member.role
                        activation = [string]$member.activation
                        negative_activation = [string]$member.negative_activation
                        context = ('{0} {1}' -f [string]$group.purpose, [string]$group.selection_policy).Trim()
                    }) | Out-Null
            }
        }
    }

    $skills = New-Object System.Collections.Generic.List[object]
    $actualNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @(Get-SkillProjectionFiles $managedRoot)) {
        $meta = Read-SkillMetadata ([string]$item.file) -Observation
        $name = ([string]$meta.declared_name).Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { $name = Split-Path ([string]$item.dir) -Leaf }
        if (-not $actualNames.Add($name)) { continue }
        if (-not $membership.ContainsKey($name) -or $membership[$name].Count -eq 0) {
            Add-CapabilityCatalogMembership $membership $name $fallbackDomain
        }
        $relativeWithinManaged = ([string]$item.file).Substring($managedRoot.TrimEnd('\', '/').Length).TrimStart('\', '/')
        $relativeFromCatalog = ('..\{0}' -f $relativeWithinManaged)
        $rules = if ($rulesByName.ContainsKey($name)) { @($rulesByName[$name].ToArray() | Sort-Object group, role) } else { @() }
        $skills.Add([ordered]@{
                name = $name
                description = [string]$meta.description
                relative_path = $relativeFromCatalog
                entrypoint_sha256 = Get-FileContentHash ([string]$item.file)
                domains = @($membership[$name] | Sort-Object)
                load_side_effect = 'read_only'
                routing_rules = @($rules)
            }) | Out-Null
    }

    $domainRows = New-Object System.Collections.Generic.List[object]
    foreach ($domainName in @($domainPurpose.Keys | Sort-Object)) {
        $names = @($skills | Where-Object { @($_.domains) -contains $domainName } | ForEach-Object { [string]$_.name } | Sort-Object -Unique)
        if ($names.Count -eq 0) { continue }
        $domainRows.Add([ordered]@{ name = $domainName; purpose = [string]$domainPurpose[$domainName]; skill_names = $names }) | Out-Null
    }
    if (@($skills | Where-Object { @($_.domains) -contains $fallbackDomain }).Count -gt 0 -and -not $domainPurpose.Contains($fallbackDomain)) {
        $fallbackNames = @($skills | Where-Object { @($_.domains) -contains $fallbackDomain } | ForEach-Object { [string]$_.name } | Sort-Object -Unique)
        $domainRows.Add([ordered]@{ name = $fallbackDomain; purpose = $fallbackPurpose; skill_names = $fallbackNames }) | Out-Null
    }

    $catalog = [ordered]@{
        schema_version = 1
        decision_owner = 'host_ai'
        semantic_routing_performed = $false
        domains = @($domainRows.ToArray() | Sort-Object name)
        skills = @($skills.ToArray() | Sort-Object name)
        capabilities = @()
    }
    $catalog.catalog_fingerprint = Get-CapabilityCatalogTextSha256 ($catalog | ConvertTo-Json -Depth 20 -Compress)
    return $catalog
}

function New-CapabilityRouterCatalogDocument($projectionCfg) {
    return New-SkillDiscoveryCatalogDocument $projectionCfg
}

function Sync-SkillDiscoveryCatalog($projectionCfg) {
    if ($null -eq $projectionCfg -or $projectionCfg.PSObject.Properties.Match('managed_source_path').Count -eq 0) {
        return [pscustomobject]@{ enabled = $false; reason = 'not_configured'; changed = $false; persisted = $false; path = ''; skill_count = 0; domain_count = 0 }
    }
    $catalogPath = Get-SkillDiscoveryCatalogPath $projectionCfg
    $catalog = New-SkillDiscoveryCatalogDocument $projectionCfg
    $desired = $catalog | ConvertTo-Json -Depth 20
    $existing = if (Test-Path -LiteralPath $catalogPath -PathType Leaf) { Get-ContentUtf8 $catalogPath } else { '' }
    $changed = -not [string]::Equals($existing.TrimEnd("`r", "`n"), $desired.TrimEnd("`r", "`n"), [System.StringComparison]::Ordinal)
    if ($changed -and -not $DryRun) { Set-ContentUtf8 $catalogPath $desired }
    return [pscustomobject]@{
        enabled = $true
        reason = 'ok'
        changed = $changed
        persisted = (-not $DryRun)
        path = $catalogPath
        skill_count = @($catalog.skills).Count
        domain_count = @($catalog.domains).Count
    }
}

function New-SkillProjectionPlan($projectionCfg) {
    Need ($null -ne $projectionCfg) "skill_projection 配置为空"
    $enabled = -not ($projectionCfg.PSObject.Properties.Match("enabled").Count -gt 0) -or [bool]$projectionCfg.enabled
    if (-not $enabled) {
        return [pscustomobject]@{ schema_version = 2; enabled = $false; skills = @(); canonical = @(); active = @(); disabled = @(); conflicts = @(); unique_names = @(); active_names = @(); duplicate_name_groups = 0; external_skills = @(); external_inventory_warnings = @() }
    }

    Need ($projectionCfg.PSObject.Properties.Match("sources").Count -gt 0 -and $null -ne $projectionCfg.sources) "skill_projection 缺少 sources"
    $all = New-Object System.Collections.Generic.List[object]
    $sourceOrder = 0
    foreach ($source in @($projectionCfg.sources)) {
        Need ($null -ne $source) "skill_projection.sources 不能包含空值"
        Need (-not [string]::IsNullOrWhiteSpace([string]$source.id)) "skill_projection source 缺少 id"
        Need (-not [string]::IsNullOrWhiteSpace([string]$source.path)) ("skill_projection source 缺少 path：{0}" -f [string]$source.id)
        foreach ($entry in @(Get-SkillProjectionSourceEntries $source $sourceOrder)) {
            $all.Add($entry) | Out-Null
        }
        $sourceOrder++
    }

    $groups = @{}
    foreach ($entry in @($all.ToArray())) {
        $key = ([string]$entry.name).ToLowerInvariant()
        if (-not $groups.ContainsKey($key)) { $groups[$key] = New-Object System.Collections.Generic.List[object] }
        $groups[$key].Add($entry) | Out-Null
    }

    $canonical = New-Object System.Collections.Generic.List[object]
    $disabled = New-Object System.Collections.Generic.List[object]
    $conflicts = New-Object System.Collections.Generic.List[object]
    $duplicateGroups = 0
    foreach ($key in @($groups.Keys | Sort-Object)) {
        $candidates = @($groups[$key].ToArray() | Sort-Object @{ Expression = "priority"; Descending = $true }, @{ Expression = "source_order"; Ascending = $true }, @{ Expression = "path"; Ascending = $true })
        if ($candidates.Count -eq 0) { continue }
        $winner = $candidates[0]
        $canonical.Add($winner) | Out-Null
        if ($candidates.Count -le 1) { continue }

        $duplicateGroups++
        $hashes = @($candidates | ForEach-Object { [string]$_.package_hash } | Sort-Object -Unique)
        $isConflict = $hashes.Count -gt 1
        if ($isConflict) {
            $conflicts.Add([pscustomobject]([ordered]@{
                        name = [string]$winner.name
                        winner_path = [string]$winner.path
                        winner_source_id = [string]$winner.source_id
                        candidate_paths = @($candidates | ForEach-Object { [string]$_.path })
                        package_hashes = @($hashes)
                        resolution = "priority"
                    })) | Out-Null
        }
        foreach ($loser in @($candidates | Select-Object -Skip 1)) {
            $disabled.Add([pscustomobject]([ordered]@{
                        name = [string]$loser.name
                        path = [string]$loser.path
                        source_id = [string]$loser.source_id
                        source_root = [string]$loser.source_root
                        content_hash = [string]$loser.content_hash
                        package_hash = [string]$loser.package_hash
                        target_platforms = @($loser.target_platforms)
                        canonical_path = [string]$winner.path
                        canonical_source_id = [string]$winner.source_id
                        decision = if ($isConflict) { "conflict_priority_winner" } else { "duplicate_same_content" }
                    })) | Out-Null
        }
    }

    $canonicalByName = @{}
    foreach ($entry in @($canonical.ToArray())) {
        $canonicalByName[[string]$entry.name] = $entry
    }

    $aliases = @{}
    if ($projectionCfg.PSObject.Properties.Match("aliases").Count -gt 0 -and $null -ne $projectionCfg.aliases) {
        foreach ($alias in @($projectionCfg.aliases)) {
            Need ($null -ne $alias) "skill_projection.aliases 不能包含空值"
            $aliasName = ([string]$alias.name).Trim()
            $replacement = ([string]$alias.replacement).Trim()
            Need (-not [string]::IsNullOrWhiteSpace($aliasName)) "skill_projection alias 缺少 name"
            Need (-not [string]::IsNullOrWhiteSpace($replacement)) ("skill_projection alias 缺少 replacement：{0}" -f $aliasName)
            Need (-not [string]::Equals($aliasName, $replacement, [System.StringComparison]::OrdinalIgnoreCase)) ("skill_projection alias 不能指向自身：{0}" -f $aliasName)
            Need (-not $aliases.ContainsKey($aliasName)) ("skill_projection alias 重复：{0}" -f $aliasName)
            if ($canonicalByName.ContainsKey($aliasName)) {
                Need ($canonicalByName.ContainsKey($replacement)) ("skill_projection alias replacement 不存在：{0} -> {1}" -f $aliasName, $replacement)
            }
            $aliases[$aliasName] = $replacement
        }
    }

    $externalInventory = Get-CodexExternalSkillInventory $projectionCfg
    $externalSkillMetadataChars = [int]$externalInventory.metadata_chars

    $active = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @($canonical.ToArray() | Sort-Object name)) {
        $name = [string]$entry.name
        if ($aliases.ContainsKey($name)) {
            $replacement = [string]$aliases[$name]
            $replacementEntry = $canonicalByName[$replacement]
            $disabled.Add([pscustomobject]([ordered]@{
                        name = $name
                        path = [string]$entry.path
                        source_id = [string]$entry.source_id
                        source_root = [string]$entry.source_root
                        content_hash = [string]$entry.content_hash
                        package_hash = [string]$entry.package_hash
                        target_platforms = @($entry.target_platforms)
                        canonical_path = [string]$replacementEntry.path
                        canonical_source_id = [string]$replacementEntry.source_id
                        replacement = $replacement
                        decision = "alias_replaced"
                    })) | Out-Null
            continue
        }
        $active.Add($entry) | Out-Null
    }

    $skillMetadataChars = 0
    foreach ($entry in @($active.ToArray())) {
        $skillMetadataChars += ([string]$entry.name).Length + ([string]$entry.description).Length
    }
    $estimatedMetadataChars = $skillMetadataChars + $externalSkillMetadataChars

    return [pscustomobject]([ordered]@{
        schema_version = 2
        enabled = $true
        conflict_policy = "system_then_priority_then_source_order"
        skills = @($all.ToArray() | Sort-Object name, @{ Expression = "priority"; Descending = $true }, path)
        canonical = @($canonical.ToArray() | Sort-Object name)
        active = @($active.ToArray() | Sort-Object name)
        disabled = @($disabled.ToArray() | Sort-Object name, path)
        conflicts = @($conflicts.ToArray() | Sort-Object name)
        unique_names = @($canonical.ToArray() | ForEach-Object { [string]$_.name } | Sort-Object)
        active_names = @($active.ToArray() | ForEach-Object { [string]$_.name } | Sort-Object)
        duplicate_name_groups = $duplicateGroups
        skill_metadata_chars = $skillMetadataChars
        external_skill_count = [int]$externalInventory.skill_count
        external_skill_metadata_chars = $externalSkillMetadataChars
        estimated_metadata_chars = $estimatedMetadataChars
        external_skills = @($externalInventory.skills)
        external_inventory_warnings = @($externalInventory.warnings)
    })
}

function Build-CodexSkillsProjectionToml([string]$existingToml, $disabledEntries) {
    $begin = "# BEGIN skills-manager:skills-projection"
    $end = "# END skills-manager:skills-projection"
    $lines = if ([string]::IsNullOrEmpty($existingToml)) { @() } else { @($existingToml -split "`r?`n") }
    $kept = New-Object System.Collections.Generic.List[string]
    $inside = $false
    $insideManagedTable = $false
    $foundBegin = $false
    $foundEnd = $false
    foreach ($line in $lines) {
        if ($line.Trim() -eq $begin) {
            Need (-not $inside) "Codex skills projection 受管块重复开始"
            $inside = $true
            $insideManagedTable = $false
            $foundBegin = $true
            continue
        }
        if ($line.Trim() -eq $end) {
            Need ($inside) "Codex skills projection 受管块缺少开始标记"
            $inside = $false
            $insideManagedTable = $false
            $foundEnd = $true
            continue
        }
        if (-not $inside) {
            $kept.Add([string]$line) | Out-Null
            continue
        }

        $trimmed = $line.Trim()
        if ($trimmed -match '^\[\[\s*skills\s*\.\s*config\s*\]\](?:\s*#.*)?$') {
            $insideManagedTable = $true
            continue
        }
        if ($trimmed -match '^\[\[?.+\]\]?(?:\s*#.*)?$') {
            $insideManagedTable = $false
        }
        if (-not $insideManagedTable) { $kept.Add([string]$line) | Out-Null }
    }
    Need (-not $inside) "Codex skills projection 受管块缺少结束标记"
    Need ($foundBegin -eq $foundEnd) "Codex skills projection 受管块标记不完整"

    while ($kept.Count -gt 0 -and [string]::IsNullOrWhiteSpace($kept[$kept.Count - 1])) { $kept.RemoveAt($kept.Count - 1) }
    $output = New-Object System.Collections.Generic.List[string]
    $output.AddRange([string[]]$kept.ToArray())
    $entries = @($disabledEntries | Sort-Object path -Unique)
    if ($entries.Count -gt 0) {
        if ($output.Count -gt 0) { $output.Add("") | Out-Null }
        $output.Add($begin) | Out-Null
        foreach ($entry in $entries) {
            $output.Add("[[skills.config]]") | Out-Null
            $output.Add(("path = {0}" -f (ConvertTo-TomlBasicValue ([string]$entry.path)))) | Out-Null
            $output.Add("enabled = false") | Out-Null
            $output.Add("") | Out-Null
        }
        if ($output.Count -gt 0 -and [string]::IsNullOrWhiteSpace($output[$output.Count - 1])) { $output.RemoveAt($output.Count - 1) }
        $output.Add($end) | Out-Null
    }
    return (($output.ToArray() -join "`r`n").TrimEnd() + "`r`n")
}

function Backup-CodexSkillProjectionConfig([string]$configPath) {
    if ($DryRun -or -not (Test-Path -LiteralPath $configPath -PathType Leaf)) { return $null }
    $codexRoot = Split-Path $configPath -Parent
    $backupRoot = Join-Path $codexRoot "config-backups"
    EnsureDir $backupRoot
    $backupPath = Join-Path $backupRoot ("config.toml.skills-projection.{0}.bak" -f (Get-Date -Format "yyyyMMdd-HHmmss-fff"))
    Copy-Item -LiteralPath $configPath -Destination $backupPath -Force
    return $backupPath
}

function Test-ConfiguredHostProjection($cfg) {
    if ($null -eq $cfg) { return $false }
    $repoRoot = [System.IO.Path]::GetFullPath($Root)
    foreach ($targetCfg in @($cfg.targets)) {
        if ($null -eq $targetCfg -or [string]::IsNullOrWhiteSpace([string]$targetCfg.path)) { continue }
        $targetPath = Resolve-TargetDir ([string]$targetCfg.path)
        if (-not [string]::IsNullOrWhiteSpace($targetPath) -and -not (Is-PathInsideOrEqual $targetPath $repoRoot)) {
            return $true
        }
    }
    if ($cfg.PSObject.Properties.Match("skill_projection").Count -eq 0 -or $null -eq $cfg.skill_projection) { return $false }
    $projectionCfg = $cfg.skill_projection
    foreach ($propertyName in @("user_skill_root", "codex_config_path")) {
        if ($projectionCfg.PSObject.Properties.Match($propertyName).Count -eq 0) { continue }
        $candidate = Resolve-SkillProjectionPath ([string]$projectionCfg.$propertyName)
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not (Is-PathInsideOrEqual $candidate $repoRoot)) {
            return $true
        }
    }
    if ($projectionCfg.PSObject.Properties.Match("native_projection").Count -gt 0 -and $null -ne $projectionCfg.native_projection -and
        $projectionCfg.native_projection.PSObject.Properties.Match("target_root").Count -gt 0) {
        $nativeTarget = Resolve-SkillProjectionPath ([string]$projectionCfg.native_projection.target_root)
        if (-not [string]::IsNullOrWhiteSpace($nativeTarget) -and -not (Is-PathInsideOrEqual $nativeTarget $repoRoot)) { return $true }
    }
    return $false
}

function Invoke-HostProjectionGitText([string]$repositoryPath, [string[]]$gitArguments) {
    $output = @(& git -C $repositoryPath @gitArguments 2>&1)
    $exitCode = $LASTEXITCODE
    $text = (($output | ForEach-Object { Convert-GitOutputLineToText $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n").Trim()
    if ($exitCode -ne 0) {
        throw ("git -C '{0}' {1} failed with exit code {2}: {3}" -f $repositoryPath, ($gitArguments -join " "), $exitCode, $text)
    }
    return $text
}

function Get-HostProjectionPromotionContext($cfg, [switch]$AllowUnverified) {
    $requiresPromotion = Test-ConfiguredHostProjection $cfg
    if (-not $requiresPromotion) {
        return [pscustomobject]([ordered]@{
                required = $false
                source_revision = ""
                source_worktree_dirty = $false
                source_git_state = "not_checked_local_only"
                promotion_mode = "local_only"
            })
    }

    $sourceRevision = ""
    $sourceDirty = $true
    $gitState = "unavailable"
    try {
        $inside = Invoke-HostProjectionGitText $Root @("rev-parse", "--is-inside-work-tree")
        Need ([string]::Equals($inside, "true", [System.StringComparison]::OrdinalIgnoreCase)) "当前技能源不在 Git 工作树中"
        $sourceRevision = Invoke-HostProjectionGitText $Root @("rev-parse", "HEAD")
        Need ($sourceRevision -match '^[0-9a-fA-F]{40,64}$') "无法解析技能源 commit"
        $status = Invoke-HostProjectionGitText $Root @("status", "--porcelain=v1", "--untracked-files=all")
        $sourceDirty = -not [string]::IsNullOrWhiteSpace($status)
        $gitState = if ($sourceDirty) { "dirty" } else { "clean" }
    }
    catch {
        if (-not $AllowUnverified) {
            throw ("正式宿主投影要求可验证的 clean Git commit；Git 取证失败。可仅在明确接受风险时使用 -AllowUnverifiedHostProjection。{0}" -f $_.Exception.Message)
        }
        $gitState = "unavailable"
    }

    if ($sourceDirty -and -not $AllowUnverified) {
        throw "正式宿主投影要求 clean Git commit；当前工作树存在未提交或未跟踪改动。请先完成门禁并提交，或仅在明确接受风险时使用 -AllowUnverifiedHostProjection。"
    }

    return [pscustomobject]([ordered]@{
            required = $true
            source_revision = $sourceRevision
            source_worktree_dirty = [bool]$sourceDirty
            source_git_state = $gitState
            promotion_mode = if ($sourceDirty -or $gitState -ne "clean") { "unverified_override" } else { "verified_clean_commit" }
        })
}

function Sync-CapabilityRouterCatalog($projectionCfg) {
    return Sync-SkillDiscoveryCatalog $projectionCfg
}

function Get-SkillProjectionPlanFingerprint($Plan, $NativeProjectionPlan = $null) {
    $identity = [ordered]@{
        enabled = [bool]$Plan.enabled
        canonical = @($Plan.canonical | Sort-Object name, path | ForEach-Object {
                [ordered]@{
                    name = [string]$_.name
                    path = [IO.Path]::GetFullPath([string]$_.path)
                    content_hash = [string]$_.content_hash
                    package_hash = [string]$_.package_hash
                }
            })
        disabled = @($Plan.disabled | Sort-Object name, path | ForEach-Object {
                [ordered]@{ name = [string]$_.name; path = [IO.Path]::GetFullPath([string]$_.path); decision = [string]$_.decision }
            })
        native_plan_id = if ($null -eq $NativeProjectionPlan) { '' } else { [string]$NativeProjectionPlan.plan_id }
    }
    return Get-StringSha256 ($identity | ConvertTo-Json -Depth 12 -Compress)
}

function Get-SkillProjectionPromotionRecord([string]$manifestPath, $promotionContext = $null, [string]$projectionFingerprint = '') {
    if ($null -ne $promotionContext) {
        return [pscustomobject]@{
            source_revision = [string]$promotionContext.source_revision
            source_worktree_dirty = [bool]$promotionContext.source_worktree_dirty
            source_git_state = [string]$promotionContext.source_git_state
            promotion_mode = [string]$promotionContext.promotion_mode
            promoted_at = (Get-Date).ToString("o")
            provenance_status = "current"
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($manifestPath) -and (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        try {
            $existingManifest = Get-ContentUtf8 $manifestPath | ConvertFrom-Json
            if ($existingManifest.PSObject.Properties.Match("promotion_mode").Count -gt 0) {
                $existingFingerprint = if ($existingManifest.PSObject.Properties.Match('projection_fingerprint').Count -gt 0) { [string]$existingManifest.projection_fingerprint } else { '' }
                if ([string]::IsNullOrWhiteSpace($projectionFingerprint) -or -not [string]::Equals($existingFingerprint, $projectionFingerprint, [StringComparison]::OrdinalIgnoreCase)) {
                    return [pscustomobject]@{
                        source_revision = ""
                        source_worktree_dirty = $true
                        source_git_state = "not_evaluated_after_projection_change"
                        promotion_mode = "stale"
                        promoted_at = ""
                        provenance_status = "stale"
                    }
                }
                return [pscustomobject]@{
                    source_revision = [string]$existingManifest.source_revision
                    source_worktree_dirty = [bool]$existingManifest.source_worktree_dirty
                    source_git_state = [string]$existingManifest.source_git_state
                    promotion_mode = [string]$existingManifest.promotion_mode
                    promoted_at = [string]$existingManifest.promoted_at
                    provenance_status = "current"
                }
            }
        }
        catch {
            Log ("技能投影晋级 provenance 读取失败，将记录为 not_evaluated：{0}" -f $_.Exception.Message) "WARN"
        }
    }

    return [pscustomobject]@{
        source_revision = ""
        source_worktree_dirty = $false
        source_git_state = "not_evaluated"
        promotion_mode = "not_evaluated"
        promoted_at = ""
        provenance_status = "not_evaluated"
    }
}

function Get-SkillProjectionFileTransactionSnapshot([string]$Path) {
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (Test-PathEntry $fullPath) {
        Need (Test-Path -LiteralPath $fullPath -PathType Leaf) ("Projection transaction expected a file target: {0}" -f $fullPath)
        return [pscustomobject]@{ path = $fullPath; existed = $true; bytes = [IO.File]::ReadAllBytes($fullPath) }
    }
    return [pscustomobject]@{ path = $fullPath; existed = $false; bytes = [byte[]]@() }
}

function Restore-SkillProjectionFileTransactionSnapshot($Snapshot) {
    $path = [IO.Path]::GetFullPath([string]$Snapshot.path)
    if (-not [bool]$Snapshot.existed) {
        if (Test-PathEntry $path) {
            Need (Test-Path -LiteralPath $path -PathType Leaf) ("Projection rollback found non-file drift: {0}" -f $path)
            Remove-Item -LiteralPath $path -Force
        }
        return
    }

    EnsureDir (Split-Path -Parent $path)
    $temporaryPath = '{0}.rollback.{1}' -f $path, ([guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllBytes($temporaryPath, [byte[]]$Snapshot.bytes)
        Move-Item -LiteralPath $temporaryPath -Destination $path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
    }
}

function Get-CodexManagedSkillLinkTransactionSnapshot($projectionCfg, [string]$TargetRoot) {
    $managedRoot = Resolve-SkillProjectionPath ([string]$projectionCfg.managed_source_path)
    $targetRootPath = Resolve-SkillProjectionPath $TargetRoot
    $rootExisted = Test-Path -LiteralPath $targetRootPath -PathType Container
    if (Test-PathEntry $targetRootPath) {
        Need $rootExisted ("Projection target root is not a directory: {0}" -f $targetRootPath)
    }

    $excluded = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @($projectionCfg.managed_link_excludes)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$name)) { $excluded.Add(([string]$name).Trim()) | Out-Null }
    }
    $included = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @($projectionCfg.managed_link_includes)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$name)) { $included.Add(([string]$name).Trim()) | Out-Null }
    }
    $useIncludeFilter = $included.Count -gt 0
    $affected = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($directory in @(Get-ChildItem -LiteralPath $managedRoot -Directory -Force | Where-Object Name -ne '.system' | Sort-Object Name)) {
        if ($excluded.Contains($directory.Name) -or ($useIncludeFilter -and -not $included.Contains($directory.Name))) { continue }
        $linkPath = [IO.Path]::GetFullPath((Join-Path $targetRootPath $directory.Name))
        if (Test-PathEntry $linkPath) {
            Need (Is-ReparsePoint $linkPath) ("Projection target conflict is not a managed junction: {0}" -f $linkPath)
            $target = Get-ReparsePointTargetFullPath $linkPath
            Need (-not [string]::IsNullOrWhiteSpace($target)) ("Projection target junction cannot be resolved: {0}" -f $linkPath)
            $affected[$linkPath] = [pscustomobject]@{ path = $linkPath; existed = $true; target = $target }
        }
        else {
            $affected[$linkPath] = [pscustomobject]@{ path = $linkPath; existed = $false; target = '' }
        }
    }

    if ($rootExisted) {
        $managedPrefix = $managedRoot.TrimEnd('\') + '\'
        foreach ($entry in @(Get-ChildItem -LiteralPath $targetRootPath -Directory -Force -ErrorAction SilentlyContinue | Where-Object Name -ne '.system')) {
            if (-not (Is-ReparsePoint $entry.FullName)) { continue }
            $target = Get-ReparsePointTargetFullPath $entry.FullName
            if ([string]::IsNullOrWhiteSpace($target) -or -not $target.StartsWith($managedPrefix, [StringComparison]::OrdinalIgnoreCase)) { continue }
            $linkPath = [IO.Path]::GetFullPath($entry.FullName)
            if (-not $affected.ContainsKey($linkPath)) {
                $affected[$linkPath] = [pscustomobject]@{ path = $linkPath; existed = $true; target = $target }
            }
        }
    }

    return [pscustomobject]@{
        managed_root = $managedRoot
        target_root = $targetRootPath
        root_existed = $rootExisted
        entries = @($affected.Values | Sort-Object path)
    }
}

function Restore-CodexManagedSkillLinkTransactionSnapshot($Snapshot) {
    $managedRoot = [IO.Path]::GetFullPath([string]$Snapshot.managed_root)
    foreach ($state in @($Snapshot.entries | Sort-Object path -Descending)) {
        $path = [IO.Path]::GetFullPath([string]$state.path)
        if ([bool]$state.existed) {
            if (Test-PathEntry $path) {
                Need (Is-ReparsePoint $path) ("Projection link rollback found non-junction drift: {0}" -f $path)
                $currentTarget = Get-ReparsePointTargetFullPath $path
                if ([string]::Equals([string]$currentTarget, [string]$state.target, [StringComparison]::OrdinalIgnoreCase)) { continue }
                Invoke-RemoveItem $path -Recurse
            }
            New-Junction $path ([string]$state.target) -QuietIfUnchanged
            continue
        }

        if (Test-PathEntry $path) {
            Need (Is-ReparsePoint $path) ("Projection link rollback found unexpected non-junction state: {0}" -f $path)
            $currentTarget = Get-ReparsePointTargetFullPath $path
            Need (-not [string]::IsNullOrWhiteSpace($currentTarget) -and (Is-PathInsideOrEqual $currentTarget $managedRoot)) ("Projection link rollback refused an unrelated junction: {0}" -f $path)
            Invoke-RemoveItem $path -Recurse
        }
    }

    $targetRoot = [IO.Path]::GetFullPath([string]$Snapshot.target_root)
    if (-not [bool]$Snapshot.root_existed -and (Test-Path -LiteralPath $targetRoot -PathType Container) -and @(Get-ChildItem -LiteralPath $targetRoot -Force).Count -eq 0) {
        Remove-Item -LiteralPath $targetRoot -Force
    }
}

function New-CodexSkillProjectionTransaction($projectionCfg, [string]$ConfigPath, [string]$ManifestPath) {
    $filePaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $filePaths.Add([IO.Path]::GetFullPath($ConfigPath)) | Out-Null
    $filePaths.Add([IO.Path]::GetFullPath($ManifestPath)) | Out-Null
    $managedRoot = ''
    if ($projectionCfg.PSObject.Properties.Match('managed_source_path').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$projectionCfg.managed_source_path)) {
        $managedRoot = Resolve-SkillProjectionPath ([string]$projectionCfg.managed_source_path)
        $filePaths.Add((Get-SkillDiscoveryCatalogPath $projectionCfg)) | Out-Null
    }
    $nativeSettings = Get-CfgObjectProperty $projectionCfg 'native_projection'
    if ($null -ne $nativeSettings -and -not [string]::IsNullOrWhiteSpace([string](Get-CfgObjectProperty $nativeSettings 'receipt_path'))) {
        $filePaths.Add([IO.Path]::GetFullPath((Resolve-SkillProjectionPath ([string](Get-CfgObjectProperty $nativeSettings 'receipt_path'))))) | Out-Null
    }

    $linkSnapshots = New-Object Collections.Generic.List[object]
    if (-not [string]::IsNullOrWhiteSpace($managedRoot) -and (Test-Path -LiteralPath $managedRoot -PathType Container)) {
        $targetRoots = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        if ($projectionCfg.PSObject.Properties.Match('user_skill_root').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$projectionCfg.user_skill_root)) {
            $userSkillRoot = Resolve-SkillProjectionPath ([string]$projectionCfg.user_skill_root)
            $targetRoots.Add($userSkillRoot) | Out-Null
        }
        if ($null -ne $nativeSettings -and [bool](Get-CfgObjectProperty $nativeSettings 'enabled') -and -not [string]::IsNullOrWhiteSpace([string](Get-CfgObjectProperty $nativeSettings 'target_root'))) {
            $nativeTargetRoot = Resolve-SkillProjectionPath ([string](Get-CfgObjectProperty $nativeSettings 'target_root'))
            $targetRoots.Add($nativeTargetRoot) | Out-Null
        }
        foreach ($targetRoot in @($targetRoots | Sort-Object)) {
            $linkSnapshots.Add((Get-CodexManagedSkillLinkTransactionSnapshot $projectionCfg $targetRoot)) | Out-Null
        }
    }

    return [pscustomobject]@{
        file_snapshots = @($filePaths | Sort-Object | ForEach-Object { Get-SkillProjectionFileTransactionSnapshot $_ })
        link_snapshots = @($linkSnapshots.ToArray())
        config_backup_path = ''
    }
}

function Invoke-CodexSkillProjectionSyncCore($projectionCfg, $promotionContext = $null, $transaction = $null) {
    $configRaw = if ($projectionCfg.PSObject.Properties.Match("codex_config_path").Count -gt 0) { [string]$projectionCfg.codex_config_path } else { "~/.codex/config.toml" }
    $manifestRaw = if ($projectionCfg.PSObject.Properties.Match("manifest_path").Count -gt 0) { [string]$projectionCfg.manifest_path } else { "reports/skill-projection/current.json" }
    $configPath = Resolve-SkillProjectionPath $configRaw
    $manifestPath = Resolve-SkillProjectionPath $manifestRaw
    $catalogProjection = Sync-SkillDiscoveryCatalog $projectionCfg
    $nativeProjectionPlan = $null
    $nativeProjectionApply = $null
    $nativeProjectionAuthoritative = $false
    $nativeSettings = Get-CfgObjectProperty $projectionCfg 'native_projection'
    if ($null -ne $nativeSettings -and [bool](Get-CfgObjectProperty $nativeSettings 'enabled')) {
        $managedRoot = Resolve-SkillProjectionPath ([string](Get-CfgObjectProperty $projectionCfg 'managed_source_path'))
        $includedNames = @((Get-CfgObjectProperty $projectionCfg 'managed_link_includes') | ForEach-Object { [string]$_ })
        $excludedNames = @((Get-CfgObjectProperty $projectionCfg 'managed_link_excludes') | ForEach-Object { [string]$_ })
        $capturedAt = [DateTimeOffset]::UtcNow.ToString('o')
        $nativeProjectionPlan = New-NativeSkillProjectionRuntimePlan -ManagedRoot $managedRoot -Config ([pscustomobject]@{ skill_projection = $projectionCfg }) -IncludedNames $includedNames -ExcludedNames $excludedNames -GeneratedAt $capturedAt
        Need ([string]$nativeProjectionPlan.status -eq 'ready' -and [bool]$nativeProjectionPlan.pass) ("native skill projection blocked: enabled={0}, kept={1}, omitted={2}" -f [int]$nativeProjectionPlan.enabled_total, [int]$nativeProjectionPlan.kept_total, [int]$nativeProjectionPlan.omitted_total)
        $nativeProjectionAuthoritative = $true
        if ($DryRun) {
            $nativeProjectionApply = [pscustomobject]@{ status = 'planned'; receipt_id = ''; receipt_path = [string]$nativeProjectionPlan.receipt_path; changed_names = @(); receipt = $null }
        }
        else {
            $nativeProjectionApply = Apply-NativeSkillProjection -Plan $nativeProjectionPlan -ApplyToken ([string]$nativeProjectionPlan.apply_token)
        }
    }
    $plan = New-SkillProjectionPlan $projectionCfg

    $existing = if (Test-Path -LiteralPath $configPath -PathType Leaf) { Get-ContentUtf8 $configPath } else { "" }
    $desired = Build-CodexSkillsProjectionToml $existing @($plan.disabled)
    $changed = -not [string]::Equals($existing, $desired, [System.StringComparison]::Ordinal)
    $backupPath = $null

    if (-not $DryRun) {
        $writeResult = & {
            $writtenBackupPath = $null
            if ($changed) {
                $writtenBackupPath = Backup-CodexSkillProjectionConfig $configPath
                if ($null -ne $transaction) { $transaction.config_backup_path = if ($null -eq $writtenBackupPath) { '' } else { [string]$writtenBackupPath } }
                Set-ContentUtf8 $configPath $desired
            }
            $projectionFingerprint = Get-SkillProjectionPlanFingerprint $plan $nativeProjectionPlan
            $promotion = Get-SkillProjectionPromotionRecord $manifestPath $promotionContext $projectionFingerprint
            $manifest = [ordered]@{
                schema_version = 2
                projection_fingerprint = $projectionFingerprint
                source_revision = [string]$promotion.source_revision
                source_worktree_dirty = [bool]$promotion.source_worktree_dirty
                source_git_state = [string]$promotion.source_git_state
                promotion_mode = [string]$promotion.promotion_mode
                promoted_at = [string]$promotion.promoted_at
                provenance_status = [string]$promotion.provenance_status
                enabled = [bool]$plan.enabled
                generated_at = (Get-Date).ToString("o")
                conflict_policy = [string]$plan.conflict_policy
                source_count = @($projectionCfg.sources).Count
                skill_entry_count = @($plan.skills).Count
                unique_name_count = @($plan.unique_names).Count
                active_name_count = @($plan.active_names).Count
                duplicate_name_groups = [int]$plan.duplicate_name_groups
                disabled_path_count = @($plan.disabled).Count
                conflict_count = @($plan.conflicts).Count
                skill_metadata_chars = [int]$plan.skill_metadata_chars
                external_skill_count = [int]$plan.external_skill_count
                external_skill_metadata_chars = [int]$plan.external_skill_metadata_chars
                estimated_metadata_chars = [int]$plan.estimated_metadata_chars
                external_skills = @($plan.external_skills)
                external_inventory_warnings = @($plan.external_inventory_warnings)
                skills = @($plan.skills)
                canonical = @($plan.canonical)
                active = @($plan.active)
                disabled = @($plan.disabled)
                conflicts = @($plan.conflicts)
                native_projection = if (-not $nativeProjectionAuthoritative) { $null } else { [ordered]@{
                    authoritative = $true
                    status = [string]$nativeProjectionApply.status
                    plan_id = [string]$nativeProjectionPlan.plan_id
                    receipt_id = [string]$nativeProjectionApply.receipt_id
                    receipt_path = [string]$nativeProjectionApply.receipt_path
                    enabled_total = [int]$nativeProjectionPlan.enabled_total
                    kept_total = [int]$nativeProjectionPlan.kept_total
                    omitted_total = [int]$nativeProjectionPlan.omitted_total
                    truncated = [bool]$nativeProjectionPlan.truncated
                } }
            }
            Set-ContentUtf8 $manifestPath ($manifest | ConvertTo-Json -Depth 20)
            return [pscustomobject]@{ backup_path = if ($null -eq $writtenBackupPath) { "" } else { [string]$writtenBackupPath } }
        }
        $backupPath = [string]$writeResult.backup_path
    }

    return [pscustomobject]@{
        success = $true
        persisted = (-not $DryRun)
        changed = $changed
        config_path = $configPath
        manifest_path = $manifestPath
        backup_path = if ($null -eq $backupPath) { "" } else { [string]$backupPath }
        capability_catalog_projection = $catalogProjection
        native_projection = if (-not $nativeProjectionAuthoritative) { $null } else { [pscustomobject]@{ plan = $nativeProjectionPlan; apply = $nativeProjectionApply } }
        plan = $plan
    }
}

function Sync-CodexSkillProjection($projectionCfg, $promotionContext = $null) {
    if ($DryRun) { return Invoke-CodexSkillProjectionSyncCore $projectionCfg $promotionContext }

    $configRaw = if ($projectionCfg.PSObject.Properties.Match('codex_config_path').Count -gt 0) { [string]$projectionCfg.codex_config_path } else { '~/.codex/config.toml' }
    $manifestRaw = if ($projectionCfg.PSObject.Properties.Match('manifest_path').Count -gt 0) { [string]$projectionCfg.manifest_path } else { 'reports/skill-projection/current.json' }
    $transaction = New-CodexSkillProjectionTransaction $projectionCfg (Resolve-SkillProjectionPath $configRaw) (Resolve-SkillProjectionPath $manifestRaw)
    try {
        $result = Invoke-CodexSkillProjectionSyncCore $projectionCfg $promotionContext $transaction
        $result | Add-Member -NotePropertyName transaction_status -NotePropertyValue 'committed' -Force
        return $result
    }
    catch {
        $failure = $_
        $rollbackErrors = New-Object Collections.Generic.List[string]
        foreach ($snapshot in @($transaction.link_snapshots | Sort-Object target_root -Descending)) {
            try { Restore-CodexManagedSkillLinkTransactionSnapshot $snapshot }
            catch { $rollbackErrors.Add($_.Exception.Message) | Out-Null }
        }
        foreach ($snapshot in @($transaction.file_snapshots | Sort-Object path -Descending)) {
            try { Restore-SkillProjectionFileTransactionSnapshot $snapshot }
            catch { $rollbackErrors.Add($_.Exception.Message) | Out-Null }
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$transaction.config_backup_path) -and (Test-Path -LiteralPath ([string]$transaction.config_backup_path) -PathType Leaf)) {
            try { Remove-Item -LiteralPath ([string]$transaction.config_backup_path) -Force }
            catch { $rollbackErrors.Add($_.Exception.Message) | Out-Null }
        }
        if ($rollbackErrors.Count -gt 0) {
            throw ("Skill projection sync failed and aggregate rollback was incomplete. original={0}; rollback={1}" -f $failure.Exception.Message, ($rollbackErrors -join ' | '))
        }
        throw $failure
    }
}

function Sync-ConfiguredSkillProjection($cfg, $promotionContext = $null) {
    if ($null -eq $cfg -or $cfg.PSObject.Properties.Match("skill_projection").Count -eq 0 -or $null -eq $cfg.skill_projection) {
        return [pscustomobject]@{ success = $true; persisted = $false; skipped = $true; plan = $null }
    }
    return (Sync-CodexSkillProjection $cfg.skill_projection $promotionContext)
}
