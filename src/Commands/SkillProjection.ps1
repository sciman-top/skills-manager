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
            status = if ($changed) { "reconciliation_needed" } else { "not_needed" }
            reason = if ($changed) { "canonical_inventory_changed" } else { "canonical_inventory_unchanged" }
            added_names = $added
            removed_names = $removed
            metadata_changed_names = $metadataChanged
            before_fingerprint = [string]$before.fingerprint
            after_fingerprint = [string]$after.fingerprint
            config_sha256 = if (Test-Path -LiteralPath $skillsConfigPath -PathType Leaf) { Get-FileContentHash $skillsConfigPath } else { "" }
            next_action = if ($changed) { "host_ai_profile_reconciliation" } else { "none" }
            advisor_command = if ($changed) { "skills.ps1 技能配置 调和" } else { "" }
            active_profile = [string]$currentPlan.active_profile
            profile_names = @($currentPlan.profile_budgets | ForEach-Object { [string]$_.profile } | Sort-Object -Unique)
            unrouted_names = @($currentPlan.unrouted_names)
            writes_profile_config = $false
            signal_path = $signalPath
            signal_updated = $false
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
    $desired = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($dir in @(Get-ChildItem -LiteralPath $managedRoot -Directory -Force | Where-Object Name -ne ".system" | Sort-Object Name)) {
        if ($excluded.Contains($dir.Name)) { continue }
        $linkPath = Join-Path $userRoot $dir.Name
        New-Junction $linkPath $dir.FullName -QuietIfUnchanged
        $desired.Add($dir.Name) | Out-Null
    }

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
        return [pscustomobject]@{ schema_version = 2; enabled = $false; skills = @(); canonical = @(); active = @(); disabled = @(); conflicts = @(); unique_names = @(); active_names = @(); duplicate_name_groups = 0; profile_routed_name_count = 0; unrouted_name_count = 0; profile_routed_names = @(); unrouted_names = @(); external_skills = @(); external_inventory_warnings = @(); routing_report = (Get-EmptySkillRoutingReport) }
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
    $routingReport = New-SkillRoutingReport $projectionCfg @($canonical.ToArray()) @($active.ToArray()) @($externalInventory.skills)

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

