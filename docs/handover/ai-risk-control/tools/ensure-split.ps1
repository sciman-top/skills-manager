# ensure-split.ps1 —— ag-split 分流器「幂等自愈」
#
# 解决什么问题：
#   本机开了「快速启动」(HiberbootEnabled=1)，关机会走混合休眠恢复，
#   **Startup 文件夹里的 ag-split.lnk 不会被执行** → 分流器不启动；
#   同时系统代理可能被其它软件改回 10808 → Google 流量走被标记的出口 IP。
#
# 本脚本做什么（全部幂等，缺什么补什么）：
#   1) 分流器（默认 127.0.0.1:10810）没监听 → 拉起它
#   2) 系统代理不是 127.0.0.1:10810 → 改回来（例外表不动）
#      【安全阀】系统代理指着分流器、但分流器起不来 → 回退到常驻前端，避免整机断网
#   3) 用户级 HTTP_PROXY/HTTPS_PROXY/ALL_PROXY 不是 10810 → 改回来
#   4) Startup 快捷方式 ag-split.lnk 缺失 → 补建
#   5) 只读验证：默认出口与 Google DNS 可达性
#
# 用法：
#   pwsh -NoProfile -ExecutionPolicy Bypass -File D:\TOOL\v2rayN\ag-split\ensure-split.ps1 [-Quiet]
# 退出码：0 = 全部就绪；1 = 有项目未完成
#
# ── 可注入参数（受控验收用）──────────────────────────────────
#   全部路径/端口/注册表键/环境变量作用域都可覆盖，便于在夹具下运行
#   而不触碰真实系统状态。不传则用默认值，行为与改造前一致。

param(
    [switch]$Quiet,

    # 分流器
    [string]$XrayPath      = 'D:\TOOL\v2rayN\ag-split\ag-split-core.exe',
    [string]$ConfigPath    = 'D:\TOOL\v2rayN\ag-split\config.json',
    [string]$WorkDir       = 'D:\TOOL\v2rayN',
    [int]   $Port          = 10810,
    [string]$TaskName      = 'AgSplitEgress',
    [string]$FallbackProxy = '127.0.0.1:10808',   # 回退目标：常驻前端（v2rayN）

    # 状态文件
    [string]$LogPath       = 'D:\TOOL\v2rayN\ag-split\ensure-split.log',
    [string]$BackupPath    = 'D:\TOOL\v2rayN\ag-split\proxy-backup.json',

    # 系统代理注册表键（测试时可指向临时键）
    [string]$ProxyRegPath  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
    # 环境变量作用域：User（默认，持久） / Process（测试用，进程结束即消失）
    [string]$EnvScope      = 'User',
    # Startup 目录（测试时可指向临时目录）
    [string]$StartupDir    = '',

    # 开关（受控验收用）
    [switch]$NoStart,          # 不尝试拉起分流器（覆盖启动分支）
    [switch]$NoEnvWrite,       # 完全不写环境变量
    [switch]$NoStartupLnk,     # 不动 Startup 快捷方式
    [switch]$NoEgressProbe     # 不做出口探测（离线）
)

$ErrorActionPreference = 'Continue'

# 系统代理例外表里必须包含的域名（缺了会导致对应流量走代理）
$REQUIRED_EXCEPTIONS = @(
    '*.workbuddy.ai', '*.codebuddy.ai', '*.lkeap.cloud.tencent.com',
    '*.workbuddy.cn', '*.codebuddy.cn'
)

if ([string]::IsNullOrWhiteSpace($StartupDir)) {
    try { $StartupDir = [Environment]::GetFolderPath('Startup') } catch { $StartupDir = '' }
}

$pending = 0

function Write-Log {
    param([string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -Path $LogPath -Value $line -Encoding UTF8 } catch { }
    if (-not $Quiet) { Write-Host $line }
}

function Test-TcpPort {
    param([int]$Port)
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect('127.0.0.1', $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(1200)) { $c.Close(); return $false }
        $c.EndConnect($iar); $c.Close(); return $true
    } catch { return $false }
}

