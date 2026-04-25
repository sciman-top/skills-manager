function Parse-KeyValueToken([string]$token, [string]$flagName) {
    Need (-not [string]::IsNullOrWhiteSpace($token)) ("{0} 参数不能为空" -f $flagName)
    $pair = $token.Split("=", 2)
    Need ($pair.Count -eq 2) ("{0} 参数格式必须是 KEY=VALUE：{1}" -f $flagName, $token)
    $key = $pair[0].Trim()
    Need (-not [string]::IsNullOrWhiteSpace($key)) ("{0} 参数的 KEY 不能为空：{1}" -f $flagName, $token)
    return [pscustomobject]@{
        key = $key
        value = $pair[1]
    }
}

function Normalize-McpProcessArgs([string[]]$processArgs) {
    $normalized = New-Object System.Collections.Generic.List[string]
    if ($null -eq $processArgs) { return @() }
    for ($i = 0; $i -lt $processArgs.Count; $i++) {
        $t = [string]$processArgs[$i]
        if ($t -eq "--arg") {
            if ($i + 1 -lt $processArgs.Count) {
                $normalized.Add([string]$processArgs[++$i]) | Out-Null
            }
            continue
        }
        if ($t.ToLowerInvariant().StartsWith("--arg=")) {
            $normalized.Add($t.Substring(6)) | Out-Null
            continue
        }
        $normalized.Add($t) | Out-Null
    }
    return $normalized.ToArray()
}

function Get-StableHashSuffix([string]$seed, [int]$len = 10) {
    if ([string]::IsNullOrWhiteSpace($seed)) { return $null }
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($seed)
        $hashBytes = $sha1.ComputeHash($bytes)
        $hex = ([System.BitConverter]::ToString($hashBytes)).Replace("-", "").ToLowerInvariant()
        if ($len -le 0) { return $hex }
        if ($hex.Length -le $len) { return $hex }
        return $hex.Substring(0, $len)
    }
    finally {
        $sha1.Dispose()
    }
}

function Normalize-McpServiceNameWithFallback([string]$name, [string]$fallbackSeed = $null) {
    $norm = Normalize-Name $name
    if (-not [string]::IsNullOrWhiteSpace($norm)) { return $norm }

    $seed = $null
    if (-not [string]::IsNullOrWhiteSpace($fallbackSeed)) {
        $seed = $fallbackSeed
    }
    elseif (-not [string]::IsNullOrWhiteSpace($name)) {
        $seed = $name
    }

    if (-not [string]::IsNullOrWhiteSpace($seed)) {
        $suffix = Get-StableHashSuffix $seed 10
        if (-not [string]::IsNullOrWhiteSpace($suffix)) {
            $autoName = "mcp-{0}" -f $suffix
            Write-Host ("MCP 服务名无法规范化，已自动生成：{0} -> {1}" -f $name, $autoName) -ForegroundColor Yellow
            return $autoName
        }
    }

    Need $false ("MCP 服务名 无法规范化，请更换名称：{0}" -f $name)
    return $null
}

function Parse-McpStdioCommandLine([string]$name, [string]$commandLine) {
    $tokens = Split-Args $commandLine
    $tokens = Normalize-McpProcessArgs @($tokens)
    Need ($tokens.Count -gt 0) ("MCP 服务命令不能为空：{0}" -f $name)
    return [pscustomobject]@{
        command = [string]$tokens[0]
        args = if ($tokens.Count -gt 1) { @($tokens[1..($tokens.Count - 1)]) } else { @() }
    }
}

function Parse-McpInstallArgs([string[]]$tokens) {
    Need ($tokens -and $tokens.Count -gt 0) "缺少 MCP 服务参数。示例：安装MCP context7 --cmd npx -- -y @upstash/context7-mcp"
    $result = [ordered]@{
        name = $null
        transport = "stdio"
        command = $null
        args = @()
        url = $null
        env = @{}
        headers = @{}
        bearer_token_env_var = $null
    }
    $collectProcessArgs = $false

    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $t = $tokens[$i]
        if ($t -eq "--") {
            if ($i + 1 -lt $tokens.Count) {
                $result.args += $tokens[($i + 1)..($tokens.Count - 1)]
            }
            break
        }

        if ($collectProcessArgs) {
            $result.args += $t
            continue
        }

        if (-not $t.StartsWith("-")) {
            if (-not $result.name) {
                $result.name = $t
                continue
            }
            # Backward compatible: allow "name <cmd> <args...>" without --cmd or "--".
            if ($result.transport -eq "stdio" -and [string]::IsNullOrWhiteSpace($result.command) -and [string]::IsNullOrWhiteSpace($result.url)) {
                $collectProcessArgs = $true
                $result.args += $t
                continue
            }
            $result.args += $t
            continue
        }

        $key = $t.ToLowerInvariant()
        if ($key -eq "--transport" -or $key -eq "-t") {
            Need ($i + 1 -lt $tokens.Count) ("参数缺少值：{0}" -f $t)
            $nextVal = [string]$tokens[++$i]
            Need (-not $nextVal.StartsWith("-")) ("参数缺少值：{0}" -f $t)
            $result.transport = $nextVal
            continue
        }
        if ($key -eq "--cmd" -or $key -eq "--command") {
            Need ($i + 1 -lt $tokens.Count) ("参数缺少值：{0}" -f $t)
            $nextVal = [string]$tokens[++$i]
            Need (-not $nextVal.StartsWith("-")) ("参数缺少值：{0}" -f $t)
            $result.command = $nextVal
            continue
        }
        if ($key -eq "--url") {
            Need ($i + 1 -lt $tokens.Count) "参数缺少值：--url"
            $nextVal = [string]$tokens[++$i]
            Need (-not $nextVal.StartsWith("-")) "参数缺少值：--url"
            $result.url = $nextVal
            continue
        }
        if ($key -eq "--arg") {
            Need ($i + 1 -lt $tokens.Count) "参数缺少值：--arg"
            $result.args += $tokens[++$i]
            continue
        }
        if ($key -eq "--env") {
            Need ($i + 1 -lt $tokens.Count) "参数缺少值：--env"
            $pair = Parse-KeyValueToken $tokens[++$i] "--env"
            $result.env[$pair.key] = $pair.value
            continue
        }
        if ($key -eq "--header") {
            Need ($i + 1 -lt $tokens.Count) "参数缺少值：--header"
            $pair = Parse-KeyValueToken $tokens[++$i] "--header"
            $result.headers[$pair.key] = $pair.value
            continue
        }
        if ($key -eq "--bearer-token-env-var") {
            Need ($i + 1 -lt $tokens.Count) "参数缺少值：--bearer-token-env-var"
            $result.bearer_token_env_var = [string]$tokens[++$i]
            continue
        }

        # Backward compatible: in stdio mode, unknown options are treated as process
        # arguments so users can omit "--" (PowerShell may swallow the separator).
        if (-not [string]::IsNullOrWhiteSpace($result.name) -and $result.transport -eq "stdio" -and [string]::IsNullOrWhiteSpace($result.url)) {
            if (-not [string]::IsNullOrWhiteSpace($result.command)) {
                $result.args += $t
                continue
            }
            $collectProcessArgs = $true
            $result.args += $t
            continue
        }
        throw ("未知参数：{0}" -f $t)
    }

    Need (-not [string]::IsNullOrWhiteSpace($result.name)) "缺少 MCP 服务名称。示例：安装MCP context7 --cmd npx -- -y @upstash/context7-mcp"

    if (-not [string]::IsNullOrWhiteSpace($result.transport)) {
        $result.transport = $result.transport.Trim().ToLowerInvariant()
    }
    if ([string]::IsNullOrWhiteSpace($result.transport)) { $result.transport = "stdio" }
    Need (($result.transport -eq "stdio") -or ($result.transport -eq "sse") -or ($result.transport -eq "http")) "transport 仅支持 stdio/sse/http"

    if ($result.transport -eq "stdio") {
        $result.args = Normalize-McpProcessArgs @($result.args)
        if ([string]::IsNullOrWhiteSpace($result.command) -and $result.args.Count -gt 0) {
            $result.command = [string]$result.args[0]
            if ($result.args.Count -gt 1) {
                $result.args = $result.args[1..($result.args.Count - 1)]
            }
            else {
                $result.args = @()
            }
        }
        Need (-not [string]::IsNullOrWhiteSpace($result.command)) "stdio MCP 需要 --cmd/--command"
        if ($result.command.Contains(" ") -and $result.args.Count -eq 0) {
            $parts = Split-Args $result.command
            Need ($parts.Count -gt 0) "无法解析 --cmd 命令"
            $result.command = $parts[0]
            if ($parts.Count -gt 1) {
                $result.args = $parts[1..($parts.Count - 1)]
            }
        }
    }
    else {
        Need (-not [string]::IsNullOrWhiteSpace($result.url)) "sse/http MCP 需要 --url"
        if (-not [string]::IsNullOrWhiteSpace([string]$result.bearer_token_env_var)) {
            $result.bearer_token_env_var = [string]$result.bearer_token_env_var.Trim()
        }
    }

    $fallbackSeed = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$result.command)) {
        $fallbackSeed = [string]$result.command
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$result.url)) {
        $fallbackSeed = [string]$result.url
    }
    $result.name = Normalize-McpServiceNameWithFallback $result.name $fallbackSeed

    return [pscustomobject]$result
}

