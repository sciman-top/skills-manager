# 锁定域原语：skills.lock.json 的路径/来源指纹/读写/一致性校验与工作区应用。
# 从 Config.ps1 纯迁移（函数名与实现逐字不变）；CLI 入口 验证锁定/锁定
# 在 Commands/Update.ps1；配置 schema/校验在 Domain/ConfigContract.ps1，迁移在 Config.ps1。

function Get-LockPath {
    return (Join-Path $Root "skills.lock.json")
}

function Get-ImportLockSourceKind($import) {
    if ($null -eq $import) { return "git" }
    $kind = [string](Get-CfgObjectProperty $import "source_kind")
    if (-not [string]::IsNullOrWhiteSpace($kind)) { return $kind.Trim().ToLowerInvariant() }
    $mode = [string](Get-CfgObjectProperty $import "mode")
    if ([string]::IsNullOrWhiteSpace($mode)) { $mode = "manual" }
    $repo = [string](Get-CfgObjectProperty $import "repo")
    if ($mode -eq "manual" -and (Test-LocalZipRepoInput $repo)) { return "local_zip" }
    return "git"
}

function Get-ImportLockSourceHash([string]$repo, [string]$sourceKind) {
    $kind = if ([string]::IsNullOrWhiteSpace($sourceKind)) { "git" } else { $sourceKind.Trim().ToLowerInvariant() }
    if ($kind -ne "local_zip") { return $null }
    Need (Test-LocalZipRepoInput $repo) ("锁定失败：本地 zip 源不存在或无效：{0}" -f $repo)
    return (Get-FileContentHash $repo)
}

function Get-ImportLockWorkspaceFingerprint([string]$repoPath, [string]$algorithm = "sha256-tree-v2") {
    Need (-not [string]::IsNullOrWhiteSpace($repoPath)) "repoPath 不能为空"
    Need (Test-Path -LiteralPath $repoPath) ("锁定失败：缺少 import 缓存目录 {0}" -f $repoPath)
    switch ($algorithm.Trim().ToLowerInvariant()) {
        "metadata-tree-v1" { return (Get-LegacyDirectoryMetadataFingerprint $repoPath) }
        "sha256-tree-v2" { return (Get-DirectoryFingerprint $repoPath) }
        default { throw ("锁文件包含未知的 import 工作区指纹算法：{0}" -f $algorithm) }
    }
}

function Assert-ImportLockWorkspaceFingerprint($lockEntry, [string]$repoPath, [string]$label) {
    $expectedFingerprint = [string](Get-CfgObjectProperty $lockEntry "workspace_fingerprint")
    Need (-not [string]::IsNullOrWhiteSpace($expectedFingerprint)) ("锁文件缺少 import 工作区指纹：{0}" -f $label)
    $algorithm = [string](Get-CfgObjectProperty $lockEntry "workspace_fingerprint_algorithm")
    if ([string]::IsNullOrWhiteSpace($algorithm)) {
        $algorithm = "metadata-tree-v1"
        Log ("锁文件仍使用旧版 import 工作区指纹，重新执行锁定可迁移：{0}" -f $label) "WARN"
    }
    $actualFingerprint = Get-ImportLockWorkspaceFingerprint $repoPath $algorithm
    Need ($actualFingerprint -eq $expectedFingerprint) ("import 内容不匹配：{0}（algorithm={1}, lock={2}, actual={3}）" -f $label, $algorithm, $expectedFingerprint, $actualFingerprint)
}

