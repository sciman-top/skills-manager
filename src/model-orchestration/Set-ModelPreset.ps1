#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Resolve','Plan','Apply','Rollback')][string]$Action = 'Plan',
    [string]$Preset = 'gpt6_astra_only',
    [string[]]$AvailablePreset = @(),
    [string]$CodexRoot = (Join-Path $env:USERPROFILE '.codex'),
    [string]$ClaudeRoot = (Join-Path $env:USERPROFILE '.claude'),
    [string]$ReceiptPath = ''
)
$ErrorActionPreference = 'Stop'
$policy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'presets.json') -Raw | ConvertFrom-Json -AsHashtable
$AvailablePreset = @($AvailablePreset | ForEach-Object { $_.Split(',', [StringSplitOptions]::TrimEntries) })
if ($AvailablePreset.Count -gt 0) {
    foreach ($id in $AvailablePreset) { if ($policy.codex_order -cnotcontains $id) { throw "Unknown Codex preset: $id" } }
    $selected = @($policy.codex_order | Where-Object { $AvailablePreset -ccontains $_ })
    if ($selected.Count -eq 0) { throw 'No available preset.' }
    $Preset = $selected[0]
}
if (-not $policy.presets.Contains($Preset)) { throw 'Unknown preset.' }
$modelPreset = $policy.presets[$Preset]
$routes = [ordered]@{}
foreach ($slot in $policy.slots.Keys) { $routes[$slot] = @{ model = $modelPreset.model; effort = $modelPreset.efforts[$policy.slots[$slot]] } }
if ($Action -eq 'Resolve') { @{ preset = $Preset; routes = $routes; availability = 'operator_declared' } | ConvertTo-Json -Depth 8; return }
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
    if ((Hash $File.path) -cne $File.after_hash) { throw "Rollback drift: $($File.path)" }
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
        if ((Hash $f.path) -cne $f.after_hash) { throw "Rollback drift: $($f.path)" }
        if ($f.before_hash -and (Hash $f.backup) -cne $f.before_hash) { throw 'Backup hash mismatch.' }
    }
    foreach ($f in @($receipt.files)[($receipt.files.Count-1)..0]) { RestoreFile $f }
    'Rollback complete.'; return
}
if ($modelPreset.host -eq 'zcode') { throw 'ZCode native model/effort write interface is not verified; resolve is available, native projection is blocked.' }
function SetScalar([string]$Text,[string]$Section,[string]$Key,[string]$Value) {
    # Only edit known flat scalar keys; unfamiliar TOML shapes are rejected.
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in ($Text -split '\r?\n')) { $lines.Add($line) }
    $start = 0; $end = $lines.Count
    if ($Section) {
        $headers = @(0..($lines.Count-1) | Where-Object { $lines[$_] -cmatch ('^\[' + [regex]::Escape($Section) + '\]\s*$') })
        if ($headers.Count -ne 1) { throw "Expected one [$Section] section." }
        $start = $headers[0] + 1
    }
    for ($i=$start; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*\[') { $end=$i; break } }
    $hits = @($start..($end-1) | Where-Object { $lines[$_] -match ('^\s*' + [regex]::Escape($Key) + '\s*=') })
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
if ($modelPreset.host -eq 'codex') {
foreach ($id in $policy.codex_order) {
    $p = $policy.presets[$id]
    $profileNames[$id] = $id.Replace('_','-')
    $roleBlocks = [Collections.Generic.List[string]]::new()
    foreach ($slot in $policy.slots.Keys) {
        $tier = $policy.slots[$slot]; $effort = $p.efforts[$tier]
        $rolePath = Join-Path $PSScriptRoot ".generated/codex/$id/$slot.toml"
        $readOnly = $slot -in @('quick_triage','standard_review')
        $description = "Execution slot $slot, $($p.model)/$effort. " + $(if ($readOnly) { 'Read-only evidence work.' } else { 'Bounded implementation with proportionate verification.' })
        $instructions = "Execute only the assigned $slot task within the supplied scope. Preserve unrelated changes. Do not delegate or change models. Return concrete evidence and stop at the assigned boundary."
        if ($readOnly) { $instructions += ' Do not modify files or external state.' }
        $roleText = @("name = `"$slot`"", "description = `"$description`"", "model = `"$($p.model)`"", "model_reasoning_effort = `"$effort`"", "developer_instructions = `"$instructions`"", '', '[agents]', 'enabled = false', '') -join "`n"
        AddFile $rolePath $roleText
        $roleBlocks.Add("[agents.$slot]`ndescription = `"$description`"`nconfig_file = '$($rolePath.Replace('\','/'))'`n")
    }
    $header = @("model = `"$($p.model)`"", "review_model = `"$($p.model)`"", "model_reasoning_effort = `"$($p.efforts.standard)`"", "developer_instructions = `"Use only the five named execution slots from this preset. Never mix model families. Spawn with bounded history (fork_turns=none or an explicit positive count), not all. No gateway selection or task replay. Slot effort is mandatory.`"", '', '[agents]', "default_subagent_model = `"$($p.model)`"", "default_subagent_reasoning_effort = `"$($p.efforts.standard)`"") -join "`n"
    $profileText = $header + "`n`n" + ($roleBlocks -join "`n")
    AddFile (Join-Path $CodexRoot "$($profileNames[$id]).config.toml") $profileText
    if ($id -ceq $Preset) { $activeBlocks = $roleBlocks -join "`n" }
}
$configPath = Join-Path $CodexRoot 'config.toml'
$config = [IO.File]::ReadAllText($configPath)
$config = [regex]::Replace($config, '(?ms)^# model-orchestration begin\r?\n.*?^# model-orchestration end\r?\n?', '')
$config = SetScalar $config '' 'model' ('"'+$modelPreset.model+'"')
$config = SetScalar $config '' 'review_model' ('"'+$modelPreset.model+'"')
$config = SetScalar $config '' 'model_reasoning_effort' ('"'+$modelPreset.efforts.standard+'"')
$config = SetScalar $config 'agents' 'default_subagent_model' ('"'+$modelPreset.model+'"')
$config = SetScalar $config 'agents' 'default_subagent_reasoning_effort' ('"'+$modelPreset.efforts.standard+'"')
$config = $config.TrimEnd() + "`n# model-orchestration begin`n$activeBlocks`n# model-orchestration end`n"
AddFile $configPath $config
}
elseif ($modelPreset.host -eq 'claude') {
    $ClaudeRoot = [IO.Path]::GetFullPath($ClaudeRoot)
    $settingsPath = Join-Path $ClaudeRoot 'settings.json'
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -AsHashtable
    if (-not $settings.Contains('env')) { $settings.env = [ordered]@{} }
    $settings.model = $modelPreset.model
    $settings.availableModels = @($modelPreset.model)
    $settings.effortLevel = $modelPreset.efforts.standard
    foreach ($key in @('ANTHROPIC_MODEL','ANTHROPIC_DEFAULT_MODEL','ANTHROPIC_DEFAULT_FABLE_MODEL','ANTHROPIC_DEFAULT_OPUS_MODEL','ANTHROPIC_DEFAULT_SONNET_MODEL','ANTHROPIC_DEFAULT_HAIKU_MODEL','CLAUDE_CODE_SUBAGENT_MODEL')) { $settings.env[$key] = $modelPreset.model }
    $settings.env.CLAUDE_CODE_SUBAGENT_MODEL_FORCE = '1'
    $settings.env.CLAUDE_CODE_EFFORT_LEVEL = $modelPreset.efforts.standard
    AddFile $settingsPath ($settings | ConvertTo-Json -Depth 80)
    foreach ($slot in $policy.slots.Keys) {
        $name = $slot.Replace('_','-')
        $effort = $modelPreset.efforts[$policy.slots[$slot]]
        $body = @('---',"name: $name", "description: $slot execution slot using DeepSeek V4.1 Flash at $effort effort.", "model: $($modelPreset.model)", "effort: $effort", 'disallowedTools: Agent', '---', '', 'Perform only the assigned bounded task. Preserve unrelated work. Return concrete verification evidence. Do not change models or delegate.')
        if ($slot -in @('quick_triage','standard_review')) { $body += 'Read-only: do not modify files or external state.' }
        AddFile (Join-Path $ClaudeRoot "agents/$name.md") (($body -join "`n")+"`n")
    }
}
$changed = @($files | Where-Object { -not (Test-Path -LiteralPath $_.path) -or [IO.File]::ReadAllText($_.path).Replace("`r`n","`n") -cne $_.text.Replace("`r`n","`n") })
if ($Action -eq 'Plan') { @{preset=$Preset; files=@($changed | ForEach-Object { @{path=$_.path;before_hash=$_.before_hash} }); routes=$routes; gateway_changes=0} | ConvertTo-Json -Depth 8; return }
if ($changed.Count -eq 0) { 'No changes.'; return }
$run = Join-Path $stateRoot ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
[IO.Directory]::CreateDirectory($run) | Out-Null
$receipt = @{schema_version=1;preset=$Preset;status='prepared';files=@()}
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
@{preset=$Preset;receipt=$receiptFile;changed=$changed.Count;host_loaded=$false;execution_boundary='Start-ModelSlot.ps1 disables native delegation'} | ConvertTo-Json
