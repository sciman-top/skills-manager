$Root = (Resolve-Path ".").Path
$CfgPath = Join-Path $Root "skills.json"
$LogPath = Join-Path $Root "build.log"
$VendorDir = Join-Path $Root "vendor"
$AgentDir = Join-Path $Root "agent"
$OverridesDir = Join-Path $Root "overrides"
$ManualDir = Join-Path $Root "manual"
$ImportDir = Join-Path $Root "imports"

function Get-LogRotateMaxBytes {
    $v = $null
    if ($null -ne $script:LogMaxBytes) { $v = $script:LogMaxBytes }
    elseif ($null -ne $global:LogMaxBytes) { $v = $global:LogMaxBytes }
    try {
        $n = [int64]$v
        if ($n -gt 0) { return $n }
    }
    catch {}
    return 1048576
}
function Get-LogMaxBackups {
    $v = $null
    if ($null -ne $script:LogMaxBackups) { $v = $script:LogMaxBackups }
    elseif ($null -ne $global:LogMaxBackups) { $v = $global:LogMaxBackups }
    try {
        $n = [int]$v
        if ($n -gt 0) { return $n }
    }
    catch {}
    return 5
}
function Rotate-LogIfNeeded {
    if ([string]::IsNullOrWhiteSpace($LogPath)) { return }
    if (-not (Test-Path $LogPath)) { return }
    $maxBytes = Get-LogRotateMaxBytes
    $maxBackups = Get-LogMaxBackups
    try {
        $size = (Get-Item $LogPath -ErrorAction Stop).Length
        if ($size -lt $maxBytes) { return }
        for ($i = $maxBackups; $i -ge 1; $i--) {
            $src = if ($i -eq 1) { $LogPath } else { "{0}.{1}" -f $LogPath, ($i - 1) }
            $dst = "{0}.{1}" -f $LogPath, $i
            if (-not (Test-Path $src)) { continue }
            if (Test-Path $dst) { Remove-Item -Force $dst }
            Move-Item -Force $src $dst
        }
    }
    catch {}
}
function Write-LogRecord([string]$Level, [string]$Message, [object]$Data) {
    if ($DryRun) { return }
    Rotate-LogIfNeeded
    $record = [ordered]@{
        ts    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        level = $Level.ToUpperInvariant()
        msg   = $Message
    }
    if ($null -ne $Data) { $record.data = $Data }
    ($record | ConvertTo-Json -Depth 20 -Compress) | Out-File -FilePath $LogPath -Append -Encoding UTF8
}
function Log([string]$msg, [string]$Level = "INFO", [switch]$NoHost, [object]$Data) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $lvl = $Level.ToUpperInvariant()
    $line = "[{0}][{1}] {2}" -f $timestamp, $lvl, $msg
    if (-not $NoHost) {
        switch ($lvl) {
            "WARN" { Write-Host $line -ForegroundColor Yellow }
            "ERROR" { Write-Host $line -ForegroundColor Red }
            "DEBUG" { Write-Host $line -ForegroundColor DarkGray }
            default { Write-Host $line }
        }
    }
    Write-LogRecord $lvl $msg $Data
}
function Invoke-WithMetric(
    [string]$Metric,
    [scriptblock]$Action,
    [hashtable]$Data = $null,
    [switch]$NoHost
) {
    Need (-not [string]::IsNullOrWhiteSpace($Metric)) "metric 不能为空"
    Need ($null -ne $Action) "Action 不能为空"

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ok = $false
    try {
        $result = & $Action
        $ok = $true
        return $result
    }
    finally {
        $sw.Stop()
        $payload = [ordered]@{
            metric = $Metric
            duration_ms = [int]$sw.ElapsedMilliseconds
            success = $ok
        }
        if ($Data) {
            foreach ($k in $Data.Keys) {
                $payload[$k] = $Data[$k]
            }
        }
        Log ("性能埋点：{0}" -f $Metric) "INFO" -NoHost:$NoHost $payload
    }
}

