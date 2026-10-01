# ============================================================
#  WorkBuddy 风控自检脚本
#  只读检测，不修改、不删除任何文件。
#
#  !! 版本说明 !!
#  .ps1 与 .sh 为同一套检查逻辑的双实现；.ps1 曾在生成环境无法实测，
#  2026-09-29 已在真实环境实测通过；第 6 节检查代理覆盖，第 9 节检查实际错误日志、
#  活动自动化与 MCP 认证失败重试。
#  若本脚本报错，请改用 .sh 版本（Git Bash 中运行）。
#
#  用法（任选其一）：
#    1) 右键本文件 -> 使用 PowerShell 运行
#    2) powershell -ExecutionPolicy Bypass -File .\workbuddy-risk-selfcheck.ps1
#    3) 在已打开的 PowerShell 里： & ".\workbuddy-risk-selfcheck.ps1"
#
#  可选参数：
#    -OutFile <路径>   把报告同时写入文件（默认写到同目录 selfcheck-report-ps1.txt，
#                      有意与 .sh 版的 selfcheck-report.txt 分开，避免两种格式互相覆盖）
#    -NoFile           只在屏幕输出，不写文件
# ============================================================

param(
    [string]$OutFile = "",
    [switch]$NoFile
)

$ErrorActionPreference = 'SilentlyContinue'

$WB   = Join-Path $env:USERPROFILE '.workbuddy-ai'
$WBL  = Join-Path $env:USERPROFILE '.workbuddy'
$lines = New-Object System.Collections.ArrayList

function W([string]$s) { [void]$lines.Add($s) }
function Section([string]$t) {
    W ""
    W ("-" * 62)
    W ("  " + $t)
    W ("-" * 62)
}

$riskHigh = 0
$riskMid  = 0
$passCount = 0

function Ok([string]$t, [string]$d)   { W ("  [正常] " + $t); if ($d) { W ("         " + $d) }; $script:passCount++ }
function Mid([string]$t, [string]$d)  { W ("  [注意] " + $t); if ($d) { W ("         " + $d) }; $script:riskMid++ }
function Bad([string]$t, [string]$d)  { W ("  [高危] " + $t); if ($d) { W ("         " + $d) }; $script:riskHigh++ }
function Info([string]$t, [string]$d) { W ("  [信息] " + $t); if ($d) { W ("         " + $d) } }

