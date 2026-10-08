param(
    [string]$ConfigPath = 'D:\TOOL\v2rayN\ag-split\config.json',
    [string]$CorePath = 'D:\TOOL\v2rayN\ag-split\ag-split-core.exe'
)

$ErrorActionPreference = 'Stop'
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$googleRules = @($config.routing.rules | Where-Object { @($_.domain) -contains 'domain:googleapis.com' })
if ($googleRules.Count -ne 1) { throw '无法确定唯一 Google 出站规则' }
$googleOutbounds = @($config.outbounds | Where-Object { $_.tag -eq $googleRules[0].outboundTag })
if ($googleOutbounds.Count -ne 1) { throw '无法确定唯一 Google 出站配置' }

$reservation = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$reservation.Start()
$probePort = $reservation.LocalEndpoint.Port
$reservation.Stop()
$probeRoot = Join-Path $env:TEMP ('ag-egress-probe-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $probeRoot
$probeProcess = $null

try {
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().User
    foreach ($principal in @($currentUser, [Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            $principal, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
    }
    Set-Acl -LiteralPath $probeRoot -AclObject $acl
    $probeConfigPath = Join-Path $probeRoot 'config.json'
    $probeConfig = @{
        log = @{ loglevel = 'none' }
        dns = $config.dns
        inbounds = @(@{
            tag = 'probe'; listen = '127.0.0.1'; port = $probePort
            protocol = 'http'; settings = @{}
        })
        outbounds = $googleOutbounds
    }
    $probeConfig | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $probeConfigPath -Encoding utf8NoBOM
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $CorePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @('run', '-c', $probeConfigPath)) { $startInfo.ArgumentList.Add($argument) }
    $probeProcess = [Diagnostics.Process]::Start($startInfo)
    $stdoutRead = $probeProcess.StandardOutput.ReadToEndAsync()
    $stderrRead = $probeProcess.StandardError.ReadToEndAsync()
    $ready = $false
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        if ($probeProcess.HasExited) { throw '临时出口探针启动失败' }
        $connections = @(Get-NetTCPConnection -LocalPort $probePort -State Listen -ErrorAction SilentlyContinue)
        if ($connections.Count -gt 0 -and @($connections | Where-Object { $_.OwningProcess -ne $probeProcess.Id -or $_.LocalAddress -ne '127.0.0.1' }).Count -eq 0) {
            $ready = $true
            break
        }
        Start-Sleep -Milliseconds 400
    }
    if (-not $ready) { throw '临时出口探针未就绪' }
    $response = & curl.exe -fsS -m 20 --noproxy "" -x "http://127.0.0.1:$probePort" 'http://ip-api.com/json/?fields=status,query,country,isp,hosting,proxy' 2>$null
    $probeExit = $LASTEXITCODE
    if ($probeExit -ne 0) {
        # curl exit 28 = operation timed out: the node could not reach ip-api.com
        # within 20s, i.e. the candidate egress itself is likely unusable.
        if ($probeExit -eq 28) { throw '出口属性查询超时（curl exit 28）：经该节点 20s 内无法到达 ip-api.com，节点出口大概率不可用，不能作为干净出口候选' }
        throw "出口属性查询失败 exit=$probeExit"
    }
    $result = $response | ConvertFrom-Json
    $exitAddress = $null
    if ($result.status -ne 'success' -or -not [Net.IPAddress]::TryParse([string]$result.query, [ref]$exitAddress) -or
        $result.hosting -isnot [bool] -or $result.proxy -isnot [bool]) {
        throw '出口属性查询返回无效结果'
    }
    [pscustomobject]@{
        ExitIp = $result.query
        Country = $result.country
        Isp = $result.isp
        Hosting = $result.hosting
        Proxy = $result.proxy
        ConfigHash = (Get-FileHash -LiteralPath $ConfigPath -Algorithm SHA256).Hash
        Evidence = 'isolated_node_probe; third_party_classification; not_account_acceptance'
    }
}
finally {
    if ($probeProcess) {
        if (-not $probeProcess.HasExited) { $probeProcess.Kill() }
        $probeProcess.WaitForExit()
        $probeProcess.Dispose()
    }
    $probeDirectory = Get-Item -LiteralPath $probeRoot
    if ($probeDirectory.Parent.FullName -eq [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') -and
        -not ($probeDirectory.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Remove-Item -LiteralPath $probeRoot -Recurse -Force
    }
}