function Get-SkillProjectionPromotionRecord([string]$manifestPath, $promotionContext = $null) {
    if ($null -ne $promotionContext) {
        return [pscustomobject]@{
            source_revision = [string]$promotionContext.source_revision
            source_worktree_dirty = [bool]$promotionContext.source_worktree_dirty
            source_git_state = [string]$promotionContext.source_git_state
            promotion_mode = [string]$promotionContext.promotion_mode
            promoted_at = (Get-Date).ToString("o")
            gate_receipt_status = [string]$promotionContext.gate_receipt_status
            gate_receipt_path = [string]$promotionContext.gate_receipt_path
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($manifestPath) -and (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        try {
            $existingManifest = Get-ContentUtf8 $manifestPath | ConvertFrom-Json
            if ($existingManifest.PSObject.Properties.Match("promotion_mode").Count -gt 0) {
                $existingGateReceipt = if ($existingManifest.PSObject.Properties.Match("gate_receipt").Count -gt 0) { $existingManifest.gate_receipt } else { $null }
                return [pscustomobject]@{
                    source_revision = [string]$existingManifest.source_revision
                    source_worktree_dirty = [bool]$existingManifest.source_worktree_dirty
                    source_git_state = [string]$existingManifest.source_git_state
                    promotion_mode = [string]$existingManifest.promotion_mode
                    promoted_at = [string]$existingManifest.promoted_at
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
        gate_receipt_status = "not_provided"
        gate_receipt_path = ""
    }
}

function Sync-CodexSkillProjection($projectionCfg, [string]$verifiedBuildSignature = "", $promotionContext = $null) {
    $configRaw = if ($projectionCfg.PSObject.Properties.Match("codex_config_path").Count -gt 0) { [string]$projectionCfg.codex_config_path } else { "~/.codex/config.toml" }
    $manifestRaw = if ($projectionCfg.PSObject.Properties.Match("manifest_path").Count -gt 0) { [string]$projectionCfg.manifest_path } else { "reports/skill-projection/current.json" }
    $configPath = Resolve-SkillProjectionPath $configRaw
    $manifestPath = Resolve-SkillProjectionPath $manifestRaw
    $catalogProjection = Invoke-WithMetric 'projection_capability_catalog' { Sync-CapabilityRouterCatalog $projectionCfg } @{ command = '技能投影' } -NoHost
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
        Need ([bool]$plan.budget_pass) ("技能描述预算超限：estimated={0}, limit={1}, profile={2}" -f [int]$plan.estimated_metadata_chars, [int]$plan.effective_budget_limit_chars, [string]$plan.active_profile)
        $oversizedProfiles = @($plan.profile_budgets | Where-Object { -not [bool]$_.budget_pass } | ForEach-Object { "{0}={1}/{2}" -f $_.profile, $_.estimated_metadata_chars, $_.budget_limit_chars })
        Need ([bool]$plan.all_profiles_budget_pass) ("技能 profile 描述预算超限：{0}" -f ($oversizedProfiles -join ", "))
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
                Set-ContentUtf8 $configPath $desired
            }
            $promotion = Get-SkillProjectionPromotionRecord $manifestPath $promotionContext
            $manifest = [ordered]@{
                schema_version = 2
                package_hash_cache_schema = Get-SkillProjectionPackageHashCacheSchemaVersion
                agent_build_signature = $verifiedBuildSignature
                source_revision = [string]$promotion.source_revision
                source_worktree_dirty = [bool]$promotion.source_worktree_dirty
                source_git_state = [string]$promotion.source_git_state
                promotion_mode = [string]$promotion.promotion_mode
                promoted_at = [string]$promotion.promoted_at
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
            }
            Set-ContentUtf8 $manifestPath ($manifest | ConvertTo-Json -Depth 20)
            if ([string]$reconciliation.status -eq "reconciliation_needed") {
                try {
                    Set-ContentUtf8 ([string]$reconciliation.signal_path) ($reconciliation | ConvertTo-Json -Depth 8)
                    $reconciliation.signal_updated = $true
                }
                catch {
                    Log ("profile reconciliation signal 写入失败，不阻断技能投影：{0}" -f $_.Exception.Message) "WARN"
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

function Copy-SkillProjectionConfig($projectionCfg) {
    Need ($null -ne $projectionCfg) "skill_projection 配置为空"
    return (($projectionCfg | ConvertTo-Json -Depth 50) | ConvertFrom-Json)
}

function Add-SkillProfileReconciliationFinding($findings, [string]$code, [string]$message, [bool]$blocking, [string]$skill = "", [string]$profile = "") {
    $findings.Add([pscustomobject]([ordered]@{
                code = $code
                message = $message
                blocking = $blocking
                skill = $skill
                profile = $profile
            })) | Out-Null
}

function New-SkillProfileReconciliationPlan($projectionCfg, [string]$configSha256, $proposal = $null, [int]$maxChanges = 50) {
    Need ($null -ne $projectionCfg) "skill_projection 配置为空"
    Need (Test-SkillProjectionSha256 $configSha256) "configSha256 必须是 SHA-256"
    Need ($maxChanges -gt 0 -and $maxChanges -le 200) "maxChanges 必须位于 1..200"

    $findings = New-Object System.Collections.Generic.List[object]
    $actions = New-Object System.Collections.Generic.List[object]
    $inventoryCfg = Copy-SkillProjectionConfig $projectionCfg
    foreach ($propertyName in @("profiles", "active_profile", "resident_names", "aliases")) {
        if ($inventoryCfg.PSObject.Properties.Match($propertyName).Count -gt 0) {
            $inventoryCfg.PSObject.Properties.Remove($propertyName)
        }
    }
    $inventory = New-SkillProjectionPlan $inventoryCfg
    $canonicalByName = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($inventory.canonical)) { $canonicalByName[[string]$entry.name] = $entry }

    $profileByName = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($projectionCfg.PSObject.Properties.Match("profiles").Count -eq 0 -or $null -eq $projectionCfg.profiles) {
        Add-SkillProfileReconciliationFinding $findings "profiles_missing" "skill_projection.profiles is required." $true
    }
    else {
        foreach ($property in @($projectionCfg.profiles.PSObject.Properties)) { $profileByName[[string]$property.Name] = $property }
    }

    $residentNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @($projectionCfg.resident_names)) { if (-not [string]::IsNullOrWhiteSpace([string]$name)) { $residentNames.Add([string]$name) | Out-Null } }
    $aliasNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($alias in @($projectionCfg.aliases)) { if ($null -ne $alias -and -not [string]::IsNullOrWhiteSpace([string]$alias.name)) { $aliasNames.Add([string]$alias.name) | Out-Null } }

    $membership = @{}
    foreach ($property in @($projectionCfg.profiles.PSObject.Properties)) {
        $profileName = [string]$property.Name
        foreach ($rawName in @($property.Value.enabled_names)) {
            $skillName = ([string]$rawName).Trim()
            if (-not $canonicalByName.ContainsKey($skillName)) {
                Add-SkillProfileReconciliationFinding $findings "stale_profile_reference" ("Profile '{0}' references missing skill '{1}'." -f $profileName, $skillName) $true $skillName $profileName
                continue
            }
            $key = $skillName.ToLowerInvariant()
            if (-not $membership.ContainsKey($key)) { $membership[$key] = New-Object System.Collections.Generic.List[string] }
            $membership[$key].Add($profileName) | Out-Null
        }
    }
    foreach ($name in @($residentNames)) {
        if (-not $canonicalByName.ContainsKey($name)) {
            Add-SkillProfileReconciliationFinding $findings "stale_resident_reference" ("resident_names references missing skill '{0}'." -f $name) $true $name
        }
    }

    $overlaps = New-Object System.Collections.Generic.List[object]
    foreach ($key in @($membership.Keys | Sort-Object)) {
        $profiles = @($membership[$key].ToArray() | Sort-Object -Unique)
        if ($profiles.Count -ge 3) {
            $entry = $canonicalByName[$key]
            $overlaps.Add([pscustomobject]@{ skill = [string]$entry.name; profiles = $profiles; profile_count = $profiles.Count }) | Out-Null
        }
    }

    $currentPlan = $null
    if (@($findings | Where-Object blocking).Count -eq 0) {
        try { $currentPlan = New-SkillProjectionPlan $projectionCfg }
        catch { Add-SkillProfileReconciliationFinding $findings "current_projection_invalid" $_.Exception.Message $true }
    }

    $proposedPlan = $null
    if ($null -ne $proposal) {
        if ($proposal.PSObject.Properties.Match("schema_version").Count -eq 0 -or [int]$proposal.schema_version -ne 1) {
            Add-SkillProfileReconciliationFinding $findings "proposal_schema_invalid" "Proposal must use schema_version=1." $true
        }
        if ([string]$proposal.decision_owner -ne "host_ai") {
            Add-SkillProfileReconciliationFinding $findings "proposal_owner_invalid" "Proposal decision_owner must be host_ai." $true
        }
        if (-not [string]::Equals([string]$proposal.base_config_sha256, $configSha256, [System.StringComparison]::OrdinalIgnoreCase)) {
            Add-SkillProfileReconciliationFinding $findings "stale_config_hash" "Proposal base_config_sha256 does not match the current skills.json." $true
        }
        $changes = @($proposal.changes)
        if ($proposal.PSObject.Properties.Match("changes").Count -eq 0 -or $changes.Count -eq 0) {
            Add-SkillProfileReconciliationFinding $findings "proposal_changes_missing" "Proposal changes must be a non-empty array." $true
        }
        elseif ($changes.Count -gt $maxChanges) {
            Add-SkillProfileReconciliationFinding $findings "proposal_change_limit_exceeded" ("Proposal has {0} changes; limit is {1}." -f $changes.Count, $maxChanges) $true
        }

        $proposedCfg = Copy-SkillProjectionConfig $projectionCfg
        $seenSkills = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($change in $changes) {
            if ($null -eq $change) { Add-SkillProfileReconciliationFinding $findings "proposal_change_invalid" "Proposal changes cannot contain null." $true; continue }
            $skillName = ([string]$change.skill).Trim()
            if ([string]::IsNullOrWhiteSpace($skillName) -or -not $canonicalByName.ContainsKey($skillName)) {
                Add-SkillProfileReconciliationFinding $findings "unknown_skill" ("Unknown skill '{0}'." -f $skillName) $true $skillName
                continue
            }
            $canonicalEntry = $canonicalByName[$skillName]
            $canonicalName = [string]$canonicalEntry.name
            if (-not $seenSkills.Add($canonicalName)) {
                Add-SkillProfileReconciliationFinding $findings "duplicate_skill_change" ("Skill '{0}' appears more than once in proposal changes." -f $canonicalName) $true $canonicalName
                continue
            }
            if ([bool]$canonicalEntry.is_system -or $residentNames.Contains($canonicalName) -or $aliasNames.Contains($canonicalName)) {
                Add-SkillProfileReconciliationFinding $findings "protected_skill_mutation" ("System, resident, and alias skills cannot be reconciled through profiles: '{0}'." -f $canonicalName) $true $canonicalName
                continue
            }
            if ([string]::IsNullOrWhiteSpace([string]$change.reason)) {
                Add-SkillProfileReconciliationFinding $findings "reason_missing" ("Skill '{0}' requires a non-empty host rationale." -f $canonicalName) $true $canonicalName
                continue
            }
            $addNames = @($change.add_profiles | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
            $removeNames = @($change.remove_profiles | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
            if ($addNames.Count -eq 0 -and $removeNames.Count -eq 0) {
                Add-SkillProfileReconciliationFinding $findings "empty_profile_change" ("Skill '{0}' must add or remove at least one profile." -f $canonicalName) $true $canonicalName
                continue
            }
            foreach ($profileName in @($addNames | Where-Object { $_ -in $removeNames })) {
                Add-SkillProfileReconciliationFinding $findings "profile_operation_conflict" ("Profile '{0}' is both added and removed for '{1}'." -f $profileName, $canonicalName) $true $canonicalName $profileName
            }
            foreach ($operation in @(
                    @($addNames | ForEach-Object { [pscustomobject]@{ name = $_; operation = "add" } }) +
                    @($removeNames | ForEach-Object { [pscustomobject]@{ name = $_; operation = "remove" } })
                )) {
                $requestedProfile = [string]$operation.name
                if (-not $profileByName.ContainsKey($requestedProfile)) {
                    Add-SkillProfileReconciliationFinding $findings "unknown_profile" ("Unknown profile '{0}'." -f $requestedProfile) $true $canonicalName $requestedProfile
                    continue
                }
                $profileName = [string]$profileByName[$requestedProfile].Name
                $proposedProfile = $proposedCfg.profiles.PSObject.Properties[$profileName].Value
                $before = @($proposedProfile.enabled_names | ForEach-Object { [string]$_ })
                $contains = @($before | Where-Object { [string]::Equals($_, $canonicalName, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
                if ($operation.operation -eq "add" -and $contains) {
                    Add-SkillProfileReconciliationFinding $findings "add_existing_membership" ("Skill '{0}' already belongs to profile '{1}'." -f $canonicalName, $profileName) $true $canonicalName $profileName
                    continue
                }
                if ($operation.operation -eq "remove" -and -not $contains) {
                    Add-SkillProfileReconciliationFinding $findings "remove_missing_membership" ("Skill '{0}' does not belong to profile '{1}'." -f $canonicalName, $profileName) $true $canonicalName $profileName
                    continue
                }
                $after = if ($operation.operation -eq "add") { @($before + $canonicalName | Sort-Object -Unique) } else { @($before | Where-Object { -not [string]::Equals($_, $canonicalName, [System.StringComparison]::OrdinalIgnoreCase) }) }
                $proposedProfile.enabled_names = @($after)
                $actions.Add([pscustomobject]([ordered]@{
                            operation = [string]$operation.operation
                            skill = $canonicalName
                            profile = $profileName
                            path = ("skill_projection.profiles.{0}.enabled_names" -f $profileName)
                            before = @($before)
                            after = @($after)
                            reason = [string]$change.reason
                        })) | Out-Null
            }
        }

        if (@($findings | Where-Object blocking).Count -eq 0) {
            try {
                Need ([string]::Equals([string]$proposedCfg.active_profile, [string]$projectionCfg.active_profile, [System.StringComparison]::Ordinal)) "active_profile changed during reconciliation"
                $proposedPlan = New-SkillProjectionPlan $proposedCfg
                if (-not [bool]$proposedPlan.all_profiles_budget_pass) {
                    $oversized = @($proposedPlan.profile_budgets | Where-Object { -not [bool]$_.budget_pass } | ForEach-Object { "{0}={1}/{2}" -f $_.profile, $_.estimated_metadata_chars, $_.budget_limit_chars })
                    Add-SkillProfileReconciliationFinding $findings "proposed_budget_exceeded" ("Proposed profile metadata exceeds budget: {0}." -f ($oversized -join ", ")) $true
                }
                if ([bool]$proposedPlan.routing_report.blocking) {
                    Add-SkillProfileReconciliationFinding $findings "proposed_routing_blocked" "Proposed projection violates an enforce-mode routing policy." $true
                }
            }
            catch { Add-SkillProfileReconciliationFinding $findings "proposed_projection_invalid" $_.Exception.Message $true }
        }
    }

    if ($null -eq $proposal -and $null -ne $currentPlan) {
        if (-not [bool]$currentPlan.all_profiles_budget_pass) { Add-SkillProfileReconciliationFinding $findings "current_budget_exceeded" "One or more current profiles exceed the metadata budget." $true }
        if ([bool]$currentPlan.routing_report.blocking) { Add-SkillProfileReconciliationFinding $findings "current_routing_blocked" "Current projection violates an enforce-mode routing policy." $true }
    }

    $currentSummary = if ($null -eq $currentPlan) { $null } else { [pscustomobject]([ordered]@{
                active_profile = [string]$currentPlan.active_profile
                unrouted_names = @($currentPlan.unrouted_names)
                profile_budgets = @($currentPlan.profile_budgets)
                all_profiles_budget_pass = [bool]$currentPlan.all_profiles_budget_pass
            }) }
    $proposedSummary = if ($null -eq $proposedPlan) { $null } else { [pscustomobject]([ordered]@{
                active_profile = [string]$proposedPlan.active_profile
                unrouted_names = @($proposedPlan.unrouted_names)
                profile_budgets = @($proposedPlan.profile_budgets)
                all_profiles_budget_pass = [bool]$proposedPlan.all_profiles_budget_pass
            }) }
    $hostHandoff = [pscustomobject]([ordered]@{
            required = ($null -eq $proposal)
            semantic_owner = "host_ai"
            next_action = if ($null -eq $proposal) { "inspect_full_skill_descriptions_and_create_minimum_proposal" } elseif (@($findings | Where-Object blocking).Count -eq 0) { "proposal_validated" } else { "revise_proposal_from_findings" }
            base_config_sha256 = $configSha256.ToLowerInvariant()
            profile_names = @($profileByName.Keys | Sort-Object)
            candidate_names = if ($null -eq $currentSummary) { @() } else { @($currentSummary.unrouted_names) }
            constraints = @("no_lexical_router", "non_active_profile_canary_only", "fresh_task_replay_required", "receipt_and_rollback_required")
        })
    return [pscustomobject]([ordered]@{
            schema_version = 1
            command = "plan-skill-profile-reconciliation"
            decision_owner = "host_ai"
            semantic_routing_performed = $false
            pass = (@($findings | Where-Object blocking).Count -eq 0)
            apply_allowed = $false
            writes_performed = $false
            config_sha256 = $configSha256.ToLowerInvariant()
            proposal_supplied = ($null -ne $proposal)
            current = $currentSummary
            actions = @($actions.ToArray())
            proposed = $proposedSummary
            overlaps = @($overlaps.ToArray())
            host_handoff = $hostHandoff
            finding_count = $findings.Count
            findings = @($findings.ToArray())
        })
}

function Read-SkillProfileReconciliationProposal([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    $full = if ([System.IO.Path]::IsPathRooted($path)) { [System.IO.Path]::GetFullPath($path) } else { [System.IO.Path]::GetFullPath((Join-Path $Root $path)) }
    Need (Test-Path -LiteralPath $full -PathType Leaf) ("Proposal file does not exist: {0}" -f $full)
    try { return (Get-ContentUtf8 $full | ConvertFrom-Json) }
    catch { throw ("Proposal JSON is invalid: {0}" -f $_.Exception.Message) }
}

function Invoke-SkillProfileCommand([string[]]$tokens) {
    $cfg = LoadCfg
    Need ($cfg.PSObject.Properties.Match("skill_projection").Count -gt 0 -and $null -ne $cfg.skill_projection) "未配置 skill_projection"
    $projection = $cfg.skill_projection
    Need ($projection.PSObject.Properties.Match("profiles").Count -gt 0 -and $null -ne $projection.profiles) "未配置技能 profiles"
    $action = if ($null -eq $tokens -or $tokens.Count -eq 0) { "列表" } else { ([string]$tokens[0]).Trim().ToLowerInvariant() }
    if ($action -in @("列表", "list")) {
        foreach ($property in @($projection.profiles.PSObject.Properties | Sort-Object Name)) {
            $marker = if ([string]::Equals($property.Name, [string]$projection.active_profile, [System.StringComparison]::OrdinalIgnoreCase)) { "*" } else { " " }
            Write-Host ("{0} {1} ({2} skills)" -f $marker, $property.Name, @($property.Value.enabled_names).Count)
        }
        return
    }
    if ($action -in @("调和", "reconcile")) {
        Need ($tokens.Count -le 2) "技能配置 调和/reconcile 最多接受一个 proposal JSON 路径"
        $proposal = if ($tokens.Count -eq 2) { Read-SkillProfileReconciliationProposal ([string]$tokens[1]) } else { $null }
        $result = New-SkillProfileReconciliationPlan $projection (Get-FileContentHash $CfgPath) $proposal
        Write-Output ($result | ConvertTo-Json -Depth 20)
        if (-not [bool]$result.pass) { exit 2 }
        return
    }
    Need ($action -in @("使用", "use")) ("技能配置仅支持 列表/list、调和/reconcile 或 使用/use：{0}" -f $action)
    Need ($tokens.Count -ge 2) "技能配置 使用 缺少 profile 名称"
    $name = ([string]$tokens[1]).Trim()
    $profileProperty = @($projection.profiles.PSObject.Properties | Where-Object { [string]::Equals($_.Name, $name, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    Need ($profileProperty.Count -eq 1) ("技能 profile 不存在：{0}" -f $name)
    $projection.active_profile = [string]$profileProperty[0].Name
    $plan = New-SkillProjectionPlan $projection
    Need ([bool]$plan.budget_pass) ("技能 profile 超出描述预算：{0} ({1}/{2})" -f $name, $plan.estimated_metadata_chars, $plan.effective_budget_limit_chars)
    $raw = Get-ContentUtf8 $CfgPath
    SaveCfgSafe $cfg $raw
    $result = Sync-CodexSkillProjection $projection
    Write-Host ("已使用技能 profile：{0}；active={1}, metadata={2}/{3}, persisted={4}" -f $name, @($result.plan.active).Count, $result.plan.estimated_metadata_chars, $result.plan.effective_budget_limit_chars, [bool]$result.persisted)
    if ([bool]$result.reconciliation.signal_updated) {
        Write-Host ("检测到 canonical skill inventory 变化；profile reconciliation signal：{0}" -f [string]$result.reconciliation.signal_path) -ForegroundColor Yellow
    }
}

function Sync-ConfiguredSkillProjection($cfg, [string]$verifiedBuildSignature = "", $promotionContext = $null) {
    if ($null -eq $cfg -or $cfg.PSObject.Properties.Match("skill_projection").Count -eq 0 -or $null -eq $cfg.skill_projection) {
        return [pscustomobject]@{ success = $true; persisted = $false; skipped = $true; plan = $null }
    }
    return (Sync-CodexSkillProjection $cfg.skill_projection $verifiedBuildSignature $promotionContext)
}