W "============================================================"
W "  WorkBuddy 风控自检报告"
W ("  生成时间: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
W ("  计算机:   " + $env:COMPUTERNAME + "   用户: " + $env:USERNAME)
W "============================================================"

# ------------------------------------------------------------
Section "1. hosts 文件劫持检测"
# ------------------------------------------------------------
$hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
if (Test-Path $hostsPath) {
    $bad = @()
    foreach ($ln in (Get-Content $hostsPath)) {
        $t = $ln.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        if ($t -match 'workbuddy|codebuddy|tencent|qq\.com') { $bad += $t }
    }
    if ($bad.Count -eq 0) {
        Ok "hosts 无 WorkBuddy/腾讯相关劫持条目" "灰产「积分充值」通常靠改 hosts 实现，此项正常说明未被劫持"
    } else {
        Bad ("hosts 中存在可疑条目 " + $bad.Count + " 条") ($bad -join ' | ')
    }
} else {
    Info "未找到 hosts 文件" $hostsPath
}

# ------------------------------------------------------------
Section "2. 自定义模型 / 反代检测"
# ------------------------------------------------------------
$modelsPath = Join-Path $WB 'models.json'
if (Test-Path $modelsPath) {
    $raw = (Get-Content $modelsPath -Raw)
    if ($raw -match '^\s*\[\s*\]\s*$' -or $raw -match '^\s*\{\s*\}\s*$') {
        Ok "models.json 为空" "未配置任何自定义模型，即未接入反代 / API 中转站"
    } else {
        Bad "models.json 存在自定义模型配置" "需核对模型来源：协议 8.3.2 允许合法来源的自定义模型（官方保留审查权）；风险在来源不明接入与反代/中转用途"
        W ("         内容片段: " + $raw.Substring(0, [Math]::Min(300, $raw.Length)))
    }
} else {
    Ok "未发现 models.json" "等同于未配置自定义模型"
}

$susp = @()
foreach ($p in (Get-Process)) {
    $n = $p.ProcessName
    if ($n -match 'workbuddy2api|workbuddy-proxy|wb2api|flowrebound') { $susp += $n }
}
if ($susp.Count -eq 0) {
    Ok "未发现反代 / Token 提取类进程" "已排查 workbuddy2api / workbuddy-proxy / FlowRebound 等"
} else {
    Bad ("发现反代类进程: " + ($susp -join ', ')) "这类工具抓取客户端 Token 对外提供 API，官方已明确『一经发现做封号处理』"
}

# ------------------------------------------------------------
Section "3. 客户端配置第三方指向检测"
# ------------------------------------------------------------
$setPath = Join-Path $WB 'settings.json'
if (Test-Path $setPath) {
    $txt = Get-Content $setPath -Raw
    $hits = @()
    if ($txt -match '"baseUrl"')   { $hits += 'baseUrl' }
    if ($txt -match '"apiKey"')    { $hits += 'apiKey' }
    if ($txt -match '"endpoint"')  { $hits += 'endpoint' }
    if ($hits.Count -eq 0) {
        Ok "settings.json 未出现 baseUrl / apiKey / endpoint" "客户端未指向第三方服务"
    } else {
        Mid ("settings.json 中出现字段: " + ($hits -join ', ')) "请确认这些不是指向非官方服务的配置"
    }
} else {
    Info "未找到 settings.json" $setPath
}

# ------------------------------------------------------------
Section "4. 账号与设备指纹"
# ------------------------------------------------------------
$devId = "未知"
$devFile = Join-Path $WBL 'device-id'
if (Test-Path $devFile) { $devId = (Get-Content $devFile -Raw).Trim() }
Info "本机设备指纹 device-id" $devId

$acctDirs = @()
foreach ($d in (Get-ChildItem $WB -Directory)) {
    if ($d.Name -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { $acctDirs += $d.Name }
}
if ($acctDirs.Count -le 1) {
    Ok ("本机登录过的账号数: " + $acctDirs.Count) "单账号使用，无账号关联风险"
} else {
    Mid ("本机登录过 " + $acctDirs.Count + " 个账号，共用同一设备指纹") "同设备多账号是「账号关联 / 批量注册」的典型特征，新账号有被连坐的风险"
    foreach ($a in $acctDirs) { W ("         - " + $a) }
    W "         建议：不要在客户端里来回切换这些账号；不要再注册新账号"
}

# ------------------------------------------------------------
Section "5. 系统代理与 WorkBuddy 直连检测"
# ------------------------------------------------------------
$wbDomains = @()
$logRoot = Join-Path $WBL 'logs'
if (Test-Path $logRoot) {
    $u = Get-ChildItem $logRoot -Recurse -Filter *.log | Select-Object -First 60 |
         ForEach-Object { [regex]::Matches((Get-Content $_.FullName -Raw), 'https?://([a-zA-Z0-9._-]+)') } |
         ForEach-Object { $_.Groups[1].Value }
    $wbDomains = $u | Group-Object | Sort-Object Count -Descending | Select-Object -First 5
}
if ($wbDomains.Count -gt 0) {
    Info "客户端实际访问的域名（按频次）"
    foreach ($g in $wbDomains) { W ("         " + $g.Name + "  x" + $g.Count) }
} else {
    Info "未能从日志中提取域名" "可手动查看: $logRoot"
}

$proxyEnable = $null
$proxyServer = $null
try {
    $ie = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
    $proxyEnable = $ie.ProxyEnable
    $proxyServer = $ie.ProxyServer
} catch { }
if ($null -eq $proxyEnable) {
    Info "无法读取系统代理设置" "可能被安全策略限制，请手动查看：设置 - 网络和 Internet - 代理"
} elseif ($proxyEnable -eq 1) {
    Mid "系统代理已开启" ("代理服务器: " + $proxyServer)
    W "         请确认 WorkBuddy 域名在代理的『例外/bypass』列表中，否则流量会走代理出口 IP"
} else {
    Ok "系统代理未开启" "WorkBuddy 走本机直连"
}

$v2cands = @(
    'D:\TOOL\v2rayN\guiConfigs\guiNConfig.json',
    (Join-Path $env:USERPROFILE 'Downloads\Compressed\v2rayN-windows-64\guiConfigs\guiNConfig.json'),
    (Join-Path $env:APPDATA 'v2rayN\guiConfigs\guiNConfig.json')
)
$v2 = $v2cands | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($v2) {
    $vc = Get-Content $v2 -Raw
    $m = [regex]::Match($vc, '"SysProxyType"\s*:\s*(\d+)')
    if ($m.Success) {
        $st = [int]$m.Groups[1].Value
        $stLabel = "未知"
        if ($st -eq 0) { $stLabel = "清除系统代理" }
        if ($st -eq 1) { $stLabel = "自动配置系统代理（系统代理开启）" }
        if ($st -eq 2) { $stLabel = "不改变系统代理" }
        if ($st -eq 3) { $stLabel = "PAC 模式" }
        Info ("v2rayN SysProxyType = " + $st) $stLabel
    }
    $e = [regex]::Match($vc, '"SystemProxyExceptions"\s*:\s*"([^"]*)"')
    if ($e.Success) {
        $exc = $e.Groups[1].Value
        $need = @()
        foreach ($d in @('workbuddy', 'codebuddy')) {
            if ($exc -match ($d + '\.ai')) { $need += ($d + '.ai 已在例外') } else { $need += ($d + '.ai 缺失') }
        }
        if ($exc -match 'lkeap\.cloud\.tencent\.com') { $need += 'lkeap.cloud.tencent.com 已在例外' } else { $need += 'lkeap.cloud.tencent.com 缺失' }
        $missing = @($need | Where-Object { $_ -match '缺失' })
        if ($missing.Count -eq 0) {
            Ok "代理例外列表已包含 WorkBuddy 域名" ($need -join ' ; ')
        } else {
            Mid "代理例外列表缺少 WorkBuddy 域名" ($need -join ' ; ')
            W "         若客户端访问的是 .cn 版，需补充 *.workbuddy.cn ; *.codebuddy.cn"
        }
    }
} else {
    Info "未找到 v2rayN 配置" "若使用其它代理客户端，请在其规则中确认 WorkBuddy 域名走直连"
}

# ------------------------------------------------------------
Section "6. 代理环境覆盖（WinINET 例外 / NO_PROXY / 代理变量）"
# ------------------------------------------------------------
$reqDom = @('workbuddy.ai','codebuddy.ai','lkeap.cloud.tencent.com','workbuddy.cn','codebuddy.cn')
$envScopeOrder = @('Process','User','Machine')
function Get-EnvByScope([string]$name) {
    $r = [ordered]@{}
    foreach ($scope in $envScopeOrder) {
        try {
            $vars = [Environment]::GetEnvironmentVariables($scope)
            $v = $vars[$name]
            if ($null -eq $v) { $r[$scope] = '' } else { $r[$scope] = [string]$v }
        } catch {
            $r[$scope] = ''
        }
    }
    return $r
}
function Get-EffectiveEnv([string]$name) {
    $all = Get-EnvByScope $name
    foreach ($scope in $envScopeOrder) {
        if (-not [string]::IsNullOrWhiteSpace($all[$scope])) {
            return [pscustomobject]@{ Name=$name; Value=[string]$all[$scope]; Source=$scope; All=$all }
        }
    }
    return [pscustomobject]@{ Name=$name; Value=''; Source=''; All=$all }
}
function Redact-ProxyValue([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return '<unset>' }
    return [regex]::Replace($value, '(?i)(?<=://)[^/@\s]*@', '<redacted>@')
}
$effectiveNoProxy = Get-EffectiveEnv 'NO_PROXY'
$npx = [string]$effectiveNoProxy.Value
$proxyScopeNote = "生效优先级 Process > User > Machine；报告区分自检进程与持久化配置"
if ($npx.Trim()) {
    $miss2 = @($reqDom | Where-Object { $npx -notmatch [regex]::Escape($_) })
    $source = $effectiveNoProxy.Source
    if ($miss2.Count -eq 0) {
        Ok "NO_PROXY 覆盖全部必需域名" ("来源: " + $source + "；" + $npx)
    } else {
        Mid ("NO_PROXY 未覆盖: " + ($miss2 -join ' ')) ("来源: " + $source + "；" + $npx)
    }
} else {
    Mid "NO_PROXY 未设置" ("Process/User/Machine 均未设置；" + $proxyScopeNote)
}
$proxyNames = @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY')
$proxyFacts = @()
$proxyFound = $false
foreach ($name in $proxyNames) {
    $fact = Get-EffectiveEnv $name
    if ($fact.Value) {
        $proxyFound = $true
        $scopes = @($envScopeOrder | Where-Object { $fact.All[$_] })
        $proxyFacts += ($name + "=" + (Redact-ProxyValue $fact.Value) + " [生效:" + $fact.Source + ";已配置:" + ($scopes -join ',') + "]")
    }
}
if ($proxyFound) {
    Mid "检测到代理环境变量" (($proxyFacts -join ' ; ') + "；" + $proxyScopeNote)
} else {
    Ok "Process/User/Machine 均未设置全局代理环境变量" ""
}
$noProxyScopes = Get-EnvByScope 'NO_PROXY'
$noProxyConfigured = @($envScopeOrder | Where-Object { $noProxyScopes[$_] })
if ($noProxyConfigured.Count -gt 1) {
    Info "NO_PROXY 在多个环境变量作用域存在" ("已配置: " + ($noProxyConfigured -join ',') + "；新进程以较高优先级值为准")
}

# ------------------------------------------------------------
Section "7. 客户端重启频率"
# ------------------------------------------------------------
$autoLog = Join-Path $WBL 'logs\automation.log'
if (Test-Path $autoLog) {
    $today = (Get-Date).ToString('yyyy-MM-dd')
    $n = (Get-Content $autoLog | Where-Object { $_ -like "*$today*" -and $_ -match 'started' }).Count
    if ($n -le 3) {
        Ok ("今日客户端启动 " + $n + " 次") "重启频率正常"
    } elseif ($n -le 8) {
        Mid ("今日客户端启动 " + $n + " 次") "重启偏频繁。报错时请先停手，不要靠反复重启来试"
    } else {
        Bad ("今日客户端启动 " + $n + " 次") "反复重启会被计入异常行为特征，请停止这种排查方式"
    }
} else {
    Info "未找到 automation.log" $autoLog
}

# ------------------------------------------------------------
Section "8. 自动化 / 定时任务"
# ------------------------------------------------------------
$taskDir = Join-Path $WB 'tasks'
if (Test-Path $taskDir) {
    $tc = (Get-ChildItem $taskDir -Directory).Count
    if ($tc -eq 0) { Ok "无任务目录" } else { Info ("任务目录数: " + $tc) "请在客户端「定时任务」中确认是否有高频任务在跑" }
} else {
    Ok "未发现 tasks 目录"
}

# ------------------------------------------------------------
Section "9. 实际服务错误日志、活动自动化与 MCP 认证重试"
# ------------------------------------------------------------
$logRoots = @((Join-Path $WBL 'logs'), (Join-Path $WB 'logs')) | Where-Object { Test-Path $_ }
$logFiles = @()
foreach ($root in $logRoots) {
    $logFiles += Get-ChildItem $root -Recurse -File -Include *.log,*.jsonl,*.txt -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 120
}
# 真实 API 响应只在 */sdk/conversations/*.log（与 .sh 版同口径）：项目会话日志会回显
# 你自己执行过的 grep 命令与文档文本，全量扫会把这些当成命中（实测 5/5 全是回显）。
# 注意 conversations 集必须独立全量枚举，不能从"最近 120 个文件"里筛——
# 历史事故日的文件不够新，会被 recency 截断漏掉，把"检索不到"误报成"未发生"。
$apiLogs = @()
foreach ($root in $logRoots) {
    $apiLogs += Get-ChildItem $root -Recurse -File -Filter *.log -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match 'sdk[/\\]conversations[/\\]' }
}
if ($apiLogs.Count -gt 0) { $logFiles = $apiLogs }
$real403 = 0; $real429 = 0; $newest403 = ''
foreach ($lf in $logFiles) {
    foreach ($ln in (Get-Content $lf.FullName -ErrorAction SilentlyContinue)) {
        if ($ln -match 'CREATE_ENTER|EB_SYNC_ADDED|BashTool|Sandbox|command=|title=') { continue }
        if ($ln -match '(?i)bizCode=11140|httpStatus=403|403 request illegal|refusal classified') {
            $real403++
            # 按天归因：真实 API 日志行以 ISO 时间戳开头；无时间戳行（夹具）保持空 = 按当前复发处理
            if ($ln -match '^[\[\s]*(\d{4}-\d{2}-\d{2})') { if ($Matches[1] -gt $newest403) { $newest403 = $Matches[1] } }
        }
        # 错误体在日志里常以嵌套 JSON 出现（引号前带反斜杠转义），模式同时匹配裸/转义两种形式
        if ($ln -match '(?i)exceeded retry limit.*429|status:\s*429|429 Too Many Requests|\\?"statusCode\\?":\s*429') { $real429++ }
    }
}
# 历史事故降级：最新命中在 2 天前（换号/修复前的旧账号风控期会在日志里停留数日），不算当前复发
$today403 = (Get-Date).ToString('yyyy-MM-dd'); $yday403 = (Get-Date).AddDays(-1).ToString('yyyy-MM-dd')
if ($real403 -gt 0 -and ($newest403 -eq '' -or $newest403 -ge $yday403)) {
    if ($newest403 -ne '') { Bad "实际日志命中 403/11140: $real403 条" "已排除用户标题与命令回显；最新 $newest403" }
    else { Bad "实际日志命中 403/11140: $real403 条" "已排除用户标题与命令回显" }
} elseif ($real403 -gt 0) {
    Mid "实际日志命中 403/11140: $real403 条（最新 $newest403，2 天前且其后无复发）" "历史事故记录（如换号前旧账号风控期），非当前复发"
} else { Ok "实际日志未命中结构化 403/11140" "" }
if ($real429 -gt 0) { Mid "实际日志命中 429/Too Many Requests: $real429 条" "不等于账号封禁，需结合 Retry-After/上游状态" } else { Ok "实际日志未命中结构化 429" "" }

$dbPath = if ($env:WB_DB_FILE) { $env:WB_DB_FILE } else { Join-Path $WB 'workbuddy.db' }
$activeAuto = $null
$py = Get-Command python -ErrorAction SilentlyContinue
if ($py -and (Test-Path $dbPath)) {
    $code = 'import sqlite3,sys; c=sqlite3.connect("file:"+sys.argv[1]+"?mode=ro",uri=True); print(c.execute("select count(*) from automations where status=''ACTIVE'' and deleted_at is null").fetchone()[0])'
    try { $activeAuto = (& $py.Source -c $code $dbPath 2>$null | Select-Object -Last 1).Trim() } catch { $activeAuto = $null }
}
if ($null -eq $activeAuto -or $activeAuto -eq '') { Info "无法读取活动自动化数量" "仅做本地只读检查" }
elseif ([int]$activeAuto -gt 0) { Mid ("活动自动化数量: " + $activeAuto) "请确认频率、模型与失败重试策略" }
else { Ok "活动自动化数量: 0" "" }

Info "MCP 认证检测在本 .ps1 简化版中略去" "全局计数口径会把内置插件/官方网关连接器的预期 422 误报成高危；精确分类请跑 workbuddy-risk-selfcheck.sh"

# ------------------------------------------------------------
Section "汇总"
# ------------------------------------------------------------
W ("  高危项: " + $riskHigh)
W ("  注意项: " + $riskMid)
W ("  正常项: " + $passCount)
W ""
if ($riskHigh -gt 0) {
    W "  >>> 存在高危项，请优先处理上面标 [高危] 的条目。"
} elseif ($riskMid -gt 0) {
    W "  >>> 无高危项，有若干注意项，建议按提示逐条确认。"
} else {
    W "  >>> 全部检查通过，环境干净。"
}
W ""
W "  提示：本脚本只读检测，不修改任何文件。"
W "  官方申诉/反馈：客户端 帮助 -> helpFeedback；邮箱 workbuddy_ai@tencent.com"
W ""

$report = $lines -join "`r`n"
Write-Output $report

if (-not $NoFile) {
    if ($OutFile -eq "") { $OutFile = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'selfcheck-report-ps1.txt' }
    try { $report | Out-File -FilePath $OutFile -Encoding UTF8; Write-Output ("报告已写入: " + $OutFile) } catch { }
}
