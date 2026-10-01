# register-task.ps1 —— 注册/更新「Antigravity 补丁自愈」计划任务（幂等）
#
# 本脚本是计划任务的唯一真值来源。改了 ensure-patches.ps1 的路径或参数后，
# 重新运行本脚本即可把任务更新到位。
#
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File D:\TOOL\antigravity-ensure\register-task.ps1
#
# 回滚：
#   Unregister-ScheduledTask -TaskName 'AntigravityPatchesAutoRestore' -Confirm:$false
#
# 说明：本任务取代旧的 AntigravityProxyAutoRestore（那个只恢复代理，不含汉化）。
#       注册时会一并注销旧任务，避免两套机制并存。

$ErrorActionPreference = 'Stop'

# ============ 可按需修改 ============
# 轮询间隔（分钟）。改完重新运行本脚本即可生效。
# 说明：这个轮询只在 Antigravity 未运行时才能补汉化（要独占 app.asar），
#       而 Antigravity 更新后通常是「秒级重启」，任何间隔都抓不到那个窗口。
#       所以它真正起作用的时机是「Antigravity 关闭后」——间隔越小收益越有限。
#       30 分钟已足够；在意响应速度可以调到 15，不在意可以调到 60。
$IntervalMinutes = 30
# ====================================

$taskName = 'AntigravityPatchesAutoRestore'
$oldTask  = 'AntigravityProxyAutoRestore'
$script   = 'D:\TOOL\antigravity-ensure\ensure-patches.ps1'
$user     = "$env:USERDOMAIN\$env:USERNAME"

if (-not (Test-Path $script)) { throw "找不到 $script" }

# 优先 PowerShell 7，回退 5.1
$exe = 'C:\Program Files\PowerShell\7\pwsh.exe'
if (-not (Test-Path $exe)) { $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }

$action = New-ScheduledTaskAction -Execute $exe `
    -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Quiet' -f $script)

# 周期轮询 + 登录时跑一次（登录触发覆盖重启场景）
$tOnce  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)
$tLogon = New-ScheduledTaskTrigger -AtLogOn -User $user

$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

$desc = "Antigravity 自动更新会清掉代理劫持(version.dll/config.json)与汉化(app.asar)。本任务每 $IntervalMinutes 分钟 + 登录时调用 ensure-patches.ps1 幂等自愈。回滚: Unregister-ScheduledTask -TaskName AntigravityPatchesAutoRestore"

# 注销同名旧任务与旧的代理专用任务
foreach ($n in @($taskName, $oldTask)) {
    $existing = Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $n -Confirm:$false
        Write-Host "已注销旧任务: $n"
    }
}

$registered = $false
foreach ($logonType in 'S4U', 'Interactive') {
    try {
        $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType $logonType -RunLevel Limited
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $tOnce, $tLogon `
            -Principal $principal -Settings $settings -Description $desc -ErrorAction Stop | Out-Null
        Write-Host "注册成功 (LogonType=$logonType)"
        $registered = $true
        break
    } catch {
        Write-Host "$logonType 失败: $($_.Exception.Message.Trim())"
    }
}
if (-not $registered) { throw 'S4U 与 Interactive 两种登录类型均注册失败' }

$t = Get-ScheduledTask -TaskName $taskName
Write-Host "State=$($t.State)  LogonType=$($t.Principal.LogonType)  User=$($t.Principal.UserId)"
foreach ($tr in $t.Triggers) {
    Write-Host ("Trigger: {0} rep={1}" -f $tr.CimClass.CimClassName, $tr.Repetition.Interval)
}
Write-Host "Action : $($t.Actions[0].Execute)"
Write-Host "Args   : $($t.Actions[0].Arguments)"
