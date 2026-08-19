function Parse-KeyValueToken([string]$token, [string]$flagName) {
    Need (-not [string]::IsNullOrWhiteSpace($token)) ("{0} 参数不能为空" -f $flagName)
    $pair = $token.Split("=", 2)
    Need ($pair.Count -eq 2) ("{0} 参数格式必须是 KEY=VALUE：{1}" -f $flagName, $token)
    $key = $pair[0].Trim()
    Need (-not [string]::IsNullOrWhiteSpace($key)) ("{0} 参数的 KEY 不能为空：{1}" -f $flagName, $token)
    Need ($key -notmatch '[\r\n]') ("{0} 参数的 KEY 不能包含换行：{1}" -f $flagName, $token)
    Need ($pair[1] -notmatch '[\r\n]') ("{0} 参数的 VALUE 不能包含换行：{1}" -f $flagName, $token)
    return [pscustomobject]@{
        key = $key
        value = $pair[1]
    }
}

function Resolve-McpProfileServers($cfg) {
    $baseServers = @($cfg.mcp_servers)
    if ($cfg.PSObject.Properties.Match("mcp_profiles").Count -eq 0 -or $null -eq $cfg.mcp_profiles) {
        return $baseServers
    }

    $profileCfg = $cfg.mcp_profiles
    $active = ([string]$profileCfg.active).Trim()
    Need (-not [string]::IsNullOrWhiteSpace($active)) "mcp_profiles.active 不能为空"
    Need ($profileCfg.PSObject.Properties.Match("profiles").Count -gt 0 -and $null -ne $profileCfg.profiles) "mcp_profiles 缺少 profiles"
    $profileProperty = @($profileCfg.profiles.PSObject.Properties | Where-Object { [string]::Equals($_.Name, $active, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    Need ($profileProperty.Count -eq 1) ("mcp_profiles.active 不存在：{0}" -f $active)
    $profile = $profileProperty[0].Value
    Need ($null -ne $profile -and $profile.PSObject.Properties.Match("enabled").Count -gt 0) ("MCP profile 缺少 enabled：{0}" -f $active)

    $knownNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($server in $baseServers) { $knownNames.Add([string]$server.name) | Out-Null }
    $enabledNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($rawName in @($profile.enabled)) {
        $name = ([string]$rawName).Trim()
        Need (-not [string]::IsNullOrWhiteSpace($name)) ("MCP profile enabled 不得包含空值：{0}" -f $active)
        Need ($knownNames.Contains($name)) ("MCP profile 引用了不存在的服务：{0}/{1}" -f $active, $name)
        $enabledNames.Add($name) | Out-Null
    }

    $toolOverrides = $null
    if ($profile.PSObject.Properties.Match("enabled_tools").Count -gt 0 -and $null -ne $profile.enabled_tools) {
        $toolOverrides = $profile.enabled_tools
        foreach ($property in @($toolOverrides.PSObject.Properties)) {
            Need ($knownNames.Contains([string]$property.Name)) ("MCP profile enabled_tools 引用了不存在的服务：{0}/{1}" -f $active, [string]$property.Name)
        }
    }

    $projected = New-Object System.Collections.Generic.List[object]
    foreach ($server in $baseServers) {
        $copy = [ordered]@{}
        foreach ($property in $server.PSObject.Properties) {
            $copy[[string]$property.Name] = $property.Value
        }
        $name = [string]$server.name
        $copy["enabled"] = $enabledNames.Contains($name)
        if ($null -ne $toolOverrides) {
            $toolProperty = @($toolOverrides.PSObject.Properties | Where-Object { [string]::Equals($_.Name, $name, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
            if ($toolProperty.Count -eq 1) {
                $tools = New-Object System.Collections.Generic.List[string]
                foreach ($rawTool in @($toolProperty[0].Value)) {
                    $tool = ([string]$rawTool).Trim()
                    Need (-not [string]::IsNullOrWhiteSpace($tool)) ("MCP profile enabled_tools 不得包含空值：{0}/{1}" -f $active, $name)
                    if (-not $tools.Contains($tool)) { $tools.Add($tool) | Out-Null }
                }
                $copy["enabled_tools"] = @($tools.ToArray())
            }
        }
        $projected.Add([pscustomobject]$copy) | Out-Null
    }
    return @($projected.ToArray())
}

function Remove-McpProfileServerReferences($cfg, [string[]]$serverNames) {
    if ($null -eq $cfg -or $cfg.PSObject.Properties.Match("mcp_profiles").Count -eq 0 -or $null -eq $cfg.mcp_profiles) {
        return $false
    }
    if ($cfg.mcp_profiles.PSObject.Properties.Match("profiles").Count -eq 0 -or $null -eq $cfg.mcp_profiles.profiles) {
        return $false
    }

    $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($rawName in @($serverNames)) {
        $name = ([string]$rawName).Trim()
        if (-not [string]::IsNullOrWhiteSpace($name)) { $names.Add($name) | Out-Null }
    }
    if ($names.Count -eq 0) { return $false }

    $changed = $false
    foreach ($profileProperty in @($cfg.mcp_profiles.profiles.PSObject.Properties)) {
        $profile = $profileProperty.Value
        if ($null -eq $profile) { continue }

        if ($profile.PSObject.Properties.Match("enabled").Count -gt 0) {
            $remaining = New-Object System.Collections.Generic.List[object]
            foreach ($rawName in @($profile.enabled)) {
                if ($names.Contains(([string]$rawName).Trim())) {
                    $changed = $true
                    continue
                }
                $remaining.Add($rawName) | Out-Null
            }
            $profile.enabled = @($remaining.ToArray())
        }

        if ($profile.PSObject.Properties.Match("enabled_tools").Count -gt 0 -and $null -ne $profile.enabled_tools) {
            foreach ($toolProperty in @($profile.enabled_tools.PSObject.Properties)) {
                if (-not $names.Contains([string]$toolProperty.Name)) { continue }
                $profile.enabled_tools.PSObject.Properties.Remove([string]$toolProperty.Name)
                $changed = $true
            }
        }
    }
    return $changed
}

function Get-ActiveMcpServers($servers) {
    return @($servers | Where-Object { $_.PSObject.Properties.Match("enabled").Count -eq 0 -or [bool]$_.enabled })
}

function Invoke-McpProfileCommand([string[]]$tokens) {
    $cfg = LoadCfg
    Need ($cfg.PSObject.Properties.Match("mcp_profiles").Count -gt 0 -and $null -ne $cfg.mcp_profiles) "未配置 mcp_profiles"
    $profileCfg = $cfg.mcp_profiles
    $action = if ($null -eq $tokens -or $tokens.Count -eq 0) { "列表" } else { ([string]$tokens[0]).Trim().ToLowerInvariant() }
    if ($action -in @("列表", "list")) {
        foreach ($property in @($profileCfg.profiles.PSObject.Properties | Sort-Object Name)) {
            $marker = if ([string]::Equals($property.Name, [string]$profileCfg.active, [System.StringComparison]::OrdinalIgnoreCase)) { "*" } else { " " }
            Write-Host ("{0} {1} ({2})" -f $marker, $property.Name, (@($property.Value.enabled) -join ", "))
        }
        return
    }
    Need ($action -in @("使用", "use")) ("MCP配置仅支持 列表/list 或 使用/use：{0}" -f $action)
    Need ($tokens.Count -ge 2) "MCP配置 使用 缺少 profile 名称"
    $name = ([string]$tokens[1]).Trim()
    $profileProperty = @($profileCfg.profiles.PSObject.Properties | Where-Object { [string]::Equals($_.Name, $name, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    Need ($profileProperty.Count -eq 1) ("MCP profile 不存在：{0}" -f $name)
    $profileCfg.active = [string]$profileProperty[0].Name
    $servers = @(Resolve-McpProfileServers $cfg)
    $raw = Get-ContentUtf8 $CfgPath
    SaveCfgSafe $cfg $raw
    Write-Host ("已使用 MCP profile：{0}；enabled={1}" -f $name, (@($servers | Where-Object enabled | ForEach-Object name) -join ", "))
    同步MCP
}

function Test-ValidEnvVarName([string]$name) {
    if ([string]::IsNullOrWhiteSpace($name)) { return $false }
    return ($name.Trim() -match '^[A-Za-z_][A-Za-z0-9_]*$')
}

function Assert-McpRemoteUrl([string]$url, [string]$name, [string]$transport) {
    Need (-not [string]::IsNullOrWhiteSpace($url)) ("{0} MCP 缺少 url：{1}" -f $transport, $name)
    $parsed = $null
    if (-not [System.Uri]::TryCreate($url, [System.UriKind]::Absolute, [ref]$parsed)) {
        throw ("{0} MCP URL 非法（需要绝对 http/https URL）：{1}" -f $transport, $name)
    }
    if ($parsed.Scheme -ne [System.Uri]::UriSchemeHttp -and $parsed.Scheme -ne [System.Uri]::UriSchemeHttps) {
        throw ("{0} MCP URL 非法（仅支持 http/https）：{1}" -f $transport, $name)
    }
    Need ([string]::IsNullOrWhiteSpace($parsed.UserInfo)) ("{0} MCP URL 不允许内嵌 userinfo/credential：{1}" -f $transport, $name)
    if (-not [string]::IsNullOrWhiteSpace($parsed.Query)) {
        foreach ($part in @($parsed.Query.TrimStart('?') -split '&')) {
            if ([string]::IsNullOrWhiteSpace($part)) { continue }
            $queryKey = [Uri]::UnescapeDataString(($part -split '=', 2)[0])
            Need (-not (Test-McpSensitiveKeyName $queryKey)) ("{0} MCP URL 不允许在 query 中携带敏感字段；请改用环境变量引用或 bearer_token_env_var：{1}" -f $transport, $queryKey)
        }
    }
}

function Test-McpSensitiveKeyName([string]$name) {
    if ([string]::IsNullOrWhiteSpace($name)) { return $false }
    return ($name -match '(?i)(authorization|proxy-authorization|cookie|token|secret|password|passwd|api[-_]?key|private[-_]?key|credential)')
}

function Test-McpEnvironmentTemplate([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return $false }
    return ($value.Trim() -match '^(?:(?:Bearer|Basic)\s+)?\$\{[A-Za-z_][A-Za-z0-9_]*\}$')
}

function Assert-McpKeyValueMapSafe($data, [string]$label) {
    if ($null -eq $data) { return }
    $items = @()
    if ($data -is [hashtable] -or $data -is [System.Collections.IDictionary]) {
        $items = @($data.GetEnumerator())
    }
    elseif ($data -is [pscustomobject]) {
        $items = @($data.PSObject.Properties | ForEach-Object {
                [pscustomobject]@{ Key = [string]$_.Name; Value = $_.Value }
            })
    }
    foreach ($item in $items) {
        $key = [string]$item.Key
        $value = if ($null -eq $item.Value) { "" } else { [string]$item.Value }
        Need ($key -notmatch '[\r\n]') ("{0} key 不能包含换行：{1}" -f $label, $key)
        Need ($value -notmatch '[\r\n]') ("{0} value 不能包含换行：{1}" -f $label, $key)
        if (Test-McpSensitiveKeyName $key) {
            Need (Test-McpEnvironmentTemplate $value) ("{0} 敏感字段不得保存 literal value；请使用 `${{ENV_VAR}} 引用：{1}" -f $label, $key)
        }
    }
}

function Assert-McpProcessArgsSafe([object[]]$ProcessArgs,[string]$Label='args') {
    $items=@($ProcessArgs|ForEach-Object{[string]$_})
    for($i=0;$i -lt $items.Count;$i++){
        $item=$items[$i]
        Need ($item -notmatch '[\r\n]') ("{0} 不能包含换行。" -f $Label)
        Need ($item -notmatch '(?i)\b(?:https?|postgres(?:ql)?)://[^/@\s:]+:[^/@\s]+@') ("{0} 不允许内嵌 URL credential；请改用环境变量模板。" -f $Label)
        Need ($item -notmatch '(?i)\b(?:github_pat_[A-Za-z0-9_]+|gh[pousr]_[A-Za-z0-9_]+)\b') ("{0} 不允许 literal access token；请改用环境变量模板。" -f $Label)
        if($item -match '^(?i)(--?(?:access[-_]?key|api[-_]?key|authorization|password|passwd|secret|token))=(.*)$'){
            Need (Test-McpEnvironmentTemplate ([string]$Matches[2])) ("{0} 敏感参数不得保存 literal value：{1}" -f $Label,$Matches[1])
        }
        elseif($item -match '^(?i)--?(?:access[-_]?key|api[-_]?key|authorization|password|passwd|secret|token)$'){
            Need (($i+1) -lt $items.Count -and (Test-McpEnvironmentTemplate $items[$i+1])) ("{0} 敏感参数不得保存 literal value：{1}" -f $Label,$item)
            $i++
        }
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

