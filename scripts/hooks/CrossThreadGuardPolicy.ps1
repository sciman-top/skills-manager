# Pure policy core. It parses only supplied objects and text and performs no
# filesystem, process, console, or host mutation. The wrapper owns those edges.
Set-StrictMode -Version Latest

function Get-InputProperty {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory = $true)][string[]]$Names
    )

    if ($null -eq $InputObject) { return $null }
    foreach ($name in $Names) {
        if ($InputObject -is [System.Collections.IDictionary] -and $InputObject.Contains($name)) { return $InputObject[$name] }
        $property = $InputObject.PSObject.Properties[$name]
        if ($null -ne $property) { return $property.Value }
    }
    return $null
}

function Get-ToolInputText {
    param([AllowNull()][object]$InputObject)

    if ($null -eq $InputObject) { return '' }
    if ($InputObject -is [string]) { return [string]$InputObject }
    $source = Get-InputProperty -InputObject $InputObject -Names @('code','source','input','command','cmd')
    if ($source -is [string]) { return [string]$source }
    try { return ($InputObject | ConvertTo-Json -Depth 50 -Compress) } catch { return '' }
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
                $state = 'string'; $quote = $character; $escaped = $false; [void]$builder.Append(' ')
            }
            elseif ($character -eq '/' -and $next -eq '/') {
                $state = 'line_comment'; [void]$builder.Append('  '); $index++
            }
            elseif ($character -eq '/' -and $next -eq '*') {
                $state = 'block_comment'; [void]$builder.Append('  '); $index++
            }
            else { [void]$builder.Append($character) }
            continue
        }
        if ($state -ceq 'string') {
            [void]$builder.Append($(if ($character -eq "`n" -or $character -eq "`r") { $character } else { ' ' }))
            if ($escaped) { $escaped = $false }
            elseif ($character -eq '\') { $escaped = $true }
            elseif ($character -eq $quote) { $state = 'code' }
            continue
        }
        if ($state -ceq 'line_comment') {
            if ($character -eq "`n" -or $character -eq "`r") { $state = 'code'; [void]$builder.Append($character) }
            else { [void]$builder.Append(' ') }
            continue
        }
        [void]$builder.Append($(if ($character -eq "`n" -or $character -eq "`r") { $character } else { ' ' }))
        if ($character -eq '*' -and $next -eq '/') { [void]$builder.Append(' '); $index++; $state = 'code' }
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
    if (-not $match.Success) { return $null }
    $literal = $match.Groups['literal'].Value
    try {
        if ($literal.StartsWith('"')) { return [string]($literal | ConvertFrom-Json) }
        $body = $literal.Substring(1, $literal.Length - 2)
        return [regex]::Unescape(($body -replace "\\'", "'"))
    }
    catch { return $null }
}

function Test-ReadOnlyInspectionSegment {
    param([Parameter(Mandatory = $true)][string]$Segment)

    $isRipgrep = $Segment -match '(?i)^(?:&\s*)?rg(?:\.exe)?\b'
    $isGrep = $Segment -match '(?i)^(?:&\s*)?grep(?:\.exe)?\b'
    $isPowerShellReader = $Segment -match '(?i)^(?:&\s*)?(?:Select-String|Get-Content)\b'
    $isGitGrep = $Segment -match '(?i)^(?:&\s*)?git(?:\.exe)?\s+grep\b'
    if (-not ($isRipgrep -or $isGrep -or $isPowerShellReader -or $isGitGrep)) { return $false }
    if ($Segment -match '(?s)(\$\s*\(|@\s*\(|<\s*\(|>\s*\(|`)' -or
        $Segment -match '(?i)\(\s*(?:&\s*)?(?:(?:cmd|pwsh|powershell|codex|curl|wscat|websocket)(?:\.exe)?|Invoke-Expression|iex|Start-Process|Invoke-RestMethod|Invoke-WebRequest)\b') { return $false }
    if ($isRipgrep -and $Segment -match '(?i)(?:^|\s)--pre(?:=|\s|$)') { return $false }
    if ($isGitGrep -and $Segment -match '(?i)(?:^|\s)(?:-O(?:\S*)?|--open-files-in-pager(?:=\S*)?)(?:\s|$)') { return $false }
    return $true
}

function Get-WatchTurnText {
    param([Parameter(Mandatory = $true)][object]$Payload)
    $turnText = Get-InputProperty -InputObject $Payload -Names @('__watch_turn_text')
    if ($turnText -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$turnText)) { return $null }
    return [string]$turnText
}

function Test-RetiredWatchHeartbeatTurn {
    param([Parameter(Mandatory = $true)][object]$Payload)
    $text = Get-WatchTurnText -Payload $Payload
    return -not [string]::IsNullOrWhiteSpace($text) -and $text -match '(?is)<heartbeat>.*?</heartbeat>'
}

