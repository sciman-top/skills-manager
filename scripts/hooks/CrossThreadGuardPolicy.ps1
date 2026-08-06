# Pure policy core. It parses only supplied objects and text and performs no
# filesystem, process, console, or host mutation. The wrapper owns those edges.
Set-StrictMode -Version Latest

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

function Get-InputPropertyNames {
    param([AllowNull()][object]$InputObject)

    if ($null -eq $InputObject) { return @() }
    if ($InputObject -is [System.Collections.IDictionary]) { return @($InputObject.Keys | ForEach-Object { [string]$_ }) }
    return @($InputObject.PSObject.Properties.Name)
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
        $expectedBodyHashes = @($ExpectedTargetPromptSha256, $ExpectedShutdownTargetPromptSha256)
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
    if ((Get-Sha256Lower -Text $body) -cne $declaredHash) { return $false }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedRuntimeGenerationId) -and $body -notmatch ('(?m)^watch_runtime_generation_id=' + [regex]::Escape($ExpectedRuntimeGenerationId) + '$')) { return $false }
    return $true
}

function Get-WatchTurnText {
    param([Parameter(Mandatory = $true)][object]$Payload)

    $turnText = Get-InputProperty -InputObject $Payload -Names @('__watch_turn_text')
    if ($turnText -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$turnText)) { return $null }
    return [string]$turnText
}

