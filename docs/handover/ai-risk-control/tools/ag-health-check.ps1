# ag-health-check.ps1 - Antigravity 代理链路 / 分流 / Gemini 风控 只读自检
#
# 用法（普通用户权限即可）：
#   powershell -NoProfile -ExecutionPolicy Bypass -File D:\TOOL\v2rayN\ag-health-check.ps1
#
# 只读：不修改任何配置、不重启任何进程、不写注册表。
# 退出码：0 = 无 FAIL，1 = 存在 FAIL。
#
# 【换机器前必读】下面四个变量按本机实际修改：
#   $AG_DIR  Antigravity 安装目录
#   $V2_DIR  v2rayN 安装目录
#   $FRONT   分流器地址（应与 gen-config.py 的 AG_SPLIT_PORT 一致）
#   $GOOGLE  待验证的 Google 端点

param([switch]$ProbeGoogleEgress)

$ErrorActionPreference = 'Continue'
$script:rows = New-Object System.Collections.ArrayList

function Add-Row {
    param([string]$Level, [string]$Item, [string]$Detail)
    [void]$script:rows.Add([pscustomobject]@{ Level = $Level; Item = $Item; Detail = $Detail })
}

$AG_DIR    = $null
foreach ($d in Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Programs') -Directory -ErrorAction SilentlyContinue) {
    if ($d.Name -ieq 'antigravity' -and (Test-Path (Join-Path $d.FullName 'Antigravity.exe'))) { $AG_DIR = $d.FullName; break }
}
if (-not $AG_DIR) { $AG_DIR = Join-Path $env:LOCALAPPDATA 'Programs\Antigravity' }
$V2_DIR    = 'D:\TOOL\v2rayN'
$FRONT     = 'http://127.0.0.1:10810'
$GOOGLE    = @(
    'https://daily-cloudcode-pa.googleapis.com/',
    'https://oauth2.googleapis.com/',
    'https://cloudcode-pa.googleapis.com/',
    'https://generativelanguage.googleapis.com/'
)

Write-Host '=== Antigravity 代理链路自检 ===' -ForegroundColor Cyan

# --- 1. 代理进程 ---
$v = Get-Process -Name v2rayN -ErrorAction SilentlyContinue
if ($v) { Add-Row 'PASS' 'v2rayN 前端' "pid=$($v.Id)" } else { Add-Row 'FAIL' 'v2rayN 前端' '未运行' }
# 分流器内核用「换过名的」副本 ag-split-core.exe，不叫 xray.exe
# —— 因为 v2rayN 启动/升级时会按镜像名清理旧 xray 进程，同名的分流器会被误杀。
$xs = @(Get-Process -Name xray -ErrorAction SilentlyContinue)
$sc = @(Get-Process -Name ag-split-core -ErrorAction SilentlyContinue)
$splitConnections = @(Get-NetTCPConnection -LocalPort 10810 -State Listen -ErrorAction SilentlyContinue)
$splitOwnerIds = @($splitConnections.OwningProcess | Sort-Object -Unique)
$expectedCore = Join-Path $V2_DIR 'ag-split\ag-split-core.exe'
if ($splitOwnerIds.Count -eq 1) {
    $splitOwner = Get-CimInstance Win32_Process -Filter "ProcessId=$($splitOwnerIds[0])" -ErrorAction SilentlyContinue
    $bindLocal = @($splitConnections | Where-Object { $_.LocalAddress -ne '127.0.0.1' }).Count -eq 0
    if ($bindLocal -and $splitOwner.ExecutablePath -ieq $expectedCore) {
        Add-Row 'PASS' '监听者身份' "pid=$($splitOwner.ProcessId) path=$($splitOwner.ExecutablePath)"
    } elseif ($bindLocal -and $splitOwner -and $splitOwner.Name -ieq 'ag-split-core.exe') {
        # S4U/session-0 进程对非提权查询不返回 ExecutablePath；与 ensure-split 的
        # Test-SplitListener 同口径退化：进程名 + 唯一监听 + 仅绑 127.0.0.1。
        Add-Row 'WARN' '监听者身份' "pid=$($splitOwner.ProcessId) name=$($splitOwner.Name) 绑定=127.0.0.1；可执行路径不可读（S4U 权限边界，非风险信号），提权可精确复核"
    } else {
        Add-Row 'FAIL' '监听者身份' "wrong_listener_owner pid=$($splitOwner.ProcessId) path=$($splitOwner.ExecutablePath)"
    }
} else { Add-Row 'FAIL' '监听者身份' '无法确定唯一监听者' }
if ($sc.Count -ge 1 -and $xs.Count -ge 1) {
    Add-Row 'PASS' '内核实例' "v2rayN 核心 $($xs.Count) 个 + 分流器 $($sc.Count) 个"
} elseif ($sc.Count -ge 1) {
    Add-Row 'WARN' '内核实例' "分流器在运行，但 v2rayN 核心（xray）未运行"
} elseif ($xs.Count -ge 1) {
    Add-Row 'FAIL' '内核实例' '只有 v2rayN 核心，分流器（ag-split-core）未运行'
} else {
    Add-Row 'FAIL' '内核实例' '两个内核都未运行'
}

