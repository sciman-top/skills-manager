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

function Get-SkillDiscoveryPortableCatalogPath($projectionCfg) {
    Need ($null -ne $projectionCfg) 'skill_projection 配置为空'
    $managedRoot = Resolve-SkillProjectionPath ([string]$projectionCfg.managed_source_path)
    $routerRoot = Join-Path $managedRoot 'capability-router'
    if (-not (Test-Path -LiteralPath (Join-Path $routerRoot 'SKILL.md') -PathType Leaf)) { return '' }
    return [IO.Path]::GetFullPath((Join-Path $routerRoot 'catalog.json'))
}

function Get-SkillDiscoverySideEffects($discoveryCfg) {
    $sideEffects = @{}
    if ($null -eq $discoveryCfg -or $discoveryCfg.PSObject.Properties.Match('side_effects').Count -eq 0 -or $null -eq $discoveryCfg.side_effects) {
        return $sideEffects
    }
    $raw = $discoveryCfg.side_effects
    Need ($raw -is [pscustomobject] -or $raw -is [System.Collections.IDictionary]) 'skill_projection.discovery_catalog.side_effects 必须是对象'
    $properties = if ($raw -is [System.Collections.IDictionary]) {
        @($raw.Keys | ForEach-Object { [pscustomobject]@{ Name = [string]$_; Value = $raw[$_] } })
    }
    else { @($raw.PSObject.Properties) }
    foreach ($property in $properties) {
        $name = ([string]$property.Name).Trim()
        $sideEffect = ([string]$property.Value).Trim().ToLowerInvariant()
        Need (-not [string]::IsNullOrWhiteSpace($name)) 'skill_projection.discovery_catalog.side_effects 不能包含空技能名'
        Need ($sideEffect -in @('read_only', 'external_read', 'controlled_write')) ("skill_projection.discovery_catalog.side_effects.{0} 必须声明受支持的副作用" -f $name)
        $sideEffects[$name] = $sideEffect
    }
    return $sideEffects
}

