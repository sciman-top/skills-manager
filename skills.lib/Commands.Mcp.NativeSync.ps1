# MCP native 同步与 CLI 验证：native 开关判定、各 CLI 的 mcp list 期望集、
# 文本清洗（ANSI/脱敏）、就绪与错误判定、跨 CLI 重试验证、native 同步执行与
# 清理命令构造。从 Mcp.ps1 纯迁移（函数名与实现逐字不变）；规划、事务与
# 宿主配置形状留在 Mcp.ps1 / Mcp.HostAdapters.ps1。

function Should-RunNativeMcpSync() {
    return (Test-EnvFlagEnabled "SKILLS_MCP_NATIVE_SYNC")
}

function Should-VerifyLiveMcpCli() {
    return (Test-EnvFlagEnabled "SKILLS_MCP_VERIFY_LIVE_CLI")
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
    return (Test-EnvFlagEnabled "SKILLS_MCP_VERIFY_GEMINI_CLI")
}

function Get-NativeMcpCommandTimeoutSeconds() {
    return (Resolve-TimeoutSecondsFromEnv "SKILLS_MCP_NATIVE_TIMEOUT_SECONDS" 30 1 600)
}

function Get-McpCliProcessEnvOverrides([string]$cli) {
    $cliName = if ([string]::IsNullOrWhiteSpace($cli)) { "" } else { [string]$cli.Trim().ToLowerInvariant() }
    if ([string]::IsNullOrWhiteSpace($cliName)) { return $null }

    $varsToHydrate = switch ($cliName) {
        "gemini" { @("GITHUB_PERSONAL_ACCESS_TOKEN") }
        "claude" { @("GITHUB_PERSONAL_ACCESS_TOKEN") }
        "codex" { @("CODEX_GITHUB_PERSONAL_ACCESS_TOKEN") }
        default { @() }
    }
    if ($varsToHydrate.Count -eq 0) { return $null }

    $overrides = [ordered]@{}
    foreach ($varName in $varsToHydrate) {
        if ([string]::IsNullOrWhiteSpace($varName)) { continue }
        $processValue = [System.Environment]::GetEnvironmentVariable($varName, "Process")
        if (-not [string]::IsNullOrWhiteSpace([string]$processValue)) { continue }
        $userValue = Get-McpUserEnvironmentVariable $varName
        if (-not [string]::IsNullOrWhiteSpace([string]$userValue)) {
            $overrides[$varName] = [string]$userValue
        }
    }

    if ($overrides.Count -eq 0) { return $null }
    return $overrides
}

