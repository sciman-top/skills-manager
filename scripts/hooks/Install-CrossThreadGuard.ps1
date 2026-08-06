[CmdletBinding()]
param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }),
    [string]$SourceHookPath = (Join-Path $PSScriptRoot 'block-cross-thread-send.ps1'),
    [string]$SourcePolicyPath = (Join-Path $PSScriptRoot 'CrossThreadGuardPolicy.ps1'),
    [string]$RuntimeDoctorPath = (Join-Path $PSScriptRoot 'Test-WatchGuardRuntime.ps1'),
    [string]$TargetPromptGeneratorPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'overrides\custom\watch-interrupted-task\scripts\New-WatchHeartbeatPrompt.ps1'),
    [string]$FleetPromptGeneratorPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'overrides\custom\watch-interrupted-task\scripts\New-WatchFleetSupervisorPrompt.ps1'),
    [string]$AutomationRoot = '',
    [string]$WatchFleetStateRoot = '',
    [Parameter(DontShow = $true)][switch]$InjectFinalHooksMoveFailure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedSource = (Resolve-Path -LiteralPath $SourceHookPath).Path
$resolvedPolicy = (Resolve-Path -LiteralPath $SourcePolicyPath).Path
$resolvedRuntimeDoctor = (Resolve-Path -LiteralPath $RuntimeDoctorPath).Path
$resolvedTargetGenerator = (Resolve-Path -LiteralPath $TargetPromptGeneratorPath).Path
$resolvedFleetGenerator = (Resolve-Path -LiteralPath $FleetPromptGeneratorPath).Path
$resolvedCodexHome = [System.IO.Path]::GetFullPath($CodexHome)
$hostScripts = Join-Path $resolvedCodexHome 'scripts'
$hostHook = Join-Path $hostScripts 'block-cross-thread-send.ps1'
$hostPolicy = Join-Path $hostScripts 'CrossThreadGuardPolicy.ps1'
$hostRuntimeDoctor = Join-Path $hostScripts 'Test-WatchGuardRuntime.ps1'
$hooksPath = Join-Path $resolvedCodexHome 'hooks.json'
$resolvedAutomationRoot = if ([string]::IsNullOrWhiteSpace($AutomationRoot)) { Join-Path $resolvedCodexHome 'automations' } else { [System.IO.Path]::GetFullPath($AutomationRoot) }
$resolvedFleetStateRoot = if ([string]::IsNullOrWhiteSpace($WatchFleetStateRoot)) { Join-Path $resolvedCodexHome 'watch-interrupted-task\fleet' } else { [System.IO.Path]::GetFullPath($WatchFleetStateRoot) }

# Validate every source and the existing document before touching host scripts.
$targetPromptData = ((& $resolvedTargetGenerator -TargetThreadId 'canonical-digest-probe' -AsJson) | ConvertFrom-Json -ErrorAction Stop)
$shutdownTargetPromptData = ((& $resolvedTargetGenerator -TargetThreadId 'canonical-digest-probe' -ShutdownManaged -AsJson) | ConvertFrom-Json -ErrorAction Stop)
$fleetPromptData = ((& $resolvedFleetGenerator -SupervisorThreadId 'canonical-digest-probe' -AsJson) | ConvertFrom-Json -ErrorAction Stop)
$fleetShutdownPromptData = ((& $resolvedFleetGenerator -SupervisorThreadId 'canonical-digest-probe' -ShutdownWhenAllStopped -AsJson) | ConvertFrom-Json -ErrorAction Stop)
$targetPromptHash = [string]$targetPromptData.prompt_sha256
$runtimeGenerationId = [string]$targetPromptData.watch_runtime_generation_id
$shutdownTargetPromptHash = [string]$shutdownTargetPromptData.prompt_sha256
$fleetPromptHash = [string]$fleetPromptData.prompt_sha256
$fleetShutdownPromptHash = [string]$fleetShutdownPromptData.prompt_sha256
if ($targetPromptData.policy_revision -ne 3 -or $shutdownTargetPromptData.policy_revision -ne 3 -or $fleetPromptData.policy_revision -ne 3 -or $fleetShutdownPromptData.policy_revision -ne 3 -or
    $runtimeGenerationId -notmatch '^watch-runtime-generation:[0-9a-f]{64}$' -or $shutdownTargetPromptData.watch_runtime_generation_id -cne $runtimeGenerationId -or $fleetPromptData.watch_runtime_generation_id -cne $runtimeGenerationId -or $fleetShutdownPromptData.watch_runtime_generation_id -cne $runtimeGenerationId -or
    $targetPromptHash -notmatch '^[0-9a-f]{64}$' -or $shutdownTargetPromptHash -notmatch '^[0-9a-f]{64}$' -or $fleetPromptHash -notmatch '^[0-9a-f]{64}$' -or $fleetShutdownPromptHash -notmatch '^[0-9a-f]{64}$' -or
    $shutdownTargetPromptHash -ceq $targetPromptHash -or $fleetShutdownPromptHash -ceq $fleetPromptHash) {
    throw 'Revision-3 canonical watch prompt provenance could not be derived.'
}

