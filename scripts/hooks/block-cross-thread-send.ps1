# Keep LF bytes stable because Codex hook trust hashes the installed definition.
[CmdletBinding()]
param(
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedScriptSha256,

    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedTargetPromptSha256,

    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedFleetPromptSha256,

    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedFleetShutdownPromptSha256
)

if (-not [string]::IsNullOrWhiteSpace($ExpectedScriptSha256)) {
    $actualScriptSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $PSCommandPath).Hash.ToLowerInvariant()
    if ($actualScriptSha256 -cne $ExpectedScriptSha256.ToLowerInvariant()) {
        [Console]::Error.WriteLine('Cross-thread guard script hash differs from the trusted command definition; blocking fail-closed.')
        exit 2
    }
}

$rawInput = [Console]::In.ReadToEnd()

function Write-DenyDecision {
    param([Parameter(Mandatory = $true)][string]$Reason)

    [ordered]@{
        hookSpecificOutput = [ordered]@{
            hookEventName = 'PreToolUse'
            permissionDecision = 'deny'
            permissionDecisionReason = $Reason
        }
    } | ConvertTo-Json -Depth 5 -Compress
}

function Get-InputProperty {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory = $true)][string[]]$Names
    )

    if ($null -eq $InputObject) {
        return $null
    }

    foreach ($name in $Names) {
        if ($InputObject -is [System.Collections.IDictionary] -and $InputObject.Contains($name)) {
            return $InputObject[$name]
        }
        $property = $InputObject.PSObject.Properties[$name]
        if ($null -ne $property) {
            return $property.Value
        }
    }

    return $null
}

function Get-ToolInputText {
    param([AllowNull()][object]$InputObject)

    if ($null -eq $InputObject) {
        return ''
    }
    if ($InputObject -is [string]) {
        return [string]$InputObject
    }

    $source = Get-InputProperty -InputObject $InputObject -Names @('code', 'source', 'input', 'command', 'cmd')
    if ($source -is [string]) {
        return [string]$source
    }

    try {
        return ($InputObject | ConvertTo-Json -Depth 50 -Compress)
    }
    catch {
        return ''
    }
}

function Get-JavaScriptCodeSkeleton {
    param([Parameter(Mandatory = $true)][string]$Source)

    $builder = [System.Text.StringBuilder]::new($Source.Length)
    $state = 'code'
    $quote = [char]0
    $escaped = $false
    for ($index = 0; $index -lt $Source.Length; $index++) {
        $character = $Source[$index]
        $next = if ($index + 1 -lt $Source.Length) { $Source[$index + 1] } else { [char]0 }

        if ($state -ceq 'code') {
            if ($character -eq "'" -or $character -eq '"' -or [int]$character -eq 96) {
                $state = 'string'
                $quote = $character
                $escaped = $false
                [void]$builder.Append(' ')
            }
            elseif ($character -eq '/' -and $next -eq '/') {
                $state = 'line_comment'
                [void]$builder.Append('  ')
                $index++
            }
            elseif ($character -eq '/' -and $next -eq '*') {
                $state = 'block_comment'
                [void]$builder.Append('  ')
                $index++
            }
            else {
                [void]$builder.Append($character)
            }
            continue
        }

        if ($state -ceq 'string') {
            [void]$builder.Append($(if ($character -eq "`n" -or $character -eq "`r") { $character } else { ' ' }))
            if ($escaped) {
                $escaped = $false
            }
            elseif ($character -eq '\') {
                $escaped = $true
            }
            elseif ($character -eq $quote) {
                $state = 'code'
            }
            continue
        }

        if ($state -ceq 'line_comment') {
            if ($character -eq "`n" -or $character -eq "`r") {
                $state = 'code'
                [void]$builder.Append($character)
            }
            else {
                [void]$builder.Append(' ')
            }
            continue
        }

        [void]$builder.Append($(if ($character -eq "`n" -or $character -eq "`r") { $character } else { ' ' }))
        if ($character -eq '*' -and $next -eq '/') {
            [void]$builder.Append(' ')
            $index++
            $state = 'code'
        }
    }

    return $builder.ToString()
}

function Test-CodeModeToolCall {
    param(
        [Parameter(Mandatory = $true)][string]$CodeSkeleton,
        [Parameter(Mandatory = $true)][string]$ToolNamePattern
    )

    return $CodeSkeleton -match ('(?i)(?:^|[^A-Za-z0-9_$])tools\s*(?:\?\s*\.\s*|\.\s*)(?:' + $ToolNamePattern + ')\s*\(')
}