function Extract-McpTrailingDryRunToken([string[]]$tokens) {
    $list = @($tokens)
    if ($list.Count -eq 0) {
        return [pscustomobject]@{
            tokens = @()
            dry_run = $false
        }
    }
    $last = [string]$list[$list.Count - 1]
    $tail = $last.Trim().ToLowerInvariant()
    if ($tail -eq "-dryrun" -or $tail -eq "--dryrun" -or $tail -eq "--dry-run") {
        $trimmed = @()
        if ($list.Count -gt 1) {
            $trimmed = @($list[0..($list.Count - 2)])
        }
        return [pscustomobject]@{
            tokens = $trimmed
            dry_run = $true
        }
    }
    return [pscustomobject]@{
        tokens = $list
        dry_run = $false
    }
}

function New-McpServerObject($parsed) {
    $obj = [ordered]@{
        name = $parsed.name
        transport = $parsed.transport
    }
    if ($parsed.transport -eq "stdio") {
        $obj.command = $parsed.command
        $obj.args = @($parsed.args)
        if ($parsed.env.Count -gt 0) { $obj.env = $parsed.env }
    }
    else {
        $obj.url = $parsed.url
        if ($parsed.headers.Count -gt 0) { $obj.headers = $parsed.headers }
        if (-not [string]::IsNullOrWhiteSpace([string]$parsed.bearer_token_env_var)) {
            $obj.bearer_token_env_var = [string]$parsed.bearer_token_env_var
        }
    }
    return [pscustomobject]$obj
}

function Convert-McpServersToConfigMap($servers) {
    $map = [ordered]@{}
    if ($null -eq $servers) { return [pscustomobject]$map }

    foreach ($s in $servers) {
        if ([string]::IsNullOrWhiteSpace([string]$s.name)) { continue }
        $entry = [ordered]@{}
        $transport = if ([string]::IsNullOrWhiteSpace([string]$s.transport)) { "stdio" } else { [string]$s.transport }
        $entry.transport = $transport
        if ($transport -eq "stdio") {
            if (-not [string]::IsNullOrWhiteSpace([string]$s.command)) { $entry.command = [string]$s.command }
            if ($s.PSObject.Properties.Match("args").Count -gt 0 -and $s.args -ne $null) { $entry.args = @($s.args) }
            if ($s.PSObject.Properties.Match("env").Count -gt 0 -and $s.env -ne $null) { $entry.env = $s.env }
        }
        else {
            if ($s.PSObject.Properties.Match("url").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$s.url)) { $entry.url = [string]$s.url }
            if ($s.PSObject.Properties.Match("headers").Count -gt 0 -and $s.headers -ne $null) { $entry.headers = $s.headers }
            if ($s.PSObject.Properties.Match("bearer_token_env_var").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$s.bearer_token_env_var)) {
                $entry.bearer_token_env_var = [string]$s.bearer_token_env_var
            }
        }
        $map[[string]$s.name] = [pscustomobject]$entry
    }
    return [pscustomobject]$map
}

function Convert-McpServersToGeminiConfigMap($servers) {
    $map = [ordered]@{}
    if ($null -eq $servers) { return [pscustomobject]$map }

    foreach ($s in $servers) {
        if ([string]::IsNullOrWhiteSpace([string]$s.name)) { continue }
        $entry = [ordered]@{}
        $transport = if ([string]::IsNullOrWhiteSpace([string]$s.transport)) { "stdio" } else { ([string]$s.transport).Trim().ToLowerInvariant() }
        if ($transport -eq "stdio") {
            if (-not [string]::IsNullOrWhiteSpace([string]$s.command)) { $entry.command = [string]$s.command }
            if ($s.PSObject.Properties.Match("args").Count -gt 0 -and $s.args -ne $null) { $entry.args = @($s.args) }
            if ($s.PSObject.Properties.Match("env").Count -gt 0 -and $s.env -ne $null) { $entry.env = $s.env }
        }
        else {
            if ($s.PSObject.Properties.Match("url").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$s.url)) {
                if ($transport -eq "http") { $entry.httpUrl = [string]$s.url }
                else { $entry.url = [string]$s.url }
            }
            if ($s.PSObject.Properties.Match("headers").Count -gt 0 -and $s.headers -ne $null) { $entry.headers = $s.headers }
        }
        $map[[string]$s.name] = [pscustomobject]$entry
    }
    return [pscustomobject]$map
}

function Get-CodexMcpStartupTimeoutSec($server) {
    if ($null -eq $server) { return $null }
    if ($server.PSObject.Properties.Match("startup_timeout_sec").Count -eq 0) { return $null }

    $raw = $server.startup_timeout_sec
    if ($null -eq $raw -or [string]::IsNullOrWhiteSpace([string]$raw)) { return $null }

    $parsed = 0
    if (-not [int]::TryParse([string]$raw, [ref]$parsed) -or $parsed -lt 1) {
        Log ("mcp_server.startup_timeout_sec 无效，已忽略：{0}" -f [string]$server.name) "WARN"
        return $null
    }
    return [int]$parsed
}

function Convert-McpServersToCodexConfigMap($servers) {
    $map = [ordered]@{}
    if ($null -eq $servers) { return [pscustomobject]$map }

    foreach ($s in $servers) {
        if ([string]::IsNullOrWhiteSpace([string]$s.name)) { continue }
        $entry = [ordered]@{}
        $transport = if ([string]::IsNullOrWhiteSpace([string]$s.transport)) { "stdio" } else { [string]$s.transport }
        $entry.transport = $transport
        if ($transport -eq "stdio") {
            if (-not [string]::IsNullOrWhiteSpace([string]$s.command)) { $entry.command = [string]$s.command }
            if ($s.PSObject.Properties.Match("args").Count -gt 0 -and $s.args -ne $null) { $entry.args = @($s.args) }
            if ($s.PSObject.Properties.Match("env").Count -gt 0 -and $s.env -ne $null) { $entry.env = $s.env }
        }
        else {
            if ($s.PSObject.Properties.Match("url").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$s.url)) { $entry.url = [string]$s.url }
            if ($s.PSObject.Properties.Match("headers").Count -gt 0 -and $s.headers -ne $null) { $entry.headers = $s.headers }
            if ($s.PSObject.Properties.Match("bearer_token_env_var").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$s.bearer_token_env_var)) {
                $entry.bearer_token_env_var = [string]$s.bearer_token_env_var
            }
        }

        $startupTimeoutSec = Get-CodexMcpStartupTimeoutSec $s
        if ($null -ne $startupTimeoutSec) {
            $entry.startup_timeout_sec = [int]$startupTimeoutSec
        }

        $map[[string]$s.name] = [pscustomobject]$entry
    }
    return [pscustomobject]$map
}

function Get-McpServerNameSet($servers) {
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($null -eq $servers) { return $set }
    foreach ($s in $servers) {
        $name = [string]$s.name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $set.Add($name) | Out-Null
    }
    return $set
}

function Convert-McpMapToOrderedMap($mapLike) {
    $map = [ordered]@{}
    if ($null -eq $mapLike) { return $map }

    if ($mapLike -is [hashtable] -or $mapLike -is [System.Collections.IDictionary]) {
        foreach ($k in $mapLike.Keys) {
            $name = [string]$k
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $map[$name] = $mapLike[$k]
        }
        return $map
    }

    if ($mapLike -is [pscustomobject]) {
        foreach ($p in $mapLike.PSObject.Properties) {
            $name = [string]$p.Name
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $map[$name] = $p.Value
        }
    }
    return $map
}

function Merge-McpConfigMaps($existingMapLike, $managedMapLike, $managedNameSet) {
    $merged = [ordered]@{}
    $existing = Convert-McpMapToOrderedMap $existingMapLike
    foreach ($name in $existing.Keys) {
        if ($managedNameSet.Contains([string]$name)) { continue }
        $merged[[string]$name] = $existing[$name]
    }

    $managed = Convert-McpMapToOrderedMap $managedMapLike
    foreach ($name in $managed.Keys) {
        $merged[[string]$name] = $managed[$name]
    }
    return [pscustomobject]$merged
}

function Build-GenericMcpPayload([string]$existingContent, $servers) {
    $base = [ordered]@{}
    if (-not [string]::IsNullOrWhiteSpace($existingContent)) {
        try {
            $parsed = $existingContent | ConvertFrom-Json
            if ($parsed -ne $null) {
                foreach ($p in $parsed.PSObject.Properties) {
                    $base[[string]$p.Name] = $p.Value
                }
            }
        }
        catch {
            Log ("MCP JSON 解析失败，将使用最小配置重建：{0}" -f $_.Exception.Message) "WARN"
        }
    }

    $managedMap = Convert-McpServersToConfigMap $servers
    # MCP 同步以 skills.json 为唯一真源，避免卸载后残留旧项。
    $base["mcpServers"] = $managedMap
    if ($base.Contains("mcp_servers")) { $base.Remove("mcp_servers") }
    return [pscustomobject]$base
}

