$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$hookPath = Join-Path $repoRoot 'scripts\hooks\block-cross-thread-send.ps1'

function Invoke-CrossThreadHook {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$ToolName,
        [object]$ToolInput = ([ordered]@{
            threadId = 'target-test'
            prompt = 'coordination message'
        }),
        [string]$SessionId = 'source-test'
    )

    $payload = [ordered]@{
        session_id = $SessionId
        turn_id = 'turn-test'
        hook_event_name = 'PreToolUse'
        tool_name = $ToolName
        tool_use_id = 'tool-test'
        tool_input = $ToolInput
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

    It 'blocks a handoff that carries a follow-up prompt' {
        $result = Invoke-CrossThreadHook -ToolName 'codex_app__handoff_thread' -ToolInput ([ordered]@{
            threadId = 'target-test'
            followUpPrompt = 'take over this task'
        })
        ($result.Output | ConvertFrom-Json).hookSpecificOutput.permissionDecision | Should Be 'deny'
    }

    It 'allows only a hash-valid revision-2 watch prompt for cross-target automation updates' {
        $generator = Join-Path $repoRoot 'overrides\watch-interrupted-task\scripts\New-WatchHeartbeatPrompt.ps1'
        $canonicalPrompt = & $generator -TargetThreadId 'target-test'
        $valid = Invoke-CrossThreadHook -ToolName 'codex_app__automation_update' -ToolInput ([ordered]@{
            mode = 'create'
            targetThreadId = 'target-test'
            prompt = $canonicalPrompt
        })
        $valid.Output | Should BeNullOrEmpty

        foreach ($prompt in @(
            'arbitrary cross-task prompt',
            ($canonicalPrompt -replace 'policy_revision=2', 'policy_revision=1'),
            ($canonicalPrompt -replace 'prompt_sha256=[0-9a-f]{64}', ('prompt_sha256=' + ('0' * 64)))
        )) {
            $invalid = Invoke-CrossThreadHook -ToolName 'codex_app__automation_update' -ToolInput ([ordered]@{
                mode = 'create'
                targetThreadId = 'target-test'
                prompt = $prompt
            })
            ($invalid.Output | ConvertFrom-Json).hookSpecificOutput.permissionDecision | Should Be 'deny'
        }
    }

    It 'blocks explicit app-server send bypasses without blocking source inspection' {
        $blocked = Invoke-CrossThreadHook -ToolName 'Bash' -ToolInput ([ordered]@{
            command = 'codex app-server request thread/send --thread target-test'
        })
        ($blocked.Output | ConvertFrom-Json).hookSpecificOutput.permissionDecision | Should Be 'deny'

        $inspection = Invoke-CrossThreadHook -ToolName 'Bash' -ToolInput ([ordered]@{
            command = 'rg -n send_message_to_thread tests'
        })
        $inspection.Output | Should BeNullOrEmpty

        $literalInspection = Invoke-CrossThreadHook -ToolName 'Bash' -ToolInput ([ordered]@{
            command = "rg -n 'codex app-server request thread/send' C:\Users\sciman\.codex"
        })
        $literalInspection.Output | Should BeNullOrEmpty
    }

    It 'blocks multiline and nested-shell app-server send bypasses' {
        foreach ($command in @(
            "Write-Output harmless`ncodex app-server request thread/send --thread target-test",
            'cmd /c codex app-server request thread/send --thread target-test',
            'pwsh -Command "codex app-server request thread/send --thread target-test"',
            "rg -n 'thread/send' docs`ncodex app-server request thread/send --thread target-test"
        )) {
            $result = Invoke-CrossThreadHook -ToolName 'shell_command' -ToolInput ([ordered]@{
                command = $command
            })
            $result.ExitCode | Should Be 0
            ($result.Output | ConvertFrom-Json).hookSpecificOutput.permissionDecision | Should Be 'deny'
        }
    }

    It 'blocks execution-capable options and subexpressions behind read-only command prefixes' {
        foreach ($command in @(
            'rg --pre "codex app-server request thread/send --thread target-test" thread/send docs',
            'git grep -O "codex app-server request thread/send --thread target-test" thread/send',
            'rg "$(codex app-server request thread/send --thread target-test)" docs',
            'Select-String -InputObject $(codex app-server request thread/send --thread target-test) -Pattern x',
            'Get-Content (codex app-server request thread/send --thread target-test)'
        )) {
            $result = Invoke-CrossThreadHook -ToolName 'shell_command' -ToolInput ([ordered]@{
                command = $command
            })
            $result.ExitCode | Should Be 0
            ($result.Output | ConvertFrom-Json).hookSpecificOutput.permissionDecision | Should Be 'deny'
        }
    }

    It 'fails closed when a valid payload omits tool_name' {
        $payload = [ordered]@{
            session_id = 'source-test'
            hook_event_name = 'PreToolUse'
            tool_input = [ordered]@{}
        } | ConvertTo-Json -Depth 5 -Compress
        $null = $payload | & pwsh -NoProfile -ExecutionPolicy Bypass -File $hookPath 2>$null
        $LASTEXITCODE | Should Be 2
    }

    It 'fails closed when the installed script differs from the trusted command hash' {
        $payload = [ordered]@{
            session_id = 'source-test'
            hook_event_name = 'PreToolUse'
            tool_name = 'codex_app__list_threads'
            tool_input = [ordered]@{}
        } | ConvertTo-Json -Depth 5 -Compress
        $null = $payload | & pwsh -NoProfile -ExecutionPolicy Bypass -File $hookPath -ExpectedScriptSha256 ('0' * 64) 2>$null
        $LASTEXITCODE | Should Be 2
    }

    It 'fails closed when hook input is malformed' {
        $null = '{' | & pwsh -NoProfile -ExecutionPolicy Bypass -File $hookPath 2>$null
        $LASTEXITCODE | Should Be 2
    }
}