# --- 2. 本地入站端口 ---
foreach ($p in 10808, 10809, 10810) {
    $c = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
    if ($c) { Add-Row 'PASS' "入站端口 $p" 'LISTENING' } else { Add-Row 'FAIL' "入站端口 $p" '未监听' }
}

# --- 3. 系统代理（Chromium / Sign In 通道）---
$k = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
if ($k.ProxyEnable -eq 1) { Add-Row 'PASS' '系统代理已启用' "ProxyServer=$($k.ProxyServer)" }
else { Add-Row 'FAIL' '系统代理已启用' 'ProxyEnable=0：Sign In / 渲染进程会直连，账号出现双地理，风控高风险' }
if ($k.ProxyServer -eq '127.0.0.1:10810') { Add-Row 'PASS' '系统代理指向' '127.0.0.1:10810（分流器）' }
else { Add-Row 'WARN' '系统代理指向' "当前=$($k.ProxyServer)，预期 127.0.0.1:10810" }
$ov = [string]$k.ProxyOverride
if ($ov -match 'google') { Add-Row 'FAIL' '代理例外表' '含 google 域名 -> 会直连' } else { Add-Row 'PASS' '代理例外表' '不含 google 域名' }

# --- 4. 用户级代理环境变量 ---
$ue = Get-ItemProperty -Path 'HKCU:\Environment'
$np = [string]$ue.NO_PROXY
if ($np -match 'google') { Add-Row 'FAIL' '用户级 NO_PROXY' "含 google：$np" } else { Add-Row 'PASS' '用户级 NO_PROXY' '不含 google 域名' }
foreach ($n in 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY') {
    $val = [string]$ue.$n
    if ($val -match '10810') { Add-Row 'PASS' "env $n" $val }
    else { Add-Row 'WARN' "env $n" "当前=$val，预期指向 10810" }
}

# --- 5. 分流正确性（本次加固的核心）---
$googleEgress = $null
try {
    $r = Invoke-RestMethod -Uri 'https://dns.google/resolve?name=o-o.myaddr.l.google.com&type=TXT' -Proxy $FRONT -TimeoutSec 25
    $txt = (($r.Answer | Where-Object { $_.type -eq 16 } | ForEach-Object { $_.data }) -join ' | ')
    $m = [regex]::Match($txt, 'edns0-client-subnet\s+(\d+\.\d+\.\d+)\.\d+/\d+')
    if ($m.Success) { $googleEgress = $m.Groups[1].Value + '.0/24' } else { $googleEgress = $txt }
} catch {
    Add-Row 'FAIL' 'Google 出口探测' "失败：$($_.Exception.Message)"
}
$generalIp = $null
try {
    $g = Invoke-RestMethod -Uri 'http://ip-api.com/json/?fields=status,query,country,city,isp,hosting,proxy' -Proxy $FRONT -TimeoutSec 25
    if ($g.status -eq 'success') {
        $generalIp = $g.query
        if ($g.hosting -or $g.proxy) { $flag = "hosting=$($g.hosting) proxy=$($g.proxy) —— 机房/代理特征" }
        else { $flag = 'hosting=False proxy=False' }
        Add-Row 'PASS' '默认出口属性' "$($g.query) $($g.country)/$($g.city) $($g.isp) | $flag"
    } else { Add-Row 'WARN' '默认出口属性' 'ip-api 未返回有效结果' }
} catch {
    Add-Row 'FAIL' '默认出口探测' "失败：$($_.Exception.Message)"
}
if ($googleEgress -and $generalIp) {
    Add-Row 'INFO' '出口证据边界' "Google DNS ECS=$googleEgress；默认出口=$generalIp；ECS 不证明实际 Google 出口或账号风险"
}
if ($ProbeGoogleEgress) {
    try {
        $egress = & (Join-Path $PSScriptRoot 'ag-egress-probe.ps1')
        $level = if ($egress.Hosting -or $egress.Proxy) { 'WARN' } else { 'INFO' }
        Add-Row $level 'Google 节点出口属性' "$($egress.ExitIp) $($egress.Country) $($egress.Isp) hosting=$($egress.Hosting) proxy=$($egress.Proxy)；临时实例证据，第三方分类不证明账号安全"
    } catch {
        Add-Row 'WARN' 'Google 节点出口属性' "未验证：$($_.Exception.Message)"
    }
} else { Add-Row 'INFO' 'Google 节点出口属性' '按需使用 -ProbeGoogleEgress；日常自检不启动临时实例' }

