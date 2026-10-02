# ensure-split.test.ps1 —— ag-split 分流器自愈脚本「受控验收」
#
# 原理：为每个判定分支注入一个「已知状态」的夹具（临时目录 + 临时注册表键 +
#       可控端口的监听/不监听），运行被测脚本，断言它报出预期结论。
#       夹具全部建在临时目录/临时注册表键，**不触碰真实系统代理、真实环境变量、真实任务**。
#
# 用法：
#   pwsh -NoProfile -ExecutionPolicy Bypass -File D:\TOOL\v2rayN\ag-split\ensure-split.test.ps1
# 退出码：0 = 全部通过；1 = 有失败

$ErrorActionPreference = 'Continue'

$HERE   = Split-Path -Parent $MyInvocation.MyCommand.Path
$TARGET = Join-Path $HERE 'ensure-split.ps1'
$PWSH   = 'C:\Program Files\PowerShell\7\pwsh.exe'
$TMP    = Join-Path $env:TEMP ('nova-agsplit-test-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $TMP | Out-Null

$script:PASS = 0
$script:FAIL = 0
$script:REGS = @()   # 需要在结束时清理的临时注册表键

# 完整例外表（含全部必需域名）
$EXC_OK  = '<local>;localhost;127.*;10.*;192.168.*;*.workbuddy.ai;*.codebuddy.ai;*.lkeap.cloud.tencent.com;*.workbuddy.cn;*.codebuddy.cn'
# 缺 *.workbuddy.ai
$EXC_BAD = '<local>;localhost;127.*;10.*;192.168.*;*.codebuddy.ai;*.lkeap.cloud.tencent.com;*.workbuddy.cn;*.codebuddy.cn'

# ---------- 夹具 ----------
function New-Fixture {
    param([string]$Name, [string]$ProxyServer, [string]$ProxyOverride = $EXC_OK, [int]$ProxyEnable = 1)
    $d = Join-Path $TMP $Name
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    Set-Content -Path (Join-Path $d 'fake-core.exe') -Value 'stub' -Encoding ASCII
    Set-Content -Path (Join-Path $d 'config.json')   -Value '{}'    -Encoding ASCII

    $rk = "HKCU:\Software\_nova_agsplit_test_$Name"
    Remove-Item -Path $rk -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -Path $rk -Force | Out-Null
    New-ItemProperty -Path $rk -Name ProxyEnable   -Value $ProxyEnable  -PropertyType DWord  -Force | Out-Null
    New-ItemProperty -Path $rk -Name ProxyServer   -Value $ProxyServer  -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $rk -Name ProxyOverride -Value $ProxyOverride -PropertyType String -Force | Out-Null
    $script:REGS += $rk
    return @{ Dir = $d; RegKey = $rk; CorePath = (Get-Process -Id $PID).Path }
}

# 取一个「确定没人监听」的端口
function Get-FreePort {
    $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $l.Start()
    $p = ([System.Net.IPEndPoint]$l.LocalEndpoint).Port
    $l.Stop()
    Start-Sleep -Milliseconds 120
    return $p
}

# ---------- 断言 ----------
function Run-Case {
    param(
        [string]$Name,
        [string]$Expect,
        [hashtable]$Fx,
        [int]$Port,
        [string[]]$Extra = @(),
        [int]$ExpectExit = -1,          # -1 = 不断言
        [string]$ExpectRegProxy = '',   # 非空则断言注册表里的 ProxyServer
        [switch]$PresetEnv              # 先在测试进程里把 env 设成目标值（子进程继承）
    )
    $a = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $TARGET,
           '-XrayPath',    $Fx.CorePath,
           '-TaskName',    ('AgSplitFixture-' + [IO.Path]::GetFileName($TMP)),
           '-ConfigPath',  (Join-Path $Fx.Dir 'config.json'),
           '-WorkDir',     $Fx.Dir,
           '-Port',        "$Port",
           '-ProxyRegPath', $Fx.RegKey,
           '-LogPath',     (Join-Path $Fx.Dir 'run.log'),
           '-BackupPath',  (Join-Path $Fx.Dir 'bak.json'),
           '-EnvScope',    'Process',
           '-NoStart', '-NoEgressProbe', '-NoStartupLnk') + $Extra

    # 子进程继承本进程的环境变量；-EnvScope Process 读到的就是这些值
    $saved = @{}
    if ($PresetEnv) {
        foreach ($k in 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY') { $saved[$k] = [Environment]::GetEnvironmentVariable($k, 'Process') }
        $env:HTTP_PROXY  = "http://127.0.0.1:$Port"
        $env:HTTPS_PROXY = "http://127.0.0.1:$Port"
        $env:ALL_PROXY   = "socks5h://127.0.0.1:$Port"
    }

    $out = (& $PWSH @a 2>&1 | Out-String)
    $rc  = $LASTEXITCODE

    if ($PresetEnv) {
        foreach ($k in $saved.Keys) {
            if ($null -eq $saved[$k]) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable($k, $saved[$k], 'Process') }
        }
    }

    $ok = $out.Contains($Expect)

    if ($ok -and $ExpectExit -ge 0 -and $rc -ne $ExpectExit) {
        $ok = $false
        $Expect = "$Expect 且 exit=$ExpectExit（实得 $rc）"
    }
    if ($ok -and $ExpectRegProxy -ne '') {
        $got = (Get-ItemProperty -Path $Fx.RegKey -ErrorAction SilentlyContinue).ProxyServer
        if ($got -ne $ExpectRegProxy) {
            $ok = $false
            $Expect = "$Expect 且 注册表=$ExpectRegProxy（实得 '$got'）"
        }
    }

    if ($ok) {
        Write-Host ('  [PASS] {0,-40} -> {1}' -f $Name, $Expect) -ForegroundColor Green
        $script:PASS++
    } else {
        Write-Host ('  [FAIL] {0,-40} 期望: {1}' -f $Name, $Expect) -ForegroundColor Red
        $script:FAIL++
        ($out -split "`n" | Select-Object -First 14) | ForEach-Object { Write-Host ('         | ' + $_.TrimEnd()) -ForegroundColor DarkGray }
    }
}

