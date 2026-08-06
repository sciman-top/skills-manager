function Get-EmptySkillRoutingReport {
    return [pscustomobject]([ordered]@{
            schema_version = 1
            enabled = $false
            mode = "observe"
            policy_path = ""
            group_count = 0
            active_group_count = 0
            finding_count = 0
            blocking = $false
            groups = @()
            findings = @()
        })
}

function Get-CodexEnabledPluginIds([string]$configPath) {
    if ([string]::IsNullOrWhiteSpace($configPath) -or -not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        return @()
    }

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
        if (-not [string]::IsNullOrWhiteSpace($id) -and $seen.Add($id)) {
            $ids.Add($id) | Out-Null
        }
    }
    return @($ids.ToArray() | Sort-Object)
}

function Add-SkillExternalInventoryWarning($warnings, [string]$code, [string]$subject, [string]$message) {
    $warnings.Add([pscustomobject]([ordered]@{
                code = $code
                subject = $subject
                message = $message
            })) | Out-Null
}

function Get-CodexExternalSkillInventory($projectionCfg) {
    $result = [ordered]@{
        enabled = $false
        config_path = ""
        plugin_cache_path = ""
        cache_selection = "newest_usable_version_by_mtime"
        enabled_plugin_ids = @()
        plugin_count = 0
        skill_count = 0
        metadata_chars = 0
        skills = @()
        warnings = @()
    }
    if ($null -eq $projectionCfg) {
        return [pscustomobject]$result
    }
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
            $skills.Add([pscustomobject]([ordered]@{
                        plugin_id = $pluginId
                        plugin_name = $pluginName
                        marketplace = $marketplace
                        cache_version = [string]$selectedVersion.Name
                        name = $name
                        qualified_name = ("{0}::{1}" -f $pluginId, $name)
                        description = $description
                        path = $skillFile.FullName
                    })) | Out-Null
        }
    }

    $metadataChars = 0
    foreach ($skill in @($skills.ToArray())) {
        $metadataChars += ([string]$skill.name).Length + ([string]$skill.description).Length
    }
    $result.plugin_count = $pluginIds.Count
    $result.skill_count = $skills.Count
    $result.metadata_chars = $metadataChars
    $result.skills = @($skills.ToArray() | Sort-Object plugin_id, name)
    $result.warnings = @($warnings.ToArray())
    return [pscustomobject]$result
}

function Get-SkillRoutingLocalInventory($cfg) {
    $items = New-Object System.Collections.Generic.List[object]
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($mapping in @($cfg.mappings)) {
        if ($null -eq $mapping -or -not (Should-SyncMappingToAgent $mapping)) { continue }
        $vendor = [string]$mapping.vendor
        $from = [string]$mapping.from
        if (-not $seen.Add(("{0}|{1}" -f $vendor, $from))) { continue }
        $localPath = Resolve-InstalledSkillLocalPath $cfg $mapping
        $skillFile = Join-Path $localPath 'SKILL.md'
        $meta = Get-SkillMetadataFromFile $skillFile
        $name = if ([string]::IsNullOrWhiteSpace([string]$meta.declared_name)) { [string]$mapping.to } else { [string]$meta.declared_name }
        $items.Add([pscustomobject]([ordered]@{
                    name = $name
                    description = [string]$meta.description
                    path = $skillFile
                    is_system = $false
                })) | Out-Null
    }
    foreach ($override in @(收集OverridesSkills)) {
        if ($null -eq $override) { continue }
        $from = [string]$override.from
        if ([string]::IsNullOrWhiteSpace($from) -or -not $seen.Add(("overrides|{0}" -f $from))) { continue }
        $skillFile = Join-Path ([string]$override.full) 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) { continue }
        $meta = Get-SkillMetadataFromFile $skillFile
        $name = if ([string]::IsNullOrWhiteSpace([string]$meta.declared_name)) { $from } else { [string]$meta.declared_name }
        $items.Add([pscustomobject]([ordered]@{
                    name = $name
                    description = [string]$meta.description
                    path = $skillFile
                    is_system = $false
                })) | Out-Null
    }
    return @($items.ToArray())
}

