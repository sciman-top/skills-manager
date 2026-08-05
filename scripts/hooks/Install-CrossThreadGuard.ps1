[CmdletBinding()]
param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }),
    [string]$SourceHookPath = (Join-Path $PSScriptRoot 'block-cross-thread-send.ps1'),
    [string]$RuntimeDoctorPath = (Join-Path $PSScriptRoot 'Test-WatchGuardRuntime.ps1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedSource = (Resolve-Path -LiteralPath $SourceHookPath).Path
$resolvedRuntimeDoctor = (Resolve-Path -LiteralPath $RuntimeDoctorPath).Path
$resolvedCodexHome = [System.IO.Path]::GetFullPath($CodexHome)
$hostScripts = Join-Path $resolvedCodexHome 'scripts'
$hostHook = Join-Path $hostScripts 'block-cross-thread-send.ps1'
$hostRuntimeDoctor = Join-Path $hostScripts 'Test-WatchGuardRuntime.ps1'
$hooksPath = Join-Path $resolvedCodexHome 'hooks.json'

$null = New-Item -ItemType Directory -Path $hostScripts -Force
Copy-Item -LiteralPath $resolvedSource -Destination $hostHook -Force
Copy-Item -LiteralPath $resolvedRuntimeDoctor -Destination $hostRuntimeDoctor -Force
$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedSource).Hash.ToLowerInvariant()

if (Test-Path -LiteralPath $hooksPath) {
    $document = Get-Content -Raw -LiteralPath $hooksPath | ConvertFrom-Json -Depth 50
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
    @($document.hooks.PreToolUse) | Where-Object {
        $serialized = $_ | ConvertTo-Json -Depth 20 -Compress
        $serialized -notmatch '(?i)block-cross-thread-send\.ps1|Blocking cross-task message injection|Blocking target heartbeat automation mutation'
    }
)

$command = 'pwsh -NoProfile -ExecutionPolicy Bypass -File "{0}" -ExpectedScriptSha256 "{1}"' -f $hostHook, $sourceHash
$guardGroup = [pscustomobject]@{
    matcher = '*'
    hooks = @(
        [pscustomobject]@{
            type = 'command'
            command = $command
            commandWindows = $command
            timeout = 10
            statusMessage = 'Blocking cross-task injection and target heartbeat automation mutation'
        }
    )
}
$document.hooks.PreToolUse = @($retained) + @($guardGroup)

$temporaryPath = "$hooksPath.tmp"
$document | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $temporaryPath -Encoding utf8
Move-Item -LiteralPath $temporaryPath -Destination $hooksPath -Force

[pscustomobject]@{
    status = 'installed_untrusted'
    hooks_path = $hooksPath
    host_hook_path = $hostHook
    runtime_doctor_path = $hostRuntimeDoctor
    source_sha256 = $sourceHash
    host_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $hostHook).Hash.ToLowerInvariant()
    runtime_doctor_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $hostRuntimeDoctor).Hash.ToLowerInvariant()
    trust_next_step = 'Open /hooks in a fresh Codex session and trust the exact current definition hash.'
}
