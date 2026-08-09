[CmdletBinding()]
param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }),
    [string]$SourceHookPath = (Join-Path $PSScriptRoot 'block-cross-thread-send.ps1'),
    [string]$SourcePolicyPath = (Join-Path $PSScriptRoot 'CrossThreadGuardPolicy.ps1'),
    [Parameter(DontShow = $true)][switch]$InjectFinalHooksMoveFailure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedSource = (Resolve-Path -LiteralPath $SourceHookPath).Path
$resolvedPolicy = (Resolve-Path -LiteralPath $SourcePolicyPath).Path
$resolvedCodexHome = [System.IO.Path]::GetFullPath($CodexHome)
$hostScripts = Join-Path $resolvedCodexHome 'scripts'
$hostHook = Join-Path $hostScripts 'block-cross-thread-send.ps1'
$hostPolicy = Join-Path $hostScripts 'CrossThreadGuardPolicy.ps1'
$hooksPath = Join-Path $resolvedCodexHome 'hooks.json'
$legacyDoctor = Join-Path $hostScripts 'Test-WatchGuardRuntime.ps1'

$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedSource).Hash.ToLowerInvariant()
$policyHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedPolicy).Hash.ToLowerInvariant()

# Validate the existing hooks document before touching any host file.
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
        $retainedHandlers = @(
        foreach ($handler in @($group.hooks)) {
            $handlerCommand = [string]$handler.command
            if ([string]$group.matcher -ceq '*' -and [string]$handler.type -ceq 'command' -and
                $handlerCommand -like "*$hostHook*" -and $handlerCommand -match '(?i)-ExpectedScriptSha256\b') {
                    continue
                }
                $handler
            }
        )
        if ($retainedHandlers.Count -gt 0) {
            $group.hooks = @($retainedHandlers)
            $group
        }
    }
)

$command = 'pwsh -NoProfile -ExecutionPolicy Bypass -File "{0}" -ExpectedScriptSha256 "{1}" -ExpectedPolicySha256 "{2}"' -f $hostHook, $sourceHash, $policyHash
$guardGroup = [pscustomobject]@{
    matcher = '*'
    hooks = @([pscustomobject]@{
        type = 'command'
        command = $command
        commandWindows = $command
        timeout = 10
        statusMessage = 'Blocking cross-task injection and retired watch lifecycle mutations'
    })
}
$document.hooks.PreToolUse = @($retained) + @($guardGroup)
$newHooksJson = $document | ConvertTo-Json -Depth 50

$null = New-Item -ItemType Directory -Path $hostScripts -Force
$nonce = [guid]::NewGuid().ToString('N')
$stagedHook = Join-Path $hostScripts "block-cross-thread-send.$nonce.tmp"
$stagedPolicy = Join-Path $hostScripts "CrossThreadGuardPolicy.$nonce.tmp"
$stagedHooksJson = "$hooksPath.$nonce.tmp"

$hostHookExisted = Test-Path -LiteralPath $hostHook -PathType Leaf
$hostPolicyExisted = Test-Path -LiteralPath $hostPolicy -PathType Leaf
$legacyDoctorExisted = Test-Path -LiteralPath $legacyDoctor -PathType Leaf
$originalHostHookBytes = if ($hostHookExisted) { [System.IO.File]::ReadAllBytes($hostHook) } else { $null }
$originalHostPolicyBytes = if ($hostPolicyExisted) { [System.IO.File]::ReadAllBytes($hostPolicy) } else { $null }
$originalLegacyDoctorBytes = if ($legacyDoctorExisted) { [System.IO.File]::ReadAllBytes($legacyDoctor) } else { $null }
$removeLegacyDoctor = $false

try {
    Copy-Item -LiteralPath $resolvedSource -Destination $stagedHook
    Copy-Item -LiteralPath $resolvedPolicy -Destination $stagedPolicy
    [System.IO.File]::WriteAllText($stagedHooksJson, $newHooksJson, [System.Text.UTF8Encoding]::new($false))

    Move-Item -LiteralPath $stagedHook -Destination $hostHook -Force
    Move-Item -LiteralPath $stagedPolicy -Destination $hostPolicy -Force
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
        if ($legacyDoctorExisted) { [System.IO.File]::WriteAllBytes($legacyDoctor, $originalLegacyDoctorBytes) }
        elseif (Test-Path -LiteralPath $legacyDoctor) { Remove-Item -LiteralPath $legacyDoctor -Force }
    }
    catch { $rollbackErrors.Add(('legacy_doctor: {0}' -f $_.Exception.Message)) | Out-Null }
    try {
        if ($hooksExisted) { [System.IO.File]::WriteAllBytes($hooksPath, $originalHooksBytes) }
        elseif (Test-Path -LiteralPath $hooksPath) { Remove-Item -LiteralPath $hooksPath -Force }
    }
    catch { $rollbackErrors.Add(('hooks_json: {0}' -f $_.Exception.Message)) | Out-Null }
    if ($rollbackErrors.Count -gt 0) { throw ('Cross-thread guard installation failed ({0}); rollback was partial: {1}' -f $installError.Exception.Message, ($rollbackErrors -join '; ')) }
    throw $installError
}
finally {
    Remove-Item -LiteralPath $stagedHook, $stagedPolicy, $stagedHooksJson -Force -ErrorAction SilentlyContinue
}

[pscustomobject]@{
    status = 'installed_untrusted'
    policy_revision = 5
    watch_runtime_status = 'retired_fail_closed'
    hooks_path = $hooksPath
    host_hook_path = $hostHook
    host_policy_path = $hostPolicy
    source_sha256 = $sourceHash
    host_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $hostHook).Hash.ToLowerInvariant()
    policy_source_sha256 = $policyHash
    policy_host_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $hostPolicy).Hash.ToLowerInvariant()
    legacy_doctor_removed = $removeLegacyDoctor
    legacy_doctor_cleanup_status = if ($legacyDoctorExisted) { 'manual_review_required' } else { 'not_present' }
    trust_next_step = 'Open /hooks in a fresh Codex session and trust the exact current definition hash.'
}
