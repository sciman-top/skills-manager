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
function Test-InProgressGitOperation([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    $gitAdminDir = Resolve-GitAdminDir $path
    if ([string]::IsNullOrWhiteSpace($gitAdminDir)) { return $false }
    foreach ($marker in @("MERGE_HEAD", "rebase-merge", "rebase-apply", "CHERRY_PICK_HEAD", "REVERT_HEAD")) {
        if (Test-Path -LiteralPath (Join-Path $gitAdminDir $marker)) {
            return $true
        }
    }
    return $false
}
function Get-DirtyUpdateTargets($cfg) {
    $items = New-Object System.Collections.Generic.List[object]
    if ($null -eq $cfg) { return @() }

    foreach ($v in @($cfg.vendors)) {
        $path = VendorPath $v.name
        if (-not (Test-Path $path)) { continue }
        if (-not (Test-IsGitRepoRoot $path)) { continue }
        if (Test-InProgressGitOperation $path) { continue }
        Push-Location $path
        try {
            if (Has-GitChanges) {
                $items.Add([pscustomobject]@{ kind = "vendor"; name = [string]$v.name; path = $path }) | Out-Null
            }
        }
        finally { Pop-Location }
    }
    return $items.ToArray()
}

function Get-DirtyManualImportTargets($cfg) {
    $items = New-Object System.Collections.Generic.List[object]
    if ($null -eq $cfg) { return @() }

    foreach ($i in @($cfg.imports)) {
        if ($null -eq $i) { continue }
        $iMode = if ($i.PSObject.Properties.Match("mode").Count -gt 0) { [string]$i.mode } else { "manual" }
        if ($iMode -ne "manual") { continue }
        $cache = Join-Path $ImportDir $i.name
        if (-not (Test-Path $cache)) { continue }
        if (-not (Test-IsGitRepoRoot $cache)) { continue }
        if (Test-InProgressGitOperation $cache) { continue }
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
function Test-IsGitRepoRoot([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { return $false }
    Push-Location $path
    try {
        $top = Invoke-GitCapture @("rev-parse", "--show-toplevel")
    }
    finally { Pop-Location }
    if ([string]::IsNullOrWhiteSpace($top)) { return $false }

    try {
        $resolvedPath = (Resolve-Path -LiteralPath $path -ErrorAction Stop).Path
    }
    catch {
        $resolvedPath = $path
    }
    try {
        $resolvedTop = (Resolve-Path -LiteralPath $top -ErrorAction Stop).Path
    }
    catch {
        $resolvedTop = $top
    }

    $resolvedPath = $resolvedPath.TrimEnd('\', '/')
    $resolvedTop = $resolvedTop.TrimEnd('\', '/')
    return [string]::Equals($resolvedPath, $resolvedTop, [System.StringComparison]::OrdinalIgnoreCase)
}
function Confirm-UpdateForce($cfg, [ref]$SkipForceClean) {
    if ($null -eq $SkipForceClean.Value) { $SkipForceClean.Value = @{} }
    if (-not $cfg.update_force) { return $true }

    $dirtyImports = Get-DirtyManualImportTargets $cfg
    $dirtyVendors = Get-DirtyUpdateTargets $cfg
    $dirty = @($dirtyImports) + @($dirtyVendors)
    if ($dirty.Count -eq 0) {
        Write-Host "未检测到本地改动，将按默认策略更新。"
        return $true
    }

    foreach ($d in $dirty) {
        $key = "{0}|{1}" -f $d.kind, $d.name
        $SkipForceClean.Value[$key] = $true
    }
    Write-Host ("检测到 {0} 个本地改动项，已自动保留并跳过强制清理。" -f $dirty.Count) -ForegroundColor Yellow
    return $true
}

function LoadCfg([switch]$NoAutoFix) {
    Need (Test-Path $CfgPath) "缺少配置文件：$CfgPath"
    $raw = Get-ContentUtf8 $CfgPath
    # 保守注释支持：仅移除整行 // 注释，避免误伤字符串内容。
    $clean = $raw -replace "(?m)^\s*//.*", ""
    try {
        $cfg = $clean | ConvertFrom-Json
    }
    catch {
        throw ("skills.json 解析失败：{0}。请检查 JSON 格式；注释仅支持整行 //。" -f $_.Exception.Message)
    }
    # vendors/targets 缺失或为 null/[] 由下方 Normalize-ArrayField 自动补空数组；
    # 此处不再用 -ne $null 预检（数组过滤语义会把空数组误判为缺失并自锁）。
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
    if ($changed -and -not $NoAutoFix) {
        Log "已自动修复 skills.json 中的无效项/重复项。" "WARN"
        try {
            SaveCfgSafe $cfg $raw
        }
        catch {
            # 目录已改名而配置回写失败会造成磁盘/配置名称分叉；回退目录迁移，
            # 任一回退失败时聚合暴露未复原路径，不得只留下原始保存错误。
            $unrestored = Undo-DirectoryMigrations $dirMigrations
            if (@($unrestored).Count -gt 0) {
                $detail = (@($unrestored) | ForEach-Object { "{0}:{1}({2})" -f $_.label, $_.path, $_.reason }) -join "; "
                Log ("skills.json 自动修复保存失败，且部分目录迁移未能回退：{0}" -f $detail) "ERROR"
                throw ("skills.json 保存失败：{0}；目录迁移回退未完成，磁盘与配置可能分叉：{1}" -f $_.Exception.Message, $detail)
            }
            throw
        }
    }
    return $cfg
}
function Normalize-Cfg($cfg) {
    if (-not $cfg.PSObject.Properties.Match("mappings").Count) { $cfg | Add-Member -NotePropertyName mappings -NotePropertyValue @() }
    if (-not $cfg.PSObject.Properties.Match("imports").Count) { $cfg | Add-Member -NotePropertyName imports -NotePropertyValue @() }
    if (-not $cfg.PSObject.Properties.Match("mcp_servers").Count) { $cfg | Add-Member -NotePropertyName mcp_servers -NotePropertyValue @() }
    if (-not $cfg.PSObject.Properties.Match("mcp_targets").Count) { $cfg | Add-Member -NotePropertyName mcp_targets -NotePropertyValue @() }
    if (-not $cfg.PSObject.Properties.Match("update_force").Count) { $cfg | Add-Member -NotePropertyName update_force -NotePropertyValue $true }
    # $null 必须放比较符左侧：右侧写法在数组含 null 元素时是集合过滤而非空值判断，
    # 会把含 null 的有效数组整组误判为缺失并回写清空。
    if ($null -eq $cfg.mappings) { $cfg.mappings = @() }
    if ($null -eq $cfg.imports) { $cfg.imports = @() }
    if ($null -eq $cfg.mcp_servers) { $cfg.mcp_servers = @() }
    if ($null -eq $cfg.mcp_targets) { $cfg.mcp_targets = @() }
    if ($null -eq $cfg.update_force) { $cfg.update_force = $true }
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
function Migrate-DirName([string]$baseDir, [string]$oldName, [string]$newName, [string]$label, [ref]$changed) {
    if ([string]::IsNullOrWhiteSpace($oldName) -or [string]::IsNullOrWhiteSpace($newName)) { return }
    if ($oldName -eq $newName) { return }
    $src = Join-Path $baseDir $oldName
    if (-not (Test-Path -LiteralPath $src)) { return }
    $dst = Join-Path $baseDir $newName
    if (Test-Path -LiteralPath $dst) {
        Log ("{0} 目录迁移跳过：目标已存在 {1}" -f $label, $dst) "WARN"
        return
    }
    Invoke-MoveItem $src $dst
    Log ("{0} 目录已迁移：{1} -> {2}" -f $label, $oldName, $newName) "WARN"
    $changed.Value = $true
}
function Undo-DirectoryMigrations($dirMigrations) {
    # 逐项尝试回退目录迁移，返回未能复原的条目列表（空数组=全部复原）。
    # 调用方必须把非空结果聚合进抛出的错误，不得只记 warning 后吞掉。
    $unrestored = New-Object System.Collections.Generic.List[object]
    if ($null -eq $dirMigrations) { return @() }
    foreach ($v in $dirMigrations.vendors) {
        Undo-DirNameRename $VendorDir $v.new $v.old "vendor" $unrestored
    }
    foreach ($i in $dirMigrations.imports) {
        Undo-DirNameRename $ImportDir $i.new $i.old "import 缓存" $unrestored
        if ($i.mode -eq "manual") {
            Undo-DirNameRename $ManualDir $i.new $i.old "manual 技能" $unrestored
        }
    }
    return @($unrestored.ToArray())
}
function Undo-DirNameRename([string]$baseDir, [string]$currentName, [string]$originalName, [string]$label, [System.Collections.Generic.List[object]]$unrestored) {
    if ([string]::IsNullOrWhiteSpace($currentName) -or [string]::IsNullOrWhiteSpace($originalName)) { return }
    if ($currentName -eq $originalName) { return }
    $src = Join-Path $baseDir $currentName
    if (-not (Test-Path -LiteralPath $src)) { return }
    $dst = Join-Path $baseDir $originalName
    if (Test-Path -LiteralPath $dst) {
        $unrestored.Add([pscustomobject]@{ label = $label; path = $dst; reason = "original_target_exists" }) | Out-Null
        return
    }
    try {
        Invoke-MoveItem $src $dst
        Log ("{0} 目录迁移已回退：{1} -> {2}" -f $label, $currentName, $originalName) "WARN"
    }
    catch {
        $unrestored.Add([pscustomobject]@{ label = $label; path = $src; reason = $_.Exception.Message }) | Out-Null
    }
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
    Prune-VendorRootEntries $cfg $changed

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

    $vendorNames = New-CfgVendorNameSet $cfg.vendors

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

function Prune-VendorRootEntries($cfg, [ref]$changed) {
    if ($null -eq $cfg) { return }

    # Normalize: vendor 根入口不作为实际同步输入，统一移除避免“配置显示与同步结果”分叉。
    $rootMappings = @($cfg.mappings | Where-Object {
            $_ -ne $null -and [string]$_.from -eq "." -and
            [string]$_.vendor -ne "manual" -and [string]$_.vendor -ne "overrides"
        })
    if ($rootMappings.Count -gt 0) {
        foreach ($m in $rootMappings) {
            Log ("移除 vendor 根映射（统一按具体技能路径管理）：{0}|{1}|{2}" -f [string]$m.vendor, [string]$m.from, [string]$m.to) "WARN"
        }
        $cfg.mappings = @($cfg.mappings | Where-Object { $rootMappings -notcontains $_ })
        $changed.Value = $true
    }

    $rootVendorImports = @()
    foreach ($imp in @($cfg.imports)) {
        if ($null -eq $imp) { continue }
        $mode = if ($imp.PSObject.Properties.Match("mode").Count -gt 0) { [string]$imp.mode } else { "manual" }
        if ($mode -ne "vendor") { continue }
        $skillPath = Normalize-SkillPath ([string]$imp.skill)
        if ($skillPath -eq ".") { $rootVendorImports += $imp }
    }
    if ($rootVendorImports.Count -gt 0) {
        foreach ($i in $rootVendorImports) {
            Log ("移除 vendor 根导入（skill='.'）：{0}" -f [string]$i.name) "WARN"
        }
        $cfg.imports = @($cfg.imports | Where-Object { $rootVendorImports -notcontains $_ })
        $changed.Value = $true
    }
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

function Migrate-ManualToVendor($cfg, [string]$vendorName, [string]$repo, [string]$MigrationBackupRoot = '', [object]$MigrationRecords = $null) {
    $normRepo = Normalize-RepoUrl $repo
    $migratedCount = 0
    
    # 1. Start by finding manual imports that match this repo
    # Note: 'manual' items in imports list might not strictly have 'repo' field populated correctly in all legacy cases,
    # but new ones do. We also check if we can infer it.
    
    $manualImports = @()
    foreach ($i in $cfg.imports) {
        $mode = if ($i.PSObject.Properties.Match('mode').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$i.mode)) { [string]$i.mode } else { 'manual' }
        if ($mode -eq "manual" -and (Normalize-RepoUrl $i.repo) -eq $normRepo) {
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
            $targetName = Get-CanonicalSkillTargetName $src (Make-TargetName $vendorName $targetSuffix)
            Ensure-ImportVendorMapping $cfg $vendorName $skillPath $targetName
             
            # Add vendor-mode import
            $newImport = @{ name = $vendorName; repo = $repo; ref = $imp.ref; skill = $skillPath; mode = "vendor"; sparse = $imp.sparse }
            Upsert-Import $cfg $newImport
             
            $importsToRemove += $imp

            # Remove stale manual mappings for this migrated import to avoid dangling manual refs.
            $legacyFrom = Normalize-SkillPath ([string]$oldName)
            $skillFrom = Normalize-SkillPath ([string]$skillPath)
            $beforeMappings = @($cfg.mappings).Count
            $cfg.mappings = @($cfg.mappings | Where-Object {
                    $vendor = [string]$_.vendor
                    if ($vendor -ne "manual") { return $true }
                    $from = Normalize-SkillPath ([string]$_.from)
                    if ([string]::IsNullOrWhiteSpace($from)) { return $true }
                    return ($from -ne $legacyFrom) -and ($from -ne $skillFrom)
                })
            $removedLegacyMappings = $beforeMappings - @($cfg.mappings).Count
            if ($removedLegacyMappings -gt 0) {
                Log ("已清理迁移遗留 manual 映射：{0} 项（manual/{1}）" -f $removedLegacyMappings, $oldName)
            }

            $migratedCount++
            Log ("已迁移手动技能：manual/{0} -> vendor/{1}/{2}" -f $oldName, $vendorName, $skillPath)
             
            # During 构建生效, stage the old manual tree inside the build
            # transaction. It is only discarded when the complete build is
            # committed; a failed build can therefore restore both config and
            # source data. Direct install/update callers retain the historical
            # immediate cleanup behavior.
            $manualDirPath = Join-Path $ManualDir $oldName
            if (Test-Path $manualDirPath) {
                if (-not [string]::IsNullOrWhiteSpace($MigrationBackupRoot)) {
                    EnsureDir $MigrationBackupRoot
                    $backupPath = Join-Path $MigrationBackupRoot ("{0}-{1}" -f $oldName, [Guid]::NewGuid().ToString('N'))
                    Invoke-MoveItem $manualDirPath $backupPath
                    if ($null -ne $MigrationRecords -and $MigrationRecords -is [System.Collections.IList]) {
                        $MigrationRecords.Add([pscustomobject]@{ source = $manualDirPath; backup = $backupPath }) | Out-Null
                    }
                }
                else {
                    Invoke-RemoveItem $manualDirPath -Recurse
                }
            }
        }
    }
    
    # Remove old manual imports
    $cfg.imports = $cfg.imports | Where-Object { $importsToRemove -notcontains $_ }
    
    return $migratedCount
}

function Optimize-Imports($cfg, [string]$MigrationBackupRoot = '', [object]$MigrationRecords = $null) {
    if ($null -eq $cfg) { return }
    $total = 0
    foreach ($v in $cfg.vendors) {
        if (-not [string]::IsNullOrWhiteSpace($v.repo)) {
            $total += Migrate-ManualToVendor $cfg $v.name $v.repo $MigrationBackupRoot $MigrationRecords
        }
    }
    if ($total -gt 0) {
        Log ("优化完成：共自动迁移 {0} 个手动技能到对应 Vendor。" -f $total) "WARN"
    }
}

function SaveCfg($cfg) {
    if (-not $DryRun) {
        $oldRaw = if (Test-Path -LiteralPath $CfgPath) { Get-ContentUtf8 $CfgPath } else { "" }
        Write-CfgChangeSummary $oldRaw $cfg
        $json = $cfg | ConvertTo-Json -Depth 50
        Write-Utf8FileAtomic -Path $CfgPath -Content $json
    }
}
function New-ConfigWriteSnapshot {
    $exists = [IO.File]::Exists($CfgPath)
    [byte[]]$bytes = [byte[]]::new(0)
    if ($exists) { $bytes = [IO.File]::ReadAllBytes($CfgPath) }
    return [pscustomobject]@{
        path = [IO.Path]::GetFullPath($CfgPath)
        existed = $exists
        bytes = $bytes
        hashes = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    }
}

function Restore-ConfigWriteSnapshot($Snapshot) {
    if ($Snapshot.hashes.Count -eq 0) { return }
    $path = [string]$Snapshot.path
    Need (-not (Test-AncestorChainHasReparse $path)) 'config_restore_conflict:reparse_path'
    if (-not (Test-PathEntry $path) -and -not $Snapshot.existed) { return }
    $hash = Get-FileContentHash $path
    if ([IO.File]::Exists($path) -and $Snapshot.existed) {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $originalHash = [Convert]::ToHexString($sha.ComputeHash([byte[]]$Snapshot.bytes)).ToLowerInvariant() }
        finally { $sha.Dispose() }
        if ($hash -eq $originalHash) { return }
    }
    Need (-not [string]::IsNullOrWhiteSpace($hash) -and $Snapshot.hashes.Contains($hash)) 'config_restore_conflict:external_change'
    if ($Snapshot.existed) { Write-BytesAtomic -Path $path -Bytes $Snapshot.bytes }
    else { [IO.File]::Delete($path) }
}

function SaveCfgSafe($cfg, [string]$rawBackup, $Snapshot = $null) {
    if ($DryRun) { return }
    $oldRaw = $rawBackup
    if ([string]::IsNullOrWhiteSpace($oldRaw) -and (Test-Path -LiteralPath $CfgPath)) {
        $oldRaw = Get-ContentUtf8 $CfgPath
    }
    Write-CfgChangeSummary $oldRaw $cfg
    $json = $cfg | ConvertTo-Json -Depth 50
    if ($null -ne $Snapshot) {
        Need ([IO.Path]::GetFullPath($CfgPath) -eq $Snapshot.path) 'config_snapshot_path_mismatch'
        $sha = [Security.Cryptography.SHA256]::Create()
        try { [void]$Snapshot.hashes.Add([Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json))).ToLowerInvariant()) }
        finally { $sha.Dispose() }
    }
    # Atomic replacement preserves the target on failure; a second write of an
    # older snapshot could overwrite another writer's current configuration.
    Set-ContentUtf8 $CfgPath $json
}

