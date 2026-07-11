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

function Get-SkillProjectionSourceEntries($source, [int]$sourceOrder) {
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
                    content_hash = [string](Get-FileContentHash ([string]$item.file))
                    package_hash = [string](Get-SkillPackageContentHash ([string]$item.dir))
                    target_platforms = @($platforms)
                })) | Out-Null
    }
    return @($entries.ToArray())
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
        New-Junction $linkPath $dir.FullName
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

function New-SkillProjectionPlan($projectionCfg) {
    Need ($null -ne $projectionCfg) "skill_projection 配置为空"
    $enabled = -not ($projectionCfg.PSObject.Properties.Match("enabled").Count -gt 0) -or [bool]$projectionCfg.enabled
    if (-not $enabled) {
        return [pscustomobject]@{ schema_version = 2; enabled = $false; skills = @(); canonical = @(); active = @(); disabled = @(); conflicts = @(); unique_names = @(); active_names = @(); duplicate_name_groups = 0 }
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
            Need ($canonicalByName.ContainsKey($replacement)) ("skill_projection alias replacement 不存在：{0} -> {1}" -f $aliasName, $replacement)
            $aliases[$aliasName] = $replacement
        }
    }

    $budgetLimitChars = if ($projectionCfg.PSObject.Properties.Match("budget_limit_chars").Count -gt 0) { [int]$projectionCfg.budget_limit_chars } else { 8000 }
    $externalReserveChars = if ($projectionCfg.PSObject.Properties.Match("external_metadata_reserve_chars").Count -gt 0) { [int]$projectionCfg.external_metadata_reserve_chars } else { 0 }
    Need ($budgetLimitChars -gt 0) "skill_projection.budget_limit_chars 必须大于 0"
    Need ($externalReserveChars -ge 0) "skill_projection.external_metadata_reserve_chars 不能小于 0"

    $activeProfile = ""
    $profileEnabledNames = $null
    $profileBudgets = New-Object System.Collections.Generic.List[object]
    if ($projectionCfg.PSObject.Properties.Match("profiles").Count -gt 0 -and $null -ne $projectionCfg.profiles) {
        $activeProfile = ([string]$projectionCfg.active_profile).Trim()
        Need (-not [string]::IsNullOrWhiteSpace($activeProfile)) "skill_projection 配置 profiles 时必须声明 active_profile"
        $profileProperty = @($projectionCfg.profiles.PSObject.Properties | Where-Object { [string]::Equals($_.Name, $activeProfile, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        Need ($profileProperty.Count -eq 1) ("skill_projection active_profile 不存在：{0}" -f $activeProfile)
        foreach ($property in @($projectionCfg.profiles.PSObject.Properties | Sort-Object Name)) {
            $profileName = [string]$property.Name
            $profile = $property.Value
            Need ($null -ne $profile -and $profile.PSObject.Properties.Match("enabled_names").Count -gt 0) ("skill_projection profile 缺少 enabled_names：{0}" -f $profileName)
            $enabledNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($rawName in @($profile.enabled_names)) {
                $name = ([string]$rawName).Trim()
                Need (-not [string]::IsNullOrWhiteSpace($name)) ("skill_projection profile enabled_names 不得包含空值：{0}" -f $profileName)
                Need ($canonicalByName.ContainsKey($name)) ("skill_projection profile 引用了不存在的技能：{0}/{1}" -f $profileName, $name)
                $enabledNames.Add($name) | Out-Null
            }

            $profileMetadataChars = 0
            $profileActiveSkillCount = 0
            foreach ($entry in @($canonical.ToArray())) {
                $entryName = [string]$entry.name
                if ($aliases.ContainsKey($entryName)) { continue }
                if (-not [bool]$entry.is_system -and -not $enabledNames.Contains($entryName)) { continue }
                $profileMetadataChars += $entryName.Length + ([string]$entry.description).Length
                $profileActiveSkillCount++
            }
            $profileEstimatedChars = $profileMetadataChars + $externalReserveChars
            $profileBudgets.Add([pscustomobject]([ordered]@{
                        profile = $profileName
                        enabled_name_count = $enabledNames.Count
                        active_skill_count = $profileActiveSkillCount
                        skill_metadata_chars = $profileMetadataChars
                        external_metadata_reserve_chars = $externalReserveChars
                        estimated_metadata_chars = $profileEstimatedChars
                        budget_limit_chars = $budgetLimitChars
                        budget_pass = ($profileEstimatedChars -le $budgetLimitChars)
                    })) | Out-Null

            if ([string]::Equals($profileName, $activeProfile, [System.StringComparison]::OrdinalIgnoreCase)) {
                $profileEnabledNames = $enabledNames
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
    $estimatedMetadataChars = $skillMetadataChars + $externalReserveChars
    $allProfilesBudgetPass = @($profileBudgets.ToArray() | Where-Object { -not [bool]$_.budget_pass }).Count -eq 0

    return [pscustomobject]([ordered]@{
        schema_version = 2
        enabled = $true
        conflict_policy = "system_then_priority_then_source_order"
        active_profile = $activeProfile
        skills = @($all.ToArray() | Sort-Object name, @{ Expression = "priority"; Descending = $true }, path)
        canonical = @($canonical.ToArray() | Sort-Object name)
        active = @($active.ToArray() | Sort-Object name)
        disabled = @($disabled.ToArray() | Sort-Object name, path)
        conflicts = @($conflicts.ToArray() | Sort-Object name)
        unique_names = @($canonical.ToArray() | ForEach-Object { [string]$_.name } | Sort-Object)
        active_names = @($active.ToArray() | ForEach-Object { [string]$_.name } | Sort-Object)
        duplicate_name_groups = $duplicateGroups
        skill_metadata_chars = $skillMetadataChars
        external_metadata_reserve_chars = $externalReserveChars
        estimated_metadata_chars = $estimatedMetadataChars
        budget_limit_chars = $budgetLimitChars
        budget_pass = ($estimatedMetadataChars -le $budgetLimitChars)
        all_profiles_budget_pass = $allProfilesBudgetPass
        profile_budgets = @($profileBudgets.ToArray())
    })
}

function Build-CodexSkillsProjectionToml([string]$existingToml, $disabledEntries) {
    $begin = "# BEGIN skills-manager:skills-projection"
    $end = "# END skills-manager:skills-projection"
    $lines = if ([string]::IsNullOrEmpty($existingToml)) { @() } else { @($existingToml -split "`r?`n") }
    $kept = New-Object System.Collections.Generic.List[string]
    $inside = $false
    $foundBegin = $false
    $foundEnd = $false
    foreach ($line in $lines) {
        if ($line.Trim() -eq $begin) {
            Need (-not $inside) "Codex skills projection 受管块重复开始"
            $inside = $true
            $foundBegin = $true
            continue
        }
        if ($line.Trim() -eq $end) {
            Need ($inside) "Codex skills projection 受管块缺少开始标记"
            $inside = $false
            $foundEnd = $true
            continue
        }
        if (-not $inside) { $kept.Add([string]$line) | Out-Null }
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

function Sync-CodexSkillProjection($projectionCfg) {
    $linkProjection = $null
    if ($projectionCfg.PSObject.Properties.Match("managed_source_path").Count -gt 0 -or $projectionCfg.PSObject.Properties.Match("user_skill_root").Count -gt 0) {
        $linkProjection = Sync-CodexManagedSkillLinks $projectionCfg
    }
    $plan = New-SkillProjectionPlan $projectionCfg
    if ([bool]$plan.enabled) {
        Need ([bool]$plan.budget_pass) ("技能描述预算超限：estimated={0}, limit={1}, profile={2}" -f [int]$plan.estimated_metadata_chars, [int]$plan.budget_limit_chars, [string]$plan.active_profile)
        $oversizedProfiles = @($plan.profile_budgets | Where-Object { -not [bool]$_.budget_pass } | ForEach-Object { "{0}={1}/{2}" -f $_.profile, $_.estimated_metadata_chars, $_.budget_limit_chars })
        Need ([bool]$plan.all_profiles_budget_pass) ("技能 profile 描述预算超限：{0}" -f ($oversizedProfiles -join ", "))
    }

    $configRaw = if ($projectionCfg.PSObject.Properties.Match("codex_config_path").Count -gt 0) { [string]$projectionCfg.codex_config_path } else { "~/.codex/config.toml" }
    $manifestRaw = if ($projectionCfg.PSObject.Properties.Match("manifest_path").Count -gt 0) { [string]$projectionCfg.manifest_path } else { "reports/skill-projection/current.json" }
    $configPath = Resolve-SkillProjectionPath $configRaw
    $manifestPath = Resolve-SkillProjectionPath $manifestRaw
    $existing = if (Test-Path -LiteralPath $configPath -PathType Leaf) { Get-ContentUtf8 $configPath } else { "" }
    $desired = Build-CodexSkillsProjectionToml $existing @($plan.disabled)
    $changed = -not [string]::Equals($existing, $desired, [System.StringComparison]::Ordinal)
    $backupPath = $null

    if (-not $DryRun) {
        if ($changed) {
            $backupPath = Backup-CodexSkillProjectionConfig $configPath
            Set-ContentUtf8 $configPath $desired
        }
        $manifest = [ordered]@{
            schema_version = 2
            enabled = [bool]$plan.enabled
            generated_at = (Get-Date).ToString("o")
            conflict_policy = [string]$plan.conflict_policy
            active_profile = [string]$plan.active_profile
            source_count = @($projectionCfg.sources).Count
            skill_entry_count = @($plan.skills).Count
            unique_name_count = @($plan.unique_names).Count
            active_name_count = @($plan.active_names).Count
            duplicate_name_groups = [int]$plan.duplicate_name_groups
            disabled_path_count = @($plan.disabled).Count
            conflict_count = @($plan.conflicts).Count
            skill_metadata_chars = [int]$plan.skill_metadata_chars
            external_metadata_reserve_chars = [int]$plan.external_metadata_reserve_chars
            estimated_metadata_chars = [int]$plan.estimated_metadata_chars
            budget_limit_chars = [int]$plan.budget_limit_chars
            budget_pass = [bool]$plan.budget_pass
            all_profiles_budget_pass = [bool]$plan.all_profiles_budget_pass
            profile_budgets = @($plan.profile_budgets)
            skills = @($plan.skills)
            canonical = @($plan.canonical)
            active = @($plan.active)
            disabled = @($plan.disabled)
            conflicts = @($plan.conflicts)
        }
        Set-ContentUtf8 $manifestPath ($manifest | ConvertTo-Json -Depth 20)
    }

    return [pscustomobject]@{
        success = $true
        persisted = (-not $DryRun)
        changed = $changed
        config_path = $configPath
        manifest_path = $manifestPath
        backup_path = if ($null -eq $backupPath) { "" } else { [string]$backupPath }
        managed_link_projection = $linkProjection
        plan = $plan
    }
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
    Need ($action -in @("使用", "use")) ("技能配置仅支持 列表/list 或 使用/use：{0}" -f $action)
    Need ($tokens.Count -ge 2) "技能配置 使用 缺少 profile 名称"
    $name = ([string]$tokens[1]).Trim()
    $profileProperty = @($projection.profiles.PSObject.Properties | Where-Object { [string]::Equals($_.Name, $name, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    Need ($profileProperty.Count -eq 1) ("技能 profile 不存在：{0}" -f $name)
    $projection.active_profile = [string]$profileProperty[0].Name
    $plan = New-SkillProjectionPlan $projection
    Need ([bool]$plan.budget_pass) ("技能 profile 超出描述预算：{0} ({1}/{2})" -f $name, $plan.estimated_metadata_chars, $plan.budget_limit_chars)
    $raw = Get-ContentUtf8 $CfgPath
    SaveCfgSafe $cfg $raw
    $result = Sync-CodexSkillProjection $projection
    Write-Host ("已使用技能 profile：{0}；active={1}, metadata={2}/{3}, persisted={4}" -f $name, @($result.plan.active).Count, $result.plan.estimated_metadata_chars, $result.plan.budget_limit_chars, [bool]$result.persisted)
}

function Sync-ConfiguredSkillProjection($cfg) {
    if ($null -eq $cfg -or $cfg.PSObject.Properties.Match("skill_projection").Count -eq 0 -or $null -eq $cfg.skill_projection) {
        return [pscustomobject]@{ success = $true; persisted = $false; skipped = $true; plan = $null }
    }
    return (Sync-CodexSkillProjection $cfg.skill_projection)
}
