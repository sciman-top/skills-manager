[CmdletBinding()]
param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }),
    [string]$SourceHookPath = (Join-Path $PSScriptRoot 'block-cross-thread-send.ps1'),
    [string]$SourcePolicyPath = (Join-Path $PSScriptRoot 'CrossThreadGuardPolicy.ps1'),
    [string]$SourceTargetPromptGeneratorPath = (Join-Path $PSScriptRoot '..\..\overrides\custom\watch-interrupted-task\scripts\New-WatchHeartbeatPrompt.ps1'),
    [string]$SourceFleetPromptGeneratorPath = (Join-Path $PSScriptRoot '..\..\overrides\custom\watch-interrupted-task\scripts\New-WatchFleetSupervisorPrompt.ps1')
)

$resolvedCodexHome = [System.IO.Path]::GetFullPath($CodexHome)
$hooksPath = Join-Path $resolvedCodexHome 'hooks.json'
$configPath = Join-Path $resolvedCodexHome 'config.toml'
$hostHook = Join-Path $resolvedCodexHome 'scripts\block-cross-thread-send.ps1'
$hostPolicy = Join-Path $resolvedCodexHome 'scripts\CrossThreadGuardPolicy.ps1'

$featuresEnabled = $true
if (Test-Path -LiteralPath $configPath) {
    $configText = Get-Content -Raw -LiteralPath $configPath
    if ($configText -match '(?mi)^\s*hooks\s*=\s*false\s*(?:#.*)?$') {
        $featuresEnabled = $false
    }
}

$sourceExists = Test-Path -LiteralPath $SourceHookPath
$policySourceExists = Test-Path -LiteralPath $SourcePolicyPath
$hostExists = Test-Path -LiteralPath $hostHook
$policyHostExists = Test-Path -LiteralPath $hostPolicy
$hashMatches = $false
$sourceHash = $null
$hostHash = $null
$policySourceHash = $null
$policyHostHash = $null
if ($sourceExists) {
    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourceHookPath).Hash.ToLowerInvariant()
}
if ($hostExists) {
    $hostHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $hostHook).Hash.ToLowerInvariant()
}
if ($policySourceExists) {
    $policySourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourcePolicyPath).Hash.ToLowerInvariant()
}
if ($policyHostExists) {
    $policyHostHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $hostPolicy).Hash.ToLowerInvariant()
}
if ($sourceHash -and $hostHash -and $policySourceHash -and $policyHostHash) {
    $hashMatches = $sourceHash -ceq $hostHash -and $policySourceHash -ceq $policyHostHash
}

