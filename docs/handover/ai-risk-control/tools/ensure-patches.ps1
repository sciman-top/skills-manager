# ensure-patches.ps1 —— Antigravity 更新后自动恢复「代理补丁 + 汉化补丁」
#
# 背景：Antigravity 每次自动更新都会换掉安装目录（连目录名大小写都会变），
#       `version.dll` / `config.json` / 被汉化过的 `app.asar` 全部被清掉。
#       本脚本做幂等自愈：缺什么补什么，都在就不动。
#
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File D:\TOOL\antigravity-ensure\ensure-patches.ps1
#   可选参数：
#     -Force   即使 Antigravity 正在运行，也关掉它并强制完成汉化补丁
#     -Quiet   不输出到控制台（仍写日志）
#
# 退出码：0 = 全部就绪；1 = 有项目未完成（通常因为 Antigravity 在运行）

param(
    [switch]$Force,
    [switch]$Quiet
)

$ErrorActionPreference = 'Continue'

# ============ 可按需修改的常量 ============
$TOOL_CN    = 'D:\TOOL\antigravity-cn'                        # 汉化工具目录
$TOOL_PROXY = 'D:\TOOL\antigravity-proxy\v2.4-x64'            # 代理主副本目录
$LOG_DIR    = 'D:\TOOL\antigravity-ensure'
$MARKER     = 'Antigravity 2.0 Chinese Localization Engine'   # 汉化注入标记
# ==========================================