function Get-WatchHeartbeatEnvelopeContext {
    param([Parameter(Mandatory = $true)][object]$Payload)

    $sessionId = [string](Get-InputProperty -InputObject $Payload -Names @('session_id','sessionId'))
    $combined = Get-WatchTurnText -Payload $Payload
    if ([string]::IsNullOrWhiteSpace($sessionId) -or [string]::IsNullOrWhiteSpace($combined)) { return $null }
    $pattern = '(?s)^\s*<heartbeat>\s*<automation_id>(?<automation>[^<]+)</automation_id>\s*(?:<current_time_iso>[^<]+</current_time_iso>\s*)?<instructions>\s*(?<prompt>watch-interrupted-task:(?<fleet>fleet:)?v1\s+.*?)\s*</instructions>\s*</heartbeat>\s*$'
    $match = [regex]::Match($combined,$pattern)
    if (-not $match.Success) { return $null }
    $automationId = $match.Groups['automation'].Value.Trim()
    if ($automationId -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$') { return $null }
    $prompt = $match.Groups['prompt'].Value
    if (-not (Test-CanonicalWatchPrompt -Prompt $prompt -ExpectedTargetThreadId $sessionId)) { return $null }
    $lines = @(((($prompt -replace "`r`n","`n") -replace "`r","`n").TrimEnd()) -split "`n")
    return [pscustomobject][ordered]@{
        automation_id = $automationId
        session_id = $sessionId
        prompt = $prompt
        prompt_sha256 = if ($lines.Count -ge 3) { $lines[2].Substring('prompt_sha256='.Length) } else { '' }
        role = if ($match.Groups['fleet'].Success) { 'fleet_heartbeat' } else { 'target_heartbeat' }
    }
}

function Get-WatchTurnRole {
    param([Parameter(Mandatory = $true)][object]$Payload)

    $combined = Get-WatchTurnText -Payload $Payload
    if ([string]::IsNullOrWhiteSpace($combined)) {
        return 'unknown'
    }
    $context = Get-WatchHeartbeatEnvelopeContext $Payload
    if ($null -ne $context) { return [string]$context.role }
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
    $context = Get-WatchHeartbeatEnvelopeContext $Payload
    return $null -ne $context -and [string]$context.role -ceq 'fleet_heartbeat' -and
        [string]$context.prompt_sha256 -ceq $ExpectedFleetShutdownPromptSha256.ToLowerInvariant()
}

function Test-ShutdownManagedTargetHeartbeat {
    param([Parameter(Mandatory = $true)][object]$Payload)

    if ([string]::IsNullOrWhiteSpace($ExpectedShutdownTargetPromptSha256)) { return $false }
    $context = Get-WatchHeartbeatEnvelopeContext $Payload
    return $null -ne $context -and [string]$context.role -ceq 'target_heartbeat' -and
        [string]$context.prompt_sha256 -ceq $ExpectedShutdownTargetPromptSha256.ToLowerInvariant()
}

function Test-ExactTargetSelfPause {
    param(
        [Parameter(Mandatory = $true)][object]$Payload,
        [Parameter(Mandatory = $true)][object]$ToolInput
    )

    $context = Get-WatchHeartbeatEnvelopeContext $Payload
    if ($null -eq $context) { return $false }
    $sessionId = [string]$context.session_id
    $mode = [string](Get-InputProperty -InputObject $ToolInput -Names @('mode'))
    $id = [string](Get-InputProperty -InputObject $ToolInput -Names @('id'))
    $targetThreadId = [string](Get-InputProperty -InputObject $ToolInput -Names @('targetThreadId', 'target_thread_id'))
    $status = [string](Get-InputProperty -InputObject $ToolInput -Names @('status'))
    $kind = [string](Get-InputProperty -InputObject $ToolInput -Names @('kind'))
    $prompt = [string](Get-InputProperty -InputObject $ToolInput -Names @('prompt'))
    $rrule = [string](Get-InputProperty -InputObject $ToolInput -Names @('rrule'))
    $notificationPolicy = [string](Get-InputProperty -InputObject $ToolInput -Names @('notificationPolicy','notification_policy'))
    $name = [string](Get-InputProperty -InputObject $ToolInput -Names @('name'))
    $allowedProperties = @('mode','id','targetThreadId','target_thread_id','status','kind','name','prompt','rrule','notificationPolicy','notification_policy','destination')
    $unexpected = @(Get-InputPropertyNames -InputObject $ToolInput | Where-Object { $_ -notin $allowedProperties })
    return $unexpected.Count -eq 0 -and $mode -ceq 'update' -and $status -ceq 'PAUSED' -and $kind -ceq 'heartbeat' -and
        $id -ceq [string]$context.automation_id -and $targetThreadId -ceq $sessionId -and
        -not [string]::IsNullOrWhiteSpace($name) -and $prompt -ceq [string]$context.prompt -and
        $rrule -ceq 'FREQ=MINUTELY;INTERVAL=12' -and $notificationPolicy -ceq 'failed_runs_only' -and
        (Test-ShutdownManagedTargetHeartbeat -Payload $Payload)
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
    $targetThreadId = [string](Get-WatchAutomationTargetId -ToolInput $ToolInput -Payload $Payload)
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
    param(
        [AllowNull()][object]$ToolInput,
        [AllowNull()][object]$Payload
    )

    $id = [string](Get-InputProperty -InputObject $ToolInput -Names @('id'))
    $metadata = Get-InputProperty -InputObject $Payload -Names @('__watch_automation_metadata')
    if ($null -ne $metadata -and [string](Get-InputProperty -InputObject $metadata -Names @('id')) -ceq $id) {
        $metadataTarget = [string](Get-InputProperty -InputObject $metadata -Names @('target_thread_id','targetThreadId'))
        if (-not [string]::IsNullOrWhiteSpace($metadataTarget)) { return $metadataTarget }
    }
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

function ConvertFrom-WatchStaticAutomationCall {
    param([Parameter(Mandatory = $true)][string]$Source)

    $skeleton = Get-JavaScriptCodeSkeleton $Source
    $toolCalls = [regex]::Matches($skeleton,'(?i)tools\s*\.\s*codex_app__automation_update\s*\(')
    if ($toolCalls.Count -ne 1 -or
        $Source -notmatch '(?is)^\s*(?:const\s+result\s*=\s*)?await\s+tools\.codex_app__automation_update\s*\(\s*\{.*\}\s*\)\s*;\s*(?:text\s*\(\s*result\s*\)\s*;\s*)?$') { return $null }
    if ($skeleton -match '(?is)\btools\s*(?:\?\s*\.)?\s*\[' -or
        $skeleton -match '(?is)\b(?:const|let|var)\s+(?:[A-Za-z_$][A-Za-z0-9_$]*|\{[^}]*\}|\[[^\]]*\])\s*=\s*tools\b') { return $null }

    $result = [ordered]@{}
    foreach ($name in @('mode','id','kind','name','prompt','rrule','status','notificationPolicy','targetThreadId','destination')) {
        $value = Get-JavaScriptPropertyString -Source $Source -Name $name
        if ($null -ne $value) { $result[$name] = [string]$value }
    }
    if (-not $result.Contains('mode')) { return $null }
    return [pscustomobject]$result
}

function Test-WatchFleetCandidateReceipt {
    param([Parameter(Mandatory = $true)][object]$Payload,[switch]$RequireSupervisorDeleted)

    $context = Get-WatchHeartbeatEnvelopeContext $Payload
    $state = Get-InputProperty -InputObject $Payload -Names @('__watch_fleet_state')
    if ($null -eq $context -or $null -eq $state -or [string]$context.role -cne 'fleet_heartbeat') { return $false }
    if ([string](Get-InputProperty -InputObject $state -Names @('automation_id')) -cne [string]$context.automation_id -or
        [string](Get-InputProperty -InputObject $state -Names @('watch_runtime_generation_id')) -cne $ExpectedRuntimeGenerationId) { return $false }
    $candidate = Get-InputProperty -InputObject $state -Names @('candidate')
    if ($null -eq $candidate -or -not [bool](Get-InputProperty -InputObject $candidate -Names @('final_recheck_completed'))) { return $false }
    $expiry = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string](Get-InputProperty -InputObject $candidate -Names @('expires_at_utc')),[ref]$expiry) -or
        $expiry -le [datetimeoffset]::UtcNow) { return $false }
    if ($RequireSupervisorDeleted) {
        return [bool](Get-InputProperty -InputObject $candidate -Names @('supervisor_deleted')) -and
            [string](Get-InputProperty -InputObject $candidate -Names @('supervisor_delete_receipt_key')) -match '^watch-supervisor-delete:[0-9a-f]{64}$'
    }
    return $true
}