function Test-SplitListener {
    param([int]$ListenPort, [string]$ExpectedPath)
    try {
        $connections = @(Get-NetTCPConnection -LocalPort $ListenPort -State Listen -ErrorAction Stop)
        $ownerIds = @($connections.OwningProcess | Sort-Object -Unique)
        if ($ownerIds.Count -ne 1 -or @($connections | Where-Object { $_.LocalAddress -ne '127.0.0.1' }).Count -gt 0) {
            return $false
        }
        $owner = Get-CimInstance Win32_Process -Filter "ProcessId=$($ownerIds[0])" -ErrorAction Stop
        return ($owner.ExecutablePath -and [IO.Path]::GetFullPath($owner.ExecutablePath) -ieq [IO.Path]::GetFullPath($ExpectedPath))
    } catch { return $false }
}

function Test-SplitTaskAction {
    param([object[]]$Actions, [string]$ExpectedPath, [string]$ExpectedConfig)
    if ($Actions.Count -ne 1) { return $false }
    try {
        return (
            [IO.Path]::GetFullPath($Actions[0].Execute) -ieq [IO.Path]::GetFullPath($ExpectedPath) -and
            $Actions[0].Arguments.Trim() -ieq ('run -c "{0}"' -f $ExpectedConfig)
        )
    } catch { return $false }
}

Write-Log '========== ensure-split 开始 =========='

# ---------- 0. 前置：文件存在性 ----------
foreach ($p in @($XrayPath, $ConfigPath)) {
    if (-not (Test-Path $p)) { Write-Log "错误：缺少 $p"; exit 1 }
}

# ---------- 1. 分流器是否在监听 ----------
$listening = Test-TcpPort $Port
Write-Log ("分流器 {0} 监听中: {1}" -f $Port, $listening)

$t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($t -and (-not (Test-SplitTaskAction @($t.Actions) $XrayPath $ConfigPath) -or $t.State -eq 'Disabled')) {
    Write-Log 'wrong_task_action：计划任务路径、配置参数或启用状态不符'
    exit 1
}
if ($listening -and -not (Test-SplitListener $Port $XrayPath)) {
    Write-Log 'wrong_listener_owner：端口监听者路径或绑定地址不符，保持现有配置'
    exit 1
}

if (-not $listening -and -not $NoStart) {
    if ($t) {
        Write-Log "通过计划任务拉起: $TaskName"
        Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    } else {
        Write-Log '计划任务不存在，直接拉起内核（注意：这种方式拉起的进程可能随宿主结束而退出）'
        try {
            Start-Process -FilePath $XrayPath `
                -ArgumentList @('run', '-c', "`"$ConfigPath`"") `
                -WorkingDirectory $WorkDir -WindowStyle Hidden -ErrorAction Stop
        } catch {
            Write-Log "直接拉起失败: $($_.Exception.Message)"
        }
    }
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 400
        if (Test-TcpPort $Port) { break }
    }
    $listening = Test-TcpPort $Port
    Write-Log ("拉起后监听中: {0}" -f $listening)
    if ($listening -and -not (Test-SplitListener $Port $XrayPath)) {
        Write-Log 'wrong_listener_owner：启动后端口监听者身份不符，保持现有配置'
        exit 1
    }
}
if (-not $listening) {
    Write-Log '分流器未就绪 —— 后续代理切换按「安全阀」规则处理'
    $pending = 1
}

# ---------- 2. 系统代理 ----------
$IS   = $ProxyRegPath
$WANT = "127.0.0.1:$Port"
$cur  = Get-ItemProperty -Path $IS -ErrorAction SilentlyContinue
if (-not $cur) { Write-Log "错误：读不到代理注册表键 $IS"; exit 1 }

