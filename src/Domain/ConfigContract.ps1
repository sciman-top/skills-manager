function Assert-IsArray($value) {
    return ($value -is [System.Collections.IList]) -and -not ($value -is [string])
}
function Test-CfgObjectProperty($obj, [string]$name) {
    if ($null -eq $obj) { return $false }
    if ($obj -is [System.Collections.IDictionary] -or
        $obj -is [System.Collections.Specialized.OrderedDictionary] -or
        $obj -is [System.Collections.Specialized.IOrderedDictionary]) {
        foreach ($key in @($obj.Keys)) {
            if ([string]::Equals([string]$key, $name, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
        return $false
    }
    return ($obj.PSObject.Properties.Match($name).Count -gt 0)
}
function Test-CfgArrayProperty($obj, [string]$name) {
    if ($null -eq $obj) { return $false }
    if ($obj -is [System.Collections.IDictionary] -or
        $obj -is [System.Collections.Specialized.OrderedDictionary] -or
        $obj -is [System.Collections.Specialized.IOrderedDictionary]) {
        foreach ($key in @($obj.Keys)) {
            if ([string]::Equals([string]$key, $name, [System.StringComparison]::OrdinalIgnoreCase)) {
                return (Assert-IsArray $obj[$key])
            }
        }
        return $false
    }
    $property = @($obj.PSObject.Properties | Where-Object { [string]::Equals($_.Name, $name, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    if ($property.Count -ne 1) { return $false }
    return (Assert-IsArray $property[0].Value)
}
function Get-CfgObjectProperty($obj, [string]$name) {
    if ($null -eq $obj) { return $null }
    if ($obj -is [System.Collections.IDictionary] -or
        $obj -is [System.Collections.Specialized.OrderedDictionary] -or
        $obj -is [System.Collections.Specialized.IOrderedDictionary]) {
        if ($obj.Contains($name)) {
            $value = $obj[$name]
            if (Assert-IsArray $value) { Write-Output -NoEnumerate $value } else { return $value }
            return
        }
        foreach ($key in @($obj.Keys)) {
            if ([string]::Equals([string]$key, $name, [System.StringComparison]::OrdinalIgnoreCase)) {
                $value = $obj[$key]
                if (Assert-IsArray $value) { Write-Output -NoEnumerate $value } else { return $value }
                return
            }
        }
        return $null
    }
    if ($obj.PSObject.Properties.Match($name).Count -eq 0) { return $null }
    $value = $obj.$name
    if (Assert-IsArray $value) { Write-Output -NoEnumerate $value } else { return $value }
}
function New-CfgVendorNameSet($vendors = @()) {
    $set = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $set.Add("manual") | Out-Null
    $set.Add("overrides") | Out-Null
    foreach ($v in @($vendors)) {
        if ($null -eq $v) { continue }
        $name = if ($v -is [string]) { [string]$v } else { [string](Get-CfgObjectProperty $v "name") }
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $set.Add($name) | Out-Null
    }
    return $set
}
function New-CfgMcpServerNameSet($servers = @()) {
    $set = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($server in @($servers)) {
        if ($null -eq $server) { continue }
        $name = if ($server -is [string]) { [string]$server } else { [string](Get-CfgObjectProperty $server "name") }
        if (-not [string]::IsNullOrWhiteSpace($name)) { $set.Add($name.Trim()) | Out-Null }
    }
    return $set
}
function Get-CfgArrayField($cfg, [string]$name, [bool]$required, [System.Collections.Generic.List[string]]$errors) {
    $value = Get-CfgObjectProperty $cfg $name
    if ($null -eq $value) {
        if ($required) { $errors.Add(("skills.json 缺少 {0}" -f $name)) | Out-Null }
        return @()
    }
    if (Assert-IsArray $value) { return @($value) }
    if ($value -is [hashtable] -or $value -is [pscustomobject]) { return @($value) }
    $errors.Add(("skills.json 的 {0} 必须是数组" -f $name)) | Out-Null
    return @()
}
$script:SkillsConfigSchemaVersion = 3
function Test-CfgIntegerValue($value) {
    return ($value -is [byte] -or $value -is [sbyte] -or
        $value -is [int16] -or $value -is [uint16] -or
        $value -is [int32] -or $value -is [uint32] -or
        $value -is [int64] -or $value -is [uint64])
}
function Get-CfgSchemaVersionInfo($cfg) {
    $errors = New-Object System.Collections.Generic.List[string]
    $observations = New-Object System.Collections.Generic.List[object]
    $declared = $false
    $version = 1

    if ($null -ne $cfg -and (Test-CfgObjectProperty $cfg "schema_version")) {
        $declared = $true
        $rawVersion = Get-CfgObjectProperty $cfg "schema_version"
        if (-not (Test-CfgIntegerValue $rawVersion)) {
            $errors.Add("schema_version 必须是整数") | Out-Null
            $version = $null
        }
        else {
            $version = [int64]$rawVersion
            $allowedVersions = @(1, 2, $script:SkillsConfigSchemaVersion) | Sort-Object -Unique
            if ($version -notin $allowedVersions) {
                $errors.Add(("不支持的 schema_version；当前支持 {0}" -f ($allowedVersions -join '/'))) | Out-Null
            }
        }
    }
    else {
        $observations.Add([pscustomobject]@{
            code = "legacy_schema_version_missing"
            path = "$.schema_version"
            message = "Missing schema_version is read as legacy v1; add schema_version only through an explicit migration."
        }) | Out-Null
    }

    return [pscustomobject]@{
        current_version = $script:SkillsConfigSchemaVersion
        effective_version = $version
        declared = $declared
        source = if ($declared) { "declared" } else { "legacy_default" }
        errors = @($errors.ToArray())
        observations = @($observations.ToArray())
    }
}
function Get-CfgVersionedContractReport($cfg) {
    $versionInfo = Get-CfgSchemaVersionInfo $cfg
    $errors = New-Object System.Collections.Generic.List[string]
    foreach ($errorText in @($versionInfo.errors)) { $errors.Add([string]$errorText) | Out-Null }

    if ($versionInfo.declared -and $versionInfo.errors.Count -eq 0) {
        if ([int]$versionInfo.effective_version -eq 1) {
            $versionInfo.observations += [pscustomobject]@{
                code = 'legacy_schema_v1_deprecated'
                path = '$.schema_version'
                message = 'Schema v1 remains readable for migration only; new repository configuration must use schema v3.'
            }
        }
        elseif ([int]$versionInfo.effective_version -eq 2) {
            $versionInfo.observations += [pscustomobject]@{
                code = 'schema_v2_observe'
                path = '$.schema_version'
                message = 'Schema v2 remains readable for migration only; new repository configuration must use schema v3.'
            }
        }
        foreach ($fieldName in @("vendors", "targets", "mappings", "imports", "mcp_servers", "mcp_targets")) {
            if ((Test-CfgObjectProperty $cfg $fieldName) -and -not (Assert-IsArray (Get-CfgObjectProperty $cfg $fieldName))) {
                $errors.Add(("schema v{0} 要求 {1} 为数组" -f $versionInfo.effective_version, $fieldName)) | Out-Null
            }
        }
        if ((Test-CfgObjectProperty $cfg "update_force") -and (Get-CfgObjectProperty $cfg "update_force") -isnot [bool]) {
            $errors.Add(("schema v{0} 要求 update_force 为布尔值" -f $versionInfo.effective_version)) | Out-Null
        }
        if ((Test-CfgObjectProperty $cfg "sync_mode") -and (Get-CfgObjectProperty $cfg "sync_mode") -isnot [string]) {
            $errors.Add(("schema v{0} 要求 sync_mode 为字符串" -f $versionInfo.effective_version)) | Out-Null
        }
        foreach ($fieldName in @("skill_projection", "mcp_profiles")) {
            $fieldValue = Get-CfgObjectProperty $cfg $fieldName
            if ($null -ne $fieldValue -and $fieldValue -isnot [pscustomobject] -and $fieldValue -isnot [System.Collections.IDictionary]) {
                $errors.Add(("schema v{0} 要求 {1} 为对象" -f $versionInfo.effective_version, $fieldName)) | Out-Null
            }
        }
        if ([int]$versionInfo.effective_version -eq 1 -and @($cfg.mcp_servers | Where-Object { [string]$_.transport -eq 'sse' }).Count -gt 0) {
            $versionInfo.observations += [pscustomobject]@{
                code = 'legacy_sse_transport_deprecated'
                path = '$.mcp_servers[].transport'
                message = 'Legacy SSE is readable in schema v1 only and must be migrated to Streamable HTTP.'
            }
        }
    }

    foreach ($errorText in @(Get-CfgContractErrors $cfg ([int]$versionInfo.effective_version))) { $errors.Add([string]$errorText) | Out-Null }
    $topLevelFindings = Get-CfgTopLevelFieldContractFindings $cfg ([int]$versionInfo.effective_version)
    foreach ($errorText in @($topLevelFindings.errors)) { $errors.Add([string]$errorText) | Out-Null }
    foreach ($observation in @($topLevelFindings.observations)) { $versionInfo.observations += $observation }
    return [pscustomobject]@{
        schema = $versionInfo
        valid = ($errors.Count -eq 0)
        errors = @($errors.ToArray())
        observations = @($versionInfo.observations)
    }
}
function Get-CfgForbiddenHostRuntimeFieldNames {
    return @('model', 'model_provider', 'provider', 'auth', 'session', 'orchestrator', 'daemon', 'agent_runtime')
}

function Get-CfgTopLevelFieldAllowlist {
    return @('schema_version', 'sync_mode', 'update_force', 'skill_projection', 'vendors', 'mappings', 'imports', 'targets', 'mcp_servers', 'mcp_profiles', 'mcp_targets')
}

function Get-CfgTopLevelFieldContractFindings($cfg, [int]$EffectiveVersion) {
    $errors = New-Object System.Collections.Generic.List[string]
    $observations = New-Object System.Collections.Generic.List[object]
    if ($null -eq $cfg) { return [pscustomobject]@{ errors = @(); observations = @() } }
    $allowlist = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($fieldName in @(Get-CfgTopLevelFieldAllowlist)) { $allowlist.Add($fieldName) | Out-Null }
    foreach ($property in @($cfg.PSObject.Properties)) {
        if (-not $allowlist.Contains($property.Name)) {
            if ($EffectiveVersion -ge 3) {
                $errors.Add(("skills.json 顶层字段未被 schema v3 允许：{0}" -f $property.Name)) | Out-Null
            }
            else {
                $observations.Add([pscustomobject]@{
                    code = 'unknown_top_level_field_v2_observe'
                    path = ('$.{0}' -f $property.Name)
                    message = 'Unknown top-level field is read under schema v2 observe mode; migrate to the v3 allowlist.'
                }) | Out-Null
            }
        }
    }
    return [pscustomobject]@{ errors = @($errors.ToArray()); observations = @($observations.ToArray()) }
}

function Get-NativeAgentBridgeConfigErrors($Bridge) {
    $errors = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Bridge) { return @() }
    if ($Bridge -isnot [pscustomobject] -and $Bridge -isnot [System.Collections.IDictionary]) {
        $errors.Add('skill_projection.native_agent_bridge 必须是对象') | Out-Null
        return @($errors.ToArray())
    }
    if ((Get-CfgObjectProperty $Bridge 'enabled') -isnot [bool]) { $errors.Add('skill_projection.native_agent_bridge.enabled 必须是布尔值') | Out-Null }
    foreach ($fieldName in @('owner', 'source_root', 'target_root', 'receipt_path')) {
        if ([string]::IsNullOrWhiteSpace([string](Get-CfgObjectProperty $Bridge $fieldName))) {
            $errors.Add(("skill_projection.native_agent_bridge.{0} 不能为空" -f $fieldName)) | Out-Null
        }
    }
    $sourceRoot = [string](Get-CfgObjectProperty $Bridge 'source_root')
    if (-not [string]::IsNullOrWhiteSpace($sourceRoot) -and (-not (Test-SafeRelativePath $sourceRoot -AllowDot) -or $sourceRoot -notmatch '^agent[\\/]')) {
        $errors.Add('skill_projection.native_agent_bridge.source_root 必须位于 generated agent/ 下') | Out-Null
    }
    $targetRoot = (([string](Get-CfgObjectProperty $Bridge 'target_root')).Replace('\', '/')).TrimEnd('/')
    if (-not [string]::IsNullOrWhiteSpace($targetRoot) -and -not [string]::Equals($targetRoot, '~/.codex/agents', [StringComparison]::OrdinalIgnoreCase)) {
        $errors.Add('skill_projection.native_agent_bridge.target_root 必须等于 ~/.codex/agents') | Out-Null
    }
    if ([string](Get-CfgObjectProperty $Bridge 'receipt_path') -notmatch '^reports[\\/]native-agent-bridge[\\/][^\\/]+\.json$') {
        $errors.Add('skill_projection.native_agent_bridge.receipt_path 必须位于 reports/native-agent-bridge 且为直接子级 JSON 文件') | Out-Null
    }
    $definitions = Get-CfgObjectProperty $Bridge 'definitions'
    if (-not (Assert-IsArray $definitions) -or @($definitions).Count -eq 0) {
        $errors.Add('skill_projection.native_agent_bridge.definitions 必须是非空数组') | Out-Null
    }
    else {
        $names = @($definitions | ForEach-Object { ([string]$_).Trim() })
        if (@($names | Where-Object { $_ -notmatch '^[a-z0-9][a-z0-9-]*$' }).Count -gt 0) {
            $errors.Add('skill_projection.native_agent_bridge.definitions 必须是 canonical agent names') | Out-Null
        }
        if (@(Get-DuplicateValues $names).Count -gt 0) {
            $errors.Add('skill_projection.native_agent_bridge.definitions 不能重复') | Out-Null
        }
    }
    return @($errors.ToArray())
}

function Get-CfgContractErrors($cfg, [int]$SchemaVersion = 0) {
    $errors = New-Object System.Collections.Generic.List[string]
    if ($null -eq $cfg) {
        $errors.Add("skills.json 为空或无法解析为对象") | Out-Null
        return @($errors.ToArray())
    }
    if ($SchemaVersion -le 0) {
        $versionInfo = Get-CfgSchemaVersionInfo $cfg
        if ($versionInfo.errors.Count -eq 0) { $SchemaVersion = [int]$versionInfo.effective_version }
    }

    foreach ($fieldName in @(Get-CfgForbiddenHostRuntimeFieldNames)) {
        if (Test-CfgObjectProperty $cfg $fieldName) {
            $errors.Add(("skills.json 顶层字段属于宿主 runtime 职责，禁止配置：{0}" -f $fieldName)) | Out-Null
        }
    }

    $vendors = Get-CfgArrayField $cfg "vendors" $true $errors
    $targets = Get-CfgArrayField $cfg "targets" $true $errors
    $mappings = Get-CfgArrayField $cfg "mappings" $false $errors
    $imports = Get-CfgArrayField $cfg "imports" $false $errors
    $mcpServers = Get-CfgArrayField $cfg "mcp_servers" $false $errors
    $mcpTargets = Get-CfgArrayField $cfg "mcp_targets" $false $errors
    $skillProjection = Get-CfgObjectProperty $cfg "skill_projection"
    $usesProjectionProfiles = ($null -ne (Get-CfgObjectProperty $skillProjection 'projection_profiles'))
    foreach ($bridgeError in @(Get-NativeAgentBridgeConfigErrors (Get-CfgObjectProperty $skillProjection 'native_agent_bridge'))) {
        $errors.Add([string]$bridgeError) | Out-Null
    }

    foreach ($target in @($targets)) {
        $managedLinkOnly = Get-CfgObjectProperty $target 'managed_link_only'
        if ($null -eq $managedLinkOnly) { continue }
        if ($managedLinkOnly -isnot [bool]) { $errors.Add('target.managed_link_only 必须是布尔值') | Out-Null; continue }
        if (-not [bool]$managedLinkOnly) { continue }
        if ([string](Get-CfgObjectProperty $cfg 'sync_mode') -ne 'link') { $errors.Add('managed_link_only target 仅支持 sync_mode=link') | Out-Null }
        if ([string](Get-CfgObjectProperty $target 'receipt_path') -notmatch '^reports[\\/]skill-projection[\\/][^\\/]+\.json$') { $errors.Add('managed_link_only target.receipt_path 必须位于 reports/skill-projection 且为直接子级 JSON 文件') | Out-Null }
        if (-not $usesProjectionProfiles) {
            $includes = Get-CfgObjectProperty $skillProjection 'managed_link_includes'
            if (-not (Assert-IsArray $includes) -or @($includes).Count -eq 0) { $errors.Add('managed_link_only target 需要 skill_projection.managed_link_includes') | Out-Null }
        }
    }

    if ($null -ne $skillProjection) {
        $projectionEnabled = Get-CfgObjectProperty $skillProjection "enabled"
        if ($null -ne $projectionEnabled -and $projectionEnabled -isnot [bool]) {
            $errors.Add("skill_projection.enabled 必须是布尔值") | Out-Null
        }
        $externalInventory = Get-CfgObjectProperty $skillProjection "external_skill_inventory"
        if ($null -ne $externalInventory) {
            if ($externalInventory -isnot [pscustomobject] -and $externalInventory -isnot [System.Collections.IDictionary]) {
                $errors.Add("skill_projection.external_skill_inventory 必须是对象") | Out-Null
            }
            else {
                $externalInventoryEnabled = Get-CfgObjectProperty $externalInventory "enabled"
                if ($null -ne $externalInventoryEnabled -and $externalInventoryEnabled -isnot [bool]) {
                    $errors.Add("skill_projection.external_skill_inventory.enabled 必须是布尔值") | Out-Null
                }
            }
        }
        $nativeProjection = Get-CfgObjectProperty $skillProjection "native_projection"
        if ($null -ne $nativeProjection) {
            foreach ($fieldName in @('owner', 'target_root', 'receipt_path')) {
                if ([string]::IsNullOrWhiteSpace([string](Get-CfgObjectProperty $nativeProjection $fieldName))) { $errors.Add(("skill_projection.native_projection.{0} 不能为空" -f $fieldName)) | Out-Null }
            }
            if ((Get-CfgObjectProperty $nativeProjection 'enabled') -isnot [bool]) { $errors.Add('skill_projection.native_projection.enabled 必须是布尔值') | Out-Null }
            if (-not [string]::Equals(([string](Get-CfgObjectProperty $nativeProjection 'target_root')).TrimEnd('\', '/'), ([string](Get-CfgObjectProperty $skillProjection 'user_skill_root')).TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) { $errors.Add('skill_projection.native_projection.target_root 必须等于 skill_projection.user_skill_root') | Out-Null }
            $nativeTargetText = [string](Get-CfgObjectProperty $nativeProjection 'target_root')
            $nativeTargetResolved = if ($nativeTargetText.StartsWith('~')) { $nativeTargetText -replace '^~', [Environment]::GetFolderPath('UserProfile') } elseif ([IO.Path]::IsPathRooted($nativeTargetText)) { $nativeTargetText } else { Join-Path $Root $nativeTargetText }
            $nativeTargetFull = [IO.Path]::GetFullPath($nativeTargetResolved).TrimEnd('\', '/')
            if ([string]::Equals($nativeTargetFull, [IO.Path]::GetPathRoot($nativeTargetFull).TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) { $errors.Add('skill_projection.native_projection.target_root 不能是文件系统根目录') | Out-Null }
            if ([string](Get-CfgObjectProperty $nativeProjection 'receipt_path') -notmatch '^reports[\\/]skill-projection[\\/][^\\/]+\.json$') { $errors.Add('skill_projection.native_projection.receipt_path 必须位于 reports/skill-projection 且为直接子级 JSON 文件') | Out-Null }
        }
        $projectionSources = Get-CfgObjectProperty $skillProjection "sources"
        if (-not (Assert-IsArray $projectionSources)) {
            $errors.Add("skill_projection.sources 必须是数组") | Out-Null
        }
        else {
            foreach ($source in @($projectionSources)) {
                $sourceId = [string](Get-CfgObjectProperty $source "id")
                $sourcePath = [string](Get-CfgObjectProperty $source "path")
                if ([string]::IsNullOrWhiteSpace($sourceId)) { $errors.Add("skill_projection source 缺少 id") | Out-Null }
                if ([string]::IsNullOrWhiteSpace($sourcePath)) { $errors.Add(("skill_projection source 缺少 path：{0}" -f $sourceId)) | Out-Null }
            }
        }
        $managedLinkExcludes = Get-CfgObjectProperty $skillProjection "managed_link_excludes"
        $normalizedExcludes = @()
        if ($null -ne $managedLinkExcludes) {
            if (-not (Assert-IsArray $managedLinkExcludes)) {
                $errors.Add("skill_projection.managed_link_excludes 必须是数组") | Out-Null
            }
            else {
                foreach ($exclude in @($managedLinkExcludes)) {
                    $name = [string]$exclude
                    if ([string]::IsNullOrWhiteSpace($name)) {
                        $errors.Add("skill_projection.managed_link_excludes 不能包含空字符串") | Out-Null
                        continue
                    }
                    $normalizedExcludes += $name.Trim().ToLowerInvariant()
                }
                $duplicateExcludes = @(Get-DuplicateValues $normalizedExcludes)
                if ($duplicateExcludes.Count -gt 0) {
                    $errors.Add(("skill_projection.managed_link_excludes 重复：{0}" -f ($duplicateExcludes -join ", "))) | Out-Null
                }
            }
        }
        $managedLinkIncludes = Get-CfgObjectProperty $skillProjection "managed_link_includes"
        if ($null -ne $managedLinkIncludes) {
            if (-not (Assert-IsArray $managedLinkIncludes)) {
                $errors.Add("skill_projection.managed_link_includes 必须是数组") | Out-Null
            }
            else {
                $normalizedIncludes = @()
                foreach ($include in @($managedLinkIncludes)) {
                    $name = [string]$include
                    if ([string]::IsNullOrWhiteSpace($name)) {
                        $errors.Add("skill_projection.managed_link_includes 不能包含空字符串") | Out-Null
                        continue
                    }
                    $normalizedIncludes += $name.Trim().ToLowerInvariant()
                }
                if ($normalizedIncludes.Count -eq 0) {
                    $errors.Add("skill_projection.managed_link_includes 至少需要一个技能") | Out-Null
                }
                $duplicateIncludes = @(Get-DuplicateValues $normalizedIncludes)
                if ($duplicateIncludes.Count -gt 0) {
                    $errors.Add(("skill_projection.managed_link_includes 重复：{0}" -f ($duplicateIncludes -join ", "))) | Out-Null
                }
                $conflictingLinks = @($normalizedIncludes | Where-Object { $normalizedExcludes -contains $_ } | Sort-Object -Unique)
                if ($conflictingLinks.Count -gt 0) {
                    $errors.Add(("skill_projection managed link include/exclude 冲突：{0}" -f ($conflictingLinks -join ", "))) | Out-Null
                }
            }
        }
        foreach ($profileError in @(Get-SkillProjectionProfileContractErrors $skillProjection $targets)) {
            $errors.Add([string]$profileError) | Out-Null
        }
    }

    $mcpProfiles = Get-CfgObjectProperty $cfg "mcp_profiles"
    if ($null -ne $mcpProfiles) {
        $mcpServerNames = New-CfgMcpServerNameSet $mcpServers
        $activeMcpProfile = [string](Get-CfgObjectProperty $mcpProfiles "active")
        $profiles = Get-CfgObjectProperty $mcpProfiles "profiles"
        if ([string]::IsNullOrWhiteSpace($activeMcpProfile)) { $errors.Add("mcp_profiles.active 不能为空") | Out-Null }
        if ($null -eq $profiles) { $errors.Add("mcp_profiles 缺少 profiles") | Out-Null }
        else {
            foreach ($profileProperty in @($profiles.PSObject.Properties)) {
                $profileName = [string]$profileProperty.Name
                $profile = $profileProperty.Value
                if (-not (Test-CfgArrayProperty $profile "enabled")) {
                    $errors.Add(("MCP profile.enabled 必须是数组：{0}" -f $profileName)) | Out-Null
                }
                else {
                    foreach ($rawName in @($profile.enabled)) {
                        $name = ([string]$rawName).Trim()
                        if (-not $mcpServerNames.Contains($name)) { $errors.Add(("MCP profile 引用了不存在的服务：{0}/{1}" -f $profileName, $name)) | Out-Null }
                    }
                }
                if ($null -ne $profile -and $profile.PSObject.Properties.Match("enabled_tools").Count -gt 0 -and $null -ne $profile.enabled_tools) {
                    foreach ($toolProperty in @($profile.enabled_tools.PSObject.Properties)) {
                        if (-not $mcpServerNames.Contains([string]$toolProperty.Name)) {
                            $errors.Add(("MCP profile enabled_tools 引用了不存在的服务：{0}/{1}" -f $profileName, [string]$toolProperty.Name)) | Out-Null
                        }
                    }
                }
            }
        }
    }

    foreach ($v in $vendors) {
        $name = [string](Get-CfgObjectProperty $v "name")
        $repo = [string](Get-CfgObjectProperty $v "repo")
        if ([string]::IsNullOrWhiteSpace($name)) { $errors.Add("vendor 缺少 name") | Out-Null }
        if ([string]::IsNullOrWhiteSpace($repo)) { $errors.Add(("vendor {0} 缺少 repo" -f $name)) | Out-Null }
    }

    foreach ($t in $targets) {
        $path = [string](Get-CfgObjectProperty $t "path")
        if ([string]::IsNullOrWhiteSpace($path)) { $errors.Add("target 缺少 path") | Out-Null }
    }

    foreach ($m in $mappings) {
        $vendor = [string](Get-CfgObjectProperty $m "vendor")
        $from = [string](Get-CfgObjectProperty $m "from")
        $to = [string](Get-CfgObjectProperty $m "to")
        if ([string]::IsNullOrWhiteSpace($vendor)) { $errors.Add("mapping 缺少 vendor") | Out-Null }
        if ([string]::IsNullOrWhiteSpace($from)) { $errors.Add("mapping 缺少 from") | Out-Null }
        if ([string]::IsNullOrWhiteSpace($to)) { $errors.Add("mapping 缺少 to") | Out-Null }
        if (-not [string]::IsNullOrWhiteSpace($from) -and -not (Test-SafeRelativePath $from -AllowDot)) {
            $errors.Add(("mapping.from 非法（仅允许相对路径，禁止 .. 与绝对路径）：{0}" -f $from)) | Out-Null
        }
        if (-not [string]::IsNullOrWhiteSpace($to) -and -not (Test-SafeRelativePath $to)) {
            $errors.Add(("mapping.to 非法（仅允许相对路径，禁止 .. 与绝对路径）：{0}" -f $to)) | Out-Null
        }
        elseif ($SchemaVersion -ge 2 -and $to -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
            $errors.Add(("schema v2 要求 mapping.to 为 canonical skill name：{0}" -f $to)) | Out-Null
        }
    }

    foreach ($i in $imports) {
        $name = [string](Get-CfgObjectProperty $i "name")
        $repo = [string](Get-CfgObjectProperty $i "repo")
        $skill = Normalize-SkillPath ([string](Get-CfgObjectProperty $i "skill"))
        $mode = [string](Get-CfgObjectProperty $i "mode")
        if ([string]::IsNullOrWhiteSpace($name)) { $errors.Add("import 缺少 name") | Out-Null }
        if ([string]::IsNullOrWhiteSpace($repo)) { $errors.Add("import 缺少 repo") | Out-Null }
        if (-not (Test-SafeRelativePath $skill -AllowDot)) {
            $errors.Add(("import.skill 非法（仅允许相对路径，禁止 .. 与绝对路径）：{0}" -f $skill)) | Out-Null
        }
        if (-not [string]::IsNullOrWhiteSpace($mode) -and $mode -ne "manual" -and $mode -ne "vendor") {
            $errors.Add(("import mode 仅支持 manual 或 vendor：{0}" -f $name)) | Out-Null
        }
    }

    foreach ($s in $mcpServers) {
        $name = [string](Get-CfgObjectProperty $s "name")
        $transport = [string](Get-CfgObjectProperty $s "transport")
        if ([string]::IsNullOrWhiteSpace($transport)) { $transport = "stdio" }
        if ([string]::IsNullOrWhiteSpace($name)) { $errors.Add("mcp_server 缺少 name") | Out-Null }
        $allowedTransports = if ($SchemaVersion -ge 2) { @('stdio', 'http') } else { @('stdio', 'sse', 'http') }
        if ($transport -notin $allowedTransports) {
            $errors.Add(("mcp_server.transport 仅支持 {0}：{1}" -f ($allowedTransports -join '/'), $name)) | Out-Null
            continue
        }
        if ($transport -eq "stdio") {
            $command = [string](Get-CfgObjectProperty $s "command")
            if ([string]::IsNullOrWhiteSpace($command)) { $errors.Add(("mcp_server(stdio) 缺少 command：{0}" -f $name)) | Out-Null }
        }
        else {
            $url = [string](Get-CfgObjectProperty $s "url")
            if ([string]::IsNullOrWhiteSpace($url)) { $errors.Add(("mcp_server({0}) 缺少 url：{1}" -f $transport, $name)) | Out-Null }
        }
    }

    foreach ($mt in $mcpTargets) {
        if ($mt -is [string]) {
            if ([string]::IsNullOrWhiteSpace([string]$mt)) { $errors.Add("mcp_targets 不能包含空字符串") | Out-Null }
            continue
        }
        $path = [string](Get-CfgObjectProperty $mt "path")
        if ([string]::IsNullOrWhiteSpace($path)) { $errors.Add("mcp_targets 项缺少 path") | Out-Null }
    }

    $modeValue = [string](Get-CfgObjectProperty $cfg "sync_mode")
    if ([string]::IsNullOrWhiteSpace($modeValue)) { $modeValue = "link" }
    if ($modeValue -ne "link" -and $modeValue -ne "sync") {
        $errors.Add("sync_mode 仅支持 link 或 sync") | Out-Null
    }

    $vendorNames = New-CfgVendorNameSet $vendors
    foreach ($m in $mappings) {
        $vendor = [string](Get-CfgObjectProperty $m "vendor")
        if (-not [string]::IsNullOrWhiteSpace($vendor) -and -not $vendorNames.Contains($vendor)) {
            $errors.Add(("mapping 引用了不存在的 vendor：{0}" -f $vendor)) | Out-Null
        }
    }

    return @($errors.ToArray())
}
function Get-DuplicateValues([object[]]$items) {
    if ($null -eq $items) { return @() }
    return $items | Group-Object | Where-Object { $_.Count -gt 1 } | Select-Object -ExpandProperty Name
}
function Assert-Cfg($cfg) {
    $versionInfo = Get-CfgSchemaVersionInfo $cfg
    Need ($versionInfo.errors.Count -eq 0) (($versionInfo.errors | Select-Object -First 1) -join '')
    $effectiveSchemaVersion = [int]$versionInfo.effective_version
    if ($effectiveSchemaVersion -eq 1) {
        Log 'skills.json schema v1 仅保留迁移读取兼容；新配置请使用 schema v3。' 'WARN'
    }
    foreach ($fieldName in @(Get-CfgForbiddenHostRuntimeFieldNames)) {
        Need (-not (Test-CfgObjectProperty $cfg $fieldName)) ("skills.json 顶层字段属于宿主 runtime 职责，禁止配置：{0}" -f $fieldName)
    }
    $topLevelFindings = Get-CfgTopLevelFieldContractFindings $cfg $effectiveSchemaVersion
    foreach ($observation in @($topLevelFindings.observations)) { Log $observation.message 'WARN' }
    Need (@($topLevelFindings.errors).Count -eq 0) ([string]@($topLevelFindings.errors)[0])
    Need (Assert-IsArray $cfg.vendors) "skills.json 的 vendors 必须是数组"
    Need (Assert-IsArray $cfg.targets) "skills.json 的 targets 必须是数组"
    Need (Assert-IsArray $cfg.mappings) "skills.json 的 mappings 必须是数组"
    Need (Assert-IsArray $cfg.imports) "skills.json 的 imports 必须是数组"
    Need (Assert-IsArray $cfg.mcp_servers) "skills.json 的 mcp_servers 必须是数组"
    Need (Assert-IsArray $cfg.mcp_targets) "skills.json 的 mcp_targets 必须是数组"
    foreach ($v in $cfg.vendors) {
        Need (-not [string]::IsNullOrWhiteSpace($v.name)) "vendor 缺少 name"
        Need (-not [string]::IsNullOrWhiteSpace($v.repo)) "vendor $($v.name) 缺少 repo"
    }
    foreach ($t in $cfg.targets) {
        Need (-not [string]::IsNullOrWhiteSpace($t.path)) "target 缺少 path"
        if (Test-CfgObjectProperty $t 'managed_link_only') {
            Need ((Get-CfgObjectProperty $t 'managed_link_only') -is [bool]) 'target.managed_link_only 必须是布尔值'
            if ([bool](Get-CfgObjectProperty $t 'managed_link_only')) {
                Need ([string]$cfg.sync_mode -eq 'link') 'managed_link_only target 仅支持 sync_mode=link'
                Need ([string](Get-CfgObjectProperty $t 'receipt_path') -match '^reports[\\/]skill-projection[\\/][^\\/]+\.json$') 'managed_link_only target.receipt_path 必须位于 reports/skill-projection 且为直接子级 JSON 文件'
                $usesProjectionProfiles = $null -ne (Get-CfgObjectProperty $cfg.skill_projection 'projection_profiles')
                if (-not $usesProjectionProfiles) {
                    Need ($null -ne $cfg.skill_projection -and (Assert-IsArray (Get-CfgObjectProperty $cfg.skill_projection 'managed_link_includes')) -and @((Get-CfgObjectProperty $cfg.skill_projection 'managed_link_includes')).Count -gt 0) 'managed_link_only target 需要 skill_projection.managed_link_includes'
                }
            }
        }
    }
    foreach ($m in $cfg.mappings) {
        Need (-not [string]::IsNullOrWhiteSpace($m.vendor)) "mapping 缺少 vendor"
        Need (-not [string]::IsNullOrWhiteSpace($m.from)) "mapping 缺少 from"
        Need (-not [string]::IsNullOrWhiteSpace($m.to)) "mapping 缺少 to"
        Need (Test-SafeRelativePath $m.from -AllowDot) ("mapping.from 非法（仅允许相对路径，禁止 .. 与绝对路径）：{0}" -f $m.from)
        Need (Test-SafeRelativePath $m.to) ("mapping.to 非法（仅允许相对路径，禁止 .. 与绝对路径）：{0}" -f $m.to)
        if ($effectiveSchemaVersion -ge 2) {
            Need ([string]$m.to -match '^[a-z0-9]+(?:-[a-z0-9]+)*$') ("schema v2 要求 mapping.to 为 canonical skill name：{0}" -f $m.to)
        }
    }
    foreach ($i in $cfg.imports) {
        Need (-not [string]::IsNullOrWhiteSpace($i.name)) "import 缺少 name"
        Need (-not [string]::IsNullOrWhiteSpace($i.repo)) "import 缺少 repo"
        $importSkill = Normalize-SkillPath ([string]$i.skill)
        Need (Test-SafeRelativePath $importSkill -AllowDot) ("import.skill 非法（仅允许相对路径，禁止 .. 与绝对路径）：{0}" -f $i.skill)
    }
    foreach ($s in $cfg.mcp_servers) {
        Need (-not [string]::IsNullOrWhiteSpace($s.name)) "mcp_server 缺少 name"
        $transport = if ($s.PSObject.Properties.Match("transport").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$s.transport)) { [string]$s.transport } else { "stdio" }
        $allowedTransports = if ($effectiveSchemaVersion -ge 2) { @('stdio', 'http') } else { @('stdio', 'sse', 'http') }
        Need ($transport -in $allowedTransports) ("mcp_server.transport 仅支持 {0}：{1}" -f ($allowedTransports -join '/'), $s.name)
        if ($effectiveSchemaVersion -eq 1 -and $transport -eq 'sse') {
            Log ("legacy SSE transport 已弃用，请迁移到 Streamable HTTP：{0}" -f $s.name) 'WARN'
        }
        if ($transport -eq "stdio") {
            Need ($s.PSObject.Properties.Match("command").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$s.command)) ("mcp_server(stdio) 缺少 command：{0}" -f $s.name)
        }
        else {
            Need ($s.PSObject.Properties.Match("url").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$s.url)) ("mcp_server({0}) 缺少 url：{1}" -f $transport, $s.name)
        }
    }
    foreach ($mt in $cfg.mcp_targets) {
        if ($mt -is [string]) {
            Need (-not [string]::IsNullOrWhiteSpace([string]$mt)) "mcp_targets 不能包含空字符串"
            continue
        }
        Need ($mt.PSObject.Properties.Match("path").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$mt.path)) "mcp_targets 项缺少 path"
    }

    if ($cfg.PSObject.Properties.Match("skill_projection").Count -gt 0 -and $null -ne $cfg.skill_projection) {
        $projection = $cfg.skill_projection
        if ($projection.PSObject.Properties.Match("enabled").Count -gt 0) {
            Need ($projection.enabled -is [bool]) "skill_projection.enabled 必须是布尔值"
        }
        if ($projection.PSObject.Properties.Match("external_skill_inventory").Count -gt 0 -and $null -ne $projection.external_skill_inventory) {
            $externalInventory = $projection.external_skill_inventory
            Need ($externalInventory -is [pscustomobject] -or $externalInventory -is [System.Collections.IDictionary]) "skill_projection.external_skill_inventory 必须是对象"
            if (Test-CfgObjectProperty $externalInventory "enabled") {
                Need ((Get-CfgObjectProperty $externalInventory "enabled") -is [bool]) "skill_projection.external_skill_inventory.enabled 必须是布尔值"
            }
        }
        if ($projection.PSObject.Properties.Match('native_projection').Count -gt 0 -and $null -ne $projection.native_projection) {
            $nativeProjection = $projection.native_projection
            Need ($nativeProjection.enabled -is [bool]) 'skill_projection.native_projection.enabled 必须是布尔值'
            foreach ($fieldName in @('owner', 'target_root', 'receipt_path')) { Need (-not [string]::IsNullOrWhiteSpace([string](Get-CfgObjectProperty $nativeProjection $fieldName))) ("skill_projection.native_projection.{0} 不能为空" -f $fieldName) }
            Need ([string]::Equals(([string]$nativeProjection.target_root).TrimEnd('\', '/'), ([string]$projection.user_skill_root).TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) 'skill_projection.native_projection.target_root 必须等于 skill_projection.user_skill_root'
            $nativeTargetText = [string]$nativeProjection.target_root
            $nativeTargetResolved = if ($nativeTargetText.StartsWith('~')) { $nativeTargetText -replace '^~', [Environment]::GetFolderPath('UserProfile') } elseif ([IO.Path]::IsPathRooted($nativeTargetText)) { $nativeTargetText } else { Join-Path $Root $nativeTargetText }
            $nativeTargetFull = [IO.Path]::GetFullPath($nativeTargetResolved).TrimEnd('\', '/')
            Need (-not [string]::Equals($nativeTargetFull, [IO.Path]::GetPathRoot($nativeTargetFull).TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) 'skill_projection.native_projection.target_root 不能是文件系统根目录'
            Need ([string]$nativeProjection.receipt_path -match '^reports[\\/]skill-projection[\\/][^\\/]+\.json$') 'skill_projection.native_projection.receipt_path 必须位于 reports/skill-projection 且为直接子级 JSON 文件'
        }
        foreach ($bridgeError in @(Get-NativeAgentBridgeConfigErrors (Get-CfgObjectProperty $projection 'native_agent_bridge'))) {
            Need ($false) ([string]$bridgeError)
        }
        Need ($projection.PSObject.Properties.Match("sources").Count -gt 0 -and (Assert-IsArray $projection.sources)) "skill_projection.sources 必须是数组"
        foreach ($source in @($projection.sources)) {
            Need (-not [string]::IsNullOrWhiteSpace([string]$source.id)) "skill_projection source 缺少 id"
            Need (-not [string]::IsNullOrWhiteSpace([string]$source.path)) ("skill_projection source 缺少 path：{0}" -f [string]$source.id)
        }
        $dupProjectionSources = @(Get-DuplicateValues ($projection.sources | ForEach-Object { $_.id }))
        Need ($dupProjectionSources.Count -eq 0) ("skill_projection source id 重复：{0}" -f ($dupProjectionSources -join ", "))
        if ($projection.PSObject.Properties.Match("managed_link_excludes").Count -gt 0 -and $null -ne $projection.managed_link_excludes) {
            Need (Assert-IsArray $projection.managed_link_excludes) "skill_projection.managed_link_excludes 必须是数组"
            foreach ($exclude in @($projection.managed_link_excludes)) {
                Need (-not [string]::IsNullOrWhiteSpace([string]$exclude)) "skill_projection.managed_link_excludes 不能包含空字符串"
            }
            $dupManagedLinkExcludes = @(Get-DuplicateValues ($projection.managed_link_excludes | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() }))
            Need ($dupManagedLinkExcludes.Count -eq 0) ("skill_projection.managed_link_excludes 重复：{0}" -f ($dupManagedLinkExcludes -join ", "))
        }
        if ($projection.PSObject.Properties.Match("managed_link_includes").Count -gt 0 -and $null -ne $projection.managed_link_includes) {
            Need (Assert-IsArray $projection.managed_link_includes) "skill_projection.managed_link_includes 必须是数组"
            Need (@($projection.managed_link_includes).Count -gt 0) "skill_projection.managed_link_includes 至少需要一个技能"
            foreach ($include in @($projection.managed_link_includes)) {
                Need (-not [string]::IsNullOrWhiteSpace([string]$include)) "skill_projection.managed_link_includes 不能包含空字符串"
            }
            $normalizedManagedLinkIncludes = @($projection.managed_link_includes | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
            $dupManagedLinkIncludes = @(Get-DuplicateValues $normalizedManagedLinkIncludes)
            Need ($dupManagedLinkIncludes.Count -eq 0) ("skill_projection.managed_link_includes 重复：{0}" -f ($dupManagedLinkIncludes -join ", "))
            $normalizedManagedLinkExcludes = @($projection.managed_link_excludes | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
            $managedLinkConflicts = @($normalizedManagedLinkIncludes | Where-Object { $normalizedManagedLinkExcludes -contains $_ } | Sort-Object -Unique)
            Need ($managedLinkConflicts.Count -eq 0) ("skill_projection managed link include/exclude 冲突：{0}" -f ($managedLinkConflicts -join ", "))
        }
    }

    if ($cfg.PSObject.Properties.Match("mcp_profiles").Count -gt 0 -and $null -ne $cfg.mcp_profiles) {
        $mcpProfiles = $cfg.mcp_profiles
        $mcpServerNames = New-CfgMcpServerNameSet $cfg.mcp_servers
        Need (-not [string]::IsNullOrWhiteSpace([string]$mcpProfiles.active)) "mcp_profiles.active 不能为空"
        Need ($mcpProfiles.PSObject.Properties.Match("profiles").Count -gt 0 -and $null -ne $mcpProfiles.profiles) "mcp_profiles 缺少 profiles"
        Need (@($mcpProfiles.profiles.PSObject.Properties | Where-Object { $_.Name -eq [string]$mcpProfiles.active }).Count -gt 0) ("mcp_profiles.active 不存在：{0}" -f [string]$mcpProfiles.active)
        foreach ($profileProperty in @($mcpProfiles.profiles.PSObject.Properties)) {
            $profileName = [string]$profileProperty.Name
            $profile = $profileProperty.Value
            Need (Test-CfgArrayProperty $profile "enabled") ("MCP profile.enabled 必须是数组：{0}" -f $profileName)
            foreach ($rawName in @($profile.enabled)) {
                $name = ([string]$rawName).Trim()
                Need ($mcpServerNames.Contains($name)) ("MCP profile 引用了不存在的服务：{0}/{1}" -f $profileName, $name)
            }
            if ($profile.PSObject.Properties.Match("enabled_tools").Count -gt 0 -and $null -ne $profile.enabled_tools) {
                foreach ($toolProperty in @($profile.enabled_tools.PSObject.Properties)) {
                    Need ($mcpServerNames.Contains([string]$toolProperty.Name)) ("MCP profile enabled_tools 引用了不存在的服务：{0}/{1}" -f $profileName, [string]$toolProperty.Name)
                }
            }
        }
    }

    $mode = $cfg.sync_mode
    Need (($mode -eq "link") -or ($mode -eq "sync")) "sync_mode 仅支持 link 或 sync"

    $dupVendors = @(Get-DuplicateValues ($cfg.vendors | ForEach-Object { $_.name }))
    Need ($dupVendors.Count -eq 0) ("vendor 名称重复：{0}" -f ($dupVendors -join ", "))

    $dupImports = @(Get-DuplicateValues ($cfg.imports | ForEach-Object { $_.name }))
    Need ($dupImports.Count -eq 0) ("import 名称重复：{0}" -f ($dupImports -join ", "))

    $dupTargets = @(Get-DuplicateValues ($cfg.targets | ForEach-Object { $_.path }))
    if ($dupTargets.Count -gt 0) {
        Log ("目标路径重复（建议去重）：{0}" -f ($dupTargets -join ", ")) "WARN"
    }

    $dupTo = @(Get-DuplicateValues ($cfg.mappings | ForEach-Object { $_.to }))
    if ($dupTo.Count -gt 0) {
        Log ("mappings 的 to 重复（可能覆盖）：{0}" -f ($dupTo -join ", ")) "WARN"
    }

    $vendorNames = New-CfgVendorNameSet $cfg.vendors
    foreach ($m in $cfg.mappings) {
        Need ($vendorNames.Contains($m.vendor)) ("mapping 引用了不存在的 vendor：{0}" -f $m.vendor)
    }

    foreach ($i in $cfg.imports) {
        if ($i.PSObject.Properties.Match("mode").Count -gt 0) {
            Need (($i.mode -eq "manual") -or ($i.mode -eq "vendor")) ("import mode 仅支持 manual 或 vendor：{0}" -f $i.name)
        }
    }
}