# --- 6. Google 端点连通性（经前门，404 = 正常）---
foreach ($u in $GOOGLE) {
    $code = 'ERR'
    try { $code = [int](Invoke-WebRequest -Uri $u -Proxy $FRONT -TimeoutSec 25 -UseBasicParsing).StatusCode }
    catch { if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode } }
    if ($code -in 200, 204, 404) { Add-Row 'PASS' 'Google 端点' "$u -> $code" }
    else { Add-Row 'FAIL' 'Google 端点' "$u -> $code" }
}

# --- 7. antigravity-proxy 部署与配置 ---
$dll = Join-Path $AG_DIR 'version.dll'
$cfg = Join-Path $AG_DIR 'config.json'
if (Test-Path $dll) { Add-Row 'PASS' '代理 DLL' 'version.dll 已就位' } else { Add-Row 'FAIL' '代理 DLL' "$dll 不存在" }
if (Test-Path $cfg) {
    try {
        $jc = Get-Content -Raw -Encoding UTF8 $cfg | ConvertFrom-Json
        if ($jc.proxy.port -eq 10810) { Add-Row 'PASS' 'DLL 上游' "proxy=$($jc.proxy.host):$($jc.proxy.port)" }
        else { Add-Row 'WARN' 'DLL 上游' "proxy.port=$($jc.proxy.port)，预期 10810" }
        if ($jc.diagnostics.agent_ip_probe) { Add-Row 'PASS' '出口 IP 自检' 'agent_ip_probe 已开启' }
        else { Add-Row 'INFO' '出口 IP 自检' 'v2.4 已知限制：DLL 运行时会重写 config.json 并写回 false，无法持久开启；不影响分流' }
    } catch { Add-Row 'FAIL' '代理配置' "解析失败：$($_.Exception.Message)" }
} else { Add-Row 'FAIL' '代理配置' "$cfg 不存在" }

# --- 7b. 分流器 WorkBuddy 直连规则（防回归守护）---
# WorkBuddy（Electron）只要进程带 HTTP_PROXY 就硬编码 setProxy 并把 bypass 固定为
# localhost —— WinINET 例外表和 NO_PROXY 对它全部失效（2026-09-30 app.asar 反编译实证）。
# 分流器侧的五域直连规则是第二道防线；config.json 由 gen-config.py 重新生成时不得丢失。
$splitCfgPath = Join-Path $V2_DIR 'ag-split\config.json'
if (-not (Test-Path $splitCfgPath)) {
    Add-Row 'WARN' '分流器 WorkBuddy 直连规则' "$splitCfgPath 不存在"
} else {
    try {
        $rawCfg = Get-Content -Raw -Encoding UTF8 $splitCfgPath | ConvertFrom-Json
        $directRules = @($rawCfg.routing.rules | Where-Object { $_.outboundTag -eq 'direct' })
        $needDomains = @('domain:workbuddy.ai','domain:workbuddy.cn','domain:codebuddy.ai','domain:codebuddy.cn','domain:lkeap.cloud.tencent.com')
        $haveDomains = @($directRules | ForEach-Object { $_.domain }) | Select-Object -Unique
        $missingDomains = @($needDomains | Where-Object { $_ -notin $haveDomains })
        $hasFreedom = @($rawCfg.outbounds | Where-Object { $_.tag -eq 'direct' -and $_.protocol -eq 'freedom' }).Count -eq 1
        if ($hasFreedom -and $missingDomains.Count -eq 0) {
            Add-Row 'PASS' '分流器 WorkBuddy 直连规则' '五域 -> direct(freedom) 在兜底前；env 短路时的第二道防线在位'
        } else {
            $why = @()
            if (-not $hasFreedom) { $why += 'direct(freedom) outbound 缺失' }
            if ($missingDomains.Count -gt 0) { $why += ('规则缺失: ' + ($missingDomains -join ', ')) }
            Add-Row 'FAIL' '分流器 WorkBuddy 直连规则' ($why -join '；')
        }
    } catch { Add-Row 'FAIL' '分流器 WorkBuddy 直连规则' "解析失败：$($_.Exception.Message)" }
}