function Get-RetiredWatchTargetId {
    param([AllowNull()][object]$ToolInput)

    $id = [string](Get-InputProperty -InputObject $ToolInput -Names @('id'))
    if ($id -match '^watch-interrupted-task-v1-target-thread-id-([A-Za-z0-9][A-Za-z0-9._:-]{0,255})$') { return $Matches[1] }
    $targetThreadId = [string](Get-InputProperty -InputObject $ToolInput -Names @('targetThreadId','target_thread_id'))
    if (-not [string]::IsNullOrWhiteSpace($targetThreadId)) { return $targetThreadId }
    $prompt = [string](Get-InputProperty -InputObject $ToolInput -Names @('prompt'))
    if ($prompt -match '(?m)^watch-interrupted-task:v1 target_thread_id=([A-Za-z0-9][A-Za-z0-9._:-]{0,255})$') { return $Matches[1] }
    if ($prompt -match '(?m)^watch-interrupted-task:fleet:v1 supervisor_thread_id=([A-Za-z0-9][A-Za-z0-9._:-]{0,255})$') { return $Matches[1] }
    return $null
}

function Test-ExplicitLegacyWatchCleanupIntent {
    param([Parameter(Mandatory = $true)][string]$Text)

    $trimmed = $Text.Trim()
    if ($trimmed -notmatch '(?i)守夜|watch-interrupted-task|heartbeat') { return $false }
    if ($trimmed -notmatch '(?i)关闭|删除|清理|移除|close|delete|remove|clean\s*up') { return $false }
    if ($trimmed -match '(?i)(不要|请勿|无需|别|禁止|切勿|不允许|不应|不能|do\s+not|don''t).{0,24}(关闭|删除|清理|移除|close|delete|remove|clean\s*up)' -or
        $trimmed -match '(?i)(为什么|为何|怎么会|是否|会不会|\?|？)' -or
        $trimmed -match '(?i)(?:(文档|示例|说明|写着|写进|提到|quoted|example|documentation).{0,32}(关闭|删除|清理|移除|close|delete|remove)|(关闭|删除|清理|移除|close|delete|remove).{0,32}(文档|示例|说明|写着|写进|提到|quoted|example|documentation))') { return $false }
    return $true
}

function Test-ExactCurrentLegacyWatchDelete {
    param(
        [Parameter(Mandatory = $true)][object]$Payload,
        [Parameter(Mandatory = $true)][object]$ToolInput
    )

    if (Test-RetiredWatchHeartbeatTurn -Payload $Payload) { return $false }
    $sessionId = [string](Get-InputProperty -InputObject $Payload -Names @('session_id','sessionId'))
    $mode = [string](Get-InputProperty -InputObject $ToolInput -Names @('mode'))
    $id = [string](Get-InputProperty -InputObject $ToolInput -Names @('id'))
    $text = Get-WatchTurnText -Payload $Payload
    return -not [string]::IsNullOrWhiteSpace($sessionId) -and $mode -ceq 'delete' -and
        $id -ceq "watch-interrupted-task-v1-target-thread-id-$sessionId" -and
        -not [string]::IsNullOrWhiteSpace($text) -and (Test-ExplicitLegacyWatchCleanupIntent -Text $text)
}

