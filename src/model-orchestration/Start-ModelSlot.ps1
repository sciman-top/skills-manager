#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Preset = 'gpt6_astra_only',
    [string[]]$AvailablePreset = @(),
    [Parameter(Mandatory)][ValidateSet('quick_triage','routine_maintenance','standard_review','bounded_implementation','deep_investigation_or_implementation')][string]$Slot,
    [string]$WorkingDirectory = (Get-Location).Path,
    [string]$Prompt = '',
    [switch]$Plan,
    [switch]$Ephemeral
)
$ErrorActionPreference = 'Stop'
$policy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'presets.json') -Raw | ConvertFrom-Json -AsHashtable
$resolved = & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve -Preset $Preset -AvailablePreset $AvailablePreset | ConvertFrom-Json -AsHashtable
$Preset = $resolved.preset
$route = $resolved.routes[$Slot]
$targetHost = $policy.presets[$Preset].host
$WorkingDirectory = (Resolve-Path -LiteralPath $WorkingDirectory).Path
if ($targetHost -eq 'zcode') { throw 'ZCode native launch interface is not verified.' }
if ($targetHost -eq 'codex') {
    $cliArgs = @('exec','--profile',$Preset.Replace('_','-'),'--strict-config','--json','--skip-git-repo-check','-C',$WorkingDirectory,
        '-c',('model="'+$route.model+'"'),'-c',('review_model="'+$route.model+'"'),
        '-c',('model_reasoning_effort="'+$route.effort+'"'),'-c','agents.enabled=false','--disable','multi_agent')
    if ($Ephemeral) { $cliArgs += '--ephemeral' }
    if ($Slot -in @('quick_triage','standard_review')) { $cliArgs += @('--sandbox','read-only') }
    $executable = 'codex'
}
else {
    $cliArgs = @('--print','--output-format','json','--model',$route.model,'--effort',$route.effort,'--disallowedTools','Agent')
    if ($Ephemeral) { $cliArgs += '--no-session-persistence' }
    if ($Slot -in @('quick_triage','standard_review')) { $cliArgs += @('--tools','Read,Glob,Grep') }
    $executable = (Get-Command claude -CommandType Application).Source
}
if ($Plan) {
    @{preset=$Preset;slot=$Slot;model=$route.model;effort=$route.effort;host=$targetHost;delegation_enabled=$false;working_directory=$WorkingDirectory} | ConvertTo-Json
    return
}
if ([string]::IsNullOrWhiteSpace($Prompt)) { throw 'Prompt is required to execute a slot.' }
# No arbitrary CLI pass-through: the caller cannot override the frozen route or re-enable delegation.
$scopedPrompt = "Execution slot: $Slot. Use only this session's configured model/effort. Do not delegate, start another AI process, change provider/model settings, or replay this task under another preset. "
if ($Slot -in @('quick_triage','standard_review')) { $scopedPrompt += 'This is read-only work; do not modify files or external state. ' }
$scopedPrompt += "`n`n"+$Prompt
Push-Location -LiteralPath $WorkingDirectory
try {
    & $executable @cliArgs $scopedPrompt
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "Slot process failed (exit=$code); no replay or preset substitution performed." }
}
finally { Pop-Location }
