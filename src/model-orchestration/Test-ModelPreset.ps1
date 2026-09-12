#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$count = 0
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message }; $script:count++ }
$policy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'presets.json') -Raw | ConvertFrom-Json -AsHashtable
$expected = @{
    gpt6_astra_only=@('gpt-6-astra','low','medium','high')
    gpt56_sol_only=@('gpt-5.6-sol','low','medium','high')
    gpt56_terra_only=@('gpt-5.6-terra','high','xhigh','max')
    gpt56_luna_only=@('gpt-5.6-luna','high','xhigh','max')
    glm53_flash_only=@('glm-5.3-flash','low','high','max')
    deepseek_flash_only=@('deepseek-flash','high','high','max')
}
Assert ($policy.presets.Count -eq 6 -and $policy.slots.Count -eq 5) 'Preset/slot count'
foreach ($id in $expected.Keys) {
    $resolved = & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve -Preset $id | ConvertFrom-Json -AsHashtable
    foreach ($slot in $policy.slots.Keys) {
        $index = @('light','standard','deep').IndexOf($policy.slots[$slot]) + 1
        Assert ($resolved.routes[$slot].model -ceq $expected[$id][0] -and $resolved.routes[$slot].effort -ceq $expected[$id][$index]) "Wrong route: $id/$slot"
    }
}
$selected = & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve -AvailablePreset gpt56_luna_only,gpt56_sol_only | ConvertFrom-Json
Assert ($selected.preset -eq 'gpt56_sol_only') 'Ordered selection'
$cliSelection = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Slot standard_review -AvailablePreset 'gpt56_luna_only,gpt56_sol_only' -Plan | ConvertFrom-Json
Assert ($LASTEXITCODE -eq 0 -and $cliSelection.preset -eq 'gpt56_sol_only' -and $cliSelection.effort -eq 'medium' -and $cliSelection.delegation_enabled -eq $false) 'Native CLI available-set binding'
foreach ($id in @($policy.codex_order) + @('deepseek_flash_only')) {
    foreach ($slot in $policy.slots.Keys) {
        $plan = & (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Preset $id -Slot $slot -Plan | ConvertFrom-Json
        $p = $policy.presets[$id]
        $effort = $p.efforts[$policy.slots[$slot]]
        Assert ($plan.model -eq $p.model -and $plan.effort -eq $effort -and $plan.delegation_enabled -eq $false) 'Frozen route and delegation disabled'
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
    $claudeTarget = Join-Path $fixture 'claude'
    [IO.Directory]::CreateDirectory($claudeTarget) | Out-Null
    $settings = Join-Path $claudeTarget 'settings.json'
    [IO.File]::WriteAllText($settings, '{"model":"old","env":{"ANTHROPIC_BASE_URL":"preserve-endpoint","ANTHROPIC_AUTH_TOKEN":"test-sentinel"},"permissions":{"deny":["test-deny"]}}')
    $settingsBefore = (Get-FileHash -LiteralPath $settings).Hash
    $claudeReceipt = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -Preset deepseek_flash_only -ClaudeRoot $claudeTarget | ConvertFrom-Json
    $projected = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json
    Assert ($projected.env.ANTHROPIC_BASE_URL -eq 'preserve-endpoint' -and $projected.env.ANTHROPIC_AUTH_TOKEN -eq 'test-sentinel' -and $projected.permissions.deny[0] -eq 'test-deny') 'Claude unrelated config changed'
    Assert ($projected.model -eq 'deepseek-flash' -and $projected.effortLevel -eq 'high' -and $projected.env.CLAUDE_CODE_SUBAGENT_MODEL_FORCE -eq '1' -and $projected.availableModels.Count -eq 1 -and $projected.availableModels[0] -eq 'deepseek-flash') 'Claude family projection'
    Assert ((& (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Plan -Preset deepseek_flash_only -ClaudeRoot $claudeTarget | ConvertFrom-Json).files.Count -eq 0) 'Claude not idempotent'
    & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Rollback -ReceiptPath $claudeReceipt.receipt | Out-Null
    Assert ((Get-FileHash -LiteralPath $settings).Hash -ceq $settingsBefore) 'Claude rollback bytes'
}
finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    if (-not $resolvedFixture.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolvedFixture -Recurse
}
"PASS: $count assertions (routes, ordered selection, launcher delegation controls, no replay, projection idempotence, exact rollback)."
