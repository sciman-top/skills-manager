function Get-CfgCountSnapshot($cfg) {
    if ($null -eq $cfg) { return @{} }
    return [ordered]@{
        vendors = @($cfg.vendors).Count
        targets = @($cfg.targets).Count
        mappings = @($cfg.mappings).Count
        imports = @($cfg.imports).Count
        mcp_servers = @($cfg.mcp_servers).Count
        mcp_targets = @($cfg.mcp_targets).Count
    }
}
function Get-CfgChangeSummaryLines([string]$oldRaw, $newCfg) {
    $keys = @("vendors", "targets", "mappings", "imports", "mcp_servers", "mcp_targets")
    $newSnap = Get-CfgCountSnapshot $newCfg
    $oldSnap = [ordered]@{}
    foreach ($k in $keys) { $oldSnap[$k] = 0 }

    if (-not [string]::IsNullOrWhiteSpace($oldRaw)) {
        try {
            $clean = $oldRaw -replace "(?m)^\s*//.*", ""
            $oldCfg = $clean | ConvertFrom-Json
            $oldSnap = Get-CfgCountSnapshot $oldCfg
        }
        catch {}
    }

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($k in $keys) {
        $oldVal = if ($oldSnap.Contains($k)) { [int]$oldSnap[$k] } else { 0 }
        $newVal = if ($newSnap.Contains($k)) { [int]$newSnap[$k] } else { 0 }
        if ($oldVal -ne $newVal) {
            $lines.Add(("{0}: {1} -> {2}" -f $k, $oldVal, $newVal)) | Out-Null
        }
    }
    return $lines.ToArray()
}
function Write-CfgChangeSummary([string]$oldRaw, $newCfg) {
    $lines = Get-CfgChangeSummaryLines $oldRaw $newCfg
    if ($lines.Count -eq 0) { return }
    Write-Host "配置变更摘要："
    foreach ($l in $lines) { Write-Host ("- {0}" -f $l) }
}
function Get-DirtyUpdateTargets($cfg) {
    $items = New-Object System.Collections.Generic.List[object]
    if ($null -eq $cfg) { return @() }

    foreach ($v in @($cfg.vendors)) {
        $path = VendorPath $v.name
        if (-not (Test-Path $path)) { continue }
        Push-Location $path
        try {
            if (Has-GitChanges) {
                $items.Add([pscustomobject]@{ kind = "vendor"; name = [string]$v.name; path = $path }) | Out-Null
            }
        }
        finally { Pop-Location }
    }
    foreach ($i in @($cfg.imports)) {
        if ($i.mode -ne "manual") { continue }
        $cache = Join-Path $ImportDir $i.name
        if (-not (Test-Path $cache)) { continue }
        Push-Location $cache
        try {
            if (Has-GitChanges) {
                $items.Add([pscustomobject]@{ kind = "import"; name = [string]$i.name; path = $cache }) | Out-Null
            }
        }
        finally { Pop-Location }
    }
    return $items.ToArray()
}
function Confirm-UpdateForce($cfg, [ref]$SkipForceClean) {
    if ($null -eq $SkipForceClean.Value) { $SkipForceClean.Value = @{} }
    if (-not $cfg.update_force) { return $true }
    if (-not (Confirm-Action "更新将逐项确认是否丢弃本地改动，继续吗？" "Y" -DefaultNo)) {
        Write-Host "已取消更新。"
        return $false
    }

    $dirty = Get-DirtyUpdateTargets $cfg
    if ($dirty.Count -eq 0) {
        Write-Host "未检测到 vendor/imports 本地改动，将按默认策略更新。"
        return $true
    }

    Write-Host ("检测到 {0} 个本地改动项，将逐项确认：" -f $dirty.Count)
    foreach ($d in $dirty) {
        $key = "{0}|{1}" -f $d.kind, $d.name
        $label = "{0}/{1}" -f $d.kind, $d.name
        if (Confirm-Action ("是否在更新时丢弃该项改动：{0}" -f $label) "Y" -DefaultNo) {
            continue
        }
        $SkipForceClean.Value[$key] = $true
        Write-Host ("将保留本地改动并跳过强制清理：{0}" -f $label) -ForegroundColor Yellow
    }
    return $true
}

