$script:ReleaseUpdateRepository = 'sciman-top/skills-manager'
$script:ReleaseUpdateHttpGet = $null

function Get-ReleaseUpdateTokens([string[]]$Tokens) {
    $result = [ordered]@{ action = 'check'; yes = $false; json = $false; repository = $script:ReleaseUpdateRepository; sync_mcp = $false }
    foreach ($token in @($Tokens)) {
        $value = [string]$token
        switch -Regex ($value.ToLowerInvariant()) {
            '^--check$' { $result.action = 'check'; continue }
            '^--apply$' { $result.action = 'apply'; continue }
            '^--yes$' { $result.yes = $true; continue }
            '^--json$' { $result.json = $true; continue }
            '^--sync-mcp$' { $result.sync_mcp = $true; continue }
            '^--repo=' { $result.repository = $value.Substring(7); continue }
            default { throw ("release-update 不支持参数：{0}" -f $value) }
        }
    }
    $result.repository = ([string]$result.repository).Trim()
    Need ($result.repository -match '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') 'release-update --repo 必须是 owner/repository'
    Need ($result.action -ne 'apply' -or $result.yes) 'release-update --apply 必须显式加 --yes'
    return [pscustomobject]$result
}

function Get-ReleaseUpdateManifest([string]$InstallRoot = $Root) {
    $path = Join-Path $InstallRoot 'RELEASE-MANIFEST.json'
    Need (Test-Path -LiteralPath $path -PathType Leaf) '当前目录不是 GitHub Release 安装目录；源码开发版请使用 Git 更新'
    $manifest = Get-ContentUtf8 $path | ConvertFrom-Json
    Need ([string]$manifest.product -eq 'skills-manager' -and -not [string]::IsNullOrWhiteSpace([string]$manifest.version)) 'RELEASE-MANIFEST.json 无效'
    return $manifest
}

function Invoke-ReleaseUpdateHttpGet([string]$Uri, [string]$OutFile = '') {
    if ($null -ne $script:ReleaseUpdateHttpGet) { return & $script:ReleaseUpdateHttpGet $Uri $OutFile }
    $headers = @{ 'Accept' = 'application/vnd.github+json'; 'User-Agent' = 'skills-manager-release-update' }
    if ([string]::IsNullOrWhiteSpace($OutFile)) { return Invoke-RestMethod -Uri $Uri -Headers $headers -ErrorAction Stop }
    Invoke-WebRequest -Uri $Uri -Headers $headers -OutFile $OutFile -ErrorAction Stop | Out-Null
}

function ConvertFrom-ReleaseChecksumText([string]$Text, [string]$FileName) {
    foreach ($line in @($Text -split "`r?`n")) {
        $match = [regex]::Match($line, '^\s*(?<hash>[A-Fa-f0-9]{64})\s+\*?(?<name>.+?)\s*$')
        if ($match.Success -and [string]$match.Groups['name'].Value -eq $FileName) { return $match.Groups['hash'].Value.ToLowerInvariant() }
    }
    throw ("SHA256SUMS.txt 未包含发布资产：{0}" -f $FileName)
}

function ConvertTo-ReleaseVersionKey([string]$Version) {
    $value = ([string]$Version).Trim()
    Need ($value -match '^v(?<year>\d{4})\.(?<month>\d{2})\.(?<day>\d{2})(?:\.(?<patch>\d+))?(?:-(?<pre>[0-9A-Za-z.-]+))?$') ("Release version 不符合 vYYYY.MM.DD[.N][-prerelease]：{0}" -f $Version)
    $date = [DateTime]::new([int]$Matches.year, [int]$Matches.month, [int]$Matches.day)
    $patch = if ($Matches.patch) { [int64]$Matches.patch } else { 0L }
    $pre = if ($Matches.pre) { [string]$Matches.pre } else { $null }
    return [pscustomobject]@{ date = $date; patch = $patch; prerelease = $pre }
}

function Compare-ReleaseVersion([string]$Left, [string]$Right) {
    $a = ConvertTo-ReleaseVersionKey $Left; $b = ConvertTo-ReleaseVersionKey $Right
    $cmp = $a.date.CompareTo($b.date)
    if ($cmp -ne 0) { return $cmp }
    $cmp = $a.patch.CompareTo($b.patch)
    if ($cmp -ne 0) { return $cmp }
    if ($null -eq $a.prerelease -and $null -ne $b.prerelease) { return 1 }
    if ($null -ne $a.prerelease -and $null -eq $b.prerelease) { return -1 }
    return [StringComparer]::Ordinal.Compare([string]$a.prerelease, [string]$b.prerelease)
}

