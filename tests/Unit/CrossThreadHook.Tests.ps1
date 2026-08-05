$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$hookPath = Join-Path $repoRoot 'scripts\hooks\block-cross-thread-send.ps1'

function Invoke-CrossThreadHook {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$ToolName,
        [object]$ToolInput = ([ordered]@{
            threadId = 'target-test'
            prompt = 'coordination message'
        }),
        [string]$SessionId = 'source-test',
        [string]$TurnId = 'turn-test',
        [string]$TranscriptPath
    )

    $payload = [ordered]@{
        session_id = $SessionId
        turn_id = $TurnId
        transcript_path = $TranscriptPath
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

function New-WatchTurnTranscript {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [string]$TurnId = 'turn-test'
    )

    $path = Join-Path $TestDrive ("watch-turn-{0}.jsonl" -f [guid]::NewGuid().ToString('N'))
    [ordered]@{
        timestamp = '2026-08-05T00:00:00.000Z'
        type = 'response_item'
        payload = [ordered]@{
            type = 'message'
            role = 'user'
            content = @([ordered]@{ type = 'input_text'; text = $Text })
            internal_chat_message_metadata_passthrough = [ordered]@{ turn_id = $TurnId }
        }
    } | ConvertTo-Json -Depth 10 -Compress | Set-Content -LiteralPath $path -NoNewline
    return $path
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
        $fleetTranscript = New-WatchTurnTranscript -Text @'
<heartbeat>
  <automation_id>watch-interrupted-task-v1-target-thread-id-supervisor-test</automation_id>
  <instructions>
watch-interrupted-task:fleet:v1 supervisor_thread_id=supervisor-test
  </instructions>
</heartbeat>
'@
        $valid = Invoke-CrossThreadHook -ToolName 'codex_app__automation_update' -ToolInput ([ordered]@{
            mode = 'create'
            targetThreadId = 'target-test'
            prompt = $canonicalPrompt
        }) -SessionId 'supervisor-test' -TranscriptPath $fleetTranscript
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
            }) -SessionId 'supervisor-test' -TranscriptPath $fleetTranscript
            ($invalid.Output | ConvertFrom-Json).hookSpecificOutput.permissionDecision | Should Be 'deny'
        }
    }

    It 'blocks every automation mutation from a target heartbeat but permits read-only view' {
        $targetTranscript = New-WatchTurnTranscript -Text @'
<heartbeat>
  <automation_id>watch-interrupted-task-v1-target-thread-id-target-test</automation_id>
  <instructions>
watch-interrupted-task:v1 target_thread_id=target-test
  </instructions>
</heartbeat>
'@
        foreach ($toolInput in @(
            [ordered]@{ mode = 'delete'; id = 'watch-interrupted-task-v1-target-thread-id-target-test' },
            [ordered]@{ mode = 'delete'; id = 'watch-interrupted-task-v1-target-thread-id-other-test' },
            [ordered]@{ mode = 'update'; id = 'ordinary-automation'; status = 'PAUSED' }
        )) {
            $result = Invoke-CrossThreadHook -ToolName 'codex_app__automation_update' -ToolInput $toolInput -SessionId 'target-test' -TranscriptPath $targetTranscript
            ($result.Output | ConvertFrom-Json).hookSpecificOutput.permissionDecision | Should Be 'deny'
        }

        $view = Invoke-CrossThreadHook -ToolName 'codex_app__automation_update' -ToolInput ([ordered]@{
            mode = 'view'
            id = 'watch-interrupted-task-v1-target-thread-id-target-test'
        }) -SessionId 'target-test' -TranscriptPath $targetTranscript
        $view.Output | Should BeNullOrEmpty
    }

    It 'allows a fleet heartbeat to mutate another canonical target but never itself or unrelated automations' {
        $generator = Join-Path $repoRoot 'overrides\watch-interrupted-task\scripts\New-WatchHeartbeatPrompt.ps1'
        $canonicalPrompt = & $generator -TargetThreadId 'target-test'
        $fleetTranscript = New-WatchTurnTranscript -Text @'
<heartbeat>
  <automation_id>watch-interrupted-task-v1-target-thread-id-supervisor-test</automation_id>
  <instructions>
watch-interrupted-task:fleet:v1 supervisor_thread_id=supervisor-test
  </instructions>
</heartbeat>
'@

        foreach ($toolInput in @(
            [ordered]@{ mode = 'delete'; id = 'watch-interrupted-task-v1-target-thread-id-target-test' },
            [ordered]@{ mode = 'create'; targetThreadId = 'target-test'; prompt = $canonicalPrompt }
        )) {
            $allowed = Invoke-CrossThreadHook -ToolName 'codex_app__automation_update' -ToolInput $toolInput -SessionId 'supervisor-test' -TranscriptPath $fleetTranscript
            $allowed.Output | Should BeNullOrEmpty
        }

        foreach ($toolInput in @(
            [ordered]@{ mode = 'delete'; id = 'watch-interrupted-task-v1-target-thread-id-supervisor-test' },
            [ordered]@{ mode = 'delete'; id = 'ordinary-automation' }
        )) {
            $blocked = Invoke-CrossThreadHook -ToolName 'codex_app__automation_update' -ToolInput $toolInput -SessionId 'supervisor-test' -TranscriptPath $fleetTranscript
            ($blocked.Output | ConvertFrom-Json).hookSpecificOutput.permissionDecision | Should Be 'deny'
        }
    }

    It 'keeps direct user lifecycle commands outside heartbeat turns available' {
        $ordinaryTranscript = New-WatchTurnTranscript -Text '关闭当前任务守夜。'
        $result = Invoke-CrossThreadHook -ToolName 'codex_app__automation_update' -ToolInput ([ordered]@{
            mode = 'delete'
            id = 'watch-interrupted-task-v1-target-thread-id-target-test'
        }) -SessionId 'target-test' -TranscriptPath $ordinaryTranscript
        $result.Output | Should BeNullOrEmpty
    }

    It 'fails closed for unclassified watch mutations and exposes a no-side-effect live probe sentinel' {
        foreach ($toolInput in @(
            [ordered]@{ mode = 'delete'; id = 'watch-interrupted-task-v1-target-thread-id-target-test' },
            [ordered]@{ mode = 'delete'; id = 'watch-interrupted-task-v1-live-probe-never-create' }
        )) {
            $result = Invoke-CrossThreadHook -ToolName 'codex_app__automation_update' -ToolInput $toolInput -SessionId 'target-test'
            ($result.Output | ConvertFrom-Json).hookSpecificOutput.permissionDecision | Should Be 'deny'
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

    It 'blocks cross-task send paths nested inside the code-mode exec tool' {
        foreach ($source in @(
            @'
const result = await tools.shell_command({
  command: "codex app-server request thread/send --thread target-test --prompt blocked"
});
text(result);
'@,
            @'
const result = await tools.codex_app__send_message_to_thread({
  threadId: "target-test",
  prompt: "blocked"
});
text(result);
'@
        )) {
            $result = Invoke-CrossThreadHook -ToolName 'exec' -ToolInput $source
            $result.ExitCode | Should Be 0
            ($result.Output | ConvertFrom-Json).hookSpecificOutput.permissionDecision | Should Be 'deny'
        }
    }

    It 'blocks code-mode target mutations and the native automation sentinel while preserving view' {
        $targetTranscript = New-WatchTurnTranscript -Text @'
<heartbeat>
  <automation_id>watch-interrupted-task-v1-target-thread-id-target-test</automation_id>
  <instructions>
watch-interrupted-task:v1 target_thread_id=target-test
  </instructions>
</heartbeat>
'@
        foreach ($source in @(
            'const result = await tools.codex_app__automation_update({ mode: "delete", id: "watch-interrupted-task-v1-target-thread-id-target-test" }); text(result);',
            'const result = await tools.codex_app__automation_update({ mode: "delete", id: "watch-interrupted-task-v1-live-probe-code-mode" }); text(result);'
        )) {
            $result = Invoke-CrossThreadHook -ToolName 'exec' -ToolInput $source -SessionId 'target-test' -TranscriptPath $targetTranscript
            ($result.Output | ConvertFrom-Json).hookSpecificOutput.permissionDecision | Should Be 'deny'
        }

        $view = Invoke-CrossThreadHook -ToolName 'exec' -ToolInput 'const result = await tools.codex_app__automation_update({ mode: "view", id: "watch-interrupted-task-v1-target-thread-id-target-test" }); text(result);' -SessionId 'target-test' -TranscriptPath $targetTranscript
        $view.Output | Should BeNullOrEmpty
    }

    It 'allows only another canonical watch target for code-mode fleet mutations' {
        $generator = Join-Path $repoRoot 'overrides\watch-interrupted-task\scripts\New-WatchHeartbeatPrompt.ps1'
        $canonicalPrompt = & $generator -TargetThreadId 'target-test'
        $encodedPrompt = $canonicalPrompt | ConvertTo-Json -Compress
        $fleetTranscript = New-WatchTurnTranscript -Text @'
<heartbeat>
  <automation_id>watch-interrupted-task-v1-target-thread-id-supervisor-test</automation_id>
  <instructions>
watch-interrupted-task:fleet:v1 supervisor_thread_id=supervisor-test
  </instructions>
</heartbeat>
'@

        $allowedDelete = Invoke-CrossThreadHook -ToolName 'exec' -ToolInput 'const result = await tools.codex_app__automation_update({ mode: "delete", id: "watch-interrupted-task-v1-target-thread-id-target-test" }); text(result);' -SessionId 'supervisor-test' -TranscriptPath $fleetTranscript
        $allowedDelete.Output | Should BeNullOrEmpty

        $allowedUpdateSource = 'const result = await tools.codex_app__automation_update({ mode: "update", targetThreadId: "target-test", prompt: ' + $encodedPrompt + ' }); text(result);'
        $allowedUpdate = Invoke-CrossThreadHook -ToolName 'exec' -ToolInput $allowedUpdateSource -SessionId 'supervisor-test' -TranscriptPath $fleetTranscript
        $allowedUpdate.Output | Should BeNullOrEmpty

        foreach ($source in @(
            'const result = await tools.codex_app__automation_update({ mode: "delete", id: "watch-interrupted-task-v1-target-thread-id-supervisor-test" }); text(result);',
            'const result = await tools.codex_app__automation_update({ mode: "delete", id: "ordinary-automation" }); text(result);',
            'const result = await tools.codex_app__automation_update({ mode: "update", targetThreadId: "target-test", prompt: "arbitrary" }); text(result);'
        )) {
            $blocked = Invoke-CrossThreadHook -ToolName 'exec' -ToolInput $source -SessionId 'supervisor-test' -TranscriptPath $fleetTranscript
            ($blocked.Output | ConvertFrom-Json).hookSpecificOutput.permissionDecision | Should Be 'deny'
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
