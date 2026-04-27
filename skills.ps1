#requires -Version 5.1
param(
    [ValidateSet("menu", "初始化", "新增技能库", "删除技能库", "发现", "发现技能", "命令导入安装", "安装", "从技能库选择安装", "卸载", "卸载技能", "选择", "构建生效", "构建并生效", "更新", "更新上游并重建", "锁定", "生成锁文件", "清理无效映射", "打开配置", "解除关联", "清理备份", "自动更新设置", "帮助", "help", "--help", "-h", "doctor", "add", "npx", "安装MCP", "卸载MCP", "同步MCP", "mcp-install", "mcp-uninstall", "mcp-sync", "审查目标", "audit-targets", "一键", "workflow", "prune-invalid-mappings")]
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
$script:ActiveLogPath = $null
$script:LogPathFallbackWarned = $false

function Resolve-ActiveLogPath {
    if (-not [string]::IsNullOrWhiteSpace($script:ActiveLogPath)) { return $script:ActiveLogPath }
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) { $candidates += $LogPath }
    $tempRoot = $env:TEMP
    if ([string]::IsNullOrWhiteSpace($tempRoot)) { $tempRoot = [System.IO.Path]::GetTempPath() }
    if (-not [string]::IsNullOrWhiteSpace($tempRoot)) {
        $candidates += (Join-Path $tempRoot "skills-manager-build.log")
    }
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        try {
            $parent = Split-Path -Parent $candidate
            if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            [System.IO.File]::AppendAllText($candidate, "")
            $script:ActiveLogPath = $candidate
            return $script:ActiveLogPath
        }
        catch {}
    }
    return $null
}

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
function Rotate-LogIfNeeded([string]$TargetPath) {
    if ([string]::IsNullOrWhiteSpace($TargetPath)) { return }
    if (-not (Test-Path -LiteralPath $TargetPath)) { return }
    $maxBytes = Get-LogRotateMaxBytes
    $maxBackups = Get-LogMaxBackups
    try {
        $size = (Get-Item -LiteralPath $TargetPath -ErrorAction Stop).Length
        if ($size -lt $maxBytes) { return }
        for ($i = $maxBackups; $i -ge 1; $i--) {
            $src = if ($i -eq 1) { $TargetPath } else { "{0}.{1}" -f $TargetPath, ($i - 1) }
            $dst = "{0}.{1}" -f $TargetPath, $i
            if (-not (Test-Path -LiteralPath $src)) { continue }
            if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force }
            Move-Item -LiteralPath $src -Destination $dst -Force
        }
    }
    catch {}
}
function Write-LogRecord([string]$Level, [string]$Message, [object]$Data) {
    if ($DryRun) { return }
    $targetPath = Resolve-ActiveLogPath
    if ([string]::IsNullOrWhiteSpace($targetPath)) { return }
    Rotate-LogIfNeeded $targetPath
    $record = [ordered]@{
        ts    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        level = $Level.ToUpperInvariant()
        msg   = $Message
    }
    if ($null -ne $Data) { $record.data = $Data }
    $json = ($record | ConvertTo-Json -Depth 20 -Compress)
    try {
        $json | Out-File -FilePath $targetPath -Append -Encoding UTF8
        return
    }
    catch {}
    if ($targetPath -ne $LogPath) { return }

    # 主日志路径不可写时，自动回退到 TEMP，避免日志故障中断主流程
    $script:ActiveLogPath = $null
    $fallbackPath = Resolve-ActiveLogPath
    if ([string]::IsNullOrWhiteSpace($fallbackPath) -or $fallbackPath -eq $targetPath) { return }
    try {
        $json | Out-File -FilePath $fallbackPath -Append -Encoding UTF8
        if (-not $script:LogPathFallbackWarned) {
            Write-Host ("[WARN] 日志路径不可写，已切换到：{0}" -f $fallbackPath) -ForegroundColor Yellow
            $script:LogPathFallbackWarned = $true
        }
    }
    catch {}
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
    if (-not (Test-PathEntry $path)) { return }
    $recurseFlag = if ($Recurse) { "-Recurse " } else { "" }
    Log ("Remove-Item {0}{1}" -f $recurseFlag, $path)
    if (-not $DryRun) {
        if ($Recurse) { Remove-Item -LiteralPath $path -Recurse -Force }
        else { Remove-Item -LiteralPath $path -Force }
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
    if (-not (Test-PathEntry $path)) { return $true }
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
    if (-not $DryRun) { Move-Item -LiteralPath $src -Destination $dst -Force }
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
    if ([string]::IsNullOrWhiteSpace($p)) { return }
    if (-not (Test-Path -LiteralPath $p -PathType Container)) {
        [System.IO.Directory]::CreateDirectory($p) | Out-Null
    }
}
function Clear-FileWriteBlockAttributes([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    try {
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        $resetAttrs = [System.IO.FileAttributes]::ReadOnly -bor [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System
        if (($item.Attributes -band $resetAttrs) -ne 0) {
            $item.Attributes = ($item.Attributes -band (-bnot $resetAttrs))
        }
    }
    catch {}
}
function Set-ContentUtf8([string]$path, [string]$content) {
    if ($DryRun) { return }
    $parent = Split-Path $path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent)) { EnsureDir $parent }
    Clear-FileWriteBlockAttributes $path
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $bytes = $utf8NoBom.GetBytes($content)
    $tempPath = "{0}.tmp-{1}" -f $path, ([System.Guid]::NewGuid().ToString("N"))
    $backupPath = "{0}.bak-{1}" -f $path, ([System.Guid]::NewGuid().ToString("N"))
    $maxAttempts = 4
    $delayMs = 200
    for ($attempt = 0; $attempt -lt $maxAttempts; $attempt++) {
        try {
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                [System.IO.File]::WriteAllBytes($tempPath, $bytes)
                [System.IO.File]::Replace($tempPath, $path, $backupPath, $true)
                if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
                    Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
                }
            }
            else {
                [System.IO.File]::WriteAllBytes($path, $bytes)
            }
            Clear-FileWriteBlockAttributes $path
            return
        }
        catch {
            $baseException = $_.Exception
            if ($baseException -is [System.Management.Automation.MethodInvocationException] -and $baseException.InnerException) {
                $baseException = $baseException.InnerException
            }
            $isRetryable = ($baseException -is [System.UnauthorizedAccessException]) -or ($baseException -is [System.IO.IOException])
            if (-not $isRetryable) { throw }

            if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
                try { Remove-Item -LiteralPath $tempPath -Force -ErrorAction Stop } catch {}
            }
            if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
                try { Remove-Item -LiteralPath $backupPath -Force -ErrorAction Stop } catch {}
            }
            Clear-FileWriteBlockAttributes $path

            if ($attempt -ge ($maxAttempts - 1)) {
                # Some restricted hosts allow file writes but deny atomic replace/move.
                try {
                    [System.IO.File]::WriteAllBytes($path, $bytes)
                    Clear-FileWriteBlockAttributes $path
                    return
                }
                catch {
                    throw $baseException
                }
            }
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
function Resolve-PowerShellExecutable {
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_ALLOW_WINDOWS_POWERSHELL)) {
        $legacy = Get-Command powershell -ErrorAction SilentlyContinue
        if ($legacy) { return [string]$legacy.Source }
    }

    $programFilesPwsh = if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        Join-Path $env:ProgramFiles "PowerShell\7\pwsh.exe"
    } else {
        $null
    }
    if (-not [string]::IsNullOrWhiteSpace($programFilesPwsh) -and (Test-Path -LiteralPath $programFilesPwsh)) {
        return $programFilesPwsh
    }

    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) { return [string]$pwsh.Source }

    $legacyFallback = Get-Command powershell -ErrorAction SilentlyContinue
    if ($legacyFallback) { return [string]$legacyFallback.Source }

    throw "未找到 PowerShell 可执行文件。请优先安装 PowerShell 7 (pwsh)。"
}
function Read-HostSafe([string]$prompt) {
    $value = Read-Host $prompt
    if ($null -eq $value) { return "" }
    return $value.Trim()
}
function Read-MenuChoice([string]$prompt = "请选择") {
    $choice = Read-HostSafe $prompt
    if ([string]::IsNullOrWhiteSpace($choice)) { return "0" }
    return $choice
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
    if (-not (Get-Variable -Name DryRunMirrorCommands -Scope Script -ErrorAction SilentlyContinue)) { return }
    if ($null -eq $script:DryRunMirrorCommands) { return }
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
    $manualCount = @(收集ManualSkills $cfg).Count
    $overrideCount = @(Get-OverridesDirs).Count
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
    & (Resolve-PowerShellExecutable) @args
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
function Test-PathEntry([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    try {
        Get-Item -LiteralPath $path -Force -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}
function Is-ReparsePoint([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    try {
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
    }
    catch {
        return $false
    }
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
    if (-not (Test-PathEntry $path)) { return $null }
    if (Is-ReparsePoint $path) { return $null }
    $parent = Split-Path $path -Parent
    $leaf = Split-Path $path -Leaf
    $bak = Join-Path $parent ("{0}.bak.{1}" -f $leaf, (Get-Date -Format "yyyyMMdd-HHmmss"))
    Invoke-MoveItem $path $bak
    return $bak
}
function Backup-OverrideDir([string]$overrideName) {
    $src = Join-Path $OverridesDir $overrideName
    if (-not (Test-PathEntry $src)) { return $null }
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

    if (Test-PathEntry $linkPath) {
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
    if (Is-ReparsePoint $linkPath) {
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
    if (-not (Get-Variable -Name SkillCandidatesCache -Scope Script -ErrorAction SilentlyContinue)) { $script:SkillCandidatesCache = @{} }
    if ($null -eq $script:SkillCandidatesCache) { $script:SkillCandidatesCache = @{} }
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
function Get-GitCleanFailurePathsFromMessage([string]$message) {
    if ([string]::IsNullOrWhiteSpace($message)) { return @() }
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($segment in @($message -split "\|")) {
        $text = [string]$segment
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $trimmed = $text.Trim()
        $match = [regex]::Match($trimmed, "failed to remove(?: directory)?\s+'([^']+)'", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $match.Success) {
            $match = [regex]::Match($trimmed, "failed to remove(?: directory)?\s+([^:]+?)(?::|$)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
        if (-not $match.Success) { continue }
        $pathText = $match.Groups[1].Value
        if ([string]::IsNullOrWhiteSpace($pathText)) { continue }
        $paths.Add($pathText.Trim()) | Out-Null
    }
    return @($paths | Select-Object -Unique)
}
function Resolve-GitCleanFailurePath([string]$repoPath, [string]$rawPath) {
    if ([string]::IsNullOrWhiteSpace($repoPath) -or [string]::IsNullOrWhiteSpace($rawPath)) { return $null }
    $candidate = $rawPath.Trim().Trim("'`"").Trim()
    if ([string]::IsNullOrWhiteSpace($candidate)) { return $null }
    $candidate = $candidate -replace "/", "\"
    try {
        $repoFull = [System.IO.Path]::GetFullPath($repoPath)
    }
    catch {
        return $null
    }

    $fullPath = $null
    try {
        if ([System.IO.Path]::IsPathRooted($candidate)) {
            $fullPath = [System.IO.Path]::GetFullPath($candidate)
        }
        else {
            $fullPath = [System.IO.Path]::GetFullPath((Join-Path $repoFull $candidate))
        }
    }
    catch {
        return $null
    }
    if (-not (Is-PathInsideOrEqual $fullPath $repoFull)) { return $null }
    return $fullPath
}
function Clear-ReadOnlyAttribute([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    if (-not (Test-Path -LiteralPath $path)) { return }
    try {
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if (($item.Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
            $item.Attributes = ($item.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly))
        }
    }
    catch {}
}
function Clear-ReadOnlyAttributesRecursively([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return }
    if (-not (Test-Path -LiteralPath $path)) { return }
    Clear-ReadOnlyAttribute $path
    try {
        foreach ($child in @(Get-ChildItem -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue)) {
            Clear-ReadOnlyAttribute $child.FullName
        }
    }
    catch {}
}
function Repair-GitCleanPermissionDenied([string]$repoPath, [string]$errorMessage) {
    if ([string]::IsNullOrWhiteSpace($errorMessage)) { return $false }
    if ($errorMessage -notmatch "git clean\s+-fd") { return $false }
    if ($errorMessage -notmatch "failed to remove|Permission denied|拒绝访问|Directory not empty") { return $false }

    $rawPaths = @(Get-GitCleanFailurePathsFromMessage $errorMessage)
    if ($rawPaths.Count -eq 0) { return $false }
    $repaired = $false
    foreach ($raw in $rawPaths) {
        $fullPath = Resolve-GitCleanFailurePath $repoPath $raw
        if ([string]::IsNullOrWhiteSpace($fullPath)) {
            Log ("git clean 修复跳过（路径超出仓库边界或无效）：{0}" -f $raw) "WARN"
            continue
        }
        if (-not (Test-Path -LiteralPath $fullPath)) { continue }
        Clear-ReadOnlyAttributesRecursively $fullPath
        $removed = Invoke-RemoveItemWithRetry $fullPath -Recurse -IgnoreFailure -SilentIgnore
        if ($removed -or -not (Test-Path -LiteralPath $fullPath)) {
            Log ("git clean 权限修复完成：{0}" -f $fullPath) "WARN"
            $repaired = $true
        }
        else {
            Log ("git clean 权限修复未完成：{0}" -f $fullPath) "WARN"
        }
    }
    return $repaired
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
    $repoPath = (Get-Location).Path
    $maxCleanAttempts = 12
    for ($attempt = 1; $attempt -le $maxCleanAttempts; $attempt++) {
        try {
            Invoke-Git @("clean", "-fd")
            return
        }
        catch {
            if ($attempt -ge $maxCleanAttempts) { throw }
            if (-not (Repair-GitCleanPermissionDenied $repoPath $_.Exception.Message)) { throw }
            Log ("git clean 失败，已执行权限修复并重试（{0}/{1}）" -f $attempt, $maxCleanAttempts) "WARN"
        }
    }
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
        if (-not (Test-IsGitRepoRoot $path)) { continue }
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
        if (-not (Test-IsGitRepoRoot $cache)) { continue }
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
function Get-CfgObjectProperty($obj, [string]$name) {
    if ($null -eq $obj) { return $null }
    if ($obj -is [System.Collections.IDictionary] -or
        $obj -is [System.Collections.Specialized.OrderedDictionary] -or
        $obj -is [System.Collections.Specialized.IOrderedDictionary]) {
        if ($obj.Contains($name)) { return $obj[$name] }
        foreach ($key in @($obj.Keys)) {
            if ([string]::Equals([string]$key, $name, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $obj[$key]
            }
        }
        return $null
    }
    if ($obj.PSObject.Properties.Match($name).Count -eq 0) { return $null }
    return $obj.$name
}
function New-CfgVendorNameSet($vendors = @()) {
    $set = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $set.Add("manual") | Out-Null
    $set.Add("overrides") | Out-Null
    foreach ($v in @($vendors)) {
        if ($null -eq $v) { continue }
        $name = if ($v -is [string]) { [string]$v } else { [string](Get-CfgObjectProperty $v "name") }
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $set.Add($name) | Out-Null
    }
    return $set
}
function Get-CfgArrayField($cfg, [string]$name, [bool]$required, [System.Collections.Generic.List[string]]$errors) {
    $value = Get-CfgObjectProperty $cfg $name
    if ($null -eq $value) {
        if ($required) { $errors.Add(("skills.json 缺少 {0}" -f $name)) | Out-Null }
        return @()
    }
    if (Assert-IsArray $value) { return @($value) }
    if ($value -is [hashtable] -or $value -is [pscustomobject]) { return @($value) }
    $errors.Add(("skills.json 的 {0} 必须是数组" -f $name)) | Out-Null
    return @()
}
function Get-CfgContractErrors($cfg) {
    $errors = New-Object System.Collections.Generic.List[string]
    if ($null -eq $cfg) {
        $errors.Add("skills.json 为空或无法解析为对象") | Out-Null
        return @($errors.ToArray())
    }

    $vendors = Get-CfgArrayField $cfg "vendors" $true $errors
    $targets = Get-CfgArrayField $cfg "targets" $true $errors
    $mappings = Get-CfgArrayField $cfg "mappings" $false $errors
    $imports = Get-CfgArrayField $cfg "imports" $false $errors
    $mcpServers = Get-CfgArrayField $cfg "mcp_servers" $false $errors
    $mcpTargets = Get-CfgArrayField $cfg "mcp_targets" $false $errors

    foreach ($v in $vendors) {
        $name = [string](Get-CfgObjectProperty $v "name")
        $repo = [string](Get-CfgObjectProperty $v "repo")
        if ([string]::IsNullOrWhiteSpace($name)) { $errors.Add("vendor 缺少 name") | Out-Null }
        if ([string]::IsNullOrWhiteSpace($repo)) { $errors.Add(("vendor {0} 缺少 repo" -f $name)) | Out-Null }
    }

    foreach ($t in $targets) {
        $path = [string](Get-CfgObjectProperty $t "path")
        if ([string]::IsNullOrWhiteSpace($path)) { $errors.Add("target 缺少 path") | Out-Null }
    }

    foreach ($m in $mappings) {
        $vendor = [string](Get-CfgObjectProperty $m "vendor")
        $from = [string](Get-CfgObjectProperty $m "from")
        $to = [string](Get-CfgObjectProperty $m "to")
        if ([string]::IsNullOrWhiteSpace($vendor)) { $errors.Add("mapping 缺少 vendor") | Out-Null }
        if ([string]::IsNullOrWhiteSpace($from)) { $errors.Add("mapping 缺少 from") | Out-Null }
        if ([string]::IsNullOrWhiteSpace($to)) { $errors.Add("mapping 缺少 to") | Out-Null }
        if (-not [string]::IsNullOrWhiteSpace($from) -and -not (Test-SafeRelativePath $from -AllowDot)) {
            $errors.Add(("mapping.from 非法（仅允许相对路径，禁止 .. 与绝对路径）：{0}" -f $from)) | Out-Null
        }
        if (-not [string]::IsNullOrWhiteSpace($to) -and -not (Test-SafeRelativePath $to)) {
            $errors.Add(("mapping.to 非法（仅允许相对路径，禁止 .. 与绝对路径）：{0}" -f $to)) | Out-Null
        }
    }

    foreach ($i in $imports) {
        $name = [string](Get-CfgObjectProperty $i "name")
        $repo = [string](Get-CfgObjectProperty $i "repo")
        $skill = Normalize-SkillPath ([string](Get-CfgObjectProperty $i "skill"))
        $mode = [string](Get-CfgObjectProperty $i "mode")
        if ([string]::IsNullOrWhiteSpace($name)) { $errors.Add("import 缺少 name") | Out-Null }
        if ([string]::IsNullOrWhiteSpace($repo)) { $errors.Add("import 缺少 repo") | Out-Null }
        if (-not (Test-SafeRelativePath $skill -AllowDot)) {
            $errors.Add(("import.skill 非法（仅允许相对路径，禁止 .. 与绝对路径）：{0}" -f $skill)) | Out-Null
        }
        if (-not [string]::IsNullOrWhiteSpace($mode) -and $mode -ne "manual" -and $mode -ne "vendor") {
            $errors.Add(("import mode 仅支持 manual 或 vendor：{0}" -f $name)) | Out-Null
        }
    }

    foreach ($s in $mcpServers) {
        $name = [string](Get-CfgObjectProperty $s "name")
        $transport = [string](Get-CfgObjectProperty $s "transport")
        if ([string]::IsNullOrWhiteSpace($transport)) { $transport = "stdio" }
        if ([string]::IsNullOrWhiteSpace($name)) { $errors.Add("mcp_server 缺少 name") | Out-Null }
        if ($transport -ne "stdio" -and $transport -ne "sse" -and $transport -ne "http") {
            $errors.Add(("mcp_server.transport 仅支持 stdio/sse/http：{0}" -f $name)) | Out-Null
            continue
        }
        if ($transport -eq "stdio") {
            $command = [string](Get-CfgObjectProperty $s "command")
            if ([string]::IsNullOrWhiteSpace($command)) { $errors.Add(("mcp_server(stdio) 缺少 command：{0}" -f $name)) | Out-Null }
        }
        else {
            $url = [string](Get-CfgObjectProperty $s "url")
            if ([string]::IsNullOrWhiteSpace($url)) { $errors.Add(("mcp_server({0}) 缺少 url：{1}" -f $transport, $name)) | Out-Null }
        }
    }

    foreach ($mt in $mcpTargets) {
        if ($mt -is [string]) {
            if ([string]::IsNullOrWhiteSpace([string]$mt)) { $errors.Add("mcp_targets 不能包含空字符串") | Out-Null }
            continue
        }
        $path = [string](Get-CfgObjectProperty $mt "path")
        if ([string]::IsNullOrWhiteSpace($path)) { $errors.Add("mcp_targets 项缺少 path") | Out-Null }
    }

    $modeValue = [string](Get-CfgObjectProperty $cfg "sync_mode")
    if ([string]::IsNullOrWhiteSpace($modeValue)) { $modeValue = "link" }
    if ($modeValue -ne "link" -and $modeValue -ne "sync") {
        $errors.Add("sync_mode 仅支持 link 或 sync") | Out-Null
    }

    $vendorNames = New-CfgVendorNameSet $vendors
    foreach ($m in $mappings) {
        $vendor = [string](Get-CfgObjectProperty $m "vendor")
        if (-not [string]::IsNullOrWhiteSpace($vendor) -and -not $vendorNames.Contains($vendor)) {
            $errors.Add(("mapping 引用了不存在的 vendor：{0}" -f $vendor)) | Out-Null
        }
    }

    return @($errors.ToArray())
}
function Get-DuplicateValues([object[]]$items) {
    if ($null -eq $items) { return @() }
    return $items | Group-Object | Where-Object { $_.Count -gt 1 } | Select-Object -ExpandProperty Name
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

    $dupVendors = @(Get-DuplicateValues ($cfg.vendors | ForEach-Object { $_.name }))
    Need ($dupVendors.Count -eq 0) ("vendor 名称重复：{0}" -f ($dupVendors -join ", "))

    $dupImports = @(Get-DuplicateValues ($cfg.imports | ForEach-Object { $_.name }))
    Need ($dupImports.Count -eq 0) ("import 名称重复：{0}" -f ($dupImports -join ", "))

    $dupTargets = @(Get-DuplicateValues ($cfg.targets | ForEach-Object { $_.path }))
    if ($dupTargets.Count -gt 0) {
        Log ("目标路径重复（建议去重）：{0}" -f ($dupTargets -join ", ")) "WARN"
    }

    $dupTo = @(Get-DuplicateValues ($cfg.mappings | ForEach-Object { $_.to }))
    if ($dupTo.Count -gt 0) {
        Log ("mappings 的 to 重复（可能覆盖）：{0}" -f ($dupTo -join ", ")) "WARN"
    }

    $vendorNames = New-CfgVendorNameSet $cfg.vendors
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
        $oldRaw = if (Test-Path -LiteralPath $CfgPath) { Get-Content -LiteralPath $CfgPath -Raw } else { "" }
        Write-CfgChangeSummary $oldRaw $cfg
        $json = $cfg | ConvertTo-Json -Depth 50
        Set-ContentUtf8 $CfgPath $json
    }
}
function SaveCfgSafe($cfg, [string]$rawBackup) {
    if ($DryRun) { return }
    try {
        $oldRaw = $rawBackup
        if ([string]::IsNullOrWhiteSpace($oldRaw) -and (Test-Path -LiteralPath $CfgPath)) {
            $oldRaw = Get-Content -LiteralPath $CfgPath -Raw
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

function Get-ImportLockWorkspaceFingerprint([string]$repoPath) {
    Need (-not [string]::IsNullOrWhiteSpace($repoPath)) "repoPath 不能为空"
    Need (Test-Path -LiteralPath $repoPath) ("锁定失败：缺少 import 缓存目录 {0}" -f $repoPath)
    return (Get-DirectoryFingerprint $repoPath)
}

function Get-RepoHeadCommit([string]$repoPath) {
    Need (-not [string]::IsNullOrWhiteSpace($repoPath)) "repoPath 不能为空"
    Need (Test-Path -LiteralPath $repoPath) ("仓库目录不存在：{0}" -f $repoPath)
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
            $importEntry.workspace_fingerprint = Get-ImportLockWorkspaceFingerprint $repoPath
        }
        else {
            $importEntry.commit = Get-RepoHeadCommit $repoPath
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
    foreach ($v in @($lock.vendors)) {
        $path = VendorPath ([string]($v.name))
        $actual = Get-RepoHeadCommit $path
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

            $expectedFingerprint = [string](Get-CfgObjectProperty $i "workspace_fingerprint")
            Need (-not [string]::IsNullOrWhiteSpace($expectedFingerprint)) ("锁文件缺少 import 工作区指纹：{0}/{1}" -f $mode, [string]($i.name))
            $actualFingerprint = Get-ImportLockWorkspaceFingerprint $path
            Need ($actualFingerprint -eq $expectedFingerprint) ("import 内容不匹配：{0}/{1}（lock={2}, actual={3}）" -f $mode, [string]($i.name), $expectedFingerprint, $actualFingerprint)
            continue
        }

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
            $expectedFingerprint = [string](Get-CfgObjectProperty $i "workspace_fingerprint")
            Need (-not [string]::IsNullOrWhiteSpace($expectedFingerprint)) ("锁文件缺少 import 工作区指纹：manual/{0}" -f $name)
            $actualFingerprint = Get-ImportLockWorkspaceFingerprint $path
            Need ($actualFingerprint -eq $expectedFingerprint) ("import 内容不匹配：manual/{0}（lock={1}, actual={2}）" -f $name, $expectedFingerprint, $actualFingerprint)
            continue
        }

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
    $events = New-Object System.Collections.Generic.List[object]
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
        $events.Add([pscustomobject]@{
            metric = $metric
            duration_ms = $duration
            ts = [string]$record.ts
        }) | Out-Null
    }
    if ($events.Count -eq 0) { return @() }

    $summary = New-Object System.Collections.Generic.List[object]
    $groups = $events | Group-Object metric
    foreach ($g in $groups) {
        $recent = $g.Group | Select-Object -Last $RecentPerMetric
        if ($recent.Count -eq 0) { continue }
        $avg = [math]::Round((($recent | Measure-Object -Property duration_ms -Average).Average), 0)
        $last = ($recent | Select-Object -Last 1)
        $summary.Add([pscustomobject]@{
            metric = $g.Name
            samples = @($recent).Count
            avg_ms = [int]$avg
            last_ms = [int]$last.duration_ms
            last_ts = [string]$last.ts
        }) | Out-Null
    }
    return ($summary | Sort-Object metric)
}

function Get-DoctorGitVersion([switch]$NoHostLog) {
    if ($DryRun -or $NoHostLog) {
        $gitOut = & git version 2>$null
        if ($LASTEXITCODE -ne 0 -or $null -eq $gitOut) { throw "git version failed" }
        return (($gitOut | Select-Object -First 1).ToString().Trim())
    }
    return (Invoke-GitCapture @("version"))
}

function Get-DoctorOsDescription {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        if ($os -and -not [string]::IsNullOrWhiteSpace([string]$os.Caption)) {
            return ("{0} {1}" -f [string]$os.Caption, [string]$os.OSArchitecture).Trim()
        }
    }
    catch {}

    try {
        $description = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
        $architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
        if (-not [string]::IsNullOrWhiteSpace([string]$description)) {
            return ("{0} {1}" -f [string]$description, [string]$architecture).Trim()
        }
    }
    catch {}

    return $null
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
        $vendors = if ($cfg.PSObject.Properties.Match("vendors").Count -gt 0 -and $cfg.vendors -ne $null) { @($cfg.vendors) } else { @() }
        $vendorSet = New-CfgVendorNameSet $vendors

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
        # Update flow is network-heavy but should still surface regressions in doctor warnings.
        "update_vendor" { return 60000 }
        "update_imports" { return 180000 }
        "update_total" { return 240000 }
        # One-click workflows may include target-repo audit scans; keep this stricter than update_total but above normal audit smoke time.
        "workflow_run" { return 30000 }
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
        if ($last -gt $metricThreshold -or $avg -gt $metricThreshold) {
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

    $vendors = if ($cfg.PSObject.Properties.Match("vendors").Count -gt 0 -and $cfg.vendors -ne $null) { @($cfg.vendors) } else { @() }
    $vendorSet = New-CfgVendorNameSet $vendors
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
        $osText = Get-DoctorOsDescription
        if ([string]::IsNullOrWhiteSpace([string]$osText)) { throw "OS detection returned empty" }
        $report.checks.os = $osText
        if (-not $opts.json) { Write-Host ("OS: {0}" -f $osText) }
    }
    catch {
        $report.checks.os = "unknown"
        if (-not $opts.json) { Write-Host "OS: unknown（读取失败）" -ForegroundColor Yellow }
    }

    # 2. Git Check
    try {
        $gitVer = Get-DoctorGitVersion -NoHostLog:$opts.json
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
            # Keep parser behavior aligned with LoadCfg:
            # support whole-line comments in skills.json.
            $rawCfg = Get-Content $CfgPath -Raw
            $cleanCfg = $rawCfg -replace "(?m)^\s*//.*", ""
            $cfg = $cleanCfg | ConvertFrom-Json
            if ($cfg) {
                $contractErrors = @(Get-CfgContractErrors $cfg)
                if ($contractErrors.Count -gt 0) {
                    $report.checks.config = [ordered]@{
                        ok = $false
                        reason = ("contract_error: {0}" -f ($contractErrors -join " | "))
                        errors = @($contractErrors)
                    }
                    if (-not $opts.json) {
                        Write-Host "❌ skills.json: Contract Error" -ForegroundColor Red
                        foreach ($err in $contractErrors) {
                            Write-Host ("   - {0}" -f $err) -ForegroundColor Red
                        }
                    }
                    $pass = $false
                }
                else {
                    $cfgObj = $cfg
                    $report.checks.config = [ordered]@{ ok = $true; vendors = @($cfg.vendors).Count; mappings = @($cfg.mappings).Count }
                    if (-not $opts.json) {
                        Write-Host "✅ skills.json: Valid JSON + contract" -ForegroundColor Green
                        Write-Host ("   - Vendors: {0}" -f @($cfg.vendors).Count)
                        Write-Host ("   - Mappings: {0}" -f @($cfg.mappings).Count)
                    }
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
            $lines = Get-Content $LogPath -Tail 5000 -ErrorAction SilentlyContinue
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
        elseif ($reason -like "contract_error*") { $report.summary.errors += "config_contract_error" }
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

function Get-AddImportPlanFromParsedArgs($parsed) {
    Need ($null -ne $parsed) "parsed add args 不能为空"

    $repo = Normalize-RepoUrl $parsed.repo
    $ref = [string]$parsed.ref
    $refIsAuto = $false
    if ([string]::IsNullOrWhiteSpace($ref)) {
        $ref = "main"
        $refIsAuto = $true
    }

    $mode = [string]$parsed.mode
    if ([string]::IsNullOrWhiteSpace($mode)) { $mode = "manual" }
    $mode = $mode.ToLowerInvariant()
    Need ($mode -eq "manual" -or $mode -eq "vendor") "mode 仅支持 manual 或 vendor"

    $registerVendorOnly = (-not [bool]$parsed.skillSpecified -and -not [bool]$parsed.modeSpecified)
    if ($registerVendorOnly) { $mode = "vendor" }

    return [pscustomobject]@{
        repo = $repo
        ref = $ref
        refIsAuto = $refIsAuto
        mode = $mode
        registerVendorOnly = $registerVendorOnly
        sparse = [bool]$parsed.sparse
    }
}

function Add-ImportFromArgs([string[]]$tokens, [switch]$NoBuild) {
    Preflight
    $cfgRaw = ""
    $cfg = LoadCfg
    if (Test-Path $CfgPath) { $cfgRaw = Get-Content $CfgPath -Raw }

    $resolvedTokens = Resolve-AddTokensFromAnyFormat $tokens
    if ($resolvedTokens) { $tokens = $resolvedTokens }
    $parsed = Parse-AddArgs $tokens
    $plan = Get-AddImportPlanFromParsedArgs $parsed
    $repo = $plan.repo
    $ref = $plan.ref
    $refIsAuto = [bool]$plan.refIsAuto
    $mode = $plan.mode
    $registerVendorOnly = [bool]$plan.registerVendorOnly
    $sparse = [bool]$plan.sparse

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
    if (-not (Get-Variable -Name SkillListCache -Scope Script -ErrorAction SilentlyContinue)) { $script:SkillListCache = @{} }
    if ($null -eq $script:SkillListCache) { $script:SkillListCache = @{} }
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

function Get-InvalidMappings($cfg = $null) {
    if ($null -eq $cfg) { $cfg = LoadCfg }
    $invalid = New-Object System.Collections.Generic.List[object]
    $mappings = @($cfg.mappings)
    for ($idx = 0; $idx -lt $mappings.Count; $idx++) {
        $m = $mappings[$idx]
        if ($null -eq $m) { continue }
        if (-not (Should-SyncMappingToAgent $m)) { continue }

        $vendor = [string]$m.vendor
        $from = [string]$m.from
        $to = [string]$m.to
        $src = $null
        $reason = $null
        try {
            if (-not (Test-SafeRelativePath $from -AllowDot)) {
                $reason = "非法 mapping.from"
            }
            elseif (-not (Test-SafeRelativePath $to)) {
                $reason = "非法 mapping.to"
            }
            elseif ($vendor -eq "manual") {
                $src = Resolve-ManualImportSkillPath $cfg $from -AllowLegacyFallback
                if ([string]::IsNullOrWhiteSpace($src)) {
                    $reason = "manual 导入不存在或无效"
                }
            }
            else {
                $base = Resolve-SourceBase $vendor $cfg
                $src = Join-Path $base $from
                if (-not (Is-PathInsideOrEqual $src $base)) {
                    $reason = "mapping.from 越界"
                }
            }
        }
        catch {
            $reason = $_.Exception.Message
        }

        if ([string]::IsNullOrWhiteSpace($reason)) {
            if (-not (Test-Path -LiteralPath $src -PathType Container)) {
                $reason = "源目录不存在"
            }
            elseif (-not (Test-IsSkillDir $src)) {
                $reason = "缺少标记文件"
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($reason)) {
            $invalid.Add([pscustomobject]@{
                    index = $idx
                    vendor = $vendor
                    from = $from
                    to = $to
                    src = [string]$src
                    reason = $reason
                }) | Out-Null
        }
    }
    return $invalid.ToArray()
}

function Parse-CleanupInvalidMappingsArgs([string[]]$tokens) {
    $result = [ordered]@{
        yes = $false
        no_build = $false
    }
    foreach ($t in @($tokens)) {
        if ([string]::IsNullOrWhiteSpace([string]$t)) { continue }
        switch (([string]$t).Trim().ToLowerInvariant()) {
            "--yes" { $result.yes = $true; continue }
            "--no-build" { $result.no_build = $true; continue }
            default { throw ("未知参数：{0}（支持 --yes, --no-build）" -f [string]$t) }
        }
    }
    return [pscustomobject]$result
}

function 清理无效映射([string[]]$tokens = @()) {
    $opts = Parse-CleanupInvalidMappingsArgs $tokens
    $cfg = LoadCfg
    $invalid = @(Get-InvalidMappings $cfg)
    if ($invalid.Count -eq 0) {
        Write-Host "未发现失效 mappings。"
        return
    }

    $preview = @()
    foreach ($item in $invalid) {
        $preview += ("[{0}] {1} -> {2} ({3})" -f [string]$item.vendor, [string]$item.from, [string]$item.to, [string]$item.reason)
    }
    if (-not $opts.yes) {
        if (-not (Confirm-WithSummary "将删除以下失效 mappings" $preview "确认删除并写回 skills.json？" "Y")) {
            Write-Host "已取消清理。"
            return
        }
    }

    if (Skip-IfDryRun "清理无效映射") {
        Write-Host ("DRYRUN：预计删除失效 mappings {0} 项。" -f $invalid.Count)
        return
    }

    $dropIndexes = New-Object System.Collections.Generic.HashSet[int]
    foreach ($item in $invalid) { $dropIndexes.Add([int]$item.index) | Out-Null }
    $nextMappings = New-Object System.Collections.Generic.List[object]
    $all = @($cfg.mappings)
    for ($i = 0; $i -lt $all.Count; $i++) {
        if ($dropIndexes.Contains($i)) { continue }
        $nextMappings.Add($all[$i]) | Out-Null
    }
    $cfg.mappings = @($nextMappings)
    SaveCfg $cfg
    Clear-SkillsCache

    Write-Host ("已清理失效 mappings：{0} 项。" -f $invalid.Count) -ForegroundColor Green
    if (-not $opts.no_build) {
        Write-Host "开始【构建生效】..." -ForegroundColor Cyan
        构建生效
    }
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
    $items = @($items)
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
    if (Test-PathEntry $AgentDir) {
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
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @{} }
    try {
        $raw = Get-Content -LiteralPath $path -Raw
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
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return "missing" }
    $files = Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName
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
        $invalidMappings = New-Object System.Collections.Generic.List[object]
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
                    $invalidReason = if (-not (Test-Path -LiteralPath $src -PathType Container)) { "源目录不存在" } else { "缺少标记文件" }
                    Write-Host ("⚠️ 跳过无效技能（{0}）：{1}" -f $invalidReason, $src) -ForegroundColor Yellow
                    $invalidMappings.Add([pscustomobject]@{
                            vendor = [string]$m.vendor
                            from = [string]$m.from
                            to = [string]$m.to
                            src = [string]$src
                            reason = $invalidReason
                        }) | Out-Null
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
        if ($invalidMappings.Count -gt 0) {
            Log ("检测到 {0} 条失效 mappings（源目录不存在或缺少标记文件），建议清理 skills.json。" -f $invalidMappings.Count) "WARN"
            Write-Host ("⚠️ 检测到 {0} 条失效 mappings（未参与同步）。" -f $invalidMappings.Count) -ForegroundColor Yellow
            $preview = @($invalidMappings | Select-Object -First 10)
            foreach ($item in $preview) {
                Write-Host ("   - [{0}] {1} -> {2} ({3})" -f [string]$item.vendor, [string]$item.from, [string]$item.to, [string]$item.reason) -ForegroundColor Yellow
            }
            if ($invalidMappings.Count -gt $preview.Count) {
                Write-Host ("   ... 另有 {0} 条未显示" -f ($invalidMappings.Count - $preview.Count)) -ForegroundColor Yellow
            }
            Write-Host "   建议：删除上述 mappings 后再执行【构建生效】。" -ForegroundColor Yellow
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
        if (@($optChanges).Count -gt 0) {
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
            if ($buildFailures -and @($buildFailures).Count -gt 0) {
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
        if (@($failures).Count -gt 0) {
            throw ("构建生效失败（{0} 项）：{1}" -f @($failures).Count, [string]@($failures)[0])
        }
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

function Test-WindowsInvalidPathIssue([string]$message) {
    if ([string]::IsNullOrWhiteSpace($message)) { return $false }
    if ($message -notmatch "invalid path") { return $false }
    return ($message -match "git\s+(pull|checkout|reset)")
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
    $paths = @($paths | Select-Object -Unique | Where-Object { Test-IsGitRepoRoot ([string]$_) })
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
    if ([string]::IsNullOrWhiteSpace($repo)) { return $null }
    if (Test-LocalZipRepoInput $repo) {
        return ("zip:{0}" -f (Get-FileContentHash $repo))
    }
    $targetRef = if ([string]::IsNullOrWhiteSpace($ref)) { "main" } else { $ref }
    $candidates = @(
        $targetRef,
        ("refs/heads/{0}" -f $targetRef),
        ("refs/tags/{0}^{{}}" -f $targetRef),
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
                    $null = Ensure-Repo $cache $repo $ref $sparsePath $forceClean $false (-not $SkipFetch)
                }
                catch {
                    if ((Test-WindowsInvalidPathIssue $_.Exception.Message) -and $gitSkillPath -ne ".") {
                        $invalidPathForceClean = $forceClean
                        if (-not $invalidPathForceClean -and (Test-Path -LiteralPath $cache)) {
                            $expectedSrc = if ($skillPath -eq ".") { $cache } else { Join-Path $cache $skillPath }
                            if (-not (Test-IsSkillDir $expectedSrc)) {
                                $invalidPathForceClean = $true
                                Log ("导入缓存已不可用，非法路径回退临时启用强制清理：{0} [{1}]" -f $name, $repo) "WARN"
                            }
                        }
                        $fallbackDone = $false
                        $sparseFallbackError = $null
                        if (-not $sparse) {
                            try {
                                $fallbackSparsePath = $gitSkillPath
                                Log ("导入更新检测到 Windows 非法路径，先回退为 sparse checkout：{0} [{1}] -> {2}" -f $name, $repo, $fallbackSparsePath) "WARN"
                                $null = Ensure-Repo $cache $repo $ref $fallbackSparsePath $invalidPathForceClean $false (-not $SkipFetch)
                                $sparse = $true
                                $sparsePath = $fallbackSparsePath
                                if (-not [bool]$i.sparse) {
                                    $i.sparse = $true
                                    $cfgChanged = $true
                                }
                                $fallbackDone = $true
                            }
                            catch {
                                $sparseFallbackError = $_.Exception.Message
                                Log ("sparse checkout 回退失败，改用归档回退：{0} [{1}]；原因：{2}" -f $name, $repo, $sparseFallbackError) "WARN"
                            }
                        }
                        if (-not $fallbackDone) {
                            try {
                                Ensure-RepoFromGitArchive $cache $repo $ref $skillPath $invalidPathForceClean | Out-Null
                                Log ("导入更新已回退为 git archive：{0} [{1}] -> {2}" -f $name, $repo, $skillPath) "WARN"
                                $fallbackDone = $true
                            }
                            catch {
                                $archiveError = $_.Exception.Message
                                try {
                                    Ensure-RepoFromGitHubTreeSnapshot $cache $repo $ref $skillPath $invalidPathForceClean | Out-Null
                                    Log ("导入更新已回退为 GitHub tree 快照：{0} [{1}] -> {2}" -f $name, $repo, $skillPath) "WARN"
                                    $fallbackDone = $true
                                }
                                catch {
                                    $snapshotError = $_.Exception.Message
                                    $prefix = if ([string]::IsNullOrWhiteSpace($sparseFallbackError)) { "" } else { ("sparse={0} | " -f $sparseFallbackError) }
                                    throw ("Windows 非法路径回退失败：{0}archive={1} | snapshot={2}" -f $prefix, $archiveError, $snapshotError)
                                }
                            }
                        }
                        if (-not $fallbackDone) { throw }
                    }
                    else {
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

function Extract-McpTrailingDryRunToken([string[]]$tokens) {
    $list = @($tokens)
    if ($list.Count -eq 0) {
        return [pscustomobject]@{
            tokens = @()
            dry_run = $false
        }
    }
    $last = [string]$list[$list.Count - 1]
    $tail = $last.Trim().ToLowerInvariant()
    if ($tail -eq "-dryrun" -or $tail -eq "--dryrun" -or $tail -eq "--dry-run") {
        $trimmed = @()
        if ($list.Count -gt 1) {
            $trimmed = @($list[0..($list.Count - 2)])
        }
        return [pscustomobject]@{
            tokens = $trimmed
            dry_run = $true
        }
    }
    return [pscustomobject]@{
        tokens = $list
        dry_run = $false
    }
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

function Get-CodexMcpStartupTimeoutSec($server) {
    if ($null -eq $server) { return $null }
    if ($server.PSObject.Properties.Match("startup_timeout_sec").Count -eq 0) { return $null }

    $raw = $server.startup_timeout_sec
    if ($null -eq $raw -or [string]::IsNullOrWhiteSpace([string]$raw)) { return $null }

    $parsed = 0
    if (-not [int]::TryParse([string]$raw, [ref]$parsed) -or $parsed -lt 1) {
        Log ("mcp_server.startup_timeout_sec 无效，已忽略：{0}" -f [string]$server.name) "WARN"
        return $null
    }
    return [int]$parsed
}

function Convert-McpServersToCodexConfigMap($servers) {
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

        $startupTimeoutSec = Get-CodexMcpStartupTimeoutSec $s
        if ($null -ne $startupTimeoutSec) {
            $entry.startup_timeout_sec = [int]$startupTimeoutSec
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

    $managedMap = Convert-McpServersToConfigMap $servers
    # MCP 同步以 skills.json 为唯一真源，避免卸载后残留旧项。
    $base["mcpServers"] = $managedMap
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

function Resolve-ExternalCommandInvocation([string]$command, [string[]]$commandArgs = @()) {
    Need (-not [string]::IsNullOrWhiteSpace($command)) "外部命令名不能为空"
    $resolved = @(Get-Command $command -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($resolved.Count -gt 0 -and $null -ne $resolved[0]) {
        $resolvedPath = [string]$resolved[0].Path
        if (-not [string]::IsNullOrWhiteSpace($resolvedPath)) {
            $ext = [System.IO.Path]::GetExtension($resolvedPath).ToLowerInvariant()
            if ($ext -eq ".ps1") {
                return [pscustomobject]@{
                    file = Resolve-PowerShellExecutable
                    args = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $resolvedPath) + @($commandArgs)
                }
            }
            return [pscustomobject]@{
                file = $resolvedPath
                args = @($commandArgs)
            }
        }
    }

    return [pscustomobject]@{
        file = $command
        args = @($commandArgs)
    }
}

function Get-ExternalCommandCapturedOutput([string]$outFile, [string]$errFile) {
    $outText = if (Test-Path -LiteralPath $outFile -PathType Leaf) { Get-Content -Raw -LiteralPath $outFile } else { "" }
    $errText = if (Test-Path -LiteralPath $errFile -PathType Leaf) { Get-Content -Raw -LiteralPath $errFile } else { "" }
    $combined = New-Object System.Collections.Generic.List[string]
    foreach ($line in @((($outText + "`n" + $errText) -split "`r?`n"))) {
        if ($null -ne $line -and $line -ne "") { $combined.Add([string]$line) | Out-Null }
    }
    return [pscustomobject]@{
        output = @($combined)
        error = if ([string]::IsNullOrWhiteSpace($errText)) { "" } else { $errText.Trim() }
    }
}

function Invoke-ExternalCommandWithTimeout(
    [string]$command,
    [Alias("args")]
    [string[]]$CommandArgs = @(),
    [string]$workingDir = $null,
    [int]$timeoutSeconds = 30
) {
    Need (-not [string]::IsNullOrWhiteSpace($command)) "外部命令名不能为空"
    if ($timeoutSeconds -lt 1) { $timeoutSeconds = 1 }

    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    $proc = $null
    try {
        $effectiveWorkingDir = if ([string]::IsNullOrWhiteSpace($workingDir)) { $PWD.Path } else { $workingDir }
        $invocation = Resolve-ExternalCommandInvocation $command @($CommandArgs)
        $argList = @($invocation.args | ForEach-Object { [string]$_ })
        $proc = Start-Process -FilePath ([string]$invocation.file) -ArgumentList $argList -PassThru -WindowStyle Hidden -RedirectStandardOutput $outFile -RedirectStandardError $errFile -WorkingDirectory $effectiveWorkingDir
        $exited = $proc.WaitForExit($timeoutSeconds * 1000)
        if (-not $exited) {
            try { $proc.Kill($true) } catch { try { $proc.Kill() } catch {} }
            try { $proc.WaitForExit(2000) | Out-Null } catch {}
            $captured = Get-ExternalCommandCapturedOutput $outFile $errFile
            return [pscustomobject]@{
                timed_out = $true
                exit_code = 124
                output = @($captured.output)
                error = if ([string]::IsNullOrWhiteSpace([string]$captured.error)) { ("timeout_after_{0}s" -f $timeoutSeconds) } else { ("timeout_after_{0}s: {1}" -f $timeoutSeconds, [string]$captured.error) }
            }
        }

        $captured = Get-ExternalCommandCapturedOutput $outFile $errFile

        return [pscustomobject]@{
            timed_out = $false
            exit_code = [int]$proc.ExitCode
            output = @($captured.output)
            error = [string]$captured.error
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
        if ($null -ne $proc) { $proc.Dispose() }
        Remove-Item -LiteralPath $outFile -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $errFile -ErrorAction SilentlyContinue
    }
}

function Resolve-TimeoutSecondsFromEnv([string]$envName, [int]$defaultSeconds, [int]$minSeconds = 1, [int]$maxSeconds = 600) {
    $value = $defaultSeconds
    if ([string]::IsNullOrWhiteSpace($envName)) { return $value }

    $raw = [System.Environment]::GetEnvironmentVariable($envName)
    $parsed = 0
    if ([int]::TryParse([string]$raw, [ref]$parsed)) {
        $value = $parsed
    }

    if ($value -lt $minSeconds) { $value = $minSeconds }
    if ($value -gt $maxSeconds) { $value = $maxSeconds }
    return $value
}

function Test-EnvFlagEnabled([string]$envName) {
    if ([string]::IsNullOrWhiteSpace($envName)) { return $false }
    $raw = [System.Environment]::GetEnvironmentVariable($envName)
    if ([string]::IsNullOrWhiteSpace([string]$raw)) { return $false }
    $v = ([string]$raw).Trim().ToLowerInvariant()
    return ($v -eq "1" -or $v -eq "true" -or $v -eq "yes" -or $v -eq "on")
}

function Should-RunNativeMcpSync() {
    return (Test-EnvFlagEnabled "SKILLS_MCP_NATIVE_SYNC")
}

function Should-VerifyLiveMcpCli() {
    return (Test-EnvFlagEnabled "SKILLS_MCP_VERIFY_LIVE_CLI")
}

function Get-McpListVerifyTimeoutSeconds([string]$cli) {
    $cliName = if ([string]::IsNullOrWhiteSpace($cli)) { "" } else { [string]$cli.Trim().ToLowerInvariant() }
    $defaultSeconds = switch ($cliName) {
        "gemini" { 18 }
        "claude" { 45 }
        "codex" { 45 }
        default { 30 }
    }

    $globalTimeout = Resolve-TimeoutSecondsFromEnv "SKILLS_MCP_VERIFY_LIST_TIMEOUT_SECONDS" $defaultSeconds 1 600
    $envSuffix = if ([string]::IsNullOrWhiteSpace($cliName)) { "DEFAULT" } else { $cliName.ToUpperInvariant() }
    $perCliVar = "SKILLS_MCP_VERIFY_LIST_TIMEOUT_SECONDS_{0}" -f $envSuffix
    return (Resolve-TimeoutSecondsFromEnv $perCliVar $globalTimeout 1 600)
}

function Should-VerifyGeminiCli() {
    return (Test-EnvFlagEnabled "SKILLS_MCP_VERIFY_GEMINI_CLI")
}

function Get-NativeMcpCommandTimeoutSeconds() {
    return (Resolve-TimeoutSecondsFromEnv "SKILLS_MCP_NATIVE_TIMEOUT_SECONDS" 30 1 600)
}

function Invoke-ExternalCommandCapture(
    [string]$command,
    [Alias("args")]
    [string[]]$CommandArgs = @(),
    [int]$timeoutSeconds = 120
) {
    $result = Invoke-ExternalCommandWithTimeout $command @($CommandArgs) $null $timeoutSeconds
    return [pscustomobject]@{
        command = $command
        args = @($CommandArgs)
        exit_code = [int]$result.exit_code
        timed_out = [bool]$result.timed_out
        error = [string]$result.error
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

function Mask-SensitiveMcpCommandText([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $text }
    $masked = [string]$text
    $masked = [regex]::Replace($masked, '(?i)(Authorization\s*[:=]\s*Bearer\s+)([^"\s]+)', '$1<redacted>')
    $masked = [regex]::Replace($masked, '(?i)\bgithub_pat_[A-Za-z0-9_]+\b', '<redacted>')
    $masked = [regex]::Replace($masked, '(?i)\bgh[pousr]_[A-Za-z0-9_]+\b', '<redacted>')
    return $masked
}

function Test-IsNonInteractiveMcpError([string]$text) {
    if ([string]::IsNullOrWhiteSpace([string]$text)) { return $false }
    $normalized = ([string]$text).Trim()
    $hints = @(
        "stdout is not a terminal",
        "Input must be provided either through stdin",
        "No input provided via stdin",
        "when using --print"
    )
    foreach ($hint in $hints) {
        if ($normalized -like ("*{0}*" -f $hint)) { return $true }
    }
    return $false
}

function Test-CliMcpServerReady([string]$cli, [string[]]$expectedServers) {
    $cliName = if ([string]::IsNullOrWhiteSpace($cli)) { "" } else { [string]$cli.Trim().ToLowerInvariant() }
    $isGemini = ($cliName -eq "gemini")
    if ($null -eq $expectedServers -or $expectedServers.Count -eq 0) {
        return [pscustomobject]@{
            cli = $cli
            ok = $true
            reason = "no_expected_servers"
            missing = @()
            raw = @()
        }
    }
    if ($isGemini -and -not (Should-VerifyGeminiCli)) {
        return [pscustomobject]@{
            cli = $cli
            ok = $true
            reason = "gemini_cli_verification_skipped"
            missing = @()
            raw = @()
        }
    }
    if (-not (Get-Command $cli -ErrorAction SilentlyContinue)) {
        if ($isGemini) {
            return [pscustomobject]@{
                cli = $cli
                ok = $true
                reason = "gemini_cli_not_found_fallback"
                missing = @()
                raw = @()
            }
        }
        return [pscustomobject]@{
            cli = $cli
            ok = $false
            reason = "cli_not_found"
            missing = @($expectedServers)
            raw = @()
        }
    }

    $listTimeoutSeconds = Get-McpListVerifyTimeoutSeconds $cli
    $result = Invoke-ExternalCommandCapture $cli @("mcp", "list") $listTimeoutSeconds
    $raw = @($result.output | ForEach-Object { Remove-AnsiEscapeSequences ([string]$_) })
    if ($result.timed_out) {
        if ($isGemini) {
            return [pscustomobject]@{
                cli = $cli
                ok = $true
                reason = ("gemini_cli_timeout_fallback_{0}s" -f $listTimeoutSeconds)
                missing = @()
                raw = $raw
            }
        }
        return [pscustomobject]@{
            cli = $cli
            ok = $false
            reason = ("timeout_after_{0}s" -f $listTimeoutSeconds)
            missing = @($expectedServers)
            raw = $raw
        }
    }

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

    if (-not (Should-VerifyLiveMcpCli)) {
        foreach ($target in $targets) {
            Log ("MCP 配置态校验通过：{0} -> {1}" -f $target.cli, ((@($target.names)) -join ", "))
        }
        Log "跨 CLI MCP live 校验默认跳过；如需实机 mcp list 校验，设置 SKILLS_MCP_VERIFY_LIVE_CLI=1。" "INFO"
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
    if (-not (Should-RunNativeMcpSync)) {
        Log "原生 Claude MCP 注册默认跳过；已写入配置文件。如需执行 claude mcp add/remove，设置 SKILLS_MCP_NATIVE_SYNC=1。" "INFO"
        return
    }
    if (-not (Get-Command "claude" -ErrorAction SilentlyContinue)) {
        Log "未检测到 claude 命令，已跳过原生 MCP 同步（仅写入 .mcp.json）。" "WARN"
        return
    }
    if ($script:SkipNativeMcpForSession) {
        Log "已检测到原生 MCP CLI 非交互不可用，本轮跳过后续原生 MCP 同步。" "WARN"
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
                $safeCmdText = Mask-SensitiveMcpCommandText $cmdText
                Write-Host ("DRYRUN：将执行原生 MCP 同步 -> {0}" -f $safeCmdText)
                continue
            }
            $timeoutSeconds = Get-NativeMcpCommandTimeoutSeconds
            $native = Invoke-ExternalCommandWithTimeout "claude" @($args) $script:Root $timeoutSeconds
            if ($native.timed_out) {
                Log ("原生 MCP 同步超时（已忽略）：{0}（scope={1}，timeout={2}s）" -f [string]$s.name, $scope, $timeoutSeconds) "WARN"
                continue
            }
            if ($native.exit_code -ne 0) {
                Log ("原生 MCP 同步失败（已忽略）：{0}（scope={1}，exit={2}）{3}" -f [string]$s.name, $scope, $native.exit_code, $native.error) "WARN"
                if (Test-IsNonInteractiveMcpError ([string]$native.error)) {
                    $script:SkipNativeMcpForSession = $true
                    Log "检测到原生 MCP CLI 在非交互环境不可用，已停止本轮后续原生 MCP 同步。" "WARN"
                    break
                }
                continue
            }
            Log ("已同步原生 MCP：{0}（scope={1}）" -f [string]$s.name, $scope)
        }
        catch {
            Log ("原生 MCP 同步失败（已忽略）：{0}（scope={1}） -> {2}" -f [string]$s.name, $scope, $_.Exception.Message) "WARN"
            if (Test-IsNonInteractiveMcpError $_.Exception.Message) {
                $script:SkipNativeMcpForSession = $true
                Log "检测到原生 MCP CLI 在非交互环境不可用，已停止本轮后续原生 MCP 同步。" "WARN"
                break
            }
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
    if (-not (Should-RunNativeMcpSync)) {
        Log ("原生 Claude MCP 清理默认跳过：{0}。如需执行 claude mcp remove，设置 SKILLS_MCP_NATIVE_SYNC=1。" -f $name) "INFO"
        return
    }
    if ($script:SkipNativeMcpForSession) {
        Log ("已检测到原生 MCP CLI 非交互不可用，跳过清理：{0}" -f $name) "WARN"
        return
    }
    $ops = Get-NativeMcpCleanupCommands $name
    foreach ($op in $ops) {
        if (-not (Get-Command $op.command -ErrorAction SilentlyContinue)) { continue }
        $cmdText = "{0} {1}" -f $op.command, (($op.args | ForEach-Object { [string]$_ }) -join " ")
        if ($DryRun) {
            Write-Host ("DRYRUN：清理原生 MCP -> {0}" -f $cmdText)
            continue
        }
        try {
            $timeoutSeconds = Get-NativeMcpCommandTimeoutSeconds
            $workingDir = if ($op.project) { $script:Root } else { $null }
            $native = Invoke-ExternalCommandWithTimeout ([string]$op.command) @($op.args) $workingDir $timeoutSeconds
            if ($native.timed_out) {
                Log ("原生 MCP 清理超时（已忽略）：{0}（timeout={1}s）" -f $cmdText, $timeoutSeconds) "WARN"
                continue
            }
            if ($native.exit_code -ne 0) {
                Log ("原生 MCP 清理失败（已忽略）：{0}（exit={1}）{2}" -f $cmdText, $native.exit_code, $native.error) "WARN"
                if (Test-IsNonInteractiveMcpError ([string]$native.error)) {
                    $script:SkipNativeMcpForSession = $true
                    Log "检测到原生 MCP CLI 在非交互环境不可用，已停止本轮后续原生 MCP 清理。" "WARN"
                    break
                }
                continue
            }
            Log ("已执行原生 MCP 清理：{0}" -f $cmdText)
        }
        catch {
            Log ("原生 MCP 清理失败（已忽略）：{0} -> {1}" -f $cmdText, $_.Exception.Message) "WARN"
            if (Test-IsNonInteractiveMcpError $_.Exception.Message) {
                $script:SkipNativeMcpForSession = $true
                Log "检测到原生 MCP CLI 在非交互环境不可用，已停止本轮后续原生 MCP 清理。" "WARN"
                break
            }
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

    $managedMap = Convert-McpServersToGeminiConfigMap $servers
    # Gemini 同步以 skills.json 为唯一真源，避免卸载后残留旧项。
    $base["mcpServers"] = $managedMap
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
    $codexServers = @()
    $skippedGithubForMissingToken = $false
    $hasGithubToken = -not [string]::IsNullOrWhiteSpace($env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN) -or -not [string]::IsNullOrWhiteSpace($env:GITHUB_PERSONAL_ACCESS_TOKEN)
    if ([string]::IsNullOrWhiteSpace($env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN) -and -not [string]::IsNullOrWhiteSpace($env:GITHUB_PERSONAL_ACCESS_TOKEN)) {
        $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN = [string]$env:GITHUB_PERSONAL_ACCESS_TOKEN
    }
    foreach ($server in @($servers)) {
        if ($null -eq $server) { continue }
        if ([string]::Equals([string]$server.name, "github", [System.StringComparison]::OrdinalIgnoreCase)) {
            if (-not $hasGithubToken) {
                Log "Codex 检测到 GitHub MCP 但缺少 CODEX_GITHUB_PERSONAL_ACCESS_TOKEN（或 GITHUB_PERSONAL_ACCESS_TOKEN），已跳过同步以避免影响启动。" "WARN"
                $skippedGithubForMissingToken = $true
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

    $managedMap = Convert-McpServersToCodexConfigMap $codexServers
    $managedNames = @($managedMap.PSObject.Properties.Name | Sort-Object)
    $preserveExistingMcpSections = ($managedNames.Count -eq 0 -and $skippedGithubForMissingToken)

    $kept = New-Object System.Collections.Generic.List[string]
    if ($preserveExistingMcpSections) {
        foreach ($line in $lines) {
            $kept.Add($line) | Out-Null
        }
    }
    else {
        $skipMcpSection = $false
        foreach ($line in $lines) {
            if ($line -match '^\s*\[mcp_servers\.[^\]]+\]\s*$') {
                $skipMcpSection = $true
                continue
            }

            if ($skipMcpSection -and $line -match '^\s*\[[^\]]+\]\s*$') {
                $skipMcpSection = $false
                $kept.Add($line) | Out-Null
                continue
            }

            if (-not $skipMcpSection) {
                $kept.Add($line) | Out-Null
            }
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
    $trailingDryRun = Extract-McpTrailingDryRunToken $tokenList
    $tokenList = @($trailingDryRun.tokens)
    if (-not $DryRun -and [bool]$trailingDryRun.dry_run) {
        $script:DryRun = $true
        Write-Host "检测到尾部 -DryRun 参数，已切换为预演模式。"
    }
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

    if ($DryRun) {
        if ($replaced) {
            Write-Host ("DRYRUN：将更新 MCP 服务：{0}" -f $server.name)
        }
        else {
            Write-Host ("DRYRUN：将安装 MCP 服务：{0}" -f $server.name)
        }
    }
    elseif ($replaced) {
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
    $trailingDryRun = Extract-McpTrailingDryRunToken $tokenList
    $tokenList = @($trailingDryRun.tokens)
    if (-not $DryRun -and [bool]$trailingDryRun.dry_run) {
        $script:DryRun = $true
        Write-Host "检测到尾部 -DryRun 参数，已切换为预演模式。"
    }
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
    if ($DryRun) {
        Write-Host ("DRYRUN：将卸载 MCP 服务：{0}" -f $name)
    }
    else {
        Write-Host ("已卸载 MCP 服务：{0}" -f $name)
        Invoke-NativeMcpCleanup $name
    }
    同步MCP
}

function 同步MCP {
    Invoke-WithMetric "sync_mcp" {
        $script:SkipNativeMcpForSession = $false
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

function Get-AuditTargetsConfigPath {
    return (Join-Path $script:Root "audit-targets.json")
}

function Get-AuditStructuredProfileDefaultPath {
    return (Join-Path $script:Root "reports\skill-audit\user-profile.structured.json")
}

function Get-AuditUserProfileSnapshotPath {
    return (Join-Path $script:Root "reports\skill-audit\user-profile.json")
}

function Get-AuditOuterAiPromptOverridePath {
    return (Join-Path $script:Root "overrides\audit-outer-ai-prompt.md")
}

function Get-DefaultAuditOuterAiPrompt {
    return @"
# Outer AI Audit Prompt (Short / Codex + Claude)

目标：基于当前审查包生成可预检的 recommendations.json；预检通过后只执行 dry-run。未经明确确认，不得 apply。

0) 写入边界
- 只允许写/更新 ``reports/skill-audit/<run-id>/recommendations.json``；画像缺失时可写 ``reports/skill-audit/user-profile.structured.json``。
- 不得修改 ``outer-ai-prompt.md``、``ai-brief.md``、``user-profile.json``、``installed-skills.json``、``source-strategy.json``、``decision-insights.json``、``recommendations.template.json``、``repo-scan.json`` / ``repo-scans.json``。
- 不得把 dry-run 建议描述成已安装、已卸载或已落盘。

1) run-id
- 如果当前提示词已列出审查包目录和文件路径，以该运行包为准。
- ``<run-id>`` 只用于命令路径占位；写 recommendations 前必须已有扫描/发现运行包，执行预检或 dry-run 前必须已写出 recommendations.json。
- 若无可用运行包：立即停止并报告：先执行 ``.\skills.ps1 审查目标 扫描`` 或 ``.\skills.ps1 审查目标 发现新技能``。

2) 画像预检查（只在本轮输入显示画像不完整时执行）
- 检查 audit-targets.json.user_profile。
- 若 summary 为空或 structured 不完整：补全 ``reports/skill-audit/user-profile.structured.json``（schema 不变，summary 非空，structured_by="outer-ai"），然后执行：
  ``.\skills.ps1 审查目标 需求结构化 --profile "reports\skill-audit\user-profile.structured.json"``
- 导入后复查；失败最多重试 1 次，再失败立即停止。

3) 只读输入（必须真实读取）
- outer-ai-prompt.md、ai-brief.md、user-profile.json、installed-skills.json（仅输入快照）、source-strategy.json、decision-insights.json、recommendations.template.json
- repo-scan.json / repo-scans.json：存在才读；N/A/profile-only 不得臆造仓库事实。
- source-strategy.json 中的 evidence_policy / decision_quality_policy 是硬约束；decision-insights.json 是 keyword_trace 的可选关键词来源。

4) 产出 recommendations.json
- 路径：``reports/skill-audit/<run-id>/recommendations.json``
- ``schema_version=2``；不得保留 ``<...>``；``decision_basis.summary`` 非空
- 每条新增/卸载（skills/MCP）必须有：``reason_user_profile``、``reason_target_repo``、``sources``（仅本轮真实来源）
- 每条新增/卸载（skills/MCP）建议必须有匹配的 ``source_observations``；若策略要求，``sources`` 数量、http 来源和 observation 必须达标
- 每条新增/卸载（skills/MCP）建议应包含 ``keyword_trace.user_profile`` / ``keyword_trace.target_repo_or_context`` / ``keyword_trace.installed_state``（与 decision-insights 对齐）
- MCP 新增写 ``mcp_new_servers`` 且 ``name==server.name``；MCP 卸载写 ``mcp_removal_candidates``
- ``overlap_findings`` 仅报告；``do_not_install`` 仅记录当前不应安装项；证据不足留空

5) 自检、预检、dry-run
- 自检：JSON/schema/双理由/sources/source_observations/keyword_trace/无占位符/无重复建议
- 预检：
  ``.\skills.ps1 审查目标 预检 --recommendations "reports\skill-audit\<run-id>\recommendations.json"``
- 若预检失败（如 stale_snapshot、prompt_contract_mismatch、insufficient_source_coverage、insufficient_decision_quality、user_profile_invalid），停止并报告阻断项；不要绕过。
- dry-run：
  ``.\skills.ps1 审查目标 应用 --recommendations "reports\skill-audit\<run-id>\recommendations.json" --dry-run-ack "我知道未落盘"``
- 自检、预检或 dry-run 失败即停止并报告阻断项

6) 汇报格式（按 dry-run 原序号，不重排）
- 新增建议 / 卸载建议 / MCP 新增建议 / MCP 卸载建议
- 每项：序号、名称、reason_user_profile、reason_target_repo、sources
- 空类必须写“无该类建议”，并给 1 句原因

安全约束：未收到明确确认，不执行 ``--apply --yes``；不得把建议写成已生效。
"@
}

function Get-AuditOuterAiPromptContent {
    $overridePath = Get-AuditOuterAiPromptOverridePath
    if (Test-Path -LiteralPath $overridePath -PathType Leaf) {
        $content = Get-ContentUtf8 $overridePath
        if (-not [string]::IsNullOrWhiteSpace($content)) {
            return $content
        }
    }
    return (Get-DefaultAuditOuterAiPrompt)
}

function Show-AuditOuterAiPromptTemplate {
    $overridePath = Get-AuditOuterAiPromptOverridePath
    if (Test-Path -LiteralPath $overridePath -PathType Leaf) {
        Write-Host ("当前使用自定义提示词：{0}" -f $overridePath) -ForegroundColor Green
    }
    else {
        Write-Host "当前使用内置默认提示词。" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host (Get-AuditOuterAiPromptContent)
}

function Edit-AuditOuterAiPromptTemplate {
    $path = Get-AuditOuterAiPromptOverridePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Set-ContentUtf8 $path (Get-DefaultAuditOuterAiPrompt)
    }
    Invoke-StartProcess "notepad.exe" ("`"{0}`"" -f $path)
    Write-Host ("已打开提示词文件：{0}" -f $path) -ForegroundColor Green
}

function New-DefaultAuditUserProfile {
    return [pscustomobject]@{
        raw_text = ""
        summary = ""
        structured = [pscustomobject]@{
            primary_work_types = @()
            preferred_agents = @()
            tech_stack = @()
            common_tasks = @()
            constraints = @()
            avoidances = @()
            decision_preferences = @()
        }
        last_structured_at = ""
        structured_by = ""
    }
}

function Get-AuditStructuredProfileFieldNames {
    return @("primary_work_types", "preferred_agents", "tech_stack", "common_tasks", "constraints", "avoidances", "decision_preferences")
}

function Test-AuditObjectLike($value) {
    if ($null -eq $value) { return $false }
    return ($value -is [pscustomobject]) -or ($value -is [hashtable]) -or ($value -is [System.Collections.IDictionary])
}

function Get-AuditObjectFieldValue($source, [string]$fieldName, [ref]$value) {
    if ($null -eq $source) { return $false }
    if ($source -is [hashtable] -or $source -is [System.Collections.IDictionary]) {
        if ($source.Contains($fieldName)) {
            $value.Value = $source[$fieldName]
            return $true
        }
        return $false
    }
    if ($source.PSObject.Properties.Match($fieldName).Count -gt 0) {
        $value.Value = $source.$fieldName
        return $true
    }
    return $false
}

function Convert-AuditStringArray($value) {
    if ($null -eq $value) { return @() }
    $items = if (Assert-IsArray $value) { @($value) } else { @($value) }
    $normalized = New-Object System.Collections.Generic.List[string]
    foreach ($item in $items) {
        if ($null -eq $item) { continue }
        $text = [string]$item
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $normalized.Add($text.Trim()) | Out-Null
    }
    return @($normalized)
}

function Normalize-AuditStructuredProfile($structuredInput) {
    $normalized = [pscustomobject]@{}
    foreach ($field in Get-AuditStructuredProfileFieldNames) {
        $normalized | Add-Member -NotePropertyName $field -NotePropertyValue @() -Force
    }
    if (-not (Test-AuditObjectLike $structuredInput)) {
        return $normalized
    }
    foreach ($field in Get-AuditStructuredProfileFieldNames) {
        $rawValue = $null
        if (Get-AuditObjectFieldValue $structuredInput $field ([ref]$rawValue)) {
            $normalized.$field = @(Convert-AuditStringArray $rawValue)
        }
    }
    return $normalized
}

function Ensure-AuditUserProfile($cfg) {
    $changed = $false
    if (-not $cfg.PSObject.Properties.Match("user_profile").Count -or $null -eq $cfg.user_profile) {
        $cfg | Add-Member -NotePropertyName user_profile -NotePropertyValue (New-DefaultAuditUserProfile) -Force
        $changed = $true
    }

    $profile = $cfg.user_profile
    foreach ($name in @("raw_text", "summary", "last_structured_at", "structured_by")) {
        if (-not $profile.PSObject.Properties.Match($name).Count) {
            $profile | Add-Member -NotePropertyName $name -NotePropertyValue "" -Force
            $changed = $true
        }
        elseif ($null -eq $profile.$name) {
            $profile.$name = ""
            $changed = $true
        }
        elseif (-not ($profile.$name -is [string])) {
            $profile.$name = [string]$profile.$name
            $changed = $true
        }
    }
    if (-not $profile.PSObject.Properties.Match("structured").Count) {
        $profile | Add-Member -NotePropertyName structured -NotePropertyValue (Normalize-AuditStructuredProfile $null) -Force
        $changed = $true
    }
    $currentStructuredJson = ($profile.structured | ConvertTo-Json -Depth 20 -Compress)
    $normalizedStructured = Normalize-AuditStructuredProfile $profile.structured
    $normalizedStructuredJson = ($normalizedStructured | ConvertTo-Json -Depth 20 -Compress)
    if ($currentStructuredJson -ne $normalizedStructuredJson) {
        $profile.structured = $normalizedStructured
        $changed = $true
    }
    return $changed
}

function New-DefaultAuditTargetsConfig {
    return [pscustomobject]@{
        version = 2
        path_base = "skills_manager_root"
        user_profile = New-DefaultAuditUserProfile
        targets = @()
    }
}

function Save-AuditTargetsConfig($cfg) {
    $json = $cfg | ConvertTo-Json -Depth 20
    Set-ContentUtf8 (Get-AuditTargetsConfigPath) $json
}

function Initialize-AuditTargetsConfig {
    $path = Get-AuditTargetsConfigPath
    if (Test-Path -LiteralPath $path -PathType Leaf) { return $false }
    Save-AuditTargetsConfig (New-DefaultAuditTargetsConfig)
    return $true
}

function Load-AuditTargetsConfig {
    $path = Get-AuditTargetsConfigPath
    Need (Test-Path -LiteralPath $path -PathType Leaf) "缺少 audit-targets.json，请先运行：./skills.ps1 审查目标 初始化"
    $cfg = $null
    $lastError = $null
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        try {
            $raw = Get-ContentUtf8 $path
            if ([string]::IsNullOrWhiteSpace($raw)) {
                throw "audit-targets.json 为空"
            }
            $cfg = $raw | ConvertFrom-Json
            $lastError = $null
            break
        }
        catch {
            $lastError = $_.Exception.Message
            if ($attempt -lt 3) {
                Start-Sleep -Milliseconds 150
                continue
            }
        }
    }
    if ($null -eq $cfg) {
        throw ("audit-targets.json 解析失败：{0}" -f $lastError)
    }

    $changed = $false
    if (-not $cfg.PSObject.Properties.Match("version").Count) {
        $cfg | Add-Member -NotePropertyName version -NotePropertyValue 1
        $changed = $true
    }
    if ([int]$cfg.version -eq 1) {
        $cfg.version = 2
        $changed = $true
    }
    if (-not $cfg.PSObject.Properties.Match("path_base").Count) {
        $cfg | Add-Member -NotePropertyName path_base -NotePropertyValue "skills_manager_root"
        $changed = $true
    }
    if (-not $cfg.PSObject.Properties.Match("targets").Count -or $null -eq $cfg.targets) {
        $cfg | Add-Member -NotePropertyName targets -NotePropertyValue @() -Force
        $changed = $true
    }
    if (Ensure-AuditUserProfile $cfg) {
        $changed = $true
    }

    Need ([int]$cfg.version -eq 2) "audit-targets.json version 仅支持 2"
    Need ([string]$cfg.path_base -eq "skills_manager_root") "audit-targets.json path_base 仅支持 skills_manager_root"
    if (-not (Assert-IsArray $cfg.targets)) { $cfg.targets = @($cfg.targets) }
    if ($changed) {
        Save-AuditTargetsConfig $cfg
    }
    return $cfg
}

function Resolve-AuditTargetPath([string]$path) {
    Need (-not [string]::IsNullOrWhiteSpace($path)) "目标仓路径不能为空"
    $expanded = [Environment]::ExpandEnvironmentVariables($path.Trim())
    if ($expanded -eq "~" -or $expanded.StartsWith("~\") -or $expanded.StartsWith("~/")) {
        $userHome = [Environment]::GetFolderPath("UserProfile")
        if ($expanded.Length -eq 1) {
            $expanded = $userHome
        }
        else {
            $expanded = Join-Path $userHome $expanded.Substring(2)
        }
    }
    if ([System.IO.Path]::IsPathRooted($expanded)) {
        return [System.IO.Path]::GetFullPath($expanded)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $script:Root $expanded))
}

function Add-AuditTargetConfigEntry([string]$name, [string]$path, [string[]]$tags = @(), [string]$notes = "") {
    Initialize-AuditTargetsConfig | Out-Null
    $cfg = Load-AuditTargetsConfig
    $normName = Normalize-NameWithNotice $name "target 名称"
    Need (-not [string]::IsNullOrWhiteSpace($normName)) "target 名称不能为空"
    Need (-not [string]::IsNullOrWhiteSpace($path)) "target path 不能为空"

    $entry = [pscustomobject]@{
        name = $normName
        path = $path
        enabled = $true
        tags = @($tags | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        notes = $notes
    }

    $existing = @($cfg.targets | Where-Object { $_.name -eq $normName })
    if ($existing.Count -gt 0) {
        $existing[0].path = $entry.path
        $existing[0].enabled = $entry.enabled
        $existing[0].tags = $entry.tags
        $existing[0].notes = $entry.notes
    }
    else {
        $cfg.targets += $entry
    }
    Save-AuditTargetsConfig $cfg
    return $cfg
}

function Update-AuditTargetConfigEntry([string]$name, [string]$path, [string[]]$tags = @(), [string]$notes = "") {
    Initialize-AuditTargetsConfig | Out-Null
    $cfg = Load-AuditTargetsConfig
    $normName = Normalize-NameWithNotice $name "target 名称"
    Need (-not [string]::IsNullOrWhiteSpace($normName)) "target 名称不能为空"
    Need (-not [string]::IsNullOrWhiteSpace($path)) "target path 不能为空"

    $existing = @($cfg.targets | Where-Object { $_.name -eq $normName })
    Need ($existing.Count -gt 0) ("未找到目标仓：{0}" -f $normName)

    $existing[0].path = $path
    $existing[0].enabled = $true
    $existing[0].tags = @($tags | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $existing[0].notes = $notes
    Save-AuditTargetsConfig $cfg
    return $cfg
}

function Remove-AuditTargetConfigEntry([string]$name) {
    Initialize-AuditTargetsConfig | Out-Null
    $cfg = Load-AuditTargetsConfig
    $normName = Normalize-NameWithNotice $name "target 名称"
    Need (-not [string]::IsNullOrWhiteSpace($normName)) "target 名称不能为空"
    $before = @($cfg.targets).Count
    $cfg.targets = @($cfg.targets | Where-Object { $_.name -ne $normName })
    Need (@($cfg.targets).Count -lt $before) ("未找到目标仓：{0}" -f $normName)
    Save-AuditTargetsConfig $cfg
    return $cfg
}

function Set-AuditUserProfileRawText([string]$rawText) {
    Initialize-AuditTargetsConfig | Out-Null
    $cfg = Load-AuditTargetsConfig
    Need (-not [string]::IsNullOrWhiteSpace($rawText)) "用户基本需求不能为空"
    $cfg.user_profile.raw_text = $rawText.Trim()
    $cfg.user_profile.summary = ""
    $cfg.user_profile.structured = (New-DefaultAuditUserProfile).structured
    $cfg.user_profile.last_structured_at = ""
    $cfg.user_profile.structured_by = ""
    Save-AuditTargetsConfig $cfg
}

function Show-AuditUserProfile {
    $cfg = Load-AuditTargetsConfig
    Write-Host "=== 用户基本需求 ==="
    Write-Host ([string]$cfg.user_profile.raw_text)
    Write-Host ""
    Write-Host ("summary: {0}" -f [string]$cfg.user_profile.summary)
    Write-Host ("structured_by: {0}" -f [string]$cfg.user_profile.structured_by)
}

function New-AuditStructuredProfileDraft([string]$rawText) {
    return [pscustomobject]@{
        raw_text = $rawText
        summary = ""
        structured = (New-DefaultAuditUserProfile).structured
        last_structured_at = ""
        structured_by = "outer-ai"
    }
}

function Get-AuditFallbackSummaryFromRawText([string]$rawText) {
    $normalized = [regex]::Replace([string]$rawText, "\s+", " ").Trim()
    if ([string]::IsNullOrWhiteSpace($normalized)) { return "" }
    if ($normalized.Length -le 120) { return $normalized }
    return ($normalized.Substring(0, 120) + "...")
}

function Get-AuditStructuredProfileRequiredNonEmptyFields {
    return @("primary_work_types", "tech_stack", "common_tasks", "decision_preferences")
}

function Test-AuditTimestampString([string]$value) {
    if ([string]::IsNullOrWhiteSpace([string]$value)) { return $false }
    $parsed = [DateTimeOffset]::MinValue
    return [DateTimeOffset]::TryParse([string]$value, [ref]$parsed)
}

function Convert-AuditTimestampToIso($value, [switch]$FallbackNow) {
    if ($value -is [DateTimeOffset]) {
        return ([DateTimeOffset]$value).ToString("o")
    }
    if ($value -is [DateTime]) {
        return ([DateTimeOffset]$value).ToString("o")
    }
    if ($null -ne $value) {
        $text = [string]$value
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $parsed = [DateTimeOffset]::MinValue
            if ([DateTimeOffset]::TryParse($text, [ref]$parsed)) {
                return $parsed.ToString("o")
            }
        }
    }
    if ($FallbackNow) {
        return (Get-Date).ToString("o")
    }
    return ""
}

function Get-AuditStructuredFallbackValues([string]$field, [string]$rawText) {
    $summary = Get-AuditFallbackSummaryFromRawText $rawText
    $generic = if ([string]::IsNullOrWhiteSpace($summary)) { "general workflow" } else { $summary }
    switch ($field) {
        "primary_work_types" { return @("需求分析与交付") }
        "tech_stack" {
            if ([regex]::IsMatch($rawText, "(?i)\bwindows\b")) { return @("Windows") }
            return @("Mixed stack")
        }
        "common_tasks" { return @($generic) }
        "decision_preferences" { return @("evidence-first") }
        default { return @() }
    }
}

function Test-AuditStructuredProfileComplete($structuredInput) {
    if (-not (Test-AuditObjectLike $structuredInput)) { return $false }
    $normalized = Normalize-AuditStructuredProfile $structuredInput
    foreach ($field in Get-AuditStructuredProfileFieldNames) {
        if ($normalized.PSObject.Properties.Match($field).Count -eq 0) { return $false }
        if (-not (Assert-IsArray $normalized.$field)) { return $false }
    }
    foreach ($required in Get-AuditStructuredProfileRequiredNonEmptyFields) {
        if (@($normalized.$required).Count -eq 0) { return $false }
    }
    return $true
}

function New-AuditPrecheckStructuredProfile($cfg) {
    $rawText = [string]$cfg.user_profile.raw_text
    $summary = [string]$cfg.user_profile.summary
    if ([string]::IsNullOrWhiteSpace($summary)) {
        $summary = Get-AuditFallbackSummaryFromRawText $rawText
    }
    $structured = Normalize-AuditStructuredProfile $cfg.user_profile.structured
    foreach ($field in Get-AuditStructuredProfileRequiredNonEmptyFields) {
        if (@($structured.$field).Count -eq 0) {
            $structured.$field = @(Get-AuditStructuredFallbackValues $field $rawText)
        }
    }
    return [pscustomobject]@{
        raw_text = $rawText
        summary = $summary
        structured = $structured
        last_structured_at = (Get-Date).ToString("o")
        structured_by = "outer-ai"
    }
}

function Write-AuditUserProfileSnapshot($cfg) {
    Write-AuditJsonFile (Get-AuditUserProfileSnapshotPath) (Get-AuditUserProfileOutput $cfg)
}

function Ensure-AuditUserProfilePrecheck {
    $profilePath = Get-AuditStructuredProfileDefaultPath
    $maxAttempts = 2

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $cfg = Load-AuditTargetsConfig
        Need (-not [string]::IsNullOrWhiteSpace([string]$cfg.user_profile.raw_text)) "缺少用户基本需求，请先运行：./skills.ps1 审查目标 需求设置"

        $summaryMissing = [string]::IsNullOrWhiteSpace([string]$cfg.user_profile.summary)
        $structuredIncomplete = -not (Test-AuditStructuredProfileComplete $cfg.user_profile.structured)
        $timestampInvalid = -not (Test-AuditTimestampString ([string]$cfg.user_profile.last_structured_at))
        if (-not $summaryMissing -and -not $structuredIncomplete -and -not $timestampInvalid) {
            Write-AuditUserProfileSnapshot $cfg
            return $cfg
        }

        Write-AuditJsonFile $profilePath (New-AuditPrecheckStructuredProfile $cfg)
        try {
            Invoke-AuditStructuredProfileFlow $profilePath
        }
        catch {
            if ($attempt -ge $maxAttempts) {
                throw ("画像预检查失败：自动导入结构化需求失败（已重试 1 次）。请先执行：.\skills.ps1 审查目标 需求结构化 --profile `"{0}`"。错误：{1}" -f $profilePath, $_.Exception.Message)
            }
        }
    }

    throw ("画像预检查失败：summary/structured/last_structured_at 仍不完整（已重试 1 次）。请先执行：.\skills.ps1 审查目标 需求结构化 --profile `"{0}`"" -f $profilePath)
}

function Write-AuditStructuredProfileDraft([string]$profilePath, [string]$rawText) {
    if ([string]::IsNullOrWhiteSpace($profilePath)) {
        $profilePath = Get-AuditStructuredProfileDefaultPath
    }
    $resolved = Resolve-AuditTargetPath $profilePath
    Write-AuditJsonFile $resolved (New-AuditStructuredProfileDraft $rawText)
    return $resolved
}

function Import-AuditUserProfileStructured([string]$profilePath) {
    if ([string]::IsNullOrWhiteSpace($profilePath)) {
        $profilePath = Get-AuditStructuredProfileDefaultPath
    }
    $resolved = Resolve-AuditTargetPath $profilePath
    Need (Test-Path -LiteralPath $resolved -PathType Leaf) ("找不到 profile 文件：{0}" -f $profilePath)

    try {
        $raw = Get-ContentUtf8 $resolved
        Need (-not [string]::IsNullOrWhiteSpace($raw)) ("profile 文件为空：{0}" -f $profilePath)
        $imported = $raw | ConvertFrom-Json
    }
    catch {
        throw ("profile 文件解析失败：{0}" -f $_.Exception.Message)
    }
    Need (Test-AuditObjectLike $imported) ("profile 文件根节点必须是对象：{0}" -f $profilePath)

    Initialize-AuditTargetsConfig | Out-Null
    $cfg = Load-AuditTargetsConfig

    $importedRawText = $null
    if (Get-AuditObjectFieldValue $imported "raw_text" ([ref]$importedRawText)) {
        $text = [string]$importedRawText
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $cfg.user_profile.raw_text = $text.Trim()
        }
    }

    $importedSummary = $null
    if (Get-AuditObjectFieldValue $imported "summary" ([ref]$importedSummary)) {
        $cfg.user_profile.summary = [string]$importedSummary
    }

    $importedStructured = $null
    if (Get-AuditObjectFieldValue $imported "structured" ([ref]$importedStructured)) {
        Need (Test-AuditObjectLike $importedStructured) ("profile.structured 必须是对象：{0}" -f $profilePath)
        $cfg.user_profile.structured = Normalize-AuditStructuredProfile $importedStructured
    }

    $importedStructuredBy = $null
    if (Get-AuditObjectFieldValue $imported "structured_by" ([ref]$importedStructuredBy)) {
        $cfg.user_profile.structured_by = [string]$importedStructuredBy
    }
    else {
        $cfg.user_profile.structured_by = "manual"
    }

    $importedStructuredAt = $null
    if (Get-AuditObjectFieldValue $imported "last_structured_at" ([ref]$importedStructuredAt)) {
        $cfg.user_profile.last_structured_at = Convert-AuditTimestampToIso $importedStructuredAt -FallbackNow
    }
    else {
        $cfg.user_profile.last_structured_at = (Get-Date).ToString("o")
    }
    if (-not (Test-AuditTimestampString ([string]$cfg.user_profile.last_structured_at))) {
        $cfg.user_profile.last_structured_at = (Get-Date).ToString("o")
    }

    Ensure-AuditUserProfile $cfg | Out-Null
    Need (-not [string]::IsNullOrWhiteSpace([string]$cfg.user_profile.raw_text)) "导入后用户基本需求为空，请在 profile.raw_text 填写非空文本或先执行“需求设置”"
    Save-AuditTargetsConfig $cfg
    Write-AuditUserProfileSnapshot $cfg
}

function Invoke-AuditStructuredProfileFlow([string]$profilePath = "") {
    $cfg = Load-AuditTargetsConfig
    $defaultPath = Get-AuditStructuredProfileDefaultPath
    $chosen = if ([string]::IsNullOrWhiteSpace($profilePath)) { $defaultPath } else { $profilePath }
    $resolved = Resolve-AuditTargetPath $chosen

    if (Test-Path -LiteralPath $resolved -PathType Leaf) {
        Import-AuditUserProfileStructured $chosen
        Write-Host ("已导入结构化需求：{0}" -f $resolved) -ForegroundColor Green
        return
    }

    $draft = Write-AuditStructuredProfileDraft $chosen ([string]$cfg.user_profile.raw_text)
    Write-Host ("未找到结构化 profile，已生成默认草稿：{0}" -f $draft) -ForegroundColor Yellow
    Write-Host "请让 AI 或手动填写该文件后，再运行：./skills.ps1 审查目标 需求结构化" -ForegroundColor Yellow
}

function Write-AuditTargetsList {
    $cfg = Load-AuditTargetsConfig
    $items = @($cfg.targets)
    if ($items.Count -eq 0) {
        Write-Host "未登记目标仓。"
        return
    }
    foreach ($t in $items) {
        $resolved = Resolve-AuditTargetPath ([string]$t.path)
        $exists = Test-Path -LiteralPath $resolved
        $enabled = if ($t.PSObject.Properties.Match("enabled").Count -gt 0) { [bool]$t.enabled } else { $true }
        $enabledText = if ($enabled) { "enabled" } else { "disabled" }
        Write-Host ("- {0} [{1}] {2} -> {3} exists={4}" -f [string]$t.name, $enabledText, [string]$t.path, $resolved, $exists)
    }
}

function Assert-AuditUserProfileReady($cfg) {
    Need (-not [string]::IsNullOrWhiteSpace([string]$cfg.user_profile.raw_text)) "缺少用户基本需求，请先运行：./skills.ps1 审查目标 需求设置"
    Need (Test-AuditObjectLike $cfg.user_profile.structured) "用户结构化需求格式异常，请先运行：./skills.ps1 审查目标 需求结构化"
    foreach ($field in Get-AuditStructuredProfileFieldNames) {
        Need ($cfg.user_profile.structured.PSObject.Properties.Match($field).Count -gt 0) ("用户结构化需求缺少字段：{0}" -f $field)
        Need (Assert-IsArray $cfg.user_profile.structured.$field) ("用户结构化需求字段必须为数组：{0}" -f $field)
    }
    foreach ($required in Get-AuditStructuredProfileRequiredNonEmptyFields) {
        Need (@($cfg.user_profile.structured.$required).Count -gt 0) ("用户结构化需求字段不能为空：{0}" -f $required)
    }
    if ([string]::IsNullOrWhiteSpace([string]$cfg.user_profile.summary)) {
        Write-Host "提示：用户结构化 summary 为空，建议先完善结构化需求后再生成审查包。" -ForegroundColor Yellow
    }
    Need (Test-AuditTimestampString ([string]$cfg.user_profile.last_structured_at)) "用户结构化时间戳缺失或无效，请先运行：./skills.ps1 审查目标 需求结构化"
}

function Get-AuditUserProfileOutput($cfg) {
    return [pscustomobject]@{
        schema_version = 1
        raw_text = [string]$cfg.user_profile.raw_text
        summary = [string]$cfg.user_profile.summary
        structured = $cfg.user_profile.structured
        last_structured_at = Convert-AuditTimestampToIso $cfg.user_profile.last_structured_at -FallbackNow
        structured_by = [string]$cfg.user_profile.structured_by
    }
}

function Get-AuditRunId {
    return (Get-Date -Format "yyyyMMdd-HHmmss-fff")
}

function Get-AuditPromptContractVersion {
    return "audit-prompt-v20260427.1"
}

function Get-AuditReportRoot([string]$runId) {
    return (Join-Path $script:Root (Join-Path "reports\skill-audit" $runId))
}

function Test-AuditPlaceholderToken([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    return ([regex]::IsMatch($text, "<[^>]+>"))
}

function Get-AuditKnownRunIds {
    $auditRoot = Join-Path $script:Root "reports\skill-audit"
    if (-not (Test-Path -LiteralPath $auditRoot -PathType Container)) { return @() }
    $dirs = @(Get-ChildItem -LiteralPath $auditRoot -Directory -ErrorAction SilentlyContinue)
    return @($dirs | Select-Object -ExpandProperty Name | Sort-Object)
}

function Get-AuditRunCandidateBuckets([string[]]$RequiredFiles = @()) {
    $auditRoot = Join-Path $script:Root "reports\skill-audit"
    $result = [ordered]@{
        known = New-Object System.Collections.Generic.List[string]
        fresh = New-Object System.Collections.Generic.List[string]
        unknown = New-Object System.Collections.Generic.List[string]
        stale = New-Object System.Collections.Generic.List[string]
        missing_required = New-Object System.Collections.Generic.List[string]
        missing_required_details = New-Object System.Collections.Generic.List[string]
    }
    if (-not (Test-Path -LiteralPath $auditRoot -PathType Container)) {
        return [pscustomobject]@{
            known = @()
            fresh = @()
            unknown = @()
            stale = @()
            missing_required = @()
            missing_required_details = @()
        }
    }
    $dirs = @(
        Get-ChildItem -LiteralPath $auditRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object -Property @{ Expression = { $_.LastWriteTimeUtc }; Descending = $true }, @{ Expression = { $_.Name }; Descending = $true }
    )
    $liveStateResolved = $false
    $liveState = $null
    $liveStateAvailable = $false
    $currentPromptVersion = ""
    foreach ($dir in $dirs) {
        $result.known.Add([string]$dir.Name) | Out-Null
        $ok = $true
        $missing = New-Object System.Collections.Generic.List[string]
        foreach ($relative in @($RequiredFiles)) {
            if (-not (Test-AuditFile $dir.FullName ([string]$relative))) {
                $ok = $false
                $missing.Add([string]$relative) | Out-Null
            }
        }
        if (-not $ok) {
            $result.missing_required.Add([string]$dir.Name) | Out-Null
            $result.missing_required_details.Add(("{0}(缺少: {1})" -f [string]$dir.Name, (($missing.ToArray()) -join ","))) | Out-Null
            continue
        }

        $snapshotPath = Join-Path $dir.FullName "installed-skills.json"
        $metaPath = Join-Path $dir.FullName "audit-meta.json"
        $canCheckStale = (Test-Path -LiteralPath $snapshotPath -PathType Leaf) -and (Test-Path -LiteralPath $metaPath -PathType Leaf)
        if (-not $canCheckStale) {
            $result.unknown.Add([string]$dir.Name) | Out-Null
            continue
        }

        if (-not $liveStateResolved) {
            $liveStateResolved = $true
            try {
                $liveState = Get-AuditLiveInstalledState
                $liveStateAvailable = $true
                $currentPromptVersion = Get-AuditPromptContractVersion
            }
            catch {
                $liveStateAvailable = $false
            }
        }
        if (-not $liveStateAvailable) {
            $result.unknown.Add([string]$dir.Name) | Out-Null
            continue
        }

        $isStale = $false
        try {
            $snapshotState = Get-AuditInstalledSnapshotState $snapshotPath
            $skillSnapshotStale = ([string]$snapshotState.fingerprint -ne [string]$liveState.fingerprint)
            $mcpSnapshotStale = $false
            if ($snapshotState.PSObject.Properties.Match("mcp_fingerprint").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$snapshotState.mcp_fingerprint)) {
                $mcpSnapshotStale = ([string]$snapshotState.mcp_fingerprint -ne [string]$liveState.mcp_fingerprint)
            }
            if ($skillSnapshotStale -or $mcpSnapshotStale) {
                $isStale = $true
            }
        }
        catch {
            $result.unknown.Add([string]$dir.Name) | Out-Null
            continue
        }

        try {
            $metaRaw = Get-ContentUtf8 $metaPath
            if (-not [string]::IsNullOrWhiteSpace($metaRaw)) {
                $meta = $metaRaw | ConvertFrom-Json
                if ($meta.PSObject.Properties.Match("prompt_contract_version").Count -gt 0) {
                    $runPromptVersion = ([string]$meta.prompt_contract_version).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($runPromptVersion) -and [string]$runPromptVersion -ne [string]$currentPromptVersion) {
                        $isStale = $true
                    }
                }
            }
        }
        catch {
            $result.unknown.Add([string]$dir.Name) | Out-Null
            continue
        }

        if ($isStale) {
            $result.stale.Add([string]$dir.Name) | Out-Null
        }
        else {
            $result.fresh.Add([string]$dir.Name) | Out-Null
        }
    }

    return [pscustomobject]@{
        known = @($result.known.ToArray())
        fresh = @($result.fresh.ToArray())
        unknown = @($result.unknown.ToArray())
        stale = @($result.stale.ToArray())
        missing_required = @($result.missing_required.ToArray())
        missing_required_details = @($result.missing_required_details.ToArray())
    }
}

function Get-AuditLatestRunId([string[]]$RequiredFiles = @()) {
    $buckets = Get-AuditRunCandidateBuckets -RequiredFiles $RequiredFiles
    if (@($buckets.fresh).Count -gt 0) { return [string]$buckets.fresh[0] }
    if (@($buckets.unknown).Count -gt 0) { return [string]$buckets.unknown[0] }
    return ""
}

function Resolve-AuditRunIdInput([string]$runId, [string]$FlagName = "--run-id", [string[]]$RequiredFiles = @()) {
    if ([string]::IsNullOrWhiteSpace($runId)) { return $runId }
    $trimmed = [string]$runId
    if (-not (Test-AuditPlaceholderToken $trimmed)) { return $trimmed }
    if ([regex]::IsMatch($trimmed, "<\s*run[-_]?id\s*>", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        $resolved = Get-AuditLatestRunId -RequiredFiles $RequiredFiles
        if (-not [string]::IsNullOrWhiteSpace($resolved)) {
            return $resolved
        }
        throw ("{0} 使用占位符但未找到可用 run-id。{1}" -f $FlagName, (Get-AuditRunIdHintText $RequiredFiles))
    }
    throw ("{0} 包含未替换占位符：{1}`n{2}" -f $FlagName, $runId, (Get-AuditRunIdHintText $RequiredFiles))
}

function Resolve-AuditPathRunIdPlaceholder([string]$path, [string]$FlagName = "--recommendations", [string[]]$RequiredFiles = @()) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $path }
    if (-not (Test-AuditPlaceholderToken $path)) { return $path }
    if (-not [regex]::IsMatch($path, "<\s*run[-_]?id\s*>", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        throw ("{0} 路径包含未替换占位符：{1}`n{2}" -f $FlagName, $path, (Get-AuditRunIdHintText $RequiredFiles))
    }

    $resolvedRunId = Get-AuditLatestRunId -RequiredFiles $RequiredFiles
    if ([string]::IsNullOrWhiteSpace($resolvedRunId)) {
        throw ("{0} 路径使用 <run-id> 占位符但未找到可用 run。{1}" -f $FlagName, (Get-AuditRunIdHintText $RequiredFiles))
    }
    $resolvedPath = [regex]::Replace($path, "<\s*run[-_]?id\s*>", [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $resolvedRunId }, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (Test-AuditPlaceholderToken $resolvedPath) {
        throw ("{0} 路径仍包含未替换占位符：{1}`n{2}" -f $FlagName, $resolvedPath, (Get-AuditRunIdHintText $RequiredFiles))
    }
    return $resolvedPath
}

function Get-AuditRunIdHintText([string[]]$RequiredFiles = @()) {
    $buckets = Get-AuditRunCandidateBuckets -RequiredFiles $RequiredFiles
    $ids = @($buckets.known)
    if (@($ids).Count -eq 0) {
        return "可用 run-id：无（先执行 .\skills.ps1 审查目标 扫描）"
    }
    if (@($RequiredFiles).Count -eq 0) {
        return ("可用 run-id：{0}" -f ($ids -join ", "))
    }

    if (@($buckets.fresh).Count -gt 0) {
        return ("可用 fresh run-id：{0}" -f ((@($buckets.fresh)) -join ", "))
    }

    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add("可用 fresh run-id：无（先执行 .\skills.ps1 审查目标 扫描）") | Out-Null
    if (@($buckets.stale).Count -gt 0) {
        $parts.Add(("stale run-id：{0}" -f ((@($buckets.stale)) -join ", "))) | Out-Null
    }
    if (@($buckets.unknown).Count -gt 0) {
        $parts.Add(("未校验 freshness 的候选 run-id：{0}" -f ((@($buckets.unknown)) -join ", "))) | Out-Null
    }
    if (@($buckets.missing_required_details).Count -gt 0) {
        $parts.Add(("缺少必要文件的 run-id：{0}" -f ((@($buckets.missing_required_details)) -join "; "))) | Out-Null
    }
    return (($parts.ToArray()) -join "; ")
}

function Test-AuditFile([string]$root, [string]$relative) {
    return (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)
}

function Add-AuditUniqueValue([System.Collections.Generic.List[string]]$items, [string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return }
    if (-not $items.Contains($value)) { $items.Add($value) | Out-Null }
}

function Get-AuditPackageJson([string]$root) {
    $path = Join-Path $root "package.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { return (Get-ContentUtf8 $path | ConvertFrom-Json) }
    catch { return $null }
}

function Get-AuditPackagePropertyNames($obj, [string]$propertyName) {
    if ($null -eq $obj) { return @() }
    if (-not $obj.PSObject.Properties.Match($propertyName).Count) { return @() }
    $value = $obj.$propertyName
    if ($null -eq $value) { return @() }
    return @($value.PSObject.Properties | ForEach-Object { $_.Name })
}

function Get-AuditPackageScriptNames($pkg) {
    if ($null -eq $pkg) { return @() }
    if (-not $pkg.PSObject.Properties.Match("scripts").Count -or $null -eq $pkg.scripts) { return @() }
    return @($pkg.scripts.PSObject.Properties | ForEach-Object { $_.Name })
}

function Get-AuditRepositoryRelativePath([string]$root, [string]$fullPath) {
    if ([string]::IsNullOrWhiteSpace($root) -or [string]::IsNullOrWhiteSpace($fullPath)) { return $fullPath }
    try {
        $normalizedRoot = [System.IO.Path]::GetFullPath($root).TrimEnd('\', '/')
        $normalizedPath = [System.IO.Path]::GetFullPath($fullPath)
        if ($normalizedPath.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $normalizedPath.Substring($normalizedRoot.Length).TrimStart('\', '/').Replace('/', '\')
        }
    }
    catch {
    }
    return $fullPath
}

function Add-AuditCommandsFromText([string]$content, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$testCommands) {
    if ([string]::IsNullOrWhiteSpace($content)) { return }
    if ([regex]::IsMatch($content, "(?im)\bdotnet\s+build\b")) { Add-AuditUniqueValue $buildCommands "dotnet build" }
    if ([regex]::IsMatch($content, "(?im)\bdotnet\s+test\b")) { Add-AuditUniqueValue $testCommands "dotnet test" }
    if ([regex]::IsMatch($content, "(?im)\bnpm\s+run\s+build\b")) { Add-AuditUniqueValue $buildCommands "npm run build" }
    if ([regex]::IsMatch($content, "(?im)\bnpm\s+test\b")) { Add-AuditUniqueValue $testCommands "npm test" }
    if ([regex]::IsMatch($content, "(?im)\bpnpm\s+build\b")) { Add-AuditUniqueValue $buildCommands "pnpm build" }
    if ([regex]::IsMatch($content, "(?im)\bpnpm\s+test\b")) { Add-AuditUniqueValue $testCommands "pnpm test" }
    if ([regex]::IsMatch($content, "(?im)\byarn\s+build\b")) { Add-AuditUniqueValue $buildCommands "yarn build" }
    if ([regex]::IsMatch($content, "(?im)\byarn\s+test\b")) { Add-AuditUniqueValue $testCommands "yarn test" }
    if ([regex]::IsMatch($content, "(?im)\buv\s+run\s+pytest\b")) { Add-AuditUniqueValue $testCommands "uv run pytest" }
    if ([regex]::IsMatch($content, "(?im)\bpoetry\s+run\s+pytest\b")) { Add-AuditUniqueValue $testCommands "poetry run pytest" }
    if ([regex]::IsMatch($content, "(?im)\bpytest\b")) { Add-AuditUniqueValue $testCommands "pytest" }
}

function Add-AuditCiWorkflowFacts([string]$resolvedPath, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$testCommands, [System.Collections.Generic.List[string]]$notableFiles) {
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($fileName in @("azure-pipelines.yml", ".gitlab-ci.yml")) {
        $candidate = Join-Path $resolvedPath $fileName
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $candidates.Add($candidate) | Out-Null
        }
    }
    $githubWorkflowDir = Join-Path $resolvedPath ".github\workflows"
    if (Test-Path -LiteralPath $githubWorkflowDir -PathType Container) {
        $workflowFiles = @(
            Get-ChildItem -LiteralPath $githubWorkflowDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @(".yml", ".yaml") } |
            Select-Object -First 20
        )
        foreach ($wf in $workflowFiles) {
            $candidates.Add($wf.FullName) | Out-Null
        }
    }

    foreach ($filePath in @($candidates)) {
        Add-AuditUniqueValue $notableFiles (Get-AuditRepositoryRelativePath $resolvedPath $filePath)
        try {
            $content = Get-ContentUtf8 $filePath
        }
        catch {
            continue
        }
        Add-AuditCommandsFromText $content $buildCommands $testCommands
    }
}

function Add-AuditPyProjectFacts([string]$resolvedPath, [System.Collections.Generic.List[string]]$frameworks, [System.Collections.Generic.List[string]]$packageManagers, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$testCommands, [System.Collections.Generic.List[string]]$notableFiles) {
    $path = Join-Path $resolvedPath "pyproject.toml"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    Add-AuditUniqueValue $notableFiles "pyproject.toml"
    $content = ""
    try {
        $content = Get-ContentUtf8 $path
    }
    catch {
        return
    }
    if ([regex]::IsMatch($content, "(?im)^\s*\[tool\.poetry\]")) {
        Add-AuditUniqueValue $packageManagers "poetry"
        Add-AuditUniqueValue $buildCommands "poetry build"
    }
    if ([regex]::IsMatch($content, "(?im)^\s*\[tool\.uv\]")) {
        Add-AuditUniqueValue $packageManagers "uv"
        Add-AuditUniqueValue $buildCommands "uv build"
    }
    if ([regex]::IsMatch($content, "(?im)^\s*\[tool\.hatch")) {
        Add-AuditUniqueValue $packageManagers "hatch"
        Add-AuditUniqueValue $buildCommands "hatch build"
    }
    if ([regex]::IsMatch($content, "(?im)^\s*\[tool\.pdm")) {
        Add-AuditUniqueValue $packageManagers "pdm"
        Add-AuditUniqueValue $buildCommands "pdm build"
    }
    if ([regex]::IsMatch($content, "(?i)\bfastapi\b")) { Add-AuditUniqueValue $frameworks "fastapi" }
    if ([regex]::IsMatch($content, "(?i)\bdjango\b")) { Add-AuditUniqueValue $frameworks "django" }
    if ([regex]::IsMatch($content, "(?i)\bflask\b")) { Add-AuditUniqueValue $frameworks "flask" }
    if ([regex]::IsMatch($content, "(?i)\bpytest\b")) { Add-AuditUniqueValue $testCommands "pytest" }
}

function Add-AuditMakefileFacts([string]$resolvedPath, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$testCommands, [System.Collections.Generic.List[string]]$notableFiles) {
    foreach ($name in @("Makefile", "makefile", "GNUmakefile")) {
        $path = Join-Path $resolvedPath $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        Add-AuditUniqueValue $notableFiles $name
        $content = ""
        try {
            $content = Get-ContentUtf8 $path
        }
        catch {
            continue
        }
        if ([regex]::IsMatch($content, "(?im)^\s*build\s*:")) { Add-AuditUniqueValue $buildCommands "make build" }
        if ([regex]::IsMatch($content, "(?im)^\s*(test|check)\s*:")) { Add-AuditUniqueValue $testCommands "make test" }
        if ([regex]::IsMatch($content, "(?im)^\s*ci\s*:")) { Add-AuditUniqueValue $testCommands "make ci" }
    }
}

function Add-AuditJavaFacts([string]$resolvedPath, [System.Collections.Generic.List[string]]$languages, [System.Collections.Generic.List[string]]$frameworks, [System.Collections.Generic.List[string]]$packageManagers, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$testCommands, [System.Collections.Generic.List[string]]$notableFiles) {
    $pomPath = Join-Path $resolvedPath "pom.xml"
    $gradleCandidates = @("build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts")
    $hasPom = Test-Path -LiteralPath $pomPath -PathType Leaf
    $hasGradle = $false
    foreach ($gradleFile in @($gradleCandidates)) {
        if (Test-Path -LiteralPath (Join-Path $resolvedPath $gradleFile) -PathType Leaf) {
            $hasGradle = $true
            Add-AuditUniqueValue $notableFiles $gradleFile
        }
    }
    if (-not $hasPom -and -not $hasGradle) { return }

    Add-AuditUniqueValue $languages "java"
    if ($hasPom) {
        Add-AuditUniqueValue $notableFiles "pom.xml"
        Add-AuditUniqueValue $packageManagers "maven"
        Add-AuditUniqueValue $buildCommands "mvn -B -DskipTests package"
        Add-AuditUniqueValue $testCommands "mvn -B test"
        try {
            $pomRaw = Get-ContentUtf8 $pomPath
            if ([regex]::IsMatch($pomRaw, "(?i)spring-boot")) { Add-AuditUniqueValue $frameworks "spring-boot" }
            if ([regex]::IsMatch($pomRaw, "(?i)junit")) { Add-AuditUniqueValue $testCommands "mvn -B test" }
        }
        catch {
        }
    }
    if ($hasGradle) {
        Add-AuditUniqueValue $packageManagers "gradle"
        Add-AuditUniqueValue $buildCommands "gradle build"
        Add-AuditUniqueValue $testCommands "gradle test"
        foreach ($gradleFile in @("build.gradle", "build.gradle.kts")) {
            $gradlePath = Join-Path $resolvedPath $gradleFile
            if (-not (Test-Path -LiteralPath $gradlePath -PathType Leaf)) { continue }
            try {
                $gradleRaw = Get-ContentUtf8 $gradlePath
                if ([regex]::IsMatch($gradleRaw, "(?i)spring-boot")) { Add-AuditUniqueValue $frameworks "spring-boot" }
            }
            catch {
            }
        }
    }
    if (Test-Path -LiteralPath (Join-Path $resolvedPath "mvnw") -PathType Leaf) {
        Add-AuditUniqueValue $notableFiles "mvnw"
        Add-AuditUniqueValue $buildCommands "./mvnw -B -DskipTests package"
        Add-AuditUniqueValue $testCommands "./mvnw -B test"
    }
    if (Test-Path -LiteralPath (Join-Path $resolvedPath "gradlew") -PathType Leaf) {
        Add-AuditUniqueValue $notableFiles "gradlew"
        Add-AuditUniqueValue $buildCommands "./gradlew build"
        Add-AuditUniqueValue $testCommands "./gradlew test"
    }
}

function Add-AuditRubyFacts([string]$resolvedPath, [System.Collections.Generic.List[string]]$languages, [System.Collections.Generic.List[string]]$frameworks, [System.Collections.Generic.List[string]]$packageManagers, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$testCommands, [System.Collections.Generic.List[string]]$notableFiles) {
    $gemfilePath = Join-Path $resolvedPath "Gemfile"
    $gemspecFiles = @(Get-ChildItem -LiteralPath $resolvedPath -Filter "*.gemspec" -File -ErrorAction SilentlyContinue | Select-Object -First 10)
    $hasGemfile = Test-Path -LiteralPath $gemfilePath -PathType Leaf
    if (-not $hasGemfile -and $gemspecFiles.Count -eq 0) { return }

    Add-AuditUniqueValue $languages "ruby"
    Add-AuditUniqueValue $packageManagers "bundler"
    Add-AuditUniqueValue $buildCommands "bundle install"
    Add-AuditUniqueValue $testCommands "bundle exec rspec"
    if ($hasGemfile) {
        Add-AuditUniqueValue $notableFiles "Gemfile"
        try {
            $gemRaw = Get-ContentUtf8 $gemfilePath
            if ([regex]::IsMatch($gemRaw, "(?i)\brails\b")) { Add-AuditUniqueValue $frameworks "rails" }
            if ([regex]::IsMatch($gemRaw, "(?i)\brspec\b")) { Add-AuditUniqueValue $testCommands "bundle exec rspec" }
            if ([regex]::IsMatch($gemRaw, "(?i)\bminitest\b")) { Add-AuditUniqueValue $testCommands "bundle exec ruby -Itest" }
        }
        catch {
        }
    }
    if (Test-Path -LiteralPath (Join-Path $resolvedPath "Gemfile.lock") -PathType Leaf) {
        Add-AuditUniqueValue $notableFiles "Gemfile.lock"
    }
    if (Test-Path -LiteralPath (Join-Path $resolvedPath "Rakefile") -PathType Leaf) {
        Add-AuditUniqueValue $notableFiles "Rakefile"
        Add-AuditUniqueValue $buildCommands "bundle exec rake build"
    }
    foreach ($gemspec in @($gemspecFiles)) {
        Add-AuditUniqueValue $notableFiles (Get-AuditRepositoryRelativePath $resolvedPath $gemspec.FullName)
    }
}

function Add-AuditPhpFacts([string]$resolvedPath, [System.Collections.Generic.List[string]]$languages, [System.Collections.Generic.List[string]]$frameworks, [System.Collections.Generic.List[string]]$packageManagers, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$testCommands, [System.Collections.Generic.List[string]]$notableFiles) {
    $composerPath = Join-Path $resolvedPath "composer.json"
    if (-not (Test-Path -LiteralPath $composerPath -PathType Leaf)) { return }
    Add-AuditUniqueValue $languages "php"
    Add-AuditUniqueValue $packageManagers "composer"
    Add-AuditUniqueValue $notableFiles "composer.json"
    Add-AuditUniqueValue $buildCommands "composer install --no-interaction"
    Add-AuditUniqueValue $testCommands "composer test"
    try {
        $composer = Get-ContentUtf8 $composerPath | ConvertFrom-Json
        $deps = @()
        $deps += Get-AuditPackagePropertyNames $composer "require"
        $deps += Get-AuditPackagePropertyNames $composer "require-dev"
        foreach ($dep in $deps) {
            if ([string]$dep -match "(?i)^laravel/framework$") { Add-AuditUniqueValue $frameworks "laravel" }
            if ([string]$dep -match "(?i)^symfony/") { Add-AuditUniqueValue $frameworks "symfony" }
            if ([string]$dep -match "(?i)^phpunit/phpunit$") { Add-AuditUniqueValue $testCommands "vendor/bin/phpunit" }
        }
        $scripts = Get-AuditPackagePropertyNames $composer "scripts"
        if ($scripts -contains "test") { Add-AuditUniqueValue $testCommands "composer test" }
        if ($scripts -contains "build") { Add-AuditUniqueValue $buildCommands "composer build" }
    }
    catch {
    }
    foreach ($phpunit in @("phpunit.xml", "phpunit.xml.dist")) {
        if (Test-Path -LiteralPath (Join-Path $resolvedPath $phpunit) -PathType Leaf) {
            Add-AuditUniqueValue $notableFiles $phpunit
            Add-AuditUniqueValue $testCommands "vendor/bin/phpunit"
        }
    }
    if (Test-Path -LiteralPath (Join-Path $resolvedPath "composer.lock") -PathType Leaf) {
        Add-AuditUniqueValue $notableFiles "composer.lock"
    }
}

function Add-AuditContainerFacts([string]$resolvedPath, [System.Collections.Generic.List[string]]$frameworks, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$notableFiles) {
    $hasContainer = $false
    foreach ($dockerFile in @("Dockerfile", "docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml")) {
        $path = Join-Path $resolvedPath $dockerFile
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        Add-AuditUniqueValue $notableFiles $dockerFile
        $hasContainer = $true
    }
    if (-not $hasContainer) { return }
    Add-AuditUniqueValue $frameworks "docker"
    Add-AuditUniqueValue $buildCommands "docker build ."
    Add-AuditUniqueValue $buildCommands "docker compose up --build"
}

function Add-AuditMonorepoFacts([string]$resolvedPath, [System.Collections.Generic.List[string]]$frameworks, [System.Collections.Generic.List[string]]$packageManagers, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$testCommands, [System.Collections.Generic.List[string]]$notableFiles) {
    if (Test-Path -LiteralPath (Join-Path $resolvedPath "pnpm-workspace.yaml") -PathType Leaf) {
        Add-AuditUniqueValue $notableFiles "pnpm-workspace.yaml"
        Add-AuditUniqueValue $frameworks "monorepo"
        Add-AuditUniqueValue $packageManagers "pnpm"
        Add-AuditUniqueValue $buildCommands "pnpm -r build"
        Add-AuditUniqueValue $testCommands "pnpm -r test"
    }
    if (Test-Path -LiteralPath (Join-Path $resolvedPath "turbo.json") -PathType Leaf) {
        Add-AuditUniqueValue $notableFiles "turbo.json"
        Add-AuditUniqueValue $frameworks "turbo"
        Add-AuditUniqueValue $frameworks "monorepo"
        Add-AuditUniqueValue $buildCommands "npx turbo run build"
        Add-AuditUniqueValue $testCommands "npx turbo run test"
    }
    if (Test-Path -LiteralPath (Join-Path $resolvedPath "nx.json") -PathType Leaf) {
        Add-AuditUniqueValue $notableFiles "nx.json"
        Add-AuditUniqueValue $frameworks "nx"
        Add-AuditUniqueValue $frameworks "monorepo"
        Add-AuditUniqueValue $buildCommands "npx nx run-many -t build"
        Add-AuditUniqueValue $testCommands "npx nx run-many -t test"
    }
    if (Test-Path -LiteralPath (Join-Path $resolvedPath "lerna.json") -PathType Leaf) {
        Add-AuditUniqueValue $notableFiles "lerna.json"
        Add-AuditUniqueValue $frameworks "lerna"
        Add-AuditUniqueValue $frameworks "monorepo"
        Add-AuditUniqueValue $buildCommands "npx lerna run build"
        Add-AuditUniqueValue $testCommands "npx lerna run test"
    }
}

function Add-AuditDotnetFacts([string]$resolvedPath, [System.Collections.Generic.List[string]]$frameworks, [System.Collections.Generic.List[string]]$packageManagers, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$testCommands, [System.Collections.Generic.List[string]]$notableFiles) {
    $slnFiles = @(Get-ChildItem -LiteralPath $resolvedPath -Filter "*.sln" -File -ErrorAction SilentlyContinue | Select-Object -First 10)
    $csprojFiles = @(Get-ChildItem -LiteralPath $resolvedPath -Filter "*.csproj" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 40)
    if ($slnFiles.Count -eq 0 -and $csprojFiles.Count -eq 0) { return }
    Add-AuditUniqueValue $packageManagers "nuget"
    Add-AuditUniqueValue $buildCommands "dotnet build"
    $hasTests = $false
    foreach ($sln in @($slnFiles)) {
        Add-AuditUniqueValue $notableFiles (Get-AuditRepositoryRelativePath $resolvedPath $sln.FullName)
    }
    foreach ($proj in @($csprojFiles)) {
        Add-AuditUniqueValue $notableFiles (Get-AuditRepositoryRelativePath $resolvedPath $proj.FullName)
        if ($proj.Name -match "(?i)test") { $hasTests = $true }
        try {
            $xml = [xml](Get-ContentUtf8 $proj.FullName)
        }
        catch {
            continue
        }
        $projectNode = $xml.Project
        if ($null -ne $projectNode -and $projectNode.Attributes["Sdk"]) {
            $sdk = [string]$projectNode.Attributes["Sdk"].Value
            if ($sdk -match "(?i)web") { Add-AuditUniqueValue $frameworks "aspnetcore" }
        }
        $packageRefs = @($xml.SelectNodes("//PackageReference"))
        foreach ($ref in $packageRefs) {
            $include = ""
            if ($ref.Attributes["Include"]) { $include = [string]$ref.Attributes["Include"].Value }
            if ([string]::IsNullOrWhiteSpace($include)) { continue }
            if ($include -match "(?i)Microsoft\.AspNetCore") { Add-AuditUniqueValue $frameworks "aspnetcore" }
            if ($include -match "(?i)EntityFrameworkCore") { Add-AuditUniqueValue $frameworks "efcore" }
            if ($include -match "(?i)xunit|nunit|mstest|Microsoft\.NET\.Test\.Sdk") { $hasTests = $true }
        }
    }
    if ($hasTests -or $slnFiles.Count -gt 0) {
        Add-AuditUniqueValue $testCommands "dotnet test"
    }
}

function Get-AuditGitInfo([string]$resolvedPath) {
    $info = [ordered]@{
        is_repo = $false
        branch = ""
        commit = ""
        dirty = $false
    }
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container)) { return [pscustomobject]$info }

    Push-Location $resolvedPath
    try {
        $inside = (& git rev-parse --is-inside-work-tree 2>$null)
        if ($LASTEXITCODE -eq 0 -and [string]$inside -eq "true") {
            $info.is_repo = $true
            $branch = (& git rev-parse --abbrev-ref HEAD 2>$null)
            if ($LASTEXITCODE -eq 0) { $info.branch = ([string]$branch).Trim() }
            $commit = (& git rev-parse HEAD 2>$null)
            if ($LASTEXITCODE -eq 0) { $info.commit = ([string]$commit).Trim() }
            $status = @(& git status --porcelain 2>$null)
            if ($LASTEXITCODE -eq 0) { $info.dirty = ($status.Count -gt 0) }
        }
    }
    finally {
        Pop-Location
    }
    return [pscustomobject]$info
}

function New-AuditRepoScan([string]$targetName, [string]$resolvedPath, [string]$inputPath) {
    $exists = Test-Path -LiteralPath $resolvedPath -PathType Container
    $risks = New-Object System.Collections.Generic.List[string]
    $languages = New-Object System.Collections.Generic.List[string]
    $packageManagers = New-Object System.Collections.Generic.List[string]
    $frameworks = New-Object System.Collections.Generic.List[string]
    $buildCommands = New-Object System.Collections.Generic.List[string]
    $testCommands = New-Object System.Collections.Generic.List[string]
    $agentRuleFiles = New-Object System.Collections.Generic.List[string]
    $notableFiles = New-Object System.Collections.Generic.List[string]

    if (-not $exists) {
        Add-AuditUniqueValue $risks "target_missing"
    }

    $gitInfo = Get-AuditGitInfo $resolvedPath
    if ($exists -and -not $gitInfo.is_repo) {
        Add-AuditUniqueValue $risks "not_a_git_repo"
    }
    if ($gitInfo.dirty) {
        Add-AuditUniqueValue $risks "git_dirty"
    }

    if ($exists) {
        $pkg = Get-AuditPackageJson $resolvedPath
        if ($pkg) {
            Add-AuditUniqueValue $packageManagers "npm"
            Add-AuditUniqueValue $languages "javascript"
            Add-AuditUniqueValue $notableFiles "package.json"

            $deps = @()
            $deps += Get-AuditPackagePropertyNames $pkg "dependencies"
            $deps += Get-AuditPackagePropertyNames $pkg "devDependencies"
            foreach ($dep in $deps) {
                switch -Regex ($dep) {
                    "^vite$" { Add-AuditUniqueValue $frameworks "vite" }
                    "^next$" { Add-AuditUniqueValue $frameworks "nextjs" }
                    "^react$" { Add-AuditUniqueValue $frameworks "react" }
                    "^vue$" { Add-AuditUniqueValue $frameworks "vue" }
                    "^svelte$" { Add-AuditUniqueValue $frameworks "svelte" }
                    "^@playwright/test$" { Add-AuditUniqueValue $frameworks "playwright" }
                }
            }

            $scripts = Get-AuditPackageScriptNames $pkg
            if ($scripts -contains "build") { Add-AuditUniqueValue $buildCommands "npm run build" }
            if ($scripts -contains "test") { Add-AuditUniqueValue $testCommands "npm test" }
            if ($scripts -contains "test:ci") { Add-AuditUniqueValue $testCommands "npm run test:ci" }
            if ($scripts -contains "ci:test") { Add-AuditUniqueValue $testCommands "npm run ci:test" }
            if ($scripts -contains "typecheck") { Add-AuditUniqueValue $buildCommands "npm run typecheck" }
            if ($pkg.PSObject.Properties.Match("packageManager").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$pkg.packageManager)) {
                $pm = ([string]$pkg.packageManager).Trim().ToLowerInvariant()
                if ($pm.StartsWith("pnpm@")) { Add-AuditUniqueValue $packageManagers "pnpm" }
                elseif ($pm.StartsWith("yarn@")) { Add-AuditUniqueValue $packageManagers "yarn" }
                elseif ($pm.StartsWith("npm@")) { Add-AuditUniqueValue $packageManagers "npm" }
            }
        }

        if (Test-AuditFile $resolvedPath "pnpm-lock.yaml") { Add-AuditUniqueValue $packageManagers "pnpm"; Add-AuditUniqueValue $notableFiles "pnpm-lock.yaml" }
        if (Test-AuditFile $resolvedPath "yarn.lock") { Add-AuditUniqueValue $packageManagers "yarn"; Add-AuditUniqueValue $notableFiles "yarn.lock" }
        if (Test-AuditFile $resolvedPath "package-lock.json") { Add-AuditUniqueValue $packageManagers "npm"; Add-AuditUniqueValue $notableFiles "package-lock.json" }
        if (Test-AuditFile $resolvedPath "pyproject.toml") { Add-AuditUniqueValue $languages "python"; Add-AuditUniqueValue $notableFiles "pyproject.toml"; Add-AuditUniqueValue $packageManagers "pip" }
        if (Test-AuditFile $resolvedPath "requirements.txt") { Add-AuditUniqueValue $languages "python"; Add-AuditUniqueValue $notableFiles "requirements.txt"; Add-AuditUniqueValue $packageManagers "pip" }
        if (Test-AuditFile $resolvedPath "uv.lock") { Add-AuditUniqueValue $packageManagers "uv"; Add-AuditUniqueValue $notableFiles "uv.lock" }
        if (Test-AuditFile $resolvedPath "go.mod") { Add-AuditUniqueValue $languages "go"; Add-AuditUniqueValue $notableFiles "go.mod" }
        if (Test-AuditFile $resolvedPath "Cargo.toml") { Add-AuditUniqueValue $languages "rust"; Add-AuditUniqueValue $notableFiles "Cargo.toml" }

        foreach ($viteFile in @("vite.config.js", "vite.config.ts", "vite.config.mjs", "vite.config.mts")) {
            if (Test-AuditFile $resolvedPath $viteFile) {
                Add-AuditUniqueValue $frameworks "vite"
                Add-AuditUniqueValue $notableFiles $viteFile
            }
        }
        foreach ($nextFile in @("next.config.js", "next.config.ts", "next.config.mjs")) {
            if (Test-AuditFile $resolvedPath $nextFile) {
                Add-AuditUniqueValue $frameworks "nextjs"
                Add-AuditUniqueValue $notableFiles $nextFile
            }
        }
        foreach ($playwrightFile in @("playwright.config.js", "playwright.config.ts", "playwright.config.mjs")) {
            if (Test-AuditFile $resolvedPath $playwrightFile) {
                Add-AuditUniqueValue $frameworks "playwright"
                Add-AuditUniqueValue $notableFiles $playwrightFile
            }
        }
        foreach ($ruleFile in @("AGENTS.md", "CLAUDE.md", "GEMINI.md")) {
            if (Test-AuditFile $resolvedPath $ruleFile) {
                Add-AuditUniqueValue $agentRuleFiles $ruleFile
                Add-AuditUniqueValue $notableFiles $ruleFile
            }
        }
        Add-AuditMonorepoFacts $resolvedPath $frameworks $packageManagers $buildCommands $testCommands $notableFiles
        Add-AuditContainerFacts $resolvedPath $frameworks $buildCommands $notableFiles
        Add-AuditPyProjectFacts $resolvedPath $frameworks $packageManagers $buildCommands $testCommands $notableFiles
        Add-AuditJavaFacts $resolvedPath $languages $frameworks $packageManagers $buildCommands $testCommands $notableFiles
        Add-AuditRubyFacts $resolvedPath $languages $frameworks $packageManagers $buildCommands $testCommands $notableFiles
        Add-AuditPhpFacts $resolvedPath $languages $frameworks $packageManagers $buildCommands $testCommands $notableFiles
        Add-AuditMakefileFacts $resolvedPath $buildCommands $testCommands $notableFiles
        Add-AuditDotnetFacts $resolvedPath $frameworks $packageManagers $buildCommands $testCommands $notableFiles
        Add-AuditCiWorkflowFacts $resolvedPath $buildCommands $testCommands $notableFiles
        $slnFiles = @(Get-ChildItem -LiteralPath $resolvedPath -Filter "*.sln" -File -ErrorAction SilentlyContinue)
        $csprojFiles = @(Get-ChildItem -LiteralPath $resolvedPath -Filter "*.csproj" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($slnFiles.Count -gt 0 -or $csprojFiles.Count -gt 0) {
            Add-AuditUniqueValue $languages "dotnet"
        }
    }

    return [pscustomobject]([ordered]@{
        schema_version = 1
        scanned_at = (Get-Date).ToString("o")
        target = [ordered]@{
            name = $targetName
            path = $inputPath
            resolved_path = $resolvedPath
            exists = $exists
        }
        git = $gitInfo
        detected = [ordered]@{
            languages = @($languages)
            package_managers = @($packageManagers)
            frameworks = @($frameworks)
            build_commands = @($buildCommands)
            test_commands = @($testCommands)
            agent_rule_files = @($agentRuleFiles)
            notable_files = @($notableFiles)
        }
        risks = @($risks)
    })
}

function Get-AuditKeywordsFromText([string]$text, [int]$Limit = 120) {
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $ordered = New-Object System.Collections.Generic.List[string]
    foreach ($match in [regex]::Matches($text, "(?i)\b[a-z][a-z0-9_-]{2,}\b")) {
        $token = ([string]$match.Value).Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($token)) { continue }
        if ($seen.Add($token)) {
            $ordered.Add($token) | Out-Null
            if ($ordered.Count -ge $Limit) { return @($ordered) }
        }
    }
    foreach ($match in [regex]::Matches($text, "[\u4e00-\u9fff]{2,}")) {
        $token = ([string]$match.Value).Trim()
        if ([string]::IsNullOrWhiteSpace($token)) { continue }
        if ($seen.Add($token)) {
            $ordered.Add($token) | Out-Null
            if ($ordered.Count -ge $Limit) { return @($ordered) }
        }
    }
    return @($ordered)
}

function Merge-AuditKeywordSets([object[]]$Sets, [int]$Limit = 160) {
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $ordered = New-Object System.Collections.Generic.List[string]
    foreach ($set in @($Sets)) {
        foreach ($token in @(Convert-AuditStringArray $set)) {
            if ($seen.Add($token)) {
                $ordered.Add($token) | Out-Null
                if ($ordered.Count -ge $Limit) { return @($ordered) }
            }
        }
    }
    return @($ordered)
}

function Get-AuditUserProfileKeywords($cfg) {
    if ($null -eq $cfg -or $cfg.PSObject.Properties.Match("user_profile").Count -eq 0 -or $null -eq $cfg.user_profile) {
        return @()
    }
    $profile = $cfg.user_profile
    $sets = New-Object System.Collections.Generic.List[object]
    $sets.Add((Get-AuditKeywordsFromText ([string]$profile.raw_text) 80)) | Out-Null
    $sets.Add((Get-AuditKeywordsFromText ([string]$profile.summary) 80)) | Out-Null
    if (Test-AuditObjectLike $profile.structured) {
        foreach ($field in @("primary_work_types", "preferred_agents", "tech_stack", "common_tasks", "constraints", "avoidances", "decision_preferences")) {
            $fieldValue = $null
            if (Get-AuditObjectFieldValue $profile.structured $field ([ref]$fieldValue)) {
                $sets.Add((Convert-AuditStringArray $fieldValue)) | Out-Null
            }
        }
    }
    return (Merge-AuditKeywordSets ($sets.ToArray()) 200)
}

function Get-AuditRepoScanKeywords($scan) {
    if ($null -eq $scan) { return @() }
    $sets = New-Object System.Collections.Generic.List[object]
    if ($scan.PSObject.Properties.Match("target").Count -gt 0 -and $null -ne $scan.target) {
        if ($scan.target.PSObject.Properties.Match("name").Count -gt 0) {
            $sets.Add((Get-AuditKeywordsFromText ([string]$scan.target.name) 12)) | Out-Null
        }
    }
    if ($scan.PSObject.Properties.Match("detected").Count -gt 0 -and $null -ne $scan.detected) {
        foreach ($name in @("languages", "package_managers", "frameworks", "build_commands", "test_commands", "agent_rule_files", "notable_files")) {
            if ($scan.detected.PSObject.Properties.Match($name).Count -gt 0) {
                $sets.Add((Convert-AuditStringArray $scan.detected.$name)) | Out-Null
            }
        }
    }
    if ($scan.PSObject.Properties.Match("risks").Count -gt 0) {
        $sets.Add((Convert-AuditStringArray $scan.risks)) | Out-Null
    }
    return (Merge-AuditKeywordSets ($sets.ToArray()) 180)
}

function Get-AuditInstalledStateKeywords($installedSkills, $installedMcpServers) {
    $sets = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($installedSkills)) {
        $sets.Add((Get-AuditKeywordsFromText ([string]$item.name) 20)) | Out-Null
        $sets.Add((Get-AuditKeywordsFromText ([string]$item.description) 30)) | Out-Null
        $sets.Add((Get-AuditKeywordsFromText ([string]$item.trigger_summary) 30)) | Out-Null
        $sets.Add((Convert-AuditStringArray @([string]$item.vendor, [string]$item.source_kind))) | Out-Null
    }
    foreach ($server in @($installedMcpServers)) {
        $sets.Add((Convert-AuditStringArray @([string]$server.name, [string]$server.transport))) | Out-Null
    }
    return (Merge-AuditKeywordSets ($sets.ToArray()) 240)
}

function Get-AuditKeywordHitDetails([string]$text, [string[]]$keywords, [int]$MaxHits = 6) {
    $hits = New-Object System.Collections.Generic.List[string]
    $source = if ([string]::IsNullOrWhiteSpace($text)) { "" } else { $text.ToLowerInvariant() }
    foreach ($keyword in @(Convert-AuditStringArray $keywords)) {
        $needle = [string]$keyword
        if ([string]::IsNullOrWhiteSpace($needle)) { continue }
        if ($source.Contains($needle.ToLowerInvariant())) {
            $hits.Add($needle) | Out-Null
            if ($hits.Count -ge $MaxHits) { break }
        }
    }
    return @($hits)
}

function Get-AuditInstalledSkillFitSummary($installedSkills, [string[]]$userKeywords, [string[]]$repoKeywords) {
    $rows = @()
    foreach ($item in @($installedSkills)) {
        $text = ("{0} {1} {2}" -f [string]$item.name, [string]$item.description, [string]$item.trigger_summary)
        $userHits = Get-AuditKeywordHitDetails $text $userKeywords 8
        $repoHits = Get-AuditKeywordHitDetails $text $repoKeywords 8
        $rows += [pscustomobject]([ordered]@{
                name = [string]$item.name
                vendor = [string]$item.vendor
                from = [string]$item.from
                score = @($userHits).Count * 2 + @($repoHits).Count
                user_hit_count = @($userHits).Count
                repo_hit_count = @($repoHits).Count
                user_hits = @($userHits)
                repo_hits = @($repoHits)
            })
    }
    return @($rows | Sort-Object -Property @{ Expression = { [int]$_.score }; Descending = $true }, @{ Expression = { [int]$_.user_hit_count }; Descending = $true }, @{ Expression = { [string]$_.name } })
}

function Get-AuditMissingPreferredAgents($cfg, $installedSkills) {
    if ($null -eq $cfg -or $cfg.PSObject.Properties.Match("user_profile").Count -eq 0 -or $null -eq $cfg.user_profile) { return @() }
    if (-not (Test-AuditObjectLike $cfg.user_profile.structured)) { return @() }
    $preferred = @()
    $raw = $null
    if (Get-AuditObjectFieldValue $cfg.user_profile.structured "preferred_agents" ([ref]$raw)) {
        $preferred = @(Convert-AuditStringArray $raw)
    }
    if ($preferred.Count -eq 0) { return @() }
    $installedTokens = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($installedSkills)) {
        foreach ($token in @([string]$item.name, [string]$item.to, [string]$item.from, [string]$item.declared_name)) {
            if ([string]::IsNullOrWhiteSpace($token)) { continue }
            $installedTokens.Add($token.ToLowerInvariant()) | Out-Null
        }
    }
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($pref in @($preferred)) {
        $needle = ([string]$pref).ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($needle)) { continue }
        $matched = $false
        foreach ($token in @($installedTokens)) {
            if ($token.Contains($needle) -or $needle.Contains($token)) {
                $matched = $true
                break
            }
        }
        if (-not $matched) {
            $missing.Add([string]$pref) | Out-Null
        }
    }
    return @($missing)
}

function New-AuditDecisionInsights($cfg, $scans, $installedSkills, $installedMcpServers, [string]$Mode = "target-repo") {
    $normalizedMode = if ([string]::IsNullOrWhiteSpace($Mode)) { "target-repo" } else { $Mode.ToLowerInvariant() }
    $userKeywords = @(Get-AuditUserProfileKeywords $cfg)
    $repoKeywordSets = @()
    foreach ($scan in @($scans)) {
        $targetName = if ($scan.PSObject.Properties.Match("target").Count -gt 0 -and $null -ne $scan.target -and $scan.target.PSObject.Properties.Match("name").Count -gt 0) { [string]$scan.target.name } else { "*" }
        $repoKeywordSets += [pscustomobject]([ordered]@{
                target = $targetName
                keywords = @(Get-AuditRepoScanKeywords $scan)
                risks = if ($scan.PSObject.Properties.Match("risks").Count -gt 0) { @(Convert-AuditStringArray $scan.risks) } else { @() }
            })
    }
    $repoKeywords = @()
    if (@($repoKeywordSets).Count -gt 0) {
        $repoKeywords = @(Merge-AuditKeywordSets @($repoKeywordSets | ForEach-Object { $_.keywords }) 220)
    }
    $installedKeywords = @(Get-AuditInstalledStateKeywords $installedSkills $installedMcpServers)
    $fitRows = @(Get-AuditInstalledSkillFitSummary $installedSkills $userKeywords $repoKeywords)
    $topFit = @($fitRows | Select-Object -First 20)
    $lowFit = @($fitRows | Where-Object { [int]$_.score -le 1 } | Select-Object -First 20)
    $profileOnlyContext = @(Merge-AuditKeywordSets @($userKeywords, $installedKeywords) 180)
    return [pscustomobject]([ordered]@{
            schema_version = 1
            generated_at = (Get-Date).ToString("o")
            mode = $normalizedMode
            summary = [ordered]@{
                user_keyword_count = @($userKeywords).Count
                repo_keyword_count = @($repoKeywords).Count
                installed_state_keyword_count = @($installedKeywords).Count
                installed_skill_count = @($installedSkills).Count
                installed_mcp_server_count = @($installedMcpServers).Count
            }
            keywords = [ordered]@{
                user_profile = @($userKeywords)
                target_repo = @($repoKeywords)
                installed_state = @($installedKeywords)
                profile_only_context = @($profileOnlyContext)
            }
            targets = @($repoKeywordSets)
            fit = [ordered]@{
                top_installed_skill_matches = @($topFit)
                low_fit_installed_skills = @($lowFit)
                missing_preferred_agents = @(Get-AuditMissingPreferredAgents $cfg $installedSkills)
            }
            decision_checklist = @(
                "Each add/remove recommendation should keep keyword_trace.user_profile with keywords from decision-insights.keywords.user_profile.",
                "In target-repo mode, keyword_trace.target_repo_or_context should align with decision-insights.keywords.target_repo.",
                "In profile-only mode, keyword_trace.target_repo_or_context should align with decision-insights.keywords.profile_only_context.",
                "keyword_trace.installed_state should align with decision-insights.keywords.installed_state."
            )
        })
}

function Write-AuditJsonFile([string]$path, $data) {
    EnsureDir (Split-Path $path -Parent)
    Set-ContentUtf8 $path ($data | ConvertTo-Json -Depth 40)
}

function Write-AuditAiBrief([string]$path, $scanData, [string]$userProfilePath, [string]$repoScanPath, [string]$repoScansPath, [string]$installedSkillsPath, [string]$templatePath, [string]$Mode = "target-repo", [string]$Query = "", [string]$SourceStrategyPath = "", [string]$DecisionInsightsPath = "") {
    $normalizedMode = if ([string]::IsNullOrWhiteSpace($Mode)) { "target-repo" } else { $Mode.ToLowerInvariant() }
    $targetNames = @($scanData | ForEach-Object { $_.target.name })
    if ([string]::IsNullOrWhiteSpace($repoScanPath)) { $repoScanPath = "N/A" }
    if ([string]::IsNullOrWhiteSpace($repoScansPath)) { $repoScansPath = "N/A" }
    if ([string]::IsNullOrWhiteSpace($SourceStrategyPath)) { $SourceStrategyPath = "N/A" }
    if ([string]::IsNullOrWhiteSpace($DecisionInsightsPath)) { $DecisionInsightsPath = "N/A" }
    $recommendationsPath = Join-Path (Split-Path $path -Parent) "recommendations.json"

    if ($normalizedMode -eq "profile-only") {
        $queryText = if ([string]::IsNullOrWhiteSpace($Query)) { "N/A" } else { $Query }
        $content = @"
# Skill Audit Brief

Run ID: $(Split-Path (Split-Path $path -Parent) -Leaf)
Mode: profile-only skill discovery
Targets: N/A
Discovery query: $queryText

Use the generated user profile JSON, installed-skills snapshot JSON, and source strategy JSON to decide:

- Which installed skills should be kept for the user's long-term workflow.
- Which installed skills should be proposed for removal because they no longer fit.
- Which installed MCP servers should be kept or removed.
- Which missing skills are strongly justified without binding the decision to a target repository.
- Which missing MCP servers are strongly justified without binding the decision to a target repository.

External research is intentionally performed by the outer AI agent. Search official documentation, MCP provider documentation, security/permission notes, strong community projects, best practices, https://skills.sh/, GitHub Trending, and the find-skills workflow.

Primary output file (must be valid JSON, no prose):

$templatePath

Scan inputs:
- Single-target scan JSON: N/A
- Multi-target scans JSON: N/A
- Source strategy JSON: $SourceStrategyPath
- Decision insights JSON: $DecisionInsightsPath

Rules:

- Profile-only mode has no target repo scan; do not fabricate repository facts.
- Only write ``recommendations.json`` in this run directory. Do not modify generated input files, snapshots, prompts, briefs, templates, source strategy, decision insights, or repo scan files.
- All decisions must be based on user-profile.json, installed-skills.json (audit snapshot, not live source of truth), source-strategy.json, and real external research.
- decision-insights.json provides machine-readable keyword anchors; every add/remove skill or MCP recommendation should keep ``keyword_trace.user_profile`` + ``keyword_trace.target_repo_or_context`` + ``keyword_trace.installed_state`` aligned to it.
- Treat source-strategy.json ``evidence_policy`` and ``decision_quality_policy`` as hard constraints.
- Use ``reason_target_repo`` to explain the current installed-skill inventory / profile-only context; do not claim target repository evidence.
- If any required local input is missing, unreadable, or empty, stop and report the blocker instead of guessing.
- Network research is authorized within this audit workflow, but installation still requires --apply --yes.
- Replace every template placeholder wrapped in `<...>` or delete the example entry entirely; do not leave placeholder values in the final file.
- Keep ``recommendation_mode`` as ``profile-only``.
- Keep ``decision_basis.user_profile_used`` and ``decision_basis.source_strategy_used`` as boolean ``true``; keep ``decision_basis.target_scan_used`` as boolean ``false``; provide a non-empty ``decision_basis.summary``.
- Record ``source_observations`` for researched candidates; every selected skill/MCP add/remove recommendation must have a matching observation with real sources and matching candidate_type/name/decision.
- Skill installs require ``reason_user_profile``, ``reason_target_repo``, source links, confidence, repo, skill path, ref, and mode.
- Skill removals must include ``reason_user_profile``, ``reason_target_repo``, sources, and the exact installed ``vendor``/``from`` pair.
- MCP installs must include ``reason_user_profile``, ``reason_target_repo``, sources, confidence, a valid ``server`` payload, and provider/security evidence when available.
- MCP removals must include ``reason_user_profile``, ``reason_target_repo``, sources, and ``installed.name``.
- Skill ``install.mode`` must stay ``manual`` or ``vendor``; ``confidence`` must stay ``low``, ``medium``, or ``high``.
- MCP ``server.transport`` must stay ``stdio``/``sse``/``http``; ``stdio`` requires ``command``; ``sse/http`` requires ``url``.
- Each add/remove recommendation must keep both reasons concise and user-readable.
- If either reason field is missing on any recommendation, treat the run as incomplete and stop before dry-run summary.
- Overlap findings are report-only; do not recommend automatic uninstall.
- Use ``do_not_install`` for researched options that should stay out of the repo right now.
- Prefer high-reputation sources and avoid weak duplicate skills.
- Cover the built-in default sources and record the actual sources you used; GitHub Trending is discovery evidence only, never sufficient by itself.
- Keep recommendations machine-readable JSON matching the template.
- The template already includes placeholder example items. Replace placeholder values or delete the example entries you do not need; do not invent a different schema.
- Cite only sources you actually inspected during this run. Do not fabricate source links, source observations, or source conclusions.
- If evidence is insufficient, leave the category empty and explain briefly instead of forcing low-quality recommendations.
- After dry-run, show numbered skill add/remove and MCP add/remove lists with one-line reasons per item (``reason_user_profile`` + ``reason_target_repo``).
- If a list is empty, explicitly output "no <category> recommendations" with a brief reason.
- Keep dry-run numbering stable; do not renumber or reorder indexes in the user-facing summary.

Pre-dry-run self-check:

- recommendations.json parses as JSON and keeps ``schema_version = 2``.
- ``recommendation_mode`` is ``profile-only``.
- ``decision_basis.user_profile_used`` and ``decision_basis.source_strategy_used`` are ``true``.
- ``decision_basis.target_scan_used`` is ``false``.
- No remaining placeholder values wrapped in `<...>`.
- Each skill/MCP add/remove item has both reasons plus at least one real source.
- Each selected skill/MCP add/remove item has a matching ``source_observations`` entry with real sources.
- Each skill/MCP add/remove item keeps non-empty ``keyword_trace`` arrays (user_profile / target_repo_or_context / installed_state).
- No duplicate skill add/remove or MCP add/remove recommendations remain in the final file.
- Stop before dry-run if any self-check item fails.

Execution order:

1) Read all local inputs
2) Write ``recommendations.json`` from ``recommendations.template.json`` to ``$recommendationsPath``
3) Run the self-check and stop if any item fails
4) Execute preflight: ``.\skills.ps1 审查目标 预检 --recommendations "$recommendationsPath"``
5) Execute dry-run
6) Summarize dry-run with original indexes and one-line dual-reason entries
7) Wait for explicit user confirmation before apply

User-facing dry-run summary format:

- add: ``[index] <skill-name> | user: <reason_user_profile> | context: <reason_target_repo>``
- remove: ``[index] <skill-name> | user: <reason_user_profile> | context: <reason_target_repo>``
- mcp-add: ``[index] <mcp-name> | user: <reason_user_profile> | context: <reason_target_repo>``
- mcp-remove: ``[index] <mcp-name> | user: <reason_user_profile> | context: <reason_target_repo>``
- empty category: ``no add recommendations: <brief reason>`` / ``no removal recommendations: <brief reason>`` / ``no mcp-add recommendations: <brief reason>`` / ``no mcp-remove recommendations: <brief reason>``

User profile JSON: $userProfilePath
Installed skills JSON: $installedSkillsPath
Source strategy JSON: $SourceStrategyPath
Decision insights JSON: $DecisionInsightsPath
"@
        Set-ContentUtf8 $path $content
        return
    }

    $content = @"
# Skill Audit Brief

Run ID: $(Split-Path (Split-Path $path -Parent) -Leaf)
Targets: $($targetNames -join ", ")

Use the generated user profile JSON, repo scan JSON, and installed-skills snapshot JSON to decide:

- Which installed skills should be kept for each target repository.
- Which installed skills should be proposed for removal.
- Which installed MCP servers should be kept for each target repository.
- Which installed MCP servers should be proposed for removal.
- Which missing skills are strongly justified for these targets.
- Which missing MCP servers are strongly justified for these targets.

External research is intentionally performed by the outer AI agent. Search official documentation, MCP provider documentation, security/permission notes, strong community projects, best practices, https://skills.sh/, GitHub Trending, and the find-skills workflow.

Primary output file (must be valid JSON, no prose):

$templatePath

Scan inputs:
- Single-target scan JSON: $repoScanPath
- Multi-target scans JSON: $repoScansPath
- Source strategy JSON: $SourceStrategyPath
- Decision insights JSON: $DecisionInsightsPath

Rules:

- All decisions must be based on BOTH user-profile.json and target repo scan facts, and must use installed-skills.json as the audit snapshot for currently installed skills and MCP servers.
- Only write ``recommendations.json`` in this run directory. Do not modify generated input files, snapshots, prompts, briefs, templates, source strategy, decision insights, or repo scan files.
- Use source-strategy.json to cover the built-in source set and explain source tradeoffs.
- decision-insights.json provides machine-readable keyword anchors; every add/remove skill or MCP recommendation should keep ``keyword_trace.user_profile`` + ``keyword_trace.target_repo_or_context`` + ``keyword_trace.installed_state`` aligned to it.
- Treat source-strategy.json ``evidence_policy`` and ``decision_quality_policy`` as hard constraints.
- Treat any scan path shown as ``N/A`` as "not provided"; do not infer hidden content from it.
- If any required local input is missing, unreadable, or empty, stop and report the blocker instead of guessing.
- Network research is authorized within this audit workflow, but installation still requires --apply --yes.
- Replace every template placeholder wrapped in `<...>` or delete the example entry entirely; do not leave placeholder values in the final file.
- Keep ``decision_basis.user_profile_used``, ``decision_basis.target_scan_used``, and ``decision_basis.source_strategy_used`` as boolean ``true``, and provide a non-empty ``decision_basis.summary``.
- Record ``source_observations`` for researched candidates; every selected skill/MCP add/remove recommendation must have a matching observation with real sources and matching candidate_type/name/decision.
- Skill installs require ``reason_user_profile``, ``reason_target_repo``, source links, confidence, repo, skill path, ref, and mode.
- Skill removals must include ``reason_user_profile``, ``reason_target_repo``, sources, and the exact installed ``vendor``/``from`` pair.
- MCP installs must include ``reason_user_profile``, ``reason_target_repo``, sources, confidence, a valid ``server`` payload, and provider/security evidence when available.
- MCP removals must include ``reason_user_profile``, ``reason_target_repo``, sources, and ``installed.name``.
- Skill ``install.mode`` must stay ``manual`` or ``vendor``; ``confidence`` must stay ``low``, ``medium``, or ``high``.
- MCP ``server.transport`` must stay ``stdio``/``sse``/``http``; ``stdio`` requires ``command``; ``sse/http`` requires ``url``.
- Each add/remove recommendation must keep both reasons concise and user-readable.
- If either reason field is missing on any recommendation, treat the run as incomplete and stop before dry-run summary.
- Overlap findings are report-only; do not recommend automatic uninstall.
- Use ``do_not_install`` for researched options that should stay out of the repo right now.
- Prefer high-reputation sources and avoid weak duplicate skills.
- Cover the built-in default sources and record the actual sources you used; GitHub Trending is discovery evidence only, never sufficient by itself.
- Keep recommendations machine-readable JSON matching the template.
- The template already includes placeholder example items. Replace placeholder values or delete the example entries you do not need; do not invent a different schema.
- Cite only sources you actually inspected during this run. Do not fabricate repository facts, source links, source observations, or source conclusions.
- If evidence is insufficient, leave the category empty and explain briefly instead of forcing low-quality recommendations.
- After dry-run, show numbered skill add/remove and MCP add/remove lists with one-line reasons per item (``reason_user_profile`` + ``reason_target_repo``).
- If a list is empty, explicitly output "no <category> recommendations" with a brief reason.
- Keep dry-run numbering stable; do not renumber or reorder indexes in the user-facing summary.

Pre-dry-run self-check:

- recommendations.json parses as JSON and keeps ``schema_version = 2``.
- ``decision_basis`` keeps all required boolean flags at ``true``.
- ``decision_basis.summary`` is non-empty.
- No remaining placeholder values wrapped in `<...>`.
- Each skill/MCP add/remove item has both reasons plus at least one real source.
- Each selected skill/MCP add/remove item has a matching ``source_observations`` entry with real sources.
- Each skill/MCP add/remove item keeps non-empty ``keyword_trace`` arrays (user_profile / target_repo_or_context / installed_state).
- Each MCP add item keeps ``name == server.name``.
- No duplicate skill add/remove or MCP add/remove recommendations remain in the final file.
- Stop before dry-run if any self-check item fails.

Execution order:

1) Read all local inputs
2) Write ``recommendations.json`` from ``recommendations.template.json`` to ``$recommendationsPath``
3) Run the self-check and stop if any item fails
4) Execute preflight: ``.\skills.ps1 审查目标 预检 --recommendations "$recommendationsPath"``
5) Execute dry-run
6) Summarize dry-run with original indexes and one-line dual-reason entries
7) Wait for explicit user confirmation before apply

User-facing dry-run summary format:

- add: ``[index] <skill-name> | user: <reason_user_profile> | repo: <reason_target_repo>``
- remove: ``[index] <skill-name> | user: <reason_user_profile> | repo: <reason_target_repo>``
- mcp-add: ``[index] <mcp-name> | user: <reason_user_profile> | repo: <reason_target_repo>``
- mcp-remove: ``[index] <mcp-name> | user: <reason_user_profile> | repo: <reason_target_repo>``
- empty category: `no add recommendations: <brief reason>` / `no removal recommendations: <brief reason>` / `no mcp-add recommendations: <brief reason>` / `no mcp-remove recommendations: <brief reason>`

User profile JSON: $userProfilePath
Installed skills JSON: $installedSkillsPath
Source strategy JSON: $SourceStrategyPath
Decision insights JSON: $DecisionInsightsPath
"@
    Set-ContentUtf8 $path $content
}

function Write-AuditOuterAiPromptFile([string]$path, [string]$reportRoot, [string]$briefPath, [string]$userProfilePath, [string]$repoScanPath, [string]$repoScansPath, [string]$installedSkillsPath, [string]$templatePath, [string]$Mode = "target-repo", [string]$Query = "", [string]$SourceStrategyPath = "", [string]$DecisionInsightsPath = "") {
    $normalizedMode = if ([string]::IsNullOrWhiteSpace($Mode)) { "target-repo" } else { $Mode.ToLowerInvariant() }
    if ([string]::IsNullOrWhiteSpace($repoScanPath)) { $repoScanPath = "N/A" }
    if ([string]::IsNullOrWhiteSpace($repoScansPath)) { $repoScansPath = "N/A" }
    if ([string]::IsNullOrWhiteSpace($SourceStrategyPath)) { $SourceStrategyPath = "N/A" }
    if ([string]::IsNullOrWhiteSpace($DecisionInsightsPath)) { $DecisionInsightsPath = "N/A" }
    $queryText = if ([string]::IsNullOrWhiteSpace($Query)) { "N/A" } else { $Query }
    $inputReadStep = if ($normalizedMode -eq "profile-only") {
        "1. 阅读 ai-brief.md、user-profile.json、installed-skills.json、source-strategy.json、decision-insights.json；repo-scan 输入为 N/A 时代表本轮不绑定目标仓；这些文件只能读，不能改。"
    }
    else {
        "1. 阅读 ai-brief.md、user-profile.json、installed-skills.json，并按存在文件读取 repo-scan.json / repo-scans.json，同时读取 source-strategy.json 与 decision-insights.json；这些文件只能读，不能改。"
    }
    $basisCheckStep = if ($normalizedMode -eq "profile-only") {
        "   - recommendations.json 与模板字段同构，``recommendation_mode = profile-only``，``decision_basis.user_profile_used`` / ``decision_basis.source_strategy_used`` 为 ``true``，``decision_basis.target_scan_used`` 为 ``false``，且 ``decision_basis.summary`` 非空"
    }
    else {
        "   - recommendations.json 与模板字段同构，``decision_basis`` 三个布尔字段都为 ``true``，且 ``decision_basis.summary`` 非空"
    }
    $modeBlocking = if ($normalizedMode -eq "profile-only") {
        '- 本轮是 profile-only；不得编造目标仓事实，``reason_target_repo`` 必须解释当前已安装技能 / profile-only 场景依据'
    }
    else {
        "- 若 ``repo-scan.json`` / ``repo-scans.json`` 路径显示为 ``N/A``，表示该输入未提供，不可臆造其内容"
    }
    $content = @"
$(Get-AuditOuterAiPromptContent)

---

## Current Audit Run Files

- 审查包目录：$reportRoot
- Prompt-Contract-Version: $(Get-AuditPromptContractVersion)
- 模式：$normalizedMode
- 发现查询：$queryText
- 任务说明：$briefPath
- 用户画像：$userProfilePath
- 单目标扫描：$repoScanPath
- 多目标扫描：$repoScansPath
- 已安装技能与 MCP：$installedSkillsPath
- 来源策略：$SourceStrategyPath
- 决策洞察：$DecisionInsightsPath
- 推荐模板：$templatePath

## Required Execution Sequence

$inputReadStep
2. 按 recommendations.template.json schema v2 写出 recommendations.json
3. 先做自检（全部通过后再 dry-run）：
   - recommendations.json 可解析为 JSON，且 ``schema_version = 2``
$basisCheckStep
   - 不保留模板占位符 ``<...>`` 或未替换的示例值
   - 每条技能/MCP 新增或卸载建议都包含 ``reason_user_profile`` + ``reason_target_repo`` + 至少 1 个真实 ``sources``
   - 每条技能/MCP 新增或卸载建议都有匹配的 ``source_observations`` 记录，且 observation 也包含真实 ``sources``
   - 每条技能/MCP 新增或卸载建议都包含非空 ``keyword_trace.user_profile`` / ``keyword_trace.target_repo_or_context`` / ``keyword_trace.installed_state``
   - 技能新增建议的 ``install.mode`` 只能是 ``manual`` 或 ``vendor``，``confidence`` 只能是 ``low`` / ``medium`` / ``high``
   - MCP 新增建议必须包含合法 ``server``（``transport``=``stdio``/``sse``/``http``；``stdio`` 要有 ``command``，``sse/http`` 要有 ``url``），且 ``name`` 必须等于 ``server.name``
   - 不得保留重复的技能新增/卸载建议或重复的 MCP 新增/卸载建议
4. 执行预检；失败即停止，不得绕过：
   .\skills.ps1 审查目标 预检 --recommendations "$([System.IO.Path]::Combine($reportRoot, 'recommendations.json'))"
5. 执行 dry-run：
   .\skills.ps1 审查目标 应用 --recommendations "$([System.IO.Path]::Combine($reportRoot, 'recommendations.json'))" --dry-run-ack "我知道未落盘"
6. 根据 dry-run 结果，向用户列出“技能新增/卸载建议 + MCP 新增/卸载建议”及序号
7. 等待用户确认后，再执行：
   .\skills.ps1 审查目标 应用 --recommendations "$([System.IO.Path]::Combine($reportRoot, 'recommendations.json'))" --apply --yes

## Output Contract

- ``recommendations.json`` 必须与模板 schema 一致
- 除 ``recommendations.json`` 外，不得修改本轮审查包输入文件、快照、提示词、brief、模板、来源策略、决策洞察或 repo scan
- 技能与 MCP 的新增/卸载建议都必须保留双依据和来源，且每项理由要简短可读
- ``source_observations`` 必须记录本轮调研过的候选项；被选中的新增/卸载项必须能在其中找到对应 candidate_type/name/decision
- 若 ``source-strategy.decision_quality_policy`` 开启，``keyword_trace`` 必须满足最小命中与关键词归属校验
- 若任一建议缺少 ``reason_user_profile`` 或 ``reason_target_repo``，视为未完成，不得进入下一步
- 若证据不足，允许不推荐；不得“猜测式”新增/卸载
- 目标仓模式下，新增/卸载技能或 MCP 的判断必须同时参考用户画像、目标仓事实、已安装技能/MCP 快照、来源策略
- ``overlap_findings`` 仅用于报告重叠，``do_not_install`` 用于记录“已研究但当前不应安装”的技能或 MCP
- ``sources`` 只能填写本轮真实查看过的来源；不得伪造仓库事实或来源结论
- MCP 新增建议里 ``name`` 与 ``server.name`` 必须一致；任一类别不得出现重复建议
- 如果你继续执行 dry-run，请在总结里按 dry-run 原序号列出“技能新增/卸载建议 + MCP 新增/卸载建议”
- 每条建议必须同时展示两条简短理由（用户需求 + 目标仓/场景）
- 某一类为空时，必须显式写“无该类建议”并给 1 句简短原因
- 未经用户明确确认，不得执行 --apply --yes

## Blocking Conditions

- 任一必需输入文件缺失、为空或不可读时，立即停止并汇报阻断项
$modeBlocking
- 若自检或预检失败、仍有 ``<...>`` 占位符、或来源并非本轮真实查看结果，必须先修正再继续

## User Summary Format

- 新增建议：``[序号] <skill-name> | 用户需求：<reason_user_profile> | 目标仓/场景：<reason_target_repo>``
- 卸载建议：``[序号] <skill-name> | 用户需求：<reason_user_profile> | 目标仓/场景：<reason_target_repo>``
- MCP 新增建议：``[序号] <mcp-name> | 用户需求：<reason_user_profile> | 目标仓/场景：<reason_target_repo>``
- MCP 卸载建议：``[序号] <mcp-name> | 用户需求：<reason_user_profile> | 目标仓/场景：<reason_target_repo>``
- 空列表：``无新增建议：<简短原因>`` / ``无卸载建议：<简短原因>`` / ``无 MCP 新增建议：<简短原因>`` / ``无 MCP 卸载建议：<简短原因>``
"@
    Set-ContentUtf8 $path $content
}



function Get-AuditSourceStrategyOverridePath {
    return (Join-Path $script:Root "overrides\audit-source-strategy.json")
}

function Test-AuditMergeObjectLike($value) {
    if ($null -eq $value) { return $false }
    return ($value -is [pscustomobject]) -or ($value -is [hashtable]) -or ($value -is [System.Collections.IDictionary])
}

function Convert-AuditMergeValue($value) {
    if ($null -eq $value) { return $null }
    if ($value -is [System.Collections.IDictionary]) {
        $obj = [ordered]@{}
        foreach ($key in $value.Keys) {
            $obj[[string]$key] = Convert-AuditMergeValue $value[$key]
        }
        return $obj
    }
    if ($value -is [pscustomobject]) {
        $obj = [ordered]@{}
        foreach ($prop in $value.PSObject.Properties) {
            $obj[[string]$prop.Name] = Convert-AuditMergeValue $prop.Value
        }
        return $obj
    }
    if (Assert-IsArray $value) {
        $arr = New-Object System.Collections.Generic.List[object]
        foreach ($item in @($value)) {
            $arr.Add((Convert-AuditMergeValue $item)) | Out-Null
        }
        return $arr.ToArray()
    }
    return $value
}

function Convert-AuditMergeToObject($value) {
    if ($null -eq $value) { return $null }
    if ($value -is [System.Collections.IDictionary]) {
        $obj = [ordered]@{}
        foreach ($key in $value.Keys) {
            $obj[[string]$key] = Convert-AuditMergeToObject $value[$key]
        }
        return [pscustomobject]$obj
    }
    if (Assert-IsArray $value) {
        $arr = New-Object System.Collections.Generic.List[object]
        foreach ($item in @($value)) {
            $arr.Add((Convert-AuditMergeToObject $item)) | Out-Null
        }
        return $arr.ToArray()
    }
    return $value
}

function Merge-AuditHashtableDeep($base, $patch) {
    if (-not (Test-AuditMergeObjectLike $base)) {
        return (Convert-AuditMergeValue $patch)
    }
    if (-not (Test-AuditMergeObjectLike $patch)) {
        return (Convert-AuditMergeValue $patch)
    }
    $baseMap = Convert-AuditMergeValue $base
    $patchMap = Convert-AuditMergeValue $patch
    foreach ($key in $patchMap.Keys) {
        $next = $patchMap[$key]
        if ($baseMap.Contains($key) -and (Test-AuditMergeObjectLike $baseMap[$key]) -and (Test-AuditMergeObjectLike $next)) {
            $baseMap[$key] = Merge-AuditHashtableDeep $baseMap[$key] $next
        }
        else {
            $baseMap[$key] = $next
        }
    }
    return $baseMap
}

function Apply-AuditSourceStrategyOverride($strategy, [string]$mode) {
    $path = Get-AuditSourceStrategyOverridePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $strategy
    }
    try {
        $raw = Get-ContentUtf8 $path
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $strategy
        }
        $override = $raw | ConvertFrom-Json
    }
    catch {
        Log ("audit-source-strategy override 解析失败，忽略覆盖：{0}" -f $_.Exception.Message) "WARN"
        return $strategy
    }
    if (-not (Test-AuditMergeObjectLike $override)) {
        return $strategy
    }

    $patches = New-Object System.Collections.Generic.List[object]
    if (Test-AuditJsonProperty $override "all" -and (Test-AuditMergeObjectLike $override.all)) {
        $patches.Add($override.all) | Out-Null
    }
    if (Test-AuditJsonProperty $override $mode -and (Test-AuditMergeObjectLike $override.$mode)) {
        $patches.Add($override.$mode) | Out-Null
    }
    if ($patches.Count -eq 0) {
        $patches.Add($override) | Out-Null
    }

    $merged = Convert-AuditMergeValue $strategy
    foreach ($patch in $patches) {
        $merged = Merge-AuditHashtableDeep $merged $patch
    }
    return (Convert-AuditMergeToObject $merged)
}

function New-AuditSourceStrategy([string]$Mode = "target-repo", [string]$Query = "") {
    $normalizedMode = if ([string]::IsNullOrWhiteSpace($Mode)) { "target-repo" } else { $Mode.ToLowerInvariant() }
    Need ($normalizedMode -eq "target-repo" -or $normalizedMode -eq "profile-only") ("未知审查来源模式：{0}" -f $Mode)
    $strategy = [pscustomobject]([ordered]@{
            schema_version = 1
            mode = $normalizedMode
            query = [string]$Query
            sources = @(
                [ordered]@{
                    id = "official-docs"
                    name = "Official documentation"
                    use_for = "Verify current APIs, platform rules, support status, and recommended implementation patterns."
                },
                [ordered]@{
                    id = "mcp-provider-docs"
                    name = "MCP provider documentation"
                    use_for = "Verify MCP server availability, transport, auth model, required args, permissions, and support status before recommending install or removal."
                },
                [ordered]@{
                    id = "skills-sh"
                    name = "skills.sh"
                    use_for = "Discover skill-packaged implementations and compare skill metadata quality."
                },
                [ordered]@{
                    id = "github-trending-monthly"
                    name = "GitHub Trending monthly"
                    url = "https://github.com/trending?since=monthly"
                    use_for = "Find active, recently relevant community projects; never treat popularity alone as enough evidence."
                },
                [ordered]@{
                    id = "strong-community-projects"
                    name = "High-quality community projects"
                    use_for = "Check maintenance activity, examples, issues, releases, and adoption fit."
                },
                [ordered]@{
                    id = "best-practices"
                    name = "Best-practice guides"
                    use_for = "Compare proposed skills against mature workflow and operational guidance."
                },
                [ordered]@{
                    id = "security-and-permission-notes"
                    name = "Security and permission notes"
                    use_for = "Check auth, token scope, data access, network exposure, and rollback concerns, especially for MCP servers."
                },
                [ordered]@{
                    id = "find-skills"
                    name = "Installed find-skills workflow"
                    use_for = "Use the local skill discovery workflow as an input source when available."
                }
            )
            scoring = [ordered]@{
                authority = "Prefer first-party documentation and maintained source repositories."
                fit = "Match the user's structured profile and, in target-repo mode, concrete repo scan facts."
                duplication_risk = "Penalize recommendations that duplicate installed skills without a clear incremental benefit."
                maintenance = "Prefer projects with recent activity, clear license, and usable documentation."
                operational_cost = "Prefer skills that are easy to install, verify, and roll back."
            }
            evidence_policy = [ordered]@{
                min_unique_sources_for_changes = 2
                require_http_source_for_changes = $true
                require_source_observations_for_changes = $true
            }
            decision_quality_policy = [ordered]@{
                require_keyword_trace_for_changes = $true
                require_keyword_trace_membership = $true
                min_user_profile_keywords_per_change = 1
                min_target_repo_keywords_per_change = 1
                min_installed_state_keywords_per_change = 1
            }
            required_evidence = @(
                "Every add/remove recommendation must cite sources inspected in this run.",
                "Do not fabricate repository facts, source links, or source conclusions.",
                "Record source_observations for researched candidates so selected, rejected, and removed items remain auditable.",
                "Every change recommendation should include keyword_trace (user_profile / target_repo_or_context / installed_state) and keep these values aligned with decision-insights.json.",
                "For MCP recommendations, prefer provider documentation and security/permission notes over popularity signals.",
                "For profile-only mode, explain reason_target_repo as installed-skill inventory / profile-only context, not as a target repository claim."
            )
        })
    $strategy = Apply-AuditSourceStrategyOverride $strategy $normalizedMode
    if ($strategy.PSObject.Properties.Match("mode").Count -eq 0) {
        $strategy | Add-Member -NotePropertyName mode -NotePropertyValue $normalizedMode -Force
    }
    else {
        $strategy.mode = $normalizedMode
    }
    if ($strategy.PSObject.Properties.Match("query").Count -eq 0) {
        $strategy | Add-Member -NotePropertyName query -NotePropertyValue ([string]$Query) -Force
    }
    else {
        $strategy.query = [string]$Query
    }
    return $strategy
}

function Test-AuditJsonProperty($obj, [string]$name) {
    if ($null -eq $obj) { return $false }
    return ($obj.PSObject.Properties.Match($name).Count -gt 0)
}

function Assert-AuditBundleFileContent([string]$path, [string]$label) {
    $raw = Get-ContentUtf8 $path
    Need (-not [string]::IsNullOrWhiteSpace($raw)) ("审查包文件为空：{0} -> {1}" -f $label, $path)

    $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    if ($ext -eq ".md") { return }
    if ($ext -ne ".json") { return }

    try {
        $data = $raw | ConvertFrom-Json
    }
    catch {
        throw ("审查包 JSON 解析失败：{0} -> {1}；{2}" -f $label, $path, $_.Exception.Message)
    }
    Need ($null -ne $data) ("审查包 JSON 为空对象：{0} -> {1}" -f $label, $path)

    switch ($label) {
        "user-profile.json" {
            Need (Test-AuditJsonProperty $data "raw_text") ("user-profile 缺少 raw_text：{0}" -f $path)
            Need (-not [string]::IsNullOrWhiteSpace([string]$data.raw_text)) ("user-profile.raw_text 不能为空：{0}" -f $path)
            Need (Test-AuditJsonProperty $data "summary") ("user-profile 缺少 summary：{0}" -f $path)
            Need (-not [string]::IsNullOrWhiteSpace([string]$data.summary)) ("user-profile.summary 不能为空：{0}" -f $path)
            Need (Test-AuditJsonProperty $data "structured") ("user-profile 缺少 structured：{0}" -f $path)
            Need (Test-AuditStructuredProfileComplete $data.structured) ("user-profile.structured 不完整：{0}" -f $path)
            Need (Test-AuditJsonProperty $data "last_structured_at") ("user-profile 缺少 last_structured_at：{0}" -f $path)
            Need (Test-AuditTimestampString ([string]$data.last_structured_at)) ("user-profile.last_structured_at 无效：{0}" -f $path)
        }
        "installed-skills.json" {
            Need (Test-AuditJsonProperty $data "skills") ("installed-skills 缺少 skills：{0}" -f $path)
            Need (Assert-IsArray $data.skills) ("installed-skills.skills 必须为数组：{0}" -f $path)
            if (Test-AuditJsonProperty $data "mcp_servers") {
                Need (Assert-IsArray $data.mcp_servers) ("installed-skills.mcp_servers 必须为数组：{0}" -f $path)
            }
            if (Test-AuditJsonProperty $data "snapshot_kind") {
                Need ([string]$data.snapshot_kind -eq "audit_input") ("installed-skills.snapshot_kind 必须为 audit_input：{0}" -f $path)
            }
        }
        "source-strategy.json" {
            Need (Test-AuditJsonProperty $data "mode") ("source-strategy 缺少 mode：{0}" -f $path)
            Need (Test-AuditJsonProperty $data "sources") ("source-strategy 缺少 sources：{0}" -f $path)
            Need (Assert-IsArray $data.sources) ("source-strategy.sources 必须为数组：{0}" -f $path)
            Need (@($data.sources).Count -gt 0) ("source-strategy.sources 不能为空：{0}" -f $path)
            if (Test-AuditJsonProperty $data "evidence_policy" -and $null -ne $data.evidence_policy) {
                Need (Test-AuditJsonProperty $data.evidence_policy "min_unique_sources_for_changes") ("source-strategy.evidence_policy 缺少 min_unique_sources_for_changes：{0}" -f $path)
                Need ([int]$data.evidence_policy.min_unique_sources_for_changes -ge 1) ("source-strategy.evidence_policy.min_unique_sources_for_changes 必须 >= 1：{0}" -f $path)
            }
            if (Test-AuditJsonProperty $data "decision_quality_policy" -and $null -ne $data.decision_quality_policy) {
                Need (Test-AuditJsonProperty $data.decision_quality_policy "require_keyword_trace_for_changes") ("source-strategy.decision_quality_policy 缺少 require_keyword_trace_for_changes：{0}" -f $path)
                Need (Test-AuditJsonProperty $data.decision_quality_policy "require_keyword_trace_membership") ("source-strategy.decision_quality_policy 缺少 require_keyword_trace_membership：{0}" -f $path)
                Need (Test-AuditJsonProperty $data.decision_quality_policy "min_user_profile_keywords_per_change") ("source-strategy.decision_quality_policy 缺少 min_user_profile_keywords_per_change：{0}" -f $path)
                Need (Test-AuditJsonProperty $data.decision_quality_policy "min_target_repo_keywords_per_change") ("source-strategy.decision_quality_policy 缺少 min_target_repo_keywords_per_change：{0}" -f $path)
                Need (Test-AuditJsonProperty $data.decision_quality_policy "min_installed_state_keywords_per_change") ("source-strategy.decision_quality_policy 缺少 min_installed_state_keywords_per_change：{0}" -f $path)
            }
        }
        "recommendations.template.json" {
            Need (Test-AuditJsonProperty $data "schema_version") ("recommendations.template 缺少 schema_version：{0}" -f $path)
            Need ([int]$data.schema_version -eq 2) ("recommendations.template schema_version 必须为 2：{0}" -f $path)
            Need (Test-AuditJsonProperty $data "decision_basis") ("recommendations.template 缺少 decision_basis：{0}" -f $path)
        }
        "repo-scan.json" {
            Need (Test-AuditJsonProperty $data "target") ("repo-scan 缺少 target：{0}" -f $path)
            Need (Test-AuditJsonProperty $data "detected") ("repo-scan 缺少 detected：{0}" -f $path)
        }
        "repo-scans.json" {
            Need (Test-AuditJsonProperty $data "scans") ("repo-scans 缺少 scans：{0}" -f $path)
            Need (Assert-IsArray $data.scans) ("repo-scans.scans 必须为数组：{0}" -f $path)
            Need (@($data.scans).Count -gt 0) ("repo-scans.scans 不能为空：{0}" -f $path)
        }
        "decision-insights.json" {
            Need (Test-AuditJsonProperty $data "mode") ("decision-insights 缺少 mode：{0}" -f $path)
            Need (Test-AuditJsonProperty $data "keywords") ("decision-insights 缺少 keywords：{0}" -f $path)
            Need (Test-AuditJsonProperty $data.keywords "user_profile") ("decision-insights.keywords 缺少 user_profile：{0}" -f $path)
            Need (Test-AuditJsonProperty $data.keywords "installed_state") ("decision-insights.keywords 缺少 installed_state：{0}" -f $path)
            Need (Assert-IsArray $data.keywords.user_profile) ("decision-insights.keywords.user_profile 必须为数组：{0}" -f $path)
            Need (Assert-IsArray $data.keywords.installed_state) ("decision-insights.keywords.installed_state 必须为数组：{0}" -f $path)
        }
    }
}

function Assert-AuditBundleRequiredFiles([object[]]$files) {
    foreach ($file in @($files)) {
        Need ($null -ne $file) "审查包关键产物定义不能为空"
        $path = [string]$file.path
        $label = [string]$file.label
        if ([string]::IsNullOrWhiteSpace($label)) { $label = $path }
        Need (-not [string]::IsNullOrWhiteSpace($path)) ("审查包关键产物路径不能为空：{0}" -f $label)
        Need (Test-Path -LiteralPath $path -PathType Leaf) ("审查包缺少关键产物：{0} -> {1}" -f $label, $path)
        Assert-AuditBundleFileContent $path $label
    }
}

function New-AuditRecommendationsTemplate([string]$runId, [string]$targetName, [string]$Mode = "target-repo", [string]$Query = "") {
    $normalizedMode = if ([string]::IsNullOrWhiteSpace($Mode)) { "target-repo" } else { $Mode.ToLowerInvariant() }
    Need ($normalizedMode -eq "target-repo" -or $normalizedMode -eq "profile-only") ("未知 recommendations 模式：{0}" -f $Mode)
    $isProfileOnly = ($normalizedMode -eq "profile-only")
    $targetScanUsed = -not $isProfileOnly
    $templateNotes = if ($isProfileOnly) {
        @(
            "Replace placeholder values wrapped in <> before using this file.",
            "Delete example entries that are not needed, but keep the schema shape unchanged.",
            "Record source_observations for every researched candidate; selected add/remove candidates must have matching observations.",
            "For every add/remove skill or MCP recommendation, keep keyword_trace aligned with decision-insights.json.",
            "This is profile-only skill discovery: reason_target_repo means installed-skill inventory / profile-only context, not target repository facts."
        )
    }
    else {
        @(
            "Replace placeholder values wrapped in <> before using this file.",
            "Delete example entries that are not needed, but keep the schema shape unchanged.",
            "Record source_observations for every researched candidate; selected add/remove candidates must have matching observations.",
            "For every add/remove skill or MCP recommendation, keep keyword_trace aligned with decision-insights.json.",
            "All install/remove decisions must cite both user-profile and target-repo reasons."
        )
    }
    $basisSummary = if ($isProfileOnly) {
        "<why these recommendations reflect the user profile, installed-skill inventory, and source strategy without target repo facts>"
    }
    else {
        "<why these recommendations reflect both the user profile and the target repo facts>"
    }
    $targetReasonInstall = if ($isProfileOnly) { "<which installed-skill inventory or profile-only context justifies this skill>" } else { "<which detected target-repo facts justify this skill>" }
    $targetReasonRemoval = if ($isProfileOnly) { "<why the installed-skill inventory or profile-only context no longer justifies this skill>" } else { "<why the target repo no longer justifies this skill>" }
    $targetReasonDoNotInstall = if ($isProfileOnly) { "<why the profile-only context does not justify it>" } else { "<why the target repo does not justify it>" }
    $targetKeywordHint = if ($isProfileOnly) { "<keyword from decision-insights.keywords.profile_only_context or target_repo>" } else { "<keyword from decision-insights.keywords.target_repo>" }
    return [pscustomobject]([ordered]@{
        schema_version = 2
        run_id = $runId
        target = $targetName
        recommendation_mode = $normalizedMode
        discovery_query = [string]$Query
        template_notes = @($templateNotes)
        decision_basis = [ordered]@{
            user_profile_used = $true
            target_scan_used = $targetScanUsed
            source_strategy_used = $true
            summary = $basisSummary
        }
        empty_recommendation_reasons = @("insufficient_reliable_evidence")
        source_observations = @(
            [ordered]@{
                candidate_type = "skill"
                name = "<candidate-name>"
                decision = "add"
                rationale = "<why this candidate was selected, rejected, kept, or removed>"
                sources = @("<source-url-1>")
                source_categories = @("official-docs", "skills.sh")
            },
            [ordered]@{
                candidate_type = "mcp"
                name = "<mcp-candidate-name>"
                decision = "do_not_install"
                rationale = "<why this MCP should not be installed now, including auth, permission, or maintenance concerns>"
                sources = @("<source-url-1>")
                source_categories = @("mcp-provider-docs", "security-and-permission-notes")
            }
        )
        new_skills = @(
            [ordered]@{
                name = "<new-skill-name>"
                reason_user_profile = "<why the user's long-term workflow benefits from this skill>"
                reason_target_repo = $targetReasonInstall
                install = [ordered]@{
                    repo = "<owner/repo-or-local-path>"
                    skill = "<relative-skill-path-or-.>"
                    ref = "<branch-or-tag>"
                    mode = "manual"
                }
                confidence = "medium"
                sources = @("<source-url-1>")
                source_categories = @("official-docs", "skills.sh")
                keyword_trace = [ordered]@{
                    user_profile = @("<keyword-from-user-profile>")
                    target_repo_or_context = @($targetKeywordHint)
                    installed_state = @("<keyword-from-installed-state>")
                }
            }
        )
        overlap_findings = @(
            [ordered]@{
                name = "<existing-skill-or-skill-pair>"
                reason_user_profile = "<why overlap matters for the user's workflow>"
                reason_target_repo = $targetReasonInstall
                sources = @("<source-url-1>")
                note = "<report-only observation; no automatic uninstall>"
            }
        )
        removal_candidates = @(
            [ordered]@{
                name = "<installed-skill-name>"
                reason_user_profile = "<why the user profile no longer justifies this skill>"
                reason_target_repo = $targetReasonRemoval
                sources = @("<source-url-1>")
                source_categories = @("official-docs")
                installed = [ordered]@{
                    vendor = "<installed-vendor>"
                    from = "<installed-from>"
                }
                keyword_trace = [ordered]@{
                    user_profile = @("<keyword-from-user-profile>")
                    target_repo_or_context = @($targetKeywordHint)
                    installed_state = @("<keyword-from-installed-state>")
                }
            }
        )
        do_not_install = @(
            [ordered]@{
                name = "<skill-not-recommended>"
                reason_user_profile = "<why the user profile does not justify it>"
                reason_target_repo = $targetReasonDoNotInstall
                sources = @("<source-url-1>")
                note = "<why it should not be added now>"
            }
        )
        mcp_new_servers = @(
            [ordered]@{
                name = "<mcp-server-name>"
                reason_user_profile = "<why the user's long-term workflow benefits from this MCP server>"
                reason_target_repo = $targetReasonInstall
                confidence = "medium"
                sources = @("<source-url-1>")
                source_categories = @("official-docs")
                server = [ordered]@{
                    name = "<mcp-server-name>"
                    transport = "stdio"
                    command = "<command>"
                    args = @("<arg1>")
                }
                keyword_trace = [ordered]@{
                    user_profile = @("<keyword-from-user-profile>")
                    target_repo_or_context = @($targetKeywordHint)
                    installed_state = @("<keyword-from-installed-state>")
                }
            }
        )
        mcp_removal_candidates = @(
            [ordered]@{
                name = "<installed-mcp-name>"
                reason_user_profile = "<why the user profile no longer justifies this MCP server>"
                reason_target_repo = $targetReasonRemoval
                sources = @("<source-url-1>")
                source_categories = @("official-docs")
                installed = [ordered]@{
                    name = "<installed-mcp-name>"
                }
                keyword_trace = [ordered]@{
                    user_profile = @("<keyword-from-user-profile>")
                    target_repo_or_context = @($targetKeywordHint)
                    installed_state = @("<keyword-from-installed-state>")
                }
            }
        )
    })
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

function Get-AuditMcpServerFacts($cfg = $null) {
    if ($null -eq $cfg) { $cfg = LoadCfg }
    $facts = @()
    $servers = @()
    if ($cfg.PSObject.Properties.Match("mcp_servers").Count -gt 0 -and $null -ne $cfg.mcp_servers) {
        $servers = @($cfg.mcp_servers)
    }
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
    $mcpServers = @()
    if ($cfg.PSObject.Properties.Match("mcp_servers").Count -gt 0 -and $null -ne $cfg.mcp_servers) {
        $mcpServers = @($cfg.mcp_servers)
    }
    return [pscustomobject]([ordered]@{
        source_of_truth = "live_mappings"
        captured_at = (Get-Date).ToString("o")
        skill_count = @($facts).Count
        fingerprint = (Get-AuditFingerprintFromSkillFacts $facts)
        mcp_server_count = @($mcpServers).Count
        mcp_fingerprint = (Get-AuditFingerprintFromMcpServers $mcpServers)
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
    $mcpFingerprint = ""
    if (Test-AuditJsonProperty $data "live_mcp_fingerprint") {
        $mcpFingerprint = ([string]$data.live_mcp_fingerprint).Trim().ToLowerInvariant()
    }
    if ([string]::IsNullOrWhiteSpace($mcpFingerprint) -and @($mcpServers).Count -gt 0) {
        $mcpFingerprint = (Get-AuditFingerprintFromMcpServers $mcpServers)
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
        mcp_server_count = @($mcpServers).Count
        mcp_fingerprint = $mcpFingerprint
    })
}

function New-AuditInstalledSnapshotFallbackState($liveState, [string]$snapshotPath) {
    return [pscustomobject]([ordered]@{
        path = $snapshotPath
        snapshot_kind = "legacy_live_fallback"
        captured_at = [string]$liveState.captured_at
        skill_count = [int]$liveState.skill_count
        fingerprint = [string]$liveState.fingerprint
        mcp_server_count = if ($liveState.PSObject.Properties.Match("mcp_server_count").Count -gt 0) { [int]$liveState.mcp_server_count } else { 0 }
        mcp_fingerprint = if ($liveState.PSObject.Properties.Match("mcp_fingerprint").Count -gt 0) { [string]$liveState.mcp_fingerprint } else { "" }
    })
}

function Ensure-AuditArrayProperty($obj, [string]$name) {
    if (-not $obj.PSObject.Properties.Match($name).Count -or $null -eq $obj.$name) {
        $obj | Add-Member -NotePropertyName $name -NotePropertyValue @() -Force
    }
    elseif (-not (Assert-IsArray $obj.$name)) {
        $obj.$name = @($obj.$name)
    }
}

function Normalize-AuditStringArray($value) {
    if ($null -eq $value) { return @() }
    $items = if (Assert-IsArray $value) { @($value) } else { @($value) }
    $normalized = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $items) {
        if ($null -eq $item) { continue }
        $text = ([string]$item).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($seen.Add($text)) {
            $normalized.Add($text) | Out-Null
        }
    }
    return @($normalized)
}

function Get-AuditRecommendationChangeItemCount($rec) {
    return @($rec.new_skills).Count + @($rec.removal_candidates).Count + @($rec.mcp_new_servers).Count + @($rec.mcp_removal_candidates).Count
}

function Normalize-AuditSourceObservationDecision([string]$decision) {
    $text = ([string]$decision).Trim().ToLowerInvariant()
    switch ($text) {
        "install" { return "add" }
        "selected" { return "add" }
        "uninstall" { return "remove" }
        "removed" { return "remove" }
        "skip" { return "do_not_install" }
        "reject" { return "do_not_install" }
        "rejected" { return "do_not_install" }
        "duplicate" { return "overlap" }
        default { return $text }
    }
}

function Assert-AuditSourceObservation($item) {
    Need ($null -ne $item) "source_observations 项不能为空"
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.name)) "source_observations 缺少 name"
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.candidate_type)) ("source_observations 缺少 candidate_type：{0}" -f [string]$item.name)
    $candidateType = ([string]$item.candidate_type).Trim().ToLowerInvariant()
    Need ($candidateType -eq "skill" -or $candidateType -eq "mcp") ("source_observations.candidate_type 仅支持 skill/mcp：{0}" -f $candidateType)
    $item.candidate_type = $candidateType

    Need (-not [string]::IsNullOrWhiteSpace([string]$item.decision)) ("source_observations 缺少 decision：{0}" -f [string]$item.name)
    $decision = Normalize-AuditSourceObservationDecision ([string]$item.decision)
    Need (@("add", "remove", "keep", "do_not_install", "overlap", "ignore") -contains $decision) ("source_observations.decision 不支持：{0}" -f [string]$item.decision)
    $item.decision = $decision

    Need (-not [string]::IsNullOrWhiteSpace([string]$item.rationale)) ("source_observations 缺少 rationale：{0}" -f [string]$item.name)
    Normalize-AuditSources $item "source_observations"
    if ($item.PSObject.Properties.Match("source_categories").Count -eq 0 -or $null -eq $item.source_categories) {
        $item | Add-Member -NotePropertyName source_categories -NotePropertyValue @() -Force
    }
    else {
        $item.source_categories = @(Normalize-AuditStringArray $item.source_categories)
    }
}

function Test-AuditHasSourceObservationForChange($rec, [string]$candidateType, [string]$decision, [string]$name) {
    $normalizedType = ([string]$candidateType).Trim().ToLowerInvariant()
    $normalizedDecision = Normalize-AuditSourceObservationDecision $decision
    $normalizedName = ([string]$name).Trim()
    foreach ($observation in @($rec.source_observations)) {
        if ($null -eq $observation) { continue }
        $obsType = ([string]$observation.candidate_type).Trim().ToLowerInvariant()
        $obsDecision = Normalize-AuditSourceObservationDecision ([string]$observation.decision)
        $obsName = ([string]$observation.name).Trim()
        if ($obsType -eq $normalizedType -and $obsDecision -eq $normalizedDecision -and $obsName -eq $normalizedName -and @($observation.sources).Count -gt 0) {
            return $true
        }
    }
    return $false
}

function Get-AuditRecommendationSourceCoverage($rec) {
    $allSources = New-Object System.Collections.Generic.List[string]
    foreach ($collection in @($rec.new_skills, $rec.removal_candidates, $rec.mcp_new_servers, $rec.mcp_removal_candidates)) {
        foreach ($item in @($collection)) {
            foreach ($source in @(Normalize-AuditStringArray $item.sources)) {
                $allSources.Add($source) | Out-Null
            }
        }
    }
    $uniqueSources = @(Normalize-AuditStringArray $allSources)
    $httpSources = @($uniqueSources | Where-Object { [regex]::IsMatch([string]$_, "^(?i)https?://") })
    $missingObservation = New-Object System.Collections.Generic.List[string]
    $itemsWithObservation = 0
    $changeGroups = @(
        @{ type = "skill"; decision = "add"; items = @($rec.new_skills) },
        @{ type = "skill"; decision = "remove"; items = @($rec.removal_candidates) },
        @{ type = "mcp"; decision = "add"; items = @($rec.mcp_new_servers) },
        @{ type = "mcp"; decision = "remove"; items = @($rec.mcp_removal_candidates) }
    )
    foreach ($group in @($changeGroups)) {
        foreach ($item in @($group.items)) {
            $itemName = [string]$item.name
            if (Test-AuditHasSourceObservationForChange $rec ([string]$group.type) ([string]$group.decision) $itemName) {
                $itemsWithObservation++
            }
            else {
                $missingObservation.Add(("{0}:{1}:{2}" -f [string]$group.type, [string]$group.decision, $itemName)) | Out-Null
            }
        }
    }
    return [pscustomobject]([ordered]@{
        total_change_items = Get-AuditRecommendationChangeItemCount $rec
        unique_sources = @($uniqueSources)
        unique_source_count = @($uniqueSources).Count
        http_source_count = @($httpSources).Count
        source_observation_count = @($rec.source_observations).Count
        items_with_source_observation = $itemsWithObservation
        change_items_missing_source_observation = @($missingObservation)
    })
}

function Normalize-AuditSources($item, [string]$kind) {
    Ensure-AuditArrayProperty $item "sources"
    $normalized = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($source in @($item.sources)) {
        if ($null -eq $source) { continue }
        $text = ([string]$source).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($seen.Add($text)) {
            $normalized.Add($text) | Out-Null
        }
    }
    $item.sources = @($normalized)
    Need (@($item.sources).Count -gt 0) ("{0} 至少需要一个非空 source：{1}" -f $kind, [string]$item.name)
}

function Normalize-AuditKeywordTrace($item) {
    $defaultTrace = [pscustomobject]([ordered]@{
            user_profile = @()
            target_repo_or_context = @()
            installed_state = @()
        })
    if ($item.PSObject.Properties.Match("keyword_trace").Count -eq 0 -or $null -eq $item.keyword_trace) {
        $item | Add-Member -NotePropertyName keyword_trace -NotePropertyValue $defaultTrace -Force
        return
    }
    Need (Test-AuditObjectLike $item.keyword_trace) ("keyword_trace 必须是对象：{0}" -f [string]$item.name)
    foreach ($field in @("user_profile", "target_repo_or_context", "installed_state")) {
        if ($item.keyword_trace.PSObject.Properties.Match($field).Count -eq 0 -or $null -eq $item.keyword_trace.$field) {
            $item.keyword_trace | Add-Member -NotePropertyName $field -NotePropertyValue @() -Force
        }
        else {
            $item.keyword_trace.$field = @(Normalize-AuditStringArray $item.keyword_trace.$field)
        }
    }
}

function Assert-AuditRequiredBooleanTrue($value, [string]$fieldName) {
    Need ($value -is [bool]) ("{0} 必须是布尔值 true" -f $fieldName)
    Need ([bool]$value) ("{0} 必须为 true" -f $fieldName)
}

function Assert-AuditReasonPair($item, [string]$name) {
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.reason_user_profile)) ("{0} 缺少 reason_user_profile：{1}" -f $name, [string]$item.name)
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.reason_target_repo)) ("{0} 缺少 reason_target_repo：{1}" -f $name, [string]$item.name)
    Normalize-AuditSources $item $name
    Normalize-AuditKeywordTrace $item
}

function Assert-AuditRecommendationItem($item) {
    Need ($null -ne $item) "推荐项不能为空"
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.name)) "推荐项缺少 name"
    Assert-AuditReasonPair $item "推荐项"
    Need ($item.PSObject.Properties.Match("install").Count -gt 0 -and $null -ne $item.install) ("推荐项缺少 install：{0}" -f [string]$item.name)

    $install = $item.install
    Need (-not [string]::IsNullOrWhiteSpace([string]$install.repo)) ("推荐项缺少 install.repo：{0}" -f [string]$item.name)
    Need (Looks-LikeRepoInput ([string]$install.repo)) ("install.repo 不是有效仓库输入：{0}" -f [string]$install.repo)

    Need ($install.PSObject.Properties.Match("skill").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$install.skill)) ("推荐项缺少 install.skill：{0}" -f [string]$item.name)
    $skillPath = [string]$install.skill
    $normalizedSkill = Normalize-SkillPath $skillPath
    Need (Test-SafeRelativePath $normalizedSkill -AllowDot) ("install.skill 路径非法：{0}" -f $skillPath)
    $install.skill = $normalizedSkill

    Need ($install.PSObject.Properties.Match("mode").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$install.mode)) ("推荐项缺少 install.mode：{0}" -f [string]$item.name)
    $mode = [string]$install.mode
    $mode = $mode.ToLowerInvariant()
    Need ($mode -eq "manual" -or $mode -eq "vendor") ("install.mode 仅支持 manual 或 vendor：{0}" -f $mode)
    $install.mode = $mode

    $confidence = ([string]$item.confidence).ToLowerInvariant()
    Need ($confidence -eq "low" -or $confidence -eq "medium" -or $confidence -eq "high") ("confidence 仅支持 low/medium/high：{0}" -f [string]$item.confidence)
    $item.confidence = $confidence
    $item | Add-Member -NotePropertyName reason -NotePropertyValue ("用户需求：{0}；目标仓/场景：{1}" -f [string]$item.reason_user_profile, [string]$item.reason_target_repo) -Force
}

function Assert-AuditRemovalCandidate($item) {
    Need ($null -ne $item) "卸载建议不能为空"
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.name)) "卸载建议缺少 name"
    Assert-AuditReasonPair $item "卸载建议"
    Need ($item.PSObject.Properties.Match("installed").Count -gt 0 -and $null -ne $item.installed) ("卸载建议缺少 installed：{0}" -f [string]$item.name)
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.installed.vendor)) ("卸载建议缺少 installed.vendor：{0}" -f [string]$item.name)
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.installed.from)) ("卸载建议缺少 installed.from：{0}" -f [string]$item.name)
}

function Assert-AuditMcpServerPayload($server, [string]$itemName) {
    Need ($null -ne $server) ("MCP 新增建议缺少 server：{0}" -f $itemName)
    Need (-not [string]::IsNullOrWhiteSpace([string]$server.name)) ("MCP 新增建议缺少 server.name：{0}" -f $itemName)
    $transport = if ($server.PSObject.Properties.Match("transport").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$server.transport)) {
        ([string]$server.transport).Trim().ToLowerInvariant()
    }
    else {
        "stdio"
    }
    Need ($transport -eq "stdio" -or $transport -eq "sse" -or $transport -eq "http") ("MCP transport 仅支持 stdio/sse/http：{0}" -f $transport)
    $server.transport = $transport
    if ($transport -eq "stdio") {
        Need ($server.PSObject.Properties.Match("command").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$server.command)) ("MCP stdio 缺少 command：{0}" -f $itemName)
        if ($server.PSObject.Properties.Match("args").Count -eq 0 -or $null -eq $server.args) {
            $server | Add-Member -NotePropertyName args -NotePropertyValue @() -Force
        }
        elseif (-not (Assert-IsArray $server.args)) {
            $server.args = @($server.args)
        }
    }
    else {
        Need ($server.PSObject.Properties.Match("url").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$server.url)) ("MCP {0} 缺少 url：{1}" -f $transport, $itemName)
    }
}

function Assert-AuditMcpNewServer($item) {
    Need ($null -ne $item) "MCP 新增建议不能为空"
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.name)) "MCP 新增建议缺少 name"
    Assert-AuditReasonPair $item "MCP 新增建议"
    Need ($item.PSObject.Properties.Match("server").Count -gt 0) ("MCP 新增建议缺少 server：{0}" -f [string]$item.name)
    Assert-AuditMcpServerPayload $item.server ([string]$item.name)
    Need ([string]$item.server.name -eq [string]$item.name) ("MCP 新增建议 name 与 server.name 不一致：{0}" -f [string]$item.name)
    $confidence = ([string]$item.confidence).ToLowerInvariant()
    Need ($confidence -eq "low" -or $confidence -eq "medium" -or $confidence -eq "high") ("MCP confidence 仅支持 low/medium/high：{0}" -f [string]$item.confidence)
    $item.confidence = $confidence
    $item | Add-Member -NotePropertyName reason -NotePropertyValue ("用户需求：{0}；目标仓/场景：{1}" -f [string]$item.reason_user_profile, [string]$item.reason_target_repo) -Force
}

function Assert-AuditMcpRemovalCandidate($item) {
    Need ($null -ne $item) "MCP 卸载建议不能为空"
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.name)) "MCP 卸载建议缺少 name"
    Assert-AuditReasonPair $item "MCP 卸载建议"
    Need ($item.PSObject.Properties.Match("installed").Count -gt 0 -and $null -ne $item.installed) ("MCP 卸载建议缺少 installed：{0}" -f [string]$item.name)
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.installed.name)) ("MCP 卸载建议缺少 installed.name：{0}" -f [string]$item.name)
}

function Load-AuditRecommendations([string]$path) {
    Need (-not [string]::IsNullOrWhiteSpace($path)) "--recommendations 缺少值"
    Need (Test-Path -LiteralPath $path -PathType Leaf) ("recommendations 文件不存在：{0}" -f $path)
    try {
        $raw = Get-ContentUtf8 $path
        Need (-not [string]::IsNullOrWhiteSpace($raw)) ("recommendations 文件为空：{0}" -f $path)
        $rec = $raw | ConvertFrom-Json
    }
    catch {
        throw ("recommendations JSON 解析失败：{0}" -f $_.Exception.Message)
    }

    Need ([int]$rec.schema_version -eq 2) "recommendations.schema_version 仅支持 2"
    Need (-not [string]::IsNullOrWhiteSpace([string]$rec.run_id)) "recommendations 缺少 run_id"
    Need (-not [string]::IsNullOrWhiteSpace([string]$rec.target)) "recommendations 缺少 target"
    Need ($rec.PSObject.Properties.Match("decision_basis").Count -gt 0 -and $null -ne $rec.decision_basis) "recommendations 缺少 decision_basis"
    Need (Test-AuditJsonProperty $rec.decision_basis "user_profile_used") "decision_basis 缺少 user_profile_used"
    Need (Test-AuditJsonProperty $rec.decision_basis "target_scan_used") "decision_basis 缺少 target_scan_used"
    Need (Test-AuditJsonProperty $rec.decision_basis "source_strategy_used") "decision_basis 缺少 source_strategy_used"
    $recommendationMode = "target-repo"
    if ($rec.PSObject.Properties.Match("recommendation_mode").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$rec.recommendation_mode)) {
        $recommendationMode = ([string]$rec.recommendation_mode).ToLowerInvariant()
    }
    Need ($recommendationMode -eq "target-repo" -or $recommendationMode -eq "profile-only") ("recommendation_mode 仅支持 target-repo 或 profile-only：{0}" -f $recommendationMode)
    Assert-AuditRequiredBooleanTrue $rec.decision_basis.user_profile_used "decision_basis.user_profile_used"
    Need ($rec.decision_basis.target_scan_used -is [bool]) "decision_basis.target_scan_used 必须是布尔值"
    if ($recommendationMode -eq "profile-only") {
        Need (-not [bool]$rec.decision_basis.target_scan_used) "profile-only 模式下 decision_basis.target_scan_used 必须为 false"
    }
    else {
        Assert-AuditRequiredBooleanTrue $rec.decision_basis.target_scan_used "decision_basis.target_scan_used"
    }
    Assert-AuditRequiredBooleanTrue $rec.decision_basis.source_strategy_used "decision_basis.source_strategy_used"
    Need (-not [string]::IsNullOrWhiteSpace([string]$rec.decision_basis.summary)) "decision_basis.summary 不能为空"
    Ensure-AuditArrayProperty $rec "new_skills"
    Ensure-AuditArrayProperty $rec "overlap_findings"
    Ensure-AuditArrayProperty $rec "removal_candidates"
    Ensure-AuditArrayProperty $rec "do_not_install"
    Ensure-AuditArrayProperty $rec "mcp_new_servers"
    Ensure-AuditArrayProperty $rec "mcp_removal_candidates"
    Ensure-AuditArrayProperty $rec "empty_recommendation_reasons"
    Ensure-AuditArrayProperty $rec "source_observations"

    foreach ($item in @($rec.source_observations)) {
        Assert-AuditSourceObservation $item
    }

    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($rec.new_skills)) {
        Assert-AuditRecommendationItem $item
        $install = $item.install
        $key = "{0}|{1}|{2}" -f (Normalize-RepoUrl ([string]$install.repo)), (Normalize-SkillPath ([string]$install.skill)), ([string]$install.mode)
        Need ($seen.Add($key)) ("重复推荐安装项：{0}" -f $key)
    }

    $seenRemovals = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($rec.removal_candidates)) {
        Assert-AuditRemovalCandidate $item
        $key = "{0}|{1}" -f [string]$item.installed.vendor, [string]$item.installed.from
        Need ($seenRemovals.Add($key)) ("重复卸载建议：{0}" -f $key)
    }

    $seenMcpAdds = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($rec.mcp_new_servers)) {
        Assert-AuditMcpNewServer $item
        $key = [string]$item.server.name
        Need ($seenMcpAdds.Add($key)) ("重复 MCP 新增建议：{0}" -f $key)
    }

    $seenMcpRemovals = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($rec.mcp_removal_candidates)) {
        Assert-AuditMcpRemovalCandidate $item
        $key = [string]$item.installed.name
        Need ($seenMcpRemovals.Add($key)) ("重复 MCP 卸载建议：{0}" -f $key)
    }

    $changeItemCount = Get-AuditRecommendationChangeItemCount $rec
    $emptyReasonCodes = @(Normalize-AuditStringArray $rec.empty_recommendation_reasons)
    if ($changeItemCount -eq 0 -and $emptyReasonCodes.Count -eq 0) {
        $emptyReasonCodes = @("insufficient_reliable_evidence")
    }
    $rec.empty_recommendation_reasons = @($emptyReasonCodes)

    return $rec
}

function New-AuditInstallPlan($recommendations, $cfg = $null) {
    if ($null -eq $cfg) { $cfg = LoadCfg }
    $installedFacts = @(Get-InstalledSkillFacts $cfg)
    $installedMcpServers = @()
    if ($cfg.PSObject.Properties.Match("mcp_servers").Count -gt 0 -and $null -ne $cfg.mcp_servers) {
        $installedMcpServers = @($cfg.mcp_servers)
    }
    $items = @()
    foreach ($item in @($recommendations.new_skills)) {
        $install = $item.install
        $tokens = @([string]$install.repo, "--skill", [string]$install.skill)
        if ($install.PSObject.Properties.Match("ref").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$install.ref)) {
            $tokens += @("--ref", [string]$install.ref)
        }
        if ($install.PSObject.Properties.Match("mode").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$install.mode)) {
            $tokens += @("--mode", [string]$install.mode)
        }
        $items += [pscustomobject]([ordered]@{
            name = [string]$item.name
            reason = [string]$item.reason
            reason_user_profile = [string]$item.reason_user_profile
            reason_target_repo = [string]$item.reason_target_repo
            confidence = [string]$item.confidence
            sources = @($item.sources)
            keyword_trace = $item.keyword_trace
            tokens = @($tokens)
            status = "planned"
        })
    }

    $removals = @()
    foreach ($item in @($recommendations.removal_candidates)) {
        $match = @($installedFacts | Where-Object { $_.vendor -eq [string]$item.installed.vendor -and $_.from -eq [string]$item.installed.from })
        $status = if ($match.Count -eq 1) { "planned" } elseif ($match.Count -eq 0) { "not_found" } else { "ambiguous" }
        $matched = if ($match.Count -gt 0) { $match[0] } else { $null }
        $removals += [pscustomobject]([ordered]@{
            name = [string]$item.name
            vendor = [string]$item.installed.vendor
            from = [string]$item.installed.from
            reason = ("用户需求：{0}；目标仓/场景：{1}" -f [string]$item.reason_user_profile, [string]$item.reason_target_repo)
            reason_user_profile = [string]$item.reason_user_profile
            reason_target_repo = [string]$item.reason_target_repo
            sources = @($item.sources)
            keyword_trace = $item.keyword_trace
            matched_skill = $matched
            status = $status
        })
    }
    $mcpItems = @()
    foreach ($item in @($recommendations.mcp_new_servers)) {
        $server = $item.server
        $existing = @($installedMcpServers | Where-Object { [string]$_.name -eq [string]$server.name })
        $status = if ($existing.Count -eq 0) {
            "planned"
        }
        elseif ($existing.Count -eq 1 -and (Test-McpServerEquivalent $existing[0] $server)) {
            "already_present"
        }
        else {
            "planned"
        }
        $mcpItems += [pscustomobject]([ordered]@{
            name = [string]$item.name
            reason = [string]$item.reason
            reason_user_profile = [string]$item.reason_user_profile
            reason_target_repo = [string]$item.reason_target_repo
            confidence = [string]$item.confidence
            sources = @($item.sources)
            keyword_trace = $item.keyword_trace
            server = $server
            status = $status
        })
    }

    $mcpRemovals = @()
    foreach ($item in @($recommendations.mcp_removal_candidates)) {
        $match = @($installedMcpServers | Where-Object { [string]$_.name -eq [string]$item.installed.name })
        $status = if ($match.Count -eq 1) { "planned" } elseif ($match.Count -eq 0) { "not_found" } else { "ambiguous" }
        $matched = if ($match.Count -gt 0) { $match[0] } else { $null }
        $mcpRemovals += [pscustomobject]([ordered]@{
            name = [string]$item.name
            installed_name = [string]$item.installed.name
            reason = ("用户需求：{0}；目标仓/场景：{1}" -f [string]$item.reason_user_profile, [string]$item.reason_target_repo)
            reason_user_profile = [string]$item.reason_user_profile
            reason_target_repo = [string]$item.reason_target_repo
            sources = @($item.sources)
            keyword_trace = $item.keyword_trace
            matched_server = $matched
            status = $status
        })
    }
    return [pscustomobject]([ordered]@{
        schema_version = 2
        run_id = [string]$recommendations.run_id
        target = [string]$recommendations.target
        decision_basis = $recommendations.decision_basis
        source_observations = @($recommendations.source_observations)
        items = @($items)
        overlap_findings = @($recommendations.overlap_findings)
        removal_candidates = @($removals)
        do_not_install = @($recommendations.do_not_install)
        mcp_items = @($mcpItems)
        mcp_removal_candidates = @($mcpRemovals)
        empty_recommendation_reasons = @($recommendations.empty_recommendation_reasons)
    })
}

function Get-AuditApplyReportPath([string]$recommendationsPath) {
    $dir = Split-Path $recommendationsPath -Parent
    if ([string]::IsNullOrWhiteSpace($dir)) { $dir = "." }
    return (Join-Path $dir "apply-report.json")
}

function Get-AuditItemsStatusCount($items, [string]$status) {
    return @($items | Where-Object { [string]$_.status -eq $status }).Count
}

function New-AuditChangedCounts($items, $removals, $mcpItems = @(), $mcpRemovals = @()) {
    return [pscustomobject]([ordered]@{
        add_total = @($items).Count
        add_planned = Get-AuditItemsStatusCount $items "planned"
        add_installed = Get-AuditItemsStatusCount $items "installed"
        add_failed = Get-AuditItemsStatusCount $items "failed"
        remove_total = @($removals).Count
        remove_planned = Get-AuditItemsStatusCount $removals "planned"
        remove_removed = Get-AuditItemsStatusCount $removals "removed"
        remove_not_found = Get-AuditItemsStatusCount $removals "not_found"
        remove_ambiguous = Get-AuditItemsStatusCount $removals "ambiguous"
        mcp_add_total = @($mcpItems).Count
        mcp_add_planned = Get-AuditItemsStatusCount $mcpItems "planned"
        mcp_add_added = Get-AuditItemsStatusCount $mcpItems "added"
        mcp_add_updated = Get-AuditItemsStatusCount $mcpItems "updated"
        mcp_add_already_present = Get-AuditItemsStatusCount $mcpItems "already_present"
        mcp_add_failed = Get-AuditItemsStatusCount $mcpItems "failed"
        mcp_remove_total = @($mcpRemovals).Count
        mcp_remove_planned = Get-AuditItemsStatusCount $mcpRemovals "planned"
        mcp_remove_removed = Get-AuditItemsStatusCount $mcpRemovals "removed"
        mcp_remove_not_found = Get-AuditItemsStatusCount $mcpRemovals "not_found"
        mcp_remove_ambiguous = Get-AuditItemsStatusCount $mcpRemovals "ambiguous"
        mcp_remove_failed = Get-AuditItemsStatusCount $mcpRemovals "failed"
    })
}

function Write-AuditRecommendationSummary($plan, $snapshotState = $null, $liveState = $null) {
    Write-Host ""
    Write-Host "=== 审查建议摘要 ==="
    Write-Host ("决策依据: {0}" -f [string]$plan.decision_basis.summary)
    if ($null -ne $snapshotState -and $null -ne $liveState) {
        Write-Host ("口径: live={0} (source_of_truth), snapshot={1} (audit_input)" -f [int]$liveState.skill_count, [int]$snapshotState.skill_count)
        if ($liveState.PSObject.Properties.Match("mcp_server_count").Count -gt 0 -or $snapshotState.PSObject.Properties.Match("mcp_server_count").Count -gt 0) {
            $liveMcpCount = if ($liveState.PSObject.Properties.Match("mcp_server_count").Count -gt 0) { [int]$liveState.mcp_server_count } else { 0 }
            $snapshotMcpCount = if ($snapshotState.PSObject.Properties.Match("mcp_server_count").Count -gt 0) { [int]$snapshotState.mcp_server_count } else { 0 }
            Write-Host ("MCP 口径: live={0} (source_of_truth), snapshot={1} (audit_input)" -f $liveMcpCount, $snapshotMcpCount)
        }
    }
    Write-Host "提示：以下序号为原序号；后续 dry-run 汇报与 apply 选择必须沿用原序号。"
    $totalChanges = @($plan.items).Count + @($plan.removal_candidates).Count + @($plan.mcp_items).Count + @($plan.mcp_removal_candidates).Count
    if ($totalChanges -eq 0 -and $plan.PSObject.Properties.Match("empty_recommendation_reasons").Count -gt 0 -and @($plan.empty_recommendation_reasons).Count -gt 0) {
        Write-Host ("空建议原因码: {0}" -f ((@($plan.empty_recommendation_reasons) | ForEach-Object { [string]$_ }) -join ", "))
    }
    Write-Host ""
    Write-Host ("新增建议: {0} 项" -f @($plan.items).Count)
    if (@($plan.items).Count -eq 0) {
        Write-Host "无新增建议：当前输入证据未形成可执行新增项。"
    }
    else {
        $index = 1
        foreach ($item in @($plan.items)) {
            Write-Host ("{0}) {1}" -f $index, [string]$item.name)
            Write-Host ("   用户需求: {0}" -f [string]$item.reason_user_profile)
            Write-Host ("   目标仓/场景: {0}" -f [string]$item.reason_target_repo)
            $index++
        }
    }
    Write-Host ""
    Write-Host ("卸载建议: {0} 项" -f @($plan.removal_candidates).Count)
    if (@($plan.removal_candidates).Count -eq 0) {
        Write-Host "无卸载建议：当前输入证据未形成可执行卸载项。"
    }
    else {
        $index = 1
        foreach ($item in @($plan.removal_candidates)) {
            Write-Host ("{0}) {1} [{2}|{3}] status={4}" -f $index, [string]$item.name, [string]$item.vendor, [string]$item.from, [string]$item.status)
            Write-Host ("   用户需求: {0}" -f [string]$item.reason_user_profile)
            Write-Host ("   目标仓/场景: {0}" -f [string]$item.reason_target_repo)
            $index++
        }
    }
    Write-Host ""
    Write-Host ("MCP 新增建议: {0} 项" -f @($plan.mcp_items).Count)
    if (@($plan.mcp_items).Count -eq 0) {
        Write-Host "无 MCP 新增建议：当前输入证据未形成可执行 MCP 新增项。"
    }
    else {
        $index = 1
        foreach ($item in @($plan.mcp_items)) {
            $transport = if ($item.server.PSObject.Properties.Match("transport").Count -gt 0) { [string]$item.server.transport } else { "stdio" }
            Write-Host ("{0}) {1} transport={2} status={3}" -f $index, [string]$item.name, $transport, [string]$item.status)
            Write-Host ("   用户需求: {0}" -f [string]$item.reason_user_profile)
            Write-Host ("   目标仓/场景: {0}" -f [string]$item.reason_target_repo)
            $index++
        }
    }
    Write-Host ""
    Write-Host ("MCP 卸载建议: {0} 项" -f @($plan.mcp_removal_candidates).Count)
    if (@($plan.mcp_removal_candidates).Count -eq 0) {
        Write-Host "无 MCP 卸载建议：当前输入证据未形成可执行 MCP 卸载项。"
    }
    else {
        $index = 1
        foreach ($item in @($plan.mcp_removal_candidates)) {
            Write-Host ("{0}) {1} [name={2}] status={3}" -f $index, [string]$item.name, [string]$item.installed_name, [string]$item.status)
            Write-Host ("   用户需求: {0}" -f [string]$item.reason_user_profile)
            Write-Host ("   目标仓/场景: {0}" -f [string]$item.reason_target_repo)
            $index++
        }
    }
}

function Resolve-AuditSelection([string]$selectionText, $items, [string]$prompt, [string]$invalidMsg) {
    $items = @($items)
    if ($items.Count -eq 0) { return [pscustomobject]@{ items = @(); canceled = $false } }
    if ([string]::IsNullOrWhiteSpace($selectionText)) {
        Write-SelectionHint
        $selection = Read-SelectionIndices $prompt $items.Count $invalidMsg
        if ($selection.canceled) { return [pscustomobject]@{ items = @(); canceled = $true } }
        $idx = @($selection.indices)
    }
    else {
        $idx = @(Parse-IndexSelection $selectionText $items.Count)
        if ($idx.Count -eq 0 -and $selectionText.Trim().ToLowerInvariant() -eq "0") {
            return [pscustomobject]@{ items = @(); canceled = $true }
        }
        if ($idx.Count -eq 0) { throw $invalidMsg }
    }
    $selected = @()
    foreach ($n in $idx) { $selected += $items[$n - 1] }
    return [pscustomobject]@{ items = @($selected); canceled = $false }
}

function Remove-AuditSelectedInstalledSkills($selectedItems) {
    $cfg = LoadCfg
    $removedMappings = 0
    $removedVendorImports = 0
    $deletedManualImports = 0
    $deletedLegacyManualDirs = 0
    $deletedOverrides = 0
    $backedOverrides = 0
    foreach ($item in @($selectedItems)) {
        $vendor = [string]$item.vendor
        $from = [string]$item.from
        if ($vendor -eq "manual") {
            $before = @($cfg.imports).Count
            $cfg.imports = @($cfg.imports | Where-Object { -not ($_.mode -eq "manual" -and $_.name -eq $from) })
            $deletedManualImports += ($before - @($cfg.imports).Count)

            $legacyPath = Join-Path $ManualDir $from
            if (Test-Path $legacyPath) {
                Invoke-RemoveItem $legacyPath -Recurse
                $deletedLegacyManualDirs++
            }
            $cfg.mappings = @($cfg.mappings | Where-Object { -not ("$($_.vendor)|$($_.from)" -eq "manual|$from") })
        }
        elseif ($vendor -eq "overrides") {
            $bak = Backup-OverrideDir $from
            if ($bak) { $backedOverrides++ }
            $deletedOverrides++
        }
        else {
            $cfg.mappings = @($cfg.mappings | Where-Object { -not ("$($_.vendor)|$($_.from)" -eq "$vendor|$from") })
            $removedMappings++

            $skillPath = Normalize-SkillPath $from
            $hasSameMapping = @($cfg.mappings | Where-Object { $_.vendor -eq $vendor -and $_.from -eq $skillPath }).Count -gt 0
            if (-not $hasSameMapping) {
                $beforeImports = @($cfg.imports).Count
                $cfg.imports = @($cfg.imports | Where-Object {
                        $mode = if ($_.PSObject.Properties.Match("mode").Count -gt 0) { [string]$_.mode } else { "manual" }
                        if ($mode -ne "vendor") { return $true }
                        if ([string]$_.name -ne $vendor) { return $true }
                        $importSkill = Normalize-SkillPath ([string]$_.skill)
                        return ($importSkill -ne $skillPath)
                    })
                $removedVendorImports += ($beforeImports - @($cfg.imports).Count)
            }
        }
        $item.status = "removed"
    }
    SaveCfg $cfg
    if (@($selectedItems).Count -gt 0) {
        Clear-SkillsCache
    }
    return [pscustomobject]@{
        removed_mappings = $removedMappings
        removed_vendor_imports = $removedVendorImports
        deleted_manual_imports = $deletedManualImports
        deleted_legacy_manual_dirs = $deletedLegacyManualDirs
        deleted_overrides = $deletedOverrides
        backed_overrides = $backedOverrides
    }
}

function Ensure-AuditNewManualImportsMapped($beforeCfg) {
    $before = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($i in @($beforeCfg.imports)) {
        if ($null -eq $i) { continue }
        $before.Add([string]$i.name) | Out-Null
    }

    $cfg = LoadCfg
    $existingMappings = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($m in @($cfg.mappings)) {
        if ($null -eq $m) { continue }
        $existingMappings.Add(("{0}|{1}" -f [string]$m.vendor, [string]$m.from)) | Out-Null
    }

    $changed = $false
    foreach ($i in @($cfg.imports)) {
        if ($null -eq $i) { continue }
        $mode = if ($i.PSObject.Properties.Match("mode").Count -gt 0) { [string]$i.mode } else { "manual" }
        if ($mode -ne "manual") { continue }
        $name = [string]$i.name
        if ($before.Contains($name)) { continue }
        $key = "manual|{0}" -f $name
        if ($existingMappings.Contains($key)) { continue }
        $cfg.mappings += @{ vendor = "manual"; from = $name; to = $name }
        $existingMappings.Add($key) | Out-Null
        $changed = $true
    }
    if ($changed) { SaveCfg $cfg }
    return $changed
}

function Write-AuditBundleEvidence([string]$mode, [string]$runId, [string]$reportRoot, [string[]]$targets, [string[]]$commands = @()) {
    try {
        $date = Get-Date -Format "yyyyMMdd"
        $time = Get-Date -Format "HHmmss"
        $dir = Join-Path $script:Root "docs\change-evidence"
        EnsureDir $dir
        $safeMode = if ([string]::IsNullOrWhiteSpace($mode)) { "scan" } else { ([regex]::Replace($mode.ToLowerInvariant(), "[^a-z0-9_-]", "-")) }
        $safeRun = if ([string]::IsNullOrWhiteSpace($runId)) { "no-runid" } else { ([regex]::Replace($runId, "[^a-zA-Z0-9_-]", "-")) }
        $path = Join-Path $dir ("{0}-audit-runtime-{1}-{2}-{3}.md" -f $date, $safeMode, $safeRun, $time)
        $commandText = if (@($commands).Count -gt 0) { (@($commands) | ForEach-Object { "- `"$_`"" }) -join "`r`n" } else { "- 无" }
        $targetText = if (@($targets).Count -gt 0) { (@($targets) | ForEach-Object { "- " + [string]$_ }) -join "`r`n" } else { "- 无" }
        $content = @"
# Audit Runtime Evidence

- mode: $mode
- run_id: $runId
- report_root: $reportRoot
- timestamp: $(Get-Date -Format "o")

## Commands
$commandText

## Targets
$targetText

## Rollback
- 删除本次生成目录：`"$reportRoot`"
"@
        Set-ContentUtf8 $path $content
        return $path
    }
    catch {
        Log ("写入审查包证据失败：{0}" -f $_.Exception.Message) "WARN"
        return ""
    }
}

function Invoke-AuditTargetsScan {
    param(
        [string]$Target,
        [string]$OutDir,
        [switch]$Force
    )
    $cfg = Ensure-AuditUserProfilePrecheck
    Assert-AuditUserProfileReady $cfg
    $targets = @($cfg.targets)
    if (-not [string]::IsNullOrWhiteSpace($Target)) {
        $targets = @($targets | Where-Object { $_.name -eq (Normalize-Name $Target) })
        Need ($targets.Count -gt 0) ("未找到目标仓：{0}" -f $Target)
    }
    else {
        $targets = @($targets | Where-Object {
                if ($_.PSObject.Properties.Match("enabled").Count -eq 0) { return $true }
                return [bool]$_.enabled
            })
    }
    Need ($targets.Count -gt 0) "没有可扫描的目标仓。"

    $runId = Get-AuditRunId
    $reportRoot = if ([string]::IsNullOrWhiteSpace($OutDir)) {
        Get-AuditReportRoot $runId
    }
    else {
        Resolve-AuditTargetPath $OutDir
    }
    if (-not [string]::IsNullOrWhiteSpace($OutDir) -and (Test-Path -LiteralPath $reportRoot -PathType Container) -and -not $Force) {
        $existing = @(Get-ChildItem -LiteralPath $reportRoot -Force -ErrorAction SilentlyContinue)
        if ($existing.Count -gt 0) {
            throw ("--out 目录已存在且非空，请使用新的 run-id 目录，或显式追加 --force：{0}" -f $reportRoot)
        }
    }
    EnsureDir $reportRoot

    $userProfilePath = Join-Path $reportRoot "user-profile.json"
    Write-AuditJsonFile $userProfilePath (Get-AuditUserProfileOutput $cfg)

    $scans = @()
    foreach ($t in $targets) {
        $resolved = Resolve-AuditTargetPath ([string]$t.path)
        $scans += New-AuditRepoScan ([string]$t.name) $resolved ([string]$t.path)
    }

    $repoScanPath = ""
    $repoScansPath = ""
    if ($scans.Count -eq 1) {
        $repoScanPath = Join-Path $reportRoot "repo-scan.json"
        Write-AuditJsonFile $repoScanPath $scans[0]
    }
    else {
        $repoScansPath = Join-Path $reportRoot "repo-scans.json"
        Write-AuditJsonFile $repoScansPath ([pscustomobject]@{ schema_version = 1; run_id = $runId; scans = @($scans) })
    }

    $installedPath = Join-Path $reportRoot "installed-skills.json"
    $installedSkills = @()
    $installedMcpServers = @()
    try {
        try {
            $liveCfg = LoadCfg
        }
        catch {
            Log ("审查包生成时读取 skills.json 失败，已回退为空安装快照：{0}" -f $_.Exception.Message) "WARN"
            $liveCfg = New-AuditInstalledFactsFallbackCfg
        }
        $installedSkills = @(Get-InstalledSkillFacts $liveCfg)
        $installedMcpServers = @(Get-AuditMcpServerFacts $liveCfg)
    }
    catch {
        throw ("生成 installed-skills.json 失败：{0}" -f $_.Exception.Message)
    }
    $liveState = Get-AuditLiveInstalledState $liveCfg
    Write-AuditJsonFile $installedPath ([pscustomobject]@{
            schema_version = 1
            snapshot_kind = "audit_input"
            source_of_truth = "live_mappings"
            captured_at = (Get-Date).ToString("o")
            live_skill_count = [int]$liveState.skill_count
            live_fingerprint = [string]$liveState.fingerprint
            live_mcp_server_count = if ($liveState.PSObject.Properties.Match("mcp_server_count").Count -gt 0) { [int]$liveState.mcp_server_count } else { 0 }
            live_mcp_fingerprint = if ($liveState.PSObject.Properties.Match("mcp_fingerprint").Count -gt 0) { [string]$liveState.mcp_fingerprint } else { "" }
            skills = @($installedSkills)
            mcp_servers = @($installedMcpServers)
        })

    $sourceStrategyPath = Join-Path $reportRoot "source-strategy.json"
    Write-AuditJsonFile $sourceStrategyPath (New-AuditSourceStrategy "target-repo" "")
    $decisionInsightsPath = Join-Path $reportRoot "decision-insights.json"
    Write-AuditJsonFile $decisionInsightsPath (New-AuditDecisionInsights $cfg $scans $installedSkills $installedMcpServers "target-repo")

    $templatePath = Join-Path $reportRoot "recommendations.template.json"
    $templateTarget = if ($scans.Count -eq 1) { [string]$scans[0].target.name } else { "*" }
    Write-AuditJsonFile $templatePath (New-AuditRecommendationsTemplate $runId $templateTarget "target-repo")

    $briefPath = Join-Path $reportRoot "ai-brief.md"
    Write-AuditAiBrief $briefPath $scans $userProfilePath $repoScanPath $repoScansPath $installedPath $templatePath "target-repo" "" $sourceStrategyPath $decisionInsightsPath
    $outerAiPromptPath = Join-Path $reportRoot "outer-ai-prompt.md"
    Write-AuditOuterAiPromptFile $outerAiPromptPath $reportRoot $briefPath $userProfilePath $repoScanPath $repoScansPath $installedPath $templatePath "target-repo" "" $sourceStrategyPath $decisionInsightsPath
    $auditMetaPath = Join-Path $reportRoot "audit-meta.json"
    Write-AuditJsonFile $auditMetaPath ([pscustomobject]@{
            schema_version = 1
            run_id = [string]$runId
            mode = "target-repo"
            prompt_contract_version = (Get-AuditPromptContractVersion)
            generated_at = (Get-Date).ToString("o")
        })

    $requiredFiles = New-Object System.Collections.Generic.List[object]
    $requiredFiles.Add([pscustomobject]@{ label = "user-profile.json"; path = $userProfilePath }) | Out-Null
    if ($scans.Count -eq 1) {
        $requiredFiles.Add([pscustomobject]@{ label = "repo-scan.json"; path = $repoScanPath }) | Out-Null
    }
    else {
        $requiredFiles.Add([pscustomobject]@{ label = "repo-scans.json"; path = $repoScansPath }) | Out-Null
    }
    $requiredFiles.Add([pscustomobject]@{ label = "installed-skills.json"; path = $installedPath }) | Out-Null
    $requiredFiles.Add([pscustomobject]@{ label = "source-strategy.json"; path = $sourceStrategyPath }) | Out-Null
    $requiredFiles.Add([pscustomobject]@{ label = "decision-insights.json"; path = $decisionInsightsPath }) | Out-Null
    $requiredFiles.Add([pscustomobject]@{ label = "recommendations.template.json"; path = $templatePath }) | Out-Null
    $requiredFiles.Add([pscustomobject]@{ label = "ai-brief.md"; path = $briefPath }) | Out-Null
    $requiredFiles.Add([pscustomobject]@{ label = "outer-ai-prompt.md"; path = $outerAiPromptPath }) | Out-Null
    $requiredFiles.Add([pscustomobject]@{ label = "audit-meta.json"; path = $auditMetaPath }) | Out-Null
    if ($DryRun) {
        Write-Host ("DRYRUN：将生成审查包：{0}" -f $reportRoot) -ForegroundColor Yellow
        Write-Host "DRYRUN 关键产物预览：" -ForegroundColor Yellow
        foreach ($item in @($requiredFiles.ToArray())) {
            Write-Host ("- {0}: {1}" -f [string]$item.label, [string]$item.path)
        }
        return [pscustomobject]@{
            run_id = $runId
            path = $reportRoot
            scans = @($scans)
            dry_run = $true
        }
    }
    Assert-AuditBundleRequiredFiles ($requiredFiles.ToArray())
    Write-Host ("审查包已生成：{0}" -f $reportRoot) -ForegroundColor Green
    Write-Host "关键产物：" -ForegroundColor Cyan
    Write-Host ("- user-profile.json: {0}" -f $userProfilePath)
    if ($scans.Count -eq 1) {
        Write-Host ("- repo-scan.json: {0}" -f $repoScanPath)
    }
    else {
        Write-Host ("- repo-scans.json: {0}" -f $repoScansPath)
    }
    Write-Host ("- installed-skills.json: {0}" -f $installedPath)
    Write-Host ("- source-strategy.json: {0}" -f $sourceStrategyPath)
    Write-Host ("- decision-insights.json: {0}" -f $decisionInsightsPath)
    Write-Host ("- ai-brief.md: {0}" -f $briefPath)
    Write-Host ("- outer-ai-prompt.md: {0}" -f $outerAiPromptPath)
    Write-Host ("- audit-meta.json: {0}" -f $auditMetaPath)
    Write-Host ("- recommendations.template.json: {0}" -f $templatePath)
    Write-Host "下一步：把 outer-ai-prompt.md 交给 AI；AI 应先填写并自检 recommendations.json，再执行 dry-run，并按原序号列出技能与 MCP 的新增/卸载清单。" -ForegroundColor Yellow
    $evidencePath = Write-AuditBundleEvidence "scan" $runId $reportRoot @($scans | ForEach-Object { [string]$_.target.name }) @(".\\skills.ps1 审查目标 扫描")
    if (-not [string]::IsNullOrWhiteSpace($evidencePath)) {
        Write-Host ("审查运行证据：{0}" -f $evidencePath) -ForegroundColor Cyan
    }
    return [pscustomobject]@{
        run_id = $runId
        path = $reportRoot
        scans = @($scans)
    }
}

function Invoke-AuditSkillDiscovery {
    param(
        [string]$Query,
        [string]$OutDir,
        [switch]$Force
    )
    $cfg = Ensure-AuditUserProfilePrecheck
    Assert-AuditUserProfileReady $cfg

    $runId = Get-AuditRunId
    $reportRoot = if ([string]::IsNullOrWhiteSpace($OutDir)) {
        Get-AuditReportRoot $runId
    }
    else {
        Resolve-AuditTargetPath $OutDir
    }
    if (-not [string]::IsNullOrWhiteSpace($OutDir) -and (Test-Path -LiteralPath $reportRoot -PathType Container) -and -not $Force) {
        $existing = @(Get-ChildItem -LiteralPath $reportRoot -Force -ErrorAction SilentlyContinue)
        if ($existing.Count -gt 0) {
            throw ("--out 目录已存在且非空，请使用新的 run-id 目录，或显式追加 --force：{0}" -f $reportRoot)
        }
    }
    EnsureDir $reportRoot

    $userProfilePath = Join-Path $reportRoot "user-profile.json"
    Write-AuditJsonFile $userProfilePath (Get-AuditUserProfileOutput $cfg)

    $installedPath = Join-Path $reportRoot "installed-skills.json"
    $installedSkills = @()
    $installedMcpServers = @()
    try {
        try {
            $liveCfg = LoadCfg
        }
        catch {
            Log ("新技能发现生成时读取 skills.json 失败，已回退为空安装快照：{0}" -f $_.Exception.Message) "WARN"
            $liveCfg = New-AuditInstalledFactsFallbackCfg
        }
        $installedSkills = @(Get-InstalledSkillFacts $liveCfg)
        $installedMcpServers = @(Get-AuditMcpServerFacts $liveCfg)
    }
    catch {
        throw ("生成 installed-skills.json 失败：{0}" -f $_.Exception.Message)
    }
    $liveState = Get-AuditLiveInstalledState $liveCfg
    Write-AuditJsonFile $installedPath ([pscustomobject]@{
            schema_version = 1
            snapshot_kind = "audit_input"
            source_of_truth = "live_mappings"
            captured_at = (Get-Date).ToString("o")
            live_skill_count = [int]$liveState.skill_count
            live_fingerprint = [string]$liveState.fingerprint
            live_mcp_server_count = if ($liveState.PSObject.Properties.Match("mcp_server_count").Count -gt 0) { [int]$liveState.mcp_server_count } else { 0 }
            live_mcp_fingerprint = if ($liveState.PSObject.Properties.Match("mcp_fingerprint").Count -gt 0) { [string]$liveState.mcp_fingerprint } else { "" }
            skills = @($installedSkills)
            mcp_servers = @($installedMcpServers)
        })

    $sourceStrategyPath = Join-Path $reportRoot "source-strategy.json"
    Write-AuditJsonFile $sourceStrategyPath (New-AuditSourceStrategy "profile-only" $Query)
    $decisionInsightsPath = Join-Path $reportRoot "decision-insights.json"
    Write-AuditJsonFile $decisionInsightsPath (New-AuditDecisionInsights $cfg @() $installedSkills $installedMcpServers "profile-only")

    $templatePath = Join-Path $reportRoot "recommendations.template.json"
    Write-AuditJsonFile $templatePath (New-AuditRecommendationsTemplate $runId "profile-only" "profile-only" $Query)

    $briefPath = Join-Path $reportRoot "ai-brief.md"
    Write-AuditAiBrief $briefPath @() $userProfilePath "" "" $installedPath $templatePath "profile-only" $Query $sourceStrategyPath $decisionInsightsPath
    $outerAiPromptPath = Join-Path $reportRoot "outer-ai-prompt.md"
    Write-AuditOuterAiPromptFile $outerAiPromptPath $reportRoot $briefPath $userProfilePath "" "" $installedPath $templatePath "profile-only" $Query $sourceStrategyPath $decisionInsightsPath
    $auditMetaPath = Join-Path $reportRoot "audit-meta.json"
    Write-AuditJsonFile $auditMetaPath ([pscustomobject]@{
            schema_version = 1
            run_id = [string]$runId
            mode = "profile-only"
            prompt_contract_version = (Get-AuditPromptContractVersion)
            generated_at = (Get-Date).ToString("o")
        })

    $requiredFiles = New-Object System.Collections.Generic.List[object]
    $requiredFiles.Add([pscustomobject]@{ label = "user-profile.json"; path = $userProfilePath }) | Out-Null
    $requiredFiles.Add([pscustomobject]@{ label = "installed-skills.json"; path = $installedPath }) | Out-Null
    $requiredFiles.Add([pscustomobject]@{ label = "source-strategy.json"; path = $sourceStrategyPath }) | Out-Null
    $requiredFiles.Add([pscustomobject]@{ label = "decision-insights.json"; path = $decisionInsightsPath }) | Out-Null
    $requiredFiles.Add([pscustomobject]@{ label = "recommendations.template.json"; path = $templatePath }) | Out-Null
    $requiredFiles.Add([pscustomobject]@{ label = "ai-brief.md"; path = $briefPath }) | Out-Null
    $requiredFiles.Add([pscustomobject]@{ label = "outer-ai-prompt.md"; path = $outerAiPromptPath }) | Out-Null
    $requiredFiles.Add([pscustomobject]@{ label = "audit-meta.json"; path = $auditMetaPath }) | Out-Null
    if ($DryRun) {
        Write-Host ("DRYRUN：将生成新技能发现包：{0}" -f $reportRoot) -ForegroundColor Yellow
        Write-Host "DRYRUN 关键产物预览：" -ForegroundColor Yellow
        foreach ($item in @($requiredFiles.ToArray())) {
            Write-Host ("- {0}: {1}" -f [string]$item.label, [string]$item.path)
        }
        return [pscustomobject]@{
            run_id = $runId
            path = $reportRoot
            mode = "profile-only"
            query = [string]$Query
            scans = @()
            dry_run = $true
        }
    }
    Assert-AuditBundleRequiredFiles ($requiredFiles.ToArray())

    Write-Host ("新技能发现包已生成：{0}" -f $reportRoot) -ForegroundColor Green
    Write-Host "关键产物：" -ForegroundColor Cyan
    Write-Host ("- user-profile.json: {0}" -f $userProfilePath)
    Write-Host ("- installed-skills.json: {0}" -f $installedPath)
    Write-Host ("- source-strategy.json: {0}" -f $sourceStrategyPath)
    Write-Host ("- decision-insights.json: {0}" -f $decisionInsightsPath)
    Write-Host ("- ai-brief.md: {0}" -f $briefPath)
    Write-Host ("- outer-ai-prompt.md: {0}" -f $outerAiPromptPath)
    Write-Host ("- audit-meta.json: {0}" -f $auditMetaPath)
    Write-Host ("- recommendations.template.json: {0}" -f $templatePath)
    Write-Host "下一步：把 outer-ai-prompt.md 交给 AI；AI 应先填写并自检 recommendations.json，再执行 dry-run，并按原序号列出技能与 MCP 的新增/卸载清单。" -ForegroundColor Yellow
    $evidencePath = Write-AuditBundleEvidence "discover-skills" $runId $reportRoot @("profile-only")
    if (-not [string]::IsNullOrWhiteSpace($evidencePath)) {
        Write-Host ("审查运行证据：{0}" -f $evidencePath) -ForegroundColor Cyan
    }
    return [pscustomobject]@{
        run_id = $runId
        path = $reportRoot
        mode = "profile-only"
        query = [string]$Query
        scans = @()
    }
}

function Get-AuditPersistedChangeTotal($counts) {
    if ($null -eq $counts) { return 0 }
    $total = 0
    foreach ($field in @("add_installed", "remove_removed", "mcp_add_added", "mcp_add_updated", "mcp_remove_removed")) {
        if ($counts.PSObject.Properties.Match($field).Count -gt 0) {
            $total += [int]$counts.$field
        }
    }
    return $total
}

function Get-AuditDryRunSummaryPath([string]$recommendationsPath) {
    $dir = Split-Path $recommendationsPath -Parent
    if ([string]::IsNullOrWhiteSpace($dir)) { $dir = "." }
    return (Join-Path $dir "dry-run-summary.json")
}

function New-AuditDryRunSummary($plan, [string]$recommendationsPath) {
    $add = @()
    $index = 1
    foreach ($item in @($plan.items)) {
        $add += [pscustomobject]([ordered]@{
            index = $index
            name = [string]$item.name
            reason_user_profile = [string]$item.reason_user_profile
            reason_target_repo = [string]$item.reason_target_repo
            sources = @($item.sources)
            keyword_trace = $item.keyword_trace
            status = [string]$item.status
        })
        $index++
    }
    $remove = @()
    $index = 1
    foreach ($item in @($plan.removal_candidates)) {
        $remove += [pscustomobject]([ordered]@{
            index = $index
            name = [string]$item.name
            installed = [ordered]@{
                vendor = [string]$item.vendor
                from = [string]$item.from
            }
            reason_user_profile = [string]$item.reason_user_profile
            reason_target_repo = [string]$item.reason_target_repo
            sources = @($item.sources)
            keyword_trace = $item.keyword_trace
            status = [string]$item.status
        })
        $index++
    }
    $mcpAdd = @()
    $index = 1
    foreach ($item in @($plan.mcp_items)) {
        $mcpAdd += [pscustomobject]([ordered]@{
            index = $index
            name = [string]$item.name
            reason_user_profile = [string]$item.reason_user_profile
            reason_target_repo = [string]$item.reason_target_repo
            sources = @($item.sources)
            keyword_trace = $item.keyword_trace
            status = [string]$item.status
        })
        $index++
    }
    $mcpRemove = @()
    $index = 1
    foreach ($item in @($plan.mcp_removal_candidates)) {
        $mcpRemove += [pscustomobject]([ordered]@{
            index = $index
            name = [string]$item.name
            installed_name = [string]$item.installed_name
            reason_user_profile = [string]$item.reason_user_profile
            reason_target_repo = [string]$item.reason_target_repo
            sources = @($item.sources)
            keyword_trace = $item.keyword_trace
            status = [string]$item.status
        })
        $index++
    }
    return [pscustomobject]([ordered]@{
        schema_version = 1
        generated_at = (Get-Date).ToString("o")
        recommendations_path = $recommendationsPath
        run_id = [string]$plan.run_id
        target = [string]$plan.target
        decision_basis_summary = [string]$plan.decision_basis.summary
        empty_recommendation_reasons = if ($plan.PSObject.Properties.Match("empty_recommendation_reasons").Count -gt 0) { @($plan.empty_recommendation_reasons) } else { @() }
        source_observations = if ($plan.PSObject.Properties.Match("source_observations").Count -gt 0) { @($plan.source_observations) } else { @() }
        counts = [ordered]@{
            add = @($add).Count
            remove = @($remove).Count
            mcp_add = @($mcpAdd).Count
            mcp_remove = @($mcpRemove).Count
        }
        add = @($add)
        remove = @($remove)
        mcp_add = @($mcpAdd)
        mcp_remove = @($mcpRemove)
    })
}

function Get-AuditSourceEvidencePolicy([string]$recommendationDir) {
    $path = Join-Path $recommendationDir "source-strategy.json"
    $policy = [ordered]@{
        enabled = $false
        source_strategy_path = $path
        min_unique_sources_for_changes = 0
        require_http_source_for_changes = $false
        require_source_observations_for_changes = $false
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]$policy
    }
    try {
        $raw = Get-ContentUtf8 $path
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return [pscustomobject]$policy
        }
        $data = $raw | ConvertFrom-Json
        if ($data.PSObject.Properties.Match("evidence_policy").Count -eq 0 -or $null -eq $data.evidence_policy) {
            return [pscustomobject]$policy
        }
        $e = $data.evidence_policy
        $min = 0
        if ($e.PSObject.Properties.Match("min_unique_sources_for_changes").Count -gt 0) {
            $min = [int]$e.min_unique_sources_for_changes
        }
        $needHttp = $false
        if ($e.PSObject.Properties.Match("require_http_source_for_changes").Count -gt 0) {
            $needHttp = [bool]$e.require_http_source_for_changes
        }
        $needObservations = $false
        if ($e.PSObject.Properties.Match("require_source_observations_for_changes").Count -gt 0) {
            $needObservations = [bool]$e.require_source_observations_for_changes
        }
        $policy.enabled = ($min -gt 0 -or $needHttp -or $needObservations)
        $policy.min_unique_sources_for_changes = if ($min -lt 0) { 0 } else { $min }
        $policy.require_http_source_for_changes = $needHttp
        $policy.require_source_observations_for_changes = $needObservations
        return [pscustomobject]$policy
    }
    catch {
        return [pscustomobject]$policy
    }
}

function Test-AuditRecommendationSourceCoveragePolicy($rec, $policy) {
    $coverage = Get-AuditRecommendationSourceCoverage $rec
    $issues = New-Object System.Collections.Generic.List[string]
    if ($null -eq $policy -or -not [bool]$policy.enabled) {
        return [pscustomobject]([ordered]@{
            pass = $true
            issues = @()
            coverage = $coverage
        })
    }
    if ([int]$coverage.total_change_items -eq 0) {
        return [pscustomobject]([ordered]@{
            pass = $true
            issues = @()
            coverage = $coverage
        })
    }
    $requiredUnique = [int]$policy.min_unique_sources_for_changes
    if ($requiredUnique -gt 0 -and [int]$coverage.unique_source_count -lt $requiredUnique) {
        $issues.Add(("insufficient_source_coverage：变更建议共 {0} 项，但 unique sources={1}，低于阈值 {2}。" -f [int]$coverage.total_change_items, [int]$coverage.unique_source_count, $requiredUnique)) | Out-Null
    }
    if ([bool]$policy.require_http_source_for_changes -and [int]$coverage.http_source_count -lt 1) {
        $issues.Add("insufficient_source_coverage：变更建议缺少可验证的 http/https 来源。") | Out-Null
    }
    if ([bool]$policy.require_source_observations_for_changes -and [int]$coverage.items_with_source_observation -lt [int]$coverage.total_change_items) {
        $missing = @($coverage.change_items_missing_source_observation | Select-Object -First 5) -join ", "
        $issues.Add(("insufficient_source_coverage：变更建议需要对应 source_observations，已覆盖 {0}/{1}。缺失：{2}" -f [int]$coverage.items_with_source_observation, [int]$coverage.total_change_items, $missing)) | Out-Null
    }
    return [pscustomobject]([ordered]@{
        pass = ($issues.Count -eq 0)
        issues = @($issues)
        coverage = $coverage
    })
}

function Get-AuditDecisionQualityPolicy([string]$recommendationDir) {
    $path = Join-Path $recommendationDir "source-strategy.json"
    $policy = [ordered]@{
        enabled = $false
        source_strategy_path = $path
        mode = "target-repo"
        require_keyword_trace_for_changes = $false
        require_keyword_trace_membership = $false
        min_user_profile_keywords_per_change = 0
        min_target_repo_keywords_per_change = 0
        min_installed_state_keywords_per_change = 0
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]$policy
    }
    try {
        $raw = Get-ContentUtf8 $path
        if ([string]::IsNullOrWhiteSpace($raw)) { return [pscustomobject]$policy }
        $data = $raw | ConvertFrom-Json
        if ($data.PSObject.Properties.Match("mode").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$data.mode)) {
            $policy.mode = ([string]$data.mode).Trim().ToLowerInvariant()
        }
        if ($data.PSObject.Properties.Match("decision_quality_policy").Count -eq 0 -or $null -eq $data.decision_quality_policy) {
            return [pscustomobject]$policy
        }
        $q = $data.decision_quality_policy
        if ($q.PSObject.Properties.Match("require_keyword_trace_for_changes").Count -gt 0) {
            $policy.require_keyword_trace_for_changes = [bool]$q.require_keyword_trace_for_changes
        }
        if ($q.PSObject.Properties.Match("require_keyword_trace_membership").Count -gt 0) {
            $policy.require_keyword_trace_membership = [bool]$q.require_keyword_trace_membership
        }
        if ($q.PSObject.Properties.Match("min_user_profile_keywords_per_change").Count -gt 0) {
            $policy.min_user_profile_keywords_per_change = [Math]::Max(0, [int]$q.min_user_profile_keywords_per_change)
        }
        if ($q.PSObject.Properties.Match("min_target_repo_keywords_per_change").Count -gt 0) {
            $policy.min_target_repo_keywords_per_change = [Math]::Max(0, [int]$q.min_target_repo_keywords_per_change)
        }
        if ($q.PSObject.Properties.Match("min_installed_state_keywords_per_change").Count -gt 0) {
            $policy.min_installed_state_keywords_per_change = [Math]::Max(0, [int]$q.min_installed_state_keywords_per_change)
        }
        $policy.enabled = (
            [bool]$policy.require_keyword_trace_for_changes -or
            [bool]$policy.require_keyword_trace_membership -or
            [int]$policy.min_user_profile_keywords_per_change -gt 0 -or
            [int]$policy.min_target_repo_keywords_per_change -gt 0 -or
            [int]$policy.min_installed_state_keywords_per_change -gt 0
        )
        return [pscustomobject]$policy
    }
    catch {
        return [pscustomobject]$policy
    }
}

function Get-AuditDecisionInsights([string]$recommendationDir) {
    $path = Join-Path $recommendationDir "decision-insights.json"
    $result = [ordered]@{
        exists = $false
        path = $path
        mode = "target-repo"
        keywords = [ordered]@{
            user_profile = @()
            target_repo = @()
            profile_only_context = @()
            installed_state = @()
        }
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]$result
    }
    try {
        $raw = Get-ContentUtf8 $path
        if ([string]::IsNullOrWhiteSpace($raw)) { return [pscustomobject]$result }
        $data = $raw | ConvertFrom-Json
        $result.exists = $true
        if ($data.PSObject.Properties.Match("mode").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$data.mode)) {
            $result.mode = ([string]$data.mode).Trim().ToLowerInvariant()
        }
        if ($data.PSObject.Properties.Match("keywords").Count -gt 0 -and $null -ne $data.keywords) {
            foreach ($field in @("user_profile", "target_repo", "profile_only_context", "installed_state")) {
                if ($data.keywords.PSObject.Properties.Match($field).Count -gt 0) {
                    $result.keywords[$field] = @(Normalize-AuditStringArray $data.keywords.$field)
                }
            }
        }
        return [pscustomobject]$result
    }
    catch {
        return [pscustomobject]$result
    }
}

function Test-AuditRecommendationDecisionQualityPolicy($rec, $policy, $decisionInsights) {
    $coverage = [ordered]@{
        total_change_items = Get-AuditRecommendationChangeItemCount $rec
        items_with_complete_keyword_trace = 0
        user_keyword_ref_count = 0
        target_keyword_ref_count = 0
        installed_keyword_ref_count = 0
        unique_user_keywords = @()
        unique_target_keywords = @()
        unique_installed_keywords = @()
    }
    $issues = New-Object System.Collections.Generic.List[string]
    if ($null -eq $policy -or -not [bool]$policy.enabled) {
        return [pscustomobject]([ordered]@{
                pass = $true
                issues = @()
                coverage = [pscustomobject]$coverage
            })
    }
    if ([int]$coverage.total_change_items -eq 0) {
        return [pscustomobject]([ordered]@{
                pass = $true
                issues = @()
                coverage = [pscustomobject]$coverage
            })
    }

    $recommendationMode = "target-repo"
    if ($rec.PSObject.Properties.Match("recommendation_mode").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$rec.recommendation_mode)) {
        $recommendationMode = ([string]$rec.recommendation_mode).Trim().ToLowerInvariant()
    }
    $requiredUser = [int]$policy.min_user_profile_keywords_per_change
    $requiredTarget = [int]$policy.min_target_repo_keywords_per_change
    $requiredInstalled = [int]$policy.min_installed_state_keywords_per_change
    if ([bool]$policy.require_keyword_trace_for_changes) {
        if ($requiredUser -lt 1) { $requiredUser = 1 }
        if ($requiredTarget -lt 1) { $requiredTarget = 1 }
        if ($requiredInstalled -lt 1) { $requiredInstalled = 1 }
    }

    $userSet = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $targetSet = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $installedSet = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($token in @(Normalize-AuditStringArray $decisionInsights.keywords.user_profile)) { $null = $userSet.Add($token) }
    $targetTokens = if ($recommendationMode -eq "profile-only") { @(Normalize-AuditStringArray $decisionInsights.keywords.profile_only_context) } else { @(Normalize-AuditStringArray $decisionInsights.keywords.target_repo) }
    foreach ($token in @($targetTokens)) { $null = $targetSet.Add($token) }
    foreach ($token in @(Normalize-AuditStringArray $decisionInsights.keywords.installed_state)) { $null = $installedSet.Add($token) }
    if ([bool]$policy.require_keyword_trace_membership -and -not [bool]$decisionInsights.exists) {
        $issues.Add("insufficient_decision_quality：decision-insights.json 缺失或不可读，无法校验 keyword_trace 归属。") | Out-Null
    }

    $uniqueUser = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $uniqueTarget = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $uniqueInstalled = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $collections = @(
        @{ kind = "skill-add"; items = @($rec.new_skills) },
        @{ kind = "skill-remove"; items = @($rec.removal_candidates) },
        @{ kind = "mcp-add"; items = @($rec.mcp_new_servers) },
        @{ kind = "mcp-remove"; items = @($rec.mcp_removal_candidates) }
    )
    foreach ($group in @($collections)) {
        foreach ($item in @($group.items)) {
            $trace = $null
            if ($item.PSObject.Properties.Match("keyword_trace").Count -gt 0 -and $null -ne $item.keyword_trace -and (Test-AuditObjectLike $item.keyword_trace)) {
                $trace = $item.keyword_trace
            }
            $userRefs = @()
            $targetRefs = @()
            $installedRefs = @()
            if ($null -ne $trace) {
                if ($trace.PSObject.Properties.Match("user_profile").Count -gt 0) { $userRefs = @(Normalize-AuditStringArray $trace.user_profile) }
                if ($trace.PSObject.Properties.Match("target_repo_or_context").Count -gt 0) { $targetRefs = @(Normalize-AuditStringArray $trace.target_repo_or_context) }
                if ($trace.PSObject.Properties.Match("installed_state").Count -gt 0) { $installedRefs = @(Normalize-AuditStringArray $trace.installed_state) }
            }

            if (@($userRefs).Count -gt 0 -and @($targetRefs).Count -gt 0 -and @($installedRefs).Count -gt 0) {
                $coverage.items_with_complete_keyword_trace = [int]$coverage.items_with_complete_keyword_trace + 1
            }
            $coverage.user_keyword_ref_count = [int]$coverage.user_keyword_ref_count + @($userRefs).Count
            $coverage.target_keyword_ref_count = [int]$coverage.target_keyword_ref_count + @($targetRefs).Count
            $coverage.installed_keyword_ref_count = [int]$coverage.installed_keyword_ref_count + @($installedRefs).Count

            foreach ($token in @($userRefs)) { $null = $uniqueUser.Add($token) }
            foreach ($token in @($targetRefs)) { $null = $uniqueTarget.Add($token) }
            foreach ($token in @($installedRefs)) { $null = $uniqueInstalled.Add($token) }

            if ($requiredUser -gt 0 -and @($userRefs).Count -lt $requiredUser) {
                $issues.Add(("insufficient_decision_quality：{0} `{1}` 的 keyword_trace.user_profile 数量为 {2}，低于阈值 {3}。" -f [string]$group.kind, [string]$item.name, @($userRefs).Count, $requiredUser)) | Out-Null
            }
            if ($requiredTarget -gt 0 -and @($targetRefs).Count -lt $requiredTarget) {
                $issues.Add(("insufficient_decision_quality：{0} `{1}` 的 keyword_trace.target_repo_or_context 数量为 {2}，低于阈值 {3}。" -f [string]$group.kind, [string]$item.name, @($targetRefs).Count, $requiredTarget)) | Out-Null
            }
            if ($requiredInstalled -gt 0 -and @($installedRefs).Count -lt $requiredInstalled) {
                $issues.Add(("insufficient_decision_quality：{0} `{1}` 的 keyword_trace.installed_state 数量为 {2}，低于阈值 {3}。" -f [string]$group.kind, [string]$item.name, @($installedRefs).Count, $requiredInstalled)) | Out-Null
            }

            if ([bool]$policy.require_keyword_trace_membership -and [bool]$decisionInsights.exists) {
                $unknownUser = @($userRefs | Where-Object { -not $userSet.Contains([string]$_) })
                if (@($unknownUser).Count -gt 0) {
                    $issues.Add(("insufficient_decision_quality：{0} `{1}` 的 keyword_trace.user_profile 包含未知关键词：{2}" -f [string]$group.kind, [string]$item.name, (@($unknownUser | Select-Object -First 3) -join ", "))) | Out-Null
                }
                $unknownTarget = @($targetRefs | Where-Object { -not $targetSet.Contains([string]$_) })
                if (@($unknownTarget).Count -gt 0) {
                    $issues.Add(("insufficient_decision_quality：{0} `{1}` 的 keyword_trace.target_repo_or_context 包含未知关键词：{2}" -f [string]$group.kind, [string]$item.name, (@($unknownTarget | Select-Object -First 3) -join ", "))) | Out-Null
                }
                $unknownInstalled = @($installedRefs | Where-Object { -not $installedSet.Contains([string]$_) })
                if (@($unknownInstalled).Count -gt 0) {
                    $issues.Add(("insufficient_decision_quality：{0} `{1}` 的 keyword_trace.installed_state 包含未知关键词：{2}" -f [string]$group.kind, [string]$item.name, (@($unknownInstalled | Select-Object -First 3) -join ", "))) | Out-Null
                }
            }
        }
    }
    $coverage.unique_user_keywords = @($uniqueUser | Sort-Object)
    $coverage.unique_target_keywords = @($uniqueTarget | Sort-Object)
    $coverage.unique_installed_keywords = @($uniqueInstalled | Sort-Object)
    return [pscustomobject]([ordered]@{
            pass = ($issues.Count -eq 0)
            issues = @($issues)
            coverage = [pscustomobject]$coverage
        })
}

function Write-AuditRuntimeEvidence([string]$mode, [string]$recommendationsPath, $report, [string[]]$commands = @()) {
    try {
        $date = Get-Date -Format "yyyyMMdd"
        $time = Get-Date -Format "HHmmss"
        $dir = Join-Path $script:Root "docs\change-evidence"
        EnsureDir $dir
        $safeMode = if ([string]::IsNullOrWhiteSpace($mode)) { "unknown" } else { ([regex]::Replace($mode.ToLowerInvariant(), "[^a-z0-9_-]", "-")) }
        $runId = if ($null -ne $report -and $report.PSObject.Properties.Match("run_id").Count -gt 0) { [string]$report.run_id } else { "" }
        $safeRun = if ([string]::IsNullOrWhiteSpace($runId)) { "no-runid" } else { ([regex]::Replace($runId, "[^a-zA-Z0-9_-]", "-")) }
        $path = Join-Path $dir ("{0}-audit-runtime-{1}-{2}-{3}.md" -f $date, $safeMode, $safeRun, $time)
        $changedCountsJson = if ($null -ne $report -and $report.PSObject.Properties.Match("changed_counts").Count -gt 0) { ($report.changed_counts | ConvertTo-Json -Depth 10 -Compress) } else { "{}" }
        $rollbackText = if ($null -ne $report -and $report.PSObject.Properties.Match("rollback").Count -gt 0 -and @($report.rollback).Count -gt 0) {
            (@($report.rollback) | ForEach-Object { "- " + [string]$_ }) -join "`r`n"
        }
        else {
            "- 无"
        }
        $commandText = if (@($commands).Count -gt 0) { (@($commands) | ForEach-Object { "- `"$_`"" }) -join "`r`n" } else { "- 无" }
        $content = @"
# Audit Runtime Evidence

- mode: $mode
- run_id: $runId
- recommendations: $recommendationsPath
- success: $([bool]$report.success)
- persisted: $([bool]$report.persisted)
- timestamp: $(Get-Date -Format "o")

## Commands
$commandText

## Key Output
- changed_counts: $changedCountsJson

## Rollback
$rollbackText
"@
        Set-ContentUtf8 $path $content
        return $path
    }
    catch {
        Log ("写入审查运行证据失败：{0}" -f $_.Exception.Message) "WARN"
        return ""
    }
}

function Apply-AuditMcpSelections($selectedAddItems, $selectedRemoveItems) {
    $selectedAddItems = @($selectedAddItems)
    $selectedRemoveItems = @($selectedRemoveItems)
    if ($selectedAddItems.Count -eq 0 -and $selectedRemoveItems.Count -eq 0) {
        return [pscustomobject]@{ changed = $false }
    }

    $cfg = LoadCfg
    $cfgRaw = Get-Content $CfgPath -Raw
    $servers = @(if ($cfg.PSObject.Properties.Match("mcp_servers").Count -gt 0 -and $null -ne $cfg.mcp_servers) { @($cfg.mcp_servers) } else { @() })
    $changed = $false

    foreach ($item in $selectedAddItems) {
        $candidate = $item.server
        $existing = @($servers | Where-Object { [string]$_.name -eq [string]$candidate.name })
        if ($existing.Count -eq 1 -and (Test-McpServerEquivalent $existing[0] $candidate)) {
            $item.status = "already_present"
            continue
        }
        $replaced = $false
        for ($i = 0; $i -lt $servers.Count; $i++) {
            if ([string]$servers[$i].name -eq [string]$candidate.name) {
                $servers[$i] = $candidate
                $replaced = $true
                $changed = $true
                break
            }
        }
        if ($replaced) {
            $item.status = "updated"
        }
        else {
            $servers += $candidate
            $item.status = "added"
            $changed = $true
        }
    }

    foreach ($item in $selectedRemoveItems) {
        $name = [string]$item.installed_name
        $matches = @($servers | Where-Object { [string]$_.name -eq $name })
        if ($matches.Count -eq 0) {
            $item.status = "not_found"
            continue
        }
        if ($matches.Count -gt 1) {
            $item.status = "ambiguous"
            continue
        }
        $servers = @($servers | Where-Object { [string]$_.name -ne $name })
        $item.status = "removed"
        $changed = $true
    }

    if (-not $changed) {
        return [pscustomobject]@{ changed = $false }
    }

    if ($cfg.PSObject.Properties.Match("mcp_servers").Count -eq 0) {
        $cfg | Add-Member -NotePropertyName mcp_servers -NotePropertyValue @() -Force
    }
    $cfg.mcp_servers = @($servers)
    SaveCfgSafe $cfg $cfgRaw
    同步MCP
    return [pscustomobject]@{ changed = $true }
}

function Resolve-AuditRecommendationsPathForPreflight([string]$RecommendationsPath, [string]$RunId) {
    if (-not [string]::IsNullOrWhiteSpace($RecommendationsPath)) {
        $resolvedInputPath = Resolve-AuditPathRunIdPlaceholder $RecommendationsPath "--recommendations" @("recommendations.json", "installed-skills.json", "audit-meta.json")
        return (Resolve-AuditTargetPath $resolvedInputPath)
    }
    Need (-not [string]::IsNullOrWhiteSpace($RunId)) "预检至少需要 --run-id 或 --recommendations 其一"
    $resolvedRunId = Resolve-AuditRunIdInput $RunId "--run-id" @("recommendations.json", "installed-skills.json", "audit-meta.json")
    return (Join-Path (Get-AuditReportRoot $resolvedRunId) "recommendations.json")
}

function Get-AuditRunPromptContractVersion([string]$recommendationDir) {
    $metaPath = Join-Path $recommendationDir "audit-meta.json"
    if (Test-Path -LiteralPath $metaPath -PathType Leaf) {
        try {
            $metaRaw = Get-ContentUtf8 $metaPath
            if (-not [string]::IsNullOrWhiteSpace($metaRaw)) {
                $meta = $metaRaw | ConvertFrom-Json
                if ($meta.PSObject.Properties.Match("prompt_contract_version").Count -gt 0) {
                    $version = ([string]$meta.prompt_contract_version).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($version)) {
                        return $version
                    }
                }
            }
        }
        catch {
            # Fallback to outer-ai-prompt.md parser
        }
    }
    $promptPath = Join-Path $recommendationDir "outer-ai-prompt.md"
    if (Test-Path -LiteralPath $promptPath -PathType Leaf) {
        $promptRaw = Get-ContentUtf8 $promptPath
        if (-not [string]::IsNullOrWhiteSpace($promptRaw)) {
            $match = [regex]::Match($promptRaw, "(?m)^\s*Prompt-Contract-Version:\s*(?<version>\S+)\s*$")
            if ($match.Success) {
                return ([string]$match.Groups["version"].Value).Trim()
            }
        }
    }
    return ""
}

function Test-AuditUserProfilePreflight([string]$recommendationDir) {
    $path = Join-Path $recommendationDir "user-profile.json"
    $issues = New-Object System.Collections.Generic.List[string]
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    if (-not $exists) {
        return [pscustomobject]@{
            path = $path
            exists = $false
            ok = $true
            skipped = $true
            skipped_reason = "missing_optional_user_profile"
            issues = @($issues)
        }
    }

    try {
        Assert-AuditBundleFileContent $path "user-profile.json"
    }
    catch {
        $issues.Add([string]$_.Exception.Message) | Out-Null
    }
    return [pscustomobject]@{
        path = $path
        exists = $true
        ok = ($issues.Count -eq 0)
        skipped = $false
        skipped_reason = ""
        issues = @($issues)
    }
}

function Invoke-AuditRecommendationsPreflight {
    param(
        [string]$RecommendationsPath,
        [string]$RunId
    )
    $resolvedRecommendations = Resolve-AuditRecommendationsPathForPreflight $RecommendationsPath $RunId
    $rec = Load-AuditRecommendations $resolvedRecommendations
    $recommendationDir = Split-Path -Parent $resolvedRecommendations
    if ([string]::IsNullOrWhiteSpace($recommendationDir)) { $recommendationDir = "." }
    $snapshotPath = Join-Path $recommendationDir "installed-skills.json"
    $liveState = Get-AuditLiveInstalledState
    if (Test-Path -LiteralPath $snapshotPath -PathType Leaf) {
        $snapshotState = Get-AuditInstalledSnapshotState $snapshotPath
    }
    else {
        $snapshotState = New-AuditInstalledSnapshotFallbackState $liveState $snapshotPath
    }
    $skillSnapshotStale = ([string]$snapshotState.fingerprint -ne [string]$liveState.fingerprint)
    $mcpSnapshotStale = $false
    if ($snapshotState.PSObject.Properties.Match("mcp_fingerprint").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$snapshotState.mcp_fingerprint)) {
        $mcpSnapshotStale = ([string]$snapshotState.mcp_fingerprint -ne [string]$liveState.mcp_fingerprint)
    }
    $isSnapshotStale = ($skillSnapshotStale -or $mcpSnapshotStale)

    $runPromptVersion = Get-AuditRunPromptContractVersion $recommendationDir
    $currentPromptVersion = Get-AuditPromptContractVersion
    $promptVersionMatched = (-not [string]::IsNullOrWhiteSpace($runPromptVersion) -and [string]$runPromptVersion -eq [string]$currentPromptVersion)
    $sourcePolicy = Get-AuditSourceEvidencePolicy $recommendationDir
    $sourceCoverageCheck = Test-AuditRecommendationSourceCoveragePolicy $rec $sourcePolicy
    $decisionQualityPolicy = Get-AuditDecisionQualityPolicy $recommendationDir
    $decisionInsights = Get-AuditDecisionInsights $recommendationDir
    $decisionQualityCheck = Test-AuditRecommendationDecisionQualityPolicy $rec $decisionQualityPolicy $decisionInsights
    $userProfileCheck = Test-AuditUserProfilePreflight $recommendationDir

    $issues = New-Object System.Collections.Generic.List[string]
    if ($isSnapshotStale) {
        $issues.Add("stale_snapshot：审查快照与当前生效配置不一致，请先重新运行审查目标 扫描。") | Out-Null
    }
    if (-not $promptVersionMatched) {
        $runPromptDisplay = if ([string]::IsNullOrWhiteSpace($runPromptVersion)) { "missing" } else { [string]$runPromptVersion }
        $issues.Add(("prompt_contract_mismatch：run={0}，current={1}。请先重新运行审查目标 扫描生成新 run。" -f $runPromptDisplay, $currentPromptVersion)) | Out-Null
    }
    foreach ($issue in @($sourceCoverageCheck.issues)) {
        $issues.Add([string]$issue) | Out-Null
    }
    foreach ($issue in @($decisionQualityCheck.issues)) {
        $issues.Add([string]$issue) | Out-Null
    }
    foreach ($issue in @($userProfileCheck.issues)) {
        $issues.Add(("user_profile_invalid：{0}" -f [string]$issue)) | Out-Null
    }

    $report = [ordered]@{
        schema_version = 1
        run_id = [string]$rec.run_id
        target = [string]$rec.target
        success = ($issues.Count -eq 0)
        recommendations_path = $resolvedRecommendations
        prompt_contract = [ordered]@{
            run = $runPromptVersion
            current = $currentPromptVersion
            matched = $promptVersionMatched
        }
        source_evidence_policy = $sourcePolicy
        source_coverage = $sourceCoverageCheck.coverage
        decision_quality_policy = $decisionQualityPolicy
        decision_quality = $decisionQualityCheck.coverage
        decision_insights = $decisionInsights
        user_profile_check = $userProfileCheck
        snapshot_state = $snapshotState
        live_state = $liveState
        issues = @($issues)
    }
    $reportPath = Join-Path $recommendationDir "preflight-report.json"
    Write-AuditJsonFile $reportPath ([pscustomobject]$report)

    Write-Host ("预检报告：{0}" -f $reportPath) -ForegroundColor Cyan
    if ($issues.Count -eq 0) {
        Write-Host "预检通过：快照与提示词契约均匹配，可继续研究与 dry-run。" -ForegroundColor Green
        return [pscustomobject]$report
    }

    foreach ($issue in @($issues)) {
        Write-Host ("- {0}" -f [string]$issue) -ForegroundColor Red
    }
    throw ("预检失败：{0}" -f ($issues -join " | "))
}

function Invoke-AuditRecommendationsApply {
    param(
        [string]$RecommendationsPath,
        [string]$AddSelection,
        [string]$RemoveSelection,
        [string]$McpAddSelection,
        [string]$McpRemoveSelection,
        [string]$DryRunAck,
        [string]$StaleAck,
        [switch]$AllowStaleSnapshot,
        [bool]$RequireDryRunAck = $true,
        [switch]$Apply,
        [switch]$Yes
    )
    if ($Apply -and -not $Yes) {
        throw "执行安装必须同时传入 --apply --yes"
    }
    if ($Apply -and $Yes) {
        if ([string]::IsNullOrWhiteSpace($AddSelection)) { $AddSelection = "all" }
        if ([string]::IsNullOrWhiteSpace($RemoveSelection)) { $RemoveSelection = "all" }
        if ([string]::IsNullOrWhiteSpace($McpAddSelection)) { $McpAddSelection = "all" }
        if ([string]::IsNullOrWhiteSpace($McpRemoveSelection)) { $McpRemoveSelection = "all" }
    }
    $rec = Load-AuditRecommendations $RecommendationsPath
    $recommendationDir = Split-Path -Parent $RecommendationsPath
    if ([string]::IsNullOrWhiteSpace($recommendationDir)) { $recommendationDir = "." }
    $sourcePolicy = Get-AuditSourceEvidencePolicy $recommendationDir
    $sourceCoverageCheck = Test-AuditRecommendationSourceCoveragePolicy $rec $sourcePolicy
    $decisionQualityPolicy = Get-AuditDecisionQualityPolicy $recommendationDir
    $decisionInsights = Get-AuditDecisionInsights $recommendationDir
    $decisionQualityCheck = Test-AuditRecommendationDecisionQualityPolicy $rec $decisionQualityPolicy $decisionInsights
    if (-not [bool]$sourceCoverageCheck.pass) {
        $sourceMessage = ($sourceCoverageCheck.issues -join " | ")
        $sourceReport = [ordered]@{
            schema_version = 2
            run_id = [string]$rec.run_id
            target = [string]$rec.target
            mode = if ($Apply) { "apply" } else { "dry_run" }
            success = $false
            persisted = $false
            error_code = "insufficient_source_coverage"
            error_message = $sourceMessage
            source_evidence_policy = $sourcePolicy
            source_coverage = $sourceCoverageCheck.coverage
            decision_quality_policy = $decisionQualityPolicy
            decision_quality = $decisionQualityCheck.coverage
            decision_insights = $decisionInsights
            changed_counts = New-AuditChangedCounts @() @()
            items = @()
            removal_candidates = @()
            mcp_items = @()
            mcp_removal_candidates = @()
            overlap_findings = @()
            do_not_install = @()
            source_observations = @($rec.source_observations)
            rollback = @()
        }
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$sourceReport)
        $evidenceMode = if ($Apply) { "apply-blocked" } else { "dry-run-blocked" }
        $evidencePath = Write-AuditRuntimeEvidence $evidenceMode $RecommendationsPath ([pscustomobject]$sourceReport) @(".\\skills.ps1 审查目标 应用 --recommendations `"$RecommendationsPath`"")
        if (-not [string]::IsNullOrWhiteSpace($evidencePath)) {
            Write-Host ("审查运行证据：{0}" -f $evidencePath) -ForegroundColor Cyan
        }
        throw $sourceMessage
    }
    if (-not [bool]$decisionQualityCheck.pass) {
        $qualityMessage = ($decisionQualityCheck.issues -join " | ")
        $qualityReport = [ordered]@{
            schema_version = 2
            run_id = [string]$rec.run_id
            target = [string]$rec.target
            mode = if ($Apply) { "apply" } else { "dry_run" }
            success = $false
            persisted = $false
            error_code = "insufficient_decision_quality"
            error_message = $qualityMessage
            source_evidence_policy = $sourcePolicy
            source_coverage = $sourceCoverageCheck.coverage
            decision_quality_policy = $decisionQualityPolicy
            decision_quality = $decisionQualityCheck.coverage
            decision_insights = $decisionInsights
            changed_counts = New-AuditChangedCounts @() @()
            items = @()
            removal_candidates = @()
            mcp_items = @()
            mcp_removal_candidates = @()
            overlap_findings = @()
            do_not_install = @()
            source_observations = @($rec.source_observations)
            rollback = @()
        }
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$qualityReport)
        $evidenceMode = if ($Apply) { "apply-blocked" } else { "dry-run-blocked" }
        $evidencePath = Write-AuditRuntimeEvidence $evidenceMode $RecommendationsPath ([pscustomobject]$qualityReport) @(".\\skills.ps1 审查目标 应用 --recommendations `"$RecommendationsPath`"")
        if (-not [string]::IsNullOrWhiteSpace($evidencePath)) {
            Write-Host ("审查运行证据：{0}" -f $evidencePath) -ForegroundColor Cyan
        }
        throw $qualityMessage
    }
    $snapshotPath = Join-Path $recommendationDir "installed-skills.json"
    $liveState = Get-AuditLiveInstalledState
    if (Test-Path -LiteralPath $snapshotPath -PathType Leaf) {
        $snapshotState = Get-AuditInstalledSnapshotState $snapshotPath
    }
    else {
        Log ("recommendations 同目录缺少 installed-skills.json，已回退为 live state 快照：{0}" -f $snapshotPath) "WARN"
        $snapshotState = New-AuditInstalledSnapshotFallbackState $liveState $snapshotPath
    }
    $skillSnapshotStale = ([string]$snapshotState.fingerprint -ne [string]$liveState.fingerprint)
    $mcpSnapshotStale = $false
    if ($snapshotState.PSObject.Properties.Match("mcp_fingerprint").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$snapshotState.mcp_fingerprint)) {
        $mcpSnapshotStale = ([string]$snapshotState.mcp_fingerprint -ne [string]$liveState.mcp_fingerprint)
    }
    $isSnapshotStale = ($skillSnapshotStale -or $mcpSnapshotStale)
    if ($isSnapshotStale -and -not $AllowStaleSnapshot) {
        $staleMessage = "审查快照与当前生效配置不一致（stale_snapshot）。请先运行：.\skills.ps1 审查目标 扫描 重新生成 run 后再应用 recommendations。"
        $staleReport = [ordered]@{
            schema_version = 2
            run_id = [string]$rec.run_id
            target = [string]$rec.target
            mode = if ($Apply) { "apply" } else { "dry_run" }
            success = $false
            persisted = $false
            error_code = "stale_snapshot"
            error_message = $staleMessage
            source_evidence_policy = $sourcePolicy
            source_coverage = $sourceCoverageCheck.coverage
            decision_quality_policy = $decisionQualityPolicy
            decision_quality = $decisionQualityCheck.coverage
            decision_insights = $decisionInsights
            snapshot_state = $snapshotState
            live_state = $liveState
            changed_counts = New-AuditChangedCounts @() @()
            items = @()
            removal_candidates = @()
            mcp_items = @()
            mcp_removal_candidates = @()
            overlap_findings = @()
            do_not_install = @()
            source_observations = @($rec.source_observations)
            rollback = @()
        }
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$staleReport)
        throw $staleMessage
    }
    if ($isSnapshotStale -and $AllowStaleSnapshot) {
        $staleAckToken = Get-AuditStaleSnapshotAckToken ([string]$rec.run_id)
        Write-Host ""
        Write-Host "WARNING: 当前正在使用过期审查快照（stale_snapshot）继续执行。" -ForegroundColor Red
        Write-Host ("WARNING: live={0}, snapshot={1}" -f [int]$liveState.skill_count, [int]$snapshotState.skill_count) -ForegroundColor Red
        if ($liveState.PSObject.Properties.Match("mcp_server_count").Count -gt 0 -or $snapshotState.PSObject.Properties.Match("mcp_server_count").Count -gt 0) {
            $liveMcp = if ($liveState.PSObject.Properties.Match("mcp_server_count").Count -gt 0) { [int]$liveState.mcp_server_count } else { 0 }
            $snapshotMcp = if ($snapshotState.PSObject.Properties.Match("mcp_server_count").Count -gt 0) { [int]$snapshotState.mcp_server_count } else { 0 }
            Write-Host ("WARNING: mcp live={0}, snapshot={1}" -f $liveMcp, $snapshotMcp) -ForegroundColor Red
        }
        $staleAckInput = ""
        if (-not [string]::IsNullOrWhiteSpace($StaleAck)) {
            $staleAckInput = [string]$StaleAck
        }
        elseif (-not [Console]::IsInputRedirected) {
            $staleAckInput = Read-HostSafe ("请输入二次确认口令 `"{0}`"（回车取消）" -f $staleAckToken)
        }
        else {
            $hint = ("当前为非交互环境。请追加参数：--stale-ack `"{0}`"" -f $staleAckToken)
            $staleReport = [ordered]@{
                schema_version = 2
                run_id = [string]$rec.run_id
                target = [string]$rec.target
                mode = if ($Apply) { "apply" } else { "dry_run" }
                success = $false
                persisted = $false
                error_code = "stale_snapshot_ack_required"
                error_message = $hint
                source_evidence_policy = $sourcePolicy
                source_coverage = $sourceCoverageCheck.coverage
                decision_quality_policy = $decisionQualityPolicy
                decision_quality = $decisionQualityCheck.coverage
                decision_insights = $decisionInsights
                snapshot_state = $snapshotState
                live_state = $liveState
                changed_counts = New-AuditChangedCounts @() @()
                items = @()
                removal_candidates = @()
                mcp_items = @()
                mcp_removal_candidates = @()
                overlap_findings = @()
                do_not_install = @()
                source_observations = @($rec.source_observations)
                rollback = @()
                allow_stale_snapshot = $true
                stale_snapshot_detected = $true
                stale_acknowledged = $false
                stale_ack_expected = $staleAckToken
                stale_ack_received = ""
            }
            Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$staleReport)
            throw $hint
        }
        if ([string]::IsNullOrWhiteSpace($staleAckInput) -or $staleAckInput.Trim() -ne $staleAckToken) {
            $staleReport = [ordered]@{
                schema_version = 2
                run_id = [string]$rec.run_id
                target = [string]$rec.target
                mode = if ($Apply) { "apply" } else { "dry_run" }
                success = $false
                persisted = $false
                error_code = "stale_snapshot_ack_mismatch"
                error_message = "二次确认口令不匹配，已取消执行。"
                source_evidence_policy = $sourcePolicy
                source_coverage = $sourceCoverageCheck.coverage
                decision_quality_policy = $decisionQualityPolicy
                decision_quality = $decisionQualityCheck.coverage
                decision_insights = $decisionInsights
                snapshot_state = $snapshotState
                live_state = $liveState
                changed_counts = New-AuditChangedCounts @() @()
                items = @()
                removal_candidates = @()
                mcp_items = @()
                mcp_removal_candidates = @()
                overlap_findings = @()
                do_not_install = @()
                source_observations = @($rec.source_observations)
                rollback = @()
                allow_stale_snapshot = $true
                stale_snapshot_detected = $true
                stale_acknowledged = $false
                stale_ack_expected = $staleAckToken
                stale_ack_received = [string]$staleAckInput
            }
            Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$staleReport)
            throw "二次确认失败：未通过过期快照确认。"
        }
    }
    $plan = New-AuditInstallPlan $rec
    $report = [ordered]@{
        schema_version = 2
        run_id = [string]$rec.run_id
        target = [string]$rec.target
        decision_basis = $plan.decision_basis
        mode = if ($Apply) { "apply" } else { "dry_run" }
        success = $true
        persisted = $false
        source_evidence_policy = $sourcePolicy
        source_coverage = $sourceCoverageCheck.coverage
        decision_quality_policy = $decisionQualityPolicy
        decision_quality = $decisionQualityCheck.coverage
        decision_insights = $decisionInsights
        allow_stale_snapshot = [bool]$AllowStaleSnapshot
        stale_snapshot_detected = [bool]$isSnapshotStale
        stale_acknowledged = if ($isSnapshotStale -and $AllowStaleSnapshot) { $true } else { $false }
        changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
        snapshot_state = $snapshotState
        live_state = $liveState
        items = @($plan.items)
        removal_candidates = @($plan.removal_candidates)
        mcp_items = @($plan.mcp_items)
        mcp_removal_candidates = @($plan.mcp_removal_candidates)
        overlap_findings = @($plan.overlap_findings)
        do_not_install = @($plan.do_not_install)
        source_observations = @($plan.source_observations)
        rollback = @()
    }

    Write-AuditRecommendationSummary $plan $snapshotState $liveState

    if (-not $Apply) {
        Write-Host "dry-run 预览（沿用原序号）："
        foreach ($item in @($plan.items)) {
            Write-Host ("DRYRUN install: {0}" -f ($item.tokens -join " "))
        }
        foreach ($item in @($plan.removal_candidates)) {
            Write-Host ("DRYRUN remove: [{0}|{1}] {2}" -f [string]$item.vendor, [string]$item.from, [string]$item.name)
        }
        foreach ($item in @($plan.mcp_items)) {
            $server = $item.server
            $transport = if ($server.PSObject.Properties.Match("transport").Count -gt 0) { [string]$server.transport } else { "stdio" }
            if ($transport -eq "stdio") {
                $argsText = if ($server.PSObject.Properties.Match("args").Count -gt 0 -and $null -ne $server.args -and @($server.args).Count -gt 0) { " " + ((@($server.args) | ForEach-Object { [string]$_ }) -join " ") } else { "" }
                Write-Host ("DRYRUN mcp-add: {0} --transport stdio --cmd {1}{2}" -f [string]$server.name, [string]$server.command, $argsText)
            }
            else {
                Write-Host ("DRYRUN mcp-add: {0} --transport {1} --url {2}" -f [string]$server.name, $transport, [string]$server.url)
            }
        }
        foreach ($item in @($plan.mcp_removal_candidates)) {
            Write-Host ("DRYRUN mcp-remove: {0}" -f [string]$item.installed_name)
        }
        $dryRunSummaryPath = Get-AuditDryRunSummaryPath $RecommendationsPath
        $dryRunSummary = New-AuditDryRunSummary $plan $RecommendationsPath
        Write-AuditJsonFile $dryRunSummaryPath $dryRunSummary
        $report["dry_run_summary_path"] = $dryRunSummaryPath
        Write-Host ("dry-run 机器可读摘要：{0}" -f $dryRunSummaryPath) -ForegroundColor Cyan
        Write-Host "DRY-RUN 完成：未修改任何技能映射或 MCP 配置（未落盘）。" -ForegroundColor Red
        Write-Host ("如需真正执行，请运行：.\skills.ps1 审查目标 应用 --recommendations `"{0}`" --apply --yes" -f $RecommendationsPath) -ForegroundColor Red
        if ($RequireDryRunAck) {
            $ackToken = Get-AuditDryRunAckToken
            $ackInput = ""
            if (-not [string]::IsNullOrWhiteSpace($DryRunAck)) {
                $ackInput = [string]$DryRunAck
            }
            elseif (-not [Console]::IsInputRedirected) {
                $ackInput = Read-HostSafe ("请输入确认口令 `"{0}`" 表示你已知晓 dry-run 未落盘（回车取消）" -f $ackToken)
            }
            else {
                Write-Host ("当前为非交互环境。请追加参数：--dry-run-ack `"{0}`"" -f $ackToken) -ForegroundColor Red
            }
            if ([string]::IsNullOrWhiteSpace($ackInput) -or $ackInput.Trim() -ne $ackToken) {
                $report.success = $false
                $report["canceled"] = $true
                $report["dry_run_acknowledged"] = $false
                $report["dry_run_ack_expected"] = $ackToken
                $report["dry_run_ack_received"] = [string]$ackInput
                $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
                Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
                $evidencePath = Write-AuditRuntimeEvidence "dry-run-canceled" $RecommendationsPath ([pscustomobject]$report) @(".\\skills.ps1 审查目标 应用 --recommendations `"$RecommendationsPath`"")
                if (-not [string]::IsNullOrWhiteSpace($evidencePath)) {
                    Write-Host ("审查运行证据：{0}" -f $evidencePath) -ForegroundColor Cyan
                }
                return [pscustomobject]$report
            }
            $report["dry_run_acknowledged"] = $true
        }
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
        $evidencePath = Write-AuditRuntimeEvidence "dry-run" $RecommendationsPath ([pscustomobject]$report) @(".\\skills.ps1 审查目标 应用 --recommendations `"$RecommendationsPath`" --dry-run-ack `"$([string]$DryRunAck)`"")
        if (-not [string]::IsNullOrWhiteSpace($evidencePath)) {
            Write-Host ("审查运行证据：{0}" -f $evidencePath) -ForegroundColor Cyan
        }
        return [pscustomobject]$report
    }

    $selectedAdd = Resolve-AuditSelection $AddSelection $plan.items "请输入要安装的新增建议序号（空=跳过，0=取消）" "新增建议序号无效"
    if ($selectedAdd.canceled) {
        $report.success = $false
        $report["canceled"] = $true
        $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
        $report.persisted = $false
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
        return [pscustomobject]$report
    }
    $selectedRemove = Resolve-AuditSelection $RemoveSelection @($plan.removal_candidates | Where-Object { $_.status -eq "planned" }) "请输入要卸载的建议序号（空=跳过，0=取消）" "卸载建议序号无效"
    if ($selectedRemove.canceled) {
        $report.success = $false
        $report["canceled"] = $true
        $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
        $report.persisted = $false
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
        return [pscustomobject]$report
    }
    $selectedMcpAdd = Resolve-AuditSelection $McpAddSelection @($plan.mcp_items | Where-Object { $_.status -eq "planned" }) "请输入要新增的 MCP 建议序号（空=跳过，0=取消）" "MCP 新增建议序号无效"
    if ($selectedMcpAdd.canceled) {
        $report.success = $false
        $report["canceled"] = $true
        $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
        $report.persisted = $false
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
        return [pscustomobject]$report
    }
    $selectedMcpRemove = Resolve-AuditSelection $McpRemoveSelection @($plan.mcp_removal_candidates | Where-Object { $_.status -eq "planned" }) "请输入要卸载的 MCP 建议序号（空=跳过，0=取消）" "MCP 卸载建议序号无效"
    if ($selectedMcpRemove.canceled) {
        $report.success = $false
        $report["canceled"] = $true
        $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
        $report.persisted = $false
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
        return [pscustomobject]$report
    }

    try {
        foreach ($item in @($selectedAdd.items)) {
            $commandText = ".\skills.ps1 add {0}" -f ($item.tokens -join " ")
            try {
                Write-Host ("Installing recommended skill: {0}" -f $item.name) -ForegroundColor Cyan
                $beforeCfg = LoadCfg
                $ok = Add-ImportFromArgs $item.tokens -NoBuild
                if (-not $ok) { throw ("推荐技能安装失败：{0}" -f $item.name) }
                Ensure-AuditNewManualImportsMapped $beforeCfg | Out-Null
                $item.status = "installed"
                $item | Add-Member -NotePropertyName command -NotePropertyValue $commandText -Force
                $report.rollback += ("Remove matching imports/mappings for recommended skill '{0}' if rollback is required." -f $item.name)
            }
            catch {
                $item.status = "failed"
                $item | Add-Member -NotePropertyName command -NotePropertyValue $commandText -Force
                $item | Add-Member -NotePropertyName error -NotePropertyValue $_.Exception.Message -Force
                $report.success = $false
                $report.items = @($plan.items)
                $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
                $report.persisted = ((Get-AuditPersistedChangeTotal $report.changed_counts) -gt 0)
                Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
                throw
            }
        }

        if (@($selectedRemove.items).Count -gt 0) {
            Remove-AuditSelectedInstalledSkills $selectedRemove.items | Out-Null
            foreach ($item in @($selectedRemove.items)) {
                $report.rollback += ("Re-add removed skill mapping/import for '{0}' if rollback is required." -f $item.name)
            }
        }

        if (@($selectedMcpAdd.items).Count -gt 0 -or @($selectedMcpRemove.items).Count -gt 0) {
            try {
                Apply-AuditMcpSelections $selectedMcpAdd.items $selectedMcpRemove.items | Out-Null
                foreach ($item in @($selectedMcpAdd.items)) {
                    if ([string]$item.status -eq "added" -or [string]$item.status -eq "updated") {
                        $report.rollback += ("Restore previous MCP config for '{0}' if rollback is required." -f [string]$item.name)
                    }
                }
                foreach ($item in @($selectedMcpRemove.items)) {
                    if ([string]$item.status -eq "removed") {
                        $report.rollback += ("Re-add removed MCP server '{0}' if rollback is required." -f [string]$item.installed_name)
                    }
                }
            }
            catch {
                foreach ($item in @($selectedMcpAdd.items)) {
                    if ([string]$item.status -eq "planned") { $item.status = "failed" }
                    $item | Add-Member -NotePropertyName error -NotePropertyValue $_.Exception.Message -Force
                }
                foreach ($item in @($selectedMcpRemove.items)) {
                    if ([string]$item.status -eq "planned") { $item.status = "failed" }
                    $item | Add-Member -NotePropertyName error -NotePropertyValue $_.Exception.Message -Force
                }
                $report.success = $false
                $report.items = @($plan.items)
                $report.removal_candidates = @($plan.removal_candidates)
                $report.mcp_items = @($plan.mcp_items)
                $report.mcp_removal_candidates = @($plan.mcp_removal_candidates)
                $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
                $report.persisted = ((Get-AuditPersistedChangeTotal $report.changed_counts) -gt 0)
                Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
                throw
            }
        }

        $hasSkillChanges = (@($selectedAdd.items).Count -gt 0 -or @($selectedRemove.items).Count -gt 0)
        $hasMcpChanges = (@($selectedMcpAdd.items).Count -gt 0 -or @($selectedMcpRemove.items).Count -gt 0)

        if ($hasSkillChanges) {
            构建生效
        }
        if ($hasSkillChanges -or $hasMcpChanges) {
            $doctorResult = Invoke-Doctor @("--strict", "--threshold-ms", "8000")
            if ($doctorResult -and $doctorResult.PSObject.Properties.Match("pass").Count -gt 0 -and -not [bool]$doctorResult.pass) {
                $report.success = $false
                $report.items = @($plan.items)
                $report.removal_candidates = @($plan.removal_candidates)
                $report.mcp_items = @($plan.mcp_items)
                $report.mcp_removal_candidates = @($plan.mcp_removal_candidates)
                $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
                $report.persisted = ((Get-AuditPersistedChangeTotal $report.changed_counts) -gt 0)
                Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
                throw "doctor --strict failed after applying recommendations"
            }
        }

        $report.items = @($plan.items)
        $report.removal_candidates = @($plan.removal_candidates)
        $report.mcp_items = @($plan.mcp_items)
        $report.mcp_removal_candidates = @($plan.mcp_removal_candidates)
        $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
        $report.persisted = ((Get-AuditPersistedChangeTotal $report.changed_counts) -gt 0)
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
        $evidencePath = Write-AuditRuntimeEvidence "apply" $RecommendationsPath ([pscustomobject]$report) @(".\\skills.ps1 审查目标 应用 --recommendations `"$RecommendationsPath`" --apply --yes")
        if (-not [string]::IsNullOrWhiteSpace($evidencePath)) {
            Write-Host ("审查运行证据：{0}" -f $evidencePath) -ForegroundColor Cyan
        }
        return [pscustomobject]$report
    }
    catch {
        if ($report.success) { $report.success = $false }
        $report.items = @($plan.items)
        $report.removal_candidates = @($plan.removal_candidates)
        $report.mcp_items = @($plan.mcp_items)
        $report.mcp_removal_candidates = @($plan.mcp_removal_candidates)
        $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
        $report.persisted = ((Get-AuditPersistedChangeTotal $report.changed_counts) -gt 0)
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
        $evidencePath = Write-AuditRuntimeEvidence "apply-failed" $RecommendationsPath ([pscustomobject]$report) @(".\\skills.ps1 审查目标 应用 --recommendations `"$RecommendationsPath`" --apply --yes")
        if (-not [string]::IsNullOrWhiteSpace($evidencePath)) {
            Write-Host ("审查运行证据：{0}" -f $evidencePath) -ForegroundColor Cyan
        }
        throw
    }
}

function Get-AuditApplyConfirmationToken([string]$runId) {
    if ([string]::IsNullOrWhiteSpace($runId)) { return "APPLY" }
    return ("APPLY {0}" -f $runId)
}

function Get-AuditDryRunAckToken {
    return "我知道未落盘"
}

function Get-AuditStaleSnapshotAckToken([string]$runId) {
    if ([string]::IsNullOrWhiteSpace($runId)) { return "我确认使用过期快照" }
    return ("我确认使用过期快照 {0}" -f $runId)
}

function Invoke-AuditRecommendationsTwoStageApply {
    param(
        [string]$RecommendationsPath,
        [string]$AddSelection,
        [string]$RemoveSelection,
        [string]$McpAddSelection,
        [string]$McpRemoveSelection,
        [string]$DryRunAck,
        [string]$StaleAck,
        [switch]$AllowStaleSnapshot
    )
    $dryRunReport = Invoke-AuditRecommendationsApply -RecommendationsPath $RecommendationsPath -AddSelection $AddSelection -RemoveSelection $RemoveSelection -McpAddSelection $McpAddSelection -McpRemoveSelection $McpRemoveSelection -DryRunAck $DryRunAck -StaleAck $StaleAck -AllowStaleSnapshot:$AllowStaleSnapshot -RequireDryRunAck $true
    if ($dryRunReport.PSObject.Properties.Match("success").Count -gt 0 -and -not [bool]$dryRunReport.success) {
        Write-Host "应用确认结束：dry-run 未完成确认，未执行落盘。" -ForegroundColor Yellow
        return $dryRunReport
    }
    $plannedAdds = @($dryRunReport.items | Where-Object { [string]$_.status -eq "planned" }).Count
    $plannedRemoves = @($dryRunReport.removal_candidates | Where-Object { [string]$_.status -eq "planned" }).Count
    $plannedMcpAdds = @($dryRunReport.mcp_items | Where-Object { [string]$_.status -eq "planned" }).Count
    $plannedMcpRemoves = @($dryRunReport.mcp_removal_candidates | Where-Object { [string]$_.status -eq "planned" }).Count
    if ($plannedAdds -eq 0 -and $plannedRemoves -eq 0 -and $plannedMcpAdds -eq 0 -and $plannedMcpRemoves -eq 0) {
        Write-Host "应用确认结束：无可执行变更，保持当前状态。" -ForegroundColor Yellow
        return $dryRunReport
    }

    $confirmToken = Get-AuditApplyConfirmationToken ([string]$dryRunReport.run_id)
    Write-Host ""
    Write-Host ("确认口令：{0}" -f $confirmToken) -ForegroundColor Yellow
    $confirmation = Read-HostSafe "请输入确认口令后回车执行（回车取消）"
    if ([string]::IsNullOrWhiteSpace($confirmation) -or $confirmation.Trim() -ne $confirmToken) {
        Write-Host "已取消执行。未做任何落盘更改。" -ForegroundColor Yellow
        return [pscustomobject]([ordered]@{
            schema_version = 2
            run_id = [string]$dryRunReport.run_id
            target = [string]$dryRunReport.target
            mode = "apply_flow"
            success = $false
            canceled = $true
            expected_confirmation = $confirmToken
            received_confirmation = [string]$confirmation
        })
    }
    return (Invoke-AuditRecommendationsApply -RecommendationsPath $RecommendationsPath -AddSelection $AddSelection -RemoveSelection $RemoveSelection -McpAddSelection $McpAddSelection -McpRemoveSelection $McpRemoveSelection -StaleAck $StaleAck -AllowStaleSnapshot:$AllowStaleSnapshot -Apply -Yes)
}

function Get-AuditLatestApplyReportPath {
    $auditRoot = Join-Path $script:Root "reports\skill-audit"
    if (-not (Test-Path -LiteralPath $auditRoot -PathType Container)) { return $null }
    $candidates = @(Get-ChildItem -Path $auditRoot -Recurse -File -Filter "apply-report.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($candidates.Count -eq 0) { return $null }
    return [string]$candidates[0].FullName
}

function Show-AuditLatestStatus {
    $path = Get-AuditLatestApplyReportPath
    if ([string]::IsNullOrWhiteSpace($path)) {
        Write-Host "未找到 apply-report.json。请先执行：审查目标 应用确认 或 审查目标 应用。" -ForegroundColor Yellow
        return
    }
    try {
        $raw = Get-ContentUtf8 $path
        Need (-not [string]::IsNullOrWhiteSpace($raw)) ("状态文件为空：{0}" -f $path)
        $report = $raw | ConvertFrom-Json
    }
    catch {
        throw ("读取状态文件失败：{0}" -f $_.Exception.Message)
    }
    $counts = if ($report.PSObject.Properties.Match("changed_counts").Count -gt 0 -and $null -ne $report.changed_counts) { $report.changed_counts } else { $null }
    $persisted = if ($report.PSObject.Properties.Match("persisted").Count -gt 0) { [bool]$report.persisted } else { $false }
    Write-Host "=== 审查目标最近状态 ==="
    Write-Host ("report: {0}" -f $path)
    Write-Host ("run_id: {0}" -f [string]$report.run_id)
    Write-Host ("mode: {0}" -f [string]$report.mode)
    Write-Host ("success: {0}" -f [string]$report.success)
    Write-Host ("persisted: {0}" -f $persisted)
    if ($null -ne $counts) {
        Write-Host ("changes: add_installed={0}, remove_removed={1}, add_planned={2}, remove_planned={3}, remove_not_found={4}" -f [int]$counts.add_installed, [int]$counts.remove_removed, [int]$counts.add_planned, [int]$counts.remove_planned, [int]$counts.remove_not_found)
        if ($counts.PSObject.Properties.Match("mcp_add_total").Count -gt 0) {
            Write-Host ("mcp_changes: add_added={0}, add_updated={1}, add_planned={2}, remove_removed={3}, remove_planned={4}, remove_not_found={5}" -f [int]$counts.mcp_add_added, [int]$counts.mcp_add_updated, [int]$counts.mcp_add_planned, [int]$counts.mcp_remove_removed, [int]$counts.mcp_remove_planned, [int]$counts.mcp_remove_not_found)
        }
    }
    if ([string]$report.mode -eq "dry_run" -and -not $persisted) {
        Write-Host "警告：最近一次仅为 dry-run，未落盘。" -ForegroundColor Red
    }
}

function Parse-AuditTargetsArgs([string[]]$tokens) {
    $result = [ordered]@{
        action = "list"
        name = $null
        path = $null
        profile = $null
        target = $null
        run_id = $null
        out = $null
        query = $null
        recommendations = $null
        dry_run_ack = $null
        stale_ack = $null
        allow_stale_snapshot = $false
        force = $false
        add_selection = $null
        remove_selection = $null
        mcp_add_selection = $null
        mcp_remove_selection = $null
        apply = $false
        yes = $false
        tags = @()
        notes = ""
    }

    $items = @($tokens | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($items.Count -gt 0) {
        $head = ([string]$items[0]).ToLowerInvariant()
        switch ($head) {
            "初始化" { $result.action = "init"; $items = @($items | Select-Object -Skip 1) }
            "init" { $result.action = "init"; $items = @($items | Select-Object -Skip 1) }
            "需求设置" { $result.action = "profile_set"; $items = @($items | Select-Object -Skip 1) }
            "profile-set" { $result.action = "profile_set"; $items = @($items | Select-Object -Skip 1) }
            "需求查看" { $result.action = "profile_show"; $items = @($items | Select-Object -Skip 1) }
            "profile-show" { $result.action = "profile_show"; $items = @($items | Select-Object -Skip 1) }
            "需求结构化" { $result.action = "profile_structure"; $items = @($items | Select-Object -Skip 1) }
            "profile-structure" { $result.action = "profile_structure"; $items = @($items | Select-Object -Skip 1) }
            "添加" { $result.action = "add"; $items = @($items | Select-Object -Skip 1) }
            "add" { $result.action = "add"; $items = @($items | Select-Object -Skip 1) }
            "修改" { $result.action = "update"; $items = @($items | Select-Object -Skip 1) }
            "update" { $result.action = "update"; $items = @($items | Select-Object -Skip 1) }
            "删除" { $result.action = "remove"; $items = @($items | Select-Object -Skip 1) }
            "remove" { $result.action = "remove"; $items = @($items | Select-Object -Skip 1) }
            "列表" { $result.action = "list"; $items = @($items | Select-Object -Skip 1) }
            "列出" { $result.action = "list"; $items = @($items | Select-Object -Skip 1) }
            "目标列表" { $result.action = "list"; $items = @($items | Select-Object -Skip 1) }
            "target-list" { $result.action = "list"; $items = @($items | Select-Object -Skip 1) }
            "targets" { $result.action = "list"; $items = @($items | Select-Object -Skip 1) }
            "list" { $result.action = "list"; $items = @($items | Select-Object -Skip 1) }
            "扫描" { $result.action = "scan"; $items = @($items | Select-Object -Skip 1) }
            "scan" { $result.action = "scan"; $items = @($items | Select-Object -Skip 1) }
            "发现新技能" { $result.action = "discover_skills"; $items = @($items | Select-Object -Skip 1) }
            "discover-skills" { $result.action = "discover_skills"; $items = @($items | Select-Object -Skip 1) }
            "discover" { $result.action = "discover_skills"; $items = @($items | Select-Object -Skip 1) }
            "状态" { $result.action = "status"; $items = @($items | Select-Object -Skip 1) }
            "status" { $result.action = "status"; $items = @($items | Select-Object -Skip 1) }
            "预检" { $result.action = "preflight"; $items = @($items | Select-Object -Skip 1) }
            "preflight" { $result.action = "preflight"; $items = @($items | Select-Object -Skip 1) }
            "应用确认" { $result.action = "apply_flow"; $items = @($items | Select-Object -Skip 1) }
            "apply-flow" { $result.action = "apply_flow"; $items = @($items | Select-Object -Skip 1) }
            "应用" { $result.action = "apply"; $items = @($items | Select-Object -Skip 1) }
            "apply" { $result.action = "apply"; $items = @($items | Select-Object -Skip 1) }
            "帮助" { $result.action = "help"; $items = @($items | Select-Object -Skip 1) }
            "help" { $result.action = "help"; $items = @($items | Select-Object -Skip 1) }
            "--help" { $result.action = "help"; $items = @($items | Select-Object -Skip 1) }
            "-h" { $result.action = "help"; $items = @($items | Select-Object -Skip 1) }
            default { throw ("未知审查目标子命令：{0}" -f $items[0]) }
        }
    }

    $positional = @()
    for ($i = 0; $i -lt $items.Count; $i++) {
        $t = [string]$items[$i]
        $key = $t.ToLowerInvariant()
        switch ($key) {
            "--target" {
                Need ($i + 1 -lt $items.Count) "--target 缺少值"
                $result.target = [string]$items[++$i]
                continue
            }
            "--run-id" {
                Need ($i + 1 -lt $items.Count) "--run-id 缺少值"
                $result.run_id = Resolve-AuditRunIdInput ([string]$items[++$i]) "--run-id" @("recommendations.json", "installed-skills.json", "audit-meta.json")
                continue
            }
            "--profile" {
                Need ($i + 1 -lt $items.Count) "--profile 缺少值"
                $result.profile = [string]$items[++$i]
                continue
            }
            "--out" {
                Need ($i + 1 -lt $items.Count) "--out 缺少值"
                $result.out = [string]$items[++$i]
                if (Test-AuditPlaceholderToken $result.out) {
                    throw ("--out 路径包含未替换占位符：{0}`n{1}" -f $result.out, (Get-AuditRunIdHintText))
                }
                continue
            }
            "--query" {
                Need ($i + 1 -lt $items.Count) "--query 缺少值"
                $result.query = [string]$items[++$i]
                continue
            }
            "--recommendations" {
                Need ($i + 1 -lt $items.Count) "--recommendations 缺少值"
                $result.recommendations = Resolve-AuditPathRunIdPlaceholder ([string]$items[++$i]) "--recommendations" @("recommendations.json", "installed-skills.json", "audit-meta.json")
                continue
            }
            "--dry-run-ack" {
                Need ($i + 1 -lt $items.Count) "--dry-run-ack 缺少值"
                $result.dry_run_ack = [string]$items[++$i]
                continue
            }
            "--stale-ack" {
                Need ($i + 1 -lt $items.Count) "--stale-ack 缺少值"
                $result.stale_ack = [string]$items[++$i]
                continue
            }
            "--allow-stale-snapshot" {
                $result.allow_stale_snapshot = $true
                continue
            }
            "--force" {
                $result.force = $true
                continue
            }
            "--add-indexes" {
                Need ($i + 1 -lt $items.Count) "--add-indexes 缺少值"
                $result.add_selection = [string]$items[++$i]
                continue
            }
            "--remove-indexes" {
                Need ($i + 1 -lt $items.Count) "--remove-indexes 缺少值"
                $result.remove_selection = [string]$items[++$i]
                continue
            }
            "--mcp-add-indexes" {
                Need ($i + 1 -lt $items.Count) "--mcp-add-indexes 缺少值"
                $result.mcp_add_selection = [string]$items[++$i]
                continue
            }
            "--mcp-remove-indexes" {
                Need ($i + 1 -lt $items.Count) "--mcp-remove-indexes 缺少值"
                $result.mcp_remove_selection = [string]$items[++$i]
                continue
            }
            "--apply" {
                $result.apply = $true
                continue
            }
            "--yes" {
                $result.yes = $true
                continue
            }
            "--tag" {
                Need ($i + 1 -lt $items.Count) "--tag 缺少值"
                $result.tags += [string]$items[++$i]
                continue
            }
            "--notes" {
                Need ($i + 1 -lt $items.Count) "--notes 缺少值"
                $result.notes = [string]$items[++$i]
                continue
            }
            default {
                $positional += $t
            }
        }
    }

    if ($result.action -eq "add" -or $result.action -eq "update") {
        Need ($positional.Count -ge 2) "目标仓操作需要 name 和 path"
        $result.name = [string]$positional[0]
        $result.path = [string]$positional[1]
    }
    elseif ($result.action -eq "remove") {
        Need ($positional.Count -ge 1) "删除目标仓需要 name"
        $result.name = [string]$positional[0]
    }
    return [pscustomobject]$result
}

function Show-AuditTargetsCommandHelp {
    Write-Host "审查目标 子命令：" -ForegroundColor Cyan
    Write-Host "  .\skills.ps1 审查目标 帮助"
    Write-Host "  .\skills.ps1 审查目标 初始化"
    Write-Host "  .\skills.ps1 审查目标 需求设置"
    Write-Host "  .\skills.ps1 审查目标 需求查看"
    Write-Host "  .\skills.ps1 审查目标 需求结构化 [--profile <file>]"
    Write-Host "  .\skills.ps1 审查目标 添加 <name> <path>"
    Write-Host "  .\skills.ps1 审查目标 修改 <name> <path>"
    Write-Host "  .\skills.ps1 审查目标 删除 <name>"
    Write-Host "  .\skills.ps1 审查目标 列表"
    Write-Host "  .\skills.ps1 审查目标 目标列表"
    Write-Host "  .\skills.ps1 审查目标 扫描 [--target <name>] [--out <dir>] [--force]"
    Write-Host "  .\skills.ps1 审查目标 发现新技能 [--query <text>] [--out <dir>] [--force]"
    Write-Host "  .\skills.ps1 审查目标 预检 --run-id <run-id>"
    Write-Host "  .\skills.ps1 审查目标 预检 --recommendations <file>"
    Write-Host "  .\skills.ps1 审查目标 应用确认 --recommendations <file>"
    Write-Host "  .\skills.ps1 审查目标 应用 --recommendations <file> [--dry-run-ack ""我知道未落盘""]"
    Write-Host "  .\skills.ps1 审查目标 状态"
}

function Invoke-AuditTargetsCommand([string[]]$tokens = @()) {
    $opts = Parse-AuditTargetsArgs $tokens
    switch ($opts.action) {
        "help" { Show-AuditTargetsCommandHelp }
        "init" {
            if (Initialize-AuditTargetsConfig) {
                Write-Host "已创建 audit-targets.json" -ForegroundColor Green
            }
            else {
                Write-Host "audit-targets.json 已存在，未覆盖。" -ForegroundColor Yellow
            }
        }
        "profile_set" {
            $rawText = Read-HostSafe "请输入用户基本需求（长文本）"
            Set-AuditUserProfileRawText $rawText
            $defaultPath = Get-AuditStructuredProfileDefaultPath
            $profilePath = Read-HostSafe ("结构化 profile 文件路径（回车使用默认：{0}；输入 0 跳过）" -f $defaultPath)
            if ([string]$profilePath.Trim() -eq "0") {
                Write-Host "已保存用户基本需求。结构化导入已跳过。" -ForegroundColor Green
            }
            else {
                Invoke-AuditStructuredProfileFlow $profilePath
            }
        }
        "profile_show" { Show-AuditUserProfile }
        "profile_structure" {
            Invoke-AuditStructuredProfileFlow $opts.profile
        }
        "add" {
            Add-AuditTargetConfigEntry $opts.name $opts.path $opts.tags $opts.notes | Out-Null
            Write-Host ("已登记目标仓：{0}" -f (Normalize-Name $opts.name)) -ForegroundColor Green
        }
        "update" {
            Update-AuditTargetConfigEntry $opts.name $opts.path $opts.tags $opts.notes | Out-Null
            Write-Host ("已更新目标仓：{0}" -f (Normalize-Name $opts.name)) -ForegroundColor Green
        }
        "remove" {
            Remove-AuditTargetConfigEntry $opts.name | Out-Null
            Write-Host ("已删除目标仓：{0}" -f (Normalize-Name $opts.name)) -ForegroundColor Green
        }
        "list" { Write-AuditTargetsList }
        "status" { Show-AuditLatestStatus }
        "preflight" { Invoke-AuditRecommendationsPreflight -RecommendationsPath $opts.recommendations -RunId $opts.run_id | Out-Null }
        "scan" { Invoke-AuditTargetsScan -Target $opts.target -OutDir $opts.out -Force:$opts.force | Out-Null }
        "discover_skills" { Invoke-AuditSkillDiscovery -Query $opts.query -OutDir $opts.out -Force:$opts.force | Out-Null }
        "apply_flow" { Invoke-AuditRecommendationsTwoStageApply -RecommendationsPath $opts.recommendations -AddSelection $opts.add_selection -RemoveSelection $opts.remove_selection -McpAddSelection $opts.mcp_add_selection -McpRemoveSelection $opts.mcp_remove_selection -DryRunAck $opts.dry_run_ack -StaleAck $opts.stale_ack -AllowStaleSnapshot:$opts.allow_stale_snapshot | Out-Null }
        "apply" { Invoke-AuditRecommendationsApply -RecommendationsPath $opts.recommendations -AddSelection $opts.add_selection -RemoveSelection $opts.remove_selection -McpAddSelection $opts.mcp_add_selection -McpRemoveSelection $opts.mcp_remove_selection -DryRunAck $opts.dry_run_ack -StaleAck $opts.stale_ack -AllowStaleSnapshot:$opts.allow_stale_snapshot -RequireDryRunAck (-not $opts.apply) -Apply:$opts.apply -Yes:$opts.yes | Out-Null }
    }
}

function Get-WorkflowCatalog {
    $doctorStrictStep = [pscustomobject]@{
        id = "doctor_strict"
        title = "严格健康检查（doctor --strict）"
        command = "doctor --strict --threshold-ms 8000"
        action = {
            $report = Invoke-Doctor @("--strict", "--threshold-ms", "8000")
            if ($report -and $report.PSObject.Properties.Match("pass").Count -gt 0 -and -not [bool]$report.pass) {
                throw "doctor --strict failed"
            }
        }
    }

    return [ordered]@{
        quickstart = [pscustomobject]@{
            key = "quickstart"
            name = "新手"
            description = "从浏览技能到安装、重建并同步、严格检查的一条龙流程。"
            steps = @(
                [pscustomobject]@{
                    id = "discover"
                    title = "浏览技能"
                    command = "发现"
                    action = { 发现 }
                },
                [pscustomobject]@{
                    id = "install_interactive"
                    title = "选择安装"
                    command = "安装"
                    action = { 安装 }
                },
                [pscustomobject]@{
                    id = "build_apply"
                    title = "重建并同步"
                    command = "构建生效"
                    action = { 构建生效 }
                },
                $doctorStrictStep
            )
        }
        maintenance = [pscustomobject]@{
            key = "maintenance"
            name = "维护"
            description = "适合日常维护：更新上游、重建并同步、同步 MCP、严格检查。"
            steps = @(
                [pscustomobject]@{
                    id = "update"
                    title = "更新上游"
                    command = "更新"
                    action = { 更新 }
                },
                [pscustomobject]@{
                    id = "build_apply"
                    title = "重建并同步"
                    command = "构建生效"
                    action = { 构建生效 }
                },
                [pscustomobject]@{
                    id = "sync_mcp"
                    title = "同步 MCP"
                    command = "同步MCP"
                    action = { 同步MCP }
                },
                $doctorStrictStep
            )
        }
        audit = [pscustomobject]@{
            key = "audit"
            name = "审查"
            description = "聚焦目标仓审查：查看需求、生成审查包、回看最近状态。"
            steps = @(
                [pscustomobject]@{
                    id = "audit_profile_show"
                    title = "查看需求"
                    command = "审查目标 需求查看"
                    action = { Invoke-AuditTargetsCommand @("profile-show") }
                },
                [pscustomobject]@{
                    id = "audit_target_list"
                    title = "目标仓列表"
                    command = "审查目标 列出"
                    action = { Invoke-AuditTargetsCommand @("list") }
                },
                [pscustomobject]@{
                    id = "audit_scan"
                    title = "生成审查包"
                    command = "审查目标 扫描"
                    action = { Invoke-AuditTargetsCommand @("scan") }
                },
                [pscustomobject]@{
                    id = "audit_status"
                    title = "查看最近状态"
                    command = "审查目标 状态"
                    action = { Invoke-AuditTargetsCommand @("status") }
                }
            )
        }
        all = [pscustomobject]@{
            key = "all"
            name = "全流程"
            description = "通用一键巡检：更新上游、浏览技能、重建并同步、同步 MCP、严格检查。"
            steps = @(
                [pscustomobject]@{
                    id = "update"
                    title = "更新上游"
                    command = "更新"
                    action = { 更新 }
                },
                [pscustomobject]@{
                    id = "discover"
                    title = "浏览技能"
                    command = "发现"
                    action = { 发现 }
                },
                [pscustomobject]@{
                    id = "build_apply"
                    title = "重建并同步"
                    command = "构建生效"
                    action = { 构建生效 }
                },
                [pscustomobject]@{
                    id = "sync_mcp"
                    title = "同步 MCP"
                    command = "同步MCP"
                    action = { 同步MCP }
                },
                $doctorStrictStep
            )
        }
    }
}

function Resolve-WorkflowProfileKey([string]$profile) {
    if ([string]::IsNullOrWhiteSpace($profile)) { return $null }
    $k = $profile.Trim().ToLowerInvariant()
    switch ($k) {
        "新手" { return "quickstart" }
        "quickstart" { return "quickstart" }
        "start" { return "quickstart" }
        "onboarding" { return "quickstart" }
        "维护" { return "maintenance" }
        "maintenance" { return "maintenance" }
        "maintain" { return "maintenance" }
        "审查" { return "audit" }
        "audit" { return "audit" }
        "全流程" { return "all" }
        "all" { return "all" }
        "full" { return "all" }
        default { return $null }
    }
}

function Parse-WorkflowArgs([string[]]$tokens) {
    $opts = [ordered]@{
        profile = $null
        list = $false
        continue_on_error = $false
        no_prompt = $false
    }
    if ($null -eq $tokens) { return [pscustomobject]$opts }

    :tokenLoop for ($i = 0; $i -lt $tokens.Count; $i++) {
        $token = [string]$tokens[$i]
        if ([string]::IsNullOrWhiteSpace($token)) { continue }
        $lower = $token.Trim().ToLowerInvariant()
        switch ($lower) {
            "--list" { $opts.list = $true; continue tokenLoop }
            "-l" { $opts.list = $true; continue tokenLoop }
            "--continue-on-error" { $opts.continue_on_error = $true; continue tokenLoop }
            "--no-prompt" { $opts.no_prompt = $true; continue tokenLoop }
            "--profile" {
                Need ($i + 1 -lt $tokens.Count) "--profile 缺少值"
                $rawProfile = [string]$tokens[++$i]
                $resolved = Resolve-WorkflowProfileKey $rawProfile
                Need (-not [string]::IsNullOrWhiteSpace($resolved)) ("未知工作流场景：{0}" -f $rawProfile)
                $opts.profile = $resolved
                continue tokenLoop
            }
        }

        if ($token.StartsWith("-")) {
            throw ("未知一键参数：{0}" -f $token)
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$opts.profile)) {
            throw ("重复的场景参数：{0}" -f $token)
        }
        $positional = Resolve-WorkflowProfileKey $token
        Need (-not [string]::IsNullOrWhiteSpace($positional)) ("未知工作流场景：{0}" -f $token)
        $opts.profile = $positional
    }

    return [pscustomobject]$opts
}

function Write-WorkflowCatalog($catalog) {
    Write-Host "=== 一键工作流可用场景 ===" -ForegroundColor Cyan
    foreach ($key in @("quickstart", "maintenance", "audit", "all")) {
        if (-not $catalog.Contains($key)) { continue }
        $w = $catalog[$key]
        Write-Host ("- {0} ({1}): {2}" -f $w.name, $w.key, $w.description)
    }
    Write-Host ""
    Write-Host "示例：" -ForegroundColor DarkGray
    Write-Host ".\skills.ps1 一键 新手"
    Write-Host ".\skills.ps1 一键 维护 --continue-on-error"
    Write-Host ".\skills.ps1 一键 审查 --no-prompt"
    Write-Host ".\skills.ps1 workflow all --no-prompt"
}

function Select-WorkflowProfileInteractively($catalog) {
    while ($true) {
        Write-Host ""
        Write-Host "=== 选择一键工作流场景 ==="
        Write-Host "1) 新手（浏览技能 -> 选择安装 -> 重建并同步 -> doctor --strict）"
        Write-Host "2) 维护（更新上游 -> 重建并同步 -> 同步 MCP -> doctor --strict）"
        Write-Host "3) 审查（查看需求 -> 目标仓列表 -> 生成审查包 -> 查看最近状态）"
        Write-Host "4) 全流程（更新上游 -> 浏览技能 -> 重建并同步 -> 同步 MCP -> doctor --strict）"
        Write-Host "0) 取消"
        $choice = Read-MenuChoice "请选择（回车取消）"
        switch ($choice) {
            "1" { return "quickstart" }
            "2" { return "maintenance" }
            "3" { return "audit" }
            "4" { return "all" }
            "0" { return $null }
            default { Write-Host "无效选择。" }
        }
    }
}

function Get-WorkflowPreviewLines($workflow) {
    $lines = New-Object System.Collections.Generic.List[string]
    $idx = 0
    foreach ($step in @($workflow.steps)) {
        $idx++
        $line = ("{0,2}. {1}  [{2}]" -f $idx, [string]$step.title, [string]$step.command)
        $lines.Add($line) | Out-Null
    }
    return $lines.ToArray()
}

function Invoke-WorkflowStep([int]$Index, [int]$Total, $Step) {
    $title = [string]$Step.title
    $command = [string]$Step.command
    $id = [string]$Step.id
    Write-Host ("[{0}/{1}] {2}" -f $Index, $Total, $title) -ForegroundColor Cyan
    Write-Host ("  command: {0}" -f $command) -ForegroundColor DarkGray

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $error = ""
    $success = $false
    try {
        & $Step.action
        $success = $true
        Write-Host ("  ✅ 完成（{0} ms）" -f [int]$sw.ElapsedMilliseconds) -ForegroundColor Green
    }
    catch {
        $error = $_.Exception.Message
        Write-Host ("  ❌ 失败（{0} ms）：{1}" -f [int]$sw.ElapsedMilliseconds, $error) -ForegroundColor Red
    }
    finally {
        $sw.Stop()
    }

    return [pscustomobject]@{
        id = $id
        title = $title
        command = $command
        success = $success
        duration_ms = [int]$sw.ElapsedMilliseconds
        error = $error
    }
}

function Write-WorkflowResultSummary($workflow, $results, [int]$totalMs) {
    $failed = @($results | Where-Object { -not [bool]$_.success })
    $passed = @($results | Where-Object { [bool]$_.success })
    Write-Host ""
    Write-Host ("=== 一键工作流完成：{0} ===" -f [string]$workflow.name) -ForegroundColor Cyan
    Write-Host ("总耗时：{0} ms" -f $totalMs)
    Write-Host ("步骤：成功 {0} / 失败 {1}" -f $passed.Count, $failed.Count)
    if ($failed.Count -gt 0) {
        foreach ($item in $failed) {
            Write-Host ("- 失败：{0} => {1}" -f [string]$item.command, [string]$item.error) -ForegroundColor Yellow
        }
    }
}

function Invoke-Workflow([string[]]$tokens = @()) {
    $opts = Parse-WorkflowArgs $tokens
    $catalog = Get-WorkflowCatalog

    if ($opts.list) {
        Write-WorkflowCatalog $catalog
        return [pscustomobject]@{ pass = $true; listed = $true }
    }

    $profileKey = [string]$opts.profile
    if ([string]::IsNullOrWhiteSpace($profileKey)) {
        if ($opts.no_prompt) {
            $profileKey = "all"
            Write-Host "未指定场景且启用 --no-prompt，默认使用：全流程（all）"
        }
        else {
            $profileKey = Select-WorkflowProfileInteractively $catalog
            if ([string]::IsNullOrWhiteSpace($profileKey)) {
                Write-Host "已取消一键工作流。"
                return [pscustomobject]@{ pass = $false; canceled = $true }
            }
        }
    }

    Need ($catalog.Contains($profileKey)) ("未知工作流场景：{0}" -f $profileKey)
    $workflow = $catalog[$profileKey]
    $preview = @(Get-WorkflowPreviewLines $workflow)

    if (-not $opts.no_prompt) {
        if (-not (Confirm-WithSummary ("将执行一键工作流：{0}" -f [string]$workflow.name) $preview "确认继续执行？" "Y")) {
            Write-Host "已取消一键工作流。"
            return [pscustomobject]@{ pass = $false; canceled = $true }
        }
    }

    return (Invoke-WithMetric "workflow_run" {
        $results = New-Object System.Collections.Generic.List[object]
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $index = 0
        foreach ($step in @($workflow.steps)) {
            $index++
            $result = Invoke-WorkflowStep $index @($workflow.steps).Count $step
            $results.Add($result) | Out-Null
            if (-not [bool]$result.success -and -not [bool]$opts.continue_on_error) {
                break
            }
        }
        $sw.Stop()

        $resultArray = $results.ToArray()
        Write-WorkflowResultSummary $workflow $resultArray ([int]$sw.ElapsedMilliseconds)
        $failed = @($resultArray | Where-Object { -not [bool]$_.success })
        $pass = ($failed.Count -eq 0)
        Log ("一键工作流执行完成：{0}（pass={1}）" -f [string]$workflow.key, $pass) "INFO" -Data @{
            profile = [string]$workflow.key
            pass = $pass
            total_ms = [int]$sw.ElapsedMilliseconds
            step_total = @($resultArray).Count
            step_failed = $failed.Count
        }
        if (-not $pass -and -not [bool]$opts.continue_on_error) {
            throw ("一键工作流失败：{0}" -f [string]$failed[0].error)
        }
        return [pscustomobject]@{
            pass = $pass
            profile = [string]$workflow.key
            continue_on_error = [bool]$opts.continue_on_error
            results = @($resultArray)
            total_ms = [int]$sw.ElapsedMilliseconds
        }
    } @{ command = "一键工作流"; profile = [string]$workflow.key } -NoHost)
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
    if (Skip-IfDryRun "解除关联") { return }
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
function Get-自动更新默认模式 {
    return "weekly"
}
function Get-自动更新默认时间 {
    return "20:00"
}
function Get-自动更新默认星期 {
    return "Friday"
}
function Get-自动更新星期别名映射 {
    return [ordered]@{
        "mon" = "Monday"; "monday" = "Monday"; "1" = "Monday"; "周一" = "Monday"; "星期一" = "Monday"
        "tue" = "Tuesday"; "tues" = "Tuesday"; "tuesday" = "Tuesday"; "2" = "Tuesday"; "周二" = "Tuesday"; "星期二" = "Tuesday"
        "wed" = "Wednesday"; "wednesday" = "Wednesday"; "3" = "Wednesday"; "周三" = "Wednesday"; "星期三" = "Wednesday"
        "thu" = "Thursday"; "thur" = "Thursday"; "thurs" = "Thursday"; "thursday" = "Thursday"; "4" = "Thursday"; "周四" = "Thursday"; "星期四" = "Thursday"
        "fri" = "Friday"; "friday" = "Friday"; "5" = "Friday"; "周五" = "Friday"; "星期五" = "Friday"
        "sat" = "Saturday"; "saturday" = "Saturday"; "6" = "Saturday"; "周六" = "Saturday"; "星期六" = "Saturday"
        "sun" = "Sunday"; "sunday" = "Sunday"; "7" = "Sunday"; "周日" = "Sunday"; "星期日" = "Sunday"; "周天" = "Sunday"; "星期天" = "Sunday"
    }
}
function Normalize-自动更新模式([string]$mode) {
    if ([string]::IsNullOrWhiteSpace($mode)) { return (Get-自动更新默认模式) }
    $v = $mode.Trim().ToLowerInvariant()
    if ($v -eq "daily" -or $v -eq "每天" -or $v -eq "每日") { return "daily" }
    if ($v -eq "weekly" -or $v -eq "每周") { return "weekly" }
    throw ("自动更新模式仅支持 daily 或 weekly：{0}" -f $mode)
}
function Normalize-自动更新时间([string]$at) {
    $value = if ([string]::IsNullOrWhiteSpace($at)) { Get-自动更新默认时间 } else { $at.Trim() }
    Need ($value -match "^\d{1,2}:\d{2}$") ("时间格式无效：{0}（请使用 HH:mm）" -f $value)
    $parts = $value.Split(":")
    $hour = [int]$parts[0]
    $minute = [int]$parts[1]
    Need ($hour -ge 0 -and $hour -le 23) ("小时无效：{0}（0-23）" -f $hour)
    Need ($minute -ge 0 -and $minute -le 59) ("分钟无效：{0}（0-59）" -f $minute)
    return ("{0:D2}:{1:D2}" -f $hour, $minute)
}
function Normalize-自动更新星期([string]$day) {
    $raw = if ([string]::IsNullOrWhiteSpace($day)) { Get-自动更新默认星期 } else { $day.Trim() }
    $key = $raw.ToLowerInvariant()
    $map = Get-自动更新星期别名映射
    if ($map.Contains($key)) { return [string]$map[$key] }
    $allowed = @("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
    foreach ($item in $allowed) {
        if ($item.Equals($raw, [System.StringComparison]::OrdinalIgnoreCase)) { return $item }
    }
    throw ("星期无效：{0}（可用 Monday..Sunday / 周一..周日）" -f $day)
}
function Format-自动更新计划说明([string]$mode, [string]$at, [string]$dayOfWeek) {
    if ($mode -eq "daily") {
        return ("每天 {0}" -f $at)
    }
    return ("每周 {0} {1}" -f $dayOfWeek, $at)
}
function Get-自动更新任务描述([string]$mode, [string]$at, [string]$dayOfWeek) {
    return ("skills-manager 自动执行 更新 + 同步 MCP | mode={0};at={1};day={2}" -f $mode, $at, $dayOfWeek)
}
function Parse-自动更新任务描述([string]$description) {
    $result = [ordered]@{
        found = $false
        mode = (Get-自动更新默认模式)
        at = (Get-自动更新默认时间)
        day = (Get-自动更新默认星期)
    }
    if ([string]::IsNullOrWhiteSpace($description)) { return [pscustomobject]$result }
    if ($description -notmatch "mode=([^;|]+)") { return [pscustomobject]$result }
    $result.mode = Normalize-自动更新模式 $Matches[1]
    if ($description -match "at=([^;|]+)") {
        $result.at = Normalize-自动更新时间 $Matches[1]
    }
    if ($description -match "day=([^;|]+)") {
        $result.day = Normalize-自动更新星期 $Matches[1]
    }
    $result.found = $true
    return [pscustomobject]$result
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
    $parsed = Parse-自动更新任务描述 ([string]$task.Description)
    $schedule = if ($parsed.found) { Format-自动更新计划说明 ([string]$parsed.mode) ([string]$parsed.at) ([string]$parsed.day) } else { "（旧任务：计划信息未记录）" }
    Write-Host ("自动更新：已启用（{0}，本机时间）" -f $schedule)
    Write-Host ("任务名：{0}" -f $taskName)
    Write-Host ("状态：{0}" -f $state)
    Write-Host ("下次运行：{0}" -f $nextRun)
    Write-Host ("上次运行：{0}" -f $lastRun)
}
function 启用自动更新([string]$Mode = "", [string]$At = "", [string]$DayOfWeek = "") {
    $taskName = Get-自动更新任务名
    $runnerPath = Get-自动更新脚本路径
    Need (Test-Path $runnerPath) ("缺少自动更新脚本：{0}" -f $runnerPath)
    Need (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue) "当前环境不支持 ScheduledTasks 模块。"
    Need (Get-Command New-ScheduledTaskAction -ErrorAction SilentlyContinue) "当前环境不支持 ScheduledTasks 模块。"
    $pwsh = Resolve-PowerShellExecutable

    $modeNormalized = Normalize-自动更新模式 $Mode
    $atNormalized = Normalize-自动更新时间 $At
    $dayNormalized = if ($modeNormalized -eq "weekly") { Normalize-自动更新星期 $DayOfWeek } else { Get-自动更新默认星期 }

    if (Skip-IfDryRun "启用自动更新计划任务") { return }

    $args = ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $runnerPath)
    $action = New-ScheduledTaskAction -Execute $pwsh -Argument $args -WorkingDirectory $Root
    $trigger = if ($modeNormalized -eq "daily") {
        New-ScheduledTaskTrigger -Daily -At $atNormalized
    }
    else {
        New-ScheduledTaskTrigger -Weekly -DaysOfWeek $dayNormalized -At $atNormalized
    }
    $principal = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $description = Get-自动更新任务描述 $modeNormalized $atNormalized $dayNormalized
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $description -Force | Out-Null
    Write-Host ("✅ 已启用自动更新：{0}（本机时间）。" -f (Format-自动更新计划说明 $modeNormalized $atNormalized $dayNormalized))
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
        Write-Host "目标：按计划自动执行【更新 + 同步 MCP】"
        查看自动更新状态
        Write-Host "1) 启用/更新计划（daily/weekly）"
        Write-Host "2) 禁用"
        Write-Host "3) 查看状态"
        Write-Host "0) 返回"
        $c = Read-MenuChoice "请选择（回车返回）"
        switch ($c) {
            "1" {
                $modeInput = Read-HostSafe ("计划模式（daily/weekly，默认 {0}）" -f (Get-自动更新默认模式))
                $atInput = Read-HostSafe ("执行时间（HH:mm，默认 {0}）" -f (Get-自动更新默认时间))
                $modeNormalized = Normalize-自动更新模式 $modeInput
                $dayInput = ""
                if ($modeNormalized -eq "weekly") {
                    $dayInput = Read-HostSafe ("每周几执行（Monday..Sunday 或 周一..周日，默认 {0}）" -f (Get-自动更新默认星期))
                }
                启用自动更新 -Mode $modeNormalized -At $atInput -DayOfWeek $dayInput
            }
            "2" { 禁用自动更新 }
            "3" { 查看自动更新状态 }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}

function MCP菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== MCP 服务 ==="
        Write-Host "1) 新增 MCP"
        Write-Host "2) 卸载 MCP"
        Write-Host "3) 同步配置"
        Write-Host "0) 返回"
        $c = Read-MenuChoice "请选择（回车返回）"
        switch ($c) {
            "1" { 安装MCP }
            "2" { 卸载MCP }
            "3" { 同步MCP }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}

function 技能库管理菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== 技能库管理 ==="
        Write-Host "1) 新增技能库"
        Write-Host "2) 删除技能库"
        Write-Host "3) 生成锁文件"
        Write-Host "4) 打开 skills.json"
        Write-Host "0) 返回"
        $c = Read-MenuChoice "请选择（回车返回）"
        switch ($c) {
            "1" { 新增技能库 }
            "2" { 删除技能库 }
            "3" { 锁定 }
            "4" { 打开配置 }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}

function 更多菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== 更多 ==="
        Write-Host "1) 一键工作流"
        Write-Host "2) 自动更新"
        Write-Host "3) 解除目标目录关联"
        Write-Host "4) 清理 .bak 备份"
        Write-Host "0) 返回"
        $c = Read-MenuChoice "请选择（回车返回）"
        switch ($c) {
            "1" { Invoke-Workflow @() }
            "2" { 自动更新设置 }
            "3" { 解除关联 }
            "4" { 清理备份 }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}

function 帮助 {
    @'
Skills 管理器（中文菜单）

常用流程：
  1) 接入来源：新增技能库，或用 add/npx 导入单个技能
  2) 安装技能：浏览技能 -> 选择安装/粘贴命令导入 -> 重建并同步
  3) 日常维护：更新上游 -> 重建并同步 -> doctor --strict
  4) 目标仓审查：查看需求 -> 生成审查包 -> 预检建议 -> 应用建议

菜单地图：
  - 主菜单：浏览技能、选择安装、粘贴命令导入、卸载技能、重建并同步、更新上游
  - 目标仓审查：需求、目标仓、审查包、预检、应用、状态
  - MCP 服务：新增 MCP、卸载 MCP、同步配置
  - 技能库管理：新增/删除技能库、生成锁文件、打开 skills.json
  - 更多：一键工作流、自动更新、解除目标目录关联、清理 .bak 备份

主要功能说明：
  - 浏览技能：只列出当前来源中的可用技能，不改配置
  - 选择安装：勾选技能并写入 `mappings`
  - 粘贴命令导入：解析 `add` / `npx` 命令，导入后自动重建
  - 卸载技能：从 `mappings` 移除，必要时清理导入目录和备份
  - 重建并同步：根据 `skills.json` 重建 `agent/` 并同步到 `targets`
  - 更新上游：拉取 `vendor/`、`imports/` 后重建并同步
  - 目标仓审查：生成审查包，先 dry-run，再按确认口令落盘
  - MCP 服务：维护 `skills.json` 中的 `mcp_servers` 并同步到目标 CLI
  - 技能库管理：维护来源、锁文件和配置
  - 一键工作流：按场景执行组合流程；支持 `--list`、`--no-prompt`、`--continue-on-error`

易混点：
  - 只想让本地配置重新输出：用“重建并同步”（CLI：`构建生效`）
  - 想拉取上游新内容：用“更新上游”（CLI：`更新`）
  - 已知道安装命令：用“粘贴命令导入”；想先浏览再挑选：用“选择安装”
  - `add`/`npx` 未指定 `--skill` 时只新增技能库，不会安装整库技能
  - `应用` 默认只 dry-run；只有 `--apply --yes` 才真正写入

常用命令：
  .\skills.ps1 发现
  .\skills.ps1 安装
  .\skills.ps1 命令导入安装
  .\skills.ps1 卸载
  .\skills.ps1 新增技能库
  .\skills.ps1 add <repo> [--skill <name>] [--ref <branch/tag>] [--mode manual|vendor] [--sparse]
  .\skills.ps1 npx "skills add <repo> [--skill <name>] [--ref <branch/tag>] [--mode manual|vendor] [--sparse]"
  .\skills.ps1 构建生效
  .\skills.ps1 更新 -Plan
  .\skills.ps1 更新 -Upgrade
  .\skills.ps1 锁定
  .\skills.ps1 清理无效映射 [--yes] [--no-build]

一键工作流：
  .\skills.ps1 一键 --list
  .\skills.ps1 一键 新手
  .\skills.ps1 一键 维护 --continue-on-error
  .\skills.ps1 一键 审查 --no-prompt
  .\skills.ps1 workflow all --no-prompt

MCP：
  .\skills.ps1 安装MCP <name> -- <command> [args...]          （推荐）
  .\skills.ps1 安装MCP <name> --cmd <command> [--arg <arg>...] （兼容）
  .\skills.ps1 安装MCP <name> --transport http --url <url> [--bearer-token-env-var <ENV>] 
  .\skills.ps1 卸载MCP <name>
  .\skills.ps1 同步MCP

目标仓审查：
  .\skills.ps1 审查目标 需求设置
  .\skills.ps1 审查目标 需求查看
  .\skills.ps1 审查目标 需求结构化 --profile <file>
  .\skills.ps1 审查目标 列表
  .\skills.ps1 审查目标 添加 <name> <path>
  .\skills.ps1 审查目标 修改 <name> <path>
  .\skills.ps1 审查目标 删除 <name>
  .\skills.ps1 审查目标 扫描 [--target <name>] [--out <dir>] [--force]
  .\skills.ps1 审查目标 发现新技能 [--query <text>] [--out <dir>] [--force]
  .\skills.ps1 审查目标 预检 --run-id <run-id>
  .\skills.ps1 审查目标 预检 --recommendations <file>
  .\skills.ps1 审查目标 应用确认 --recommendations <file> [--allow-stale-snapshot] [--stale-ack "<token>"]
  .\skills.ps1 审查目标 应用 --recommendations <file> [--dry-run-ack "我知道未落盘"] [--allow-stale-snapshot] [--stale-ack "<token>"]
  .\skills.ps1 审查目标 应用 --recommendations <file> --apply --yes [--add-indexes "1,3"] [--remove-indexes "2"] [--mcp-add-indexes "1"] [--mcp-remove-indexes "2"] [--allow-stale-snapshot] [--stale-ack "<token>"]
  .\skills.ps1 审查目标 状态

维护：
  .\skills.ps1 解除关联
  .\skills.ps1 清理备份
  .\skills.ps1 自动更新设置
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
  - sync_mode：Windows 优先 link（junction），受限环境用 sync

MCP/门禁环境变量：
  - SKILLS_MCP_VERIFY_GEMINI_CLI=1|true|yes|on：启用 Gemini CLI 实机校验（默认关闭）
  - SKILLS_MCP_VERIFY_LIST_TIMEOUT_SECONDS：统一设置 mcp list 校验超时（秒）
  - SKILLS_MCP_VERIFY_LIST_TIMEOUT_SECONDS_<CLI>：按 CLI 覆盖校验超时（秒）
  - SKILLS_MCP_NATIVE_TIMEOUT_SECONDS：原生 claude mcp add/remove 超时（秒）
  - SKILLS_MCP_VERIFY_ATTEMPTS / SKILLS_MCP_VERIFY_INTERVAL_SECONDS：跨 CLI 校验重试次数/间隔（秒）
  - SKILLS_SYNC_MCP_THRESHOLD_MS：doctor JSON 门禁里 sync_mcp 的阈值（毫秒）

过滤语法（批量安装/卸载/发现命令）：
  - 多关键词：空格分隔，AND 过滤（如：docx pdf）
  - 正则：用 /.../ 包裹（如：/docx|pdf/）

本地技能：
  - add/npx 显式指定 --skill 时默认落入 imports（mode=manual），可用 --mode vendor 改为 vendor 管理。
  - manual/ 仅用于旧数据兼容；自定义改动请放入 overrides/。
  - “命令导入安装”支持多行输入 add / npx skills add / npx add-skill。
  - `安装` / `卸载` / `更新` / `构建生效` / `锁定` 等旧命令仍可使用。

目标仓审查：
  - 用户基本需求是全局长期上下文；目标仓是项目级上下文。外层 AI 必须同时基于两者判断技能保留、卸载与新增。
  - `发现新技能` 是不绑定目标仓的 profile-only 模式，复用同一套审查包、提示词、recommendations.json、dry-run/apply 流程。
  - 启动审查流程后，外层 AI 可以在本次流程内自主联网研究；联网不等于自动安装。
  - 设置用户基本需求后会自动进入结构化导入流程；回车使用默认路径 `reports\skill-audit\user-profile.structured.json`，不存在时会自动生成草稿文件。
  - 已内置“外层 AI 审查提示词”；生成审查包时会输出运行态 `outer-ai-prompt.md`，优先把它交给外层 AI，而不是只交 `ai-brief.md`。
  - 运行态 `ai-brief.md` / `outer-ai-prompt.md` 属于审查包产物；如需改默认提示词，请改 `src/Commands/AuditTargets.ps1` 或 `overrides/audit-outer-ai-prompt.md`，不要直接手改 run 目录产物。
  - 外层 AI 应先写完并自检 `recommendations.json`（schema、占位符、双理由、真实来源），再进入 dry-run。
  - `应用确认` 是单入口两阶段流程：先 dry-run，再要求输入确认口令 `APPLY <run-id>` 才执行落盘。
  - `应用` 默认只做 dry-run，且需显式确认口令 `我知道未落盘`；只有 `--apply --yes` 才会真正执行选中的新增/卸载。
  - 建议先执行 `预检`：会提前检查 `stale_snapshot` 与提示词契约版本，避免“先研究后阻断”。
  - `应用`/`应用确认` 会校验同目录 `installed-skills.json` 快照与当前 live mappings 指纹；若快照过期（stale_snapshot）会阻断并要求先重新 `审查目标 扫描`。
  - 仅在你明确接受风险时可加 `--allow-stale-snapshot` 跳过该阻断（报告会标记 stale 风险）。
  - 使用 `--allow-stale-snapshot` 时会触发红色警告并要求二次确认口令；非交互环境请用 `--stale-ack "<token>"` 提前传入。
  - `--out` 若指向已存在且非空目录，默认阻断，防止覆盖旧审查包；如确需复用，显式追加 `--force`。
  - `--run-id` / `--recommendations` 里出现 `<run-id>` 时会自动解析为最近可用 run；若无可用 run 才阻断并给出提示。
  - `状态` 可查看最近一次 `apply-report.json` 的 `mode/success/persisted/changed_counts`。
  - 执行前会分别列出“技能新增/卸载”和“MCP 新增/卸载”四份带序号清单；dry-run 后向用户汇报时必须沿用原序号，并同时展示用户需求 / 目标仓两条简短依据。
  - `--add-indexes` / `--remove-indexes` 作用于技能清单；`--mcp-add-indexes` / `--mcp-remove-indexes` 作用于 MCP 清单；四份清单独立编号。

提示：如遇 PowerShell 脚本执行被拦，可在当前窗口临时放开：
  Set-ExecutionPolicy -Scope Process Bypass
'@ | Write-Host
}

function Resolve-AuditMenuRecommendationsPath([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) {
        return 'reports\skill-audit\<run-id>\recommendations.json'
    }
    return $path
}

function 目标仓管理菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== 目标仓管理 ==="
        Write-Host "1) 查看目标仓列表"
        Write-Host "2) 新增目标仓"
        Write-Host "3) 修改目标仓"
        Write-Host "4) 删除目标仓"
        Write-Host "0) 返回"
        $c = Read-MenuChoice "请选择（回车返回）"
        switch ($c) {
            "1" { Invoke-AuditTargetsCommand @("list") }
            "2" {
                $name = Read-HostSafe "目标仓名称"
                $path = Read-HostSafe "目标仓路径"
                if (-not [string]::IsNullOrWhiteSpace($name) -and -not [string]::IsNullOrWhiteSpace($path)) {
                    Invoke-AuditTargetsCommand @("add", $name, $path)
                }
            }
            "3" {
                $cfg = Load-AuditTargetsConfig
                $targets = @($cfg.targets)
                if ($targets.Count -eq 0) {
                    Write-Host "未登记目标仓。"
                    continue
                }
                $selection = Select-Items $targets `
                { param($idx, $item)
                    $enabled = if ($item.PSObject.Properties.Match("enabled").Count -gt 0) { [bool]$item.enabled } else { $true }
                    $enabledText = if ($enabled) { "enabled" } else { "disabled" }
                    return ("{0,3}) [{1}] {2} -> {3}" -f $idx, $enabledText, [string]$item.name, [string]$item.path)
                } `
                    "请选择要修改的目标仓（输入 0 取消）" `
                    "未解析到有效序号，已取消修改。"
                if ($selection.canceled -or @($selection.items).Count -eq 0) {
                    Write-Host "已取消修改目标仓。"
                    continue
                }
                $name = [string]$selection.items[0].name
                $path = Read-HostSafe "新的目标仓路径"
                if (-not [string]::IsNullOrWhiteSpace($name) -and -not [string]::IsNullOrWhiteSpace($path)) {
                    Invoke-AuditTargetsCommand @("update", $name, $path)
                }
            }
            "4" {
                $cfg = Load-AuditTargetsConfig
                $targets = @($cfg.targets)
                if ($targets.Count -eq 0) {
                    Write-Host "未登记目标仓。"
                    continue
                }
                $selection = Select-Items $targets `
                { param($idx, $item)
                    $enabled = if ($item.PSObject.Properties.Match("enabled").Count -gt 0) { [bool]$item.enabled } else { $true }
                    $enabledText = if ($enabled) { "enabled" } else { "disabled" }
                    return ("{0,3}) [{1}] {2} -> {3}" -f $idx, $enabledText, [string]$item.name, [string]$item.path)
                } `
                    "请选择要删除的目标仓（输入 0 取消）" `
                    "未解析到有效序号，已取消删除。"
                if ($selection.canceled -or @($selection.items).Count -eq 0) {
                    Write-Host "已取消删除目标仓。"
                    continue
                }
                $picked = $selection.items[0]
                $preview = @(
                    ("name: {0}" -f [string]$picked.name),
                    ("path: {0}" -f [string]$picked.path)
                ) -join "`n"
                if (-not (Confirm-WithSummary "将删除以下目标仓" $preview "确认删除该目标仓？" "Y")) {
                    Write-Host "已取消删除目标仓。"
                    continue
                }
                $name = [string]$picked.name
                if (-not [string]::IsNullOrWhiteSpace($name)) {
                    Invoke-AuditTargetsCommand @("remove", $name)
                }
            }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}

function 审查高级菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== 审查高级设置 ==="
        Write-Host "1) 导入结构化需求"
        Write-Host "2) 初始化审查配置"
        Write-Host "3) 查看 AI 提示词"
        Write-Host "4) 编辑 AI 提示词"
        Write-Host "5) 直接执行建议（高级）"
        Write-Host "0) 返回"
        $c = Read-MenuChoice "请选择（回车返回）"
        switch ($c) {
            "1" {
                $defaultPath = Get-AuditStructuredProfileDefaultPath
                $profile = Read-HostSafe ("请输入结构化 profile 文件路径（回车使用默认：{0}）" -f $defaultPath)
                if ([string]::IsNullOrWhiteSpace($profile)) {
                    Invoke-AuditTargetsCommand @("profile-structure")
                }
                else {
                    Invoke-AuditTargetsCommand @("profile-structure", "--profile", $profile)
                }
            }
            "2" { Invoke-AuditTargetsCommand @("init") }
            "3" { Show-AuditOuterAiPromptTemplate }
            "4" { Edit-AuditOuterAiPromptTemplate }
            "5" {
                $path = Resolve-AuditMenuRecommendationsPath (Read-HostSafe "recommendations 文件路径（回车=最近 run）")
                Invoke-AuditTargetsCommand @("apply", "--recommendations", $path, "--apply", "--yes")
            }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}

function 审查目标菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== 目标仓审查 ==="
        Write-Host "流程：需求 -> 审查包 -> 预检 -> 应用"
        Write-Host "1) 查看需求"
        Write-Host "2) 编辑需求"
        Write-Host "3) 目标仓列表"
        Write-Host "4) 生成审查包"
        Write-Host "5) 预检建议"
        Write-Host "6) 应用建议（先 dry-run）"
        Write-Host "7) 查看最近状态"
        Write-Host "8) 发现新技能"
        Write-Host "9) 目标仓管理"
        Write-Host "10) 高级设置"
        Write-Host "0) 返回"
        $c = Read-MenuChoice "请选择（回车返回）"
        switch ($c) {
            "1" { Invoke-AuditTargetsCommand @("profile-show") }
            "2" { Invoke-AuditTargetsCommand @("profile-set") }
            "3" { Invoke-AuditTargetsCommand @("list") }
            "4" {
                $cfg = Load-AuditTargetsConfig
                $targets = @($cfg.targets)
                if ($targets.Count -eq 0) {
                    Write-Host "未登记目标仓。"
                    continue
                }
                Write-Host "留空将扫描全部 enabled 目标仓。"
                $selection = Select-Items $targets `
                { param($idx, $item)
                    $enabled = if ($item.PSObject.Properties.Match("enabled").Count -gt 0) { [bool]$item.enabled } else { $true }
                    $enabledText = if ($enabled) { "enabled" } else { "disabled" }
                    return ("{0,3}) [{1}] {2} -> {3}" -f $idx, $enabledText, [string]$item.name, [string]$item.path)
                } `
                    "请选择要扫描的目标仓（输入 0 或直接回车=全部 enabled）" `
                    "未解析到有效序号，已取消生成审查包。"
                if ($selection.canceled) {
                    Invoke-AuditTargetsCommand @("scan")
                    continue
                }
                $picked = @($selection.items)
                if ($picked.Count -eq 0) {
                    Invoke-AuditTargetsCommand @("scan")
                }
                else {
                    Invoke-AuditTargetsCommand @("scan", "--target", [string]$picked[0].name)
                }
            }
            "5" {
                $path = Resolve-AuditMenuRecommendationsPath (Read-HostSafe "recommendations 文件路径（回车=最近 run）")
                Invoke-AuditTargetsCommand @("preflight", "--recommendations", $path)
            }
            "6" {
                $path = Resolve-AuditMenuRecommendationsPath (Read-HostSafe "recommendations 文件路径（回车=最近 run）")
                Invoke-AuditTargetsCommand @("apply-flow", "--recommendations", $path)
            }
            "7" { Invoke-AuditTargetsCommand @("status") }
            "8" {
                $query = Read-HostSafe "发现查询（可留空）"
                if ([string]::IsNullOrWhiteSpace($query)) {
                    Invoke-AuditTargetsCommand @("discover-skills")
                }
                else {
                    Invoke-AuditTargetsCommand @("discover-skills", "--query", $query)
                }
            }
            "9" { 目标仓管理菜单 }
            "10" { 审查高级菜单 }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}

function 菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== Skills 管理器 ==="
        Write-Host "1) 浏览技能"
        Write-Host "2) 选择安装"
        Write-Host "3) 粘贴命令导入"
        Write-Host "4) 卸载技能"
        Write-Host "5) 重建并同步"
        Write-Host "6) 更新上游"
        Write-Host "7) 目标仓审查"
        Write-Host "8) MCP 服务"
        Write-Host "9) 技能库管理"
        Write-Host "10) 更多"
        Write-Host "98) 帮助"
        Write-Host "0) 退出"
        $c = Read-MenuChoice "请选择（回车退出）"
        switch ($c) {
            "1" { 发现 }
            "2" { 安装 }
            "3" { 命令导入安装 }
            "4" { 卸载 }
            "5" { 构建生效 }
            "6" { 更新 }
            "7" { 审查目标菜单 }
            "8" { MCP菜单 }
            "9" { 技能库管理菜单 }
            "10" { 更多菜单 }
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
            "清理无效映射" { 清理无效映射 (Merge-FilterAndArgs $Filter $args) }
            "prune-invalid-mappings" { 清理无效映射 (Merge-FilterAndArgs $Filter $args) }
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
            "审查目标" { Invoke-AuditTargetsCommand (Merge-FilterAndArgs $Filter $args) }
            "audit-targets" { Invoke-AuditTargetsCommand (Merge-FilterAndArgs $Filter $args) }
            "一键" { Invoke-Workflow (Merge-FilterAndArgs $Filter $args) }
            "workflow" { Invoke-Workflow (Merge-FilterAndArgs $Filter $args) }
            "打开配置" { 打开配置 }
            "解除关联" { 解除关联 }
            "清理备份" { 清理备份 }
            "自动更新设置" { 自动更新设置 }
            "帮助" { 帮助 }
            "help" { 帮助 }
            "--help" { 帮助 }
            "-h" { 帮助 }
            "doctor" {
                $doctorTokens = @()
                if (-not [string]::IsNullOrWhiteSpace($Filter)) { $doctorTokens += $Filter }
                $doctorTokens += @($args)
                $doctorResult = Invoke-Doctor $doctorTokens
                $strictRequested = @($doctorTokens | Where-Object { ([string]$_).Trim().ToLowerInvariant() -eq "--strict" }).Count -gt 0
                if ($strictRequested -and $doctorResult -and $doctorResult.PSObject.Properties.Match("pass").Count -gt 0 -and -not [bool]$doctorResult.pass) {
                    exit 2
                }
            }
        }
    }
    catch {
        $msg = $_.Exception.Message
        if ($env:SKILLS_DEBUG_STACK -eq "1") {
            $stack = $_.ScriptStackTrace
            if (-not [string]::IsNullOrWhiteSpace($stack)) {
                Write-Host ("[DEBUG_STACK] " + $stack) -ForegroundColor DarkYellow
            }
        }
        Log ("未处理错误：{0}" -f $msg) "ERROR"
        Write-Host ("❌ 发生错误：{0}" -f $msg) -ForegroundColor Red
        exit 1
    }
}

