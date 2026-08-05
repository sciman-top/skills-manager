[CmdletBinding()]
param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }),
    [string]$SourceHookPath = (Join-Path $PSScriptRoot 'block-cross-thread-send.ps1'),
    [string]$RuntimeDoctorPath = (Join-Path $PSScriptRoot 'Test-WatchGuardRuntime.ps1'),
    [string]$TargetPromptGeneratorPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'overrides\custom\watch-interrupted-task\scripts\New-WatchHeartbeatPrompt.ps1'),
    [string]$FleetPromptGeneratorPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'overrides\custom\watch-interrupted-task\scripts\New-WatchFleetSupervisorPrompt.ps1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedSource = (Resolve-Path -LiteralPath $SourceHookPath).Path
$resolvedRuntimeDoctor = (Resolve-Path -LiteralPath $RuntimeDoctorPath).Path
$resolvedTargetGenerator = (Resolve-Path -LiteralPath $TargetPromptGeneratorPath).Path
$resolvedFleetGenerator = (Resolve-Path -LiteralPath $FleetPromptGeneratorPath).Path
$resolvedCodexHome = [System.IO.Path]::GetFullPath($CodexHome)
$hostScripts = Join-Path $resolvedCodexHome 'scripts'
$hostHook = Join-Path $hostScripts 'block-cross-thread-send.ps1'
$hostRuntimeDoctor = Join-Path $hostScripts 'Test-WatchGuardRuntime.ps1'
$hooksPath = Join-Path $resolvedCodexHome 'hooks.json'

# Validate every source and the existing document before touching host scripts.
$targetPromptData = ((& $resolvedTargetGenerator -TargetThreadId 'canonical-digest-probe' -AsJson) | ConvertFrom-Json -ErrorAction Stop)
$fleetPromptData = ((& $resolvedFleetGenerator -SupervisorThreadId 'canonical-digest-probe' -AsJson) | ConvertFrom-Json -ErrorAction Stop)
$fleetShutdownPromptData = ((& $resolvedFleetGenerator -SupervisorThreadId 'canonical-digest-probe' -ShutdownWhenAllStopped -AsJson) | ConvertFrom-Json -ErrorAction Stop)
$targetPromptHash = [string]$targetPromptData.prompt_sha256
$fleetPromptHash = [string]$fleetPromptData.prompt_sha256
$fleetShutdownPromptHash = [string]$fleetShutdownPromptData.prompt_sha256
if ($targetPromptData.policy_revision -ne 3 -or $fleetPromptData.policy_revision -ne 3 -or $fleetShutdownPromptData.policy_revision -ne 3 -or
    $targetPromptHash -notmatch '^[0-9a-f]{64}$' -or $fleetPromptHash -notmatch '^[0-9a-f]{64}$' -or $fleetShutdownPromptHash -notmatch '^[0-9a-f]{64}$' -or
    $fleetShutdownPromptHash -ceq $fleetPromptHash) {
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
$command = 'pwsh -NoProfile -ExecutionPolicy Bypass -File "{0}" -ExpectedScriptSha256 "{1}" -ExpectedTargetPromptSha256 "{2}" -ExpectedFleetPromptSha256 "{3}" -ExpectedFleetShutdownPromptSha256 "{4}"' -f $hostHook, $sourceHash, $targetPromptHash, $fleetPromptHash, $fleetShutdownPromptHash
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
$stagedDoctor = Join-Path $hostScripts "Test-WatchGuardRuntime.$nonce.tmp"
$stagedHooksJson = "$hooksPath.$nonce.tmp"

$hostHookExisted = Test-Path -LiteralPath $hostHook -PathType Leaf
$hostDoctorExisted = Test-Path -LiteralPath $hostRuntimeDoctor -PathType Leaf
$originalHostHookBytes = if ($hostHookExisted) { [System.IO.File]::ReadAllBytes($hostHook) } else { $null }
$originalHostDoctorBytes = if ($hostDoctorExisted) { [System.IO.File]::ReadAllBytes($hostRuntimeDoctor) } else { $null }

try {
    Copy-Item -LiteralPath $resolvedSource -Destination $stagedHook
    Copy-Item -LiteralPath $resolvedRuntimeDoctor -Destination $stagedDoctor
    [System.IO.File]::WriteAllText($stagedHooksJson, $newHooksJson, [System.Text.UTF8Encoding]::new($false))

    Move-Item -LiteralPath $stagedHook -Destination $hostHook -Force
    Move-Item -LiteralPath $stagedDoctor -Destination $hostRuntimeDoctor -Force
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
    Remove-Item -LiteralPath $stagedHook, $stagedDoctor, $stagedHooksJson -Force -ErrorAction SilentlyContinue
}

[pscustomobject]@{
    status = 'installed_untrusted'
    policy_revision = 3
    hooks_path = $hooksPath
    host_hook_path = $hostHook
    runtime_doctor_path = $hostRuntimeDoctor
    source_sha256 = $sourceHash
    host_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $hostHook).Hash.ToLowerInvariant()
    runtime_doctor_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $hostRuntimeDoctor).Hash.ToLowerInvariant()
    target_prompt_sha256 = $targetPromptHash
    fleet_prompt_sha256 = $fleetPromptHash
    fleet_shutdown_prompt_sha256 = $fleetShutdownPromptHash
    trust_next_step = 'Open /hooks in a fresh Codex session and trust the exact current definition hash.'
}
