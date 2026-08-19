#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$TaskName = 'skills-manager-weekly-update-friday-2000',
    [ValidateSet('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')]
    [string]$DayOfWeek = 'Friday',
    [datetime]$At = '20:00'
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runnerPath = Join-Path $repoRoot 'scripts\weekly-skills-update.ps1'
if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) { throw "Weekly runner is missing: $runnerPath" }

$pwsh = (Get-Command pwsh -ErrorAction Stop | Select-Object -First 1).Source
$arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $runnerPath
$action = New-ScheduledTaskAction -Execute $pwsh -Argument $arguments -WorkingDirectory $repoRoot
$trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek $DayOfWeek -At $At
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2)
$description = 'Safely update skills sources and lock state. Does not mutate MCP or push Git commits.'
$taskDefinition = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Description $description

Register-ScheduledTask -TaskName $TaskName -InputObject $taskDefinition -Force | Out-Null

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
$taskAction = @($task.Actions)[0]
if ($taskAction.Execute -ne $pwsh -or $taskAction.Arguments -notlike "*$runnerPath*") {
    throw 'Scheduled task verification failed: action does not match the weekly runner.'
}

[pscustomobject][ordered]@{
    task_name = $TaskName
    state = [string]$task.State
    executable = $taskAction.Execute
    arguments = $taskAction.Arguments
    working_directory = $taskAction.WorkingDirectory
    runner_exists = (Test-Path -LiteralPath $runnerPath -PathType Leaf)
    mcp_mutations = 0
} | ConvertTo-Json