function Add-SkillRoutingDeclaredPathLeaf($names, [string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    $normalized = $path.Trim().Replace('\', '/').TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($normalized)) { return }
    $leaf = @($normalized -split '/')[-1].Trim()
    if (-not [string]::IsNullOrWhiteSpace($leaf)) {
        $names.Add($leaf) | Out-Null
    }
}

function Get-SkillRoutingDeclaredSourceNames($cfg, $materializedSkills) {
    $names = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($materializedSkills)) {
        if ($null -eq $entry) { continue }
        $path = Get-SkillRoutingEntryPath $entry
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $name = ([string]$entry.name).Trim()
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $names.Add($name) | Out-Null
        }
    }
    foreach ($import in @((Get-CfgObjectProperty $cfg 'imports'))) {
        if ($null -eq $import) { continue }
        Add-SkillRoutingDeclaredPathLeaf $names ([string](Get-CfgObjectProperty $import 'skill'))
    }
    foreach ($mapping in @((Get-CfgObjectProperty $cfg 'mappings'))) {
        if ($null -eq $mapping) { continue }
        Add-SkillRoutingDeclaredPathLeaf $names ([string](Get-CfgObjectProperty $mapping 'from'))
    }
    return @($names | Sort-Object)
}

function Get-SkillRoutingPolicy([string]$path) {
    Need (-not [string]::IsNullOrWhiteSpace($path)) 'skill routing policy path is empty'
    Need (Test-Path -LiteralPath $path -PathType Leaf) ("skill routing policy does not exist: {0}" -f $path)
    try {
        $policy = Get-ContentUtf8 $path | ConvertFrom-Json
    }
    catch {
        throw ("skill routing policy JSON parse failed: {0}" -f $_.Exception.Message)
    }
    Need ([int]$policy.schema_version -in @(1, 2)) 'skill routing policy only supports schema_version=1 or 2'
    $mode = ([string]$policy.mode).Trim().ToLowerInvariant()
    Need ($mode -eq 'observe' -or $mode -eq 'enforce') ("skill routing policy mode only supports observe/enforce: {0}" -f $mode)
    $policy.mode = $mode
    foreach ($field in @('trigger_rules', 'groups', 'conflicts')) {
        Need ($policy.PSObject.Properties.Match($field).Count -gt 0 -and (Assert-IsArray $policy.$field)) ("skill routing policy {0} must be an array" -f $field)
    }
    return $policy
}

function Get-SkillRoutingEntryPath($entry) {
    if ($null -eq $entry) { return '' }
    if ($entry.PSObject.Properties.Match('path').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$entry.path)) {
        return [string]$entry.path
    }
    if ($entry.PSObject.Properties.Match('local_path').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$entry.local_path)) {
        return (Join-Path ([string]$entry.local_path) 'SKILL.md')
    }
    return ''
}

function Add-SkillRoutingFinding($findings, [string]$code, [string]$severity, [string]$subject, [string]$message, [string]$resolution = '') {
    $findings.Add([pscustomobject]([ordered]@{
                code = $code
                severity = $severity
                subject = $subject
                message = $message
                resolution = $resolution
            })) | Out-Null
}