function LoadCfg() {
    Need (Test-Path $CfgPath) "缺少配置文件：$CfgPath"
    $raw = Get-Content $CfgPath -Raw
    # 保守注释支持：仅移除整行 // 注释，避免误伤字符串内容。
    $clean = $raw -replace "(?m)^\s*//.*", ""
    try {
        $cfg = $clean | ConvertFrom-Json
    }
    catch {
        throw ("skills.json 解析失败：{0}。请检查 JSON 格式；注释仅支持整行 //。" -f $_.Exception.Message)
    }
    Need ($cfg.vendors -ne $null) "skills.json 缺少 vendors"
    Need ($cfg.targets -ne $null) "skills.json 缺少 targets"
    $cfg = Normalize-Cfg $cfg
    $changed = $false
    $dirMigrations = [ordered]@{
        vendors = @()
        imports = @()
    }
    Normalize-ArrayField $cfg "vendors" ([ref]$changed)
    Normalize-ArrayField $cfg "targets" ([ref]$changed)
    Normalize-ArrayField $cfg "mappings" ([ref]$changed)
    Normalize-ArrayField $cfg "imports" ([ref]$changed)
    Normalize-ArrayField $cfg "mcp_servers" ([ref]$changed)
    Normalize-ArrayField $cfg "mcp_targets" ([ref]$changed)
    Fix-Cfg $cfg ([ref]$changed) ([ref]$dirMigrations)
    Assert-Cfg $cfg
    Apply-DirectoryMigrations $dirMigrations ([ref]$changed)
    if ($changed) {
        Log "已自动修复 skills.json 中的无效项/重复项。" "WARN"
        SaveCfgSafe $cfg $raw
    }
    return $cfg
}
function Normalize-Cfg($cfg) {
    if (-not $cfg.PSObject.Properties.Match("mappings").Count) { $cfg | Add-Member -NotePropertyName mappings -NotePropertyValue @() }
    if (-not $cfg.PSObject.Properties.Match("imports").Count) { $cfg | Add-Member -NotePropertyName imports -NotePropertyValue @() }
    if (-not $cfg.PSObject.Properties.Match("mcp_servers").Count) { $cfg | Add-Member -NotePropertyName mcp_servers -NotePropertyValue @() }
    if (-not $cfg.PSObject.Properties.Match("mcp_targets").Count) { $cfg | Add-Member -NotePropertyName mcp_targets -NotePropertyValue @() }
    if (-not $cfg.PSObject.Properties.Match("update_force").Count) { $cfg | Add-Member -NotePropertyName update_force -NotePropertyValue $true }
    if ($cfg.mappings -eq $null) { $cfg.mappings = @() }
    if ($cfg.imports -eq $null) { $cfg.imports = @() }
    if ($cfg.mcp_servers -eq $null) { $cfg.mcp_servers = @() }
    if ($cfg.mcp_targets -eq $null) { $cfg.mcp_targets = @() }
    if ($cfg.update_force -eq $null) { $cfg.update_force = $true }
    if ([string]::IsNullOrWhiteSpace($cfg.sync_mode)) { $cfg.sync_mode = "link" }
    return $cfg
}
function Normalize-ArrayField($cfg, [string]$name, [ref]$changed) {
    if (-not $cfg.PSObject.Properties.Match($name).Count) {
        $cfg | Add-Member -NotePropertyName $name -NotePropertyValue @()
        $changed.Value = $true
        Log ("缺少 {0}，已自动补为空数组。" -f $name) "WARN"
        return
    }
    $val = $cfg.$name
    if ($null -eq $val) {
        $cfg.$name = @()
        $changed.Value = $true
        Log ("{0} 为空，已自动补为空数组。" -f $name) "WARN"
        return
    }
    if (Assert-IsArray $val) { return }
    if ($val -is [hashtable] -or $val -is [pscustomobject]) {
        $cfg.$name = @($val)
        $changed.Value = $true
        Log ("{0} 非数组，已自动包裹为数组。" -f $name) "WARN"
        return
    }
    throw ("skills.json 的 {0} 必须是数组" -f $name)
}
function Assert-IsArray($value) {
    return ($value -is [System.Collections.IList]) -and -not ($value -is [string])
}
function Get-DuplicateValues([object[]]$items) {
    if ($null -eq $items) { return @() }
    return $items | Group-Object | Where-Object { $_.Count -gt 1 } | Select-Object -ExpandProperty Name
}
function Migrate-DirName([string]$baseDir, [string]$oldName, [string]$newName, [string]$label, [ref]$changed) {
    if ([string]::IsNullOrWhiteSpace($oldName) -or [string]::IsNullOrWhiteSpace($newName)) { return }
    if ($oldName -eq $newName) { return }
    $src = Join-Path $baseDir $oldName
    if (-not (Test-Path $src)) { return }
    $dst = Join-Path $baseDir $newName
    if (Test-Path $dst) {
        Log ("{0} 目录迁移跳过：目标已存在 {1}" -f $label, $dst) "WARN"
        return
    }
    Invoke-MoveItem $src $dst
    Log ("{0} 目录已迁移：{1} -> {2}" -f $label, $oldName, $newName) "WARN"
    $changed.Value = $true
}
function Apply-DirectoryMigrations($dirMigrations, [ref]$changed) {
    if ($null -eq $dirMigrations) { return }
    $seen = New-Object System.Collections.Generic.HashSet[string]

    foreach ($v in $dirMigrations.vendors) {
        $key = ("vendor|{0}|{1}" -f $v.old, $v.new)
        if (-not $seen.Add($key)) { continue }
        Migrate-DirName $VendorDir $v.old $v.new "vendor" ([ref]$changed)
    }
    foreach ($i in $dirMigrations.imports) {
        $cacheKey = ("import-cache|{0}|{1}" -f $i.old, $i.new)
        if ($seen.Add($cacheKey)) {
            Migrate-DirName $ImportDir $i.old $i.new "import 缓存" ([ref]$changed)
        }
        if ($i.mode -eq "manual") {
            $manualKey = ("manual|{0}|{1}" -f $i.old, $i.new)
            if ($seen.Add($manualKey)) {
                Migrate-DirName $ManualDir $i.old $i.new "manual 技能" ([ref]$changed)
            }
        }
    }
}
function Fix-Cfg($cfg, [ref]$changed, [ref]$dirMigrations) {
    if ($null -eq $dirMigrations.Value) {
        $dirMigrations.Value = [ordered]@{ vendors = @(); imports = @() }
    }
    $vendorRenameMap = @{}
    foreach ($v in $cfg.vendors) {
        $old = [string]$v.name
        $new = Normalize-Name $old
        Need (-not [string]::IsNullOrWhiteSpace($new)) ("vendor 名称无法规范化：{0}" -f $old)
        if ($old -ne $new) {
            Log ("vendor 名称已自动规范化：{0} -> {1}" -f $old, $new) "WARN"
            $v.name = $new
            $dirMigrations.Value.vendors += [pscustomobject]@{ old = $old; new = $new }
            $changed.Value = $true
        }
        $vendorRenameMap[$old] = $new
    }

    foreach ($i in $cfg.imports) {
        if ($null -eq $i.name) { continue }
        $oldImport = [string]$i.name
        $newImport = Normalize-Name $oldImport
        Need (-not [string]::IsNullOrWhiteSpace($newImport)) ("import 名称无法规范化：{0}" -f $oldImport)
        if ($i.PSObject.Properties.Match("mode").Count -gt 0 -and $i.mode -eq "vendor") {
            if ($vendorRenameMap.ContainsKey($oldImport)) { $newImport = $vendorRenameMap[$oldImport] }
        }
        if ($oldImport -ne $newImport) {
            Log ("import 名称已自动规范化：{0} -> {1}" -f $oldImport, $newImport) "WARN"
            $i.name = $newImport
            $mode = if ($i.PSObject.Properties.Match("mode").Count -gt 0) { [string]$i.mode } else { "manual" }
            $dirMigrations.Value.imports += [pscustomobject]@{ old = $oldImport; new = $newImport; mode = $mode }
            $changed.Value = $true
        }
    }

    foreach ($m in $cfg.mappings) {
        if ($null -eq $m.vendor) { continue }
        $oldVendor = [string]$m.vendor
        $newVendor = $oldVendor
        if ($oldVendor.ToLowerInvariant() -eq "manual") {
            $newVendor = "manual"
        }
        else {
            $normVendor = Normalize-Name $oldVendor
            Need (-not [string]::IsNullOrWhiteSpace($normVendor)) ("mapping.vendor 无法规范化：{0}" -f $oldVendor)
            $newVendor = $normVendor
            if ($vendorRenameMap.ContainsKey($oldVendor)) { $newVendor = $vendorRenameMap[$oldVendor] }
        }
        if ($oldVendor -ne $newVendor) {
            Log ("mapping.vendor 已自动规范化：{0} -> {1}" -f $oldVendor, $newVendor) "WARN"
            $m.vendor = $newVendor
            $changed.Value = $true
        }
    }

    if (($cfg.sync_mode -ne "link") -and ($cfg.sync_mode -ne "sync")) {
        Log ("sync_mode 无效，已重置为 link：{0}" -f $cfg.sync_mode) "WARN"
        $cfg.sync_mode = "link"
        $changed.Value = $true
    }

    $dedupVendors = @()
    $seenVendors = New-Object System.Collections.Generic.HashSet[string]
    foreach ($v in $cfg.vendors) {
        if ($seenVendors.Add($v.name)) {
            $dedupVendors += $v
        }
        else {
            Log ("发现重复 vendor，已移除：{0}" -f $v.name) "WARN"
            $changed.Value = $true
        }
    }
    $cfg.vendors = $dedupVendors

    Repair-VendorImports $cfg $changed

    $dedupImports = @()
    $seenImports = New-Object System.Collections.Generic.HashSet[string]
    foreach ($i in $cfg.imports) {
        if ($seenImports.Add($i.name)) {
            if ($i.PSObject.Properties.Match("mode").Count -gt 0) {
                if ($i.mode -ne "manual" -and $i.mode -ne "vendor") {
                    Log ("import mode 无效，已改为 manual：{0}" -f $i.name) "WARN"
                    $i.mode = "manual"
                    $changed.Value = $true
                }
            }
            $dedupImports += $i
        }
        else {
            Log ("发现重复 import，已移除：{0}" -f $i.name) "WARN"
            $changed.Value = $true
        }
    }
    $cfg.imports = $dedupImports

    $dedupTargets = @()
    $seenTargets = New-Object System.Collections.Generic.HashSet[string]
    foreach ($t in $cfg.targets) {
        if ($seenTargets.Add($t.path)) {
            $dedupTargets += $t
        }
        else {
            Log ("发现重复 target，已移除：{0}" -f $t.path) "WARN"
            $changed.Value = $true
        }
    }
    $cfg.targets = $dedupTargets

    $dedupMcpServers = @()
    $seenMcpServers = New-Object System.Collections.Generic.HashSet[string]
    foreach ($s in $cfg.mcp_servers) {
        if ($null -eq $s) { continue }
        $rawName = [string]$s.name
        $normName = Normalize-Name $rawName
        Need (-not [string]::IsNullOrWhiteSpace($normName)) ("mcp_server.name 无效：{0}" -f $rawName)
        if ($rawName -ne $normName) {
            Log ("MCP 服务名已自动规范化：{0} -> {1}" -f $rawName, $normName) "WARN"
            $s.name = $normName
            $changed.Value = $true
        }
        if ($s.PSObject.Properties.Match("transport").Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$s.transport)) {
            $s | Add-Member -NotePropertyName transport -NotePropertyValue "stdio" -Force
            $changed.Value = $true
        }
        else {
            $s.transport = ([string]$s.transport).ToLowerInvariant()
        }

        if ($seenMcpServers.Add($s.name)) {
            $dedupMcpServers += $s
        }
        else {
            Log ("发现重复 mcp_server，已移除：{0}" -f $s.name) "WARN"
            $changed.Value = $true
        }
    }
    $cfg.mcp_servers = $dedupMcpServers

    $dedupMcpTargets = @()
    $seenMcpTargets = New-Object System.Collections.Generic.HashSet[string]
    foreach ($mt in $cfg.mcp_targets) {
        if ($mt -is [string]) {
            $pathValue = [string]$mt
            if (-not [string]::IsNullOrWhiteSpace($pathValue) -and $seenMcpTargets.Add($pathValue)) {
                $dedupMcpTargets += $pathValue
            }
            continue
        }
        if ($null -eq $mt -or $mt.PSObject.Properties.Match("path").Count -eq 0) { continue }
        $pathValue = [string]$mt.path
        if ([string]::IsNullOrWhiteSpace($pathValue)) { continue }
        if ($seenMcpTargets.Add($pathValue)) {
            $dedupMcpTargets += $mt
        }
        else {
            Log ("发现重复 mcp_target，已移除：{0}" -f $pathValue) "WARN"
            $changed.Value = $true
        }
    }
    $cfg.mcp_targets = $dedupMcpTargets

    $vendorNames = New-Object System.Collections.Generic.HashSet[string]
    foreach ($v in $cfg.vendors) { $vendorNames.Add($v.name) | Out-Null }
    $vendorNames.Add("manual") | Out-Null

    $dedupMappings = @()
    $seenMappings = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in $cfg.mappings) {
        $key = "$($m.vendor)|$($m.from)|$($m.to)"
        if (-not $vendorNames.Contains($m.vendor)) {
            Log ("mapping 引用了不存在的 vendor，已移除：{0}" -f $m.vendor) "WARN"
            $changed.Value = $true
            continue
        }
        if ($seenMappings.Add($key)) {
            $dedupMappings += $m
        }
        else {
            Log ("发现重复 mapping，已移除：{0}" -f $key) "WARN"
            $changed.Value = $true
        }
    }
    $cfg.mappings = $dedupMappings
}

