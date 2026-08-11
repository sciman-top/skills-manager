function Parse-SkillEvolutionOptions([object[]]$Tokens) {
    if (@($Tokens).Count -lt 1) { throw 'skill-evolution requires prepare, evaluate, plan, apply, or rollback.' }
    $result = [ordered]@{ command = ([string]$Tokens[0]).ToLowerInvariant(); flags = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase); values = @{} }
    for ($index = 1; $index -lt @($Tokens).Count; $index++) {
        $token = [string]$Tokens[$index]
        if (-not $token.StartsWith('--')) { throw ('Unexpected skill-evolution argument: {0}' -f $token) }
        $name = $token.ToLowerInvariant()
        if ($name -in @('--json', '--execute')) { $result.flags.Add($name) | Out-Null; continue }
        if ($index + 1 -ge @($Tokens).Count) { throw ('{0} requires a value.' -f $token) }
        $index++
        if (-not $result.values.ContainsKey($name)) { $result.values[$name] = [System.Collections.Generic.List[string]]::new() }
        $result.values[$name].Add([string]$Tokens[$index]) | Out-Null
    }
    return [pscustomobject]$result
}

function Get-SkillEvolutionOption($Options, [string]$Name, [switch]$Required, [switch]$Multiple) {
    $key = $Name.ToLowerInvariant()
    $values = if ($Options.values.ContainsKey($key)) { @($Options.values[$key].ToArray()) } else { @() }
    if ($Required -and $values.Count -eq 0) { throw ('Missing required option: {0}' -f $Name) }
    if (-not $Multiple -and $values.Count -gt 1) { throw ('Option may be specified only once: {0}' -f $Name) }
    if ($Multiple) { return $values }
    return $(if ($values.Count -gt 0) { $values[0] } else { $null })
}

function Read-SkillEvolutionJson([string]$Path, [string]$Label) {
    $full = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw ('{0} not found: {1}' -f $Label, $full) }
    try { return [System.IO.File]::ReadAllText($full) | ConvertFrom-Json }
    catch { throw ('{0} is not valid JSON: {1}' -f $Label, $_.Exception.Message) }
}

function Get-SkillEvolutionCandidateContext([string]$CandidateDirectory) {
    $state = Get-SkillEvolutionPackageState $CandidateDirectory
    if (-not $state.pass) { throw ('Candidate package failed static validation: {0}' -f (@($state.findings.code) -join ',')) }
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($file in @($state.files)) {
        $content = [System.IO.File]::ReadAllText((Join-Path $state.root ([string]$file.path)))
        $parts.Add(("## {0}`n{1}" -f $file.path, $content)) | Out-Null
    }
    return [pscustomobject]@{ state = $state; text = ($parts.ToArray() -join "`n`n") }
}

function ConvertFrom-SkillEvolutionAgentJson([string]$Text) {
    $value = $Text.Trim()
    if ($value -match '(?s)^```(?:json)?\s*(.*?)\s*```$') { $value = $matches[1] }
    try { return $value | ConvertFrom-Json }
    catch { return $null }
}