function Get-SkillDiscoveryDependencyMap() {
    $contractPath = Join-Path $Root 'config\skill-dependency-closure.json'
    Need (Test-Path -LiteralPath $contractPath -PathType Leaf) '冷发现依赖闭包合同缺失：config/skill-dependency-closure.json'
    try { $contract = Get-ContentUtf8 $contractPath | ConvertFrom-Json }
    catch { throw ('冷发现依赖闭包合同不是有效 JSON：{0}' -f $_.Exception.Message) }
    Need ($contract.schema_version -eq 1) '冷发现依赖闭包合同 schema_version 必须为 1'
    Need ($contract.PSObject.Properties.Match('dependencies').Count -gt 0 -and $contract.dependencies -is [System.Collections.IEnumerable]) '冷发现依赖闭包合同 dependencies 必须是数组'

    $dependencyMap = @{}
    foreach ($entry in @($contract.dependencies)) {
        $name = ([string]$entry.skill).Trim()
        $requires = @($entry.requires | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        Need (-not [string]::IsNullOrWhiteSpace($name)) '冷发现依赖闭包合同条目缺少 skill'
        Need (-not $dependencyMap.ContainsKey($name)) ("冷发现依赖闭包合同重复技能：{0}" -f $name)
        Need (@($requires | Sort-Object -Unique).Count -eq $requires.Count) ("冷发现依赖闭包合同存在重复依赖：{0}" -f $name)
        Need (-not ($requires -contains $name)) ("冷发现依赖闭包合同不允许自依赖：{0}" -f $name)
        $dependencyMap[$name] = @($requires | Sort-Object)
    }
    return $dependencyMap
}

function New-SkillDiscoveryCatalogDocument($projectionCfg) {
    Need ($null -ne $projectionCfg) 'skill_projection 配置为空'
    Need ($projectionCfg.PSObject.Properties.Match('managed_source_path').Count -gt 0) 'skill_projection 缺少 managed_source_path'
    $managedRoot = Resolve-SkillProjectionPath ([string]$projectionCfg.managed_source_path)
    Need (Test-Path -LiteralPath $managedRoot -PathType Container) ("受管技能源不存在：{0}" -f $managedRoot)

    $domainPurpose = [ordered]@{}
    $membership = @{}
    $sideEffects = @{}
    $dependencyMap = Get-SkillDiscoveryDependencyMap
    $fallbackDomain = 'other'
    $fallbackPurpose = 'Installed cold skills not assigned to a narrower domain; inspect only when no specific domain covers the request.'
    if ($projectionCfg.PSObject.Properties.Match('discovery_catalog').Count -gt 0 -and $null -ne $projectionCfg.discovery_catalog) {
        $discoveryCfg = $projectionCfg.discovery_catalog
        $sideEffects = Get-SkillDiscoverySideEffects $discoveryCfg
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
        $skills.Add([ordered]@{
                name = $name
                description = [string]$meta.description
                relative_path = $relativeFromCatalog
                entrypoint_sha256 = Get-FileContentHash ([string]$item.file)
                domains = @($membership[$name] | Sort-Object)
                load_side_effect = 'read_only'
                side_effect = if ($sideEffects.ContainsKey($name)) { [string]$sideEffects[$name] } else { 'unknown' }
                dependencies = if ($dependencyMap.ContainsKey($name)) { @($dependencyMap[$name]) } else { @() }
                routing_rules = @()
            }) | Out-Null
    }

    foreach ($configuredName in @($membership.Keys | Sort-Object)) {
        Need ($actualNames.Contains([string]$configuredName)) ("skill_projection.discovery_catalog.domain_memberships 引用了不存在的 canonical skill：{0}" -f $configuredName)
    }
    foreach ($configuredName in @($sideEffects.Keys | Sort-Object)) {
        Need ($actualNames.Contains([string]$configuredName)) ("skill_projection.discovery_catalog.side_effects 引用了不存在的 canonical skill：{0}" -f $configuredName)
    }
    foreach ($caller in @($dependencyMap.Keys | Sort-Object)) {
        if (-not $actualNames.Contains($caller)) { continue }
        foreach ($required in @($dependencyMap[$caller])) {
            Need ($actualNames.Contains($required)) ("冷发现依赖闭包合同依赖不存在于 canonical skill：{0} -> {1}" -f $caller, $required)
        }
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

function Sync-SkillDiscoveryCatalog($projectionCfg) {
    if ($null -eq $projectionCfg -or $projectionCfg.PSObject.Properties.Match('managed_source_path').Count -eq 0) {
        return [pscustomobject]@{ enabled = $false; reason = 'not_configured'; changed = $false; persisted = $false; path = ''; skill_count = 0; domain_count = 0 }
    }
    $catalogPath = Get-SkillDiscoveryCatalogPath $projectionCfg
    $portableCatalogPath = Get-SkillDiscoveryPortableCatalogPath $projectionCfg
    $catalog = New-SkillDiscoveryCatalogDocument $projectionCfg
    $desired = $catalog | ConvertTo-Json -Depth 20
    $existing = if (Test-Path -LiteralPath $catalogPath -PathType Leaf) { Get-ContentUtf8 $catalogPath } else { '' }
    $primaryChanged = -not [string]::Equals($existing.TrimEnd("`r", "`n"), $desired.TrimEnd("`r", "`n"), [System.StringComparison]::Ordinal)
    $portableExisting = if (-not [string]::IsNullOrWhiteSpace($portableCatalogPath) -and (Test-Path -LiteralPath $portableCatalogPath -PathType Leaf)) { Get-ContentUtf8 $portableCatalogPath } else { '' }
    $portableChanged = -not [string]::IsNullOrWhiteSpace($portableCatalogPath) -and -not [string]::Equals($portableExisting.TrimEnd("`r", "`n"), $desired.TrimEnd("`r", "`n"), [System.StringComparison]::Ordinal)
    if (-not $DryRun) {
        if ($primaryChanged) { Set-ContentUtf8 $catalogPath $desired }
        if ($portableChanged) { Set-ContentUtf8 $portableCatalogPath $desired }
    }
    return [pscustomobject]@{
        enabled = $true
        reason = 'ok'
        changed = ($primaryChanged -or $portableChanged)
        persisted = (-not $DryRun)
        path = $catalogPath
        portable_path = $portableCatalogPath
        skill_count = @($catalog.skills).Count
        domain_count = @($catalog.domains).Count
    }
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
    if ($projectionCfg.PSObject.Properties.Match("native_agent_bridge").Count -gt 0 -and $null -ne $projectionCfg.native_agent_bridge -and
        $projectionCfg.native_agent_bridge.PSObject.Properties.Match("target_root").Count -gt 0) {
        $nativeAgentTarget = Resolve-SkillProjectionPath ([string]$projectionCfg.native_agent_bridge.target_root)
        if (-not [string]::IsNullOrWhiteSpace($nativeAgentTarget) -and -not (Is-PathInsideOrEqual $nativeAgentTarget $repoRoot)) { return $true }
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
        $portableCatalogPath = Get-SkillDiscoveryPortableCatalogPath $projectionCfg
        if (-not [string]::IsNullOrWhiteSpace($portableCatalogPath)) { $filePaths.Add($portableCatalogPath) | Out-Null }
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
    $selection = Get-SkillProjectionEffectiveSelection $projectionCfg 'codex'
    $configRaw = if ($projectionCfg.PSObject.Properties.Match("codex_config_path").Count -gt 0) { [string]$projectionCfg.codex_config_path } else { "~/.codex/config.toml" }
    $manifestRaw = if ($projectionCfg.PSObject.Properties.Match("manifest_path").Count -gt 0) { [string]$projectionCfg.manifest_path } else { "reports/skill-projection/current.json" }
    $configPath = Resolve-SkillProjectionPath $configRaw
    $manifestPath = Resolve-SkillProjectionPath $manifestRaw
    $catalogProjection = Sync-SkillDiscoveryCatalog $projectionCfg
    $nativeProjectionPlan = $null
    $nativeProjectionFingerprintPlan = $null
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
        $nativeProjectionFingerprintPlan = $nativeProjectionPlan
        $nativeProjectionAuthoritative = $true
        if ($DryRun) {
            $nativeProjectionApply = [pscustomobject]@{ status = 'planned'; receipt_id = ''; receipt_path = [string]$nativeProjectionPlan.receipt_path; changed_names = @(); receipt = $null }
        }
        else {
            $nativeProjectionApply = Apply-NativeSkillProjection -Plan $nativeProjectionPlan
            # The apply plan can contain owned links that are removed while switching
            # profiles. Persist the post-apply steady state in the manifest
            # fingerprint so a fresh validation does not treat that successful
            # transition as source drift.
            $nativeProjectionFingerprintPlan = New-NativeSkillProjectionRuntimePlan -ManagedRoot $managedRoot -Config ([pscustomobject]@{ skill_projection = $projectionCfg }) -IncludedNames $includedNames -ExcludedNames $excludedNames
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
            $projectionFingerprint = Get-SkillProjectionPlanFingerprint $plan $nativeProjectionFingerprintPlan $selection
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
                projection_selection = [ordered]@{
                    host = [string](Get-OperationObjectProperty $selection 'host')
                    profile = [string](Get-OperationObjectProperty $selection 'profile')
                    include_all = [bool](Get-OperationObjectProperty $selection 'include_all')
                    included_names = @((Get-OperationObjectProperty $selection 'included_names') | ForEach-Object { [string]$_ } | Sort-Object)
                    excluded_names = @((Get-OperationObjectProperty $selection 'excluded_names') | ForEach-Object { [string]$_ } | Sort-Object)
                }
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
        selection = $selection
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

function Sync-ConfiguredSkillProjection($cfg, $promotionContext = $null, [string]$SkillProfile = '') {
    if ($null -eq $cfg -or $cfg.PSObject.Properties.Match("skill_projection").Count -eq 0 -or $null -eq $cfg.skill_projection) {
        return [pscustomobject]@{ success = $true; persisted = $false; skipped = $true; plan = $null }
    }
    $selection = Resolve-SkillProjectionSelection -ProjectionConfig $cfg.skill_projection -HostName codex -RequestedProfile $SkillProfile
    $projectionCfg = New-SkillProjectionHostConfig -ProjectionConfig $cfg.skill_projection -Selection $selection
    return (Sync-CodexSkillProjection $projectionCfg $promotionContext)
}