function Match-VendorByRepo($cfg, [string]$repo) {
    if ([string]::IsNullOrWhiteSpace($repo)) { return $null }
    $normRepo = Normalize-RepoUrl $repo
    foreach ($v in $cfg.vendors) {
        $vRepo = Normalize-RepoUrl $v.repo
        if ($vRepo -eq $normRepo) { return $v }
    }
    return $null
}

function Repair-VendorImports($cfg, [ref]$changed) {
    if ($null -eq $cfg -or $null -eq $cfg.imports) { return }
    foreach ($i in @($cfg.imports)) {
        $mode = if ($i.PSObject.Properties.Match("mode").Count -gt 0) { [string]$i.mode } else { "manual" }
        if ($mode -ne "vendor") { continue }

        $vendorName = [string]$i.name
        $matchedVendor = Match-VendorByRepo $cfg ([string]$i.repo)
        if ($matchedVendor) {
            $canonicalName = [string]$matchedVendor.name
            if ($vendorName -ne $canonicalName) {
                Log ("vendor import 名称已按 repo 自动归并：{0} -> {1}" -f $vendorName, $canonicalName) "WARN"
                $i.name = $canonicalName
                $vendorName = $canonicalName
                $changed.Value = $true
            }
        }

        $skillPath = Normalize-SkillPath ([string]$i.skill)
        if ([string]::IsNullOrWhiteSpace($skillPath)) { $skillPath = "." }
        if ([string]$i.skill -ne $skillPath) {
            $i.skill = $skillPath
            $changed.Value = $true
        }
    }
}