function Invoke-RemoveItem([string]$path, [switch]$Recurse) {
    if (-not (Test-Path $path)) { return }
    $recurseFlag = if ($Recurse) { "-Recurse " } else { "" }
    Log ("Remove-Item {0}{1}" -f $recurseFlag, $path)
    if (-not $DryRun) {
        if ($Recurse) { Remove-Item -Recurse -Force $path }
        else { Remove-Item -Force $path }
    }
}
function Invoke-RemoveItemWithRetry(
    [string]$path,
    [switch]$Recurse,
    [int]$MaxAttempts = 4,
    [int]$DelayMs = 250,
    [switch]$IgnoreFailure,
    [switch]$SilentIgnore
) {
    if (-not (Test-Path $path)) { return $true }
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Invoke-RemoveItem $path -Recurse:$Recurse
            return $true
        }
        catch {
            if ($attempt -ge $MaxAttempts) {
                if ($IgnoreFailure) {
                    if (-not $SilentIgnore) {
                        Log ("清理失败（已忽略）：{0}；原因：{1}" -f $path, $_.Exception.Message) "WARN"
                    }
                    return $false
                }
                throw
            }
            Start-Sleep -Milliseconds $DelayMs
        }
    }
    return $false
}
function Invoke-MoveItem([string]$src, [string]$dst) {
    Log ("Move-Item {0} -> {1}" -f $src, $dst)
    if (-not $DryRun) { Move-Item -Force $src $dst }
}
function Invoke-StartProcess([string]$file, [string]$args) {
    Log ("Start-Process {0} {1}" -f $file, $args)
    if (-not $DryRun) {
        if ([string]::IsNullOrWhiteSpace($args)) {
            Start-Process -FilePath $file
        }
        else {
            Start-Process -FilePath $file -ArgumentList $args
        }
    }
}
function Invoke-MklinkJunction([string]$linkPath, [string]$targetPath) {
    Log ("cmd /c mklink /J `"{0}`" `"{1}`"" -f $linkPath, $targetPath)
    if ($DryRun) { return }
    & cmd /c mklink /J "$linkPath" "$targetPath" | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "mklink 失败：$linkPath -> $targetPath" }
}
function EnsureDir([string]$p) {
    if ($DryRun) { return }
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
}
function Set-ContentUtf8([string]$path, [string]$content) {
    if ($DryRun) { return }
    $parent = Split-Path $path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent)) { EnsureDir $parent }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $bytes = $utf8NoBom.GetBytes($content)
    $maxAttempts = 4
    $delayMs = 200
    for ($attempt = 0; $attempt -lt $maxAttempts; $attempt++) {
        try {
            [System.IO.File]::WriteAllBytes($path, $bytes)
            return
        }
        catch {
            $baseException = $_.Exception
            if ($baseException -is [System.Management.Automation.MethodInvocationException] -and $baseException.InnerException) {
                $baseException = $baseException.InnerException
            }
            $isRetryable = ($baseException -is [System.UnauthorizedAccessException]) -or ($baseException -is [System.IO.IOException])
            if (-not $isRetryable) { throw }

            if (Test-Path -LiteralPath $path -PathType Leaf) {
                try {
                    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
                    $resetAttrs = [System.IO.FileAttributes]::ReadOnly -bor [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System
                    if (($item.Attributes -band $resetAttrs) -ne 0) {
                        $item.Attributes = ($item.Attributes -band (-bnot $resetAttrs))
                    }
                }
                catch {}
            }

            if ($attempt -ge ($maxAttempts - 1)) { throw $baseException }
            Start-Sleep -Milliseconds $delayMs
        }
    }
}
function Get-ContentUtf8([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    return ([System.Text.Encoding]::UTF8.GetString($bytes))
}
function Resolve-RelativeSkillPlaceholderTarget([string]$skillFile, [string]$rootPath) {
    if ([string]::IsNullOrWhiteSpace($skillFile) -or [string]::IsNullOrWhiteSpace($rootPath)) { return $null }
    if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) { return $null }
    if (-not (Test-Path -LiteralPath $rootPath)) { return $null }

    $raw = Get-Content -LiteralPath $skillFile -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }

    $lines = @($raw -split "\r?\n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -ne 1) { return $null }

    $relative = $lines[0].Trim()
    if ([string]::IsNullOrWhiteSpace($relative)) { return $null }
    if ([System.IO.Path]::IsPathRooted($relative)) { return $null }
    if (-not ($relative -match "\.md$")) { return $null }

    $baseDir = Split-Path -Parent $skillFile
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $baseDir $relative))
    $rootFull = [System.IO.Path]::GetFullPath($rootPath)
    $selfFull = [System.IO.Path]::GetFullPath($skillFile)
    if ($candidate -eq $selfFull) { return $null }
    if (-not (Is-PathInsideOrEqual $candidate $rootFull)) { return $null }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $null }

    $targetRaw = Get-ContentUtf8 $candidate
    if ([string]::IsNullOrWhiteSpace($targetRaw)) { return $null }
    $targetNormalized = $targetRaw.TrimStart([char]0xFEFF).TrimStart()
    if ($targetNormalized -notmatch "^---(\r?\n|$)") { return $null }
    return $candidate
}
function Expand-RelativeSkillPlaceholders([string]$rootPath) {
    if ([string]::IsNullOrWhiteSpace($rootPath)) { return 0 }
    if (-not (Test-Path -LiteralPath $rootPath)) { return 0 }

    $count = 0
    foreach ($skillFile in (Get-ChildItem -LiteralPath $rootPath -Recurse -Filter "SKILL.md" -File -ErrorAction SilentlyContinue)) {
        $target = Resolve-RelativeSkillPlaceholderTarget $skillFile.FullName $rootPath
        if ([string]::IsNullOrWhiteSpace($target)) { continue }
        $content = Get-ContentUtf8 $target
        Set-ContentUtf8 $skillFile.FullName $content
        $count++
    }
    return $count
}
function Get-FileContentHash([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($path)
        try {
            $hash = $sha.ComputeHash($stream)
            return ([System.BitConverter]::ToString($hash) -replace "-", "").ToLowerInvariant()
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        $sha.Dispose()
    }
}
function Need($cond, [string]$msg) { if (-not $cond) { throw $msg } }
function Read-HostSafe([string]$prompt) {
    $value = Read-Host $prompt
    if ($null -eq $value) { return "" }
    return $value.Trim()
}
function Is-Yes([string]$answer) {
    if ([string]::IsNullOrWhiteSpace($answer)) { return $false }
    $v = $answer.Trim().ToLowerInvariant()
    return ($v -eq "y" -or $v -eq "yes")
}
function Confirm-Action([string]$prompt, [string]$token = "Y", [switch]$DefaultNo) {
    if ([string]::IsNullOrWhiteSpace($token)) { $token = "Y" }
    $suffix = if ($DefaultNo) { " (默认=N)" } else { "" }
    $userInput = Read-HostSafe ("{0}，输入 {1} 继续{2}" -f $prompt, $token, $suffix)
    if ($token -eq "Y") { return (Is-Yes $userInput) }
    if ([string]::IsNullOrWhiteSpace($userInput)) { return $false }
    return ($userInput.Equals($token, [System.StringComparison]::OrdinalIgnoreCase))
}
function Print-PreviewList([string]$title, [string[]]$items, [int]$maxShow = 20) {
    Write-Host $title
    if ($items.Count -eq 0) {
        Write-Host "- 无"
        return
    }
    $shown = 0
    foreach ($p in ($items | Sort-Object)) {
        Write-Host ("- {0}" -f $p)
        $shown++
        if ($shown -ge $maxShow) { break }
    }
    if ($items.Count -gt $maxShow) {
        Write-Host ("... 另有 {0} 项未显示" -f ($items.Count - $maxShow))
    }
}
function Print-ActionSummary([string]$title, [string[]]$items) {
    $count = if ($null -eq $items) { 0 } else { $items.Count }
    Write-Host ("{0}（{1} 项）" -f $title, $count)
    Print-PreviewList "预览（部分）：" $items
}
function Confirm-WithSummary([string]$title, [string[]]$items, [string]$confirmPrompt, [string]$token = "Y") {
    Print-ActionSummary $title $items
    return (Confirm-Action $confirmPrompt $token -DefaultNo)
}
function Skip-IfDryRun([string]$action) {
    if (-not $DryRun) { return $false }
    Write-Host ("DRYRUN：{0} 已跳过执行。" -f $action)
    return $true
}
function Start-DryRunMirrorCollect {
    if (-not $DryRun) { return }
    $script:CollectDryRunMirror = $true
    $script:DryRunMirrorCommands = New-Object System.Collections.Generic.List[string]
}
function Stop-DryRunMirrorCollect {
    $script:CollectDryRunMirror = $false
}
function Write-DryRunMirrorSummary([string]$title = "DRYRUN Robocopy 预览", [int]$maxShow = 20) {
    if (-not $DryRun) { return }
    if (-not $script:DryRunMirrorCommands) { return }
    $count = $script:DryRunMirrorCommands.Count
    if ($count -eq 0) { return }
    Write-Host ("{0}：共 {1} 条" -f $title, $count)
    $shown = 0
    foreach ($cmd in $script:DryRunMirrorCommands) {
        Write-Host $cmd
        $shown++
        if ($shown -ge $maxShow) { break }
    }
    if ($count -gt $maxShow) {
        Write-Host ("... 另有 {0} 条未显示" -f ($count - $maxShow))
    }
}
function Get-BuildSummary($cfg) {
    $manualCount = (收集ManualSkills $cfg).Count
    $overrideCount = (Get-OverridesDirs).Count
    return ("构建摘要：mappings={0}，imports(manual)={1}，overrides={2}，targets={3}，sync_mode={4}" -f $cfg.mappings.Count, $manualCount, $overrideCount, $cfg.targets.Count, $cfg.sync_mode)
}
function Write-BuildSummary($cfg = $null) {
    try {
        if ($null -eq $cfg) { $cfg = LoadCfg }
        Write-Host (Get-BuildSummary $cfg)
    }
    catch {}
}
function Format-VendorPreview($vendors) {
    return ($vendors | ForEach-Object { "$($_.name) :: $($_.repo)" })
}
function Get-DisplayVendor($item) {
    if ($null -eq $item) { return "" }
    if ($item.PSObject.Properties.Match("display_vendor").Count -gt 0) {
        $display = [string]$item.display_vendor
        if (-not [string]::IsNullOrWhiteSpace($display)) { return $display }
    }
    return [string]$item.vendor
}
function Format-MappingPreview($items, [string]$targetPrefix = "") {
    $prefix = if ([string]::IsNullOrWhiteSpace($targetPrefix)) { "" } else { ($targetPrefix + " ") }
    return ($items | ForEach-Object { "$prefix$(Get-DisplayVendor $_) :: $($_.from) -> $($_.to)" })
}
function Format-SkillPreview($items) {
    return ($items | ForEach-Object { "$(Get-DisplayVendor $_) :: $($_.from)" })
}
function Preflight {
    Need (Get-Command git -ErrorAction SilentlyContinue) "未找到 git，请先安装 Git 并确保在 PATH 中。"
    Need (Get-Command robocopy -ErrorAction SilentlyContinue) "未找到 robocopy，请确保在 PATH 中（Windows 默认包含）。"
    EnsureDir $VendorDir
    EnsureDir $AgentDir
    EnsureDir $OverridesDir
    EnsureDir $ImportDir
}
function RoboMirror([string]$src, [string]$dst) {
    EnsureDir $dst
    $cmd = "robocopy `"$src`" `"$dst`" /MIR /NFL /NDL /NJH /NJS /NP"
    if ($DryRun) {
        if ($script:CollectDryRunMirror) {
            if (-not $script:DryRunMirrorCommands) {
                $script:DryRunMirrorCommands = New-Object System.Collections.Generic.List[string]
            }
            $script:DryRunMirrorCommands.Add($cmd) | Out-Null
        }
        else {
            Write-Host $cmd
        }
        return
    }
    & robocopy $src $dst /MIR /NFL /NDL /NJH /NJS /NP 2>&1 |
    Where-Object { $_ -and $_.Trim() } |
    Out-Host
    if ($LASTEXITCODE -ge 8) { throw "robocopy 失败（exit=$LASTEXITCODE）：$src -> $dst" }
}
function Is-ReparsePoint([string]$path) {
    if (-not (Test-Path $path)) { return $false }
    $item = Get-Item $path -Force
    return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}
function Is-PathUnder([string]$path, [string]$root) {
    if ([string]::IsNullOrWhiteSpace($path) -or [string]::IsNullOrWhiteSpace($root)) { return $false }
    $rootNorm = $root.TrimEnd("\")
    return $path.StartsWith(($rootNorm + "\"), [System.StringComparison]::OrdinalIgnoreCase)
}
function Is-PathInsideOrEqual([string]$path, [string]$root) {
    if ([string]::IsNullOrWhiteSpace($path) -or [string]::IsNullOrWhiteSpace($root)) { return $false }
    try {
        $pathNorm = [System.IO.Path]::GetFullPath($path).TrimEnd("\")
        $rootNorm = [System.IO.Path]::GetFullPath($root).TrimEnd("\")
    }
    catch {
        return $false
    }
    if ($pathNorm.Equals($rootNorm, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $pathNorm.StartsWith(($rootNorm + "\"), [System.StringComparison]::OrdinalIgnoreCase)
}
function Is-DriveRoot([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    try {
        $full = [System.IO.Path]::GetFullPath($path).TrimEnd("\")
    }
    catch {
        return $false
    }
    return ($full -match "^[A-Za-z]:$")
}
function Test-SafeRelativePath([string]$path, [switch]$AllowDot) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    $p = $path.Trim().Replace("/", "\")
    if ([System.IO.Path]::IsPathRooted($p)) { return $false }
    if ($p -match "^[A-Za-z]:") { return $false }
    $parts = $p.Split("\") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($part in $parts) {
        if ($part -eq "..") { return $false }
    }
    if (-not $AllowDot -and $p -eq ".") { return $false }
    return $true
}
function Assert-SafeTargetDir([string]$targetPath) {
    Need (-not [string]::IsNullOrWhiteSpace($targetPath)) "target path 不能为空"
    Need (-not (Is-DriveRoot $targetPath)) ("target path 不能是盘符根目录：{0}" -f $targetPath)
    Need (-not (Is-PathInsideOrEqual $Root $targetPath)) ("target path 不能是仓库根或其父级：{0}" -f $targetPath)
    Need (-not (Is-PathInsideOrEqual $AgentDir $targetPath)) ("target path 不能是 agent/ 或其父级：{0}" -f $targetPath)
    Need (-not (Is-PathInsideOrEqual $targetPath $AgentDir)) ("target path 不能位于 agent/ 内部：{0}" -f $targetPath)
}
function Is-ExcludedPath([string]$path, [string[]]$roots) {
    foreach ($r in $roots) {
        if (Is-PathUnder $path $r) { return $true }
    }
    return $false
}
function Backup-DirIfNeeded([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    if (Is-ReparsePoint $path) { return $null }
    $parent = Split-Path $path -Parent
    $leaf = Split-Path $path -Leaf
    $bak = Join-Path $parent ("{0}.bak.{1}" -f $leaf, (Get-Date -Format "yyyyMMdd-HHmmss"))
    Invoke-MoveItem $path $bak
    return $bak
}
function Backup-OverrideDir([string]$overrideName) {
    $src = Join-Path $OverridesDir $overrideName
    if (-not (Test-Path $src)) { return $null }
    $bakRoot = Join-Path $OverridesDir ".bak"
    EnsureDir $bakRoot
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $bakName = "{0}.bak.{1}" -f $overrideName, $stamp
    $bakPath = Join-Path $bakRoot $bakName
    Invoke-MoveItem $src $bakPath
    return $bakPath
}
function New-Junction([string]$linkPath, [string]$targetPath) {
    EnsureDir $targetPath
    EnsureDir (Split-Path $linkPath -Parent)

    if (Test-Path $linkPath) {
        if (Is-ReparsePoint $linkPath) {
            Invoke-RemoveItem $linkPath -Recurse
        }
        else {
            Backup-DirIfNeeded $linkPath | Out-Null
        }
    }

    # mklink /J: 不需要管理员权限（Junction）
    Invoke-MklinkJunction $linkPath $targetPath
}
function Find-LatestBackup([string]$path) {
    $parent = Split-Path $path -Parent
    $leaf = Split-Path $path -Leaf
    $pattern = "{0}.bak.*" -f $leaf
    Get-ChildItem $parent -Directory -Filter $pattern -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}
function Remove-JunctionAndRestore([string]$linkPath) {
    if ((Test-Path $linkPath) -and (Is-ReparsePoint $linkPath)) {
        Invoke-RemoveItem $linkPath -Recurse
        $bak = Find-LatestBackup $linkPath
        if ($bak) {
            Invoke-MoveItem $bak.FullName $linkPath
        }
    }
    else {
        $bak = Find-LatestBackup $linkPath
        if ($bak) {
            if (Confirm-Action ("检测到备份：{0}，是否恢复？" -f $bak.Name) "Y" -DefaultNo) {
                if (Test-Path $linkPath) { Backup-DirIfNeeded $linkPath | Out-Null }
                Invoke-MoveItem $bak.FullName $linkPath
            }
            else {
                Write-Host ("已保留备份未恢复：{0}" -f $bak.FullName)
            }
        }
        else {
            Write-Host "当前不是链接目录：$linkPath"
        }
    }
}
function VendorPath([string]$vendorName) {
    return (Join-Path $VendorDir $vendorName)
}
function Normalize-Name([string]$name) {
    if ([string]::IsNullOrWhiteSpace($name)) { return $null }
    $n = $name.Trim()
    $n = $n -replace "[\\/]", "-"
    $n = $n -replace "[^A-Za-z0-9_-]", "-"
    $n = $n -replace "_", "-"
    $n = $n -replace "-{2,}", "-"
    $n = $n.Trim("-")
    $n = $n.ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($n)) { return $null }
    return $n
}
function Normalize-NameWithNotice([string]$name, [string]$label = "名称") {
    $norm = Normalize-Name $name
    Need (-not [string]::IsNullOrWhiteSpace($norm)) ("{0} 无法规范化，请更换名称：{1}" -f $label, $name)
    if ($name -ne $norm) {
        Write-Host ("{0} 已自动规范化：{1} -> {2}" -f $label, $name, $norm) -ForegroundColor Yellow
    }
    return $norm
}
function Normalize-SkillPath([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return "." }
    $p = $path.Trim()
    $p = $p -replace "/", "\"
    $p = $p.Trim("\")
    if ([string]::IsNullOrWhiteSpace($p)) { return "." }
    return $p
}
function To-GitPath([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return "." }
    $p = $path -replace "\\", "/"
    if ($p -eq ".") { return "." }
    return $p
}
function Clear-SkillsCache {
    $script:SkillCandidatesCache = @{}
    $script:SkillListCache = @{}
}
function Test-IsSkillDir([string]$path) {
    if (-not (Test-Path $path)) { return $false }
    $markers = @("SKILL.md", "AGENTS.md", "GEMINI.md", "CLAUDE.md")
    foreach ($m in $markers) {
        if (Test-Path (Join-Path $path $m)) { return $true }
    }
    return $false
}
function Get-SkillCandidates([string]$base) {
    if (-not $script:SkillCandidatesCache) { $script:SkillCandidatesCache = @{} }
    if ($script:SkillCandidatesCache.ContainsKey($base)) {
        return ,@($script:SkillCandidatesCache[$base])
    }
    $items = @()
    if (-not (Test-Path $base)) { return ,$items }
  
    # Find all potential marker files
    $found = Get-ChildItem $base -Recurse -File -ErrorAction SilentlyContinue | 
    Where-Object { $_.Name -match "^(SKILL|AGENTS|GEMINI|CLAUDE)\.md$" }
    
    $seenDirs = New-Object System.Collections.Generic.HashSet[string]
    foreach ($f in $found) {
        $dir = $f.Directory.FullName
        if (-not $seenDirs.Add($dir)) { continue }
    
        $rel = $dir.Substring($base.Length).TrimStart("\\")
        if ([string]::IsNullOrWhiteSpace($rel)) { $rel = "." }
        $items += [pscustomobject]@{ rel = $rel; leaf = (Split-Path $rel -Leaf) }
    }
    # Keep array shape for single-item results; callers rely on .Count.
    $items = @($items | Sort-Object rel)
    $script:SkillCandidatesCache[$base] = $items
    return ,$items
}
function Format-SkillCandidates([object[]]$items, [string]$base) {
    if ($items.Count -eq 0) { return "" }
    $lines = @()
    $lines += ("可选路径（共 {0}）：" -f $items.Count)
    foreach ($i in ($items | Select-Object -First 20)) {
        $lines += ("- {0}" -f $i.rel)
    }
    if ($items.Count -gt 20) {
        $lines += ("... 另有 {0} 项未显示" -f ($items.Count - 20))
    }
    $lines += ("提示：仓库内未发现 SKILL.md，但已搜索 AGENTS.md, GEMINI.md, CLAUDE.md 等入口文件。")
    return ($lines -join [Environment]::NewLine)
}
function Resolve-SkillPath([string]$base, [string]$skillPath) {
    $src = if ($skillPath -eq ".") { $base } else { Join-Path $base $skillPath }
    if (Test-IsSkillDir $src) { return $skillPath }

    # Common shorthand: allow "--skill foo" to resolve to "skills/foo".
    if ($skillPath -ne "." -and $skillPath -notmatch "[\\/]") {
        $prefixed = Join-Path "skills" $skillPath
        $prefixedSrc = Join-Path $base $prefixed
        if (Test-IsSkillDir $prefixedSrc) {
            Write-Host ("未找到指定路径，已自动补全为：{0}" -f $prefixed)
            return $prefixed
        }
    }

    $candidates = Get-SkillCandidates $base
    Need ($candidates.Count -gt 0) "仓库内未发现任何有效的技能标记文件（SKILL.md, AGENTS.md, GEMINI.md, CLAUDE.md）"

    if ($skillPath -ne ".") {
        $leaf = Split-Path $skillPath -Leaf
        $matches = $candidates | Where-Object { $_.leaf -eq $leaf }
        if ($matches.Count -eq 1) {
            Write-Host ("未找到指定路径，已按同名目录自动修正为：{0}" -f $matches[0].rel)
            return $matches[0].rel
        }
        if ($matches.Count -gt 1) {
            $msg = "未找到技能入口文件：{0}。提示：同名候选过多，请用 --skill 指定准确路径。" -f $src
            $msg += [Environment]::NewLine + (Format-SkillCandidates $matches $base)
            throw $msg
        }

        $leafNorm = Normalize-Name $leaf
        if (-not [string]::IsNullOrWhiteSpace($leafNorm)) {
            $fuzzyMatches = @($candidates | Where-Object {
                    $candNorm = Normalize-Name $_.leaf
                    if ([string]::IsNullOrWhiteSpace($candNorm)) { return $false }
                    return ($leafNorm -eq $candNorm) -or ($leafNorm.EndsWith("-$candNorm"))
                })
            if ($fuzzyMatches.Count -eq 1) {
                Write-Host ("未找到指定路径，已按后缀匹配自动修正为：{0}" -f $fuzzyMatches[0].rel)
                return $fuzzyMatches[0].rel
            }
            if ($fuzzyMatches.Count -gt 1) {
                $msg = "未找到技能入口文件：{0}。提示：后缀匹配候选过多，请用 --skill 指定准确路径。" -f $src
                $msg += [Environment]::NewLine + (Format-SkillCandidates $fuzzyMatches $base)
                throw $msg
            }
        }

        if ($candidates.Count -eq 1) {
            Write-Host ("未找到指定路径，仓库仅有一个技能入口目录，已自动使用：{0}" -f $candidates[0].rel)
            return $candidates[0].rel
        }
    }

    if ($skillPath -eq "." -and $candidates.Count -eq 1) {
        Write-Host ("仓库仅有一个技能入口目录，已自动使用：{0}" -f $candidates[0].rel)
        return $candidates[0].rel
    }

    $msg = "未找到技能入口文件：{0}。提示：请用 --skill 指定子目录（常见前缀：skills/、plugins/<plugin>/skills/）。" -f $src
    $msg += [Environment]::NewLine + (Format-SkillCandidates $candidates $base)
    throw $msg
}
function Split-Args([string]$line) {
    if ([string]::IsNullOrWhiteSpace($line)) { return @() }
    $tokens = New-Object System.Collections.Generic.List[string]
    $sb = New-Object System.Text.StringBuilder
    $inSingle = $false
    $inDouble = $false
    $everQuoted = $false
    $chars = $line.ToCharArray()
    for ($i = 0; $i -lt $chars.Length; $i++) {
        $ch = $chars[$i]
        if ($inDouble -and $ch -eq "\") {
            if ($i + 1 -lt $chars.Length -and ($chars[$i + 1] -eq '"' -or $chars[$i + 1] -eq "\")) {
                $i++
                $null = $sb.Append($chars[$i])
                continue
            }
        }
        if ($ch -eq "'" -and -not $inDouble) {
            $inSingle = -not $inSingle
            $everQuoted = $true
            continue
        }
        if ($ch -eq '"' -and -not $inSingle) {
            $inDouble = -not $inDouble
            $everQuoted = $true
            continue
        }
        if ([char]::IsWhiteSpace($ch) -and -not $inSingle -and -not $inDouble) {
            if ($sb.Length -gt 0 -or $everQuoted) {
                $tokens.Add($sb.ToString()) | Out-Null
                $sb.Clear() | Out-Null
                $everQuoted = $false
            }
            continue
        }
        $null = $sb.Append($ch)
    }
    if ($inSingle -or $inDouble) {
        throw "参数解析失败：存在未闭合的引号。"
    }
    if ($sb.Length -gt 0 -or $everQuoted) { $tokens.Add($sb.ToString()) | Out-Null }
    return $tokens.ToArray()
}
function Split-RepoSkillSuffix([string]$repoToken) {
    if ([string]::IsNullOrWhiteSpace($repoToken)) { return $null }
    $token = $repoToken.Trim()
    if ($token -notmatch "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@.+$") { return $null }
    $parts = $token.Split("@", 2)
    if ($parts.Count -ne 2) { return $null }
    if ([string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1])) { return $null }
    return [pscustomobject]@{
        repo = $parts[0]
        skill = $parts[1]
    }
}
function Parse-AddArgs([string[]]$tokens) {
    $result = [ordered]@{ repo = $null; skills = @(); ref = $null; mode = "manual"; sparse = $false; name = $null }
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $t = $tokens[$i]
        if ($t -match "^-") {
            $key = $t.ToLowerInvariant()
            if ($key -eq "--sparse") { $result.sparse = $true; continue }
            if ($key -match "^--skill=") {
                $val = $t.Substring(8)
                if ([string]::IsNullOrWhiteSpace($val)) { throw "参数值不能为空：--skill" }
                $result.skills += $val
                continue
            }
            if ($key -match "^--ref=") {
                $val = $t.Substring(6)
                if ([string]::IsNullOrWhiteSpace($val)) { throw "参数值不能为空：--ref" }
                $result.ref = $val
                continue
            }
            if ($key -match "^--mode=") {
                $val = $t.Substring(7)
                if ([string]::IsNullOrWhiteSpace($val)) { throw "参数值不能为空：--mode" }
                $result.mode = $val
                continue
            }
            if ($key -match "^--name=") {
                $val = $t.Substring(7)
                if ([string]::IsNullOrWhiteSpace($val)) { throw "参数值不能为空：--name" }
                $result.name = $val
                continue
            }
      
            if ($key -eq "--skill" -or $key -eq "--ref" -or $key -eq "--mode" -or $key -eq "--name") {
                if ($i + 1 -ge $tokens.Count) { throw "参数缺少值：$t" }
                $val = $tokens[++$i]
                if ($val -match "^-") { throw "参数缺少值：$t" }
                if ([string]::IsNullOrWhiteSpace($val)) { throw ("参数值不能为空：{0}" -f $key) }
                switch ($key) {
                    "--skill" { $result.skills += $val }
                    "--ref" { $result.ref = $val }
                    "--mode" { $result.mode = $val }
                    "--name" { $result.name = $val }
                }
                continue
            }
      
            # Handle flags that take a value but we want to ignore (like --agent, -a)
            if ($key -eq "--agent" -or $key -eq "-a") {
                if ($i + 1 -lt $tokens.Count) { $i++ }
                continue
            }
      
            # Handle boolean flags we want to ignore
            if ($key -eq "-g" -or $key -eq "--global" -or $key -eq "-y" -or $key -eq "--yes") {
                continue
            }

            Log ("未知参数：$t，已跳过。") "WARN"
        }
        else {
            if (-not $result.repo) { $result.repo = $t }
        }
    }
    Need (-not [string]::IsNullOrWhiteSpace($result.repo)) "缺少 repo 参数。示例：add <repo> --skill <name>"
    $repoSkill = Split-RepoSkillSuffix $result.repo
    if ($repoSkill -and $result.skills.Count -eq 0) {
        $result.repo = $repoSkill.repo
        $result.skills += $repoSkill.skill
        Write-Host ("检测到 repo@skill 写法，已自动转换为：repo={0} --skill {1}" -f $repoSkill.repo, $repoSkill.skill) -ForegroundColor Yellow
    }
    if ($result.skills.Count -eq 0) { $result.skills += "." }
    foreach ($skill in $result.skills) {
        if ([string]::IsNullOrWhiteSpace([string]$skill)) { throw "参数值不能为空：--skill" }
        $normalizedSkill = Normalize-SkillPath ([string]$skill)
        Need (Test-SafeRelativePath $normalizedSkill -AllowDot) ("skill 路径非法（仅允许相对路径，禁止 .. 与绝对路径）：{0}" -f $skill)
    }
    return $result
}
function Get-AddTokensFromNpx([string[]]$tokens) {
    if ($tokens.Count -eq 1) { $tokens = Split-Args $tokens[0] }
    if ($tokens.Count -eq 0) { throw "npx 参数为空。" }
    $first = $tokens[0].ToLowerInvariant()
    if ($first -eq "npx" -or $first -eq "npx.cmd") {
        if ($tokens.Count -eq 1) { throw "npx 参数为空。" }
        $tokens = $tokens[1..($tokens.Count - 1)]
    }
    if ($tokens.Count -ge 2 -and $tokens[0].ToLowerInvariant() -eq "skills" -and $tokens[1].ToLowerInvariant() -eq "add") {
        if ($tokens.Count -lt 3) { throw "缺少 repo 参数。示例：add <repo> --skill <name>" }
        return $tokens[2..($tokens.Count - 1)]
    }
    if ($tokens[0].ToLowerInvariant() -eq "add-skill") {
        if ($tokens.Count -ge 2) { return $tokens[1..($tokens.Count - 1)] }
        throw "缺少 repo 参数。示例：add <repo> --skill <name>"
    }
    throw "不支持的 npx 子命令。仅支持：skills add / add-skill"
}
function Get-AddTokensFromCommandLineTokens([string[]]$tokens) {
    if (-not $tokens -or $tokens.Count -eq 0) { return @() }

    $normalized = New-Object System.Collections.Generic.List[string]
    foreach ($t in $tokens) {
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        $normalized.Add($t)
    }
    if ($normalized.Count -eq 0) { return @() }
    $tokens = $normalized.ToArray()

    $head = $tokens[0].Trim().Trim("'`"")
    $headNorm = ($head -replace "/", "\").ToLowerInvariant()
    if ($headNorm -match "(^|\\)skills\.(ps1|cmd)$") {
        if ($tokens.Count -eq 1) { throw "缺少子命令。示例：add <repo> --skill <name>" }
        $tokens = $tokens[1..($tokens.Count - 1)]
        if ($tokens.Count -eq 0) { throw "缺少子命令。示例：add <repo> --skill <name>" }
        $headNorm = ($tokens[0].Trim().Trim("'`"") -replace "/", "\").ToLowerInvariant()
    }

    if ($headNorm -eq "npx" -or $headNorm -eq "npx.cmd") {
        return Get-AddTokensFromNpx $tokens
    }
    if ($headNorm -eq "skills") {
        if ($tokens.Count -eq 1) { throw "缺少子命令。仅支持：skills add <repo> --skill <name>" }
        $sub = $tokens[1].ToLowerInvariant()
        if ($sub -ne "add") { throw "不支持的 skills 子命令。仅支持：skills add" }
        if ($tokens.Count -lt 3) { throw "缺少 repo 参数。示例：add <repo> --skill <name>" }
        return $tokens[2..($tokens.Count - 1)]
    }
    if ($headNorm -eq "add") {
        if ($tokens.Count -eq 1) { throw "缺少 repo 参数。示例：add <repo> --skill <name>" }
        return $tokens[1..($tokens.Count - 1)]
    }
    return $tokens
}
function Merge-FilterAndArgs([string]$filter, [string[]]$tokens) {
    $merged = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($filter)) {
        $merged.Add($filter) | Out-Null
    }
    if ($tokens) {
        foreach ($t in $tokens) {
            if ($null -eq $t) { continue }
            $merged.Add([string]$t) | Out-Null
        }
    }
    return $merged.ToArray()
}
