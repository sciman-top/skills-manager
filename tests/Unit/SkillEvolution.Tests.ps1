$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $repoRoot 'src\Application\SkillEvolution.ps1')
. (Join-Path $repoRoot 'src\Commands\SkillEvolution.ps1')

function 构建生效 { param([switch]$SkipHostProjection) $script:skillEvolutionBuildCalls++ }

function New-SkillEvolutionFixtureRepo([string]$Root) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'overrides\custom') | Out-Null
    [IO.File]::WriteAllText((Join-Path $Root 'skills.json'), '{"schema_version":1,"skill_projection":{"managed_link_includes":["core-skill"],"manifest_path":"reports/skill-projection/current.json"}}', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $Root 'skills.lock.json'), '{"schema_version":1}', [Text.UTF8Encoding]::new($false))
}

function New-SkillEvolutionCandidate([string]$Root, [string]$Name = 'demo-skill') {
    $candidate = Join-Path $Root ('candidate\{0}' -f $Name)
    New-Item -ItemType Directory -Force -Path $candidate | Out-Null
    $skill = "---`nname: $Name`ndescription: Use when the repeated fixture workflow needs the admitted deterministic steps.`n---`n`n# $Name`n`nApply the bounded fixture workflow and preserve negative cases.`n"
    [IO.File]::WriteAllText((Join-Path $candidate 'SKILL.md'), $skill, [Text.UTF8Encoding]::new($false))
    $state = Get-SkillEvolutionPackageState $candidate
    $manifest = [pscustomobject]@{ schema_version = 1; skill_name = $Name; candidate_mode = 'new'; candidate_directory = $candidate; baseline_fingerprint = Get-OperationSha256 ''; initial_candidate_fingerprint = $state.fingerprint; allowed_paths = @($state.files.path) }
    [IO.File]::WriteAllText((Join-Path $candidate 'candidate.json'), ($manifest | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    return $candidate
}

function New-SkillEvolutionCorpus {
    return [pscustomobject]@{
        schema_version = 1
        baseline_metrics = [pscustomobject]@{ success_count = 0; false_trigger_count = 0; tool_rounds = 10; side_effects = 0 }
        cases = @(
            [pscustomobject]@{ id = 'positive-a'; kind = 'positive'; request = 'fixture a' }
            [pscustomobject]@{ id = 'positive-b'; kind = 'positive'; request = 'fixture b' }
            [pscustomobject]@{ id = 'negative-a'; kind = 'negative'; request = 'unrelated' }
            [pscustomobject]@{ id = 'baseline-a'; kind = 'baseline'; request = 'no skill' }
        )
    }
}

function New-SkillEvolutionCaseResults([string]$Name = 'demo-skill') {
    return @(
        [pscustomobject]@{ case_id = 'positive-a'; exit_code = 0; parse_ok = $true; applicable = $true; task_satisfied = $true; selected_skill = $Name; tool_rounds = 1; side_effects = 0; duration_ms = 1; input_tokens = 1; output_tokens = 1; model = 'gpt-5.6-sol'; reasoning_effort = 'medium' }
        [pscustomobject]@{ case_id = 'positive-b'; exit_code = 0; parse_ok = $true; applicable = $true; task_satisfied = $true; selected_skill = $Name; tool_rounds = 1; side_effects = 0; duration_ms = 1; input_tokens = 1; output_tokens = 1; model = 'gpt-5.6-sol'; reasoning_effort = 'medium' }
        [pscustomobject]@{ case_id = 'negative-a'; exit_code = 0; parse_ok = $true; applicable = $false; task_satisfied = $false; selected_skill = $null; tool_rounds = 0; side_effects = 0; duration_ms = 1; input_tokens = 1; output_tokens = 1; model = 'gpt-5.6-sol'; reasoning_effort = 'medium' }
        [pscustomobject]@{ case_id = 'baseline-a'; exit_code = 0; parse_ok = $true; applicable = $false; task_satisfied = $false; selected_skill = $null; tool_rounds = 0; side_effects = 0; duration_ms = 1; input_tokens = 1; output_tokens = 1; model = 'gpt-5.6-sol'; reasoning_effort = 'medium' }
    )
}

function New-AdmittedPilot {
    $common = [ordered]@{ schema_version = 1; signal_type = 'repeated_manual_work'; surface = 'repo_supply'; target_skill = 'demo-skill'; issue_signature = 'sig-redacted'; evidence_link = 'evidence://fixture'; baseline = 'native'; native_equivalent = 'none'; disposition = 'candidate'; workflow_stable = $true; consumer = 'fixture-consumer'; net_benefit_metric = 'rework'; rollback_condition = 'restore baseline'; retirement_condition = 'native coverage' }
    $signalA = [pscustomobject]$common
    $signalBMap = [ordered]@{}; foreach ($key in $common.Keys) { $signalBMap[$key] = $common[$key] }; $signalBMap.negative_case = $true
    return [pscustomobject]@{ schema_version = 1; samples = @([pscustomobject]@{ sample_id = 'sample-a'; task_id = 'task-a'; countable = $true; synthetic = $false; self_referential = $false; skill_signal = $signalA }, [pscustomobject]@{ sample_id = 'sample-b'; task_id = 'task-b'; countable = $true; synthetic = $false; self_referential = $false; skill_signal = [pscustomobject]$signalBMap }) }
}

Describe 'SkillEvolution controlled lifecycle' {
    BeforeEach {
        $script:fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('skill-evolution-tests-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:fixtureRoot | Out-Null
        $script:fixtureRepo = Join-Path $script:fixtureRoot 'repo'
        New-SkillEvolutionFixtureRepo $script:fixtureRepo
        $script:Root = $script:fixtureRepo
        $script:skillEvolutionBuildCalls = 0
        $script:evolutionRoot = Join-Path $script:fixtureRepo 'reports\skill-evolution\fixture-run'
        New-Item -ItemType Directory -Force -Path $script:evolutionRoot | Out-Null
    }
    AfterEach { if (Test-Path -LiteralPath $script:fixtureRoot) { Remove-Item -LiteralPath $script:fixtureRoot -Recurse -Force } }

    It 'rejects a candidate admitted from only one real task' {
        $pilot = New-AdmittedPilot
        $result = Test-SkillEvolutionAdmission -Pilot $pilot -SignalIds @('sample-a')
        $result.pass | Should -BeFalse
        @($result.findings.code) | Should -Contain 'independent_signal_threshold_not_met'
        @($result.findings.code) | Should -Contain 'negative_case_missing'
    }

    It 'does not let no_change samples force candidate admission' {
        $pilot = New-AdmittedPilot
        foreach ($sample in @($pilot.samples)) { $sample.skill_signal.signal_type = 'no_change' }
        $result = Test-SkillEvolutionAdmission -Pilot $pilot -SignalIds @('sample-a', 'sample-b') -SkillName 'demo-skill'
        $result.pass | Should -BeFalse
        $result.actionable_signal_count | Should -Be 0
        @($result.findings.code) | Should -Contain 'independent_signal_threshold_not_met'
    }

    It 'rejects an actionable signal when a native equivalent already covers it' {
        $pilot = New-AdmittedPilot
        $pilot.samples[0].skill_signal.native_equivalent = 'host-native-skill'
        $result = Test-SkillEvolutionAdmission -Pilot $pilot -SignalIds @('sample-a', 'sample-b') -SkillName 'demo-skill'
        $result.pass | Should -BeFalse
        @($result.findings.code) | Should -Contain 'native_equivalent_present'
    }

    It 'prepares an isolated candidate with zero active/provider/host writes' {
        $result = Invoke-SkillEvolutionPrepare -Pilot (New-AdmittedPilot) -SignalIds @('sample-a', 'sample-b') -SkillName 'demo-skill' -CandidateMode new -OutRoot $script:evolutionRoot -RepoRoot $script:fixtureRepo
        $result.pass | Should -BeTrue
        $result.active_writes | Should -Be 0
        $result.provider_calls | Should -Be 0
        $result.host_writes | Should -Be 0
        Test-Path -LiteralPath (Join-Path $result.candidate_directory 'candidate.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:fixtureRepo 'overrides\custom\demo-skill') | Should -BeFalse
    }

    It 'requires two positives, a negative, and a no-skill baseline' {
        $candidate = New-SkillEvolutionCandidate $script:evolutionRoot
        $corpus = New-SkillEvolutionCorpus
        $corpus.cases = @($corpus.cases | Where-Object id -ne 'baseline-a')
        $result = Invoke-SkillEvolutionEvaluate -CandidateDirectory $candidate -Corpus $corpus -RepoRoot $script:fixtureRepo
        $result.pass | Should -BeFalse
        @($result.findings.code) | Should -Contain 'no_skill_baseline_missing'
    }

    It 'keeps static evaluation provider-free and ineligible for promotion' {
        $candidate = New-SkillEvolutionCandidate $script:evolutionRoot
        $result = Invoke-SkillEvolutionEvaluate -CandidateDirectory $candidate -Corpus (New-SkillEvolutionCorpus) -RepoRoot $script:fixtureRepo
        $result.pass | Should -BeTrue
        $result.promotion_eligible | Should -BeFalse
        $result.provider_calls | Should -Be 0
        $result.host_writes | Should -Be 0
    }

    It 'rejects executable, hook, or network candidate surfaces' {
        $candidate = New-SkillEvolutionCandidate $script:evolutionRoot
        New-Item -ItemType Directory -Force -Path (Join-Path $candidate 'scripts') | Out-Null
        [IO.File]::WriteAllText((Join-Path $candidate 'scripts\run.ps1'), 'Invoke-WebRequest https://example.invalid', [Text.UTF8Encoding]::new($false))
        $state = Get-SkillEvolutionPackageState $candidate
        $state.pass | Should -BeFalse
        @($state.findings.code) | Should -Contain 'candidate_path_forbidden'
    }

    It 'rejects traversal paths and candidate junctions' {
        (Test-SkillEvolutionAllowedRelativePath 'references\..\..\skills.json') | Should -BeFalse
        $candidate = New-SkillEvolutionCandidate $script:evolutionRoot
        $outside = Join-Path $script:fixtureRoot 'outside'; New-Item -ItemType Directory -Force -Path $outside | Out-Null
        New-Item -ItemType Junction -Path (Join-Path $candidate 'references') -Target $outside | Out-Null
        $state = Get-SkillEvolutionPackageState $candidate
        $state.pass | Should -BeFalse
        @($state.findings.code) | Should -Contain 'candidate_reparse_entry'
    }

    It 'does not count an unparseable failed negative execution as a passing control' {
        $candidate = New-SkillEvolutionCandidate $script:evolutionRoot
        $results = @(New-SkillEvolutionCaseResults)
        $results[2].exit_code = 1
        $results[2].parse_ok = $false
        $result = Invoke-SkillEvolutionEvaluate -CandidateDirectory $candidate -Corpus (New-SkillEvolutionCorpus) -CaseResults $results -Execute -RepoRoot $script:fixtureRepo
        $result.pass | Should -BeFalse
        $result.promotion_eligible | Should -BeFalse
        @($result.findings.code) | Should -Contain 'forward_test_receipt_invalid'
    }

    It 'creates a promotion plan only from exact-current evaluation and review hashes' {
        $candidate = New-SkillEvolutionCandidate $script:evolutionRoot
        $evaluation = Invoke-SkillEvolutionEvaluate -CandidateDirectory $candidate -Corpus (New-SkillEvolutionCorpus) -CaseResults (New-SkillEvolutionCaseResults) -Execute -RepoRoot $script:fixtureRepo
        $evaluation.promotion_eligible | Should -BeTrue
        $evaluationPath = Join-Path $script:evolutionRoot 'evaluation.json'
        Write-SkillEvolutionJsonAtomic $evaluationPath $evaluation
        $review = [pscustomobject]@{ candidate_fingerprint = $evaluation.candidate_fingerprint; baseline_fingerprint = $evaluation.baseline_fingerprint; allowed_paths = @($evaluation.allowed_paths); reviewer = 'fixture-reviewer'; decision = 'approve'; reviewed_at = [datetimeoffset]::UtcNow.AddMinutes(-1).ToString('o'); expires_at = [datetimeoffset]::UtcNow.AddHours(1).ToString('o'); evaluation_receipt_hash = Get-SkillEvolutionFileHash $evaluationPath }
        $reviewPath = Join-Path $script:evolutionRoot 'review.json'; Write-SkillEvolutionJsonAtomic $reviewPath $review
        $plan = New-SkillEvolutionPlan -CandidateDirectory $candidate -Evaluation $evaluation -EvaluationPath $evaluationPath -Review $review -ReviewPath $reviewPath -RepoRoot $script:fixtureRepo
        $plan.domain | Should -Be 'skill_lifecycle'
        (Test-OperationPlanContract $plan).pass | Should -BeTrue
        $plan.lifecycle.projection_disposition | Should -Be 'cold_catalog_only'
    }

    It 'fails closed on an expired review' {
        $candidate = New-SkillEvolutionCandidate $script:evolutionRoot
        $evaluation = Invoke-SkillEvolutionEvaluate -CandidateDirectory $candidate -Corpus (New-SkillEvolutionCorpus) -CaseResults (New-SkillEvolutionCaseResults) -Execute -RepoRoot $script:fixtureRepo
        $evaluationPath = Join-Path $script:evolutionRoot 'evaluation.json'; Write-SkillEvolutionJsonAtomic $evaluationPath $evaluation
        $review = [pscustomobject]@{ candidate_fingerprint = $evaluation.candidate_fingerprint; baseline_fingerprint = $evaluation.baseline_fingerprint; allowed_paths = @($evaluation.allowed_paths); reviewer = 'fixture-reviewer'; decision = 'approve'; reviewed_at = [datetimeoffset]::UtcNow.AddHours(-2).ToString('o'); expires_at = [datetimeoffset]::UtcNow.AddHours(-1).ToString('o'); evaluation_receipt_hash = Get-SkillEvolutionFileHash $evaluationPath }
        $reviewPath = Join-Path $script:evolutionRoot 'review.json'; Write-SkillEvolutionJsonAtomic $reviewPath $review
        { New-SkillEvolutionPlan -CandidateDirectory $candidate -Evaluation $evaluation -EvaluationPath $evaluationPath -Review $review -ReviewPath $reviewPath -RepoRoot $script:fixtureRepo } | Should -Throw
    }

    It 'applies only overrides custom and rolls back the exact receipt package' {
        $candidate = New-SkillEvolutionCandidate $script:evolutionRoot
        $evaluation = Invoke-SkillEvolutionEvaluate -CandidateDirectory $candidate -Corpus (New-SkillEvolutionCorpus) -CaseResults (New-SkillEvolutionCaseResults) -Execute -RepoRoot $script:fixtureRepo
        $evaluationPath = Join-Path $script:evolutionRoot 'evaluation.json'; Write-SkillEvolutionJsonAtomic $evaluationPath $evaluation
        $review = [pscustomobject]@{ candidate_fingerprint = $evaluation.candidate_fingerprint; baseline_fingerprint = $evaluation.baseline_fingerprint; allowed_paths = @($evaluation.allowed_paths); reviewer = 'fixture-reviewer'; decision = 'approve'; reviewed_at = [datetimeoffset]::UtcNow.AddMinutes(-1).ToString('o'); expires_at = [datetimeoffset]::UtcNow.AddHours(1).ToString('o'); evaluation_receipt_hash = Get-SkillEvolutionFileHash $evaluationPath }
        $reviewPath = Join-Path $script:evolutionRoot 'review.json'; Write-SkillEvolutionJsonAtomic $reviewPath $review
        $plan = New-SkillEvolutionPlan -CandidateDirectory $candidate -Evaluation $evaluation -EvaluationPath $evaluationPath -Review $review -ReviewPath $reviewPath -RepoRoot $script:fixtureRepo
        $maliciousPlan = ($plan | ConvertTo-Json -Depth 30) | ConvertFrom-Json
        $maliciousPlan.lifecycle.allowed_paths = @('SKILL.md', 'references\..\..\skills.json')
        $maliciousPlan.actions[0].metadata.allowed_paths = @($maliciousPlan.lifecycle.allowed_paths)
        { Invoke-SkillEvolutionApply -Plan $maliciousPlan -Token PROMOTE_SKILL_CANDIDATE -ReceiptPath (Join-Path $script:evolutionRoot 'malicious-receipt.json') -RepoRoot $script:fixtureRepo } | Should -Throw
        { Invoke-SkillEvolutionApply -Plan $plan -Token wrong -ReceiptPath (Join-Path $script:evolutionRoot 'wrong-token-receipt.json') -RepoRoot $script:fixtureRepo } | Should -Throw
        $skillPath = Join-Path $candidate 'SKILL.md'; $originalSkill = [IO.File]::ReadAllText($skillPath)
        [IO.File]::WriteAllText($skillPath, ($originalSkill + "`ndrift"), [Text.UTF8Encoding]::new($false))
        { Invoke-SkillEvolutionApply -Plan $plan -Token PROMOTE_SKILL_CANDIDATE -ReceiptPath (Join-Path $script:evolutionRoot 'drift-receipt.json') -RepoRoot $script:fixtureRepo } | Should -Throw
        [IO.File]::WriteAllText($skillPath, $originalSkill, [Text.UTF8Encoding]::new($false))
        $configHash = Get-SkillEvolutionFileHash (Join-Path $script:fixtureRepo 'skills.json')
        $receipt = Invoke-SkillEvolutionApply -Plan $plan -Token PROMOTE_SKILL_CANDIDATE -ReceiptPath (Join-Path $script:evolutionRoot 'receipts\receipt.json') -RepoRoot $script:fixtureRepo
        $receipt.status | Should -Be 'applied'
        Test-Path -LiteralPath (Join-Path $script:fixtureRepo 'overrides\custom\demo-skill\SKILL.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:fixtureRepo 'agent') | Should -BeFalse
        (Get-SkillEvolutionFileHash (Join-Path $script:fixtureRepo 'skills.json')) | Should -Be $configHash
        $receipt.lifecycle.host_writes | Should -Be 0
        $receipt.lifecycle.projection_changed | Should -BeFalse
        $rolled = Invoke-SkillEvolutionRollback -Receipt $receipt -Token ROLLBACK_SKILL_PROMOTION -RepoRoot $script:fixtureRepo
        $rolled.status | Should -Be 'rolled_back'
        Test-Path -LiteralPath (Join-Path $script:fixtureRepo 'overrides\custom\demo-skill') | Should -BeFalse
    }

    It 'refuses rollback after promoted source drift' {
        $candidate = New-SkillEvolutionCandidate $script:evolutionRoot
        $evaluation = Invoke-SkillEvolutionEvaluate -CandidateDirectory $candidate -Corpus (New-SkillEvolutionCorpus) -CaseResults (New-SkillEvolutionCaseResults) -Execute -RepoRoot $script:fixtureRepo
        $evaluationPath = Join-Path $script:evolutionRoot 'evaluation.json'; Write-SkillEvolutionJsonAtomic $evaluationPath $evaluation
        $review = [pscustomobject]@{ candidate_fingerprint = $evaluation.candidate_fingerprint; baseline_fingerprint = $evaluation.baseline_fingerprint; allowed_paths = @($evaluation.allowed_paths); reviewer = 'fixture-reviewer'; decision = 'approve'; reviewed_at = [datetimeoffset]::UtcNow.AddMinutes(-1).ToString('o'); expires_at = [datetimeoffset]::UtcNow.AddHours(1).ToString('o'); evaluation_receipt_hash = Get-SkillEvolutionFileHash $evaluationPath }
        $reviewPath = Join-Path $script:evolutionRoot 'review.json'; Write-SkillEvolutionJsonAtomic $reviewPath $review
        $plan = New-SkillEvolutionPlan -CandidateDirectory $candidate -Evaluation $evaluation -EvaluationPath $evaluationPath -Review $review -ReviewPath $reviewPath -RepoRoot $script:fixtureRepo
        $receipt = Invoke-SkillEvolutionApply -Plan $plan -Token PROMOTE_SKILL_CANDIDATE -ReceiptPath (Join-Path $script:evolutionRoot 'receipts\receipt.json') -RepoRoot $script:fixtureRepo
        Add-Content -LiteralPath (Join-Path $script:fixtureRepo 'overrides\custom\demo-skill\SKILL.md') -Value 'drift'
        { Invoke-SkillEvolutionRollback -Receipt $receipt -Token ROLLBACK_SKILL_PROMOTION -RepoRoot $script:fixtureRepo } | Should -Throw
    }

    It 'emits a structured question review request without active or host writes' {
        $candidate = New-SkillEvolutionCandidate $script:evolutionRoot
        $evaluation = Invoke-SkillEvolutionEvaluate -CandidateDirectory $candidate -Corpus (New-SkillEvolutionCorpus) -CaseResults (New-SkillEvolutionCaseResults) -Execute -RepoRoot $script:fixtureRepo
        $evaluationPath = Join-Path $script:evolutionRoot 'evaluation-review.json'; Write-SkillEvolutionJsonAtomic $evaluationPath $evaluation
        $requestPath = Join-Path $script:evolutionRoot 'promotion-review-request.json'
        $result = New-SkillEvolutionPromotionReviewRequest -CandidateDirectory $candidate -Evaluation $evaluation -EvaluationPath $evaluationPath -OutPath $requestPath -RepoRoot $script:fixtureRepo
        $result.request.status | Should -Be 'authorization_required'
        $result.request.interaction.kind | Should -Be 'question'
        $result.request.interaction.host_must_pause | Should -BeTrue
        $result.request.interaction.default_decision | Should -Be 'reject'
        $result.request.authorization_token | Should -Be 'PROMOTE_SKILL_CANDIDATE'
        Test-Path -LiteralPath (Join-Path $script:fixtureRepo 'overrides\custom\demo-skill') | Should -BeFalse
    }

    It 'turns an approval into the existing exact reviewed promotion plan' {
        $candidate = New-SkillEvolutionCandidate $script:evolutionRoot
        $evaluation = Invoke-SkillEvolutionEvaluate -CandidateDirectory $candidate -Corpus (New-SkillEvolutionCorpus) -CaseResults (New-SkillEvolutionCaseResults) -Execute -RepoRoot $script:fixtureRepo
        $evaluationPath = Join-Path $script:evolutionRoot 'evaluation-decision.json'; Write-SkillEvolutionJsonAtomic $evaluationPath $evaluation
        $requestPath = Join-Path $script:evolutionRoot 'promotion-decision-request.json'
        $requestResult = New-SkillEvolutionPromotionReviewRequest -CandidateDirectory $candidate -Evaluation $evaluation -EvaluationPath $evaluationPath -OutPath $requestPath -RepoRoot $script:fixtureRepo
        $decisionPath = Join-Path $script:evolutionRoot 'promotion-decision.json'
        $decisionResult = New-SkillEvolutionDecision -Request $requestResult.request -RequestPath $requestPath -Decision approve -Reviewer user -Token PROMOTE_SKILL_CANDIDATE -OutPath $decisionPath -RepoRoot $script:fixtureRepo
        $plan = New-SkillEvolutionPlan -CandidateDirectory $candidate -Evaluation $evaluation -EvaluationPath $evaluationPath -Review $decisionResult.decision -ReviewPath $decisionPath -RepoRoot $script:fixtureRepo
        (Test-OperationPlanContract $plan).pass | Should -BeTrue
        $plan.lifecycle.projection_disposition | Should -Be 'cold_catalog_only'
    }

    It 'deletes only an explicitly rejected isolated candidate' {
        $candidate = New-SkillEvolutionCandidate $script:evolutionRoot
        $evaluation = Invoke-SkillEvolutionEvaluate -CandidateDirectory $candidate -Corpus (New-SkillEvolutionCorpus) -CaseResults (New-SkillEvolutionCaseResults) -Execute -RepoRoot $script:fixtureRepo
        $evaluationPath = Join-Path $script:evolutionRoot 'evaluation-reject.json'; Write-SkillEvolutionJsonAtomic $evaluationPath $evaluation
        $requestPath = Join-Path $script:evolutionRoot 'promotion-reject-request.json'
        $requestResult = New-SkillEvolutionPromotionReviewRequest -CandidateDirectory $candidate -Evaluation $evaluation -EvaluationPath $evaluationPath -OutPath $requestPath -RepoRoot $script:fixtureRepo
        $decisionPath = Join-Path $script:evolutionRoot 'promotion-reject-decision.json'
        $decision = New-SkillEvolutionDecision -Request $requestResult.request -RequestPath $requestPath -Decision reject_delete -Reviewer user -Token DELETE_REJECTED_SKILL_CANDIDATE -OutPath $decisionPath -RepoRoot $script:fixtureRepo
        $configHash = Get-SkillEvolutionFileHash (Join-Path $script:fixtureRepo 'skills.json')
        $cleaned = Invoke-SkillEvolutionRejectedCleanup -Decision $decision.decision -Token DELETE_REJECTED_SKILL_CANDIDATE -OutPath (Join-Path $script:evolutionRoot 'cleanup-receipt.json') -RepoRoot $script:fixtureRepo
        $cleaned.status | Should -Be 'cleaned'
        Test-Path -LiteralPath $candidate | Should -BeFalse
        (Get-SkillEvolutionFileHash (Join-Path $script:fixtureRepo 'skills.json')) | Should -Be $configHash
        Test-Path -LiteralPath (Join-Path $script:fixtureRepo 'overrides\custom\demo-skill') | Should -BeFalse
    }

    It 'stages activation through OperationPlan and rolls back before projection' {
        $candidate = New-SkillEvolutionCandidate $script:evolutionRoot
        $target = Join-Path $script:fixtureRepo 'overrides\custom\demo-skill'
        Copy-SkillEvolutionPackage $candidate $target @('SKILL.md')
        $promotionReceiptPath = Join-Path $script:evolutionRoot 'fixture-promotion-receipt.json'
        $targetState = Get-SkillEvolutionTargetState $script:fixtureRepo 'demo-skill'
        $promotionReceipt = New-OperationReceipt -OperationId fixture-promotion -Status applied -StartedAt ([datetimeoffset]::UtcNow.AddMinutes(-1).ToString('o')) -CompletedAt ([datetimeoffset]::UtcNow.ToString('o'))
        $promotionReceipt | Add-Member -NotePropertyName lifecycle -NotePropertyValue ([pscustomobject]@{ skill_name = 'demo-skill'; after_fingerprint = $targetState.fingerprint })
        Write-SkillEvolutionJsonAtomic $promotionReceiptPath $promotionReceipt
        $requestPath = Join-Path $script:evolutionRoot 'activation-request.json'
        $requestResult = New-SkillEvolutionActivationReviewRequest -SkillName demo-skill -Action auto -PromotionReceiptPath $promotionReceiptPath -OutPath $requestPath -RepoRoot $script:fixtureRepo
        $requestResult.request.action | Should -Be 'enable'
        (@($requestResult.request.interaction.options.decision) -join '|') | Should -Be 'approve|reject'
        ($null -eq $requestResult.request.interaction.deletion_token) | Should -BeTrue
        $decisionPath = Join-Path $script:evolutionRoot 'activation-decision.json'
        $decision = New-SkillEvolutionDecision -Request $requestResult.request -RequestPath $requestPath -Decision approve -Reviewer user -Token ACTIVATE_SKILL_ON_HOST -OutPath $decisionPath -RepoRoot $script:fixtureRepo
        $plan = New-SkillEvolutionActivationPlan -Request $requestResult.request -RequestPath $requestPath -Decision $decision.decision -DecisionPath $decisionPath -RepoRoot $script:fixtureRepo
        (Test-OperationPlanContract $plan).pass | Should -BeTrue
        $plan.lifecycle.projection_disposition | Should -Be 'staged_then_project_after_clean_gate'
        $receiptPath = Join-Path $script:evolutionRoot 'activation-receipt.json'
        $receipt = Invoke-SkillEvolutionActivationApply -Plan $plan -Token ACTIVATE_SKILL_ON_HOST -ReceiptPath $receiptPath -RepoRoot $script:fixtureRepo
        $receipt.lifecycle.projection_state | Should -Be 'staged_not_projected'
        @((Get-Content -LiteralPath (Join-Path $script:fixtureRepo 'skills.json') -Raw | ConvertFrom-Json).skill_projection.managed_link_includes) | Should -Contain 'demo-skill'
        (Test-SkillEvolutionProjectionAuthorization $receipt $decisionPath PROJECT_SKILL_TO_HOST $script:fixtureRepo).pass | Should -BeTrue
        $serializedReceipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
        (Test-SkillEvolutionProjectionAuthorization $serializedReceipt $decisionPath PROJECT_SKILL_TO_HOST $script:fixtureRepo).pass | Should -BeTrue
        $rolled = Invoke-SkillEvolutionActivationRollback -Receipt $receipt -Token ROLLBACK_SKILL_ACTIVATION -OutPath (Join-Path $script:evolutionRoot 'activation-rollback.json') -RepoRoot $script:fixtureRepo
        $rolled.status | Should -Be 'rolled_back'
        @((Get-Content -LiteralPath (Join-Path $script:fixtureRepo 'skills.json') -Raw | ConvertFrom-Json).skill_projection.managed_link_includes) | Should -Not -Contain 'demo-skill'
    }

    It 'stages retirement without deleting the source package' {
        $candidate = New-SkillEvolutionCandidate $script:evolutionRoot
        $target = Join-Path $script:fixtureRepo 'overrides\custom\demo-skill'; Copy-SkillEvolutionPackage $candidate $target @('SKILL.md')
        $cfgPath = Join-Path $script:fixtureRepo 'skills.json'; $cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json; $cfg.skill_projection.managed_link_includes = @('core-skill', 'demo-skill'); Write-SkillEvolutionJsonAtomic $cfgPath $cfg
        $requestPath = Join-Path $script:evolutionRoot 'retire-request.json'
        $requestResult = New-SkillEvolutionActivationReviewRequest -SkillName demo-skill -Action retire -OutPath $requestPath -RepoRoot $script:fixtureRepo
        $decisionPath = Join-Path $script:evolutionRoot 'retire-decision.json'
        $decision = New-SkillEvolutionDecision -Request $requestResult.request -RequestPath $requestPath -Decision approve -Reviewer user -Token RETIRE_SKILL_ON_HOST -OutPath $decisionPath -RepoRoot $script:fixtureRepo
        $plan = New-SkillEvolutionActivationPlan -Request $requestResult.request -RequestPath $requestPath -Decision $decision.decision -DecisionPath $decisionPath -RepoRoot $script:fixtureRepo
        $receipt = Invoke-SkillEvolutionActivationApply -Plan $plan -Token RETIRE_SKILL_ON_HOST -ReceiptPath (Join-Path $script:evolutionRoot 'retire-receipt.json') -RepoRoot $script:fixtureRepo
        @((Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json).skill_projection.managed_link_includes) | Should -Not -Contain 'demo-skill'
        Test-Path -LiteralPath (Join-Path $target 'SKILL.md') | Should -BeTrue
        $receipt.lifecycle.host_writes | Should -Be 0
    }

    It 'keeps an activation package cold when the Desktop reviewer rejects it' {
        $candidate = New-SkillEvolutionCandidate $script:evolutionRoot
        $target = Join-Path $script:fixtureRepo 'overrides\custom\demo-skill'; Copy-SkillEvolutionPackage $candidate $target @('SKILL.md')
        $requestPath = Join-Path $script:evolutionRoot 'activation-reject-request.json'
        $request = New-SkillEvolutionActivationReviewRequest -SkillName demo-skill -Action enable -OutPath $requestPath -RepoRoot $script:fixtureRepo
        $configHash = Get-SkillEvolutionFileHash (Join-Path $script:fixtureRepo 'skills.json')
        $run = Invoke-SkillEvolutionCommand @('decide', '--request', $requestPath, '--decision', 'reject', '--reviewer', 'user', '--token', 'REJECT_SKILL_ACTIVATION_CHANGE', '--out', (Join-Path $script:evolutionRoot 'activation-reject'), '--json')
        $run.envelope.data.status | Should -Be 'rejected_package_remains_cold'
        $run.envelope.data.disposition | Should -Be 'package_remains_cold'
        $run.envelope.data.cleanup_not_before | Should -BeNullOrEmpty
        (Get-SkillEvolutionFileHash (Join-Path $script:fixtureRepo 'skills.json')) | Should -Be $configHash
        Test-Path -LiteralPath (Join-Path $target 'SKILL.md') | Should -BeTrue
    }

    It 'rejects activation review after catalog drift' {
        $candidate = New-SkillEvolutionCandidate $script:evolutionRoot
        $target = Join-Path $script:fixtureRepo 'overrides\custom\demo-skill'; Copy-SkillEvolutionPackage $candidate $target @('SKILL.md')
        $requestPath = Join-Path $script:evolutionRoot 'activation-catalog-request.json'
        $request = New-SkillEvolutionActivationReviewRequest -SkillName demo-skill -Action enable -OutPath $requestPath -RepoRoot $script:fixtureRepo
        Add-Content -LiteralPath (Join-Path $script:fixtureRepo 'skills.lock.json') -Value 'drift'
        $validation = Test-SkillEvolutionReviewRequest $request.request $requestPath $script:fixtureRepo
        $validation.pass | Should -BeFalse
        @($validation.findings.code) | Should -Contain 'review_request_catalog_drift'
    }

    It 're-reads activation request and decision semantics before apply' {
        $candidate = New-SkillEvolutionCandidate $script:evolutionRoot
        $target = Join-Path $script:fixtureRepo 'overrides\custom\demo-skill'; Copy-SkillEvolutionPackage $candidate $target @('SKILL.md')
        $requestPath = Join-Path $script:evolutionRoot 'activation-reread-request.json'
        $request = New-SkillEvolutionActivationReviewRequest -SkillName demo-skill -Action enable -OutPath $requestPath -RepoRoot $script:fixtureRepo
        $decisionPath = Join-Path $script:evolutionRoot 'activation-reread-decision.json'
        $decision = New-SkillEvolutionDecision -Request $request.request -RequestPath $requestPath -Decision approve -Reviewer user -Token ACTIVATE_SKILL_ON_HOST -OutPath $decisionPath -RepoRoot $script:fixtureRepo
        $plan = New-SkillEvolutionActivationPlan -Request $request.request -RequestPath $requestPath -Decision $decision.decision -DecisionPath $decisionPath -RepoRoot $script:fixtureRepo
        $forgedDecision = Get-Content -LiteralPath $decisionPath -Raw | ConvertFrom-Json
        $forgedDecision.decision = 'reject'; Write-SkillEvolutionJsonAtomic $decisionPath $forgedDecision
        $plan.lifecycle.review_hash = Get-SkillEvolutionFileHash $decisionPath
        { Invoke-SkillEvolutionActivationApply -Plan $plan -Token ACTIVATE_SKILL_ON_HOST -ReceiptPath (Join-Path $script:evolutionRoot 'forged-decision-receipt.json') -RepoRoot $script:fixtureRepo } | Should -Throw

        $requestPath2 = Join-Path $script:evolutionRoot 'activation-reread-request-2.json'
        $request2 = New-SkillEvolutionActivationReviewRequest -SkillName demo-skill -Action enable -OutPath $requestPath2 -RepoRoot $script:fixtureRepo
        $decisionPath2 = Join-Path $script:evolutionRoot 'activation-reread-decision-2.json'
        $decision2 = New-SkillEvolutionDecision -Request $request2.request -RequestPath $requestPath2 -Decision approve -Reviewer user -Token ACTIVATE_SKILL_ON_HOST -OutPath $decisionPath2 -RepoRoot $script:fixtureRepo
        $plan2 = New-SkillEvolutionActivationPlan -Request $request2.request -RequestPath $requestPath2 -Decision $decision2.decision -DecisionPath $decisionPath2 -RepoRoot $script:fixtureRepo
        $forgedRequest = Get-Content -LiteralPath $requestPath2 -Raw | ConvertFrom-Json
        $forgedRequest.authorization_token = 'FORGED'; $forgedRequest.interaction.approval_token = 'FORGED'; Write-SkillEvolutionJsonAtomic $requestPath2 $forgedRequest
        $plan2.lifecycle.request_hash = Get-SkillEvolutionFileHash $requestPath2
        { Invoke-SkillEvolutionActivationApply -Plan $plan2 -Token ACTIVATE_SKILL_ON_HOST -ReceiptPath (Join-Path $script:evolutionRoot 'forged-request-receipt.json') -RepoRoot $script:fixtureRepo } | Should -Throw
    }

    It 'rejects a different decision path even when its content hash matches' {
        $candidate = New-SkillEvolutionCandidate $script:evolutionRoot
        $target = Join-Path $script:fixtureRepo 'overrides\custom\demo-skill'; Copy-SkillEvolutionPackage $candidate $target @('SKILL.md')
        $requestPath = Join-Path $script:evolutionRoot 'activation-path-request.json'
        $request = New-SkillEvolutionActivationReviewRequest -SkillName demo-skill -Action enable -OutPath $requestPath -RepoRoot $script:fixtureRepo
        $decisionPath = Join-Path $script:evolutionRoot 'activation-path-decision.json'
        $decision = New-SkillEvolutionDecision -Request $request.request -RequestPath $requestPath -Decision approve -Reviewer user -Token ACTIVATE_SKILL_ON_HOST -OutPath $decisionPath -RepoRoot $script:fixtureRepo
        $plan = New-SkillEvolutionActivationPlan -Request $request.request -RequestPath $requestPath -Decision $decision.decision -DecisionPath $decisionPath -RepoRoot $script:fixtureRepo
        $receipt = Invoke-SkillEvolutionActivationApply -Plan $plan -Token ACTIVATE_SKILL_ON_HOST -ReceiptPath (Join-Path $script:evolutionRoot 'activation-path-receipt.json') -RepoRoot $script:fixtureRepo
        $copyPath = Join-Path $script:evolutionRoot 'activation-path-decision-copy.json'; Copy-Item -LiteralPath $decisionPath -Destination $copyPath
        $authorization = Test-SkillEvolutionProjectionAuthorization $receipt $copyPath PROJECT_SKILL_TO_HOST $script:fixtureRepo
        $authorization.pass | Should -BeFalse
        @($authorization.findings.code) | Should -Contain 'projection_decision_path_invalid'
    }

    It 'rechecks projection authorization after the full gate before any host write' {
        $candidate = New-SkillEvolutionCandidate $script:evolutionRoot
        $target = Join-Path $script:fixtureRepo 'overrides\custom\demo-skill'; Copy-SkillEvolutionPackage $candidate $target @('SKILL.md')
        [IO.File]::WriteAllText((Join-Path $script:fixtureRepo '.gitignore'), "reports/`n", [Text.UTF8Encoding]::new($false))
        & git -C $script:fixtureRepo init -q
        & git -C $script:fixtureRepo config user.email fixture@example.invalid
        & git -C $script:fixtureRepo config user.name fixture
        & git -C $script:fixtureRepo add .
        & git -C $script:fixtureRepo commit -q -m fixture
        $LASTEXITCODE | Should -Be 0

        $receiptPath = Join-Path $script:evolutionRoot 'project-recheck-receipt.json'
        $decisionPath = Join-Path $script:evolutionRoot 'project-recheck-decision.json'
        $receipt = New-OperationReceipt -OperationId project-recheck -Status applied -StartedAt ([datetimeoffset]::UtcNow.AddMinutes(-1).ToString('o')) -CompletedAt ([datetimeoffset]::UtcNow.ToString('o'))
        $receipt | Add-Member -NotePropertyName lifecycle -NotePropertyValue ([pscustomobject]@{ operation_kind = 'activation'; skill_name = 'demo-skill'; activation_action = 'enable'; projection_state = 'staged_not_projected' })
        Write-SkillEvolutionJsonAtomic $receiptPath $receipt
        Write-SkillEvolutionJsonAtomic $decisionPath ([pscustomobject]@{ decision = 'approve' })

        $script:projectionAuthorizationChecks = 0
        Mock Test-SkillEvolutionProjectionAuthorization {
            $script:projectionAuthorizationChecks++
            if ($script:projectionAuthorizationChecks -eq 1) { return [pscustomobject]@{ pass = $true; findings = @() } }
            return [pscustomobject]@{ pass = $false; findings = @([pscustomobject]@{ code = 'projection_review_expired' }) }
        }
        Mock Invoke-SkillEvolutionFullGateForProjection { return [pscustomobject]@{ status = 'passed' } }

        { Invoke-SkillEvolutionCommand @('project', '--receipt', $receiptPath, '--decision', $decisionPath, '--token', 'PROJECT_SKILL_TO_HOST', '--out', (Join-Path $script:evolutionRoot 'projection.json'), '--json') } | Should -Throw
        $script:projectionAuthorizationChecks | Should -Be 2
        $script:skillEvolutionBuildCalls | Should -Be 0
    }

    It 'automatically promotes, cold-builds, and returns the next activation question after approval' {
        $candidate = New-SkillEvolutionCandidate $script:evolutionRoot
        $evaluation = Invoke-SkillEvolutionEvaluate -CandidateDirectory $candidate -Corpus (New-SkillEvolutionCorpus) -CaseResults (New-SkillEvolutionCaseResults) -Execute -RepoRoot $script:fixtureRepo
        $evaluationPath = Join-Path $script:evolutionRoot 'command-evaluation.json'; Write-SkillEvolutionJsonAtomic $evaluationPath $evaluation
        $requestPath = Join-Path $script:evolutionRoot 'command-promotion-request.json'
        $request = New-SkillEvolutionPromotionReviewRequest -CandidateDirectory $candidate -Evaluation $evaluation -EvaluationPath $evaluationPath -OutPath $requestPath -RepoRoot $script:fixtureRepo
        $outRoot = Join-Path $script:evolutionRoot 'command-approve'
        $run = Invoke-SkillEvolutionCommand @('decide', '--request', $requestPath, '--decision', 'approve', '--reviewer', 'user', '--token', 'PROMOTE_SKILL_CANDIDATE', '--out', $outRoot, '--json')
        $run.exit_code | Should -Be 0
        $run.envelope.data.status | Should -Be 'authorization_required'
        $run.envelope.data.interaction.kind | Should -Be 'question'
        $run.envelope.data.truth_boundary | Should -Be 'promoted_cold_catalog_not_projected'
        $script:skillEvolutionBuildCalls | Should -Be 1
        Test-Path -LiteralPath (Join-Path $script:fixtureRepo 'overrides\custom\demo-skill\SKILL.md') | Should -BeTrue
        @((Get-Content -LiteralPath (Join-Path $script:fixtureRepo 'skills.json') -Raw | ConvertFrom-Json).skill_projection.managed_link_includes) | Should -Not -Contain 'demo-skill'
    }
}