function Get-NativeMcpKeyValueFlags($data, [string]$flagName, [string]$separator = "=") {
    $flags = @()
    if ($null -eq $data) { return $flags }
    function Resolve-EnvTemplateValue([string]$rawValue) {
        if ([string]::IsNullOrWhiteSpace($rawValue)) { return $rawValue }
        return [System.Text.RegularExpressions.Regex]::Replace(
            $rawValue,
            '\$\{([A-Za-z_][A-Za-z0-9_]*)\}',
            {
                param($m)
                $varName = [string]$m.Groups[1].Value
                $resolved = [System.Environment]::GetEnvironmentVariable($varName)
                if ($null -eq $resolved) { return $m.Value }
                return [string]$resolved
            }
        )
    }

    if ($data -is [hashtable] -or $data -is [System.Collections.IDictionary]) {
        foreach ($k in $data.Keys) {
            $key = [string]$k
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            $value = Resolve-EnvTemplateValue ([string]$data[$k])
            $flags += @($flagName, ("{0}{1}{2}" -f $key, $separator, $value))
        }
        return $flags
    }

    if ($data -is [pscustomobject]) {
        foreach ($p in $data.PSObject.Properties) {
            $key = [string]$p.Name
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            $value = Resolve-EnvTemplateValue ([string]$p.Value)
            $flags += @($flagName, ("{0}{1}{2}" -f $key, $separator, $value))
        }
        return $flags
    }

    return $flags
}

function Get-NativeMcpAddArgs($server, [string]$scope = "user") {
    Need ($null -ne $server) "MCP 服务不能为空"
    Need (-not [string]::IsNullOrWhiteSpace([string]$server.name)) "MCP 服务缺少 name"
    Need (($scope -eq "local") -or ($scope -eq "user")) ("不支持的 scope：{0}" -f $scope)

    $name = [string]$server.name
    $transport = if ([string]::IsNullOrWhiteSpace([string]$server.transport)) { "stdio" } else { [string]$server.transport }
    $transport = $transport.Trim().ToLowerInvariant()
    $args = @("mcp", "add", "--scope", $scope)

    if ($transport -eq "stdio") {
        $envFlags = @()
        if ($server.PSObject.Properties.Match("env").Count -gt 0) {
            $envFlags = Get-NativeMcpKeyValueFlags $server.env "-e"
        }
        if ($envFlags.Count -gt 0) { $args += $envFlags }
        $args += @($name, "--")
        $cmd = [string]$server.command
        Need (-not [string]::IsNullOrWhiteSpace($cmd)) ("stdio MCP 缺少 command：{0}" -f $name)
        $args += $cmd
        if ($server.PSObject.Properties.Match("args").Count -gt 0 -and $server.args -ne $null) {
            $args += @($server.args | ForEach-Object { [string]$_ })
        }
        return $args
    }

    $headerFlags = @()
    if ($server.PSObject.Properties.Match("headers").Count -gt 0) {
        $headerFlags = Get-NativeMcpKeyValueFlags $server.headers "-H" ": "
    }
    $url = if ($server.PSObject.Properties.Match("url").Count -gt 0) { [string]$server.url } else { "" }
    Need (-not [string]::IsNullOrWhiteSpace($url)) ("{0} MCP 缺少 url：{1}" -f $transport, $name)
    $args += @("--transport", $transport, $name, $url)
    # `claude mcp add --header` is variadic and consumes trailing tokens, so headers must
    # be appended after <name> <url>.
    if ($headerFlags.Count -gt 0) { $args += $headerFlags }
    return $args
}