# 首次改动前留一份原始值，便于回滚
if (-not (Test-Path $BackupPath)) {
    try {
        [pscustomobject]@{
            saved_at      = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            ProxyEnable   = $cur.ProxyEnable
            ProxyServer   = $cur.ProxyServer
            ProxyOverride = $cur.ProxyOverride
            AutoConfigURL = $cur.AutoConfigURL
        } | ConvertTo-Json -Depth 5 | Set-Content -Path $BackupPath -Encoding UTF8
        Write-Log "已备份原始代理设置 -> $BackupPath"
    } catch { Write-Log "备份代理设置失败: $($_.Exception.Message)" }
}

if ($cur.ProxyEnable -eq 1 -and $cur.ProxyServer -eq $WANT) {
    if ($listening) {
        Write-Log "系统代理 OK: $($cur.ProxyServer)"
    } else {
        # 【安全阀】系统代理指着分流器，但分流器没起来 —— 立刻回退，否则整机断网。
        # 这是 2026-10-01 实际发生过的事故：v2rayN 升级时按镜像名杀掉了同名内核。
        $fb = $FallbackProxy
        if (Test-Path $BackupPath) {
            try {
                $b = Get-Content -Raw -Encoding UTF8 $BackupPath | ConvertFrom-Json
                if ($b.ProxyServer -and $b.ProxyServer -ne $WANT) { $fb = $b.ProxyServer }
            } catch { }
        }
        Write-Log ("分流器未就绪 -> 回退系统代理 {0} -> {1}（避免整机断网）" -f $cur.ProxyServer, $fb)
        try {
            Set-ItemProperty -Path $IS -Name ProxyServer -Value $fb -Type String
            Write-Log ("系统代理 已回退: {0}" -f (Get-ItemProperty -Path $IS).ProxyServer)
        } catch {
            Write-Log "系统代理 回退失败: $($_.Exception.Message)"
        }
        $pending = 1
    }
} elseif (-not $listening) {
    Write-Log ("系统代理 保持 {0}（分流器未就绪，不改）" -f $cur.ProxyServer)
    $pending = 1
} else {
    Write-Log ("系统代理 待修正: {0} -> {1}" -f $cur.ProxyServer, $WANT)
    try {
        Set-ItemProperty -Path $IS -Name ProxyEnable -Value 1      -Type DWord
        Set-ItemProperty -Path $IS -Name ProxyServer -Value $WANT -Type String
        Write-Log ("系统代理 已设为: {0}" -f (Get-ItemProperty -Path $IS).ProxyServer)
    } catch {
        Write-Log "系统代理 设置失败: $($_.Exception.Message)"
        $pending = 1
    }
}

# 例外表只做检查，不覆写（避免抹掉用户已有规则）
$ov = (Get-ItemProperty -Path $IS -ErrorAction SilentlyContinue).ProxyOverride
$missing = @($REQUIRED_EXCEPTIONS | Where-Object { $ov -notlike "*$_*" })
if ($missing.Count -gt 0) {
    Write-Log ("警告：系统代理例外表缺少 {0}" -f ($missing -join ', '))
    Write-Log '      （不自动修改，请人工确认后追加到 ProxyOverride）'
    $pending = 1
} else {
    Write-Log '系统代理例外表 OK（workbuddy / codebuddy / lkeap 均在）'
}

