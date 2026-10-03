#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$count = 0
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message }; $script:count++ }
$policy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'presets.json') -Raw | ConvertFrom-Json -AsHashtable
$slots = @($policy.slots)
$expected = @{
    gpt61_sol_only     = @{ menu = @(@('gpt-6.1-sol','low'),@('gpt-6.1-sol','medium'),@('gpt-6.1-sol','high')); map = @{quick_triage=0;routine_maintenance=1;standard_review=1;bounded_implementation=1;deep_investigation_or_implementation=2;test_execution=1;documentation_review=0;architecture_review=2} }
    gpt6_luna_only     = @{ menu = @(,@('gpt-6-luna','max')); map = @{quick_triage=0;routine_maintenance=0;standard_review=0;bounded_implementation=0;deep_investigation_or_implementation=0;test_execution=0;documentation_review=0;architecture_review=0} }
    glm53_flash_only    = @{ menu = @(@('glm-5.3-flash','high'),@('glm-5.3-flash','max')); map = @{quick_triage=0;routine_maintenance=0;standard_review=0;bounded_implementation=0;deep_investigation_or_implementation=1;test_execution=0;documentation_review=0;architecture_review=1} }
}
Assert ($policy.presets.Count -eq 3 -and $slots.Count -gt 3) 'Three models and multiple slots'
Assert (('codex' -in $policy.presets['glm53_flash_only'].hosts) -and ('zcode' -in $policy.presets['glm53_flash_only'].hosts)) 'GLM host facets'
foreach ($id in $expected.Keys) {
    $resolved = & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve -Preset $id | ConvertFrom-Json -AsHashtable
    foreach ($slot in $slots) {
        $pair = $expected[$id].menu[$expected[$id].map[$slot]]
        Assert ($resolved.routes[$slot].model -ceq $pair[0] -and $resolved.routes[$slot].effort -ceq $pair[1]) "Wrong route: $id/$slot"
    }
}
$defaultResolved = & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve | ConvertFrom-Json
Assert ($defaultResolved.preset -ceq $policy.default_preset -and $defaultResolved.preset -ceq 'gpt61_sol_only') 'Default comes from policy'
Assert ($defaultResolved.active_presets.Count -eq 3 -and $defaultResolved.enabled_routes.Count -eq 6) 'All three models and six tuples jointly active'
$reselection = $defaultResolved.reselection
Assert ($null -ne $reselection -and @($reselection.rate_limit_order).Count -eq 3) 'Reselection contract derives from the active pool'
Assert ((@($reselection.rate_limit_order | Where-Object { $_.preset -ceq 'gpt6_luna_only' })[0].menu | ForEach-Object { $_.effort }) -ccontains 'max') 'Single-effort preset has no lower-effort entry in the reselection contract'
Assert ($reselection.prohibition.Contains('429') -and $reselection.prohibition.Contains('never')) 'Reselection prohibition pins rate-limit semantics'
Assert (@($defaultResolved.enabled_routes.model | Select-Object -Unique).Count -eq 3) 'Pool includes distinct model families'
Assert ('deepseek-flash' -cnotin @($defaultResolved.enabled_routes.model)) 'DeepSeek removed from active pool'
$selected = & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve -AvailablePreset gpt6_luna_only,gpt61_sol_only | ConvertFrom-Json
Assert ($selected.preset -eq 'gpt61_sol_only') 'Ordered selection'
Assert ($selected.active_presets.Count -eq 2 -and $selected.enabled_routes.Count -eq 4) 'AvailablePreset retains the whole selected pool'
$cliSelection = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Slot standard_review -AvailablePreset 'gpt6_luna_only,gpt61_sol_only' -Plan | ConvertFrom-Json
Assert ($LASTEXITCODE -eq 0 -and $cliSelection.preset -eq 'gpt61_sol_only' -and $cliSelection.effort -eq 'medium' -and $cliSelection.delegation_enabled -eq $false) 'Native CLI available-set binding'
foreach ($legacyId in $policy.aliases.Keys) {
    $legacyResolved = & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve -Preset $legacyId | ConvertFrom-Json
    Assert ($legacyResolved.preset -ceq $policy.aliases[$legacyId]) 'Legacy preset alias'
}
$legacySelection = & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve -AvailablePreset gpt56_luna_only,gpt56_sol_terra | ConvertFrom-Json
Assert ($legacySelection.preset -ceq 'gpt61_sol_only') 'Legacy available-set aliases'
foreach ($id in @($policy.active_presets)) {
    foreach ($slot in $slots) {
        $plan = & (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Preset $id -Slot $slot -Plan | ConvertFrom-Json
        $pair = $expected[$id].menu[$expected[$id].map[$slot]]
        Assert ($plan.model -eq $pair[0] -and $plan.effort -eq $pair[1] -and $plan.delegation_enabled -eq $false) 'Frozen route and delegation disabled'
    }
}
foreach ($entry in $defaultResolved.enabled_routes) {
    foreach ($slot in $slots) {
        $plan = & (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Slot $slot -Model $entry.model -Effort $entry.effort -Plan | ConvertFrom-Json
        Assert ($plan.model -ceq $entry.model -and $plan.effort -ceq $entry.effort -and $plan.delegation_enabled -eq $false) 'Every slot can use every pool tuple'
        Assert ($plan.read_only -eq ($slot -cin @($policy.read_only_slots))) 'Cross-model selection retains slot read-only boundary'
    }
}
foreach ($invalidSelection in @(
    @{Slot='standard_review';Model='deepseek-flash';Effort='high'},
    @{Slot='standard_review';Model='gpt-6.1-sol';Effort='max'},
    @{Slot='standard_review';Model='gpt-6-luna'},
    @{Slot='unknown_slot'},
    @{Slot='standard_review';Preset='deepseek_flash_only'},
    @{Slot='standard_review';AvailablePreset=@('gpt61_sol_only');Model='gpt-6-luna';Effort='max'}
)) {
    $rejected = $false
    try { & (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') @invalidSelection -Plan | Out-Null } catch { $rejected = $true }
    Assert $rejected 'Reject removed, incomplete or out-of-pool selection'
}
$deepReadOnly = & (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Slot deep_investigation_or_implementation -ReadOnly -Model gpt-6-luna -Effort max -Plan | ConvertFrom-Json
Assert $deepReadOnly.read_only 'Deep cross-model review supports explicit read-only scope'
$launcher = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Raw
Assert ($launcher.Contains('no replay or preset substitution performed') -and $launcher.Contains('No arbitrary CLI pass-through')) 'Failed task must not replay'
if (Test-Path Function:/global:codex) { throw 'Cannot install acceptance mock over an existing global codex function.' }
$global:ModelSlotAcceptanceCalls = [Collections.Generic.List[object]]::new()
$global:ModelSlotAcceptanceExitCode = 1
function global:codex {
    $global:ModelSlotAcceptanceCalls.Add(@($args))
    $global:LASTEXITCODE = $global:ModelSlotAcceptanceExitCode
    if ($global:ModelSlotAcceptanceExitCode -ne 0) { '{"type":"turn.failed","error":{"message":"429 Too Many Requests (simulated)"}}' }
    else { '{"type":"turn.completed"}' }
}
try {
    $failedRequest = $false
    $failureMessage = ''
    try {
        & (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Slot architecture_review -Model gpt-6.1-sol -Effort high -ReadOnly -Prompt 'Simulated unavailable request' | Out-Null
    }
    catch {
        $failureMessage = $_.Exception.Message
        $failedRequest = $failureMessage -like '*no replay or preset substitution performed*'
    }
    Assert $failedRequest 'Simulated 429 returns control to the caller'
    $jsonMatch = [regex]::Match($failureMessage, '\{.*\}')
    Assert $jsonMatch.Success 'Failure message embeds the structured slot_failure document'
    $slotFailure = $jsonMatch.Value | ConvertFrom-Json
    Assert ($null -ne $slotFailure.slot_failure) 'Failure emits a structured slot_failure document'
    Assert ($slotFailure.slot_failure.failed_tuple.model -ceq 'gpt-6.1-sol' -and $slotFailure.slot_failure.failed_tuple.effort -ceq 'high') 'slot_failure records the exact failed tuple'
    $lowerEfforts = @($slotFailure.slot_failure.reselection.within_preset_lower | ForEach-Object { $_.effort })
    Assert ($lowerEfforts.Count -eq 2 -and $lowerEfforts[0] -ceq 'medium' -and $lowerEfforts[1] -ceq 'low') 'Rate-limit chain starts with nearest lower effort in the same preset'
    Assert (@($slotFailure.slot_failure.reselection.cross_preset | Where-Object { $_.preset -ceq 'gpt6_luna_only' }).Count -eq 1) 'Rate-limit chain continues cross-preset in active order'
    Assert (@($slotFailure.slot_failure.reselection.within_preset_higher_overload_only | ForEach-Object { $_.effort }) -cnotcontains 'high') 'The failed effort itself is never listed as a reselection option'
    Assert ($slotFailure.slot_failure.reselection.prohibition.Contains('429')) 'Prohibition text pins rate-limit semantics'
    Assert ($global:ModelSlotAcceptanceCalls.Count -eq 1) 'Failed request does not automatically launch another route'
    Assert ($global:ModelSlotAcceptanceCalls[0] -ccontains 'model_reasoning_effort="high"') 'Failed request retains its exact effort'
    $global:ModelSlotAcceptanceExitCode = 0
    & (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Slot architecture_review -Model gpt-6.1-sol -Effort medium -ReadOnly -Prompt 'Explicit remaining read-only work after simulated 429' | Out-Null
    Assert ($global:ModelSlotAcceptanceCalls.Count -eq 2 -and $global:ModelSlotAcceptanceCalls[1] -ccontains 'model_reasoning_effort="medium"') 'Caller can explicitly select a lower effort after failure'
    & (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Slot architecture_review -Model gpt-6-luna -Effort max -ReadOnly -Prompt 'Explicit remaining read-only work on another supported model after simulated 429' | Out-Null
    Assert ($global:ModelSlotAcceptanceCalls.Count -eq 3 -and $global:ModelSlotAcceptanceCalls[2] -ccontains 'model="gpt-6-luna"' -and $global:ModelSlotAcceptanceCalls[2] -ccontains 'model_reasoning_effort="max"') 'Caller can explicitly reselect another supported model after failure'
    & (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Slot architecture_review -Model gpt-6.1-sol -Effort high -ReadOnly -Prompt 'New independent higher-effort task' | Out-Null
    Assert ($global:ModelSlotAcceptanceCalls.Count -eq 4 -and $global:ModelSlotAcceptanceCalls[3] -ccontains 'model_reasoning_effort="high"') 'Caller can explicitly select higher effort for new work'
    foreach ($capturedCall in $global:ModelSlotAcceptanceCalls) {
        Assert ($capturedCall -ccontains 'read-only' -and $capturedCall -ccontains 'agents.enabled=false') 'Reselection preserves read-only mode and disabled nested delegation'
    }
}
finally {
    Remove-Item Function:/global:codex
    Remove-Variable ModelSlotAcceptanceCalls,ModelSlotAcceptanceExitCode -Scope Global -ErrorAction SilentlyContinue
}
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('model-preset-test-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
try {
    foreach ($name in @('Set-ModelPreset.ps1','Start-ModelSlot.ps1','presets.json')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $fixture }
    $target = Join-Path $fixture 'codex'
    [IO.Directory]::CreateDirectory($target) | Out-Null
    $cfg = Join-Path $target 'config.toml'
    $original = "model = `"old`"`r`nmodel_provider = `"preserve-provider`"`r`n[agents]`r`nenabled = true`r`nmax_concurrent_threads_per_session = 2`r`n"
    [IO.File]::WriteAllText($cfg,$original,[Text.UTF8Encoding]::new($true))
    $before = (Get-FileHash -LiteralPath $cfg).Hash
    $receipt = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -CodexRoot $target | ConvertFrom-Json
    Assert ((Get-Content -LiteralPath $cfg -Raw).Contains('preserve-provider')) 'Provider changed'
    Assert ((Get-Content -LiteralPath $cfg -Raw).Contains('# availability-rules: ')) 'Shared config carries the availability re-selection rules'
    $profileText = Get-Content -LiteralPath (Join-Path $target 'gpt61-sol-only.config.toml') -Raw
    Assert ($profileText.Contains('429/quota/rate-limit/auth/billing: nearest lower effort within the same preset')) 'Profile instructions pin the 429 downgrade chain'
    Assert ($profileText.Contains('confirmed service overload/unavailable: nearest lower effort, then nearest higher effort')) 'Profile instructions reserve higher effort for confirmed overload'
    Assert (-not (Test-Path -LiteralPath (Join-Path $target 'hooks.json'))) 'Projection must not install hooks'
    Assert ((& (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Plan -CodexRoot $target | ConvertFrom-Json).files.Count -eq 0) 'Not idempotent'
    & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Rollback -CodexRoot $target -ReceiptPath $receipt.receipt | Out-Null
    Assert ((Get-FileHash -LiteralPath $cfg).Hash -ceq $before) 'Rollback must restore exact bytes including BOM'
    $quotedRoot = '"model" = "old"' + "`n[agents] # inline comment`nenabled = true`n"
    [IO.File]::WriteAllText($cfg, $quotedRoot)
    $quotedReceipt = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -CodexRoot $target | ConvertFrom-Json
    $quotedResult = Get-Content -LiteralPath $cfg -Raw
    Assert (@([regex]::Matches($quotedResult, '(?m)^\s*(?:model|"model"|''model'')\s*=')).Count -eq 1) 'Quoted root model key must be replaced instead of duplicated'
    Assert ($quotedResult.Contains('[agents] # inline comment')) 'Commented agents table must be recognized'
    & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Rollback -ReceiptPath $quotedReceipt.receipt | Out-Null
    Assert ((Get-Content -LiteralPath $cfg -Raw) -ceq $quotedRoot) 'Quoted-root rollback must restore original content'
    $emptyRoot = "[agents]`n[unrelated]`nmodel = `"preserve-other-section`""
    [IO.File]::WriteAllText($cfg, $emptyRoot)
    $emptyRootReceipt = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -CodexRoot $target | ConvertFrom-Json
    $emptyRootResult = Get-Content -LiteralPath $cfg -Raw
    Assert ($emptyRootResult.StartsWith('model = "gpt-6.1-sol"')) 'Empty root must receive its own model key'
    Assert ($emptyRootResult.Contains("[unrelated]`nmodel = `"preserve-other-section`"")) 'Empty root must preserve other sections'
    & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Rollback -CodexRoot $target -ReceiptPath $emptyRootReceipt.receipt | Out-Null
    Assert ((Get-Content -LiteralPath $cfg -Raw) -ceq $emptyRoot) 'Empty-root rollback must restore original content'
    $parentRoot = '"model" = "gpt-6-luna" # keep parent' + "`r`n" + 'review_model = "gpt-6.1-sol"' + "`r`n" + 'model_reasoning_effort = "max"' + "`r`n[agents]`r`nenabled = true`r`nmax_concurrent_threads_per_session = 2`r`ndefault_subagent_model = `"old`"`r`ndefault_subagent_reasoning_effort = `"xhigh`"`r`n"
    [IO.File]::WriteAllText($cfg, $parentRoot, [Text.UTF8Encoding]::new($true))
    $parentBefore = (Get-FileHash -LiteralPath $cfg).Hash
    $subagentPlan = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Plan -SubagentsOnly -CodexRoot $target | ConvertFrom-Json
    Assert ($subagentPlan.scope -ceq 'subagents_only' -and (Get-FileHash -LiteralPath $cfg).Hash -ceq $parentBefore) 'Subagent Plan is read-only'
    $subagentReceipt = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -SubagentsOnly -CodexRoot $target | ConvertFrom-Json
    $subagentConfig = Get-Content -LiteralPath $cfg -Raw
    Assert ($subagentConfig.StartsWith($parentRoot.Substring(0, $parentRoot.IndexOf('[agents]')).Replace("`r`n","`n"))) 'Subagent projection preserves exact parent lines and comments'
    Assert ($subagentConfig.Contains('default_subagent_model = "gpt-6.1-sol"') -and $subagentConfig.Contains('default_subagent_reasoning_effort = "medium"')) 'Subagent standard defaults'
    Assert ($subagentConfig.Contains('max_concurrent_threads_per_session = 2') -and $subagentConfig.Contains('enabled = true')) 'Native delegation and concurrency preserved'
    foreach ($entry in $defaultResolved.enabled_routes) {
        Assert ($subagentConfig.Contains("[agents.$($entry.role)]")) 'All tuple roles coexist in the shared config'
        $roleText = Get-Content -LiteralPath (Join-Path $fixture ".generated/codex/pool/$($entry.role).toml") -Raw
        Assert ($roleText.Contains("model = `"$($entry.model)`"") -and $roleText.Contains("model_reasoning_effort = `"$($entry.effort)`"") -and $roleText.Contains('enabled = false')) 'Tuple role pins its exact route and disables nested delegation'
    }
    Assert (-not $subagentConfig.Contains('deepseek')) 'Active projection excludes DeepSeek'
    Assert ((& (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Plan -SubagentsOnly -CodexRoot $target | ConvertFrom-Json).files.Count -eq 0) 'Subagent projection is idempotent'
    & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Rollback -ReceiptPath $subagentReceipt.receipt | Out-Null
    Assert ((Get-FileHash -LiteralPath $cfg).Hash -ceq $parentBefore) 'Subagent rollback restores exact parent config bytes'
    $fixturePolicyPath = Join-Path $fixture 'presets.json'
    $expandedPolicy = Get-Content -LiteralPath $fixturePolicyPath -Raw | ConvertFrom-Json -AsHashtable
    $expandedPolicy.slots += 'custom_task'
    foreach ($presetId in $expandedPolicy.presets.Keys) { $expandedPolicy.presets[$presetId].slot_map.custom_task = 0 }
    [IO.File]::WriteAllText($fixturePolicyPath, ($expandedPolicy | ConvertTo-Json -Depth 12))
    $customPlan = & (Join-Path $fixture 'Start-ModelSlot.ps1') -Slot custom_task -Model gpt-6-luna -Effort max -Plan | ConvertFrom-Json
    Assert ($customPlan.slot -ceq 'custom_task' -and $customPlan.model -ceq 'gpt-6-luna') 'Additional configured slot can use another model without launcher edits'
    $customReceipt = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -SubagentsOnly -CodexRoot $target | ConvertFrom-Json
    Assert ((Get-Content -LiteralPath $cfg -Raw).Contains('[agents.custom_task]')) 'Additional configured slot projects to a native role'
    & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Rollback -ReceiptPath $customReceipt.receipt | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'presets.json') -Destination $fixturePolicyPath -Force
    [IO.File]::WriteAllText($cfg, $original)
    $retryReceipt = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -CodexRoot $target | ConvertFrom-Json
    $retryState = Get-Content -LiteralPath $retryReceipt.receipt -Raw | ConvertFrom-Json
    $lockedPath = [string]$retryState.files[0].path
    $lockedStream = [IO.File]::Open($lockedPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $rollbackBlocked = $false
    try { & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Rollback -ReceiptPath $retryReceipt.receipt | Out-Null }
    catch { $rollbackBlocked = $true }
    finally { $lockedStream.Dispose() }
    Assert $rollbackBlocked 'Rollback interruption fixture must fail once'
    & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Rollback -ReceiptPath $retryReceipt.receipt | Out-Null
    Assert ((Get-Content -LiteralPath $cfg -Raw) -ceq $original) 'Interrupted rollback must be retryable'
    Assert (-not (Test-Path -LiteralPath $lockedPath)) 'Retry must remove a created file that blocked the first rollback'
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
"PASS: $count assertions (joint model pool, cross-model slots, read-only boundaries, extensible slots, removed-model rejection, projection idempotence, exact rollback)."
