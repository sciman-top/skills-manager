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

function New-SkillProjectionCompatibilityReport {
    return [pscustomobject]([ordered]@{
            schema_version = 1
            enabled = $false
            mode = 'compatibility_only'
            policy_path = ''
            group_count = 0
            active_group_count = 0
            finding_count = 0
            blocking = $false
            semantic_selection_applied = $false
            profile_reachability_authority = 'none'
            groups = @()
            findings = @()
        })
}

function Get-CodexEnabledPluginIds([string]$configPath) {
    if ([string]::IsNullOrWhiteSpace($configPath) -or -not (Test-Path -LiteralPath $configPath -PathType Leaf)) { return @() }

    $content = Get-ContentUtf8 $configPath
    $pattern = '(?ms)^\s*\[plugins\.(?:"(?<quoted>[^"]+)"|(?<bare>[^\]\r\n]+))\]\s*\r?\n(?<body>.*?)(?=^\s*\[|\z)'
    $ids = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $tableRegex = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::None, [TimeSpan]::FromSeconds(1))
    $enabledRegex = [regex]::new('^\s*enabled\s*=\s*true\s*(?:#.*)?$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Multiline, [TimeSpan]::FromSeconds(1))
    foreach ($match in $tableRegex.Matches($content)) {
        $body = [string]$match.Groups['body'].Value
        if (-not $enabledRegex.IsMatch($body)) { continue }
        $id = if ($match.Groups['quoted'].Success) { [string]$match.Groups['quoted'].Value } else { [string]$match.Groups['bare'].Value }
        $id = $id.Trim()
        if (-not [string]::IsNullOrWhiteSpace($id) -and $seen.Add($id)) { $ids.Add($id) | Out-Null }
    }
    return @($ids.ToArray() | Sort-Object)
}

function Add-SkillExternalInventoryWarning($warnings, [string]$code, [string]$subject, [string]$message) {
    $warnings.Add([pscustomobject][ordered]@{ code = $code; subject = $subject; message = $message }) | Out-Null
}

function Get-CodexExternalSkillInventory($projectionCfg) {
    $result = [ordered]@{
        enabled = $false
        config_path = ''
        plugin_cache_path = ''
        cache_selection = 'newest_usable_version_by_mtime'
        enabled_plugin_ids = @()
        plugin_count = 0
        skill_count = 0
        metadata_chars = 0
        skills = @()
        warnings = @()
    }
    if ($null -eq $projectionCfg) { return [pscustomobject]$result }
    $inventoryCfg = Get-CfgObjectProperty $projectionCfg 'external_skill_inventory'
    if ($null -eq $inventoryCfg) { return [pscustomobject]$result }
    $enabledRaw = Get-CfgObjectProperty $inventoryCfg 'enabled'
    $enabled = ($null -eq $enabledRaw) -or [bool]$enabledRaw
    $result.enabled = $enabled
    if (-not $enabled) { return [pscustomobject]$result }

    $configRawValue = Get-CfgObjectProperty $projectionCfg 'codex_config_path'
    $cacheRawValue = Get-CfgObjectProperty $inventoryCfg 'plugin_cache_path'
    $configRaw = if ([string]::IsNullOrWhiteSpace([string]$configRawValue)) { '~/.codex/config.toml' } else { [string]$configRawValue }
    $cacheRaw = if ([string]::IsNullOrWhiteSpace([string]$cacheRawValue)) { '~/.codex/plugins/cache' } else { [string]$cacheRawValue }
    $configPath = Resolve-SkillProjectionPath $configRaw
    $cachePath = Resolve-SkillProjectionPath $cacheRaw
    $result.config_path = $configPath
    $result.plugin_cache_path = $cachePath
    $warnings = New-Object System.Collections.Generic.List[object]
    $skills = New-Object System.Collections.Generic.List[object]

    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        Add-SkillExternalInventoryWarning $warnings 'codex_config_missing' $configPath 'Codex config is unavailable; external plugin skills were not inventoried.'
        $result.warnings = @($warnings.ToArray())
        return [pscustomobject]$result
    }

    $pluginIds = @(Get-CodexEnabledPluginIds $configPath)
    $result.enabled_plugin_ids = @($pluginIds)
    if (-not (Test-Path -LiteralPath $cachePath -PathType Container)) {
        Add-SkillExternalInventoryWarning $warnings 'plugin_cache_missing' $cachePath 'Codex plugin cache is unavailable; enabled plugins could not be resolved to skill metadata.'
        $result.plugin_count = $pluginIds.Count
        $result.warnings = @($warnings.ToArray())
        return [pscustomobject]$result
    }

    foreach ($pluginId in $pluginIds) {
        $separator = $pluginId.LastIndexOf('@')
        if ($separator -le 0 -or $separator -ge ($pluginId.Length - 1)) {
            Add-SkillExternalInventoryWarning $warnings 'invalid_plugin_id' $pluginId 'Expected enabled plugin id in name@marketplace form.'
            continue
        }
        $pluginName = $pluginId.Substring(0, $separator)
        $marketplace = $pluginId.Substring($separator + 1)
        $safeSegmentPattern = '^[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9_-])?$'
        if ($pluginName -notmatch $safeSegmentPattern -or $marketplace -notmatch $safeSegmentPattern) {
            Add-SkillExternalInventoryWarning $warnings 'unsafe_plugin_id' $pluginId 'Plugin id contains a path segment and was not resolved against the cache.'
            continue
        }
        $pluginRoot = Join-Path (Join-Path $cachePath $marketplace) $pluginName
        if (-not (Test-Path -LiteralPath $pluginRoot -PathType Container)) {
            Add-SkillExternalInventoryWarning $warnings 'enabled_plugin_cache_missing' $pluginId ("No cache directory was found at {0}." -f $pluginRoot)
            continue
        }

        $selectedVersion = $null
        $selectedSkillFiles = @()
        foreach ($versionDir in @(Get-ChildItem -LiteralPath $pluginRoot -Directory -ErrorAction SilentlyContinue | Sort-Object @{ Expression = 'LastWriteTimeUtc'; Descending = $true }, @{ Expression = 'Name'; Descending = $true })) {
            $skillsRoot = Join-Path $versionDir.FullName 'skills'
            if (-not (Test-Path -LiteralPath $skillsRoot -PathType Container)) { continue }
            $candidateFiles = @(Get-ChildItem -LiteralPath $skillsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    $skillFile = Join-Path $_.FullName 'SKILL.md'
                    if (Test-Path -LiteralPath $skillFile -PathType Leaf) { Get-Item -LiteralPath $skillFile }
                })
            if ($candidateFiles.Count -eq 0) { continue }
            $selectedVersion = $versionDir
            $selectedSkillFiles = @($candidateFiles)
            break
        }
        if ($null -eq $selectedVersion) {
            Add-SkillExternalInventoryWarning $warnings 'enabled_plugin_skills_missing' $pluginId 'The newest usable plugin cache has no direct skills/*/SKILL.md entries.'
            continue
        }

        foreach ($skillFile in @($selectedSkillFiles | Sort-Object FullName)) {
            $meta = Get-SkillMetadataFromFile $skillFile.FullName
            $name = if ([string]::IsNullOrWhiteSpace([string]$meta.declared_name)) { $skillFile.Directory.Name } else { [string]$meta.declared_name }
            $description = [string]$meta.description
            $skills.Add([pscustomobject][ordered]@{
                    plugin_id = $pluginId
                    plugin_name = $pluginName
                    marketplace = $marketplace
                    cache_version = [string]$selectedVersion.Name
                    name = $name
                    qualified_name = ("{0}::{1}" -f $pluginId, $name)
                    description = $description
                    path = $skillFile.FullName
                }) | Out-Null
        }
    }

    $metadataChars = 0
    foreach ($skill in @($skills.ToArray())) { $metadataChars += ([string]$skill.name).Length + ([string]$skill.description).Length }
    $result.plugin_count = $pluginIds.Count
    $result.skill_count = $skills.Count
    $result.metadata_chars = $metadataChars
    $result.skills = @($skills.ToArray() | Sort-Object plugin_id, name)
    $result.warnings = @($warnings.ToArray())
    return [pscustomobject]$result
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