function Section($t) { Write-Host ''; Write-Host $t -ForegroundColor Cyan }

# ============================================================
Write-Host '============================================================'
Write-Host '  ag-split 自愈脚本 · 受控验收'
Write-Host ("  时间: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Write-Host ("  被测: {0}" -f $TARGET)
Write-Host '============================================================'

# 准备一个真实监听端口（模拟「分流器在跑」）
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$PORT_UP   = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
$PORT_DOWN = Get-FreePort

Write-Host ("  夹具端口: 在跑=$PORT_UP  不在=$PORT_DOWN")

# ---------------- 分支 1：分流器在跑 ----------------
Section '分支 1 · 分流器在跑'

$fx = New-Fixture 'b1_wrong' "127.0.0.1:$PORT_DOWN"
Run-Case '在跑 + 代理指向别处' '系统代理 已设为: 127.0.0.1:' $fx $PORT_UP @() 0 ("127.0.0.1:$PORT_UP")

$fx = New-Fixture 'b1_ok' "127.0.0.1:$PORT_UP"
Run-Case '在跑 + 代理已正确' '系统代理 OK' $fx $PORT_UP @() 0

$fx = New-Fixture 'b1_exc_ok' "127.0.0.1:$PORT_UP" $EXC_OK
Run-Case '在跑 + 例外表完整' '系统代理例外表 OK' $fx $PORT_UP @() 0

$fx = New-Fixture 'b1_exc_bad' "127.0.0.1:$PORT_UP" $EXC_BAD
Run-Case '在跑 + 例外表缺 workbuddy' '警告：系统代理例外表缺少' $fx $PORT_UP @() 1

$fx = New-Fixture 'b1_disabled' "127.0.0.1:$PORT_DOWN" $EXC_OK 0
Run-Case '在跑 + 代理被禁用(ProxyEnable=0)' '系统代理 已设为: 127.0.0.1:' $fx $PORT_UP @() 0 ("127.0.0.1:$PORT_UP")

# ---------------- 分支 2：分流器不在（含安全阀）----------------
Section '分支 2 · 分流器不在 —— 安全阀'

$fx = New-Fixture 'b2_valve' "127.0.0.1:$PORT_DOWN"
Run-Case '不在 + 代理指向它【安全阀回退】' '系统代理 已回退' $fx $PORT_DOWN @() 1 '127.0.0.1:10808'

$fx = New-Fixture 'b2_valve_custom' "127.0.0.1:$PORT_DOWN"
Run-Case '不在 + 回退目标可覆盖' '系统代理 已回退' $fx $PORT_DOWN @('-FallbackProxy', '127.0.0.1:19999') 1 '127.0.0.1:19999'

$fx = New-Fixture 'b2_other' '127.0.0.1:18080'
Run-Case '不在 + 代理指向第三方' '系统代理 保持' $fx $PORT_DOWN @() 1 '127.0.0.1:18080'

# ---------------- 分支 3：前置校验 ----------------
Section '分支 3 · 前置校验'

$fx = New-Fixture 'b3_nocore' "127.0.0.1:$PORT_UP"
$fx.CorePath = Join-Path $fx.Dir 'fake-core.exe'
Remove-Item (Join-Path $fx.Dir 'fake-core.exe') -Force -ErrorAction SilentlyContinue
Run-Case '缺少内核文件' '错误：缺少' $fx $PORT_UP @() 1

$fx = New-Fixture 'b3_nocfg' "127.0.0.1:$PORT_UP"
Remove-Item (Join-Path $fx.Dir 'config.json') -Force -ErrorAction SilentlyContinue
Run-Case '缺少配置文件' '错误：缺少' $fx $PORT_UP @() 1

# ---------------- 分支 4：环境变量 ----------------
Section '分支 4 · 代理环境变量'

$fx = New-Fixture 'b4_env' "127.0.0.1:$PORT_UP"
Run-Case 'env 已正确' 'env OK: HTTP_PROXY' $fx $PORT_UP @() 0 -PresetEnv

$fx = New-Fixture 'b4_env_fix' "127.0.0.1:$PORT_UP"
Run-Case 'env 值不对 -> 被修正' 'env 已修正: HTTP_PROXY' $fx $PORT_UP @() 0

$fx = New-Fixture 'b4_skip' "127.0.0.1:$PORT_UP"
Run-Case 'NoEnvWrite 时跳过' 'env 检查已跳过' $fx $PORT_UP @('-NoEnvWrite') 0

$fx = New-Fixture 'b4_down' "127.0.0.1:$PORT_DOWN"
Run-Case '分流器失效时不覆盖环境变量' 'env 写入已跳过：分流器未就绪' $fx $PORT_DOWN @() 1 '127.0.0.1:10808'

# ---------------- 分支 5：备份与开关 ----------------
Section '分支 5 · 备份与开关'

$fx = New-Fixture 'b5_bak' "127.0.0.1:$PORT_UP"
Run-Case '首次运行写备份' '已备份原始代理设置' $fx $PORT_UP @() 0
if (Test-Path (Join-Path $fx.Dir 'bak.json')) {
    Write-Host '  [PASS] 备份文件确实落盘' -ForegroundColor Green; $script:PASS++
} else {
    Write-Host '  [FAIL] 备份文件确实落盘' -ForegroundColor Red; $script:FAIL++
}

$fx = New-Fixture 'b5_noprobe' "127.0.0.1:$PORT_UP"
Run-Case 'NoEgressProbe 时跳过探测' '出口探测已跳过' $fx $PORT_UP @() 0

Section '分支 6 · 监听者身份'
$fx = New-Fixture 'b6_wrong_owner' "127.0.0.1:$PORT_UP"
$fx.CorePath = Join-Path $fx.Dir 'fake-core.exe'
Run-Case '端口已开但程序路径不符' 'wrong_listener_owner' $fx $PORT_UP @() 1 ("127.0.0.1:$PORT_UP")
if (-not (Test-Path (Join-Path $fx.Dir 'bak.json'))) {
    Write-Host '  [PASS] 身份不符时未进入配置写入' -ForegroundColor Green; $script:PASS++
} else {
    Write-Host '  [FAIL] 身份不符时发生配置写入' -ForegroundColor Red; $script:FAIL++
}

$parseTokens = $null
$parseErrors = $null
$targetAst = [Management.Automation.Language.Parser]::ParseFile($TARGET, [ref]$parseTokens, [ref]$parseErrors)
$taskFunction = $targetAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-SplitTaskAction' }, $true)
. ([scriptblock]::Create($taskFunction.Extent.Text))
$validAction = [pscustomobject]@{ Execute = $PWSH; Arguments = 'run -c "fixture.json"' }
$wrongAction = [pscustomobject]@{ Execute = $PWSH; Arguments = 'run -c "other.json"' }
foreach ($taskCase in @(
    @{ Name = '正确任务动作'; Actions = @($validAction); Expected = $true },
    @{ Name = '错误配置参数'; Actions = @($wrongAction); Expected = $false },
    @{ Name = '无任务动作'; Actions = @(); Expected = $false },
    @{ Name = '多个任务动作'; Actions = @($validAction, $wrongAction); Expected = $false }
)) {
    if ((Test-SplitTaskAction $taskCase.Actions $PWSH 'fixture.json') -eq $taskCase.Expected) {
        Write-Host ("  [PASS] {0}" -f $taskCase.Name) -ForegroundColor Green; $script:PASS++
    } else {
        Write-Host ("  [FAIL] {0}" -f $taskCase.Name) -ForegroundColor Red; $script:FAIL++
    }
}

# ---------------- 汇总 ----------------
$listener.Stop()

Write-Host ''
Write-Host '============================================================'
if ($script:FAIL -eq 0) {
    Write-Host ("  受控验收结果: PASS {0} / FAIL {1}" -f $script:PASS, $script:FAIL) -ForegroundColor Green
} else {
    Write-Host ("  受控验收结果: PASS {0} / FAIL {1}" -f $script:PASS, $script:FAIL) -ForegroundColor Red
}
Write-Host '============================================================'

# 清理
foreach ($rk in $script:REGS) { Remove-Item -Path $rk -Recurse -Force -ErrorAction SilentlyContinue }
Remove-Item -Path $TMP -Recurse -Force -ErrorAction SilentlyContinue

if ($script:FAIL -eq 0) { exit 0 } else { exit 1 }
