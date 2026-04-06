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
    $result.name = Normalize-NameWithNotice $result.name "MCP 服务名"

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
    }

    return [pscustomobject]$result
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

function Get-NativeMcpKeyValueFlags($data, [string]$flagName) {
    $flags = @()
    if ($null -eq $data) { return $flags }

    if ($data -is [hashtable] -or $data -is [System.Collections.IDictionary]) {
        foreach ($k in $data.Keys) {
            $key = [string]$k
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            $value = [string]$data[$k]
            $flags += @($flagName, ("{0}={1}" -f $key, $value))
        }
        return $flags
    }

    if ($data -is [pscustomobject]) {
        foreach ($p in $data.PSObject.Properties) {
            $key = [string]$p.Name
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            $value = [string]$p.Value
            $flags += @($flagName, ("{0}={1}" -f $key, $value))
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
        $headerFlags = Get-NativeMcpKeyValueFlags $server.headers "-H"
    }
    if ($headerFlags.Count -gt 0) { $args += $headerFlags }
    $url = if ($server.PSObject.Properties.Match("url").Count -gt 0) { [string]$server.url } else { "" }
    Need (-not [string]::IsNullOrWhiteSpace($url)) ("{0} MCP 缺少 url：{1}" -f $transport, $name)
    $args += @("--transport", $transport, $name, $url)
    return $args
}

function Invoke-NativeMcpSync($servers) {
    if (-not (Get-Command "claude" -ErrorAction SilentlyContinue)) {
        Log "未检测到 claude 命令，已跳过原生 MCP 同步（仅写入 .mcp.json）。" "WARN"
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
                Write-Host ("DRYRUN：将执行原生 MCP 同步 -> {0}" -f $cmdText)
                continue
            }
            Push-Location $script:Root
            try { & claude @args | Out-Host } finally { Pop-Location }
            Log ("已同步原生 MCP：{0}（scope={1}）" -f [string]$s.name, $scope)
        }
        catch {
            Log ("原生 MCP 同步失败（已忽略）：{0}（scope={1}） -> {2}" -f [string]$s.name, $scope, $_.Exception.Message) "WARN"
        }
    }
}

function Get-NativeMcpCleanupCommands([string]$name) {
    Need (-not [string]::IsNullOrWhiteSpace($name)) "MCP 服务名不能为空"
    return @(
        [pscustomobject]@{ command = "claude"; args = @("mcp", "remove", $name, "--scope", "user"); project = $false }
        [pscustomobject]@{ command = "claude"; args = @("mcp", "remove", $name); project = $true }
    )
}

function Invoke-NativeMcpCleanup([string]$name) {
    $ops = Get-NativeMcpCleanupCommands $name
    foreach ($op in $ops) {
        if (-not (Get-Command $op.command -ErrorAction SilentlyContinue)) { continue }
        $cmdText = "{0} {1}" -f $op.command, (($op.args | ForEach-Object { [string]$_ }) -join " ")
        if ($DryRun) {
            Write-Host ("DRYRUN：清理原生 MCP -> {0}" -f $cmdText)
            continue
        }
        try {
            if ($op.project) {
                Push-Location $script:Root
                try { & $op.command @($op.args) | Out-Host } finally { Pop-Location }
            }
            else {
                & $op.command @($op.args) | Out-Host
            }
            Log ("已执行原生 MCP 清理：{0}" -f $cmdText)
        }
        catch {
            Log ("原生 MCP 清理失败（已忽略）：{0} -> {1}" -f $cmdText, $_.Exception.Message) "WARN"
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
    $base["mcpServers"] = Convert-McpServersToGeminiConfigMap $servers
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
    $kept = New-Object System.Collections.Generic.List[string]
    $skipMcpSection = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*\[mcp_servers\.[^\]]+\]\s*$') {
            $skipMcpSection = $true
            continue
        }
        if ($skipMcpSection -and $line -match '^\s*\[[^\]]+\]\s*$') {
            $skipMcpSection = $false
        }
        if (-not $skipMcpSection) {
            $kept.Add($line) | Out-Null
        }
    }

    while ($kept.Count -gt 0 -and [string]::IsNullOrWhiteSpace($kept[$kept.Count - 1])) {
        $kept.RemoveAt($kept.Count - 1)
    }

    $output = New-Object System.Collections.Generic.List[string]
    $output.AddRange([string[]](Apply-CodexPermissionDefaults @([string[]]$kept.ToArray())))

    $map = Convert-McpServersToConfigMap $servers
    $names = @($map.PSObject.Properties.Name | Sort-Object)
    if ($names.Count -gt 0) {
        if ($output.Count -gt 0) { $output.Add("") | Out-Null }
        foreach ($name in $names) {
            $entry = $map.$name
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

function 安装MCP([string[]]$tokens = @()) {
    $cfg = LoadCfg
    $cfgRaw = Get-Content $CfgPath -Raw

    $tokenList = @($tokens | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
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
    $updated = @()
    $replaced = $false
    foreach ($s in $existing) {
        if ([string]$s.name -eq [string]$server.name) {
            $updated += $server
            $replaced = $true
        }
        else {
            $updated += $s
        }
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
        $cfg = LoadCfg
        $servers = @($cfg.mcp_servers)

        $roots = Resolve-McpTargetRootsFromCfg $cfg
        Need ($roots.Count -gt 0) "未找到可同步的 MCP 目标目录（请检查 targets/mcp_targets 配置）。"
        $candidatePaths = Get-McpTargetCandidatePaths $cfg

        $payload = [ordered]@{
            mcpServers = Convert-McpServersToConfigMap $servers
        }
        $json = $payload | ConvertTo-Json -Depth 50

        $written = @()
        foreach ($targetRoot in $roots) {
            $file = Join-Path $targetRoot ".mcp.json"
            if ($DryRun) {
                Write-Host ("DRYRUN：将写入 MCP 配置 -> {0}" -f $file)
                $written += $file
                continue
            }
            EnsureDir $targetRoot
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
            Set-ContentUtf8 $projectTraePath $json
            $written += $projectTraePath
            Log ("已同步项目级 Trae MCP 配置：{0}" -f $projectTraePath)
        }

        Write-Host ("已同步 MCP 服务配置到 {0} 个目标。" -f $written.Count)
        Invoke-NativeMcpSync $servers
        if ($servers.Count -eq 0) {
            Write-Host "提示：当前 mcp_servers 为空，已将各目标写为空配置。"
        }
    } @{ command = "同步MCP" } -NoHost
}