$hooksExisted = Test-Path -LiteralPath $hooksPath -PathType Leaf
$originalHooksBytes = if ($hooksExisted) { [System.IO.File]::ReadAllBytes($hooksPath) } else { $null }
if ($hooksExisted) {
    $document = ([System.Text.UTF8Encoding]::new($false).GetString($originalHooksBytes)) | ConvertFrom-Json -Depth 50 -ErrorAction Stop
}
else {
    $document = [pscustomobject]@{
        description = 'User-level Codex lifecycle hooks.'
        hooks = [pscustomobject]@{}
    }
}

if ($null -eq $document.PSObject.Properties['hooks']) {
    $document | Add-Member -MemberType NoteProperty -Name hooks -Value ([pscustomobject]@{})
}
if ($null -eq $document.hooks.PSObject.Properties['PreToolUse']) {
    $document.hooks | Add-Member -MemberType NoteProperty -Name PreToolUse -Value @()
}

$retained = @(
    foreach ($group in @($document.hooks.PreToolUse)) {
        $managed = $false
        foreach ($handler in @($group.hooks)) {
            $handlerCommand = [string]$handler.command
            if ([string]$group.matcher -ceq '*' -and [string]$handler.type -ceq 'command' -and
                $handlerCommand -like "*$hostHook*" -and $handlerCommand -match '(?i)-ExpectedScriptSha256\b') {
                $managed = $true
                break
            }
        }
        if (-not $managed) { $group }
    }
)

$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedSource).Hash.ToLowerInvariant()
$policyHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedPolicy).Hash.ToLowerInvariant()
$command = 'pwsh -NoProfile -ExecutionPolicy Bypass -File "{0}" -ExpectedScriptSha256 "{1}" -ExpectedPolicySha256 "{2}" -ExpectedTargetPromptSha256 "{3}" -ExpectedShutdownTargetPromptSha256 "{4}" -ExpectedFleetPromptSha256 "{5}" -ExpectedFleetShutdownPromptSha256 "{6}" -ExpectedRuntimeGenerationId "{7}" -AutomationRoot "{8}" -WatchFleetStateRoot "{9}"' -f $hostHook, $sourceHash, $policyHash, $targetPromptHash, $shutdownTargetPromptHash, $fleetPromptHash, $fleetShutdownPromptHash, $runtimeGenerationId, $resolvedAutomationRoot, $resolvedFleetStateRoot
$guardGroup = [pscustomobject]@{
    matcher = '*'
    hooks = @([pscustomobject]@{
        type = 'command'
        command = $command
        commandWindows = $command
        timeout = 10
        statusMessage = 'Blocking cross-task injection and enforcing canonical watch recovery metadata'
    })
}
$document.hooks.PreToolUse = @($retained) + @($guardGroup)
$newHooksJson = $document | ConvertTo-Json -Depth 50

$null = New-Item -ItemType Directory -Path $hostScripts -Force
$nonce = [guid]::NewGuid().ToString('N')
$stagedHook = Join-Path $hostScripts "block-cross-thread-send.$nonce.tmp"
$stagedPolicy = Join-Path $hostScripts "CrossThreadGuardPolicy.$nonce.tmp"
$stagedDoctor = Join-Path $hostScripts "Test-WatchGuardRuntime.$nonce.tmp"
$stagedHooksJson = "$hooksPath.$nonce.tmp"

$hostHookExisted = Test-Path -LiteralPath $hostHook -PathType Leaf
$hostPolicyExisted = Test-Path -LiteralPath $hostPolicy -PathType Leaf
$hostDoctorExisted = Test-Path -LiteralPath $hostRuntimeDoctor -PathType Leaf
$originalHostHookBytes = if ($hostHookExisted) { [System.IO.File]::ReadAllBytes($hostHook) } else { $null }
$originalHostPolicyBytes = if ($hostPolicyExisted) { [System.IO.File]::ReadAllBytes($hostPolicy) } else { $null }
$originalHostDoctorBytes = if ($hostDoctorExisted) { [System.IO.File]::ReadAllBytes($hostRuntimeDoctor) } else { $null }