# --- 8. 分流器自启（以计划任务为准，Startup 快捷方式只作冗余）---
# 本机 HiberbootEnabled=1：关机走混合休眠恢复，Startup 文件夹项【不会】被执行，
# 所以「ag-split.lnk 存在」≠「分流器会自启」。判据必须是计划任务。
$hb = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
$t8 = Get-ScheduledTask -TaskName 'AgSplitEgress' -ErrorAction SilentlyContinue
if (-not $t8) {
    $why = ''
    if ($hb -eq 1) { $why = '（本机快速启动已开，Startup 项不可靠）' }
    Add-Row 'WARN' '分流器自启' "未找到计划任务 AgSplitEgress$why"
} elseif ($t8.State -eq 'Disabled') {
    Add-Row 'WARN' '分流器自启' '计划任务 AgSplitEgress 已禁用'
} elseif (@($t8.Actions).Count -ne 1 -or $t8.Actions[0].Execute -ine $expectedCore -or $t8.Actions[0].Arguments.Trim() -ine ('run -c "{0}"' -f (Join-Path $V2_DIR 'ag-split\config.json'))) {
    Add-Row 'FAIL' '分流器自启' 'wrong_task_action：路径或配置参数不符'
} else {
    $d = "计划任务 AgSplitEgress=$($t8.State)"
    if ($hb -eq 1) { $d += '；快速启动已开 -> 靠计划任务而非 Startup 项' }
    Add-Row 'PASS' '分流器自启' $d
}

# --- 9. 风控特征串（只看应用日志，避开 brain 会话自污染）---
$patterns = @('location is not supported', 'FAILED_PRECONDITION', 'RESOURCE_EXHAUSTED', 'PERMISSION_DENIED')
$hits = @()
foreach ($root in @((Join-Path $env:APPDATA 'Antigravity\logs'), (Join-Path $AG_DIR 'logs'))) {
    if (-not (Test-Path $root)) { continue }
    foreach ($p in $patterns) {
        $m = Select-String -Path (Join-Path $root '*') -Pattern $p -SimpleMatch -ErrorAction SilentlyContinue
        if ($m) { $hits += "$p x$($m.Count)" }
    }
}
if ($hits.Count -eq 0) { Add-Row 'PASS' '风控特征串' '应用日志中无 location / quota / permission 拒绝记录' }
else { Add-Row 'WARN' '风控特征串' ($hits -join '; ') }

# --- 输出 ---
Write-Host ''
$script:rows | Format-Table -AutoSize -Property Level, Item, Detail | Out-String -Width 400 | Write-Host
$fails = @($script:rows | Where-Object { $_.Level -eq 'FAIL' }).Count
$warns = @($script:rows | Where-Object { $_.Level -eq 'WARN' }).Count
$infos = @($script:rows | Where-Object { $_.Level -eq 'INFO' }).Count
$pass  = @($script:rows | Where-Object { $_.Level -eq 'PASS' }).Count
Write-Host ("汇总: PASS={0}  WARN={1}  FAIL={2}  INFO={3}" -f $pass, $warns, $fails, $infos) -ForegroundColor Cyan
if ($fails -gt 0) { Write-Host '存在 FAIL 项，需要处理。' -ForegroundColor Red; exit 1 }
Write-Host '无 FAIL 项。' -ForegroundColor Green
exit 0
