[CmdletBinding()]
param()

$rawInput = [Console]::In.ReadToEnd()

try {
    $payload = $rawInput | ConvertFrom-Json -Depth 50 -ErrorAction Stop
}
catch {
    [Console]::Error.WriteLine('Cross-thread guard could not parse PreToolUse input; blocking fail-closed.')
    exit 2
}

$toolName = [string]$payload.tool_name
if ($toolName -notmatch '(?i)(^|__|\.)send_message_to_thread$') {
    exit 0
}

[ordered]@{
    hookSpecificOutput = [ordered]@{
        hookEventName = 'PreToolUse'
        permissionDecision = 'deny'
        permissionDecisionReason = 'Cross-task message injection is disabled. The user must communicate directly in the target task.'
    }
} | ConvertTo-Json -Depth 5 -Compress

exit 0
