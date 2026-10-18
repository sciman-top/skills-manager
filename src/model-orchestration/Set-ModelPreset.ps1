#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Resolve','Plan','Apply','Rollback')][string]$Action = 'Plan',
    [string]$Preset = '',
    [string[]]$AvailablePreset = @(),
    [string]$CodexRoot = $(if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { $env:CODEX_HOME } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex' }),
    [string]$ClaudeRoot = $(if (-not [string]::IsNullOrWhiteSpace($env:CLAUDE_CONFIG_DIR)) { $env:CLAUDE_CONFIG_DIR } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude' }),
    [string]$ZCodeRoot = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.zcode'),
    [string]$ReceiptPath = '',
    [switch]$SubagentsOnly,
    [string]$CapabilityProbePath = '',
    [ValidateSet('codex','claude','zcode')][string]$ExecutionHost = 'codex'
)
$ErrorActionPreference = 'Stop'
$allowedModelEffortByHost = [ordered]@{
    codex = @(
        'gpt-6-luna|max'
        'glm-5.3-flash|xhigh'
        'claude-haiku-5-5|medium'
        'claude-haiku-5-5|high'
        'claude-haiku-5-5|xhigh'
        # The current Codex native catalog exposes this Gemini Flash model ID with the high tier in its slug.
        'gemini-3.8-flash-high|high'
    )
    claude = @(
        'claude-haiku-5-5|medium'
        'claude-haiku-5-5|high'
        'claude-haiku-5-5|xhigh'
    )
    zcode = @('glm-5.3-flash|max')
}
$allowedModelEffortTuples = @($allowedModelEffortByHost.Values | ForEach-Object { $_ } | Select-Object -Unique)
$policy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'presets.json') -Raw | ConvertFrom-Json -AsHashtable
# Fail closed on any malformed preset, not only the selected one: slot_map keys,
# index range, and menu population are the whole contract between menu and slots.
$slotNames = @($policy.slots)
if ($slotNames.Count -eq 0 -or @($slotNames | Select-Object -Unique).Count -ne $slotNames.Count) { throw 'Slots must be nonempty and unique.' }
foreach ($slot in $slotNames) { if ($slot -cnotmatch '^[a-z][a-z0-9_]*$') { throw "Invalid slot name: $slot" } }
if ('routine_maintenance' -cnotin $slotNames) { throw 'The default routine_maintenance slot is required.' }
foreach ($slot in @($policy.read_only_slots)) { if ($slot -cnotin $slotNames) { throw "Unknown read-only slot: $slot" } }
$autoRouteNames = @($policy.auto_routes.Keys)
$autoRouteKey = (@($autoRouteNames | Sort-Object) -join ',')
$slotKey = (@($slotNames | Sort-Object) -join ',')
if ($autoRouteNames.Count -ne $slotNames.Count -or $autoRouteKey -cne $slotKey) {
    throw 'auto_routes must cover exactly all slots.'
}
$dispatchPolicy = $policy.dispatch_policy
if (-not $dispatchPolicy -or
    $dispatchPolicy.max_controlled_launcher_invocations_per_bounded_task -ne 1 -or
    $dispatchPolicy.max_explicit_reselections -ne 1 -or
    $dispatchPolicy.duplicate_prompt_replay -ne $false -or
    $dispatchPolicy.parallel_duplicate_requests -ne $false -or
    $dispatchPolicy.rate_limit_action -cne 'stop_and_wait_for_fresh_parent_selection' -or
    $dispatchPolicy.auth_or_risk_action -cne 'stop_and_operator_review' -or
    $dispatchPolicy.overload_action -cne 'one_explicit_reselection_only') {
    throw 'dispatch_policy must enforce one attempt, one explicit reselection, and no duplicate replay.'
}
function Get-PresetMenu {
    param($PresetPolicy, [string]$HostName)
    $hostMenus = $PresetPolicy['host_menus']
    if ($hostMenus -and $hostMenus.Contains($HostName)) {
        return @($hostMenus[$HostName])
    }
    return @($PresetPolicy['menu'])
}
# Host-scoped strict subagent allowlist (user requirement, 2026-10-18): every menu and host
# menu tuple must be one of these; a host facet may only use its own tuples. gemini-3.8-flash
# is the relay slug gemini-3.8-flash-high.
function Assert-PresetMenu {
    param([string]$PresetId, [string]$HostName, $Menu)
    $menu = @($Menu)
    if ($menu.Count -eq 0) { throw "Preset $PresetId has an empty menu for host $HostName." }
    foreach ($entry in $menu) {
        if ($entry.model -cnotmatch '^[a-z0-9][a-z0-9.-]*$' -or $entry.effort -cnotin @('low','medium','high','max','xhigh')) { throw "Invalid tuple in preset $PresetId for host $HostName." }
        $tupleKey = "$($entry.model)|$($entry.effort)"
        if ($tupleKey -cnotin $allowedModelEffortTuples) { throw "Tuple outside the fixed model/effort allowlist in preset $PresetId for host $HostName`: $($entry.model)/$($entry.effort)" }
    }
    # Failure re-selection uses menu indices as effort order.
    $effortOrder = @('low','medium','high','max','xhigh')
    for ($index = 1; $index -lt $menu.Count; $index++) {
        if ($menu[$index].model -cne $menu[0].model -or
            [array]::IndexOf($effortOrder, $menu[$index].effort) -le [array]::IndexOf($effortOrder, $menu[$index - 1].effort)) {
            throw "Preset $PresetId menu for host $HostName must use one model with strictly increasing effort."
        }
    }
}
foreach ($id in $policy.presets.Keys) {
    $p = $policy.presets[$id]
    Assert-PresetMenu $id 'default' $p.menu
    $hosts = @($p.hosts)
    if ($hosts.Count -eq 0 -or ($hosts | Where-Object { $_ -cnotin @('codex','claude','zcode') })) { throw "Preset $id has invalid hosts." }
    if ($p.host_menus) {
        foreach ($hostName in $p.host_menus.Keys) {
            if ($hostName -cnotin $hosts) { throw "Preset $id has a host menu without a matching host facet: $hostName" }
            Assert-PresetMenu $id $hostName $p.host_menus[$hostName]
        }
    }
    if (-not $p.slot_map -or @($p.slot_map.Keys).Count -ne $slotNames.Count) { throw "Preset $id slot_map must cover exactly all slots." }
    foreach ($hostName in $hosts) {
        $hostMenu = @(Get-PresetMenu $p $hostName)
        foreach ($entry in $hostMenu) {
            $tupleKey = "$($entry.model)|$($entry.effort)"
            if ($tupleKey -cnotin $allowedModelEffortByHost[$hostName]) { throw "Tuple outside the fixed model/effort allowlist for host $hostName in preset $id`: $($entry.model)/$($entry.effort)" }
        }
        foreach ($slot in $slotNames) {
            if (-not $p.slot_map.Contains($slot)) { throw "Preset $id is missing slot mapping: $slot" }
            $idx = $p.slot_map[$slot]
            if ($idx -isnot [int] -and $idx -isnot [long]) { throw "Preset $id slot index must be an integer: $slot" }
            if ($idx -lt 0 -or $idx -ge $hostMenu.Count) { throw "Preset $id slot index out of range for host $hostName`: $slot -> $idx" }
        }
    }
}
foreach ($slot in $slotNames) {
    $autoPreset = [string]$policy.auto_routes[$slot]
    if (-not $policy.presets.Contains($autoPreset)) { throw "auto_routes[$slot] points to an unknown preset: $autoPreset" }
}
# Schema v7: every slot declares its overload alternates and controlled-launch policy explicitly. An empty list
# is an explicit "no automatic alternate", never an implicit fallback.
if ([int]$policy.schema_version -ne 7) { throw 'presets.json must use schema_version 7 (explicit per-slot fallbacks and controlled-launch policy).' }
if (-not $policy.fallbacks) { throw 'fallbacks must declare every slot.' }
if ((@($policy.fallbacks.Keys | Sort-Object) -join ',') -cne $slotKey) { throw 'fallbacks must declare exactly all slots.' }
foreach ($slot in $slotNames) {
    $alternates = @($policy.fallbacks[$slot])
    if ($alternates.Count -gt 3) { throw "fallbacks[$slot] lists more than three alternates." }
    $autoPresetId = [string]$policy.auto_routes[$slot]
    $primaryKeys = @(foreach ($hostName in @($policy.presets[$autoPresetId].hosts)) {
        $primaryEntry = @(Get-PresetMenu $policy.presets[$autoPresetId] $hostName)[$policy.presets[$autoPresetId].slot_map[$slot]]
        "$autoPresetId|$($primaryEntry.model)|$($primaryEntry.effort)"
    })
    $seenKeys = @{}
    foreach ($alternate in $alternates) {
        $alternatePreset = [string]$alternate.preset
        if (-not $policy.presets.Contains($alternatePreset)) { throw "fallbacks[$slot] references an unknown preset: $alternatePreset" }
        $inMenu = $false
        foreach ($hostName in @($policy.presets[$alternatePreset].hosts)) {
            if (@(Get-PresetMenu $policy.presets[$alternatePreset] $hostName | Where-Object { $_.model -ceq [string]$alternate.model -and $_.effort -ceq [string]$alternate.effort }).Count -gt 0) { $inMenu = $true }
        }
        if (-not $inMenu) { throw "fallbacks[$slot] tuple is not in preset ${alternatePreset}: $($alternate.model)/$($alternate.effort)" }
        $tupleKey = "$alternatePreset|$($alternate.model)|$($alternate.effort)"
        if ($tupleKey -cin $primaryKeys) { throw "fallbacks[$slot] repeats the slot's own route: $tupleKey" }
        if ($seenKeys.ContainsKey($tupleKey)) { throw "fallbacks[$slot] lists a duplicate: $tupleKey" }
        $seenKeys[$tupleKey] = $true
    }
}
$aliases = if ($policy.aliases) { $policy.aliases } else { @{} }
foreach ($alias in $aliases.Keys) {
    if ($policy.presets.Contains($alias) -or -not $policy.presets.Contains($aliases[$alias])) { throw "Invalid preset alias: $alias" }
}
$explicitPreset = -not [string]::IsNullOrWhiteSpace($Preset)
if (-not $explicitPreset) { $Preset = $policy.default_preset }
if ($aliases.Contains($Preset)) { $Preset = $aliases[$Preset] }
$AvailablePreset = @($AvailablePreset | ForEach-Object {
    foreach ($availableId in $_.Split(',', [StringSplitOptions]::TrimEntries)) {
        if ($aliases.Contains($availableId)) { $aliases[$availableId] } else { $availableId }
    }
})
$requestedPool = if ($AvailablePreset.Count -gt 0) { $AvailablePreset } else { @($policy.active_presets) }
if ($requestedPool.Count -eq 0) { throw 'No active model pool.' }
foreach ($id in $requestedPool) { if (-not $policy.presets.Contains($id)) { throw "Unknown pool preset: $id" } }
$activePresets = @($policy.active_presets | Where-Object { $requestedPool -ccontains $_ })
if ($activePresets.Count -ne @($requestedPool | Select-Object -Unique).Count) { throw 'Pool contains a preset outside active_presets.' }
if (-not $explicitPreset -and $Preset -cnotin $activePresets) { $Preset = $activePresets[0] }
if ($Preset -cnotin $activePresets) { throw 'Selected default preset is outside the active pool.' }
$hostActivePresets = @($activePresets | Where-Object { $ExecutionHost -in @($policy.presets[$_].hosts) })
if ($hostActivePresets.Count -eq 0) { throw "No active preset is available on host $ExecutionHost." }
if ($Preset -notin $hostActivePresets) {
    if ($explicitPreset) { throw "Selected preset is not available on host $ExecutionHost`: $Preset" }
    $Preset = $hostActivePresets[0]
}
$activePresets = $hostActivePresets
if (-not $policy.presets.Contains($Preset)) { throw 'Unknown preset.' }
# Deterministic availability re-selection contract, derived from the active
# pool (never hard-coded model names).  Rate-limit/quota/auth failures must not
# escalate effort (a higher effort spends more tokens against the same limit);
# only confirmed service overload/unavailability may try a higher effort.
function Get-ReselectionContract {
    param($Policy, [string[]]$ActiveIds, [string]$HostName)
    $menus = [ordered]@{}
    foreach ($id in $ActiveIds) {
        $menus[$id] = @(Get-PresetMenu $Policy.presets[$id] $HostName | ForEach-Object { @{ model = [string]$_.model; effort = [string]$_.effort } })
    }
    return [ordered]@{
        rule = 'Parent re-selects for the NEXT bounded task; never hot-swap a running task; record failed tuple, failure, selected tuple and remaining scope.'
        rate_limit_order = @($ActiveIds | ForEach-Object { @{ preset = $_; menu = $menus[$_] } })
        overload_higher_effort_allowed_presets = @($ActiveIds)
        prohibition = 'No silent model aliasing, no effort substitution, no automatic replay; a 429/quota/rate-limit/auth/risk/billing failure is never an effort escalation signal.'
    }
}
$reselectionContract = Get-ReselectionContract $policy $activePresets $ExecutionHost
$reselectionSummary = ('429/quota/rate-limit/auth/risk: stop and wait for operator or fresh parent selection; confirmed overload/unavailable: at most one explicit reselection for the NEXT bounded task, only when the alternate tuple is supported. No hot-swap, aliasing, effort substitution, duplicate prompt replay, or automatic retry. Record failed tuple, failure, selected tuple and remaining scope.')
$modelPreset = $policy.presets[$Preset]
$routes = [ordered]@{}
$routePresetIds = [ordered]@{}
foreach ($slot in $slotNames) {
    $requestedRoutePreset = if ($explicitPreset) { $Preset } else { [string]$policy.auto_routes[$slot] }
    $routePreset = $requestedRoutePreset
    $fallbackFrom = $null
    if ($routePreset -notin $activePresets) {
        if ($explicitPreset) { throw "Selected preset is not available for slot ${slot}: $routePreset" }
        $fallbackFrom = $routePreset
        $routePreset = @($activePresets | Where-Object { $ExecutionHost -in @($policy.presets[$_].hosts) })[0]
        if ([string]::IsNullOrWhiteSpace($routePreset)) { throw "No active preset remains for auto_routes[$slot] on host $ExecutionHost." }
    }
    $routePolicy = $policy.presets[$routePreset]
    $routeMenu = @(Get-PresetMenu $routePolicy $ExecutionHost)
    $entry = $routeMenu[$routePolicy.slot_map[$slot]]
    $routePresetIds[$slot] = $routePreset
    # Declared alternates restricted to the active host pool, with the route's own tuple removed.
    $declaredFallback = @()
    foreach ($alternate in @($policy.fallbacks[$slot])) {
        $alternatePreset = [string]$alternate.preset
        if ($alternatePreset -cnotin $activePresets) { continue }
        if ($alternatePreset -ceq $routePreset -and [string]$alternate.model -ceq [string]$entry.model -and [string]$alternate.effort -ceq [string]$entry.effort) { continue }
        $alternateFound = @(Get-PresetMenu $policy.presets[$alternatePreset] $ExecutionHost | Where-Object { $_.model -ceq [string]$alternate.model -and $_.effort -ceq [string]$alternate.effort })
        if ($alternateFound.Count -eq 0) { continue }
        $declaredFallback += @{ preset = $alternatePreset; model = [string]$alternate.model; effort = [string]$alternate.effort }
    }
    $routes[$slot] = @{ preset = $routePreset; requested_preset = $requestedRoutePreset; fallback_from = $fallbackFrom; model = [string]$entry.model; effort = [string]$entry.effort; declared_fallback = $declaredFallback }
}
$enabledRoutes = @()
$roleNames = @($slotNames)
foreach ($id in $activePresets) {
    $prefix = $policy.role_prefixes[$id]
    if ($prefix -cnotmatch '^[a-z][a-z0-9_]*$') { throw "Invalid role prefix: $id" }
    foreach ($entry in (Get-PresetMenu $policy.presets[$id] $ExecutionHost)) {
        $roleName = "$($prefix)_$($entry.effort)"
        if ($roleName -cin $roleNames) { throw "Duplicate execution role: $roleName" }
        $roleNames += $roleName
        $enabledRoutes += @{preset=$id;role=$roleName;model=$entry.model;effort=$entry.effort;hosts=@($policy.presets[$id].hosts)}
    }
}
if ($Action -eq 'Resolve') { @{ preset = $Preset; host = $ExecutionHost; auto_routing = (-not $explicitPreset); active_presets=$activePresets; hosts = @($modelPreset.hosts); routes = $routes; enabled_routes=$enabledRoutes; slots=$slotNames; read_only_slots=@($policy.read_only_slots); availability = 'operator_declared'; dispatch_policy=$dispatchPolicy; reselection = (Get-ReselectionContract $policy $activePresets $ExecutionHost) } | ConvertTo-Json -Depth 8; return }
$CodexRoot = [IO.Path]::GetFullPath($CodexRoot)
$stateRoot = Join-Path $PSScriptRoot '.state'
function Hash([string]$Path) { if (Test-Path -LiteralPath $Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }; return $null }
function WriteAtomic([string]$Path, [string]$Text) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try { [IO.File]::WriteAllText($temp, $Text, [Text.UTF8Encoding]::new($false)); [IO.File]::Move($temp, $Path, $true) }
    finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp } }
}
function RestoreFile($File) {
    $currentHash = Hash $File.path
    $alreadyRestored = if ($File.before_hash) { $currentHash -ceq $File.before_hash } else { $null -eq $currentHash }
    if ($alreadyRestored) { return }
    if ($currentHash -cne $File.after_hash) { throw "Rollback drift: $($File.path)" }
    if ($File.before_hash) {
        if ((Hash $File.backup) -cne $File.before_hash) { throw 'Backup hash mismatch.' }
        $temp = "$($File.path).$([guid]::NewGuid().ToString('N')).tmp"
        try { [IO.File]::Copy($File.backup,$temp,$false); [IO.File]::Move($temp,$File.path,$true) }
        finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp } }
    }
    else { Remove-Item -LiteralPath $File.path }
}
if ($Action -eq 'Rollback') {
    if (-not $ReceiptPath) { throw 'ReceiptPath is required.' }
    $receipt = Get-Content -LiteralPath $ReceiptPath -Raw | ConvertFrom-Json -AsHashtable
    foreach ($f in $receipt.files) {
        $currentHash = Hash $f.path
        $isBefore = if ($f.before_hash) { $currentHash -ceq $f.before_hash } else { $null -eq $currentHash }
        if (-not $isBefore -and $currentHash -cne $f.after_hash) { throw "Rollback drift: $($f.path)" }
        if ($f.before_hash -and (Hash $f.backup) -cne $f.before_hash) { throw 'Backup hash mismatch.' }
    }
    $receipt.status = 'rollback_in_progress'; WriteAtomic $ReceiptPath ($receipt | ConvertTo-Json -Depth 12)
    try {
        foreach ($f in @($receipt.files)[($receipt.files.Count-1)..0]) { RestoreFile $f }
        $receipt.status = 'rolled_back'; WriteAtomic $ReceiptPath ($receipt | ConvertTo-Json -Depth 12)
    }
    catch {
        $receipt.status = 'rollback_blocked'; $receipt.last_error = $_.Exception.Message
        WriteAtomic $ReceiptPath ($receipt | ConvertTo-Json -Depth 12)
        throw
    }
    'Rollback complete.'; return
}
# Explicitly selected presets must have a native facet for the target host.
if ($ExecutionHost -eq 'codex' -and 'codex' -notin @($modelPreset.hosts)) { throw 'Codex native model/effort projection is not available for the selected preset.' }
if ($ExecutionHost -eq 'claude' -and 'claude' -notin @($modelPreset.hosts)) { throw 'Claude native model/effort projection is not available for the selected preset.' }
if ($ExecutionHost -eq 'zcode' -and 'zcode' -notin @($modelPreset.hosts)) { throw 'ZCode native model/effort projection is not available for the selected preset.' }
if ($ExecutionHost -eq 'zcode' -and -not $SubagentsOnly) { throw 'ZCode projection supports only -SubagentsOnly.' }
function SetScalar([string]$Text,[string]$Section,[string]$Key,[string]$Value) {
    # Only edit known flat scalar keys; unfamiliar TOML shapes are rejected.
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in ($Text -split '\r?\n')) { $lines.Add($line) }
    $start = 0; $end = $lines.Count
    if ($Section) {
        $headers = @(0..($lines.Count-1) | Where-Object { $lines[$_] -cmatch ('^\[' + [regex]::Escape($Section) + '\]\s*(?:#.*)?$') })
        if ($headers.Count -ne 1) { throw "Expected one [$Section] section." }
        $start = $headers[0] + 1
    }
    for ($i=$start; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*\[') { $end=$i; break } }
    $hits = @(for ($i=$start; $i -lt $end; $i++) {
        $keyPattern = '(?:' + [regex]::Escape($Key) + '|"' + [regex]::Escape($Key) + '"|''' + [regex]::Escape($Key) + ''')'
        if ($lines[$i] -match ('^\s*' + $keyPattern + '\s*=')) { $i }
    })
    if ($hits.Count -gt 1) { throw "Duplicate scalar: $Key" }
    $newLine = "$Key = $Value"
    if ($hits.Count -eq 1) { $lines[$hits[0]] = $newLine } else { $lines.Insert($end, $newLine) }
    return $lines -join "`n"
}
function GetScalar([string]$Text,[string]$Section,[string]$Key) {
    $lines = @($Text -split '\r?\n')
    $start = 0; $end = $lines.Count
    if ($Section) {
        $headers = @(0..($lines.Count-1) | Where-Object { $lines[$_] -cmatch ('^\[' + [regex]::Escape($Section) + '\]\s*(?:#.*)?$') })
        if ($headers.Count -gt 1) { throw "Duplicate [$Section] section." }
        if ($headers.Count -eq 0) { return $null }
        $start = $headers[0] + 1
    }
    for ($i=$start; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*\[') { $end=$i; break } }
    $keyPattern = '(?:' + [regex]::Escape($Key) + '|"' + [regex]::Escape($Key) + '"|''' + [regex]::Escape($Key) + ''')'
    $hits = @(for ($i=$start; $i -lt $end; $i++) { if ($lines[$i] -match ('^\s*' + $keyPattern + '\s*=\s*(?<value>true|false)\s*(?:#.*)?$')) { $matches['value'].ToLowerInvariant() } })
    if ($hits.Count -gt 1) { throw "Duplicate scalar: $Key" }
    if ($hits.Count -eq 0) { return $null }
    return $hits[0]
}
function RemoveScalar([string]$Text,[string]$Section,[string]$Key) {
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in ($Text -split '\r?\n')) { $lines.Add($line) }
    $start = 0; $end = $lines.Count
    if ($Section) {
        $headers = @(0..($lines.Count-1) | Where-Object { $lines[$_] -cmatch ('^\[' + [regex]::Escape($Section) + '\]\s*(?:#.*)?$') })
        if ($headers.Count -ne 1) { throw "Expected one [$Section] section." }
        $start = $headers[0] + 1
    }
    for ($i=$start; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*\[') { $end=$i; break } }
    $keyPattern = '(?:' + [regex]::Escape($Key) + '|"' + [regex]::Escape($Key) + '"|''' + [regex]::Escape($Key) + ''')'
    $hits = @(for ($i=$start; $i -lt $end; $i++) { if ($lines[$i] -match ('^\s*' + $keyPattern + '\s*=')) { $i } })
    if ($hits.Count -gt 1) { throw "Duplicate scalar: $Key" }
    if ($hits.Count -eq 1) { $lines.RemoveAt($hits[0]) }
    return $lines -join "`n"
}
$files = [Collections.Generic.List[object]]::new()
function AddFile([string]$Path,[string]$Text) {
    $files.Add(@{path=[IO.Path]::GetFullPath($Path); text=$Text; before_hash=(Hash $Path)})
}
$profileNames = @{}
$projectionScope = if ($SubagentsOnly) { 'subagents_only' } else { 'full_preset' }
$slotGuidance = @{
    quick_triage = 'Select for a small read-only lookup or known error classification; downgrade here only after the remaining question is concrete and bounded.'
    routine_maintenance = 'Select for a small known fix with a local proof. If the cause or ownership is unclear across modules, use deep_investigation before starting a separate implementation task.'
    standard_review = 'Select for read-only review of a bounded change; use deep_investigation for unresolved cross-module behavior, architecture, security or interacting constraints.'
    bounded_implementation = 'Select for a scoped implementation with clear inputs, write set and proof; use deep_implementation only when the implementation itself has unresolved interacting constraints.'
    deep_investigation = 'Read-only investigation for unresolved cross-module root cause, architecture, security boundaries or interacting constraints. Return findings and a proposed bounded write set; do not implement the fix.'
    deep_implementation = 'Write-capable work for a complex implementation with an explicit scope and write set. The parent supplies the prior investigation or concrete requirements, proof and stop; do not turn this into open-ended discovery.'
    test_execution = 'Select for running scoped tests and diagnosing failures; the parent supplies the allowed command and verification boundary.'
    documentation_review = 'Select for read-only documentation and contract consistency checks.'
    architecture_review = 'Select for read-only architecture, interacting constraints or security boundary review.'
}
$parentGuidance = 'Split work by dependencies and choose the named native execution slot by task shape before dispatch. Use the deterministic auto route for the slot unless the parent records an explicit supported tuple override; different tasks may use different models simultaneously. Delegate only when explicitly authorized. Parallelize only independently verifiable slices with disjoint write sets and positive benefit within native concurrency limits. Do not replay an identical prompt, start duplicate parallel requests, or automatically launch another task after 429/quota/rate-limit/auth/risk responses. Stop, record the failed tuple and remaining scope, and wait for a fresh parent selection. A confirmed overload may receive one explicit reselection only when the alternate tuple is currently supported and the parent tracks the task-level budget. Do not hot-swap a running task, select a gateway, or silently substitute an effort across host menus. On Codex, use the named native slot or exact-tuple role; each generated agent config pins one of the approved model/effort tuples. Start-ModelSlot.ps1 remains an explicitly invoked one-shot CLI path; its retry cap does not govern native agent requests and it is not a substitute for native subagent dispatch.'
$tupleBlocks = [Collections.Generic.List[string]]::new()
$nativeCodexTuples = @('gpt-6-luna|max','glm-5.3-flash|xhigh','claude-haiku-5-5|medium','claude-haiku-5-5|high','claude-haiku-5-5|xhigh','gemini-3.8-flash-high|high')
function Test-NativeCodexTuple($Entry) { return ("$($Entry.model)|$($Entry.effort)" -cin $nativeCodexTuples) }
$nativeAgentAvailable = @($enabledRoutes | Where-Object { Test-NativeCodexTuple $_ }).Count -gt 0
foreach ($entry in $enabledRoutes) {
    if ($ExecutionHost -cne 'codex' -or 'codex' -notin $entry.hosts) { continue }
    if (-not (Test-NativeCodexTuple $entry)) { continue }
    $rolePath = Join-Path $PSScriptRoot ".generated/codex/pool/$($entry.role).toml"
    $description = "Model pool role $($entry.role), $($entry.model)/$($entry.effort). Parent assigns the task slot, exact scope, write set, proof and stop; use only when this exact tuple is supported by the current host."
    $instructions = 'Execute the assigned bounded task and obey its read-only or write scope. Preserve unrelated work. Do not delegate, change models or replay completed writes. Return verification evidence and unresolved uncertainty to the parent, then stop.'
    $roleText = @("name = `"$($entry.role)`"", "description = `"$description`"", "model = `"$($entry.model)`"", "model_reasoning_effort = `"$($entry.effort)`"", "developer_instructions = `"$instructions`"", '') -join "`n"
    AddFile $rolePath $roleText
    $tupleBlocks.Add("[agents.$($entry.role)]`ndescription = `"$description`"`nconfig_file = '$($rolePath.Replace('\','/'))'`n")
}
$capability = [ordered]@{
    status = 'not_applicable'
    host = $ExecutionHost
    source = $CapabilityProbePath
    tuples = @()
    unsupported = @()
}
function Get-CodexCatalog([string]$Path) {
    if ($Path) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Capability probe file not found: $Path" }
        try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) }
        catch { throw "Capability probe file is not valid JSON: $($_.Exception.Message)" }
    }
    $output = @(& codex debug models 2>&1)
    $probeCode = $LASTEXITCODE
    if ($probeCode -ne 0) { throw "codex debug models failed (exit=$probeCode)." }
    try { return (($output | Out-String).Trim() | ConvertFrom-Json) }
    catch { throw "codex debug models did not return JSON: $($_.Exception.Message)" }
}
function Test-CodexNativeTuples($Catalog, $Entries, [string]$Source) {
    $models = @($Catalog.models)
    if ($models.Count -eq 0) { throw 'Codex capability catalog contains no models.' }
    $tupleResults = [Collections.Generic.List[object]]::new()
    $unsupported = [Collections.Generic.List[object]]::new()
    foreach ($entry in $Entries) {
        $model = [string]$entry.model
        $effort = [string]$entry.effort
        $modelInfo = @($models | Where-Object { $_.slug -ceq $model })[0]
        if ($null -eq $modelInfo) {
            $record = [ordered]@{ model=$model; effort=$effort; status='model_missing'; supported_efforts=@() }
            $tupleResults.Add($record); $unsupported.Add($record); continue
        }
        $levels = if ($modelInfo.PSObject.Properties.Name -contains 'supported_reasoning_levels') { @($modelInfo.supported_reasoning_levels) } else { @() }
        $supported = @($levels | ForEach-Object {
            if ($_ -is [string]) { [string]$_ }
            elseif ($null -ne $_ -and $_.PSObject.Properties.Name -contains 'effort') { [string]$_.effort }
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        $status = if ($supported -ccontains $effort) { 'supported' } else { 'tuple_unsupported' }
        $record = [ordered]@{ model=$model; effort=$effort; status=$status; supported_efforts=@($supported) }
        $tupleResults.Add($record)
        if ($status -ne 'supported') { $unsupported.Add($record) }
    }
    return [ordered]@{
        status = if ($unsupported.Count -eq 0) { 'native_supported' } else { 'blocked' }
        host = 'codex'
        source = $Source
        tuples = @($tupleResults)
        unsupported = @($unsupported)
    }
}
if ($ExecutionHost -eq 'codex' -and 'codex' -in @($modelPreset.hosts)) {
    $codexEntries = @($enabledRoutes | Where-Object { 'codex' -in @($_.hosts) })
    try {
        $catalog = Get-CodexCatalog $CapabilityProbePath
        $capabilitySource = if ($CapabilityProbePath) { $CapabilityProbePath } else { 'codex debug models' }
        $capability = Test-CodexNativeTuples $catalog $codexEntries $capabilitySource
    }
    catch {
        $capability.status = 'probe_failed'
        $capability.reason = $_.Exception.Message
        $doc = @{ capability_blocked = $capability } | ConvertTo-Json -Depth 12 -Compress
        throw "Codex native capability preflight failed; no host files were written. $doc"
    }
    if (@($capability.unsupported).Count -gt 0) {
        $doc = @{ capability_blocked = $capability } | ConvertTo-Json -Depth 12 -Compress
        throw "Codex native capability preflight blocked projection; no host files were written. $doc"
    }
}
if ($ExecutionHost -eq 'codex' -and 'codex' -in $modelPreset.hosts) {
# Every active preset with a codex facet gets a complete native profile, so the
# strict slot launcher can freeze any selected pool member; codex_order wins.
$codexIds = @($policy.codex_order | Where-Object { $activePresets -ccontains $_ -and 'codex' -in $policy.presets[$_].hosts })
foreach ($id in $policy.presets.Keys) { if ($activePresets -ccontains $id -and $id -cnotin $codexIds -and 'codex' -in $policy.presets[$id].hosts) { $codexIds += $id } }
foreach ($id in $codexIds) {
    $p = $policy.presets[$id]
    $profileNames[$id] = $id.Replace('_','-')
    $roleBlocks = [Collections.Generic.List[string]]::new()
        $codexMenu = @(Get-PresetMenu $p 'codex')
        $standard = $codexMenu[$p.slot_map['routine_maintenance']]
    $profileNativeAgentAvailable = @($codexMenu | Where-Object { Test-NativeCodexTuple $_ }).Count -gt 0
    foreach ($slot in $slotNames) {
        $entry = $codexMenu[$p.slot_map[$slot]]
        if (-not (Test-NativeCodexTuple $entry)) { continue }
        $rolePath = Join-Path $PSScriptRoot ".generated/codex/$id/$slot.toml"
        $readOnly = $slot -cin @($policy.read_only_slots)
        $guidance = if ($slotGuidance.ContainsKey($slot)) { $slotGuidance[$slot] } else { 'Select for the configured bounded task; the parent supplies scope, proof and stop.' }
        $description = "Execution slot $slot, $($entry.model)/$($entry.effort). " + $(if ($readOnly) { 'Read-only evidence work. ' } else { 'Bounded implementation with proportionate verification. ' }) + $guidance + ' This is a default route; choose a supported model pool role for a different model/effort on this task.'
        $instructions = "Execute only the assigned $slot task within the supplied scope. Preserve unrelated changes. Do not delegate or change models. Return concrete evidence and any unresolved uncertainty for parent re-selection before a new bounded task. Do not replay completed writes. Stop at the assigned boundary."
        if ($readOnly) { $instructions += ' Do not modify files or external state.' }
        $roleText = @("name = `"$slot`"", "description = `"$description`"", "model = `"$($entry.model)`"", "model_reasoning_effort = `"$($entry.effort)`"", "developer_instructions = `"$instructions`"", '') -join "`n"
        AddFile $rolePath $roleText
        $roleBlocks.Add("[agents.$slot]`ndescription = `"$description`"`nconfig_file = '$($rolePath.Replace('\','/'))'`n")
    }
    $profileAgentSection = if ($profileNativeAgentAvailable) {
        "[agents]`ndefault_subagent_model = `"$($standard.model)`"`ndefault_subagent_reasoning_effort = `"$($standard.effort)`""
    }
    else { "[agents]`nenabled = false" }
    $header = @("model = `"$($standard.model)`"", "review_model = `"$($standard.model)`"", "model_reasoning_effort = `"$($standard.effort)`"", "developer_instructions = `"$parentGuidance`"", '', $profileAgentSection) -join "`n"
    $profileText = $header + "`n`n" + ($roleBlocks -join "`n") + "`n" + ($tupleBlocks -join "`n")
    AddFile (Join-Path $CodexRoot "$($profileNames[$id]).config.toml") $profileText
    if ($id -ceq $Preset) { $activeBlocks = $roleBlocks -join "`n" }
}
$activeRoleBlocks = [Collections.Generic.List[string]]::new()
foreach ($slot in $slotNames) {
    $routePreset = $routePresetIds[$slot]
    $routePath = Join-Path $PSScriptRoot ".generated/codex/$routePreset/$slot.toml"
    $route = $routes[$slot]
    if (-not (Test-NativeCodexTuple $route)) { continue }
    $activeRoleBlocks.Add("[agents.$slot]`ndescription = `"Auto route $slot, $($route.model)/$($route.effort) via $routePreset. Parent supplies scope, proof and stop.`"`nconfig_file = '$($routePath.Replace('\','/'))'`n")
}
$activeBlocks = $activeRoleBlocks -join "`n"
$configPath = Join-Path $CodexRoot 'config.toml'
$standard = @(Get-PresetMenu $modelPreset 'codex')[$modelPreset.slot_map['routine_maintenance']]
$defaultSubagent = $routes['routine_maintenance']
$config = [IO.File]::ReadAllText($configPath)
$nativeEnableMarker = [regex]::Match($config, '(?m)^# model-orchestration-native-agents-enabled-prior=(true|false|unset)\s*$')
$nativeAgentPrior = if ($nativeEnableMarker.Success) { $nativeEnableMarker.Groups[1].Value } else { GetScalar $config 'agents' 'enabled' }
$config = [regex]::Replace($config, '(?ms)^# model-orchestration begin\r?\n.*?^# model-orchestration end\r?\n?', '')
# Older host edits can leave owned role tables outside the managed markers.
# Retire only tables pointing into this tool's generated Codex directory.
$ownedRoleRoot = (Join-Path $PSScriptRoot '.generated/codex').Replace('\','/') + '/'
$config = [regex]::Replace($config, '(?ms)^\[agents\.[a-z0-9_]+\][^\r\n]*\r?\n(?:(?!^\[).)*', {
    param($match)
    $text = $match.Value
    if ($text -notmatch ('(?m)^config_file = ''' + [regex]::Escape($ownedRoleRoot))) { return $text }
    $lines = @($text -split '\r?\n')
    foreach ($line in $lines) {
        if ($line -notmatch '^\s*(?:$|#|\[agents\.|description\s*=|config_file\s*=)') { throw 'Owned role contains unexpected fields; review before retirement.' }
    }
    return (@($lines | Where-Object { $_ -match '^\s*#' -and $_ -notmatch '^# (?:model-orchestration|availability-rules:)' }) -join "`n") + "`n"
})
$config = [regex]::Replace($config, '(?m)^# model-orchestration (?:begin|end)\r?\n?', '')
if (-not $SubagentsOnly) {
    $config = SetScalar $config '' 'model' ('"'+$standard.model+'"')
    $config = SetScalar $config '' 'review_model' ('"'+$standard.model+'"')
    $config = SetScalar $config '' 'model_reasoning_effort' ('"'+$standard.effort+'"')
}
if ($nativeAgentAvailable) {
    if ($nativeEnableMarker.Success) {
        if ($nativeAgentPrior -eq 'unset') { $config = RemoveScalar $config 'agents' 'enabled' }
        else { $config = SetScalar $config 'agents' 'enabled' $nativeAgentPrior }
    }
    $config = SetScalar $config 'agents' 'default_subagent_model' ('"'+$defaultSubagent.model+'"')
    $config = SetScalar $config 'agents' 'default_subagent_reasoning_effort' ('"'+$defaultSubagent.effort+'"')
}
else {
    if ($nativeAgentPrior -notin @('true','false','unset')) { $nativeAgentPrior = 'unset' }
    $config = SetScalar $config 'agents' 'enabled' 'false'
    $config = RemoveScalar $config 'agents' 'default_subagent_model'
    $config = RemoveScalar $config 'agents' 'default_subagent_reasoning_effort'
}
$nativeEnableMarkerText = if (-not $nativeAgentAvailable) { "`n# model-orchestration-native-agents-enabled-prior=$nativeAgentPrior" } else { '' }
$config = $config.TrimEnd() + "`n# model-orchestration begin`n# availability-rules: $reselectionSummary$nativeEnableMarkerText`n$activeBlocks`n$($tupleBlocks -join "`n")`n# model-orchestration end`n"
AddFile $configPath $config
}
# Not elseif: a preset may carry both facets (one Apply can project Claude Code
# and the shared codex surface together).
if ($ExecutionHost -eq 'claude' -and 'claude' -in $modelPreset.hosts) {
    $ClaudeRoot = [IO.Path]::GetFullPath($ClaudeRoot)
    $standard = @(Get-PresetMenu $modelPreset 'claude')[$modelPreset.slot_map['routine_maintenance']]
    $settingsPath = Join-Path $ClaudeRoot 'settings.json'
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -AsHashtable
    if (-not $settings.Contains('env')) { $settings.env = [ordered]@{} }
    if (-not $SubagentsOnly) {
        $settings.model = $standard.model
        $settings.availableModels = @($standard.model)
        $settings.effortLevel = $standard.effort
        foreach ($key in @('ANTHROPIC_MODEL','ANTHROPIC_DEFAULT_MODEL','ANTHROPIC_DEFAULT_FABLE_MODEL','ANTHROPIC_DEFAULT_OPUS_MODEL','ANTHROPIC_DEFAULT_SONNET_MODEL','ANTHROPIC_DEFAULT_HAIKU_MODEL')) { $settings.env[$key] = $standard.model }
        $settings.env.CLAUDE_CODE_EFFORT_LEVEL = $standard.effort
    }
    $settings.env.CLAUDE_CODE_SUBAGENT_MODEL = $standard.model
    $settings.env.CLAUDE_CODE_SUBAGENT_MODEL_FORCE = '1'
    AddFile $settingsPath ($settings | ConvertTo-Json -Depth 80)
    foreach ($slot in $slotNames) {
        $name = $slot.Replace('_','-')
        $entry = @(Get-PresetMenu $modelPreset 'claude')[$modelPreset.slot_map[$slot]]
        $body = @('---',"name: $name", "description: $slot execution slot using $($entry.model) at $($entry.effort) effort. $($slotGuidance[$slot])", "model: $($entry.model)", "effort: $($entry.effort)", 'disallowedTools: Agent', '---', '', 'Perform only the assigned bounded task. Preserve unrelated work. Return concrete verification evidence and unresolved uncertainty for parent re-selection before a new bounded task. Do not replay completed writes, change models or delegate.')
        if ($slot -cin @($policy.read_only_slots)) { $body += 'Read-only: do not modify files or external state.' }
        AddFile (Join-Path $ClaudeRoot "agents/$name.md") (($body -join "`n")+"`n")
    }
}
if ($ExecutionHost -eq 'zcode' -and 'zcode' -in $modelPreset.hosts) {
    $ZCodeRoot = [IO.Path]::GetFullPath($ZCodeRoot)
    $zcodeMenu = @(Get-PresetMenu $modelPreset 'zcode')
    if ($zcodeMenu.Count -ne 1 -or $zcodeMenu[0].model -cne 'glm-5.3-flash' -or $zcodeMenu[0].effort -cne 'max') {
        throw 'The ZCode writer only supports the reviewed GLM-5.3-Flash/max host facet.'
    }
    $sourcePath = Join-Path $ZCodeRoot 'agents/glm-max.md'
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "ZCode model source agent is required: $sourcePath" }
    $sourceText = [IO.File]::ReadAllText($sourcePath)
    $frontmatterMatch = [regex]::Match($sourceText, '\A---\s*\r?\n(?<frontmatter>.*?)\r?\n---(?:\r?\n|$)', [Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $frontmatterMatch.Success) { throw 'ZCode model source agent has invalid frontmatter.' }
    $zcodeModelMatch = [regex]::Match($frontmatterMatch.Groups['frontmatter'].Value, '(?m)^model\s*:\s*(?<value>.+?)\s*$')
    $zcodeEffortMatch = [regex]::Match($frontmatterMatch.Groups['frontmatter'].Value, '(?m)^thoughtLevel\s*:\s*(?<value>.+?)\s*$')
    if (-not $zcodeModelMatch.Success -or -not $zcodeEffortMatch.Success) { throw 'ZCode model source agent must declare exact model and thoughtLevel fields.' }
    $zcodeModel = $zcodeModelMatch.Groups['value'].Value.Trim()
    if (($zcodeModel.StartsWith('"') -and $zcodeModel.EndsWith('"')) -or ($zcodeModel.StartsWith("'") -and $zcodeModel.EndsWith("'"))) {
        $zcodeModel = $zcodeModel.Substring(1, $zcodeModel.Length - 2)
    }
    $zcodeEffort = $zcodeEffortMatch.Groups['value'].Value.Trim().Trim([char[]]@('"', "'"))
    if ($zcodeModel -cnotmatch '^[A-Za-z0-9][A-Za-z0-9:./_-]*$' -or $zcodeModel -cnotmatch '(?i)(?:^|/)GLM-5\.3-Flash$') {
        throw 'ZCode model source agent must name the configured GLM-5.3-Flash model without whitespace or YAML-special characters.'
    }
    if ($zcodeEffort -cne 'max') { throw 'ZCode model source agent must declare thoughtLevel: max.' }
    $managedMarker = '<!-- managed-by: skills-manager/model-orchestration -->'
    $zcodeEffort = [string]$zcodeMenu[0].effort
    foreach ($slot in $slotNames) {
        $name = "skills-manager-$($slot.Replace('_','-'))"
        $path = Join-Path $ZCodeRoot "agents/$name.md"
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $existingText = [IO.File]::ReadAllText($path)
            if (-not $existingText.Contains($managedMarker)) { throw "Refusing to overwrite user-owned ZCode agent: $path" }
        }
        $readOnly = $slot -cin @($policy.read_only_slots)
        $guidance = if ($slotGuidance.ContainsKey($slot)) { $slotGuidance[$slot] } else { 'Execute the assigned bounded task; return evidence and stop.' }
        $description = "Execution slot $slot. $guidance"
        $modelScalar = $zcodeModel.Replace('"','\"')
        $descriptionScalar = $description.Replace('"','\"')
        $body = @(
            '---',
            "name: $name",
            "description: `"$descriptionScalar`"",
            "model: `"$modelScalar`"",
            "thoughtLevel: $zcodeEffort",
            '---',
            '',
            $managedMarker,
            "Execute only the assigned $slot task within the supplied scope. Preserve unrelated changes. Do not delegate, change models, or replay completed writes. Return concrete evidence and unresolved uncertainty for parent selection before a new bounded task. Stop at the assigned boundary."
        )
        if ($readOnly) { $body += 'Read-only: do not modify files or external state.' }
        AddFile $path (($body -join "`n")+"`n")
    }
}
$changed = @($files | Where-Object { -not (Test-Path -LiteralPath $_.path) -or [IO.File]::ReadAllText($_.path).Replace("`r`n","`n") -cne $_.text.Replace("`r`n","`n") })
if ($Action -eq 'Plan') {
    $nativeTupleRoles = @($enabledRoutes | Where-Object { Test-NativeCodexTuple $_ } | ForEach-Object { @{ role=$_.role; model=$_.model; effort=$_.effort } })
    $nativePolicy = @{ enabled=$nativeAgentAvailable; default_slot='routine_maintenance'; default_model=$defaultSubagent.model; default_effort=$defaultSubagent.effort; tuple_roles=$nativeTupleRoles; direct_cli_path='Start-ModelSlot.ps1' }
    @{preset=$Preset; host=$ExecutionHost; active_presets=$activePresets; enabled_routes=$enabledRoutes; scope=$projectionScope; files=@($changed | ForEach-Object { @{path=$_.path;before_hash=$_.before_hash} }); routes=$routes; reselection=$reselectionContract; capability=$capability; native_agent_policy=$nativePolicy; gateway_changes=0} | ConvertTo-Json -Depth 12
    return
}
if ($changed.Count -eq 0) { 'No changes.'; return }
$run = Join-Path $stateRoot ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
[IO.Directory]::CreateDirectory($run) | Out-Null
$receipt = @{schema_version=2;preset=$Preset;active_presets=$activePresets;scope=$projectionScope;status='prepared';capability=$capability;files=@()}
foreach ($f in $changed) {
    if ((Hash $f.path) -cne $f.before_hash) { throw "Before-hash drift: $($f.path)" }
    $backup = Join-Path $run ("$($receipt.files.Count).bak")
    if ($f.before_hash) { [IO.File]::Copy($f.path,$backup,$false); if ((Hash $backup) -cne $f.before_hash) { throw 'Backup mismatch.' } }
    $receipt.files += @{path=$f.path;before_hash=$f.before_hash;backup=$backup;after_hash=$null}
}
$receiptFile = Join-Path $run 'receipt.json'
WriteAtomic $receiptFile ($receipt | ConvertTo-Json -Depth 12)
try {
    for ($i=0; $i -lt $changed.Count; $i++) {
        $f=$changed[$i]
        if ((Hash $f.path) -cne $f.before_hash) { throw "Apply drift: $($f.path)" }
        WriteAtomic $f.path $f.text
        $receipt.files[$i].after_hash = Hash $f.path
        WriteAtomic $receiptFile ($receipt | ConvertTo-Json -Depth 12)
    }
    $receipt.status='filesystem_projected'
    WriteAtomic $receiptFile ($receipt | ConvertTo-Json -Depth 12)
}
catch {
    $failure = $_
    $receipt.status='apply_failed'; WriteAtomic $receiptFile ($receipt | ConvertTo-Json -Depth 12)
    $applied = @($receipt.files | Where-Object after_hash)
    try {
        for ($j=$applied.Count-1; $j -ge 0; $j--) { RestoreFile $applied[$j] }
        $receipt.status='rolled_back'
    }
    catch { $receipt.status='rollback_blocked' }
    WriteAtomic $receiptFile ($receipt | ConvertTo-Json -Depth 12)
    throw "Apply failed ($($failure.Exception.Message)); $($receipt.status). Receipt: $receiptFile"
}
@{preset=$Preset;host=$ExecutionHost;active_presets=$activePresets;scope=$projectionScope;receipt=$receiptFile;changed=$changed.Count;capability=$capability;host_loaded=$false;execution_boundary='Codex projects named model-pinned native slots and tuple roles; Start-ModelSlot.ps1 is a separate explicitly invoked one-shot CLI path'} | ConvertTo-Json -Depth 12
