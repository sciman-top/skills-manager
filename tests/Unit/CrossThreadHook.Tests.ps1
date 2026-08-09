$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$policyPath = Join-Path $repoRoot 'scripts\hooks\CrossThreadGuardPolicy.ps1'
$hookPath = Join-Path $repoRoot 'scripts\hooks\block-cross-thread-send.ps1'
. $policyPath

function Invoke-CrossThreadPolicy {
    param(
        [Parameter(Mandatory = $true)][string]$ToolName,
        [AllowNull()][object]$ToolInput
    )
    Get-CrossThreadGuardDecision -Payload ([pscustomobject][ordered]@{
        hook_event_name = 'PreToolUse'
        tool_name = $ToolName
        tool_input = $ToolInput
    })
}

Describe 'Cross-thread guard policy' {
    It 'blocks direct cross-task send and handoff tools' {
        foreach ($name in @('codex_app__send_message_to_thread', 'codex_app__handoff_thread')) {
            (Invoke-CrossThreadPolicy -ToolName $name -ToolInput @{}).permission_decision | Should Be 'deny'
        }
    }

    It 'allows read-only automation view and blocks every automation mutation' {
        (Invoke-CrossThreadPolicy -ToolName 'codex_app__automation_update' -ToolInput @{ mode='view'; id='ordinary' }).permission_decision | Should Be 'allow'
        foreach ($mode in @('create', 'update', 'delete')) {
            (Invoke-CrossThreadPolicy -ToolName 'codex_app__automation_update' -ToolInput @{ mode=$mode; id='ordinary' }).permission_decision | Should Be 'deny'
        }
    }

    It 'blocks power mutation from shell and code mode' {
        (Invoke-CrossThreadPolicy -ToolName 'shell_command' -ToolInput @{ command='shutdown.exe /s /t 120' }).permission_decision | Should Be 'deny'
        (Invoke-CrossThreadPolicy -ToolName 'exec' -ToolInput 'await tools.shell_command({ command: "Restart-Computer" });').permission_decision | Should Be 'deny'
    }

    It 'blocks direct, bracket, aliased, and dynamic high-risk code-mode routes' {
        foreach ($source in @(
            'await tools.codex_app__send_message_to_thread({ threadId: "target" });',
            'await tools["codex_app__send_message_to_thread"]({ threadId: "target" });',
            'const sender = tools.codex_app__send_message_to_thread; await sender({ threadId: "target" });',
            'const name = "codex_app__automation_" + "update"; await tools[name]({ mode: "delete", id: "ordinary" });'
        )) {
            (Invoke-CrossThreadPolicy -ToolName 'exec' -ToolInput $source).permission_decision | Should Be 'deny'
        }
    }

    It 'blocks shell app-server send bypasses while allowing literal source inspection' {
        (Invoke-CrossThreadPolicy -ToolName 'shell_command' -ToolInput @{ command='codex app-server request thread/send --thread target' }).permission_decision | Should Be 'deny'
        (Invoke-CrossThreadPolicy -ToolName 'shell_command' -ToolInput @{ command="rg -n 'thread/send' docs" }).permission_decision | Should Be 'allow'
    }

    It 'ignores commented high-risk code-mode syntax' {
        $source = '/* tools.codex_app__send_message_to_thread({ threadId: "target" }); */ text("safe");'
        (Invoke-CrossThreadPolicy -ToolName 'exec' -ToolInput $source).permission_decision | Should Be 'allow'
    }

    It 'fails closed for malformed native hook input' {
        (Get-CrossThreadGuardDecision -Payload ([pscustomobject]@{ hook_event_name='PostToolUse'; tool_name='x'; tool_input=@{} })).exit_code | Should Be 2
        (Get-CrossThreadGuardDecision -Payload ([pscustomobject]@{ hook_event_name='PreToolUse'; tool_input=@{} })).exit_code | Should Be 2
    }

    It 'fails closed when the wrapper input is malformed or its hash differs' {
        $null = '{' | & pwsh -NoProfile -ExecutionPolicy Bypass -File $hookPath 2>$null
        $LASTEXITCODE | Should Be 2

        $payload = @{ hook_event_name='PreToolUse'; tool_name='codex_app__list_threads'; tool_input=@{} } | ConvertTo-Json -Compress
        $null = $payload | & pwsh -NoProfile -ExecutionPolicy Bypass -File $hookPath -ExpectedScriptSha256 ('0' * 64) 2>$null
        $LASTEXITCODE | Should Be 2
    }
}
