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
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($meta.declared_name) -and $line -match "^\s*name:\s*(.+?)\s*$") {
            $meta.declared_name = $Matches[1].Trim().Trim("'`"")
        }
        if ([string]::IsNullOrWhiteSpace($meta.description) -and $line -match "^\s*description:\s*(.+?)\s*$") {
            $meta.description = $Matches[1].Trim().Trim("'`"")
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
        return (Join-Path $script:OverridesDir $from)
    }
    return (Join-Path (VendorPath $vendor) $from)
}

function Get-InstalledSkillFacts($cfg = $null) {
    if ($null -eq $cfg) { $cfg = LoadCfg }
    $facts = @()
    foreach ($m in @($cfg.mappings)) {
        if ($null -eq $m) { continue }
        if (-not (Should-SyncMappingToAgent $m)) { continue }
        $vendor = [string]$m.vendor
        $from = [string]$m.from
        $to = [string]$m.to
        $localPath = Resolve-InstalledSkillLocalPath $cfg $m
        $skillFile = Join-Path $localPath "SKILL.md"
        $meta = Get-SkillMetadataFromFile $skillFile

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
            local_path = $localPath
        })
    }
    return @($facts)
}

function Get-AuditFingerprintFromVendorFromPairs($pairs) {
    $normalized = New-Object System.Collections.Generic.List[string]
    foreach ($pair in @($pairs)) {
        if ($null -eq $pair) { continue }
        $text = ([string]$pair).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $normalized.Add($text.ToLowerInvariant()) | Out-Null
    }
    $ordered = @($normalized | Sort-Object -Unique)
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
    $pairs = @()
    foreach ($item in @($facts)) {
        if ($null -eq $item) { continue }
        $vendor = ""
        $from = ""
        if ($item.PSObject.Properties.Match("vendor").Count -gt 0) { $vendor = [string]$item.vendor }
        if ($item.PSObject.Properties.Match("from").Count -gt 0) { $from = [string]$item.from }
        if ([string]::IsNullOrWhiteSpace($vendor) -or [string]::IsNullOrWhiteSpace($from)) { continue }
        $pairs += ("{0}|{1}" -f $vendor, $from)
    }
    return (Get-AuditFingerprintFromVendorFromPairs $pairs)
}

function Get-AuditLiveInstalledState($cfg = $null) {
    if ($null -eq $cfg) { $cfg = LoadCfg }
    $facts = @(Get-InstalledSkillFacts $cfg)
    return [pscustomobject]([ordered]@{
        source_of_truth = "live_mappings"
        captured_at = (Get-Date).ToString("o")
        skill_count = @($facts).Count
        fingerprint = (Get-AuditFingerprintFromSkillFacts $facts)
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
    $fingerprint = ""
    if (Test-AuditJsonProperty $data "live_fingerprint") {
        $fingerprint = ([string]$data.live_fingerprint).Trim().ToLowerInvariant()
    }
    if ([string]::IsNullOrWhiteSpace($fingerprint)) {
        $fingerprint = (Get-AuditFingerprintFromSkillFacts $skills)
    }
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
    })
}

function New-AuditInstalledSnapshotFallbackState($liveState, [string]$snapshotPath) {
    return [pscustomobject]([ordered]@{
        path = $snapshotPath
        snapshot_kind = "legacy_live_fallback"
        captured_at = [string]$liveState.captured_at
        skill_count = [int]$liveState.skill_count
        fingerprint = [string]$liveState.fingerprint
    })
}
