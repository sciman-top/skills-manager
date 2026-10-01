# wire-split.ps1 —— 把系统前门（系统代理 + 用户级代理环境变量）接到 ag-split 分流器
# 一次性执行；执行后所有联网软件都先到 127.0.0.1:10810，
# Google 系域名走干净出口，其余原样走 v2rayN（原线路）。
#
# 【换机器前必读】下面的路径与端口按本机实际修改：
#   - 分流器配置路径   D:\TOOL\v2rayN\ag-split\config.json
#   - xray 可执行文件  D:\TOOL\v2rayN\bin\xray\xray.exe
#   - 分流器端口       10810（必须与 gen-config.py 的 AG_SPLIT_PORT 一致）
# 注意：脚本会广播 WM_SETTINGCHANGE，让新启动的进程立刻看到新环境变量。

$ErrorActionPreference = 'Continue'
$log = @()

# 1) 用户级代理环境变量 -> 分流器
$envs = [ordered]@{
    'HTTP_PROXY'  = 'http://127.0.0.1:10810'
    'HTTPS_PROXY' = 'http://127.0.0.1:10810'
    'ALL_PROXY'   = 'socks5h://127.0.0.1:10810'
}
foreach ($k in $envs.Keys) {
    [Environment]::SetEnvironmentVariable($k, $envs[$k], 'User')
    $log += "env  $k = $($envs[$k])"
}

# 2) 系统代理 -> 分流器（例外表保持不动）
$is = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
Set-ItemProperty -Path $is -Name ProxyEnable -Value 1     -Type DWord
Set-ItemProperty -Path $is -Name ProxyServer -Value '127.0.0.1:10810' -Type String
$k = Get-ItemProperty -Path $is
$log += "sys  ProxyEnable=$($k.ProxyEnable) ProxyServer=$($k.ProxyServer)"

# 3) 广播 WM_SETTINGCHANGE，让新启动的进程立即看到新的环境变量
try {
    Add-Type -Namespace AgSplit -Name Native -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@ -ErrorAction Stop
    $res = [UIntPtr]::Zero
    [void][AgSplit.Native]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$res)
    $log += 'broadcast WM_SETTINGCHANGE ok'
} catch {
    $log += "broadcast failed: $($_.Exception.Message)"
}

# 4) 开机自启：Startup 文件夹放一个指向 xray 的快捷方式
try {
    $startup = [Environment]::GetFolderPath('Startup')
    $lnkPath = Join-Path $startup 'ag-split.lnk'
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($lnkPath)
    $sc.TargetPath       = 'D:\TOOL\v2rayN\bin\xray\xray.exe'
    $sc.Arguments        = 'run -c "D:\TOOL\v2rayN\ag-split\config.json"'
    $sc.WorkingDirectory = 'D:\TOOL\v2rayN'
    $sc.WindowStyle      = 7
    $sc.Description      = 'Antigravity Google-only egress splitter'
    $sc.Save()
    $log += "startup lnk -> $lnkPath"
} catch {
    $log += "startup lnk failed: $($_.Exception.Message)"
}

$log | Out-File -Encoding utf8 'D:\CODE\skills-manager\artifacts\work\agdiag\wire.txt'
'wire done'
