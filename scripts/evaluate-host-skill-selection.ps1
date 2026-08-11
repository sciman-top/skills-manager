[CmdletBinding()]
param(
    [string]$CorpusPath,
    [string]$OutputRoot,
    [string[]]$CaseId,
    [ValidateSet('selection', 'cold_load', 'invocation', 'all')][string]$Mode = 'all',
    [string]$Model = 'gpt-5.6-sol',
    [ValidateSet('native_events', 'self_report', 'read_heuristic')][string]$InvocationMode = 'native_events',
    [string]$EventsPath,
    [string]$ProjectionPath,
    [ValidateSet('low', 'medium', 'high', 'xhigh')][string]$ReasoningEffort = 'medium',
    [switch]$Execute,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($CorpusPath)) { $CorpusPath = Join-Path $repoRoot 'config\host-skill-selection-evaluation.json' }
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $repoRoot 'reports\host-skill-selection-acceptance' }
$schemaPath = Join-Path $repoRoot 'config\codex-skill-profile-benchmark-output.schema.json'
$configPath = Join-Path $repoRoot 'skills.json'
if ([string]::IsNullOrWhiteSpace($ProjectionPath)) { $ProjectionPath = Join-Path $repoRoot 'reports\skill-projection\current.json' }
$operationPath = Join-Path $repoRoot 'src\Domain\OperationPlan.ps1'
$tracePath = Join-Path $repoRoot 'src\Domain\NativeInvocationTrace.ps1'
$traceAdapterPath = Join-Path $repoRoot 'src\Infrastructure\NativeInvocationTraceAdapters.ps1'
if (Test-Path -LiteralPath $operationPath) { . $operationPath }
if (Test-Path -LiteralPath $tracePath) { . $tracePath }
if (Test-Path -LiteralPath $traceAdapterPath) { . $traceAdapterPath }

