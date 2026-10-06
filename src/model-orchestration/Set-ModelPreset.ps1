#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Resolve','Plan','Apply','Rollback')][string]$Action = 'Plan',
    [string]$Preset = '',
    [string[]]$AvailablePreset = @(),
    [string]$CodexRoot = $(if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { $env:CODEX_HOME } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex' }),
    [string]$ClaudeRoot = $(if (-not [string]::IsNullOrWhiteSpace($env:CLAUDE_CONFIG_DIR)) { $env:CLAUDE_CONFIG_DIR } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude' }),
    [string]$ReceiptPath = '',
    [switch]$SubagentsOnly
)
$ErrorActionPreference = 'Stop'
$policy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'presets.json') -Raw | ConvertFrom-Json -AsHashtable
# Fail closed on any malformed preset, not only the selected one: slot_map keys,
# index range, and menu population are the whole contract between menu and slots.
$slotNames = @($policy.slots)
if ($slotNames.Count -eq 0 -or @($slotNames | Select-Object -Unique).Count -ne $slotNames.Count) { throw 'Slots must be nonempty and unique.' }
foreach ($slot in $slotNames) { if ($slot -cnotmatch '^[a-z][a-z0-9_]*$') { throw "Invalid slot name: $slot" } }
if ('routine_maintenance' -cnotin $slotNames) { throw 'The default routine_maintenance slot is required.' }
foreach ($slot in @($policy.read_only_slots)) { if ($slot -cnotin $slotNames) { throw "Unknown read-only slot: $slot" } }
foreach ($id in $policy.presets.Keys) {
    $p = $policy.presets[$id]
    $menu = @($p.menu)
    if ($menu.Count -eq 0) { throw "Preset $id has an empty menu." }
    foreach ($entry in $menu) {
        if ($entry.model -cnotmatch '^[a-z0-9][a-z0-9.-]*$' -or $entry.effort -cnotin @('low','medium','high','max')) { throw "Invalid tuple in preset $id." }
    }
    # Failure re-selection uses menu indices as effort order.
    $effortOrder = @('low','medium','high','max')
    for ($index = 1; $index -lt $menu.Count; $index++) {
        if ($menu[$index].model -cne $menu[0].model -or
            [array]::IndexOf($effortOrder, $menu[$index].effort) -le [array]::IndexOf($effortOrder, $menu[$index - 1].effort)) {
            throw "Preset $id menu must use one model with strictly increasing effort."
        }
    }
    $hosts = @($p.hosts)
    if ($hosts.Count -eq 0 -or ($hosts | Where-Object { $_ -cnotin @('codex','claude','zcode') })) { throw "Preset $id has invalid hosts." }
    if (-not $p.slot_map -or @($p.slot_map.Keys).Count -ne $slotNames.Count) { throw "Preset $id slot_map must cover exactly all slots." }
    foreach ($slot in $slotNames) {
        if (-not $p.slot_map.Contains($slot)) { throw "Preset $id is missing slot mapping: $slot" }
        $idx = $p.slot_map[$slot]
        if ($idx -isnot [int] -and $idx -isnot [long]) { throw "Preset $id slot index must be an integer: $slot" }
        if ($idx -lt 0 -or $idx -ge $menu.Count) { throw "Preset $id slot index out of range: $slot -> $idx" }
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
if (-not $policy.presets.Contains($Preset)) { throw 'Unknown preset.' }
# Deterministic availability re-selection contract, derived from the active
# pool (never hard-coded model names).  Rate-limit/quota/auth failures must not
# escalate effort (a higher effort spends more tokens against the same limit);
# only confirmed service overload/unavailability may try a higher effort.
function Get-ReselectionContract($Policy, [string[]]$ActiveIds) {
    $menus = [ordered]@{}
    foreach ($id in $ActiveIds) {
        $menus[$id] = @($Policy.presets[$id].menu | ForEach-Object { @{ model = [string]$_.model; effort = [string]$_.effort } })
    }
    return [ordered]@{
        rule = 'Parent re-selects for the NEXT bounded task; never hot-swap a running task; record failed tuple, failure, selected tuple and remaining scope.'
        rate_limit_order = @($ActiveIds | ForEach-Object { @{ preset = $_; menu = $menus[$_] } })
        overload_higher_effort_allowed_presets = @($ActiveIds)
        prohibition = 'No silent model aliasing, no effort substitution, no automatic replay; a 429/quota/rate-limit/auth/billing failure is never an effort escalation signal.'
    }
}
$reselectionContract = Get-ReselectionContract $policy $activePresets
$reselectionSummary = ('429/quota/auth: nearest lower effort within preset, then presets in order ' + (@($activePresets -join ' -> ')) + '; overload/unavailable: also nearest higher effort. Record failed tuple, failure, selected tuple, remaining scope; never hot-swap, alias, or escalate on rate limits.')
$modelPreset = $policy.presets[$Preset]
$routes = [ordered]@{}
foreach ($slot in $slotNames) {
    $entry = $modelPreset.menu[$modelPreset.slot_map[$slot]]
    $routes[$slot] = @{ model = $entry.model; effort = $entry.effort }
}
$enabledRoutes = @()
$roleNames = @($slotNames)
foreach ($id in $activePresets) {
    $prefix = $policy.role_prefixes[$id]
    if ($prefix -cnotmatch '^[a-z][a-z0-9_]*$') { throw "Invalid role prefix: $id" }
    foreach ($entry in $policy.presets[$id].menu) {
        $roleName = "$($prefix)_$($entry.effort)"
        if ($roleName -cin $roleNames) { throw "Duplicate execution role: $roleName" }
        $roleNames += $roleName
        $enabledRoutes += @{preset=$id;role=$roleName;model=$entry.model;effort=$entry.effort;hosts=@($policy.presets[$id].hosts)}
    }
}
if ($Action -eq 'Resolve') { @{ preset = $Preset; active_presets=$activePresets; hosts = @($modelPreset.hosts); routes = $routes; enabled_routes=$enabledRoutes; slots=$slotNames; read_only_slots=@($policy.read_only_slots); availability = 'operator_declared'; reselection = (Get-ReselectionContract $policy $activePresets) } | ConvertTo-Json -Depth 8; return }
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
# Only the codex/claude facets have a verified write interface; a preset whose
# hosts are zcode-only stays resolve-only (fail closed, never guessed writes).
if ('codex' -notin $modelPreset.hosts -and 'claude' -notin $modelPreset.hosts) { throw 'ZCode native model/effort write interface is not verified; resolve is available, native projection is blocked.' }
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
$files = [Collections.Generic.List[object]]::new()
function AddFile([string]$Path,[string]$Text) {
    $files.Add(@{path=[IO.Path]::GetFullPath($Path); text=$Text; before_hash=(Hash $Path)})
}
$profileNames = @{}
$projectionScope = if ($SubagentsOnly) { 'subagents_only' } else { 'full_preset' }
$slotGuidance = @{
    quick_triage = 'Select for a small read-only lookup or known error classification; downgrade here only after the remaining question is concrete and bounded.'
    routine_maintenance = 'Select for ordinary fixes with a known interface and local proof; upgrade the next bounded task to the deep slot if cross-module uncertainty remains.'
    standard_review = 'Select for read-only review of a bounded change; use the deep slot with an explicit read-only scope for architecture, security or unresolved cross-module questions.'
    bounded_implementation = 'Select for a scoped implementation with clear inputs, write set and proof; use the deep slot if interacting constraints remain unresolved.'
    deep_investigation_or_implementation = 'Select for unresolved cross-module root cause, architecture, security boundaries or complex implementation; missing input, auth errors and rate limits are not reasons to increase effort.'
    test_execution = 'Select for running scoped tests and diagnosing failures; the parent supplies the allowed command and verification boundary.'
    documentation_review = 'Select for read-only documentation and contract consistency checks.'
    architecture_review = 'Select for read-only architecture, interacting constraints or security boundary review.'
}
$tupleBlocks = [Collections.Generic.List[string]]::new()
foreach ($entry in $enabledRoutes) {
    if ('codex' -notin $entry.hosts) { continue }
    $rolePath = Join-Path $PSScriptRoot ".generated/codex/pool/$($entry.role).toml"
    $description = "Model pool role $($entry.role), $($entry.model)/$($entry.effort). Parent assigns the task slot, exact scope, write set, proof and stop; use only when this exact tuple is supported by the current host."
    $instructions = 'Execute the assigned bounded task and obey its read-only or write scope. Preserve unrelated work. Do not delegate, change models or replay completed writes. Return verification evidence and unresolved uncertainty to the parent, then stop.'
    $roleText = @("name = `"$($entry.role)`"", "description = `"$description`"", "model = `"$($entry.model)`"", "model_reasoning_effort = `"$($entry.effort)`"", "developer_instructions = `"$instructions`"", '', '[agents]', 'enabled = false', '') -join "`n"
    AddFile $rolePath $roleText
    $tupleBlocks.Add("[agents.$($entry.role)]`ndescription = `"$description`"`nconfig_file = '$($rolePath.Replace('\','/'))'`n")
}
if ('codex' -in $modelPreset.hosts) {
# Every preset with a codex facet gets a complete native profile, so the strict
# slot launcher can freeze any of them; codex_order presets come first.
$codexIds = @($policy.codex_order | Where-Object { 'codex' -in $policy.presets[$_].hosts })
foreach ($id in $policy.presets.Keys) { if ($id -cnotin $codexIds -and 'codex' -in $policy.presets[$id].hosts) { $codexIds += $id } }
foreach ($id in $codexIds) {
    $p = $policy.presets[$id]
    $profileNames[$id] = $id.Replace('_','-')
    $roleBlocks = [Collections.Generic.List[string]]::new()
    $standard = $p.menu[$p.slot_map['routine_maintenance']]
    foreach ($slot in $slotNames) {
        $entry = $p.menu[$p.slot_map[$slot]]
        $rolePath = Join-Path $PSScriptRoot ".generated/codex/$id/$slot.toml"
        $readOnly = $slot -cin @($policy.read_only_slots)
        $guidance = if ($slotGuidance.ContainsKey($slot)) { $slotGuidance[$slot] } else { 'Select for the configured bounded task; the parent supplies scope, proof and stop.' }
        $description = "Execution slot $slot, $($entry.model)/$($entry.effort). " + $(if ($readOnly) { 'Read-only evidence work. ' } else { 'Bounded implementation with proportionate verification. ' }) + $guidance + ' This is a default route; choose a supported model pool role for a different model/effort on this task.'
        $instructions = "Execute only the assigned $slot task within the supplied scope. Preserve unrelated changes. Do not delegate or change models. Return concrete evidence and any unresolved uncertainty for parent re-selection before a new bounded task. Do not replay completed writes. Stop at the assigned boundary."
        if ($readOnly) { $instructions += ' Do not modify files or external state.' }
        $roleText = @("name = `"$slot`"", "description = `"$description`"", "model = `"$($entry.model)`"", "model_reasoning_effort = `"$($entry.effort)`"", "developer_instructions = `"$instructions`"", '', '[agents]', 'enabled = false', '') -join "`n"
        AddFile $rolePath $roleText
        $roleBlocks.Add("[agents.$slot]`ndescription = `"$description`"`nconfig_file = '$($rolePath.Replace('\','/'))'`n")
    }
    $header = @("model = `"$($standard.model)`"", "review_model = `"$($standard.model)`"", "model_reasoning_effort = `"$($standard.effort)`"", "developer_instructions = `"Split work by dependencies and choose a named execution slot by task shape before dispatch. Select each child's model and effort independently from the supported tuples in the active model pool; different tasks may use different models simultaneously. Semantic slots are extensible and do not limit child count. Delegate only when explicitly authorized. Parallelize independently verifiable tasks with disjoint write sets and positive benefit within native concurrency limits. Preserve specialist execution contracts. Re-select for new bounded work without replaying completed writes. Missing input, auth errors and rate limits are not effort escalation triggers. Availability failures: stop the task with its evidence, then re-select for the next bounded task in fixed order - 429/quota/rate-limit/auth/billing: nearest lower effort within the same preset, then the next active preset; confirmed service overload/unavailable: nearest lower effort, then nearest higher effort, then cross-preset. Record the failed tuple, the failure, the selected tuple and remaining scope before re-dispatch. Spawn with bounded history. No gateway selection or task replay.`"", '', '[agents]', "default_subagent_model = `"$($standard.model)`"", "default_subagent_reasoning_effort = `"$($standard.effort)`"") -join "`n"
    $profileText = $header + "`n`n" + ($roleBlocks -join "`n") + "`n" + ($tupleBlocks -join "`n")
    AddFile (Join-Path $CodexRoot "$($profileNames[$id]).config.toml") $profileText
    if ($id -ceq $Preset) { $activeBlocks = $roleBlocks -join "`n" }
}
$configPath = Join-Path $CodexRoot 'config.toml'
$standard = $modelPreset.menu[$modelPreset.slot_map['routine_maintenance']]
$config = [IO.File]::ReadAllText($configPath)
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
$config = SetScalar $config 'agents' 'default_subagent_model' ('"'+$standard.model+'"')
$config = SetScalar $config 'agents' 'default_subagent_reasoning_effort' ('"'+$standard.effort+'"')
$config = $config.TrimEnd() + "`n# model-orchestration begin`n# availability-rules: $reselectionSummary`n$activeBlocks`n$($tupleBlocks -join "`n")`n# model-orchestration end`n"
AddFile $configPath $config
}
# Not elseif: a preset may carry both facets (deepseek projects Claude Code and
# the shared codex surface in one Apply).
if ('claude' -in $modelPreset.hosts) {
    $ClaudeRoot = [IO.Path]::GetFullPath($ClaudeRoot)
    $standard = $modelPreset.menu[$modelPreset.slot_map['routine_maintenance']]
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
        $entry = $modelPreset.menu[$modelPreset.slot_map[$slot]]
        $body = @('---',"name: $name", "description: $slot execution slot using $($entry.model) at $($entry.effort) effort. $($slotGuidance[$slot])", "model: $($entry.model)", "effort: $($entry.effort)", 'disallowedTools: Agent', '---', '', 'Perform only the assigned bounded task. Preserve unrelated work. Return concrete verification evidence and unresolved uncertainty for parent re-selection before a new bounded task. Do not replay completed writes, change models or delegate.')
        if ($slot -cin @($policy.read_only_slots)) { $body += 'Read-only: do not modify files or external state.' }
        AddFile (Join-Path $ClaudeRoot "agents/$name.md") (($body -join "`n")+"`n")
    }
}
$changed = @($files | Where-Object { -not (Test-Path -LiteralPath $_.path) -or [IO.File]::ReadAllText($_.path).Replace("`r`n","`n") -cne $_.text.Replace("`r`n","`n") })
if ($Action -eq 'Plan') { @{preset=$Preset; active_presets=$activePresets; enabled_routes=$enabledRoutes; scope=$projectionScope; files=@($changed | ForEach-Object { @{path=$_.path;before_hash=$_.before_hash} }); routes=$routes; reselection=$reselectionContract; gateway_changes=0} | ConvertTo-Json -Depth 8; return }
if ($changed.Count -eq 0) { 'No changes.'; return }
$run = Join-Path $stateRoot ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
[IO.Directory]::CreateDirectory($run) | Out-Null
$receipt = @{schema_version=2;preset=$Preset;active_presets=$activePresets;scope=$projectionScope;status='prepared';files=@()}
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
@{preset=$Preset;active_presets=$activePresets;scope=$projectionScope;receipt=$receiptFile;changed=$changed.Count;host_loaded=$false;execution_boundary='Start-ModelSlot.ps1 freezes one child route and disables nested delegation'} | ConvertTo-Json