function Get-SkillProjectionPackageHashCacheSchemaVersion {
    return 1
}

function Test-SkillProjectionSha256([string]$value) {
    return (-not [string]::IsNullOrWhiteSpace($value) -and $value -match '^[0-9a-fA-F]{64}$')
}

function New-SkillProjectionPackageHashContext($projectionCfg, [string]$verifiedBuildSignature, [string]$manifestPath) {
    $context = [pscustomobject]([ordered]@{
        cache_schema = Get-SkillProjectionPackageHashCacheSchemaVersion
        verified_build_signature = $verifiedBuildSignature
        managed_root = ""
        cache_valid = $false
        cache_entries = @{}
        cache_hits = 0
        cache_misses = 0
        full_hash_count = 0
        fingerprint_ms = 0
        full_hash_ms = 0
    })
    if ($null -eq $projectionCfg -or [string]::IsNullOrWhiteSpace($verifiedBuildSignature)) { return $context }
    if ($projectionCfg.PSObject.Properties.Match("managed_source_path").Count -eq 0) { return $context }

    $managedRoot = Resolve-SkillProjectionPath ([string]$projectionCfg.managed_source_path)
    if ([string]::IsNullOrWhiteSpace($managedRoot) -or -not (Test-Path -LiteralPath $managedRoot -PathType Container)) { return $context }
    $context.managed_root = $managedRoot
    if ([string]::IsNullOrWhiteSpace($manifestPath) -or -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return $context }

    try {
        $manifest = Get-ContentUtf8 $manifestPath | ConvertFrom-Json
        if ($null -eq $manifest) { return $context }
        if ($manifest.PSObject.Properties.Match("package_hash_cache_schema").Count -eq 0 -or [int]$manifest.package_hash_cache_schema -ne $context.cache_schema) { return $context }
        if ($manifest.PSObject.Properties.Match("agent_build_signature").Count -eq 0 -or [string]$manifest.agent_build_signature -ne $verifiedBuildSignature) { return $context }

        $entries = @{}
        foreach ($entry in @($manifest.skills)) {
            if ($null -eq $entry) { continue }
            $skillDir = [string]$entry.skill_dir
            $packageHash = [string]$entry.package_hash
            $packageFingerprint = [string]$entry.package_fingerprint
            $contentHash = [string]$entry.content_hash
            if ([string]::IsNullOrWhiteSpace($skillDir) -or [string]::IsNullOrWhiteSpace($packageHash) -or [string]::IsNullOrWhiteSpace($packageFingerprint) -or [string]::IsNullOrWhiteSpace($contentHash)) { continue }
            if (-not (Test-SkillProjectionSha256 $packageHash) -or -not (Test-SkillProjectionSha256 $packageFingerprint) -or -not (Test-SkillProjectionSha256 $contentHash)) { continue }
            $key = [System.IO.Path]::GetFullPath($skillDir).ToLowerInvariant()
            $entries[$key] = [pscustomobject]@{
                package_hash = $packageHash
                package_fingerprint = $packageFingerprint
                content_hash = $contentHash
            }
        }
        $context.cache_entries = $entries
        $context.cache_valid = $true
    }
    catch {
        Log ("技能投影哈希缓存读取失败，已回退完整计算：{0}" -f $_.Exception.Message) "WARN"
    }
    return $context
}

function Get-SkillProjectionPackageHash([string]$skillDir, [string]$contentHash, $packageHashContext) {
    $fullSkillDir = [System.IO.Path]::GetFullPath($skillDir)
    $cacheKey = $fullSkillDir.ToLowerInvariant()
    $managedTarget = ""
    $packageFingerprint = ""
    $isManaged = $false

    if ($null -ne $packageHashContext -and -not [string]::IsNullOrWhiteSpace([string]$packageHashContext.managed_root) -and (Is-ReparsePoint $fullSkillDir)) {
        $target = Get-ReparsePointTargetFullPath $fullSkillDir
        if (-not [string]::IsNullOrWhiteSpace($target) -and (Is-PathInsideOrEqual $target ([string]$packageHashContext.managed_root))) {
            $managedTarget = [System.IO.Path]::GetFullPath($target)
            $isManaged = $true
            $fingerprintTimer = [System.Diagnostics.Stopwatch]::StartNew()
            try { $packageFingerprint = Get-DirectoryFingerprint $managedTarget }
            finally {
                $fingerprintTimer.Stop()
                $packageHashContext.fingerprint_ms += [int]$fingerprintTimer.ElapsedMilliseconds
            }
        }
    }

    if ($isManaged -and [bool]$packageHashContext.cache_valid -and $packageHashContext.cache_entries.ContainsKey($cacheKey)) {
        $cached = $packageHashContext.cache_entries[$cacheKey]
        if ([string]$cached.package_fingerprint -eq $packageFingerprint -and [string]$cached.content_hash -eq $contentHash) {
            $packageHashContext.cache_hits++
            return [pscustomobject]@{
                package_hash = [string]$cached.package_hash
                package_fingerprint = $packageFingerprint
                cache_hit = $true
            }
        }
    }

    if ($isManaged) { $packageHashContext.cache_misses++ }
    $hashTimer = [System.Diagnostics.Stopwatch]::StartNew()
    try { $packageHash = Get-SkillPackageContentHash $fullSkillDir }
    finally {
        $hashTimer.Stop()
        if ($null -ne $packageHashContext) {
            $packageHashContext.full_hash_count++
            $packageHashContext.full_hash_ms += [int]$hashTimer.ElapsedMilliseconds
        }
    }
    return [pscustomobject]@{
        package_hash = [string]$packageHash
        package_fingerprint = $packageFingerprint
        cache_hit = $false
    }
}

