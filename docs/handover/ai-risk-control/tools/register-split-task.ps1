# register-split-task.ps1 -- register the ag-split egress splitter + its watchdog
# ASCII-only on purpose (avoid encoding issues on zh-CN Windows).
#
# Why two tasks:
#   AgSplitEgress  -- runs the splitter core (long-lived process).
#   AgSplitWatchdog -- every 3 min runs ensure-split.ps1, which
#                      (a) restarts the splitter if it died, and
#                      (b) reverts the system proxy if the splitter cannot come back.
#                      Without (b), a dead splitter + system-proxy-pointing-at-it
#                      means the whole machine loses internet.
#
# Background facts learned the hard way (2026-10-01):
#   * This machine has Fast Startup (HiberbootEnabled=1): Startup-folder shortcuts
#     are NOT executed on a hybrid-shutdown resume -> a scheduled task is required.
#   * v2rayN, when it starts/updates, kills old core processes BY IMAGE NAME.
#     A splitter core literally named "xray.exe" gets killed with it.
#     -> the splitter uses a renamed copy: ag-split\ag-split-core.exe
#   * Registering a task requires Interactive + Limited when not elevated;
#     S4U / Highest / ServiceAccount are rejected with "Access denied".
#   * 2026-10-04: both tasks upgraded to S4U (elevated registration) so the
#     watchdog console no longer flashes every 3 min and the core console is
#     not visible at all (closing it used to kill the splitter). S4U trade-offs:
#     core access log no longer visible live (use ensure-split.log and
#     ag-split-live-acceptance.ps1 instead), and WM_SETTINGCHANGE broadcast
#     from the watchdog reaches no interactive window (persistent env/proxy
#     registry writes still land in the real user hive while logged on).

$ErrorActionPreference = 'Continue'

$XRAY  = 'D:\TOOL\v2rayN\ag-split\ag-split-core.exe'
$CFG   = 'D:\TOOL\v2rayN\ag-split\config.json'
$WD    = 'D:\TOOL\v2rayN'
$TASK  = 'AgSplitEgress'
$WATCH = 'AgSplitWatchdog'
$ENSURE= 'D:\TOOL\v2rayN\ag-split\ensure-split.ps1'
$PWSH  = 'C:\Program Files\PowerShell\7\pwsh.exe'
$OUT   = 'D:\TOOL\v2rayN\ag-split\register-split-task.log'

function Say($m) { "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))  $m" | Out-File -Append -Encoding utf8 $OUT }

Say '===== register-split-task start ====='

foreach ($p in @($XRAY, $CFG, $ENSURE, $PWSH)) {
    if (-not (Test-Path $p)) { Say "ERROR: missing $p"; exit 1 }
}

# S4U ("run whether logged on or not", no stored password) runs both tasks in a
# non-interactive session: no per-3-min console flash, no visible core console.
# It needs an elevated shell; fall back to Interactive when not elevated
# (the pre-2026-10-04 behavior).
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $logonType = 'S4U'
} else {
    $logonType = 'Interactive'
    Say 'WARNING: not elevated -> Interactive registration (console will flash); re-run elevated for S4U'
}
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType $logonType -RunLevel Limited
$logon     = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

# ---------- 1. splitter core ----------
$actSplit = New-ScheduledTaskAction -Execute $XRAY -Argument ('run -c "{0}"' -f $CFG) -WorkingDirectory $WD
$setSplit = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Seconds 0) `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

Get-ScheduledTask -TaskName $TASK -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
try {
    Register-ScheduledTask -TaskName $TASK -Action $actSplit -Trigger $logon -Settings $setSplit -Principal $principal `
        -Description 'ag-split egress splitter core (Google -> clean exit, rest -> v2rayN)' -ErrorAction Stop | Out-Null
    Say "registered: $TASK"
} catch { Say "REGISTER FAILED ($TASK): $($_.Exception.Message)"; exit 1 }

# ---------- 2. watchdog ----------
$actWatch = New-ScheduledTaskAction -Execute $PWSH `
    -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Quiet -NoEgressProbe' -f $ENSURE)
$trigWatch = New-ScheduledTaskTrigger -Once -At (Get-Date).Date.AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes 3) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

Get-ScheduledTask -TaskName $WATCH -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
try {
    Register-ScheduledTask -TaskName $WATCH -Action $actWatch -Trigger @($logon, $trigWatch) -Settings $setSplit -Principal $principal `
        -Description 'ag-split watchdog: restart splitter, revert system proxy if it stays down' -ErrorAction Stop | Out-Null
    Say "registered: $WATCH (every 3 min + at logon)"
} catch { Say "REGISTER FAILED ($WATCH): $($_.Exception.Message)" }

# ---------- 3. report ----------
foreach ($n in @($TASK, $WATCH)) {
    $t = Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue
    if ($t) {
        Say ("{0}: state={1} triggers={2} principal={3}/{4}" -f $n, $t.State, $t.Triggers.Count, $t.Principal.UserId, $t.Principal.LogonType)
        Say ("    action: {0} {1}" -f $t.Actions[0].Execute, $t.Actions[0].Arguments)
    } else {
        Say ("{0}: NOT FOUND" -f $n)
    }
}
Say '===== register-split-task done ====='
