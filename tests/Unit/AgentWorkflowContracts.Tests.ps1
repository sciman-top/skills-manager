$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$script:Root = $repoRoot
. (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')

foreach ($relativePath in @(
        'src\Domain\AgentWorkflow.ps1',
        'src\Application\ModelAndAgentPolicy.ps1',
        'src\Commands\AgentWorkflow.ps1'
    )) {
    $candidate = Join-Path $repoRoot $relativePath
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { . $candidate }
}

function Assert-AgentWorkflowFunction([string]$Name) {
    Get-Command $Name -CommandType Function -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
}

function Get-AgentWorkflowFixture([string]$Name) {
    return Get-Content -LiteralPath (Join-Path $repoRoot ('tests\fixtures\agent-workflow\{0}' -f $Name)) -Raw | ConvertFrom-Json
}

Describe 'Agent workflow advisory contracts' {
    It 'constructs and validates a plain-object TaskGraph' {
        Assert-AgentWorkflowFunction 'New-AgentTaskGraph'
        Assert-AgentWorkflowFunction 'Test-AgentTaskGraphContract'
        $fixture = Get-AgentWorkflowFixture 'valid-request.json'
        $graph = New-AgentTaskGraph -GraphId $fixture.task_graph.graph_id -BaseRevision $fixture.task_graph.base_revision -IntegrationOwner $fixture.task_graph.integration_owner -Tasks $fixture.task_graph.tasks

        $result = Test-AgentTaskGraphContract $graph

        $result.pass | Should Be $true
        $graph.schema_version | Should Be 1
        (@($graph.tasks.task_id) -join ',') | Should Be 'discover,implement,document,integrate'
    }

    It 'fails closed for unknown dependencies cycles and duplicate integration order' {
        Assert-AgentWorkflowFunction 'Test-AgentTaskGraphContract'
        $fixture = Get-AgentWorkflowFixture 'invalid-request.json'
        $fixture.task_graph.tasks[0].depends_on += 'missing-task'

        $result = Test-AgentTaskGraphContract $fixture.task_graph

        $result.pass | Should Be $false
        foreach ($code in @('dependency_unknown', 'task_graph_cycle', 'integration_order_duplicate', 'verification_required')) {
            @($result.findings | Where-Object code -eq $code).Count | Should BeGreaterThan 0
        }
    }

    It 'builds deterministic dependency waves without executing agents' {
        Assert-AgentWorkflowFunction 'New-AgentExecutionPlan'
        $fixture = Get-AgentWorkflowFixture 'valid-request.json'

        $plan = New-AgentExecutionPlan -TaskGraph $fixture.task_graph

        $plan.pass | Should Be $true
        @($plan.waves).Count | Should Be 3
        (@($plan.waves[0].groups[0].task_ids) -join ',') | Should Be 'discover'
        (@($plan.waves[1].groups[0].task_ids) -join ',') | Should Be 'implement,document'
        (@($plan.waves[2].groups[0].task_ids) -join ',') | Should Be 'integrate'
        $plan.provider_calls | Should Be 0
        $plan.native_mutations | Should Be 0
        $plan.writes | Should Be 0
    }

    It 'admits ready disjoint tasks and keeps final integration serial' {
        Assert-AgentWorkflowFunction 'Test-AgentParallelAdmission'
        $fixture = Get-AgentWorkflowFixture 'valid-request.json'

        $parallel = Test-AgentParallelAdmission -TaskGraph $fixture.task_graph -TaskIds @('implement', 'document') -CompletedTaskIds @('discover')
        $integration = Test-AgentParallelAdmission -TaskGraph $fixture.task_graph -TaskIds @('integrate') -CompletedTaskIds @('implement', 'document')

        $parallel.pass | Should Be $true
        $parallel.mode | Should Be 'isolated_parallel'
        $integration.pass | Should Be $false
        @($integration.findings | Where-Object code -eq 'task_not_parallelizable').Count | Should Be 1
    }

    It 'rejects parallel tasks with shared paths seams external writes or missing ownership' {
        Assert-AgentWorkflowFunction 'Test-AgentParallelAdmission'
        $fixture = Get-AgentWorkflowFixture 'invalid-request.json'

        $result = Test-AgentParallelAdmission -TaskGraph $fixture.task_graph -TaskIds @('alpha', 'beta') -CompletedTaskIds @('alpha', 'beta')

        $result.pass | Should Be $false
        foreach ($code in @('write_set_conflict', 'coordination_key_conflict', 'external_state_conflict', 'verification_required')) {
            @($result.findings | Where-Object code -eq $code).Count | Should BeGreaterThan 0
        }
    }

    It 'validates an immutable fresh Radar snapshot and rejects stale advisory data' {
        Assert-AgentWorkflowFunction 'New-RadarSnapshot'
        Assert-AgentWorkflowFunction 'Test-RadarSnapshotContract'
        $valid = Get-AgentWorkflowFixture 'valid-request.json'
        $stale = Get-AgentWorkflowFixture 'invalid-request.json'
        $snapshot = New-RadarSnapshot -SnapshotId $valid.radar_snapshot.snapshot_id -Source $valid.radar_snapshot.source -CapturedAt $valid.radar_snapshot.captured_at -ExpiresAt $valid.radar_snapshot.expires_at -RawHash $valid.radar_snapshot.raw_hash -Entries $valid.radar_snapshot.entries

        (Test-RadarSnapshotContract -Snapshot $snapshot -Now $valid.now).pass | Should Be $true
        $staleResult = Test-RadarSnapshotContract -Snapshot $stale.radar_snapshot -Now $stale.now
        $staleResult.pass | Should Be $false
        @($staleResult.findings | Where-Object code -eq 'radar_snapshot_stale').Count | Should Be 1
    }

    It 'keeps model routing host-owned and gives the user override priority across four soft anchors' {
        Assert-AgentWorkflowFunction 'New-ModelPolicyProposal'
        $fixture = Get-AgentWorkflowFixture 'valid-request.json'
        $proposal = $fixture.model_proposals[0]

        $result = New-ModelPolicyProposal -TaskId $proposal.task_id -RequestedTier $proposal.requested_tier -Rationale $proposal.rationale -RadarSnapshot $fixture.radar_snapshot -HostAvailablePairs $proposal.host_available_pairs -LocalOutcomes $proposal.local_outcomes -Now $fixture.now -UserOverrideTier $proposal.user_override_tier

        $result.decision_owner | Should Be 'host_ai'
        $result.selected_tier | Should Be 'terra_high'
        $result.model_family | Should Be 'gpt-5.6-terra'
        $result.reasoning_effort | Should Be 'high'
        $result.user_override | Should Be $true
        $result.evidence_priority | Should Be 'user_override_then_local_outcomes_then_host_availability_then_radar_then_host_default'
        $result.provider_calls | Should Be 0
        $result.native_mutations | Should Be 0
    }

    It 'falls back to the host default when Radar is stale or a pair is unavailable' {
        Assert-AgentWorkflowFunction 'New-ModelPolicyProposal'
        $fixture = Get-AgentWorkflowFixture 'invalid-request.json'

        $result = New-ModelPolicyProposal -TaskId 'alpha' -RequestedTier 'sol_xhigh' -Rationale 'Host proposal.' -RadarSnapshot $fixture.radar_snapshot -HostAvailablePairs @('gpt-5.6-luna|max') -Now $fixture.now

        $result.selected_tier | Should Be 'host_default'
        $result.fallback_reason | Should Match 'radar_snapshot_stale|host_pair_unavailable'
        $result.advisory_only | Should Be $true
    }

    It 'requires a FailurePacket before a model tier can change' {
        Assert-AgentWorkflowFunction 'New-AgentFailurePacket'
        Assert-AgentWorkflowFunction 'Test-AgentFailurePacketContract'
        $packet = New-AgentFailurePacket -IssueId 'issue-capacity-1' -TaskId 'implement' -BaseRevision '84cb53aa' -FailureKind capacity -AttemptCount 2 -EscalationCount 0 -AttemptedTier luna_max -AttemptedModel 'gpt-5.6-luna' -AttemptedEffort max -Commands @('focused tests') -Failures @('reasoning incomplete') -VerifiedFacts @('inputs present') -ExactWriteSet @('src/Domain/Feature.ps1') -CorrectionSummary 'Added the missing invariant.' -NextRecommendation 'replan and escalate'

        (Test-AgentFailurePacketContract $packet).pass | Should Be $true
        $packet.issue_id | Should Be 'issue-capacity-1'
        $packet.schema_version | Should Be 1
    }

    It 'chooses corrected retry rescope bounded escalation and supervisor takeover by failure kind' {
        Assert-AgentWorkflowFunction 'Get-AgentEscalationDecision'
        $base = [pscustomobject]@{ schema_version = 1; issue_id = 'issue-1'; task_id = 'task-1'; base_revision = '84cb53aa'; failure_kind = 'capacity'; attempt_count = 1; escalation_count = 0; attempted_tier = 'luna_max'; attempted_model = 'gpt-5.6-luna'; attempted_effort = 'max'; commands = @('test'); failures = @('incomplete'); verified_facts = @('context complete'); unresolved_questions = @(); artifacts = @(); exact_write_set = @('src/a.ps1'); correction_summary = 'Tightened acceptance criteria.'; next_recommendation = 'retry' }

        (Get-AgentEscalationDecision -FailurePacket $base).action | Should Be 'corrected_retry'
        $base.failure_kind = 'context'
        (Get-AgentEscalationDecision -FailurePacket $base).action | Should Be 'rescope_task_graph'
        $base.failure_kind = 'capacity'; $base.attempt_count = 2
        $lunaEscalation = Get-AgentEscalationDecision -FailurePacket $base
        $lunaEscalation.action | Should Be 'replan_and_escalate'
        $lunaEscalation.next_tier | Should Be 'terra_high'
        $base.attempted_tier = 'terra_high'; $base.escalation_count = 1
        (Get-AgentEscalationDecision -FailurePacket $base).next_tier | Should Be 'sol_medium'
        $base.attempted_tier = 'sol_medium'
        (Get-AgentEscalationDecision -FailurePacket $base).next_tier | Should Be 'sol_xhigh'
        $base.failure_kind = 'permission'
        (Get-AgentEscalationDecision -FailurePacket $base).action | Should Be 'fail_closed'
        $base.failure_kind = 'capacity'; $base.attempt_count = 4; $base.escalation_count = 2; $base.attempted_tier = 'sol_xhigh'
        (Get-AgentEscalationDecision -FailurePacket $base).action | Should Be 'supervisor_takeover'
    }

    It 'returns zero-write provider-free validate and plan envelopes' {
        Assert-AgentWorkflowFunction 'Invoke-AgentValidateCommand'
        Assert-AgentWorkflowFunction 'Invoke-AgentPlanCommand'
        $fixturePath = Join-Path $repoRoot 'tests\fixtures\agent-workflow\valid-request.json'

        $validation = Invoke-AgentValidateCommand @('--input', $fixturePath, '--json')
        $plan = Invoke-AgentPlanCommand @('--input', $fixturePath, '--json')

        $validation.exit_code | Should Be 0
        $plan.exit_code | Should Be 0
        $validation.envelope.provider_calls | Should Be 0
        $validation.envelope.native_mutations | Should Be 0
        $validation.envelope.writes | Should Be 0
        $plan.envelope.provider_calls | Should Be 0
        $plan.envelope.executor | Should Be 'host_native_runtime'
        Test-Path -LiteralPath ($fixturePath + '.out') | Should Be $false
    }

    It 'keeps the domain and application contracts free of IO clock environment and terminal effects' {
        Assert-AgentWorkflowFunction 'Test-AgentTaskGraphContract'
        $text = @('src\Domain\AgentWorkflow.ps1', 'src\Application\ModelAndAgentPolicy.ps1') | ForEach-Object { Get-Content -LiteralPath (Join-Path $repoRoot $_) -Raw }
        ($text -join "`n") | Should Not Match '(?im)^\s*(Get-Content|Set-Content|Add-Content|Remove-Item|Copy-Item|Move-Item|Test-Path|Resolve-Path|Get-Date|Write-Host|Write-Output|Start-Process|Invoke-WebRequest|exit)\b'
        ($text -join "`n") | Should Not Match '(?i)\$env:'
    }
}
