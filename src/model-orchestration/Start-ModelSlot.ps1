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
    throw "Capability preflight blocked dispatch; no model request was sent. $doc"
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
function Get-ProviderCapabilityEvidence([string]$Path, [string]$Model, [string]$Effort) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'CapabilityProbePath is required for provider_override.' }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Provider capability evidence not found: $Path" }
    try { $root = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    catch { throw "Provider capability evidence is not valid JSON: $($_.Exception.Message)" }
    $records = if ($root.PSObject.Properties.Name -contains 'tuples') { @($root.tuples) } else { @($root) }
    $match = @($records | Where-Object { [string]$_.model -ceq $Model -and [string]$_.effort -ceq $Effort -and [string]$_.status -ceq 'verified' })[0]
    if ($null -eq $match) { throw "Provider evidence has no verified exact tuple '$Model/$Effort'." }
    $surface = [string]$root.surface
    if ([string]::IsNullOrWhiteSpace($surface)) { $surface = [string]$root.provider }
    if ([string]::IsNullOrWhiteSpace($surface)) { $surface = [string]$match.surface; if ([string]::IsNullOrWhiteSpace($surface)) { $surface = [string]$match.provider } }
    $source = [string]$root.source
    if ([string]::IsNullOrWhiteSpace($source)) { $source = [string]$match.source }
    $observedText = [string]$root.observed_at
    if ([string]::IsNullOrWhiteSpace($observedText)) { $observedText = [string]$match.observed_at }
    $expiresText = [string]$root.expires_at
    if ([string]::IsNullOrWhiteSpace($expiresText)) { $expiresText = [string]$match.expires_at }
    if ([string]::IsNullOrWhiteSpace($surface) -or [string]::IsNullOrWhiteSpace($source) -or [string]::IsNullOrWhiteSpace($observedText) -or [string]::IsNullOrWhiteSpace($expiresText)) {
        throw 'Provider capability evidence must bind surface/provider, observed_at, expires_at and source.'
    }
    try {
        $observed = [DateTimeOffset]::Parse($observedText, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        $expires = [DateTimeOffset]::Parse($expiresText, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
    }
    catch { throw 'Provider capability evidence has invalid observed_at or expires_at.' }
    $now = [DateTimeOffset]::UtcNow
    if ($observed -gt $now -or $expires -le $now -or $expires -le $observed) { throw 'Provider capability evidence is outside its validity window.' }
    [ordered]@{
        model = $Model
        effort = $Effort
        status = 'verified'
        surface = $surface
        observed_at = $observed.ToString('o')
        expires_at = $expires.ToString('o')
        source = $source
    }
}
function Get-CodexRetryControl([string]$ProfileName) {
    $codexRoot = if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        [IO.Path]::GetFullPath($env:CODEX_HOME)
    }
    else {
        Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'
    }
    $basePath = Join-Path $codexRoot 'config.toml'
    $profilePath = Join-Path $codexRoot ($ProfileName + '.config.toml')
    $baseText = if (Test-Path -LiteralPath $basePath -PathType Leaf) { [IO.File]::ReadAllText($basePath) } else { '' }
    $profileText = if (Test-Path -LiteralPath $profilePath -PathType Leaf) { [IO.File]::ReadAllText($profilePath) } else { '' }

    function Get-RootTomlString([string]$Text, [string]$Key) {
        if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
        $rootText = [regex]::Split($Text, '(?m)^\s*\[[^\]]+\]\s*(?:#.*)?$')[0]
        $keyPattern = [regex]::Escape($Key)
        $pattern = '(?m)^\s*' + $keyPattern + '\s*=\s*(?:"(?<double>[^"]+)"|''(?<single>[^'']+)'')\s*(?:#.*)?$'
        $matches = [regex]::Matches($rootText, $pattern)
        if ($matches.Count -gt 1) { throw "Codex TOML has duplicate root key '$Key'." }
        if ($matches.Count -eq 0) { return $null }
        if ($matches[0].Groups['double'].Success) { return $matches[0].Groups['double'].Value }
        return $matches[0].Groups['single'].Value
    }

    $providerId = Get-RootTomlString $profileText 'model_provider'
    if ([string]::IsNullOrWhiteSpace($providerId)) { $providerId = Get-RootTomlString $baseText 'model_provider' }
    if ([string]::IsNullOrWhiteSpace($providerId) -or $providerId -ceq 'openai') {
        throw 'The effective Codex provider is built-in or unset; the documented per-provider retry cap is unavailable.'
    }
    if ($providerId -cnotmatch '^[A-Za-z0-9_-]+$') { throw 'The effective Codex provider id cannot be safely addressed by a CLI config override.' }

    $sectionPattern = '(?m)^\s*\[model_providers\.' + [regex]::Escape($providerId) + '\]\s*(?:#.*)?$'
    if ($baseText -notmatch $sectionPattern -and $profileText -notmatch $sectionPattern) {
        throw 'The effective Codex provider has no declared custom model_providers table for a per-invocation retry override.'
    }
    return [ordered]@{
        provider_id = $providerId
        request_max_retries = 0
        stream_max_retries = 0
        scope = 'this_codex_cli_invocation'
    }
}
$codexRetryControl = $null
if (-not $Plan -and $targetHost -eq 'codex') {
    try { $codexRetryControl = Get-CodexRetryControl $routePreset.Replace('_','-') }
    catch { ThrowCapabilityBlock 'retry_control_unavailable' $_.Exception.Message }
    $capability.retry_control = $codexRetryControl
}
if (-not $Plan) {
    if ($CapabilityMode -eq 'provider_override') {
        try { $capability.evidence = Get-ProviderCapabilityEvidence $CapabilityProbePath ([string]$route.model) ([string]$route.effort) }
        catch { ThrowCapabilityBlock 'provider_evidence_invalid' $_.Exception.Message }
        $capability.status = 'provider_evidence_verified'
        $capability.surface = $capability.evidence.surface
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
    if ($null -ne $codexRetryControl) {
        $providerId = [string]$codexRetryControl.provider_id
        $cliArgs += @('-c',("model_providers.$providerId.request_max_retries=0"),'-c',("model_providers.$providerId.stream_max_retries=0"))
    }
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
$maxExplicitReselections = [int]$resolved.dispatch_policy.max_explicit_reselections
if ($ReselectionCount -ge $maxExplicitReselections) {
    $budget = [ordered]@{
        status = 'reselection_budget_exhausted'
        slot = $Slot
        preset = $routePreset
        model = [string]$route.model
        effort = [string]$route.effort
        host = $targetHost
        reselection_count = $ReselectionCount
        max_explicit_reselections = $maxExplicitReselections
        upstream_contacted = $false
        replay_allowed = $false
        next_action = 'stop_and_wait_for_fresh_parent_selection'
    }
    $budgetDoc = @{ reselection_budget_exhausted = $budget } | ConvertTo-Json -Depth 8 -Compress
    $budgetDoc
    throw "Reselection budget exhausted; no upstream request was sent. $budgetDoc"
}
# No arbitrary CLI pass-through: the caller cannot override the frozen route or re-enable delegation.
$scopedPrompt = "Execution slot: $Slot. Use only this session's configured model/effort. Do not delegate, start another AI process, change provider/model settings, or replay this task under another preset. "
if ($readOnlyTask) { $scopedPrompt += 'This is read-only work; do not modify files or external state. ' }
$scopedPrompt += "`n`n"+$Prompt
function Classify-Failure([object[]]$Output) {
    $errors = [Collections.Generic.List[object]]::new()
    foreach ($item in @($Output)) {
        $event = $null
        if ($item -is [string]) {
            $text = ([string]$item).Trim()
            if ([string]::IsNullOrWhiteSpace($text)) { continue }
            try { $event = $text | ConvertFrom-Json } catch { continue }
        } else { $event = $item }
        if ($null -eq $event) { continue }
        foreach ($property in @('error','errors')) {
            if ($event.PSObject.Properties.Name -contains $property) {
                foreach ($errorRecord in @($event.$property)) { if ($null -ne $errorRecord -and $errorRecord -isnot [string]) { $errors.Add($errorRecord) } }
            }
        }
    }
    foreach ($errorRecord in $errors) {
        $tokens = @(
            $errorRecord.code, $errorRecord.reason_code, $errorRecord.category, $errorRecord.type, $errorRecord.status, $errorRecord.http_status
        ) | ForEach-Object { if ($null -ne $_) { ([string]$_).Trim().ToLowerInvariant() } } | Where-Object { $_ }
        if (@($tokens | Where-Object { $_ -in @('risk','account_risk','policy_violation','safety_block','fraud','banned') }).Count -gt 0) { return [pscustomobject]@{ class='account_risk'; source='structured_error_event' } }
        if (@($tokens | Where-Object { $_ -in @('429','rate_limit','rate-limit','quota','too_many_requests') }).Count -gt 0) { return [pscustomobject]@{ class='rate_limit'; source='structured_error_event' } }
        if (@($tokens | Where-Object { $_ -in @('401','403','auth','authentication','unauthorized','forbidden','permission') }).Count -gt 0) { return [pscustomobject]@{ class='auth_or_permission'; source='structured_error_event' } }
        if (@($tokens | Where-Object { $_ -in @('502','503','504','overload','service_unavailable','upstream_unavailable','temporarily_unavailable') }).Count -gt 0) { return [pscustomobject]@{ class='upstream_unavailable'; source='structured_error_event' } }
        if (@($tokens | Where-Object { $_ -in @('tool_error','environment_error','sandbox_error','not_found') }).Count -gt 0) { return [pscustomobject]@{ class='tool_or_environment'; source='structured_error_event' } }
    }
    [pscustomobject]@{ class='unknown'; source=if ($errors.Count -gt 0) { 'structured_error_unclassified' } else { 'unstructured_output' } }
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
        # Reselection options must be the resolved host facet's menu (a preset
        # may override its menu per host under host_menus), not the default menu.
        $menuByPreset = @{}
        foreach ($entry in @($resolved.reselection.rate_limit_order)) { $menuByPreset[[string]$entry.preset] = @($entry.menu | ForEach-Object { @{ model = [string]$_.model; effort = [string]$_.effort } }) }
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
        $classification = Classify-Failure $launchOutput
        $failureClass = [string]$classification.class
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
                failure_source = [string]$classification.source
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
