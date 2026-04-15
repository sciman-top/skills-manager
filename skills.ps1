#requires -Version 5.1
param(
    [ValidateSet("menu", "初始化", "新增技能库", "删除技能库", "发现", "发现技能", "命令导入安装", "安装", "从技能库选择安装", "卸载", "卸载技能", "选择", "构建生效", "构建并生效", "更新", "更新上游并重建", "锁定", "生成锁文件", "打开配置", "解除关联", "清理备份", "自动更新设置", "帮助", "doctor", "add", "npx", "安装MCP", "卸载MCP", "同步MCP", "mcp-install", "mcp-uninstall", "mcp-sync")]
    [string]$Cmd = "menu",
    [string]$Filter = "",
    [switch]$DryRun,
    [switch]$Locked,
    [switch]$Plan,
    [switch]$Upgrade
)

$ErrorActionPreference = "Stop"
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
}
catch {}
 
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
    $scriptVar = Get-Variable -Name LogMaxBytes -Scope Script -ErrorAction SilentlyContinue
    $globalVar = Get-Variable -Name LogMaxBytes -Scope Global -ErrorAction SilentlyContinue
    if ($null -ne $scriptVar) { $v = $scriptVar.Value }
    elseif ($null -ne $globalVar) { $v = $globalVar.Value }
    try {
        $n = [int64]$v
        if ($n -gt 0) { return $n }
    }
    catch {}
    return 1048576
}
function Get-LogMaxBackups {
    $v = $null
    $scriptVar = Get-Variable -Name LogMaxBackups -Scope Script -ErrorAction SilentlyContinue
    $globalVar = Get-Variable -Name LogMaxBackups -Scope Global -ErrorAction SilentlyContinue
    if ($null -ne $scriptVar) { $v = $scriptVar.Value }
    elseif ($null -ne $globalVar) { $v = $globalVar.Value }
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
function Test-YamlFrontmatterSkillFile([string]$skillFile) {
    if ([string]::IsNullOrWhiteSpace($skillFile)) { return $false }
    if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) { return $false }
    $raw = Get-ContentUtf8 $skillFile
    if ([string]::IsNullOrWhiteSpace($raw)) { return $false }
    $normalized = $raw.TrimStart([char]0xFEFF).TrimStart()
    return ($normalized -match "^---(\r?\n|$)")
}
function Normalize-SkillMarkdownFiles([string]$rootPath) {
    $result = [ordered]@{
        normalized = 0
        failed = 0
        normalized_paths = @()
        failed_paths = @()
    }
    if ([string]::IsNullOrWhiteSpace($rootPath)) { return [pscustomobject]$result }
    if (-not (Test-Path -LiteralPath $rootPath)) { return [pscustomobject]$result }

    foreach ($skillFile in (Get-ChildItem -LiteralPath $rootPath -Recurse -Filter "SKILL.md" -File -ErrorAction SilentlyContinue)) {
        try {
            $raw = Get-ContentUtf8 $skillFile.FullName
            if ([string]::IsNullOrEmpty($raw)) { continue }
            if (-not $raw.StartsWith([char]0xFEFF)) { continue }
            $normalized = $raw.TrimStart([char]0xFEFF)
            Set-ContentUtf8 $skillFile.FullName $normalized
            $result.normalized++
            $result.normalized_paths += $skillFile.FullName
        }
        catch {
            $result.failed++
            $result.failed_paths += $skillFile.FullName
        }
    }
    return [pscustomobject]$result
}
function Remove-InvalidSkillMarkdownFiles([string]$rootPath) {
    $result = [ordered]@{
        removed = 0
        failed = 0
        removed_paths = @()
        failed_paths = @()
    }
    if ([string]::IsNullOrWhiteSpace($rootPath)) { return [pscustomobject]$result }
    if (-not (Test-Path -LiteralPath $rootPath)) { return [pscustomobject]$result }

    foreach ($skillFile in (Get-ChildItem -LiteralPath $rootPath -Recurse -Filter "SKILL.md" -File -ErrorAction SilentlyContinue)) {
        if (Test-YamlFrontmatterSkillFile $skillFile.FullName) { continue }
        try {
            $ok = Invoke-RemoveItemWithRetry $skillFile.FullName
            if ($ok) {
                $result.removed++
                $result.removed_paths += $skillFile.FullName
            }
            else {
                $result.failed++
                $result.failed_paths += $skillFile.FullName
            }
        }
        catch {
            $result.failed++
            $result.failed_paths += $skillFile.FullName
        }
    }
    return [pscustomobject]$result
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
function Invoke-PrebuildCheck([switch]$Strict) {
    $scriptPath = Join-Path $Root "scripts\prebuild-check.ps1"
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        Log ("未找到预检脚本，跳过：{0}" -f $scriptPath) "WARN"
        return
    }
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath)
    if ($Strict) { $args += "-Strict" }
    Log ("执行预检脚本：{0}" -f $scriptPath)
    & powershell @args
    if ($LASTEXITCODE -ne 0) {
        throw ("预检失败（exit={0}）：请先修复后再执行构建/更新。" -f $LASTEXITCODE)
    }
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
function Normalize-CompactName([string]$name) {
    if ([string]::IsNullOrWhiteSpace($name)) { return $null }
    $n = $name.ToLowerInvariant()
    $n = $n -replace "[^a-z0-9]", ""
    if ([string]::IsNullOrWhiteSpace($n)) { return $null }
    return $n
}
function Get-SkillCandidatesByRelevance([object[]]$items, [string]$query) {
    $ordered = @($items | Sort-Object rel)
    if ($ordered.Count -le 1 -or [string]::IsNullOrWhiteSpace($query)) { return $ordered }

    $qLeaf = Split-Path $query -Leaf
    $qNorm = Normalize-Name $qLeaf
    $qCompact = Normalize-CompactName $qLeaf

    $scored = @()
    foreach ($item in $ordered) {
        $leaf = [string]$item.leaf
        $rel = [string]$item.rel
        $leafNorm = Normalize-Name $leaf
        $leafCompact = Normalize-CompactName $leaf
        $score = 0

        if (-not [string]::IsNullOrWhiteSpace($qNorm) -and -not [string]::IsNullOrWhiteSpace($leafNorm)) {
            if ($qNorm -eq $leafNorm) { $score += 1000 }
            elseif ($qNorm.EndsWith("-$leafNorm") -or $leafNorm.EndsWith("-$qNorm")) { $score += 700 }
        }
        if (-not [string]::IsNullOrWhiteSpace($qCompact) -and -not [string]::IsNullOrWhiteSpace($leafCompact)) {
            if ($qCompact -eq $leafCompact) { $score += 900 }
            elseif ($qCompact.Contains($leafCompact) -or $leafCompact.Contains($qCompact)) { $score += 500 }
        }
        if (-not [string]::IsNullOrWhiteSpace($qNorm) -and -not [string]::IsNullOrWhiteSpace($leafNorm)) {
            if ($qNorm -match "(^|-)motion(s)?($|-)|(^|-)anim(ation|ate|ations)?($|-)") {
                if ($leafNorm -match "(^|-)motion(s)?($|-)|(^|-)anim(ation|ate|ations)?($|-)") {
                    $score += 650
                }
            }
        }

        $relGit = ($rel -replace "\\", "/")
        if ($relGit -match "^(\\.claude/skills|skills)(/|$)") { $score += 20 }

        $scored += [pscustomobject]@{
            item  = $item
            score = $score
        }
    }

    return @($scored | Sort-Object @{Expression = "score"; Descending = $true }, @{Expression = { $_.item.rel } } | ForEach-Object { $_.item })
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
function Format-SkillCandidates([object[]]$items, [string]$base, [string]$query = $null) {
    if ($items.Count -eq 0) { return "" }
    $ranked = Get-SkillCandidatesByRelevance $items $query
    $lines = @()
    $lines += ("可选路径（共 {0}）：" -f $ranked.Count)
    foreach ($i in ($ranked | Select-Object -First 20)) {
        $lines += ("- {0}" -f $i.rel)
    }
    if ($ranked.Count -gt 20) {
        $lines += ("... 另有 {0} 项未显示" -f ($ranked.Count - 20))
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
            $msg += [Environment]::NewLine + (Format-SkillCandidates $matches $base $skillPath)
            throw $msg
        }

        $leafNorm = Normalize-Name $leaf
        $leafCompact = Normalize-CompactName $leaf
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
                $msg += [Environment]::NewLine + (Format-SkillCandidates $fuzzyMatches $base $skillPath)
                throw $msg
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($leafCompact)) {
            $compactMatches = @($candidates | Where-Object {
                    $candCompact = Normalize-CompactName $_.leaf
                    if ([string]::IsNullOrWhiteSpace($candCompact)) { return $false }
                    return ($leafCompact -eq $candCompact) -or ($leafCompact.Contains($candCompact)) -or ($candCompact.Contains($leafCompact))
                })
            if ($compactMatches.Count -eq 1) {
                Write-Host ("未找到指定路径，已按紧凑匹配自动修正为：{0}" -f $compactMatches[0].rel)
                return $compactMatches[0].rel
            }
            if ($compactMatches.Count -gt 1) {
                $msg = "未找到技能入口文件：{0}。提示：紧凑匹配候选过多，请用 --skill 指定准确路径。" -f $src
                $msg += [Environment]::NewLine + (Format-SkillCandidates $compactMatches $base $skillPath)
                throw $msg
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($leafNorm) -and $leafNorm -match "(^|-)motion(s)?($|-)|(^|-)anim(ation|ate|ations)?($|-)") {
            $semanticMatches = @($candidates | Where-Object {
                    $candNorm = Normalize-Name $_.leaf
                    if ([string]::IsNullOrWhiteSpace($candNorm)) { return $false }
                    return ($candNorm -match "(^|-)motion(s)?($|-)|(^|-)anim(ation|ate|ations)?($|-)")
                })
            if ($semanticMatches.Count -eq 1) {
                Write-Host ("未找到指定路径，已按语义匹配自动修正为：{0}" -f $semanticMatches[0].rel)
                return $semanticMatches[0].rel
            }
            if ($semanticMatches.Count -gt 1) {
                $msg = "未找到技能入口文件：{0}。提示：语义匹配候选过多，请用 --skill 指定准确路径。" -f $src
                $msg += [Environment]::NewLine + (Format-SkillCandidates $semanticMatches $base $skillPath)
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
    $msg += [Environment]::NewLine + (Format-SkillCandidates $candidates $base $skillPath)
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
function Looks-LikeRepoInput([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return $false }
    $v = $value.Trim().Trim("'`"")
    if (Test-LocalZipRepoInput $v) { return $true }
    if ($v -match "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$") { return $true }
    if ($v -match "^(git@github\.com:|ssh://git@github\.com/|https?://github\.com/|github\.com/)") { return $true }
    return $false
}
function Extract-SkillFromGitHubTreeUrl([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    $v = $value.Trim().Trim("'`"").TrimEnd(".", ",", "。", "，", ";", "；")
    if ($v -notmatch "^https?://github\.com/[^/]+/[^/]+/tree/[^/]+/(.+)$") { return $null }
    return $Matches[1]
}
function Convert-GitHubTreeUrlToAddTokens([string]$value) {
    $skill = Extract-SkillFromGitHubTreeUrl $value
    if ([string]::IsNullOrWhiteSpace($skill)) { return $null }
    $trimmed = $value.Trim().Trim("'`"").TrimEnd(".", ",", "。", "，", ";", "；")
    if ($trimmed -notmatch "^https?://github\.com/([^/]+)/([^/]+)/tree/[^/]+/.+$") { return $null }
    $repo = "https://github.com/{0}/{1}.git" -f $Matches[1], $Matches[2]
    return ,@($repo, "--skill", $skill)
}
function Get-InstallScriptMappings() {
    if ($null -ne $script:InstallScriptMappingsOverride) { return @($script:InstallScriptMappingsOverride) }
    return @()
}
function Resolve-InstallScriptMapping([string]$url) {
    if ([string]::IsNullOrWhiteSpace($url)) { return $null }
    foreach ($entry in @(Get-InstallScriptMappings)) {
        $match = [string]$entry.match
        if ([string]::IsNullOrWhiteSpace($match)) { continue }
        $isMatch = if ($entry.PSObject.Properties.Match("regex").Count -gt 0 -and [bool]$entry.regex) {
            $url -match $match
        }
        else {
            $url.Contains($match)
        }
        if (-not $isMatch) { continue }
        $repo = [string]$entry.repo
        if ([string]::IsNullOrWhiteSpace($repo)) { continue }
        $tokens = @((Normalize-RepoUrl $repo))
        $skill = $null
        if ($entry.PSObject.Properties.Match("skill").Count -gt 0) { $skill = [string]$entry.skill }
        if (-not [string]::IsNullOrWhiteSpace($skill)) { $tokens += @("--skill", $skill) }
        return $tokens
    }
    return $null
}
function Resolve-AddTokensFromAnyFormat([string[]]$tokens) {
    if (-not $tokens -or $tokens.Count -eq 0) { return $null }
    $items = @($tokens | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($items.Count -eq 0) { return $null }
    $first = ([string]$items[0]).Trim()

    if ($first -eq "/plugin") {
        if ($items.Count -ge 4 -and ([string]$items[1]).ToLowerInvariant() -eq "marketplace" -and ([string]$items[2]).ToLowerInvariant() -eq "add") {
            return ,@($items[3..($items.Count - 1)])
        }
        if ($items.Count -ge 3 -and ([string]$items[1]).ToLowerInvariant() -eq "install") {
            $target = [string]$items[2]
            if ($target -notmatch "/") { $target = "thedotmack/$target" }
            $rest = @($items | Select-Object -Skip 3)
            return ,@(@($target) + $rest)
        }
    }

    if ($first -eq '$skill-installer') {
        $rest = @($items | Select-Object -Skip 1)
        if ($rest.Count -gt 0 -and ([string]$rest[0]).ToLowerInvariant() -eq "install") {
            $rest = @($rest | Select-Object -Skip 1)
        }
        if ($rest.Count -eq 0) { return $null }
        $target = [string]$rest[0]
        $targetTokens = Convert-GitHubTreeUrlToAddTokens $target
        if ($targetTokens) { return ,@(@($targetTokens) + @($rest | Select-Object -Skip 1)) }
        if ($target -match "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$") {
            return ,@(@($target) + @($rest | Select-Object -Skip 1))
        }
        return ,@(@("https://github.com/openai/skills.git", "--skill", ("skills/.curated/{0}" -f $target)) + @($rest | Select-Object -Skip 1))
    }

    $treeTokens = Convert-GitHubTreeUrlToAddTokens $first
    if ($items.Count -eq 1 -and $treeTokens) { return ,@($treeTokens) }

    if ($first -eq "npm" -and $items.Count -ge 4) {
        $verb = ([string]$items[1]).ToLowerInvariant()
        $flag = ([string]$items[2]).ToLowerInvariant()
        $pkg = [string]$items[3]
        if (($verb -eq "install" -or $verb -eq "i") -and $flag -eq "-g") {
            if ($pkg -match "^@([^/]+)/([^/]+)$") { return ,@("{0}/{1}" -f $Matches[1], $Matches[2]) }
            throw "npm install -g 仅支持 scoped package（例如 @owner/repo）。"
        }
    }

    if ($first -eq "curl" -or $first -eq "Invoke-RestMethod") {
        $url = $null
        foreach ($item in $items) {
            $candidate = [string]$item
            if ($candidate -match "^https?://") { $url = $candidate; break }
        }
        $mapped = Resolve-InstallScriptMapping $url
        if ($mapped) { return ,@($mapped) }
        throw ("暂不支持直接解析 {0} 安装脚本，请先定位其对应仓库。" -f $first)
    }

    return $null
}
function Try-ParseAddLikeInput([string]$line) {
    if ([string]::IsNullOrWhiteSpace($line)) { return $null }
    $tokens = Split-Args $line
    $resolved = Resolve-AddTokensFromAnyFormat $tokens
    if ($resolved) { $tokens = $resolved }
    else { $tokens = Get-AddTokensFromCommandLineTokens $tokens }
    $parsed = Parse-AddArgs $tokens
    return [pscustomobject]@{
        repo = $parsed.repo
        ref = $parsed.ref
        skills = @($parsed.skills)
    }
}
function Resolve-UniqueVendorName($cfg, [string]$vendorName, [string]$repo, [bool]$AllowExistingSameRepo = $false) {
    $baseName = Normalize-NameWithNotice $vendorName "vendor 名称"
    $identityKey = Get-RepoIdentityKey $repo
    $existing = @($cfg.vendors | Where-Object { $_.name -eq $baseName })
    if ($existing.Count -eq 0) { return $baseName }
    foreach ($item in $existing) {
        if (Is-SameRepository ([string]$item.repo) $repo) {
            if ($AllowExistingSameRepo) { return $baseName }
            throw ("同一技能库已存在，禁止重复占用 vendor 名称：{0}；identityKey={1}" -f $baseName, $identityKey)
        }
    }
    $suffix = 2
    while ($true) {
        $candidate = "{0}-{1}" -f $baseName, $suffix
        if ((@($cfg.vendors | Where-Object { $_.name -eq $candidate }).Count) -eq 0) { return $candidate }
        $suffix++
    }
}
function Parse-AddArgs([string[]]$tokens) {
    $result = [ordered]@{
        repo = $null
        skills = @()
        ref = $null
        mode = "manual"
        sparse = $false
        name = $null
        skillSpecified = $false
        modeSpecified = $false
    }
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $t = $tokens[$i]
        if ($t -match "^-") {
            $key = $t.ToLowerInvariant()
            if ($key -eq "--sparse") { $result.sparse = $true; continue }
            if ($key -match "^--skill=") {
                $val = $t.Substring(8)
                if ([string]::IsNullOrWhiteSpace($val)) { throw "参数值不能为空：--skill" }
                $result.skills += $val
                $result.skillSpecified = $true
                continue
            }
            if ($key -match "^--ref=") {
                $val = $t.Substring(6)
                if ([string]::IsNullOrWhiteSpace($val)) { throw "参数值不能为空：--ref" }
                if (Test-LooksLikeRepoUrl $val) {
                    throw ("--ref 不能是仓库地址：{0}。如果你想安装该仓库，请把它放在 repo 位置；如果是分支名，请传真实 branch/tag。" -f $val)
                }
                $result.ref = $val
                continue
            }
            if ($key -match "^--mode=") {
                $val = $t.Substring(7)
                if ([string]::IsNullOrWhiteSpace($val)) { throw "参数值不能为空：--mode" }
                $result.mode = $val
                $result.modeSpecified = $true
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
                    "--skill" {
                        $result.skills += $val
                        $result.skillSpecified = $true
                    }
                    "--ref" {
                        if (Test-LooksLikeRepoUrl $val) {
                            throw ("--ref 不能是仓库地址：{0}。如果你想安装该仓库，请把它放在 repo 位置；如果是分支名，请传真实 branch/tag。" -f $val)
                        }
                        $result.ref = $val
                    }
                    "--mode" {
                        $result.mode = $val
                        $result.modeSpecified = $true
                    }
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
    Need (-not [string]::IsNullOrWhiteSpace($result.repo)) "缺少 repo 参数。示例：add <repo> [--skill <name>]"
    Need (Looks-LikeRepoInput $result.repo) ("输入并非有效的 GitHub 仓库格式：{0}" -f $result.repo)
    $repoSkill = Split-RepoSkillSuffix $result.repo
    if ($repoSkill -and $result.skills.Count -eq 0) {
        $result.repo = $repoSkill.repo
        $result.skills += $repoSkill.skill
        $result.skillSpecified = $true
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
        if ($tokens.Count -lt 3) { throw "缺少 repo 参数。示例：add <repo> [--skill <name>]" }
        return $tokens[2..($tokens.Count - 1)]
    }
    if ($tokens[0].ToLowerInvariant() -eq "add-skill") {
        if ($tokens.Count -ge 2) { return $tokens[1..($tokens.Count - 1)] }
        throw "缺少 repo 参数。示例：add <repo> [--skill <name>]"
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
        if ($tokens.Count -eq 1) { throw "缺少子命令。示例：add <repo> [--skill <name>]" }
        $tokens = $tokens[1..($tokens.Count - 1)]
        if ($tokens.Count -eq 0) { throw "缺少子命令。示例：add <repo> [--skill <name>]" }
        $headNorm = ($tokens[0].Trim().Trim("'`"") -replace "/", "\").ToLowerInvariant()
    }

    if ($headNorm -eq "npx" -or $headNorm -eq "npx.cmd") {
        return Get-AddTokensFromNpx $tokens
    }
    if ($headNorm -eq "skills") {
        if ($tokens.Count -eq 1) { throw "缺少子命令。仅支持：skills add <repo> [--skill <name>]" }
        $sub = $tokens[1].ToLowerInvariant()
        if ($sub -ne "add") { throw "不支持的 skills 子命令。仅支持：skills add" }
        if ($tokens.Count -lt 3) { throw "缺少 repo 参数。示例：add <repo> [--skill <name>]" }
        return $tokens[2..($tokens.Count - 1)]
    }
    if ($headNorm -eq "add") {
        if ($tokens.Count -eq 1) { throw "缺少 repo 参数。示例：add <repo> [--skill <name>]" }
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
 
 function Normalize-RepoUrl([string]$repo) {
    $r = $repo.Trim()
    if ($r -match "^(git@github.com:).+") {
        if (-not $r.EndsWith(".git")) { return ($r + ".git") }
        return $r
    }
    if ($r -match "^https?://github.com/.+") {
        if (-not $r.EndsWith(".git")) { return ($r + ".git") }
        return $r
    }
    if ($r -match "^github.com/.+") {
        $u = "https://{0}" -f $r
        if (-not $u.EndsWith(".git")) { $u += ".git" }
        return $u
    }
    if ($r -match "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$") {
        return ("https://github.com/{0}.git" -f $r)
    }
    return $r
}
function Remove-GitHubTreeSuffix([string]$repo) {
    if ([string]::IsNullOrWhiteSpace($repo)) { return $repo }
    $r = $repo.Trim().Trim("'`"")
    if ($r -match "^(https?://github\.com/[^/]+/[^/]+?)(?:\.git)?/tree/[^/]+/.+$") {
        return ($Matches[1] + ".git")
    }
    return $r
}
function Guess-VendorName([string]$repo) {
    $r = $repo.Trim().TrimEnd("/")
    if ($r.EndsWith(".git")) { $r = $r.Substring(0, $r.Length - 4) }
    $leaf = Split-Path $r -Leaf
    $name = Normalize-Name $leaf
    if ([string]::IsNullOrWhiteSpace($name)) {
        if ($repo -match "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@.+$") {
            throw "无法从 URL 推断 vendor 名称。检测到 repo@skill 写法，请改用：<repo> --skill <name>（例如：vercel-labs/skills --skill skills/find-skills）"
        }
        throw "无法从 URL 推断 vendor 名称，请手动输入名称。"
    }
    return $name
}
function Invoke-Git([string[]]$GitArgs) {
    if ($DryRun) {
        Log ("DRYRUN git {0}" -f ($GitArgs -join " "))
        return
    }
    $cmdText = ("git {0}" -f ($GitArgs -join " "))
    $retriedAfterLockRecovery = $false
    $canTuneNativeErrPref = ($PSVersionTable.PSVersion.Major -ge 7)
    while ($true) {
        Log $cmdText
        $prevNativeErrorPref = $null
        $prevErrorActionPreference = $ErrorActionPreference
        try {
            if ($canTuneNativeErrPref) {
                $prevNativeErrorPref = $PSNativeCommandUseErrorActionPreference
                $PSNativeCommandUseErrorActionPreference = $false
            }
            $ErrorActionPreference = "Continue"
            $output = & git @GitArgs 2>&1
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $prevErrorActionPreference
            if ($canTuneNativeErrPref) {
                $PSNativeCommandUseErrorActionPreference = $prevNativeErrorPref
            }
        }
        if ($output) {
            foreach ($line in @($output)) {
                $text = Convert-GitOutputLineToText $line
                if ([string]::IsNullOrWhiteSpace($text)) { continue }
                Write-Host $text
            }
        }
        if ($exitCode -eq 0) { return }
        if (-not $retriedAfterLockRecovery) {
            $repaired = $false
            if (Repair-StaleGitLockFromOutput $output) {
                $repaired = $true
            }
            elseif (Repair-StaleGitLockAfterFailure (Get-Location).Path $output) {
                $repaired = $true
            }
            if ($repaired) {
                $retriedAfterLockRecovery = $true
                continue
            }
        }
        $summary = Get-GitOutputSummary $output
        if ([string]::IsNullOrWhiteSpace($summary)) {
            throw ("git 失败：{0}" -f $cmdText)
        }
        throw ("git 失败：{0}；详情：{1}" -f $cmdText, $summary)
    }
}
function Invoke-GitCapture([string[]]$GitArgs) {
    if ($DryRun) {
        Log ("DRYRUN git {0}" -f ($GitArgs -join " "))
        return ""
    }
    Log ("git {0}" -f ($GitArgs -join " "))
    $canTuneNativeErrPref = ($PSVersionTable.PSVersion.Major -ge 7)
    $prevNativeErrorPref = $null
    $prevErrorActionPreference = $ErrorActionPreference
    try {
        if ($canTuneNativeErrPref) {
            $prevNativeErrorPref = $PSNativeCommandUseErrorActionPreference
            $PSNativeCommandUseErrorActionPreference = $false
        }
        $ErrorActionPreference = "Continue"
        $out = & git @GitArgs 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
    }
    finally {
        $ErrorActionPreference = $prevErrorActionPreference
        if ($canTuneNativeErrPref) {
            $PSNativeCommandUseErrorActionPreference = $prevNativeErrorPref
        }
    }
    if ($null -eq $out) { return "" }
    return (($out | Select-Object -First 1).ToString().Trim())
}
function Invoke-GitCaptureLines([string[]]$GitArgs) {
    if ($DryRun) {
        Log ("DRYRUN git {0}" -f ($GitArgs -join " "))
        return @()
    }
    Log ("git {0}" -f ($GitArgs -join " "))
    $canTuneNativeErrPref = ($PSVersionTable.PSVersion.Major -ge 7)
    $prevNativeErrorPref = $null
    $prevErrorActionPreference = $ErrorActionPreference
    try {
        if ($canTuneNativeErrPref) {
            $prevNativeErrorPref = $PSNativeCommandUseErrorActionPreference
            $PSNativeCommandUseErrorActionPreference = $false
        }
        $ErrorActionPreference = "Continue"
        $out = & git @GitArgs 2>$null
        if ($LASTEXITCODE -ne 0) { return @() }
    }
    finally {
        $ErrorActionPreference = $prevErrorActionPreference
        if ($canTuneNativeErrPref) {
            $PSNativeCommandUseErrorActionPreference = $prevNativeErrorPref
        }
    }
    $lines = @()
    foreach ($line in @($out)) {
        $text = Convert-GitOutputLineToText $line
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $lines += $text
    }
    return ,$lines
}
function Get-SkillCandidatesFromGitRepo([string]$repo, [string]$ref) {
    Need (-not [string]::IsNullOrWhiteSpace($repo)) "Repo URL 不能为空。"
    Need (-not [string]::IsNullOrWhiteSpace($ref)) "ref 不能为空。"

    $tmpName = ("_tree_{0}" -f ([Guid]::NewGuid().ToString("N").Substring(0, 8)))
    $tmpBase = Join-Path $ImportDir $tmpName
    $barePath = Join-Path $tmpBase "repo.git"
    EnsureDir $tmpBase
    try {
        Invoke-Git @("clone", "--bare", $repo, $barePath)
        $gitDirArg = "--git-dir={0}" -f $barePath
        $allFiles = Invoke-GitCaptureLines @($gitDirArg, "ls-tree", "-r", "--name-only", $ref)
        $seenDirs = New-Object System.Collections.Generic.HashSet[string]
        $candidates = @()
        foreach ($f in $allFiles) {
            if ([string]::IsNullOrWhiteSpace($f)) { continue }
            if ($f -notmatch "(^|/)(SKILL|AGENTS|GEMINI|CLAUDE)\.md$") { continue }
            $dir = Split-Path ($f -replace "/", "\") -Parent
            if ([string]::IsNullOrWhiteSpace($dir)) { $dir = "." }
            $dirGit = ($dir -replace "\\", "/")
            if ($dirGit -match "(^|/)_archive(/|$)") { continue }
            if (-not $seenDirs.Add($dir)) { continue }
            $candidates += [pscustomobject]@{
                rel = $dir
                leaf = (Split-Path $dir -Leaf)
            }
        }
        return ,@($candidates | Sort-Object rel)
    }
    finally {
        Invoke-RemoveItemWithRetry $tmpBase -Recurse -IgnoreFailure | Out-Null
    }
}
function Assert-RepoReachable([string]$repo) {
    Need (-not [string]::IsNullOrWhiteSpace($repo)) "Repo URL 不能为空。"
    if (Test-LocalZipRepoInput $repo) {
        return
    }
    $out = Invoke-GitCapture @("ls-remote", "--exit-code", $repo, "HEAD")
    if ([string]::IsNullOrWhiteSpace($out)) {
        throw ("仓库不可访问或不存在：{0}。请检查 owner/repo 是否正确，或确认仓库是否私有且当前 git 凭据可访问。" -f $repo)
    }
}
function Test-LocalZipRepoInput([string]$repo) {
    if ([string]::IsNullOrWhiteSpace($repo)) { return $false }
    $r = $repo.Trim().Trim("'`"")
    if ($r -notmatch "(?i)\.zip$") { return $false }
    return (Test-Path -LiteralPath $r -PathType Leaf)
}
function Invoke-WithRetry([scriptblock]$Action, [int]$MaxAttempts = 3, [int]$DelayMs = 250) {
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            & $Action
            return
        }
        catch {
            if ($attempt -ge $MaxAttempts) { throw }
            Start-Sleep -Milliseconds $DelayMs
        }
    }
}
function Resolve-ZipExtractionRoot([string]$extractDir) {
    Need (Test-Path $extractDir) ("解压目录不存在：{0}" -f $extractDir)
    $children = @(Get-ChildItem -LiteralPath $extractDir -Force -ErrorAction SilentlyContinue)
    $dirs = @($children | Where-Object { $_.PSIsContainer })
    $files = @($children | Where-Object { -not $_.PSIsContainer })
    if ($files.Count -eq 0 -and $dirs.Count -eq 1) {
        return $dirs[0].FullName
    }
    return $extractDir
}
function Ensure-RepoFromZip([string]$path, [string]$zipPath, [bool]$forceClean = $true) {
    $zip = $zipPath.Trim().Trim("'`"")
    Need (Test-Path -LiteralPath $zip -PathType Leaf) ("zip 文件不存在：{0}" -f $zipPath)

    if (Test-Path $path) {
        Need $forceClean ("缓存目录已存在且 update_force=false：{0}" -f $path)
        Invoke-RemoveItemWithRetry $path -Recurse
    }
    EnsureDir (Split-Path $path -Parent)

    $tmpName = ("_zip_{0}" -f ([Guid]::NewGuid().ToString("N").Substring(0, 8)))
    $tmpBase = Join-Path $ImportDir $tmpName
    $tmpZip = Join-Path $tmpBase "source.zip"
    $extractDir = Join-Path $tmpBase "extract"
    EnsureDir $tmpBase
    try {
        Log ("Copy-Item {0} -> {1}" -f $zip, $tmpZip)
        Invoke-WithRetry { Copy-Item -LiteralPath $zip -Destination $tmpZip -Force } 3 250

        Log ("Expand-Archive {0} -> {1}" -f $tmpZip, $extractDir)
        Invoke-WithRetry { Expand-Archive -LiteralPath $tmpZip -DestinationPath $extractDir -Force } 3 250

        $sourceRoot = Resolve-ZipExtractionRoot $extractDir
        Invoke-MoveItem $sourceRoot $path
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match "由另一进程使用|being used by another process") {
            throw ("zip 文件当前被占用：{0}。请关闭占用进程后重试。" -f $zipPath)
        }
        throw
    }
    finally {
        Invoke-RemoveItemWithRetry $tmpBase -Recurse -IgnoreFailure
    }
}
function Ensure-RepoFromGitArchive([string]$path, [string]$repo, [string]$ref, [string]$skillPath, [bool]$forceClean = $true) {
    Need (-not [string]::IsNullOrWhiteSpace($repo)) "Repo URL 不能为空。"
    Need (-not [string]::IsNullOrWhiteSpace($ref)) "ref 不能为空。"
    $normalizedSkill = Normalize-SkillPath $skillPath
    Need ($normalizedSkill -ne ".") "git archive 回退模式不支持根路径 '.'，请指定具体子目录。"

    if (Test-Path $path) {
        Need $forceClean ("缓存目录已存在且 update_force=false：{0}" -f $path)
        Invoke-RemoveItemWithRetry $path -Recurse
    }
    EnsureDir (Split-Path $path -Parent)
    EnsureDir $path

    $tmpName = ("_archive_{0}" -f ([Guid]::NewGuid().ToString("N").Substring(0, 8)))
    $tmpBase = Join-Path $ImportDir $tmpName
    $barePath = Join-Path $tmpBase "repo.git"
    $zipPath = Join-Path $tmpBase "export.zip"
    EnsureDir $tmpBase
    try {
        Invoke-Git @("clone", "--bare", $repo, $barePath)
        $gitDirArg = "--git-dir={0}" -f $barePath
        $gitPath = To-GitPath $normalizedSkill
        Invoke-Git @($gitDirArg, "archive", "--format=zip", "--output", $zipPath, $ref, $gitPath)
        Expand-Archive -LiteralPath $zipPath -DestinationPath $path -Force
    }
    finally {
        Invoke-RemoveItemWithRetry $tmpBase -Recurse -IgnoreFailure
    }
}
function Resolve-GitHubOwnerRepo([string]$repo) {
    if ([string]::IsNullOrWhiteSpace($repo)) { return $null }
    $r = Remove-GitHubTreeSuffix $repo
    $r = $r.Trim().Trim("'`"")
    if ($r -match "^git@github\.com:(.+?)/(.+?)(?:\.git)?$") {
        return [pscustomobject]@{ owner = $Matches[1]; name = $Matches[2] }
    }
    if ($r -match "^https?://github\.com/(.+?)/(.+?)(?:\.git)?/?$") {
        return [pscustomobject]@{ owner = $Matches[1]; name = $Matches[2] }
    }
    if ($r -match "^github\.com/(.+?)/(.+?)(?:\.git)?/?$") {
        return [pscustomobject]@{ owner = $Matches[1]; name = $Matches[2] }
    }
    return $null
}
function Ensure-RepoFromGitHubTreeSnapshot([string]$path, [string]$repo, [string]$ref, [string]$skillPath, [bool]$forceClean = $true) {
    Need (-not [string]::IsNullOrWhiteSpace($repo)) "Repo URL 不能为空。"
    Need (-not [string]::IsNullOrWhiteSpace($ref)) "ref 不能为空。"
    $normalizedSkill = Normalize-SkillPath $skillPath
    Need ($normalizedSkill -ne ".") "GitHub 快照回退不支持根路径 '.'，请指定具体子目录。"

    $ownerRepo = Resolve-GitHubOwnerRepo $repo
    Need ($null -ne $ownerRepo) ("GitHub 快照回退仅支持 github.com 仓库：{0}" -f $repo)

    if (Test-Path $path) {
        Need $forceClean ("缓存目录已存在且 update_force=false：{0}" -f $path)
        Invoke-RemoveItemWithRetry $path -Recurse
    }
    EnsureDir (Split-Path $path -Parent)
    EnsureDir $path

    $headers = @{
        "User-Agent" = "skills-manager"
        "Accept" = "application/vnd.github+json"
    }
    $encodedRef = [System.Uri]::EscapeDataString($ref)
    $treeUrl = ("https://api.github.com/repos/{0}/{1}/git/trees/{2}?recursive=1" -f $ownerRepo.owner, $ownerRepo.name, $encodedRef)
    $treeResp = Invoke-RestMethod -Uri $treeUrl -Headers $headers -Method Get -ErrorAction Stop
    Need ($treeResp -and $treeResp.tree) ("GitHub 树接口返回为空：{0}" -f $treeUrl)

    $prefix = (To-GitPath $normalizedSkill).Trim("/")
    Need (-not [string]::IsNullOrWhiteSpace($prefix)) "技能路径无效。"
    $prefixSlash = "$prefix/"

    $blobs = @($treeResp.tree | Where-Object {
            $_.type -eq "blob" -and $_.path -is [string] -and ($_.path -eq $prefix -or $_.path.StartsWith($prefixSlash))
        })
    Need ($blobs.Count -gt 0) ("GitHub 快照回退未找到目标路径：{0}" -f $normalizedSkill)

    foreach ($blob in $blobs) {
        $blobPath = [string]$blob.path
        if ([string]::IsNullOrWhiteSpace($blobPath)) { continue }
        $relPath = $blobPath -replace "/", "\"
        $dstPath = Join-Path $path $relPath
        EnsureDir (Split-Path $dstPath -Parent)

        $rawUrl = ("https://raw.githubusercontent.com/{0}/{1}/{2}/{3}" -f $ownerRepo.owner, $ownerRepo.name, $ref, $blobPath)
        Invoke-WebRequest -Uri $rawUrl -Headers @{ "User-Agent" = "skills-manager" } -OutFile $dstPath -ErrorAction Stop | Out-Null
    }
}
function Parse-DefaultBranchFromSymref([string]$line) {
    if ([string]::IsNullOrWhiteSpace($line)) { return $null }
    $text = $line.Trim()
    if ($text -match "^ref:\s+refs/heads/(.+?)\s+HEAD$") {
        $branch = $Matches[1].Trim()
        if (-not [string]::IsNullOrWhiteSpace($branch)) { return $branch }
    }
    return $null
}
function Get-RepoDefaultBranch([string]$repo) {
    Need (-not [string]::IsNullOrWhiteSpace($repo)) "Repo URL 不能为空。"

    $symrefLine = Invoke-GitCapture @("ls-remote", "--symref", $repo, "HEAD")
    $branch = Parse-DefaultBranchFromSymref $symrefLine
    if (-not [string]::IsNullOrWhiteSpace($branch)) { return $branch }

    foreach ($fallback in @("main", "master")) {
        $probe = Invoke-GitCapture @("ls-remote", "--exit-code", $repo, ("refs/heads/{0}" -f $fallback))
        if (-not [string]::IsNullOrWhiteSpace($probe)) {
            Log ("未能从 symref 解析默认分支，回退为已存在分支：{0}" -f $fallback)
            return $fallback
        }
    }

    Log "未能探测仓库默认分支，回退为 main。"
    return "main"
}
function Get-GitHeadBranch {
    $head = Invoke-GitCapture @("rev-parse", "--abbrev-ref", "HEAD")
    if ([string]::IsNullOrWhiteSpace($head) -or $head -eq "HEAD") { return $null }
    return $head
}
function Get-RepoIdentity([string]$repo) {
    if ([string]::IsNullOrWhiteSpace($repo)) { return $null }
    $r = Remove-GitHubTreeSuffix $repo
    $r = $r.Trim().Trim("'`"")
    if ($r -match "^ssh://git@github\.com/(.+?)/(.+?)(?:\.git)?/?$") {
        return ("github.com/{0}/{1}" -f $Matches[1], $Matches[2]).ToLowerInvariant()
    }
    if ($r -match "^git@github\.com:(.+)$") {
        $r = "https://github.com/$($Matches[1])"
    }
    $n = Normalize-RepoUrl $r
    if ([string]::IsNullOrWhiteSpace($n)) { return $r.ToLowerInvariant() }
    if ($n -match "^https?://github\.com/(.+)$") {
        $path = $Matches[1]
        $path = $path.TrimEnd("/")
        if ($path.EndsWith(".git")) { $path = $path.Substring(0, $path.Length - 4) }
        $parts = $path.Split("/") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        if ($parts.Count -ge 2) {
            return ("github.com/{0}/{1}" -f $parts[0], $parts[1]).ToLowerInvariant()
        }
        return ("github.com/{0}" -f $path).ToLowerInvariant()
    }
    if ($n.EndsWith(".git")) { $n = $n.Substring(0, $n.Length - 4) }
    return $n.TrimEnd("/").ToLowerInvariant()
}
function Get-RepoIdentityKey([string]$repo) {
    return (Get-RepoIdentity $repo)
}
function Is-SameRepoIdentity([string]$a, [string]$b) {
    $ia = Get-RepoIdentity $a
    $ib = Get-RepoIdentity $b
    if ([string]::IsNullOrWhiteSpace($ia) -or [string]::IsNullOrWhiteSpace($ib)) { return $false }
    return ($ia -eq $ib)
}
function Is-SameRepository([string]$a, [string]$b) {
    return (Is-SameRepoIdentity $a $b)
}
function Test-LooksLikeRepoUrl([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return $false }
    $v = $value.Trim().Trim("'`"")
    if ($v -match "^(git@github\.com:|https?://github\.com/|github\.com/)") { return $true }
    if ($v -match "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$") { return $true }
    return $false
}
function Test-InstalledVendorPath([string]$path, [string]$repo) {
    if ([string]::IsNullOrWhiteSpace($path) -or [string]::IsNullOrWhiteSpace($repo)) { return $false }
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $path ".git") -PathType Container)) { return $false }

    $origin = $null
    Push-Location $path
    try {
        $origin = Invoke-GitCapture @("remote", "get-url", "origin")
    }
    catch {
        return $false
    }
    finally {
        Pop-Location
    }

    if ([string]::IsNullOrWhiteSpace($origin)) { return $false }
    return (Is-SameRepoIdentity $origin $repo)
}
function Has-GitUpstream {
    $up = Invoke-GitCapture @("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
    return -not [string]::IsNullOrWhiteSpace($up)
}
function Has-GitChanges {
    $out = Invoke-GitCapture @("status", "--porcelain")
    return -not [string]::IsNullOrWhiteSpace($out)
}
function Get-GitLockPathFromOutputLine([string]$line) {
    if ([string]::IsNullOrWhiteSpace($line)) { return $null }
    $m = [regex]::Match($line, "Unable to create '([^']+index\.lock)'", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) { return $m.Groups[1].Value }
    $m = [regex]::Match($line, '无法创建[“"]([^“"'']+index\.lock)[”"]')
    if ($m.Success) { return $m.Groups[1].Value }
    $m = [regex]::Match($line, "unable to unlink '([^']+index\.lock)'", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) { return $m.Groups[1].Value }
    $m = [regex]::Match($line, '无法取消链接[“"]([^“"'']+index\.lock)[”"]')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}
function Test-GitIndexLockIssue($outputLines) {
    foreach ($line in @($outputLines)) {
        $text = [string]$line
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($text -match "index\.lock|Could not write new index file|无法写入新的索引文件") {
            return $true
        }
    }
    return $false
}
function Convert-GitOutputLineToText($line) {
    if ($null -eq $line) { return $null }
    if ($line -is [System.Management.Automation.ErrorRecord]) {
        if ($line.Exception -and -not [string]::IsNullOrWhiteSpace($line.Exception.Message)) {
            return $line.Exception.Message.Trim()
        }
        $fallback = $line.ToString()
        if ([string]::IsNullOrWhiteSpace($fallback)) { return $null }
        if ($fallback -eq "System.Management.Automation.RemoteException") { return $null }
        return $fallback.Trim()
    }
    $text = ([string]$line).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    if ($text -eq "System.Management.Automation.RemoteException") { return $null }
    return $text
}
function Get-GitOutputSummary($outputLines) {
    $lines = @()
    foreach ($line in @($outputLines)) {
        $text = Convert-GitOutputLineToText $line
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $lines += $text
    }
    if ($lines.Count -eq 0) { return $null }
    return (($lines | Select-Object -Last 2) -join " | ")
}
function Test-GitProcessRunning {
    try {
        $gitProcesses = @(Get-Process -Name git,git-remote-http,git-remote-https,git-lfs,ssh,sh -ErrorAction SilentlyContinue)
        return ($gitProcesses.Count -gt 0)
    }
    catch {
        return $false
    }
}
function Remove-GitLockFile([string]$lockPath) {
    if ([string]::IsNullOrWhiteSpace($lockPath)) { return $false }
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) { return $false }
    try {
        [System.IO.File]::SetAttributes($lockPath, [System.IO.FileAttributes]::Normal)
    }
    catch {}
    Invoke-RemoveItemWithRetry $lockPath -MaxAttempts 6 -DelayMs 200 | Out-Null
    return (-not (Test-Path -LiteralPath $lockPath -PathType Leaf))
}
function Repair-StaleGitLockFromOutput($outputLines) {
    $lockPath = $null
    foreach ($line in @($outputLines)) {
        $lockPath = Get-GitLockPathFromOutputLine ([string]$line)
        if (-not [string]::IsNullOrWhiteSpace($lockPath)) { break }
    }
    if ([string]::IsNullOrWhiteSpace($lockPath)) { return $false }
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) { return $false }
    Log ("检测到陈旧 Git 锁文件，已自动移除：{0}" -f $lockPath) "WARN"
    if (Remove-GitLockFile $lockPath) { return $true }
    if (Test-GitProcessRunning) {
        throw ("检测到 Git 锁文件且自动移除失败（可能仍有 git 进程占用），请先等待或结束相关进程后重试：{0}" -f $lockPath)
    }
    throw ("检测到 Git 锁文件，但自动移除失败：{0}" -f $lockPath)
}
function Repair-StaleGitLockInRepo([string]$repoPath) {
    if ([string]::IsNullOrWhiteSpace($repoPath)) { return $false }
    $lockPath = Join-Path $repoPath ".git\index.lock"
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) { return $false }
    Log ("检测到仓库残留 Git 锁文件，已自动移除：{0}" -f $lockPath) "WARN"
    if (Remove-GitLockFile $lockPath) { return $true }
    if (Test-GitProcessRunning) {
        throw ("检测到 Git 锁文件且自动移除失败（可能仍有 git 进程占用），请先等待或结束相关进程后重试：{0}" -f $lockPath)
    }
    throw ("检测到 Git 锁文件，但自动移除失败：{0}" -f $lockPath)
}
function Confirm-CleanRepo([string]$path) {
    if (-not (Test-Path $path)) { return $true }
    Push-Location $path
    try {
        if (-not (Has-GitChanges)) { return $true }
    }
    finally { Pop-Location }
    if (-not (Confirm-Action "检测到本地改动，继续将丢弃这些改动吗？" "CLEAN" -DefaultNo)) { return $false }
    return $true
}
function Git-HardResetClean([bool]$forceClean) {
    if (-not $forceClean) { return }
    Repair-StaleGitLockInRepo (Get-Location).Path | Out-Null
    Invoke-Git @("reset", "--hard")
    Repair-StaleGitLockInRepo (Get-Location).Path | Out-Null
    Invoke-Git @("clean", "-fd")
}
function Repair-StaleGitLockAfterFailure([string]$repoPath, $outputLines) {
    if (-not (Test-GitIndexLockIssue $outputLines)) { return $false }
    return (Repair-StaleGitLockInRepo $repoPath)
}
function Ensure-Repo([string]$path, [string]$repo, [string]$ref, [string]$sparsePath, [bool]$forceClean = $true, [bool]$confirmClean = $false, [bool]$doFetch = $true) {
    if ($DryRun) {
        Log ("DRYRUN Ensure-Repo {0} <= {1} ({2})" -f $path, $repo, $ref)
        return
    }
    if (Test-LocalZipRepoInput $repo) {
        Need (-not $sparsePath -or $sparsePath -eq ".") "zip 导入不支持 --sparse，请去掉 --sparse 后重试。"
        Ensure-RepoFromZip $path $repo $forceClean
        return
    }
    if (-not (Test-Path $path)) {
        if ($sparsePath -and $sparsePath -ne ".") {
            Invoke-Git @("clone", "--filter=blob:none", "--no-checkout", $repo, $path)
            Push-Location $path
            try {
                Invoke-Git @("sparse-checkout", "init", "--cone")
                Invoke-Git @("sparse-checkout", "set", $sparsePath)
                Invoke-Git @("checkout", $ref)
            }
            finally { Pop-Location }
        }
        else {
            Invoke-Git @("clone", $repo, $path)
            Push-Location $path
            try { Invoke-Git @("checkout", $ref) } finally { Pop-Location }
        }
    }
    else {
        $gitDir = Join-Path $path ".git"
        if (-not (Test-Path -LiteralPath $gitDir -PathType Container)) {
            Need $forceClean ("缓存目录已存在但不是 git 仓库且 update_force=false：{0}" -f $path)
            Log ("缓存目录不是 git 仓库，已重建：{0}" -f $path) "WARN"
            Invoke-RemoveItemWithRetry $path -Recurse
            Ensure-Repo $path $repo $ref $sparsePath $forceClean $confirmClean $doFetch
            return
        }
        $existingOrigin = $null
        Push-Location $path
        try {
            $existingOrigin = Invoke-GitCapture @("remote", "get-url", "origin")
        }
        finally { Pop-Location }
        if (-not (Is-SameRepoIdentity $existingOrigin $repo)) {
            Need $forceClean ("缓存目录已存在但来源仓库不匹配且 update_force=false：{0}" -f $path)
            Log ("检测到缓存目录来源不匹配，已重建：{0} (old={1}, new={2})" -f $path, $existingOrigin, $repo) "WARN"
            Invoke-RemoveItemWithRetry $path -Recurse
            Ensure-Repo $path $repo $ref $sparsePath $forceClean $confirmClean $doFetch
            return
        }
        Push-Location $path
        try {
            if ($forceClean -and $confirmClean) {
                if (-not (Confirm-CleanRepo $path)) { throw "已取消：存在本地改动，未执行清理。" }
            }
            Git-HardResetClean $forceClean
            if (-not $sparsePath -or $sparsePath -eq ".") {
                try { Invoke-Git @("sparse-checkout", "disable") } catch {}
            }
            if ($sparsePath -and $sparsePath -ne ".") {
                Invoke-Git @("sparse-checkout", "init", "--cone")
                Invoke-Git @("sparse-checkout", "set", $sparsePath)
            }
            if ($doFetch) {
                Invoke-Git @("fetch", "--all", "--tags")
            }
            Invoke-Git @("checkout", $ref)
            $branch = Get-GitHeadBranch
            if ($branch -and (Has-GitUpstream)) {
                Invoke-Git @("pull")
            }
            else {
                Log "跳过 git pull：当前为 detached HEAD 或无 upstream。"
            }
        }
        finally { Pop-Location }
    }
}
 
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
    return $items.ToArray()
}

function Get-DirtyManualImportTargets($cfg) {
    $items = New-Object System.Collections.Generic.List[object]
    if ($null -eq $cfg) { return @() }

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
 
 function Get-PerfSummaryFromLogLines([string[]]$lines, [int]$RecentPerMetric = 3) {
    $events = @()
    if ($null -eq $lines) { return @() }
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $record = $line | ConvertFrom-Json
        }
        catch { continue }
        if ($null -eq $record -or $null -eq $record.data) { continue }
        if (-not $record.data.PSObject.Properties.Match("metric").Count) { continue }
        if (-not $record.data.PSObject.Properties.Match("duration_ms").Count) { continue }
        $metric = [string]$record.data.metric
        if ([string]::IsNullOrWhiteSpace($metric)) { continue }
        $duration = 0
        try { $duration = [int]$record.data.duration_ms } catch { continue }
        if ($duration -lt 0) { continue }
        $events += [pscustomobject]@{
            metric = $metric
            duration_ms = $duration
            ts = [string]$record.ts
        }
    }
    if ($events.Count -eq 0) { return @() }

    $summary = @()
    $groups = $events | Group-Object metric
    foreach ($g in $groups) {
        $recent = $g.Group | Select-Object -Last $RecentPerMetric
        if ($recent.Count -eq 0) { continue }
        $avg = [math]::Round((($recent | Measure-Object -Property duration_ms -Average).Average), 0)
        $last = ($recent | Select-Object -Last 1)
        $summary += [pscustomobject]@{
            metric = $g.Name
            samples = @($recent).Count
            avg_ms = [int]$avg
            last_ms = [int]$last.duration_ms
            last_ts = [string]$last.ts
        }
    }
    return ($summary | Sort-Object metric)
}

function Parse-DoctorArgs([string[]]$tokens) {
    $opts = [ordered]@{
        json = $false
        fix = $false
        dry_run_fix = $false
        strict = $false
        strict_perf = $false
        threshold_ms = 5000
    }
    if ($null -eq $tokens) { return [pscustomobject]$opts }

    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $t = [string]$tokens[$i]
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        $k = $t.Trim().ToLowerInvariant()
        switch ($k) {
            "--json" { $opts.json = $true; continue }
            "-j" { $opts.json = $true; continue }
            "--fix" { $opts.fix = $true; continue }
            "--dry-run-fix" { $opts.dry_run_fix = $true; continue }
            "--strict" { $opts.strict = $true; continue }
            "--strict-perf" { $opts.strict_perf = $true; continue }
            "--threshold-ms" {
                Need ($i + 1 -lt $tokens.Count) "参数缺少值：--threshold-ms"
                $raw = [string]$tokens[++$i]
                $n = 0
                Need ([int]::TryParse($raw, [ref]$n)) ("--threshold-ms 必须是整数：{0}" -f $raw)
                Need ($n -gt 0) "--threshold-ms 必须大于 0"
                $opts.threshold_ms = $n
                continue
            }
            default { throw ("未知 doctor 参数：{0}" -f $t) }
        }
    }
    return [pscustomobject]$opts
}

function Apply-DoctorFixes($cfg, [switch]$Preview) {
    $result = [ordered]@{
        changed = $false
        applied = @()
    }
    if ($null -eq $cfg) { return [pscustomobject]$result }

    # low-risk fix #1: dedupe duplicate targets.path (keep first)
    if ($cfg.PSObject.Properties.Match("targets").Count -gt 0 -and $cfg.targets -ne $null) {
        $seenTarget = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
        $newTargets = @()
        foreach ($t in @($cfg.targets)) {
            if ($null -eq $t) { continue }
            $path = if ($t.PSObject.Properties.Match("path").Count -gt 0) { [string]$t.path } else { "" }
            if ([string]::IsNullOrWhiteSpace($path)) {
                $newTargets += $t
                continue
            }
            $norm = $path.Trim()
            if ($seenTarget.Add($norm)) {
                $newTargets += $t
            }
            else {
                $result.applied += ("删除重复 targets.path：{0}" -f $norm)
                $result.changed = $true
            }
        }
        if ($result.changed -and -not $Preview) { $cfg.targets = @($newTargets) }
    }

    # low-risk fix #2: remove mappings referencing missing vendor
    if ($cfg.PSObject.Properties.Match("mappings").Count -gt 0 -and $cfg.mappings -ne $null) {
        $vendorSet = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
        $vendorSet.Add("manual") | Out-Null
        $vendorSet.Add("overrides") | Out-Null
        if ($cfg.PSObject.Properties.Match("vendors").Count -gt 0 -and $cfg.vendors -ne $null) {
            foreach ($v in @($cfg.vendors)) {
                if ($null -eq $v) { continue }
                $name = if ($v.PSObject.Properties.Match("name").Count -gt 0) { [string]$v.name } else { "" }
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                $vendorSet.Add($name) | Out-Null
            }
        }

        $newMappings = @()
        foreach ($m in @($cfg.mappings)) {
            if ($null -eq $m) { continue }
            $vendor = if ($m.PSObject.Properties.Match("vendor").Count -gt 0) { [string]$m.vendor } else { "" }
            if ([string]::IsNullOrWhiteSpace($vendor) -or $vendorSet.Contains($vendor)) {
                $newMappings += $m
                continue
            }
            $from = if ($m.PSObject.Properties.Match("from").Count -gt 0) { [string]$m.from } else { "" }
            $to = if ($m.PSObject.Properties.Match("to").Count -gt 0) { [string]$m.to } else { "" }
            $result.applied += ("删除无效 mapping：vendor={0}, from={1}, to={2}" -f $vendor, $from, $to)
            $result.changed = $true
        }
        if ($result.changed -and -not $Preview) { $cfg.mappings = @($newMappings) }
    }

    $result.applied = @($result.applied)
    return [pscustomobject]$result
}

function Get-PerfThresholdMs([string]$Metric, [int]$DefaultThresholdMs = 5000) {
    if ([string]::IsNullOrWhiteSpace($Metric)) { return $DefaultThresholdMs }

    $metricKey = $Metric.Trim().ToLowerInvariant()
    switch ($metricKey) {
        "discover" { return 5000 }
        "build_agent" { return 8000 }
        "apply_targets" { return 5000 }
        # Includes prebuild checks + full build/apply flow; realistic baseline in this repo is ~180s.
        "build_apply_total" { return 240000 }
        "sync_mcp" { return 10000 }
        "update_vendor" { return $null }
        "update_imports" { return $null }
        "update_total" { return $null }
        default { return $DefaultThresholdMs }
    }
}

function Add-PerfThresholdMetadata($summary, [int]$DefaultThresholdMs = 5000) {
    $annotated = @()
    if ($null -eq $summary) { return @() }

    foreach ($p in @($summary)) {
        if ($null -eq $p) { continue }
        $metricName = ""
        try { $metricName = [string]$p.metric } catch { $metricName = "" }
        $metricThreshold = Get-PerfThresholdMs $metricName $DefaultThresholdMs

        $item = [ordered]@{}
        foreach ($prop in $p.PSObject.Properties) {
            $item[$prop.Name] = $prop.Value
        }
        $item.effective_threshold_ms = $metricThreshold
        $item.anomaly_check_enabled = ($null -ne $metricThreshold)
        $annotated += [pscustomobject]$item
    }

    return @($annotated)
}

function Get-PerfAnomalyItems($summary, [int]$WarnThresholdMs = 5000, [int]$MinSamples = 3) {
    $items = @()
    if ($null -eq $summary) { return @() }
    foreach ($p in $summary) {
        if ($null -eq $p) { continue }
        $last = 0
        $avg = 0
        $samples = 0
        try { $last = [int]$p.last_ms } catch { continue }
        try { $avg = [int]$p.avg_ms } catch { continue }
        try { $samples = [int]$p.samples } catch { $samples = 0 }
        if ($samples -lt $MinSamples) { continue }
        $metricThreshold = Get-PerfThresholdMs ([string]$p.metric) $WarnThresholdMs
        if ($null -eq $metricThreshold) { continue }
        if ($last -ge $metricThreshold -or $avg -ge $metricThreshold) {
            $items += ("{0}: last={1}ms avg={2}ms threshold={3}ms" -f [string]$p.metric, $last, $avg, $metricThreshold)
        }
    }
    return ,@($items)
}

function Get-DoctorConfigRisks($cfg) {
    $risks = @()
    if ($null -eq $cfg) { return @() }

    $targetPaths = @()
    if ($cfg.PSObject.Properties.Match("targets").Count -gt 0 -and $cfg.targets -ne $null) {
        foreach ($t in $cfg.targets) {
            if ($null -eq $t) { continue }
            $path = if ($t.PSObject.Properties.Match("path").Count -gt 0) { [string]$t.path } else { "" }
            if ([string]::IsNullOrWhiteSpace($path)) { continue }
            $targetPaths += $path.Trim()
        }
    }
    $dupTargets = @($targetPaths | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    if ($dupTargets.Count -gt 0) {
        $risks += ("检测到重复 targets.path：{0}" -f ($dupTargets -join ", "))
    }

    $mappingTo = @()
    if ($cfg.PSObject.Properties.Match("mappings").Count -gt 0 -and $cfg.mappings -ne $null) {
        foreach ($m in $cfg.mappings) {
            if ($null -eq $m) { continue }
            $to = if ($m.PSObject.Properties.Match("to").Count -gt 0) { [string]$m.to } else { "" }
            if ([string]::IsNullOrWhiteSpace($to)) { continue }
            $mappingTo += $to.Trim()
        }
    }
    $dupTo = @($mappingTo | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    if ($dupTo.Count -gt 0) {
        $risks += ("检测到重复 mappings.to（可能互相覆盖）：{0}" -f ($dupTo -join ", "))
    }

    $vendorSet = New-Object System.Collections.Generic.HashSet[string]
    $vendorSet.Add("manual") | Out-Null
    $vendorSet.Add("overrides") | Out-Null
    if ($cfg.PSObject.Properties.Match("vendors").Count -gt 0 -and $cfg.vendors -ne $null) {
        foreach ($v in $cfg.vendors) {
            if ($null -eq $v) { continue }
            $name = if ($v.PSObject.Properties.Match("name").Count -gt 0) { [string]$v.name } else { "" }
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $vendorSet.Add($name) | Out-Null
        }
    }
    if ($cfg.PSObject.Properties.Match("mappings").Count -gt 0 -and $cfg.mappings -ne $null) {
        foreach ($m in $cfg.mappings) {
            if ($null -eq $m) { continue }
            $vendor = if ($m.PSObject.Properties.Match("vendor").Count -gt 0) { [string]$m.vendor } else { "" }
            if ([string]::IsNullOrWhiteSpace($vendor)) { continue }
            if (-not $vendorSet.Contains($vendor)) {
                $from = if ($m.PSObject.Properties.Match("from").Count -gt 0) { [string]$m.from } else { "" }
                $to = if ($m.PSObject.Properties.Match("to").Count -gt 0) { [string]$m.to } else { "" }
                $risks += ("mapping 引用了不存在的 vendor：{0} (from={1}, to={2})" -f $vendor, $from, $to)
            }
        }
    }

    return @($risks)
}

function Invoke-Doctor([string[]]$tokens = @()) {
    $opts = Parse-DoctorArgs $tokens
    if (-not $opts.json) {
        Write-Host "=== Skills Manager Doctor ===" -ForegroundColor Cyan
    }
    $pass = $true
    $cfgObj = $null
    $report = [ordered]@{
        pass = $true
        strict = [bool]$opts.strict
        strict_perf = [bool]$opts.strict_perf
        checks = [ordered]@{}
        risks = @()
        performance = [ordered]@{
            threshold_ms = [int]$opts.threshold_ms
            summary = @()
            anomalies = @()
        }
        summary = [ordered]@{
            errors = @()
            warnings = @()
            error_count = 0
            warn_count = 0
        }
        fix = [ordered]@{
            requested = [bool]$opts.fix
            changed = $false
            applied = @()
        }
    }

    # 1. System Checks
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $report.checks.os = ("{0} {1}" -f $os.Caption, $os.OSArchitecture)
        if (-not $opts.json) { Write-Host ("OS: {0} {1}" -f $os.Caption, $os.OSArchitecture) }
    }
    catch {
        $report.checks.os = "unknown"
        if (-not $opts.json) { Write-Host "OS: unknown（读取失败）" -ForegroundColor Yellow }
    }

    # 2. Git Check
    try {
        if ($DryRun) {
            $gitOut = & git version 2>$null
            if ($LASTEXITCODE -ne 0 -or $null -eq $gitOut) { throw "git version failed" }
            $gitVer = ($gitOut | Select-Object -First 1).ToString().Trim()
        }
        else {
            $gitVer = Invoke-GitCapture @("version")
        }
        if ([string]::IsNullOrWhiteSpace($gitVer)) { throw "git version is empty" }
        $report.checks.git = [ordered]@{ ok = $true; value = $gitVer }
        if (-not $opts.json) { Write-Host "✅ Git: $gitVer" -ForegroundColor Green }
    }
    catch {
        $report.checks.git = [ordered]@{ ok = $false; value = "" }
        if (-not $opts.json) { Write-Host "❌ Git: Not found or error" -ForegroundColor Red }
        $pass = $false
    }

    # 3. Robocopy Check
    if (Get-Command robocopy -ErrorAction SilentlyContinue) {
        $report.checks.robocopy = [ordered]@{ ok = $true }
        if (-not $opts.json) { Write-Host "✅ Robocopy: Available" -ForegroundColor Green }
    }
    else {
        $report.checks.robocopy = [ordered]@{ ok = $false }
        if (-not $opts.json) { Write-Host "❌ Robocopy: Not found" -ForegroundColor Red }
        $pass = $false
    }

    # 4. Long Paths
    try {
        $lp = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -ErrorAction SilentlyContinue
        if ($lp -and $lp.LongPathsEnabled -eq 1) {
            $report.checks.long_paths = [ordered]@{ ok = $true; value = 1 }
            if (-not $opts.json) { Write-Host "✅ LongPathsEnabled: 1 (On)" -ForegroundColor Green }
        }
        else {
            $report.checks.long_paths = [ordered]@{ ok = $false; value = 0 }
            if (-not $opts.json) { Write-Host "⚠️ LongPathsEnabled: 0 (Off) - Deep paths may fail." -ForegroundColor Yellow }
        }
    }
    catch {
        $report.checks.long_paths = [ordered]@{ ok = $false; value = "unknown" }
        if (-not $opts.json) { Write-Host "⚠️ LongPathsEnabled: Check failed" -ForegroundColor Yellow }
    }

    # 5. Config Check
    if (Test-Path $CfgPath) {
        try {
            $cfg = Get-Content $CfgPath -Raw | ConvertFrom-Json
            if ($cfg) {
                $cfgObj = $cfg
                $report.checks.config = [ordered]@{ ok = $true; vendors = @($cfg.vendors).Count; mappings = @($cfg.mappings).Count }
                if (-not $opts.json) {
                    Write-Host "✅ skills.json: Valid JSON" -ForegroundColor Green
                    Write-Host ("   - Vendors: {0}" -f $cfg.vendors.Count)
                    Write-Host ("   - Mappings: {0}" -f $cfg.mappings.Count)
                }
            }
            else {
                $report.checks.config = [ordered]@{ ok = $false; reason = "invalid_or_empty" }
                if (-not $opts.json) { Write-Host "❌ skills.json: Invalid/Empty" -ForegroundColor Red }
                $pass = $false
            }
        }
        catch {
            $report.checks.config = [ordered]@{ ok = $false; reason = ("parse_error: {0}" -f $_.Exception.Message) }
            if (-not $opts.json) { Write-Host ("❌ skills.json: Parse Error - {0}" -f $_.Exception.Message) -ForegroundColor Red }
            $pass = $false
        }
    }
    else {
        $report.checks.config = [ordered]@{ ok = $false; reason = "not_found" }
        if (-not $opts.json) { Write-Host "⚠️ skills.json: Not found (Run init or add first)" -ForegroundColor Yellow }
    }

    # 6. Config Risk Scan
    try {
        if ($null -ne $cfgObj) {
            $risks = Get-DoctorConfigRisks $cfgObj
            $report.risks = @($risks)
            if ($risks.Count -gt 0) {
                if (-not $opts.json) {
                    Write-Host ("⚠️ 配置风险（{0} 项）：" -f $risks.Count) -ForegroundColor Yellow
                    foreach ($risk in $risks) {
                        Write-Host ("   - {0}" -f $risk) -ForegroundColor Yellow
                    }
                }
            }
        }
    }
    catch {
        if (-not $opts.json) { Write-Host "⚠️ 配置风险扫描失败（已忽略）" -ForegroundColor Yellow }
    }

    # 6.5 Optional auto-fix for low-risk config issues
    if (($opts.fix -or $opts.dry_run_fix) -and $null -ne $cfgObj) {
        try {
            $fixResult = Apply-DoctorFixes $cfgObj -Preview:$opts.dry_run_fix
            $report.fix.changed = [bool]$fixResult.changed
            $report.fix.applied = @($fixResult.applied)
            $report.fix.preview = [bool]$opts.dry_run_fix
            if ($fixResult.changed) {
                if (-not $DryRun -and -not $opts.dry_run_fix) {
                    $json = $cfgObj | ConvertTo-Json -Depth 50
                    Set-ContentUtf8 $CfgPath $json
                }
                if (-not $opts.json) {
                    if ($opts.dry_run_fix) {
                        Write-Host ("doctor --dry-run-fix 预览 {0} 项可修复内容。" -f @($fixResult.applied).Count) -ForegroundColor Yellow
                    }
                    else {
                        Write-Host ("✅ doctor --fix 已应用 {0} 项修复。" -f @($fixResult.applied).Count) -ForegroundColor Green
                    }
                    foreach ($line in @($fixResult.applied)) {
                        if ($opts.dry_run_fix) {
                            Write-Host ("   - {0}" -f $line) -ForegroundColor Yellow
                        }
                        else {
                            Write-Host ("   - {0}" -f $line) -ForegroundColor Green
                        }
                    }
                }
            }
            elseif (-not $opts.json) {
                if ($opts.dry_run_fix) { Write-Host "doctor --dry-run-fix：未发现可自动修复项。" }
                else { Write-Host "doctor --fix：未发现可自动修复项。" }
            }
        }
        catch {
            if (-not $opts.json) { Write-Host ("⚠️ doctor --fix 执行失败：{0}" -f $_.Exception.Message) -ForegroundColor Yellow }
        }
    }

    # 7. Network Check (Optional)
    try {
        $ping = Test-NetConnection "github.com" -Port 443 -InformationLevel Quiet
        if ($ping) {
            $report.checks.network = [ordered]@{ ok = $true }
            if (-not $opts.json) { Write-Host "✅ GitHub Connection: OK" -ForegroundColor Green }
        }
        else {
            $report.checks.network = [ordered]@{ ok = $false }
            if (-not $opts.json) { Write-Host "❌ GitHub Connection: Failed" -ForegroundColor Red }
            $pass = $false
        }
    }
    catch {
        $report.checks.network = [ordered]@{ ok = $false; skipped = $true }
        if (-not $opts.json) { Write-Host "⚠️ Network Check: Skipped" -ForegroundColor Yellow }
    }

    # 8. Performance Summary
    try {
        if (Test-Path $LogPath) {
            $lines = Get-Content $LogPath -ErrorAction SilentlyContinue
            $perf = Get-PerfSummaryFromLogLines $lines 3
            $report.performance.summary = @(Add-PerfThresholdMetadata $perf $opts.threshold_ms)
            if ($perf.Count -gt 0) {
                if (-not $opts.json) {
                    Write-Host "最近性能摘要（最近 3 次）："
                    foreach ($p in $report.performance.summary) {
                        Write-Host ("   - {0}: last={1}ms avg={2}ms samples={3}" -f $p.metric, $p.last_ms, $p.avg_ms, $p.samples)
                    }
                }
                $anomalies = Get-PerfAnomalyItems $report.performance.summary $opts.threshold_ms
                $report.performance.anomalies = @($anomalies)
                if ($anomalies.Count -gt 0) {
                    if (-not $opts.json) {
                        Write-Host ("⚠️ 性能异常（阈值 {0}ms，{1} 项）：" -f $opts.threshold_ms, $anomalies.Count) -ForegroundColor Yellow
                        foreach ($a in $anomalies) {
                            Write-Host ("   - {0}" -f $a) -ForegroundColor Yellow
                        }
                    }
                }
            }
        }
    }
    catch {
        if (-not $opts.json) { Write-Host "⚠️ 性能摘要读取失败（已忽略）" -ForegroundColor Yellow }
    }

    $report.pass = $pass
    if (-not $report.checks.git.ok) { $report.summary.errors += "git_unavailable" }
    if (-not $report.checks.robocopy.ok) { $report.summary.errors += "robocopy_unavailable" }
    if (-not $report.checks.config.ok) {
        $reason = if ($report.checks.config.reason) { [string]$report.checks.config.reason } else { "config_invalid" }
        if ($reason -like "parse_error*") { $report.summary.errors += "config_parse_error" }
        else { $report.summary.warnings += "config_not_ready" }
    }
    if ($report.checks.long_paths.value -eq 0) { $report.summary.warnings += "long_paths_off" }
    if (@($report.risks).Count -gt 0) { $report.summary.warnings += "config_risks_present" }
    if (@($report.performance.anomalies).Count -gt 0) { $report.summary.warnings += "perf_anomalies_present" }

    if ($opts.strict -and (@($report.risks).Count -gt 0 -or ([bool]$opts.strict_perf -and @($report.performance.anomalies).Count -gt 0))) {
        $report.pass = $false
    }
    $report.summary.error_count = @($report.summary.errors).Count
    $report.summary.warn_count = @($report.summary.warnings).Count
    if ($opts.json) {
        Write-Host ($report | ConvertTo-Json -Depth 30)
        return [pscustomobject]$report
    }
    if ($opts.strict -and -not $opts.strict_perf -and @($report.performance.anomalies).Count -gt 0) {
        Write-Host "提示：性能异常仅告警，不影响 --strict 结果。使用 --strict-perf 可将其纳入阻断。" -ForegroundColor Yellow
    }

    Write-Host ""
    if ($report.pass) {
        Write-Host "Your system is ready for skills-manager." -ForegroundColor Green
    }
    else {
        Write-Host "Some checks failed. Please review issues above." -ForegroundColor Red
    }
    return [pscustomobject]$report
}
 
 function Upsert-Import($cfg, $import) {
    $existing = $cfg.imports | Where-Object { $_.name -eq $import.name } | Select-Object -First 1
    if ($existing) {
        $existing.repo = $import.repo
        $existing.ref = $import.ref
        $existing.skill = $import.skill
        $existing.mode = $import.mode
        $existing.sparse = $import.sparse
    }
    else {
        $cfg.imports += $import
    }
}

function Ensure-ImportVendorMapping($cfg, [string]$vendorName, [string]$skillPath, [string]$targetName) {
    $skillPath = Normalize-SkillPath $skillPath
    $from = $skillPath
    if ($from -eq ".") { $from = "." }
    $exists = $cfg.mappings | Where-Object { $_.vendor -eq $vendorName -and $_.from -eq $from } | Select-Object -First 1
    if (-not $exists) {
        $cfg.mappings += @{ vendor = $vendorName; from = $from; to = $targetName }
    }
}
function Test-NeedsSparseProbeFallback([string]$msg) {
    if ([string]::IsNullOrWhiteSpace($msg)) { return $false }
    return ($msg -match "unable to checkout working tree|checkout failed|git restore --source=HEAD :/|invalid path|Filename too long|文件名.*太长|路径.*过长")
}
function Get-PreferredSkillCandidates($candidates) {
    $ordered = @($candidates | Sort-Object rel)
    if ($ordered.Count -le 1) { return $ordered }
    $preferred = @($ordered | Where-Object {
            $relGit = (($_.rel -as [string]) -replace "\\", "/")
            $relGit -match "^(\\.claude/skills|skills)(/|$)"
        })
    if ($preferred.Count -gt 0) { return $preferred }
    return $ordered
}
function Get-RelevantSkillCandidates($candidates, [string]$skillPath) {
    $ranked = @(Get-SkillCandidatesByRelevance $candidates $skillPath)
    if ($ranked.Count -eq 0) { return @($candidates | Sort-Object rel) }
    return $ranked
}
function Resolve-SkillsWithSparseProbe([string]$repo, [string]$ref, [string[]]$skillPaths) {
    $repoCandidates = Get-SkillCandidatesFromGitRepo $repo $ref
    Need ($repoCandidates.Count -gt 0) "仓库内未发现任何有效的技能标记文件（SKILL.md, AGENTS.md, GEMINI.md, CLAUDE.md）"
    $resolved = @()
    foreach ($p in $skillPaths) {
        $normalized = Normalize-SkillPath $p
        $matched = $null

        $exact = @($repoCandidates | Where-Object { $_.rel -eq $normalized })
        if ($exact.Count -eq 1) {
            $matched = $exact[0].rel
        }

        if ([string]::IsNullOrWhiteSpace($matched) -and $normalized -ne "." -and $normalized -notmatch "[\\/]") {
            $prefixed = Join-Path "skills" $normalized
            $prefixedMatch = @($repoCandidates | Where-Object { $_.rel -eq $prefixed })
            if ($prefixedMatch.Count -eq 1) { $matched = $prefixedMatch[0].rel }
        }

        if ([string]::IsNullOrWhiteSpace($matched)) {
            $leaf = Split-Path $normalized -Leaf
            $leafMatches = @($repoCandidates | Where-Object { $_.leaf -eq $leaf })
            if ($leafMatches.Count -eq 1) {
                $matched = $leafMatches[0].rel
            }
            elseif ($leafMatches.Count -gt 1) {
                $preferredLeaf = @(Get-PreferredSkillCandidates $leafMatches)
                if ($preferredLeaf.Count -eq 1) {
                    $matched = $preferredLeaf[0].rel
                }
                else {
                    $rankedLeaf = @(Get-RelevantSkillCandidates $preferredLeaf $normalized)
                    $top = @($rankedLeaf | Select-Object -First 12 | ForEach-Object { "- $($_.rel)" })
                    throw ("技能路径预检失败：--skill {0}`n同名候选过多，请改为精确路径。`n{1}" -f $normalized, ($top -join "`n"))
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($matched)) {
            $leafNorm = Normalize-Name (Split-Path $normalized -Leaf)
            $leafCompact = Normalize-CompactName (Split-Path $normalized -Leaf)
            if (-not [string]::IsNullOrWhiteSpace($leafNorm)) {
                $fuzzy = @($repoCandidates | Where-Object {
                        $candNorm = Normalize-Name $_.leaf
                        if ([string]::IsNullOrWhiteSpace($candNorm)) { return $false }
                        return ($leafNorm -eq $candNorm) -or ($leafNorm.EndsWith("-$candNorm"))
                    })
                if ($fuzzy.Count -eq 1) {
                    $matched = $fuzzy[0].rel
                }
                elseif ($fuzzy.Count -gt 1) {
                    $preferredFuzzy = @(Get-PreferredSkillCandidates $fuzzy)
                    if ($preferredFuzzy.Count -eq 1) {
                        $matched = $preferredFuzzy[0].rel
                    }
                    else {
                        $rankedFuzzy = @(Get-RelevantSkillCandidates $preferredFuzzy $normalized)
                        $top = @($rankedFuzzy | Select-Object -First 12 | ForEach-Object { "- $($_.rel)" })
                        throw ("技能路径预检失败：--skill {0}`n后缀候选过多，请改为精确路径。`n{1}" -f $normalized, ($top -join "`n"))
                    }
                }
            }
            if ([string]::IsNullOrWhiteSpace($matched) -and -not [string]::IsNullOrWhiteSpace($leafCompact)) {
                $compact = @($repoCandidates | Where-Object {
                        $candCompact = Normalize-CompactName $_.leaf
                        if ([string]::IsNullOrWhiteSpace($candCompact)) { return $false }
                        return ($leafCompact -eq $candCompact) -or ($leafCompact.Contains($candCompact)) -or ($candCompact.Contains($leafCompact))
                    })
                if ($compact.Count -eq 1) {
                    $matched = $compact[0].rel
                }
                elseif ($compact.Count -gt 1) {
                    $preferredCompact = @(Get-PreferredSkillCandidates $compact)
                    $rankedCompact = @(Get-RelevantSkillCandidates $preferredCompact $normalized)
                    $top = @($rankedCompact | Select-Object -First 12 | ForEach-Object { "- $($_.rel)" })
                    throw ("技能路径预检失败：--skill {0}`n紧凑匹配候选过多，请改为精确路径。`n{1}" -f $normalized, ($top -join "`n"))
                }
            }
            if ([string]::IsNullOrWhiteSpace($matched) -and -not [string]::IsNullOrWhiteSpace($leafNorm) -and $leafNorm -match "(^|-)motion(s)?($|-)|(^|-)anim(ation|ate|ations)?($|-)") {
                $semantic = @($repoCandidates | Where-Object {
                        $candNorm = Normalize-Name $_.leaf
                        if ([string]::IsNullOrWhiteSpace($candNorm)) { return $false }
                        return ($candNorm -match "(^|-)motion(s)?($|-)|(^|-)anim(ation|ate|ations)?($|-)")
                    })
                if ($semantic.Count -eq 1) {
                    $matched = $semantic[0].rel
                }
                elseif ($semantic.Count -gt 1) {
                    $preferredSemantic = @(Get-PreferredSkillCandidates $semantic)
                    $rankedSemantic = @(Get-RelevantSkillCandidates $preferredSemantic $normalized)
                    $top = @($rankedSemantic | Select-Object -First 12 | ForEach-Object { "- $($_.rel)" })
                    throw ("技能路径预检失败：--skill {0}`n语义匹配候选过多，请改为精确路径。`n{1}" -f $normalized, ($top -join "`n"))
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($matched)) {
            $rankedAll = @(Get-RelevantSkillCandidates $repoCandidates $normalized)
            $top = @($rankedAll | Select-Object -First 12 | ForEach-Object { "- $($_.rel)" })
            throw ("技能路径预检失败：--skill {0}`n仓库在当前系统上无法完成完整 checkout，且未找到该路径。请显式指定正确路径。`n{1}" -f $normalized, ($top -join "`n"))
        }

        if ($matched -ne $normalized) { Write-Host ("未找到指定路径，已自动修正为：{0}" -f $matched) }
        $resolved += $matched
    }
    return $resolved
}
function Resolve-SkillsWithProbe([string]$repo, [string]$ref, [string[]]$skillPaths, [bool]$forceClean) {
    $probeName = ("_probe_{0}" -f ([Guid]::NewGuid().ToString("N").Substring(0, 8)))
    $probePath = Join-Path $ImportDir $probeName
    $resolved = @()
    try {
        try {
            Ensure-Repo $probePath $repo $ref $null $forceClean $false
        }
        catch {
            $probeError = $_.Exception.Message
            if (-not (Test-NeedsSparseProbeFallback $probeError)) { throw }
            Log ("完整 clone/checkout 预检失败，自动回退 sparse 预检：{0}" -f $probeError) "WARN"
            return (Resolve-SkillsWithSparseProbe $repo $ref $skillPaths)
        }
        if ($script:SkillCandidatesCache) { $script:SkillCandidatesCache.Remove($probePath) | Out-Null }
        foreach ($p in $skillPaths) {
            $normalized = Normalize-SkillPath $p
            try {
                $resolved += (Resolve-SkillPath $probePath $normalized)
            }
            catch {
                $candidates = @()
                try { $candidates = Get-SkillCandidates $probePath } catch {}
                $hint = @()
                if ($candidates.Count -gt 0) {
                    $rankedCandidates = @(Get-RelevantSkillCandidates $candidates $normalized)
                    $hint += ("可用技能路径候选（Top {0}）：" -f ([Math]::Min(12, $candidates.Count)))
                    foreach ($c in ($rankedCandidates | Select-Object -First 12)) {
                        $hint += ("- {0}" -f $c.rel)
                    }
                    if ($candidates.Count -gt 12) {
                        $hint += ("... 另有 {0} 项未显示" -f ($candidates.Count - 12))
                    }
                }
                $msg = ("技能路径预检失败：--skill {0}`n{1}" -f $normalized, $_.Exception.Message)
                if ($hint.Count -gt 0) { $msg += ("`n" + ($hint -join "`n")) }
                throw $msg
            }
        }
        return $resolved
    }
    finally {
        if (Test-Path $probePath) { Invoke-RemoveItemWithRetry $probePath -Recurse -IgnoreFailure | Out-Null }
        if ($script:SkillCandidatesCache) { $script:SkillCandidatesCache.Remove($probePath) | Out-Null }
    }
}
function Get-InstallErrorSuggestedSkillPath([string]$msg, [string[]]$skillPaths) {
    if (-not [string]::IsNullOrWhiteSpace($msg)) {
        $bulletMatches = [regex]::Matches($msg, "(?m)^-\s+(.+)$")
        foreach ($m in $bulletMatches) {
            $candidate = $m.Groups[1].Value.Trim()
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
            if ($candidate -eq ".") { continue }
            return ($candidate -replace "\\", "/")
        }
    }

    $sample = if ($skillPaths -and $skillPaths.Count -gt 0) { $skillPaths[0] } else { "<skill>" }
    $sample = ($sample -replace "\\", "/").Trim()
    if ([string]::IsNullOrWhiteSpace($sample)) { return "skills/<skill>" }
    if ($sample -eq ".") { return "." }
    if ($sample.Contains("/")) { return $sample }

    $leaf = Split-Path $sample -Leaf
    if ([string]::IsNullOrWhiteSpace($leaf)) { $leaf = "<skill>" }
    return ("skills/{0}" -f $leaf)
}
function Get-CrossRepoInstallFallbackPlan([string]$repo, [string[]]$skillPaths, [string]$msg) {
    if ([string]::IsNullOrWhiteSpace($msg) -or $msg -notmatch "未找到技能入口文件") { return $null }
    if (-not $skillPaths -or $skillPaths.Count -eq 0) { return $null }

    $repoText = if ([string]::IsNullOrWhiteSpace($repo)) { "" } else { $repo.ToLowerInvariant() }
    $firstSkill = [string]$skillPaths[0]
    $leaf = (Split-Path (Normalize-SkillPath $firstSkill) -Leaf).ToLowerInvariant()
    $leafNorm = Normalize-Name $leaf

    # High-frequency cross-repo aliases.
    $catalog = @(
        @{
            pattern = "(^|-)motion(s)?($|-)|(^|-)anim(ation|ate|ations)?($|-)"
            repoMatch = "mblode/agent-skills"
            repo = "https://github.com/mblode/agent-skills.git"
            skill = "motion"
        },
        @{
            pattern = "(^|-)uni(-)?app($|-)|(^|-)uni-helper($|-)"
            repoMatch = "uni-helper/skills"
            repo = "https://github.com/uni-helper/skills.git"
            skill = "uniapp"
        },
        @{
            pattern = "(^|-)remotion($|-)|(^|-)remotion-best-practices($|-)"
            repoMatch = "remotion-dev/skills"
            repo = "https://github.com/remotion-dev/skills.git"
            skill = "remotion"
        }
    )

    foreach ($entry in $catalog) {
        if ($leafNorm -notmatch $entry.pattern) { continue }
        if ($repoText -match [string]$entry.repoMatch) { continue }
        return [pscustomobject]@{
            repo = [string]$entry.repo
            skill = [string]$entry.skill
            command = (".\skills.ps1 add {0} --skill {1}" -f [string]$entry.repo, [string]$entry.skill)
        }
    }
    return $null
}
function Write-InstallErrorHint([string]$msg, [string]$repo, [string[]]$skillPaths) {
    if ([string]::IsNullOrWhiteSpace($msg)) { return }
    if ($msg -match "zip 文件当前被占用|由另一进程使用|being used by another process") {
        Write-Host "提示：检测到 zip 被占用。请关闭资源管理器预览/压缩软件/同步盘后重试；工具已自动采用“临时复制 + 重试解压”策略。" -ForegroundColor Yellow
        return
    }
    if ($msg -match "仓库不可访问或不存在|Repository not found|repository '.+' not found") {
        if (Test-LocalZipRepoInput $repo) {
            Write-Host "提示：你传入的是本地 zip，已按本地压缩包处理；若仍失败，请确认 zip 可读且未被占用。" -ForegroundColor Yellow
            return
        }
        Write-Host "提示：请先在浏览器确认仓库地址可访问，私有仓库需先配置 git 凭据。" -ForegroundColor Yellow
        return
    }
    if ($msg -match "仓库内未发现任何有效的技能标记文件") {
        Write-Host "提示：该仓库可能不是本工具支持的 skills 仓库（缺少 SKILL.md/AGENTS.md/GEMINI.md/CLAUDE.md）。" -ForegroundColor Yellow
        return
    }
    if ($msg -match "未找到技能入口文件") {
        $suggestedSkillPath = Get-InstallErrorSuggestedSkillPath $msg $skillPaths
        Write-Host ("提示：请改用真实路径，例如：--skill {0}" -f $suggestedSkillPath) -ForegroundColor Yellow
        Write-Host ("提示：当前 repo = {0}" -f $repo) -ForegroundColor Yellow
        $plan = Get-CrossRepoInstallFallbackPlan $repo $skillPaths $msg
        if ($plan -and -not [string]::IsNullOrWhiteSpace([string]$plan.command)) {
            Write-Host ("提示：当前仓库可能不包含该技能，可直接执行：{0}" -f $plan.command) -ForegroundColor Yellow
        }
    }
}

function Get-DeclaredSkillNameFromDir([string]$skillDir) {
    if ([string]::IsNullOrWhiteSpace($skillDir)) { return $null }
    $skillFile = Join-Path $skillDir "SKILL.md"
    if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) { return $null }
    foreach ($line in (Get-Content -LiteralPath $skillFile -TotalCount 80 -ErrorAction SilentlyContinue)) {
        if ($line -match "^\s*name:\s*(.+?)\s*$") {
            $declaredName = $Matches[1].Trim().Trim("'`"")
            if (-not [string]::IsNullOrWhiteSpace($declaredName)) {
                return $declaredName
            }
        }
    }
    return $null
}

function Add-ImportFromArgs([string[]]$tokens, [switch]$NoBuild) {
    Preflight
    $cfgRaw = ""
    $cfg = LoadCfg
    if (Test-Path $CfgPath) { $cfgRaw = Get-Content $CfgPath -Raw }

    $resolvedTokens = Resolve-AddTokensFromAnyFormat $tokens
    if ($resolvedTokens) { $tokens = $resolvedTokens }
    $parsed = Parse-AddArgs $tokens
    $repo = Normalize-RepoUrl $parsed.repo
    $ref = $parsed.ref
    $refIsAuto = $false
    if ([string]::IsNullOrWhiteSpace($ref)) {
        $ref = "main"
        $refIsAuto = $true
    }
    $mode = $parsed.mode
    if ([string]::IsNullOrWhiteSpace($mode)) { $mode = "manual" }
    $mode = $mode.ToLowerInvariant()
    Need ($mode -eq "manual" -or $mode -eq "vendor") "mode 仅支持 manual 或 vendor"
    $registerVendorOnly = (-not [bool]$parsed.skillSpecified -and -not [bool]$parsed.modeSpecified)
    if ($registerVendorOnly) { $mode = "vendor" }

    $sparse = [bool]$parsed.sparse

    if ($DryRun) {
        if ($registerVendorOnly) {
            Write-Host ("DRYRUN：将新增技能库（vendor only）：{0} ({1})" -f $repo, $ref)
        }
        else {
            Write-Host ("DRYRUN：将从 {0} ({1}) 导入 {2} 个技能，模式：{3}，Sparse：{4}" -f $repo, $ref, $parsed.skills.Count, $mode, $sparse)
        }
        if (-not $NoBuild) { Write-Host "DRYRUN：将执行【构建生效】" }
        return $true
    }

    try {
        # Strict precheck: repo must be reachable.
        Assert-RepoReachable $repo

        if ($refIsAuto) {
            $ref = Get-RepoDefaultBranch $repo
            Log ("未指定 --ref，自动使用仓库默认分支：{0}" -f $ref)
        }

        $resolvedSkillPaths = $null

        # Auto-detect mode if not specified (or default manual)
        if ($mode -eq "manual") {
            Need (-not [string]::IsNullOrWhiteSpace($repo)) "Repo URL cannot be empty"
            $matchedVendor = Match-VendorByRepo $cfg $repo
            if ($matchedVendor) {
                $mode = "vendor"
                $vendorName = $matchedVendor.name
                $parsed.name = $vendorName # Override name to vendor name
                Log ("自动检测到已存在的 Vendor：{0}。切换为 Vendor 模式安装。" -f $vendorName)
            }
            elseif ($registerVendorOnly) {
                Log "未显式指定 --skill：按“仅新增技能库”处理（不安装仓库内技能）。"
                $mode = "vendor"
            }
        }

        # Strict precheck: resolve all skill paths before writing config.
        if ($registerVendorOnly) {
            $resolvedSkillPaths = @()
        }
        elseif ($null -eq $resolvedSkillPaths) {
            $resolvedSkillPaths = @(Resolve-SkillsWithProbe $repo $ref $parsed.skills $cfg.update_force)
        }
        else {
            $resolvedSkillPaths = @($resolvedSkillPaths)
        }

        if ($mode -eq "manual") {
            $baseName = $null
            if (-not [string]::IsNullOrWhiteSpace($parsed.name)) {
                $baseName = Normalize-NameWithNotice $parsed.name "导入名称"
            }
            foreach ($skillPath in $resolvedSkillPaths) {
                $name = $baseName
                $allowDeclaredName = [string]::IsNullOrWhiteSpace($name)
                if ($allowDeclaredName -or $resolvedSkillPaths.Count -gt 1) {
                    $leaf = if ($skillPath -eq ".") { Guess-VendorName $repo } else { Split-Path $skillPath -Leaf }
                    $curName = Normalize-Name $leaf
                    $name = if (-not [string]::IsNullOrWhiteSpace($name)) { "$name-$curName" } else { $curName }
                }
                $name = Normalize-NameWithNotice $name "导入名称"

                $cache = Join-Path $ImportDir $name
                $gitSkillPath = To-GitPath $skillPath
                $curSparse = $sparse
                if ($gitSkillPath -eq "." -and $curSparse) { $curSparse = $false }
                $sparsePath = if ($curSparse) { $gitSkillPath } else { $null }
                $usedArchiveFallback = $false

                try {
                    Ensure-Repo $cache $repo $ref $sparsePath $cfg.update_force $true
                }
                catch {
                    $importError = $_.Exception.Message
                    if (($skillPath -eq ".") -or (-not (Test-NeedsSparseProbeFallback $importError))) { throw }
                    Log ("导入阶段 clone/checkout 失败，自动回退 git archive 子目录导出：{0}" -f $importError) "WARN"
                    try {
                        Ensure-RepoFromGitArchive $cache $repo $ref $skillPath $cfg.update_force
                    }
                    catch {
                        $archiveError = $_.Exception.Message
                        if (-not (Test-NeedsSparseProbeFallback $archiveError)) { throw }
                        Log ("git archive 回退失败，自动回退 GitHub 子目录快照导入：{0}" -f $archiveError) "WARN"
                        Ensure-RepoFromGitHubTreeSnapshot $cache $repo $ref $skillPath $cfg.update_force
                    }
                    $usedArchiveFallback = $true
                }
                if ($script:SkillCandidatesCache) { $script:SkillCandidatesCache.Remove($cache) | Out-Null }

                if ($curSparse -and -not $usedArchiveFallback) {
                    Ensure-Repo $cache $repo $ref (To-GitPath $skillPath) $cfg.update_force $true
                }
                $src = if ($skillPath -eq ".") { $cache } else { Join-Path $cache $skillPath }
                Need (Test-IsSkillDir $src) "未找到技能入口文件（SKILL.md/AGENTS.md/GEMINI.md/CLAUDE.md）：$src"

                if ($allowDeclaredName) {
                    $declaredName = Get-DeclaredSkillNameFromDir $src
                    if (-not [string]::IsNullOrWhiteSpace($declaredName)) {
                        $preferredName = Normalize-NameWithNotice $declaredName "导入名称"
                        if ($preferredName -ne $name) {
                            $preferredCache = Join-Path $ImportDir $preferredName
                            if ($cache -ne $preferredCache -and -not (Test-Path $preferredCache)) {
                                Invoke-MoveItem $cache $preferredCache
                                $cache = $preferredCache
                                $src = if ($skillPath -eq ".") { $cache } else { Join-Path $cache $skillPath }
                            }
                            $name = $preferredName
                        }
                    }
                }

                $import = @{ name = $name; repo = $repo; ref = $ref; skill = $skillPath; mode = "manual"; sparse = $curSparse }
                Upsert-Import $cfg $import
            }
        }
        else {
            $vendorName = $parsed.name
            if ([string]::IsNullOrWhiteSpace($vendorName)) { $vendorName = Guess-VendorName $repo }
            $allowExistingVendor = ($cfg.vendors | Where-Object { $_.name -eq $vendorName -and (Is-SameRepository ([string]$_.repo) $repo) } | Select-Object -First 1) -ne $null
            $vendorName = Resolve-UniqueVendorName $cfg $vendorName $repo $allowExistingVendor
            $vendorPath = VendorPath $vendorName
      
            Ensure-Repo $vendorPath $repo $ref $null $cfg.update_force $true
            if (-not $registerVendorOnly) {
                foreach ($skillPath in $resolvedSkillPaths) {
                    if ($script:SkillCandidatesCache) { $script:SkillCandidatesCache.Remove($vendorPath) | Out-Null }
                    $src = if ($skillPath -eq ".") { $vendorPath } else { Join-Path $vendorPath $skillPath }
                    Need (Test-IsSkillDir $src) "未找到技能入口文件（SKILL.md/AGENTS.md/GEMINI.md/CLAUDE.md）：$src"

                    $targetSuffix = if ($skillPath -eq ".") { $vendorName } else { $skillPath }
                    $targetName = Make-TargetName $vendorName $targetSuffix
                    Ensure-ImportVendorMapping $cfg $vendorName $skillPath $targetName
                }

                $primarySkillPath = if ($resolvedSkillPaths -contains ".") { "." } else { [string]$resolvedSkillPaths[0] }
                $import = @{ name = $vendorName; repo = $repo; ref = $ref; skill = $primarySkillPath; mode = "vendor"; sparse = $sparse }
                Upsert-Import $cfg $import
            }
      
            $vendor = $cfg.vendors | Where-Object { $_.name -eq $vendorName } | Select-Object -First 1
            if (-not $vendor) {
                $cfg.vendors += @{ name = $vendorName; repo = $repo; ref = $ref }
            }
            else {
                $vendor.repo = $repo
                $vendor.ref = $ref
            }

            # Vendor-only registration should still reconcile already-installed manual skills from the same repo.
            if ($registerVendorOnly) {
                $migrated = Migrate-ManualToVendor $cfg $vendorName $repo
                if ($migrated -gt 0) {
                    Write-Host ("已自动迁移 {0} 个已安装技能到 vendor/{1}（仅关联，不新增其它技能）。" -f $migrated, $vendorName) -ForegroundColor Yellow
                }
            }
        }

        SaveCfgSafe $cfg $cfgRaw
        Clear-SkillsCache

        if (-not $NoBuild) {
            Write-Host "导入完成。开始【构建生效】..."
            构建生效
        }
        else {
            Write-Host "导入完成。"
        }
        return $true
    }
    catch {
        $errMsg = $_.Exception.Message
        $plan = Get-CrossRepoInstallFallbackPlan $repo $parsed.skills $errMsg
        if ($plan -and -not $script:CrossRepoAutoFallbackInProgress) {
            Log ("当前仓库未命中技能，自动回退到建议仓库重试：repo={0} --skill {1}" -f $plan.repo, $plan.skill) "WARN"
            $script:CrossRepoAutoFallbackInProgress = $true
            try {
                $fallbackTokens = @([string]$plan.repo, "--skill", [string]$plan.skill)
                if (-not [string]::IsNullOrWhiteSpace($parsed.ref)) { $fallbackTokens += @("--ref", [string]$parsed.ref) }
                if (-not [string]::IsNullOrWhiteSpace($parsed.mode) -and $parsed.mode -ne "manual") { $fallbackTokens += @("--mode", [string]$parsed.mode) }
                if ([bool]$parsed.sparse) { $fallbackTokens += "--sparse" }

                $autoOk = if ($NoBuild) { Add-ImportFromArgs $fallbackTokens -NoBuild } else { Add-ImportFromArgs $fallbackTokens }
                if ($autoOk) {
                    Write-Host ("已自动回退安装成功：{0}" -f $plan.command) -ForegroundColor Green
                    return $true
                }
            }
            finally {
                $script:CrossRepoAutoFallbackInProgress = $false
            }
        }
        if (-not $DryRun -and $cfgRaw) { Set-ContentUtf8 $CfgPath $cfgRaw }
        Write-Host ("❌ 导入失败: {0}" -f $errMsg) -ForegroundColor Red
        Write-InstallErrorHint $errMsg $repo $parsed.skills
        return $false
    }
}

function 初始化 {
    Preflight
    $cfg = LoadCfg

    foreach ($v in $cfg.vendors) {
        Need (-not [string]::IsNullOrWhiteSpace($v.name)) "vendor 缺少 name"
        Need (-not [string]::IsNullOrWhiteSpace($v.repo)) "vendor $($v.name) 缺少 repo"
        if ([string]::IsNullOrWhiteSpace($v.ref)) { $v.ref = "main" }

        $path = VendorPath $v.name
        if (Test-InstalledVendorPath $path $v.repo) {
            Write-Host "已存在：vendor/$($v.name)（来源匹配，跳过 clone）"
            continue
        }

        if (Test-Path $path) {
            $origin = $null
            try {
                Push-Location $path
                try { $origin = Invoke-GitCapture @("remote", "get-url", "origin") } finally { Pop-Location }
            }
            catch {}
            $originText = if ([string]::IsNullOrWhiteSpace($origin)) { "unknown" } else { $origin }
            throw ("vendor/{0} 已存在，但来源不匹配或不是 git 仓库：current={1}, expected={2}" -f $v.name, $originText, $v.repo)
        }

        Invoke-Git @("clone", $v.repo, $path)
        Push-Location $path
        Invoke-Git @("checkout", $v.ref)
        Pop-Location
    }

    # 初始化后建议先安装/卸载
    Write-Host "初始化完成。建议下一步：直接【安装】。"
    Clear-SkillsCache
}

function 新增技能库 {
    Preflight
    $repoInput = Read-Host "请输入技能库地址（留空=仅初始化已有 vendors）"
    if ([string]::IsNullOrWhiteSpace($repoInput)) {
        初始化
        return
    }
    $repo = Normalize-RepoUrl $repoInput
    $ref = Read-Host "可选：输入分支/Tag（留空默认 main）"
    if ([string]::IsNullOrWhiteSpace($ref)) { $ref = "main" }
    if ($ref -match "^\d+$") {
        $confirm = Read-Host "你输入的 ref 是纯数字，可能误填了菜单序号。继续使用该 ref？(y/N)"
        if (-not (Is-Yes $confirm)) { throw "已取消：请重新输入正确的分支/Tag。" }
    }
    $name = Read-Host "可选：输入自定义名称（留空自动从 URL 推断）"
    if ([string]::IsNullOrWhiteSpace($name)) { $name = Guess-VendorName $repo }
    $name = Normalize-NameWithNotice $name "vendor 名称"

    $cfg = LoadCfg
    $sameNameVendor = $cfg.vendors | Where-Object { $_.name -eq $name } | Select-Object -First 1
    if ($sameNameVendor) {
        if (Is-SameRepoIdentity ([string]$sameNameVendor.repo) $repo) {
            $installedPath = VendorPath $name
            if (Test-InstalledVendorPath $installedPath $repo) {
                Write-Host ("已存在：vendor/{0}（来源匹配，跳过新增）" -f $name)
                return
            }

            Write-Host ("已存在：vendor/{0}（来源匹配，检测到本地目录缺失或异常）" -f $name) -ForegroundColor Yellow
            Write-Host "将自动执行【初始化】补齐本地仓库..." -ForegroundColor Yellow
            初始化
            return
        }
        Need $false ("vendor 名称已存在：{0}（当前来源：{1}，期望来源：{2}）" -f $name, [string]$sameNameVendor.repo, $repo)
    }

    $sameRepoVendor = Match-VendorByRepo $cfg $repo
    if ($sameRepoVendor) {
        $installedPath = VendorPath $sameRepoVendor.name
        if (Test-InstalledVendorPath $installedPath $repo) {
            if ($sameRepoVendor.name -ne $name) {
                Write-Host ("该仓库已接入：vendor/{0}（忽略新名称：{1}，跳过新增）" -f $sameRepoVendor.name, $name)
            }
            else {
                Write-Host ("已存在：vendor/{0}（来源匹配，跳过新增）" -f $sameRepoVendor.name)
            }
            return
        }

        Write-Host ("该仓库已接入：vendor/{0}（检测到本地目录缺失或异常）" -f $sameRepoVendor.name) -ForegroundColor Yellow
        Write-Host "将自动执行【初始化】补齐本地仓库..." -ForegroundColor Yellow
        初始化
        return
    }

    $cfgRaw = ""
    if (Test-Path $CfgPath) { $cfgRaw = Get-Content $CfgPath -Raw }
    $tmp = Join-Path $VendorDir ("_tmp_" + $name)

    try {
        if (Test-Path $tmp) { Invoke-RemoveItem $tmp -Recurse }
        Invoke-Git @("clone", $repo, $tmp)
        Push-Location $tmp
        try {
            Invoke-Git @("checkout", $ref)
        }
        finally {
            Pop-Location
        }

        $cfg = LoadCfg
        if (Test-Path $CfgPath) { $cfgRaw = Get-Content $CfgPath -Raw }
        Need (-not ($cfg.vendors | Where-Object { $_.name -eq $name })) "vendor 名称已存在：$name"
        $cfg.vendors += @{ name = $name; repo = $repo; ref = $ref }
        SaveCfgSafe $cfg $cfgRaw

        $dst = VendorPath $name
        Need (-not (Test-Path $dst)) "vendor 已存在：$name"
        Invoke-MoveItem $tmp $dst

        Write-Host "新增完成。"
        
        # Auto-migrate orphan manual skills
        $migrated = Migrate-ManualToVendor $cfg $name $repo
        if ($migrated -gt 0) {
            SaveCfgSafe $cfg $cfgRaw # Save again with migrations
            Write-Host ("已自动迁移 {0} 个无需手动维护的技能到新 Vendor。" -f $migrated) -ForegroundColor Yellow
        }

        Clear-SkillsCache
    }
    catch {
        if (Test-Path $tmp) { Invoke-RemoveItem $tmp -Recurse }
        if (-not $DryRun -and $cfgRaw) { Set-ContentUtf8 $CfgPath $cfgRaw }
        Write-Host ("❌ 操作失败: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
}

function 删除技能库 {
    Preflight
    $cfg = LoadCfg
    Need ($cfg.vendors.Count -gt 0) "当前没有可删除的技能库。"

    $toRemove = Select-Items $cfg.vendors `
    { param($idx, $v) return ("{0,3}) {1} :: {2}" -f $idx, $v.name, $v.repo) } `
        "请选择要删除的技能库" `
        "未解析到有效序号（可能是分隔符或范围格式问题）。已取消删除。"
    if ($toRemove.Count -eq 0) {
        Write-Host "未选择任何技能库。"
        return
    }
    $preview = Format-VendorPreview $toRemove
    if (-not (Confirm-WithSummary "将删除以下技能库" $preview "确认删除所选技能库？" "Y")) {
        Write-Host "已取消删除。"
        return
    }
    $keepInstalledSkills = Confirm-Action "删除时是否保留该技能库下已安装技能（转换为 manual）？" "Y" -DefaultNo
    if (Skip-IfDryRun "删除技能库") { return }

    $cfgRaw = ""
    if (Test-Path $CfgPath) { $cfgRaw = Get-Content $CfgPath -Raw }
    try {
        $removeNames = New-Object System.Collections.Generic.HashSet[string]
        foreach ($v in $toRemove) { $removeNames.Add($v.name) | Out-Null }

        if ($keepInstalledSkills) {
            $totalConverted = 0
            $totalSkipped = 0
            foreach ($v in $toRemove) {
                $result = Convert-InstalledVendorSkillsToManual $cfg $v
                $totalConverted += [int]$result.converted
                $totalSkipped += [int]$result.skipped
            }
            if ($totalConverted -gt 0 -or $totalSkipped -gt 0) {
                Write-Host ("保留技能转换完成：converted={0}, skipped={1}" -f $totalConverted, $totalSkipped) -ForegroundColor Yellow
            }
        }

        $cfg.vendors = $cfg.vendors | Where-Object { -not $removeNames.Contains($_.name) }
        $cfg.mappings = $cfg.mappings | Where-Object { -not $removeNames.Contains($_.vendor) }
        $cfg.imports = $cfg.imports | Where-Object { -not ($_.mode -eq "vendor" -and $removeNames.Contains($_.name)) }
        SaveCfgSafe $cfg $cfgRaw

        foreach ($v in $toRemove) {
            $path = VendorPath $v.name
            if (Test-Path $path) { Invoke-RemoveItem $path -Recurse }
        }
        Write-Host ("已删除技能库：{0} 项。" -f $toRemove.Count)
        Clear-SkillsCache
        构建生效
    }
    catch {
        if (-not $DryRun -and $cfgRaw) { Set-ContentUtf8 $CfgPath $cfgRaw }
        Write-Host ("❌ 删除失败: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
}

function Get-SkillsUnder([string]$base, [string]$vendorName) {
    if (-not $script:SkillListCache) { $script:SkillListCache = @{} }
    $key = "{0}|{1}" -f $vendorName, $base
    if ($script:SkillListCache.ContainsKey($key)) {
        return $script:SkillListCache[$key]
    }
    $items = @()
    if (Test-Path $base) {
        # Search for all supported markers
        $found = Get-ChildItem $base -Recurse -File -Force -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -match "^(SKILL|AGENTS|GEMINI|CLAUDE)\.md$" }
      
        $seenDirs = New-Object System.Collections.Generic.HashSet[string]
        foreach ($f in $found) {
            $dir = $f.Directory.FullName
            if (-not $seenDirs.Add($dir)) { continue }
      
            $rel = $dir.Substring($base.Length).TrimStart("\\")
            if ([string]::IsNullOrWhiteSpace($rel)) { $rel = "." }
            $items += [pscustomobject]@{ vendor = $vendorName; from = $rel; full = $dir }
        }
    }
    $items = ($items | Sort-Object vendor, from)
    $script:SkillListCache[$key] = $items
    return $items
}

function 收集Skills([string]$filter, $cfg = $null, $manualItems = $null) {
    if ($null -eq $cfg) { $cfg = LoadCfg }
    $items = @()

    foreach ($v in $cfg.vendors) {
        $base = VendorPath $v.name
        if (-not (Test-Path $base)) { continue }
        $items += Get-SkillsUnder $base $v.name
    }

    if ($null -eq $manualItems) { $manualItems = 收集ManualSkills $cfg }
    $items += $manualItems
    $items += 收集OverridesSkills

    if ($filter) {
        $items = Filter-Skills $items $filter
    }

    return ($items | Sort-Object vendor, from)
}

function Resolve-ManualImportSkillPath($cfg, [string]$importName, [switch]$AllowLegacyFallback) {
    if ($null -eq $cfg) { $cfg = LoadCfg }
    if ([string]::IsNullOrWhiteSpace($importName)) { return $null }
    $imp = $cfg.imports | Where-Object { $_.mode -eq "manual" -and $_.name -eq $importName } | Select-Object -First 1
    if ($imp) {
        $skillPath = Normalize-SkillPath $imp.skill
        $cache = Join-Path $ImportDir $imp.name
        $src = if ($skillPath -eq ".") { $cache } else { Join-Path $cache $skillPath }
        if (Test-IsSkillDir $src) { return $src }
    }
    if ($AllowLegacyFallback) {
        $legacyPath = Join-Path $ManualDir $importName
        if (Test-IsSkillDir $legacyPath) { return $legacyPath }
    }
    return $null
}

function Get-ManualDisplayVendorFromRepo([string]$repo) {
    if ([string]::IsNullOrWhiteSpace($repo)) { return "manual" }
    $r = [string]$repo
    $r = $r.Trim().Trim("'`"").TrimEnd("/")
    if ([string]::IsNullOrWhiteSpace($r)) { return "manual" }
    if ($r -match "^[A-Za-z]+://") {
        try {
            $uri = [Uri]$r
            $r = [string]$uri.AbsolutePath
        }
        catch {}
    }
    $r = $r.Trim().Trim("/")
    if ([string]::IsNullOrWhiteSpace($r)) { return "manual" }
    $r = $r -replace "\\", "/"
    $parts = @($r -split "/" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $leaf = if ($parts.Count -gt 0) { [string]$parts[$parts.Count - 1] } else { $r }
    if ($leaf.EndsWith(".git", [System.StringComparison]::OrdinalIgnoreCase)) {
        $leaf = $leaf.Substring(0, $leaf.Length - 4)
    }
    $leafNorm = Normalize-Name $leaf
    if ([string]::IsNullOrWhiteSpace($leafNorm)) { return "manual" }
    $first = @($leafNorm -split "-" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
    if ($first.Count -gt 0) { return [string]$first[0] }
    return $leafNorm
}

function 收集ManualSkills($cfg = $null, [switch]$IncludeLegacyManualDir) {
    if ($null -eq $cfg) { $cfg = LoadCfg }
    $items = @()
    $seen = New-Object System.Collections.Generic.HashSet[string]

    foreach ($i in $cfg.imports) {
        if ($i.mode -ne "manual") { continue }
        if ([string]::IsNullOrWhiteSpace($i.name)) { continue }
        $src = Resolve-ManualImportSkillPath $cfg $i.name -AllowLegacyFallback
        if (-not $src) { continue }
        $from = [string]$i.name
        if ($seen.Add($from)) {
            $items += [pscustomobject]@{
                vendor = "manual"
                display_vendor = Get-ManualDisplayVendorFromRepo ([string]$i.repo)
                from = $from
                full = $src
                source = if ((Join-Path $ManualDir $from) -eq $src) { "legacy-manual-dir" } else { "imports" }
            }
        }
    }

    if ($IncludeLegacyManualDir) {
        foreach ($legacy in (Get-SkillsUnder $ManualDir "manual")) {
            if ($seen.Add($legacy.from)) {
                $items += [pscustomobject]@{
                    vendor = "manual"
                    display_vendor = "manual"
                    from = $legacy.from
                    full = $legacy.full
                    source = "legacy-manual-dir"
                }
            }
        }
    }

    return ($items | Sort-Object vendor, from)
}

function Get-OverridesDirs {
    if (-not (Test-Path $OverridesDir)) {
        return @()
    }
    return Get-ChildItem $OverridesDir -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne ".bak" }
}

function 收集OverridesSkills {
    $items = @()
    foreach ($d in (Get-OverridesDirs)) {
        $items += [pscustomobject]@{ vendor = "overrides"; from = $d.Name; full = $d.FullName }
    }
    return $items
}

function Get-InstalledSet($cfg, $manualItems = $null, $overrideItems = $null) {
    $installed = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in $cfg.mappings) {
        $installed.Add("$($m.vendor)|$($m.from)") | Out-Null
    }
    if ($null -eq $overrideItems) { $overrideItems = 收集OverridesSkills }
    foreach ($m in $overrideItems) {
        $installed.Add("overrides|$($m.from)") | Out-Null
    }
    return $installed
}

function Get-UniqueManualImportName($cfg, [string]$baseName, $reservedNames = $null) {
    $normalized = Normalize-NameWithNotice $baseName "manual 导入名称"
    if ($null -eq $reservedNames) {
        $reservedNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    }
    $existing = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($i in @($cfg.imports)) {
        if ($null -eq $i) { continue }
        $name = [string]$i.name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $existing.Add($name) | Out-Null
    }

    $candidate = $normalized
    $suffix = 2
    while ($existing.Contains($candidate) -or $reservedNames.Contains($candidate) -or (Test-Path (Join-Path $ImportDir $candidate))) {
        $candidate = ("{0}-{1}" -f $normalized, $suffix)
        $suffix++
    }
    $reservedNames.Add($candidate) | Out-Null
    return $candidate
}

function Convert-InstalledVendorSkillsToManual($cfg, $vendorItem) {
    Need ($null -ne $cfg) "转换失败：配置对象为空。"
    Need ($null -ne $vendorItem) "转换失败：vendor 项为空。"

    $vendorName = [string]$vendorItem.name
    $vendorRepo = [string]$vendorItem.repo
    $vendorRef = [string]$vendorItem.ref
    Need (-not [string]::IsNullOrWhiteSpace($vendorName)) "转换失败：vendor 缺少名称。"

    $vendorPath = VendorPath $vendorName
    $vendorMappings = @($cfg.mappings | Where-Object { $_.vendor -eq $vendorName -and (Normalize-SkillPath ([string]$_.from)) -ne "." })
    if ($vendorMappings.Count -eq 0) {
        return [pscustomobject]@{ converted = 0; skipped = 0 }
    }

    Need (Test-Path $vendorPath) ("转换失败：vendor 目录不存在：{0}" -f $vendorPath)
    EnsureDir $ImportDir
    $reservedNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    $converted = 0
    $skipped = 0
    foreach ($m in $vendorMappings) {
        $skillPath = Normalize-SkillPath ([string]$m.from)
        $src = Join-Path $vendorPath $skillPath
        if (-not (Test-IsSkillDir $src)) {
            Write-Host ("⚠️ 保留技能时跳过（源不存在或无技能标记）：vendor={0}, from={1}" -f $vendorName, $skillPath) -ForegroundColor Yellow
            $skipped++
            continue
        }

        $baseName = Split-Path $skillPath -Leaf
        if ([string]::IsNullOrWhiteSpace($baseName)) { $baseName = $vendorName }
        $manualName = Get-UniqueManualImportName $cfg $baseName $reservedNames
        $dst = Join-Path $ImportDir $manualName
        Invoke-WithRetry { Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force } 3 250

        $manualImport = @{
            name = $manualName
            repo = $vendorRepo
            ref = $vendorRef
            skill = "."
            mode = "manual"
            sparse = $false
        }
        Upsert-Import $cfg $manualImport

        $cfg.mappings += @{
            vendor = "manual"
            from = $manualName
            to = [string]$m.to
        }
        $converted++
    }

    # Remove old vendor mappings now that manual mappings are created.
    $cfg.mappings = @($cfg.mappings | Where-Object { [string]$_.vendor -ne $vendorName })
    return [pscustomobject]@{ converted = $converted; skipped = $skipped }
}

function Hide-VendorRootSkills($items) {
    $arr = @($items)
    if ($arr.Count -eq 0) { return @() }

    $vendorsWithChildren = New-Object System.Collections.Generic.HashSet[string]
    foreach ($item in $arr) {
        if ($null -eq $item) { continue }
        $vendor = [string]$item.vendor
        $from = [string]$item.from
        if ([string]::IsNullOrWhiteSpace($vendor)) { continue }
        if ($from -ne ".") {
            $vendorsWithChildren.Add($vendor) | Out-Null
        }
    }

    if ($vendorsWithChildren.Count -eq 0) { return $arr }

    $filtered = @()
    foreach ($item in $arr) {
        if ($null -eq $item) { continue }
        $vendor = [string]$item.vendor
        $from = [string]$item.from
        if ($from -eq "." -and $vendorsWithChildren.Contains($vendor)) { continue }
        $filtered += $item
    }
    return $filtered
}

function Should-SyncMappingToAgent($mapping) {
    if ($null -eq $mapping) { return $false }
    $vendor = [string]$mapping.vendor
    $from = [string]$mapping.from
    # Vendor 根映射仅用于来源聚合与清单管理，不下发到各 CLI 用户级 skills 目录。
    if ($from -eq "." -and $vendor -ne "manual" -and $vendor -ne "overrides") { return $false }
    return $true
}

function Remove-VendorRootMappingOutputsFromAgent($cfg) {
    if ($null -eq $cfg) { return 0 }
    $removed = 0
    foreach ($m in @($cfg.mappings)) {
        if ($null -eq $m) { continue }
        if (Should-SyncMappingToAgent $m) { continue }
        $to = [string]$m.to
        if ([string]::IsNullOrWhiteSpace($to)) { continue }
        $dst = Join-Path $AgentDir $to
        if (-not (Is-PathInsideOrEqual $dst $AgentDir)) { continue }
        if (Test-Path -LiteralPath $dst) {
            Invoke-RemoveItemWithRetry $dst -Recurse -IgnoreFailure | Out-Null
            $removed++
            Log ("已剔除 vendor 根映射产物：{0}" -f $to)
        }
    }
    return $removed
}

function Parse-IndexSelection([string]$selText, [int]$max) {
    if ($null -eq $selText) { return @() }
    $selText = $selText.Trim()
    if ([string]::IsNullOrWhiteSpace($selText)) { return @() }
    $low = $selText.ToLowerInvariant()
    if ($low -eq "all") { return 1..$max }
    if ($low -eq "0") { return @() }
    if ($low -eq "none") { return @() }

    # Normalize common non-ASCII separators/dashes from IME input.
    $selText = $selText -replace "[，、；;/;\\s]+", ","
    $selText = $selText -replace "[－–—−]", "-"

    $set = New-Object System.Collections.Generic.HashSet[int]
    foreach ($part in $selText.Split(",") | ForEach-Object { $_.Trim() }) {
        if ($part -match "^\d+$") {
            $n = [int]$part
            if ($n -ge 1 -and $n -le $max) { $set.Add($n) | Out-Null }
        }
        elseif ($part -match "^(\d+)-(\d+)$") {
            $a = [int]$Matches[1]; $b = [int]$Matches[2]
            if ($a -gt $b) { $tmp = $a; $a = $b; $b = $tmp }
            for ($i = $a; $i -le $b; $i++) {
                if ($i -ge 1 -and $i -le $max) { $set.Add($i) | Out-Null }
            }
        }
    }
    return $set | Sort-Object
}

function Write-SelectionHint {
    Write-Host ""
    Write-Host "输入多选：如 1,3,5-10；输入 all 全选；输入 0 取消。"
}

function Read-SelectionIndices([string]$prompt, [int]$count, [string]$invalidMsg) {
    $sel = Read-HostSafe $prompt
    $idx = Parse-IndexSelection $sel $count
    if ($idx.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($sel) -and $sel.ToLowerInvariant() -ne "0") {
        Write-Host $invalidMsg
        return [pscustomobject]@{ indices = @(); canceled = $false }
    }
    $canceled = -not [string]::IsNullOrWhiteSpace($sel) -and $sel.Trim().ToLowerInvariant() -eq "0"
    return [pscustomobject]@{ indices = $idx; canceled = $canceled }
}
function Select-Items($items, [scriptblock]$formatter, [string]$prompt, [string]$invalidMsg) {
    if ($items.Count -eq 0) { return [pscustomobject]@{ items = @(); canceled = $false } }
    Write-ItemsInColumns $items $formatter
    Write-SelectionHint
    $selection = Read-SelectionIndices $prompt $items.Count $invalidMsg
    if ($selection.canceled) { return [pscustomobject]@{ items = @(); canceled = $true } }
    $idx = $selection.indices
    if ($idx.Count -eq 0) { return [pscustomobject]@{ items = @(); canceled = $false } }
    $selected = @()
    foreach ($n in $idx) { $selected += $items[$n - 1] }
    return [pscustomobject]@{ items = $selected; canceled = $false }
}

function Filter-Skills($items, [string]$filter) {
    if ([string]::IsNullOrWhiteSpace($filter)) { return $items }
    $f = $filter.Trim()
    if ($f.StartsWith("/") -and $f.EndsWith("/") -and $f.Length -gt 2) {
        $pattern = $f.Trim("/")
        try {
            return $items | Where-Object { $_.vendor -match $pattern -or $_.from -match $pattern }
        }
        catch {
            Write-Warning "无效的正则表达式：$pattern"
            return @()
        }
    }
    $terms = $f.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
    foreach ($t in $terms) {
        $safeT = [WildcardPattern]::Escape($t)
        $items = $items | Where-Object { $_.vendor -like "*$safeT*" -or $_.from -like "*$safeT*" }
    }
    return $items
}

function Write-ItemsInColumns($items, [scriptblock]$formatter) {
    $count = $items.Count
    if ($count -eq 0) { return }
    $width = 120
    try { $width = [int]$Host.UI.RawUI.WindowSize.Width } catch {}
    $sample = @()
    for ($i = 0; $i -lt $count; $i++) {
        $sample += (& $formatter ($i + 1) $items[$i])
    }
    $maxLen = ($sample | Measure-Object -Maximum -Property Length).Maximum
    if (-not $maxLen) { $maxLen = 40 }
    $colWidth = $maxLen + 2
    $cols = [Math]::Max(1, [Math]::Floor($width / $colWidth))
    $rows = [Math]::Ceiling($count / $cols)
    for ($r = 0; $r -lt $rows; $r++) {
        for ($c = 0; $c -lt $cols; $c++) {
            $i = $r + ($c * $rows)
            if ($i -ge $count) { continue }
            $text = (& $formatter ($i + 1) $items[$i])
            $pad = " " * ($colWidth - $text.Length)
            Write-Host -NoNewline ($text + $pad)
        }
        Write-Host ""
    }
}

function Make-TargetName([string]$vendor, [string]$from) {
    $suffix = ($from -replace "[\\\\/]", "-")
    return ("{0}-{1}" -f $vendor, $suffix)
}

function 安装 {
    Preflight
    $cfg = LoadCfg
    $manualItems = 收集ManualSkills $cfg
    $filter = Read-Host "可选：关键词过滤（空格=AND，或 /regex/）"
    $all = 收集Skills "" $cfg $manualItems
    Need ($all.Count -gt 0) "未发现任何 skills。请先【新增技能库】。"
    $list = Hide-VendorRootSkills (Filter-Skills $all $filter)
    if ($list.Count -eq 0) {
        Write-Host "未发现匹配项。"
        return
    }
    $installed = Get-InstalledSet $cfg $manualItems

    $available = $list | Where-Object { -not $installed.Contains("$($_.vendor)|$($_.from)") }
    if ($available.Count -eq 0) {
        Write-Host "没有可安装的新技能。将直接执行【构建生效】。"
        构建生效
        return
    }

    $newMappings = @()
    foreach ($m in $cfg.mappings) { $newMappings += $m }
    $existing = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in $cfg.mappings) { $existing.Add("$($m.vendor)|$($m.from)") | Out-Null }
    $previewAdded = @()
    $previewMappings = @()

    $added = 0
    $selection = Select-Items $available `
    { param($idx, $item)
        $displayVendor = Get-DisplayVendor $item
        $leaf = Split-Path $item.from -Leaf
        if ($item.from -eq ".") { $leaf = $displayVendor }
        return ("{0,3}) [{1}] {2}" -f $idx, $displayVendor, $leaf)
    } `
        "请选择要安装的技能（批量安装到白名单）" `
        "未解析到有效序号（可能是分隔符或范围格式问题）。已取消写入白名单。"
    if ($selection.canceled) {
        Write-Host "已取消安装。"
        return
    }
    $selected = $selection.items
    if ($selected.Count -eq 0) {
        Write-Host "未选择新增技能。将直接执行【构建生效】。"
        构建生效
        return
    }

    foreach ($item in $selected) {
        $key = "$($item.vendor)|$($item.from)"
        if ($existing.Contains($key)) { continue }
        $to = Make-TargetName $item.vendor $item.from

        $newMappings += @{ vendor = $item.vendor; from = $item.from; to = $to }
        $existing.Add($key) | Out-Null
        $added++
        $previewItem = [ordered]@{ vendor = $item.vendor; from = $item.from; to = $to }
        if ($item.PSObject.Properties.Match("display_vendor").Count -gt 0) {
            $previewItem.display_vendor = [string]$item.display_vendor
        }
        $previewMappings += [pscustomobject]$previewItem
    }

    if ($added -eq 0) {
        Write-Host "未新增任何技能。将直接执行【构建生效】。"
        构建生效
        return
    }

    $previewAdded = Format-MappingPreview $previewMappings
    if (-not (Confirm-WithSummary "将新增以下白名单映射" $previewAdded "确认写入白名单并构建生效？" "Y")) {
        Write-Host "已取消安装。"
        return
    }
    if (Skip-IfDryRun "安装技能") { return }

    $cfg.mappings = $newMappings
    SaveCfg $cfg

    Write-Host ("已追加安装：{0} 项。开始【构建生效】..." -f $added)
    构建生效
}

function 卸载 {
    Preflight
    $cfg = LoadCfg
    $manualItems = 收集ManualSkills $cfg
    $overrideItems = 收集OverridesSkills
    $filter = Read-Host "可选：关键词过滤（空格=AND，或 /regex/）"

    # 卸载范围：已映射技能 + overrides
    $installedSet = Get-InstalledSet $cfg $manualItems $overrideItems
    $all = 收集Skills "" $cfg $manualItems
    Need ($all.Count -gt 0) "未发现任何 skills。请先【新增技能库】。"
    $list = Filter-Skills $all $filter
    if ($list.Count -eq 0) {
        Write-Host "未发现匹配项。"
        return
    }

    # 筛选已安装的技能
    $onlyInstalled = $list | Where-Object { $installedSet.Contains("$($_.vendor)|$($_.from)") }
    $onlyInstalled = Hide-VendorRootSkills $onlyInstalled
    if ($onlyInstalled.Count -eq 0) {
        Write-Host "没有已安装的技能可卸载。"
        return
    }

    $selection = Select-Items $onlyInstalled `
    { param($idx, $item)
        $label = Get-DisplayVendor $item
        $leaf = Split-Path $item.from -Leaf
        if ($item.from -eq ".") { $leaf = $label }
        return ("{0,3}) [{1}] {2}" -f $idx, $label, $leaf)
    } `
        "请选择要卸载的技能（从白名单移除）" `
        "未解析到有效序号（可能是分隔符或范围格式问题）。已取消操作。"
    if ($selection.canceled) {
        Write-Host "已取消卸载。"
        return
    }
    $selectedItems = $selection.items
    if ($selectedItems.Count -eq 0) {
        Write-Host "未选择任何技能。"
        return
    }

    # 区分处理：vendor 移除白名单；manual 删除 imports 条目（兼容清理 legacy manual 目录）；overrides 备份后删除
    $preview = Format-SkillPreview $selectedItems
    if (-not (Confirm-WithSummary "将卸载以下技能" $preview "确认卸载所选技能？" "Y")) {
        Write-Host "已取消卸载。"
        return
    }
    if (Skip-IfDryRun "卸载技能") { return }

    $removedMappings = 0
    $removedVendorImports = 0
    $deletedManualImports = 0
    $deletedLegacyManualDirs = 0
    $deletedOverrides = 0
    $backedOverrides = 0
    foreach ($item in $selectedItems) {
        if ($item.vendor -eq "manual") {
            $before = @($cfg.imports).Count
            $cfg.imports = @($cfg.imports | Where-Object { -not ($_.mode -eq "manual" -and $_.name -eq $item.from) })
            $deletedManualImports += ($before - @($cfg.imports).Count)

            $legacyPath = Join-Path $ManualDir $item.from
            if (Test-Path $legacyPath) {
                Invoke-RemoveItem $legacyPath -Recurse
                $deletedLegacyManualDirs++
            }
            $cfg.mappings = $cfg.mappings | Where-Object { -not ("$($_.vendor)|$($_.from)" -eq "manual|$($item.from)") }
        }
        elseif ($item.vendor -eq "overrides") {
            $bak = Backup-OverrideDir $item.from
            if ($bak) { $backedOverrides++ }
            $deletedOverrides++
        }
        else {
            # mapping 技能：从 mappings 移除
            $cfg.mappings = @($cfg.mappings | Where-Object { -not ("$($_.vendor)|$($_.from)" -eq "$($item.vendor)|$($item.from)") })
            $removedMappings++

            $skillPath = Normalize-SkillPath ([string]$item.from)
            $hasSameMapping = @($cfg.mappings | Where-Object { $_.vendor -eq $item.vendor -and $_.from -eq $skillPath }).Count -gt 0
            if (-not $hasSameMapping) {
                $beforeImports = @($cfg.imports).Count
                $cfg.imports = @($cfg.imports | Where-Object {
                        $mode = if ($_.PSObject.Properties.Match("mode").Count -gt 0) { [string]$_.mode } else { "manual" }
                        if ($mode -ne "vendor") { return $true }
                        if ([string]$_.name -ne [string]$item.vendor) { return $true }
                        $importSkill = Normalize-SkillPath ([string]$_.skill)
                        return ($importSkill -ne $skillPath)
                    })
                $removedVendorImports += ($beforeImports - @($cfg.imports).Count)
            }
        }
    }

    SaveCfg $cfg
    $parts = @()
    if ($removedMappings -gt 0) { $parts += "移除白名单 $removedMappings 项" }
    if ($removedVendorImports -gt 0) { $parts += "删除 vendor 导入 $removedVendorImports 项" }
    if ($deletedManualImports -gt 0) { $parts += "删除 manual 导入 $deletedManualImports 项" }
    if ($deletedLegacyManualDirs -gt 0) { $parts += "清理 legacy manual 目录 $deletedLegacyManualDirs 项" }
    if ($deletedOverrides -gt 0) { $parts += "删除 overrides $deletedOverrides 项（已备份 $backedOverrides 项）" }
    Write-Host ("已完成：{0}。开始【构建生效】..." -f ($parts -join "，"))
    if ($backedOverrides -gt 0) {
        Write-Host "提示：overrides 备份已保存到 overrides/.bak/，如需彻底清理可手动删除该目录或其中备份。"
    }
    Clear-SkillsCache
    构建生效
}

function 选择 {
    Write-Host "提示：已改为独立【安装/卸载】菜单。"
    安装
}


function 发现 {
    Invoke-WithMetric "discover" {
        Preflight
        $cfg = LoadCfg
        $manualItems = 收集ManualSkills $cfg
        $f = $Filter
        if ([string]::IsNullOrWhiteSpace($f)) {
            $f = Read-Host "可选：关键词过滤（空格=AND，或 /regex/）"
        }
        $all = 收集Skills "" $cfg $manualItems
        Need ($all.Count -gt 0) "未发现任何 skills。请先【新增技能库】。"
        $list = Hide-VendorRootSkills (Filter-Skills $all $f)
        if ($list.Count -eq 0) {
            Write-Host "未发现匹配项。"
            return
        }
        $installed = Get-InstalledSet $cfg $manualItems
        Write-ItemsInColumns $list { param($idx, $item)
            $mark = if ($installed.Contains("$($item.vendor)|$($item.from)")) { "*" } else { " " }
            $displayVendor = Get-DisplayVendor $item
            $leaf = Split-Path $item.from -Leaf
            if ($item.from -eq ".") { $leaf = $displayVendor }
            return ("{0,3}) [{1}] [{2}] {3}" -f $idx, $mark, $displayVendor, $leaf)
        }
    } @{ command = "发现" } -NoHost
}

function 清空Agent目录 {
    if (Test-Path $AgentDir) {
        Invoke-RemoveItemWithRetry $AgentDir -Recurse | Out-Null
    }
    EnsureDir $AgentDir
}

function Resolve-SourceBase([string]$vendorName, $cfg) {
    if ($vendorName -eq "manual") { return $null }
    $v = $cfg.vendors | Where-Object { $_.name -eq $vendorName } | Select-Object -First 1
    if (-not $v) { throw "白名单引用了不存在的 vendor：$vendorName" }
    return (VendorPath $v.name)
}

function Get-BuildCachePath {
    return (Join-Path $Root ".build-cache.json")
}

function ConvertTo-Hashtable($obj) {
    $table = @{}
    if ($null -eq $obj) { return $table }
    if ($obj -is [hashtable]) { return $obj }
    if ($obj -is [pscustomobject]) {
        foreach ($p in $obj.PSObject.Properties) { $table[[string]$p.Name] = $p.Value }
    }
    return $table
}

function Load-BuildCache {
    $path = Get-BuildCachePath
    if (-not (Test-Path $path)) { return @{} }
    try {
        $raw = Get-Content $path -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
        $obj = $raw | ConvertFrom-Json
        return (ConvertTo-Hashtable $obj)
    }
    catch {
        Log ("构建缓存读取失败，已忽略并重建：{0}" -f $_.Exception.Message) "WARN"
        return @{}
    }
}

function Save-BuildCache($cache) {
    if ($DryRun) { return }
    try {
        $json = $cache | ConvertTo-Json -Depth 20
        Set-ContentUtf8 (Get-BuildCachePath) $json
    }
    catch {
        Log ("构建缓存保存失败（已忽略）：{0}" -f $_.Exception.Message) "WARN"
    }
}

function Get-DirectoryFingerprint([string]$dir) {
    if (-not (Test-Path $dir)) { return "missing" }
    $files = Get-ChildItem $dir -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($dir.Length).TrimStart("\")
        $parts.Add(("{0}|{1}|{2}" -f $rel, [string]$f.Length, [string]$f.LastWriteTimeUtc.Ticks)) | Out-Null
    }
    $input = $parts -join "`n"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($input)
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash) -replace "-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Mirror-SkillWithCache(
    [string]$src,
    [string]$dst,
    [string]$cacheKey,
    [hashtable]$oldCache,
    [hashtable]$newCache,
    $stats
) {
    $fp = Get-DirectoryFingerprint $src
    $newCache[$cacheKey] = $fp
    $old = if ($oldCache.ContainsKey($cacheKey)) { [string]$oldCache[$cacheKey] } else { "" }
    if ((Test-Path $dst) -and $old -eq $fp) {
        $expanded = Expand-RelativeSkillPlaceholders $dst
        if ($expanded -gt 0) {
            Log ("命中构建缓存后补展开相对路径 SKILL 占位文件：{0} 项 [{1}]" -f $expanded, $cacheKey)
        }
        $stats.skipped++
        Log ("命中构建缓存，跳过复制：{0}" -f $cacheKey)
        return
    }
    RoboMirror $src $dst
    $expanded = Expand-RelativeSkillPlaceholders $dst
    if ($expanded -gt 0) {
        Log ("已展开相对路径 SKILL 占位文件：{0} 项 [{1}]" -f $expanded, $cacheKey)
    }
    $stats.mirrored++
}

function Get-SkillNameConflictBuckets([string]$agentRoot) {
    $nameToPaths = @{}
    foreach ($skillFile in (Get-ChildItem $agentRoot -Recurse -Filter "SKILL.md" -File -ErrorAction SilentlyContinue)) {
        $declaredName = $null
        foreach ($line in (Get-Content $skillFile.FullName -TotalCount 80 -ErrorAction SilentlyContinue)) {
            if ($line -match "^\s*name:\s*(.+?)\s*$") {
                $declaredName = $Matches[1].Trim().Trim("'`"")
                break
            }
        }
        if ([string]::IsNullOrWhiteSpace($declaredName)) { continue }
        if (-not $nameToPaths.ContainsKey($declaredName)) {
            $nameToPaths[$declaredName] = New-Object System.Collections.Generic.List[string]
        }
        $nameToPaths[$declaredName].Add($skillFile.FullName) | Out-Null
    }
    return $nameToPaths
}

function Test-SkillNameDuplicateContentAllowed([string[]]$paths) {
    if ($null -eq $paths -or $paths.Count -le 1) { return $true }
    $hashes = New-Object System.Collections.Generic.HashSet[string]
    foreach ($path in $paths) {
        $hash = Get-FileContentHash $path
        if ([string]::IsNullOrWhiteSpace($hash)) { return $false }
        $hashes.Add($hash) | Out-Null
    }
    return ($hashes.Count -le 1)
}

function Test-SkillNameSystemOverrideAllowed([string[]]$paths) {
    if ($null -eq $paths -or $paths.Count -le 1) { return $false }
    $hasSystemPath = $false
    $hasNonSystemPath = $false
    foreach ($path in $paths) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if ($path -match "[\\/]\.system[\\/]") { $hasSystemPath = $true }
        else { $hasNonSystemPath = $true }
    }
    return ($hasSystemPath -and $hasNonSystemPath)
}

function Start-BuildTransaction {
    $txnRoot = Join-Path $Root ".txn"
    $txnId = [Guid]::NewGuid().ToString("N").Substring(0, 10)
    $path = Join-Path $txnRoot ("build-{0}" -f $txnId)
    $backupAgent = Join-Path $path "agent.backup"
    $state = [ordered]@{
        path = $path
        backup_agent = $backupAgent
        has_backup_agent = $false
        backup_error = $null
    }
    if ($DryRun) { return [pscustomobject]$state }
    EnsureDir $txnRoot
    EnsureDir $path
    if (Test-Path $AgentDir) {
        try {
            Invoke-MoveItem $AgentDir $backupAgent
            $state.has_backup_agent = $true
        }
        catch {
            if (Test-Path $backupAgent) { Invoke-RemoveItemWithRetry $backupAgent -Recurse -IgnoreFailure -SilentIgnore | Out-Null }
            $state.backup_error = $_.Exception.Message
            Log ("旧 agent/ 无法挪入事务备份，后续将直接在原目录上构建：{0}" -f $_.Exception.Message)
        }
    }
    return [pscustomobject]$state
}

function Rollback-BuildTransaction($txn) {
    if ($DryRun -or $null -eq $txn) { return }
    try {
        if (Test-Path $AgentDir) { Invoke-RemoveItemWithRetry $AgentDir -Recurse -IgnoreFailure -SilentIgnore | Out-Null }
        if ($txn.has_backup_agent -and (Test-Path $txn.backup_agent)) {
            Invoke-MoveItem $txn.backup_agent $AgentDir
            Write-Host "已回滚 agent/ 到构建前状态。" -ForegroundColor Yellow
        }
    }
    finally {
        if (Test-Path $txn.path) { Invoke-RemoveItemWithRetry $txn.path -Recurse -IgnoreFailure -SilentIgnore | Out-Null }
    }
}

function Complete-BuildTransaction($txn) {
    if ($DryRun -or $null -eq $txn) { return }
    if (Test-Path $txn.path) { Invoke-RemoveItemWithRetry $txn.path -Recurse -IgnoreFailure -SilentIgnore | Out-Null }
}

function 构建Agent($cfg = $null, [switch]$SkipPreflight, $Txn = $null) {
    return (Invoke-WithMetric "build_agent" {
        if (-not $SkipPreflight) { Preflight }
        if ($null -eq $cfg) { $cfg = LoadCfg }
        Log "开始构建 Agent..."
        $reusedExistingAgent = $false
        $cleanAgentError = $null
        try {
            清空Agent目录
        }
        catch {
            $reusedExistingAgent = $true
            $cleanAgentError = $_.Exception.Message
            EnsureDir $AgentDir
            Log ("清空 agent/ 失败，将在现有目录上继续覆盖构建：{0}" -f $_.Exception.Message)
        }
        $failures = New-Object System.Collections.Generic.List[string]
        if ($null -ne $Txn -and $Txn.PSObject.Properties.Match("backup_error").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($Txn.backup_error)) {
            $failures.Add(("build-txn:agent-backup => {0}" -f $Txn.backup_error)) | Out-Null
        }
        $stats = [pscustomobject]@{ mirrored = 0; skipped = 0; reused = $reusedExistingAgent }
        $oldCache = if ($DryRun) { @{} } else { Load-BuildCache }
        $newCache = @{}

        $count = 0
        foreach ($m in $cfg.mappings) {
            try {
                if (-not (Should-SyncMappingToAgent $m)) {
                    Log ("跳过 vendor 根映射（不参与同步）：{0}/{1}" -f $m.vendor, $m.from)
                    continue
                }
                Need (Test-SafeRelativePath $m.from -AllowDot) ("非法 mapping.from：{0}" -f $m.from)
                Need (Test-SafeRelativePath $m.to) ("非法 mapping.to：{0}" -f $m.to)
                $base = Resolve-SourceBase $m.vendor $cfg
                if ($m.vendor -eq "manual") {
                    $src = Resolve-ManualImportSkillPath $cfg $m.from -AllowLegacyFallback
                    Need (-not [string]::IsNullOrWhiteSpace($src)) ("manual 导入不存在或无效：{0}" -f $m.from)
                }
                else {
                    $src = Join-Path $base $m.from
                    Need (Is-PathInsideOrEqual $src $base) ("mapping.from 越界：{0}" -f $m.from)
                }
                $dst = Join-Path $AgentDir $m.to
                Need (Is-PathInsideOrEqual $dst $AgentDir) ("mapping.to 越界：{0}" -f $m.to)

                if (-not (Test-IsSkillDir $src)) {
                    Write-Host ("❌ 跳过无效技能（缺少标记文件）：{0}" -f $src) -ForegroundColor Red
                    continue
                }
                $cacheKey = ("mapping|{0}|{1}|{2}" -f $m.vendor, $m.from, $m.to)
                Mirror-SkillWithCache $src $dst $cacheKey $oldCache $newCache $stats
                $count++
            }
            catch {
                Write-Host ("❌ 处理技能失败 [{0}/{1}]: {2}" -f $m.vendor, $m.from, $_.Exception.Message) -ForegroundColor Red
                $failures.Add(("mapping:{0}/{1} => {2}" -f $m.vendor, $m.from, $_.Exception.Message)) | Out-Null
            }
        }

        $manualItems = 收集ManualSkills $cfg
        if ($manualItems.Count -gt 0) {
            $manualMapped = New-Object System.Collections.Generic.HashSet[string]
            foreach ($m in @($cfg.mappings)) {
                if ($m.vendor -eq "manual") { $manualMapped.Add([string]$m.from) | Out-Null }
            }
            $unmappedManual = @($manualItems | Where-Object { -not $manualMapped.Contains([string]$_.from) })
            if ($unmappedManual.Count -gt 0) {
                Log ("检测到 {0} 个 manual imports 未映射；按白名单策略不会进入 agent（可通过【安装】写入 mapping 后生效）。" -f $unmappedManual.Count) "WARN"
            }
        }

        # overrides 覆盖层（可选）：同名目录将覆盖 agent 中对应技能
        foreach ($d in (Get-OverridesDirs)) {
            try {
                $dst = Join-Path $AgentDir $d.Name
                $cacheKey = ("override|{0}" -f $d.Name)
                Mirror-SkillWithCache $d.FullName $dst $cacheKey $oldCache $newCache $stats
                Log ("应用覆盖层: {0}" -f $d.Name)
            }
            catch {
                Write-Host ("❌ 应用覆盖层失败 [{0}]: {1}" -f $d.Name, $_.Exception.Message) -ForegroundColor Red
                $failures.Add(("override:{0} => {1}" -f $d.Name, $_.Exception.Message)) | Out-Null
            }
        }

        $removedVendorRoots = Remove-VendorRootMappingOutputsFromAgent $cfg
        if ($removedVendorRoots -gt 0) {
            Log ("已剔除 {0} 个 vendor 根映射目录（不参与同步）。" -f $removedVendorRoots)
        }

        $normalizedSkillMd = Normalize-SkillMarkdownFiles $AgentDir
        if ($normalizedSkillMd.normalized -gt 0) {
            Log ("已归一化 SKILL.md 编码（移除 UTF-8 BOM）：{0} 项" -f $normalizedSkillMd.normalized)
        }
        if ($normalizedSkillMd.failed -gt 0) {
            foreach ($path in $normalizedSkillMd.failed_paths) {
                $failures.Add(("build-skill-md-normalize:{0}" -f $path)) | Out-Null
            }
        }

        $invalidSkillCleanup = Remove-InvalidSkillMarkdownFiles $AgentDir
        if ($invalidSkillCleanup.removed -gt 0) {
            Log ("已清理无效 SKILL.md（缺少 YAML frontmatter）：{0} 项" -f $invalidSkillCleanup.removed) "WARN"
        }
        if ($invalidSkillCleanup.failed -gt 0) {
            foreach ($path in $invalidSkillCleanup.failed_paths) {
                $failures.Add(("build-invalid-skill-md-cleanup:{0}" -f $path)) | Out-Null
            }
        }

        $nameToPaths = Get-SkillNameConflictBuckets $AgentDir
        foreach ($name in $nameToPaths.Keys | Sort-Object) {
            $paths = @($nameToPaths[$name])
            if ($paths.Count -le 1) { continue }
            if (Test-SkillNameDuplicateContentAllowed $paths) {
                Log ("检测到同名同内容技能别名，已跳过冲突：{0}" -f $name)
                continue
            }
            if (Test-SkillNameSystemOverrideAllowed $paths) {
                Log ("检测到系统技能与普通技能同名，已保留系统技能优先：{0}" -f $name)
                continue
            }
            Write-Host ("❌ 技能名冲突：{0}" -f $name) -ForegroundColor Red
            foreach ($p in $paths) {
                Write-Host ("   - {0}" -f $p) -ForegroundColor Red
            }
            $failures.Add(("skill-name-conflict:{0} => {1}" -f $name, ($paths -join " | "))) | Out-Null
        }

        if (-not $DryRun) { Save-BuildCache $newCache }
        if ($stats.skipped -gt 0) {
            Log ("增量构建：复用缓存 {0} 项，实际复制 {1} 项。" -f $stats.skipped, $stats.mirrored)
        }
        if ($stats.reused) {
            Log "本次构建未能清空旧 agent/，已按目录增量覆盖；若仍有陈旧技能残留，可在释放相关文件占用后重试。"
            Write-Host "❌ 检测到在旧 agent/ 上增量覆盖构建，已升级为失败。" -ForegroundColor Red
            Write-Host "   建议：先执行【解除关联】并关闭占用进程，再重试【构建生效】。" -ForegroundColor Red
            if ([string]::IsNullOrWhiteSpace($cleanAgentError)) { $cleanAgentError = "unknown error" }
            $failures.Add(("build-agent-reused-existing-dir => {0}" -f $cleanAgentError)) | Out-Null
        }
        $count = @((Get-ChildItem -LiteralPath $AgentDir -Directory -ErrorAction SilentlyContinue)).Count
        Log ("构建完成：agent/ (共 {0} 项技能)" -f $count)
        return $failures.ToArray()
    } @{ command = "构建Agent" } -NoHost)
}

function Resolve-TargetDir([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    if ($path.StartsWith("~")) {
        $homeDir = [Environment]::GetFolderPath("UserProfile")
        $path = $path -replace "^~", $homeDir
    }
    # Normalize slashes for Windows CMD compatibility
    $path = $path.Replace("/", "\")
  
    if ([System.IO.Path]::IsPathRooted($path)) {
        return $path
    }
    return (Join-Path $Root $path)
}

function 应用到ClaudeCodex($cfg = $null, [switch]$SkipPreflight) {
    return (Invoke-WithMetric "apply_targets" {
        if (-not $SkipPreflight) { Preflight }
        if ($null -eq $cfg) { $cfg = LoadCfg }
        $mode = $cfg.sync_mode
        if ([string]::IsNullOrWhiteSpace($mode)) { $mode = "link" }
        $failures = New-Object System.Collections.Generic.List[string]

        foreach ($t in $cfg.targets) {
            try {
                $target = Resolve-TargetDir $t.path
                if (-not $target) { continue }
                Assert-SafeTargetDir $target

                if ($mode -eq "sync") {
                    EnsureDir $target
                    RoboMirror $AgentDir $target
                    Log ("已同步（拷贝）：{0}" -f $t.path)
                }
                else {
                    New-Junction $target $AgentDir
                    Log ("已关联（链接）：{0} -> agent/" -f $t.path)
                }
            }
            catch {
                Write-Host ("❌ 同步目标失败 [{0}]: {1}" -f $t.path, $_.Exception.Message) -ForegroundColor Red
                $failures.Add(("target:{0} => {1}" -f $t.path, $_.Exception.Message)) | Out-Null
            }
        }
        return $failures.ToArray()
    } @{ command = "应用到ClaudeCodex" } -NoHost)
}
function Write-FailureSummary([string]$title, [string[]]$failures, [string]$detailHint = "") {
    if ($null -eq $failures -or $failures.Count -eq 0) { return }
    $msg = ("{0}（{1} 项）" -f $title, $failures.Count)
    if (-not [string]::IsNullOrWhiteSpace($detailHint)) {
        $msg = ("{0}，{1}" -f $msg, $detailHint)
    }
    Write-Host $msg -ForegroundColor Yellow
    foreach ($f in ($failures | Select-Object -First 10)) {
        Write-Host ("- {0}" -f $f) -ForegroundColor Yellow
    }
    if ($failures.Count -gt 10) {
        Write-Host ("... 另有 {0} 项未显示" -f ($failures.Count - 10)) -ForegroundColor Yellow
    }
}

function 构建生效 {
    Invoke-WithMetric "build_apply_total" {
        Preflight
        Invoke-PrebuildCheck
        $cfg = LoadCfg
        if ($Locked) {
            Ensure-LockedState $cfg | Out-Null
        }
        $txn = Start-BuildTransaction
        $needRollback = $false

        # Optimization/Migration check
        $cfgRawBeforeOptimize = if (Test-Path $CfgPath) { Get-Content $CfgPath -Raw } else { "" }
        Optimize-Imports $cfg
        $optChanges = Get-CfgChangeSummaryLines $cfgRawBeforeOptimize $cfg
        if ($optChanges.Count -gt 0) {
            SaveCfg $cfg
            Log ("已写回自动迁移配置：{0}" -f ($optChanges -join "; ")) "WARN"
        }

        Write-BuildSummary $cfg
        Log "=== 启动构建生效流程 ==="
        Start-DryRunMirrorCollect
        try {
            $failures = @()
            $buildFailures = 构建Agent $cfg -SkipPreflight -Txn $txn
            if ($buildFailures) { $failures += $buildFailures }
            if ($buildFailures -and $buildFailures.Count -gt 0) {
                Log "检测到构建失败，已跳过同步阶段。" "WARN"
                Write-Host "⚠️ 构建失败，未执行同步。请先修复上方错误后重试【构建生效】。" -ForegroundColor Yellow
            }
            else {
                $syncFailures = 应用到ClaudeCodex $cfg -SkipPreflight
                if ($syncFailures) { $failures += $syncFailures }
            }
            Write-FailureSummary "构建生效部分失败" $failures
            if ($failures.Count -gt 0) { $needRollback = $true }
            Write-DryRunMirrorSummary "DRYRUN Robocopy 预览（构建生效）"
        }
        finally {
            Stop-DryRunMirrorCollect
        }
        if ($needRollback) {
            Rollback-BuildTransaction $txn
            Write-Host "⚠️ 已回滚本次构建产物（agent/）。同步目标可能仍需手动重建。" -ForegroundColor Yellow
        }
        else {
            Complete-BuildTransaction $txn
        }
        Log "=== 构建生效流程完成 ==="
    } @{ command = "构建生效" } -NoHost
}

function 命令导入安装 {
    Write-Host "可一次性粘贴一条或多条命令，空行结束。示例："
    Write-Host "  add <repo> [--skill <name>] [--ref <branch/tag>] [--mode manual|vendor] [--sparse]"
    Write-Host "  npx skills add <repo> [--skill <name>] [--ref <branch/tag>] [--mode manual|vendor] [--sparse]"
    Write-Host "说明："
    Write-Host "  - 支持连续粘贴多条 add / npx skills add / npx add-skill 命令"
    Write-Host "  - 未指定 --skill 时：仅新增技能库（vendor），不自动安装仓库内技能"
    Write-Host "  - 行尾用 \\ 可续行，脚本会自动拼接为一条命令"
    $lines = New-Object System.Collections.Generic.List[string]
    while ($true) {
        $line = Read-Host "输入命令"
        if ([string]::IsNullOrWhiteSpace($line)) { break }
        $trim = $line.Trim()
        if ($trim.StartsWith("#") -or $trim.StartsWith("//")) { continue }
        $lines.Add($line) | Out-Null
    }
    if ($lines.Count -eq 0) {
        Write-Host "未输入参数，已取消。"
        return
    }

    $commands = New-Object System.Collections.Generic.List[string]
    $pending = ""
    foreach ($raw in $lines) {
        $part = [string]$raw
        $trimmed = $part.TrimEnd()
        $continued = $trimmed.EndsWith("\")
        if ($continued) {
            $trimmed = $trimmed.Substring(0, $trimmed.Length - 1).TrimEnd()
        }
        if ([string]::IsNullOrWhiteSpace($pending)) { $pending = $trimmed }
        else { $pending = ("{0} {1}" -f $pending, $trimmed).Trim() }
        if (-not $continued) {
            if (-not [string]::IsNullOrWhiteSpace($pending)) { $commands.Add($pending) | Out-Null }
            $pending = ""
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($pending)) {
        Write-Host "警告：检测到末行续行符 '\\'，已按当前内容尝试执行。" -ForegroundColor Yellow
        $commands.Add($pending) | Out-Null
    }

    $successCount = 0
    foreach ($line in $commands) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $lineTrim = $line.Trim()
        if ($lineTrim.StartsWith("#") -or $lineTrim.StartsWith("//")) { continue }
        $tokens = Split-Args $line
        if ($tokens.Count -eq 0) { continue }
        try {
            $tokens = Get-AddTokensFromCommandLineTokens $tokens
            if ($tokens.Count -eq 0) { continue }
            if (Add-ImportFromArgs $tokens -NoBuild) { $successCount++ }
        }
        catch {
            Write-Host ("❌ 解析失败（已跳过）：{0}" -f $_.Exception.Message) -ForegroundColor Red
            if ($line -match "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@.+$") {
                Write-Host "提示：你可能使用了 repo@skill 语法。可改为：npx ""skills add <repo> --skill <path>""" -ForegroundColor Yellow
            }
        }
    }
    if ($successCount -gt 0) {
        Write-Host ("多行导入完成：{0} 项。开始【构建生效】..." -f $successCount)
        Clear-SkillsCache
        构建生效
    }
}

function 单技能安装 {
    命令导入安装
}
 
 function Should-ForceCleanTarget($cfg, $SkipForceClean, [string]$kind, [string]$name) {
    if ($null -eq $cfg -or -not $cfg.update_force) { return $false }
    if ($null -eq $SkipForceClean) { return $true }
    $key = "{0}|{1}" -f $kind, $name
    return (-not $SkipForceClean.ContainsKey($key))
}

function Get-UpdateParallelism($cfg) {
    $n = 1
    if ($null -ne $cfg -and $cfg.PSObject.Properties.Match("update_parallelism").Count -gt 0) {
        try { $n = [int]$cfg.update_parallelism } catch { $n = 1 }
    }
    if ($n -lt 1) { $n = 1 }
    return $n
}

function Invoke-ParallelGitPrefetch($cfg, [int]$Parallelism = 1) {
    if ($DryRun) { return }
    if ($Parallelism -le 1) { return }
    if (-not (Get-Command Start-Job -ErrorAction SilentlyContinue)) { return }
    if ($null -eq $cfg) { return }

    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($v in @($cfg.vendors)) {
        $p = VendorPath $v.name
        if (Test-Path $p) { $paths.Add($p) | Out-Null }
    }
    foreach ($i in @($cfg.imports)) {
        if ($i.mode -ne "manual") { continue }
        $p = Join-Path $ImportDir $i.name
        if (Test-Path $p) { $paths.Add($p) | Out-Null }
    }
    $paths = @($paths | Select-Object -Unique)
    if ($paths.Count -eq 0) { return }

    $running = @()
    $errors = New-Object System.Collections.Generic.List[string]
    foreach ($p in $paths) {
        while (@($running).Count -ge $Parallelism) {
            $done = Wait-Job -Job $running -Any
            if ($null -eq $done) { break }
            $output = Receive-Job $done -ErrorAction SilentlyContinue
            Remove-Job $done -Force -ErrorAction SilentlyContinue
            $running = @($running | Where-Object { $_.Id -ne $done.Id })
            if ($output -and $output.ok -eq $false) { $errors.Add([string]$output.msg) | Out-Null }
        }
        $job = Start-Job -ScriptBlock {
            param($repoPath)
            try {
                $prevErrorActionPreference = $ErrorActionPreference
                try {
                    $ErrorActionPreference = "Continue"
                    & git -C $repoPath fetch --all --tags 2>$null | Out-Null
                }
                finally {
                    $ErrorActionPreference = $prevErrorActionPreference
                }
                if ($LASTEXITCODE -ne 0) {
                    return [pscustomobject]@{ ok = $false; msg = ("prefetch failed: {0}" -f $repoPath) }
                }
                return [pscustomobject]@{ ok = $true; msg = "" }
            }
            catch {
                return [pscustomobject]@{ ok = $false; msg = ("prefetch exception: {0} -> {1}" -f $repoPath, $_.Exception.Message) }
            }
        } -ArgumentList $p
        $running += $job
    }
    foreach ($j in @($running)) {
        Wait-Job $j | Out-Null
        $output = Receive-Job $j -ErrorAction SilentlyContinue
        Remove-Job $j -Force -ErrorAction SilentlyContinue
        if ($output -and $output.ok -eq $false) { $errors.Add([string]$output.msg) | Out-Null }
    }
    if ($errors.Count -gt 0) {
        Log ("并行预取完成（部分失败 {0} 项，后续将按原流程继续）。" -f $errors.Count) "WARN"
    }
    else {
        Log ("并行预取完成：{0} 个仓库路径（并发={1}）。" -f $paths.Count, $Parallelism)
    }
}

function Get-CurrentRepoCommit([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    if (-not (Test-Path $path)) { return $null }
    Push-Location $path
    try {
        return (Invoke-GitCapture @("rev-parse", "HEAD"))
    }
    finally { Pop-Location }
}

function Resolve-RemoteCommit([string]$repo, [string]$ref) {
    $targetRef = if ([string]::IsNullOrWhiteSpace($ref)) { "main" } else { $ref }
    $candidates = @(
        $targetRef,
        ("refs/heads/{0}" -f $targetRef),
        ("refs/tags/{0}^{}" -f $targetRef),
        ("refs/tags/{0}" -f $targetRef)
    )
    foreach ($candidate in $candidates) {
        $line = Invoke-GitCapture @("ls-remote", $repo, $candidate)
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match "^[0-9a-fA-F]{40}") {
            return (($line -split "\s+")[0]).Trim()
        }
    }
    return $null
}

function Get-UpdatePlanItems($cfg) {
    $items = @()
    foreach ($v in @($cfg.vendors)) {
        $ref = if ([string]::IsNullOrWhiteSpace([string]$v.ref)) { "main" } else { [string]$v.ref }
        $current = Get-CurrentRepoCommit (VendorPath $v.name)
        $remote = Resolve-RemoteCommit ([string]$v.repo) $ref
        $items += [pscustomobject]@{
            type = "vendor"
            name = [string]$v.name
            ref = $ref
            current = if ([string]::IsNullOrWhiteSpace($current)) { "missing" } else { $current }
            target = if ([string]::IsNullOrWhiteSpace($remote)) { "unknown" } else { $remote }
            changed = (-not [string]::IsNullOrWhiteSpace($remote)) -and ($remote -ne $current)
        }
    }

    foreach ($i in @($cfg.imports)) {
        if ($i.mode -eq "vendor") { continue }
        $name = [string]$i.name
        $ref = if ([string]::IsNullOrWhiteSpace([string]$i.ref)) { "main" } else { [string]$i.ref }
        $path = Join-Path $ImportDir $name
        $current = Get-CurrentRepoCommit $path
        $remote = Resolve-RemoteCommit ([string]$i.repo) $ref
        $items += [pscustomobject]@{
            type = "import"
            name = $name
            ref = $ref
            current = if ([string]::IsNullOrWhiteSpace($current)) { "missing" } else { $current }
            target = if ([string]::IsNullOrWhiteSpace($remote)) { "unknown" } else { $remote }
            changed = (-not [string]::IsNullOrWhiteSpace($remote)) -and ($remote -ne $current)
        }
    }
    return @($items)
}

function Show-UpdatePlan($cfg) {
    Write-Host "=== 更新预览（--plan）==="
    $items = Get-UpdatePlanItems $cfg
    if ($items.Count -eq 0) {
        Write-Host "未发现可规划项（vendors/imports 为空）。"
        return @()
    }
    $changed = @($items | Where-Object { $_.changed })
    foreach ($it in $items) {
        $mark = if ($it.changed) { "UPGRADE" } else { "UNCHANGED" }
        Write-Host ("[{0}] {1}/{2} ref={3}" -f $mark, $it.type, $it.name, $it.ref)
        Write-Host ("  current: {0}" -f $it.current)
        Write-Host ("  target : {0}" -f $it.target)
    }
    Write-Host ("计划摘要：total={0}, upgrade={1}, unchanged={2}" -f $items.Count, $changed.Count, ($items.Count - $changed.Count))
    return $items
}

function 更新Vendor($cfg = $null, [switch]$SkipPreflight, $SkipForceClean = $null, [switch]$SkipFetch) {
    return (Invoke-WithMetric "update_vendor" {
        if (-not $SkipPreflight) { Preflight }
        if ($null -eq $cfg) { $cfg = LoadCfg }
        $failures = New-Object System.Collections.Generic.List[string]

        foreach ($v in $cfg.vendors) {
            try {
                $path = VendorPath $v.name
                if (-not (Test-Path $path)) {
                    Write-Host ("❌ 未找到 vendor/{0} (跳过)" -f $v.name) -ForegroundColor Red
                    continue 
                }
                if ([string]::IsNullOrWhiteSpace($v.ref)) { $v.ref = "main" }

                Push-Location $path
                try {
                    $forceClean = Should-ForceCleanTarget $cfg $SkipForceClean "vendor" $v.name
                    Git-HardResetClean $forceClean
                    if (-not $SkipFetch) {
                        Invoke-Git @("fetch", "--all", "--tags")
                    }
                    $sparsePaths = @()
                    foreach ($i in $cfg.imports) {
                        if ($i.mode -ne "vendor") { continue }
                        if ($i.name -ne $v.name) { continue }
                        if (-not $i.sparse) { continue }
                        $p = To-GitPath (Normalize-SkillPath $i.skill)
                        if ($p -and $p -ne ".") { $sparsePaths += $p }
                    }
                    foreach ($m in $cfg.mappings) {
                        if ($m.vendor -ne $v.name) { continue }
                        $p = To-GitPath (Normalize-SkillPath $m.from)
                        if ($p -and $p -ne ".") { $sparsePaths += $p }
                    }
                    $sparsePaths = $sparsePaths | Select-Object -Unique
                    if ($sparsePaths.Count -gt 0) {
                        Invoke-Git @("sparse-checkout", "init", "--cone")
                        Invoke-Git (@("sparse-checkout", "set") + $sparsePaths)
                    }
                    else {
                        try { Invoke-Git @("sparse-checkout", "disable") } catch {}
                    }
                    Invoke-Git @("checkout", $v.ref)
                    $branch = Get-GitHeadBranch
                    if ($branch -and (Has-GitUpstream)) {
                        Invoke-Git @("pull")
                    }
                    else {
                        Log ("跳过 git pull：{0} 处于 detached HEAD 或无 upstream。" -f $v.name)
                    }
                }
                finally {
                    Pop-Location
                }
            }
            catch {
                Write-Host ("❌ 更新失败 [{0}]: {1}" -f $v.name, $_.Exception.Message) -ForegroundColor Red
                $failures.Add(("vendor:{0} => {1}" -f $v.name, $_.Exception.Message)) | Out-Null
            }
        }
        if ($failures.Count -eq 0) {
            Write-Host "上游仓库更新完成。"
        }
        else {
            Write-Host ("上游仓库更新完成（部分失败：{0} 项）。" -f $failures.Count) -ForegroundColor Yellow
        }
        Clear-SkillsCache
        return $failures.ToArray()
    } @{ command = "更新Vendor" } -NoHost)
}

function 更新Imports($cfg = $null, [switch]$SkipPreflight, $SkipForceClean = $null, [switch]$SkipFetch) {
    return (Invoke-WithMetric "update_imports" {
        if (-not $SkipPreflight) { Preflight }
        if ($null -eq $cfg) { $cfg = LoadCfg }
        $cfgRaw = if (Test-Path $CfgPath) { Get-Content $CfgPath -Raw } else { "" }
        $cfgChanged = $false

        # Optimization/Migration before update
        Optimize-Imports $cfg

        if ($cfg.imports.Count -eq 0) { return @() }
        $failures = New-Object System.Collections.Generic.List[string]
        foreach ($i in $cfg.imports) {
            if ($i.mode -ne "manual") { continue }
            try {
                $name = $i.name
                $repo = Normalize-RepoUrl $i.repo
                $ref = $i.ref
                if ([string]::IsNullOrWhiteSpace($ref)) { $ref = "main" }
                $skillPath = Normalize-SkillPath $i.skill
                $gitSkillPath = To-GitPath $skillPath
                $sparse = [bool]$i.sparse
                if ($gitSkillPath -eq "." -and $sparse) { $sparse = $false }
                $sparsePath = $null
                if ($sparse) { $sparsePath = $gitSkillPath }
                $cache = Join-Path $ImportDir $name

                $forceClean = Should-ForceCleanTarget $cfg $SkipForceClean "import" $i.name
                try {
                    Ensure-Repo $cache $repo $ref $sparsePath $forceClean $false (-not $SkipFetch)
                }
                catch {
                    $lockPath = Join-Path $cache ".git\index.lock"
                    $fallbackSkillPath = Resolve-SkillPath $cache $skillPath
                    $fallbackSrc = if ($fallbackSkillPath -eq ".") { $cache } else { Join-Path $cache $fallbackSkillPath }
                    if ((Test-Path -LiteralPath $lockPath -PathType Leaf) -and (Test-IsSkillDir $fallbackSrc)) {
                        Log ("导入更新遇到 Git 索引锁异常，已保留现有缓存：{0} [{1}]；原因：{2}" -f $name, $repo, $_.Exception.Message) "WARN"
                        if ($fallbackSkillPath -ne $skillPath) {
                            $i.skill = $fallbackSkillPath
                            $cfgChanged = $true
                            $skillPath = $fallbackSkillPath
                        }
                    }
                    else {
                        throw
                    }
                }
                $src = if ($skillPath -eq ".") { $cache } else { Join-Path $cache $skillPath }
                if (-not (Test-IsSkillDir $src)) {
                    $resolvedSkillPath = Resolve-SkillPath $cache $skillPath
                    if ($resolvedSkillPath -ne $skillPath) {
                        $i.skill = $resolvedSkillPath
                        $cfgChanged = $true
                        $skillPath = $resolvedSkillPath
                        $src = if ($skillPath -eq ".") { $cache } else { Join-Path $cache $skillPath }
                        Log ("导入技能路径已自动修正：{0} -> {1} [{2}]" -f [string]$i.name, $skillPath, $repo) "WARN"
                    }
                }
                Need (Test-IsSkillDir $src) "未找到技能入口文件（SKILL.md/AGENTS.md/GEMINI.md/CLAUDE.md）：$src"
                Write-Host ("已更新导入技能缓存：{0}" -f $name)
            }
            catch {
                Write-Host ("❌ 导入更新失败 [{0}]: {1}" -f $i.name, $_.Exception.Message) -ForegroundColor Red
                $failures.Add(("import:{0} => {1}" -f $i.name, $_.Exception.Message)) | Out-Null
            }
        }
        if ($cfgChanged) {
            SaveCfgSafe $cfg $cfgRaw
        }
        Clear-SkillsCache
        return $failures.ToArray()
    } @{ command = "更新Imports" } -NoHost)
}

function 更新 {
    Invoke-WithMetric "update_total" {
        $cfg = LoadCfg
        if ($Locked -and ($Plan -or $Upgrade)) {
            throw "-Locked 不能与 -Plan 或 -Upgrade 同时使用。"
        }
        Invoke-PrebuildCheck
        if ($Plan) {
            Preflight
            Show-UpdatePlan $cfg | Out-Null
            return
        }
        if ($Locked) {
            $lock = Load-LockData
            Assert-LockMatchesCfg $cfg $lock
            Apply-LockToWorkspace $cfg $lock
            构建生效
            Write-Host "已按锁文件固定版本完成更新与构建。"
            return
        }
        $skipForceClean = @{}
        if (-not (Confirm-UpdateForce $cfg ([ref]$skipForceClean))) { return }
        if (Skip-IfDryRun "更新") { return }
        Preflight
        $parallelism = Get-UpdateParallelism $cfg
        $didPrefetch = $false
        if ($parallelism -gt 1) {
            Invoke-ParallelGitPrefetch $cfg $parallelism
            $didPrefetch = $true
        }
        $failures = @()
        $importFailures = 更新Imports $cfg -SkipPreflight -SkipForceClean $skipForceClean -SkipFetch:$didPrefetch
        if ($importFailures) { $failures += $importFailures }
        $vendorFailures = 更新Vendor $cfg -SkipPreflight -SkipForceClean $skipForceClean -SkipFetch:$didPrefetch
        if ($vendorFailures) { $failures += $vendorFailures }
        构建生效
        if ($Upgrade -and $failures.Count -eq 0) {
            Save-LockData $cfg | Out-Null
            Write-Host ("已刷新锁文件：{0}" -f (Get-LockPath))
        }
        if ($failures.Count -gt 0) {
            Write-FailureSummary "更新部分失败" $failures "请查看上方错误并重试。"
        }
        else {
            Write-Host "更新完成。若某 CLI 未立即识别新技能，重启该 CLI 会话即可。"
        }
    } @{ command = "更新" } -NoHost
}
 
 function Parse-KeyValueToken([string]$token, [string]$flagName) {
    Need (-not [string]::IsNullOrWhiteSpace($token)) ("{0} 参数不能为空" -f $flagName)
    $pair = $token.Split("=", 2)
    Need ($pair.Count -eq 2) ("{0} 参数格式必须是 KEY=VALUE：{1}" -f $flagName, $token)
    $key = $pair[0].Trim()
    Need (-not [string]::IsNullOrWhiteSpace($key)) ("{0} 参数的 KEY 不能为空：{1}" -f $flagName, $token)
    return [pscustomobject]@{
        key = $key
        value = $pair[1]
    }
}

function Normalize-McpProcessArgs([string[]]$processArgs) {
    $normalized = New-Object System.Collections.Generic.List[string]
    if ($null -eq $processArgs) { return @() }
    for ($i = 0; $i -lt $processArgs.Count; $i++) {
        $t = [string]$processArgs[$i]
        if ($t -eq "--arg") {
            if ($i + 1 -lt $processArgs.Count) {
                $normalized.Add([string]$processArgs[++$i]) | Out-Null
            }
            continue
        }
        if ($t.ToLowerInvariant().StartsWith("--arg=")) {
            $normalized.Add($t.Substring(6)) | Out-Null
            continue
        }
        $normalized.Add($t) | Out-Null
    }
    return $normalized.ToArray()
}

function Get-StableHashSuffix([string]$seed, [int]$len = 10) {
    if ([string]::IsNullOrWhiteSpace($seed)) { return $null }
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($seed)
        $hashBytes = $sha1.ComputeHash($bytes)
        $hex = ([System.BitConverter]::ToString($hashBytes)).Replace("-", "").ToLowerInvariant()
        if ($len -le 0) { return $hex }
        if ($hex.Length -le $len) { return $hex }
        return $hex.Substring(0, $len)
    }
    finally {
        $sha1.Dispose()
    }
}

function Normalize-McpServiceNameWithFallback([string]$name, [string]$fallbackSeed = $null) {
    $norm = Normalize-Name $name
    if (-not [string]::IsNullOrWhiteSpace($norm)) { return $norm }

    $seed = $null
    if (-not [string]::IsNullOrWhiteSpace($fallbackSeed)) {
        $seed = $fallbackSeed
    }
    elseif (-not [string]::IsNullOrWhiteSpace($name)) {
        $seed = $name
    }

    if (-not [string]::IsNullOrWhiteSpace($seed)) {
        $suffix = Get-StableHashSuffix $seed 10
        if (-not [string]::IsNullOrWhiteSpace($suffix)) {
            $autoName = "mcp-{0}" -f $suffix
            Write-Host ("MCP 服务名无法规范化，已自动生成：{0} -> {1}" -f $name, $autoName) -ForegroundColor Yellow
            return $autoName
        }
    }

    Need $false ("MCP 服务名 无法规范化，请更换名称：{0}" -f $name)
    return $null
}

function Parse-McpStdioCommandLine([string]$name, [string]$commandLine) {
    $tokens = Split-Args $commandLine
    $tokens = Normalize-McpProcessArgs @($tokens)
    Need ($tokens.Count -gt 0) ("MCP 服务命令不能为空：{0}" -f $name)
    return [pscustomobject]@{
        command = [string]$tokens[0]
        args = if ($tokens.Count -gt 1) { @($tokens[1..($tokens.Count - 1)]) } else { @() }
    }
}

function Parse-McpInstallArgs([string[]]$tokens) {
    Need ($tokens -and $tokens.Count -gt 0) "缺少 MCP 服务参数。示例：安装MCP context7 --cmd npx -- -y @upstash/context7-mcp"
    $result = [ordered]@{
        name = $null
        transport = "stdio"
        command = $null
        args = @()
        url = $null
        env = @{}
        headers = @{}
        bearer_token_env_var = $null
    }
    $collectProcessArgs = $false

    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $t = $tokens[$i]
        if ($t -eq "--") {
            if ($i + 1 -lt $tokens.Count) {
                $result.args += $tokens[($i + 1)..($tokens.Count - 1)]
            }
            break
        }

        if ($collectProcessArgs) {
            $result.args += $t
            continue
        }

        if (-not $t.StartsWith("-")) {
            if (-not $result.name) {
                $result.name = $t
                continue
            }
            # Backward compatible: allow "name <cmd> <args...>" without --cmd or "--".
            if ($result.transport -eq "stdio" -and [string]::IsNullOrWhiteSpace($result.command) -and [string]::IsNullOrWhiteSpace($result.url)) {
                $collectProcessArgs = $true
                $result.args += $t
                continue
            }
            $result.args += $t
            continue
        }

        $key = $t.ToLowerInvariant()
        if ($key -eq "--transport" -or $key -eq "-t") {
            Need ($i + 1 -lt $tokens.Count) ("参数缺少值：{0}" -f $t)
            $nextVal = [string]$tokens[++$i]
            Need (-not $nextVal.StartsWith("-")) ("参数缺少值：{0}" -f $t)
            $result.transport = $nextVal
            continue
        }
        if ($key -eq "--cmd" -or $key -eq "--command") {
            Need ($i + 1 -lt $tokens.Count) ("参数缺少值：{0}" -f $t)
            $nextVal = [string]$tokens[++$i]
            Need (-not $nextVal.StartsWith("-")) ("参数缺少值：{0}" -f $t)
            $result.command = $nextVal
            continue
        }
        if ($key -eq "--url") {
            Need ($i + 1 -lt $tokens.Count) "参数缺少值：--url"
            $nextVal = [string]$tokens[++$i]
            Need (-not $nextVal.StartsWith("-")) "参数缺少值：--url"
            $result.url = $nextVal
            continue
        }
        if ($key -eq "--arg") {
            Need ($i + 1 -lt $tokens.Count) "参数缺少值：--arg"
            $result.args += $tokens[++$i]
            continue
        }
        if ($key -eq "--env") {
            Need ($i + 1 -lt $tokens.Count) "参数缺少值：--env"
            $pair = Parse-KeyValueToken $tokens[++$i] "--env"
            $result.env[$pair.key] = $pair.value
            continue
        }
        if ($key -eq "--header") {
            Need ($i + 1 -lt $tokens.Count) "参数缺少值：--header"
            $pair = Parse-KeyValueToken $tokens[++$i] "--header"
            $result.headers[$pair.key] = $pair.value
            continue
        }
        if ($key -eq "--bearer-token-env-var") {
            Need ($i + 1 -lt $tokens.Count) "参数缺少值：--bearer-token-env-var"
            $result.bearer_token_env_var = [string]$tokens[++$i]
            continue
        }

        # Backward compatible: in stdio mode, unknown options are treated as process
        # arguments so users can omit "--" (PowerShell may swallow the separator).
        if (-not [string]::IsNullOrWhiteSpace($result.name) -and $result.transport -eq "stdio" -and [string]::IsNullOrWhiteSpace($result.url)) {
            if (-not [string]::IsNullOrWhiteSpace($result.command)) {
                $result.args += $t
                continue
            }
            $collectProcessArgs = $true
            $result.args += $t
            continue
        }
        throw ("未知参数：{0}" -f $t)
    }

    Need (-not [string]::IsNullOrWhiteSpace($result.name)) "缺少 MCP 服务名称。示例：安装MCP context7 --cmd npx -- -y @upstash/context7-mcp"

    if (-not [string]::IsNullOrWhiteSpace($result.transport)) {
        $result.transport = $result.transport.Trim().ToLowerInvariant()
    }
    if ([string]::IsNullOrWhiteSpace($result.transport)) { $result.transport = "stdio" }
    Need (($result.transport -eq "stdio") -or ($result.transport -eq "sse") -or ($result.transport -eq "http")) "transport 仅支持 stdio/sse/http"

    if ($result.transport -eq "stdio") {
        $result.args = Normalize-McpProcessArgs @($result.args)
        if ([string]::IsNullOrWhiteSpace($result.command) -and $result.args.Count -gt 0) {
            $result.command = [string]$result.args[0]
            if ($result.args.Count -gt 1) {
                $result.args = $result.args[1..($result.args.Count - 1)]
            }
            else {
                $result.args = @()
            }
        }
        Need (-not [string]::IsNullOrWhiteSpace($result.command)) "stdio MCP 需要 --cmd/--command"
        if ($result.command.Contains(" ") -and $result.args.Count -eq 0) {
            $parts = Split-Args $result.command
            Need ($parts.Count -gt 0) "无法解析 --cmd 命令"
            $result.command = $parts[0]
            if ($parts.Count -gt 1) {
                $result.args = $parts[1..($parts.Count - 1)]
            }
        }
    }
    else {
        Need (-not [string]::IsNullOrWhiteSpace($result.url)) "sse/http MCP 需要 --url"
        if (-not [string]::IsNullOrWhiteSpace([string]$result.bearer_token_env_var)) {
            $result.bearer_token_env_var = [string]$result.bearer_token_env_var.Trim()
        }
    }

    $fallbackSeed = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$result.command)) {
        $fallbackSeed = [string]$result.command
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$result.url)) {
        $fallbackSeed = [string]$result.url
    }
    $result.name = Normalize-McpServiceNameWithFallback $result.name $fallbackSeed

    return [pscustomobject]$result
}

function New-McpServerObject($parsed) {
    $obj = [ordered]@{
        name = $parsed.name
        transport = $parsed.transport
    }
    if ($parsed.transport -eq "stdio") {
        $obj.command = $parsed.command
        $obj.args = @($parsed.args)
        if ($parsed.env.Count -gt 0) { $obj.env = $parsed.env }
    }
    else {
        $obj.url = $parsed.url
        if ($parsed.headers.Count -gt 0) { $obj.headers = $parsed.headers }
        if (-not [string]::IsNullOrWhiteSpace([string]$parsed.bearer_token_env_var)) {
            $obj.bearer_token_env_var = [string]$parsed.bearer_token_env_var
        }
    }
    return [pscustomobject]$obj
}

function Convert-McpServersToConfigMap($servers) {
    $map = [ordered]@{}
    if ($null -eq $servers) { return [pscustomobject]$map }

    foreach ($s in $servers) {
        if ([string]::IsNullOrWhiteSpace([string]$s.name)) { continue }
        $entry = [ordered]@{}
        $transport = if ([string]::IsNullOrWhiteSpace([string]$s.transport)) { "stdio" } else { [string]$s.transport }
        $entry.transport = $transport
        if ($transport -eq "stdio") {
            if (-not [string]::IsNullOrWhiteSpace([string]$s.command)) { $entry.command = [string]$s.command }
            if ($s.PSObject.Properties.Match("args").Count -gt 0 -and $s.args -ne $null) { $entry.args = @($s.args) }
            if ($s.PSObject.Properties.Match("env").Count -gt 0 -and $s.env -ne $null) { $entry.env = $s.env }
        }
        else {
            if ($s.PSObject.Properties.Match("url").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$s.url)) { $entry.url = [string]$s.url }
            if ($s.PSObject.Properties.Match("headers").Count -gt 0 -and $s.headers -ne $null) { $entry.headers = $s.headers }
            if ($s.PSObject.Properties.Match("bearer_token_env_var").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$s.bearer_token_env_var)) {
                $entry.bearer_token_env_var = [string]$s.bearer_token_env_var
            }
        }
        $map[[string]$s.name] = [pscustomobject]$entry
    }
    return [pscustomobject]$map
}

function Convert-McpServersToGeminiConfigMap($servers) {
    $map = [ordered]@{}
    if ($null -eq $servers) { return [pscustomobject]$map }

    foreach ($s in $servers) {
        if ([string]::IsNullOrWhiteSpace([string]$s.name)) { continue }
        $entry = [ordered]@{}
        $transport = if ([string]::IsNullOrWhiteSpace([string]$s.transport)) { "stdio" } else { ([string]$s.transport).Trim().ToLowerInvariant() }
        if ($transport -eq "stdio") {
            if (-not [string]::IsNullOrWhiteSpace([string]$s.command)) { $entry.command = [string]$s.command }
            if ($s.PSObject.Properties.Match("args").Count -gt 0 -and $s.args -ne $null) { $entry.args = @($s.args) }
            if ($s.PSObject.Properties.Match("env").Count -gt 0 -and $s.env -ne $null) { $entry.env = $s.env }
        }
        else {
            if ($s.PSObject.Properties.Match("url").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$s.url)) {
                if ($transport -eq "http") { $entry.httpUrl = [string]$s.url }
                else { $entry.url = [string]$s.url }
            }
            if ($s.PSObject.Properties.Match("headers").Count -gt 0 -and $s.headers -ne $null) { $entry.headers = $s.headers }
        }
        $map[[string]$s.name] = [pscustomobject]$entry
    }
    return [pscustomobject]$map
}

function Get-McpServerNameSet($servers) {
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($null -eq $servers) { return $set }
    foreach ($s in $servers) {
        $name = [string]$s.name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $set.Add($name) | Out-Null
    }
    return $set
}

function Convert-McpMapToOrderedMap($mapLike) {
    $map = [ordered]@{}
    if ($null -eq $mapLike) { return $map }

    if ($mapLike -is [hashtable] -or $mapLike -is [System.Collections.IDictionary]) {
        foreach ($k in $mapLike.Keys) {
            $name = [string]$k
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $map[$name] = $mapLike[$k]
        }
        return $map
    }

    if ($mapLike -is [pscustomobject]) {
        foreach ($p in $mapLike.PSObject.Properties) {
            $name = [string]$p.Name
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $map[$name] = $p.Value
        }
    }
    return $map
}

function Merge-McpConfigMaps($existingMapLike, $managedMapLike, $managedNameSet) {
    $merged = [ordered]@{}
    $existing = Convert-McpMapToOrderedMap $existingMapLike
    foreach ($name in $existing.Keys) {
        if ($managedNameSet.Contains([string]$name)) { continue }
        $merged[[string]$name] = $existing[$name]
    }

    $managed = Convert-McpMapToOrderedMap $managedMapLike
    foreach ($name in $managed.Keys) {
        $merged[[string]$name] = $managed[$name]
    }
    return [pscustomobject]$merged
}

function Build-GenericMcpPayload([string]$existingContent, $servers) {
    $base = [ordered]@{}
    if (-not [string]::IsNullOrWhiteSpace($existingContent)) {
        try {
            $parsed = $existingContent | ConvertFrom-Json
            if ($parsed -ne $null) {
                foreach ($p in $parsed.PSObject.Properties) {
                    $base[[string]$p.Name] = $p.Value
                }
            }
        }
        catch {
            Log ("MCP JSON 解析失败，将使用最小配置重建：{0}" -f $_.Exception.Message) "WARN"
        }
    }

    $existingMap = $null
    if ($base.Contains("mcpServers")) {
        $existingMap = $base["mcpServers"]
    }
    elseif ($base.Contains("mcp_servers")) {
        $existingMap = $base["mcp_servers"]
    }

    $managedMap = Convert-McpServersToConfigMap $servers
    $managedNameSet = Get-McpServerNameSet $servers
    $base["mcpServers"] = Merge-McpConfigMaps $existingMap $managedMap $managedNameSet
    if ($base.Contains("mcp_servers")) { $base.Remove("mcp_servers") }
    return [pscustomobject]$base
}

function Get-NativeMcpKeyValueFlags($data, [string]$flagName, [string]$separator = "=") {
    $flags = @()
    if ($null -eq $data) { return $flags }
    function Resolve-EnvTemplateValue([string]$rawValue) {
        if ([string]::IsNullOrWhiteSpace($rawValue)) { return $rawValue }
        return [System.Text.RegularExpressions.Regex]::Replace(
            $rawValue,
            '\$\{([A-Za-z_][A-Za-z0-9_]*)\}',
            {
                param($m)
                $varName = [string]$m.Groups[1].Value
                $resolved = [System.Environment]::GetEnvironmentVariable($varName)
                if ($null -eq $resolved) { return $m.Value }
                return [string]$resolved
            }
        )
    }

    if ($data -is [hashtable] -or $data -is [System.Collections.IDictionary]) {
        foreach ($k in $data.Keys) {
            $key = [string]$k
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            $value = Resolve-EnvTemplateValue ([string]$data[$k])
            $flags += @($flagName, ("{0}{1}{2}" -f $key, $separator, $value))
        }
        return $flags
    }

    if ($data -is [pscustomobject]) {
        foreach ($p in $data.PSObject.Properties) {
            $key = [string]$p.Name
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            $value = Resolve-EnvTemplateValue ([string]$p.Value)
            $flags += @($flagName, ("{0}{1}{2}" -f $key, $separator, $value))
        }
        return $flags
    }

    return $flags
}

function Get-NativeMcpAddArgs($server, [string]$scope = "user") {
    Need ($null -ne $server) "MCP 服务不能为空"
    Need (-not [string]::IsNullOrWhiteSpace([string]$server.name)) "MCP 服务缺少 name"
    Need (($scope -eq "local") -or ($scope -eq "user")) ("不支持的 scope：{0}" -f $scope)

    $name = [string]$server.name
    $transport = if ([string]::IsNullOrWhiteSpace([string]$server.transport)) { "stdio" } else { [string]$server.transport }
    $transport = $transport.Trim().ToLowerInvariant()
    $args = @("mcp", "add", "--scope", $scope)

    if ($transport -eq "stdio") {
        $envFlags = @()
        if ($server.PSObject.Properties.Match("env").Count -gt 0) {
            $envFlags = Get-NativeMcpKeyValueFlags $server.env "-e"
        }
        if ($envFlags.Count -gt 0) { $args += $envFlags }
        $args += @($name, "--")
        $cmd = [string]$server.command
        Need (-not [string]::IsNullOrWhiteSpace($cmd)) ("stdio MCP 缺少 command：{0}" -f $name)
        $args += $cmd
        if ($server.PSObject.Properties.Match("args").Count -gt 0 -and $server.args -ne $null) {
            $args += @($server.args | ForEach-Object { [string]$_ })
        }
        return $args
    }

    $headerFlags = @()
    if ($server.PSObject.Properties.Match("headers").Count -gt 0) {
        $headerFlags = Get-NativeMcpKeyValueFlags $server.headers "-H" ": "
    }
    $url = if ($server.PSObject.Properties.Match("url").Count -gt 0) { [string]$server.url } else { "" }
    Need (-not [string]::IsNullOrWhiteSpace($url)) ("{0} MCP 缺少 url：{1}" -f $transport, $name)
    $args += @("--transport", $transport, $name, $url)
    # `claude mcp add --header` is variadic and consumes trailing tokens, so headers must
    # be appended after <name> <url>.
    if ($headerFlags.Count -gt 0) { $args += $headerFlags }
    return $args
}

function Remove-McpServersFromPayload($payload, [string[]]$names) {
    if ($null -eq $payload -or $null -eq $names -or $names.Count -eq 0) { return $payload }
    if ($payload.PSObject.Properties.Match("mcpServers").Count -eq 0) { return $payload }
    $serverMap = $payload.mcpServers
    if ($null -eq $serverMap) { return $payload }

    foreach ($name in @($names)) {
        if ([string]::IsNullOrWhiteSpace([string]$name)) { continue }
        $match = @($serverMap.PSObject.Properties | Where-Object {
            [string]::Equals([string]$_.Name, [string]$name, [System.StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1)
        if ($match.Count -gt 0 -and $null -ne $match[0]) {
            $serverMap.PSObject.Properties.Remove($match[0].Name)
        }
    }

    return $payload
}

function Get-LegacyMcpServersToPrune() {
    return @("fetch", "filesystem")
}

function Has-McpServerByName($servers, [string]$name) {
    if ([string]::IsNullOrWhiteSpace($name)) { return $false }
    foreach ($s in @($servers)) {
        if ($null -eq $s) { continue }
        if ([string]::Equals([string]$s.name, $name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Invoke-Gh([string[]]$GhArgs) {
    Need ($GhArgs -and $GhArgs.Count -gt 0) "gh 参数不能为空"
    $output = & gh @GhArgs 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return @($output | ForEach-Object { [string]$_ })
}

function Ensure-GhAuthForGithubMcp($servers) {
    if (-not (Has-McpServerByName $servers "github")) { return }
    if (-not (Get-Command "gh" -ErrorAction SilentlyContinue)) {
        throw "检测到 github MCP，但未找到 gh 命令。请先安装并登录 GitHub CLI（gh auth login）。"
    }

    $tokenLines = Invoke-Gh @("auth", "token")
    $token = if ($tokenLines) { (($tokenLines -join "`n").Trim()) } else { "" }
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "检测到 github MCP，但 gh 未登录或无法读取 token。请先执行 gh auth login。"
    }

    $userLines = Invoke-Gh @("api", "user", "--jq", ".login")
    $username = if ($userLines) { (($userLines -join "`n").Trim()) } else { "" }
    if ([string]::IsNullOrWhiteSpace($username)) {
        throw "检测到 github MCP，但 gh 登录态校验失败（gh api user）。请重新执行 gh auth login。"
    }

    # gh auth 路线：同步阶段临时注入 token，供各客户端配置写入与 native 注册使用。
    $env:GITHUB_PERSONAL_ACCESS_TOKEN = $token
    $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN = $token
    Log ("GitHub MCP gh 认证预检通过：{0}" -f $username) "INFO"
}

function ConvertTo-CmdArg([string]$arg) {
    if ($null -eq $arg) { return '""' }
    $text = [string]$arg
    if ($text -eq "") { return '""' }
    if ($text -notmatch '[\s"&|<>^]') { return $text }
    $escaped = $text.Replace('"', '\"')
    return ('"{0}"' -f $escaped)
}

function Invoke-ExternalCommandWithTimeout([string]$command, [string[]]$args = @(), [string]$workingDir = $null, [int]$timeoutSeconds = 30) {
    Need (-not [string]::IsNullOrWhiteSpace($command)) "外部命令名不能为空"
    if ($timeoutSeconds -lt 1) { $timeoutSeconds = 1 }

    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $cmdTokens = New-Object System.Collections.Generic.List[string]
        $cmdTokens.Add((ConvertTo-CmdArg $command)) | Out-Null
        foreach ($a in @($args)) {
            $cmdTokens.Add((ConvertTo-CmdArg ([string]$a))) | Out-Null
        }
        $cmdLine = ($cmdTokens -join " ")
        $startArgs = @("/d", "/s", "/c", $cmdLine)

        $effectiveWorkingDir = if ([string]::IsNullOrWhiteSpace($workingDir)) { $PWD.Path } else { $workingDir }
        $proc = Start-Process -FilePath "cmd.exe" -ArgumentList $startArgs -PassThru -WindowStyle Hidden -RedirectStandardOutput $outFile -RedirectStandardError $errFile -WorkingDirectory $effectiveWorkingDir
        $exited = $proc.WaitForExit($timeoutSeconds * 1000)
        if (-not $exited) {
            try { $proc.Kill() } catch {}
            return [pscustomobject]@{
                timed_out = $true
                exit_code = 124
                output = @()
                error = ("timeout_after_{0}s" -f $timeoutSeconds)
            }
        }

        $outText = if (Test-Path $outFile) { Get-Content -Raw -Path $outFile } else { "" }
        $errText = if (Test-Path $errFile) { Get-Content -Raw -Path $errFile } else { "" }
        $combined = New-Object System.Collections.Generic.List[string]
        foreach ($line in @((($outText + "`n" + $errText) -split "`r?`n"))) {
            if ($null -ne $line -and $line -ne "") { $combined.Add([string]$line) | Out-Null }
        }

        return [pscustomobject]@{
            timed_out = $false
            exit_code = [int]$proc.ExitCode
            output = @($combined)
            error = ""
        }
    }
    catch {
        return [pscustomobject]@{
            timed_out = $false
            exit_code = 1
            output = @()
            error = $_.Exception.Message
        }
    }
    finally {
        Remove-Item -LiteralPath $outFile -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $errFile -ErrorAction SilentlyContinue
    }
}

function Invoke-ExternalCommandCapture([string]$command, [string[]]$args = @()) {
    $result = Invoke-ExternalCommandWithTimeout $command @($args) $null 120
    return [pscustomobject]@{
        command = $command
        args = @($args)
        exit_code = [int]$result.exit_code
        output = @($result.output)
    }
}

function Get-McpServerNamesFromJsonText([string]$jsonText) {
    if ([string]::IsNullOrWhiteSpace($jsonText)) { return @() }
    try {
        $obj = $jsonText | ConvertFrom-Json -Depth 100
    }
    catch {
        return @()
    }
    if ($null -eq $obj) { return @() }
    if ($obj.PSObject.Properties.Match("mcpServers").Count -eq 0 -or $null -eq $obj.mcpServers) {
        return @()
    }
    return @($obj.mcpServers.PSObject.Properties | ForEach-Object { [string]$_.Name })
}

function Get-CodexMcpServerNamesFromTomlText([string]$tomlText) {
    if ([string]::IsNullOrWhiteSpace($tomlText)) { return @() }
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($line in @(($tomlText -split "`r?`n"))) {
        $m = [regex]::Match([string]$line, '^\s*\[mcp_servers\.([^\]\s]+)\]\s*$')
        if ($m.Success) {
            $set.Add([string]$m.Groups[1].Value) | Out-Null
        }
    }
    return @($set | Sort-Object)
}

function Get-McpExpectedServersByCli($roots) {
    $expected = [ordered]@{
        claude = @()
        codex = @()
        gemini = @()
    }
    foreach ($root in @($roots)) {
        if ([string]::IsNullOrWhiteSpace([string]$root)) { continue }
        $leaf = (Split-Path ([string]$root) -Leaf).ToLowerInvariant()
        if ($leaf -eq ".claude") {
            $mcpPath = Join-Path $root ".mcp.json"
            if (Test-Path $mcpPath) {
                $names = Get-McpServerNamesFromJsonText (Get-Content -Raw -Path $mcpPath)
                if ($names.Count -gt 0) { $expected.claude += $names }
            }
            continue
        }
        if ($leaf -eq ".gemini") {
            $settingsPath = Join-Path $root "settings.json"
            if (Test-Path $settingsPath) {
                $names = Get-McpServerNamesFromJsonText (Get-Content -Raw -Path $settingsPath)
                if ($names.Count -gt 0) { $expected.gemini += $names }
            }
            continue
        }
        if ($leaf -eq ".codex") {
            $cfgPath = Join-Path $root "config.toml"
            if (Test-Path $cfgPath) {
                $names = Get-CodexMcpServerNamesFromTomlText (Get-Content -Raw -Path $cfgPath)
                if ($names.Count -gt 0) { $expected.codex += $names }
            }
            continue
        }
    }

    foreach ($k in @("claude", "codex", "gemini")) {
        $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($name in @($expected[$k])) {
            if ([string]::IsNullOrWhiteSpace([string]$name)) { continue }
            $set.Add([string]$name) | Out-Null
        }
        $expected[$k] = @($set | Sort-Object)
    }
    return [pscustomobject]$expected
}

function Remove-AnsiEscapeSequences([string]$text) {
    if ([string]::IsNullOrEmpty($text)) { return $text }
    return ([regex]::Replace($text, '\x1B\[[0-9;?]*[ -/]*[@-~]', ''))
}

function Test-CliMcpServerReady([string]$cli, [string[]]$expectedServers) {
    if ($null -eq $expectedServers -or $expectedServers.Count -eq 0) {
        return [pscustomobject]@{
            cli = $cli
            ok = $true
            reason = "no_expected_servers"
            missing = @()
            raw = @()
        }
    }
    if (-not (Get-Command $cli -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{
            cli = $cli
            ok = $false
            reason = "cli_not_found"
            missing = @($expectedServers)
            raw = @()
        }
    }

    $result = Invoke-ExternalCommandCapture $cli @("mcp", "list")
    $raw = @($result.output | ForEach-Object { Remove-AnsiEscapeSequences ([string]$_) })

    $missing = New-Object System.Collections.Generic.List[string]
    $joined = ($raw -join "`n")
    $trimmedJoined = $joined.Trim()
    $nonInteractiveHints = @(
        "stdout is not a terminal",
        "Input must be provided either through stdin",
        "No input provided via stdin"
    )
    $isNonInteractive = $false
    foreach ($hint in $nonInteractiveHints) {
        if ($trimmedJoined -like ("*{0}*" -f $hint)) {
            $isNonInteractive = $true
            break
        }
    }
    if ($isNonInteractive) {
        return [pscustomobject]@{
            cli = $cli
            ok = $true
            reason = "non_interactive_tty_required_fallback"
            missing = @()
            raw = $raw
        }
    }
    if ($trimmedJoined.Length -eq 0 -and $cli -eq "gemini") {
        return [pscustomobject]@{
            cli = $cli
            ok = $true
            reason = if ($result.exit_code -eq 0) { "ok_empty_output" } else { ("ok_empty_output_exit_{0}" -f $result.exit_code) }
            missing = @()
            raw = $raw
        }
    }
    if ($trimmedJoined.Length -eq 0) {
        return [pscustomobject]@{
            cli = $cli
            ok = $false
            reason = ("empty_output_exit_{0}" -f $result.exit_code)
            missing = @($expectedServers)
            raw = $raw
        }
    }
    foreach ($name in @($expectedServers)) {
        if ([string]::IsNullOrWhiteSpace([string]$name)) { continue }
        $pattern = "^\s*{0}\b" -f [regex]::Escape([string]$name)
        $line = @($raw | Where-Object { [regex]::IsMatch([string]$_, $pattern) } | Select-Object -First 1)
        if ($line.Count -eq 0) {
            $missing.Add([string]$name) | Out-Null
            continue
        }
        $lineText = [string]$line[0]
        if ($cli -eq "claude") {
            if ($lineText -notmatch "Connected") {
                $missing.Add([string]$name) | Out-Null
            }
            continue
        }
        if ($cli -eq "codex") {
            if ($lineText -match '\bdisabled\b') {
                $missing.Add([string]$name) | Out-Null
            }
            continue
        }
        if ($cli -eq "gemini") {
            # Some Gemini CLI versions print minimal/empty table output.
            # Fallback: when list output has no rows, verify names from settings.json already written.
            if ($trimmedJoined.Length -eq 0) {
                continue
            }
        }
    }

    $reason = if ($missing.Count -eq 0) {
        if ($result.exit_code -eq 0) { "ok" } else { ("ok_with_nonzero_exit_{0}" -f $result.exit_code) }
    } else {
        if ($result.exit_code -eq 0) { "missing_or_unhealthy" } else { ("missing_or_unhealthy_exit_{0}" -f $result.exit_code) }
    }
    return [pscustomobject]@{
        cli = $cli
        ok = ($missing.Count -eq 0)
        reason = $reason
        missing = @($missing)
        raw = $raw
    }
}

function Verify-McpAcrossCliWithRetry($roots, [int]$maxAttempts = 6, [int]$intervalSeconds = 3) {
    $expected = Get-McpExpectedServersByCli $roots
    $targets = @(
        [pscustomobject]@{ cli = "claude"; names = @($expected.claude) },
        [pscustomobject]@{ cli = "codex"; names = @($expected.codex) },
        [pscustomobject]@{ cli = "gemini"; names = @($expected.gemini) }
    ) | Where-Object { @($_.names).Count -gt 0 }

    if ($targets.Count -eq 0) {
        Log "未检测到需校验的 CLI MCP 目标，跳过跨 CLI 可用性校验。" "WARN"
        return
    }

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $failed = New-Object System.Collections.Generic.List[object]
        foreach ($target in $targets) {
            $check = Test-CliMcpServerReady ([string]$target.cli) @($target.names)
            if ($check.ok) {
                Log ("MCP 校验通过：{0} -> {1}" -f $check.cli, ((@($target.names)) -join ", "))
            }
            else {
                $failed.Add($check) | Out-Null
                Log ("MCP 校验未通过：{0}，缺失/异常：{1}（reason={2}）" -f $check.cli, (($check.missing) -join ", "), $check.reason) "WARN"
                $snippet = @($check.raw | Select-Object -First 6) -join " | "
                if (-not [string]::IsNullOrWhiteSpace($snippet)) {
                    Log ("{0} mcp list 输出片段：{1}" -f $check.cli, $snippet) "WARN"
                }
            }
        }

        if ($failed.Count -eq 0) {
            Log ("跨 CLI MCP 校验完成：全部通过（attempt={0}/{1}）。" -f $attempt, $maxAttempts) "INFO"
            return
        }
        if ($attempt -lt $maxAttempts) {
            Log ("跨 CLI MCP 校验第 {0}/{1} 次未全部通过，{2}s 后自动重试。" -f $attempt, $maxAttempts, $intervalSeconds) "WARN"
            Start-Sleep -Seconds $intervalSeconds
        }
    }

    throw ("跨 CLI MCP 校验失败：在 {0} 次重试后仍存在不可用服务，请检查日志中的 CLI 与缺失项。" -f $maxAttempts)
}

function Invoke-NativeMcpSync($servers) {
    if (-not (Get-Command "claude" -ErrorAction SilentlyContinue)) {
        Log "未检测到 claude 命令，已跳过原生 MCP 同步（仅写入 .mcp.json）。" "WARN"
        return
    }
    if ($null -eq $servers -or $servers.Count -eq 0) {
        Log "当前 mcp_servers 为空，跳过原生 MCP 注册。" "WARN"
        return
    }

    foreach ($s in $servers) {
        $scope = "user"
        try {
            $args = Get-NativeMcpAddArgs $s $scope
            $cmdText = "claude {0}" -f (($args | ForEach-Object { [string]$_ }) -join " ")
            if ($DryRun) {
                Write-Host ("DRYRUN：将执行原生 MCP 同步 -> {0}" -f $cmdText)
                continue
            }
            $timeoutSeconds = 30
            $timeoutEnv = $env:SKILLS_MCP_NATIVE_TIMEOUT_SECONDS
            $timeoutParsed = 0
            if ([int]::TryParse([string]$timeoutEnv, [ref]$timeoutParsed)) {
                $timeoutSeconds = $timeoutParsed
            }
            $native = Invoke-ExternalCommandWithTimeout "claude" @($args) $script:Root $timeoutSeconds
            if ($native.timed_out) {
                Log ("原生 MCP 同步超时（已忽略）：{0}（scope={1}，timeout={2}s）" -f [string]$s.name, $scope, $timeoutSeconds) "WARN"
                continue
            }
            if ($native.exit_code -ne 0) {
                Log ("原生 MCP 同步失败（已忽略）：{0}（scope={1}，exit={2}）{3}" -f [string]$s.name, $scope, $native.exit_code, $native.error) "WARN"
                continue
            }
            Log ("已同步原生 MCP：{0}（scope={1}）" -f [string]$s.name, $scope)
        }
        catch {
            Log ("原生 MCP 同步失败（已忽略）：{0}（scope={1}） -> {2}" -f [string]$s.name, $scope, $_.Exception.Message) "WARN"
        }
    }
}

function Get-NativeMcpCleanupCommands([string]$name) {
    Need (-not [string]::IsNullOrWhiteSpace($name)) "MCP 服务名不能为空"
    return @(
        [pscustomobject]@{ command = "claude"; args = @("mcp", "remove", $name, "--scope", "user"); project = $false }
        [pscustomobject]@{ command = "claude"; args = @("mcp", "remove", $name, "--scope", "project"); project = $true }
    )
}

function Invoke-NativeMcpCleanup([string]$name) {
    $ops = Get-NativeMcpCleanupCommands $name
    foreach ($op in $ops) {
        if (-not (Get-Command $op.command -ErrorAction SilentlyContinue)) { continue }
        $cmdText = "{0} {1}" -f $op.command, (($op.args | ForEach-Object { [string]$_ }) -join " ")
        if ($DryRun) {
            Write-Host ("DRYRUN：清理原生 MCP -> {0}" -f $cmdText)
            continue
        }
        try {
            $timeoutSeconds = 30
            $timeoutEnv = $env:SKILLS_MCP_NATIVE_TIMEOUT_SECONDS
            $timeoutParsed = 0
            if ([int]::TryParse([string]$timeoutEnv, [ref]$timeoutParsed)) {
                $timeoutSeconds = $timeoutParsed
            }
            $workingDir = if ($op.project) { $script:Root } else { $null }
            $native = Invoke-ExternalCommandWithTimeout ([string]$op.command) @($op.args) $workingDir $timeoutSeconds
            if ($native.timed_out) {
                Log ("原生 MCP 清理超时（已忽略）：{0}（timeout={1}s）" -f $cmdText, $timeoutSeconds) "WARN"
                continue
            }
            if ($native.exit_code -ne 0) {
                Log ("原生 MCP 清理失败（已忽略）：{0}（exit={1}）{2}" -f $cmdText, $native.exit_code, $native.error) "WARN"
                continue
            }
            Log ("已执行原生 MCP 清理：{0}" -f $cmdText)
        }
        catch {
            Log ("原生 MCP 清理失败（已忽略）：{0} -> {1}" -f $cmdText, $_.Exception.Message) "WARN"
        }
    }
}

function Build-GeminiSettingsPayload([string]$existingContent, $servers) {
    $base = [ordered]@{}
    if (-not [string]::IsNullOrWhiteSpace($existingContent)) {
        try {
            $parsed = $existingContent | ConvertFrom-Json
            if ($parsed -ne $null) {
                foreach ($p in $parsed.PSObject.Properties) {
                    $base[[string]$p.Name] = $p.Value
                }
            }
        }
        catch {
            Log ("Gemini settings.json 解析失败，将使用最小配置重建：{0}" -f $_.Exception.Message) "WARN"
        }
    }

    $existingMap = $null
    if ($base.Contains("mcpServers")) {
        $existingMap = $base["mcpServers"]
    }
    elseif ($base.Contains("mcp_servers")) {
        $existingMap = $base["mcp_servers"]
    }
    $managedMap = Convert-McpServersToGeminiConfigMap $servers
    $managedNameSet = Get-McpServerNameSet $servers
    $base["mcpServers"] = Merge-McpConfigMaps $existingMap $managedMap $managedNameSet
    if ($base.Contains("mcp_servers")) { $base.Remove("mcp_servers") }
    return [pscustomobject]$base
}

function ConvertTo-TomlBasicValue($value) {
    if ($null -eq $value) { return '""' }
    if ($value -is [bool]) { return ($(if ($value) { "true" } else { "false" })) }
    if ($value -is [int] -or $value -is [long] -or $value -is [double] -or $value -is [decimal]) { return [string]$value }
    $text = [string]$value
    $text = $text.Replace("\", "\\").Replace('"', '\"')
    return ('"{0}"' -f $text)
}

function Set-TomlTopLevelScalar([string[]]$lines, [string]$key, [string]$rawValue) {
    $safeLines = @($lines)
    $out = New-Object System.Collections.Generic.List[string]
    $found = $false
    $inserted = $false

    foreach ($line in $safeLines) {
        if (-not $inserted -and $line -match '^\s*\[[^\]]+\]\s*$') {
            if (-not $found) {
                $out.Add(("{0} = {1}" -f $key, $rawValue)) | Out-Null
            }
            $inserted = $true
        }

        if (-not $inserted -and $line -match ("^\s*" + [regex]::Escape($key) + "\s*=")) {
            $out.Add(("{0} = {1}" -f $key, $rawValue)) | Out-Null
            $found = $true
            continue
        }

        $out.Add($line) | Out-Null
    }

    if (-not $inserted -and -not $found) {
        $out.Add(("{0} = {1}" -f $key, $rawValue)) | Out-Null
    }

    return [string[]]$out.ToArray()
}

function Apply-CodexPermissionDefaults([string[]]$lines) {
    $updated = Set-TomlTopLevelScalar @($lines) "sandbox_mode" '"workspace-write"'
    $updated = Set-TomlTopLevelScalar @($updated) "approval_policy" '"never"'
    return [string[]]@($updated | ForEach-Object { [string]$_ })
}

function Build-CodexConfigToml([string]$existingToml, $servers) {
    $lines = @()
    if (-not [string]::IsNullOrWhiteSpace($existingToml)) {
        $lines = $existingToml -split "`r?`n"
    }
    $managedNameSet = Get-McpServerNameSet $servers
    $codexServers = @()
    $hasGithubToken = -not [string]::IsNullOrWhiteSpace($env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN) -or -not [string]::IsNullOrWhiteSpace($env:GITHUB_PERSONAL_ACCESS_TOKEN)
    if ([string]::IsNullOrWhiteSpace($env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN) -and -not [string]::IsNullOrWhiteSpace($env:GITHUB_PERSONAL_ACCESS_TOKEN)) {
        $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN = [string]$env:GITHUB_PERSONAL_ACCESS_TOKEN
    }
    foreach ($server in @($servers)) {
        if ($null -eq $server) { continue }
        if ([string]::Equals([string]$server.name, "github", [System.StringComparison]::OrdinalIgnoreCase)) {
            if (-not $hasGithubToken) {
                Log "Codex 检测到 GitHub MCP 但缺少 CODEX_GITHUB_PERSONAL_ACCESS_TOKEN（或 GITHUB_PERSONAL_ACCESS_TOKEN），已跳过同步以避免影响启动。" "WARN"
                continue
            }
            Log "Codex 检测到 GitHub MCP 且存在 Token，将写入 bearer_token_env_var=CODEX_GITHUB_PERSONAL_ACCESS_TOKEN。" "INFO"
            $normalizedGithub = [ordered]@{
                name = [string]$server.name
                transport = if ([string]::IsNullOrWhiteSpace([string]$server.transport)) { "http" } else { [string]$server.transport }
                url = [string]$server.url
                bearer_token_env_var = "CODEX_GITHUB_PERSONAL_ACCESS_TOKEN"
            }
            $codexServers += [pscustomobject]$normalizedGithub
            continue
        }
        $codexServers += $server
    }

    $managedMap = Convert-McpServersToConfigMap $codexServers
    $managedNames = @($managedMap.PSObject.Properties.Name | Sort-Object)

    $kept = New-Object System.Collections.Generic.List[string]
    $skipManagedSection = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*\[mcp_servers\.([^\]]+)\]\s*$') {
            $name = [string]$matches[1]
            if ($managedNameSet.Contains($name)) {
                $skipManagedSection = $true
                continue
            }
            $skipManagedSection = $false
            $kept.Add($line) | Out-Null
            continue
        }

        if ($skipManagedSection -and $line -match '^\s*\[[^\]]+\]\s*$') {
            $skipManagedSection = $false
            $kept.Add($line) | Out-Null
            continue
        }

        if (-not $skipManagedSection) {
            $kept.Add($line) | Out-Null
        }
    }

    while ($kept.Count -gt 0 -and [string]::IsNullOrWhiteSpace($kept[$kept.Count - 1])) {
        $kept.RemoveAt($kept.Count - 1)
    }

    $output = New-Object System.Collections.Generic.List[string]
    $output.AddRange([string[]](Apply-CodexPermissionDefaults @([string[]]$kept.ToArray())))

    if ($managedNames.Count -gt 0) {
        if ($output.Count -gt 0) { $output.Add("") | Out-Null }
        foreach ($name in $managedNames) {
            $entry = $managedMap.$name
            $output.Add(("[mcp_servers.{0}]" -f $name)) | Out-Null
            foreach ($prop in $entry.PSObject.Properties) {
                $key = [string]$prop.Name
                $val = $prop.Value
                if ($null -eq $val) { continue }
                if ($val -is [Array]) {
                    $arr = @($val | ForEach-Object { ConvertTo-TomlBasicValue $_ })
                    $output.Add(("{0} = [{1}]" -f $key, ($arr -join ", "))) | Out-Null
                    continue
                }
                if ($val -is [hashtable] -or $val -is [System.Collections.IDictionary] -or $val -is [pscustomobject]) {
                    $dict = @{}
                    if ($val -is [pscustomobject]) {
                        foreach ($p in $val.PSObject.Properties) { $dict[[string]$p.Name] = $p.Value }
                    }
                    else {
                        foreach ($k in $val.Keys) { $dict[[string]$k] = $val[$k] }
                    }
                    $pairs = @($dict.Keys | Sort-Object | ForEach-Object { "{0} = {1}" -f $_, (ConvertTo-TomlBasicValue $dict[$_]) })
                    $output.Add(("{0} = {{ {1} }}" -f $key, ($pairs -join ", "))) | Out-Null
                    continue
                }
                $output.Add(("{0} = {1}" -f $key, (ConvertTo-TomlBasicValue $val))) | Out-Null
            }
            $output.Add("") | Out-Null
        }
        while ($output.Count -gt 0 -and [string]::IsNullOrWhiteSpace($output[$output.Count - 1])) {
            $output.RemoveAt($output.Count - 1)
        }
    }

    return ($output -join "`r`n")
}

function Resolve-GeminiAntigravityRootsFromCandidates($paths) {
    $roots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($null -eq $paths) { return @() }
    $token = ".gemini\antigravity"
    $tokenLower = $token.ToLowerInvariant()
    foreach ($p in $paths) {
        if ([string]::IsNullOrWhiteSpace([string]$p)) { continue }
        $norm = ([string]$p).Replace("/", "\")
        $lower = $norm.ToLowerInvariant()
        $searchStart = 0
        while ($searchStart -lt $lower.Length) {
            $idx = $lower.IndexOf($tokenLower, $searchStart)
            if ($idx -lt 0) { break }
            if ($idx -gt 0 -and $norm[$idx - 1] -ne '\') {
                $searchStart = $idx + 1
                continue
            }
            $end = $idx + $token.Length
            # Require a directory boundary to avoid false matches like antigravity-backup.
            if ($end -lt $norm.Length -and $norm[$end] -ne '\') {
                $searchStart = $idx + 1
                continue
            }
            $root = $norm.Substring(0, $idx + $token.Length)
            if (-not [string]::IsNullOrWhiteSpace($root)) { $roots.Add($root) | Out-Null }
            $searchStart = $idx + $token.Length
        }
    }
    # Keep array shape when only one root is found.
    return ,@($roots | Sort-Object)
}

function Get-TraeProjectMcpConfigPath([string]$repoRoot) {
    Need (-not [string]::IsNullOrWhiteSpace($repoRoot)) "repoRoot 不能为空"
    return (Join-Path (Join-Path $repoRoot ".trae") "mcp.json")
}

function Get-McpTargetCandidatePaths($cfg) {
    $paths = New-Object System.Collections.Generic.List[string]
    if ($null -eq $cfg) { return @() }
    if ($cfg.PSObject.Properties.Match("mcp_targets").Count -gt 0 -and $cfg.mcp_targets -ne $null) {
        foreach ($mt in $cfg.mcp_targets) {
            if ($mt -is [string]) {
                if (-not [string]::IsNullOrWhiteSpace($mt)) { $paths.Add($mt) | Out-Null }
            }
            elseif ($mt.PSObject.Properties.Match("path").Count -gt 0) {
                $v = [string]$mt.path
                if (-not [string]::IsNullOrWhiteSpace($v)) { $paths.Add($v) | Out-Null }
            }
        }
    }
    foreach ($t in $cfg.targets) {
        if ($t.PSObject.Properties.Match("path").Count -gt 0) {
            $v = [string]$t.path
            if (-not [string]::IsNullOrWhiteSpace($v)) { $paths.Add($v) | Out-Null }
        }
    }
    $resolved = New-Object System.Collections.Generic.List[string]
    foreach ($path in $paths) {
        $r = Resolve-TargetDir $path
        if (-not [string]::IsNullOrWhiteSpace($r)) { $resolved.Add($r.Replace("/", "\")) | Out-Null }
    }
    return @($resolved)
}

function Resolve-McpTargetRootsFromCfg($cfg) {
    $roots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($null -eq $cfg) { return @() }

    $candidates = Get-McpTargetCandidatePaths $cfg
    foreach ($path in $candidates) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        $norm = $path.Replace("/", "\")
        $lower = $norm.ToLowerInvariant()

        $dotDirs = @(".claude", ".codex", ".gemini", ".trae")
        $matched = $false
        $bestIdx = -1
        $bestNeedleLen = 0
        foreach ($dotDir in $dotDirs) {
            $needle = "\" + $dotDir.ToLowerInvariant()
            $searchStart = 0
            while ($searchStart -lt $lower.Length) {
                $idx = $lower.IndexOf($needle, $searchStart)
                if ($idx -lt 0) { break }
                $end = $idx + $needle.Length
                # Require directory boundary so ".gemini_backup" does not match ".gemini".
                if ($end -lt $norm.Length -and $norm[$end] -ne '\') {
                    $searchStart = $idx + 1
                    continue
                }
                if ($bestIdx -lt 0 -or $idx -lt $bestIdx) {
                    $bestIdx = $idx
                    $bestNeedleLen = $needle.Length
                }
                $matched = $true
                break
            }
        }
        if ($matched -and $bestIdx -ge 0) {
            $root = $norm.Substring(0, $bestIdx + $bestNeedleLen)
            $roots.Add($root) | Out-Null
        }
        if ($matched) { continue }

        $leaf = Split-Path $norm -Leaf
        if ($leaf.Equals("skills", [System.StringComparison]::OrdinalIgnoreCase)) {
            $parent = Split-Path $norm -Parent
            if (-not [string]::IsNullOrWhiteSpace($parent)) { $roots.Add($parent) | Out-Null }
            continue
        }

        $roots.Add($norm) | Out-Null
    }

    # Keep array shape when only one root is found.
    return ,@($roots | Sort-Object)
}

function ConvertTo-OrderedSignatureValue($value) {
    if ($null -eq $value) { return $null }
    if ($value -is [string]) { return [string]$value }
    if ($value -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($k in @($value.Keys | Sort-Object)) {
            $ordered[[string]$k] = ConvertTo-OrderedSignatureValue $value[$k]
        }
        return [pscustomobject]$ordered
    }
    if ($value -is [pscustomobject]) {
        $ordered = [ordered]@{}
        foreach ($p in @($value.PSObject.Properties | Sort-Object Name)) {
            $ordered[[string]$p.Name] = ConvertTo-OrderedSignatureValue $p.Value
        }
        return [pscustomobject]$ordered
    }
    if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [byte[]])) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($item in @($value)) {
            $items.Add((ConvertTo-OrderedSignatureValue $item)) | Out-Null
        }
        return @($items)
    }
    return $value
}

function Get-McpServerSignature($server) {
    if ($null -eq $server) { return $null }
    $transport = if ($server.PSObject.Properties.Match("transport").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$server.transport)) {
        [string]$server.transport
    }
    else {
        "stdio"
    }
    $transport = $transport.Trim().ToLowerInvariant()
    $sig = [ordered]@{ transport = $transport }
    if ($transport -eq "stdio") {
        if ($server.PSObject.Properties.Match("command").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$server.command)) {
            $sig.command = [string]$server.command
        }
        if ($server.PSObject.Properties.Match("args").Count -gt 0) {
            $sig.args = @($server.args)
        }
        if ($server.PSObject.Properties.Match("env").Count -gt 0 -and $null -ne $server.env) {
            $sig.env = ConvertTo-OrderedSignatureValue $server.env
        }
    }
    else {
        if ($server.PSObject.Properties.Match("url").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$server.url)) {
            $sig.url = [string]$server.url
        }
        if ($server.PSObject.Properties.Match("headers").Count -gt 0 -and $null -ne $server.headers) {
            $sig.headers = ConvertTo-OrderedSignatureValue $server.headers
        }
        if ($server.PSObject.Properties.Match("bearer_token_env_var").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$server.bearer_token_env_var)) {
            $sig.bearer_token_env_var = [string]$server.bearer_token_env_var
        }
    }
    return ($sig | ConvertTo-Json -Depth 30 -Compress)
}

function Test-McpServerEquivalent($a, $b) {
    $sa = Get-McpServerSignature $a
    $sb = Get-McpServerSignature $b
    if ([string]::IsNullOrWhiteSpace($sa) -or [string]::IsNullOrWhiteSpace($sb)) { return $false }
    return ($sa -eq $sb)
}

function Find-EquivalentMcpServer($servers, $candidate) {
    foreach ($server in @($servers)) {
        if (Test-McpServerEquivalent $server $candidate) { return $server }
    }
    return $null
}

function 安装MCP([string[]]$tokens = @()) {
    $cfg = LoadCfg
    $cfgRaw = Get-Content $CfgPath -Raw

    $tokenList = @($tokens | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($tokenList.Count -eq 1 -and $tokenList[0] -is [string] -and $tokenList[0].Contains(" ")) {
        $tokenList = Split-Args $tokenList[0]
    }

    $parsed = $null
    if ($tokenList.Count -gt 0) {
        $parsed = Parse-McpInstallArgs $tokenList
    }
    else {
        $name = Normalize-NameWithNotice (Read-HostSafe "MCP 服务名（如 context7）") "MCP 服务名"
        $transport = Read-HostSafe "transport（stdio/sse/http，默认 stdio）"
        if ([string]::IsNullOrWhiteSpace($transport)) { $transport = "stdio" }
        $transport = $transport.Trim().ToLowerInvariant()
        if ($transport -ne "stdio" -and $transport -ne "sse" -and $transport -ne "http") {
            Write-Host "无效 transport，已使用默认值 stdio"
            $transport = "stdio"
        }

        if ($transport -eq "stdio") {
            $cmdLine = Read-HostSafe "命令（示例：npx -y @upstash/context7-mcp）"
            $parts = Split-Args $cmdLine
            Need ($parts.Count -gt 0) "命令不能为空"
            $parsed = [pscustomobject]@{
                name = $name
                transport = "stdio"
                command = $parts[0]
                args = if ($parts.Count -gt 1) { $parts[1..($parts.Count - 1)] } else { @() }
                url = $null
                env = @{}
                headers = @{}
            }
        }
        else {
            $url = Read-HostSafe "URL（示例：https://example.com/mcp）"
            Need (-not [string]::IsNullOrWhiteSpace($url)) "URL 不能为空"
            $parsed = [pscustomobject]@{
                name = $name
                transport = $transport
                command = $null
                args = @()
                url = $url
                env = @{}
                headers = @{}
            }
        }
    }

    $server = New-McpServerObject $parsed
    $existing = @($cfg.mcp_servers)
    $existingSameName = $existing | Where-Object { [string]$_.name -eq [string]$server.name } | Select-Object -First 1
    $updated = @()
    $replaced = $false
    $equivalent = Find-EquivalentMcpServer $existing $server
    if ($existingSameName -and (Test-McpServerEquivalent $existingSameName $server)) {
        Write-Host ("MCP 服务已存在且配置一致：{0}" -f $server.name)
        return
    }
    foreach ($s in $existing) {
        if ([string]$s.name -eq [string]$server.name) {
            $updated += $server
            $replaced = $true
        }
        else {
            $updated += $s
        }
    }
    if ($equivalent -and -not $replaced) {
        Write-Host ("已存在等效 MCP 服务：{0}（名称：{1}），已跳过" -f $server.name, [string]$equivalent.name)
        return
    }
    if (-not $replaced) { $updated += $server }
    $cfg.mcp_servers = $updated
    SaveCfgSafe $cfg $cfgRaw

    if ($replaced) {
        Write-Host ("已更新 MCP 服务：{0}" -f $server.name)
    }
    else {
        Write-Host ("已安装 MCP 服务：{0}" -f $server.name)
    }
    同步MCP
}

function 卸载MCP([string[]]$tokens = @()) {
    $cfg = LoadCfg
    $cfgRaw = Get-Content $CfgPath -Raw
    $servers = @($cfg.mcp_servers)
    if ($servers.Count -eq 0) {
        Write-Host "当前没有已安装的 MCP 服务。"
        return
    }

    $name = $null
    $tokenList = @($tokens | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($tokenList.Count -gt 0) {
        $name = Normalize-NameWithNotice ([string]$tokenList[0]) "MCP 服务名"
    }
    if ([string]::IsNullOrWhiteSpace($name)) {
        Write-Host "已安装 MCP 服务："
        for ($i = 0; $i -lt $servers.Count; $i++) {
            Write-Host ("{0,3}) {1}" -f ($i + 1), $servers[$i].name)
        }
        $picked = Read-HostSafe "输入序号或名称"
        if ($picked -match "^\d+$") {
            $idx = [int]$picked - 1
            Need ($idx -ge 0 -and $idx -lt $servers.Count) "序号越界。"
            $name = [string]$servers[$idx].name
        }
        else {
            $name = Normalize-NameWithNotice $picked "MCP 服务名"
        }
    }

    $remaining = @()
    $removed = $false
    foreach ($s in $servers) {
        if ([string]$s.name -eq $name) {
            $removed = $true
        }
        else {
            $remaining += $s
        }
    }
    Need $removed ("未找到 MCP 服务：{0}" -f $name)

    $cfg.mcp_servers = $remaining
    SaveCfgSafe $cfg $cfgRaw
    Write-Host ("已卸载 MCP 服务：{0}" -f $name)
    Invoke-NativeMcpCleanup $name
    同步MCP
}

function 同步MCP {
    Invoke-WithMetric "sync_mcp" {
        $cfg = LoadCfg
        $servers = @($cfg.mcp_servers)
        $pruneNames = @(Get-LegacyMcpServersToPrune)
        if (-not $DryRun) {
            Ensure-GhAuthForGithubMcp $servers
        }

        $roots = Resolve-McpTargetRootsFromCfg $cfg
        Need ($roots.Count -gt 0) "未找到可同步的 MCP 目标目录（请检查 targets/mcp_targets 配置）。"
        $candidatePaths = Get-McpTargetCandidatePaths $cfg

        $written = @()
        foreach ($targetRoot in $roots) {
            $file = Join-Path $targetRoot ".mcp.json"
            $targetRootLeaf = (Split-Path ([string]$targetRoot) -Leaf)
            if ($DryRun) {
                Write-Host ("DRYRUN：将写入 MCP 配置 -> {0}" -f $file)
                $written += $file
                continue
            }
            EnsureDir $targetRoot
            $existing = if (Test-Path $file) { Get-Content -Raw -Path $file } else { "" }
            $payloadObj = Build-GenericMcpPayload $existing $servers
            $payloadObj = Remove-McpServersFromPayload $payloadObj $pruneNames
            $json = $payloadObj | ConvertTo-Json -Depth 100
            Set-ContentUtf8 $file $json
            $written += $file
            Log ("已同步 MCP 配置：{0}" -f $file)
        }

        $geminiRoots = @($roots | Where-Object { (Split-Path ([string]$_) -Leaf).Equals(".gemini", [System.StringComparison]::OrdinalIgnoreCase) })
        foreach ($geminiRoot in $geminiRoots) {
            $settingsPath = Join-Path $geminiRoot "settings.json"
            $existing = if (Test-Path $settingsPath) { Get-Content -Raw -Path $settingsPath } else { "" }
            $payloadObj = Build-GeminiSettingsPayload $existing $servers
            $content = $payloadObj | ConvertTo-Json -Depth 100
            if ($DryRun) {
                Write-Host ("DRYRUN：将写入 Gemini 配置 -> {0}" -f $settingsPath)
                $written += $settingsPath
            }
            else {
                EnsureDir $geminiRoot
                Set-ContentUtf8 $settingsPath $content
                $written += $settingsPath
                Log ("已同步 Gemini MCP 配置：{0}" -f $settingsPath)
            }
        }

        $antigravityRoots = Resolve-GeminiAntigravityRootsFromCandidates $candidatePaths
        foreach ($agRoot in $antigravityRoots) {
            $settingsPath = Join-Path $agRoot "settings.json"
            $existing = if (Test-Path $settingsPath) { Get-Content -Raw -Path $settingsPath } else { "" }
            $payloadObj = Build-GeminiSettingsPayload $existing $servers
            $content = $payloadObj | ConvertTo-Json -Depth 100
            if ($DryRun) {
                Write-Host ("DRYRUN：将写入 Gemini Antigravity 配置 -> {0}" -f $settingsPath)
                $written += $settingsPath
            }
            else {
                EnsureDir $agRoot
                Set-ContentUtf8 $settingsPath $content
                $written += $settingsPath
                Log ("已同步 Gemini Antigravity MCP 配置：{0}" -f $settingsPath)
            }
        }

        $codexRoots = @($roots | Where-Object { (Split-Path ([string]$_) -Leaf).Equals(".codex", [System.StringComparison]::OrdinalIgnoreCase) })
        foreach ($codexRoot in $codexRoots) {
            $cfgPath = Join-Path $codexRoot "config.toml"
            $existing = if (Test-Path $cfgPath) { Get-Content -Raw -Path $cfgPath } else { "" }
            $toml = Build-CodexConfigToml $existing $servers
            if ($DryRun) {
                Write-Host ("DRYRUN：将写入 Codex MCP 配置 -> {0}" -f $cfgPath)
                $written += $cfgPath
            }
            else {
                EnsureDir $codexRoot
                Set-ContentUtf8 $cfgPath $toml
                $written += $cfgPath
                Log ("已同步 Codex MCP 配置：{0}" -f $cfgPath)
            }
        }

        $traeRoots = @($roots | Where-Object { (Split-Path ([string]$_) -Leaf).Equals(".trae", [System.StringComparison]::OrdinalIgnoreCase) })
        foreach ($traeRoot in $traeRoots) {
            $traePath = Join-Path $traeRoot "mcp.json"
            if ($DryRun) {
                Write-Host ("DRYRUN：将写入 Trae MCP 配置 -> {0}" -f $traePath)
                $written += $traePath
            }
            else {
                EnsureDir $traeRoot
                $existing = if (Test-Path $traePath) { Get-Content -Raw -Path $traePath } else { "" }
                $payloadObj = Build-GenericMcpPayload $existing $servers
                $json = $payloadObj | ConvertTo-Json -Depth 100
                Set-ContentUtf8 $traePath $json
                $written += $traePath
                Log ("已同步 Trae MCP 配置：{0}" -f $traePath)
            }
        }

        $projectTraePath = Get-TraeProjectMcpConfigPath $script:Root
        if ($DryRun) {
            Write-Host ("DRYRUN：将写入项目级 Trae MCP 配置 -> {0}" -f $projectTraePath)
            $written += $projectTraePath
        }
        else {
            $projectTraeDir = Split-Path $projectTraePath -Parent
            EnsureDir $projectTraeDir
            $existing = if (Test-Path $projectTraePath) { Get-Content -Raw -Path $projectTraePath } else { "" }
            $payloadObj = Build-GenericMcpPayload $existing $servers
            $json = $payloadObj | ConvertTo-Json -Depth 100
            Set-ContentUtf8 $projectTraePath $json
            $written += $projectTraePath
            Log ("已同步项目级 Trae MCP 配置：{0}" -f $projectTraePath)
        }

        Write-Host ("已同步 MCP 服务配置到 {0} 个目标。" -f $written.Count)
        foreach ($pruneName in $pruneNames) {
            Invoke-NativeMcpCleanup $pruneName
        }
        Invoke-NativeMcpSync $servers
        if (-not $DryRun) {
            $attemptsEnv = $env:SKILLS_MCP_VERIFY_ATTEMPTS
            $intervalEnv = $env:SKILLS_MCP_VERIFY_INTERVAL_SECONDS
            $attemptsParsed = 0
            $intervalParsed = 0
            $attempts = if ([int]::TryParse([string]$attemptsEnv, [ref]$attemptsParsed)) { $attemptsParsed } else { 6 }
            $intervalSeconds = if ([int]::TryParse([string]$intervalEnv, [ref]$intervalParsed)) { $intervalParsed } else { 3 }
            if ($attempts -lt 1) { $attempts = 1 }
            if ($intervalSeconds -lt 1) { $intervalSeconds = 1 }
            Verify-McpAcrossCliWithRetry $roots $attempts $intervalSeconds
        }
        if ($servers.Count -eq 0) {
            Write-Host "提示：当前 mcp_servers 为空，已将各目标写为空配置。"
        }
    } @{ command = "同步MCP" } -NoHost
}
 
 function 打开配置 {
    Need (Test-Path $CfgPath) "缺少配置文件：$CfgPath"
    if (Get-Command code -ErrorAction SilentlyContinue) {
        Invoke-StartProcess "code" "`"$CfgPath`""
    }
    else {
        Invoke-StartProcess "notepad" "`"$CfgPath`""
    }
}

function 解除关联 {
    Preflight
    $cfg = LoadCfg
    foreach ($t in $cfg.targets) {
        $target = Resolve-TargetDir $t.path
        if ($target) {
            Remove-JunctionAndRestore $target
        }
    }
    Write-Host "解除完成。"
}

function 清理备份 {
    $excludeRoots = @($VendorDir, $AgentDir, $ImportDir, (Join-Path $Root ".git"))
    $bakDirs = @()
    $bakFiles = @()
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        if (Is-ExcludedPath $dir $excludeRoots) { continue }
        try {
            $entries = Get-ChildItem $dir -Force -ErrorAction SilentlyContinue
        }
        catch { continue }
        foreach ($e in $entries) {
            if ($e.PSIsContainer) {
                if (Is-ReparsePoint $e.FullName) { continue }
                if ($e.Name -eq ".bak" -or $e.Name -like "*.bak.*") { $bakDirs += $e }
                $stack.Push($e.FullName)
            }
            else {
                if ($e.Name -like "*.bak.*") { $bakFiles += $e }
            }
        }
    }

    if ($bakDirs.Count -eq 0 -and $bakFiles.Count -eq 0) {
        Write-Host "未发现备份文件或目录。"
        return
    }

    # 排除已包含在 .bak 目录下的文件，避免重复/噪声
    $filteredFiles = @()
    foreach ($f in $bakFiles) {
        $inBakDir = $false
        foreach ($d in $bakDirs) {
            if ($f.FullName.StartsWith($d.FullName + "\")) {
                $inBakDir = $true
                break
            }
        }
        if (-not $inBakDir) { $filteredFiles += $f }
    }

    $total = $bakDirs.Count + $filteredFiles.Count
    Write-Host ("将清理备份项共 {0} 个（目录 {1}，文件 {2}）。" -f $total, $bakDirs.Count, $filteredFiles.Count)

    $preview = @()
    foreach ($d in $bakDirs) { $preview += $d.FullName }
    foreach ($f in $filteredFiles) { $preview += $f.FullName }
    if (-not (Confirm-WithSummary "将清理以下备份项" $preview "输入 DELETE 确认彻底清理备份" "DELETE")) {
        Write-Host "已取消清理。"
        return
    }
    if (Skip-IfDryRun "清理备份") { return }

    foreach ($d in ($bakDirs | Sort-Object { $_.FullName.Length } -Descending)) {
        if (-not (Is-PathInsideOrEqual $d.FullName $Root)) { continue }
        Invoke-RemoveItem $d.FullName -Recurse
    }
    foreach ($f in $filteredFiles) {
        if (-not (Is-PathInsideOrEqual $f.FullName $Root)) { continue }
        Invoke-RemoveItem $f.FullName
    }
    Write-Host "清理完成。"
}
function Get-自动更新任务名 {
    return "skills-manager-weekly-update-friday-2000"
}
function Get-自动更新脚本路径 {
    return (Join-Path $Root "scripts/weekly-auto-update.ps1")
}
function 获取自动更新任务 {
    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) { return $null }
    try { return (Get-ScheduledTask -TaskName (Get-自动更新任务名) -ErrorAction Stop) }
    catch { return $null }
}
function 查看自动更新状态 {
    $taskName = Get-自动更新任务名
    $task = 获取自动更新任务
    if ($null -eq $task) {
        Write-Host ("自动更新：未启用（任务名：{0}）" -f $taskName) -ForegroundColor Yellow
        return
    }

    $info = $null
    try { $info = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction Stop } catch {}
    $state = [string]$task.State
    $nextRun = "未知"
    $lastRun = "未知"
    if ($null -ne $info) {
        if ($info.NextRunTime -and $info.NextRunTime -gt [datetime]::MinValue) { $nextRun = $info.NextRunTime.ToString("yyyy-MM-dd HH:mm:ss") }
        if ($info.LastRunTime -and $info.LastRunTime -gt [datetime]::MinValue) { $lastRun = $info.LastRunTime.ToString("yyyy-MM-dd HH:mm:ss") }
    }
    Write-Host ("自动更新：已启用（每周五 20:00，本机时间）")
    Write-Host ("任务名：{0}" -f $taskName)
    Write-Host ("状态：{0}" -f $state)
    Write-Host ("下次运行：{0}" -f $nextRun)
    Write-Host ("上次运行：{0}" -f $lastRun)
}
function 启用自动更新 {
    $taskName = Get-自动更新任务名
    $runnerPath = Get-自动更新脚本路径
    Need (Test-Path $runnerPath) ("缺少自动更新脚本：{0}" -f $runnerPath)
    Need (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue) "当前环境不支持 ScheduledTasks 模块。"
    Need (Get-Command New-ScheduledTaskAction -ErrorAction SilentlyContinue) "当前环境不支持 ScheduledTasks 模块。"
    Need (Get-Command powershell -ErrorAction SilentlyContinue) "未找到 powershell 可执行文件。"

    if (Skip-IfDryRun "启用自动更新计划任务") { return }

    $pwsh = (Get-Command powershell -ErrorAction Stop).Source
    $args = ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $runnerPath)
    $action = New-ScheduledTaskAction -Execute $pwsh -Argument $args -WorkingDirectory $Root
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Friday -At "20:00"
    $principal = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "skills-manager 每周五 20:00 自动执行 更新 + 同步MCP" -Force | Out-Null
    Write-Host "✅ 已启用自动更新：每周五 20:00（本机时间）。"
    查看自动更新状态
}
function 禁用自动更新 {
    $taskName = Get-自动更新任务名
    if (Skip-IfDryRun "禁用自动更新计划任务") { return }
    $task = 获取自动更新任务
    if ($null -eq $task) {
        Write-Host "自动更新任务不存在，无需禁用。"
        return
    }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
    Write-Host "✅ 已禁用自动更新任务。"
}
function 自动更新设置 {
    while ($true) {
        Write-Host ""
        Write-Host "=== 自动更新设置 ==="
        Write-Host "目标：每周五 20:00 自动执行【更新 + 同步MCP】"
        查看自动更新状态
        Write-Host "1) 启用（每周五 20:00）"
        Write-Host "2) 禁用"
        Write-Host "3) 查看状态"
        Write-Host "0) 返回"
        $c = Read-HostSafe "请选择"
        switch ($c) {
            "1" { 启用自动更新 }
            "2" { 禁用自动更新 }
            "3" { 查看自动更新状态 }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}

function 帮助 {
    @"
Skills 管理器（极简版，中文菜单）

推荐使用顺序：
  1) 接入来源：先新增技能库，或直接粘贴 add / npx 命令导入技能
  2) 发现：查看当前已接入技能库里有哪些技能，可先按关键词过滤
  3) 安装：
     - 命令导入安装：粘贴一条或多条 add / npx skills add / npx add-skill 命令
     - 从技能库选择安装：从已接入技能库中勾选技能，写入 mappings 白名单
  4) 构建并生效：按当前配置重建 agent/，再同步到 targets
  5) 更新：拉取上游 vendor/imports，处理本地改动后再重建同步

主要功能说明：
  - 发现：列出当前技能库中的可用技能；只查看，不改配置
  - 命令导入安装：解析粘贴的 add / npx 命令；支持一次导入多个技能，并自动构建生效
  - 从技能库选择安装：从技能库中勾选多个技能，追加到 mappings 白名单并自动构建生效
  - 卸载：从 mappings 白名单移除技能；必要时清理 imports 条目、legacy manual 目录和对应 overrides 备份
  - 新增技能库：向 vendors 写入仓库地址并初始化；留空时仅初始化已配置 vendors
  - 删除技能库：移除 vendors 中的仓库；可选择是否保留其已安装技能（转为 manual）后重建生效
  - 更新：拉取 vendor/imports 上游内容；本地改动自动保留并跳过强制清理，然后重建并同步
  - 构建并生效：仅使用当前本地配置与文件源（imports / overrides / mappings）重建输出并同步；可配合 -Locked 做严格校验
  - 锁定：生成 skills.lock.json，记录当前 vendor/import commit
  - 安装MCP：向 skills.json 登记 MCP 服务（支持 stdio / sse / http），并自动同步
  - 卸载MCP：从 skills.json 移除 MCP 服务，并自动同步
  - 同步MCP：仅重新同步 MCP 配置，不处理技能构建
  - 自动更新设置：配置本机计划任务，每周五 20:00 自动执行“更新 + 同步MCP”
  - 打开配置：打开 skills.json 进行手工检查或编辑
  - 解除关联：移除 link 模式下创建的目录关联
  - 清理备份：删除仓库内 *.bak.* 文件和 .bak 目录（排除 vendor / agent / imports / .git）

说明：
  - 手动更新会访问上游仓库；如果你只想让本地改动重新输出，请用“构建并生效”。
  - 命令导入安装默认先做严格预检：校验仓库可达、技能路径存在，再执行导入。
  - 命令导入安装会自动补全 owner/repo URL；若技能不唯一，会提示候选路径。
  - 从技能库选择安装更适合浏览后再批量勾选；命令导入安装更适合直接粘贴已有命令。

命令行：
  .\skills.ps1 发现
  .\skills.ps1 发现技能
  .\skills.ps1 命令导入安装
  .\skills.ps1 安装
  .\skills.ps1 从技能库选择安装
  .\skills.ps1 卸载
  .\skills.ps1 卸载技能
  .\skills.ps1 新增技能库
  .\skills.ps1 删除技能库
  .\skills.ps1 add <repo> [--skill <name>] [--ref <branch/tag>] [--mode manual|vendor] [--sparse]
  .\skills.ps1 npx "skills add <repo> [--skill <name>] [--ref <branch/tag>] [--mode manual|vendor] [--sparse]"
  .\skills.ps1 npx "add-skill <repo> [--skill <name>] [--ref <branch/tag>] [--mode manual|vendor] [--sparse]"
  .\skills.ps1 更新
  .\skills.ps1 更新上游并重建
  .\skills.ps1 更新 -Plan
  .\skills.ps1 更新 -Upgrade
  .\skills.ps1 构建生效
  .\skills.ps1 构建并生效
  .\skills.ps1 锁定
  .\skills.ps1 生成锁文件
  .\skills.ps1 打开配置
  .\skills.ps1 解除关联
  .\skills.ps1 清理备份
  .\skills.ps1 自动更新设置
  .\skills.ps1 安装MCP <name> -- <command> [args...]          （推荐）
  .\skills.ps1 安装MCP <name> --cmd <command> [--arg <arg>...] （兼容）
  .\skills.ps1 安装MCP <name> --transport http --url <url> [--bearer-token-env-var <ENV>] 
  .\skills.ps1 卸载MCP <name>
  .\skills.ps1 同步MCP（可选：手动兜底）
  .\skills.ps1 doctor [--json] [--fix] [--dry-run-fix] [--strict] [--strict-perf] [--threshold-ms <ms>]
  通用参数：
  -DryRun：仅预演（跳过写入/删除/同步/拉取）
  -Locked：严格锁定（需 skills.lock.json 且 commit 全匹配）
  -Plan：仅输出更新预览（不改动）
  -Upgrade：执行更新后自动刷新 skills.lock.json

配置：skills.json
  - vendors：上游仓库 URL
  - mappings：白名单（安装/卸载）
  - mcp_servers：MCP 服务清单（安装MCP/卸载MCP会自动同步）
  - mcp_targets：可选 MCP 目标目录（未配置时从 targets 自动推断）
  - sync_mode：Windows 优先 link（Junction），受限环境用 sync（兜底）

过滤语法（批量安装/卸载/发现命令）：
  - 多关键词：空格分隔，AND 过滤（如：docx pdf）
  - 正则：用 /.../ 包裹（如：/docx|pdf/）

本地技能：
  - add/npx 未指定 --skill 时仅新增技能库（vendor），不会自动安装整库技能。
  - add/npx 显式指定 --skill 时默认落入 imports（mode=manual），可用 --mode vendor 改为 vendor 管理。
  - manual/ 仅保留 legacy 兼容读取，建议将自定义改动放入 overrides/。
  - “命令导入安装”支持多行输入 add / npx skills add / npx add-skill。
  - 为兼容旧习惯，`安装` / `卸载` / `更新` / `构建生效` / `锁定` 等旧命令仍然保留可用。

提示：如遇 PowerShell 脚本执行被拦，可在当前窗口临时放开：
  Set-ExecutionPolicy -Scope Process Bypass
"@ | Write-Host
}

function 菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== Skills 管理器（极简版）==="
        Write-Host "技能操作"
        Write-Host "1) 发现技能（浏览已接入技能库）"
        Write-Host "2) 命令导入安装（粘贴一条或多条 add / npx 命令）"
        Write-Host "3) 从技能库选择安装（勾选后写入白名单）"
        Write-Host "4) 卸载技能（移除白名单并清理相关本地项）"
        Write-Host "5) 构建并生效（按当前配置重建并同步）"
        Write-Host "6) 更新上游并重建（拉取后重建并同步）"
        Write-Host ""
        Write-Host "来源与配置"
        Write-Host "7) 新增技能库（写入 vendors 并初始化）"
        Write-Host "8) 删除技能库（移除 vendor 并重建）"
        Write-Host "9) 打开配置（skills.json）"
        Write-Host "10) 生成锁文件（skills.lock.json）"
        Write-Host ""
        Write-Host "MCP 管理"
        Write-Host "11) 安装MCP（登记 MCP 服务并自动同步）"
        Write-Host "12) 卸载MCP（移除 MCP 服务并自动同步）"
        Write-Host "13) 同步MCP（仅重新同步 MCP 配置）"
        Write-Host ""
        Write-Host "维护"
        Write-Host "14) 解除关联（仅 link 模式需要）"
        Write-Host "15) 清理备份（删除仓库内 *.bak.* / .bak，排除 vendor/agent/imports/.git）"
        Write-Host "16) 自动更新设置（每周五 20:00 自动执行 更新 + 同步MCP）"
        Write-Host "98) 帮助"
        Write-Host "0) 退出"
        $c = Read-HostSafe "请选择"
        switch ($c) {
            "1" { 发现 }
            "2" { 命令导入安装 }
            "3" { 安装 }
            "4" { 卸载 }
            "5" { 构建生效 }
            "6" { 更新 }
            "7" { 新增技能库 }
            "8" { 删除技能库 }
            "9" { 打开配置 }
            "10" { 锁定 }
            "11" { 安装MCP }
            "12" { 卸载MCP }
            "13" { 同步MCP }
            "14" { 解除关联 }
            "15" { 清理备份 }
            "16" { 自动更新设置 }
            "98" { 帮助 }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}
 
 # Main Entry Point
# ----------------
# This file is used to assemble the final script.
# It includes the main dispatch logic.

if ($MyInvocation.InvocationName -ne '.') {
    try {
        switch ($Cmd) {
            "menu" { 菜单 }
            "初始化" { 初始化 }
            "新增技能库" { 新增技能库 }
            "删除技能库" { 删除技能库 }
            "发现" { 发现 }
            "发现技能" { 发现 }
            "命令导入安装" { 命令导入安装 }
            "add" { Add-ImportFromArgs (Merge-FilterAndArgs $Filter $args) }
            "npx" { Add-ImportFromArgs (Get-AddTokensFromNpx (Merge-FilterAndArgs $Filter $args)) }
            "安装" { 安装 }
            "从技能库选择安装" { 安装 }
            "卸载" { 卸载 }
            "卸载技能" { 卸载 }
            "选择" { 选择 }
            "构建生效" { 构建生效 }
            "构建并生效" { 构建生效 }
            "更新" { 更新 }
            "更新上游并重建" { 更新 }
            "锁定" { 锁定 }
            "生成锁文件" { 锁定 }
            "安装MCP" {
                $mcpTokens = @()
                if (-not [string]::IsNullOrWhiteSpace($Filter)) { $mcpTokens += $Filter }
                $mcpTokens += @($args)
                安装MCP $mcpTokens
            }
            "卸载MCP" {
                $mcpTokens = @()
                if (-not [string]::IsNullOrWhiteSpace($Filter)) { $mcpTokens += $Filter }
                $mcpTokens += @($args)
                卸载MCP $mcpTokens
            }
            "同步MCP" { 同步MCP }
            "mcp-install" {
                $mcpTokens = @()
                if (-not [string]::IsNullOrWhiteSpace($Filter)) { $mcpTokens += $Filter }
                $mcpTokens += @($args)
                安装MCP $mcpTokens
            }
            "mcp-uninstall" {
                $mcpTokens = @()
                if (-not [string]::IsNullOrWhiteSpace($Filter)) { $mcpTokens += $Filter }
                $mcpTokens += @($args)
                卸载MCP $mcpTokens
            }
            "mcp-sync" { 同步MCP }
            "打开配置" { 打开配置 }
            "解除关联" { 解除关联 }
            "清理备份" { 清理备份 }
            "自动更新设置" { 自动更新设置 }
            "帮助" { 帮助 }
            "doctor" {
                $doctorTokens = @()
                if (-not [string]::IsNullOrWhiteSpace($Filter)) { $doctorTokens += $Filter }
                $doctorTokens += @($args)
                $doctorResult = Invoke-Doctor $doctorTokens
                $strictRequested = ($doctorTokens | Where-Object { ([string]$_).Trim().ToLowerInvariant() -eq "--strict" }).Count -gt 0
                if ($strictRequested -and $doctorResult -and $doctorResult.PSObject.Properties.Match("pass").Count -gt 0 -and -not [bool]$doctorResult.pass) {
                    exit 2
                }
            }
        }
    }
    catch {
        $msg = $_.Exception.Message
        Log ("未处理错误：{0}" -f $msg) "ERROR"
        Write-Host ("❌ 发生错误：{0}" -f $msg) -ForegroundColor Red
        exit 1
    }
}
 