function Test-WatchFleetDelete {
    param([Parameter(Mandatory = $true)][object]$Payload,[Parameter(Mandatory = $true)][object]$ToolInput)

    if (-not (Test-ShutdownArmedFleetHeartbeat $Payload)) { return $false }
    $context = Get-WatchHeartbeatEnvelopeContext $Payload
    $metadata = Get-InputProperty -InputObject $Payload -Names @('__watch_automation_metadata')
    $id = [string](Get-InputProperty -InputObject $ToolInput -Names @('id'))
    if ($null -eq $context -or $null -eq $metadata -or [string](Get-InputProperty -InputObject $ToolInput -Names @('mode')) -cne 'delete' -or
        [string](Get-InputProperty -InputObject $metadata -Names @('id')) -cne $id -or
        [string](Get-InputProperty -InputObject $metadata -Names @('kind')) -cne 'heartbeat') { return $false }

    $targetThreadId = [string](Get-InputProperty -InputObject $metadata -Names @('target_thread_id'))
    $prompt = [string](Get-InputProperty -InputObject $metadata -Names @('prompt'))
    if ($id -ceq [string]$context.automation_id) {
        return $targetThreadId -ceq [string]$context.session_id -and
            (Test-CanonicalWatchPrompt -Prompt $prompt -ExpectedTargetThreadId $targetThreadId) -and
            (Test-WatchFleetCandidateReceipt -Payload $Payload)
    }

    if ($targetThreadId -ceq [string]$context.session_id -or
        [string](Get-InputProperty -InputObject $metadata -Names @('status')) -cne 'PAUSED' -or
        -not (Test-CanonicalWatchPrompt -Prompt $prompt -ExpectedTargetThreadId $targetThreadId)) { return $false }
    $lines = @(((($prompt -replace "`r`n","`n") -replace "`r","`n").TrimEnd()) -split "`n")
    return $lines.Count -ge 3 -and $lines[2] -ceq ('prompt_sha256=' + $ExpectedShutdownTargetPromptSha256.ToLowerInvariant())
}

function Test-WatchFleetPowerAction {
    param([Parameter(Mandatory = $true)][object]$Payload,[Parameter(Mandatory = $true)][string]$Command)
    return (Test-ShutdownArmedFleetHeartbeat $Payload) -and
        $Command -cmatch '^shutdown\.exe /s /t 120 /c "watch-interrupted-task: all monitored tasks stopped"$' -and
        (Test-WatchFleetCandidateReceipt -Payload $Payload -RequireSupervisorDeleted)
}