function Migrate-ManualToVendor($cfg, [string]$vendorName, [string]$repo) {
    $normRepo = Normalize-RepoUrl $repo
    $migratedCount = 0
    
    # 1. Start by finding manual imports that match this repo
    # Note: 'manual' items in imports list might not strictly have 'repo' field populated correctly in all legacy cases,
    # but new ones do. We also check if we can infer it.
    
    $manualImports = @()
    foreach ($i in $cfg.imports) {
        if ($i.mode -eq "manual" -and (Normalize-RepoUrl $i.repo) -eq $normRepo) {
            $manualImports += $i
        }
    }

    # Migrate in a single pass to avoid mutating import names before legacy cleanup.
    $importsToRemove = @()
    foreach ($imp in $manualImports) {
        $oldName = $imp.name
        $skillPath = $imp.skill
        if ([string]::IsNullOrWhiteSpace($skillPath)) { $skillPath = "." }
        
        $vPath = VendorPath $vendorName
        $src = if ($skillPath -eq ".") { $vPath } else { Join-Path $vPath $skillPath }
        
        if (Test-IsSkillDir $src) {
            $targetSuffix = if ($skillPath -eq ".") { $vendorName } else { $skillPath }
            $targetName = Make-TargetName $vendorName $targetSuffix
            Ensure-ImportVendorMapping $cfg $vendorName $skillPath $targetName
             
            # Add vendor-mode import
            $newImport = @{ name = $vendorName; repo = $repo; ref = $imp.ref; skill = $skillPath; mode = "vendor"; sparse = $imp.sparse }
            Upsert-Import $cfg $newImport
             
            $importsToRemove += $imp

            $migratedCount++
            Log ("已迁移手动技能：manual/{0} -> vendor/{1}/{2}" -f $oldName, $vendorName, $skillPath)
             
            # Remove Manual Directory
            $manualDirPath = Join-Path $ManualDir $oldName
            if (Test-Path $manualDirPath) {
                Invoke-RemoveItem $manualDirPath -Recurse
            }
        }
    }
    
    # Remove old manual imports
    $cfg.imports = $cfg.imports | Where-Object { $importsToRemove -notcontains $_ }
    
    return $migratedCount
}

