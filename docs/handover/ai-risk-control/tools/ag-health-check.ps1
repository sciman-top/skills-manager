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
    $gen24 = ($generalIp -split '\.')[0..2] -join '.'
    if ($googleEgress.StartsWith($gen24)) {
        Add-Row 'FAIL' '分流正确性' "Google 与默认流量同一出口（$gen24）—— 分流未生效"
    } else {
        Add-Row 'PASS' '分流正确性' "Google -> $googleEgress ；其余 -> $generalIp"
    }
}

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