function Get-RepoHeadCommit([string]$repoPath, [hashtable]$HeadCache = $null) {
    Need (-not [string]::IsNullOrWhiteSpace($repoPath)) "repoPath 不能为空"
    Need (Test-Path -LiteralPath $repoPath) ("仓库目录不存在：{0}" -f $repoPath)
    $cacheKey = [IO.Path]::GetFullPath($repoPath).TrimEnd('\', '/')
    if ($null -ne $HeadCache -and $HeadCache.ContainsKey($cacheKey)) {
        return [string]$HeadCache[$cacheKey]
    }
    Push-Location $repoPath
    try {
        if ($DryRun) {
            Log "DRYRUN(read) git rev-parse HEAD"
            $rawHead = & git rev-parse HEAD 2>$null
            if ($LASTEXITCODE -ne 0) {
                $head = $null
            }
            elseif ($null -eq $rawHead) {
                $head = ""
            }
            else {
                $head = ([string]($rawHead | Select-Object -First 1)).Trim()
            }
        }
        else {
            $head = Invoke-GitCapture @("rev-parse", "HEAD")
        }
        Need (-not [string]::IsNullOrWhiteSpace($head)) ("无法读取仓库 HEAD：{0}" -f $repoPath)
        if ($null -ne $HeadCache) { $HeadCache[$cacheKey] = $head }
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
    $repoHeadCache = @{}
    $vendors = @()
    foreach ($v in @($cfg.vendors | Sort-Object name)) {
        $path = VendorPath $v.name
        Need (Test-Path $path) ("生成锁文件失败：缺少 vendor 目录 {0}" -f $path)
        $vendors += [ordered]@{
            name = [string]($v.name)
            repo = [string]($v.repo)
            ref = if ([string]::IsNullOrWhiteSpace([string]($v.ref))) { "main" } else { [string]($v.ref) }
            commit = Get-RepoHeadCommit $path $repoHeadCache
        }
    }

    $imports = @()
    foreach ($i in @($cfg.imports | Sort-Object @{Expression="name"}, @{Expression="mode"})) {
        $mode = if ($i.PSObject.Properties.Match("mode").Count -gt 0) { [string]($i.mode) } else { "manual" }
        $repoPath = if ($mode -eq "vendor") { VendorPath ([string]($i.name)) } else { Join-Path $ImportDir ([string]($i.name)) }
        Need (Test-Path $repoPath) ("生成锁文件失败：缺少 import 缓存目录 {0}" -f $repoPath)
        $sourceKind = Get-ImportLockSourceKind $i
        $importEntry = [ordered]@{
            name = [string]($i.name)
            mode = $mode
            repo = [string]($i.repo)
            ref = if ([string]::IsNullOrWhiteSpace([string]($i.ref))) { "main" } else { [string]($i.ref) }
            skill = Normalize-SkillPath ([string]($i.skill))
            sparse = [bool]$i.sparse
        }
        if ($sourceKind -eq "local_zip") {
            $importEntry.source_kind = $sourceKind
            $importEntry.source_hash = Get-ImportLockSourceHash ([string]($i.repo)) $sourceKind
            $importEntry.workspace_fingerprint_algorithm = "sha256-tree-v2"
            $importEntry.workspace_fingerprint = Get-ImportLockWorkspaceFingerprint $repoPath "sha256-tree-v2"
        }
        else {
            $importEntry.commit = Get-RepoHeadCommit $repoPath $repoHeadCache
        }
        $imports += $importEntry
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
    $raw = Get-ContentUtf8 $path
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
    $expVendorJson = @($vendorExpected.Keys | Sort-Object | ForEach-Object {
            [ordered]@{
                name = [string]$_
                repo = [string]$vendorExpected[$_].repo
                ref = [string]$vendorExpected[$_].ref
            }
        }) | ConvertTo-Json -Depth 20 -Compress
    $actVendorJson = @($vendorActual.Keys | Sort-Object | ForEach-Object {
            [ordered]@{
                name = [string]$_
                repo = [string]$vendorActual[$_].repo
                ref = [string]$vendorActual[$_].ref
            }
        }) | ConvertTo-Json -Depth 20 -Compress
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
    $expImportJson = @($importExpected.Keys | Sort-Object | ForEach-Object {
            [ordered]@{
                key = [string]$_
                repo = [string]$importExpected[$_].repo
                ref = [string]$importExpected[$_].ref
                skill = [string]$importExpected[$_].skill
                sparse = [bool]$importExpected[$_].sparse
            }
        }) | ConvertTo-Json -Depth 20 -Compress
    $actImportJson = @($importActual.Keys | Sort-Object | ForEach-Object {
            [ordered]@{
                key = [string]$_
                repo = [string]$importActual[$_].repo
                ref = [string]$importActual[$_].ref
                skill = [string]$importActual[$_].skill
                sparse = [bool]$importActual[$_].sparse
            }
        }) | ConvertTo-Json -Depth 20 -Compress
    Need ($expImportJson -eq $actImportJson) "锁文件与当前 imports 配置不一致，请重新执行 .\skills.ps1 锁定"
}

function Assert-LockMatchesWorkspace($cfg, $lock) {
    $repoHeadCache = @{}
    foreach ($v in @($lock.vendors)) {
        $path = VendorPath ([string]($v.name))
        $actual = Get-RepoHeadCommit $path $repoHeadCache
        Need ($actual -eq [string]($v.commit)) ("vendor 提交不匹配：{0}（lock={1}, actual={2}）" -f [string]($v.name), [string]($v.commit), [string]$actual)
    }
    foreach ($i in @($lock.imports)) {
        $mode = if ([string]::IsNullOrWhiteSpace([string]($i.mode))) { "manual" } else { [string]($i.mode) }
        $path = if ($mode -eq "vendor") { VendorPath ([string]($i.name)) } else { Join-Path $ImportDir ([string]($i.name)) }
        $sourceKind = Get-ImportLockSourceKind $i
        if ($sourceKind -eq "local_zip") {
            $expectedSourceHash = [string](Get-CfgObjectProperty $i "source_hash")
            Need (-not [string]::IsNullOrWhiteSpace($expectedSourceHash)) ("锁文件缺少 local zip 源指纹：{0}/{1}" -f $mode, [string]($i.name))
            $actualSourceHash = Get-ImportLockSourceHash ([string]($i.repo)) $sourceKind
            Need ($actualSourceHash -eq $expectedSourceHash) ("import 源文件不匹配：{0}/{1}（lock={2}, actual={3}）" -f $mode, [string]($i.name), $expectedSourceHash, $actualSourceHash)

            Assert-ImportLockWorkspaceFingerprint $i $path ("{0}/{1}" -f $mode, [string]($i.name))
            continue
        }

        $actual = Get-RepoHeadCommit $path $repoHeadCache
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
            Set-GitSparseCheckout $sparsePaths
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
        $sourceKind = Get-ImportLockSourceKind $i
        if ($gitSkillPath -eq "." -and $sparse) { $sparse = $false }
        $sparsePath = if ($sparse) { $gitSkillPath } else { $null }
        $path = Join-Path $ImportDir $name
        $forceClean = [bool]$cfg.update_force

        if ($sourceKind -eq "local_zip") {
            $expectedSourceHash = [string](Get-CfgObjectProperty $i "source_hash")
            Need (-not [string]::IsNullOrWhiteSpace($expectedSourceHash)) ("锁文件缺少 local zip 源指纹：manual/{0}" -f $name)
            $actualSourceHash = Get-ImportLockSourceHash $repo $sourceKind
            Need ($actualSourceHash -eq $expectedSourceHash) ("import 源文件不匹配：manual/{0}（lock={1}, actual={2}）" -f $name, $expectedSourceHash, $actualSourceHash)
            $forceClean = $true
        }

        Ensure-Repo $path $repo $ref $sparsePath $forceClean $false $true
        if ($sourceKind -eq "local_zip") {
            Assert-ImportLockWorkspaceFingerprint $i $path ("manual/{0}" -f $name)
            continue
        }

        Push-Location $path
        try { Invoke-Git @("checkout", [string]($i.commit)) }
        finally { Pop-Location }
    }
    Clear-SkillsCache
}