function Get-ReleaseUpdateSnapshot([string]$Repository, $LocalManifest) {
    $release = Invoke-ReleaseUpdateHttpGet ("https://api.github.com/repos/{0}/releases/latest" -f $Repository)
    Need ($null -ne $release -and -not [bool]$release.draft -and -not [bool]$release.prerelease) 'GitHub latest Release 不可用或不是正式版'
    $tag = ([string]$release.tag_name).Trim()
    ConvertTo-ReleaseVersionKey $tag | Out-Null
    $packageType = ([string]$LocalManifest.package).Trim().ToLowerInvariant()
    Need ($packageType -in @('bootstrap','portable')) '当前 RELEASE-MANIFEST.json package 必须是 bootstrap 或 portable'
    $assets = @($release.assets)
    $packageAsset = @($assets | Where-Object { [string]$_.name -eq ("skills-manager-{0}-{1}.zip" -f $tag, $packageType) }) | Select-Object -First 1
    $checksums = @($assets | Where-Object { [string]$_.name -eq ("skills-manager-{0}-SHA256SUMS.txt" -f $tag) }) | Select-Object -First 1
    Need ($null -ne $packageAsset -and $null -ne $checksums) 'GitHub Release 缺少当前安装类型 ZIP 或 SHA256SUMS.txt'
    $checksumText = [string](Invoke-ReleaseUpdateHttpGet ([string]$checksums.browser_download_url))
    $hash = ConvertFrom-ReleaseChecksumText $checksumText ([string]$packageAsset.name)
    return [pscustomobject][ordered]@{
        repository = $Repository
        current_version = [string]$LocalManifest.version
        latest_version = $tag
        update_available = ((Compare-ReleaseVersion ([string]$LocalManifest.version) $tag) -lt 0)
        release_url = [string]$release.html_url
        package = $packageType
        package_name = [string]$packageAsset.name
        package_url = [string]$packageAsset.browser_download_url
        package_sha256 = $hash
    }
}

function Test-ReleaseUpdatePristineInstallation([string]$InstallRoot, $Manifest) {
    $root = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\', '/')
    $entries = @($Manifest.files)
    Need ($entries.Count -gt 0) 'RELEASE-MANIFEST.json 缺少文件清单，无法安全覆盖本地安装'
    foreach ($entry in $entries) {
        $relative = [string]$entry.path
        Need (-not [string]::IsNullOrWhiteSpace($relative) -and -not [IO.Path]::IsPathRooted($relative) -and $relative -notmatch '(^|[\\/])\.\.([\\/]|$)') 'RELEASE-MANIFEST.json 包含不安全路径'
        $path = [IO.Path]::GetFullPath((Join-Path $root $relative))
        Need (Is-PathInsideOrEqual $path $root) 'RELEASE-MANIFEST.json 文件路径越界'
        Need (Test-Path -LiteralPath $path -PathType Leaf) ("发行文件缺失：{0}" -f $relative)
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        Need ($actual -eq ([string]$entry.sha256).ToLowerInvariant()) ("本地发行文件已修改：{0}；请使用 Git 源码开发版或先迁移定制内容" -f $relative)
    }
    return $true
}

