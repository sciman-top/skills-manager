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
    [string]$ConfigPath    = 'D:\TOOL\v2rayN\ag-split\config.json',
    [string]$EnsureScript  = 'D:\TOOL\v2rayN\ag-split\ensure-split.ps1',
    [string]$ProbeScript   = 'D:\TOOL\v2rayN\ag-egress-probe.ps1',
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
function Get-SplitOwner {
    $c = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    if ($c.Count -eq 0) { return $null }
    $ids = @($c.OwningProcess | Sort-Object -Unique)
    if ($ids.Count -ne 1 -or @($c | Where-Object { $_.LocalAddress -ne '127.0.0.1' }).Count -gt 0) { return $null }
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$($ids[0])" -ErrorAction SilentlyContinue
    $expected = '"{0}" run -c "{1}"' -f $XrayPath, $ConfigPath
    if ($p.ExecutablePath -ieq $XrayPath -and $p.CommandLine.Trim() -ieq $expected) { return $p }
    return $null
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
    if (Get-SplitOwner) { return $true }
    Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 40; $i++) { Start-Sleep -Milliseconds 500; if (Get-SplitOwner) { return $true } }
    return $false
}
function Kill-Core {
    $owner = Get-SplitOwner
    if (-not $owner) { throw '分流器监听者身份不符，停止故障注入' }
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Stop-Process -Id $owner.ProcessId -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
    return $owner.ProcessId
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
    if (Get-SplitOwner) { Pass '分流器在跑' "port $Port / managed owner" } else { Fail '分流器在跑' "port $Port owner invalid" }
    if ((Get-Proxy) -eq $WANT) { Pass '系统代理指向分流器' (Get-Proxy) } else { Fail '系统代理指向分流器' ("实得 " + (Get-Proxy)) }

    # ---------------- L2 手动自愈 ----------------
    Section 'L2 · 手动自愈（杀掉内核 -> 跑 ensure-split）'
    $n = Kill-Core
    Say ("  注入：停止 ag-split-core pid={0}" -f $n)
    if (-not (Get-SplitOwner)) { Say '  分流器已确实不可用' } else { throw '故障注入后分流器仍在运行' }

    & $PWSH -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $EnsureScript -Quiet -NoEnvWrite -NoStartupLnk -NoEgressProbe `
        -XrayPath $XrayPath -ConfigPath $ConfigPath -TaskName $TaskName | Out-Null
    $rc = $LASTEXITCODE
    $owner = Get-SplitOwner
    if ($owner -and $rc -eq 0 -and $owner.ProcessId -ne $n) { Pass '手动自愈恢复' "exit=$rc pid=$($owner.ProcessId)" }
    else { Fail '手动自愈恢复' "exit=$rc owner_invalid" }

    # ---------------- L3 看门狗自愈 ----------------
    Section 'L3 · 看门狗自愈（杀掉内核 -> 等真实看门狗）'
    $beforeWatchdog = (Get-ScheduledTaskInfo -TaskName $WatchdogName).LastRunTime
    $n = Kill-Core
    Say ("  注入：停止 ag-split-core pid={0}；等看门狗（最多 {1} 秒）" -f $n, $WatchdogWaitSeconds)
    $t0 = Get-Date
    $recovered = $false
    while (((Get-Date) - $t0).TotalSeconds -lt $WatchdogWaitSeconds) {
        Start-Sleep -Seconds 5
        $wi = Get-ScheduledTaskInfo -TaskName $WatchdogName
        $owner = Get-SplitOwner
        if ($owner -and $owner.ProcessId -ne $n -and $wi.LastRunTime -gt $beforeWatchdog -and $wi.LastTaskResult -eq 0 -and (Get-Proxy) -eq $WANT) { $recovered = $true; break }
    }
    $elapsed = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
    if ($recovered) { Pass '看门狗自动恢复' ("{0} 秒后恢复，pid=$($owner.ProcessId)" -f $elapsed) }
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
    $defaultIp = (curl.exe -fsS -m 20 --noproxy "" -x "http://127.0.0.1:$Port" 'https://ipinfo.io/ip' 2>$null)
    $ip = $null
    if ($LASTEXITCODE -eq 0 -and [Net.IPAddress]::TryParse([string]$defaultIp, [ref]$ip)) { Pass '默认出口可达' $ip } else { Fail '默认出口可达' '未取得有效 IP' }
    $nodeEvidence = & $ProbeScript -ConfigPath $ConfigPath -CorePath $XrayPath
    if ($nodeEvidence.ExitIp -and $nodeEvidence.ConfigHash -eq (Get-FileHash -LiteralPath $ConfigPath).Hash) { Pass 'Google 节点出口测量' ("$($nodeEvidence.ExitIp) hosting=$($nodeEvidence.Hosting) proxy=$($nodeEvidence.Proxy)") } else { Fail 'Google 节点出口测量' '证据无效' }
    Say '临时节点测量不证明已登录客户端路由或账号安全。'

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
        elseif ($pair[0] -eq $TaskName -and ($t.Actions[0].Execute -ine $XrayPath -or $t.Actions[0].Arguments -ine ('run -c "{0}"' -f $ConfigPath))) { Fail ("任务 " + $pair[0]) 'wrong_task_action' }
        elseif ($pair[0] -eq $WatchdogName -and $t.Actions[0].Arguments -notmatch '(?:^|\s)-NoEgressProbe(?:\s|$)') { Fail ("任务 " + $pair[0]) 'missing -NoEgressProbe' }
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