function Optimize-Imports($cfg) {
    if ($null -eq $cfg) { return }
    $total = 0
    foreach ($v in $cfg.vendors) {
        if (-not [string]::IsNullOrWhiteSpace($v.repo)) {
            $total += Migrate-ManualToVendor $cfg $v.name $v.repo
        }
    }
    if ($total -gt 0) {
        Log ("优化完成：共自动迁移 {0} 个手动技能到对应 Vendor。" -f $total) "WARN"
    }
}

function Assert-Cfg($cfg) {
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
    }
    foreach ($m in $cfg.mappings) {
        Need (-not [string]::IsNullOrWhiteSpace($m.vendor)) "mapping 缺少 vendor"
        Need (-not [string]::IsNullOrWhiteSpace($m.from)) "mapping 缺少 from"
        Need (-not [string]::IsNullOrWhiteSpace($m.to)) "mapping 缺少 to"
        Need (Test-SafeRelativePath $m.from -AllowDot) ("mapping.from 非法（仅允许相对路径，禁止 .. 与绝对路径）：{0}" -f $m.from)
        Need (Test-SafeRelativePath $m.to) ("mapping.to 非法（仅允许相对路径，禁止 .. 与绝对路径）：{0}" -f $m.to)
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
        Need (($transport -eq "stdio") -or ($transport -eq "sse") -or ($transport -eq "http")) ("mcp_server.transport 仅支持 stdio/sse/http：{0}" -f $s.name)
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

    $mode = $cfg.sync_mode
    Need (($mode -eq "link") -or ($mode -eq "sync")) "sync_mode 仅支持 link 或 sync"

    $dupVendors = Get-DuplicateValues ($cfg.vendors | ForEach-Object { $_.name })
    Need ($dupVendors.Count -eq 0) ("vendor 名称重复：{0}" -f ($dupVendors -join ", "))

    $dupImports = Get-DuplicateValues ($cfg.imports | ForEach-Object { $_.name })
    Need ($dupImports.Count -eq 0) ("import 名称重复：{0}" -f ($dupImports -join ", "))

    $dupTargets = Get-DuplicateValues ($cfg.targets | ForEach-Object { $_.path })
    if ($dupTargets.Count -gt 0) {
        Log ("目标路径重复（建议去重）：{0}" -f ($dupTargets -join ", ")) "WARN"
    }

    $dupTo = Get-DuplicateValues ($cfg.mappings | ForEach-Object { $_.to })
    if ($dupTo.Count -gt 0) {
        Log ("mappings 的 to 重复（可能覆盖）：{0}" -f ($dupTo -join ", ")) "WARN"
    }

    $vendorNames = New-Object System.Collections.Generic.HashSet[string]
    foreach ($v in $cfg.vendors) { $vendorNames.Add($v.name) | Out-Null }
    $vendorNames.Add("manual") | Out-Null
    foreach ($m in $cfg.mappings) {
        Need ($vendorNames.Contains($m.vendor)) ("mapping 引用了不存在的 vendor：{0}" -f $m.vendor)
    }

    foreach ($i in $cfg.imports) {
        if ($i.PSObject.Properties.Match("mode").Count -gt 0) {
            Need (($i.mode -eq "manual") -or ($i.mode -eq "vendor")) ("import mode 仅支持 manual 或 vendor：{0}" -f $i.name)
        }
    }
}
function SaveCfg($cfg) {
    if (-not $DryRun) {
        $oldRaw = if (Test-Path $CfgPath) { Get-Content $CfgPath -Raw } else { "" }
        Write-CfgChangeSummary $oldRaw $cfg
        $json = $cfg | ConvertTo-Json -Depth 50
        Set-ContentUtf8 $CfgPath $json
    }
}
function SaveCfgSafe($cfg, [string]$rawBackup) {
    if ($DryRun) { return }
    try {
        $oldRaw = $rawBackup
        if ([string]::IsNullOrWhiteSpace($oldRaw) -and (Test-Path $CfgPath)) {
            $oldRaw = Get-Content $CfgPath -Raw
        }
        Write-CfgChangeSummary $oldRaw $cfg
        $json = $cfg | ConvertTo-Json -Depth 50
        Set-ContentUtf8 $CfgPath $json
    }
    catch {
        if ($rawBackup) {
            Set-ContentUtf8 $CfgPath $rawBackup
        }
        throw
    }
}