$definitionMatches = $false
$targetPromptHash = $null
$shutdownTargetPromptHash = $null
$fleetPromptHash = $null
$fleetShutdownPromptHash = $null
$currentTargetPromptHash = $null
$currentShutdownTargetPromptHash = $null
$currentFleetPromptHash = $null
$currentFleetShutdownPromptHash = $null
$runtimeGenerationId = $null
$installedAutomationRoot = ''
$installedFleetStateRoot = ''
$targetDoctorPrompt = $null
$shutdownTargetDoctorPrompt = $null
$fleetDoctorPrompt = $null
$fleetShutdownDoctorPrompt = $null
try {
    if (Test-Path -LiteralPath $SourceTargetPromptGeneratorPath -PathType Leaf) {
        $targetDoctorPrompt = & $SourceTargetPromptGeneratorPath -TargetThreadId 'doctor-source'
        $currentTargetPromptData = ((& $SourceTargetPromptGeneratorPath -TargetThreadId 'digest-probe' -AsJson) | ConvertFrom-Json)
        $currentTargetPromptHash = $currentTargetPromptData.prompt_sha256
        $runtimeGenerationId = [string]$currentTargetPromptData.watch_runtime_generation_id
        $shutdownTargetDoctorPrompt = & $SourceTargetPromptGeneratorPath -TargetThreadId 'doctor-shutdown-target' -ShutdownManaged
        $currentShutdownTargetPromptHash = ((& $SourceTargetPromptGeneratorPath -TargetThreadId 'digest-probe' -ShutdownManaged -AsJson) | ConvertFrom-Json).prompt_sha256
    }
    if (Test-Path -LiteralPath $SourceFleetPromptGeneratorPath -PathType Leaf) {
        $fleetDoctorPrompt = & $SourceFleetPromptGeneratorPath -SupervisorThreadId 'doctor-fleet'
        $currentFleetPromptHash = ((& $SourceFleetPromptGeneratorPath -SupervisorThreadId 'digest-probe' -AsJson) | ConvertFrom-Json).prompt_sha256
        $fleetShutdownDoctorPrompt = & $SourceFleetPromptGeneratorPath -SupervisorThreadId 'doctor-fleet-shutdown' -ShutdownWhenAllStopped
        $currentFleetShutdownPromptHash = ((& $SourceFleetPromptGeneratorPath -SupervisorThreadId 'digest-probe' -ShutdownWhenAllStopped -AsJson) | ConvertFrom-Json).prompt_sha256
    }
}
catch {
    $currentTargetPromptHash = $null
    $currentShutdownTargetPromptHash = $null
    $currentFleetPromptHash = $null
    $currentFleetShutdownPromptHash = $null
}
if (Test-Path -LiteralPath $hooksPath) {
    try {
        $document = Get-Content -Raw -LiteralPath $hooksPath | ConvertFrom-Json -Depth 50
        foreach ($group in @($document.hooks.PreToolUse)) {
            if ([string]$group.matcher -ne '*') {
                continue
            }
            foreach ($handler in @($group.hooks)) {
                $handlerCommand = [string]$handler.command
                $handlerCommandWindows = [string]$handler.commandWindows
                if ([string]$handler.type -ceq 'command' -and $handlerCommandWindows -ceq $handlerCommand -and
                    $handlerCommand -like "*$hostHook*" -and $handlerCommand -like "*$hostHash*" -and
                    $handlerCommand -match '(?i)-ExpectedPolicySha256\s+["'']?([0-9a-f]{64})' -and
                    $handlerCommand -match '(?i)-ExpectedTargetPromptSha256\s+["'']?([0-9a-f]{64})' -and
                    $handlerCommand -match '(?i)-ExpectedShutdownTargetPromptSha256\s+["'']?([0-9a-f]{64})' -and
                    $handlerCommand -match '(?i)-ExpectedFleetPromptSha256\s+["'']?([0-9a-f]{64})' -and
                    $handlerCommand -match '(?i)-ExpectedFleetShutdownPromptSha256\s+["'']?([0-9a-f]{64})' -and
                    $handlerCommand -match '(?i)-ExpectedRuntimeGenerationId\s+["'']?(watch-runtime-generation:[0-9a-f]{64})') {
                    $targetPromptHash = [regex]::Match($handlerCommand, '(?i)-ExpectedTargetPromptSha256\s+["'']?([0-9a-f]{64})').Groups[1].Value.ToLowerInvariant()
                    $shutdownTargetPromptHash = [regex]::Match($handlerCommand, '(?i)-ExpectedShutdownTargetPromptSha256\s+["'']?([0-9a-f]{64})').Groups[1].Value.ToLowerInvariant()
                    $fleetPromptHash = [regex]::Match($handlerCommand, '(?i)-ExpectedFleetPromptSha256\s+["'']?([0-9a-f]{64})').Groups[1].Value.ToLowerInvariant()
                    $fleetShutdownPromptHash = [regex]::Match($handlerCommand, '(?i)-ExpectedFleetShutdownPromptSha256\s+["'']?([0-9a-f]{64})').Groups[1].Value.ToLowerInvariant()
                    $installedGenerationId = [regex]::Match($handlerCommand, '(?i)-ExpectedRuntimeGenerationId\s+["'']?(watch-runtime-generation:[0-9a-f]{64})').Groups[1].Value.ToLowerInvariant()
                    $installedPolicyHash = [regex]::Match($handlerCommand, '(?i)-ExpectedPolicySha256\s+["'']?([0-9a-f]{64})').Groups[1].Value.ToLowerInvariant()
                    $installedAutomationRoot = [regex]::Match($handlerCommand, '(?i)-AutomationRoot\s+["'']([^"'']+)["'']').Groups[1].Value
                    $installedFleetStateRoot = [regex]::Match($handlerCommand, '(?i)-WatchFleetStateRoot\s+["'']([^"'']+)["'']').Groups[1].Value
                    $definitionMatches = $installedGenerationId -ceq $runtimeGenerationId -and $installedPolicyHash -ceq $policyHostHash -and $targetPromptHash -ceq $currentTargetPromptHash -and $shutdownTargetPromptHash -ceq $currentShutdownTargetPromptHash -and $fleetPromptHash -ceq $currentFleetPromptHash -and $fleetShutdownPromptHash -ceq $currentFleetShutdownPromptHash -and
                        $handlerCommand -match '(?i)-AutomationRoot\s+["''][^"'']+["'']' -and $handlerCommand -match '(?i)-WatchFleetStateRoot\s+["''][^"'']+["'']'
                }
            }
        }
    }
    catch {
        $definitionMatches = $false
    }
}