function Remove-McpServersFromPayload($payload, [string[]]$names) {
    if ($null -eq $payload -or $null -eq $names -or $names.Count -eq 0) { return $payload }
    if ($payload.PSObject.Properties.Match("mcpServers").Count -eq 0) { return $payload }
    $serverMap = $payload.mcpServers
    if ($null -eq $serverMap) { return $payload }

    foreach ($name in @($names)) {
        if ([string]::IsNullOrWhiteSpace([string]$name)) { continue }
        $match = @($serverMap.PSObject.Properties | Where-Object {
            [string]::Equals([string]$_.Name, [string]$name, [System.StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1)
        if ($match.Count -gt 0 -and $null -ne $match[0]) {
            $serverMap.PSObject.Properties.Remove($match[0].Name)
        }
    }

    return $payload
}

function Get-LegacyMcpServersToPrune() {
    return @("fetch", "filesystem")
}

function Has-McpServerByName($servers, [string]$name) {
    if ([string]::IsNullOrWhiteSpace($name)) { return $false }
    foreach ($s in @($servers)) {
        if ($null -eq $s) { continue }
        if ([string]::Equals([string]$s.name, $name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Invoke-Gh([string[]]$GhArgs) {
    Need ($GhArgs -and $GhArgs.Count -gt 0) "gh 参数不能为空"
    $output = & gh @GhArgs 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return @($output | ForEach-Object { [string]$_ })
}

function Ensure-GhAuthForGithubMcp($servers) {
    if (-not (Has-McpServerByName $servers "github")) { return }
    if (-not (Get-Command "gh" -ErrorAction SilentlyContinue)) {
        throw "检测到 github MCP，但未找到 gh 命令。请先安装并登录 GitHub CLI（gh auth login）。"
    }

    $tokenLines = Invoke-Gh @("auth", "token")
    $token = if ($tokenLines) { (($tokenLines -join "`n").Trim()) } else { "" }
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "检测到 github MCP，但 gh 未登录或无法读取 token。请先执行 gh auth login。"
    }

    $userLines = Invoke-Gh @("api", "user", "--jq", ".login")
    $username = if ($userLines) { (($userLines -join "`n").Trim()) } else { "" }
    if ([string]::IsNullOrWhiteSpace($username)) {
        throw "检测到 github MCP，但 gh 登录态校验失败（gh api user）。请重新执行 gh auth login。"
    }

    # gh auth 路线：同步阶段临时注入 token，供各客户端配置写入与 native 注册使用。
    $env:GITHUB_PERSONAL_ACCESS_TOKEN = $token
    $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN = $token
    Log ("GitHub MCP gh 认证预检通过：{0}" -f $username) "INFO"
}

function Resolve-ExternalCommandInvocation([string]$command, [string[]]$commandArgs = @()) {
    Need (-not [string]::IsNullOrWhiteSpace($command)) "外部命令名不能为空"
    $resolved = @(Get-Command $command -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($resolved.Count -gt 0 -and $null -ne $resolved[0]) {
        $resolvedPath = [string]$resolved[0].Path
        if (-not [string]::IsNullOrWhiteSpace($resolvedPath)) {
            $ext = [System.IO.Path]::GetExtension($resolvedPath).ToLowerInvariant()
            if ($ext -eq ".ps1") {
                return [pscustomobject]@{
                    file = Resolve-PowerShellExecutable
                    args = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $resolvedPath) + @($commandArgs)
                }
            }
            return [pscustomobject]@{
                file = $resolvedPath
                args = @($commandArgs)
            }
        }
    }

    return [pscustomobject]@{
        file = $command
        args = @($commandArgs)
    }
}

function Get-ExternalCommandCapturedOutput([string]$outFile, [string]$errFile) {
    $outText = if (Test-Path -LiteralPath $outFile -PathType Leaf) { Get-Content -Raw -LiteralPath $outFile } else { "" }
    $errText = if (Test-Path -LiteralPath $errFile -PathType Leaf) { Get-Content -Raw -LiteralPath $errFile } else { "" }
    $combined = New-Object System.Collections.Generic.List[string]
    foreach ($line in @((($outText + "`n" + $errText) -split "`r?`n"))) {
        if ($null -ne $line -and $line -ne "") { $combined.Add([string]$line) | Out-Null }
    }
    return [pscustomobject]@{
        output = @($combined)
        error = if ([string]::IsNullOrWhiteSpace($errText)) { "" } else { $errText.Trim() }
    }
}

function Invoke-ExternalCommandWithTimeout(
    [string]$command,
    [Alias("args")]
    [string[]]$CommandArgs = @(),
    [string]$workingDir = $null,
    [int]$timeoutSeconds = 30
) {
    Need (-not [string]::IsNullOrWhiteSpace($command)) "外部命令名不能为空"
    if ($timeoutSeconds -lt 1) { $timeoutSeconds = 1 }

    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    $proc = $null
    try {
        $effectiveWorkingDir = if ([string]::IsNullOrWhiteSpace($workingDir)) { $PWD.Path } else { $workingDir }
        $invocation = Resolve-ExternalCommandInvocation $command @($CommandArgs)
        $argList = @($invocation.args | ForEach-Object { [string]$_ })
        $proc = Start-Process -FilePath ([string]$invocation.file) -ArgumentList $argList -PassThru -WindowStyle Hidden -RedirectStandardOutput $outFile -RedirectStandardError $errFile -WorkingDirectory $effectiveWorkingDir
        $exited = $proc.WaitForExit($timeoutSeconds * 1000)
        if (-not $exited) {
            try { $proc.Kill($true) } catch { try { $proc.Kill() } catch {} }
            try { $proc.WaitForExit(2000) | Out-Null } catch {}
            $captured = Get-ExternalCommandCapturedOutput $outFile $errFile
            return [pscustomobject]@{
                timed_out = $true
                exit_code = 124
                output = @($captured.output)
                error = if ([string]::IsNullOrWhiteSpace([string]$captured.error)) { ("timeout_after_{0}s" -f $timeoutSeconds) } else { ("timeout_after_{0}s: {1}" -f $timeoutSeconds, [string]$captured.error) }
            }
        }

        $captured = Get-ExternalCommandCapturedOutput $outFile $errFile

        return [pscustomobject]@{
            timed_out = $false
            exit_code = [int]$proc.ExitCode
            output = @($captured.output)
            error = [string]$captured.error
        }
    }
    catch {
        return [pscustomobject]@{
            timed_out = $false
            exit_code = 1
            output = @()
            error = $_.Exception.Message
        }
    }
    finally {
        if ($null -ne $proc) { $proc.Dispose() }
        Remove-Item -LiteralPath $outFile -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $errFile -ErrorAction SilentlyContinue
    }
}

function Resolve-TimeoutSecondsFromEnv([string]$envName, [int]$defaultSeconds, [int]$minSeconds = 1, [int]$maxSeconds = 600) {
    $value = $defaultSeconds
    if ([string]::IsNullOrWhiteSpace($envName)) { return $value }

    $raw = [System.Environment]::GetEnvironmentVariable($envName)
    $parsed = 0
    if ([int]::TryParse([string]$raw, [ref]$parsed)) {
        $value = $parsed
    }

    if ($value -lt $minSeconds) { $value = $minSeconds }
    if ($value -gt $maxSeconds) { $value = $maxSeconds }
    return $value
}

function Get-McpListVerifyTimeoutSeconds([string]$cli) {
    $cliName = if ([string]::IsNullOrWhiteSpace($cli)) { "" } else { [string]$cli.Trim().ToLowerInvariant() }
    $defaultSeconds = switch ($cliName) {
        "gemini" { 18 }
        "claude" { 45 }
        "codex" { 45 }
        default { 30 }
    }

    $globalTimeout = Resolve-TimeoutSecondsFromEnv "SKILLS_MCP_VERIFY_LIST_TIMEOUT_SECONDS" $defaultSeconds 1 600
    $envSuffix = if ([string]::IsNullOrWhiteSpace($cliName)) { "DEFAULT" } else { $cliName.ToUpperInvariant() }
    $perCliVar = "SKILLS_MCP_VERIFY_LIST_TIMEOUT_SECONDS_{0}" -f $envSuffix
    return (Resolve-TimeoutSecondsFromEnv $perCliVar $globalTimeout 1 600)
}

function Should-VerifyGeminiCli() {
    $raw = [System.Environment]::GetEnvironmentVariable("SKILLS_MCP_VERIFY_GEMINI_CLI")
    if ([string]::IsNullOrWhiteSpace([string]$raw)) { return $false }
    $v = [string]$raw
    $v = $v.Trim().ToLowerInvariant()
    return ($v -eq "1" -or $v -eq "true" -or $v -eq "yes" -or $v -eq "on")
}

function Get-NativeMcpCommandTimeoutSeconds() {
    return (Resolve-TimeoutSecondsFromEnv "SKILLS_MCP_NATIVE_TIMEOUT_SECONDS" 30 1 600)
}

function Invoke-ExternalCommandCapture(
    [string]$command,
    [Alias("args")]
    [string[]]$CommandArgs = @(),
    [int]$timeoutSeconds = 120
) {
    $result = Invoke-ExternalCommandWithTimeout $command @($CommandArgs) $null $timeoutSeconds
    return [pscustomobject]@{
        command = $command
        args = @($CommandArgs)
        exit_code = [int]$result.exit_code
        timed_out = [bool]$result.timed_out
        error = [string]$result.error
        output = @($result.output)
    }
}

function Get-McpServerNamesFromJsonText([string]$jsonText) {
    if ([string]::IsNullOrWhiteSpace($jsonText)) { return @() }
    try {
        $obj = $jsonText | ConvertFrom-Json -Depth 100
    }
    catch {
        return @()
    }
    if ($null -eq $obj) { return @() }
    if ($obj.PSObject.Properties.Match("mcpServers").Count -eq 0 -or $null -eq $obj.mcpServers) {
        return @()
    }
    return @($obj.mcpServers.PSObject.Properties | ForEach-Object { [string]$_.Name })
}

function Get-CodexMcpServerNamesFromTomlText([string]$tomlText) {
    if ([string]::IsNullOrWhiteSpace($tomlText)) { return @() }
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($line in @(($tomlText -split "`r?`n"))) {
        $m = [regex]::Match([string]$line, '^\s*\[mcp_servers\.([^\]\s]+)\]\s*$')
        if ($m.Success) {
            $set.Add([string]$m.Groups[1].Value) | Out-Null
        }
    }
    return @($set | Sort-Object)
}

function Get-McpExpectedServersByCli($roots) {
    $expected = [ordered]@{
        claude = @()
        codex = @()
        gemini = @()
    }
    foreach ($root in @($roots)) {
        if ([string]::IsNullOrWhiteSpace([string]$root)) { continue }
        $leaf = (Split-Path ([string]$root) -Leaf).ToLowerInvariant()
        if ($leaf -eq ".claude") {
            $mcpPath = Join-Path $root ".mcp.json"
            if (Test-Path $mcpPath) {
                $names = Get-McpServerNamesFromJsonText (Get-Content -Raw -Path $mcpPath)
                if ($names.Count -gt 0) { $expected.claude += $names }
            }
            continue
        }
        if ($leaf -eq ".gemini") {
            $settingsPath = Join-Path $root "settings.json"
            if (Test-Path $settingsPath) {
                $names = Get-McpServerNamesFromJsonText (Get-Content -Raw -Path $settingsPath)
                if ($names.Count -gt 0) { $expected.gemini += $names }
            }
            continue
        }
        if ($leaf -eq ".codex") {
            $cfgPath = Join-Path $root "config.toml"
            if (Test-Path $cfgPath) {
                $names = Get-CodexMcpServerNamesFromTomlText (Get-Content -Raw -Path $cfgPath)
                if ($names.Count -gt 0) { $expected.codex += $names }
            }
            continue
        }
    }

    foreach ($k in @("claude", "codex", "gemini")) {
        $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($name in @($expected[$k])) {
            if ([string]::IsNullOrWhiteSpace([string]$name)) { continue }
            $set.Add([string]$name) | Out-Null
        }
        $expected[$k] = @($set | Sort-Object)
    }
    return [pscustomobject]$expected
}

function Remove-AnsiEscapeSequences([string]$text) {
    if ([string]::IsNullOrEmpty($text)) { return $text }
    return ([regex]::Replace($text, '\x1B\[[0-9;?]*[ -/]*[@-~]', ''))
}

function Mask-SensitiveMcpCommandText([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $text }
    $masked = [string]$text
    $masked = [regex]::Replace($masked, '(?i)(Authorization\s*[:=]\s*Bearer\s+)([^"\s]+)', '$1<redacted>')
    $masked = [regex]::Replace($masked, '(?i)\bgithub_pat_[A-Za-z0-9_]+\b', '<redacted>')
    $masked = [regex]::Replace($masked, '(?i)\bgh[pousr]_[A-Za-z0-9_]+\b', '<redacted>')
    return $masked
}

function Test-IsNonInteractiveMcpError([string]$text) {
    if ([string]::IsNullOrWhiteSpace([string]$text)) { return $false }
    $normalized = ([string]$text).Trim()
    $hints = @(
        "stdout is not a terminal",
        "Input must be provided either through stdin",
        "No input provided via stdin",
        "when using --print"
    )
    foreach ($hint in $hints) {
        if ($normalized -like ("*{0}*" -f $hint)) { return $true }
    }
    return $false
}

function Test-CliMcpServerReady([string]$cli, [string[]]$expectedServers) {
    $cliName = if ([string]::IsNullOrWhiteSpace($cli)) { "" } else { [string]$cli.Trim().ToLowerInvariant() }
    $isGemini = ($cliName -eq "gemini")
    if ($null -eq $expectedServers -or $expectedServers.Count -eq 0) {
        return [pscustomobject]@{
            cli = $cli
            ok = $true
            reason = "no_expected_servers"
            missing = @()
            raw = @()
        }
    }
    if ($isGemini -and -not (Should-VerifyGeminiCli)) {
        return [pscustomobject]@{
            cli = $cli
            ok = $true
            reason = "gemini_cli_verification_skipped"
            missing = @()
            raw = @()
        }
    }
    if (-not (Get-Command $cli -ErrorAction SilentlyContinue)) {
        if ($isGemini) {
            return [pscustomobject]@{
                cli = $cli
                ok = $true
                reason = "gemini_cli_not_found_fallback"
                missing = @()
                raw = @()
            }
        }
        return [pscustomobject]@{
            cli = $cli
            ok = $false
            reason = "cli_not_found"
            missing = @($expectedServers)
            raw = @()
        }
    }

    $listTimeoutSeconds = Get-McpListVerifyTimeoutSeconds $cli
    $result = Invoke-ExternalCommandCapture $cli @("mcp", "list") $listTimeoutSeconds
    $raw = @($result.output | ForEach-Object { Remove-AnsiEscapeSequences ([string]$_) })
    if ($result.timed_out) {
        if ($isGemini) {
            return [pscustomobject]@{
                cli = $cli
                ok = $true
                reason = ("gemini_cli_timeout_fallback_{0}s" -f $listTimeoutSeconds)
                missing = @()
                raw = $raw
            }
        }
        return [pscustomobject]@{
            cli = $cli
            ok = $false
            reason = ("timeout_after_{0}s" -f $listTimeoutSeconds)
            missing = @($expectedServers)
            raw = $raw
        }
    }

    $missing = New-Object System.Collections.Generic.List[string]
    $joined = ($raw -join "`n")
    $trimmedJoined = $joined.Trim()
    $nonInteractiveHints = @(
        "stdout is not a terminal",
        "Input must be provided either through stdin",
        "No input provided via stdin"
    )
    $isNonInteractive = $false
    foreach ($hint in $nonInteractiveHints) {
        if ($trimmedJoined -like ("*{0}*" -f $hint)) {
            $isNonInteractive = $true
            break
        }
    }
    if ($isNonInteractive) {
        return [pscustomobject]@{
            cli = $cli
            ok = $true
            reason = "non_interactive_tty_required_fallback"
            missing = @()
            raw = $raw
        }
    }
    if ($trimmedJoined.Length -eq 0 -and $cli -eq "gemini") {
        return [pscustomobject]@{
            cli = $cli
            ok = $true
            reason = if ($result.exit_code -eq 0) { "ok_empty_output" } else { ("ok_empty_output_exit_{0}" -f $result.exit_code) }
            missing = @()
            raw = $raw
        }
    }
    if ($trimmedJoined.Length -eq 0) {
        return [pscustomobject]@{
            cli = $cli
            ok = $false
            reason = ("empty_output_exit_{0}" -f $result.exit_code)
            missing = @($expectedServers)
            raw = $raw
        }
    }
    foreach ($name in @($expectedServers)) {
        if ([string]::IsNullOrWhiteSpace([string]$name)) { continue }
        $pattern = "^\s*{0}\b" -f [regex]::Escape([string]$name)
        $line = @($raw | Where-Object { [regex]::IsMatch([string]$_, $pattern) } | Select-Object -First 1)
        if ($line.Count -eq 0) {
            $missing.Add([string]$name) | Out-Null
            continue
        }
        $lineText = [string]$line[0]
        if ($cli -eq "claude") {
            if ($lineText -notmatch "Connected") {
                $missing.Add([string]$name) | Out-Null
            }
            continue
        }
        if ($cli -eq "codex") {
            if ($lineText -match '\bdisabled\b') {
                $missing.Add([string]$name) | Out-Null
            }
            continue
        }
        if ($cli -eq "gemini") {
            # Some Gemini CLI versions print minimal/empty table output.
            # Fallback: when list output has no rows, verify names from settings.json already written.
            if ($trimmedJoined.Length -eq 0) {
                continue
            }
        }
    }

    $reason = if ($missing.Count -eq 0) {
        if ($result.exit_code -eq 0) { "ok" } else { ("ok_with_nonzero_exit_{0}" -f $result.exit_code) }
    } else {
        if ($result.exit_code -eq 0) { "missing_or_unhealthy" } else { ("missing_or_unhealthy_exit_{0}" -f $result.exit_code) }
    }
    return [pscustomobject]@{
        cli = $cli
        ok = ($missing.Count -eq 0)
        reason = $reason
        missing = @($missing)
        raw = $raw
    }
}

function Verify-McpAcrossCliWithRetry($roots, [int]$maxAttempts = 6, [int]$intervalSeconds = 3) {
    $expected = Get-McpExpectedServersByCli $roots
    $targets = @(
        [pscustomobject]@{ cli = "claude"; names = @($expected.claude) },
        [pscustomobject]@{ cli = "codex"; names = @($expected.codex) },
        [pscustomobject]@{ cli = "gemini"; names = @($expected.gemini) }
    ) | Where-Object { @($_.names).Count -gt 0 }

    if ($targets.Count -eq 0) {
        Log "未检测到需校验的 CLI MCP 目标，跳过跨 CLI 可用性校验。" "WARN"
        return
    }

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $failed = New-Object System.Collections.Generic.List[object]
        foreach ($target in $targets) {
            $check = Test-CliMcpServerReady ([string]$target.cli) @($target.names)
            if ($check.ok) {
                Log ("MCP 校验通过：{0} -> {1}" -f $check.cli, ((@($target.names)) -join ", "))
            }
            else {
                $failed.Add($check) | Out-Null
                Log ("MCP 校验未通过：{0}，缺失/异常：{1}（reason={2}）" -f $check.cli, (($check.missing) -join ", "), $check.reason) "WARN"
                $snippet = @($check.raw | Select-Object -First 6) -join " | "
                if (-not [string]::IsNullOrWhiteSpace($snippet)) {
                    Log ("{0} mcp list 输出片段：{1}" -f $check.cli, $snippet) "WARN"
                }
            }
        }

        if ($failed.Count -eq 0) {
            Log ("跨 CLI MCP 校验完成：全部通过（attempt={0}/{1}）。" -f $attempt, $maxAttempts) "INFO"
            return
        }
        if ($attempt -lt $maxAttempts) {
            Log ("跨 CLI MCP 校验第 {0}/{1} 次未全部通过，{2}s 后自动重试。" -f $attempt, $maxAttempts, $intervalSeconds) "WARN"
            Start-Sleep -Seconds $intervalSeconds
        }
    }

    throw ("跨 CLI MCP 校验失败：在 {0} 次重试后仍存在不可用服务，请检查日志中的 CLI 与缺失项。" -f $maxAttempts)
}

function Invoke-NativeMcpSync($servers) {
    if (-not (Get-Command "claude" -ErrorAction SilentlyContinue)) {
        Log "未检测到 claude 命令，已跳过原生 MCP 同步（仅写入 .mcp.json）。" "WARN"
        return
    }
    if ($script:SkipNativeMcpForSession) {
        Log "已检测到原生 MCP CLI 非交互不可用，本轮跳过后续原生 MCP 同步。" "WARN"
        return
    }
    if ($null -eq $servers -or $servers.Count -eq 0) {
        Log "当前 mcp_servers 为空，跳过原生 MCP 注册。" "WARN"
        return
    }

    foreach ($s in $servers) {
        $scope = "user"
        try {
            $args = Get-NativeMcpAddArgs $s $scope
            $cmdText = "claude {0}" -f (($args | ForEach-Object { [string]$_ }) -join " ")
            if ($DryRun) {
                $safeCmdText = Mask-SensitiveMcpCommandText $cmdText
                Write-Host ("DRYRUN：将执行原生 MCP 同步 -> {0}" -f $safeCmdText)
                continue
            }
            $timeoutSeconds = Get-NativeMcpCommandTimeoutSeconds
            $native = Invoke-ExternalCommandWithTimeout "claude" @($args) $script:Root $timeoutSeconds
            if ($native.timed_out) {
                Log ("原生 MCP 同步超时（已忽略）：{0}（scope={1}，timeout={2}s）" -f [string]$s.name, $scope, $timeoutSeconds) "WARN"
                continue
            }
            if ($native.exit_code -ne 0) {
                Log ("原生 MCP 同步失败（已忽略）：{0}（scope={1}，exit={2}）{3}" -f [string]$s.name, $scope, $native.exit_code, $native.error) "WARN"
                if (Test-IsNonInteractiveMcpError ([string]$native.error)) {
                    $script:SkipNativeMcpForSession = $true
                    Log "检测到原生 MCP CLI 在非交互环境不可用，已停止本轮后续原生 MCP 同步。" "WARN"
                    break
                }
                continue
            }
            Log ("已同步原生 MCP：{0}（scope={1}）" -f [string]$s.name, $scope)
        }
        catch {
            Log ("原生 MCP 同步失败（已忽略）：{0}（scope={1}） -> {2}" -f [string]$s.name, $scope, $_.Exception.Message) "WARN"
            if (Test-IsNonInteractiveMcpError $_.Exception.Message) {
                $script:SkipNativeMcpForSession = $true
                Log "检测到原生 MCP CLI 在非交互环境不可用，已停止本轮后续原生 MCP 同步。" "WARN"
                break
            }
        }
    }
}

function Get-NativeMcpCleanupCommands([string]$name) {
    Need (-not [string]::IsNullOrWhiteSpace($name)) "MCP 服务名不能为空"
    return @(
        [pscustomobject]@{ command = "claude"; args = @("mcp", "remove", $name, "--scope", "user"); project = $false }
        [pscustomobject]@{ command = "claude"; args = @("mcp", "remove", $name, "--scope", "project"); project = $true }
    )
}

function Invoke-NativeMcpCleanup([string]$name) {
    if ($script:SkipNativeMcpForSession) {
        Log ("已检测到原生 MCP CLI 非交互不可用，跳过清理：{0}" -f $name) "WARN"
        return
    }
    $ops = Get-NativeMcpCleanupCommands $name
    foreach ($op in $ops) {
        if (-not (Get-Command $op.command -ErrorAction SilentlyContinue)) { continue }
        $cmdText = "{0} {1}" -f $op.command, (($op.args | ForEach-Object { [string]$_ }) -join " ")
        if ($DryRun) {
            Write-Host ("DRYRUN：清理原生 MCP -> {0}" -f $cmdText)
            continue
        }
        try {
            $timeoutSeconds = Get-NativeMcpCommandTimeoutSeconds
            $workingDir = if ($op.project) { $script:Root } else { $null }
            $native = Invoke-ExternalCommandWithTimeout ([string]$op.command) @($op.args) $workingDir $timeoutSeconds
            if ($native.timed_out) {
                Log ("原生 MCP 清理超时（已忽略）：{0}（timeout={1}s）" -f $cmdText, $timeoutSeconds) "WARN"
                continue
            }
            if ($native.exit_code -ne 0) {
                Log ("原生 MCP 清理失败（已忽略）：{0}（exit={1}）{2}" -f $cmdText, $native.exit_code, $native.error) "WARN"
                if (Test-IsNonInteractiveMcpError ([string]$native.error)) {
                    $script:SkipNativeMcpForSession = $true
                    Log "检测到原生 MCP CLI 在非交互环境不可用，已停止本轮后续原生 MCP 清理。" "WARN"
                    break
                }
                continue
            }
            Log ("已执行原生 MCP 清理：{0}" -f $cmdText)
        }
        catch {
            Log ("原生 MCP 清理失败（已忽略）：{0} -> {1}" -f $cmdText, $_.Exception.Message) "WARN"
            if (Test-IsNonInteractiveMcpError $_.Exception.Message) {
                $script:SkipNativeMcpForSession = $true
                Log "检测到原生 MCP CLI 在非交互环境不可用，已停止本轮后续原生 MCP 清理。" "WARN"
                break
            }
        }
    }
}

function Build-GeminiSettingsPayload([string]$existingContent, $servers) {
    $base = [ordered]@{}
    if (-not [string]::IsNullOrWhiteSpace($existingContent)) {
        try {
            $parsed = $existingContent | ConvertFrom-Json
            if ($parsed -ne $null) {
                foreach ($p in $parsed.PSObject.Properties) {
                    $base[[string]$p.Name] = $p.Value
                }
            }
        }
        catch {
            Log ("Gemini settings.json 解析失败，将使用最小配置重建：{0}" -f $_.Exception.Message) "WARN"
        }
    }

    $managedMap = Convert-McpServersToGeminiConfigMap $servers
    # Gemini 同步以 skills.json 为唯一真源，避免卸载后残留旧项。
    $base["mcpServers"] = $managedMap
    if ($base.Contains("mcp_servers")) { $base.Remove("mcp_servers") }
    return [pscustomobject]$base
}

function ConvertTo-TomlBasicValue($value) {
    if ($null -eq $value) { return '""' }
    if ($value -is [bool]) { return ($(if ($value) { "true" } else { "false" })) }
    if ($value -is [int] -or $value -is [long] -or $value -is [double] -or $value -is [decimal]) { return [string]$value }
    $text = [string]$value
    $text = $text.Replace("\", "\\").Replace('"', '\"')
    return ('"{0}"' -f $text)
}

function Set-TomlTopLevelScalar([string[]]$lines, [string]$key, [string]$rawValue) {
    $safeLines = @($lines)
    $out = New-Object System.Collections.Generic.List[string]
    $found = $false
    $inserted = $false

    foreach ($line in $safeLines) {
        if (-not $inserted -and $line -match '^\s*\[[^\]]+\]\s*$') {
            if (-not $found) {
                $out.Add(("{0} = {1}" -f $key, $rawValue)) | Out-Null
            }
            $inserted = $true
        }

        if (-not $inserted -and $line -match ("^\s*" + [regex]::Escape($key) + "\s*=")) {
            $out.Add(("{0} = {1}" -f $key, $rawValue)) | Out-Null
            $found = $true
            continue
        }

        $out.Add($line) | Out-Null
    }

    if (-not $inserted -and -not $found) {
        $out.Add(("{0} = {1}" -f $key, $rawValue)) | Out-Null
    }

    return [string[]]$out.ToArray()
}

function Apply-CodexPermissionDefaults([string[]]$lines) {
    $updated = Set-TomlTopLevelScalar @($lines) "sandbox_mode" '"workspace-write"'
    $updated = Set-TomlTopLevelScalar @($updated) "approval_policy" '"never"'
    return [string[]]@($updated | ForEach-Object { [string]$_ })
}

function Build-CodexConfigToml([string]$existingToml, $servers) {
    $lines = @()
    if (-not [string]::IsNullOrWhiteSpace($existingToml)) {
        $lines = $existingToml -split "`r?`n"
    }
    $codexServers = @()
    $skippedGithubForMissingToken = $false
    $hasGithubToken = -not [string]::IsNullOrWhiteSpace($env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN) -or -not [string]::IsNullOrWhiteSpace($env:GITHUB_PERSONAL_ACCESS_TOKEN)
    if ([string]::IsNullOrWhiteSpace($env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN) -and -not [string]::IsNullOrWhiteSpace($env:GITHUB_PERSONAL_ACCESS_TOKEN)) {
        $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN = [string]$env:GITHUB_PERSONAL_ACCESS_TOKEN
    }
    foreach ($server in @($servers)) {
        if ($null -eq $server) { continue }
        if ([string]::Equals([string]$server.name, "github", [System.StringComparison]::OrdinalIgnoreCase)) {
            if (-not $hasGithubToken) {
                Log "Codex 检测到 GitHub MCP 但缺少 CODEX_GITHUB_PERSONAL_ACCESS_TOKEN（或 GITHUB_PERSONAL_ACCESS_TOKEN），已跳过同步以避免影响启动。" "WARN"
                $skippedGithubForMissingToken = $true
                continue
            }
            Log "Codex 检测到 GitHub MCP 且存在 Token，将写入 bearer_token_env_var=CODEX_GITHUB_PERSONAL_ACCESS_TOKEN。" "INFO"
            $normalizedGithub = [ordered]@{
                name = [string]$server.name
                transport = if ([string]::IsNullOrWhiteSpace([string]$server.transport)) { "http" } else { [string]$server.transport }
                url = [string]$server.url
                bearer_token_env_var = "CODEX_GITHUB_PERSONAL_ACCESS_TOKEN"
            }
            $codexServers += [pscustomobject]$normalizedGithub
            continue
        }
        $codexServers += $server
    }

    $managedMap = Convert-McpServersToCodexConfigMap $codexServers
    $managedNames = @($managedMap.PSObject.Properties.Name | Sort-Object)
    $preserveExistingMcpSections = ($managedNames.Count -eq 0 -and $skippedGithubForMissingToken)

    $kept = New-Object System.Collections.Generic.List[string]
    if ($preserveExistingMcpSections) {
        foreach ($line in $lines) {
            $kept.Add($line) | Out-Null
        }
    }
    else {
        $skipMcpSection = $false
        foreach ($line in $lines) {
            if ($line -match '^\s*\[mcp_servers\.[^\]]+\]\s*$') {
                $skipMcpSection = $true
                continue
            }

            if ($skipMcpSection -and $line -match '^\s*\[[^\]]+\]\s*$') {
                $skipMcpSection = $false
                $kept.Add($line) | Out-Null
                continue
            }

            if (-not $skipMcpSection) {
                $kept.Add($line) | Out-Null
            }
        }
    }

    while ($kept.Count -gt 0 -and [string]::IsNullOrWhiteSpace($kept[$kept.Count - 1])) {
        $kept.RemoveAt($kept.Count - 1)
    }

    $output = New-Object System.Collections.Generic.List[string]
    $output.AddRange([string[]](Apply-CodexPermissionDefaults @([string[]]$kept.ToArray())))

    if ($managedNames.Count -gt 0) {
        if ($output.Count -gt 0) { $output.Add("") | Out-Null }
        foreach ($name in $managedNames) {
            $entry = $managedMap.$name
            $output.Add(("[mcp_servers.{0}]" -f $name)) | Out-Null
            foreach ($prop in $entry.PSObject.Properties) {
                $key = [string]$prop.Name
                $val = $prop.Value
                if ($null -eq $val) { continue }
                if ($val -is [Array]) {
                    $arr = @($val | ForEach-Object { ConvertTo-TomlBasicValue $_ })
                    $output.Add(("{0} = [{1}]" -f $key, ($arr -join ", "))) | Out-Null
                    continue
                }
                if ($val -is [hashtable] -or $val -is [System.Collections.IDictionary] -or $val -is [pscustomobject]) {
                    $dict = @{}
                    if ($val -is [pscustomobject]) {
                        foreach ($p in $val.PSObject.Properties) { $dict[[string]$p.Name] = $p.Value }
                    }
                    else {
                        foreach ($k in $val.Keys) { $dict[[string]$k] = $val[$k] }
                    }
                    $pairs = @($dict.Keys | Sort-Object | ForEach-Object { "{0} = {1}" -f $_, (ConvertTo-TomlBasicValue $dict[$_]) })
                    $output.Add(("{0} = {{ {1} }}" -f $key, ($pairs -join ", "))) | Out-Null
                    continue
                }
                $output.Add(("{0} = {1}" -f $key, (ConvertTo-TomlBasicValue $val))) | Out-Null
            }
            $output.Add("") | Out-Null
        }
        while ($output.Count -gt 0 -and [string]::IsNullOrWhiteSpace($output[$output.Count - 1])) {
            $output.RemoveAt($output.Count - 1)
        }
    }

    return ($output -join "`r`n")
}

function Resolve-GeminiAntigravityRootsFromCandidates($paths) {
    $roots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($null -eq $paths) { return @() }
    $token = ".gemini\antigravity"
    $tokenLower = $token.ToLowerInvariant()
    foreach ($p in $paths) {
        if ([string]::IsNullOrWhiteSpace([string]$p)) { continue }
        $norm = ([string]$p).Replace("/", "\")
        $lower = $norm.ToLowerInvariant()
        $searchStart = 0
        while ($searchStart -lt $lower.Length) {
            $idx = $lower.IndexOf($tokenLower, $searchStart)
            if ($idx -lt 0) { break }
            if ($idx -gt 0 -and $norm[$idx - 1] -ne '\') {
                $searchStart = $idx + 1
                continue
            }
            $end = $idx + $token.Length
            # Require a directory boundary to avoid false matches like antigravity-backup.
            if ($end -lt $norm.Length -and $norm[$end] -ne '\') {
                $searchStart = $idx + 1
                continue
            }
            $root = $norm.Substring(0, $idx + $token.Length)
            if (-not [string]::IsNullOrWhiteSpace($root)) { $roots.Add($root) | Out-Null }
            $searchStart = $idx + $token.Length
        }
    }
    # Keep array shape when only one root is found.
    return ,@($roots | Sort-Object)
}

function Get-TraeProjectMcpConfigPath([string]$repoRoot) {
    Need (-not [string]::IsNullOrWhiteSpace($repoRoot)) "repoRoot 不能为空"
    return (Join-Path (Join-Path $repoRoot ".trae") "mcp.json")
}

function Get-McpTargetCandidatePaths($cfg) {
    $paths = New-Object System.Collections.Generic.List[string]
    if ($null -eq $cfg) { return @() }
    if ($cfg.PSObject.Properties.Match("mcp_targets").Count -gt 0 -and $cfg.mcp_targets -ne $null) {
        foreach ($mt in $cfg.mcp_targets) {
            if ($mt -is [string]) {
                if (-not [string]::IsNullOrWhiteSpace($mt)) { $paths.Add($mt) | Out-Null }
            }
            elseif ($mt.PSObject.Properties.Match("path").Count -gt 0) {
                $v = [string]$mt.path
                if (-not [string]::IsNullOrWhiteSpace($v)) { $paths.Add($v) | Out-Null }
            }
        }
    }
    foreach ($t in $cfg.targets) {
        if ($t.PSObject.Properties.Match("path").Count -gt 0) {
            $v = [string]$t.path
            if (-not [string]::IsNullOrWhiteSpace($v)) { $paths.Add($v) | Out-Null }
        }
    }
    $resolved = New-Object System.Collections.Generic.List[string]
    foreach ($path in $paths) {
        $r = Resolve-TargetDir $path
        if (-not [string]::IsNullOrWhiteSpace($r)) { $resolved.Add($r.Replace("/", "\")) | Out-Null }
    }
    return @($resolved)
}

function Resolve-McpTargetRootsFromCfg($cfg) {
    $roots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($null -eq $cfg) { return @() }

    $candidates = Get-McpTargetCandidatePaths $cfg
    foreach ($path in $candidates) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        $norm = $path.Replace("/", "\")
        $lower = $norm.ToLowerInvariant()

        $dotDirs = @(".claude", ".codex", ".gemini", ".trae")
        $matched = $false
        $bestIdx = -1
        $bestNeedleLen = 0
        foreach ($dotDir in $dotDirs) {
            $needle = "\" + $dotDir.ToLowerInvariant()
            $searchStart = 0
            while ($searchStart -lt $lower.Length) {
                $idx = $lower.IndexOf($needle, $searchStart)
                if ($idx -lt 0) { break }
                $end = $idx + $needle.Length
                # Require directory boundary so ".gemini_backup" does not match ".gemini".
                if ($end -lt $norm.Length -and $norm[$end] -ne '\') {
                    $searchStart = $idx + 1
                    continue
                }
                if ($bestIdx -lt 0 -or $idx -lt $bestIdx) {
                    $bestIdx = $idx
                    $bestNeedleLen = $needle.Length
                }
                $matched = $true
                break
            }
        }
        if ($matched -and $bestIdx -ge 0) {
            $root = $norm.Substring(0, $bestIdx + $bestNeedleLen)
            $roots.Add($root) | Out-Null
        }
        if ($matched) { continue }

        $leaf = Split-Path $norm -Leaf
        if ($leaf.Equals("skills", [System.StringComparison]::OrdinalIgnoreCase)) {
            $parent = Split-Path $norm -Parent
            if (-not [string]::IsNullOrWhiteSpace($parent)) { $roots.Add($parent) | Out-Null }
            continue
        }

        $roots.Add($norm) | Out-Null
    }

    # Keep array shape when only one root is found.
    return ,@($roots | Sort-Object)
}

function ConvertTo-OrderedSignatureValue($value) {
    if ($null -eq $value) { return $null }
    if ($value -is [string]) { return [string]$value }
    if ($value -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($k in @($value.Keys | Sort-Object)) {
            $ordered[[string]$k] = ConvertTo-OrderedSignatureValue $value[$k]
        }
        return [pscustomobject]$ordered
    }
    if ($value -is [pscustomobject]) {
        $ordered = [ordered]@{}
        foreach ($p in @($value.PSObject.Properties | Sort-Object Name)) {
            $ordered[[string]$p.Name] = ConvertTo-OrderedSignatureValue $p.Value
        }
        return [pscustomobject]$ordered
    }
    if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [byte[]])) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($item in @($value)) {
            $items.Add((ConvertTo-OrderedSignatureValue $item)) | Out-Null
        }
        return @($items)
    }
    return $value
}

function Get-McpServerSignature($server) {
    if ($null -eq $server) { return $null }
    $transport = if ($server.PSObject.Properties.Match("transport").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$server.transport)) {
        [string]$server.transport
    }
    else {
        "stdio"
    }
    $transport = $transport.Trim().ToLowerInvariant()
    $sig = [ordered]@{ transport = $transport }
    if ($transport -eq "stdio") {
        if ($server.PSObject.Properties.Match("command").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$server.command)) {
            $sig.command = [string]$server.command
        }
        if ($server.PSObject.Properties.Match("args").Count -gt 0) {
            $sig.args = @($server.args)
        }
        if ($server.PSObject.Properties.Match("env").Count -gt 0 -and $null -ne $server.env) {
            $sig.env = ConvertTo-OrderedSignatureValue $server.env
        }
    }
    else {
        if ($server.PSObject.Properties.Match("url").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$server.url)) {
            $sig.url = [string]$server.url
        }
        if ($server.PSObject.Properties.Match("headers").Count -gt 0 -and $null -ne $server.headers) {
            $sig.headers = ConvertTo-OrderedSignatureValue $server.headers
        }
        if ($server.PSObject.Properties.Match("bearer_token_env_var").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$server.bearer_token_env_var)) {
            $sig.bearer_token_env_var = [string]$server.bearer_token_env_var
        }
    }
    return ($sig | ConvertTo-Json -Depth 30 -Compress)
}

function Test-McpServerEquivalent($a, $b) {
    $sa = Get-McpServerSignature $a
    $sb = Get-McpServerSignature $b
    if ([string]::IsNullOrWhiteSpace($sa) -or [string]::IsNullOrWhiteSpace($sb)) { return $false }
    return ($sa -eq $sb)
}

function Find-EquivalentMcpServer($servers, $candidate) {
    foreach ($server in @($servers)) {
        if (Test-McpServerEquivalent $server $candidate) { return $server }
    }
    return $null
}

function 安装MCP([string[]]$tokens = @()) {
    $cfg = LoadCfg
    $cfgRaw = Get-Content $CfgPath -Raw

    $tokenList = @($tokens | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $trailingDryRun = Extract-McpTrailingDryRunToken $tokenList
    $tokenList = @($trailingDryRun.tokens)
    if (-not $DryRun -and [bool]$trailingDryRun.dry_run) {
        $script:DryRun = $true
        Write-Host "检测到尾部 -DryRun 参数，已切换为预演模式。"
    }
    if ($tokenList.Count -eq 1 -and $tokenList[0] -is [string] -and $tokenList[0].Contains(" ")) {
        $tokenList = Split-Args $tokenList[0]
    }

    $parsed = $null
    if ($tokenList.Count -gt 0) {
        $parsed = Parse-McpInstallArgs $tokenList
    }
    else {
        $name = Normalize-NameWithNotice (Read-HostSafe "MCP 服务名（如 context7）") "MCP 服务名"
        $transport = Read-HostSafe "transport（stdio/sse/http，默认 stdio）"
        if ([string]::IsNullOrWhiteSpace($transport)) { $transport = "stdio" }
        $transport = $transport.Trim().ToLowerInvariant()
        if ($transport -ne "stdio" -and $transport -ne "sse" -and $transport -ne "http") {
            Write-Host "无效 transport，已使用默认值 stdio"
            $transport = "stdio"
        }

        if ($transport -eq "stdio") {
            $cmdLine = Read-HostSafe "命令（示例：npx -y @upstash/context7-mcp）"
            $parts = Split-Args $cmdLine
            Need ($parts.Count -gt 0) "命令不能为空"
            $parsed = [pscustomobject]@{
                name = $name
                transport = "stdio"
                command = $parts[0]
                args = if ($parts.Count -gt 1) { $parts[1..($parts.Count - 1)] } else { @() }
                url = $null
                env = @{}
                headers = @{}
            }
        }
        else {
            $url = Read-HostSafe "URL（示例：https://example.com/mcp）"
            Need (-not [string]::IsNullOrWhiteSpace($url)) "URL 不能为空"
            $parsed = [pscustomobject]@{
                name = $name
                transport = $transport
                command = $null
                args = @()
                url = $url
                env = @{}
                headers = @{}
            }
        }
    }

    $server = New-McpServerObject $parsed
    $existing = @($cfg.mcp_servers)
    $existingSameName = $existing | Where-Object { [string]$_.name -eq [string]$server.name } | Select-Object -First 1
    $updated = @()
    $replaced = $false
    $equivalent = Find-EquivalentMcpServer $existing $server
    if ($existingSameName -and (Test-McpServerEquivalent $existingSameName $server)) {
        Write-Host ("MCP 服务已存在且配置一致：{0}" -f $server.name)
        return
    }
    foreach ($s in $existing) {
        if ([string]$s.name -eq [string]$server.name) {
            $updated += $server
            $replaced = $true
        }
        else {
            $updated += $s
        }
    }
    if ($equivalent -and -not $replaced) {
        Write-Host ("已存在等效 MCP 服务：{0}（名称：{1}），已跳过" -f $server.name, [string]$equivalent.name)
        return
    }
    if (-not $replaced) { $updated += $server }
    $cfg.mcp_servers = $updated
    SaveCfgSafe $cfg $cfgRaw

    if ($replaced) {
        Write-Host ("已更新 MCP 服务：{0}" -f $server.name)
    }
    else {
        Write-Host ("已安装 MCP 服务：{0}" -f $server.name)
    }
    同步MCP
}

function 卸载MCP([string[]]$tokens = @()) {
    $cfg = LoadCfg
    $cfgRaw = Get-Content $CfgPath -Raw
    $servers = @($cfg.mcp_servers)
    if ($servers.Count -eq 0) {
        Write-Host "当前没有已安装的 MCP 服务。"
        return
    }

    $name = $null
    $tokenList = @($tokens | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $trailingDryRun = Extract-McpTrailingDryRunToken $tokenList
    $tokenList = @($trailingDryRun.tokens)
    if (-not $DryRun -and [bool]$trailingDryRun.dry_run) {
        $script:DryRun = $true
        Write-Host "检测到尾部 -DryRun 参数，已切换为预演模式。"
    }
    if ($tokenList.Count -gt 0) {
        $name = Normalize-NameWithNotice ([string]$tokenList[0]) "MCP 服务名"
    }
    if ([string]::IsNullOrWhiteSpace($name)) {
        Write-Host "已安装 MCP 服务："
        for ($i = 0; $i -lt $servers.Count; $i++) {
            Write-Host ("{0,3}) {1}" -f ($i + 1), $servers[$i].name)
        }
        $picked = Read-HostSafe "输入序号或名称"
        if ($picked -match "^\d+$") {
            $idx = [int]$picked - 1
            Need ($idx -ge 0 -and $idx -lt $servers.Count) "序号越界。"
            $name = [string]$servers[$idx].name
        }
        else {
            $name = Normalize-NameWithNotice $picked "MCP 服务名"
        }
    }

    $remaining = @()
    $removed = $false
    foreach ($s in $servers) {
        if ([string]$s.name -eq $name) {
            $removed = $true
        }
        else {
            $remaining += $s
        }
    }
    Need $removed ("未找到 MCP 服务：{0}" -f $name)

    $cfg.mcp_servers = $remaining
    SaveCfgSafe $cfg $cfgRaw
    Write-Host ("已卸载 MCP 服务：{0}" -f $name)
    Invoke-NativeMcpCleanup $name
    同步MCP
}

function 同步MCP {
    Invoke-WithMetric "sync_mcp" {
        $script:SkipNativeMcpForSession = $false
        $cfg = LoadCfg
        $servers = @($cfg.mcp_servers)
        $pruneNames = @(Get-LegacyMcpServersToPrune)
        if (-not $DryRun) {
            Ensure-GhAuthForGithubMcp $servers
        }

        $roots = Resolve-McpTargetRootsFromCfg $cfg
        Need ($roots.Count -gt 0) "未找到可同步的 MCP 目标目录（请检查 targets/mcp_targets 配置）。"
        $candidatePaths = Get-McpTargetCandidatePaths $cfg

        $written = @()
        foreach ($targetRoot in $roots) {
            $file = Join-Path $targetRoot ".mcp.json"
            $targetRootLeaf = (Split-Path ([string]$targetRoot) -Leaf)
            if ($DryRun) {
                Write-Host ("DRYRUN：将写入 MCP 配置 -> {0}" -f $file)
                $written += $file
                continue
            }
            EnsureDir $targetRoot
            $existing = if (Test-Path $file) { Get-Content -Raw -Path $file } else { "" }
            $payloadObj = Build-GenericMcpPayload $existing $servers
            $payloadObj = Remove-McpServersFromPayload $payloadObj $pruneNames
            $json = $payloadObj | ConvertTo-Json -Depth 100
            Set-ContentUtf8 $file $json
            $written += $file
            Log ("已同步 MCP 配置：{0}" -f $file)
        }

        $geminiRoots = @($roots | Where-Object { (Split-Path ([string]$_) -Leaf).Equals(".gemini", [System.StringComparison]::OrdinalIgnoreCase) })
        foreach ($geminiRoot in $geminiRoots) {
            $settingsPath = Join-Path $geminiRoot "settings.json"
            $existing = if (Test-Path $settingsPath) { Get-Content -Raw -Path $settingsPath } else { "" }
            $payloadObj = Build-GeminiSettingsPayload $existing $servers
            $content = $payloadObj | ConvertTo-Json -Depth 100
            if ($DryRun) {
                Write-Host ("DRYRUN：将写入 Gemini 配置 -> {0}" -f $settingsPath)
                $written += $settingsPath
            }
            else {
                EnsureDir $geminiRoot
                Set-ContentUtf8 $settingsPath $content
                $written += $settingsPath
                Log ("已同步 Gemini MCP 配置：{0}" -f $settingsPath)
            }
        }

        $antigravityRoots = Resolve-GeminiAntigravityRootsFromCandidates $candidatePaths
        foreach ($agRoot in $antigravityRoots) {
            $settingsPath = Join-Path $agRoot "settings.json"
            $existing = if (Test-Path $settingsPath) { Get-Content -Raw -Path $settingsPath } else { "" }
            $payloadObj = Build-GeminiSettingsPayload $existing $servers
            $content = $payloadObj | ConvertTo-Json -Depth 100
            if ($DryRun) {
                Write-Host ("DRYRUN：将写入 Gemini Antigravity 配置 -> {0}" -f $settingsPath)
                $written += $settingsPath
            }
            else {
                EnsureDir $agRoot
                Set-ContentUtf8 $settingsPath $content
                $written += $settingsPath
                Log ("已同步 Gemini Antigravity MCP 配置：{0}" -f $settingsPath)
            }
        }

        $codexRoots = @($roots | Where-Object { (Split-Path ([string]$_) -Leaf).Equals(".codex", [System.StringComparison]::OrdinalIgnoreCase) })
        foreach ($codexRoot in $codexRoots) {
            $cfgPath = Join-Path $codexRoot "config.toml"
            $existing = if (Test-Path $cfgPath) { Get-Content -Raw -Path $cfgPath } else { "" }
            $toml = Build-CodexConfigToml $existing $servers
            if ($DryRun) {
                Write-Host ("DRYRUN：将写入 Codex MCP 配置 -> {0}" -f $cfgPath)
                $written += $cfgPath
            }
            else {
                EnsureDir $codexRoot
                Set-ContentUtf8 $cfgPath $toml
                $written += $cfgPath
                Log ("已同步 Codex MCP 配置：{0}" -f $cfgPath)
            }
        }

        $traeRoots = @($roots | Where-Object { (Split-Path ([string]$_) -Leaf).Equals(".trae", [System.StringComparison]::OrdinalIgnoreCase) })
        foreach ($traeRoot in $traeRoots) {
            $traePath = Join-Path $traeRoot "mcp.json"
            if ($DryRun) {
                Write-Host ("DRYRUN：将写入 Trae MCP 配置 -> {0}" -f $traePath)
                $written += $traePath
            }
            else {
                EnsureDir $traeRoot
                $existing = if (Test-Path $traePath) { Get-Content -Raw -Path $traePath } else { "" }
                $payloadObj = Build-GenericMcpPayload $existing $servers
                $json = $payloadObj | ConvertTo-Json -Depth 100
                Set-ContentUtf8 $traePath $json
                $written += $traePath
                Log ("已同步 Trae MCP 配置：{0}" -f $traePath)
            }
        }

        $projectTraePath = Get-TraeProjectMcpConfigPath $script:Root
        if ($DryRun) {
            Write-Host ("DRYRUN：将写入项目级 Trae MCP 配置 -> {0}" -f $projectTraePath)
            $written += $projectTraePath
        }
        else {
            $projectTraeDir = Split-Path $projectTraePath -Parent
            EnsureDir $projectTraeDir
            $existing = if (Test-Path $projectTraePath) { Get-Content -Raw -Path $projectTraePath } else { "" }
            $payloadObj = Build-GenericMcpPayload $existing $servers
            $json = $payloadObj | ConvertTo-Json -Depth 100
            Set-ContentUtf8 $projectTraePath $json
            $written += $projectTraePath
            Log ("已同步项目级 Trae MCP 配置：{0}" -f $projectTraePath)
        }

        Write-Host ("已同步 MCP 服务配置到 {0} 个目标。" -f $written.Count)
        foreach ($pruneName in $pruneNames) {
            Invoke-NativeMcpCleanup $pruneName
        }
        Invoke-NativeMcpSync $servers
        if (-not $DryRun) {
            $attemptsEnv = $env:SKILLS_MCP_VERIFY_ATTEMPTS
            $intervalEnv = $env:SKILLS_MCP_VERIFY_INTERVAL_SECONDS
            $attemptsParsed = 0
            $intervalParsed = 0
            $attempts = if ([int]::TryParse([string]$attemptsEnv, [ref]$attemptsParsed)) { $attemptsParsed } else { 6 }
            $intervalSeconds = if ([int]::TryParse([string]$intervalEnv, [ref]$intervalParsed)) { $intervalParsed } else { 3 }
            if ($attempts -lt 1) { $attempts = 1 }
            if ($intervalSeconds -lt 1) { $intervalSeconds = 1 }
            Verify-McpAcrossCliWithRetry $roots $attempts $intervalSeconds
        }
        if ($servers.Count -eq 0) {
            Write-Host "提示：当前 mcp_servers 为空，已将各目标写为空配置。"
        }
    } @{ command = "同步MCP" } -NoHost
}