$LOG = Join-Path $LOG_DIR 'ensure.log'
if (-not (Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Force -Path $LOG_DIR | Out-Null }

function Write-Log {
    param([string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $LOG -Value $line -Encoding UTF8
    if (-not $Quiet) { Write-Host $line }
}

function Get-NodeExe {
    $candidates = @(
        'C:\Program Files\nodejs\node.exe',
        (Join-Path $env:LOCALAPPDATA 'Programs\nodejs\node.exe')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    $cmd = Get-Command node -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-AntigravityDir {
    # 大小写不敏感定位；目录名随版本变化（Antigravity / antigravity）
    $base = Join-Path $env:LOCALAPPDATA 'Programs'
    foreach ($d in Get-ChildItem -Path $base -Directory -ErrorAction SilentlyContinue) {
        if ($d.Name -ieq 'antigravity' -and (Test-Path (Join-Path $d.FullName 'Antigravity.exe'))) {
            return $d.FullName
        }
    }
    return $null
}

function Test-AsarLocalized {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $latin1 = [System.Text.Encoding]::GetEncoding(28591)
    return $latin1.GetString($bytes).Contains($MARKER)
}

function Get-Sha256Short {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '' }
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.Substring(0, 16)
}

function Get-ConfigFingerprint {
    # 只比对「有效配置项」。不比对整文件哈希，因为：
    #   - DLL 运行时会周期性重写 config.json（换行符、格式、diagnostics 都会被改）
    #   - diagnostics.agent_ip_probe 在 v2.4 上无法持久，不参与比对
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 'MISSING' }
    try {
        $c = Get-Content -Raw -Encoding UTF8 $Path | ConvertFrom-Json
        $parts = @(
            "$($c.proxy.host):$($c.proxy.port)/$($c.proxy.type)",
            "child_injection=$($c.child_injection)/$($c.child_injection_mode)",
            "fake_ip=$($c.fake_ip.enabled)/$($c.fake_ip.cidr)",
            "ports=$($c.proxy_rules.allowed_ports -join ',')",
            "dns=$($c.proxy_rules.dns_mode) ipv6=$($c.proxy_rules.ipv6_mode)",
            "udp=$($c.proxy_rules.udp_mode)/$($c.proxy_rules.udp_fallback)",
            "targets=$($c.target_processes -join ',')",
            "log=$($c.log_level) traffic=$($c.traffic_logging)"
        )
        return ($parts -join ' | ')
    } catch {
        return "PARSE_ERROR"
    }
}

$pending = 0

Write-Log '========== ensure-patches 开始 =========='

# ---------- 1. 定位安装目录 ----------
$agDir = Get-AntigravityDir
if (-not $agDir) {
    Write-Log '错误：找不到 Antigravity 安装目录（%LOCALAPPDATA%\Programs\*ntigravity\Antigravity.exe）'
    exit 1
}
Write-Log "安装目录 : $agDir"

$resDir = Join-Path $agDir 'resources'
if (-not (Test-Path $resDir)) { $resDir = Join-Path $agDir 'Resources' }

$procs = @(Get-Process -Name Antigravity, language_server -ErrorAction SilentlyContinue)
$running = $procs.Count -gt 0
Write-Log ("Antigravity 运行中: {0}" -f $running)

# ---------- 2. 代理补丁 ----------
$dllDst = Join-Path $agDir 'version.dll'
$cfgDst = Join-Path $agDir 'config.json'
$dllSrc = Join-Path $TOOL_PROXY 'version.dll'
$cfgSrc = Join-Path $TOOL_PROXY 'config.json'

# version.dll 是二进制，必须逐字节一致。
# 覆盖策略：缺失必补；已存在且哈希一致则不动；已存在但哈希不一致时，
#          只有在 Antigravity 未运行时才替换（不写正在被加载的 DLL）。
if (-not (Test-Path $dllSrc)) {
    Write-Log "警告：主副本缺失 $dllSrc"; $pending = 1
} elseif (-not (Test-Path $dllDst)) {
    try {
        Copy-Item $dllSrc $dllDst -Force -ErrorAction Stop
        Write-Log '代理补丁 已部署: version.dll（原本缺失）'
    } catch {
        Write-Log "代理补丁 失败  : version.dll —— $($_.Exception.Message)"
        $pending = 1
    }
} elseif ((Get-Sha256Short $dllSrc) -eq (Get-Sha256Short $dllDst)) {
    Write-Log '代理补丁 OK  : version.dll 已是最新'
} elseif ($running) {
    Write-Log '代理补丁 待处理: version.dll 与主副本不一致，但 Antigravity 运行中，不覆盖已加载的 DLL；关闭后下次自动修正'
    $pending = 1
} else {
    try {
        Copy-Item $dllSrc $dllDst -Force -ErrorAction Stop
        Write-Log '代理补丁 已修正: version.dll（哈希不一致，已按主副本覆盖）'
    } catch {
        Write-Log "代理补丁 失败  : version.dll —— $($_.Exception.Message)"
        $pending = 1
    }
}

# config.json 会被 DLL 运行时改写，用「有效配置项」比对，避免无意义重写
if (-not (Test-Path $cfgSrc)) {
    Write-Log "警告：主副本缺失 $cfgSrc"; $pending = 1
} else {
    $fpSrc = Get-ConfigFingerprint $cfgSrc
    $fpDst = Get-ConfigFingerprint $cfgDst
    if ($fpSrc -eq $fpDst) {
        Write-Log '代理补丁 OK  : config.json 有效项一致'
    } elseif ($fpDst -eq 'MISSING' -or $fpDst -eq 'PARSE_ERROR') {
        try {
            Copy-Item $cfgSrc $cfgDst -Force -ErrorAction Stop
            Write-Log '代理补丁 已部署: config.json（缺失或不可解析）'
        } catch {
            Write-Log "代理补丁 失败  : config.json —— $($_.Exception.Message)"
            $pending = 1
        }
    } else {
        # 有效项确实不同：保留 DLL 已写入的 diagnostics，只覆盖其余字段
        try {
            $srcObj = Get-Content -Raw -Encoding UTF8 $cfgSrc | ConvertFrom-Json
            $dstObj = Get-Content -Raw -Encoding UTF8 $cfgDst | ConvertFrom-Json
            $srcObj.diagnostics = $dstObj.diagnostics
            $json = $srcObj | ConvertTo-Json -Depth 20
            [System.IO.File]::WriteAllText($cfgDst, $json, (New-Object System.Text.UTF8Encoding($false)))
            Write-Log '代理补丁 已修正: config.json 有效项与主副本不一致，已按主副本覆盖（保留 DLL 写入的 diagnostics）'
        } catch {
            Write-Log "代理补丁 失败  : config.json —— $($_.Exception.Message)"
            $pending = 1
        }
    }
}

# ---------- 3. 汉化补丁 ----------
$asar = Join-Path $resDir 'app.asar'
if (-not (Test-Path $asar)) {
    Write-Log "错误：找不到 $asar"
    exit 1
}

if (Test-AsarLocalized $asar) {
    Write-Log '汉化补丁 OK  : app.asar 已包含注入标记'
} else {
    Write-Log '汉化补丁 缺失: app.asar 不含注入标记'

    if ($running -and -not $Force) {
        Write-Log '跳过汉化：Antigravity 正在运行。关闭它后本脚本会自动补打（或加 -Force 强制）。'
        $pending = 1
    } else {
        if ($running -and $Force) {
            Write-Log '按 -Force 关闭 Antigravity ...'
            $procs | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
        }
        $node = Get-NodeExe
        if (-not $node) {
            Write-Log '错误：找不到 node.exe，无法执行汉化。请安装 Node.js。'
            $pending = 1
        } else {
            $localize = Join-Path $TOOL_CN 'localize.js'
            if (-not (Test-Path $localize)) {
                Write-Log "错误：找不到汉化工具 $localize"
                $pending = 1
            } else {
                Write-Log "执行汉化: $node $localize --now"
                $nodeDir = Split-Path $node -Parent
                $env:PATH = "$nodeDir;$env:PATH"
                # node 输出是 UTF-8，中文 Windows 的控制台默认是 GBK，不设会乱码
                $prevEnc = $null
                try { $prevEnc = [Console]::OutputEncoding; [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
                Push-Location $TOOL_CN
                try {
                    & $node $localize '--now' 2>&1 | ForEach-Object { Write-Log "  $_" }
                } finally {
                    Pop-Location
                    if ($prevEnc) { try { [Console]::OutputEncoding = $prevEnc } catch { } }
                }
                if (Test-AsarLocalized $asar) {
                    Write-Log '汉化补丁 已恢复 ✓'
                } else {
                    Write-Log '汉化补丁 仍然缺失 ✗ —— 请手动运行 node localize.js --now 查看报错'
                    $pending = 1
                }
            }
        }
    }
}

# ---------- 4. ag-split 分流器（Google 出口自愈） ----------
# 背景：本机开了「快速启动」(HiberbootEnabled=1)，关机走混合休眠恢复，
#       Startup 文件夹里的 ag-split.lnk 不会被执行 → 分流器不启动，
#       系统代理可能被改回 10808 → Google/Antigravity 流量走被标记的出口 IP。
#       这里把分流器自愈挂进每 30 分钟的自愈循环。
$splitScript = 'D:\TOOL\v2rayN\ag-split\ensure-split.ps1'
$pwshExe     = 'C:\Program Files\PowerShell\7\pwsh.exe'
if ((Test-Path $splitScript) -and (Test-Path $pwshExe)) {
    Write-Log '分流器自愈：调用 ensure-split.ps1'
    try {
        $splitOut = & $pwshExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $splitScript -Quiet 2>&1
        foreach ($l in $splitOut) { Write-Log "  $l" }
        if ($LASTEXITCODE -ne 0) { $pending = 1 }
    } catch {
        Write-Log "分流器自愈 失败: $($_.Exception.Message)"
        $pending = 1
    }
} else {
    Write-Log "跳过分流器自愈：未找到 $splitScript"
}

# ---------- 5. 汇总 ----------
if ($pending -eq 0) {
    Write-Log '结果：全部就绪'
} else {
    Write-Log '结果：有项目未完成'
}
Write-Log '========== ensure-patches 结束 =========='

exit $pending