function Get-CrossThreadGuardDecision {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Payload)

    $hookEventName = [string](Get-InputProperty -InputObject $Payload -Names @('hook_event_name','hookEventName'))
    if ($hookEventName -cne 'PreToolUse') {
        return [pscustomobject]@{ exit_code=2; permission_decision='error'; reason='Cross-thread guard was invoked outside PreToolUse; blocking fail-closed.' }
    }
    $toolName = [string](Get-InputProperty -InputObject $Payload -Names @('tool_name'))
    if ([string]::IsNullOrWhiteSpace($toolName)) {
        return [pscustomobject]@{ exit_code=2; permission_decision='error'; reason='Cross-thread guard received PreToolUse input without tool_name; blocking fail-closed.' }
    }

    $toolInput = Get-InputProperty -InputObject $Payload -Names @('tool_input')
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
        $hasSendOrHandoffRoute = Test-CodeModeHighRiskRoute -Source $source -CodeSkeleton $codeSkeleton -ToolNamePattern '(?:[A-Za-z0-9_]+__)?(?:send_message_to_thread|handoff_thread)'
        $hasAliasedDynamicRoute = $codeSkeleton -match '(?is)\b(?:const|let|var)\s+(?:[A-Za-z_$][A-Za-z0-9_$]*|\{[^}]*\}|\[[^\]]*\])\s*=\s*tools\b'
        $hasNestedShellTool = Test-CodeModeToolCall -CodeSkeleton $codeSkeleton -ToolNamePattern '(?:shell_command|exec_command)'
        $literalShellCommand = if ($hasNestedShellTool) { [string](Get-JavaScriptPropertyString -Source $source -Name 'command') } else { '' }
        $hasPowerMutationRoute = $hasNestedShellTool -and $literalShellCommand -match '(?i)\b(?:shutdown(?:\.exe)?|Stop-Computer|Restart-Computer|Win32Shutdown|InitiateSystemShutdown|ExitWindowsEx)\b'
        $hasNestedAutomationTool = Test-CodeModeHighRiskRoute -Source $source -CodeSkeleton $codeSkeleton -ToolNamePattern '(?:[A-Za-z0-9_]+__)?automation_update'
        $hasDynamicToolRoute = $codeSkeleton -match '(?is)\btools\s*(?:\?\s*\.)?\s*\[[^\]]*\]'

        if ($hasNestedAutomationTool) {
            $denyReason = 'Code-mode automation mutation is disabled after watch runtime retirement; use the native read-only view or exact current legacy delete path.'
        }
        elseif ($hasPowerMutationRoute) {
            $denyReason = 'Code-mode power actions are blocked because their turn origin cannot be proven at the native tool boundary.'
        }
        elseif ($hasSendOrHandoffRoute) {
            $denyReason = 'Code mode cannot send or hand off another task.'
        }
        elseif ($hasAliasedDynamicRoute -or $hasDynamicToolRoute) {
            $denyReason = 'Dynamic code-mode tool dispatch cannot prove that cross-task and automation mutation routes are absent.'
        }
        elseif ($hasNestedShellTool) {
            $nestedCommand = [string](Get-JavaScriptPropertyString -Source $source -Name 'command')
            if ([string]::IsNullOrWhiteSpace($nestedCommand)) { $nestedCommand = [string](Get-JavaScriptPropertyString -Source $source -Name 'cmd') }
            if ($nestedCommand -match '(?i)\bcodex(?:\.(?:cmd|ps1|exe))?\s+app-server\b[^\r\n;&|]*\bthread[\/.:-]send\b' -or
                $nestedCommand -match '(?i)^\s*(?:send_message_to_thread|sendMessageToThread)\b') {
                $denyReason = 'Shell or app-server cross-task send bypasses nested in code mode are disabled.'
            }
        }
    }
    elseif ($toolName -match '(?i)(^|__|\.)automation_update$') {
        $mode = [string](Get-InputProperty -InputObject $toolInput -Names @('mode'))
        $automationId = [string](Get-InputProperty -InputObject $toolInput -Names @('id'))
        $prompt = [string](Get-InputProperty -InputObject $toolInput -Names @('prompt'))
        $watchTargetThreadId = [string](Get-RetiredWatchTargetId -ToolInput $toolInput)
        $turnText = Get-WatchTurnText -Payload $Payload
        $mentionsWatchLifecycle = -not [string]::IsNullOrWhiteSpace($turnText) -and $turnText -match '(?i)守夜|watch-interrupted-task|heartbeat'
        $isWatchMutation = -not [string]::IsNullOrWhiteSpace($watchTargetThreadId) -or
            $prompt -match '(?m)^watch-interrupted-task(?::fleet)?:v1 ' -or
            $automationId -match '^watch-interrupted-task-v1-live-probe-'

        if ($mode -ceq 'view') {
            # Read-only automation inspection remains available from every turn role.
        }
        elseif (Test-RetiredWatchHeartbeatTurn -Payload $Payload) {
            $denyReason = 'Heartbeat turns cannot mutate automation after watch runtime retirement.'
        }
        elseif (($isWatchMutation -or $mentionsWatchLifecycle) -and -not (Test-ExactCurrentLegacyWatchDelete -Payload $Payload -ToolInput $toolInput)) {
            $denyReason = 'Retired watch automation is cleanup-only; only an explicit ordinary-turn delete for the exact current legacy watch id is allowed.'
        }
    }
    elseif ($toolName -match '(?i)^(Bash|shell_command|exec_command)$') {
        $command = [string](Get-InputProperty -InputObject $toolInput -Names @('command','cmd'))
        $hasPowerMutation = $command -match '(?im)(?:^|[\r\n;&|])\s*(?:&\s*)?(?:(?:cmd|pwsh|powershell)(?:\.exe)?\s+(?:/c|-Command)\s+)?(?:shutdown(?:\.exe)?|Stop-Computer|Restart-Computer|Win32Shutdown|InitiateSystemShutdown|ExitWindowsEx)\b'
        if ($hasPowerMutation -and (Test-RetiredWatchHeartbeatTurn -Payload $Payload)) {
            $denyReason = 'Heartbeat-origin power actions are disabled after watch runtime retirement.'
        }
        elseif ($hasPowerMutation -and [string]::IsNullOrWhiteSpace((Get-WatchTurnText -Payload $Payload))) {
            $denyReason = 'Power action turn origin could not be classified; blocking fail-closed.'
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
            if (($hasExecutableSend -or $hasExecutionSubexpression -or $hasReaderExecOption) -and -not (Test-ReadOnlyInspectionSegment -Segment $trimmedSegment)) {
                $denyReason = 'Shell or app-server cross-task send bypasses are disabled.'
                break
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($denyReason)) {
        return [pscustomobject]@{ exit_code=0; permission_decision='deny'; reason=$denyReason }
    }
    return [pscustomobject]@{ exit_code=0; permission_decision='allow'; reason='' }
}
