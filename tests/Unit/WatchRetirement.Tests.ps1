Describe 'watch-interrupted-task retirement contract' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $script:skill = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\SKILL.md')
        $script:metadata = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\agents\openai.yaml')
        $script:config = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'skills.json') | ConvertFrom-Json
        $script:targetGenerator = Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\scripts\New-WatchHeartbeatPrompt.ps1'
        $script:fleetGenerator = Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\scripts\New-WatchFleetSupervisorPrompt.ps1'
        . (Join-Path $repoRoot 'scripts\hooks\CrossThreadGuardPolicy.ps1')

        $script:targetPrompt = & $script:targetGenerator -TargetThreadId 'retired-target' -ShutdownManaged
        $script:targetPromptHash = ((& $script:targetGenerator -TargetThreadId 'digest-probe' -AsJson) | ConvertFrom-Json).prompt_sha256
        $script:shutdownTargetPromptHash = ((& $script:targetGenerator -TargetThreadId 'digest-probe' -ShutdownManaged -AsJson) | ConvertFrom-Json).prompt_sha256
        $script:fleetPromptHash = ((& $script:fleetGenerator -SupervisorThreadId 'digest-probe' -AsJson) | ConvertFrom-Json).prompt_sha256
        $script:fleetShutdownPromptHash = ((& $script:fleetGenerator -SupervisorThreadId 'digest-probe' -ShutdownWhenAllStopped -AsJson) | ConvertFrom-Json).prompt_sha256
        $script:runtimeGenerationId = ((& $script:targetGenerator -TargetThreadId 'digest-probe' -AsJson) | ConvertFrom-Json).watch_runtime_generation_id
    }

    It 'removes the legacy watch from the resident skill set' {
        @($script:config.skill_projection.resident_names) | Should Not Contain 'watch-interrupted-task'
    }

    It 'fails closed and forbids every legacy lifecycle activation' {
        $script:skill | Should Match 'runtime_status=retired_fail_closed'
        $script:skill | Should Match 'Never create, arm, enable, resume, reactivate, update, clone, or schedule'
        $script:skill | Should Match 'Never emit heartbeat XML'
        $script:skill | Should Match 'Never execute `shutdown\.exe`'
    }

    It 'exposes only cleanup-oriented host metadata' {
        $script:metadata | Should Match '旧守夜退役入口'
        $script:metadata | Should Match 'never create, arm, resume, or update a watch'
        $script:metadata | Should Not Match 'recover this task'
    }

    It 'denies every heartbeat-origin lifecycle mutation and power action after retirement' {
        $fleetPrompt = & $script:fleetGenerator -SupervisorThreadId 'retired-supervisor'
        $fleetShutdownPrompt = & $script:fleetGenerator -SupervisorThreadId 'retired-supervisor' -ShutdownWhenAllStopped
        $targetEnvelope = "<heartbeat>`n<automation_id>retired-target-automation</automation_id>`n<instructions>`n$script:targetPrompt`n</instructions>`n</heartbeat>"
        $fleetEnvelope = "<heartbeat>`n<automation_id>retired-supervisor-automation</automation_id>`n<instructions>`n$fleetPrompt`n</instructions>`n</heartbeat>"
        $fleetShutdownEnvelope = "<heartbeat>`n<automation_id>retired-supervisor-automation</automation_id>`n<instructions>`n$fleetShutdownPrompt`n</instructions>`n</heartbeat>"
        $freshCandidate = [ordered]@{
            final_recheck_completed = $true
            expires_at_utc = [datetimeoffset]::UtcNow.AddMinutes(5).ToString('o')
            supervisor_deleted = $true
            supervisor_delete_receipt_key = 'watch-supervisor-delete:' + ('a' * 64)
        }

        $cases = @(
            [ordered]@{
                session_id = 'retired-target'
                hook_event_name = 'PreToolUse'
                tool_name = 'codex_app__automation_update'
                tool_input = [ordered]@{ mode='update'; id='retired-target-automation'; kind='heartbeat'; name='Retired target'; prompt=$script:targetPrompt; rrule='FREQ=MINUTELY;INTERVAL=12'; status='PAUSED'; notificationPolicy='failed_runs_only'; targetThreadId='retired-target' }
                __watch_turn_text = $targetEnvelope
            }
            [ordered]@{
                session_id = 'retired-supervisor'
                hook_event_name = 'PreToolUse'
                tool_name = 'codex_app__automation_update'
                tool_input = [ordered]@{ mode='create'; kind='heartbeat'; name='Retired target'; prompt=(& $script:targetGenerator -TargetThreadId 'retired-target'); rrule='FREQ=MINUTELY;INTERVAL=12'; status='ACTIVE'; notificationPolicy='failed_runs_only'; targetThreadId='retired-target' }
                __watch_turn_text = $fleetEnvelope
            }
            [ordered]@{
                session_id = 'retired-supervisor'
                hook_event_name = 'PreToolUse'
                tool_name = 'codex_app__automation_update'
                tool_input = [ordered]@{ mode='delete'; id='retired-target-automation' }
                __watch_turn_text = $fleetShutdownEnvelope
                __watch_automation_metadata = [ordered]@{ id='retired-target-automation'; kind='heartbeat'; target_thread_id='retired-target'; prompt=$script:targetPrompt; status='PAUSED' }
                __watch_fleet_state = [ordered]@{ automation_id='retired-supervisor-automation'; watch_runtime_generation_id=$script:runtimeGenerationId; candidate=$freshCandidate }
            }
            [ordered]@{
                session_id = 'retired-supervisor'
                hook_event_name = 'PreToolUse'
                tool_name = 'shell_command'
                tool_input = [ordered]@{ command='shutdown.exe /s /t 120 /c "watch-interrupted-task: all monitored tasks stopped"' }
                __watch_turn_text = $fleetShutdownEnvelope
                __watch_fleet_state = [ordered]@{ automation_id='retired-supervisor-automation'; watch_runtime_generation_id=$script:runtimeGenerationId; candidate=$freshCandidate }
            }
        )

        foreach ($case in $cases) {
            $decision = Get-CrossThreadGuardDecision -Payload ([pscustomobject]$case)
            $decision.permission_decision | Should Be 'deny'
        }
    }

    It 'allows only an explicit ordinary-turn delete for the exact current legacy watch id' {
        $exactId = 'watch-interrupted-task-v1-target-thread-id-retired-target'
        $allowed = Get-CrossThreadGuardDecision -Payload ([pscustomobject][ordered]@{
            session_id = 'retired-target'
            hook_event_name = 'PreToolUse'
            tool_name = 'codex_app__automation_update'
            tool_input = [ordered]@{ mode='delete'; id=$exactId }
            __watch_turn_text = '关闭当前任务的旧守夜。'
        })
        $allowed.permission_decision | Should Be 'allow'

        foreach ($case in @(
            [ordered]@{ Text='开启当前任务守夜。'; Input=[ordered]@{ mode='create'; kind='heartbeat'; targetThreadId='retired-target'; prompt='watch-interrupted-task:v1 target_thread_id=retired-target' } }
            [ordered]@{ Text='恢复当前任务守夜。'; Input=[ordered]@{ mode='update'; id=$exactId; kind='heartbeat'; status='ACTIVE'; targetThreadId='retired-target'; prompt='watch-interrupted-task:v1 target_thread_id=retired-target' } }
            [ordered]@{ Text='不要关闭当前任务守夜。'; Input=[ordered]@{ mode='delete'; id=$exactId } }
            [ordered]@{ Text='请把“关闭当前任务守夜”写进文档。'; Input=[ordered]@{ mode='delete'; id=$exactId } }
            [ordered]@{ Text='关闭当前任务守夜。'; Input=[ordered]@{ mode='delete'; id='watch-interrupted-task-v1-target-thread-id-other-target' } }
        )) {
            $decision = Get-CrossThreadGuardDecision -Payload ([pscustomobject][ordered]@{
                session_id = 'retired-target'
                hook_event_name = 'PreToolUse'
                tool_name = 'codex_app__automation_update'
                tool_input = $case.Input
                __watch_turn_text = $case.Text
            })
            $decision.permission_decision | Should Be 'deny'
        }
    }

    It 'projects only the cross-thread guard contract and no retired watch runtime metadata' {
        $codexHome = Join-Path $TestDrive 'installer-retirement-home'
        $null = New-Item -ItemType Directory -Path $codexHome -Force
        Set-Content -LiteralPath (Join-Path $codexHome 'config.toml') -Value "hooks = true`n" -NoNewline
        [ordered]@{ hooks = [ordered]@{ PreToolUse = @() } } |
            ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $codexHome 'hooks.json') -NoNewline

        $installer = Join-Path $repoRoot 'scripts\hooks\Install-CrossThreadGuard.ps1'
        $result = @(& $installer -CodexHome $codexHome)
        $hooks = Get-Content -Raw -LiteralPath (Join-Path $codexHome 'hooks.json') | ConvertFrom-Json
        $guard = @($hooks.hooks.PreToolUse | ForEach-Object { $_.hooks } | Where-Object { [string]$_.command -like '*block-cross-thread-send.ps1*' })[0]

        [string]$guard.command | Should Match '-ExpectedScriptSha256'
        [string]$guard.command | Should Match '-ExpectedPolicySha256'
        [string]$guard.command | Should Not Match 'ExpectedTargetPromptSha256|ExpectedShutdownTargetPromptSha256|ExpectedFleetPromptSha256|ExpectedFleetShutdownPromptSha256|ExpectedRuntimeGenerationId|AutomationRoot|WatchFleetStateRoot'
        @($result[0].PSObject.Properties.Name) | Should Not Contain 'watch_runtime_generation_id'
        Test-Path -LiteralPath (Join-Path $codexHome 'scripts\Test-WatchGuardRuntime.ps1') | Should Be $false
    }

    It 'removes retired recovery parameters and state readers from the active hook surface' {
        $hookPath = Join-Path $repoRoot 'scripts\hooks\block-cross-thread-send.ps1'
        $policyPath = Join-Path $repoRoot 'scripts\hooks\CrossThreadGuardPolicy.ps1'
        $hookCommand = Get-Command -Name $hookPath
        $decisionCommand = Get-Command -Name 'Get-CrossThreadGuardDecision'
        $retiredParameters = @(
            'ExpectedTargetPromptSha256','ExpectedShutdownTargetPromptSha256','ExpectedFleetPromptSha256',
            'ExpectedFleetShutdownPromptSha256','ExpectedRuntimeGenerationId','AutomationRoot','WatchFleetStateRoot'
        )

        foreach ($name in $retiredParameters) {
            @($hookCommand.Parameters.Keys) | Should Not Contain $name
            @($decisionCommand.Parameters.Keys) | Should Not Contain $name
        }
        (Get-Content -Raw -LiteralPath $hookPath) | Should Not Match 'Read-WatchAutomationMetadata|Read-WatchFleetState|__watch_automation_metadata|__watch_fleet_state'
        (Get-Content -Raw -LiteralPath $policyPath) | Should Not Match 'Test-CanonicalWatchPrompt|Test-WatchFleetCandidateReceipt|Test-WatchFleetDelete|Test-WatchFleetPowerAction|watch_runtime_generation_id'
    }
}
