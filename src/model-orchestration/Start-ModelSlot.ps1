#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Preset = '',
    [string[]]$AvailablePreset = @(),
    [Parameter(Mandatory)][string]$Slot,
    [string]$Model = '',
    [string]$Effort = '',
    [switch]$ReadOnly,
    [string]$WorkingDirectory = (Get-Location).Path,
    [string]$Prompt = '',
    [switch]$Plan,
    [switch]$Ephemeral
)
$ErrorActionPreference = 'Stop'
$policy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'presets.json') -Raw | ConvertFrom-Json -AsHashtable
$resolved = & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve -Preset $Preset -AvailablePreset $AvailablePreset | ConvertFrom-Json -AsHashtable
$Preset = $resolved.preset
if ($Slot -cnotin @($resolved.slots)) { throw "Unknown configured slot: $Slot" }
$route = $resolved.routes[$Slot]
if ([string]::IsNullOrWhiteSpace($Model) -xor [string]::IsNullOrWhiteSpace($Effort)) { throw 'Model and Effort must be supplied together.' }
if (-not [string]::IsNullOrWhiteSpace($Model)) {
    $matchingRoutes = @($resolved.enabled_routes | Where-Object { $_.model -ceq $Model -and $_.effort -ceq $Effort })
    if ($matchingRoutes.Count -ne 1) { throw 'Exact model/effort tuple is outside the active pool.' }
    $route = $matchingRoutes[0]
    $Preset = $route.preset
}
$readOnlyTask = $ReadOnly -or $Slot -cin @($resolved.read_only_slots)
$presetHosts = @($policy.presets[$Preset].hosts)
# Launch on the first declared facet with a verified native interface, so the
# primary host wins (deepseek=claude) and zcode is always skipped as
# resolve-only; a zcode-only preset has no launchable facet at all.
$targetHost = $null
foreach ($h in $presetHosts) { if ($h -ceq 'codex' -or $h -ceq 'claude') { $targetHost = $h; break } }
if (-not $targetHost) { throw 'ZCode native launch interface is not verified.' }
$WorkingDirectory = (Resolve-Path -LiteralPath $WorkingDirectory).Path
if ($targetHost -eq 'codex') {
    $cliArgs = @('exec','--profile',$Preset.Replace('_','-'),'--strict-config','--json','--skip-git-repo-check','-C',$WorkingDirectory,
        '-c',('model="'+$route.model+'"'),'-c',('review_model="'+$route.model+'"'),
        '-c',('model_reasoning_effort="'+$route.effort+'"'),'-c','agents.enabled=false','--disable','multi_agent')
    if ($Ephemeral) { $cliArgs += '--ephemeral' }
    if ($readOnlyTask) { $cliArgs += @('--sandbox','read-only') }
    $executable = 'codex'
}
else {
    $cliArgs = @('--print','--output-format','json','--model',$route.model,'--effort',$route.effort,'--disallowedTools','Agent')
    if ($Ephemeral) { $cliArgs += '--no-session-persistence' }
    if ($readOnlyTask) { $cliArgs += @('--tools','Read,Glob,Grep') }
    $executable = 'claude'
}
if ($Plan) {
    @{preset=$Preset;active_presets=$resolved.active_presets;slot=$Slot;model=$route.model;effort=$route.effort;host=$targetHost;read_only=$readOnlyTask;delegation_enabled=$false;working_directory=$WorkingDirectory} | ConvertTo-Json
    return
}
if ([string]::IsNullOrWhiteSpace($Prompt)) { throw 'Prompt is required to execute a slot.' }
# No arbitrary CLI pass-through: the caller cannot override the frozen route or re-enable delegation.
$scopedPrompt = "Execution slot: $Slot. Use only this session's configured model/effort. Do not delegate, start another AI process, change provider/model settings, or replay this task under another preset. "
if ($readOnlyTask) { $scopedPrompt += 'This is read-only work; do not modify files or external state. ' }
$scopedPrompt += "`n`n"+$Prompt
Push-Location -LiteralPath $WorkingDirectory
try {
    # End variadic Claude tool options before passing the positional prompt.
    if ($targetHost -eq 'claude') { $cliArgs += '--' }
    & $executable @cliArgs $scopedPrompt
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        # Structured failure for explicit parent re-selection.  The launcher
        # never retries or substitutes; higher-effort entries are listed only
        # for confirmed service overload, never for 429/quota/rate-limit.
        $failedTuple = @{ preset = $Preset; slot = $Slot; model = $route.model; effort = $route.effort; host = $targetHost; read_only = $readOnlyTask }
        $menuByPreset = @{}
        foreach ($id in @($resolved.active_presets)) { $menuByPreset[$id] = @($policy.presets[$id].menu | ForEach-Object { @{ model = [string]$_.model; effort = [string]$_.effort } }) }
        $withinLower = @()
        $withinHigher = @()
        $failedIndex = -1
        for ($i = 0; $i -lt $menuByPreset[$Preset].Count; $i++) {
            if ($menuByPreset[$Preset][$i].model -ceq $route.model -and $menuByPreset[$Preset][$i].effort -ceq $route.effort) { $failedIndex = $i; break }
        }
        if ($failedIndex -gt 0) { $withinLower = @($menuByPreset[$Preset])[($failedIndex - 1)..0] }
        if ($failedIndex -ge 0 -and $failedIndex -lt ($menuByPreset[$Preset].Count - 1)) { $withinHigher = @($menuByPreset[$Preset])[($failedIndex + 1)..($menuByPreset[$Preset].Count - 1)] }
        # Cross-preset fallback follows the declared active order without
        # wrapping around to entries that precede the failed preset.  A failed
        # final preset therefore has no implicit cross-model retry; the parent
        # must make a fresh operator choice instead of silently cycling back.
        $crossPreset = @()
        $failedPresetIndex = [array]::IndexOf([string[]]@($resolved.active_presets), [string]$Preset)
        if ($failedPresetIndex -ge 0) {
            for ($j = $failedPresetIndex + 1; $j -lt @($resolved.active_presets).Count; $j++) {
                $id = @($resolved.active_presets)[$j]
                $crossPreset += @{ preset = $id; options = $menuByPreset[$id] }
            }
        }
        $failureDoc = @{ slot_failure = [ordered]@{
                exit = $code
                failed_tuple = $failedTuple
                reselection = [ordered]@{
                    within_preset_lower = $withinLower
                    cross_preset = $crossPreset
                    within_preset_higher_overload_only = $withinHigher
                    prohibition = 'Explicit parent re-selection for the next bounded task only; no automatic replay. For 429/quota/rate-limit/auth/billing use lower-effort or cross-preset entries; higher effort is reserved for confirmed service overload. Record failed tuple, failure, selected tuple and remaining scope.'
                }
            }
        } | ConvertTo-Json -Depth 6 -Compress
        $failureDoc
        throw "Slot process failed (exit=$code); no replay or preset substitution performed. $failureDoc"
    }
}
finally { Pop-Location }
