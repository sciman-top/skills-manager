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
        if ($key.StartsWith("--arg=")) {
            $result.args += $t.Substring(6)
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
    Need (($result.transport -eq "stdio") -or ($result.transport -eq "http")) "transport 仅支持 stdio/http；旧 SSE 已弃用"

    if ($result.transport -eq "stdio") {
        Assert-McpKeyValueMapSafe $result.env "--env"
        Assert-McpProcessArgsSafe $result.args '--args'
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
        Assert-McpRemoteUrl ([string]$result.url) ([string]$result.name) ([string]$result.transport)
        Assert-McpKeyValueMapSafe $result.headers "--header"
        if (-not [string]::IsNullOrWhiteSpace([string]$result.bearer_token_env_var)) {
            $result.bearer_token_env_var = [string]$result.bearer_token_env_var.Trim()
            Need (Test-ValidEnvVarName $result.bearer_token_env_var) ("bearer token 环境变量名非法：{0}" -f $result.bearer_token_env_var)
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

function Get-McpServersToPrune($servers) {
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($name in @(Get-LegacyMcpServersToPrune)) {
        if ([string]::IsNullOrWhiteSpace([string]$name)) { continue }
        if (Has-McpServerByName $servers ([string]$name)) { continue }
        $names.Add([string]$name) | Out-Null
    }
    return @($names.ToArray())
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

function Get-McpUserEnvironmentVariable([string]$name) {
    Need (-not [string]::IsNullOrWhiteSpace($name)) "环境变量名不能为空"
    return [System.Environment]::GetEnvironmentVariable($name, "User")
}

function Get-EnvironmentVariableWithScope([string]$name, [string[]]$scopes = @("Process", "User", "Machine")) {
    Need (-not [string]::IsNullOrWhiteSpace($name)) "环境变量名不能为空"
    foreach ($scope in @($scopes)) {
        $value = if ([string]$scope -eq "User") { Get-McpUserEnvironmentVariable $name } else { [System.Environment]::GetEnvironmentVariable($name, $scope) }
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return [pscustomobject]@{
                name = $name
                scope = [string]$scope
                value = [string]$value
            }
        }
    }
    return $null
}

function Convert-PostgresKeyValueConnectionStringToUrl([string]$connectionString) {
    if ([string]::IsNullOrWhiteSpace($connectionString)) { return $null }
    if ($connectionString -match '^\s*postgres(ql)?://') { return $connectionString.Trim() }
    if ($connectionString -notmatch '(?i)(^|;)Host\s*=') { return $null }

    $map = @{}
    foreach ($part in ($connectionString -split ';')) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $pair = $part -split '=', 2
        if ($pair.Count -ne 2) { continue }
        $key = $pair[0].Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        $map[$key] = $pair[1].Trim()
    }

    $hostValue = $map["host"]
    $portValue = $map["port"]
    $databaseValue = $map["database"]
    $userValue = $map["username"]
    if ([string]::IsNullOrWhiteSpace($userValue)) { $userValue = $map["user id"] }
    if ([string]::IsNullOrWhiteSpace($userValue)) { $userValue = $map["userid"] }
    $passwordValue = $map["password"]

    if ([string]::IsNullOrWhiteSpace($hostValue) -or
        [string]::IsNullOrWhiteSpace($portValue) -or
        [string]::IsNullOrWhiteSpace($databaseValue) -or
        [string]::IsNullOrWhiteSpace($userValue) -or
        [string]::IsNullOrWhiteSpace($passwordValue)) {
        return $null
    }

    return ("postgresql://{0}:{1}@{2}:{3}/{4}" -f
        [System.Uri]::EscapeDataString($userValue),
        [System.Uri]::EscapeDataString($passwordValue),
        $hostValue,
        $portValue,
        [System.Uri]::EscapeDataString($databaseValue))
}

function Test-McpServerUsesPostgresConnectionString($server) {
    if ($null -eq $server) { return $false }
    if ([string]::Equals([string]$server.name, "postgres", [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    $text = ""
    if ($server.PSObject.Properties.Match("command").Count -gt 0) { $text += " " + [string]$server.command }
    if ($server.PSObject.Properties.Match("args").Count -gt 0 -and $null -ne $server.args) { $text += " " + (@($server.args) -join " ") }
    return ($text -match 'POSTGRES_CONNECTION_STRING' -or $text -match '@modelcontextprotocol/server-postgres')
}

function Ensure-PostgresMcpEnvironment($servers) {
    $needsPostgres = $false
    foreach ($server in @($servers)) {
        if (-not (Test-McpServerUsesPostgresConnectionString $server)) { continue }

        $hasEnabled = $server.PSObject.Properties.Match("enabled").Count -gt 0
        if ($hasEnabled) {
            Need ($server.enabled -is [bool]) ("mcp_server.enabled 必须是布尔值：{0}" -f [string]$server.name)
            if (-not [bool]$server.enabled) { continue }
        }

        $needsPostgres = $true
        break
    }
    if (-not $needsPostgres) { return }

    $resolved = Get-EnvironmentVariableWithScope "POSTGRES_CONNECTION_STRING"
    Need ($null -ne $resolved) "检测到 postgres MCP，但缺少 POSTGRES_CONNECTION_STRING。请先设置用户级 postgresql:// 连接串。"

    $raw = [string]$resolved.value
    $normalized = Convert-PostgresKeyValueConnectionStringToUrl $raw
    Need (-not [string]::IsNullOrWhiteSpace($normalized)) "检测到 postgres MCP，但 POSTGRES_CONNECTION_STRING 不是可用的 postgresql:// URL，也无法从 Host=...;Port=...;Database=...;Username=...;Password=... 形态转换。"

    # Keep normalization process-scoped. The wrapper also normalizes User/Machine
    # values at invocation time, so sync never persists a database credential.
    $env:POSTGRES_CONNECTION_STRING = $normalized
    if ($raw -ne $normalized -or [string]$resolved.scope -ne "Process") {
        Log ("Postgres MCP 连接串仅注入当前同步进程：source_scope={0}, shape=postgres-url" -f [string]$resolved.scope) "INFO"
    }
}

function Ensure-GhAuthForGithubMcp($servers) {
    $requiresAuthentication = $false
    foreach ($server in @($servers)) {
        if ($null -eq $server -or -not [string]::Equals([string]$server.name, "github", [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $hasEnabled = $server.PSObject.Properties.Match("enabled").Count -gt 0
        if ($hasEnabled) {
            Need ($server.enabled -is [bool]) "mcp_server.enabled 必须是布尔值：github"
            if (-not [bool]$server.enabled) { continue }
        }

        $requiresAuthentication = $true
        break
    }
    if (-not $requiresAuthentication) { return }

    $githubResolved = Get-EnvironmentVariableWithScope "GITHUB_PERSONAL_ACCESS_TOKEN"
    $codexResolved = Get-EnvironmentVariableWithScope "CODEX_GITHUB_PERSONAL_ACCESS_TOKEN"
    $githubToken = if ($null -eq $githubResolved) { "" } else { [string]$githubResolved.value }
    $codexToken = if ($null -eq $codexResolved) { "" } else { [string]$codexResolved.value }
    if (-not [string]::IsNullOrWhiteSpace($githubToken) -and
        -not [string]::IsNullOrWhiteSpace($codexToken) -and
        $githubToken -cne $codexToken) {
        throw "检测到 GitHub MCP，但 GITHUB_PERSONAL_ACCESS_TOKEN 与 CODEX_GITHUB_PERSONAL_ACCESS_TOKEN 不一致；请由操作者统一配置。"
    }
    $token = if (-not [string]::IsNullOrWhiteSpace($codexToken)) { $codexToken } else { $githubToken }
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "检测到 github MCP，但未发现已由操作者配置的 token 环境变量。请设置 GITHUB_PERSONAL_ACCESS_TOKEN 或 CODEX_GITHUB_PERSONAL_ACCESS_TOKEN；不会从 gh credential store 自动复制凭据。"
    }

    # Hydrate only this sync process. User/Machine values remain untouched.
    $env:GITHUB_PERSONAL_ACCESS_TOKEN = $token
    $env:CODEX_GITHUB_PERSONAL_ACCESS_TOKEN = $token
    $sourceScope = if ($null -ne $codexResolved) { [string]$codexResolved.scope } elseif ($null -ne $githubResolved) { [string]$githubResolved.scope } else { "Process" }
    Log ("GitHub MCP 凭据预检通过：source_scope={0}，仅注入当前同步进程。" -f $sourceScope) "INFO"
}

function Test-EnvFlagEnabled([string]$envName) {
    if ([string]::IsNullOrWhiteSpace($envName)) { return $false }
    $raw = [System.Environment]::GetEnvironmentVariable($envName)
    if ([string]::IsNullOrWhiteSpace([string]$raw)) { return $false }
    $v = ([string]$raw).Trim().ToLowerInvariant()
    return ($v -eq "1" -or $v -eq "true" -or $v -eq "yes" -or $v -eq "on")
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
        # Audit facts carry sanitized key lists plus a value digest so that
        # env-only changes still move the fingerprint.
        if ($server.PSObject.Properties.Match("env_keys").Count -gt 0 -and $null -ne $server.env_keys) {
            $sig.env_keys = @($server.env_keys | ForEach-Object { ([string]$_).Trim() } | Sort-Object)
        }
        if ($server.PSObject.Properties.Match("env_signature").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$server.env_signature)) {
            $sig.env_signature = [string]$server.env_signature
        }
    }
    else {
        if ($server.PSObject.Properties.Match("url").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$server.url)) {
            $sig.url = [string]$server.url
        }
        if ($server.PSObject.Properties.Match("headers").Count -gt 0 -and $null -ne $server.headers) {
            $sig.headers = ConvertTo-OrderedSignatureValue $server.headers
        }
        if ($server.PSObject.Properties.Match("header_keys").Count -gt 0 -and $null -ne $server.header_keys) {
            $sig.header_keys = @($server.header_keys | ForEach-Object { ([string]$_).Trim() } | Sort-Object)
        }
        if ($server.PSObject.Properties.Match("header_signature").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$server.header_signature)) {
            $sig.header_signature = [string]$server.header_signature
        }
        if ($server.PSObject.Properties.Match("bearer_token_env_var").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$server.bearer_token_env_var)) {
            $sig.bearer_token_env_var = [string]$server.bearer_token_env_var
        }
    }
    if ($server.PSObject.Properties.Match("enabled").Count -gt 0) {
        Need ($server.enabled -is [bool]) "mcp_server.enabled 必须是布尔值"
        $sig.enabled = [bool]$server.enabled
    }
    if ($server.PSObject.Properties.Match("enabled_tools").Count -gt 0 -and $null -ne $server.enabled_tools) {
        $tools = @()
        foreach ($rawTool in @($server.enabled_tools)) {
            $tool = ([string]$rawTool).Trim()
            Need (-not [string]::IsNullOrWhiteSpace($tool)) "mcp_server.enabled_tools 不得包含空值"
            Need (-not ($tool.Contains("`r") -or $tool.Contains("`n"))) "mcp_server.enabled_tools 不得包含换行"
            if ($tools -notcontains $tool) { $tools += $tool }
        }
        $sig.enabled_tools = @($tools | Sort-Object)
    }
    # startup_timeout_sec 参与 Codex 投影（无效值经 Get-CodexMcpStartupTimeoutSec 归一为忽略）；
    # 不进签名则手改该字段不会移动 MCP 指纹。
    $startupTimeout = Get-CodexMcpStartupTimeoutSec $server
    if ($null -ne $startupTimeout) { $sig.startup_timeout_sec = [int]$startupTimeout }
    return ($sig | ConvertTo-Json -Depth 30 -Compress)
}

function Test-McpServerEquivalent($a, $b) {
    $sa = Get-McpServerSignature $a
    $sb = Get-McpServerSignature $b
    if ([string]::IsNullOrWhiteSpace($sa) -or [string]::IsNullOrWhiteSpace($sb)) { return $false }
    # 大小写敏感比较：command/args/url path/env 键值的仅大小写变更必须移动指纹，
    # 否则同步会误判 unchanged 跳过重写（仓库其余安全比较统一 -ceq）。
    return ($sa -ceq $sb)
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
        $transport = Read-HostSafe "transport（stdio/http，默认 stdio）"
        if ([string]::IsNullOrWhiteSpace($transport)) { $transport = "stdio" }
        $transport = $transport.Trim().ToLowerInvariant()
        if ($transport -ne "stdio" -and $transport -ne "http") {
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

    if ($DryRun) {
        if ($replaced) {
            Write-Host ("DRYRUN：将更新 MCP 服务：{0}" -f $server.name)
        }
        else {
            Write-Host ("DRYRUN：将安装 MCP 服务：{0}" -f $server.name)
        }
    }
    elseif ($replaced) {
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
    Remove-McpProfileServerReferences $cfg @($name) | Out-Null
    SaveCfgSafe $cfg $cfgRaw
    if ($DryRun) {
        Write-Host ("DRYRUN：将卸载 MCP 服务：{0}" -f $name)
    }
    else {
        Write-Host ("已卸载 MCP 服务：{0}" -f $name)
        Invoke-NativeMcpCleanup $name
    }
    同步MCP
}

function Get-McpSyncManagedTargetSpecs {
    param(
        $Roots = @(),
        $CandidatePaths = @(),
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    $specs = New-Object System.Collections.Generic.List[object]
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $flatRoots = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @($Roots)) {
        foreach ($value in @($entry)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) { $flatRoots.Add([string]$value) | Out-Null }
        }
    }

    function Add-McpTargetSpec([string]$Path, [string]$Kind, [string]$Root) {
        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        $key = Normalize-OperationPathKey $Path
        if (-not $seen.Add($key)) { return }
        $specs.Add([pscustomobject][ordered]@{
                path = $Path
                kind = $Kind
                root = $Root
            }) | Out-Null
    }

    foreach ($root in @($flatRoots.ToArray() | Where-Object { -not (Split-Path ([string]$_) -Leaf).Equals('.zcode', [System.StringComparison]::OrdinalIgnoreCase) } | Sort-Object)) {
        Add-McpTargetSpec (Join-Path $root (Get-McpGenericConfigFileName $root)) 'generic_json' $root
    }
    foreach ($root in @($flatRoots.ToArray() | Where-Object { (Split-Path ([string]$_) -Leaf).Equals('.gemini', [System.StringComparison]::OrdinalIgnoreCase) } | Sort-Object)) {
        Add-McpTargetSpec (Join-Path $root 'settings.json') 'gemini_settings' $root
    }
    foreach ($root in @(Resolve-GeminiAntigravityRootsFromCandidates $CandidatePaths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object)) {
        Add-McpTargetSpec (Join-Path $root 'settings.json') 'gemini_antigravity_settings' $root
    }
    foreach ($root in @($flatRoots.ToArray() | Where-Object { (Split-Path ([string]$_) -Leaf).Equals('.codex', [System.StringComparison]::OrdinalIgnoreCase) } | Sort-Object)) {
        Add-McpTargetSpec (Join-Path $root 'config.toml') 'codex_toml' $root
    }
    foreach ($root in @($flatRoots.ToArray() | Where-Object { (Split-Path ([string]$_) -Leaf).Equals('.zcode', [System.StringComparison]::OrdinalIgnoreCase) } | Sort-Object)) {
        Add-McpTargetSpec (Get-ZCodeMcpConfigPath $root) 'zcode_json' $root
    }
    $traeRoots = @($flatRoots.ToArray() | Where-Object { (Split-Path ([string]$_) -Leaf).Equals('.trae', [System.StringComparison]::OrdinalIgnoreCase) } | Sort-Object)
    foreach ($root in $traeRoots) {
        Add-McpTargetSpec (Join-Path $root 'mcp.json') 'trae_json' $root
    }
    if ($traeRoots.Count -gt 0) {
        Add-McpTargetSpec (Get-TraeProjectMcpConfigPath $RepoRoot) 'trae_project_json' $RepoRoot
    }

    return @($specs.ToArray())
}

function Get-McpExistingStateValue($ExistingStates, [string]$Path) {
    if ($null -eq $ExistingStates) {
        return [pscustomobject]@{ exists = $false; content = '' }
    }
    $key = Normalize-OperationPathKey $Path
    if ($ExistingStates -is [System.Collections.IDictionary] -and $ExistingStates.Contains($key)) {
        return $ExistingStates[$key]
    }
    if ($ExistingStates -is [pscustomobject]) {
        $property = @($ExistingStates.PSObject.Properties | Where-Object { $_.Name -eq $key } | Select-Object -First 1)
        if ($property.Count -eq 1) { return $property[0].Value }
    }
    return [pscustomobject]@{ exists = $false; content = '' }
}

function New-McpSyncDesiredState {
    param(
        [object[]]$Specs = @(),
        [object[]]$Servers = @(),
        [object[]]$ActiveServers = @(),
        [string[]]$ProfileDisabledNames = @(),
        [string[]]$PruneNames = @(),
        $ExistingStates = $null
    )

    $desired = New-Object System.Collections.Generic.List[object]
    foreach ($spec in @($Specs)) {
        $path = [string]$spec.path
        $state = Get-McpExistingStateValue $ExistingStates $path
        $existing = if ($null -eq $state -or $null -eq $state.content) { '' } else { [string]$state.content }
        $content = $null

        switch ([string]$spec.kind) {
            'generic_json' {
                $payload = Build-GenericMcpPayload $existing $ActiveServers
                $payload = Remove-McpServersFromPayload $payload @($PruneNames + $ProfileDisabledNames)
                $content = $payload | ConvertTo-Json -Depth 100
            }
            'gemini_settings' {
                $payload = Build-GeminiSettingsPayload $existing $ActiveServers
                $payload = Remove-McpServersFromPayload $payload $ProfileDisabledNames
                $content = $payload | ConvertTo-Json -Depth 100
            }
            'gemini_antigravity_settings' {
                $payload = Build-GeminiSettingsPayload $existing $ActiveServers
                $payload = Remove-McpServersFromPayload $payload $ProfileDisabledNames
                $content = $payload | ConvertTo-Json -Depth 100
            }
            'codex_toml' {
                $content = Build-CodexConfigToml $existing $Servers ([string]$spec.root)
            }
            'zcode_json' {
                $payload = Build-ZCodeMcpPayload $existing $ActiveServers
                $content = $payload | ConvertTo-Json -Depth 100
            }
            'trae_json' {
                $payload = Build-GenericMcpPayload $existing $ActiveServers
                $payload = Remove-McpServersFromPayload $payload $ProfileDisabledNames
                $content = $payload | ConvertTo-Json -Depth 100
            }
            'trae_project_json' {
                $payload = Build-GenericMcpPayload $existing $ActiveServers
                $payload = Remove-McpServersFromPayload $payload $ProfileDisabledNames
                $content = $payload | ConvertTo-Json -Depth 100
            }
            default { throw ('Unsupported MCP managed target kind: {0}' -f [string]$spec.kind) }
        }

        $beforeHash = if ([bool]$state.exists) { Get-OperationSha256 $existing } else { $null }
        $desiredHash = Get-OperationSha256 ([string]$content)
        $desired.Add([pscustomobject][ordered]@{
                target_ref = 'mcp-target-{0}' -f (Get-OperationSha256 (Normalize-OperationPathKey $path)).Substring(0, 16)
                path = $path
                kind = [string]$spec.kind
                root = [string]$spec.root
                owner = 'skills-manager:mcp:{0}' -f [string]$spec.kind
                existed = [bool]$state.exists
                before_hash = $beforeHash
                desired_hash = $desiredHash
                changed = ($beforeHash -ne $desiredHash)
                desired_content = [string]$content
            }) | Out-Null
    }
    return @($desired.ToArray() | Sort-Object target_ref)
}

function New-McpSyncOperationPlanResult {
    param(
        [object[]]$DesiredState = @(),
        [Parameter(Mandatory = $true)][string]$CreatedAt,
        [string]$SourceRevision
    )

    $targets = New-Object System.Collections.Generic.List[object]
    $actions = New-Object System.Collections.Generic.List[object]
    foreach ($target in @($DesiredState)) {
        $targets.Add([pscustomobject][ordered]@{
                target_ref = [string]$target.target_ref
                path = [string]$target.path
                before_hash = $target.before_hash
                desired_hash = [string]$target.desired_hash
                owner = [string]$target.owner
            }) | Out-Null
        if ([bool]$target.changed) {
            $verb = if ([bool]$target.existed) { 'Update' } else { 'Create' }
            $actions.Add([pscustomobject][ordered]@{
                    type = if ([bool]$target.existed) { 'update' } else { 'create' }
                    target_ref = [string]$target.target_ref
                    summary = ('{0} managed MCP target ({1})' -f $verb, [string]$target.kind)
                    risk = 'medium'
                    metadata = [pscustomobject]@{ target_kind = [string]$target.kind }
                }) | Out-Null
        }
    }

    $orderedTargets = @($targets.ToArray() | Sort-Object target_ref)
    $orderedActions = @($actions.ToArray() | Sort-Object target_ref, type)
    $fingerprint = Get-OperationSha256 (($orderedTargets | ConvertTo-Json -Depth 20 -Compress) + '|' + [string]$SourceRevision)
    $plan = New-OperationPlan `
        -OperationId ('mcp-sync-{0}' -f $fingerprint.Substring(0, 16)) `
        -Domain 'mcp' `
        -Mode 'dry_run' `
        -CreatedAt $CreatedAt `
        -SourceRevision $SourceRevision `
        -Targets $orderedTargets `
        -Actions $orderedActions `
        -Preconditions @('skills.json contract valid', 'managed target roots resolved') `
        -Verification @('repo target hashes only; host loading and live acceptance are not claimed') `
        -Rollback @('plan mode performs no managed target or native mutation')

    return [pscustomobject][ordered]@{
        schema_version = 1
        kind = 'mcp_sync_plan'
        operation_plan = $plan
        summary = [pscustomobject][ordered]@{
            managed_target_count = @($DesiredState).Count
            changed_target_count = @($DesiredState | Where-Object changed).Count
            unchanged_target_count = @($DesiredState | Where-Object { -not [bool]$_.changed }).Count
            native_mutation_planned = $false
            profile_changed = $false
            host_loaded = 'not_run'
            live_accepted = 'not_run'
        }
    }
}

function Load-McpPlanConfigReadOnly {
    Need (Test-Path -LiteralPath $CfgPath -PathType Leaf) "缺少配置文件：$CfgPath"
    $raw = Get-ContentUtf8 $CfgPath
    $clean = $raw -replace '(?m)^\s*//.*', ''
    try { $cfg = $clean | ConvertFrom-Json }
    catch { throw ("skills.json 解析失败：{0}" -f $_.Exception.Message) }
    $contract = Get-CfgVersionedContractReport $cfg
    Need (@($contract.errors).Count -eq 0) "skills.json 未通过只读合同校验，plan 不会自动修复配置。"
    $cfg = Normalize-Cfg $cfg
    Assert-Cfg $cfg
    return [pscustomobject]@{ cfg = $cfg; raw = $raw }
}

function Parse-McpSyncPlanOptions([string[]]$Tokens = @()) {
    $json = $false
    $outPath = ''
    $plan = $false
    $items = @($Tokens | Where-Object { $null -ne $_ })
    for ($i = 0; $i -lt $items.Count; $i++) {
        $token = ([string]$items[$i]).Trim()
        switch -Regex ($token) {
            '^(?i)--plan$' { $plan = $true; continue }
            '^(?i)--json$' { $json = $true; continue }
            '^(?i)--out=(.+)$' { $outPath = [string]$Matches[1]; continue }
            '^(?i)--out$' {
                Need (($i + 1) -lt $items.Count) '--out 需要路径值。'
                $i++
                $outPath = [string]$items[$i]
                Need (-not [string]::IsNullOrWhiteSpace($outPath)) '--out 需要非空路径值。'
                continue
            }
            '^$' { continue }
            default { throw ('未知 MCP plan 参数：{0}' -f $token) }
        }
    }
    return [pscustomobject]@{ plan = $plan; json = $json; out_path = $outPath }
}

function Get-McpExistingStates([object[]]$Specs) {
    $states = @{}
    foreach ($spec in @($Specs)) {
        $path = [string]$spec.path
        $exists = Test-Path -LiteralPath $path -PathType Leaf
        $states[(Normalize-OperationPathKey $path)] = [pscustomobject]@{
            exists = $exists
            content = if ($exists) { Get-Content -LiteralPath $path -Raw -Encoding UTF8 } else { '' }
        }
    }
    return $states
}

function Get-McpSyncPlanningContext([switch]$ReadOnlyConfig) {
    # 只读规划上下文（同步MCP --plan）必须无进程副作用：注入 DryRun=true，
    # 使规划链上的 env 复制等副作用守卫一律生效；真实同步（无开关）不受影响。
    $previousDryRun = $DryRun
    if ($ReadOnlyConfig -and -not $DryRun) { $DryRun = $true }
    try {
        $loaded = if ($ReadOnlyConfig) { Load-McpPlanConfigReadOnly } else { [pscustomobject]@{ cfg = (LoadCfg); raw = (Get-ContentUtf8 $CfgPath) } }
        $cfg = $loaded.cfg
        $servers = @(Resolve-McpProfileServers $cfg)
        $activeServers = @(Get-ActiveMcpServers $servers)
        $profileDisabledNames = @($servers | Where-Object { $_.PSObject.Properties.Match('enabled').Count -gt 0 -and -not [bool]$_.enabled } | ForEach-Object { [string]$_.name })
        $pruneNames = @(Get-McpServersToPrune $servers)
        $roots = @(Resolve-McpTargetRootsFromCfg $cfg)
        Need ($roots.Count -gt 0) "未找到可同步的 MCP 目标目录（请检查 targets/mcp_targets 配置）。"
        $candidatePaths = @(Get-McpTargetCandidatePaths $cfg)
        $specs = @(Get-McpSyncManagedTargetSpecs -Roots $roots -CandidatePaths $candidatePaths -RepoRoot $script:Root)
        $existingStates = Get-McpExistingStates $specs
        $desiredState = @(New-McpSyncDesiredState -Specs $specs -Servers $servers -ActiveServers $activeServers -ProfileDisabledNames $profileDisabledNames -PruneNames $pruneNames -ExistingStates $existingStates)
        return [pscustomobject]@{
            cfg = $cfg
            config_raw = [string]$loaded.raw
            config_revision = Get-OperationSha256 ([string]$loaded.raw)
            servers = $servers
            active_servers = $activeServers
            profile_disabled_names = $profileDisabledNames
            prune_names = $pruneNames
            roots = $roots
            desired_state = $desiredState
        }
    }
    finally { $DryRun = $previousDryRun }
}

function Invoke-McpSyncPlan([switch]$Json, [string]$OutPath = '') {
    $context = Get-McpSyncPlanningContext -ReadOnlyConfig
    $createdAt = (Get-Item -LiteralPath $CfgPath).LastWriteTimeUtc.ToString('o')
    $result = New-McpSyncOperationPlanResult -DesiredState $context.desired_state -CreatedAt $createdAt -SourceRevision $context.config_revision
    $validation = Test-OperationPlanContract $result.operation_plan
    Need ([bool]$validation.pass) ("MCP plan contract validation failed: {0}" -f (@($validation.findings.code) -join ', '))
    $serialized = $result | ConvertTo-Json -Depth 50

    if (-not [string]::IsNullOrWhiteSpace($OutPath)) {
        $resolvedOut = Resolve-TargetDir $OutPath
        $parent = Split-Path $resolvedOut -Parent
        if (-not [string]::IsNullOrWhiteSpace($parent)) { EnsureDir $parent }
        Set-ContentUtf8 $resolvedOut $serialized
    }
    if ($Json) {
        Write-Output $serialized
        return
    }
    Write-Host ("MCP plan：targets={0}, changed={1}, unchanged={2}, native=0" -f $result.summary.managed_target_count, $result.summary.changed_target_count, $result.summary.unchanged_target_count)
    foreach ($action in @($result.operation_plan.actions)) {
        $target = @($result.operation_plan.targets | Where-Object target_ref -eq $action.target_ref | Select-Object -First 1)
        Write-Host ("- {0}: {1}" -f $action.type, [string]$target[0].path)
    }
    if (-not [string]::IsNullOrWhiteSpace($OutPath)) { Write-Host ("Plan JSON：{0}" -f (Resolve-TargetDir $OutPath)) }
}

function Write-McpDesiredTarget($target) {
    $path = [string]$target.path
    $parent = Split-Path $path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent)) { EnsureDir $parent }
    if ([string]$target.kind -eq 'codex_toml') { Ensure-CodexMcpNodeCacheWrapper ([string]$target.root) }
    Write-Utf8FileAtomic -Path $path -Content ([string]$target.desired_content)
    switch ([string]$target.kind) {
        'gemini_settings' { Log ("已同步 Gemini MCP 配置：{0}" -f $path) }
        'gemini_antigravity_settings' { Log ("已同步 Gemini Antigravity MCP 配置：{0}" -f $path) }
        'codex_toml' { Log ("已同步 Codex MCP 配置：{0}" -f $path) }
        'zcode_json' { Log ("已同步 ZCode MCP 配置：{0}" -f $path) }
        'trae_json' { Log ("已同步 Trae MCP 配置：{0}" -f $path) }
        'trae_project_json' { Log ("已同步项目级 Trae MCP 配置：{0}" -f $path) }
        default { Log ("已同步 MCP 配置：{0}" -f $path) }
    }
}

function Test-McpTargetReparsePath([string]$Path,[string]$Root) {
    $cursor=[IO.Path]::GetFullPath($Path);$boundary=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    while($true){
        if([IO.File]::Exists($cursor) -or [IO.Directory]::Exists($cursor)){if(([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $true}}
        if($cursor.TrimEnd('\','/').Equals($boundary,[StringComparison]::OrdinalIgnoreCase)){break}
        $parent=[IO.Directory]::GetParent($cursor);if($null -eq $parent -or -not (Test-OperationPathWithinRoot $parent.FullName $boundary)){break};$cursor=$parent.FullName
    }
    return $false
}

function Assert-McpDesiredStateFresh([object[]]$DesiredState,[string]$ExpectedConfigRevision='') {
    if(-not [string]::IsNullOrWhiteSpace($ExpectedConfigRevision)){
        $currentConfigRevision=Get-OperationSha256 (Get-ContentUtf8 $CfgPath)
        Need ($currentConfigRevision -eq $ExpectedConfigRevision) 'MCP source_revision_stale：skills.json changed after planning.'
    }
    foreach($target in @($DesiredState)){
        $path=[IO.Path]::GetFullPath([string]$target.path);$root=[IO.Path]::GetFullPath([string]$target.root)
        Need (Test-OperationPathWithinRoot $path $root) ("MCP target_out_of_root：{0}" -f $path)
        Need (-not (Test-McpTargetReparsePath $path $root)) ("MCP target_reparse_forbidden：{0}" -f $path)
        Need (-not (Test-AncestorChainHasReparse $root)) ("MCP target_root_ancestor_reparse_forbidden：{0}" -f $root)
        $exists=Test-Path -LiteralPath $path -PathType Leaf;$before=$target.before_hash
        if($null -eq $before){Need (-not $exists) ("MCP target_created_since_plan：{0}" -f $path)}
        else{Need $exists ("MCP target_missing_since_plan：{0}" -f $path);Need ((Get-OperationSha256 (Get-ContentUtf8 $path)) -eq [string]$before) ("MCP target_hash_stale：{0}" -f $path)}
    }
}

function Restore-McpManagedTargetSnapshot([object[]]$Snapshot) {
    $conflicts=New-Object System.Collections.Generic.List[string]
    $failures=New-Object System.Collections.Generic.List[string]
    foreach($entry in @($Snapshot)){
        $path=[string]$entry.path
        try {
        if(Test-AncestorChainHasReparse $path){$conflicts.Add($path)|Out-Null;continue}
        $item=Get-ExistingFileSystemItem $path
        if($null -eq $item){
            # Managed writes never delete an existing target. Its disappearance
            # therefore belongs to another writer, not to our rollback.
            if([bool]$entry.existed){$conflicts.Add($path)|Out-Null}
            continue
        }
        if($item.PSIsContainer){$conflicts.Add($path)|Out-Null;continue}
        if(Test-Path -LiteralPath $path -PathType Leaf){
            $currentHash=Get-OperationSha256 (Get-ContentUtf8 $path)
            if([bool]$entry.existed -and $currentHash -eq [string]$entry.before_hash){continue}
            $allowed=@([string]$entry.before_hash,[string]$entry.desired_hash)|Where-Object{-not [string]::IsNullOrWhiteSpace($_)}
            if($currentHash -notin $allowed){$conflicts.Add($path)|Out-Null;continue}
        }
        if([bool]$entry.existed){Write-BytesAtomic -Path $path -Bytes ([byte[]]$entry.bytes)}
        elseif(Test-Path -LiteralPath $path -PathType Leaf){Remove-Item -LiteralPath $path -Force}
        }
        catch { $failures.Add(('{0}: {1}' -f $path,$_.Exception.Message))|Out-Null }
    }
    Need ($conflicts.Count -eq 0 -and $failures.Count -eq 0) ("MCP rollback_conflict/recovery_failed: conflicts=[{0}]; errors=[{1}]" -f ($conflicts -join ', '),($failures -join '; '))
}

function Get-McpImplicitSidecarTargets([object[]]$DesiredState) {
    $targets=New-Object System.Collections.Generic.List[object]
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($target in @($DesiredState|Where-Object{[string]$_.kind -eq 'codex_toml'})){
        $root=[IO.Path]::GetFullPath([string]$target.root)
        $nodePath=Join-Path $root 'scripts/mcp-node-cache-wrapper.mjs'
        if($seen.Add($nodePath)){$targets.Add([pscustomobject]@{path=$nodePath;root=$root;desired_content=(Get-CodexMcpNodeCacheWrapperContent);changed=$false})|Out-Null}
        $postgresPath=Join-Path $root 'scripts/mcp-postgres-env-wrapper.mjs'
        if($seen.Add($postgresPath)){$targets.Add([pscustomobject]@{path=$postgresPath;root=$root;desired_content=(Get-CodexMcpPostgresEnvWrapperContent);changed=$false})|Out-Null}
    }
    return @($targets.ToArray())
}

function Remove-McpCreatedRootIfEmpty([string]$Root) {
    if(-not (Test-Path -LiteralPath $Root -PathType Container)){return}
    if(Test-McpTargetReparsePath $Root $Root){return}
    $files=@([IO.Directory]::GetFiles($Root,'*',[IO.SearchOption]::AllDirectories))
    if($files.Count -gt 0){return}
    $reparse=@([IO.Directory]::GetFileSystemEntries($Root,'*',[IO.SearchOption]::AllDirectories)|Where-Object{([IO.File]::GetAttributes($_)-band [IO.FileAttributes]::ReparsePoint)-ne 0})
    if($reparse.Count -gt 0){return}
    Remove-Item -LiteralPath $Root -Recurse -Force
}

function Invoke-McpManagedTargetTransaction([object[]]$DesiredState,[string]$ExpectedConfigRevision='') {
    $lockEntries=New-Object System.Collections.Generic.List[object]
    $snapshot=New-Object System.Collections.Generic.List[object]
    $createdRoots=New-Object System.Collections.Generic.List[string]
    $transactionSucceeded=$false
    try{
        $roots=@($DesiredState|ForEach-Object{[IO.Path]::GetFullPath([string]$_.root)}|Sort-Object -Unique)
        foreach($root in $roots){
            $drive=[IO.Path]::GetPathRoot($root).TrimEnd('\','/');$trimmed=$root.TrimEnd('\','/')
            Need (-not $trimmed.Equals($drive,[StringComparison]::OrdinalIgnoreCase)) ("MCP target_root_forbidden：{0}" -f $root)
            if(Test-Path -LiteralPath $root){Need (Test-Path -LiteralPath $root -PathType Container) ("MCP target_root_not_directory：{0}" -f $root);continue}
            $parent=[IO.Directory]::GetParent($root)
            Need ($null -ne $parent -and (Test-Path -LiteralPath $parent.FullName -PathType Container)) ("MCP target_root_parent_missing：{0}" -f $root)
            Need (-not (Test-McpTargetReparsePath $parent.FullName $parent.FullName)) ("MCP target_root_parent_reparse_forbidden：{0}" -f $root)
        }
        foreach($root in $roots){
            if(-not (Test-Path -LiteralPath $root -PathType Container)){[IO.Directory]::CreateDirectory($root)|Out-Null;$createdRoots.Add($root)|Out-Null}
            Need (-not (Test-McpTargetReparsePath $root $root)) ("MCP target_reparse_forbidden：{0}" -f $root)
            $lockPath=Join-Path $root '.skills-manager-mcp-sync.lock'
            $stream=Request-McpSyncLock $lockPath
            $lockEntries.Add([pscustomobject]@{path=$lockPath;stream=$stream})|Out-Null
        }
        Assert-McpDesiredStateFresh $DesiredState $ExpectedConfigRevision
        foreach($target in @($DesiredState)){
            $path=[string]$target.path;$exists=Test-Path -LiteralPath $path -PathType Leaf
            $snapshot.Add([pscustomobject]@{path=$path;existed=$exists;bytes=$(if($exists){[IO.File]::ReadAllBytes($path)}else{[byte[]]::new(0)});before_hash=$target.before_hash;desired_hash=(Get-OperationSha256 ([string]$target.desired_content))})|Out-Null
        }
        $sidecars=@(Get-McpImplicitSidecarTargets $DesiredState)
        foreach($sidecar in $sidecars){
            $path=[IO.Path]::GetFullPath([string]$sidecar.path);$root=[IO.Path]::GetFullPath([string]$sidecar.root)
            Need (Test-OperationPathWithinRoot $path $root) ("MCP sidecar_out_of_root：{0}" -f $path)
            Need (-not (Test-McpTargetReparsePath $path $root)) ("MCP sidecar_reparse_forbidden：{0}" -f $path)
            $exists=Test-Path -LiteralPath $path -PathType Leaf
            $beforeHash=$(if($exists){Get-OperationSha256 (Get-ContentUtf8 $path)}else{$null})
            $sidecar|Add-Member -NotePropertyName before_hash -NotePropertyValue $beforeHash -Force
            $sidecar|Add-Member -NotePropertyName desired_hash -NotePropertyValue (Get-OperationSha256 ([string]$sidecar.desired_content)) -Force
            $sidecar|Add-Member -NotePropertyName changed -NotePropertyValue ($beforeHash -ne [string]$sidecar.desired_hash) -Force
            $snapshot.Add([pscustomobject]@{path=$path;existed=$exists;bytes=$(if($exists){[IO.File]::ReadAllBytes($path)}else{[byte[]]::new(0)});before_hash=$beforeHash;desired_hash=(Get-OperationSha256 ([string]$sidecar.desired_content))})|Out-Null
        }
        $targetsToWrite = @($DesiredState | Where-Object {
            if ([bool]$_.changed) { return $true }
            if ([string]$_.kind -ne 'codex_toml') { return $false }
            $targetRoot = [IO.Path]::GetFullPath([string]$_.root)
            return @($sidecars | Where-Object { [IO.Path]::GetFullPath([string]$_.root) -eq $targetRoot -and [bool]$_.changed }).Count -gt 0
        })
        foreach($target in $targetsToWrite){
            Assert-McpDesiredStateFresh @($target) $ExpectedConfigRevision
            if([string]$target.kind -eq 'codex_toml'){
                $targetRoot=[IO.Path]::GetFullPath([string]$target.root)
                foreach($sidecar in @($sidecars|Where-Object{[IO.Path]::GetFullPath([string]$_.root) -eq $targetRoot})){
                    if (-not [bool]$target.changed -and -not [bool]$sidecar.changed) { continue }
                    $exists=Test-Path -LiteralPath $sidecar.path -PathType Leaf
                    if($null -eq $sidecar.before_hash){Need (-not $exists) ("MCP sidecar_created_since_lock：{0}" -f $sidecar.path)}
                    else{Need $exists ("MCP sidecar_missing_since_lock：{0}" -f $sidecar.path);Need ((Get-OperationSha256 (Get-ContentUtf8 $sidecar.path)) -eq [string]$sidecar.before_hash) ("MCP sidecar_hash_stale：{0}" -f $sidecar.path)}
                }
            }
            Write-McpDesiredTarget $target
        }
        $transactionSucceeded=$true
        return [pscustomobject]@{pass=$true;writes=$targetsToWrite.Count;sidecar_writes=@($sidecars|Where-Object changed).Count;snapshot=@($snapshot.ToArray());rollback_policy='managed_files_only_before_native_effects'}
    }catch{
        # 还原自身失败时不得替换原始同步异常：聚合两者保留完整故障定位入口。
        $syncError=$_.Exception.Message
        if($snapshot.Count -gt 0){try{Restore-McpManagedTargetSnapshot @($snapshot.ToArray())}catch{throw ('MCP managed target rollback failed: {0}; sync failure: {1}' -f $_.Exception.Message,$syncError)}}
        throw
    }finally{
        foreach($lock in @($lockEntries.ToArray())){$lock.stream.Dispose();if(Test-Path -LiteralPath $lock.path -PathType Leaf){Remove-Item -LiteralPath $lock.path -Force -ErrorAction SilentlyContinue}}
        if(-not $transactionSucceeded){foreach($root in @($createdRoots.ToArray())|Sort-Object Length -Descending){Remove-McpCreatedRootIfEmpty $root}}
    }
}

function Request-McpSyncLock([string]$LockPath) {
    # CreateNew 独占锁：进程硬杀后锁文件会残留并永久阻塞后续同步。
    # 超过 15 分钟的陈锁视为硬杀残留做接管；新近锁仍 fail closed（可能存在并发同步）。
    try {
        return [IO.File]::Open($LockPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    }
    catch [IO.IOException] {
        $staleAfterMinutes = 15
        $lockItem = Get-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue
        if ($null -ne $lockItem -and $lockItem.LastWriteTimeUtc -lt (Get-Date).ToUniversalTime().AddMinutes(-$staleAfterMinutes)) {
            Log ("检测到陈旧 MCP 同步锁（超过 {0} 分钟，疑似进程硬杀残留），已接管：{1}" -f $staleAfterMinutes, $LockPath) "WARN"
            Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue
            return [IO.File]::Open($LockPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        }
        throw ("MCP 同步锁不可用（存在并发同步或新近残留锁；确认无并发后可删除锁文件重试）：{0}；原因：{1}" -f $LockPath, $_.Exception.Message)
    }
}

function 同步MCP {
    & {
        $script:SkipNativeMcpForSession = $false
        $context = Get-McpSyncPlanningContext
        if (-not $DryRun) {
            Ensure-PostgresMcpEnvironment $context.active_servers
            Ensure-GhAuthForGithubMcp $context.active_servers
        }

        $managedTransaction=$null
        foreach ($target in @($context.desired_state)) { if ($DryRun) { Write-Host ("DRYRUN：将写入 MCP 配置 -> {0}" -f [string]$target.path) } }
        if(-not $DryRun){$managedTransaction=Invoke-McpManagedTargetTransaction -DesiredState @($context.desired_state) -ExpectedConfigRevision ([string]$context.config_revision)}

        $nativeMutationEnabled=Should-RunNativeMcpSync
        try{
            Write-Host ("已同步 MCP 服务配置到 {0} 个目标。" -f @($context.desired_state).Count)
            foreach ($pruneName in @($context.prune_names)) { Invoke-NativeMcpCleanup $pruneName }
            Invoke-NativeMcpSync $context.active_servers
            if (-not $DryRun) {
                $attemptsParsed = 0
                $intervalParsed = 0
                $attempts = if ([int]::TryParse([string]$env:SKILLS_MCP_VERIFY_ATTEMPTS, [ref]$attemptsParsed)) { $attemptsParsed } else { 6 }
                $intervalSeconds = if ([int]::TryParse([string]$env:SKILLS_MCP_VERIFY_INTERVAL_SECONDS, [ref]$intervalParsed)) { $intervalParsed } else { 3 }
                if ($attempts -lt 1) { $attempts = 1 }
                if ($intervalSeconds -lt 1) { $intervalSeconds = 1 }
                Verify-McpAcrossCliWithRetry $context.roots $attempts $intervalSeconds
            }
        }catch{
            if($null -ne $managedTransaction -and -not $nativeMutationEnabled){Restore-McpManagedTargetSnapshot @($managedTransaction.snapshot)}
            elseif($null -ne $managedTransaction){Log 'MCP managed files were retained because opt-in native side effects may already have occurred and cannot be transactionally compensated.' 'WARN'}
            throw
        }
        if (@($context.servers).Count -eq 0) { Write-Host "提示：当前 mcp_servers 为空，已将各目标写为空配置。" }
    }
}
