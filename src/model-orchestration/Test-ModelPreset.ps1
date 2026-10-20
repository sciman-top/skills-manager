#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$count = 0

function Set-ModelSlotFixtureRunner([string]$Path) {
    $text = [IO.File]::ReadAllText($Path)
    $ast = [Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$null)
    $node = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-ModelSlotProcess' }, $true)
    if ($null -eq $node) { throw 'Fixture runner function not found.' }
    $mock = @'
function Invoke-ModelSlotProcess {
    param([string]$Executable, [string[]]$Arguments, [int]$LimitSeconds, [hashtable]$Environment = @{})
    $output = @(& $Executable @Arguments 2>&1)
    $timeout = $global:ModelSlotAcceptanceFailureMode -ceq 'process_timeout'
    [pscustomobject]@{
        started=$true; timed_out=$timeout; timeout_kind=$(if ($timeout) { 'process_timeout' } else { $null }); exit_code=$(if ($timeout) { 124 } else { $LASTEXITCODE }); output=$output
    }
}
'@
    [IO.File]::WriteAllText($Path, $text.Substring(0,$node.Extent.StartOffset) + $mock + $text.Substring($node.Extent.EndOffset))
}
$acceptanceFixture = Join-Path ([IO.Path]::GetTempPath()) ('model-slot-acceptance-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($acceptanceFixture) | Out-Null
foreach ($name in @('Set-ModelPreset.ps1','Start-ModelSlot.ps1','presets.json')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $acceptanceFixture
}
$acceptanceLauncher = Join-Path $acceptanceFixture 'Start-ModelSlot.ps1'
Set-ModelSlotFixtureRunner $acceptanceLauncher
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message }; $script:count++ }
$policy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'presets.json') -Raw | ConvertFrom-Json -AsHashtable
$slots = @($policy.slots)
$expected = @{
    glm53_flash_only    = @{ menu = @(,@('glm-5.3-flash','xhigh')); map = @{quick_triage=0;routine_maintenance=0;standard_review=0;bounded_implementation=0;deep_investigation=0;deep_implementation=0;test_execution=0;documentation_review=0;architecture_review=0} }
    gemini38_flash_only = @{ menu = @(,@('gemini-3.8-flash-high','high')); map = @{quick_triage=0;routine_maintenance=0;standard_review=0;bounded_implementation=0;deep_investigation=0;deep_implementation=0;test_execution=0;documentation_review=0;architecture_review=0} }
    gpt6_luna_only      = @{ menu = @(,@('gpt-6-luna','max')); map = @{quick_triage=0;routine_maintenance=0;standard_review=0;bounded_implementation=0;deep_investigation=0;deep_implementation=0;test_execution=0;documentation_review=0;architecture_review=0} }
}
Assert ($policy.presets.Count -eq 3 -and $slots.Count -gt 3) 'Three single-tier models and multiple slots'
Assert (('codex' -in $policy.presets['glm53_flash_only'].hosts) -and ('zcode' -in $policy.presets['glm53_flash_only'].hosts)) 'GLM host facets'
Assert (-not $policy.presets.Contains('claude_haiku55_only')) 'Retired Claude Haiku preset is absent from the pool'
Assert (@($policy.presets['gemini38_flash_only'].hosts).Count -eq 1 -and 'codex' -in $policy.presets['gemini38_flash_only'].hosts) 'Gemini stays codex-only'
$zcodeResolved = & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve -ExecutionHost zcode -Preset glm53_flash_only | ConvertFrom-Json -AsHashtable
Assert ($zcodeResolved.host -ceq 'zcode' -and $zcodeResolved.routes.quick_triage.model -ceq 'glm-5.3-flash' -and $zcodeResolved.routes.quick_triage.effort -ceq 'max') 'ZCode keeps the native GLM max facet'
Assert (@($zcodeResolved.enabled_routes | Where-Object { $_.model -ceq 'glm-5.3-flash' -and $_.effort -ceq 'max' }).Count -eq 1) 'ZCode exposes only the reviewed GLM max tuple'
Assert (@($zcodeResolved.enabled_routes).Count -eq 1) 'ZCode exposes no other model/effort tuple'
$zcodeAutoResolved = & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve -ExecutionHost zcode | ConvertFrom-Json -AsHashtable
Assert ($zcodeAutoResolved.auto_routing -and @($zcodeAutoResolved.active_presets).Count -eq 1 -and $zcodeAutoResolved.active_presets[0] -ceq 'glm53_flash_only') 'ZCode automatic routing narrows the pool to its native GLM facet'
foreach ($slot in $slots) { Assert ($zcodeAutoResolved.routes[$slot].model -ceq 'glm-5.3-flash' -and $zcodeAutoResolved.routes[$slot].effort -ceq 'max') "ZCode maps the supported native tuple to $slot" }
$claudeHostRejected = $false
try { & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve -ExecutionHost claude | Out-Null } catch { $claudeHostRejected = $_.Exception.Message -like '*No active preset is available on host claude*' }
Assert $claudeHostRejected 'Retired Claude host facet fails closed instead of resolving a Haiku pool'
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
Assert ($defaultResolved.active_presets.Count -eq 3 -and $defaultResolved.enabled_routes.Count -eq 3) 'Three presets expose three enabled codex tuples'
$expectedCodexTuples = @('gpt-6-luna/max','glm-5.3-flash/xhigh','gemini-3.8-flash-high/high') | Sort-Object
Assert (((@($defaultResolved.enabled_routes | ForEach-Object { "$($_.model)/$($_.effort)" } | Sort-Object) -join ',') -ceq ($expectedCodexTuples -join ','))) 'Codex exposes exactly the three approved tuples'
Assert (@($policy.auto_routes.Values | Select-Object -Unique).Count -eq 3) 'Automatic routes use all three pool model families'
Assert ((@($defaultResolved.enabled_routes | Where-Object { $_.model -ceq 'claude-haiku-5-5' })).Count -eq 0) 'Retired Haiku tuple is absent from enabled routes'
$autoRoutes = @{
    quick_triage = 'gemini38_flash_only'
    routine_maintenance = 'glm53_flash_only'
    standard_review = 'gemini38_flash_only'
    bounded_implementation = 'glm53_flash_only'
    deep_investigation = 'gpt6_luna_only'
    deep_implementation = 'gemini38_flash_only'
    test_execution = 'glm53_flash_only'
    documentation_review = 'gpt6_luna_only'
    architecture_review = 'gpt6_luna_only'
}
foreach ($slot in $slots) { Assert ($defaultResolved.auto_routing -and $defaultResolved.routes.$slot.preset -ceq $autoRoutes[$slot]) "Automatic task-shape route: $slot" }
$reselection = $defaultResolved.reselection
Assert ($null -ne $reselection -and @($reselection.rate_limit_order).Count -eq 3) 'Reselection contract derives from the active pool'
Assert ((@($reselection.rate_limit_order | Where-Object { $_.preset -ceq 'glm53_flash_only' })[0].menu | ForEach-Object { $_.effort }) -ccontains 'xhigh') 'Codex GLM menu uses the exact native xhigh tuple'
Assert ($reselection.prohibition.Contains('429') -and $reselection.prohibition.Contains('risk') -and $reselection.prohibition.Contains('never')) 'Reselection prohibition pins rate-limit and risk semantics'
Assert ($defaultResolved.dispatch_policy.max_controlled_launcher_invocations_per_bounded_task -eq 1 -and $defaultResolved.dispatch_policy.PSObject.Properties.Name -notcontains 'max_upstream_attempts_per_bounded_task' -and $defaultResolved.dispatch_policy.max_explicit_reselections -eq 1 -and -not $defaultResolved.dispatch_policy.duplicate_prompt_replay -and $defaultResolved.dispatch_policy.rate_limit_action -ceq 'stop_and_wait_for_fresh_parent_selection' -and $defaultResolved.dispatch_policy.auth_or_risk_action -ceq 'stop_and_operator_review' -and $defaultResolved.dispatch_policy.overload_action -ceq 'one_explicit_reselection_only') 'Controlled launcher safety policy'
Assert (@($defaultResolved.enabled_routes.model | Select-Object -Unique).Count -eq 3) 'Pool includes distinct model families'
Assert (@($defaultResolved.enabled_routes | Where-Object { $_.model -ceq 'gpt-6-luna' })[0].effort -ceq 'max') 'Luna tuple is pinned to max'
Assert ('gpt-5.6-terra' -cnotin @($defaultResolved.enabled_routes.model)) 'Terra removed from active pool'
$selected = & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve -AvailablePreset glm53_flash_only,gemini38_flash_only | ConvertFrom-Json
Assert ($selected.preset -eq 'glm53_flash_only') 'Ordered selection'
Assert ($selected.active_presets.Count -eq 2 -and $selected.enabled_routes.Count -eq 2) 'AvailablePreset retains the whole selected pool'
Assert ([int]$policy.schema_version -eq 7 -and @($policy.fallbacks.Keys).Count -eq $slots.Count) 'Schema v7 declares fallbacks and controlled-launch policy for every slot'
Assert ((@($defaultResolved.routes.architecture_review.declared_fallback | ForEach-Object { "$($_.model)/$($_.effort)" }) -join ',') -ceq 'glm-5.3-flash/xhigh,gemini-3.8-flash-high/high') 'Resolve exposes the declared alternates of each route'
Assert (@($zcodeResolved.routes.quick_triage.declared_fallback).Count -eq 0) 'ZCode pool exposes no alternate outside its reviewed facet'
Assert ((@($selected.routes.architecture_review.declared_fallback | ForEach-Object { "$($_.model)/$($_.effort)" }) -join ',') -ceq 'gemini-3.8-flash-high/high') 'Alternates stay inside the active pool and exclude the substituted route'
$cliSelection = & $acceptanceLauncher -Slot deep_investigation -AvailablePreset 'glm53_flash_only,gemini38_flash_only' -Plan | ConvertFrom-Json
Assert ($null -ne $cliSelection.preset -and $cliSelection.preset -eq 'glm53_flash_only' -and $cliSelection.route_preset -eq 'glm53_flash_only' -and $cliSelection.effort -eq 'xhigh' -and $cliSelection.delegation_enabled -eq $false) 'Native CLI chooses the first available preset when the deep investigation route (Luna) is excluded'
foreach ($legacyId in $policy.aliases.Keys) {
    $legacyResolved = & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve -Preset $legacyId | ConvertFrom-Json
    Assert ($legacyResolved.preset -ceq $policy.aliases[$legacyId]) 'Legacy preset alias'
}
$legacyRejected = $false
try { & (Join-Path $PSScriptRoot 'Set-ModelPreset.ps1') -Action Resolve -AvailablePreset gpt_terra_only,glm53_flash_only | Out-Null } catch { $legacyRejected = $true }
Assert $legacyRejected 'Removed Terra presets and aliases are rejected, not silently resolved'
foreach ($id in @($policy.active_presets)) {
    foreach ($slot in $slots) {
        $plan = & $acceptanceLauncher -Preset $id -Slot $slot -Plan | ConvertFrom-Json
        $pair = $expected[$id].menu[$expected[$id].map[$slot]]
        Assert ($plan.model -eq $pair[0] -and $plan.effort -eq $pair[1] -and $plan.delegation_enabled -eq $false) 'Frozen route and delegation disabled'
    }
}
foreach ($entry in $defaultResolved.enabled_routes) {
    foreach ($slot in $slots) {
        $plan = & $acceptanceLauncher -Slot $slot -Model $entry.model -Effort $entry.effort -Plan | ConvertFrom-Json
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
    @{Slot='standard_review';Model='claude-haiku-5-5';Effort='high'},
    @{Slot='standard_review';Model='claude-haiku-5-5';Effort='xhigh'},
    @{Slot='unknown_slot'},
    @{Slot='deep_investigation_or_implementation'},
    @{Slot='standard_review';Preset='gpt_terra_only'},
    @{Slot='standard_review';Preset='claude_haiku55_only'},
    @{Slot='standard_review';AvailablePreset=@('glm53_flash_only');Model='gpt-6-luna';Effort='max'}
)) {
    $rejected = $false
    try { & $acceptanceLauncher @invalidSelection -Plan | Out-Null } catch { $rejected = $true }
    Assert $rejected 'Reject removed, incomplete or out-of-pool selection'
}
$deepReadOnly = & $acceptanceLauncher -Slot deep_investigation -Model gemini-3.8-flash-high -Effort high -Plan | ConvertFrom-Json
Assert $deepReadOnly.read_only 'Deep investigation is read-only by slot contract'
$deepImplementation = & $acceptanceLauncher -Slot deep_implementation -Model gemini-3.8-flash-high -Effort high -Plan | ConvertFrom-Json
Assert (-not $deepImplementation.read_only) 'Deep implementation is a distinct write-capable slot'
$launcher = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Start-ModelSlot.ps1') -Raw
Assert ($launcher.Contains('no replay or preset substitution performed') -and $launcher.Contains('No arbitrary CLI pass-through')) 'Failed task must not replay'
$providerEvidencePath = Join-Path ([IO.Path]::GetTempPath()) ('model-provider-evidence-'+[guid]::NewGuid().ToString('N')+'.json')
$providerEvidence = [ordered]@{
    schema_version = 1
    provider_id = 'fixture_provider'
    surface = 'codex_provider_channel'
    observed_at = [DateTimeOffset]::UtcNow.AddMinutes(-5).ToString('o')
    expires_at = [DateTimeOffset]::UtcNow.AddMinutes(5).ToString('o')
    source = 'test-current-parent-receipt'
    tuples = @(
        @{ model = 'gpt-6-luna'; effort = 'max'; status = 'verified' },
        @{ model = 'glm-5.3-flash'; effort = 'xhigh'; status = 'verified' },
        @{ model = 'gemini-3.8-flash-high'; effort = 'high'; status = 'verified' }
    )
}
[IO.File]::WriteAllText($providerEvidencePath, ($providerEvidence | ConvertTo-Json -Depth 8))
$providerMismatchPath = Join-Path ([IO.Path]::GetTempPath()) ('model-provider-mismatch-'+[guid]::NewGuid().ToString('N')+'.json')
$providerMismatch = [ordered]@{
    schema_version = $providerEvidence.schema_version
    provider_id = 'other_fixture_provider'
    surface = $providerEvidence.surface
    observed_at = $providerEvidence.observed_at
    expires_at = $providerEvidence.expires_at
    source = $providerEvidence.source
    tuples = $providerEvidence.tuples
}
[IO.File]::WriteAllText($providerMismatchPath, ($providerMismatch | ConvertTo-Json -Depth 8))
$profileProviderEvidencePath = Join-Path ([IO.Path]::GetTempPath()) ('model-profile-provider-evidence-'+[guid]::NewGuid().ToString('N')+'.json')
$profileProviderEvidence = [ordered]@{
    schema_version = $providerEvidence.schema_version
    provider_id = 'fixture_profile_provider'
    surface = $providerEvidence.surface
    observed_at = $providerEvidence.observed_at
    expires_at = $providerEvidence.expires_at
    source = $providerEvidence.source
    tuples = $providerEvidence.tuples
}
[IO.File]::WriteAllText($profileProviderEvidencePath, ($profileProviderEvidence | ConvertTo-Json -Depth 8))
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
        if ($global:ModelSlotAcceptanceFailureMode -ceq 'mixed_events') { $global:ModelSlotAcceptanceErrorEvents }
        elseif ($global:ModelSlotAcceptanceFailureMode -ceq 'timeout_message_only') { '{"type":"turn.failed","error":{"message":"request timeout (simulated)"}}' }
        elseif ($global:ModelSlotAcceptanceFailureMode -ceq 'process_timeout') { '{"type":"turn.failed","error":{"code":"unknown"}}' }
        else { '{"type":"turn.failed","error":{"code":"rate_limit","message":"Too Many Requests (simulated)"}}' }
    }
    else { '{"type":"turn.completed"}' }
}
try {
    $providerMismatchFailure = ''
    try { & $acceptanceLauncher -Slot architecture_review -Model gpt-6-luna -Effort max -ReadOnly -CapabilityMode provider_override -CapabilityProbePath $providerMismatchPath -Prompt 'Mismatched provider must block' | Out-Null }
    catch { $providerMismatchFailure = $_.Exception.Message }
    Assert ($providerMismatchFailure -like '*provider_mismatch*' -and $providerMismatchFailure -like '*upstream_contacted*false*') 'Provider evidence must match the effective Codex provider'
    Assert ($global:ModelSlotAcceptanceCalls.Count -eq 0) 'Provider mismatch blocks before CLI launch'
    foreach ($failedRoute in @(
            @{ model = 'gpt-6-luna'; effort = 'max'; fallback = @('glm-5.3-flash/xhigh','gemini-3.8-flash-high/high'); lower = @() },
            @{ model = 'glm-5.3-flash'; effort = 'xhigh'; fallback = @('gemini-3.8-flash-high/high'); lower = @() },
            @{ model = 'gemini-3.8-flash-high'; effort = 'high'; fallback = @('glm-5.3-flash/xhigh'); lower = @() }
    )) {
        $failureMessage = ''
        try { & $acceptanceLauncher -Slot architecture_review -Model $failedRoute.model -Effort $failedRoute.effort -ReadOnly -CapabilityMode provider_override -CapabilityProbePath $providerEvidencePath -Prompt 'Simulated unavailable request' | Out-Null }
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
    Assert ($global:ModelSlotAcceptanceCalls.Count -eq 3) 'Failures never automatically retry'
    $global:ModelSlotAcceptanceFailureMode = 'timeout_message_only'
    $timeoutFailure = ''
    try { & $acceptanceLauncher -Slot architecture_review -Model gpt-6-luna -Effort max -ReadOnly -CapabilityMode provider_override -CapabilityProbePath $providerEvidencePath -Prompt 'Output contains timeout text but no structured code' | Out-Null }
    catch { $timeoutFailure = $_.Exception.Message }
    $timeoutJson = [regex]::Match($timeoutFailure, '\{.*\}')
    Assert $timeoutJson.Success 'Unclassified structured error still emits failure evidence'
    $timeoutDoc = ($timeoutJson.Value | ConvertFrom-Json).slot_failure
    Assert ($timeoutDoc.failure_class -ceq 'unknown' -and $timeoutDoc.failure_source -ceq 'structured_error_unclassified' -and $timeoutDoc.retry_policy.next_action -ceq 'diagnose_before_any_new_dispatch') 'Timeout text without a structured code stays unknown'
    $global:ModelSlotAcceptanceFailureMode = 'process_timeout'
    $callsBeforeTimeout = $global:ModelSlotAcceptanceCalls.Count
    $processTimeoutFailure = ''
    try { & $acceptanceLauncher -Slot architecture_review -Model gpt-6-luna -Effort max -ReadOnly -CapabilityMode provider_override -CapabilityProbePath $providerEvidencePath -TimeoutSeconds 1 -Prompt 'Simulated process timeout without replay' | Out-Null }
    catch { $processTimeoutFailure = $_.Exception.Message }
    $processTimeoutMatch = [regex]::Match($processTimeoutFailure, '\{.*\}')
    Assert $processTimeoutMatch.Success 'Launcher timeout emits structured failure evidence'
    $processTimeoutDoc = ($processTimeoutMatch.Value | ConvertFrom-Json).slot_failure
    Assert ($processTimeoutDoc.failure_class -ceq 'launcher_timeout' -and $processTimeoutDoc.execution.timed_out -and $processTimeoutDoc.exit -eq 124 -and $processTimeoutDoc.retry_policy.next_action -ceq 'diagnose_before_any_new_dispatch') 'Launcher timeout requires diagnosis rather than alternate model dispatch'
    Assert ($global:ModelSlotAcceptanceCalls.Count -eq $callsBeforeTimeout + 1 -and -not $processTimeoutDoc.retry_policy.replay_allowed) 'Launcher timeout makes exactly one controlled call with no replay'
    $global:ModelSlotAcceptanceFailureMode = 'rate_limit'
    $budgetMessage = ''
    try { & $acceptanceLauncher -Slot architecture_review -Model glm-5.3-flash -Effort xhigh -ReadOnly -CapabilityMode provider_override -CapabilityProbePath $providerEvidencePath -ReselectionCount 1 -Prompt 'Budget must block before launch' | Out-Null }
    catch { $budgetMessage = $_.Exception.Message }
    Assert ($budgetMessage -like '*Reselection budget exhausted*' -and $budgetMessage -like '*no upstream request was sent*') 'Exhausted reselection budget blocks dispatch'
    Assert ($global:ModelSlotAcceptanceCalls.Count -eq 5) 'Exhausted reselection budget makes no launch call'
    $budgetJson = [regex]::Match($budgetMessage, '\{.*\}')
    Assert $budgetJson.Success 'Budget block emits structured evidence'
    $budget = ($budgetJson.Value | ConvertFrom-Json).reselection_budget_exhausted
    Assert ($budget.reselection_count -eq 1 -and $budget.max_explicit_reselections -eq 1 -and $budget.upstream_contacted -eq $false) 'Budget evidence records the hard stop'
    $global:ModelSlotAcceptanceExitCode = 0
    & $acceptanceLauncher -Slot architecture_review -Model glm-5.3-flash -Effort xhigh -ReadOnly -CapabilityMode provider_override -CapabilityProbePath $providerEvidencePath -Prompt 'Explicit remaining read-only work' | Out-Null
    Assert ($global:ModelSlotAcceptanceCalls.Count -eq 6) 'Parent can explicitly select the next supported model'
    foreach ($call in $global:ModelSlotAcceptanceCalls) {
        Assert ($call -ccontains 'read-only' -and $call -ccontains 'agents.enabled=false' -and (($call -ccontains 'model_reasoning_effort="max"') -or ($call -ccontains 'model_reasoning_effort="xhigh"') -or ($call -ccontains 'model_reasoning_effort="high"'))) 'All launches preserve read-only, fixed tuple and no nested delegation'
        Assert ($call -ccontains 'model_providers.fixture_provider.request_max_retries=0' -and $call -ccontains 'model_providers.fixture_provider.stream_max_retries=0') 'Codex CLI retries are capped for the selected custom provider'
    }

    $global:ModelSlotAcceptanceExitCode = 1
    $global:ModelSlotAcceptanceFailureMode = 'mixed_events'
    foreach ($failureCase in @(
        @{ codes = @('service_unavailable','rate_limit'); class = 'rate_limit'; action = 'stop_and_wait_for_fresh_parent_selection' },
        @{ codes = @('rate_limit','service_unavailable'); class = 'rate_limit'; action = 'stop_and_wait_for_fresh_parent_selection' },
        @{ codes = @('service_unavailable','unauthorized'); class = 'auth_or_permission'; action = 'stop_and_operator_review' },
        @{ codes = @('rate_limit','account_risk'); class = 'account_risk'; action = 'stop_and_operator_review' },
        @{ codes = @('account_risk','rate_limit'); class = 'account_risk'; action = 'stop_and_operator_review' },
        @{ codes = @('service_unavailable','tool_error'); class = 'tool_or_environment'; action = 'diagnose_before_any_new_dispatch' },
        @{ codes = @('service_unavailable'); class = 'upstream_unavailable'; action = 'one_explicit_reselection_only' }
    )) {
        $global:ModelSlotAcceptanceErrorEvents = @($failureCase.codes | ForEach-Object { @{ type='turn.failed'; error=@{ code=$_ } } | ConvertTo-Json -Compress })
        $beforeFailureCalls = $global:ModelSlotAcceptanceCalls.Count
        $mixedFailure = ''
        try { & $acceptanceLauncher -Slot architecture_review -Model gpt-6-luna -Effort max -ReadOnly -CapabilityMode provider_override -CapabilityProbePath $providerEvidencePath -Prompt 'Classify complete failure stream without replay' | Out-Null }
        catch { $mixedFailure = $_.Exception.Message }
        $mixedDoc = (([regex]::Match($mixedFailure, '{.*}')).Value | ConvertFrom-Json).slot_failure
        Assert ($mixedDoc.failure_class -ceq $failureCase.class -and $mixedDoc.retry_policy.next_action -ceq $failureCase.action) "Complete stream classification: $($failureCase.codes -join ',')"
        Assert ($global:ModelSlotAcceptanceCalls.Count -eq ($beforeFailureCalls + 1)) 'Mixed failure events never cause a retry'
    }
    $global:ModelSlotAcceptanceExitCode = 0
    $global:ModelSlotAcceptanceFailureMode = 'rate_limit'

    $profileConfigPath = Join-Path $testCodexHome 'glm53-flash-only.config.toml'
    $profileConfigText = @'
model_provider = "fixture_profile_provider"

[model_providers.fixture_profile_provider]
name = "profile-fixture"
base_url = "https://profile-fixture.invalid/v1"
'@
    [IO.File]::WriteAllText($profileConfigPath, $profileConfigText)
    & $acceptanceLauncher -Slot architecture_review -Model glm-5.3-flash -Effort xhigh -ReadOnly -CapabilityMode provider_override -CapabilityProbePath $profileProviderEvidencePath -Prompt 'Profile provider wins' | Out-Null
    $profileCall = $global:ModelSlotAcceptanceCalls[$global:ModelSlotAcceptanceCalls.Count - 1]
    Assert ($profileCall -ccontains 'model_providers.fixture_profile_provider.request_max_retries=0' -and $profileCall -ccontains 'model_providers.fixture_profile_provider.stream_max_retries=0' -and -not ($profileCall -ccontains 'model_providers.fixture_provider.request_max_retries=0')) 'Profile provider takes precedence over base config for retry control'

    Remove-Item -LiteralPath $profileConfigPath
    [IO.File]::WriteAllText($codexConfigPath, 'model = "gpt-6-luna"' + [Environment]::NewLine)
    $beforeRetryControlBlock = $global:ModelSlotAcceptanceCalls.Count
    $retryControlFailure = ''
    try { & $acceptanceLauncher -Slot architecture_review -Model gpt-6-luna -Effort max -ReadOnly -CapabilityMode native -Prompt 'Must block without retry control' | Out-Null }
    catch { $retryControlFailure = $_.Exception.Message }
    Assert ($retryControlFailure -like '*retry_control_unavailable*' -and $retryControlFailure -like '*upstream_contacted*false*') 'Missing custom-provider retry control blocks before dispatch'
    Assert ($global:ModelSlotAcceptanceCalls.Count -eq $beforeRetryControlBlock) 'Retry-control blocker makes no model call'
    $overrideRetryControlFailure = ''
    try { & $acceptanceLauncher -Slot architecture_review -Model gpt-6-luna -Effort max -ReadOnly -CapabilityMode provider_override -CapabilityProbePath $providerEvidencePath -Prompt 'Provider override must block without retry control' | Out-Null }
    catch { $overrideRetryControlFailure = $_.Exception.Message }
    Assert ($overrideRetryControlFailure -like '*retry_control_unavailable*' -and $overrideRetryControlFailure -like '*upstream_contacted*false*') 'Provider override also fails closed without retry control'
    Assert ($global:ModelSlotAcceptanceCalls.Count -eq $beforeRetryControlBlock) 'Provider-override retry-control blocker makes no model call'
}
finally {
    Remove-Item Function:/global:codex
    $acceptanceResolved = [IO.Path]::GetFullPath($acceptanceFixture)
    if (-not $acceptanceResolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe acceptance fixture path.' }
    Remove-Item -LiteralPath $acceptanceResolved -Recurse
    Remove-Variable ModelSlotAcceptanceCalls,ModelSlotAcceptanceExitCode,ModelSlotAcceptanceFailureMode,ModelSlotAcceptanceErrorEvents -Scope Global -ErrorAction SilentlyContinue
    if ($null -eq $previousCodexHome) { Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue } else { $env:CODEX_HOME = $previousCodexHome }
    Remove-Item -LiteralPath $testCodexHome -Recurse -Force -ErrorAction SilentlyContinue
}
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('model-preset-test-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
try {
    foreach ($name in @('Set-ModelPreset.ps1','Start-ModelSlot.ps1','presets.json')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $fixture }
    Set-ModelSlotFixtureRunner (Join-Path $fixture 'Start-ModelSlot.ps1')
    $target = Join-Path $fixture 'codex'
    [IO.Directory]::CreateDirectory($target) | Out-Null
    $cfg = Join-Path $target 'config.toml'
    $original = "model = `"old`"`r`nmodel_provider = `"preserve-provider`"`r`n[agents]`r`nenabled = true`r`nmax_concurrent_threads_per_session = 2`r`n"
    [IO.File]::WriteAllText($cfg,$original,[Text.UTF8Encoding]::new($true))
    $projectionCapabilityPath = Join-Path $fixture 'models-all-supported.json'
    $catalogBinding = @{
        source = 'codex debug models'
        codex_root = $target
        observed_at = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')
        expires_at = [DateTimeOffset]::UtcNow.AddMinutes(3).ToString('o')
    }
    $projectionCatalog = $catalogBinding.Clone()
    $projectionCatalog.models = @(
        @{ slug = 'gpt-6-luna'; supported_reasoning_levels = @(@{ effort = 'max' }) },
        @{ slug = 'glm-5.3-flash'; supported_reasoning_levels = @(@{ effort = 'xhigh' }) },
        @{ slug = 'gemini-3.8-flash-high'; supported_reasoning_levels = @(@{ effort = 'high' }) }
    )
    [IO.File]::WriteAllText($projectionCapabilityPath, ($projectionCatalog | ConvertTo-Json -Depth 8))
    $before = (Get-FileHash -LiteralPath $cfg).Hash
    $receipt = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -CodexRoot $target -CapabilityProbePath $projectionCapabilityPath | ConvertFrom-Json
    Assert ($receipt.capability.status -ceq 'native_supported' -and @($receipt.capability.tuples).Count -eq 3) 'Apply records the verified native tuple set'
    Assert ($receipt.capability.codex_root -ceq $target -and $receipt.capability.evidence_kind -ceq 'bound_snapshot' -and ([DateTimeOffset]$receipt.capability.observed_at) -eq ([DateTimeOffset]$catalogBinding.observed_at)) 'Capability receipt preserves the bound snapshot identity'
    Assert (-not $receipt.host_loaded -and $receipt.execution_boundary -like '*named model-pinned native slots and tuple roles*') 'Apply records the native projection boundary without claiming host load'
    Assert ((Get-Content -LiteralPath $cfg -Raw).Contains('preserve-provider')) 'Provider changed'
    $projectedConfig = Get-Content -LiteralPath $cfg -Raw
    Assert ($projectedConfig.Contains('# availability-rules: ') -and $projectedConfig.Contains('429/quota/rate-limit/auth/risk: stop and wait') -and $projectedConfig.Contains('No hot-swap, aliasing, effort substitution')) 'Shared config carries the stop-and-wait availability rules'
    $profileText = Get-Content -LiteralPath (Join-Path $target 'glm53-flash-only.config.toml') -Raw
    Assert ($profileText.Contains('choose the named native execution slot by task shape before dispatch') -and $profileText.Contains('Do not replay an identical prompt')) 'Profile instructions require task-shape native slot dispatch and prohibit duplicate replay'
    Assert ($profileText.Contains('confirmed overload may receive one explicit reselection only')) 'Profile instructions reserve one alternate for confirmed overload'
    Assert ($profileText.Contains('On Codex, use the named native slot or exact-tuple role') -and $profileText.Contains('not a substitute for native subagent dispatch')) 'Profile instructions make exact-tuple native roles primary and keep the CLI launcher explicit'
    Assert ($profileText.Contains('[agents]') -and $profileText.Contains('default_subagent_model = "glm-5.3-flash"') -and $profileText.Contains('default_subagent_reasoning_effort = "xhigh"') -and -not $profileText.Contains('enabled = false')) 'GLM profile defaults to its own native tuple and keeps delegation enabled'
    $lunaProfileText = Get-Content -LiteralPath (Join-Path $target 'gpt6-luna-only.config.toml') -Raw
    Assert ($lunaProfileText.Contains('default_subagent_model = "gpt-6-luna"') -and $lunaProfileText.Contains('default_subagent_reasoning_effort = "max"') -and -not $lunaProfileText.Contains('enabled = false')) 'Luna profile pins its allowed native default tuple'
    $projectedAgentTables = @([regex]::Matches($projectedConfig, '(?m)^\[agents\.([^\]]+)\]') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
    Assert ($projectedAgentTables.Count -eq ($slots.Count + $expectedCodexTuples.Count)) 'Shared Codex config registers all nine task slots and three exact-tuple roles'
    foreach ($slot in $slots) { Assert ($projectedConfig.Contains("[agents.$slot]")) "Shared Codex config registers task slot $slot" }
    Assert (-not (Test-Path -LiteralPath (Join-Path $target 'hooks.json'))) 'Projection must not install hooks'
    Assert ((& (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Plan -CodexRoot $target -CapabilityProbePath $projectionCapabilityPath | ConvertFrom-Json).files.Count -eq 0) 'Not idempotent'
    & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Rollback -CodexRoot $target -ReceiptPath $receipt.receipt | Out-Null
    Assert ((Get-FileHash -LiteralPath $cfg).Hash -ceq $before) 'Rollback must restore exact bytes including BOM'
    $nonLunaReceipt = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -AvailablePreset @('glm53_flash_only','gemini38_flash_only') -CodexRoot $target -CapabilityProbePath $projectionCapabilityPath | ConvertFrom-Json
    $nonLunaConfig = Get-Content -LiteralPath $cfg -Raw
    Assert ($nonLunaConfig.Contains('enabled = true') -and -not $nonLunaConfig.Contains('# model-orchestration-native-agents-enabled-prior=') -and $nonLunaConfig.Contains('default_subagent_model = "glm-5.3-flash"') -and $nonLunaConfig.Contains('default_subagent_reasoning_effort = "xhigh"') -and $nonLunaConfig.Contains('max_concurrent_threads_per_session = 2')) 'Non-Luna pool keeps native agents enabled and defaults to its routine slot tuple'
    Assert (@([regex]::Matches($nonLunaConfig, '(?m)^\[agents\.([^\]]+)\]')).Count -eq ($slots.Count + $expectedCodexTuples.Count - 1)) 'Non-Luna pool projects its two exact tuple roles and all task slots'
    $nonLunaProfileDefaults = @{
        'glm53-flash-only' = @{ model = 'glm-5.3-flash'; effort = 'xhigh' }
        'gemini38-flash-only' = @{ model = 'gemini-3.8-flash-high'; effort = 'high' }
    }
    foreach ($profileName in $nonLunaProfileDefaults.Keys) {
        $profileConfigText = Get-Content -LiteralPath (Join-Path $target "$profileName.config.toml") -Raw
        $profileDefault = $nonLunaProfileDefaults[$profileName]
        Assert ($profileConfigText.Contains("default_subagent_model = `"$($profileDefault.model)`"") -and $profileConfigText.Contains("default_subagent_reasoning_effort = `"$($profileDefault.effort)`"") -and -not $profileConfigText.Contains('enabled = false')) "Profile defaults to its native routine tuple and keeps delegation enabled: $profileName"
    }
    foreach ($profileId in @('glm53_flash_only','gemini38_flash_only')) {
        $profilePolicy = $policy.presets[$profileId]
        $profileConfigText = Get-Content -LiteralPath (Join-Path $target "$($profileId.Replace('_','-')).config.toml") -Raw
        Assert (-not $profileConfigText.Contains('enabled = false')) "Preset profile leaves native delegation enabled: $profileId"
        foreach ($slot in $slots) {
            $profileEntry = $profilePolicy.menu[$profilePolicy.slot_map[$slot]]
            $slotConfigText = Get-Content -LiteralPath (Join-Path $fixture ".generated/codex/$profileId/$slot.toml") -Raw
            Assert ($profileConfigText.Contains("[agents.$slot]") -and $slotConfigText.Contains("model = `"$($profileEntry.model)`"") -and $slotConfigText.Contains("model_reasoning_effort = `"$($profileEntry.effort)`"")) "Profile slot pins its configured tuple: $profileId/$slot -> $($profileEntry.model)/$($profileEntry.effort)"
        }
    }
    $restoredReceipt = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -CodexRoot $target -CapabilityProbePath $projectionCapabilityPath | ConvertFrom-Json
    $restoredConfig = Get-Content -LiteralPath $cfg -Raw
    Assert ($restoredConfig.Contains('enabled = true') -and $restoredConfig.Contains('default_subagent_model = "glm-5.3-flash"') -and $restoredConfig.Contains('default_subagent_reasoning_effort = "xhigh"') -and -not $restoredConfig.Contains('model-orchestration-native-agents-enabled-prior=')) 'Full active pool defaults to the routine native route and preserves delegation'
    & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Rollback -CodexRoot $target -ReceiptPath $restoredReceipt.receipt | Out-Null
    & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Rollback -CodexRoot $target -ReceiptPath $nonLunaReceipt.receipt | Out-Null
    Assert ((Get-FileHash -LiteralPath $cfg).Hash -ceq $before) 'Non-Luna native projection and restore sequence rolls back to the exact original config'
    $zcodeTarget = Join-Path $fixture 'zcode'
    $zcodeAgents = Join-Path $zcodeTarget 'agents'
    [IO.Directory]::CreateDirectory($zcodeAgents) | Out-Null
    $zcodeSourcePath = Join-Path $zcodeAgents 'glm-max.md'
    $zcodeSourceText = @('---','name: glm-max','description: Existing host-owned GLM max definition','model: "account:test-plan/GLM-5.3-Flash"','thoughtLevel: max','---','','Keep this source agent untouched.') -join "`n"
    [IO.File]::WriteAllText($zcodeSourcePath, $zcodeSourceText + "`n", [Text.UTF8Encoding]::new($false))
    $zcodeSourceHash = (Get-FileHash -LiteralPath $zcodeSourcePath -Algorithm SHA256).Hash
    $zcodeFullPlanRejected = $false
    try { & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Plan -ExecutionHost zcode -ZCodeRoot $zcodeTarget | Out-Null }
    catch { $zcodeFullPlanRejected = $_.Exception.Message -like '*ZCode projection supports only -SubagentsOnly*' }
    Assert $zcodeFullPlanRejected 'ZCode plan rejects a misleading full-preset scope'
    $zcodePlan = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Plan -SubagentsOnly -ExecutionHost zcode -ZCodeRoot $zcodeTarget | ConvertFrom-Json -AsHashtable
    Assert ($zcodePlan.host -ceq 'zcode' -and $zcodePlan.scope -ceq 'subagents_only' -and @($zcodePlan.files).Count -eq $slots.Count -and $zcodePlan.capability.host -ceq 'zcode') 'ZCode plan lists only the native slot-agent projection'
    Assert ((Get-FileHash -LiteralPath $zcodeSourcePath -Algorithm SHA256).Hash -ceq $zcodeSourceHash -and -not (Test-Path -LiteralPath (Join-Path $zcodeAgents 'skills-manager-quick-triage.md'))) 'ZCode plan preserves its model source and writes no files'
    foreach ($slot in $slots) { Assert ($zcodePlan.routes[$slot].model -ceq 'glm-5.3-flash' -and $zcodePlan.routes[$slot].effort -ceq 'max') "ZCode plan routes $slot through GLM/max" }
    $zcodeReceipt = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -SubagentsOnly -ExecutionHost zcode -ZCodeRoot $zcodeTarget | ConvertFrom-Json
    Assert ($zcodeReceipt.host -ceq 'zcode' -and $zcodeReceipt.changed -eq $slots.Count -and $zcodeReceipt.host_loaded -eq $false) 'ZCode Apply records filesystem projection without claiming host load'
    foreach ($slot in $slots) {
        $agentName = "skills-manager-$($slot.Replace('_','-'))"
        $agentPath = Join-Path $zcodeAgents "$agentName.md"
        $agentText = Get-Content -LiteralPath $agentPath -Raw
        Assert ($agentText.Contains("name: $agentName") -and $agentText.Contains('model: "account:test-plan/GLM-5.3-Flash"') -and $agentText.Contains('thoughtLevel: max') -and $agentText.Contains('managed-by: skills-manager/model-orchestration')) "ZCode agent pins host model/max and is marked as managed: $slot"
        Assert ($agentText.Contains('Read-only: do not modify files or external state.') -eq ($slot -cin @($policy.read_only_slots))) "ZCode agent retains the semantic read-only boundary: $slot"
    }
    Assert ((Get-FileHash -LiteralPath $zcodeSourcePath -Algorithm SHA256).Hash -ceq $zcodeSourceHash) 'ZCode projection does not edit its host-owned source agent'
    Assert ((& (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Plan -SubagentsOnly -ExecutionHost zcode -ZCodeRoot $zcodeTarget | ConvertFrom-Json).files.Count -eq 0) 'ZCode projection is idempotent'
    & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Rollback -ReceiptPath $zcodeReceipt.receipt | Out-Null
    Assert ((Get-FileHash -LiteralPath $zcodeSourcePath -Algorithm SHA256).Hash -ceq $zcodeSourceHash -and @((Get-ChildItem -LiteralPath $zcodeAgents -Filter 'skills-manager-*.md' -File)).Count -eq 0) 'ZCode rollback removes only generated slots and preserves the source agent'
    $zcodeCollisionPath = Join-Path $zcodeAgents 'skills-manager-quick-triage.md'
    [IO.File]::WriteAllText($zcodeCollisionPath, 'name: user-owned')
    $zcodeCollisionHash = (Get-FileHash -LiteralPath $zcodeCollisionPath -Algorithm SHA256).Hash
    $zcodeCollisionRejected = $false
    try { & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Plan -SubagentsOnly -ExecutionHost zcode -ZCodeRoot $zcodeTarget | Out-Null }
    catch { $zcodeCollisionRejected = $_.Exception.Message -like '*Refusing to overwrite user-owned ZCode agent*' }
    Assert ($zcodeCollisionRejected -and (Get-FileHash -LiteralPath $zcodeCollisionPath -Algorithm SHA256).Hash -ceq $zcodeCollisionHash) 'ZCode projection refuses an unmarked user-owned agent'
    Remove-Item -LiteralPath $zcodeCollisionPath -Force
    $zcodeInvalidModel = $zcodeSourceText.Replace('account:test-plan/GLM-5.3-Flash','account:test-plan/GLM-5.2-Flash')
    [IO.File]::WriteAllText($zcodeSourcePath, $zcodeInvalidModel + "`n", [Text.UTF8Encoding]::new($false))
    $zcodeInvalidRejected = $false
    try { & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Plan -SubagentsOnly -ExecutionHost zcode -ZCodeRoot $zcodeTarget | Out-Null }
    catch { $zcodeInvalidRejected = $_.Exception.Message -like '*must name the configured GLM-5.3-Flash model*' }
    Assert ($zcodeInvalidRejected -and @((Get-ChildItem -LiteralPath $zcodeAgents -Filter 'skills-manager-*.md' -File)).Count -eq 0) 'ZCode projection fails closed when its host model source drifts'
    [IO.File]::WriteAllText($zcodeSourcePath, $zcodeSourceText + "`n", [Text.UTF8Encoding]::new($false))
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
    Assert ($subagentPlan.native_agent_policy.enabled -and $subagentPlan.native_agent_policy.default_slot -ceq 'routine_maintenance' -and $subagentPlan.native_agent_policy.default_model -ceq 'glm-5.3-flash' -and $subagentPlan.native_agent_policy.default_effort -ceq 'xhigh' -and @($subagentPlan.native_agent_policy.tuple_roles).Count -eq 3) 'Plan describes all three native tuple roles and its routine-slot default'
    $subagentReceipt = & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -SubagentsOnly -CodexRoot $target -CapabilityProbePath $projectionCapabilityPath | ConvertFrom-Json
    $subagentConfig = Get-Content -LiteralPath $cfg -Raw
    Assert ($subagentConfig.StartsWith($parentRoot.Substring(0, $parentRoot.IndexOf('[agents]')).Replace("`r`n","`n"))) 'Subagent projection preserves exact parent lines and comments'
    Assert ($subagentConfig.Contains('default_subagent_model = "glm-5.3-flash"') -and $subagentConfig.Contains('default_subagent_reasoning_effort = "xhigh"')) 'Subagent default follows the routine-maintenance auto route'
    Assert ($subagentConfig.Contains('max_concurrent_threads_per_session = 2') -and $subagentConfig.Contains('enabled = true')) 'Native delegation and concurrency preserved'
    foreach ($entry in $defaultResolved.enabled_routes) {
        $nativeTuple = "$($entry.model)/$($entry.effort)" -cin $expectedCodexTuples
        $rolePath = Join-Path $fixture ".generated/codex/pool/$($entry.role).toml"
        Assert (($subagentConfig.Contains("[agents.$($entry.role)]")) -eq $nativeTuple) "Exact allowlisted tuple role registration: $($entry.role)"
        Assert ((Test-Path -LiteralPath $rolePath) -eq $nativeTuple) "Generated native tuple file matches the verified pool: $($entry.role)"
        if ($nativeTuple) {
            $roleText = Get-Content -LiteralPath $rolePath -Raw
            Assert ($roleText.Contains("model = `"$($entry.model)`"") -and $roleText.Contains("model_reasoning_effort = `"$($entry.effort)`"") -and -not $roleText.Contains('[agents]') -and -not $roleText.Contains('sandbox_mode')) "Native tuple role pins its exact approved model/effort without embedding parent-session settings: $($entry.role)"
            Assert ($roleText.Contains('Do not delegate')) 'Native tuple role instructs the child not to delegate'
        }
    }
    foreach ($slot in $slots) {
        $route = $defaultResolved.routes.$slot
        $rolePath = Join-Path $fixture ".generated/codex/$($route.preset)/$slot.toml"
        $roleText = Get-Content -LiteralPath $rolePath -Raw
        Assert ($subagentConfig.Contains("[agents.$slot]") -and $roleText.Contains("name = `"$slot`"") -and $roleText.Contains("model = `"$($route.model)`"") -and $roleText.Contains("model_reasoning_effort = `"$($route.effort)`"") -and $roleText.Contains('Do not delegate or change models.')) "Native execution slot pins the automatic task-shape tuple: $slot -> $($route.model)/$($route.effort)"
    }
    Assert (-not $subagentConfig.Contains('[agents.terra') -and -not $subagentConfig.Contains('default_subagent_model = "gpt-5.6-terra"')) 'Managed projection excludes removed Terra roles and defaults'
    Assert ((& (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Plan -SubagentsOnly -CodexRoot $target -CapabilityProbePath $projectionCapabilityPath | ConvertFrom-Json).files.Count -eq 0) 'Subagent projection is idempotent'
    & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Rollback -ReceiptPath $subagentReceipt.receipt | Out-Null
    Assert ((Get-FileHash -LiteralPath $cfg).Hash -ceq $parentBefore) 'Subagent rollback restores exact parent config bytes'
    $catalogPath = Join-Path $fixture 'models.json'
    $catalog = $catalogBinding.Clone()
    $catalog.models = @(
        @{ slug = 'gpt-6-luna'; supported_reasoning_levels = @(@{ effort = 'max' }) },
        @{ slug = 'glm-5.3-flash'; supported_reasoning_levels = @(@{ effort = 'max' }) },
        @{ slug = 'gemini-3.8-flash-high'; supported_reasoning_levels = @(@{ effort = 'max' }) }
    )
    [IO.File]::WriteAllText($catalogPath, ($catalog | ConvertTo-Json -Depth 8))
    $blockedProjectionBefore = (Get-FileHash -LiteralPath $cfg).Hash
    $blockedProjectionMessage = ''
    try { & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Apply -CodexRoot $target -CapabilityProbePath $catalogPath | Out-Null }
    catch { $blockedProjectionMessage = $_.Exception.Message }
    Assert ($blockedProjectionMessage -like '*capability preflight blocked projection*' -and $blockedProjectionMessage -like '*no host files were written*') 'Unsupported native projection fails closed'
    Assert ((Get-FileHash -LiteralPath $cfg).Hash -ceq $blockedProjectionBefore) 'Blocked native projection leaves host config unchanged'
    $previousFixtureCodexHome = $env:CODEX_HOME
    $providerExecutionHome = Join-Path $fixture 'provider-execution-home'
    [IO.Directory]::CreateDirectory($providerExecutionHome) | Out-Null
    [IO.File]::WriteAllText((Join-Path $providerExecutionHome 'config.toml'), $codexConfigText)
    $env:CODEX_HOME = $providerExecutionHome
    $catalog.codex_root = $providerExecutionHome
    [IO.File]::WriteAllText($catalogPath, ($catalog | ConvertTo-Json -Depth 8))
    $global:CapabilityCalls = [Collections.Generic.List[object]]::new()
    function global:codex {
        $global:CapabilityCalls.Add(@($args))
        $global:LASTEXITCODE = 0
        '{"type":"turn.completed"}'
    }
    try {
        $blocked = $false
        try { & (Join-Path $fixture 'Start-ModelSlot.ps1') -Slot standard_review -Model glm-5.3-flash -Effort xhigh -CapabilityProbePath $catalogPath -Prompt 'blocked native tuple' | Out-Null }
        catch { $blocked = $_.Exception.Message -like '*no model request was sent*' -and $_.Exception.Message -like '*tuple_unsupported*' }
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
        if ($null -eq $previousFixtureCodexHome) { Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue } else { $env:CODEX_HOME = $previousFixtureCodexHome }
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
    $customRootConfig = Get-Content -LiteralPath $cfg -Raw
    $customLunaProfile = Get-Content -LiteralPath (Join-Path $target 'gpt6-luna-only.config.toml') -Raw
    $customRootRole = Get-Content -LiteralPath (Join-Path $fixture '.generated/codex/glm53_flash_only/custom_task.toml') -Raw
    $customLunaRole = Get-Content -LiteralPath (Join-Path $fixture '.generated/codex/gpt6_luna_only/custom_task.toml') -Raw
    Assert ($customRootConfig.Contains('[agents.custom_task]') -and $customRootRole.Contains('model = "glm-5.3-flash"') -and $customRootRole.Contains('model_reasoning_effort = "xhigh"') -and $customLunaProfile.Contains('[agents.custom_task]') -and $customLunaRole.Contains('model = "gpt-6-luna"') -and $customLunaRole.Contains('model_reasoning_effort = "max"')) 'Additional slot uses its GLM auto route natively and keeps its exact tuple in every profile'
    & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Rollback -ReceiptPath $customReceipt.receipt | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'presets.json') -Destination $fixturePolicyPath -Force
    $descendingPolicy = Get-Content -LiteralPath $fixturePolicyPath -Raw | ConvertFrom-Json -AsHashtable
    # No active model exposes two allowlisted efforts any more; appending the same single
    # allowlisted tuple still violates the strict-increase order check with allowed tuples.
    $descendingPolicy.presets.glm53_flash_only.menu += @{model='glm-5.3-flash';effort='xhigh'}
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
    $hostMenus['codex'] = @(@{ model = 'glm-5.3-flash'; effort = 'xhigh' })
    $hostMenuPolicy.presets['glm53_flash_only']['host_menus'] = $hostMenus
    foreach ($slot in $slots) { $hostMenuPolicy.presets['glm53_flash_only'].slot_map[$slot] = 0 }
    [IO.File]::WriteAllText($fixturePolicyPath, ($hostMenuPolicy | ConvertTo-Json -Depth 12))
    $hostMenuEvidencePath = Join-Path $fixture 'models-host-menu-evidence.json'
    $hostMenuEvidence = [ordered]@{
        schema_version = 1
        provider_id = 'fixture_provider'
        surface = 'codex_provider_channel'
        observed_at = [DateTimeOffset]::UtcNow.AddMinutes(-5).ToString('o')
        expires_at = [DateTimeOffset]::UtcNow.AddMinutes(5).ToString('o')
        source = 'test-host-menu-reselection'
        tuples = @(
            @{ model = 'glm-5.3-flash'; effort = 'xhigh'; status = 'verified' },
            @{ model = 'gemini-3.8-flash-high'; effort = 'high'; status = 'verified' }
        )
    }
    [IO.File]::WriteAllText($hostMenuEvidencePath, ($hostMenuEvidence | ConvertTo-Json -Depth 8))
    $previousHostMenuCodexHome = $env:CODEX_HOME
    $env:CODEX_HOME = $providerExecutionHome
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
        Assert ($hostMenuFailure -like '*no replay or preset substitution performed*') "Host-menu failure returns control without replay: $hostMenuFailure"
        $hostMenuDoc = (([regex]::Match($hostMenuFailure, '\{.*\}')).Value | ConvertFrom-Json).slot_failure
        Assert (@($hostMenuDoc.reselection.within_preset_lower).Count -eq 0) 'Single-rung host menu leaves no within-preset downgrade'
        Assert ((@($hostMenuDoc.reselection.declared_fallback | ForEach-Object { "$($_.model)/$($_.effort)" }) -join ',') -ceq 'gemini-3.8-flash-high/high') 'Failure reselection menus follow the codex host menu'
        Assert ($global:HostMenuFailureCalls.Count -eq 1) 'Host-menu failure still makes exactly one launch call'
    }
    finally {
        Remove-Item Function:/global:codex -ErrorAction SilentlyContinue
        Remove-Variable HostMenuFailureCalls -Scope Global -ErrorAction SilentlyContinue
        if ($null -eq $previousHostMenuCodexHome) { Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue } else { $env:CODEX_HOME = $previousHostMenuCodexHome }
    }
    # Declared alternates fail closed at load; each case starts from the shipped policy.
    $fallbackCases = @(
        @{ name = 'missing slot declaration'; mutate = { param($p) $p.fallbacks.Remove('documentation_review') } },
        @{ name = 'alternate repeats the own route'; mutate = { param($p) $p.fallbacks.architecture_review = @(@{ preset = 'gpt6_luna_only'; model = 'gpt-6-luna'; effort = 'max' }) } },
        @{ name = 'tuple absent from its preset'; mutate = { param($p) $p.fallbacks.quick_triage = @(@{ preset = 'glm53_flash_only'; model = 'glm-5.3-flash'; effort = 'high' }) } },
        @{ name = 'duplicate alternate'; mutate = { param($p) $p.fallbacks.standard_review = @(@{ preset = 'gemini38_flash_only'; model = 'gemini-3.8-flash-high'; effort = 'high' }, @{ preset = 'gemini38_flash_only'; model = 'gemini-3.8-flash-high'; effort = 'high' }) } },
        @{ name = 'unknown preset'; mutate = { param($p) $p.fallbacks.quick_triage = @(@{ preset = 'gpt61_sol_only'; model = 'gpt-6.1-sol'; effort = 'max' }) } },
        @{ name = 'more than three alternates'; mutate = { param($p) $p.fallbacks.test_execution = @(1..4 | ForEach-Object { @{ preset = 'gemini38_flash_only'; model = 'gemini-3.8-flash-high'; effort = 'high' } }) } },
        @{ name = 'menu tuple outside the strict subagent allowlist'; mutate = { param($p) $p.presets.gpt6_luna_only.menu = @(@{ model = 'gpt-6-luna'; effort = 'xhigh' }) } },
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
    $allowlistCases = @(
        @{ name = 'unlisted model'; mutate = { param($p) $p.presets.gpt6_luna_only.menu[0].model = 'gpt-5.6-terra' } },
        @{ name = 'wrong Luna effort'; mutate = { param($p) $p.presets.gpt6_luna_only.menu[0].effort = 'high' } },
        @{ name = 'Codex GLM max'; mutate = { param($p) $p.presets.glm53_flash_only.menu[0].effort = 'max' } },
        @{ name = 'ZCode GLM xhigh'; mutate = { param($p) $p.presets.glm53_flash_only.host_menus.zcode[0].effort = 'xhigh' } },
        @{ name = 'retired Haiku model'; mutate = { param($p) $p.presets.gpt6_luna_only.menu[0].model = 'claude-haiku-5-5' } },
        @{ name = 'bare Gemini family name'; mutate = { param($p) $p.presets.gemini38_flash_only.menu[0].model = 'gemini-3.8-flash' } }
    )
    foreach ($allowlistCase in $allowlistCases) {
        $casePolicy = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'presets.json') -Raw | ConvertFrom-Json -AsHashtable
        & $allowlistCase.mutate $casePolicy
        [IO.File]::WriteAllText($fixturePolicyPath, ($casePolicy | ConvertTo-Json -Depth 12))
        $caseRejected = $false
        try { & (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Resolve | Out-Null } catch { $caseRejected = $true }
        Assert $caseRejected "Out-of-allowlist model/effort fails closed: $($allowlistCase.name)"
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'presets.json') -Destination $fixturePolicyPath -Force
    Assert ((& (Join-Path $fixture 'Set-ModelPreset.ps1') -Action Resolve | ConvertFrom-Json).routes.architecture_review.declared_fallback.Count -eq 2) 'Restored shipped fallbacks resolve again'
}
finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    if (-not $resolvedFixture.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolvedFixture -Recurse
    foreach ($evidencePath in @($providerEvidencePath,$providerMismatchPath,$profileProviderEvidencePath)) {
        if (Test-Path -LiteralPath $evidencePath) { Remove-Item -LiteralPath $evidencePath -Force }
    }
}
"PASS: $count assertions (joint model pool, direct/native routing boundaries, provider controls, read-only slots, projection lifecycle, and exact rollback)."