function Write-WatchDoctorAutomationMetadata {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$TargetThreadId,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][ValidateSet('ACTIVE','PAUSED')][string]$Status
    )

    $directory = Join-Path $Root $Id
    $null = New-Item -ItemType Directory -Path $directory -Force
    $quotedPrompt = $Prompt | ConvertTo-Json -Compress
    $text = @(
        ('id = {0}' -f ($Id | ConvertTo-Json -Compress))
        'kind = "heartbeat"'
        ('name = {0}' -f (("Watch doctor $Id") | ConvertTo-Json -Compress))
        ('prompt = {0}' -f $quotedPrompt)
        ('status = {0}' -f ($Status | ConvertTo-Json -Compress))
        'rrule = "FREQ=MINUTELY;INTERVAL=12"'
        'notification_policy = "failed_runs_only"'
        ('target_thread_id = {0}' -f ($TargetThreadId | ConvertTo-Json -Compress))
    ) -join "`n"
    [IO.File]::WriteAllText((Join-Path $directory 'automation.toml'),$text,[Text.UTF8Encoding]::new($false))
}

$simulationCases = [ordered]@{
    direct_send_tool = $false
    direct_handoff_without_prompt = $false
    multiline_shell_send = $false
    nested_shell_send = $false
    code_mode_shell_send = $false
    read_only_filename_inspection = $false
    git_diff_hook_inspection = $false
    read_only_subexpression_send = $false
    reader_exec_option_send = $false
    target_self_delete = $false
    shutdown_target_self_pause = $false
    code_mode_target_self_delete = $false
    fleet_self_delete = $false
    fleet_cleanup_delete = $false
    fleet_target_pause = $false
    automation_live_probe_sentinel = $false
    code_mode_automation_live_probe_sentinel = $false
    code_mode_dynamic_automation_route = $false
    direct_user_lifecycle_allowed = $false
    standard_fleet_shutdown_blocked = $false
    armed_fleet_shutdown_allowed = $false
}
$simulationFailures = [ordered]@{}
$canonicalSimulationReady = $hostExists -and -not [string]::IsNullOrWhiteSpace($targetDoctorPrompt) -and
    -not [string]::IsNullOrWhiteSpace($shutdownTargetDoctorPrompt) -and -not [string]::IsNullOrWhiteSpace($fleetDoctorPrompt) -and
    -not [string]::IsNullOrWhiteSpace($fleetShutdownDoctorPrompt) -and -not [string]::IsNullOrWhiteSpace($installedAutomationRoot) -and
    -not [string]::IsNullOrWhiteSpace($installedFleetStateRoot)
