#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$count = 0
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message }; $script:count++ }
$policy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'presets.json') -Raw | ConvertFrom-Json -AsHashtable
$slots = @($policy.slots)
$expected = @{
    glm53_flash_only    = @{ menu = @(,@('glm-5.3-flash','xhigh')); map = @{quick_triage=0;routine_maintenance=0;standard_review=0;bounded_implementation=0;deep_investigation=0;deep_implementation=0;test_execution=0;documentation_review=0;architecture_review=0} }
    claude_haiku55_only = @{ menu = @(@('claude-haiku-5-5','medium'),@('claude-haiku-5-5','high'),@('claude-haiku-5-5','xhigh')); map = @{quick_triage=0;routine_maintenance=1;standard_review=2;bounded_implementation=2;deep_investigation=2;deep_implementation=2;test_execution=1;documentation_review=1;architecture_review=2} }
    gemini38_flash_only = @{ menu = @(,@('gemini-3.8-flash-high','high')); map = @{quick_triage=0;routine_maintenance=0;standard_review=0;bounded_implementation=0;deep_investigation=0;deep_implementation=0;test_execution=0;documentation_review=0;architecture_review=0} }
    gpt6_luna_only      = @{ menu = @(,@('gpt-6-luna','max')); map = @{quick_triage=0;routine_maintenance=0;standard_review=0;bounded_implementation=0;deep_investigation=0;deep_implementation=0;test_execution=0;documentation_review=0;architecture_review=0} }
}
Assert ($policy.presets.Count -eq 4 -and $slots.Count -gt 3) 'Four single-tier models and multiple slots'
Assert (('codex' -in $policy.presets['glm53_flash_only'].hosts) -and ('zcode' -in $policy.presets['glm53_flash_only'].hosts)) 'GLM host facets'
Assert (('codex' -in $policy.presets['claude_haiku55_only'].hosts) -and ('claude' -in $policy.presets['claude_haiku55_only'].hosts)) 'Haiku declares the codex and claude facets'
Assert (@($policy.presets['gemini38_flash_only'].hosts).Count -eq 1 -and 'codex' -in $policy.presets['gemini38_flash_only'].hosts) 'Gemini stays codex-only'
$zcodeResolved = & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve -ExecutionHost zcode -Preset glm53_flash_only | ConvertFrom-Json -AsHashtable
Assert ($zcodeResolved.host -ceq 'zcode' -and $zcodeResolved.routes.quick_triage.model -ceq 'glm-5.3-flash' -and $zcodeResolved.routes.quick_triage.effort -ceq 'max') 'ZCode keeps the native GLM max facet'
Assert (@($zcodeResolved.enabled_routes | Where-Object { $_.model -ceq 'glm-5.3-flash' -and $_.effort -ceq 'max' }).Count -eq 1) 'ZCode exposes only the reviewed GLM max tuple'
foreach ($foreignPreset in @('claude_haiku55_only','gemini38_flash_only')) {
    $zcodeForeignRejected = $false
    try { & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve -ExecutionHost zcode -Preset $foreignPreset | Out-Null } catch { $zcodeForeignRejected = $true }
    Assert $zcodeForeignRejected "Unverified ZCode facet stays blocked: $foreignPreset"
}
foreach ($id in $expected.Keys) {
    $resolved = & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve -Preset $id | ConvertFrom-Json -AsHashtable
    foreach ($slot in $slots) {
        $pair = $expected[$id].menu[$expected[$id].map[$slot]]
        Assert ($resolved.routes[$slot].model -ceq $pair[0] -and $resolved.routes[$slot].effort -ceq $pair[1]) "Wrong route: $id/$slot"
    }
}
$defaultResolved = & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve | ConvertFrom-Json
Assert ($defaultResolved.preset -ceq $policy.default_preset -and $defaultResolved.preset -ceq 'gpt6_luna_only') 'Default comes from policy'
Assert ($defaultResolved.active_presets.Count -eq 4 -and $defaultResolved.enabled_routes.Count -eq 6) 'Four presets expose six enabled codex tuples'
Assert (@($policy.auto_routes.Values | Where-Object { $_ -cne 'gpt6_luna_only' }).Count -eq 0) 'Every automatic daily route is gpt6_luna_only; GLM, Haiku and Gemini stay as declared alternates'
Assert ((@($defaultResolved.enabled_routes | Where-Object { $_.model -ceq 'claude-haiku-5-5' } | ForEach-Object { $_.effort }) -join ',') -ceq 'medium,high,xhigh') 'Haiku exposes the three-rung menu in effort order'
$autoRoutes = @{
    quick_triage = 'gpt6_luna_only'
    routine_maintenance = 'gpt6_luna_only'
    standard_review = 'gpt6_luna_only'
    bounded_implementation = 'gpt6_luna_only'
    deep_investigation = 'gpt6_luna_only'
    deep_implementation = 'gpt6_luna_only'
    test_execution = 'gpt6_luna_only'
    documentation_review = 'gpt6_luna_only'
    architecture_review = 'gpt6_luna_only'
}
foreach ($slot in $slots) { Assert ($defaultResolved.auto_routing -and $defaultResolved.routes.$slot.preset -ceq $autoRoutes[$slot]) "Automatic task-shape route: $slot" }
$reselection = $defaultResolved.reselection
Assert ($null -ne $reselection -and @($reselection.rate_limit_order).Count -eq 4) 'Reselection contract derives from the active pool'
Assert ((@($reselection.rate_limit_order | Where-Object { $_.preset -ceq 'glm53_flash_only' })[0].menu | ForEach-Object { $_.effort }) -ccontains 'xhigh') 'Codex GLM menu uses the exact native xhigh tuple'
Assert ($reselection.prohibition.Contains('429') -and $reselection.prohibition.Contains('risk') -and $reselection.prohibition.Contains('never')) 'Reselection prohibition pins rate-limit and risk semantics'
Assert ($defaultResolved.dispatch_policy.max_upstream_attempts_per_bounded_task -eq 1 -and $defaultResolved.dispatch_policy.max_explicit_reselections -eq 1 -and -not $defaultResolved.dispatch_policy.duplicate_prompt_replay -and $defaultResolved.dispatch_policy.rate_limit_action -ceq 'stop_and_wait_for_fresh_parent_selection' -and $defaultResolved.dispatch_policy.auth_or_risk_action -ceq 'stop_and_operator_review' -and $defaultResolved.dispatch_policy.overload_action -ceq 'one_explicit_reselection_only') 'One-attempt upstream safety policy'
Assert (@($defaultResolved.enabled_routes.model | Select-Object -Unique).Count -eq 4) 'Pool includes distinct model families'
Assert (@($defaultResolved.enabled_routes | Where-Object { $_.model -ceq 'gpt-6-luna' })[0].effort -ceq 'max') 'Luna tuple is pinned to max'
Assert ('gpt-5.6-terra' -cnotin @($defaultResolved.enabled_routes.model)) 'Terra removed from active pool'
$selected = & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve -AvailablePreset glm53_flash_only,claude_haiku55_only | ConvertFrom-Json
Assert ($selected.preset -eq 'glm53_flash_only') 'Ordered selection'
Assert ($selected.active_presets.Count -eq 2 -and $selected.enabled_routes.Count -eq 4) 'AvailablePreset retains the whole selected pool including haiku rungs'
Assert ([int]$policy.schema_version -eq 6 -and @($policy.fallbacks.Keys).Count -eq $slots.Count) 'Schema v6 declares fallbacks for every slot'
Assert ((@($defaultResolved.routes.architecture_review.declared_fallback | ForEach-Object { "$($_.model)/$($_.effort)" }) -join ',') -ceq 'claude-haiku-5-5/xhigh,gemini-3.8-flash-high/high') 'Resolve exposes the declared alternates of each route'
Assert (@($zcodeResolved.routes.quick_triage.declared_fallback).Count -eq 0) 'ZCode pool exposes no alternate outside its reviewed facet'
Assert ((@($selected.routes.architecture_review.declared_fallback | ForEach-Object { "$($_.model)/$($_.effort)" }) -join ',') -ceq 'claude-haiku-5-5/xhigh') 'Alternates stay inside the active pool and exclude the substituted route'
$cliSelection = & (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Slot standard_review -AvailablePreset 'glm53_flash_only,claude_haiku55_only' -Plan | ConvertFrom-Json
Assert ($null -ne $cliSelection.preset -and $cliSelection.preset -eq 'glm53_flash_only' -and $cliSelection.route_preset -eq 'glm53_flash_only' -and $cliSelection.effort -eq 'xhigh' -and $cliSelection.delegation_enabled -eq $false) 'Native CLI available-set binding: standard_review auto route (luna) is outside the set, so the first available preset binds'
foreach ($legacyId in $policy.aliases.Keys) {
    $legacyResolved = & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve -Preset $legacyId | ConvertFrom-Json
    Assert ($legacyResolved.preset -ceq $policy.aliases[$legacyId]) 'Legacy preset alias'
}
$legacyRejected = $false
try { & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve -AvailablePreset gpt_terra_only,glm53_flash_only | Out-Null } catch { $legacyRejected = $true }
Assert $legacyRejected 'Removed Terra presets and aliases are rejected, not silently resolved'
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
    @{Slot='standard_review';Model='gpt-5.6-terra';Effort='max'},
    @{Slot='standard_review';Model='gpt-5.6-terra';Effort='high'},
    @{Slot='standard_review';Model='deepseek-flash';Effort='high'},
    @{Slot='standard_review';Model='deepseek-v4.1-flash';Effort='xhigh'},
    @{Slot='standard_review';Model='gemini-3.8-flash';Effort='high'},
    @{Slot='standard_review';Model='glm-5.3-flash';Effort='high'},
    @{Slot='standard_review';Model='gpt-6.1-sol';Effort='max'},
    @{Slot='standard_review';Model='gpt-6.1-sol';Effort='low'},
    @{Slot='standard_review';Model='gpt-6.1-sol';Effort='medium'},
    @{Slot='standard_review';Preset='gpt61_sol_only'},
    @{Slot='standard_review';Model='gpt-6-luna'},
    @{Slot='standard_review';Model='claude-haiku-5-5';Effort='low'},
    @{Slot='standard_review';Model='gpt-6-luna';Effort='xhigh'},
    @{Slot='unknown_slot'},
    @{Slot='deep_investigation_or_implementation'},
    @{Slot='standard_review';Preset='gpt_terra_only'},
    @{Slot='standard_review';AvailablePreset=@('glm53_flash_only');Model='gpt-6-luna';Effort='max'}
)) {
    $rejected = $false
    try { & (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') @invalidSelection -Plan | Out-Null } catch { $rejected = $true }
    Assert $rejected 'Reject removed, incomplete or out-of-pool selection'
}
$deepReadOnly = & (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Slot deep_investigation -Model gemini-3.8-flash-high -Effort high -Plan | ConvertFrom-Json
Assert $deepReadOnly.read_only 'Deep investigation is read-only by slot contract'
$deepImplementation = & (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Slot deep_implementation -Model gemini-3.8-flash-high -Effort high -Plan | ConvertFrom-Json
Assert (-not $deepImplementation.read_only) 'Deep implementation is a distinct write-capable slot'
$launcher = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Raw
Assert ($launcher.Contains('no replay or preset substitution performed') -and $launcher.Contains('No arbitrary CLI pass-through')) 'Failed task must not replay'
$providerEvidencePath = Join-Path ([IO.Path]::GetTempPath()) ('model-provider-evidence-'+[guid]::NewGuid().ToString('N')+'.json')
$providerEvidence = [ordered]@{
    schema_version = 1
    surface = 'codex_provider_channel'
    observed_at = [DateTimeOffset]::UtcNow.AddMinutes(-5).ToString('o')
    expires_at = [DateTimeOffset]::UtcNow.AddMinutes(5).ToString('o')
    source = 'test-current-parent-receipt'
    tuples = @(
        @{ model = 'gpt-6-luna'; effort = 'max'; status = 'verified' },
        @{ model = 'glm-5.3-flash'; effort = 'xhigh'; status = 'verified' },
        @{ model = 'claude-haiku-5-5'; effort = 'xhigh'; status = 'verified' },
        @{ model = 'gemini-3.8-flash-high'; effort = 'high'; status = 'verified' }
    )
}
[IO.File]::WriteAllText($providerEvidencePath, ($providerEvidence | ConvertTo-Json -Depth 8))
if (Test-Path Function:/global:codex) { throw 'Cannot install acceptance mock over an existing global codex function.' }
$previousCodexHome = $env:CODEX_HOME
$testCodexHome = Join-Path ([IO.Path]::GetTempPath()) ('model-preset-codex-home-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testCodexHome) | Out-Null
$codexConfigPath = Join-Path $testCodexHome 'config.toml'
$codexConfigText = @'
model_provider = "fixture_provider"

[model_providers.fixture_provider]
name = "fixture"
base_url = "https://fixture.invalid/v1"
request_max_retries = 4
stream_max_retries = 5
'@
[IO.File]::WriteAllText($codexConfigPath, $codexConfigText)
$env:CODEX_HOME = $testCodexHome
$global:ModelSlotAcceptanceCalls = [Collections.Generic.List[object]]::new()
$global:ModelSlotAcceptanceExitCode = 1
$global:ModelSlotAcceptanceFailureMode = 'rate_limit'
function global:codex {
    $global:ModelSlotAcceptanceCalls.Add(@($args))
    $global:LASTEXITCODE = $global:ModelSlotAcceptanceExitCode
    if ($global:ModelSlotAcceptanceExitCode -ne 0) {
        if ($global:ModelSlotAcceptanceFailureMode -ceq 'timeout_message_only') { '{"type":"turn.failed","error":{"message":"request timeout (simulated)"}}' }
        else { '{"type":"turn.failed","error":{"code":"rate_limit","message":"Too Many Requests (simulated)"}}' }
    }
    else { '{"type":"turn.completed"}' }
}
try {
    foreach ($failedRoute in @(
            @{ model = 'gpt-6-luna'; effort = 'max'; fallback = @('claude-haiku-5-5/xhigh','gemini-3.8-flash-high/high'); lower = @() },
            @{ model = 'glm-5.3-flash'; effort = 'xhigh'; fallback = @('claude-haiku-5-5/xhigh','gemini-3.8-flash-high/high'); lower = @() },
            @{ model = 'claude-haiku-5-5'; effort = 'xhigh'; fallback = @('gemini-3.8-flash-high/high'); lower = @('claude-haiku-5-5/high','claude-haiku-5-5/medium') },
            @{ model = 'gemini-3.8-flash-high'; effort = 'high'; fallback = @('claude-haiku-5-5/xhigh'); lower = @() }
    )) {
        $failureMessage = ''
        try { & (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Slot architecture_review -Model $failedRoute.model -Effort $failedRoute.effort -ReadOnly -CapabilityMode provider_override -CapabilityProbePath $providerEvidencePath -Prompt 'Simulated unavailable request' | Out-Null }
        catch { $failureMessage = $_.Exception.Message }
        Assert ($failureMessage -like '*no replay or preset substitution performed*') 'Failure returns control without replay'
        $jsonMatch = [regex]::Match($failureMessage, '\{.*\}')
        Assert $jsonMatch.Success 'Structured failure emitted'
        $failure = ($jsonMatch.Value | ConvertFrom-Json).slot_failure
        Assert ($failure.failed_tuple.model -ceq $failedRoute.model -and $failure.failed_tuple.effort -ceq $failedRoute.effort) 'Failed tuple is exact'
        Assert ($failure.failure_class -ceq 'rate_limit' -and $failure.failure_source -ceq 'structured_error_event') 'Failure class comes from structured error fields'
        Assert (((@($failure.reselection.within_preset_lower | ForEach-Object { "$($_.model)/$($_.effort)" }) -join ',') -ceq ($failedRoute.lower -join ','))) 'Failure ladder follows the preset menu'
        Assert (@($failure.reselection.within_preset_higher_overload_only).Count -eq 0) 'Top-rung failure has no within-preset escalation'
        Assert ((@($failure.reselection.declared_fallback | ForEach-Object { "$($_.model)/$($_.effort)" }) -join ',') -ceq ($failedRoute.fallback -join ',')) 'Declared alternates exclude the failed tuple and keep policy order'
        Assert (-not ($failure.reselection.PSObject.Properties.Name -ccontains 'cross_preset')) 'Implicit cross-preset list is retired'
    }
    Assert ($global:ModelSlotAcceptanceCalls.Count -eq 4) 'Failures never automatically retry'
    $global:ModelSlotAcceptanceFailureMode = 'timeout_message_only'
    $timeoutFailure = ''
    try { & (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Slot architecture_review -Model gpt-6-luna -Effort max -ReadOnly -CapabilityMode provider_override -CapabilityProbePath $providerEvidencePath -Prompt 'Output contains timeout text but no structured code' | Out-Null }
    catch { $timeoutFailure = $_.Exception.Message }
    $timeoutJson = [regex]::Match($timeoutFailure, '\{.*\}')
    Assert $timeoutJson.Success 'Unclassified structured error still emits failure evidence'
    $timeoutDoc = ($timeoutJson.Value | ConvertFrom-Json).slot_failure
    Assert ($timeoutDoc.failure_class -ceq 'unknown' -and $timeoutDoc.failure_source -ceq 'structured_error_unclassified' -and $timeoutDoc.retry_policy.next_action -ceq 'diagnose_before_any_new_dispatch') 'Timeout text without a structured code stays unknown'
    $global:ModelSlotAcceptanceFailureMode = 'rate_limit'
    $budgetMessage = ''
    try { & (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Slot architecture_review -Model glm-5.3-flash -Effort xhigh -ReadOnly -CapabilityMode provider_override -CapabilityProbePath $providerEvidencePath -ReselectionCount 1 -Prompt 'Budget must block before launch' | Out-Null }
    catch { $budgetMessage = $_.Exception.Message }
    Assert ($budgetMessage -like '*Reselection budget exhausted*' -and $budgetMessage -like '*no upstream request was sent*') 'Exhausted reselection budget blocks dispatch'
    Assert ($global:ModelSlotAcceptanceCalls.Count -eq 5) 'Exhausted reselection budget makes no launch call'
    $budgetJson = [regex]::Match($budgetMessage, '\{.*\}')
    Assert $budgetJson.Success 'Budget block emits structured evidence'
    $budget = ($budgetJson.Value | ConvertFrom-Json).reselection_budget_exhausted
    Assert ($budget.reselection_count -eq 1 -and $budget.max_explicit_reselections -eq 1 -and $budget.upstream_contacted -eq $false) 'Budget evidence records the hard stop'
    $global:ModelSlotAcceptanceExitCode = 0
    & (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Slot architecture_review -Model glm-5.3-flash -Effort xhigh -ReadOnly -CapabilityMode provider_override -CapabilityProbePath $providerEvidencePath -Prompt 'Explicit remaining read-only work' | Out-Null
    Assert ($global:ModelSlotAcceptanceCalls.Count -eq 6) 'Parent can explicitly select the next supported model'
    foreach ($call in $global:ModelSlotAcceptanceCalls) {
        Assert ($call -ccontains 'read-only' -and $call -ccontains 'agents.enabled=false' -and (($call -ccontains 'model_reasoning_effort="max"') -or ($call -ccontains 'model_reasoning_effort="xhigh"') -or ($call -ccontains 'model_reasoning_effort="high"'))) 'All launches preserve read-only, fixed tuple and no nested delegation'
        Assert ($call -ccontains 'model_providers.fixture_provider.request_max_retries=0' -and $call -ccontains 'model_providers.fixture_provider.stream_max_retries=0') 'Codex CLI retries are capped for the selected custom provider'
    }

    $profileConfigPath = Join-Path $testCodexHome 'glm53-flash-only.config.toml'
    $profileConfigText = @'
model_provider = "fixture_profile_provider"

[model_providers.fixture_profile_provider]
name = "profile-fixture"
base_url = "https://profile-fixture.invalid/v1"
'@
    [IO.File]::WriteAllText($profileConfigPath, $profileConfigText)
    & (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Slot architecture_review -Model glm-5.3-flash -Effort xhigh -ReadOnly -CapabilityMode provider_override -CapabilityProbePath $providerEvidencePath -Prompt 'Profile provider wins' | Out-Null
    $profileCall = $global:ModelSlotAcceptanceCalls[$global:ModelSlotAcceptanceCalls.Count - 1]
    Assert ($profileCall -ccontains 'model_providers.fixture_profile_provider.request_max_retries=0' -and $profileCall -ccontains 'model_providers.fixture_profile_provider.stream_max_retries=0' -and -not ($profileCall -ccontains 'model_providers.fixture_provider.request_max_retries=0')) 'Profile provider takes precedence over base config for retry control'

    Remove-Item -LiteralPath $profileConfigPath
    [IO.File]::WriteAllText($codexConfigPath, 'model = "gpt-6-luna"' + [Environment]::NewLine)
    $beforeRetryControlBlock = $global:ModelSlotAcceptanceCalls.Count
    $retryControlFailure = ''
    try { & (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Slot architecture_review -Model gpt-6-luna -Effort max -ReadOnly -CapabilityMode native -Prompt 'Must block without retry control' | Out-Null }
    catch { $retryControlFailure = $_.Exception.Message }
    Assert ($retryControlFailure -like '*retry_control_unavailable*' -and $retryControlFailure -like '*upstream_contacted*false*') 'Missing custom-provider retry control blocks before dispatch'
    Assert ($global:ModelSlotAcceptanceCalls.Count -eq $beforeRetryControlBlock) 'Retry-control blocker makes no model call'
}
finally {
    Remove-Item Function:/global:codex
    Remove-Variable ModelSlotAcceptanceCalls,ModelSlotAcceptanceExitCode -Scope Global -ErrorAction SilentlyContinue
    if ($null -eq $previousCodexHome) { Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue } else { $env:CODEX_HOME = $previousCodexHome }
    Remove-Item -LiteralPath $testCodexHome -Recurse -Force -ErrorAction SilentlyContinue
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
    $projectionCapabilityPath = Join-Path $fixture 'models-all-supported.json'
    $projectionCatalog = @{ models = @(
        @{ slug = 'gpt-6-luna'; supported_reasoning_levels = @(@{ effort = 'max' }) },
        @{ slug = 'glm-5.3-flash'; supported_reasoning_levels = @(@{ effort = 'xhigh' }) },
        @{ slug = 'claude-haiku-5-5'; supported_reasoning_levels = @(@{ effort = 'medium' }, @{ effort = 'high' }, @{ effort = 'xhigh' }) },
        @{ slug = 'gemini-3.8-flash-high'; supported_reasoning_levels = @(@{ effort = 'high' }) }
    ) }
    [IO.File]::WriteAllText($projectionCapabilityPath, ($projectionCatalog | ConvertTo-Json -Depth 8))
    $before = (Get-FileHash -LiteralPath $cfg).Hash
    $receipt = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -CodexRoot $target -CapabilityProbePath $projectionCapabilityPath | ConvertFrom-Json
    Assert ($receipt.capability.status -ceq 'native_supported' -and @($receipt.capability.tuples).Count -eq 6) 'Apply records the verified native tuple set'
    Assert ((Get-Content -LiteralPath $cfg -Raw).Contains('preserve-provider')) 'Provider changed'
    $projectedConfig = Get-Content -LiteralPath $cfg -Raw
    Assert ($projectedConfig.Contains('# availability-rules: ') -and $projectedConfig.Contains('429/quota/rate-limit/auth/risk: stop and wait') -and $projectedConfig.Contains('No hot-swap, aliasing, effort substitution')) 'Shared config carries the stop-and-wait availability rules'
    $profileText = Get-Content -LiteralPath (Join-Path $target 'glm53-flash-only.config.toml') -Raw
    Assert ($profileText.Contains('One upstream attempt is allowed per bounded task') -and $profileText.Contains('never replay an identical prompt')) 'Profile instructions pin the one-attempt safety policy'
    Assert ($profileText.Contains('confirmed overload may receive one explicit reselection only')) 'Profile instructions reserve one alternate for confirmed overload'
    Assert ($profileText.Contains('dispatch other tuples natively only after a passing native probe')) 'Profile instructions restrict native subagents to the verified GPT-family tuple'
    Assert (-not (Test-Path -LiteralPath (Join-Path $target 'hooks.json'))) 'Projection must not install hooks'
    Assert ((& (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Plan -CodexRoot $target -CapabilityProbePath $projectionCapabilityPath | ConvertFrom-Json).files.Count -eq 0) 'Not idempotent'
    & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Rollback -CodexRoot $target -ReceiptPath $receipt.receipt | Out-Null
    Assert ((Get-FileHash -LiteralPath $cfg).Hash -ceq $before) 'Rollback must restore exact bytes including BOM'
    $quotedRoot = '"model" = "old"' + "`n[agents] # inline comment`nenabled = true`n"
    [IO.File]::WriteAllText($cfg, $quotedRoot)
    $quotedReceipt = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -CodexRoot $target -CapabilityProbePath $projectionCapabilityPath | ConvertFrom-Json
    $quotedResult = Get-Content -LiteralPath $cfg -Raw
    Assert (@([regex]::Matches($quotedResult, '(?m)^\s*(?:model|"model"|''model'')\s*=')).Count -eq 1) 'Quoted root model key must be replaced instead of duplicated'
    Assert ($quotedResult.Contains('[agents] # inline comment')) 'Commented agents table must be recognized'
    & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Rollback -ReceiptPath $quotedReceipt.receipt | Out-Null
    Assert ((Get-Content -LiteralPath $cfg -Raw) -ceq $quotedRoot) 'Quoted-root rollback must restore original content'
    $emptyRoot = "[agents]`n[unrelated]`nmodel = `"preserve-other-section`""
    [IO.File]::WriteAllText($cfg, $emptyRoot)
    $emptyRootReceipt = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -CodexRoot $target -CapabilityProbePath $projectionCapabilityPath | ConvertFrom-Json
    $emptyRootResult = Get-Content -LiteralPath $cfg -Raw
    Assert ($emptyRootResult.StartsWith('model = "gpt-6-luna"')) 'Empty root must receive its own model key'
    Assert ($emptyRootResult.Contains("[unrelated]`nmodel = `"preserve-other-section`"")) 'Empty root must preserve other sections'
    & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Rollback -CodexRoot $target -ReceiptPath $emptyRootReceipt.receipt | Out-Null
    Assert ((Get-Content -LiteralPath $cfg -Raw) -ceq $emptyRoot) 'Empty-root rollback must restore original content'
    $parentRoot = '"model" = "gpt-5.6-terra" # keep parent' + "`r`n" + 'review_model = "gpt-5.6-terra"' + "`r`n" + 'model_reasoning_effort = "max"' + "`r`n[agents]`r`nenabled = true`r`nmax_concurrent_threads_per_session = 2`r`ndefault_subagent_model = `"old`"`r`ndefault_subagent_reasoning_effort = `"xhigh`"`r`n"
    [IO.File]::WriteAllText($cfg, $parentRoot, [Text.UTF8Encoding]::new($true))
    $parentBefore = (Get-FileHash -LiteralPath $cfg).Hash
    $subagentPlan = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Plan -SubagentsOnly -CodexRoot $target -CapabilityProbePath $projectionCapabilityPath | ConvertFrom-Json
    Assert ($subagentPlan.scope -ceq 'subagents_only' -and (Get-FileHash -LiteralPath $cfg).Hash -ceq $parentBefore) 'Subagent Plan is read-only'
    $subagentReceipt = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -SubagentsOnly -CodexRoot $target -CapabilityProbePath $projectionCapabilityPath | ConvertFrom-Json
    $subagentConfig = Get-Content -LiteralPath $cfg -Raw
    Assert ($subagentConfig.StartsWith($parentRoot.Substring(0, $parentRoot.IndexOf('[agents]')).Replace("`r`n","`n"))) 'Subagent projection preserves exact parent lines and comments'
    Assert ($subagentConfig.Contains('default_subagent_model = "gpt-6-luna"') -and $subagentConfig.Contains('default_subagent_reasoning_effort = "max"')) 'Subagent standard defaults'
    Assert ($subagentConfig.Contains('max_concurrent_threads_per_session = 2') -and $subagentConfig.Contains('enabled = true')) 'Native delegation and concurrency preserved'
    foreach ($entry in $defaultResolved.enabled_routes) {
        Assert ($subagentConfig.Contains("[agents.$($entry.role)]")) 'All tuple roles coexist in the shared config'
        $roleText = Get-Content -LiteralPath (Join-Path $fixture ".generated/codex/pool/$($entry.role).toml") -Raw
        Assert ($roleText.Contains("model = `"$($entry.model)`"") -and $roleText.Contains("model_reasoning_effort = `"$($entry.effort)`"") -and -not $roleText.Contains('[agents]') -and -not $roleText.Contains('sandbox_mode')) 'Tuple role pins its route without embedding parent-session settings'
        Assert ($roleText.Contains('Do not delegate')) 'Tuple role instructs the child not to delegate'
        $roleBlock = [regex]::Match($subagentConfig, "\[agents\.$([regex]::Escape($entry.role))\]\r?\n(?<body>[^\[]*)").Groups['body'].Value
        Assert (($roleBlock.Contains('not readable by this non-GPT tuple')) -eq ($entry.model -notlike 'gpt-*')) "Native-subagent direct-only note matches the tuple family: $($entry.role)"
    }
    Assert (-not $subagentConfig.Contains('[agents.terra') -and -not $subagentConfig.Contains('default_subagent_model = "gpt-5.6-terra"')) 'Managed projection excludes removed Terra roles and defaults'
    Assert ((& (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Plan -SubagentsOnly -CodexRoot $target -CapabilityProbePath $projectionCapabilityPath | ConvertFrom-Json).files.Count -eq 0) 'Subagent projection is idempotent'
    & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Rollback -ReceiptPath $subagentReceipt.receipt | Out-Null
    Assert ((Get-FileHash -LiteralPath $cfg).Hash -ceq $parentBefore) 'Subagent rollback restores exact parent config bytes'
    $catalogPath = Join-Path $fixture 'models.json'
    $catalog = @{ models = @(
        @{ slug = 'gpt-6-luna'; supported_reasoning_levels = @(@{ effort = 'max' }) },
        @{ slug = 'glm-5.3-flash'; supported_reasoning_levels = @(@{ effort = 'max' }) },
        @{ slug = 'gemini-3.8-flash-high'; supported_reasoning_levels = @(@{ effort = 'max' }) }
    ) }
    [IO.File]::WriteAllText($catalogPath, ($catalog | ConvertTo-Json -Depth 8))
    $blockedProjectionBefore = (Get-FileHash -LiteralPath $cfg).Hash
    $blockedProjectionMessage = ''
    try { & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -CodexRoot $target -CapabilityProbePath $catalogPath | Out-Null }
    catch { $blockedProjectionMessage = $_.Exception.Message }
    Assert ($blockedProjectionMessage -like '*capability preflight blocked projection*' -and $blockedProjectionMessage -like '*no host files were written*') 'Unsupported native projection fails closed'
    Assert ((Get-FileHash -LiteralPath $cfg).Hash -ceq $blockedProjectionBefore) 'Blocked native projection leaves host config unchanged'
    $global:CapabilityCalls = [Collections.Generic.List[object]]::new()
    function global:codex {
        $global:CapabilityCalls.Add(@($args))
        $global:LASTEXITCODE = 0
        '{"type":"turn.completed"}'
    }
    try {
        $blocked = $false
        try { & (Join-Path $fixture 'Start-ModelSlot.ps1') -Slot standard_review -Model glm-5.3-flash -Effort xhigh -CapabilityProbePath $catalogPath -Prompt 'blocked native tuple' | Out-Null }
        catch { $blocked = $_.Exception.Message -like '*no model request was sent*' }
        Assert $blocked 'Unsupported native tuple is blocked before upstream contact'
        Assert ($global:CapabilityCalls.Count -eq 0) 'Capability block makes no launch call'
        $missingEvidence = $false
        try { & (Join-Path $fixture 'Start-ModelSlot.ps1') -Slot standard_review -Model glm-5.3-flash -Effort xhigh -CapabilityMode provider_override -Prompt 'missing provider evidence must block' | Out-Null }
        catch { $missingEvidence = $_.Exception.Message -like '*provider_evidence_invalid*' -and $_.Exception.Message -like '*no model request was sent*' }
        Assert $missingEvidence 'Provider override without current evidence fails closed'
        Assert ($global:CapabilityCalls.Count -eq 0) 'Missing provider evidence makes no launch call'
        & (Join-Path $fixture 'Start-ModelSlot.ps1') -Slot standard_review -Model glm-5.3-flash -Effort xhigh -CapabilityMode provider_override -CapabilityProbePath $providerEvidencePath -Prompt 'explicit one-shot provider override' | Out-Null
        Assert ($global:CapabilityCalls.Count -eq 1) 'Provider override requires one explicit launch and does not probe/retry'
    }
    finally {
        Remove-Item Function:/global:codex -ErrorAction SilentlyContinue
        Remove-Variable CapabilityCalls -Scope Global -ErrorAction SilentlyContinue
    }
    $ownedFile = (Join-Path $fixture '.generated/codex/pool/sol_low.toml').Replace('\','/')
    $orphanConfig = $parentRoot + "`n[agents.sol_low]`ndescription = `"retired`"`nconfig_file = '$ownedFile'`n# keep this user comment`n# model-orchestration end`n[agents.user_role]`ndescription = `"unrelated`"`nconfig_file = 'D:/user-role.toml'`n"
    [IO.File]::WriteAllText($cfg, $orphanConfig)
    $orphanReceipt = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -SubagentsOnly -CodexRoot $target -CapabilityProbePath $projectionCapabilityPath | ConvertFrom-Json
    $cleaned = Get-Content -LiteralPath $cfg -Raw
    Assert (-not $cleaned.Contains('[agents.sol_low]') -and $cleaned.Contains('[agents.user_role]') -and $cleaned.Contains('# keep this user comment')) 'Retire orphan owned roles while preserving unrelated roles and comments'
    Assert ((& (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Plan -SubagentsOnly -CodexRoot $target -CapabilityProbePath $projectionCapabilityPath | ConvertFrom-Json).files.Count -eq 0) 'Orphan cleanup remains idempotent'
    & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Rollback -ReceiptPath $orphanReceipt.receipt | Out-Null
    Assert ((Get-Content -LiteralPath $cfg -Raw) -ceq $orphanConfig) 'Orphan cleanup rollback restores exact original config'
    [IO.File]::WriteAllText($cfg, $parentRoot)
    $fixturePolicyPath = Join-Path $fixture 'presets.json'
    $expandedPolicy = Get-Content -LiteralPath $fixturePolicyPath -Raw | ConvertFrom-Json -AsHashtable
    $expandedPolicy.slots += 'custom_task'
    $expandedPolicy.auto_routes.custom_task = 'glm53_flash_only'
    $expandedPolicy.fallbacks.custom_task = @()
    foreach ($presetId in $expandedPolicy.presets.Keys) { $expandedPolicy.presets[$presetId].slot_map.custom_task = 0 }
    [IO.File]::WriteAllText($fixturePolicyPath, ($expandedPolicy | ConvertTo-Json -Depth 12))
    $customPlan = & (Join-Path $fixture 'Start-ModelSlot.ps1') -Slot custom_task -Model gemini-3.8-flash-high -Effort high -Plan | ConvertFrom-Json
    Assert ($customPlan.slot -ceq 'custom_task' -and $customPlan.model -ceq 'gemini-3.8-flash-high') 'Additional configured slot can use another model without launcher edits'
    $customReceipt = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -SubagentsOnly -CodexRoot $target -CapabilityProbePath $projectionCapabilityPath | ConvertFrom-Json
    Assert ((Get-Content -LiteralPath $cfg -Raw).Contains('[agents.custom_task]')) 'Additional configured slot projects to a native role'
    & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Rollback -ReceiptPath $customReceipt.receipt | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'presets.json') -Destination $fixturePolicyPath -Force
    $descendingPolicy = Get-Content -LiteralPath $fixturePolicyPath -Raw | ConvertFrom-Json -AsHashtable
    $descendingPolicy.presets.glm53_flash_only.menu += @{model='glm-5.3-flash';effort='high'}
    [IO.File]::WriteAllText($fixturePolicyPath, ($descendingPolicy | ConvertTo-Json -Depth 12))
    $orderRejected = $false
    try { & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Resolve | Out-Null }
    catch { $orderRejected = $_.Exception.Message -like '*strictly increasing effort*' }
    Assert $orderRejected 'Reject descending menus before they can label escalation as downgrade'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'presets.json') -Destination $fixturePolicyPath -Force
    [IO.File]::WriteAllText($cfg, $original)
    $retryReceipt = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -CodexRoot $target -CapabilityProbePath $projectionCapabilityPath | ConvertFrom-Json
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
    $badText = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'presets.json') -Raw) -replace '"deep_implementation": \d+', '"deep_implementation": 9'
    [IO.File]::WriteAllText((Join-Path $fixture 'presets.json'), $badText)
    $threw = $false
    try { & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Resolve | Out-Null } catch { $threw = $true }
    Assert $threw 'Out-of-range slot index must fail closed'
    $hostMenuPolicy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'presets.json') -Raw | ConvertFrom-Json -AsHashtable
    $hostMenus = if ($hostMenuPolicy.presets['glm53_flash_only']['host_menus']) { $hostMenuPolicy.presets['glm53_flash_only']['host_menus'] } else { @{} }
    $hostMenus['codex'] = @(@{ model = 'glm-5.3-flash'; effort = 'high' }, @{ model = 'glm-5.3-flash'; effort = 'xhigh' })
    $hostMenuPolicy.presets['glm53_flash_only']['host_menus'] = $hostMenus
    [IO.File]::WriteAllText($fixturePolicyPath, ($hostMenuPolicy | ConvertTo-Json -Depth 12))
    $hostMenuEvidencePath = Join-Path $fixture 'models-host-menu-evidence.json'
    $hostMenuEvidence = [ordered]@{
        schema_version = 1
        surface = 'codex_provider_channel'
        observed_at = [DateTimeOffset]::UtcNow.AddMinutes(-5).ToString('o')
        expires_at = [DateTimeOffset]::UtcNow.AddMinutes(5).ToString('o')
        source = 'test-host-menu-reselection'
        tuples = @(
            @{ model = 'glm-5.3-flash'; effort = 'high'; status = 'verified' },
            @{ model = 'glm-5.3-flash'; effort = 'xhigh'; status = 'verified' },
            @{ model = 'gemini-3.8-flash-high'; effort = 'high'; status = 'verified' }
        )
    }
    [IO.File]::WriteAllText($hostMenuEvidencePath, ($hostMenuEvidence | ConvertTo-Json -Depth 8))
    $global:HostMenuFailureCalls = [Collections.Generic.List[object]]::new()
    function global:codex {
        $global:HostMenuFailureCalls.Add(@($args))
        $global:LASTEXITCODE = 1
        '{"type":"turn.failed","error":{"code":"rate_limit","message":"Too Many Requests (simulated)"}}'
    }
    try {
        $hostMenuFailure = ''
        try { & (Join-Path $fixture 'Start-ModelSlot.ps1') -Slot architecture_review -Model glm-5.3-flash -Effort xhigh -ReadOnly -CapabilityMode provider_override -CapabilityProbePath $hostMenuEvidencePath -Prompt 'Host facet failure document' | Out-Null }
        catch { $hostMenuFailure = $_.Exception.Message }
        Assert ($hostMenuFailure -like '*no replay or preset substitution performed*') 'Host-menu failure returns control without replay'
        $hostMenuDoc = (([regex]::Match($hostMenuFailure, '\{.*\}')).Value | ConvertFrom-Json).slot_failure
        Assert (@($hostMenuDoc.reselection.within_preset_lower | ForEach-Object { "$($_.model)/$($_.effort)" }) -ccontains 'glm-5.3-flash/high') 'Failure reselection menus follow the codex host menu'
        Assert ($global:HostMenuFailureCalls.Count -eq 1) 'Host-menu failure still makes exactly one launch call'
    }
    finally {
        Remove-Item Function:/global:codex -ErrorAction SilentlyContinue
        Remove-Variable HostMenuFailureCalls -Scope Global -ErrorAction SilentlyContinue
    }
    # Declared alternates fail closed at load; each case starts from the shipped policy.
    $fallbackCases = @(
        @{ name = 'missing slot declaration'; mutate = { param($p) $p.fallbacks.Remove('documentation_review') } },
        @{ name = 'alternate repeats the own route'; mutate = { param($p) $p.fallbacks.architecture_review = @(@{ preset = 'gpt6_luna_only'; model = 'gpt-6-luna'; effort = 'max' }) } },
        @{ name = 'tuple absent from its preset'; mutate = { param($p) $p.fallbacks.quick_triage = @(@{ preset = 'glm53_flash_only'; model = 'glm-5.3-flash'; effort = 'high' }) } },
        @{ name = 'duplicate alternate'; mutate = { param($p) $p.fallbacks.standard_review = @(@{ preset = 'claude_haiku55_only'; model = 'claude-haiku-5-5'; effort = 'high' }, @{ preset = 'claude_haiku55_only'; model = 'claude-haiku-5-5'; effort = 'high' }) } },
        @{ name = 'unknown preset'; mutate = { param($p) $p.fallbacks.quick_triage = @(@{ preset = 'gpt61_sol_only'; model = 'gpt-6.1-sol'; effort = 'max' }) } },
        @{ name = 'more than three alternates'; mutate = { param($p) $p.fallbacks.test_execution = @(1..4 | ForEach-Object { @{ preset = 'gemini38_flash_only'; model = 'gemini-3.8-flash-high'; effort = 'high' } }) } },
        @{ name = 'schema v5 policy'; mutate = { param($p) $p.schema_version = 5 } }
    )
    foreach ($fallbackCase in $fallbackCases) {
        $casePolicy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'presets.json') -Raw | ConvertFrom-Json -AsHashtable
        & $fallbackCase.mutate $casePolicy
        [IO.File]::WriteAllText($fixturePolicyPath, ($casePolicy | ConvertTo-Json -Depth 12))
        $caseRejected = $false
        try { & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Resolve | Out-Null } catch { $caseRejected = $true }
        Assert $caseRejected "Invalid declared fallback fails closed: $($fallbackCase.name)"
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'presets.json') -Destination $fixturePolicyPath -Force
    Assert ((& (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Resolve | ConvertFrom-Json).routes.architecture_review.declared_fallback.Count -eq 2) 'Restored shipped fallbacks resolve again'
}
finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    if (-not $resolvedFixture.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolvedFixture -Recurse
    if (Test-Path -LiteralPath $providerEvidencePath) { Remove-Item -LiteralPath $providerEvidencePath -Force }
}
"PASS: $count assertions (joint model pool, cross-model slots, read-only boundaries, extensible slots, removed-model rejection, projection idempotence, exact rollback)."
