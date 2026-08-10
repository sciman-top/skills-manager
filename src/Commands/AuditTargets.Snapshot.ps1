function ConvertFrom-AuditYamlBlockScalar($lines, [int]$startIndex, [int]$parentIndent, [string]$indicator) {
    $rawBlock = New-Object System.Collections.Generic.List[string]
    $contentIndent = [int]::MaxValue
    for ($index = $startIndex; $index -lt @($lines).Count; $index++) {
        $line = [string]$lines[$index]
        if ($line -match "^\s*---\s*$") { break }
        if ([string]::IsNullOrWhiteSpace($line)) {
            $rawBlock.Add("") | Out-Null
            continue
        }

        $indent = ([regex]::Match($line, "^\s*")).Value.Length
        if ($indent -le $parentIndent) { break }
        if ($indent -lt $contentIndent) { $contentIndent = $indent }
        $rawBlock.Add($line) | Out-Null
    }

    if ($rawBlock.Count -eq 0 -or $contentIndent -eq [int]::MaxValue) { return "" }
    $dedented = @($rawBlock | ForEach-Object {
            if ([string]::IsNullOrWhiteSpace([string]$_)) { "" }
            else { ([string]$_).Substring([Math]::Min($contentIndent, ([string]$_).Length)) }
        })
    $text = $dedented -join "`n"
    if ($indicator.StartsWith(">", [System.StringComparison]::Ordinal)) {
        $text = [regex]::Replace($text, "(?<!\n)\n(?!\n)", " ")
    }
    return $text.TrimEnd("`r", "`n")
}

function Get-SkillMetadataFromFile([string]$skillFile) {
    $meta = [ordered]@{
        declared_name = ""
        description = ""
        trigger_summary = ""
    }
    if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) {
        return [pscustomobject]$meta
    }

    $lines = @(Get-Content -LiteralPath $skillFile -TotalCount 120 -ErrorAction SilentlyContinue)
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = [string]$lines[$index]
        if ([string]::IsNullOrWhiteSpace($meta.declared_name) -and $line -match "^\s*name:\s*(.+?)\s*$") {
            $meta.declared_name = $Matches[1].Trim().Trim("'`"")
        }
        if ([string]::IsNullOrWhiteSpace($meta.description) -and $line -match "^\s*description:\s*(.+?)\s*$") {
            $descriptionValue = $Matches[1].Trim().Trim("'`"")
            if ($descriptionValue -match "^[>|][+-]?$") {
                $parentIndent = ([regex]::Match($line, "^\s*")).Value.Length
                $meta.description = ConvertFrom-AuditYamlBlockScalar $lines ($index + 1) $parentIndent $descriptionValue
            }
            else {
                $meta.description = $descriptionValue
            }
        }
        if ([string]::IsNullOrWhiteSpace($meta.trigger_summary) -and $line -match "(?i)trigger|use when|when to use|使用场景") {
            $meta.trigger_summary = $line.Trim()
        }
    }
    return [pscustomobject]$meta
}

function Resolve-InstalledSkillLocalPath($cfg, $mapping) {
    if ($null -eq $mapping) { return "" }
    $vendor = [string]$mapping.vendor
    $from = [string]$mapping.from
    if ($vendor -eq "manual") {
        $imp = @($cfg.imports | Where-Object { $_.name -eq $from } | Select-Object -First 1)
        if ($imp.Count -eq 0) { return (Join-Path $script:ImportDir $from) }
        $skillPath = Normalize-SkillPath ([string]$imp[0].skill)
        if ([string]::IsNullOrWhiteSpace($skillPath) -or $skillPath -eq ".") {
            return (Join-Path $script:ImportDir $from)
        }
        return (Join-Path (Join-Path $script:ImportDir $from) $skillPath)
    }
    if ($vendor -eq "overrides") {
        $override = Resolve-OverrideDir $from
        if ($null -ne $override -and @($override).Count -gt 0) {
            return [string]$override[0].FullName
        }
        return (Join-Path $script:OverridesDir $from)
    }
    return (Join-Path (VendorPath $vendor) $from)
}

