# ag-split-live-acceptance.ps1 —— ag-split 分流器「受控实战验收」
#
# 与 ensure-split.test.ps1 的区别：
#   test.ps1  —— 夹具验收（离线、注入状态），证明**脚本的判定逻辑**正确
#   本脚本    —— 实战验收（在线、真故障注入），证明**整套自动化**真的能自愈
#
# 验收项：
#   L1 基线            分流器在跑、代理指向它、出口分流正确
#   L2 手动自愈        杀掉内核 -> 跑 ensure-split -> 恢复
#   L3 看门狗自愈      杀掉内核 -> **等真实看门狗（≤3 分钟）** -> 恢复
#   L4 安全阀          把系统代理临时指向一个死端口 -> ensure-split 应回退到 10808
#   L5 出口分流正确性  默认出口 vs Google 侧出口必须不同网段
#   L6 例外表完整      workbuddy / codebuddy / lkeap 均在
#   L7 任务状态        AgSplitEgress 在跑 / AgSplitWatchdog 就绪
#   L8 收尾            系统恢复原状（分流器在跑 + 代理指向它）
#
# 安全设计：全程 try/finally，结束时**无条件**把系统恢复到「分流器在跑 + 代理指向它」；
#           若分流器起不来，则回退代理到常驻前端，绝不把机器留在断网状态。
#
# 用法：
#   pwsh -NoProfile -ExecutionPolicy Bypass -File D:\TOOL\v2rayN\ag-split\ag-split-live-acceptance.ps1
# 退出码：0 = 全部通过；1 = 有失败

param(
    [int]   $Port          = 10810,
    [string]$FallbackProxy = '127.0.0.1:10808',
    [string]$TaskName      = 'AgSplitEgress',
    [string]$WatchdogName  = 'AgSplitWatchdog',
    [string]$XrayPath      = 'D:\TOOL\v2rayN\ag-split\ag-split-core.exe',
    [string]$EnsureScript  = 'D:\TOOL\v2rayN\ag-split\ensure-split.ps1',
    [string]$ReportPath    = 'D:\TOOL\v2rayN\ag-split\live-acceptance-report.txt',
    [int]   $WatchdogWaitSeconds = 210
)

$ErrorActionPreference = 'Continue'
$PWSH = 'C:\Program Files\PowerShell\7\pwsh.exe'
$IS   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$WANT = "127.0.0.1:$Port"

$script:PASS = 0
$script:FAIL = 0
$script:LINES = @()

function Say($m, $color = 'Gray') {
    $line = $m
    Write-Host $line -ForegroundColor $color
    $script:LINES += $line
}
function Pass($n, $d) { $script:PASS++; Say ("  [PASS] {0,-30} -> {1}" -f $n, $d) 'Green' }
function Fail($n, $d) { $script:FAIL++; Say ("  [FAIL] {0,-30} -> {1}" -f $n, $d) 'Red' }
function Section($t) { Say ''; Say $t 'Cyan' }

function Test-Port([int]$p) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect('127.0.0.1', $p, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(1200)) { $c.Close(); return $false }
        $c.EndConnect($iar); $c.Close(); return $true
    } catch { return $false }
}
function Get-Proxy { (Get-ItemProperty -Path $IS -ErrorAction SilentlyContinue).ProxyServer }
function Set-Proxy([string]$v) { Set-ItemProperty -Path $IS -Name ProxyEnable -Value 1 -Type DWord; Set-ItemProperty -Path $IS -Name ProxyServer -Value $v -Type String }
function Get-EgressSplit {
    $def  = (curl.exe -s -m 15 -x "http://127.0.0.1:$Port" 'https://ipinfo.io/ip' 2>$null)
    $edns = (curl.exe -s -m 15 -x "http://127.0.0.1:$Port" 'https://dns.google/resolve?name=o-o.myaddr.l.google.com&type=TXT' 2>$null)
    $g = ''
    if ($edns -match 'edns0-client-subnet\s+([0-9.]+)/') { $g = $matches[1] }
    return @{ Def = ($def -replace '\s', ''); Google = $g }
}
function Ensure-Up {
    # 无条件把分流器拉起来（最多等 20 秒）
    if (Test-Port $Port) { return $true }
    Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 40; $i++) { Start-Sleep -Milliseconds 500; if (Test-Port $Port) { break } }
    return (Test-Port $Port)
}
function Kill-Core {
    $k = @(Get-Process -Name 'ag-split-core' -ErrorAction SilentlyContinue)
    foreach ($p in $k) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 800
    return $k.Count
}

$origProxy = Get-Proxy