# ---------- 3. 代理环境变量 ----------
if (-not $listening -and -not $NoEnvWrite) {
    Write-Log 'env 写入已跳过：分流器未就绪，避免覆盖为失效端口'
} elseif (-not $NoEnvWrite) {
    $envs = [ordered]@{
        'HTTP_PROXY'  = "http://$WANT"
        'HTTPS_PROXY' = "http://$WANT"
        'ALL_PROXY'   = "socks5h://$WANT"
    }
    foreach ($k in $envs.Keys) {
        $v = [Environment]::GetEnvironmentVariable($k, $EnvScope)
        if ($v -eq $envs[$k]) {
            Write-Log "env OK: $k"
        } else {
            try {
                [Environment]::SetEnvironmentVariable($k, $envs[$k], $EnvScope)
                Write-Log ("env 已修正: {0} scope={1}" -f $k, $EnvScope)
            } catch {
                Write-Log "env 设置失败 $k : $($_.Exception.Message)"
                $pending = 1
            }
        }
    }
    # 广播，让新进程立刻看到（仅 User 作用域有意义）
    if ($EnvScope -eq 'User') {
        try {
            Add-Type -Namespace AgSplit -Name Native -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@ -ErrorAction Stop
            $res = [UIntPtr]::Zero
            [void][AgSplit.Native]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$res)
            Write-Log 'WM_SETTINGCHANGE 已广播'
        } catch {
            Write-Log "广播跳过（环境限制）: $($_.Exception.Message)"
        }
    }
} else {
    Write-Log 'env 检查已跳过（-NoEnvWrite）'
}

# ---------- 4. Startup 快捷方式（快速启动下不生效，仅作冗余） ----------
if (-not $NoStartupLnk -and $StartupDir) {
    try {
        $lnkPath = Join-Path $StartupDir 'ag-split.lnk'
        if (Test-Path $lnkPath) {
            Write-Log 'Startup 快捷方式 OK'
        } else {
            $ws = New-Object -ComObject WScript.Shell
            $sc = $ws.CreateShortcut($lnkPath)
            $sc.TargetPath       = $XrayPath
            $sc.Arguments        = "run -c `"$ConfigPath`""
            $sc.WorkingDirectory = $WorkDir
            $sc.WindowStyle      = 7
            $sc.Description      = 'Antigravity Google-only egress splitter'
            $sc.Save()
            Write-Log "Startup 快捷方式 已补建: $lnkPath"
        }
    } catch {
        Write-Log "Startup 快捷方式 跳过: $($_.Exception.Message)"
    }
} else {
    Write-Log 'Startup 快捷方式 检查已跳过'
}

# ---------- 5. 只读验证：默认出口 vs Google 侧出口 ----------
if ($listening -and -not $NoEgressProbe) {
    try {
        $def = (curl.exe -fsS -m 15 --noproxy "" -x "http://127.0.0.1:$Port" 'https://ipinfo.io/ip' 2>$null)
        $defaultExit = $LASTEXITCODE
        $parsedAddress = $null
        if ($defaultExit -ne 0 -or -not [Net.IPAddress]::TryParse([string]$def, [ref]$parsedAddress)) {
            throw '默认出口探测未返回有效 IP'
        }
        Write-Log ("默认出口 : {0}" -f $parsedAddress)
        $edns = (curl.exe -fsS -m 15 --noproxy "" -x "http://127.0.0.1:$Port" 'https://dns.google/resolve?name=o-o.myaddr.l.google.com&type=TXT' 2>$null)
        $dnsExit = $LASTEXITCODE
        if ($dnsExit -ne 0) { throw 'Google DNS 探测请求失败' }
        $dnsResponse = $edns | ConvertFrom-Json -ErrorAction Stop
        if ($dnsResponse.Status -ne 0) { throw 'Google DNS 返回失败状态' }
        Write-Log 'Google DNS 可达；ECS 网段仅为线索，不证明实际出口 IP、分流或账号风险'
    } catch {
        Write-Log "分流验证失败: $($_.Exception.Message)"
        $pending = 1
    }
} elseif ($NoEgressProbe) {
    Write-Log '出口探测已跳过（-NoEgressProbe）'
}

# ---------- 6. 汇总 ----------
if ($pending -eq 0) { Write-Log '结果：全部就绪' } else { Write-Log '结果：有项目未完成' }
Write-Log '========== ensure-split 结束 =========='
exit $pending