function Get-InstalledSkillFacts($cfg = $null) {
    if ($null -eq $cfg) { $cfg = LoadCfg }
    $facts = @()
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($m in @($cfg.mappings)) {
        if ($null -eq $m) { continue }
        if (-not (Should-SyncMappingToAgent $m)) { continue }
        $vendor = [string]$m.vendor
        $from = [string]$m.from
        $to = [string]$m.to
        if (-not $seen.Add(("{0}|{1}" -f $vendor, $from))) { continue }
        $localPath = Resolve-InstalledSkillLocalPath $cfg $m
        $skillFile = Join-Path $localPath "SKILL.md"
        $meta = Get-SkillMetadataFromFile $skillFile
        $contentHash = [string](Get-FileContentHash $skillFile)

        $repo = ""
        $ref = ""
        $skillPath = $from
        if ($vendor -eq "manual") {
            $imp = @($cfg.imports | Where-Object { $_.name -eq $from } | Select-Object -First 1)
            if ($imp.Count -gt 0) {
                $repo = [string]$imp[0].repo
                $ref = [string]$imp[0].ref
                $skillPath = [string]$imp[0].skill
            }
        }
        elseif ($vendor -ne "overrides") {
            $v = @($cfg.vendors | Where-Object { $_.name -eq $vendor } | Select-Object -First 1)
            if ($v.Count -gt 0) {
                $repo = [string]$v[0].repo
                $ref = [string]$v[0].ref
            }
        }

        $facts += [pscustomobject]([ordered]@{
            name = if ([string]::IsNullOrWhiteSpace($meta.declared_name)) { $to } else { $meta.declared_name }
            source_kind = $vendor
            vendor = $vendor
            from = $from
            to = $to
            repo = $repo
            ref = $ref
            skill_path = $skillPath
            declared_name = $meta.declared_name
            description = $meta.description
            trigger_summary = $meta.trigger_summary
            content_hash = $contentHash
            local_path = $localPath
        })
    }
    foreach ($override in @(收集OverridesSkills)) {
        if ($null -eq $override) { continue }
        $from = [string]$override.from
        if ([string]::IsNullOrWhiteSpace($from)) { continue }
        if (-not $seen.Add(("overrides|{0}" -f $from))) { continue }
        $localPath = [string]$override.full
        $skillFile = Join-Path $localPath "SKILL.md"
        if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) { continue }
        $meta = Get-SkillMetadataFromFile $skillFile
        $contentHash = [string](Get-FileContentHash $skillFile)
        $facts += [pscustomobject]([ordered]@{
            name = if ([string]::IsNullOrWhiteSpace($meta.declared_name)) { $from } else { $meta.declared_name }
            source_kind = "overrides"
            vendor = "overrides"
            from = $from
            to = $from
            repo = ""
            ref = ""
            skill_path = $from
            declared_name = $meta.declared_name
            description = $meta.description
            trigger_summary = $meta.trigger_summary
            content_hash = $contentHash
            local_path = $localPath
        })
    }
    return @($facts)
}

