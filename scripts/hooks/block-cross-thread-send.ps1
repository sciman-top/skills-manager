# Keep LF bytes stable because Codex hook trust hashes the installed definition.
[CmdletBinding()]
param(
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedScriptSha256
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
        $property = $InputObject.PSObject.Properties[$name]
        if ($null -ne $property) {
            return $property.Value
        }
    }

    return $null
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
    if ($lines.Count -lt 5 -or $lines[1] -cne 'policy_revision=2' -or $lines[2] -cnotmatch '^prompt_sha256=([0-9a-f]{64})$' -or $lines[3] -ne '') {
        return $false
    }

    $markerTarget = $null
    if ($lines[0] -match '^watch-interrupted-task:v1 target_thread_id=([A-Za-z0-9][A-Za-z0-9._:-]{0,255})$') {
        $markerTarget = $Matches[1]
    }
    elseif ($lines[0] -match '^watch-interrupted-task:fleet:v1 supervisor_thread_id=([A-Za-z0-9][A-Za-z0-9._:-]{0,255})$') {
        $markerTarget = $Matches[1]
    }
    else {
        return $false
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedTargetThreadId) -and $markerTarget -cne $ExpectedTargetThreadId) {
        return $false
    }

    $declaredHash = $lines[2].Substring('prompt_sha256='.Length)
    $body = [string]::Join("`n", $lines[4..($lines.Count - 1)])
    return (Get-Sha256Lower -Text $body) -ceq $declaredHash
}

try {
    $payload = $rawInput | ConvertFrom-Json -Depth 50 -ErrorAction Stop
}
catch {
    [Console]::Error.WriteLine('Cross-thread guard could not parse PreToolUse input; blocking fail-closed.')
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
    $followUpPrompt = [string](Get-InputProperty -InputObject $toolInput -Names @('followUpPrompt', 'follow_up_prompt', 'prompt'))
    if (-not [string]::IsNullOrWhiteSpace($followUpPrompt)) {
        $denyReason = 'Cross-task handoff prompts are disabled. The user must communicate directly in the target task.'
    }
}
elseif ($toolName -match '(?i)(^|__|\.)automation_update$') {
    $prompt = [string](Get-InputProperty -InputObject $toolInput -Names @('prompt'))
    $targetThreadId = [string](Get-InputProperty -InputObject $toolInput -Names @('targetThreadId', 'target_thread_id'))
    $sessionId = [string]$payload.session_id
    $isWatchPrompt = $prompt -match '(?m)^watch-interrupted-task(?::fleet)?:v1 '
    $isCrossTargetPrompt = -not [string]::IsNullOrWhiteSpace($prompt) -and -not [string]::IsNullOrWhiteSpace($targetThreadId) -and $targetThreadId -cne $sessionId

    if (($isWatchPrompt -or $isCrossTargetPrompt) -and -not (Test-CanonicalWatchPrompt -Prompt $prompt -ExpectedTargetThreadId $targetThreadId)) {
        $denyReason = 'Cross-target automation prompts must use the hash-valid watch-interrupted-task policy_revision=2 envelope.'
    }
}
elseif ($toolName -match '(?i)^(Bash|shell_command|exec_command)$') {
    $command = [string](Get-InputProperty -InputObject $toolInput -Names @('command', 'cmd'))
    foreach ($segment in @($command -split '[\r\n;&|]+')) {
        $trimmedSegment = $segment.Trim()
        if ($trimmedSegment -notmatch '(?i)(send_message_to_thread|sendMessageToThread|thread[\/.:-]send)') {
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