function Invoke-SkillEvolutionForwardTests {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CandidateDirectory,
        [Parameter(Mandatory = $true)]$Corpus,
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][string]$ReasoningEffort
    )
    if (-not (Get-Command codex -ErrorAction SilentlyContinue)) { throw 'codex CLI is unavailable; execute evaluation is platform_na.' }
    $context = Get-SkillEvolutionCandidateContext $CandidateDirectory
    $manifest = Read-SkillEvolutionJson (Join-Path $context.state.root 'candidate.json') 'candidate manifest'
    $runRoot = Join-Path $context.state.root ('forward-test-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    $workspace = Join-Path $runRoot 'isolated-workspace'
    [System.IO.Directory]::CreateDirectory($workspace) | Out-Null
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($case in @($Corpus.cases)) {
        $caseId = [string]$case.id
        if ($caseId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw ('Unsafe forward-test case ID: {0}' -f $caseId) }
        $prompt = @"
This is an isolated read-only candidate-skill replay. Do not modify files, use network access, delegate, or mutate host configuration. The candidate below is not installed or projected. Decide whether its documented trigger applies to the request; if it applies, follow the candidate instructions far enough to judge whether the task can be satisfied without external writes. This is evaluation evidence, not host invocation evidence.

Return only JSON with these fields:
{"applicable":true|false,"task_satisfied":true|false,"selected_skill":"$($manifest.skill_name)"|null,"reason":"short redacted reason"}

Candidate package:
$($context.text)

Case kind: $([string]$case.kind)
User request:
$([string]$case.request)
"@
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $raw = @(& codex exec --ephemeral --json --sandbox read-only --model $Model -C $workspace --skip-git-repo-check -c ('model_reasoning_effort="{0}"' -f $ReasoningEffort) $prompt 2>&1)
        $exitCode = $LASTEXITCODE
        $timer.Stop()
        $events = @($raw | ForEach-Object { try { $_ | ConvertFrom-Json } catch { $null } } | Where-Object { $null -ne $_ })
        $message = $events | Where-Object { $_.type -eq 'item.completed' -and $_.item.type -eq 'agent_message' } | Select-Object -Last 1
        $parsed = ConvertFrom-SkillEvolutionAgentJson ([string]$message.item.text)
        $commands = @($events | Where-Object { $_.type -eq 'item.completed' -and $_.item.type -eq 'command_execution' } | ForEach-Object { [string]$_.item.command })
        $sideEffects = @($commands | Where-Object { $_ -match '(?i)(Set-Content|Out-File|Remove-Item|Move-Item|Copy-Item|New-Item|git\s+(?:add|commit|push)|Invoke-WebRequest|Invoke-RestMethod|curl|wget|Start-Process)' }).Count
        $usage = $events | Where-Object type -eq 'turn.completed' | Select-Object -Last 1
        $rawPath = Join-Path $runRoot ('{0}.jsonl' -f $caseId)
        [System.IO.File]::WriteAllLines($rawPath, @($raw | ForEach-Object { [string]$_ }), [System.Text.UTF8Encoding]::new($false))
        $results.Add([pscustomobject][ordered]@{
            case_id = $caseId
            exit_code = $exitCode
            parse_ok = ($null -ne $parsed)
            applicable = if ($parsed) { [bool]$parsed.applicable } else { $false }
            task_satisfied = if ($parsed) { [bool]$parsed.task_satisfied } else { $false }
            selected_skill = if ($parsed) { [string]$parsed.selected_skill } else { $null }
            reason = if ($parsed) { Protect-OperationSensitiveString ([string]$parsed.reason) } else { 'unparseable host result' }
            tool_rounds = $commands.Count
            side_effects = $sideEffects
            duration_ms = $timer.ElapsedMilliseconds
            input_tokens = [int]$usage.usage.input_tokens
            output_tokens = [int]$usage.usage.output_tokens
            model = $Model
            reasoning_effort = $ReasoningEffort
            raw_receipt = $rawPath
        }) | Out-Null
    }
    return [pscustomobject]@{ run_root = $runRoot; results = $results.ToArray(); provider_calls = @($Corpus.cases).Count; host_writes = 0; active_writes = 0; report_writes = @($Corpus.cases).Count }
}

