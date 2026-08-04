$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$hookPath = Join-Path $repoRoot 'scripts\hooks\block-cross-thread-send.ps1'

function Invoke-CrossThreadHook {
    param([Parameter(Mandatory = $true)][string]$ToolName)

    $payload = [ordered]@{
        session_id = 'session-test'
        turn_id = 'turn-test'
        hook_event_name = 'PreToolUse'
        tool_name = $ToolName
        tool_use_id = 'tool-test'
        tool_input = [ordered]@{
            threadId = 'target-test'
            prompt = 'coordination message'
        }
    } | ConvertTo-Json -Depth 5 -Compress

    $output = $payload | & pwsh -NoProfile -ExecutionPolicy Bypass -File $hookPath
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = @($output) -join "`n"
    }
}

Describe 'Cross-thread PreToolUse guard' {
    It 'blocks every known send-message-to-thread tool spelling' {
        foreach ($toolName in @(
            'send_message_to_thread',
            'codex_app__send_message_to_thread',
            'codex_app.send_message_to_thread'
        )) {
            $result = Invoke-CrossThreadHook -ToolName $toolName
            $result.ExitCode | Should Be 0
            $decision = $result.Output | ConvertFrom-Json
            $decision.hookSpecificOutput.hookEventName | Should Be 'PreToolUse'
            $decision.hookSpecificOutput.permissionDecision | Should Be 'deny'
            $decision.hookSpecificOutput.permissionDecisionReason | Should Match 'Cross-task message injection is disabled'
        }
    }

    It 'does not interfere with read-only thread inspection' {
        foreach ($toolName in @('codex_app__list_threads', 'codex_app__read_thread', 'codex_app__wait_threads')) {
            $result = Invoke-CrossThreadHook -ToolName $toolName
            $result.ExitCode | Should Be 0
            $result.Output | Should BeNullOrEmpty
        }
    }

    It 'fails closed when hook input is malformed' {
        $null = '{' | & pwsh -NoProfile -ExecutionPolicy Bypass -File $hookPath 2>$null
        $LASTEXITCODE | Should Be 2
    }
}