function Get-NormalizedStringArray($Value) {
    return @($Value | ForEach-Object { @(([string]$_) -split ',') } | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Get-ExpectationResult($Expected, [string[]]$Selected) {
    $required = @($Expected.required | ForEach-Object { [string]$_ })
    $forbidden = @($Expected.forbidden | ForEach-Object { [string]$_ })
    $missing = @($required | Where-Object { $Selected -notcontains $_ })
    $missingAny = [Collections.Generic.List[string]]::new()
    foreach ($group in @($Expected.required_any)) {
        $alternatives = @($group | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($alternatives.Count -gt 0 -and @($alternatives | Where-Object { $Selected -contains $_ }).Count -eq 0) {
            $missingAny.Add(($alternatives -join '|')) | Out-Null
        }
    }
    $missing = @($missing + $missingAny.ToArray())
    $unexpected = @($forbidden | Where-Object { $Selected -contains $_ })
    return [pscustomobject]@{ missing = $missing; unexpected = $unexpected; pass = ($missing.Count -eq 0 -and $unexpected.Count -eq 0) }
}

function Get-CommandTexts($Events) {
    return @($Events | Where-Object { $_.PSObject.Properties.Match('item').Count -gt 0 -and $_.item.type -eq 'command_execution' } | ForEach-Object { [string]$_.item.command } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Get-HostUsageMetrics($Events) {
    $usageEvent = $Events | Where-Object type -eq 'turn.completed' | Select-Object -Last 1
    $inputTokens = [int]$usageEvent.usage.input_tokens
    $cachedInputTokens = [int]$usageEvent.usage.cached_input_tokens
    return [pscustomobject][ordered]@{
        input_tokens = $inputTokens
        cached_input_tokens = $cachedInputTokens
        uncached_input_tokens = [Math]::Max(0, ($inputTokens - $cachedInputTokens))
        cached_input_ratio = if ($inputTokens -gt 0) { [Math]::Round(($cachedInputTokens / $inputTokens), 4) } else { 0.0 }
        output_tokens = [int]$usageEvent.usage.output_tokens
    }
}

function Get-HostCommandMetrics($Events) {
    $completed = @($Events | Where-Object { $_.type -eq 'item.completed' -and $_.item.type -eq 'command_execution' })
    $commands = @($completed | ForEach-Object { [string]$_.item.command })
    return [pscustomobject][ordered]@{
        command_count = $commands.Count
        router_call_count = @($commands | Where-Object { $_ -match 'route-capability\.ps1' }).Count
        command_item_count = @($completed | ForEach-Object { [string]$_.item.id } | Sort-Object -Unique).Count
        tool_round_count = $null
        tool_round_source = 'unavailable_from_exec_jsonl'
    }
}

function Test-RawSkillRead([string[]]$Commands, [string]$SkillPath) {
    if ([string]::IsNullOrWhiteSpace($SkillPath)) { return $false }
    $normalizedPath = [IO.Path]::GetFullPath($SkillPath).ToLowerInvariant()
    foreach ($command in $Commands) {
        $normalizedCommand = $command.Replace('\\', '\').ToLowerInvariant()
        if ($normalizedCommand.Contains('get-content') -and $normalizedCommand.Contains('-raw') -and $normalizedCommand.Contains($normalizedPath)) { return $true }
    }
    return $false
}

function Get-HostSelectionPrompt($Case) {
    if ([bool]$Case.explicit_fallback) {
        $selectionContract = 'The user explicitly invoked `$capability-router`. Treat that named invocation as authoritative and include capability-router in selected_skills.'
    }
    else {
        $selectionContract = 'Using only the skill name/description catalog visible at this fresh task boundary and the ordinary trigger rules, return the exact skill names you would invoke before doing the work. Do not invent a cold skill that is not visible. If no direct visible skill matches, select capability-router only when explicit fallback discovery is actually needed. If no skill is needed, return an empty array.'
    }
    return @"
This is a read-only host-native skill-selection evaluation. Do not call tools, modify files, switch profiles, create a plan, delegate, or use a worktree. Do not solve the user request.
$selectionContract

User request:
$($Case.request)
"@
}

function Invoke-HostCase($Case, [string]$RunMode, [string]$RunRoot, [string]$CaseCwd, $CanonicalByName) {
    $prompt = if ($RunMode -eq 'selection') {
        Get-HostSelectionPrompt $Case
    }
    else {
@"
This is a read-only cold skill-loading acceptance probe. Do not solve the user request, modify files, switch profiles, create a plan, delegate, or use a worktree.
Act as the host AI and execute the installed capability-router fallback contract for the complete request below. Read capability-router/SKILL.md completely with Get-Content -Raw. Do not search repository source, configuration, or generated files. Call route-capability.ps1 once without a hint and project only discovery_domains.name,purpose. Choose at most two domains from their purposes and the complete request, run discovery with DomainHint, and project only candidate kind/name/description/path/domains/active/availability/side_effect fields to keep output small. Choose the smallest sufficient capability, rerun deterministic policy with that Candidate, and project only selected/activation_plan/excluded. If policy permits load_skill, read the selected cold SKILL.md completely with Get-Content -Raw. Do not use lexical scores and do not reveal or guess benchmark expectations.
Return selected_skills containing the workflow skills actually selected, including capability-router and the final cold skill when loaded.

User request:
$($Case.request)
"@
    }

    $timer = [Diagnostics.Stopwatch]::StartNew()
    $raw = @(& codex exec --ephemeral --json --sandbox read-only --model $Model -C $CaseCwd --skip-git-repo-check -c 'model_provider="openai"' --output-schema $schemaPath $prompt 2>&1)
    $exitCode = $LASTEXITCODE
    $timer.Stop()
    $events = @($raw | ForEach-Object { try { $_ | ConvertFrom-Json } catch { $null } } | Where-Object { $null -ne $_ })
    $usage = Get-HostUsageMetrics $events
    $commandMetrics = Get-HostCommandMetrics $events
    $messageEvent = $events | Where-Object { $_.type -eq 'item.completed' -and $_.item.type -eq 'agent_message' } | Select-Object -Last 1
    $parsed = $null
    try { $parsed = ([string]$messageEvent.item.text) | ConvertFrom-Json } catch { }
    $selected = if ($null -ne $parsed) { @($parsed.selected_skills | ForEach-Object { [string]$_ }) } else { @() }
    $expected = if ($RunMode -eq 'selection') { $Case.expected } else { [pscustomobject]@{ required = @([string]$Case.cold_probe.target_skill); forbidden = @($Case.cold_probe.forbidden) } }
    $expectation = Get-ExpectationResult $expected $selected
    $commands = Get-CommandTexts $events
    $routerScriptInvoked = @($commands | Where-Object { $_ -match 'route-capability\.ps1' }).Count -gt 0
    $routerSkillPath = if ($CanonicalByName.ContainsKey('capability-router')) { [string]$CanonicalByName['capability-router'] } else { '' }
    $targetName = if ($RunMode -eq 'cold_load') { [string]$Case.cold_probe.target_skill } else { '' }
    $targetPath = if ($targetName -and $CanonicalByName.ContainsKey($targetName)) { [string]$CanonicalByName[$targetName] } else { '' }
    $routerRead = if ($RunMode -eq 'cold_load') { Test-RawSkillRead $commands $routerSkillPath } else { $false }
    $targetRead = if ($RunMode -eq 'cold_load') { Test-RawSkillRead $commands $targetPath } else { $false }
    $chainPass = if ($RunMode -eq 'cold_load') { $routerScriptInvoked } else { $true }

    $safeId = [string]$Case.id
    $raw | Set-Content -LiteralPath (Join-Path $RunRoot ("{0}-{1}.jsonl" -f $RunMode, $safeId)) -Encoding utf8
    return [pscustomobject][ordered]@{
        mode = $RunMode
        case_id = $safeId
        category = [string]$Case.category
        language = [string]$Case.language
        profile = if ($RunMode -eq 'selection') { [string]$Case.profile } else { 'default' }
        target_skill = $targetName
        exit_code = $exitCode
        parse_ok = ($null -ne $parsed)
        duration_ms = $timer.ElapsedMilliseconds
        input_tokens = [int]$usage.input_tokens
        cached_input_tokens = [int]$usage.cached_input_tokens
        uncached_input_tokens = [int]$usage.uncached_input_tokens
        cached_input_ratio = [double]$usage.cached_input_ratio
        output_tokens = [int]$usage.output_tokens
        command_count = [int]$commandMetrics.command_count
        router_call_count = [int]$commandMetrics.router_call_count
        command_item_count = [int]$commandMetrics.command_item_count
        tool_round_count = $null
        tool_round_source = [string]$commandMetrics.tool_round_source
        selected_skills = @($selected)
        missing_required = @($expectation.missing)
        selected_forbidden = @($expectation.unexpected)
        router_script_invoked = $routerScriptInvoked
        router_skill_raw_read = $routerRead
        target_skill_raw_read = $targetRead
        raw_read_oracle = 'weak_observation_only'
        expectation_pass = ($exitCode -eq 0 -and $null -ne $parsed -and $expectation.pass)
        chain_pass = $chainPass
        pass = ($exitCode -eq 0 -and $null -ne $parsed -and $expectation.pass -and $chainPass)
        reason = if ($null -ne $parsed) { [string]$parsed.reason } else { '' }
    }
}

function Invoke-FormalInvocationAcceptance($Corpus, [string]$InputEventsPath, [bool]$ExecuteEvents) {
    $formalCases = @($Corpus.invocation_cases)
    if ($formalCases.Count -ne [int]$Corpus.invocation_case_count -or $formalCases.Count -lt 5) { throw 'formal invocation corpus count is invalid' }
    $requiredCategories = @('debug_positive', 'completion_verification_positive', 'powershell_custom_positive', 'no_skill_negative', 'explicit_router_fallback')
    foreach ($category in $requiredCategories) {
        if (@($formalCases | Where-Object category -eq $category).Count -ne 1) { throw ('formal invocation corpus must contain exactly one {0} case' -f $category) }
    }
    $plan = [ordered]@{
        schema_version = 1
        evaluation_id = [string]$Corpus.evaluation_id
        valid = $true
        execute = $ExecuteEvents
        mode = 'invocation'
        invocation_mode = $InvocationMode
        events_path = $InputEventsPath
        model = $Model
        reasoning_effort = $ReasoningEffort
        formal_case_count = $formalCases.Count
        case_ids = @($formalCases.id)
        provider_calls = 0
        host_writes = 0
        truth_level = 'host_evaluation_partial'
    }
    if (-not $ExecuteEvents) { return [pscustomobject]@{ pass = $true; plan_only = $true; output = [pscustomobject]$plan } }
    if ([string]::IsNullOrWhiteSpace($InputEventsPath)) { throw 'Mode invocation with -Execute requires -EventsPath.' }
    $fullEventsPath = [IO.Path]::GetFullPath($InputEventsPath)
    if (-not (Test-Path -LiteralPath $fullEventsPath -PathType Leaf)) { throw ('host events file not found: {0}' -f $fullEventsPath) }
    $receiptSet = Get-Content -LiteralPath $fullEventsPath -Raw | ConvertFrom-Json
    if ([int]$receiptSet.schema_version -ne 1 -or [string]$receiptSet.authority -ne 'native_host_events') { throw 'host events receipt must be schema v1 with authority=native_host_events' }
    $catalogFingerprint = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $findings = [Collections.Generic.List[object]]::new()
    if ([string]$receiptSet.catalog_fingerprint -ne $catalogFingerprint) { $findings.Add([pscustomobject]@{ code = 'catalog_fingerprint_mismatch'; severity = 'error'; message = 'Host events are not bound to the exact-current skills catalog.' }) | Out-Null }
    $projectionFull = [IO.Path]::GetFullPath($ProjectionPath)
    $projection = $null
    if (-not (Test-Path -LiteralPath $projectionFull -PathType Leaf)) {
        $findings.Add([pscustomobject]@{ code = 'projection_snapshot_missing'; severity = 'error'; message = 'Exact-current projection snapshot is required for invocation acceptance.' }) | Out-Null
    }
    else {
        try { $projection = Get-Content -LiteralPath $projectionFull -Raw | ConvertFrom-Json } catch { $findings.Add([pscustomobject]@{ code = 'projection_snapshot_invalid'; severity = 'error'; message = $_.Exception.Message }) | Out-Null }
    }
    $projectionFingerprint = if ($null -ne $projection) { [string]$projection.projection_fingerprint } else { '' }
    $projectionCaptured = [datetimeoffset]::MinValue
    $projectionFresh = $null -ne $projection -and $projectionFingerprint -match '^[a-f0-9]{64}$' -and @($projection.canonical).Count -gt 0 -and [datetimeoffset]::TryParse([string]$projection.generated_at, [ref]$projectionCaptured) -and ([datetimeoffset]::UtcNow - $projectionCaptured).TotalHours -ge 0 -and ([datetimeoffset]::UtcNow - $projectionCaptured).TotalHours -le 24
    if (-not $projectionFresh) { $findings.Add([pscustomobject]@{ code = 'projection_snapshot_not_fresh_complete'; severity = 'error'; message = 'Projection snapshot must be fresh, complete, and fingerprinted.' }) | Out-Null }
    if ([string]$receiptSet.projection_fingerprint -ne $projectionFingerprint) { $findings.Add([pscustomobject]@{ code = 'projection_fingerprint_mismatch'; severity = 'error'; message = 'Host events are not bound to the exact-current projection snapshot.' }) | Out-Null }
    if ([string]$receiptSet.model -ne $Model -or [string]$receiptSet.reasoning_effort -ne $ReasoningEffort) { $findings.Add([pscustomobject]@{ code = 'model_effort_mismatch'; severity = 'error'; message = 'Host events do not match the requested model and reasoning effort.' }) | Out-Null }
    $results = [Collections.Generic.List[object]]::new()
    foreach ($case in $formalCases) {
        $caseReceipts = @($receiptSet.cases | Where-Object { [string]$_.case_id -eq [string]$case.id })
        if ($caseReceipts.Count -ne 1) { $findings.Add([pscustomobject]@{ code = 'case_receipt_missing'; severity = 'error'; message = ('Missing unique receipt for {0}.' -f $case.id) }) | Out-Null; continue }
        $receipt = $caseReceipts[0]
        $captured = [datetimeoffset]::MinValue
        $fresh = [datetimeoffset]::TryParse([string]$receipt.captured_at, [ref]$captured) -and ([datetimeoffset]::UtcNow - $captured).TotalHours -ge 0 -and ([datetimeoffset]::UtcNow - $captured).TotalHours -le 24
        if ([string]$receipt.catalog_fingerprint -ne [string]$receiptSet.catalog_fingerprint -or [string]$receipt.projection_fingerprint -ne [string]$receiptSet.projection_fingerprint) { $findings.Add([pscustomobject]@{ code = 'case_fingerprint_mismatch'; severity = 'error'; message = ('Case {0} is not bound to the receipt-set fingerprints.' -f $case.id) }) | Out-Null }
        foreach ($metric in @('duration_ms', 'input_tokens', 'output_tokens', 'writes', 'side_effects')) {
            if ($null -eq $receipt.PSObject.Properties[$metric] -or [int64]$receipt.$metric -lt 0) { $findings.Add([pscustomobject]@{ code = 'case_metric_missing'; severity = 'error'; message = ('Case {0} lacks valid {1}.' -f $case.id, $metric) }) | Out-Null }
        }
        if ([int]$receipt.writes -ne 0 -or [int]$receipt.side_effects -ne 0) { $findings.Add([pscustomobject]@{ code = 'read_only_boundary_violated'; severity = 'error'; message = ('Case {0} performed writes or side effects.' -f $case.id) }) | Out-Null }
        if ([string]$receipt.model -ne $Model -or [string]$receipt.reasoning_effort -ne $ReasoningEffort) { $findings.Add([pscustomobject]@{ code = 'case_model_effort_mismatch'; severity = 'error'; message = ('Case {0} has a different model or effort.' -f $case.id) }) | Out-Null }
        $trace = New-NativeInvocationTraceFromHostEvents -Events @($receipt.events) -TraceId ('formal-{0}' -f $case.id) -Surface $(if ($receipt.surface) { [string]$receipt.surface } else { 'codex_task' }) -Source $(if ($receipt.source) { [string]$receipt.source } else { 'native_host' }) -Freshness $(if ($fresh) { 'fresh' } else { 'stale' }) -CapturedAt $receipt.captured_at -InvocationMode $InvocationMode -EventsPath $fullEventsPath -ReasoningEffort $ReasoningEffort
        $expectedSkill = [string]$case.expected_skill
        $casePass = if ([string]::IsNullOrWhiteSpace($expectedSkill)) {
            [string]$trace.outcome -eq 'abstained' -and -not [bool]$trace.invocation_observable
        }
        else {
            [string]$trace.truth_level -eq 'host_invocation_observed' -and @($trace.events | Where-Object { $_.kind -eq 'executed' -and $_.skill_name -eq $expectedSkill }).Count -ge 1
        }
        if (-not $casePass) { $findings.Add([pscustomobject]@{ code = 'formal_invocation_case_failed'; severity = 'error'; message = ('Case {0} did not satisfy its authoritative invocation contract.' -f $case.id) }) | Out-Null }
        $results.Add([pscustomobject][ordered]@{ case_id = [string]$case.id; category = [string]$case.category; expected_skill = if ($expectedSkill) { $expectedSkill } else { $null }; pass = $casePass; freshness = if ($fresh) { 'fresh' } else { 'stale' }; model = [string]$receipt.model; reasoning_effort = [string]$receipt.reasoning_effort; duration_ms = [int64]$receipt.duration_ms; input_tokens = [int64]$receipt.input_tokens; output_tokens = [int64]$receipt.output_tokens; writes = [int]$receipt.writes; side_effects = [int]$receipt.side_effects; trace = $trace }) | Out-Null
    }
    $acceptancePass = $InvocationMode -eq 'native_events' -and $results.Count -eq $formalCases.Count -and @($results | Where-Object { -not $_.pass }).Count -eq 0 -and @($findings | Where-Object severity -eq 'error').Count -eq 0
    $runRoot = Join-Path $OutputRoot ('invocation-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
    $report = [pscustomobject][ordered]@{
        schema_version = 1
        evaluation_id = [string]$Corpus.evaluation_id
        mode = 'invocation'
        pass = $acceptancePass
        truth_level = if ($acceptancePass) { 'host_invocation_observed' } else { 'host_evaluation_partial' }
        invocation_mode = $InvocationMode
        authority = [string]$receiptSet.authority
        events_path = $fullEventsPath
        catalog_fingerprint = [string]$receiptSet.catalog_fingerprint
        projection_fingerprint = [string]$receiptSet.projection_fingerprint
        projection_snapshot_path = $projectionFull
        projection_snapshot_fresh = $projectionFresh
        model = $Model
        reasoning_effort = $ReasoningEffort
        provider_calls = 0
        host_writes = 0
        findings = @($findings.ToArray())
        results = @($results.ToArray())
    }
    $reportPath = Join-Path $runRoot 'report.json'
    $report | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $reportPath -Encoding utf8
    $report | Add-Member -NotePropertyName report_path -NotePropertyValue $reportPath
    return [pscustomobject]@{ pass = $acceptancePass; plan_only = $false; output = $report }
}

$corpus = Get-Content -LiteralPath $CorpusPath -Raw | ConvertFrom-Json
if ([int]$corpus.schema_version -ne 1) { throw 'unsupported evaluation corpus schema_version' }
$invocation = if ($Mode -eq 'invocation') { Invoke-FormalInvocationAcceptance $corpus $EventsPath ([bool]$Execute) } else { $null }
if ($null -ne $invocation) {
    if ($Json) { $invocation.output | ConvertTo-Json -Depth 40 } else { $invocation.output | Format-List }
    if (-not $invocation.pass) { exit 1 }
    exit 0
}
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$projectionConfig = $config.skill_projection
$legacyProfilesProperty = $projectionConfig.PSObject.Properties['profiles']
$compatibilityProperty = $projectionConfig.PSObject.Properties['profile_compatibility']
if ($null -ne $legacyProfilesProperty -and $null -ne $legacyProfilesProperty.Value) {
    $profileSource = $projectionConfig
    $profileSourceKind = 'legacy_skill_projection'
}
elseif ($null -ne $compatibilityProperty -and $null -ne $compatibilityProperty.Value) {
    $profileSource = $compatibilityProperty.Value
    $profileSourceKind = 'profile_compatibility'
}
else {
    throw 'skill_projection has neither legacy profiles nor profile_compatibility data'
}
$profilesProperty = $profileSource.PSObject.Properties['profiles']
if ($null -eq $profilesProperty -or $null -eq $profilesProperty.Value) {
    throw ("{0} does not contain profile compatibility data" -f $profileSourceKind)
}
$originalProfile = [string]$profileSource.active_profile
$configuredProfiles = @($profilesProperty.Value.PSObject.Properties.Name)
$defaultProfile = $profilesProperty.Value.PSObject.Properties['default']
if ($null -eq $defaultProfile -or $null -eq $defaultProfile.Value) {
    throw ("{0} does not contain a default profile" -f $profileSourceKind)
}
$defaultNames = @($defaultProfile.Value.enabled_names | ForEach-Object { [string]$_ })
$requestedCaseIds = Get-NormalizedStringArray $CaseId
$cases = @($corpus.cases)
if ($requestedCaseIds.Count -gt 0) { $cases = @($cases | Where-Object { $requestedCaseIds -contains $_.id }) }
if ($cases.Count -eq 0) { throw 'no evaluation cases selected' }

$ids = @($cases | ForEach-Object { [string]$_.id })
if (@($ids | Sort-Object -Unique).Count -ne $ids.Count) { throw 'duplicate evaluation case ids' }
foreach ($case in $cases) {
    if ([string]$case.id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw "unsafe evaluation case id: $($case.id)" }
    if ([string]$case.language -notin @('zh', 'en')) { throw "invalid language for case '$($case.id)'" }
    if ($configuredProfiles -notcontains [string]$case.profile) { throw "unknown profile '$($case.profile)' for case '$($case.id)'" }
    if ($null -eq $case.expected -or $null -eq $case.expected.required -or $null -eq $case.expected.forbidden) { throw "missing selection expectation for case '$($case.id)'" }
    if ($null -ne $case.cold_probe) {
        $hints = @($case.cold_probe.domain_hints | ForEach-Object { [string]$_ })
        $target = [string]$case.cold_probe.target_skill
        if ($hints.Count -lt 1 -or $hints.Count -gt 2) { throw "cold probe '$($case.id)' must have one or two domain hints" }
        if ($hints | Where-Object { $configuredProfiles -notcontains $_ }) { throw "cold probe '$($case.id)' has an unknown domain hint" }
        if ([string]::IsNullOrWhiteSpace($target)) { throw "cold probe '$($case.id)' has no target skill" }
        if ($defaultNames -contains $target) { throw "cold probe '$($case.id)' target is already active in default" }
    }
}
if ($requestedCaseIds.Count -eq 0) {
    if ($cases.Count -ne [int]$corpus.selection_case_count) { throw 'selection_case_count does not match corpus' }
    if (@($cases | Where-Object { $null -ne $_.cold_probe }).Count -ne [int]$corpus.cold_load_case_count) { throw 'cold_load_case_count does not match corpus' }
    if (@($cases.category | Sort-Object -Unique).Count -ne [int]$corpus.category_count) { throw 'category_count does not match corpus' }
}

$selectionCases = if ($Mode -in @('selection', 'all')) { @($cases) } else { @() }
$coldCases = if ($Mode -in @('cold_load', 'all')) { @($cases | Where-Object { $null -ne $_.cold_probe }) } else { @() }
$plannedCalls = $selectionCases.Count + $coldCases.Count
$plan = [ordered]@{
    schema_version = 1
    evaluation_id = [string]$corpus.evaluation_id
    valid = $true
    execute = [bool]$Execute
    mode = $Mode
    execution_boundary = 'fresh_ephemeral_task'
    evaluation_cwd = 'isolated_non_repo_directory'
    real_profile_mutation_required = $false
    selection_execution_mode = 'host_native'
    invocation_mode = $InvocationMode
    events_path = $EventsPath
    reasoning_effort = $ReasoningEffort
    profile_compatibility_mode = 'read_only_metadata'
    semantic_owner = 'host_ai'
    selection_case_count = $selectionCases.Count
    cold_load_case_count = $coldCases.Count
    planned_calls = $plannedCalls
    case_ids = @($cases.id)
}
if (-not $Execute) {
    if ($Json) { $plan | ConvertTo-Json -Depth 5 } else { Write-Host ("evaluation corpus valid: selection={0}, cold_load={1}, planned_calls={2}" -f $selectionCases.Count, $coldCases.Count, $plannedCalls) }
    exit 0
}
$projection = Get-Content -LiteralPath $projectionPath -Raw | ConvertFrom-Json
$canonicalByName = @{}
foreach ($entry in @($projection.canonical)) { $canonicalByName[[string]$entry.name] = [string]$entry.path }
foreach ($case in $coldCases) {
    if (-not $canonicalByName.ContainsKey([string]$case.cold_probe.target_skill)) { throw "cold target not found in projection: $($case.cold_probe.target_skill)" }
}

$runId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$runRoot = Join-Path $OutputRoot $runId
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$evaluationCwd = Join-Path $runRoot 'unrelated-workspace'
New-Item -ItemType Directory -Path $evaluationCwd -Force | Out-Null
$results = [Collections.Generic.List[object]]::new()
foreach ($case in $selectionCases) {
    $results.Add((Invoke-HostCase $case 'selection' $runRoot $evaluationCwd $canonicalByName)) | Out-Null
}
foreach ($case in $coldCases) {
    $results.Add((Invoke-HostCase $case 'cold_load' $runRoot $evaluationCwd $canonicalByName)) | Out-Null
}
$items = @($results.ToArray())
$summary = @($items | Group-Object mode | ForEach-Object {
    $modeItems = @($_.Group)
    [ordered]@{
        mode = $_.Name
        calls = $modeItems.Count
        passed = @($modeItems | Where-Object pass).Count
        expectation_passed = @($modeItems | Where-Object expectation_pass).Count
        chain_passed = @($modeItems | Where-Object chain_pass).Count
        input_tokens = ($modeItems | Measure-Object input_tokens -Sum).Sum
        cached_input_tokens = ($modeItems | Measure-Object cached_input_tokens -Sum).Sum
        uncached_input_tokens = ($modeItems | Measure-Object uncached_input_tokens -Sum).Sum
        cached_input_ratio = if (($modeItems | Measure-Object input_tokens -Sum).Sum -gt 0) { [Math]::Round((($modeItems | Measure-Object cached_input_tokens -Sum).Sum / ($modeItems | Measure-Object input_tokens -Sum).Sum), 4) } else { 0.0 }
        output_tokens = ($modeItems | Measure-Object output_tokens -Sum).Sum
        command_count = ($modeItems | Measure-Object command_count -Sum).Sum
        router_call_count = ($modeItems | Measure-Object router_call_count -Sum).Sum
        command_item_count = ($modeItems | Measure-Object command_item_count -Sum).Sum
        tool_round_count = $null
        tool_round_source = 'unavailable_from_exec_jsonl'
        duration_ms = ($modeItems | Measure-Object duration_ms -Sum).Sum
    }
})
$report = [ordered]@{
    schema_version = 1
    evaluation_id = [string]$corpus.evaluation_id
    run_id = $runId
    model = $Model
    execution_boundary = 'fresh_ephemeral_task'
    evaluation_cwd = $evaluationCwd
    real_profile_mutation = $false
    selection_execution_mode = 'host_native'
    invocation_mode = $InvocationMode
    events_path = $EventsPath
    reasoning_effort = $ReasoningEffort
    profile_compatibility_mode = 'read_only_metadata'
    truth_level = 'host_evaluation_partial'
    original_profile = $originalProfile
    pass = (@($items | Where-Object { -not $_.pass }).Count -eq 0)
    summary = $summary
    results = $items
}
$reportPath = Join-Path $runRoot 'report.json'
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding utf8
if ($Json) { $report | ConvertTo-Json -Depth 12 } else { Write-Host "host skill selection evaluation: $reportPath"; $summary | Format-Table }
if (-not $report.pass) { exit 1 }