function Test-CodeModeHighRiskRoute {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$CodeSkeleton,
        [Parameter(Mandatory = $true)][string]$ToolNamePattern
    )

    $direct = Test-CodeModeToolCall -CodeSkeleton $CodeSkeleton -ToolNamePattern $ToolNamePattern
    $bracket = $Source -match ('(?is)\btools\s*(?:\?\s*\.)?\s*\[\s*["''](?:' + $ToolNamePattern + ')["'']\s*\]\s*\(')
    $alias = $CodeSkeleton -match ('(?i)\b(?:const|let|var)\s+[A-Za-z_$][A-Za-z0-9_$]*\s*=\s*tools\s*(?:\?\s*\.\s*|\.\s*)(?:' + $ToolNamePattern + ')\s*;')
    return $direct -or $bracket -or $alias
}

function Get-JavaScriptPropertyString {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $escapedName = [regex]::Escape($Name)
    $pattern = '(?is)(?:\b' + $escapedName + '\b|["'']' + $escapedName + '["''])\s*:\s*(?<literal>"(?:\\.|[^"\\])*"|''(?:\\.|[^''\\])*'')'
    $match = [regex]::Match($Source, $pattern)
    if (-not $match.Success) {
        return $null
    }

    $literal = $match.Groups['literal'].Value
    try {
        if ($literal.StartsWith('"')) {
            return [string]($literal | ConvertFrom-Json)
        }

        $body = $literal.Substring(1, $literal.Length - 2)
        return [regex]::Unescape(($body -replace "\\'", "'"))
    }
    catch {
        return $null
    }
}

function Get-Sha256Lower {
    param([Parameter(Mandatory = $true)][string]$Text)

    $normalized = (($Text -replace "`r`n", "`n") -replace "`r", "`n").TrimEnd()
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($normalized)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Test-ReadOnlyInspectionSegment {
    param([Parameter(Mandatory = $true)][string]$Segment)

    $isRipgrep = $Segment -match '(?i)^(?:&\s*)?rg(?:\.exe)?\b'
    $isGrep = $Segment -match '(?i)^(?:&\s*)?grep(?:\.exe)?\b'
    $isPowerShellReader = $Segment -match '(?i)^(?:&\s*)?(?:Select-String|Get-Content)\b'
    $isGitGrep = $Segment -match '(?i)^(?:&\s*)?git(?:\.exe)?\s+grep\b'
    if (-not ($isRipgrep -or $isGrep -or $isPowerShellReader -or $isGitGrep)) {
        return $false
    }

    # A read-only command name does not make its arguments read-only. Shell
    # subexpressions can execute a nested sender before the reader starts.
    if ($Segment -match '(?s)(\$\s*\(|@\s*\(|<\s*\(|>\s*\(|`)' -or
        $Segment -match '(?i)\(\s*(?:&\s*)?(?:(?:cmd|pwsh|powershell|codex|curl|wscat|websocket)(?:\.exe)?|Invoke-Expression|iex|Start-Process|Invoke-RestMethod|Invoke-WebRequest)\b') {
        return $false
    }

    # These otherwise read-oriented tools expose options that launch an
    # arbitrary external command or pager.
    if ($isRipgrep -and $Segment -match '(?i)(?:^|\s)--pre(?:=|\s|$)') {
        return $false
    }
    if ($isGitGrep -and $Segment -match '(?i)(?:^|\s)(?:-O(?:\S*)?|--open-files-in-pager(?:=\S*)?)(?:\s|$)') {
        return $false
    }

    return $true
}

function Test-CanonicalWatchPrompt {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [AllowEmptyString()][string]$ExpectedTargetThreadId
    )

    $normalized = (($Prompt -replace "`r`n", "`n") -replace "`r", "`n").TrimEnd()
    $lines = @($normalized -split "`n")
    if ($lines.Count -lt 5 -or $lines[1] -cne 'policy_revision=3' -or $lines[2] -cnotmatch '^prompt_sha256=([0-9a-f]{64})$' -or $lines[3] -ne '') {
        return $false
    }

    $markerTarget = $null
    $expectedBodyHashes = @()
    if ($lines[0] -match '^watch-interrupted-task:v1 target_thread_id=([A-Za-z0-9][A-Za-z0-9._:-]{0,255})$') {
        $markerTarget = $Matches[1]
        $expectedBodyHashes = @($ExpectedTargetPromptSha256)
    }
    elseif ($lines[0] -match '^watch-interrupted-task:fleet:v1 supervisor_thread_id=([A-Za-z0-9][A-Za-z0-9._:-]{0,255})$') {
        $markerTarget = $Matches[1]
        $expectedBodyHashes = @($ExpectedFleetPromptSha256, $ExpectedFleetShutdownPromptSha256)
    }
    else {
        return $false
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedTargetThreadId) -and $markerTarget -cne $ExpectedTargetThreadId) {
        return $false
    }

    $declaredHash = $lines[2].Substring('prompt_sha256='.Length)
    $trustedHashes = @($expectedBodyHashes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { ([string]$_).ToLowerInvariant() })
    if ($declaredHash -notin $trustedHashes) {
        return $false
    }
    $body = [string]::Join("`n", $lines[4..($lines.Count - 1)])
    return (Get-Sha256Lower -Text $body) -ceq $declaredHash
}