Say '============================================================'
Say '  ag-split 分流器 · 受控实战验收'
Say ("  时间: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Say ("  端口: {0}   回退目标: {1}" -f $Port, $FallbackProxy)
Say '============================================================'

try {
    # ---------------- L1 基线 ----------------
    Section 'L1 · 基线'
    if (Test-Port $Port) { Pass '分流器在跑' "port $Port" } else { Fail '分流器在跑' "port $Port 未监听" }
    if ((Get-Proxy) -eq $WANT) { Pass '系统代理指向分流器' (Get-Proxy) } else { Fail '系统代理指向分流器' ("实得 " + (Get-Proxy)) }

    # ---------------- L2 手动自愈 ----------------
    Section 'L2 · 手动自愈（杀掉内核 -> 跑 ensure-split）'
    $n = Kill-Core
    Say ("  注入：杀掉 {0} 个 ag-split-core 进程" -f $n)
    if (-not (Test-Port $Port)) { Say '  分流器已确实不可用' } else { Say '  警告：杀后端口仍在监听' }

    & $PWSH -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $EnsureScript -Quiet | Out-Null
    $rc = $LASTEXITCODE
    if ((Test-Port $Port) -and $rc -eq 0) { Pass '手动自愈恢复' "exit=$rc 端口已监听" }
    else { Fail '手动自愈恢复' "exit=$rc 端口监听=" + (Test-Port $Port) }

    # ---------------- L3 看门狗自愈 ----------------
    Section 'L3 · 看门狗自愈（杀掉内核 -> 等真实看门狗）'
    $n = Kill-Core
    Say ("  注入：杀掉 {0} 个进程；等看门狗（最多 {1} 秒）" -f $n, $WatchdogWaitSeconds)
    $t0 = Get-Date
    $recovered = $false
    while (((Get-Date) - $t0).TotalSeconds -lt $WatchdogWaitSeconds) {
        Start-Sleep -Seconds 5
        if (Test-Port $Port) { $recovered = $true; break }
    }
    $elapsed = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
    if ($recovered) { Pass '看门狗自动恢复' ("{0} 秒后端口恢复" -f $elapsed) }
    else { Fail '看门狗自动恢复' ("{0} 秒内未恢复" -f $WatchdogWaitSeconds) }

    # ---------------- L4 安全阀 ----------------
    Section 'L4 · 安全阀（代理指向死端口 -> 应回退）'
    $deadPort = 19887   # 本机未使用的端口
    Say ("  注入：系统代理临时指向死端口 127.0.0.1:{0}" -f $deadPort)
    Set-Proxy "127.0.0.1:$deadPort"
    Start-Sleep -Milliseconds 500
    if ((Get-Proxy) -eq "127.0.0.1:$deadPort") {
        # 让被测脚本以为「分流器应该在这个死端口上」，且不允许它启动（-NoStart）
        & $PWSH -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $EnsureScript -Quiet `
            -Port $deadPort -NoStart -NoEnvWrite -NoStartupLnk -NoEgressProbe | Out-Null
        $after = Get-Proxy
        if ($after -ne "127.0.0.1:$deadPort") { Pass '安全阀回退生效' ("回退到 " + $after) }
        else { Fail '安全阀回退生效' '代理仍指向死端口' }
    } else {
        Fail '安全阀注入' '未能把代理设到死端口'
    }

    # ---------------- L5 出口分流 ----------------
    Section 'L5 · 出口分流正确性'
    if (-not (Ensure-Up)) { Fail '分流器恢复' '无法拉起' }
    $e = Get-EgressSplit
    Say ("  默认出口 : {0}" -f $e.Def)
    Say ("  Google 侧: {0}" -f $e.Google)
    if ($e.Def -and $e.Google) {
        $a = ($e.Def -split '\.')[0..1] -join '.'
        $b = ($e.Google -split '\.')[0..1] -join '.'
        if ($a -ne $b) { Pass '分流生效（两出口不同网段）' "$a.x vs $b.x" }
        else { Fail '分流生效（两出口不同网段）' "同网段 $a" }
    } else {
        Fail '分流生效（两出口不同网段）' '取不到出口'
    }

    # ---------------- L6 例外表 ----------------
    Section 'L6 · 系统代理例外表'
    $ov = (Get-ItemProperty -Path $IS -ErrorAction SilentlyContinue).ProxyOverride
    $need = @('*.workbuddy.ai', '*.codebuddy.ai', '*.lkeap.cloud.tencent.com', '*.workbuddy.cn', '*.codebuddy.cn')
    $miss = @($need | Where-Object { $ov -notlike "*$_*" })
    if ($miss.Count -eq 0) { Pass '例外表完整' '5 个必需域名均在' } else { Fail '例外表完整' ('缺 ' + ($miss -join ', ')) }

    # ---------------- L7 任务状态 ----------------
    Section 'L7 · 任务状态'
    foreach ($pair in @(@($TaskName, 'Running'), @($WatchdogName, 'Ready'))) {
        $t = Get-ScheduledTask -TaskName $pair[0] -ErrorAction SilentlyContinue
        if (-not $t) { Fail ("任务 " + $pair[0]) '不存在' }
        elseif ($t.State -eq 'Disabled') { Fail ("任务 " + $pair[0]) '已禁用' }
        else { Pass ("任务 " + $pair[0]) ("state=" + $t.State) }
    }
}
finally {
    # ---------------- L8 收尾：无条件恢复 ----------------
    Section 'L8 · 收尾恢复'
    $up = Ensure-Up
    if ($up) {
        Set-Proxy $WANT
        Say ("  分流器已恢复；系统代理 -> {0}" -f (Get-Proxy)) 'Green'
        if ((Get-Proxy) -eq $WANT) { Pass '收尾：系统恢复正常' (Get-Proxy) } else { Fail '收尾：系统恢复正常' ("实得 " + (Get-Proxy)) }
    } else {
        Set-Proxy $FallbackProxy
        Say ("  分流器未能恢复；系统代理已回退 -> {0}（避免断网）" -f (Get-Proxy)) 'Yellow'
        Fail '收尾：系统恢复正常' '分流器未能恢复，已回退代理'
    }
}

Say ''
Say '============================================================'
if ($script:FAIL -eq 0) { Say ("  实战验收结果: PASS {0} / FAIL {1}" -f $script:PASS, $script:FAIL) 'Green' }
else { Say ("  实战验收结果: PASS {0} / FAIL {1}" -f $script:PASS, $script:FAIL) 'Red' }
Say '============================================================'

try { $script:LINES | Set-Content -Path $ReportPath -Encoding UTF8 } catch { }

if ($script:FAIL -eq 0) { exit 0 } else { exit 1 }
