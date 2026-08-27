#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Enable','Disable')][string]$Action,
    [Parameter(Mandatory)][string]$Root,
    [ValidatePattern('^([01]\d|2[0-3]):[0-5]\d$')][string]$Time = '09:00',
    [switch]$AutoApply,
    [switch]$SyncMcp
)

$ErrorActionPreference = 'Stop'
$taskName = 'skills-manager-release-update'
$rootPath = [IO.Path]::GetFullPath($Root)
$entry = Join-Path $rootPath 'skills.ps1'
$runner = Join-Path $rootPath 'scripts\release\release-update-scheduled-runner.ps1'
if (-not (Test-Path -LiteralPath $entry -PathType Leaf) -or -not (Test-Path -LiteralPath $runner -PathType Leaf)) { throw 'Release update scheduler requires a complete Release installation.' }
if (-not (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) { throw 'Windows Task Scheduler cmdlets are unavailable on this host.' }

if ($Action -eq 'Disable') {
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($null -ne $existing) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
    [pscustomobject]@{ command = 'release-update-schedule'; action = 'disabled'; task = $taskName } | ConvertTo-Json -Compress | Write-Output
    exit 0
}

$pwsh = (Get-Command pwsh -ErrorAction Stop | Select-Object -First 1).Source
$arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $runner),'-Root',('"{0}"' -f $rootPath))
if ($AutoApply) { $arguments += '-AutoApply' }
if ($SyncMcp) { $arguments += '-SyncMcp' }
$taskAction = New-ScheduledTaskAction -Execute $pwsh -Argument ($arguments -join ' ')
$trigger = New-ScheduledTaskTrigger -Daily -At ([datetime]::ParseExact($Time, 'HH:mm', [Globalization.CultureInfo]::InvariantCulture))
$principal = New-ScheduledTaskPrincipal -UserId ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME) -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $trigger -Principal $principal -Description 'Checks skills-manager GitHub Releases and optionally applies a verified update.' -Force | Out-Null
[pscustomobject]@{ command = 'release-update-schedule'; action = 'enabled'; task = $taskName; time = $Time; auto_apply = [bool]$AutoApply; sync_mcp = [bool]$SyncMcp } | ConvertTo-Json -Compress | Write-Output
