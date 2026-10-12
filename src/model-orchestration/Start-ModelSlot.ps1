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
    [switch]$Ephemeral,
    [ValidateSet('native','provider_override')][string]$CapabilityMode = 'native',
    [string]$CapabilityProbePath = '',
    [ValidateRange(0,1)][int]$ReselectionCount = 0
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
$routePreset = [string]$route.preset
$readOnlyTask = $ReadOnly -or $Slot -cin @($resolved.read_only_slots)
$presetHosts = @($policy.presets[$routePreset].hosts)
# Launch on the first declared facet with a verified native interface, so the
# first codex/claude host wins and zcode is always skipped as
# resolve-only; a zcode-only preset has no launchable facet at all.
$targetHost = $null
foreach ($h in $presetHosts) { if ($h -ceq 'codex' -or $h -ceq 'claude') { $targetHost = $h; break } }
if (-not $targetHost) { throw 'ZCode native launch interface is not verified.' }
$WorkingDirectory = (Resolve-Path -LiteralPath $WorkingDirectory).Path
$capability = [ordered]@{
    mode = $CapabilityMode
    host = $targetHost
    model = [string]$route.model
    effort = [string]$route.effort
    status = if ($Plan) { 'deferred' } else { 'pending' }
    native_supported = $null
    supported_efforts = @()
    upstream_contacted = $false
}
function ThrowCapabilityBlock($Status, $Reason, $SupportedEfforts = @()) {
    $capability.status = $Status
    $capability.reason = $Reason
    $capability.supported_efforts = @($SupportedEfforts)
    $capability.upstream_contacted = $false
    $doc = @{ capability_blocked = $capability } | ConvertTo-Json -Depth 8 -Compress
    $doc
    throw "Capability preflight blocked dispatch; no upstream request was sent. $doc"
}
function Get-CodexCatalog([string]$Path) {
    if ($Path) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Capability probe file not found: $Path" }
        return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
    }
    $output = @(& codex debug models 2>&1)
    $probeCode = $LASTEXITCODE
    if ($probeCode -ne 0) { throw "codex debug models failed (exit=$probeCode)." }
    try { return (($output | Out-String).Trim() | ConvertFrom-Json) }
    catch { throw "codex debug models did not return JSON: $($_.Exception.Message)" }
}
if (-not $Plan) {
    if ($CapabilityMode -eq 'provider_override') {
        $capability.status = 'provider_override_declared'
        $capability.reason = 'Explicit one-shot provider override; current provider evidence remains a parent precondition.'
    }
    else {
        if ($targetHost -ne 'codex') { ThrowCapabilityBlock 'probe_unavailable' 'Native capability probing is only implemented for Codex; use a verified host adapter.' }
        try { $catalog = Get-CodexCatalog $CapabilityProbePath }
        catch { ThrowCapabilityBlock 'probe_failed' $_.Exception.Message }
        $modelInfo = @($catalog.models | Where-Object { $_.slug -ceq $route.model })[0]
        if ($null -eq $modelInfo) { ThrowCapabilityBlock 'model_missing' "Native catalog does not contain model '$($route.model)'." }
        $supported = @($modelInfo.supported_reasoning_levels | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.effort } })
        $capability.supported_efforts = $supported
        $capability.native_supported = ($supported -ccontains $route.effort)
        if (-not $capability.native_supported) { ThrowCapabilityBlock 'tuple_unsupported' "Native catalog does not declare '$($route.model)/$($route.effort)'." $supported }
        $capability.status = 'native_supported'
    }
}
if ($targetHost -eq 'codex') {
    $cliArgs = @('exec','--profile',$routePreset.Replace('_','-'),'--strict-config','--json','--skip-git-repo-check','-C',$WorkingDirectory,
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
    @{preset=$Preset;active_presets=$resolved.active_presets;slot=$Slot;model=$route.model;effort=$route.effort;route_preset=$route.preset;auto_routing=$resolved.auto_routing;host=$targetHost;read_only=$readOnlyTask;delegation_enabled=$false;working_directory=$WorkingDirectory;capability=$capability;dispatch_policy=$resolved.dispatch_policy} | ConvertTo-Json -Depth 8
    return
}
if ([string]::IsNullOrWhiteSpace($Prompt)) { throw 'Prompt is required to execute a slot.' }
# No arbitrary CLI pass-through: the caller cannot override the frozen route or re-enable delegation.
$scopedPrompt = "Execution slot: $Slot. Use only this session's configured model/effort. Do not delegate, start another AI process, change provider/model settings, or replay this task under another preset. "
if ($readOnlyTask) { $scopedPrompt += 'This is read-only work; do not modify files or external state. ' }
$scopedPrompt += "`n`n"+$Prompt
function Classify-Failure([string]$Text) {
    if ($Text -match '(?i)(risk|suspicious|ban|banned|illegal|policy|fraud|风控|封号)') { return 'account_risk' }
    if ($Text -match '(?i)(429|rate[s-]?limit|too many requests|quota)') { return 'rate_limit' }
    if ($Text -match '(?i)(401|403|unauthori[sz]ed|forbidden|authentication|auth)') { return 'auth_or_permission' }
    if ($Text -match '(?i)(502|503|504|overload|temporarily unavailable|timeout|timed out)') { return 'upstream_unavailable' }
    if ($Text -match '(?i)(not found|cannot find|path|sandbox|tool|permission denied)') { return 'tool_or_environment' }
    return 'unknown'
}
Push-Location -LiteralPath $WorkingDirectory
try {
    # End variadic Claude tool options before passing the positional prompt.
    if ($targetHost -eq 'claude') { $cliArgs += '--' }
    $launchOutput = @(& $executable @cliArgs $scopedPrompt 2>&1)
    $launchOutput | ForEach-Object { $_ }
    $capability.upstream_contacted = $true
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        # Structured failure for explicit parent re-selection.  The launcher
        # never retries or substitutes; higher-effort entries are listed only
        # for confirmed service overload, never for 429/quota/rate-limit.
        $failedTuple = @{ preset = $routePreset; slot = $Slot; model = $route.model; effort = $route.effort; host = $targetHost; read_only = $readOnlyTask }
        $menuByPreset = @{}
        foreach ($id in @($resolved.active_presets)) { $menuByPreset[$id] = @($policy.presets[$id].menu | ForEach-Object { @{ model = [string]$_.model; effort = [string]$_.effort } }) }
        $withinLower = @()
        $withinHigher = @()
        $failedIndex = -1
        for ($i = 0; $i -lt $menuByPreset[$routePreset].Count; $i++) {
            if ($menuByPreset[$routePreset][$i].model -ceq $route.model -and $menuByPreset[$routePreset][$i].effort -ceq $route.effort) { $failedIndex = $i; break }
        }
        if ($failedIndex -gt 0) { $withinLower = @($menuByPreset[$routePreset])[($failedIndex - 1)..0] }
        if ($failedIndex -ge 0 -and $failedIndex -lt ($menuByPreset[$routePreset].Count - 1)) { $withinHigher = @($menuByPreset[$routePreset])[($failedIndex + 1)..($menuByPreset[$routePreset].Count - 1)] }
        # Cross-preset fallback follows the declared active order without
        # wrapping around to entries that precede the failed preset.  A failed
        # final preset therefore has no implicit cross-model retry; the parent
        # must make a fresh operator choice instead of silently cycling back.
        $crossPreset = @()
        $failedPresetIndex = [array]::IndexOf([string[]]@($resolved.active_presets), $routePreset)
        if ($failedPresetIndex -ge 0) {
            for ($j = $failedPresetIndex + 1; $j -lt @($resolved.active_presets).Count; $j++) {
                $id = @($resolved.active_presets)[$j]
                $crossPreset += @{ preset = $id; options = $menuByPreset[$id] }
                if (@($crossPreset).Count -ge [int]$resolved.dispatch_policy.max_explicit_reselections) { break }
            }
        }
        $failureClass = Classify-Failure (($launchOutput | Out-String))
        $nextAction = switch ($failureClass) {
            'account_risk' { 'stop_and_operator_review' }
            'auth_or_permission' { 'stop_and_operator_review' }
            'rate_limit' { 'stop_and_wait_for_fresh_parent_selection' }
            'upstream_unavailable' { 'one_explicit_reselection_only' }
            default { 'diagnose_before_any_new_dispatch' }
        }
        $failureDoc = @{ slot_failure = [ordered]@{
                exit = $code
                failure_class = $failureClass
                failed_tuple = $failedTuple
                capability = $capability
                upstream_contacted = $true
                retry_policy = [ordered]@{
                    replay_allowed = $false
                    duplicate_parallel_allowed = $false
                    next_action = $nextAction
                    explicit_reselections_remaining = [Math]::Max(0, [int]$resolved.dispatch_policy.max_explicit_reselections - $ReselectionCount)
                }
                reselection = [ordered]@{
                    within_preset_lower = $withinLower
                    cross_preset = $crossPreset
                    within_preset_higher_overload_only = $withinHigher
                    prohibition = 'One upstream attempt per bounded task; no automatic replay, duplicate parallel request, or identical-prompt resend. For 429/quota/rate-limit/auth/risk stop and wait for operator or fresh parent selection. A confirmed overload permits at most one explicit reselection, only when the alternate tuple is currently supported. Record failed tuple, failure, selected tuple and remaining scope.'
                }
            }
        } | ConvertTo-Json -Depth 6 -Compress
        $failureDoc
        throw "Slot process failed (exit=$code); no replay or preset substitution performed. $failureDoc"
    }
}
finally { Pop-Location }