function Test-SkillProjectionManagedCacheHotPath($packageHashContext) {
    if ($null -eq $packageHashContext) { return $false }
    return ([bool]$packageHashContext.cache_valid -and
        [int]$packageHashContext.cache_hits -gt 0 -and
        [int]$packageHashContext.cache_misses -eq 0)
}

function Get-SkillCanonicalInventorySnapshot($entries) {
    $items = @($entries | ForEach-Object {
            [ordered]@{
                name = [string]$_.name
                path = [string]$_.path
                description = [string]$_.description
            }
        } | Sort-Object name, path)
    $json = $items | ConvertTo-Json -Depth 5 -Compress
    return [pscustomobject]@{
        fingerprint = Get-StringSha256 ([string]$json)
        items = $items
    }
}

function Resolve-SkillProfileReconciliationSignalPath($projectionCfg, [string]$manifestPath) {
    if ($projectionCfg.PSObject.Properties.Match("reconciliation_signal_path").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$projectionCfg.reconciliation_signal_path)) {
        return (Resolve-SkillProjectionPath ([string]$projectionCfg.reconciliation_signal_path))
    }
    $manifestDir = Split-Path $manifestPath -Parent
    if ([string]::Equals((Split-Path $manifestDir -Leaf), "skill-projection", [System.StringComparison]::OrdinalIgnoreCase)) {
        return (Join-Path (Split-Path $manifestDir -Parent) "skill-profile-reconciliation\pending.json")
    }
    return (Join-Path $manifestDir "skill-profile-reconciliation-pending.json")
}

function New-SkillProfileReconciliationSignal($projectionCfg, [string]$manifestPath, $currentPlan) {
    $previousCanonical = @()
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        try {
            $previousManifest = Get-ContentUtf8 $manifestPath | ConvertFrom-Json
            $previousCanonical = @($previousManifest.canonical)
        }
        catch {
            $previousCanonical = @()
        }
    }
    $before = Get-SkillCanonicalInventorySnapshot $previousCanonical
    $after = Get-SkillCanonicalInventorySnapshot @($currentPlan.canonical)
    $beforeByName = @{}
    $afterByName = @{}
    foreach ($entry in @($before.items)) { $beforeByName[[string]$entry.name] = $entry }
    foreach ($entry in @($after.items)) { $afterByName[[string]$entry.name] = $entry }
    $added = @($afterByName.Keys | Where-Object { -not $beforeByName.ContainsKey($_) } | Sort-Object)
    $removed = @($beforeByName.Keys | Where-Object { -not $afterByName.ContainsKey($_) } | Sort-Object)
    $metadataChanged = @($afterByName.Keys | Where-Object {
            $beforeByName.ContainsKey($_) -and
            (-not [string]::Equals([string]$beforeByName[$_].path, [string]$afterByName[$_].path, [System.StringComparison]::OrdinalIgnoreCase) -or
                -not [string]::Equals([string]$beforeByName[$_].description, [string]$afterByName[$_].description, [System.StringComparison]::Ordinal))
        } | Sort-Object)
    $signalPath = Resolve-SkillProfileReconciliationSignalPath $projectionCfg $manifestPath
    $changed = ($added.Count + $removed.Count + $metadataChanged.Count) -gt 0
    $skillsConfigPath = Join-Path $Root "skills.json"
    return [pscustomobject]([ordered]@{
            schema_version = 1
            status = if ($changed) { "host_refresh_needed" } else { "not_needed" }
            reason = if ($changed) { "canonical_inventory_changed" } else { "canonical_inventory_unchanged" }
            added_names = $added
            removed_names = $removed
            metadata_changed_names = $metadataChanged
            before_fingerprint = [string]$before.fingerprint
            after_fingerprint = [string]$after.fingerprint
            config_sha256 = if (Test-Path -LiteralPath $skillsConfigPath -PathType Leaf) { Get-FileContentHash $skillsConfigPath } else { "" }
            next_action = if ($changed) { "fresh_session_or_host_handoff" } else { "none" }
            advisor_command = ""
            active_profile = [string]$currentPlan.active_profile
            profile_names = @($currentPlan.profile_budgets | ForEach-Object { [string]$_.profile } | Sort-Object -Unique)
            unrouted_names = @($currentPlan.unrouted_names)
            writes_profile_config = $false
            signal_path = $signalPath
        })
}