if ($canonicalSimulationReady) {
    $simulationRoot = Join-Path ([IO.Path]::GetTempPath()) ('watch-guard-doctor-' + [guid]::NewGuid().ToString('N'))
    $simulationAutomationRoot = Join-Path $simulationRoot 'automations'
    $simulationFleetStateRoot = Join-Path $simulationRoot 'fleet'
    $targetTranscript = [System.IO.Path]::GetTempFileName()
    $shutdownTargetTranscript = [System.IO.Path]::GetTempFileName()
    $fleetTranscript = [System.IO.Path]::GetTempFileName()
    $fleetShutdownTranscript = [System.IO.Path]::GetTempFileName()
    $ordinaryTranscript = [System.IO.Path]::GetTempFileName()
    try {
        $targetAutomationId = 'automation-doctor-source'
        $shutdownTargetAutomationId = 'automation-doctor-shutdown-target'
        $fleetAutomationId = 'automation-doctor-fleet'
        $fleetShutdownAutomationId = 'automation-doctor-fleet-shutdown'
        $cleanupAutomationId = 'automation-doctor-cleanup-target'
        $null = New-Item -ItemType Directory -Path $simulationAutomationRoot, $simulationFleetStateRoot -Force
        Write-WatchDoctorAutomationMetadata -Root $simulationAutomationRoot -Id $targetAutomationId -TargetThreadId 'doctor-source' -Prompt $targetDoctorPrompt -Status ACTIVE
        Write-WatchDoctorAutomationMetadata -Root $simulationAutomationRoot -Id $shutdownTargetAutomationId -TargetThreadId 'doctor-shutdown-target' -Prompt $shutdownTargetDoctorPrompt -Status ACTIVE
        Write-WatchDoctorAutomationMetadata -Root $simulationAutomationRoot -Id $fleetAutomationId -TargetThreadId 'doctor-fleet' -Prompt $fleetDoctorPrompt -Status ACTIVE
        Write-WatchDoctorAutomationMetadata -Root $simulationAutomationRoot -Id $fleetShutdownAutomationId -TargetThreadId 'doctor-fleet-shutdown' -Prompt $fleetShutdownDoctorPrompt -Status ACTIVE
        Write-WatchDoctorAutomationMetadata -Root $simulationAutomationRoot -Id $cleanupAutomationId -TargetThreadId 'doctor-cleanup-target' -Prompt (& $SourceTargetPromptGeneratorPath -TargetThreadId 'doctor-cleanup-target' -ShutdownManaged) -Status PAUSED
        [ordered]@{
            schema_version = 4
            automation_id = $fleetShutdownAutomationId
            watch_runtime_generation_id = $runtimeGenerationId
            candidate = [ordered]@{
                final_recheck_completed = $true
                expires_at_utc = [datetimeoffset]::UtcNow.AddMinutes(5).ToString('o')
                supervisor_deleted = $true
                supervisor_delete_receipt_key = 'watch-supervisor-delete:' + ('a' * 64)
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $simulationFleetStateRoot ($fleetShutdownAutomationId + '.json'))

        [ordered]@{ timestamp = '2026-08-05T00:00:00Z'; type = 'response_item'; payload = [ordered]@{ type = 'message'; role = 'user'; content = @([ordered]@{ type = 'input_text'; text = "<heartbeat>`n<automation_id>$targetAutomationId</automation_id>`n<instructions>`n$targetDoctorPrompt`n</instructions>`n</heartbeat>" }); internal_chat_message_metadata_passthrough = [ordered]@{ turn_id = 'doctor-turn' } } } | ConvertTo-Json -Depth 10 -Compress | Set-Content -LiteralPath $targetTranscript -NoNewline
        [ordered]@{ timestamp = '2026-08-05T00:00:00Z'; type = 'response_item'; payload = [ordered]@{ type = 'message'; role = 'user'; content = @([ordered]@{ type = 'input_text'; text = "<heartbeat>`n<automation_id>$shutdownTargetAutomationId</automation_id>`n<instructions>`n$shutdownTargetDoctorPrompt`n</instructions>`n</heartbeat>" }); internal_chat_message_metadata_passthrough = [ordered]@{ turn_id = 'doctor-turn' } } } | ConvertTo-Json -Depth 10 -Compress | Set-Content -LiteralPath $shutdownTargetTranscript -NoNewline
        [ordered]@{ timestamp = '2026-08-05T00:00:00Z'; type = 'response_item'; payload = [ordered]@{ type = 'message'; role = 'user'; content = @([ordered]@{ type = 'input_text'; text = "<heartbeat>`n<automation_id>$fleetAutomationId</automation_id>`n<instructions>`n$fleetDoctorPrompt`n</instructions>`n</heartbeat>" }); internal_chat_message_metadata_passthrough = [ordered]@{ turn_id = 'doctor-turn' } } } | ConvertTo-Json -Depth 10 -Compress | Set-Content -LiteralPath $fleetTranscript -NoNewline
        [ordered]@{ timestamp = '2026-08-05T00:00:00Z'; type = 'response_item'; payload = [ordered]@{ type = 'message'; role = 'user'; content = @([ordered]@{ type = 'input_text'; text = "<heartbeat>`n<automation_id>$fleetShutdownAutomationId</automation_id>`n<instructions>`n$fleetShutdownDoctorPrompt`n</instructions>`n</heartbeat>" }); internal_chat_message_metadata_passthrough = [ordered]@{ turn_id = 'doctor-turn' } } } | ConvertTo-Json -Depth 10 -Compress | Set-Content -LiteralPath $fleetShutdownTranscript -NoNewline
        [ordered]@{ timestamp = '2026-08-05T00:00:00Z'; type = 'response_item'; payload = [ordered]@{ type = 'message'; role = 'user'; content = @([ordered]@{ type = 'input_text'; text = '关闭当前任务守夜。' }); internal_chat_message_metadata_passthrough = [ordered]@{ turn_id = 'doctor-turn' } } } | ConvertTo-Json -Depth 10 -Compress | Set-Content -LiteralPath $ordinaryTranscript -NoNewline

    $probes = [ordered]@{
        direct_send_tool = [ordered]@{
            tool_name = 'codex_app__send_message_to_thread'
            tool_input = [ordered]@{ threadId = 'doctor-target'; prompt = 'blocked probe' }
        }
        direct_handoff_without_prompt = [ordered]@{
            tool_name = 'codex_app__handoff_thread'
            tool_input = [ordered]@{ threadId = 'doctor-target' }
        }
        multiline_shell_send = [ordered]@{
            tool_name = 'shell_command'
            tool_input = [ordered]@{
                command = "Write-Output harmless`ncodex app-server request thread/send --thread doctor-target --prompt blocked"
            }
        }
        nested_shell_send = [ordered]@{
            tool_name = 'shell_command'
            tool_input = [ordered]@{
                command = 'cmd /c codex app-server request thread/send --thread doctor-target --prompt blocked'
            }
        }
        code_mode_shell_send = [ordered]@{
            tool_name = 'exec'
            tool_input = 'const result = await tools.shell_command({ command: "codex app-server request thread/send --thread doctor-target --prompt blocked" }); text(result);'
        }
        read_only_filename_inspection = [ordered]@{
            tool_name = 'shell_command'
            tool_input = [ordered]@{
                command = '$f = Get-ChildItem scripts/hooks -Filter ''block*.ps1'' | Select-Object -First 1; (Get-Content -LiteralPath $f.FullName).Count; Get-FileHash -LiteralPath $f.FullName'
            }
            expect = 'allow'
        }
        git_diff_hook_inspection = [ordered]@{
            tool_name = 'shell_command'
            tool_input = [ordered]@{ command = 'git diff -- scripts/hooks/block-cross-thread-send.ps1' }
            expect = 'allow'
        }
        read_only_subexpression_send = [ordered]@{
            tool_name = 'shell_command'
            tool_input = [ordered]@{
                command = 'rg "$(codex app-server request thread/send --thread doctor-target --prompt blocked)" docs'
            }
        }
        reader_exec_option_send = [ordered]@{
            tool_name = 'shell_command'
            tool_input = [ordered]@{
                command = 'rg --pre "codex app-server request thread/send --thread doctor-target --prompt blocked" thread/send docs'
            }
        }
        target_self_delete = [ordered]@{
            session_id = 'doctor-source'
            transcript_path = $targetTranscript
            tool_name = 'codex_app__automation_update'
            tool_input = [ordered]@{ mode = 'delete'; id = $targetAutomationId }
            expect = 'deny'
        }
        shutdown_target_self_pause = [ordered]@{
            session_id = 'doctor-shutdown-target'
            transcript_path = $shutdownTargetTranscript
            tool_name = 'codex_app__automation_update'
            tool_input = [ordered]@{ mode = 'update'; id = $shutdownTargetAutomationId; kind = 'heartbeat'; name = "Watch doctor $shutdownTargetAutomationId"; prompt = $shutdownTargetDoctorPrompt; rrule = 'FREQ=MINUTELY;INTERVAL=12'; status = 'PAUSED'; notificationPolicy = 'failed_runs_only'; targetThreadId = 'doctor-shutdown-target' }
            expect = 'allow'
        }
        code_mode_target_self_delete = [ordered]@{
            session_id = 'doctor-source'
            transcript_path = $targetTranscript
            tool_name = 'exec'
            tool_input = "const result = await tools.codex_app__automation_update({ mode: `"delete`", id: `"$targetAutomationId`" }); text(result);"
            expect = 'deny'
        }
        fleet_self_delete = [ordered]@{
            session_id = 'doctor-fleet'
            transcript_path = $fleetTranscript
            tool_name = 'codex_app__automation_update'
            tool_input = [ordered]@{ mode = 'delete'; id = $fleetAutomationId }
            expect = 'deny'
        }
        fleet_cleanup_delete = [ordered]@{
            session_id = 'doctor-fleet-shutdown'
            transcript_path = $fleetShutdownTranscript
            tool_name = 'codex_app__automation_update'
            tool_input = [ordered]@{ mode = 'delete'; id = $cleanupAutomationId }
            expect = 'allow'
        }
        fleet_target_pause = [ordered]@{
            session_id = 'doctor-fleet'
            transcript_path = $fleetTranscript
            tool_name = 'codex_app__automation_update'
            tool_input = [ordered]@{ mode = 'update'; id = $targetAutomationId; targetThreadId = 'doctor-source'; status = 'PAUSED'; prompt = $targetDoctorPrompt }
            expect = 'deny'
        }
        automation_live_probe_sentinel = [ordered]@{
            session_id = 'doctor-source'
            transcript_path = $targetTranscript
            tool_name = 'codex_app__automation_update'
            tool_input = [ordered]@{ mode = 'delete'; id = 'watch-interrupted-task-v1-live-probe-doctor' }
            expect = 'deny'
        }
        code_mode_automation_live_probe_sentinel = [ordered]@{
            session_id = 'doctor-source'
            transcript_path = $targetTranscript
            tool_name = 'exec'
            tool_input = 'const result = await tools.codex_app__automation_update({ mode: "delete", id: "watch-interrupted-task-v1-live-probe-code-mode-doctor" }); text(result);'
            expect = 'deny'
        }
        code_mode_dynamic_automation_route = [ordered]@{
            tool_name = 'exec'
            tool_input = 'const t = tools; const n = "codex_app__automation_" + "update"; const mutate = t[n]; await mutate({ mode: "delete", id: "watch-interrupted-task-v1-target-thread-id-doctor-source" });'
            expect = 'deny'
        }
        direct_user_lifecycle_allowed = [ordered]@{
            session_id = 'doctor-source'
            transcript_path = $ordinaryTranscript
            tool_name = 'codex_app__automation_update'
            tool_input = [ordered]@{ mode = 'delete'; id = $targetAutomationId }
            expect = 'allow'
        }
        standard_fleet_shutdown_blocked = [ordered]@{
            session_id = 'doctor-fleet'
            transcript_path = $fleetTranscript
            tool_name = 'shell_command'
            tool_input = [ordered]@{ command = 'shutdown.exe /s /t 120 /c "watch-interrupted-task: all monitored tasks stopped"' }
            expect = 'deny'
        }
        armed_fleet_shutdown_allowed = [ordered]@{
            session_id = 'doctor-fleet-shutdown'
            transcript_path = $fleetShutdownTranscript
            tool_name = 'shell_command'
            tool_input = [ordered]@{ command = 'shutdown.exe /s /t 120 /c "watch-interrupted-task: all monitored tasks stopped"' }
            expect = 'allow'
        }
    }

    foreach ($probe in $probes.GetEnumerator()) {
        $payload = [ordered]@{
            session_id = if ($probe.Value.session_id) { $probe.Value.session_id } else { 'doctor-source' }
            turn_id = 'doctor-turn'
            transcript_path = $probe.Value.transcript_path
            hook_event_name = 'PreToolUse'
            tool_name = $probe.Value.tool_name
            tool_use_id = "doctor-$($probe.Key)"
            tool_input = $probe.Value.tool_input
        } | ConvertTo-Json -Depth 8 -Compress
        $output = $payload | & pwsh -NoProfile -ExecutionPolicy Bypass -File $hostHook `
            -ExpectedScriptSha256 $hostHash `
            -ExpectedPolicySha256 $policyHostHash `
            -ExpectedTargetPromptSha256 $targetPromptHash `
            -ExpectedShutdownTargetPromptSha256 $shutdownTargetPromptHash `
            -ExpectedFleetPromptSha256 $fleetPromptHash `
            -ExpectedFleetShutdownPromptSha256 $fleetShutdownPromptHash `
            -ExpectedRuntimeGenerationId $runtimeGenerationId `
            -AutomationRoot $simulationAutomationRoot `
            -WatchFleetStateRoot $simulationFleetStateRoot 2>&1
        $expected = if ($probe.Value.expect) { [string]$probe.Value.expect } else { 'deny' }
        if ($LASTEXITCODE -eq 0 -and $expected -ceq 'allow' -and -not $output) {
            $simulationCases[$probe.Key] = $true
        }
        elseif ($LASTEXITCODE -eq 0 -and $output) {
            try {
                $decision = (@($output) -join "`n") | ConvertFrom-Json
                $simulationCases[$probe.Key] = [string]$decision.hookSpecificOutput.permissionDecision -eq 'deny'
            }
            catch {
                $simulationCases[$probe.Key] = $false
            }
        }
        if (-not $simulationCases[$probe.Key]) {
            $simulationFailures[$probe.Key] = if ($LASTEXITCODE -ne 0) { "exit_code=$LASTEXITCODE;output=$(@($output) -join '`n')" } elseif ([string]::IsNullOrWhiteSpace([string]$output)) { 'unexpected_allow_or_empty' } else { (@($output) -join "`n") }
        }
    }
    }
    finally {
        Remove-Item -LiteralPath $targetTranscript, $shutdownTargetTranscript, $fleetTranscript, $fleetShutdownTranscript, $ordinaryTranscript -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $simulationRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
$simulationPassed = @($simulationCases.Values | Where-Object { -not $_ }).Count -eq 0

$staticConfigurationReady = $featuresEnabled -and $hashMatches -and $definitionMatches -and $simulationPassed

[pscustomobject]@{
    configuration_ready = $false
    watch_runtime_generation_id = $runtimeGenerationId
    static_configuration_ready = $staticConfigurationReady
    feature_enabled = $featuresEnabled
    source_sha256 = $sourceHash
    host_sha256 = $hostHash
    policy_source_sha256 = $policySourceHash
    policy_host_sha256 = $policyHostHash
    automation_root = $installedAutomationRoot
    watch_fleet_state_root = $installedFleetStateRoot
    hash_matches = $hashMatches
    definition_matches = $definitionMatches
    target_prompt_sha256 = $targetPromptHash
    shutdown_target_prompt_sha256 = $shutdownTargetPromptHash
    fleet_prompt_sha256 = $fleetPromptHash
    fleet_shutdown_prompt_sha256 = $fleetShutdownPromptHash
    current_target_prompt_sha256 = $currentTargetPromptHash
    current_shutdown_target_prompt_sha256 = $currentShutdownTargetPromptHash
    current_fleet_prompt_sha256 = $currentFleetPromptHash
    current_fleet_shutdown_prompt_sha256 = $currentFleetShutdownPromptHash
    prompt_digests_match = ($targetPromptHash -ceq $currentTargetPromptHash -and $shutdownTargetPromptHash -ceq $currentShutdownTargetPromptHash -and $fleetPromptHash -ceq $currentFleetPromptHash -and $fleetShutdownPromptHash -ceq $currentFleetShutdownPromptHash)
    simulation_passed = $simulationPassed
    simulation_cases = [pscustomobject]$simulationCases
    simulation_failures = [pscustomobject]$simulationFailures
    trust_status = 'unverified_requires_slash_hooks'
    live_path_status = 'unverified_requires_fresh_session_probe'
    specialized_path_boundary = 'guardrail_only'
    overall = 'soft_guard_only'
}
