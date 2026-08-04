[CmdletBinding()]
param(
    [string]$CorpusPath,
    [string]$OutputRoot,
    [string[]]$CaseId,
    [ValidateSet('selection', 'cold_load', 'all')][string]$Mode = 'all',
    [string]$Model = 'gpt-5.6-sol',
    [switch]$AllowRealProfileMutation,
    [switch]$Execute,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($CorpusPath)) { $CorpusPath = Join-Path $repoRoot 'config\host-skill-selection-evaluation.json' }
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $repoRoot 'reports\host-skill-selection-acceptance' }
$schemaPath = Join-Path $repoRoot 'config\codex-skill-profile-benchmark-output.schema.json'
$skillsScript = Join-Path $repoRoot 'skills.ps1'
$configPath = Join-Path $repoRoot 'skills.json'
$projectionPath = Join-Path $repoRoot 'reports\skill-projection\current.json'

function Get-NormalizedStringArray($Value) {
    return @($Value | ForEach-Object { @(([string]$_) -split ',') } | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Set-EvaluationProfile([string]$Name) {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $skillsScript '技能配置' '使用' $Name | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "profile switch failed: $Name" }
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

function Invoke-HostCase($Case, [string]$RunMode, [string]$RunRoot, [string]$CaseCwd, $CanonicalByName) {
    $prompt = if ($RunMode -eq 'selection') {
@"
This is a read-only host-native skill-selection evaluation. Do not call tools, modify files, switch profiles, create a plan, delegate, or use a worktree. Do not solve the user request.
Using only the skill name/description catalog visible at this fresh task boundary and the ordinary trigger rules, return the exact skill names you would invoke before doing the work. Do not invent a cold skill that is not visible. If no direct visible skill matches, select capability-router only when its cross-profile cold-discovery trigger applies. If no skill is needed, return an empty array.

User request:
$($Case.request)
"@
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

$corpus = Get-Content -LiteralPath $CorpusPath -Raw | ConvertFrom-Json
if ([int]$corpus.schema_version -ne 1) { throw 'unsupported evaluation corpus schema_version' }
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$originalProfile = [string]$config.skill_projection.active_profile
$configuredProfiles = @($config.skill_projection.profiles.PSObject.Properties.Name)
$defaultNames = @($config.skill_projection.profiles.default.enabled_names | ForEach-Object { [string]$_ })
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
    real_profile_mutation_required = ($selectionCases.Count -gt 0)
    real_profile_mutation_authorized = [bool]$AllowRealProfileMutation
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
if ($selectionCases.Count -gt 0 -and -not $AllowRealProfileMutation) {
    throw 'selection execution changes the real active profile; rerun with -AllowRealProfileMutation or use -Mode cold_load'
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
try {
    foreach ($group in @($selectionCases | Group-Object profile)) {
        Set-EvaluationProfile ([string]$group.Name)
        foreach ($case in @($group.Group)) { $results.Add((Invoke-HostCase $case 'selection' $runRoot $evaluationCwd $canonicalByName)) | Out-Null }
    }
    if ($coldCases.Count -gt 0) {
        foreach ($case in $coldCases) { $results.Add((Invoke-HostCase $case 'cold_load' $runRoot $evaluationCwd $canonicalByName)) | Out-Null }
    }
}
finally {
    if ($selectionCases.Count -gt 0) { Set-EvaluationProfile $originalProfile }
}

$restored = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$restoredProfile = [string]$restored.skill_projection.active_profile
if (-not [string]::Equals($restoredProfile, $originalProfile, [StringComparison]::OrdinalIgnoreCase)) { throw "evaluation did not restore active profile: expected=$originalProfile actual=$restoredProfile" }
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
    real_profile_mutation = ($selectionCases.Count -gt 0)
    truth_level = 'host_evaluation_partial'
    original_profile = $originalProfile
    restored_profile = $restoredProfile
    pass = (@($items | Where-Object { -not $_.pass }).Count -eq 0)
    summary = $summary
    results = $items
}
$reportPath = Join-Path $runRoot 'report.json'
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding utf8
if ($Json) { $report | ConvertTo-Json -Depth 12 } else { Write-Host "host skill selection evaluation: $reportPath"; $summary | Format-Table }
if (-not $report.pass) { exit 1 }
