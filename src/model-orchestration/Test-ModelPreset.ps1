#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$count = 0
function global:claude {
    $global:ModelSlotCapturedArgs = @($args)
    $global:LASTEXITCODE = 0
}
try {
    & (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Preset deepseek_flash_only -Slot quick_triage -Prompt 'argument boundary test'
    if ($global:ModelSlotCapturedArgs[-2] -cne '--' -or $global:ModelSlotCapturedArgs[-1] -notlike '*argument boundary test') { throw 'Claude prompt must follow option terminator.' }
    if ($global:ModelSlotCapturedArgs -notcontains 'Read,Glob,Grep' -or $global:ModelSlotCapturedArgs -notcontains 'Agent') { throw 'Claude tool restrictions missing.' }
    $count += 2
}
finally {
    Remove-Item Function:/claude
    Remove-Variable ModelSlotCapturedArgs -Scope Global -ErrorAction SilentlyContinue
}
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message }; $script:count++ }
$policy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'presets.json') -Raw | ConvertFrom-Json -AsHashtable
$slots = @($policy.slots)
$expected = @{
    gpt56_sol_terra     = @{ menu = @(@('gpt-5.6-terra','high'),@('gpt-5.6-terra','xhigh'),@('gpt-5.6-sol','medium')); map = @{quick_triage=0;routine_maintenance=1;standard_review=1;bounded_implementation=1;deep_investigation_or_implementation=2} }
    gpt56_luna_only     = @{ menu = @(@('gpt-5.6-luna','high'),@('gpt-5.6-luna','xhigh')); map = @{quick_triage=0;routine_maintenance=0;standard_review=0;bounded_implementation=0;deep_investigation_or_implementation=1} }
    glm53_flash_only    = @{ menu = @(@('glm-5.3-flash','high'),@('glm-5.3-flash','max')); map = @{quick_triage=0;routine_maintenance=0;standard_review=0;bounded_implementation=0;deep_investigation_or_implementation=1} }
    deepseek_flash_only = @{ menu = @(@('deepseek-flash','high'),@('deepseek-flash','max')); map = @{quick_triage=0;routine_maintenance=0;standard_review=0;bounded_implementation=0;deep_investigation_or_implementation=1} }
}
Assert ($policy.presets.Count -eq 4 -and $slots.Count -eq 5) 'Preset/slot count'
Assert (('codex' -in $policy.presets['glm53_flash_only'].hosts) -and ('claude' -in $policy.presets['deepseek_flash_only'].hosts) -and ('codex' -in $policy.presets['deepseek_flash_only'].hosts)) 'Dual-host facets'
foreach ($id in $expected.Keys) {
    $resolved = & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve -Preset $id | ConvertFrom-Json -AsHashtable
    foreach ($slot in $slots) {
        $pair = $expected[$id].menu[$expected[$id].map[$slot]]
        Assert ($resolved.routes[$slot].model -ceq $pair[0] -and $resolved.routes[$slot].effort -ceq $pair[1]) "Wrong route: $id/$slot"
    }
}
$selected = & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve -AvailablePreset gpt56_luna_only,gpt56_sol_terra | ConvertFrom-Json
Assert ($selected.preset -eq 'gpt56_sol_terra') 'Ordered selection'
$cliSelection = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Slot standard_review -AvailablePreset 'gpt56_luna_only,gpt56_sol_terra' -Plan | ConvertFrom-Json
Assert ($LASTEXITCODE -eq 0 -and $cliSelection.preset -eq 'gpt56_sol_terra' -and $cliSelection.effort -eq 'xhigh' -and $cliSelection.delegation_enabled -eq $false) 'Native CLI available-set binding'
foreach ($id in @($policy.codex_order) + @('glm53_flash_only') + @('deepseek_flash_only')) {
    foreach ($slot in $slots) {
        $plan = & (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Preset $id -Slot $slot -Plan | ConvertFrom-Json
        $pair = $expected[$id].menu[$expected[$id].map[$slot]]
        Assert ($plan.model -eq $pair[0] -and $plan.effort -eq $pair[1] -and $plan.delegation_enabled -eq $false) 'Frozen route and delegation disabled'
    }
}
$launcher = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Raw
Assert ($launcher.Contains('no replay or preset substitution performed') -and $launcher.Contains('No arbitrary CLI pass-through')) 'Failed task must not replay'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('model-preset-test-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
try {
    foreach ($name in @('Set-ModelPreset.ps1','presets.json')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $fixture }
    $target = Join-Path $fixture 'codex'
    [IO.Directory]::CreateDirectory($target) | Out-Null
    $cfg = Join-Path $target 'config.toml'
    $original = "model = `"old`"`r`nmodel_provider = `"preserve-provider`"`r`n[agents]`r`nenabled = true`r`nmax_concurrent_threads_per_session = 2`r`n"
    [IO.File]::WriteAllText($cfg,$original,[Text.UTF8Encoding]::new($true))
    $before = (Get-FileHash -LiteralPath $cfg).Hash
    $receipt = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -CodexRoot $target | ConvertFrom-Json
    Assert ((Get-Content -LiteralPath $cfg -Raw).Contains('preserve-provider')) 'Provider changed'
    Assert (-not (Test-Path -LiteralPath (Join-Path $target 'hooks.json'))) 'Projection must not install hooks'
    Assert ((& (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Plan -CodexRoot $target | ConvertFrom-Json).files.Count -eq 0) 'Not idempotent'
    & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Rollback -CodexRoot $target -ReceiptPath $receipt.receipt | Out-Null
    Assert ((Get-FileHash -LiteralPath $cfg).Hash -ceq $before) 'Rollback must restore exact bytes including BOM'
    $emptyRoot = "[agents]`n[unrelated]`nmodel = `"preserve-other-section`""
    [IO.File]::WriteAllText($cfg, $emptyRoot)
    $emptyRootReceipt = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -CodexRoot $target | ConvertFrom-Json
    $emptyRootResult = Get-Content -LiteralPath $cfg -Raw
    Assert ($emptyRootResult.StartsWith('model = "gpt-5.6-terra"')) 'Empty root must receive its own model key'
    Assert ($emptyRootResult.Contains("[unrelated]`nmodel = `"preserve-other-section`"")) 'Empty root must preserve other sections'
    & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Rollback -CodexRoot $target -ReceiptPath $emptyRootReceipt.receipt | Out-Null
    Assert ((Get-Content -LiteralPath $cfg -Raw) -ceq $emptyRoot) 'Empty-root rollback must restore original content'
    $claudeTarget = Join-Path $fixture 'claude'
    [IO.Directory]::CreateDirectory($claudeTarget) | Out-Null
    $settings = Join-Path $claudeTarget 'settings.json'
    [IO.File]::WriteAllText($settings, '{"model":"old","env":{"ANTHROPIC_BASE_URL":"preserve-endpoint","ANTHROPIC_AUTH_TOKEN":"test-sentinel"},"permissions":{"deny":["test-deny"]}}')
    $settingsBefore = (Get-FileHash -LiteralPath $settings).Hash
    $claudeReceipt = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -Preset deepseek_flash_only -ClaudeRoot $claudeTarget -CodexRoot $target | ConvertFrom-Json
    $projected = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json
    Assert ($projected.env.ANTHROPIC_BASE_URL -eq 'preserve-endpoint' -and $projected.env.ANTHROPIC_AUTH_TOKEN -eq 'test-sentinel' -and $projected.permissions.deny[0] -eq 'test-deny') 'Claude unrelated config changed'
    Assert ($projected.model -eq 'deepseek-flash' -and $projected.effortLevel -eq 'high' -and $projected.env.CLAUDE_CODE_SUBAGENT_MODEL_FORCE -eq '1' -and $projected.availableModels.Count -eq 1 -and $projected.availableModels[0] -eq 'deepseek-flash') 'Claude family projection'
    Assert ((& (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Plan -Preset deepseek_flash_only -ClaudeRoot $claudeTarget -CodexRoot $target | ConvertFrom-Json).files.Count -eq 0) 'Claude not idempotent'
    & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Rollback -ReceiptPath $claudeReceipt.receipt | Out-Null
    Assert ((Get-FileHash -LiteralPath $settings).Hash -ceq $settingsBefore) 'Claude rollback bytes'
    $badText = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'presets.json') -Raw) -replace '"deep_investigation_or_implementation": \d+', '"deep_investigation_or_implementation": 9'
    [IO.File]::WriteAllText((Join-Path $fixture 'presets.json'), $badText)
    $threw = $false
    try { & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Resolve | Out-Null } catch { $threw = $true }
    Assert $threw 'Out-of-range slot index must fail closed'
}
finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    if (-not $resolvedFixture.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolvedFixture -Recurse
}
"PASS: $count assertions (routes, ordered selection, launcher delegation controls, no replay, projection idempotence, exact rollback)."
