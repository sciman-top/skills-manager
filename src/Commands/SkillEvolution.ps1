function Parse-SkillEvolutionOptions([object[]]$Tokens) {
    if (@($Tokens).Count -lt 1) { throw 'skill-evolution requires prepare, evaluate, request, decide, plan, apply, project, cleanup, or rollback.' }
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

function Add-SkillEvolutionHostAction($Value, $Action) {
    if ($null -eq $Value -or $null -eq $Action) { return $Value }
    $Value | Add-Member -NotePropertyName host_action -NotePropertyValue $Action -Force
    return $Value
}

function Invoke-SkillEvolutionColdBuild([scriptblock]$Rollback, [string]$FailureLabel) {
    try {
        构建生效 -SkipHostProjection
        return [pscustomobject]@{ status = 'passed'; command = '构建生效 -SkipHostProjection'; host_writes = 0; projection_changed = $false }
    }
    catch {
        $buildFailure = $_.Exception.Message
        $rollbackFailure = $null; $restoreBuildFailure = $null
        try { & $Rollback | Out-Null }
        catch { $rollbackFailure = $_.Exception.Message }
        if ([string]::IsNullOrWhiteSpace($rollbackFailure)) {
            try { 构建生效 -SkipHostProjection }
            catch { $restoreBuildFailure = $_.Exception.Message }
        }
        throw ('{0}; build={1}; rollback={2}; restore_build={3}' -f $FailureLabel, $buildFailure, $(if ($rollbackFailure) { $rollbackFailure } else { 'passed' }), $(if ($restoreBuildFailure) { $restoreBuildFailure } else { 'passed' }))
    }
}

function Invoke-SkillEvolutionFullGateForProjection {
    $runner = Join-Path $Root 'scripts\quality\run-local-quality-gates.ps1'
    $verifier = Join-Path $Root 'scripts\quality\verify-current-quality-gate.ps1'
    if (-not (Test-Path -LiteralPath $runner -PathType Leaf) -or -not (Test-Path -LiteralPath $verifier -PathType Leaf)) { throw 'Full quality-gate scripts are unavailable.' }
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $runner -Profile full -ReuseCurrentReceipt
    if ($LASTEXITCODE -ne 0) { throw ('Exact-current full gate failed with exit code {0}.' -f $LASTEXITCODE) }
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $verifier -RequiredProfile full -RequiredStatus passed
    if ($LASTEXITCODE -ne 0) { throw ('Exact-current full gate receipt verification failed with exit code {0}.' -f $LASTEXITCODE) }
    $pointerPath = Join-Path $Root 'reports\quality-gates\current.json'
    $pointer = Read-SkillEvolutionJson $pointerPath 'quality gate pointer'
    return [pscustomobject]@{ status = 'passed'; pointer_path = $pointerPath; receipt_path = [string]$pointer.receipt_path; receipt_hash = [string]$pointer.receipt_sha256 }
}

function Get-SkillEvolutionOption($Options, [string]$Name, [switch]$Required, [switch]$Multiple) {
    $key = $Name.ToLowerInvariant()
    [object[]]$values = if ($Options.values.ContainsKey($key)) { @($Options.values[$key].ToArray()) } else { @() }
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
            if ([bool]$data.pass) {
                $data = Add-SkillEvolutionHostAction $data ([pscustomobject][ordered]@{ automatic = $true; action = 'author_candidate'; required_skill = 'skill-creator'; candidate_directory = [string]$data.candidate_directory; instruction = 'Use skill-creator in the isolated candidate directory, then run execute evaluation. Do not write active sources or host roots.' })
            }
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
            if ($execute -and [bool]$data.promotion_eligible) {
                $requestPath = Join-Path (Split-Path -Parent $outFull) ('promotion-review-request-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
                $reviewRequest = New-SkillEvolutionPromotionReviewRequest -CandidateDirectory $candidate -Evaluation $data -EvaluationPath $outFull -OutPath $requestPath -RepoRoot $Root
                $data | Add-Member -NotePropertyName status -NotePropertyValue 'authorization_required' -Force
                $data | Add-Member -NotePropertyName review_request_path -NotePropertyValue $reviewRequest.request_path -Force
                $data | Add-Member -NotePropertyName interaction -NotePropertyValue $reviewRequest.request.interaction -Force
                $data = Add-SkillEvolutionHostAction $data ([pscustomobject][ordered]@{ automatic = $false; action = 'notify_and_pause'; request_path = $reviewRequest.request_path; interaction = $reviewRequest.request.interaction })
            }
        }
        'request' {
            $skill = Get-SkillEvolutionOption $options '--skill' -Required
            $action = Get-SkillEvolutionOption $options '--action'
            if ([string]::IsNullOrWhiteSpace($action)) { $action = 'auto' }
            if ($action -notin @('auto', 'enable', 'refresh', 'retire')) { throw ('Unsupported request action: {0}' -f $action) }
            $promotionReceipt = Get-SkillEvolutionOption $options '--promotion-receipt'
            if (-not [string]::IsNullOrWhiteSpace($promotionReceipt)) { $promotionReceipt = Resolve-SkillEvolutionPath $promotionReceipt $Root }
            $out = Resolve-SkillEvolutionPath (Get-SkillEvolutionOption $options '--out' -Required) $Root
            $requestResult = New-SkillEvolutionActivationReviewRequest -SkillName $skill -Action $action -PromotionReceiptPath $promotionReceipt -OutPath $out -RepoRoot $Root
            $data = [pscustomobject][ordered]@{ pass = $true; status = 'authorization_required'; review_request_path = $requestResult.request_path; request_hash = $requestResult.request_hash; interaction = $requestResult.request.interaction; active_writes = 0; host_writes = 0; provider_calls = 0 }
            $data = Add-SkillEvolutionHostAction $data ([pscustomobject][ordered]@{ automatic = $false; action = 'notify_and_pause'; request_path = $requestResult.request_path; interaction = $requestResult.request.interaction })
        }
        'decide' {
            $requestPath = Resolve-SkillEvolutionPath (Get-SkillEvolutionOption $options '--request' -Required) $Root
            $decisionValue = Get-SkillEvolutionOption $options '--decision' -Required
            if ($decisionValue -notin @('approve', 'reject', 'reject_delete')) { throw ('Unsupported decision: {0}' -f $decisionValue) }
            $reviewer = Get-SkillEvolutionOption $options '--reviewer' -Required
            $token = Get-SkillEvolutionOption $options '--token' -Required
            $outRoot = Assert-SkillEvolutionReportPath (Resolve-SkillEvolutionPath (Get-SkillEvolutionOption $options '--out' -Required) $Root) $Root
            [System.IO.Directory]::CreateDirectory($outRoot) | Out-Null
            $request = Read-SkillEvolutionJson $requestPath 'skill evolution review request'
            if ($decisionValue -eq 'reject_delete' -and [string]$request.review_type -ne 'promotion') { throw 'reject_delete is only valid for an isolated promotion candidate.' }
            $decisionPath = Join-Path $outRoot ('decision-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
            $decisionResult = New-SkillEvolutionDecision -Request $request -RequestPath $requestPath -Decision $decisionValue -Reviewer $reviewer -Token $token -OutPath $decisionPath -RepoRoot $Root
            if ($decisionValue -in @('reject', 'reject_delete')) {
                $cleanup = $null
                if ($decisionValue -eq 'reject_delete') {
                    $cleanup = Invoke-SkillEvolutionRejectedCleanup -Decision $decisionResult.decision -Token DELETE_REJECTED_SKILL_CANDIDATE -OutPath (Join-Path $outRoot 'cleanup-receipt.json') -RepoRoot $Root
                }
                $rejectionStatus = if ($cleanup) { 'rejected_and_cleaned' } elseif ([string]$request.review_type -eq 'activation') { 'rejected_package_remains_cold' } else { 'rejected_retained' }
                $data = [pscustomobject][ordered]@{ pass = $true; status = $rejectionStatus; disposition = [string]$decisionResult.decision.disposition; decision_path = $decisionResult.decision_path; cleanup = $cleanup; cleanup_not_before = $decisionResult.decision.cleanup_not_before; active_writes = 0; host_writes = 0; provider_calls = 0 }
            }
            elseif ([string]$request.review_type -eq 'promotion') {
                $evaluation = Read-SkillEvolutionJson ([string]$request.evaluation_path) 'evaluation receipt'
                $plan = New-SkillEvolutionPlan -CandidateDirectory ([string]$request.subject_path) -Evaluation $evaluation -EvaluationPath ([string]$request.evaluation_path) -Review $decisionResult.decision -ReviewPath $decisionResult.decision_path -RepoRoot $Root
                $planPath = Join-Path $outRoot 'promotion-plan.json'; Write-SkillEvolutionJsonAtomic $planPath $plan
                $receiptPath = Join-Path $outRoot 'promotion-receipt.json'
                $receipt = Invoke-SkillEvolutionApply -Plan $plan -Token PROMOTE_SKILL_CANDIDATE -ReceiptPath $receiptPath -RepoRoot $Root
                $build = Invoke-SkillEvolutionColdBuild { Invoke-SkillEvolutionRollback -Receipt $receipt -Token ROLLBACK_SKILL_PROMOTION -OutPath (Join-Path $outRoot 'automatic-promotion-rollback.json') -RepoRoot $Root } 'Cold catalog build failed after promotion'
                $activationRequestPath = Join-Path $outRoot 'activation-review-request.json'
                $activationRequest = New-SkillEvolutionActivationReviewRequest -SkillName ([string]$request.skill_name) -Action auto -PromotionReceiptPath $receiptPath -OutPath $activationRequestPath -RepoRoot $Root
                $data = [pscustomobject][ordered]@{ pass = $true; status = 'authorization_required'; promotion_receipt_path = $receiptPath; cold_build = $build; review_request_path = $activationRequest.request_path; interaction = $activationRequest.request.interaction; truth_boundary = 'promoted_cold_catalog_not_projected'; host_writes = 0; provider_calls = 0 }
                $data = Add-SkillEvolutionHostAction $data ([pscustomobject][ordered]@{ automatic = $false; action = 'notify_and_pause'; request_path = $activationRequest.request_path; interaction = $activationRequest.request.interaction })
            }
            else {
                $plan = New-SkillEvolutionActivationPlan -Request $request -RequestPath $requestPath -Decision $decisionResult.decision -DecisionPath $decisionResult.decision_path -RepoRoot $Root
                $planPath = Join-Path $outRoot 'activation-plan.json'; Write-SkillEvolutionJsonAtomic $planPath $plan
                $receiptPath = Join-Path $outRoot 'activation-receipt.json'
                $receipt = Invoke-SkillEvolutionActivationApply -Plan $plan -Token $token -ReceiptPath $receiptPath -RepoRoot $Root
                $build = Invoke-SkillEvolutionColdBuild { Invoke-SkillEvolutionActivationRollback -Receipt $receipt -Token ROLLBACK_SKILL_ACTIVATION -OutPath (Join-Path $outRoot 'automatic-activation-rollback.json') -RepoRoot $Root } 'Cold build failed after activation staging'
                $projectCommand = '.\skills.ps1 skill-evolution project --receipt "{0}" --decision "{1}" --token PROJECT_SKILL_TO_HOST --out "{2}" --json' -f $receiptPath, $decisionResult.decision_path, (Join-Path $outRoot 'projection-receipt.json')
                $data = [pscustomobject][ordered]@{ pass = $true; status = 'repo_closeout_required'; activation_receipt_path = $receiptPath; decision_path = $decisionResult.decision_path; cold_build = $build; truth_boundary = 'activation_staged_not_projected'; host_writes = 0; provider_calls = 0 }
                $data = Add-SkillEvolutionHostAction $data ([pscustomobject][ordered]@{ automatic = $true; action = 'commit_gate_and_project'; instruction = 'Commit only the reviewed package/config/generated changes, then invoke the project command. Project reuses or runs the exact-current full gate and refuses dirty source.'; project_command = $projectCommand })
            }
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
            $receipt = Invoke-SkillEvolutionApply -Plan $plan -Token $token -ReceiptPath $out -RepoRoot $Root
            $build = Invoke-SkillEvolutionColdBuild { Invoke-SkillEvolutionRollback -Receipt $receipt -Token ROLLBACK_SKILL_PROMOTION -OutPath (([IO.Path]::ChangeExtension($out, '.automatic-rollback.json'))) -RepoRoot $Root } 'Cold catalog build failed after promotion'
            $activationRequestPath = Join-Path (Split-Path -Parent $out) ('activation-review-request-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
            $activationRequest = New-SkillEvolutionActivationReviewRequest -SkillName ([string]$receipt.lifecycle.skill_name) -Action auto -PromotionReceiptPath $out -OutPath $activationRequestPath -RepoRoot $Root
            $data = [pscustomobject]@{ pass = $true; status = 'authorization_required'; receipt = $receipt; receipt_path = $out; cold_build = $build; review_request_path = $activationRequest.request_path; interaction = $activationRequest.request.interaction; truth_boundary = 'promoted_cold_catalog_not_projected'; host_writes = 0; projection_changed = $false }
            $data = Add-SkillEvolutionHostAction $data ([pscustomobject][ordered]@{ automatic = $false; action = 'notify_and_pause'; request_path = $activationRequest.request_path; interaction = $activationRequest.request.interaction })
        }
        'project' {
            $receiptPath = Resolve-SkillEvolutionPath (Get-SkillEvolutionOption $options '--receipt' -Required) $Root
            $decisionPath = Resolve-SkillEvolutionPath (Get-SkillEvolutionOption $options '--decision' -Required) $Root
            $token = Get-SkillEvolutionOption $options '--token' -Required
            $out = Assert-SkillEvolutionReportPath (Resolve-SkillEvolutionPath (Get-SkillEvolutionOption $options '--out' -Required) $Root) $Root
            $activationReceipt = Read-SkillEvolutionJson $receiptPath 'activation receipt'
            $authorization = Test-SkillEvolutionProjectionAuthorization $activationReceipt $decisionPath $token $Root
            if (-not $authorization.pass) { throw ('Projection authorization is invalid: {0}' -f (@($authorization.findings.code) -join ',')) }
            $statusText = @(& git -C $Root status --porcelain=v1 --untracked-files=all 2>&1)
            if ($LASTEXITCODE -ne 0 -or -not [string]::IsNullOrWhiteSpace(($statusText -join "`n"))) { throw 'Formal host projection requires an exact clean Git worktree after the reviewed activation commit.' }
            $sourceRevision = (@(& git -C $Root rev-parse HEAD 2>&1) -join '').Trim()
            if ($LASTEXITCODE -ne 0 -or $sourceRevision -notmatch '^[0-9a-fA-F]{40,64}$') { throw 'Formal host projection requires a resolvable Git revision.' }
            $gate = Invoke-SkillEvolutionFullGateForProjection
            $postGateStatus = @(& git -C $Root status --porcelain=v1 --untracked-files=all 2>&1)
            if ($LASTEXITCODE -ne 0 -or -not [string]::IsNullOrWhiteSpace(($postGateStatus -join "`n"))) { throw 'Full gate changed the tracked source; host projection remains blocked until the source is recommitted and reverified.' }
            $postGateRevision = (@(& git -C $Root rev-parse HEAD 2>&1) -join '').Trim()
            if ($postGateRevision -ne $sourceRevision) { throw 'Source revision changed during the full gate.' }
            $authorization = Test-SkillEvolutionProjectionAuthorization $activationReceipt $decisionPath $token $Root
            if (-not $authorization.pass) { throw ('Projection authorization became invalid during the full gate: {0}' -f (@($authorization.findings.code) -join ',')) }
            构建生效
            $cfg = Read-SkillEvolutionJson (Join-Path $Root 'skills.json') 'skills config'
            $manifestPath = Resolve-SkillEvolutionPath ([string]$cfg.skill_projection.manifest_path) $Root
            $manifest = Read-SkillEvolutionJson $manifestPath 'skill projection manifest'
            $surface = New-SkillSurfaceView -RepoRoot $Root -Config $cfg
            if (-not [bool]$surface.pass) { throw ('Post-projection skill surface inventory failed: {0}' -f (@($surface.findings.code) -join ',')) }
            if (Test-Path -LiteralPath $out) { throw ('Projection receipt already exists: {0}' -f $out) }
            $projectionReceipt = [pscustomobject][ordered]@{ schema_version = 1; status = 'projected'; projected_at = [datetimeoffset]::UtcNow.ToString('o'); skill_name = [string]$activationReceipt.lifecycle.skill_name; action = [string]$activationReceipt.lifecycle.activation_action; source_revision = $sourceRevision; activation_receipt_path = $receiptPath; activation_receipt_hash = Get-SkillEvolutionFileHash $receiptPath; decision_path = $decisionPath; decision_hash = Get-SkillEvolutionFileHash $decisionPath; quality_gate = $gate; projection_manifest_path = $manifestPath; projection_fingerprint = [string]$manifest.projection_fingerprint; promotion_mode = [string]$manifest.promotion_mode; native_projection = $manifest.native_projection; surface_inventory = $surface; host_projection_written = $true; host_inventory_loaded = 'not_observed'; host_invocation_observed = 'not_observed'; live_accepted = 'not_accepted'; next_host_action = 'Run a fresh task with authoritative injection/execution events; keep host acceptance partial when receipts are unavailable.' }
            Write-SkillEvolutionJsonAtomic $out $projectionReceipt
            $data = $projectionReceipt
        }
        'cleanup' {
            $decisionPath = Resolve-SkillEvolutionPath (Get-SkillEvolutionOption $options '--decision' -Required) $Root
            $token = Get-SkillEvolutionOption $options '--token' -Required
            $out = Resolve-SkillEvolutionPath (Get-SkillEvolutionOption $options '--out' -Required) $Root
            $decision = Read-SkillEvolutionJson $decisionPath 'rejection decision'
            $data = Invoke-SkillEvolutionRejectedCleanup -Decision $decision -Token $token -OutPath $out -RepoRoot $Root
        }
        'rollback' {
            $receiptPath = Resolve-SkillEvolutionPath (Get-SkillEvolutionOption $options '--receipt' -Required) $Root
            $token = Get-SkillEvolutionOption $options '--token' -Required
            $out = Get-SkillEvolutionOption $options '--out'
            if (-not [string]::IsNullOrWhiteSpace($out)) { $out = Resolve-SkillEvolutionPath $out $Root }
            $receipt = Read-SkillEvolutionJson $receiptPath 'promotion receipt'
            if ([string]$receipt.lifecycle.operation_kind -eq 'activation') { $data = Invoke-SkillEvolutionActivationRollback -Receipt $receipt -Token $token -OutPath $out -RepoRoot $Root }
            else { $data = Invoke-SkillEvolutionRollback -Receipt $receipt -Token $token -OutPath $out -RepoRoot $Root }
        }
        default { throw ('Unknown skill-evolution command: {0}' -f $command) }
    }
    $pass = if ($null -ne (Get-SkillEvolutionProperty $data 'pass')) { [bool]$data.pass } elseif ([string]$data.status -in @('failed', 'partial')) { $false } else { $true }
    $envelope = [pscustomobject][ordered]@{ schema_version = 1; command = ('skill-evolution-{0}' -f $command); pass = $pass; truth_boundary = if ($command -eq 'evaluate' -and $options.flags.Contains('--execute')) { 'isolated_forward_test_not_host_invocation' } else { 'repo_controlled_skill_lifecycle' }; data = $data }
    $output = if ($json) { $envelope | ConvertTo-Json -Depth 80 -Compress } else {
        $summary = 'skill-evolution {0}: pass={1}; status={2}' -f $command, $pass, [string](Get-SkillEvolutionProperty $data 'status')
        $interaction = Get-SkillEvolutionProperty $data 'interaction'
        if ($null -ne $interaction -and [bool](Get-SkillEvolutionProperty $interaction 'required')) { $summary += "`nQUESTION: " + [string]$interaction.question }
        $summary
    }
    return [pscustomobject]@{ exit_code = $(if ($pass) { 0 } else { 2 }); output = $output; json = $json; envelope = $envelope }
}