function Get-AuditExternalSkillFacts($cfg = $null) {
    if ($null -eq $cfg) { $cfg = LoadCfg }
    if ($cfg.PSObject.Properties.Match('skill_projection').Count -eq 0 -or $null -eq $cfg.skill_projection) { return @() }
    $facts = New-Object System.Collections.Generic.List[object]
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $projection = $cfg.skill_projection
    $userSkillRootRaw = if ($projection.PSObject.Properties.Match('user_skill_root').Count -gt 0) { [string]$projection.user_skill_root } else { '~/.agents/skills' }
    $userSkillRoot = Resolve-SkillProjectionPath $userSkillRootRaw
    foreach ($item in @(Get-SkillProjectionFiles $userSkillRoot | Where-Object is_system)) {
        $skillFile = [string]$item.file
        $meta = Get-SkillMetadataFromFile $skillFile
        $name = [string]$meta.declared_name
        if ([string]::IsNullOrWhiteSpace($name) -or -not $seen.Add(('system::{0}' -f $name))) { continue }
        $facts.Add([pscustomobject]([ordered]@{
                    source_kind = 'system'
                    name = $name
                    qualified_name = $name
                    description = [string]$meta.description
                    trigger_summary = [string]$meta.trigger_summary
                    content_hash = [string](Get-FileContentHash $skillFile)
                    local_path = Split-Path -Parent $skillFile
                    plugin_id = ''
                })) | Out-Null
    }

    $inventory = Get-CodexExternalSkillInventory $projection
    foreach ($item in @($inventory.skills)) {
        $qualifiedName = [string]$item.qualified_name
        if ([string]::IsNullOrWhiteSpace($qualifiedName) -or -not $seen.Add(('plugin::{0}' -f $qualifiedName))) { continue }
        $facts.Add([pscustomobject]([ordered]@{
                    source_kind = 'plugin'
                    name = [string]$item.name
                    qualified_name = $qualifiedName
                    description = [string]$item.description
                    trigger_summary = [string]$item.description
                    content_hash = [string](Get-FileContentHash ([string]$item.path))
                    local_path = Split-Path -Parent ([string]$item.path)
                    plugin_id = [string]$item.plugin_id
                })) | Out-Null
    }
    return @($facts.ToArray() | Sort-Object source_kind, qualified_name)
}

function Get-AuditMcpServerFacts($cfg = $null) {
    if ($null -eq $cfg) { $cfg = LoadCfg }
    $facts = @()
    $servers = @(Resolve-McpProfileServers $cfg)
    foreach ($s in $servers) {
        if ($null -eq $s) { continue }
        $name = [string]$s.name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $transport = if ($s.PSObject.Properties.Match("transport").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$s.transport)) {
            ([string]$s.transport).Trim().ToLowerInvariant()
        }
        else {
            "stdio"
        }
        $row = [ordered]@{
            name = $name
            transport = $transport
            enabled = $true
        }
        if ($s.PSObject.Properties.Match("enabled").Count -gt 0) {
            Need ($s.enabled -is [bool]) ("mcp_server.enabled 必须是布尔值：{0}" -f $name)
            $row.enabled = [bool]$s.enabled
        }
        if ($s.PSObject.Properties.Match("enabled_tools").Count -gt 0 -and $null -ne $s.enabled_tools) {
            $enabledTools = @()
            foreach ($rawTool in @($s.enabled_tools)) {
                $tool = ([string]$rawTool).Trim()
                Need (-not [string]::IsNullOrWhiteSpace($tool)) ("mcp_server.enabled_tools 不得包含空值：{0}" -f $name)
                if ($enabledTools -notcontains $tool) { $enabledTools += $tool }
            }
            $row.enabled_tools = @($enabledTools | Sort-Object)
        }
        if ($transport -eq "stdio") {
            $row.command = if ($s.PSObject.Properties.Match("command").Count -gt 0) { [string]$s.command } else { "" }
            $row.args = if ($s.PSObject.Properties.Match("args").Count -gt 0 -and $null -ne $s.args) { @($s.args) } else { @() }
            $envKeys = @()
            if ($s.PSObject.Properties.Match("env").Count -gt 0 -and $null -ne $s.env) {
                if ($s.env -is [hashtable] -or $s.env -is [System.Collections.IDictionary]) {
                    $envKeys = @($s.env.Keys | ForEach-Object { [string]$_ } | Sort-Object)
                }
                else {
                    $envKeys = @($s.env.PSObject.Properties.Name | ForEach-Object { [string]$_ } | Sort-Object)
                }
            }
            $row.env_keys = @($envKeys)
        }
        else {
            $row.url = if ($s.PSObject.Properties.Match("url").Count -gt 0) { [string]$s.url } else { "" }
            $headerKeys = @()
            if ($s.PSObject.Properties.Match("headers").Count -gt 0 -and $null -ne $s.headers) {
                if ($s.headers -is [hashtable] -or $s.headers -is [System.Collections.IDictionary]) {
                    $headerKeys = @($s.headers.Keys | ForEach-Object { [string]$_ } | Sort-Object)
                }
                else {
                    $headerKeys = @($s.headers.PSObject.Properties.Name | ForEach-Object { [string]$_ } | Sort-Object)
                }
            }
            $row.header_keys = @($headerKeys)
            $row.bearer_token_env_var = if ($s.PSObject.Properties.Match("bearer_token_env_var").Count -gt 0) { [string]$s.bearer_token_env_var } else { "" }
        }
        $facts += [pscustomobject]$row
    }
    return @($facts)
}