function Get-LockPath {
    return (Join-Path $Root "skills.lock.json")
}

function Get-RepoHeadCommit([string]$repoPath) {
    Need (-not [string]::IsNullOrWhiteSpace($repoPath)) "repoPath 不能为空"
    Need (Test-Path $repoPath) ("仓库目录不存在：{0}" -f $repoPath)
    Push-Location $repoPath
    try {
        $head = Invoke-GitCapture @("rev-parse", "HEAD")
        Need (-not [string]::IsNullOrWhiteSpace($head)) ("无法读取仓库 HEAD：{0}" -f $repoPath)
        return $head
    }
    finally { Pop-Location }
}

function Get-VendorSparsePaths($cfg, [string]$vendorName) {
    $paths = @()
    foreach ($i in @($cfg.imports)) {
        if ($i.mode -ne "vendor") { continue }
        if ($i.name -ne $vendorName) { continue }
        if (-not $i.sparse) { continue }
        $p = To-GitPath (Normalize-SkillPath $i.skill)
        if ($p -and $p -ne ".") { $paths += $p }
    }
    foreach ($m in @($cfg.mappings)) {
        if ($m.vendor -ne $vendorName) { continue }
        $p = To-GitPath (Normalize-SkillPath $m.from)
        if ($p -and $p -ne ".") { $paths += $p }
    }
    return @($paths | Select-Object -Unique)
}