function Get-SkillProjectionSourceEntries($source, [int]$sourceOrder, $packageHashContext = $null) {
    $id = [string]$source.id
    $rootPath = Resolve-SkillProjectionPath ([string]$source.path)
    $priority = if ($source.PSObject.Properties.Match("priority").Count -gt 0) { [int]$source.priority } else { 0 }
    $platforms = if ($source.PSObject.Properties.Match("platforms").Count -gt 0 -and $null -ne $source.platforms) { @($source.platforms | ForEach-Object { [string]$_ }) } else { @("codex") }
    $entries = New-Object System.Collections.Generic.List[object]

    foreach ($item in @(Get-SkillProjectionFiles $rootPath)) {
        $meta = Get-SkillMetadataFromFile ([string]$item.file)
        $declaredName = ([string]$meta.declared_name).Trim()
        if ([string]::IsNullOrWhiteSpace($declaredName)) {
            $declaredName = Split-Path ([string]$item.dir) -Leaf
        }
        $effectivePriority = $priority
        if ([bool]$item.is_system) { $effectivePriority += 100000 }
        $contentHash = [string](Get-FileContentHash ([string]$item.file))
        $packageHashResult = Get-SkillProjectionPackageHash ([string]$item.dir) $contentHash $packageHashContext
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
                    package_hash = [string]$packageHashResult.package_hash
                    package_fingerprint = [string]$packageHashResult.package_fingerprint
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

function New-CapabilityRouterCatalogDocument($projectionCfg) {
    Need ($null -ne $projectionCfg) 'skill_projection 配置为空'
    Need ($projectionCfg.PSObject.Properties.Match('managed_source_path').Count -gt 0) 'skill_projection 缺少 managed_source_path'
    $managedRoot = Resolve-SkillProjectionPath ([string]$projectionCfg.managed_source_path)
    Need (Test-Path -LiteralPath $managedRoot -PathType Container) ("受管技能源不存在：{0}" -f $managedRoot)

    $routerDir = Join-Path $managedRoot 'capability-router'
    Need (Test-Path -LiteralPath (Join-Path $routerDir 'SKILL.md') -PathType Leaf) '受管技能源缺少 capability-router'

    $policy = $null
    if ($projectionCfg.PSObject.Properties.Match('routing_policy_path').Count -gt 0) {
        $policyPath = Resolve-SkillProjectionPath ([string]$projectionCfg.routing_policy_path)
        if (Test-Path -LiteralPath $policyPath -PathType Leaf) { $policy = Get-ContentUtf8 $policyPath | ConvertFrom-Json }
    }

    $domainPurpose = [ordered]@{}
    $membership = @{}
    if ($projectionCfg.PSObject.Properties.Match('profiles').Count -gt 0 -and $null -ne $projectionCfg.profiles) {
        foreach ($property in @($projectionCfg.profiles.PSObject.Properties | Sort-Object Name)) {
            $domainName = [string]$property.Name
            $purpose = if ($property.Value.PSObject.Properties.Match('purpose').Count -gt 0) { [string]$property.Value.purpose } else { '' }
            $domainPurpose[$domainName] = $purpose
            foreach ($skillName in @($property.Value.enabled_names)) { Add-CapabilityCatalogMembership $membership ([string]$skillName) $domainName }
        }
    }

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
        $meta = Get-SkillMetadataFromFile ([string]$item.file)
        $name = ([string]$meta.declared_name).Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { $name = Split-Path ([string]$item.dir) -Leaf }
        if ([string]::Equals($name, 'capability-router', [System.StringComparison]::OrdinalIgnoreCase) -or -not $actualNames.Add($name)) { continue }
        if (-not $membership.ContainsKey($name) -or $membership[$name].Count -eq 0) {
            Add-CapabilityCatalogMembership $membership $name $fallbackDomain
        }
        $relativeWithinManaged = ([string]$item.file).Substring($managedRoot.TrimEnd('\', '/').Length).TrimStart('\', '/')
        $relativeFromRouter = ('..\{0}' -f $relativeWithinManaged)
        $rules = if ($rulesByName.ContainsKey($name)) { @($rulesByName[$name].ToArray() | Sort-Object group, role) } else { @() }
        $skills.Add([ordered]@{
                name = $name
                description = [string]$meta.description
                relative_path = $relativeFromRouter
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

    $capabilities = if ($null -ne $policy) { @($policy.capabilities | Sort-Object kind, name) } else { @() }
    $catalog = [ordered]@{
        schema_version = 1
        decision_owner = 'host_ai'
        semantic_routing_performed = $false
        domains = @($domainRows.ToArray() | Sort-Object name)
        skills = @($skills.ToArray() | Sort-Object name)
        capabilities = $capabilities
    }
    $catalog.catalog_fingerprint = Get-CapabilityCatalogTextSha256 ($catalog | ConvertTo-Json -Depth 20 -Compress)
    return $catalog
}

function Sync-CapabilityRouterCatalog($projectionCfg) {
    if ($null -eq $projectionCfg -or $projectionCfg.PSObject.Properties.Match('managed_source_path').Count -eq 0) {
        return [pscustomobject]@{ enabled = $false; reason = 'not_configured'; changed = $false; persisted = $false; path = ''; skill_count = 0; domain_count = 0 }
    }
    $managedRoot = Resolve-SkillProjectionPath ([string]$projectionCfg.managed_source_path)
    $catalogPath = Join-Path $managedRoot 'capability-router\catalog.json'
    if (-not (Test-Path -LiteralPath (Join-Path $managedRoot 'capability-router\SKILL.md') -PathType Leaf)) {
        return [pscustomobject]@{ enabled = $false; reason = 'router_missing'; changed = $false; persisted = $false; path = $catalogPath; skill_count = 0; domain_count = 0 }
    }
    $catalog = New-CapabilityRouterCatalogDocument $projectionCfg
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

function Sync-CodexManagedSkillLinks($projectionCfg) {
    Need ($null -ne $projectionCfg) "skill_projection 配置为空"
    Need ($projectionCfg.PSObject.Properties.Match("managed_source_path").Count -gt 0) "skill_projection 缺少 managed_source_path"
    Need ($projectionCfg.PSObject.Properties.Match("user_skill_root").Count -gt 0) "skill_projection 缺少 user_skill_root"
    $managedRoot = Resolve-SkillProjectionPath ([string]$projectionCfg.managed_source_path)
    $userRoot = Resolve-SkillProjectionPath ([string]$projectionCfg.user_skill_root)
    Need (Test-Path -LiteralPath $managedRoot -PathType Container) ("受管技能源不存在：{0}" -f $managedRoot)
    Need (-not [string]::Equals($managedRoot, $userRoot, [System.StringComparison]::OrdinalIgnoreCase)) "受管技能源不能与用户投影根相同"

    EnsureDir $userRoot
    $excluded = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($projectionCfg.PSObject.Properties.Match("managed_link_excludes").Count -gt 0 -and $null -ne $projectionCfg.managed_link_excludes) {
        foreach ($name in @($projectionCfg.managed_link_excludes)) {
            $excluded.Add(([string]$name).Trim()) | Out-Null
        }
    }
    $included = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($projectionCfg.PSObject.Properties.Match("managed_link_includes").Count -gt 0 -and $null -ne $projectionCfg.managed_link_includes) {
        foreach ($name in @($projectionCfg.managed_link_includes)) {
            $included.Add(([string]$name).Trim()) | Out-Null
        }
    }
    $useIncludeFilter = $included.Count -gt 0
    $desired = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($dir in @(Get-ChildItem -LiteralPath $managedRoot -Directory -Force | Where-Object Name -ne ".system" | Sort-Object Name)) {
        if ($excluded.Contains($dir.Name) -or ($useIncludeFilter -and -not $included.Contains($dir.Name))) { continue }
        # Only generated skill packages with an entrypoint belong in the host
        # skill root.  Override-only directories (for example a resource or
        # agent policy directory without SKILL.md) must remain in agent/ but
        # must not become loadable host junctions.
        if (-not (Test-Path -LiteralPath (Join-Path $dir.FullName "SKILL.md") -PathType Leaf)) { continue }
        $linkPath = Join-Path $userRoot $dir.Name
        New-Junction $linkPath $dir.FullName -QuietIfUnchanged
        $desired.Add($dir.Name) | Out-Null
    }
    $missingIncludedPackages = @($included | Where-Object { -not $desired.Contains($_) } | Sort-Object)
    Need ($missingIncludedPackages.Count -eq 0) ("managed_link_includes 中的技能包不存在或缺少 SKILL.md：{0}" -f ($missingIncludedPackages -join ", "))

    $staleRemoved = 0
    foreach ($entry in @(Get-ChildItem -LiteralPath $userRoot -Directory -Force -ErrorAction SilentlyContinue | Where-Object Name -ne ".system")) {
        if ($desired.Contains($entry.Name) -or -not (Is-ReparsePoint $entry.FullName)) { continue }
        $target = Get-ReparsePointTargetFullPath $entry.FullName
        $managedPrefix = $managedRoot.TrimEnd("\") + "\"
        if (-not [string]::IsNullOrWhiteSpace($target) -and $target.StartsWith($managedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            Invoke-RemoveItem $entry.FullName -Recurse
            $staleRemoved++
        }
    }

    return [pscustomobject]@{
        managed_source_path = $managedRoot
        user_skill_root = $userRoot
        managed_link_count = $desired.Count
        stale_link_count = $staleRemoved
    }
}

function New-SkillProjectionPlan($projectionCfg, $packageHashContext = $null) {
    Need ($null -ne $projectionCfg) "skill_projection 配置为空"
    $enabled = -not ($projectionCfg.PSObject.Properties.Match("enabled").Count -gt 0) -or [bool]$projectionCfg.enabled
    if (-not $enabled) {
        return [pscustomobject]@{ schema_version = 2; enabled = $false; skills = @(); canonical = @(); active = @(); disabled = @(); conflicts = @(); unique_names = @(); active_names = @(); duplicate_name_groups = 0; profile_routed_name_count = 0; unrouted_name_count = 0; profile_routed_names = @(); unrouted_names = @(); external_skills = @(); external_inventory_warnings = @(); routing_report = (New-SkillProjectionCompatibilityReport) }
    }

    Need ($projectionCfg.PSObject.Properties.Match("sources").Count -gt 0 -and $null -ne $projectionCfg.sources) "skill_projection 缺少 sources"
    $all = New-Object System.Collections.Generic.List[object]
    $sourceOrder = 0
    foreach ($source in @($projectionCfg.sources)) {
        Need ($null -ne $source) "skill_projection.sources 不能包含空值"
        Need (-not [string]::IsNullOrWhiteSpace([string]$source.id)) "skill_projection source 缺少 id"
        Need (-not [string]::IsNullOrWhiteSpace([string]$source.path)) ("skill_projection source 缺少 path：{0}" -f [string]$source.id)
        foreach ($entry in @(Get-SkillProjectionSourceEntries $source $sourceOrder $packageHashContext)) {
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
            Need ($canonicalByName.ContainsKey($replacement)) ("skill_projection alias replacement 不存在：{0} -> {1}" -f $aliasName, $replacement)
            $aliases[$aliasName] = $replacement
        }
    }

    $budgetLimitChars = if ($projectionCfg.PSObject.Properties.Match("budget_limit_chars").Count -gt 0) { [int]$projectionCfg.budget_limit_chars } else { 8000 }
    $externalReserveChars = if ($projectionCfg.PSObject.Properties.Match("external_metadata_reserve_chars").Count -gt 0) { [int]$projectionCfg.external_metadata_reserve_chars } else { 0 }
    Need ($budgetLimitChars -gt 0) "skill_projection.budget_limit_chars 必须大于 0"
    Need ($externalReserveChars -ge 0) "skill_projection.external_metadata_reserve_chars 不能小于 0"
    $externalInventory = Get-CodexExternalSkillInventory $projectionCfg
    $externalSkillMetadataChars = [int]$externalInventory.metadata_chars
    $effectiveExternalMetadataChars = [Math]::Max($externalReserveChars, $externalSkillMetadataChars)

    $activeProfile = ""
    $activeEffectiveBudgetLimitChars = $budgetLimitChars
    $profileEnabledNames = $null
    $profileBudgets = New-Object System.Collections.Generic.List[object]
    $profileNamesBySkill = @{}
    $profileRoutingEnabled = $false
    $residentNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($projectionCfg.PSObject.Properties.Match("resident_names").Count -gt 0 -and $null -ne $projectionCfg.resident_names) {
        foreach ($rawName in @($projectionCfg.resident_names)) {
            $name = ([string]$rawName).Trim()
            Need (-not [string]::IsNullOrWhiteSpace($name)) "skill_projection.resident_names 不得包含空值"
            Need ($canonicalByName.ContainsKey($name)) ("skill_projection resident_names 引用了不存在的技能：{0}" -f $name)
            $residentNames.Add($name) | Out-Null
        }
    }
    if ($projectionCfg.PSObject.Properties.Match("profiles").Count -gt 0 -and $null -ne $projectionCfg.profiles) {
        $profileRoutingEnabled = $true
        $activeProfile = ([string]$projectionCfg.active_profile).Trim()
        Need (-not [string]::IsNullOrWhiteSpace($activeProfile)) "skill_projection 配置 profiles 时必须声明 active_profile"
        $profileProperty = @($projectionCfg.profiles.PSObject.Properties | Where-Object { [string]::Equals($_.Name, $activeProfile, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        Need ($profileProperty.Count -eq 1) ("skill_projection active_profile 不存在：{0}" -f $activeProfile)
        foreach ($property in @($projectionCfg.profiles.PSObject.Properties | Sort-Object Name)) {
            $profileName = [string]$property.Name
            $profile = $property.Value
            Need ($null -ne $profile -and $profile.PSObject.Properties.Match("enabled_names").Count -gt 0) ("skill_projection profile 缺少 enabled_names：{0}" -f $profileName)
            $profileBudgetLimitChars = if ($profile.PSObject.Properties.Match("budget_limit_chars").Count -gt 0) { [int]$profile.budget_limit_chars } else { $budgetLimitChars }
            Need ($profileBudgetLimitChars -gt 0) ("skill_projection profile.budget_limit_chars 必须大于 0：{0}" -f $profileName)
            Need ($profileBudgetLimitChars -le $budgetLimitChars) ("skill_projection profile.budget_limit_chars 不能超过全局上限：{0}" -f $profileName)
            $enabledNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($rawName in @($profile.enabled_names)) {
                $name = ([string]$rawName).Trim()
                Need (-not [string]::IsNullOrWhiteSpace($name)) ("skill_projection profile enabled_names 不得包含空值：{0}" -f $profileName)
                Need ($canonicalByName.ContainsKey($name)) ("skill_projection profile 引用了不存在的技能：{0}/{1}" -f $profileName, $name)
                $enabledNames.Add($name) | Out-Null
                if (-not $profileNamesBySkill.ContainsKey($name)) {
                    $profileNamesBySkill[$name] = New-Object System.Collections.Generic.List[string]
                }
                $profileNamesBySkill[$name].Add($profileName) | Out-Null
            }
            foreach ($residentName in @($residentNames)) { $enabledNames.Add($residentName) | Out-Null }

            $profileMetadataChars = 0
            $profileActiveSkillCount = 0
            foreach ($entry in @($canonical.ToArray())) {
                $entryName = [string]$entry.name
                if ($aliases.ContainsKey($entryName)) { continue }
                if (-not [bool]$entry.is_system -and -not $enabledNames.Contains($entryName)) { continue }
                $profileMetadataChars += $entryName.Length + ([string]$entry.description).Length
                $profileActiveSkillCount++
            }
            $profileEstimatedChars = $profileMetadataChars + $effectiveExternalMetadataChars
            $profileBudgets.Add([pscustomobject]([ordered]@{
                        profile = $profileName
                        enabled_name_count = $enabledNames.Count
                        active_skill_count = $profileActiveSkillCount
                        skill_metadata_chars = $profileMetadataChars
                        external_metadata_reserve_chars = $externalReserveChars
                        external_skill_count = [int]$externalInventory.skill_count
                        external_skill_metadata_chars = $externalSkillMetadataChars
                        effective_external_metadata_chars = $effectiveExternalMetadataChars
                        estimated_metadata_chars = $profileEstimatedChars
                        budget_limit_chars = $profileBudgetLimitChars
                        budget_pass = ($profileEstimatedChars -le $profileBudgetLimitChars)
                    })) | Out-Null

            if ([string]::Equals($profileName, $activeProfile, [System.StringComparison]::OrdinalIgnoreCase)) {
                $profileEnabledNames = $enabledNames
                $activeEffectiveBudgetLimitChars = $profileBudgetLimitChars
            }
        }
    }

    $profileRoutedNames = New-Object System.Collections.Generic.List[string]
    $unroutedNames = New-Object System.Collections.Generic.List[string]
    if ($profileRoutingEnabled) {
        foreach ($entry in @($canonical.ToArray())) {
            $entryName = [string]$entry.name
            if ([bool]$entry.is_system -or $aliases.ContainsKey($entryName)) { continue }
            if ($residentNames.Contains($entryName) -or $profileNamesBySkill.ContainsKey($entryName)) {
                $profileRoutedNames.Add($entryName) | Out-Null
            }
            else {
                $unroutedNames.Add($entryName) | Out-Null
            }
        }
    }

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
        if ($null -ne $profileEnabledNames -and -not [bool]$entry.is_system -and -not $profileEnabledNames.Contains($name)) {
            $availableProfiles = if ($profileNamesBySkill.ContainsKey($name)) {
                @($profileNamesBySkill[$name].ToArray() | Sort-Object)
            }
            else { @() }
            $disabled.Add([pscustomobject]([ordered]@{
                        name = $name
                        path = [string]$entry.path
                        source_id = [string]$entry.source_id
                        source_root = [string]$entry.source_root
                        content_hash = [string]$entry.content_hash
                        package_hash = [string]$entry.package_hash
                        target_platforms = @($entry.target_platforms)
                        canonical_path = [string]$entry.path
                        canonical_source_id = [string]$entry.source_id
                        active_profile = $activeProfile
                        profile_reachability = if ($availableProfiles.Count -gt 0) { "routed_elsewhere" } else { "unrouted" }
                        available_profiles = @($availableProfiles)
                        decision = "profile_excluded"
                    })) | Out-Null
            continue
        }
        $active.Add($entry) | Out-Null
    }

    $skillMetadataChars = 0
    foreach ($entry in @($active.ToArray())) {
        $skillMetadataChars += ([string]$entry.name).Length + ([string]$entry.description).Length
    }
    $estimatedMetadataChars = $skillMetadataChars + $effectiveExternalMetadataChars
    $allProfilesBudgetPass = @($profileBudgets.ToArray() | Where-Object { -not [bool]$_.budget_pass }).Count -eq 0
    $routingReport = New-SkillProjectionCompatibilityReport

    return [pscustomobject]([ordered]@{
        schema_version = 2
        enabled = $true
        conflict_policy = "system_then_priority_then_source_order"
        active_profile = $activeProfile
        resident_names = @($residentNames | Sort-Object)
        skills = @($all.ToArray() | Sort-Object name, @{ Expression = "priority"; Descending = $true }, path)
        canonical = @($canonical.ToArray() | Sort-Object name)
        active = @($active.ToArray() | Sort-Object name)
        disabled = @($disabled.ToArray() | Sort-Object name, path)
        conflicts = @($conflicts.ToArray() | Sort-Object name)
        unique_names = @($canonical.ToArray() | ForEach-Object { [string]$_.name } | Sort-Object)
        active_names = @($active.ToArray() | ForEach-Object { [string]$_.name } | Sort-Object)
        duplicate_name_groups = $duplicateGroups
        profile_routed_name_count = $profileRoutedNames.Count
        unrouted_name_count = $unroutedNames.Count
        profile_routed_names = @($profileRoutedNames.ToArray() | Sort-Object)
        unrouted_names = @($unroutedNames.ToArray() | Sort-Object)
        skill_metadata_chars = $skillMetadataChars
        external_metadata_reserve_chars = $externalReserveChars
        external_skill_count = [int]$externalInventory.skill_count
        external_skill_metadata_chars = $externalSkillMetadataChars
        effective_external_metadata_chars = $effectiveExternalMetadataChars
        estimated_metadata_chars = $estimatedMetadataChars
        budget_limit_chars = $budgetLimitChars
        effective_budget_limit_chars = $activeEffectiveBudgetLimitChars
        budget_pass = ($estimatedMetadataChars -le $activeEffectiveBudgetLimitChars)
        all_profiles_budget_pass = $allProfilesBudgetPass
        profile_budgets = @($profileBudgets.ToArray())
        external_skills = @($externalInventory.skills)
        external_inventory_warnings = @($externalInventory.warnings)
        routing_report = $routingReport
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
                gate_receipt_status = "not_provided"
                gate_receipt_path = ""
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
            gate_receipt_status = "not_provided"
            gate_receipt_path = ""
        })
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
            gate_receipt_status = [string]$promotionContext.gate_receipt_status
            gate_receipt_path = [string]$promotionContext.gate_receipt_path
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
                        gate_receipt_status = "stale"
                        gate_receipt_path = ""
                    }
                }
                $existingGateReceipt = if ($existingManifest.PSObject.Properties.Match("gate_receipt").Count -gt 0) { $existingManifest.gate_receipt } else { $null }
                return [pscustomobject]@{
                    source_revision = [string]$existingManifest.source_revision
                    source_worktree_dirty = [bool]$existingManifest.source_worktree_dirty
                    source_git_state = [string]$existingManifest.source_git_state
                    promotion_mode = [string]$existingManifest.promotion_mode
                    promoted_at = [string]$existingManifest.promoted_at
                    provenance_status = "current"
                    gate_receipt_status = if ($null -ne $existingGateReceipt) { [string]$existingGateReceipt.status } else { "not_provided" }
                    gate_receipt_path = if ($null -ne $existingGateReceipt) { [string]$existingGateReceipt.path } else { "" }
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
        gate_receipt_status = "not_provided"
        gate_receipt_path = ""
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
    $filePaths.Add([IO.Path]::GetFullPath((Resolve-SkillProfileReconciliationSignalPath $projectionCfg $ManifestPath))) | Out-Null

    $managedRoot = ''
    if ($projectionCfg.PSObject.Properties.Match('managed_source_path').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$projectionCfg.managed_source_path)) {
        $managedRoot = Resolve-SkillProjectionPath ([string]$projectionCfg.managed_source_path)
        $filePaths.Add([IO.Path]::GetFullPath((Join-Path $managedRoot 'capability-router\catalog.json'))) | Out-Null
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

function Invoke-CodexSkillProjectionSyncCore($projectionCfg, [string]$verifiedBuildSignature = "", $promotionContext = $null, $transaction = $null) {
    $configRaw = if ($projectionCfg.PSObject.Properties.Match("codex_config_path").Count -gt 0) { [string]$projectionCfg.codex_config_path } else { "~/.codex/config.toml" }
    $manifestRaw = if ($projectionCfg.PSObject.Properties.Match("manifest_path").Count -gt 0) { [string]$projectionCfg.manifest_path } else { "reports/skill-projection/current.json" }
    $configPath = Resolve-SkillProjectionPath $configRaw
    $manifestPath = Resolve-SkillProjectionPath $manifestRaw
    $catalogProjection = Invoke-WithMetric 'projection_capability_catalog' { Sync-CapabilityRouterCatalog $projectionCfg } @{ command = '技能投影' } -NoHost
    $nativeProjectionPlan = $null
    $nativeProjectionApply = $null
    $nativeProjectionAuthoritative = $false
    $nativeSettings = Get-CfgObjectProperty $projectionCfg 'native_projection'
    if ($null -ne $nativeSettings -and [bool](Get-CfgObjectProperty $nativeSettings 'enabled')) {
        $managedRoot = Resolve-SkillProjectionPath ([string](Get-CfgObjectProperty $projectionCfg 'managed_source_path'))
        $includedNames = @((Get-CfgObjectProperty $projectionCfg 'managed_link_includes') | ForEach-Object { [string]$_ })
        $excludedNames = @((Get-CfgObjectProperty $projectionCfg 'managed_link_excludes') | ForEach-Object { [string]$_ })
        $capturedAt = [DateTimeOffset]::UtcNow.ToString('o')
        $snapshot = New-HostCapabilitySnapshotFromConfigFallback -ConfigPath $configPath -Surface 'cli' -CapturedAt $capturedAt
        $policyPath = Join-Path $Root 'config\native-skill-metadata-policy.json'
        $policy = if (Test-Path -LiteralPath $policyPath -PathType Leaf) { Get-ContentUtf8 $policyPath | ConvertFrom-Json } else { Get-DefaultNativeMetadataPolicy }
        $nativeProjectionPlan = New-NativeSkillProjectionRuntimePlan -ManagedRoot $managedRoot -Config ([pscustomobject]@{ skill_projection = $projectionCfg }) -Snapshot $snapshot -Policy $policy -IncludedNames $includedNames -ExcludedNames $excludedNames -GeneratedAt $capturedAt
        Need ([string]$nativeProjectionPlan.status -eq 'ready' -and [bool]$nativeProjectionPlan.pass) ("native skill projection blocked: enabled={0}, kept={1}, omitted={2}" -f [int]$nativeProjectionPlan.enabled_total, [int]$nativeProjectionPlan.kept_total, [int]$nativeProjectionPlan.omitted_total)
        $nativeProjectionAuthoritative = $true
        if ($DryRun) {
            $nativeProjectionApply = [pscustomobject]@{ status = 'planned'; receipt_id = ''; receipt_path = [string]$nativeProjectionPlan.receipt_path; changed_names = @(); receipt = $null }
        }
        else {
            $nativeProjectionApply = Invoke-WithMetric 'native_projection_apply' {
                Apply-NativeSkillProjection -Plan $nativeProjectionPlan -ApplyToken ([string]$nativeProjectionPlan.apply_token)
            } @{ command = '技能投影'; enabled_total = [int]$nativeProjectionPlan.enabled_total } -NoHost
        }
    }
    $linkProjection = $null
    if ($projectionCfg.PSObject.Properties.Match("managed_source_path").Count -gt 0 -or $projectionCfg.PSObject.Properties.Match("user_skill_root").Count -gt 0) {
        $linkProjection = Invoke-WithMetric "projection_link_reconcile" { Sync-CodexManagedSkillLinks $projectionCfg } @{ command = "技能投影" } -NoHost
    }
    $packageHashContext = New-SkillProjectionPackageHashContext $projectionCfg $verifiedBuildSignature $manifestPath
    $planTimer = [System.Diagnostics.Stopwatch]::StartNew()
    try { $plan = New-SkillProjectionPlan $projectionCfg $packageHashContext }
    finally { $planTimer.Stop() }
    $reconciliation = New-SkillProfileReconciliationSignal $projectionCfg $manifestPath $plan
    $managedCacheHotPath = Test-SkillProjectionManagedCacheHotPath $packageHashContext
    $hashMetric = if ($managedCacheHotPath) { "projection_package_hash_cache_hit" } else { "projection_package_hash_full" }
    Log ("性能埋点：{0}" -f $hashMetric) "INFO" -NoHost -Data ([ordered]@{
            metric = $hashMetric
            duration_ms = [int]($packageHashContext.fingerprint_ms + $packageHashContext.full_hash_ms)
            success = $true
            cache_hits = [int]$packageHashContext.cache_hits
            cache_misses = [int]$packageHashContext.cache_misses
            full_hash_count = [int]$packageHashContext.full_hash_count
        })
    $planMetric = if ($managedCacheHotPath) { "projection_plan_cached" } else { "projection_plan_full" }
    Log ("性能埋点：{0}" -f $planMetric) "INFO" -NoHost -Data ([ordered]@{
            metric = $planMetric
            duration_ms = [int]$planTimer.ElapsedMilliseconds
            success = $true
        })
    if ([bool]$plan.enabled) {
        if (-not $nativeProjectionAuthoritative) {
            Need ([bool]$plan.budget_pass) ("技能描述预算超限：estimated={0}, limit={1}, profile={2}" -f [int]$plan.estimated_metadata_chars, [int]$plan.effective_budget_limit_chars, [string]$plan.active_profile)
            $oversizedProfiles = @($plan.profile_budgets | Where-Object { -not [bool]$_.budget_pass } | ForEach-Object { "{0}={1}/{2}" -f $_.profile, $_.estimated_metadata_chars, $_.budget_limit_chars })
            Need ([bool]$plan.all_profiles_budget_pass) ("技能 profile 描述预算超限：{0}" -f ($oversizedProfiles -join ", "))
        }
        Need (-not [bool]$plan.routing_report.blocking) "技能路由策略存在 enforce 模式阻断项"
    }

    $existing = if (Test-Path -LiteralPath $configPath -PathType Leaf) { Get-ContentUtf8 $configPath } else { "" }
    $desired = Invoke-WithMetric "projection_render" { Build-CodexSkillsProjectionToml $existing @($plan.disabled) } @{ command = "技能投影" } -NoHost
    $changed = -not [string]::Equals($existing, $desired, [System.StringComparison]::Ordinal)
    $backupPath = $null

    if (-not $DryRun) {
        $writeResult = Invoke-WithMetric "projection_write" {
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
                package_hash_cache_schema = Get-SkillProjectionPackageHashCacheSchemaVersion
                agent_build_signature = $verifiedBuildSignature
                projection_fingerprint = $projectionFingerprint
                source_revision = [string]$promotion.source_revision
                source_worktree_dirty = [bool]$promotion.source_worktree_dirty
                source_git_state = [string]$promotion.source_git_state
                promotion_mode = [string]$promotion.promotion_mode
                promoted_at = [string]$promotion.promoted_at
                provenance_status = [string]$promotion.provenance_status
                gate_receipt = [ordered]@{
                    status = [string]$promotion.gate_receipt_status
                    path = [string]$promotion.gate_receipt_path
                }
                enabled = [bool]$plan.enabled
                generated_at = (Get-Date).ToString("o")
                conflict_policy = [string]$plan.conflict_policy
                active_profile = [string]$plan.active_profile
                resident_names = @($plan.resident_names)
                source_count = @($projectionCfg.sources).Count
                skill_entry_count = @($plan.skills).Count
                unique_name_count = @($plan.unique_names).Count
                active_name_count = @($plan.active_names).Count
                duplicate_name_groups = [int]$plan.duplicate_name_groups
                profile_routed_name_count = [int]$plan.profile_routed_name_count
                unrouted_name_count = [int]$plan.unrouted_name_count
                profile_routed_names = @($plan.profile_routed_names)
                unrouted_names = @($plan.unrouted_names)
                disabled_path_count = @($plan.disabled).Count
                conflict_count = @($plan.conflicts).Count
                skill_metadata_chars = [int]$plan.skill_metadata_chars
                external_metadata_reserve_chars = [int]$plan.external_metadata_reserve_chars
                external_skill_count = [int]$plan.external_skill_count
                external_skill_metadata_chars = [int]$plan.external_skill_metadata_chars
                effective_external_metadata_chars = [int]$plan.effective_external_metadata_chars
                estimated_metadata_chars = [int]$plan.estimated_metadata_chars
                budget_limit_chars = [int]$plan.budget_limit_chars
                effective_budget_limit_chars = [int]$plan.effective_budget_limit_chars
                budget_pass = [bool]$plan.budget_pass
                all_profiles_budget_pass = [bool]$plan.all_profiles_budget_pass
                profile_budgets = @($plan.profile_budgets)
                external_skills = @($plan.external_skills)
                external_inventory_warnings = @($plan.external_inventory_warnings)
                routing_report = $plan.routing_report
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
                    notification = $nativeProjectionApply.notification
                } }
                managed_link_projection = if ($null -eq $linkProjection) { $null } else { [ordered]@{
                    managed_source_path = [string]$linkProjection.managed_source_path
                    user_skill_root = [string]$linkProjection.user_skill_root
                    managed_link_count = [int]$linkProjection.managed_link_count
                    stale_link_count = [int]$linkProjection.stale_link_count
                } }
            }
            Set-ContentUtf8 $manifestPath ($manifest | ConvertTo-Json -Depth 20)
            if ([string]$reconciliation.status -eq "host_refresh_needed") {
                try {
                    Set-ContentUtf8 ([string]$reconciliation.signal_path) ($reconciliation | ConvertTo-Json -Depth 8)
                    $reconciliation | Add-Member -NotePropertyName signal_updated -NotePropertyValue $true -Force
                }
                catch {
                    Log ("host refresh signal 写入失败，不阻断技能投影：{0}" -f $_.Exception.Message) "WARN"
                }
            }
            return [pscustomobject]@{ backup_path = if ($null -eq $writtenBackupPath) { "" } else { [string]$writtenBackupPath } }
        } @{ command = "技能投影"; changed = $changed } -NoHost
        $backupPath = [string]$writeResult.backup_path
    }

    return [pscustomobject]@{
        success = $true
        persisted = (-not $DryRun)
        changed = $changed
        config_path = $configPath
        manifest_path = $manifestPath
        backup_path = if ($null -eq $backupPath) { "" } else { [string]$backupPath }
        managed_link_projection = $linkProjection
        capability_catalog_projection = $catalogProjection
        native_projection = if (-not $nativeProjectionAuthoritative) { $null } else { [pscustomobject]@{ plan = $nativeProjectionPlan; apply = $nativeProjectionApply } }
        reconciliation = $reconciliation
        package_hash_cache = [pscustomobject]@{
            cache_valid = [bool]$packageHashContext.cache_valid
            cache_hits = [int]$packageHashContext.cache_hits
            cache_misses = [int]$packageHashContext.cache_misses
            full_hash_count = [int]$packageHashContext.full_hash_count
            fingerprint_ms = [int]$packageHashContext.fingerprint_ms
            full_hash_ms = [int]$packageHashContext.full_hash_ms
        }
        plan = $plan
    }
}

function Sync-CodexSkillProjection($projectionCfg, [string]$verifiedBuildSignature = "", $promotionContext = $null) {
    if ($DryRun) { return Invoke-CodexSkillProjectionSyncCore $projectionCfg $verifiedBuildSignature $promotionContext }

    $configRaw = if ($projectionCfg.PSObject.Properties.Match('codex_config_path').Count -gt 0) { [string]$projectionCfg.codex_config_path } else { '~/.codex/config.toml' }
    $manifestRaw = if ($projectionCfg.PSObject.Properties.Match('manifest_path').Count -gt 0) { [string]$projectionCfg.manifest_path } else { 'reports/skill-projection/current.json' }
    $transaction = New-CodexSkillProjectionTransaction $projectionCfg (Resolve-SkillProjectionPath $configRaw) (Resolve-SkillProjectionPath $manifestRaw)
    try {
        $result = Invoke-CodexSkillProjectionSyncCore $projectionCfg $verifiedBuildSignature $promotionContext $transaction
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

function Copy-SkillProjectionConfig($projectionCfg) {
    Need ($null -ne $projectionCfg) "skill_projection 配置为空"
    return (($projectionCfg | ConvertTo-Json -Depth 50) | ConvertFrom-Json)
}

function New-SkillProfileReconciliationPlan($projectionCfg, [string]$configSha256, $proposal = $null, [int]$maxChanges = 50) {
    return [pscustomobject][ordered]@{
        schema_version = 1
        command = "plan-skill-profile-reconciliation"
        decision_owner = "host_ai"
        semantic_routing_performed = $false
        status = "deprecated"
        pass = $false
        apply_allowed = $false
        writes_performed = $false
        current = $null
        actions = @()
        proposed = $null
        overlaps = @()
        finding_count = 1
        findings = @([pscustomobject][ordered]@{
            code = "profile_reconciliation_retired"
            message = "Profile reconciliation proposals are retired; use the read-only compatibility view and explicit versioned migration or receipt rollback."
            blocking = $true
            skill = ""
            profile = ""
        })
    }
}

function Sync-ConfiguredSkillProjection($cfg, [string]$verifiedBuildSignature = "", $promotionContext = $null) {
    if ($null -eq $cfg -or $cfg.PSObject.Properties.Match("skill_projection").Count -eq 0 -or $null -eq $cfg.skill_projection) {
        return [pscustomobject]@{ success = $true; persisted = $false; skipped = $true; plan = $null }
    }
    return (Sync-CodexSkillProjection $cfg.skill_projection $verifiedBuildSignature $promotionContext)
}