function Get-CrossThreadGuardDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Payload,
        [ValidatePattern('^$|^[0-9A-Fa-f]{64}$')][string]$ExpectedTargetPromptSha256,
        [ValidatePattern('^$|^[0-9A-Fa-f]{64}$')][string]$ExpectedShutdownTargetPromptSha256,
        [ValidatePattern('^$|^[0-9A-Fa-f]{64}$')][string]$ExpectedFleetPromptSha256,
        [ValidatePattern('^$|^[0-9A-Fa-f]{64}$')][string]$ExpectedFleetShutdownPromptSha256,
        [ValidatePattern('^$|^watch-runtime-generation:[0-9a-f]{64}$')][string]$ExpectedRuntimeGenerationId
    )

    $hookEventName = [string](Get-InputProperty -InputObject $Payload -Names @('hook_event_name', 'hookEventName'))
    if ($hookEventName -cne 'PreToolUse') {
        return [pscustomobject]@{ exit_code=2; permission_decision='error'; reason='Cross-thread guard was invoked outside PreToolUse; blocking fail-closed.' }
    }

    $toolName = [string](Get-InputProperty -InputObject $Payload -Names @('tool_name'))
    if ([string]::IsNullOrWhiteSpace($toolName)) {
        return [pscustomobject]@{ exit_code=2; permission_decision='error'; reason='Cross-thread guard received PreToolUse input without tool_name; blocking fail-closed.' }
    }

    $payload = $Payload
    $toolInput = Get-InputProperty -InputObject $payload -Names @('tool_input')
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

    if ($hasPowerMutationRoute) {
        $command = $literalShellCommand
        $staticPowerCall = $source -match '(?is)^\s*(?:const\s+result\s*=\s*)?await\s+tools\.shell_command\s*\(\s*\{\s*command\s*:\s*"(?:\\.|[^"\\])*"\s*\}\s*\)\s*;\s*(?:text\s*\(\s*result\s*\)\s*;\s*)?$'
        if (-not $staticPowerCall -or -not (Test-WatchFleetPowerAction -Payload $payload -Command $command)) {
            $denyReason = 'Code-mode power actions require the exact static shutdown call and the current final fleet receipt.'
        }
    }
    elseif ($hasSendOrHandoffRoute) {
        $denyReason = 'Code mode cannot send or hand off another task.'
    }
    elseif ($hasAliasedDynamicRoute -or $hasDynamicToolRoute) {
        $denyReason = 'Dynamic code-mode tool dispatch cannot prove that cross-task and automation mutation routes are absent.'
    }
    elseif ($hasNestedAutomationTool) {
        $automationInput = ConvertFrom-WatchStaticAutomationCall $source
        if ($null -eq $automationInput) {
            $denyReason = 'Code-mode automation mutation must be one exact static native call with literal fields.'
        }
        else {
            $mode = [string](Get-InputProperty -InputObject $automationInput -Names @('mode'))
            $turnRole = Get-WatchTurnRole $payload
            if ($turnRole -ceq 'target_heartbeat') {
                if (-not (Test-ExactTargetSelfPause -Payload $payload -ToolInput $automationInput)) {
                    $denyReason = 'A shutdown-managed target may only submit the full exact ACTIVE-to-PAUSED update for its current host automation id.'
                }
            }
            elseif ($turnRole -ceq 'fleet_heartbeat') {
                if ($mode -ceq 'delete') {
                    if (-not (Test-WatchFleetDelete -Payload $payload -ToolInput $automationInput)) {
                        $denyReason = 'Fleet delete requires a matching paused canonical target or the current final supervisor receipt.'
                    }
                }
                else {
                    $targetId = [string](Get-WatchAutomationTargetId -ToolInput $automationInput -Payload $payload)
                    $prompt = [string](Get-InputProperty -InputObject $automationInput -Names @('prompt'))
                    $status = [string](Get-InputProperty -InputObject $automationInput -Names @('status'))
                    $kind = [string](Get-InputProperty -InputObject $automationInput -Names @('kind'))
                    $rrule = [string](Get-InputProperty -InputObject $automationInput -Names @('rrule'))
                    if ([string]::IsNullOrWhiteSpace($targetId) -or $targetId -ceq [string]$payload.session_id -or
                        $mode -notin @('create','update') -or $kind -cne 'heartbeat' -or $status -cne 'ACTIVE' -or
                        $rrule -cne 'FREQ=MINUTELY;INTERVAL=12' -or
                        -not (Test-CanonicalWatchPrompt -Prompt $prompt -ExpectedTargetThreadId $targetId)) {
                        $denyReason = 'Fleet enrollment and migration require one exact ACTIVE canonical 12-minute target heartbeat.'
                    }
                }
            }
            elseif ($turnRole -ceq 'ordinary_turn') {
                if (-not (Test-DirectWatchLifecycleIntent -Payload $payload -Mode $mode -ToolInput $automationInput)) {
                    $denyReason = 'Code-mode watch automation mutation requires a direct lifecycle command in the current user turn.'
                }
            }
            else { $denyReason = 'Code-mode watch automation mutation origin is unknown.' }
        }
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
}
elseif ($toolName -match '(?i)(^|__|\.)automation_update$') {
    $mode = [string](Get-InputProperty -InputObject $toolInput -Names @('mode'))
    $automationId = [string](Get-InputProperty -InputObject $toolInput -Names @('id'))
    $prompt = [string](Get-InputProperty -InputObject $toolInput -Names @('prompt'))
    $targetThreadId = [string](Get-InputProperty -InputObject $toolInput -Names @('targetThreadId', 'target_thread_id'))
    $status = [string](Get-InputProperty -InputObject $toolInput -Names @('status'))
    $sessionId = [string]$payload.session_id
    $context = Get-WatchHeartbeatEnvelopeContext $payload
    $isWatchPrompt = $prompt -match '(?m)^watch-interrupted-task(?::fleet)?:v1 '
    $isCrossTargetPrompt = -not [string]::IsNullOrWhiteSpace($prompt) -and -not [string]::IsNullOrWhiteSpace($targetThreadId) -and $targetThreadId -cne $sessionId
    $watchTargetThreadId = [string](Get-WatchAutomationTargetId -ToolInput $toolInput -Payload $payload)
    $isWatchMutation = $null -ne $context -or -not [string]::IsNullOrWhiteSpace($watchTargetThreadId) -or $isWatchPrompt -or
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
            if (-not (Test-ExactTargetSelfPause -Payload $payload -ToolInput $toolInput)) {
                $denyReason = 'A shutdown-managed target may only submit the full exact ACTIVE-to-PAUSED update for its current host automation id.'
            }
        }
        elseif ($turnRole -ceq 'fleet_heartbeat') {
            $shutdownArmedFleet = Test-ShutdownArmedFleetHeartbeat -Payload $payload
            if (-not $isWatchMutation) {
                $denyReason = 'The fleet supervisor heartbeat may mutate only canonical watch-interrupted-task automations.'
            }
            elseif ($mode -ceq 'delete') {
                if (-not (Test-WatchFleetDelete -Payload $payload -ToolInput $toolInput)) {
                    $denyReason = 'Fleet delete requires a matching paused canonical target or the current final supervisor receipt.'
                }
            }
            elseif ([string]::IsNullOrWhiteSpace($watchTargetThreadId)) {
                $denyReason = 'The fleet supervisor heartbeat could not prove the target watch identity.'
            }
            elseif ($watchTargetThreadId -ceq $sessionId) {
                $denyReason = 'The fleet supervisor heartbeat cannot update or pause its own dual-role automation.'
            }
            elseif ($mode -ceq 'update' -and $status -ieq 'PAUSED') {
                $denyReason = 'The target owns its exact shutdown-managed self-pause; the fleet supervisor may delete only after fresh PAUSED cleanup proof.'
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
            if (-not (Test-WatchFleetPowerAction -Payload $payload -Command $command)) {
                $denyReason = 'Fleet power actions require the exact command and an unexpired final supervisor receipt.'
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
        return [pscustomobject]@{ exit_code=0; permission_decision='deny'; reason=$denyReason }
    }
    return [pscustomobject]@{ exit_code=0; permission_decision='allow'; reason='' }
}