function Test-ReleaseUpdatePackage([string]$PackageRoot, [string]$ExpectedVersion, [string]$ExpectedPackage) {
    $manifest = Get-ReleaseUpdateManifest $PackageRoot
    Need ([string]$manifest.version -eq $ExpectedVersion -and [string]$manifest.package -eq $ExpectedPackage -and [bool]$manifest.publishable) '下载的 Release 包版本、类型或发布状态不匹配'
    foreach ($required in @('install.ps1','build.ps1','skills.ps1','skills.json','LICENSE')) {
        Need (Test-Path -LiteralPath (Join-Path $PackageRoot $required) -PathType Leaf) ("下载的 Release 包缺少：{0}" -f $required)
    }
    # Manifest↔payload closure: the package must contain exactly the manifest
    # file set plus the manifest itself, so unmanifested payload cannot ride
    # along inside the release ZIP and reach the install directory.
    $entries = @($manifest.files)
    Need ($entries.Count -gt 0) 'RELEASE-MANIFEST.json 缺少文件清单'
    $manifestPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $entries) { [void]$manifestPaths.Add((([string]$entry.path)).Replace('\','/')) }
    [void]$manifestPaths.Add('RELEASE-MANIFEST.json')
    $actualPaths = @(Get-ChildItem -LiteralPath $PackageRoot -Recurse -File -Force | ForEach-Object { [IO.Path]::GetRelativePath(( [IO.Path]::GetFullPath($PackageRoot)), $_.FullName).Replace('\','/') })
    $actualSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($rel in $actualPaths) {
        [void]$actualSet.Add($rel)
        Need ($manifestPaths.Contains($rel)) ("Release 包含未在 RELEASE-MANIFEST 声明的文件：{0}" -f $rel)
    }
    foreach ($entry in $entries) {
        $rel = ([string]$entry.path).Replace('\','/')
        Need ($actualSet.Contains($rel)) ("Release 包缺少 RELEASE-MANIFEST 声明的文件：{0}" -f $rel)
    }
    return $manifest
}

function Start-ReleaseUpdateHandoff([string]$StagedRoot, [string]$ExpectedVersion, [string]$PackageType, [string]$ManifestSha256, [switch]$SyncMcp) {
    $currentRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    Need (-not (Test-AncestorChainHasReparse $currentRoot)) ("release_install_root_reparse_forbidden：{0}" -f $currentRoot)
    $parent = Split-Path -Parent $currentRoot
    $leaf = Split-Path -Leaf $currentRoot
    Need (-not [string]::IsNullOrWhiteSpace($parent) -and -not [string]::IsNullOrWhiteSpace($leaf)) '当前安装目录不适合自动替换'
    Need (-not [string]::IsNullOrWhiteSpace($ManifestSha256)) '缺少 RELEASE-MANIFEST 摘要，无法安全交接更新'
    $backupRoot = Join-Path $parent ("{0}.backup-{1}-{2}" -f $leaf, $ExpectedVersion, (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss'))
    $workerSource = Join-Path $currentRoot 'scripts\release\release-update-worker.ps1'
    Need (Test-Path -LiteralPath $workerSource -PathType Leaf) '当前安装缺少 release update worker；请手动安装新版本'
    $workerPath = Join-Path ([IO.Path]::GetTempPath()) ("skills-manager-release-update-{0}.ps1" -f ([guid]::NewGuid().ToString('N')))
    Copy-Item -LiteralPath $workerSource -Destination $workerPath -Force
    $pwsh = (Get-Command pwsh -ErrorAction Stop | Select-Object -First 1).Source
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$workerPath,'-CurrentRoot',$currentRoot,'-StagedRoot',$StagedRoot,'-BackupRoot',$backupRoot,'-ExpectedVersion',$ExpectedVersion,'-PackageType',$PackageType,'-ManifestSha256',$ManifestSha256,'-ParentProcessId',$PID)
    if ($SyncMcp) { $args += '-SyncMcp' }
    $process = Start-Process -FilePath $pwsh -ArgumentList $args -WorkingDirectory $parent -WindowStyle Hidden -PassThru
    return [pscustomobject][ordered]@{ status = 'handoff_started'; worker_pid = $process.Id; staged_root = $StagedRoot; backup_root = $backupRoot }
}

function Invoke-ReleaseUpdateCommand([string[]]$Tokens) {
    $options = Get-ReleaseUpdateTokens $Tokens
    $manifest = Get-ReleaseUpdateManifest
    $snapshot = Get-ReleaseUpdateSnapshot $options.repository $manifest
    $result = [ordered]@{ schema_version = 1; command = 'release-update'; action = $options.action; current_version = $snapshot.current_version; latest_version = $snapshot.latest_version; update_available = $snapshot.update_available; repository = $snapshot.repository; release_url = $snapshot.release_url; host_loaded = $false; live_accepted = $false }
    Need (-not ($snapshot.package -eq 'portable' -and $options.sync_mcp)) 'portable Release 更新不支持 --sync-mcp；请单独执行 MCP 同步'
    if ($options.action -eq 'check' -or -not $snapshot.update_available) {
        $result.status = if ($snapshot.update_available) { 'update_available' } else { 'up_to_date' }
        if ($options.json) { return ($result | ConvertTo-Json -Depth 8) }
        Write-Host ("Release 检查完成：{0} -> {1}（{2}）" -f $snapshot.current_version, $snapshot.latest_version, $result.status)
        return [pscustomobject]$result
    }

    Test-ReleaseUpdatePristineInstallation $Root $manifest | Out-Null
    $parent = Split-Path -Parent ([IO.Path]::GetFullPath($Root))
    $stage = Join-Path $parent (".skills-manager-release-stage-{0}" -f ([guid]::NewGuid().ToString('N')))
    $zip = Join-Path $stage $snapshot.package_name
    try {
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        Invoke-ReleaseUpdateHttpGet $snapshot.package_url $zip | Out-Null
        $actualHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        Need ($actualHash -eq $snapshot.package_sha256) '下载的 Release ZIP SHA-256 不匹配'
        $extract = Join-Path $stage 'extract'
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
        $roots = @(Get-ChildItem -LiteralPath $extract -Directory -Force)
        Need ($roots.Count -eq 1) 'Release ZIP 必须只包含一个根目录'
        $package = $roots[0].FullName
        $verifiedManifest = Test-ReleaseUpdatePackage $package $snapshot.latest_version $snapshot.package
        $manifestSha = (Get-FileHash -LiteralPath (Join-Path $package 'RELEASE-MANIFEST.json') -Algorithm SHA256).Hash.ToLowerInvariant()
        $handoff = Start-ReleaseUpdateHandoff $package $snapshot.latest_version $snapshot.package -ManifestSha256 $manifestSha -SyncMcp:$options.sync_mcp
        $result.status = $handoff.status; $result.worker_pid = $handoff.worker_pid; $result.backup_root = $handoff.backup_root
        if ($options.json) { return ($result | ConvertTo-Json -Depth 8) }
        Write-Host ("Release 更新已交给后台进程：{0}。旧目录备份将保留在：{1}" -f $handoff.worker_pid, $handoff.backup_root) -ForegroundColor Green
        return [pscustomobject]$result
    }
    catch {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
        throw
    }
}

function Get-ReleaseUpdateScheduleTokens([string[]]$Tokens) {
    $result = [ordered]@{ action = ''; time = '09:00'; auto_apply = $false; sync_mcp = $false; json = $false }
    foreach ($token in @($Tokens)) {
        $value = [string]$token
        switch -Regex ($value.ToLowerInvariant()) {
            '^--enable$' { $result.action = 'Enable'; continue }
            '^--disable$' { $result.action = 'Disable'; continue }
            '^--auto-apply$' { $result.auto_apply = $true; continue }
            '^--sync-mcp$' { $result.sync_mcp = $true; continue }
            '^--json$' { $result.json = $true; continue }
            '^--time=' { $result.time = $value.Substring(7); continue }
            default { throw ("release-update-schedule 不支持参数：{0}" -f $value) }
        }
    }
    Need ($result.action -in @('Enable','Disable')) 'release-update-schedule 必须指定 --enable 或 --disable'
    Need ($result.time -match '^([01]\d|2[0-3]):[0-5]\d$') 'release-update-schedule --time 必须为 HH:mm'
    Need ($result.action -eq 'Enable' -or (-not $result.auto_apply -and -not $result.sync_mcp)) '--auto-apply 和 --sync-mcp 仅可与 --enable 一起使用'
    return [pscustomobject]$result
}

function Invoke-ReleaseUpdateScheduleCommand([string[]]$Tokens) {
    $options = Get-ReleaseUpdateScheduleTokens $Tokens
    Get-ReleaseUpdateManifest | Out-Null
    $scriptPath = Join-Path $Root 'scripts\release\register-release-update-task.ps1'
    Need (Test-Path -LiteralPath $scriptPath -PathType Leaf) '当前安装缺少 Release 更新调度脚本；请手动安装新版本'
    $pwsh = (Get-Command pwsh -ErrorAction Stop | Select-Object -First 1).Source
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$scriptPath,'-Action',$options.action,'-Root',$Root,'-Time',$options.time)
    if ($options.auto_apply) { $args += '-AutoApply' }
    if ($options.sync_mcp) { $args += '-SyncMcp' }
    $raw = & $pwsh @args
    Need ($LASTEXITCODE -eq 0) ("Release 更新调度配置失败，exit={0}" -f $LASTEXITCODE)
    $result = ($raw | Out-String | ConvertFrom-Json)
    if ($options.json) { return ($result | ConvertTo-Json -Depth 8) }
    Write-Host ("Release 更新调度已{0}：{1}" -f $(if ($options.action -eq 'Enable') { '启用' } else { '停用' }), $result.task) -ForegroundColor Green
    return $result
}