function Get-WatchTurnText {
    param([Parameter(Mandatory = $true)][object]$Payload)

    $sessionId = [string](Get-InputProperty -InputObject $Payload -Names @('session_id', 'sessionId'))
    $turnId = [string](Get-InputProperty -InputObject $Payload -Names @('turn_id', 'turnId'))
    $transcriptPath = [string](Get-InputProperty -InputObject $Payload -Names @('transcript_path', 'transcriptPath'))
    if ([string]::IsNullOrWhiteSpace($sessionId) -or [string]::IsNullOrWhiteSpace($turnId) -or
        [string]::IsNullOrWhiteSpace($transcriptPath) -or -not (Test-Path -LiteralPath $transcriptPath -PathType Leaf)) {
        return $null
    }

    $turnMessages = [System.Collections.Generic.List[string]]::new()
    try {
        foreach ($line in @(Get-Content -LiteralPath $transcriptPath -Tail 2000)) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            try {
                $record = $line | ConvertFrom-Json -Depth 50 -ErrorAction Stop
            }
            catch {
                continue
            }

            if ([string]$record.type -cne 'response_item' -or [string]$record.payload.type -cne 'message' -or
                [string]$record.payload.role -cne 'user') {
                continue
            }

            $recordTurnId = [string](Get-InputProperty -InputObject $record.payload.internal_chat_message_metadata_passthrough -Names @('turn_id', 'turnId'))
            if ($recordTurnId -cne $turnId) {
                continue
            }

            foreach ($content in @($record.payload.content)) {
                $text = [string](Get-InputProperty -InputObject $content -Names @('text'))
                if (-not [string]::IsNullOrWhiteSpace($text)) {
                    $turnMessages.Add($text)
                }
            }
        }
    }
    catch {
        return $null
    }

    if ($turnMessages.Count -eq 0) {
        return $null
    }

    return [string]::Join("`n", $turnMessages)
}

function Get-WatchTurnRole {
    param([Parameter(Mandatory = $true)][object]$Payload)

    $sessionId = [string](Get-InputProperty -InputObject $Payload -Names @('session_id', 'sessionId'))
    $combined = Get-WatchTurnText -Payload $Payload
    if ([string]::IsNullOrWhiteSpace($combined)) {
        return 'unknown'
    }

    $heartbeatPattern = '(?s)^\s*<heartbeat>\s*<automation_id>(?<automation>[^<]+)</automation_id>\s*(?:<current_time_iso>[^<]+</current_time_iso>\s*)?<instructions>\s*(?<prompt>watch-interrupted-task:(?<role>fleet:)?v1\s+.*?)\s*</instructions>\s*</heartbeat>\s*$'
    $heartbeatMatch = [regex]::Match($combined, $heartbeatPattern)
    if ($heartbeatMatch.Success) {
        $prompt = $heartbeatMatch.Groups['prompt'].Value
        $automationId = $heartbeatMatch.Groups['automation'].Value.Trim()
        if ($automationId -cne "watch-interrupted-task-v1-target-thread-id-$sessionId") {
            return 'unknown'
        }
        if (-not (Test-CanonicalWatchPrompt -Prompt $prompt -ExpectedTargetThreadId $sessionId)) {
            return 'unknown'
        }
        if ($heartbeatMatch.Groups['role'].Success) {
            return 'fleet_heartbeat'
        }
        return 'target_heartbeat'
    }
    if ($combined -match '(?s)<heartbeat>.*?</heartbeat>') {
        return 'unknown'
    }

    return 'ordinary_turn'
}