function Invoke-SkillEvolutionCommand([object[]]$Tokens = @()) {
    $options = Parse-SkillEvolutionOptions $Tokens
    $json = $options.flags.Contains('--json')
    $command = [string]$options.command
    $data = $null
    switch ($command) {
        'prepare' {
            $signals = @(Get-SkillEvolutionOption $options '--signal' -Required -Multiple)
            $skill = Get-SkillEvolutionOption $options '--skill'
            $newSkill = Get-SkillEvolutionOption $options '--new-skill'
            if (([string]::IsNullOrWhiteSpace($skill) -and [string]::IsNullOrWhiteSpace($newSkill)) -or (-not [string]::IsNullOrWhiteSpace($skill) -and -not [string]::IsNullOrWhiteSpace($newSkill))) { throw 'prepare requires exactly one of --skill or --new-skill.' }
            $out = Resolve-SkillEvolutionPath (Get-SkillEvolutionOption $options '--out' -Required) $Root
            $pilotPath = Get-SkillEvolutionOption $options '--pilot'
            if ([string]::IsNullOrWhiteSpace($pilotPath)) { $pilotPath = Join-Path $Root 'tasks\skills-manager-vnext-lean-delivery-pilot.json' }
            $pilot = Read-SkillEvolutionJson $pilotPath 'lean delivery pilot'
            $data = Invoke-SkillEvolutionPrepare -Pilot $pilot -SignalIds $signals -SkillName $(if ($skill) { $skill } else { $newSkill }) -CandidateMode $(if ($skill) { 'existing' } else { 'new' }) -OutRoot $out -RepoRoot $Root
        }
        'evaluate' {
            $candidate = Resolve-SkillEvolutionPath (Get-SkillEvolutionOption $options '--candidate' -Required) $Root
            if (-not (Test-SkillEvolutionPathWithin $candidate (Join-Path ([IO.Path]::GetFullPath($Root)) 'reports\skill-evolution'))) { throw 'Candidate must remain under reports/skill-evolution.' }
            $corpusPath = Resolve-SkillEvolutionPath (Get-SkillEvolutionOption $options '--corpus' -Required) $Root
            $corpus = Read-SkillEvolutionJson $corpusPath 'skill evolution corpus'
            $model = Get-SkillEvolutionOption $options '--model'
            if ([string]::IsNullOrWhiteSpace($model)) { $model = 'gpt-5.6-sol' }
            $effort = Get-SkillEvolutionOption $options '--reasoning-effort'
            if ([string]::IsNullOrWhiteSpace($effort)) { $effort = 'medium' }
            if ($effort -notin $script:SkillEvolutionAllowedReasoningEfforts) { throw ('Unsupported reasoning effort: {0}' -f $effort) }
            $execute = $options.flags.Contains('--execute')
            $forward = if ($execute) { Invoke-SkillEvolutionForwardTests -CandidateDirectory $candidate -Corpus $corpus -Model $model -ReasoningEffort $effort } else { [pscustomobject]@{ results = @(); provider_calls = 0; report_writes = 0 } }
            $data = Invoke-SkillEvolutionEvaluate -CandidateDirectory $candidate -Corpus $corpus -CaseResults @($forward.results) -Execute:$execute -Model $model -ReasoningEffort $effort -RepoRoot $Root
            $out = Get-SkillEvolutionOption $options '--out'
            if ([string]::IsNullOrWhiteSpace($out)) { $out = Join-Path $candidate 'evaluation.json' }
            $outFull = Assert-SkillEvolutionReportPath (Resolve-SkillEvolutionPath $out $Root) $Root
            $data.report_writes = [int]$forward.report_writes + 1
            Write-SkillEvolutionJsonAtomic $outFull $data
            $data | Add-Member -NotePropertyName receipt_path -NotePropertyValue $outFull
        }
        'plan' {
            $candidate = Resolve-SkillEvolutionPath (Get-SkillEvolutionOption $options '--candidate' -Required) $Root
            $evaluationPath = Resolve-SkillEvolutionPath (Get-SkillEvolutionOption $options '--evaluation' -Required) $Root
            $reviewPath = Resolve-SkillEvolutionPath (Get-SkillEvolutionOption $options '--review' -Required) $Root
            $out = Resolve-SkillEvolutionPath (Get-SkillEvolutionOption $options '--out' -Required) $Root
            $evaluation = Read-SkillEvolutionJson $evaluationPath 'evaluation receipt'
            $review = Read-SkillEvolutionJson $reviewPath 'reviewed change-set'
            $data = New-SkillEvolutionPlan -CandidateDirectory $candidate -Evaluation $evaluation -EvaluationPath $evaluationPath -Review $review -ReviewPath $reviewPath -RepoRoot $Root
            $outFull = Assert-SkillEvolutionReportPath $out $Root
            Write-SkillEvolutionJsonAtomic $outFull $data
            $data | Add-Member -NotePropertyName plan_path -NotePropertyValue $outFull
        }
        'apply' {
            $planPath = Resolve-SkillEvolutionPath (Get-SkillEvolutionOption $options '--plan' -Required) $Root
            $token = Get-SkillEvolutionOption $options '--token' -Required
            $out = Resolve-SkillEvolutionPath (Get-SkillEvolutionOption $options '--out' -Required) $Root
            $plan = Read-SkillEvolutionJson $planPath 'skill evolution plan'
            $data = Invoke-SkillEvolutionApply -Plan $plan -Token $token -ReceiptPath $out -RepoRoot $Root
        }
        'rollback' {
            $receiptPath = Resolve-SkillEvolutionPath (Get-SkillEvolutionOption $options '--receipt' -Required) $Root
            $token = Get-SkillEvolutionOption $options '--token' -Required
            $out = Get-SkillEvolutionOption $options '--out'
            if (-not [string]::IsNullOrWhiteSpace($out)) { $out = Resolve-SkillEvolutionPath $out $Root }
            $receipt = Read-SkillEvolutionJson $receiptPath 'promotion receipt'
            $data = Invoke-SkillEvolutionRollback -Receipt $receipt -Token $token -OutPath $out -RepoRoot $Root
        }
        default { throw ('Unknown skill-evolution command: {0}' -f $command) }
    }
    $pass = if ($null -ne (Get-SkillEvolutionProperty $data 'pass')) { [bool]$data.pass } elseif ([string]$data.status -in @('failed', 'partial')) { $false } else { $true }
    $envelope = [pscustomobject][ordered]@{ schema_version = 1; command = ('skill-evolution-{0}' -f $command); pass = $pass; truth_boundary = if ($command -eq 'evaluate' -and $options.flags.Contains('--execute')) { 'isolated_forward_test_not_host_invocation' } else { 'repo_controlled_skill_lifecycle' }; data = $data }
    $output = if ($json) { $envelope | ConvertTo-Json -Depth 80 -Compress } else { 'skill-evolution {0}: pass={1}' -f $command, $pass }
    return [pscustomobject]@{ exit_code = $(if ($pass) { 0 } else { 2 }); output = $output; json = $json; envelope = $envelope }
}