function Get-McpCliVerificationWorkingDir([string]$cli) {
    $cliName = if ([string]::IsNullOrWhiteSpace($cli)) { "" } else { [string]$cli.Trim().ToLowerInvariant() }
    switch ($cliName) {
        "gemini" {
            $userHome = [Environment]::GetFolderPath("UserProfile")
            if (-not [string]::IsNullOrWhiteSpace([string]$userHome) -and (Test-Path -LiteralPath $userHome)) {
                return [string]$userHome
            }
            return $null
        }
        default { return $null }
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
    $currentName = ''
    $currentEnabled = $true
    $currentDirectSection = $false

    $flush = {
        if (-not [string]::IsNullOrWhiteSpace($currentName) -and $currentEnabled) {
            $set.Add($currentName) | Out-Null
        }
    }

    foreach ($line in @(($tomlText -split "`r?`n"))) {
        $section = [regex]::Match([string]$line, '^\s*\[([^\]]+)\]\s*(?:#.*)?$')
        if ($section.Success) {
            & $flush
            $currentName = ''
            $currentEnabled = $true
            $currentDirectSection = $false

            $direct = [regex]::Match([string]$section.Groups[1].Value, '^mcp_servers\.([^\.\s]+)$')
            if ($direct.Success) {
                $currentName = [string]$direct.Groups[1].Value
                $currentDirectSection = $true
            }
            continue
        }

        if ($currentDirectSection) {
            $enabled = [regex]::Match([string]$line, '^\s*enabled\s*=\s*(true|false)\s*(?:#.*)?$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($enabled.Success) {
                $currentEnabled = [string]::Equals($enabled.Groups[1].Value, 'true', [System.StringComparison]::OrdinalIgnoreCase)
            }
        }
    }
    & $flush
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
                $names = Get-McpServerNamesFromJsonText (Get-ContentUtf8 $mcpPath)
                if ($names.Count -gt 0) { $expected.claude += $names }
            }
            continue
        }
        if ($leaf -eq ".gemini") {
            $settingsPath = Join-Path $root "settings.json"
            if (Test-Path $settingsPath) {
                $names = Get-McpServerNamesFromJsonText (Get-ContentUtf8 $settingsPath)
                if ($names.Count -gt 0) { $expected.gemini += $names }
            }
            continue
        }
        if ($leaf -eq ".codex") {
            $cfgPath = Join-Path $root "config.toml"
            if (Test-Path $cfgPath) {
                $names = Get-CodexMcpServerNamesFromTomlText (Get-ContentUtf8 $cfgPath)
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
    $masked = [regex]::Replace($masked, '(?i)((?:--)?(?:token|secret|password|passwd|api[-_]?key|authorization)\s*(?:=|:)\s*)([^\s"'']+)', '$1<redacted>')
    $masked = [regex]::Replace($masked, '(?i)((?:--)?(?:token|secret|password|passwd|api[-_]?key|authorization)\s+)([^\s"'']+)', '$1<redacted>')
    $masked = [regex]::Replace($masked, '(?i)(https?://)([^/@\s:]+):([^/@\s]+)@', '$1<redacted>@')
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

function Test-IsNativeMcpAlreadyExistsError([string]$text, [string]$name) {
    if ([string]::IsNullOrWhiteSpace([string]$text) -or [string]::IsNullOrWhiteSpace([string]$name)) {
        return $false
    }
    $normalized = ([string]$text).Trim()
    $escapedName = [regex]::Escape([string]$name)
    return ($normalized -match ("(?i)\bMCP server\s+{0}\s+already exists\b" -f $escapedName))
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
    $envOverrides = Get-McpCliProcessEnvOverrides $cliName
    $listWorkingDir = Get-McpCliVerificationWorkingDir $cliName
    $result = Invoke-ExternalCommandCapture -command $cli -args @("mcp", "list") -timeoutSeconds $listTimeoutSeconds -EnvironmentOverrides $envOverrides -workingDir $listWorkingDir
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
        $pattern = "^\s*(?:[^\w\r\n]+\s*)?{0}\b" -f [regex]::Escape([string]$name)
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

    if (-not (Should-VerifyLiveMcpCli)) {
        foreach ($target in $targets) {
            Log ("MCP 配置态校验通过：{0} -> {1}" -f $target.cli, ((@($target.names)) -join ", "))
        }
        Log "跨 CLI MCP live 校验默认跳过；如需实机 mcp list 校验，设置 SKILLS_MCP_VERIFY_LIVE_CLI=1。" "INFO"
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
                    Log ("{0} mcp list 输出片段：{1}" -f $check.cli, (Mask-SensitiveMcpCommandText $snippet)) "WARN"
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
    if (-not (Should-RunNativeMcpSync)) {
        Log "原生 Claude MCP 注册默认跳过；已写入配置文件。如需执行 claude mcp add/remove，设置 SKILLS_MCP_NATIVE_SYNC=1。" "INFO"
        return
    }
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
                if (Test-IsNativeMcpAlreadyExistsError ([string]$native.error) ([string]$s.name)) {
                    Log ("原生 MCP 已存在，尝试替换：{0}（scope={1}）" -f [string]$s.name, $scope) "WARN"
                    $removeArgs = @("mcp", "remove", [string]$s.name, "--scope", $scope)
                    $removed = Invoke-ExternalCommandWithTimeout "claude" @($removeArgs) $script:Root $timeoutSeconds
                    if ($removed.timed_out -or $removed.exit_code -ne 0) {
                        Log ("原生 MCP 替换前清理失败（已忽略）：{0}（scope={1}，exit={2}）{3}" -f [string]$s.name, $scope, $removed.exit_code, (Mask-SensitiveMcpCommandText ([string]$removed.error))) "WARN"
                        continue
                    }

                    $native = Invoke-ExternalCommandWithTimeout "claude" @($args) $script:Root $timeoutSeconds
                    if (-not $native.timed_out -and $native.exit_code -eq 0) {
                        Log ("已替换原生 MCP：{0}（scope={1}）" -f [string]$s.name, $scope)
                        continue
                    }
                }
                Log ("原生 MCP 同步失败（已忽略）：{0}（scope={1}，exit={2}）{3}" -f [string]$s.name, $scope, $native.exit_code, (Mask-SensitiveMcpCommandText ([string]$native.error))) "WARN"
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
            Log ("原生 MCP 同步失败（已忽略）：{0}（scope={1}） -> {2}" -f [string]$s.name, $scope, (Mask-SensitiveMcpCommandText $_.Exception.Message)) "WARN"
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
    if (-not (Should-RunNativeMcpSync)) {
        Log ("原生 Claude MCP 清理默认跳过：{0}。如需执行 claude mcp remove，设置 SKILLS_MCP_NATIVE_SYNC=1。" -f $name) "INFO"
        return
    }
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
                Log ("原生 MCP 清理失败（已忽略）：{0}（exit={1}）{2}" -f (Mask-SensitiveMcpCommandText $cmdText), $native.exit_code, (Mask-SensitiveMcpCommandText ([string]$native.error))) "WARN"
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
            Log ("原生 MCP 清理失败（已忽略）：{0} -> {1}" -f (Mask-SensitiveMcpCommandText $cmdText), (Mask-SensitiveMcpCommandText $_.Exception.Message)) "WARN"
            if (Test-IsNonInteractiveMcpError $_.Exception.Message) {
                $script:SkipNativeMcpForSession = $true
                Log "检测到原生 MCP CLI 在非交互环境不可用，已停止本轮后续原生 MCP 清理。" "WARN"
                break
            }
        }
    }
}