function Test-ShutdownArmedFleetHeartbeat {
    param([Parameter(Mandatory = $true)][object]$Payload)

    if ([string]::IsNullOrWhiteSpace($ExpectedFleetShutdownPromptSha256)) {
        return $false
    }
    $sessionId = [string](Get-InputProperty -InputObject $Payload -Names @('session_id', 'sessionId'))
    $combined = Get-WatchTurnText -Payload $Payload
    if ([string]::IsNullOrWhiteSpace($combined)) {
        return $false
    }

    $heartbeatPattern = '(?s)^\s*<heartbeat>\s*<automation_id>(?<automation>[^<]+)</automation_id>\s*(?:<current_time_iso>[^<]+</current_time_iso>\s*)?<instructions>\s*(?<prompt>watch-interrupted-task:fleet:v1\s+.*?)\s*</instructions>\s*</heartbeat>\s*$'
    $heartbeatMatch = [regex]::Match($combined, $heartbeatPattern)
    if (-not $heartbeatMatch.Success -or $heartbeatMatch.Groups['automation'].Value.Trim() -cne "watch-interrupted-task-v1-target-thread-id-$sessionId") {
        return $false
    }

    $prompt = $heartbeatMatch.Groups['prompt'].Value
    if (-not (Test-CanonicalWatchPrompt -Prompt $prompt -ExpectedTargetThreadId $sessionId)) {
        return $false
    }
    $lines = @(((($prompt -replace "`r`n", "`n") -replace "`r", "`n").TrimEnd()) -split "`n")
    return $lines.Count -ge 3 -and $lines[2] -ceq ('prompt_sha256=' + $ExpectedFleetShutdownPromptSha256.ToLowerInvariant())
}

function Test-DirectWatchLifecycleIntent {
    param(
        [Parameter(Mandatory = $true)][object]$Payload,
        [Parameter(Mandatory = $true)][string]$Mode,
        [AllowNull()][object]$ToolInput
    )

    $text = Get-WatchTurnText -Payload $Payload
    if ([string]::IsNullOrWhiteSpace($text) -or $text -match '(?s)<heartbeat>.*?</heartbeat>') {
        return $false
    }
    $text = $text.Trim()
    if ($text -notmatch '(?i)守夜|watch-interrupted-task|heartbeat') {
        return $false
    }
    if ($text -match '(?i)(不要|请勿|无需|别|禁止|切勿|不允许|不应|不能|do\s+not|don''t).{0,24}(关闭|删除|暂停|恢复|开启|启用|close|delete|pause|resume|enable|start)' -or
        $text -match '(?i)(为什么|为何|怎么会|是否|会不会|\?|？)' -or
        $text -match '(?i)(?:(文档|示例|说明|写着|写进|提到|quoted|example|documentation).{0,32}(关闭|删除|暂停|恢复|开启|启用|close|delete|pause|resume|enable|start)|(关闭|删除|暂停|恢复|开启|启用|close|delete|pause|resume|enable|start).{0,32}(文档|示例|说明|写着|写进|提到|quoted|example|documentation))') {
        return $false
    }

    $sessionId = [string](Get-InputProperty -InputObject $Payload -Names @('session_id', 'sessionId'))
    $targetThreadId = [string](Get-WatchAutomationTargetId -ToolInput $ToolInput)
    if ([string]::IsNullOrWhiteSpace($targetThreadId)) {
        return $false
    }
    if ($targetThreadId -cne $sessionId -and $text -notmatch [regex]::Escape($targetThreadId)) {
        return $false
    }

    $status = [string](Get-InputProperty -InputObject $ToolInput -Names @('status'))
    switch ($Mode.ToLowerInvariant()) {
        'delete' { return $text -match '关闭|删除|close|delete' }
        'create' { return $text -match '开启|启用|目标守夜|enable|start' }
        'update' {
            if ($status -ceq 'PAUSED') { return $text -match '暂停|pause' }
            if ($status -ceq 'ACTIVE') { return $text -match '恢复|开启|启用|resume|enable|start' }
            return $text -match '开启|启用|恢复|更新|迁移|目标守夜|enable|resume|update|migrate'
        }
        default { return $false }
    }
}