function New-SkillRoutingReport($projectionCfg, $canonicalSkills, $activeSkills, $externalSkills, $declaredSkillNames = $null) {
    $routingPolicyPath = if ($null -eq $projectionCfg) { '' } else { [string](Get-CfgObjectProperty $projectionCfg 'routing_policy_path') }
    if ([string]::IsNullOrWhiteSpace($routingPolicyPath)) {
        return Get-EmptySkillRoutingReport
    }
    $policyPath = Resolve-SkillProjectionPath $routingPolicyPath
    $policy = Get-SkillRoutingPolicy $policyPath
    $canonical = @($canonicalSkills)
    $active = @($activeSkills)
    $external = @($externalSkills)
    $canonicalNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $declaredNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $activeNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $externalNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $canonical) { $canonicalNames.Add(([string]$entry.name).Trim()) | Out-Null }
    $effectiveDeclaredNames = if ($null -eq $declaredSkillNames) { @($canonicalNames) } else { @($declaredSkillNames) }
    foreach ($name in $effectiveDeclaredNames) {
        $trimmedName = ([string]$name).Trim()
        if (-not [string]::IsNullOrWhiteSpace($trimmedName)) { $declaredNames.Add($trimmedName) | Out-Null }
    }
    foreach ($entry in $active) { $activeNames.Add(([string]$entry.name).Trim()) | Out-Null }
    foreach ($entry in $external) {
        $externalNames.Add(([string]$entry.qualified_name).Trim()) | Out-Null
        $externalNames.Add(([string]$entry.name).Trim()) | Out-Null
    }

    $findings = New-Object System.Collections.Generic.List[object]
    $groupReports = New-Object System.Collections.Generic.List[object]
    $groupIds = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $coveredLocalNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $allowedRoles = @('router', 'executor', 'validator', 'operator', 'workflow', 'reference')
    foreach ($group in @($policy.groups)) {
        Need ($null -ne $group) 'skill routing group cannot be null'
        $groupId = ([string]$group.id).Trim()
        Need (-not [string]::IsNullOrWhiteSpace($groupId)) 'skill routing group is missing id'
        Need ($groupIds.Add($groupId)) ("duplicate skill routing group id: {0}" -f $groupId)
        Need (-not [string]::IsNullOrWhiteSpace([string]$group.purpose)) ("skill routing group is missing purpose: {0}" -f $groupId)
        Need ($group.PSObject.Properties.Match('members').Count -gt 0 -and (Assert-IsArray $group.members)) ("skill routing group members must be an array: {0}" -f $groupId)

        $memberNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
        $memberRoles = @{}
        $activeMembers = New-Object System.Collections.Generic.List[string]
        foreach ($member in @($group.members)) {
            $name = ([string]$member.name).Trim()
            $role = ([string]$member.role).Trim().ToLowerInvariant()
            Need (-not [string]::IsNullOrWhiteSpace($name)) ("skill routing group member is missing name: {0}" -f $groupId)
            Need ($allowedRoles -contains $role) ("unsupported skill routing role {0}: {1}/{2}" -f $role, $groupId, $name)
            Need (-not [string]::IsNullOrWhiteSpace([string]$member.activation)) ("skill routing member is missing activation: {0}/{1}" -f $groupId, $name)
            Need ($memberNames.Add($name)) ("duplicate skill routing member: {0}/{1}" -f $groupId, $name)
            Need ($declaredNames.Contains($name)) ("skill routing member has no declared source: {0}/{1}" -f $groupId, $name)
            $memberRoles[$name] = $role
            $coveredLocalNames.Add($name) | Out-Null
            if ($activeNames.Contains($name)) { $activeMembers.Add($name) | Out-Null }
        }
        $router = ([string]$group.router).Trim()
        if (-not [string]::IsNullOrWhiteSpace($router)) {
            Need ($memberNames.Contains($router)) ("skill routing group router must also be a member: {0}/{1}" -f $groupId, $router)
            Need ([string]$memberRoles[$router] -eq 'router') ("skill routing group router member must use role=router: {0}/{1}" -f $groupId, $router)
        }

        $activeExternal = New-Object System.Collections.Generic.List[string]
        if ($group.PSObject.Properties.Match('external_members').Count -gt 0 -and $null -ne $group.external_members) {
            Need (Assert-IsArray $group.external_members) ("skill routing group external_members must be an array: {0}" -f $groupId)
            foreach ($member in @($group.external_members)) {
                $qualifiedName = ([string]$member.qualified_name).Trim()
                $role = ([string]$member.role).Trim().ToLowerInvariant()
                Need (-not [string]::IsNullOrWhiteSpace($qualifiedName)) ("external skill routing member is missing qualified_name: {0}" -f $groupId)
                Need ($allowedRoles -contains $role) ("unsupported external skill routing role {0}: {1}/{2}" -f $role, $groupId, $qualifiedName)
                Need (-not [string]::IsNullOrWhiteSpace([string]$member.activation)) ("external skill routing member is missing activation: {0}/{1}" -f $groupId, $qualifiedName)
                if ($externalNames.Contains($qualifiedName)) {
                    $activeExternal.Add($qualifiedName) | Out-Null
                }
                elseif (-not ($member.PSObject.Properties.Match('optional').Count -gt 0 -and [bool]$member.optional)) {
                    Add-SkillRoutingFinding $findings 'external_member_unavailable' 'warning' $qualifiedName ("Required external member for routing group '{0}' is unavailable." -f $groupId) 'Enable or install the declared plugin, or mark the member optional.'
                }
            }
        }

        $groupReports.Add([pscustomobject]([ordered]@{
                    id = $groupId
                    purpose = [string]$group.purpose
                    router = $router
                    router_active = (-not [string]::IsNullOrWhiteSpace($router) -and $activeNames.Contains($router))
                    active = ($activeMembers.Count -gt 0 -or $activeExternal.Count -gt 0)
                    active_local_members = @($activeMembers.ToArray())
                    active_external_members = @($activeExternal.ToArray())
                    selection_policy = [string]$group.selection_policy
                })) | Out-Null
    }

    $triggerRuleIds = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($rule in @($policy.trigger_rules)) {
        $ruleId = ([string]$rule.id).Trim()
        $severity = ([string]$rule.severity).Trim().ToLowerInvariant()
        Need (-not [string]::IsNullOrWhiteSpace($ruleId)) 'skill routing trigger rule is missing id'
        Need ($triggerRuleIds.Add($ruleId)) ("duplicate skill routing trigger rule id: {0}" -f $ruleId)
        Need ($severity -eq 'info' -or $severity -eq 'warning' -or $severity -eq 'error') ("unsupported trigger rule severity: {0}/{1}" -f $ruleId, $severity)
        Need (-not [string]::IsNullOrWhiteSpace([string]$rule.pattern)) ("skill routing trigger rule is missing pattern: {0}" -f $ruleId)
        try { $regex = [regex]::new([string]$rule.pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase, [TimeSpan]::FromSeconds(1)) }
        catch { throw ("invalid skill routing trigger regex {0}: {1}" -f $ruleId, $_.Exception.Message) }
        $scope = ([string]$rule.scan_scope).Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($scope)) { $scope = 'description' }
        Need ($scope -eq 'description' -or $scope -eq 'full') ("trigger rule scan_scope only supports description/full: {0}" -f $ruleId)
        foreach ($entry in $active) {
            $text = [string]$entry.description
            if ($scope -eq 'full') {
                $entryPath = Get-SkillRoutingEntryPath $entry
                if (-not [string]::IsNullOrWhiteSpace($entryPath) -and (Test-Path -LiteralPath $entryPath -PathType Leaf)) {
                    $text = Get-ContentUtf8 $entryPath
                }
            }
            if (-not $regex.IsMatch($text)) { continue }
            $name = [string]$entry.name
            Add-SkillRoutingFinding $findings 'strong_trigger_signal' $severity $name ("Active skill matches trigger rule '{0}'." -f $ruleId) ([string]$rule.resolution)
            if (-not $coveredLocalNames.Contains($name)) {
                Add-SkillRoutingFinding $findings 'unrouted_strong_trigger' 'warning' $name 'An active skill with a strong trigger is not covered by any routing group.' 'Add it to a routing group or narrow its trigger text.'
            }
        }
    }

    $conflictIds = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($conflict in @($policy.conflicts)) {
        $conflictId = ([string]$conflict.id).Trim()
        $severity = ([string]$conflict.severity).Trim().ToLowerInvariant()
        Need (-not [string]::IsNullOrWhiteSpace($conflictId)) 'skill routing conflict is missing id'
        Need ($conflictIds.Add($conflictId)) ("duplicate skill routing conflict id: {0}" -f $conflictId)
        Need ($conflict.PSObject.Properties.Match('members').Count -gt 0 -and (Assert-IsArray $conflict.members)) ("skill routing conflict members must be an array: {0}" -f $conflictId)
        Need ($severity -eq 'warning' -or $severity -eq 'error') ("skill routing conflict severity only supports warning/error: {0}" -f $conflictId)
        Need (-not [string]::IsNullOrWhiteSpace([string]$conflict.resolution)) ("skill routing conflict is missing resolution: {0}" -f $conflictId)
        $members = @($conflict.members | ForEach-Object { ([string]$_).Trim() })
        Need ($members.Count -ge 2) ("skill routing conflict requires at least two members: {0}" -f $conflictId)
        foreach ($name in $members) { Need ($declaredNames.Contains($name)) ("skill routing conflict member has no declared source: {0}/{1}" -f $conflictId, $name) }
        $coactive = @($members | Where-Object { $activeNames.Contains($_) })
        if ($coactive.Count -eq $members.Count) {
            Add-SkillRoutingFinding $findings 'coactive_contract_conflict' $severity $conflictId ("Potentially conflicting skills are active together: {0}." -f ($members -join ', ')) ([string]$conflict.resolution)
        }
    }

    $findingItems = @($findings.ToArray())
    $blocking = $policy.mode -eq 'enforce' -and @($findingItems | Where-Object severity -eq 'error').Count -gt 0
    return [pscustomobject]([ordered]@{
            schema_version = 1
            enabled = $true
            mode = [string]$policy.mode
            policy_path = $policyPath
            group_count = $groupReports.Count
            active_group_count = @($groupReports.ToArray() | Where-Object active).Count
            finding_count = $findingItems.Count
            blocking = $blocking
            groups = @($groupReports.ToArray())
            findings = @($findingItems | Sort-Object severity, code, subject)
        })
}