function New-LockData($cfg) {
    if ($null -eq $cfg) { $cfg = LoadCfg }
    $vendors = @()
    foreach ($v in @($cfg.vendors | Sort-Object name)) {
        $path = VendorPath $v.name
        Need (Test-Path $path) ("生成锁文件失败：缺少 vendor 目录 {0}" -f $path)
        $vendors += [ordered]@{
            name = [string]($v.name)
            repo = [string]($v.repo)
            ref = if ([string]::IsNullOrWhiteSpace([string]($v.ref))) { "main" } else { [string]($v.ref) }
            commit = Get-RepoHeadCommit $path
        }
    }

    $imports = @()
    foreach ($i in @($cfg.imports | Sort-Object @{Expression="name"}, @{Expression="mode"})) {
        $mode = if ($i.PSObject.Properties.Match("mode").Count -gt 0) { [string]($i.mode) } else { "manual" }
        $repoPath = if ($mode -eq "vendor") { VendorPath ([string]($i.name)) } else { Join-Path $ImportDir ([string]($i.name)) }
        Need (Test-Path $repoPath) ("生成锁文件失败：缺少 import 缓存目录 {0}" -f $repoPath)
        $imports += [ordered]@{
            name = [string]($i.name)
            mode = $mode
            repo = [string]($i.repo)
            ref = if ([string]::IsNullOrWhiteSpace([string]($i.ref))) { "main" } else { [string]($i.ref) }
            skill = Normalize-SkillPath ([string]($i.skill))
            sparse = [bool]$i.sparse
            commit = Get-RepoHeadCommit $repoPath
        }
    }

    return [ordered]@{
        version = 1
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        vendors = $vendors
        imports = $imports
    }
}

function Save-LockData($cfg = $null) {
    if ($null -eq $cfg) { $cfg = LoadCfg }
    $lock = New-LockData $cfg
    if ($DryRun) {
        Write-Host ("DRYRUN：将写入锁文件 -> {0}" -f (Get-LockPath))
        return $lock
    }
    $json = $lock | ConvertTo-Json -Depth 50
    Set-ContentUtf8 (Get-LockPath) $json
    return $lock
}

function Load-LockData {
    $path = Get-LockPath
    Need (Test-Path $path) ("缺少锁文件：{0}。请先执行 .\skills.ps1 锁定" -f $path)
    $raw = Get-Content $path -Raw
    Need (-not [string]::IsNullOrWhiteSpace($raw)) ("锁文件为空：{0}" -f $path)
    try {
        $lock = $raw | ConvertFrom-Json
    }
    catch {
        throw ("锁文件解析失败：{0}" -f $_.Exception.Message)
    }
    Need ($lock.PSObject.Properties.Match("version").Count -gt 0) "锁文件缺少 version"
    Need ($lock.version -eq 1) ("不支持的锁文件版本：{0}" -f $lock.version)
    Need ($lock.PSObject.Properties.Match("vendors").Count -gt 0 -and (Assert-IsArray $lock.vendors)) "锁文件 vendors 无效"
    Need ($lock.PSObject.Properties.Match("imports").Count -gt 0 -and (Assert-IsArray $lock.imports)) "锁文件 imports 无效"
    return $lock
}

function Assert-LockMatchesCfg($cfg, $lock) {
    Need ($null -ne $cfg) "cfg 不能为空"
    Need ($null -ne $lock) "lock 不能为空"

    $vendorExpected = @{}
    foreach ($v in @($cfg.vendors)) {
        $vendorExpected[[string]($v.name)] = [ordered]@{
            repo = [string]($v.repo)
            ref = if ([string]::IsNullOrWhiteSpace([string]($v.ref))) { "main" } else { [string]($v.ref) }
        }
    }
    $vendorActual = @{}
    foreach ($v in @($lock.vendors)) {
        $vendorActual[[string]($v.name)] = [ordered]@{
            repo = [string]($v.repo)
            ref = if ([string]::IsNullOrWhiteSpace([string]($v.ref))) { "main" } else { [string]($v.ref) }
        }
    }
    $expVendorJson = ($vendorExpected | ConvertTo-Json -Depth 20 -Compress)
    $actVendorJson = ($vendorActual | ConvertTo-Json -Depth 20 -Compress)
    Need ($expVendorJson -eq $actVendorJson) "锁文件与当前 vendors 配置不一致，请重新执行 .\skills.ps1 锁定"

    $importExpected = @{}
    foreach ($i in @($cfg.imports)) {
        $mode = if ($i.PSObject.Properties.Match("mode").Count -gt 0) { [string]($i.mode) } else { "manual" }
        $key = ("{0}|{1}" -f $mode, [string]($i.name))
        $importExpected[$key] = [ordered]@{
            repo = [string]($i.repo)
            ref = if ([string]::IsNullOrWhiteSpace([string]($i.ref))) { "main" } else { [string]($i.ref) }
            skill = Normalize-SkillPath ([string]($i.skill))
            sparse = [bool]$i.sparse
        }
    }
    $importActual = @{}
    foreach ($i in @($lock.imports)) {
        $mode = if ([string]::IsNullOrWhiteSpace([string]($i.mode))) { "manual" } else { [string]($i.mode) }
        $key = ("{0}|{1}" -f $mode, [string]($i.name))
        $importActual[$key] = [ordered]@{
            repo = [string]($i.repo)
            ref = if ([string]::IsNullOrWhiteSpace([string]($i.ref))) { "main" } else { [string]($i.ref) }
            skill = Normalize-SkillPath ([string]($i.skill))
            sparse = [bool]$i.sparse
        }
    }
    $expImportJson = ($importExpected | ConvertTo-Json -Depth 20 -Compress)
    $actImportJson = ($importActual | ConvertTo-Json -Depth 20 -Compress)
    Need ($expImportJson -eq $actImportJson) "锁文件与当前 imports 配置不一致，请重新执行 .\skills.ps1 锁定"
}