function Get-WatchAutomationTargetId {
    param([AllowNull()][object]$ToolInput)

    $id = [string](Get-InputProperty -InputObject $ToolInput -Names @('id'))
    if ($id -match '^watch-interrupted-task-v1-target-thread-id-([A-Za-z0-9][A-Za-z0-9._:-]{0,255})$') {
        return $Matches[1]
    }

    $targetThreadId = [string](Get-InputProperty -InputObject $ToolInput -Names @('targetThreadId', 'target_thread_id'))
    if (-not [string]::IsNullOrWhiteSpace($targetThreadId)) {
        return $targetThreadId
    }

    $prompt = [string](Get-InputProperty -InputObject $ToolInput -Names @('prompt'))
    if ($prompt -match '(?m)^watch-interrupted-task:v1 target_thread_id=([A-Za-z0-9][A-Za-z0-9._:-]{0,255})$') {
        return $Matches[1]
    }
    if ($prompt -match '(?m)^watch-interrupted-task:fleet:v1 supervisor_thread_id=([A-Za-z0-9][A-Za-z0-9._:-]{0,255})$') {
        return $Matches[1]
    }

    return $null
}

try {
    $payload = $rawInput | ConvertFrom-Json -Depth 50 -ErrorAction Stop
}
catch {
    [Console]::Error.WriteLine('Cross-thread guard could not parse PreToolUse input; blocking fail-closed.')
    exit 2
}

$hookEventName = [string](Get-InputProperty -InputObject $payload -Names @('hook_event_name', 'hookEventName'))
if ($hookEventName -cne 'PreToolUse') {
    [Console]::Error.WriteLine('Cross-thread guard was invoked outside PreToolUse; blocking fail-closed.')
    exit 2
}

$toolNameProperty = $payload.PSObject.Properties['tool_name']
if ($null -eq $toolNameProperty -or [string]::IsNullOrWhiteSpace([string]$toolNameProperty.Value)) {
    [Console]::Error.WriteLine('Cross-thread guard received PreToolUse input without tool_name; blocking fail-closed.')
    exit 2
}

$toolName = [string]$toolNameProperty.Value
$toolInput = $payload.tool_input
$denyReason = $null

