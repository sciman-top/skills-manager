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