function Get-AuditFingerprintFromMcpServers($servers) {
    $pairs = @()
    foreach ($server in @($servers)) {
        if ($null -eq $server) { continue }
        $name = ""
        if ($server.PSObject.Properties.Match("name").Count -gt 0) {
            $name = ([string]$server.name).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $sig = Get-McpServerSignature $server
        if ([string]::IsNullOrWhiteSpace($sig)) { continue }
        $pairs += ("{0}|{1}" -f $name, $sig)
    }
    return (Get-AuditFingerprintFromVendorFromPairs $pairs)
}

function Get-AuditFingerprintFromVendorFromPairs($pairs, [bool]$caseSensitive = $false) {
    $comparer = if ($caseSensitive) { [System.StringComparer]::Ordinal } else { [System.StringComparer]::OrdinalIgnoreCase }
    $normalized = New-Object System.Collections.Generic.HashSet[string]($comparer)
    foreach ($pair in @($pairs)) {
        if ($null -eq $pair) { continue }
        $text = ([string]$pair).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if (-not $caseSensitive) { $text = $text.ToLowerInvariant() }
        $normalized.Add($text) | Out-Null
    }
    [string[]]$ordered = @($normalized)
    [System.Array]::Sort($ordered, [System.StringComparer]::Ordinal)
    $payload = ($ordered -join "`n")
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        $hashBytes = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hashBytes)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-AuditFingerprintFromSkillFacts($facts) {
    $rows = @()
    $fields = @(
        "vendor",
        "from",
        "to",
        "repo",
        "ref",
        "skill_path",
        "declared_name",
        "description",
        "trigger_summary",
        "content_hash"
    )
    foreach ($item in @($facts)) {
        if ($null -eq $item) { continue }
        $vendor = ""
        $from = ""
        if ($item.PSObject.Properties.Match("vendor").Count -gt 0) { $vendor = [string]$item.vendor }
        if ($item.PSObject.Properties.Match("from").Count -gt 0) { $from = [string]$item.from }
        if ([string]::IsNullOrWhiteSpace($vendor) -or [string]::IsNullOrWhiteSpace($from)) { continue }

        $row = [ordered]@{}
        foreach ($field in $fields) {
            $value = ""
            if ($item.PSObject.Properties.Match($field).Count -gt 0 -and $null -ne $item.$field) {
                $value = [string]$item.$field
            }
            $row[$field] = $value
        }
        $rows += ($row | ConvertTo-Json -Compress)
    }
    return (Get-AuditFingerprintFromVendorFromPairs $rows $true)
}

function Get-AuditFingerprintFromExternalSkillFacts($facts) {
    $rows = @()
    foreach ($item in @($facts)) {
        if ($null -eq $item) { continue }
        $row = [ordered]@{
            source_kind = [string]$item.source_kind
            name = [string]$item.name
            qualified_name = [string]$item.qualified_name
            description = [string]$item.description
            trigger_summary = [string]$item.trigger_summary
            content_hash = [string]$item.content_hash
            plugin_id = [string]$item.plugin_id
        }
        $rows += ($row | ConvertTo-Json -Compress)
    }
    return (Get-AuditFingerprintFromVendorFromPairs $rows $true)
}

function Get-AuditHostProjectionState($cfg) {
    $projection = if ($null -ne $cfg -and $cfg.PSObject.Properties.Match('skill_projection').Count -gt 0) { $cfg.skill_projection } else { $null }
    if ($null -eq $projection -or $projection.PSObject.Properties.Match('managed_source_path').Count -eq 0 -or $projection.PSObject.Properties.Match('user_skill_root').Count -eq 0) {
        return [pscustomobject]([ordered]@{ status = 'not_provided'; managed_count = 0; broken_count = 0; stale_count = 0; fingerprint = '' })
    }
    try {
        $managedRoot = Resolve-SkillProjectionPath ([string]$projection.managed_source_path)
        $userRoot = Resolve-SkillProjectionPath ([string]$projection.user_skill_root)
        if (-not (Test-Path -LiteralPath $managedRoot -PathType Container) -or -not (Test-Path -LiteralPath $userRoot -PathType Container)) {
            return [pscustomobject]([ordered]@{ status = 'unavailable'; managed_count = 0; broken_count = 0; stale_count = 0; fingerprint = '' })
        }
        $excluded = @($projection.managed_link_excludes | ForEach-Object { [string]$_ })
        $expected = @(Get-ChildItem -LiteralPath $managedRoot -Directory -Force | Where-Object { $_.Name -ne '.system' -and $_.Name -notin $excluded -and (Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf) } | ForEach-Object Name)
        $rows = @(); $managedCount = 0; $brokenCount = 0; $staleCount = 0
        foreach ($entry in @(Get-ChildItem -LiteralPath $userRoot -Directory -Force -ErrorAction SilentlyContinue | Where-Object Name -ne '.system')) {
            if (-not (Is-ReparsePoint $entry.FullName)) { continue }
            $target = Get-ReparsePointTargetFullPath $entry.FullName
            if ([string]::IsNullOrWhiteSpace($target)) { $brokenCount++; continue }
            $managedPrefix = $managedRoot.TrimEnd('\') + '\'
            if ($target.StartsWith($managedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $managedCount++
                if ($entry.Name -notin $expected -or -not (Test-Path -LiteralPath $target -PathType Container)) { $staleCount++ }
                $rows += (([ordered]@{ name = $entry.Name; target = $target }) | ConvertTo-Json -Compress)
            }
        }
        foreach ($name in $expected) { if (-not (Test-Path -LiteralPath (Join-Path $userRoot $name))) { $staleCount++ } }
        return [pscustomobject]([ordered]@{ status = 'available'; managed_count = $managedCount; broken_count = $brokenCount; stale_count = $staleCount; fingerprint = (Get-AuditFingerprintFromVendorFromPairs $rows $true) })
    } catch { return [pscustomobject]([ordered]@{ status = 'unavailable'; managed_count = 0; broken_count = 0; stale_count = 0; fingerprint = '' }) }
}

function Get-AuditLiveInstalledState($cfg = $null) {
    if ($null -eq $cfg) { $cfg = LoadCfg }
    $facts = @(Get-InstalledSkillFacts $cfg)
    $externalFacts = @(Get-AuditExternalSkillFacts $cfg)
    $mcpServers = @()
    if ($cfg.PSObject.Properties.Match("mcp_servers").Count -gt 0 -and $null -ne $cfg.mcp_servers) {
        $mcpServers = @($cfg.mcp_servers)
    }
    return [pscustomobject]([ordered]@{
        source_of_truth = "live_mappings"
        captured_at = (Get-Date).ToString("o")
        skill_count = @($facts).Count
        fingerprint = (Get-AuditFingerprintFromSkillFacts $facts)
        external_skill_count = @($externalFacts).Count
        external_skill_fingerprint = (Get-AuditFingerprintFromExternalSkillFacts $externalFacts)
        mcp_server_count = @($mcpServers).Count
        mcp_fingerprint = (Get-AuditFingerprintFromMcpServers $mcpServers)
        host_projection = (Get-AuditHostProjectionState $cfg)
    })
}

function New-AuditInstalledFactsFallbackCfg {
    return [pscustomobject]([ordered]@{
        vendors = @()
        targets = @()
        mappings = @()
        imports = @()
        mcp_servers = @()
        mcp_targets = @()
        update_force = $false
        sync_mode = "sync"
    })
}

function Get-AuditInstalledSnapshotState([string]$snapshotPath) {
    Need (-not [string]::IsNullOrWhiteSpace($snapshotPath)) "installed-skills 快照路径不能为空"
    Need (Test-Path -LiteralPath $snapshotPath -PathType Leaf) ("缺少 installed-skills 快照：{0}" -f $snapshotPath)
    try {
        $raw = Get-ContentUtf8 $snapshotPath
        Need (-not [string]::IsNullOrWhiteSpace($raw)) ("installed-skills 快照为空：{0}" -f $snapshotPath)
        $data = $raw | ConvertFrom-Json
    }
    catch {
        throw ("installed-skills 快照解析失败：{0}" -f $_.Exception.Message)
    }
    Need (Test-AuditJsonProperty $data "skills") ("installed-skills 快照缺少 skills：{0}" -f $snapshotPath)
    Need (Assert-IsArray $data.skills) ("installed-skills.skills 必须为数组：{0}" -f $snapshotPath)
    $skills = @($data.skills)
    $externalSkills = @()
    if (Test-AuditJsonProperty $data 'external_skills' -and $null -ne $data.external_skills) {
        Need (Assert-IsArray $data.external_skills) ("installed-skills.external_skills 必须为数组：{0}" -f $snapshotPath)
        $externalSkills = @($data.external_skills)
    }
    $mcpServers = @()
    if (Test-AuditJsonProperty $data "mcp_servers" -and $null -ne $data.mcp_servers) {
        Need (Assert-IsArray $data.mcp_servers) ("installed-skills.mcp_servers 必须为数组：{0}" -f $snapshotPath)
        $mcpServers = @($data.mcp_servers)
    }
    $fingerprint = ""
    if (Test-AuditJsonProperty $data "live_fingerprint") {
        $fingerprint = ([string]$data.live_fingerprint).Trim().ToLowerInvariant()
    }
    if ([string]::IsNullOrWhiteSpace($fingerprint)) {
        $fingerprint = (Get-AuditFingerprintFromSkillFacts $skills)
    }
    $externalSkillFingerprint = ''
    if (Test-AuditJsonProperty $data 'live_external_skill_fingerprint') {
        $externalSkillFingerprint = ([string]$data.live_external_skill_fingerprint).Trim().ToLowerInvariant()
    }
    if ([string]::IsNullOrWhiteSpace($externalSkillFingerprint) -and $externalSkills.Count -gt 0) {
        $externalSkillFingerprint = Get-AuditFingerprintFromExternalSkillFacts $externalSkills
    }
    $mcpFingerprint = ""
    if (Test-AuditJsonProperty $data "live_mcp_fingerprint") {
        $mcpFingerprint = ([string]$data.live_mcp_fingerprint).Trim().ToLowerInvariant()
    }
    if ([string]::IsNullOrWhiteSpace($mcpFingerprint) -and @($mcpServers).Count -gt 0) {
        $mcpFingerprint = (Get-AuditFingerprintFromMcpServers $mcpServers)
    }
    $hostProjection = if (Test-AuditJsonProperty $data 'host_projection') { $data.host_projection } else { $null }
    $capturedAt = ""
    if (Test-AuditJsonProperty $data "captured_at") { $capturedAt = [string]$data.captured_at }
    $snapshotKind = ""
    if (Test-AuditJsonProperty $data "snapshot_kind") { $snapshotKind = [string]$data.snapshot_kind }
    return [pscustomobject]([ordered]@{
        path = $snapshotPath
        snapshot_kind = $snapshotKind
        captured_at = $capturedAt
        skill_count = $skills.Count
        fingerprint = $fingerprint
        external_skill_count = $externalSkills.Count
        external_skill_fingerprint = $externalSkillFingerprint
        mcp_server_count = @($mcpServers).Count
        mcp_fingerprint = $mcpFingerprint
        host_projection = $hostProjection
    })
}

function New-AuditInstalledSnapshotFallbackState($liveState, [string]$snapshotPath) {
    return [pscustomobject]([ordered]@{
        path = $snapshotPath
        snapshot_kind = "legacy_live_fallback"
        captured_at = [string]$liveState.captured_at
        skill_count = [int]$liveState.skill_count
        fingerprint = [string]$liveState.fingerprint
        external_skill_count = if ($liveState.PSObject.Properties.Match('external_skill_count').Count -gt 0) { [int]$liveState.external_skill_count } else { 0 }
        external_skill_fingerprint = if ($liveState.PSObject.Properties.Match('external_skill_fingerprint').Count -gt 0) { [string]$liveState.external_skill_fingerprint } else { '' }
        mcp_server_count = if ($liveState.PSObject.Properties.Match("mcp_server_count").Count -gt 0) { [int]$liveState.mcp_server_count } else { 0 }
        mcp_fingerprint = if ($liveState.PSObject.Properties.Match("mcp_fingerprint").Count -gt 0) { [string]$liveState.mcp_fingerprint } else { "" }
        host_projection = if ($liveState.PSObject.Properties.Match('host_projection').Count -gt 0) { $liveState.host_projection } else { $null }
    })
}

function Get-AuditInstalledSnapshotStaleness($snapshotState, $liveState) {
    $skillStale = ([string]$snapshotState.fingerprint -ne [string]$liveState.fingerprint)
    $mcpStale = $false
    if ($snapshotState.PSObject.Properties.Match('mcp_fingerprint').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$snapshotState.mcp_fingerprint)) {
        $mcpStale = ([string]$snapshotState.mcp_fingerprint -ne [string]$liveState.mcp_fingerprint)
    }
    $externalSkillStale = $false
    if ($snapshotState.PSObject.Properties.Match('external_skill_fingerprint').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$snapshotState.external_skill_fingerprint)) {
        $externalSkillStale = ([string]$snapshotState.external_skill_fingerprint -ne [string]$liveState.external_skill_fingerprint)
    }
    $hostStale = $false
    if ($snapshotState.PSObject.Properties.Match('host_projection').Count -gt 0 -and $null -ne $snapshotState.host_projection -and $liveState.PSObject.Properties.Match('host_projection').Count -gt 0) {
        $snapshotHost = $snapshotState.host_projection; $liveHost = $liveState.host_projection
        if ([string]$snapshotHost.status -eq 'available' -and [string]$liveHost.status -eq 'available') {
            $hostStale = ([string]$snapshotHost.fingerprint -ne [string]$liveHost.fingerprint -or [int]$liveHost.stale_count -gt 0 -or [int]$liveHost.broken_count -gt 0)
        }
    }
    return [pscustomobject]([ordered]@{
            is_stale = ($skillStale -or $mcpStale -or $externalSkillStale -or $hostStale)
            skill_stale = $skillStale
            mcp_stale = $mcpStale
            external_skill_stale = $externalSkillStale
            host_projection_stale = $hostStale
        })
}