if ($toolName -match '(?i)(^|__|\.)send_message_to_thread$') {
    $denyReason = 'Cross-task message injection is disabled. The user must communicate directly in the target task.'
}
elseif ($toolName -match '(?i)(^|__|\.)handoff_thread$') {
    $denyReason = 'Cross-task handoff is disabled. The user must coordinate and communicate directly in the target task.'
}
elseif ($toolName -match '(?i)(^|__|\.)exec$') {
    $source = Get-ToolInputText -InputObject $toolInput
    $codeSkeleton = Get-JavaScriptCodeSkeleton -Source $source
    $hasHighRiskRouteName = $source -match '(?i)\b(?:[A-Za-z0-9_]+__)?(?:send_message_to_thread|handoff_thread|automation_update)\b'
    $hasPowerMutationRoute = $source -match '(?i)\b(?:shutdown(?:\.exe)?|Stop-Computer|Restart-Computer|Win32Shutdown|InitiateSystemShutdown|ExitWindowsEx)\b'
    # Code mode is not an AST-backed trust boundary. Permit ordinary direct
    # calls, but fail closed when the tools object is aliased, destructured, or
    # indexed because the callee can no longer be proven from this hook input.
    $hasAliasedDynamicRoute = $codeSkeleton -match '(?is)\b(?:const|let|var)\s+(?:[A-Za-z_$][A-Za-z0-9_$]*|\{[^}]*\}|\[[^\]]*\])\s*=\s*tools\b'
    $hasNestedSendTool = Test-CodeModeHighRiskRoute -Source $source -CodeSkeleton $codeSkeleton -ToolNamePattern '(?:[A-Za-z0-9_]+__)?send_message_to_thread'
    $hasNestedShellTool = Test-CodeModeToolCall -CodeSkeleton $codeSkeleton -ToolNamePattern '(?:shell_command|exec_command)'
    $hasNestedAutomationTool = Test-CodeModeHighRiskRoute -Source $source -CodeSkeleton $codeSkeleton -ToolNamePattern '(?:[A-Za-z0-9_]+__)?automation_update'
    $hasDynamicToolRoute = $codeSkeleton -match '(?is)\btools\s*(?:\?\s*\.)?\s*\[[^\]]*\]'

    if ($hasPowerMutationRoute) {
        $denyReason = 'Code mode is not a trusted power-action surface; the armed fleet heartbeat must use the native typed shell tool directly.'
    }
    elseif ($hasHighRiskRouteName -or $hasAliasedDynamicRoute) {
        $denyReason = 'Code mode is not a trusted parser boundary for cross-task handoff, message, or automation mutation routes; use the native typed tool directly.'
    }
    elseif ($hasDynamicToolRoute) {
        $denyReason = 'Dynamic code-mode tool dispatch cannot prove that cross-task and automation mutation routes are absent.'
    }
    elseif ($hasNestedShellTool) {
        $nestedCommand = [string](Get-JavaScriptPropertyString -Source $source -Name 'command')
        if ([string]::IsNullOrWhiteSpace($nestedCommand)) {
            $nestedCommand = [string](Get-JavaScriptPropertyString -Source $source -Name 'cmd')
        }
        if ($nestedCommand -match '(?i)\bcodex(?:\.(?:cmd|ps1|exe))?\s+app-server\b[^\r\n;&|]*\bthread[\/.:-]send\b' -or
            $nestedCommand -match '(?i)^\s*(?:send_message_to_thread|sendMessageToThread)\b') {
            $denyReason = 'Shell or app-server cross-task send bypasses nested in code mode are disabled.'
        }
    }
    if ([string]::IsNullOrWhiteSpace($denyReason) -and $hasNestedAutomationTool) {
        $mode = [string](Get-JavaScriptPropertyString -Source $source -Name 'mode')
        $automationId = [string](Get-JavaScriptPropertyString -Source $source -Name 'id')
        $prompt = [string](Get-JavaScriptPropertyString -Source $source -Name 'prompt')
        $targetThreadId = [string](Get-JavaScriptPropertyString -Source $source -Name 'targetThreadId')
        if ([string]::IsNullOrWhiteSpace($targetThreadId)) {
            $targetThreadId = [string](Get-JavaScriptPropertyString -Source $source -Name 'target_thread_id')
        }

        $sessionId = [string]$payload.session_id
        $isWatchPrompt = $prompt -match '(?m)^watch-interrupted-task(?::fleet)?:v1 '
        $watchTargetThreadId = [string](Get-WatchAutomationTargetId -ToolInput ([ordered]@{
            id = $automationId
            targetThreadId = $targetThreadId
            prompt = $prompt
        }))
        $isWatchMutation = -not [string]::IsNullOrWhiteSpace($watchTargetThreadId) -or $isWatchPrompt -or
            $automationId -match '^watch-interrupted-task-v1-live-probe-'

        if ($automationId -match '^watch-interrupted-task-v1-live-probe-[A-Za-z0-9._:-]+$') {
            $denyReason = 'Watch automation live-probe sentinel was denied before the code-mode native automation call executed.'
        }
        else {
            $turnRole = Get-WatchTurnRole -Payload $payload
            if ($turnRole -ceq 'target_heartbeat' -and $mode -cne 'view') {
                $denyReason = 'Target heartbeats cannot mutate automation metadata through code mode; the fleet supervisor is the sole heartbeat writer.'
            }
            elseif ($turnRole -ceq 'fleet_heartbeat' -and $mode -cne 'view') {
                if (-not $isWatchMutation) {
                    $denyReason = 'The fleet supervisor heartbeat may mutate only canonical watch-interrupted-task automations through code mode.'
                }
                elseif ([string]::IsNullOrWhiteSpace($watchTargetThreadId) -or $watchTargetThreadId -ceq $sessionId) {
                    $denyReason = 'The fleet supervisor heartbeat cannot mutate its own dual-role automation through code mode.'
                }
                elseif ($mode -cne 'delete' -and -not (Test-CanonicalWatchPrompt -Prompt $prompt -ExpectedTargetThreadId $watchTargetThreadId)) {
                    $denyReason = 'Fleet code-mode target writes must carry the trusted canonical watch-interrupted-task policy_revision=3 envelope as a literal prompt.'
                }
            }
            elseif ($turnRole -ceq 'ordinary_turn' -and $mode -cne 'view' -and $isWatchMutation -and
                -not (Test-DirectWatchLifecycleIntent -Payload $payload -Mode $mode -ToolInput ([ordered]@{
                    id = $automationId
                    targetThreadId = $targetThreadId
                    prompt = $prompt
                }))) {
                $denyReason = 'Code-mode watch automation mutation requires a direct user lifecycle command in the current turn.'
            }
            elseif ($turnRole -ceq 'unknown' -and $mode -cne 'view' -and $isWatchMutation) {
                $denyReason = 'Code-mode watch automation mutation origin could not be classified from the current turn; blocking fail-closed.'
            }
        }

        if ([string]::IsNullOrWhiteSpace($denyReason) -and $mode -cne 'view' -and $isWatchPrompt -and
            -not (Test-CanonicalWatchPrompt -Prompt $prompt -ExpectedTargetThreadId $watchTargetThreadId)) {
            $denyReason = 'Code-mode watch automation prompts must use the trusted canonical watch-interrupted-task policy_revision=3 envelope.'
        }
    }
}
elseif ($toolName -match '(?i)(^|__|\.)automation_update$') {
    $mode = [string](Get-InputProperty -InputObject $toolInput -Names @('mode'))
    $automationId = [string](Get-InputProperty -InputObject $toolInput -Names @('id'))
    $prompt = [string](Get-InputProperty -InputObject $toolInput -Names @('prompt'))
    $targetThreadId = [string](Get-InputProperty -InputObject $toolInput -Names @('targetThreadId', 'target_thread_id'))
    $status = [string](Get-InputProperty -InputObject $toolInput -Names @('status'))
    $sessionId = [string]$payload.session_id
    $isWatchPrompt = $prompt -match '(?m)^watch-interrupted-task(?::fleet)?:v1 '
    $isCrossTargetPrompt = -not [string]::IsNullOrWhiteSpace($prompt) -and -not [string]::IsNullOrWhiteSpace($targetThreadId) -and $targetThreadId -cne $sessionId
    $watchTargetThreadId = [string](Get-WatchAutomationTargetId -ToolInput $toolInput)
    $isWatchMutation = -not [string]::IsNullOrWhiteSpace($watchTargetThreadId) -or $isWatchPrompt -or
        $automationId -match '^watch-interrupted-task-v1-live-probe-'

    if ($mode -ceq 'view') {
        # Read-only automation inspection is allowed from every turn role.
    }
    elseif ($automationId -match '^watch-interrupted-task-v1-live-probe-[A-Za-z0-9._:-]+$') {
        $denyReason = 'Watch automation live-probe sentinel was denied before the native automation call executed.'
    }
    else {
        $turnRole = Get-WatchTurnRole -Payload $payload
        $ordinaryMentionsWatchLifecycle = $false
        if ($turnRole -ceq 'ordinary_turn') {
            $ordinaryTurnText = Get-WatchTurnText -Payload $payload
            $ordinaryMentionsWatchLifecycle = -not [string]::IsNullOrWhiteSpace($ordinaryTurnText) -and
                $ordinaryTurnText -match '(?i)守夜|watch-interrupted-task|heartbeat'
        }
        if ($turnRole -ceq 'target_heartbeat') {
            $denyReason = 'Target heartbeats are monitor/recovery workers and cannot mutate automation metadata; the fleet supervisor is the sole heartbeat writer.'
        }
        elseif ($turnRole -ceq 'fleet_heartbeat') {
            if (-not $isWatchMutation) {
                $denyReason = 'The fleet supervisor heartbeat may mutate only canonical watch-interrupted-task automations.'
            }
            elseif ([string]::IsNullOrWhiteSpace($watchTargetThreadId) -or $watchTargetThreadId -ceq $sessionId) {
                $denyReason = 'The fleet supervisor heartbeat cannot mutate its own dual-role automation.'
            }
            elseif ($mode -ceq 'delete' -or ($mode -ceq 'update' -and $status -ieq 'PAUSED')) {
                $denyReason = 'Fleet heartbeat deletion or pause is fail-closed because PreToolUse cannot verify terminal Goal and cleanup receipt truth; a direct user lifecycle command is required.'
            }
            elseif ($mode -cne 'delete' -and -not (Test-CanonicalWatchPrompt -Prompt $prompt -ExpectedTargetThreadId $watchTargetThreadId)) {
                $denyReason = 'Fleet target automation writes must use the trusted canonical watch-interrupted-task policy_revision=3 envelope.'
            }
        }
        elseif ($turnRole -ceq 'ordinary_turn' -and ($isWatchMutation -or $ordinaryMentionsWatchLifecycle) -and
            -not (Test-DirectWatchLifecycleIntent -Payload $payload -Mode $mode -ToolInput $toolInput)) {
            $denyReason = 'Watch automation mutation requires a direct user lifecycle command in the current turn.'
        }
        elseif ($turnRole -ceq 'unknown' -and $isWatchMutation) {
            $denyReason = 'Watch automation mutation origin could not be classified from the current turn; blocking fail-closed.'
        }
    }

    if ([string]::IsNullOrWhiteSpace($denyReason) -and ($isWatchPrompt -or $isCrossTargetPrompt) -and
        -not (Test-CanonicalWatchPrompt -Prompt $prompt -ExpectedTargetThreadId $(if ($watchTargetThreadId) { $watchTargetThreadId } else { $targetThreadId }))) {
        $denyReason = 'Cross-target automation prompts must use the trusted canonical watch-interrupted-task policy_revision=3 envelope.'
    }
}
elseif ($toolName -match '(?i)^(Bash|shell_command|exec_command)$') {
    $command = [string](Get-InputProperty -InputObject $toolInput -Names @('command', 'cmd'))
    $hasPowerMutation = $command -match '(?im)(?:^|[\r\n;&|])\s*(?:&\s*)?(?:(?:cmd|pwsh|powershell)(?:\.exe)?\s+(?:/c|-Command)\s+)?(?:shutdown(?:\.exe)?|Stop-Computer|Restart-Computer|Win32Shutdown|InitiateSystemShutdown|ExitWindowsEx)\b'
    if ($hasPowerMutation) {
        $turnRole = Get-WatchTurnRole -Payload $payload
        $exactFleetShutdown = $command -match '(?i)^\s*(?:&\s*)?shutdown(?:\.exe)?\s+/s\s+/t\s+120\s+/c\s+["'']watch-interrupted-task: all monitored tasks stopped["'']\s*$'
        if ($turnRole -ceq 'fleet_heartbeat') {
            if (-not $exactFleetShutdown -or -not (Test-ShutdownArmedFleetHeartbeat -Payload $payload)) {
                $denyReason = 'Fleet heartbeat power actions require the exact non-forced 120-second command and the trusted shutdown-armed canonical prompt.'
            }
        }
        elseif ($turnRole -ne 'ordinary_turn') {
            $denyReason = 'Target, unknown, or unarmed heartbeat turns cannot execute computer power actions.'
        }
    }

    foreach ($segment in @($command -split '[\r\n;&|]+')) {
        if (-not [string]::IsNullOrWhiteSpace($denyReason)) { break }
        $trimmedSegment = $segment.Trim()
        $hasExecutableSend = $trimmedSegment -match '(?i)^\s*(?:&\s*)?(?:send_message_to_thread|sendMessageToThread)\b' -or
            $trimmedSegment -match '(?i)(?:^|\b(?:cmd|pwsh|powershell)(?:\.exe)?\s+(?:/c|-Command)\s+)["'']?\s*codex(?:\.(?:cmd|ps1|exe))?\s+app-server\b.*\bthread[\/.:-]send\b' -or
            $trimmedSegment -match '(?i)^\s*(?:&\s*)?codex(?:\.(?:cmd|ps1|exe))?\s+app-server\b.*\bthread[\/.:-]send\b' -or
            $trimmedSegment -match '(?i)^\s*(?:Invoke-Expression|iex)\b.*\bcodex(?:\.(?:cmd|ps1|exe))?\s+app-server\b.*\bthread[\/.:-]send\b' -or
            $trimmedSegment -match '(?i)^\s*Start-Process\s+(?:-[A-Za-z]+\s+)*["'']?codex(?:\.(?:cmd|ps1|exe))?["'']?\b.*\bapp-server\b.*\bthread[\/.:-]send\b'
        $hasExecutionSubexpression = $trimmedSegment -match '(?is)(?:\$\s*\(|@\s*\(|\(\s*&?\s*)\s*codex(?:\.(?:cmd|ps1|exe))?\s+app-server\b.*\bthread[\/.:-]send\b'
        $hasReaderExecOption = $trimmedSegment -match '(?i)^\s*(?:&\s*)?rg(?:\.exe)?\b.*(?:^|\s)--pre(?:=|\s).*\bthread[\/.:-]send\b' -or
            $trimmedSegment -match '(?i)^\s*(?:&\s*)?git(?:\.exe)?\s+grep\b.*(?:-O|--open-files-in-pager).*\bthread[\/.:-]send\b'
        if (-not ($hasExecutableSend -or $hasExecutionSubexpression -or $hasReaderExecOption)) {
            continue
        }

        if (-not (Test-ReadOnlyInspectionSegment -Segment $trimmedSegment)) {
            $denyReason = 'Shell or app-server cross-task send bypasses are disabled.'
            break
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($denyReason)) {
    Write-DenyDecision -Reason $denyReason
}

exit 0