try {
    Copy-Item -LiteralPath $resolvedSource -Destination $stagedHook
    Copy-Item -LiteralPath $resolvedPolicy -Destination $stagedPolicy
    Copy-Item -LiteralPath $resolvedRuntimeDoctor -Destination $stagedDoctor
    [System.IO.File]::WriteAllText($stagedHooksJson, $newHooksJson, [System.Text.UTF8Encoding]::new($false))

    Move-Item -LiteralPath $stagedHook -Destination $hostHook -Force
    Move-Item -LiteralPath $stagedPolicy -Destination $hostPolicy -Force
    Move-Item -LiteralPath $stagedDoctor -Destination $hostRuntimeDoctor -Force
    if ($InjectFinalHooksMoveFailure) { throw 'injected final hooks move failure' }
    Move-Item -LiteralPath $stagedHooksJson -Destination $hooksPath -Force
}
catch {
    $installError = $_
    $rollbackErrors = New-Object System.Collections.Generic.List[string]
    try {
        if ($hostHookExisted) { [System.IO.File]::WriteAllBytes($hostHook, $originalHostHookBytes) }
        elseif (Test-Path -LiteralPath $hostHook) { Remove-Item -LiteralPath $hostHook -Force }
    }
    catch { $rollbackErrors.Add(('host_hook: {0}' -f $_.Exception.Message)) | Out-Null }
    try {
        if ($hostPolicyExisted) { [System.IO.File]::WriteAllBytes($hostPolicy, $originalHostPolicyBytes) }
        elseif (Test-Path -LiteralPath $hostPolicy) { Remove-Item -LiteralPath $hostPolicy -Force }
    }
    catch { $rollbackErrors.Add(('host_policy: {0}' -f $_.Exception.Message)) | Out-Null }
    try {
        if ($hostDoctorExisted) { [System.IO.File]::WriteAllBytes($hostRuntimeDoctor, $originalHostDoctorBytes) }
        elseif (Test-Path -LiteralPath $hostRuntimeDoctor) { Remove-Item -LiteralPath $hostRuntimeDoctor -Force }
    }
    catch { $rollbackErrors.Add(('runtime_doctor: {0}' -f $_.Exception.Message)) | Out-Null }
    try {
        if ($hooksExisted) { [System.IO.File]::WriteAllBytes($hooksPath, $originalHooksBytes) }
        elseif (Test-Path -LiteralPath $hooksPath) { Remove-Item -LiteralPath $hooksPath -Force }
    }
    catch { $rollbackErrors.Add(('hooks_json: {0}' -f $_.Exception.Message)) | Out-Null }
    if ($rollbackErrors.Count -gt 0) { throw ('Cross-thread guard installation failed ({0}); rollback was partial: {1}' -f $installError.Exception.Message, ($rollbackErrors -join '; ')) }
    throw $installError
}
finally {
    Remove-Item -LiteralPath $stagedHook, $stagedPolicy, $stagedDoctor, $stagedHooksJson -Force -ErrorAction SilentlyContinue
}

[pscustomobject]@{
    status = 'installed_untrusted'
    policy_revision = 3
    watch_runtime_generation_id = $runtimeGenerationId
    hooks_path = $hooksPath
    host_hook_path = $hostHook
    host_policy_path = $hostPolicy
    runtime_doctor_path = $hostRuntimeDoctor
    source_sha256 = $sourceHash
    host_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $hostHook).Hash.ToLowerInvariant()
    policy_source_sha256 = $policyHash
    policy_host_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $hostPolicy).Hash.ToLowerInvariant()
    automation_root = $resolvedAutomationRoot
    watch_fleet_state_root = $resolvedFleetStateRoot
    runtime_doctor_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $hostRuntimeDoctor).Hash.ToLowerInvariant()
    target_prompt_sha256 = $targetPromptHash
    shutdown_target_prompt_sha256 = $shutdownTargetPromptHash
    fleet_prompt_sha256 = $fleetPromptHash
    fleet_shutdown_prompt_sha256 = $fleetShutdownPromptHash
    trust_next_step = 'Open /hooks in a fresh Codex session and trust the exact current definition hash.'
}