function Assert-LockMatchesWorkspace($cfg, $lock) {
    foreach ($v in @($lock.vendors)) {
        $path = VendorPath ([string]($v.name))
        $actual = Get-RepoHeadCommit $path
        Need ($actual -eq [string]($v.commit)) ("vendor 提交不匹配：{0}（lock={1}, actual={2}）" -f [string]($v.name), [string]($v.commit), [string]$actual)
    }
    foreach ($i in @($lock.imports)) {
        $mode = if ([string]::IsNullOrWhiteSpace([string]($i.mode))) { "manual" } else { [string]($i.mode) }
        $path = if ($mode -eq "vendor") { VendorPath ([string]($i.name)) } else { Join-Path $ImportDir ([string]($i.name)) }
        $actual = Get-RepoHeadCommit $path
        Need ($actual -eq [string]($i.commit)) ("import 提交不匹配：{0}/{1}（lock={2}, actual={3}）" -f $mode, [string]($i.name), [string]($i.commit), [string]$actual)
    }
}

function Ensure-LockedState($cfg = $null) {
    if ($null -eq $cfg) { $cfg = LoadCfg }
    $lock = Load-LockData
    Assert-LockMatchesCfg $cfg $lock
    Assert-LockMatchesWorkspace $cfg $lock
    return $lock
}

function Apply-LockToWorkspace($cfg, $lock) {
    foreach ($v in @($lock.vendors)) {
        $name = [string]($v.name)
        $repo = [string]($v.repo)
        $ref = if ([string]::IsNullOrWhiteSpace([string]($v.ref))) { "main" } else { [string]($v.ref) }
        $commit = [string]($v.commit)
        $path = VendorPath $name
        Ensure-Repo $path $repo $ref $null ([bool]$cfg.update_force) $false $true
        Push-Location $path
        try {
            $sparsePaths = Get-VendorSparsePaths $cfg $name
            if ($sparsePaths.Count -gt 0) {
                Invoke-Git @("sparse-checkout", "init", "--cone")
                Invoke-Git (@("sparse-checkout", "set") + $sparsePaths)
            }
            else {
                try { Invoke-Git @("sparse-checkout", "disable") } catch {}
            }
            Invoke-Git @("checkout", $commit)
        }
        finally { Pop-Location }
    }

    foreach ($i in @($lock.imports)) {
        $mode = if ([string]::IsNullOrWhiteSpace([string]($i.mode))) { "manual" } else { [string]($i.mode) }
        if ($mode -ne "manual") { continue }
        $name = [string]($i.name)
        $repo = [string]($i.repo)
        $ref = if ([string]::IsNullOrWhiteSpace([string]($i.ref))) { "main" } else { [string]($i.ref) }
        $skillPath = Normalize-SkillPath ([string]($i.skill))
        $gitSkillPath = To-GitPath $skillPath
        $sparse = [bool]$i.sparse
        if ($gitSkillPath -eq "." -and $sparse) { $sparse = $false }
        $sparsePath = if ($sparse) { $gitSkillPath } else { $null }
        $path = Join-Path $ImportDir $name
        Ensure-Repo $path $repo $ref $sparsePath ([bool]$cfg.update_force) $false $true
        Push-Location $path
        try { Invoke-Git @("checkout", [string]($i.commit)) }
        finally { Pop-Location }
    }
    Clear-SkillsCache
}

function 锁定 {
    $cfg = LoadCfg
    $lock = Save-LockData $cfg
    Write-Host ("已写入锁文件：{0}" -f (Get-LockPath))
    Write-Host ("锁定摘要：vendors={0}, imports={1}" -f @($lock.vendors).Count, @($lock.imports).Count)
}
