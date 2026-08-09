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

function New-AgentTestVerificationReceipt([string]$TaskId) {
    return [pscustomobject]@{
        schema_version = 1
        receipt_id = 'verify-' + $TaskId
        verified_at = '2026-08-05T04:40:00Z'
        verifier = 'host_ai'
        evidence_sha256 = ('b' * 64)
        commands = @('pwsh -NoProfile -File tests/run.ps1')
    }
}

Describe 'Agent workflow advisory contracts' {
    It 'constructs and validates a plain-object TaskGraph' {
        Assert-AgentWorkflowFunction 'New-AgentTaskGraph'
        Assert-AgentWorkflowFunction 'Test-AgentTaskGraphContract'
        $fixture = Get-AgentWorkflowFixture 'valid-request.json'
        $graph = New-AgentTaskGraph -GraphId $fixture.task_graph.graph_id -BaseRevision $fixture.task_graph.base_revision -IntegrationOwner $fixture.task_graph.integration_owner -Tasks $fixture.task_graph.tasks

        $result = Test-AgentTaskGraphContract $graph

        $result.pass | Should Be $true
        $graph.schema_version | Should Be 2
        (@($graph.tasks.task_id) -join ',') | Should Be 'discover,implement,document,integrate'
    }

    It 'accepts a direct fix without native or complexity admission' {
        $graph = (Get-AgentWorkflowFixture 'valid-request.json').task_graph | ConvertTo-Json -Depth 50 | ConvertFrom-Json
        $task = $graph.tasks[1]
        $task.admission_scope = 'direct_fix'
        $task.PSObject.Properties.Remove('native_baseline')
        $task.PSObject.Properties.Remove('complexity_admission')

        (Test-AgentTaskGraphContract $graph).pass | Should Be $true
    }

    It 'requires user-facing admission fields on the v2 standard path' {
        $graph = (Get-AgentWorkflowFixture 'valid-request.json').task_graph | ConvertTo-Json -Depth 50 | ConvertFrom-Json
        $graph.tasks[1].PSObject.Properties.Remove('user_outcome')

        $result = Test-AgentTaskGraphContract $graph

        @($result.findings | Where-Object code -eq 'user_outcome_required').Count | Should Be 1
    }

    It 'requires native evidence for capability governance and long-lived surfaces' {
        $graph = (Get-AgentWorkflowFixture 'valid-request.json').task_graph | ConvertTo-Json -Depth 50 | ConvertFrom-Json
        $graph.tasks[1].admission_scope = 'ai_capability'

        $capability = Test-AgentTaskGraphContract $graph

        @($capability.findings | Where-Object code -eq 'native_baseline_required').Count | Should Be 1

        $graph.tasks[1].admission_scope = 'long_lived_surface'
        $graph.tasks[1] | Add-Member -Force -NotePropertyName native_baseline -NotePropertyValue ([pscustomobject]@{
            equivalent = 'none'
            observed_gap = 'The host does not expose the required deterministic contract.'
            evidence = @('official help and repository contract evidence')
        })

        $longLived = Test-AgentTaskGraphContract $graph

        @($longLived.findings | Where-Object code -eq 'complexity_admission_required').Count | Should Be 1
    }

    It 'accepts a long-lived surface only with bounded complexity and retirement evidence' {
        $graph = (Get-AgentWorkflowFixture 'valid-request.json').task_graph | ConvertTo-Json -Depth 50 | ConvertFrom-Json
        $graph.tasks[1].admission_scope = 'long_lived_surface'
        $graph.tasks[1] | Add-Member -Force -NotePropertyName native_baseline -NotePropertyValue ([pscustomobject]@{
            equivalent = 'none'
            observed_gap = 'The host does not expose the required deterministic contract.'
            evidence = @('official help and repository contract evidence')
        })
        $graph.tasks[1] | Add-Member -Force -NotePropertyName complexity_admission -NotePropertyValue ([pscustomobject]@{
            kind = 'two_real_repetitions'
            evidence_refs = @('evidence://repeat-a', 'evidence://repeat-b')
            real_consumers = @('consumer-a')
            maintenance_cost = 'One focused validator and its contract tests.'
            retirement_trigger = 'The host exposes an equivalent stable contract.'
        })

        (Test-AgentTaskGraphContract $graph).pass | Should Be $true
    }

    It 'rejects stage inversion and missing main-chain ancestry' {
        $graph = (Get-AgentWorkflowFixture 'valid-request.json').task_graph | ConvertTo-Json -Depth 50 | ConvertFrom-Json
        $graph.tasks[0].delivery_stage = 'release'
        $graph.tasks[1].delivery_stage = 'main_chain'

        $result = Test-AgentTaskGraphContract $graph

        @($result.findings | Where-Object code -eq 'delivery_stage_dependency_invalid').Count | Should BeGreaterThan 0
        @($result.findings | Where-Object code -eq 'delivery_stage_ancestor_missing').Count | Should BeGreaterThan 0
    }

    It 'preserves explicit TaskGraph v1 compatibility validation' {
        $legacy = (Get-AgentWorkflowFixture 'valid-request.json').task_graph | ConvertTo-Json -Depth 50 | ConvertFrom-Json
        $legacy.schema_version = 1
        foreach ($task in @($legacy.tasks)) {
            foreach ($field in @('delivery_stage', 'admission_scope', 'user_outcome', 'entrypoint', 'main_chain_checkpoint', 'reuse_decision', 'native_baseline', 'complexity_admission')) {
                $task.PSObject.Properties.Remove($field)
            }
        }

        (Test-AgentTaskGraphContract $legacy).pass | Should Be $true
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

        $parallel = Test-AgentParallelAdmission -TaskGraph $fixture.task_graph -TaskIds @('implement', 'document') -CompletedTaskIds @('discover') -CompletedTaskReceipts $fixture.completion_receipts -EvaluationTime $fixture.now
        $integrationReceipts = @(
            [pscustomobject]@{ task_id = 'implement'; base_revision = '84cb53aa'; status = 'verified'; verification_receipt = (New-AgentTestVerificationReceipt 'implement') },
            [pscustomobject]@{ task_id = 'document'; base_revision = '84cb53aa'; status = 'verified'; verification_receipt = (New-AgentTestVerificationReceipt 'document') }
        )
        $integration = Test-AgentParallelAdmission -TaskGraph $fixture.task_graph -TaskIds @('integrate') -CompletedTaskIds @('implement', 'document') -CompletedTaskReceipts $integrationReceipts -EvaluationTime $fixture.now

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

    It 'requires verified completion receipts and rejects selected or unknown completed tasks' {
        $fixture = Get-AgentWorkflowFixture 'valid-request.json'
        $missingReceipt = Test-AgentParallelAdmission -TaskGraph $fixture.task_graph -TaskIds @('implement', 'document') -CompletedTaskIds @('discover')
        @($missingReceipt.findings | Where-Object code -eq 'completion_receipt_missing').Count | Should Be 1

        $unknownReceipt = @([pscustomobject]@{ task_id = 'ghost'; base_revision = '84cb53aa'; status = 'verified'; verification_receipt = (New-AgentTestVerificationReceipt 'ghost') })
        $unknown = Test-AgentParallelAdmission -TaskGraph $fixture.task_graph -TaskIds @('implement', 'document') -CompletedTaskIds @('ghost') -CompletedTaskReceipts $unknownReceipt -EvaluationTime $fixture.now
        @($unknown.findings | Where-Object code -eq 'completed_task_unknown').Count | Should Be 1

        $unclaimedReceipts = @($fixture.completion_receipts) + [pscustomobject]@{ task_id = 'document'; base_revision = '84cb53aa'; status = 'verified'; verification_receipt = (New-AgentTestVerificationReceipt 'document') }
        $unclaimed = Test-AgentParallelAdmission -TaskGraph $fixture.task_graph -TaskIds @('implement', 'document') -CompletedTaskIds @('discover') -CompletedTaskReceipts $unclaimedReceipts -EvaluationTime $fixture.now
        @($unclaimed.findings | Where-Object code -eq 'completion_receipt_unclaimed').Count | Should Be 1

        $overlapGraph = $fixture.task_graph | ConvertTo-Json -Depth 50 | ConvertFrom-Json
        $overlapGraph.tasks[0].parallelizable = $true
        $overlapGraph.tasks[0].exact_write_set = @('src/discovery.ps1')
        $overlap = Test-AgentParallelAdmission -TaskGraph $overlapGraph -TaskIds @('discover', 'implement') -CompletedTaskIds @('discover') -CompletedTaskReceipts $fixture.completion_receipts -EvaluationTime $fixture.now
        @($overlap.findings | Where-Object code -eq 'selected_task_already_completed').Count | Should Be 1

        $arbitraryReceipt = @([pscustomobject]@{ task_id = 'discover'; base_revision = '84cb53aa'; status = 'verified'; verification_receipt = 'arbitrary-string' })
        $arbitrary = Test-AgentParallelAdmission -TaskGraph $fixture.task_graph -TaskIds @('implement', 'document') -CompletedTaskIds @('discover') -CompletedTaskReceipts $arbitraryReceipt -EvaluationTime $fixture.now
        @($arbitrary.findings | Where-Object code -eq 'completion_receipt_evidence_invalid').Count | Should Be 1

        $unclosedReceipt = @([pscustomobject]@{ task_id = 'implement'; base_revision = '84cb53aa'; status = 'verified'; verification_receipt = (New-AgentTestVerificationReceipt 'implement') })
        $unclosed = Test-AgentParallelAdmission -TaskGraph $fixture.task_graph -TaskIds @() -CompletedTaskIds @('implement') -CompletedTaskReceipts $unclosedReceipt -EvaluationTime $fixture.now
        @($unclosed.findings | Where-Object code -eq 'completed_dependency_not_closed').Count | Should Be 1
    }

    It 'canonicalizes repository paths and blocks parent child and high-risk parallel work' {
        $fixture = Get-AgentWorkflowFixture 'valid-request.json'
        $graph = $fixture.task_graph | ConvertTo-Json -Depth 50 | ConvertFrom-Json
        $graph.tasks[1].exact_write_set = @('src/Feature')
        $graph.tasks[2].exact_write_set = @('src/Feature/a.ps1')
        $graph.tasks[1].coordination_keys = @()
        $graph.tasks[2].coordination_keys = @()

        $conflict = Test-AgentParallelAdmission -TaskGraph $graph -TaskIds @('implement', 'document') -CompletedTaskIds @('discover') -CompletedTaskReceipts $fixture.completion_receipts -EvaluationTime $fixture.now
        @($conflict.findings | Where-Object code -eq 'write_set_conflict').Count | Should Be 1

        $graph.tasks[2].exact_write_set = @('docs/feature.md')
        $graph.tasks[1].risk = 'high'
        $risk = Test-AgentParallelAdmission -TaskGraph $graph -TaskIds @('implement', 'document') -CompletedTaskIds @('discover') -CompletedTaskReceipts $fixture.completion_receipts -EvaluationTime $fixture.now
        @($risk.findings | Where-Object code -eq 'high_risk_parallel_forbidden').Count | Should Be 1

        $graph.tasks[1].risk = 'medium'
        $graph.tasks[1].exact_write_set = @('src/./Feature.ps1')
        @((Test-AgentTaskGraphContract $graph).findings | Where-Object code -eq 'write_set_path_invalid').Count | Should Be 1

        $graph.tasks[1].exact_write_set = @('src/Feature.ps1:alternate-stream')
        @((Test-AgentTaskGraphContract $graph).findings | Where-Object code -eq 'write_set_path_invalid').Count | Should Be 1

        foreach ($invalidPath in @('src/CON/file.ps1', 'src/file. ', 'src/aux.txt')) {
            $graph.tasks[1].exact_write_set = @($invalidPath)
            @((Test-AgentTaskGraphContract $graph).findings | Where-Object code -eq 'write_set_path_invalid').Count | Should Be 1
        }

        $graph.tasks[1].exact_write_set = @('src/café.ps1')
        $graph.tasks[2].exact_write_set = @('src/cafe' + [char]0x301 + '.ps1')
        $graph.tasks[1].coordination_keys = @()
        $graph.tasks[2].coordination_keys = @()
        $unicodeCollision = Test-AgentParallelAdmission -TaskGraph $graph -TaskIds @('implement', 'document') -CompletedTaskIds @('discover') -CompletedTaskReceipts $fixture.completion_receipts -EvaluationTime $fixture.now
        @($unicodeCollision.findings | Where-Object code -eq 'write_set_conflict').Count | Should Be 1
    }

    It 'uses one executable group per wave and makes serial tasks an explicit barrier' {
        $fixture = Get-AgentWorkflowFixture 'valid-request.json'
        $graph = $fixture.task_graph | ConvertTo-Json -Depth 50 | ConvertFrom-Json
        $graph.tasks[0].exact_write_set = @('shared/file.ps1')
        $graph.tasks[1].depends_on = @()
        $graph.tasks[1].exact_write_set = @('shared/file.ps1')
        $graph.tasks[1].coordination_keys = @()
        $graph.tasks[2].depends_on = @()
        $graph.tasks[2].coordination_keys = @()

        $plan = New-AgentExecutionPlan -TaskGraph $graph
        @($plan.waves[0].groups).Count | Should Be 1
        $plan.waves[0].groups[0].mode | Should Be 'sequential'
        (@($plan.waves[0].groups[0].task_ids) -join ',') | Should Be 'discover'
    }

    It 'validates an immutable fresh Radar snapshot and rejects stale advisory data' {
        Assert-AgentWorkflowFunction 'New-RadarSnapshot'
        Assert-AgentWorkflowFunction 'Test-RadarSnapshotContract'
        $valid = Get-AgentWorkflowFixture 'valid-request.json'
        $stale = Get-AgentWorkflowFixture 'invalid-request.json'
        $snapshot = New-RadarSnapshot -SnapshotId $valid.radar_snapshot.snapshot_id -Source $valid.radar_snapshot.source -CapturedAt $valid.radar_snapshot.captured_at -SourceUpdatedAt $valid.radar_snapshot.source_updated_at -ExpiresAt $valid.radar_snapshot.expires_at -RawHash $valid.radar_snapshot.raw_hash -Entries $valid.radar_snapshot.entries

        (Test-RadarSnapshotContract -Snapshot $snapshot -Now $valid.now).pass | Should Be $true
        $staleResult = Test-RadarSnapshotContract -Snapshot $stale.radar_snapshot -Now $stale.now
        $staleResult.pass | Should Be $false
        @($staleResult.findings | Where-Object code -eq 'radar_snapshot_stale').Count | Should Be 1
    }

    It 'fails closed for stale source data empty observations and decision fields in Radar' {
        $snapshot = [pscustomobject]@{
            schema_version = 2; snapshot_id = 'hostile-radar'; source = 'https://codexradar.com/data/intelligence-efficiency.json'
            captured_at = '2026-08-05T00:00:00Z'; source_updated_at = '2026-07-01T00:00:00Z'; expires_at = '2026-08-10T00:00:00Z'
            raw_hash = ('a' * 64); entries = @(); policy_overrides = @([pscustomobject]@{ model_family = 'gpt-5.6-terra' })
        }
        $result = Test-RadarSnapshotContract -Snapshot $snapshot -Now '2026-08-06T00:00:00Z'
        $result.pass | Should Be $false
        foreach ($code in @('radar_source_stale', 'radar_entries_empty', 'radar_decision_field_forbidden')) {
            @($result.findings | Where-Object code -eq $code).Count | Should Be 1
        }
    }

    It 'accepts only the trusted Codex Radar source and the three policy pairs' {
        $fixture = Get-AgentWorkflowFixture 'valid-request.json'
        $hostileSource = $fixture.radar_snapshot | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $hostileSource.source = 'https://example.invalid/codex-radar.json'
        @((Test-RadarSnapshotContract -Snapshot $hostileSource -Now $fixture.now).findings | Where-Object code -eq 'radar_source_untrusted').Count | Should Be 1

        $unknownPair = $fixture.radar_snapshot | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $unknownPair.entries[0].model_family = 'gpt-5.6-terra'
        $unknownPair.entries[0].reasoning_effort = 'high'
        @((Test-RadarSnapshotContract -Snapshot $unknownPair -Now $fixture.now).findings | Where-Object code -eq 'radar_pair_not_allowlisted').Count | Should Be 1

        $duplicatePair = $fixture.radar_snapshot | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $duplicatePair.entries[1].model_family = $duplicatePair.entries[0].model_family
        $duplicatePair.entries[1].reasoning_effort = $duplicatePair.entries[0].reasoning_effort
        @((Test-RadarSnapshotContract -Snapshot $duplicatePair -Now $fixture.now).findings | Where-Object code -eq 'radar_pair_duplicate').Count | Should Be 1
    }

    It 'rejects non-finite or fractional Radar metrics and requires canonical labels' {
        $fixture = Get-AgentWorkflowFixture 'valid-request.json'

        $nonFinite = $fixture.radar_snapshot | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $nonFinite.entries[0].score = [double]::NaN
        @((Test-RadarSnapshotContract -Snapshot $nonFinite -Now $fixture.now).findings | Where-Object code -eq 'radar_metric_invalid').Count | Should Be 1

        $fractionalSample = $fixture.radar_snapshot | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $fractionalSample.entries[0].sample_count = 0.5
        @((Test-RadarSnapshotContract -Snapshot $fractionalSample -Now $fixture.now).findings | Where-Object code -eq 'radar_sample_count_invalid').Count | Should Be 1

        $mislabeled = $fixture.radar_snapshot | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $mislabeled.entries[0].model_label = 'Luna max'
        @((Test-RadarSnapshotContract -Snapshot $mislabeled -Now $fixture.now).findings | Where-Object code -eq 'radar_model_label_mismatch').Count | Should Be 1
    }

    It 'rejects forbidden fields in dictionaries and requires strict RFC3339 Radar times' {
        $fixture = Get-AgentWorkflowFixture 'valid-request.json'
        $dictionary = $fixture.radar_snapshot | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
        $dictionary['policy_overrides'] = @(@{ requested_tier = 'sol_xhigh' })
        @((Test-RadarSnapshotContract -Snapshot $dictionary -Now $fixture.now).findings | Where-Object code -eq 'radar_decision_field_forbidden').Count | Should Be 1

        $orderedDictionary = [System.Collections.Specialized.OrderedDictionary]::new()
        foreach ($property in $fixture.radar_snapshot.PSObject.Properties) { $orderedDictionary.Add($property.Name, $property.Value) }
        $orderedDictionary.Add('policy_overrides', @([ordered]@{ requested_tier = 'sol_xhigh' }))
        @((Test-RadarSnapshotContract -Snapshot $orderedDictionary -Now $fixture.now).findings | Where-Object code -eq 'radar_decision_field_forbidden').Count | Should Be 1

        $cultureDate = $fixture.radar_snapshot | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $cultureDate.captured_at = '08/05/2026'
        @((Test-RadarSnapshotContract -Snapshot $cultureDate -Now $fixture.now).findings | Where-Object code -eq 'radar_captured_at_invalid').Count | Should Be 1

        @((Test-RadarSnapshotContract -Snapshot $fixture.radar_snapshot -Now '08/05/2026').findings | Where-Object code -eq 'evaluation_time_invalid').Count | Should Be 1
    }

    It 'keeps model routing host-owned and gives the user override priority across three soft anchors' {
        Assert-AgentWorkflowFunction 'New-ModelPolicyProposal'
        $fixture = Get-AgentWorkflowFixture 'valid-request.json'
        $proposal = $fixture.model_proposals[0]

        $result = New-ModelPolicyProposal -TaskId $proposal.task_id -RequestedTier $proposal.requested_tier -Rationale $proposal.rationale -RadarSnapshot $fixture.radar_snapshot -HostSurface $proposal.host_surface -HostAvailablePairs $proposal.host_available_pairs -LocalOutcomes $proposal.local_outcomes -Now $fixture.now -UserOverrideTier $proposal.user_override_tier

        $result.decision_owner | Should Be 'host_ai'
        $result.selected_tier | Should Be 'sol_low'
        $result.model_family | Should Be 'gpt-5.6-sol'
        $result.reasoning_effort | Should Be 'low'
        $result.user_override | Should Be $true
        $result.evidence_priority | Should Be 'user_override_then_local_outcomes_then_host_availability_then_host_default'
        $result.provider_calls | Should Be 0
        $result.native_mutations | Should Be 0
    }

    It 'uses Sol low as the routine tier and keeps Radar outside the active decision path' {
        Assert-AgentWorkflowFunction 'Get-AgentModelTierAnchor'
        Assert-AgentWorkflowFunction 'New-ModelPolicyProposal'
        $fixture = Get-AgentWorkflowFixture 'invalid-request.json'

        $anchor = Get-AgentModelTierAnchor 'sol_low'
        $anchor.model_family | Should Be 'gpt-5.6-sol'
        $anchor.reasoning_effort | Should Be 'low'
        (Get-AgentModelTierAnchor 'luna_max') | Should BeNullOrEmpty

        $result = New-ModelPolicyProposal -TaskId 'routine' -RequestedTier 'sol_low' -Rationale 'Bounded mechanical task.' -RadarSnapshot $fixture.radar_snapshot -HostSurface 'collaboration_spawn' -HostAvailablePairs @('gpt-5.6-sol|low') -Now $fixture.now

        $result.selected_tier | Should Be 'sol_low'
        $result.model_family | Should Be 'gpt-5.6-sol'
        $result.reasoning_effort | Should Be 'low'
        $result.evidence_priority | Should Be 'user_override_then_local_outcomes_then_host_availability_then_host_default'
        $result.PSObject.Properties.Name | Should Not Contain 'radar_snapshot_id'
        $result.PSObject.Properties.Name | Should Not Contain 'radar_entry'
        $result.evidence_sources.PSObject.Properties.Name | Should Not Contain 'radar'

        $request = Get-AgentWorkflowFixture 'valid-request.json'
        $request.radar_snapshot.entries = @()
        (Test-AgentWorkflowRequest $request).pass | Should Be $true
    }

    It 'escalates a capacity failure from Sol low to Sol medium' {
        $packet = New-AgentFailurePacket -IssueId 'issue-low-capacity' -TaskId 'routine' -BaseRevision '84cb53aa' -FailureKind capacity -AttemptCount 2 -EscalationCount 0 -AttemptedTier sol_low -AttemptedModel 'gpt-5.6-sol' -AttemptedEffort low -Commands @('focused tests') -Failures @('reasoning incomplete') -VerifiedFacts @('inputs present') -ExactWriteSet @('src/Domain/Feature.ps1') -CorrectionSummary 'Reduced the write set.' -NextRecommendation 'replan and escalate'

        $decision = Get-AgentEscalationDecision $packet
        $decision.action | Should Be 'replan_and_escalate'
        $decision.next_tier | Should Be 'sol_medium'
    }

    It 'rejects the removed Terra high tier instead of silently routing it' {
        Assert-AgentWorkflowFunction 'Get-AgentModelTierAnchor'
        Assert-AgentWorkflowFunction 'New-ModelPolicyProposal'
        $fixture = Get-AgentWorkflowFixture 'valid-request.json'

        (Get-AgentModelTierAnchor 'terra_high') | Should BeNullOrEmpty
        $result = New-ModelPolicyProposal -TaskId 'legacy-terra' -RequestedTier 'terra_high' -Rationale 'Legacy request.' -RadarSnapshot $fixture.radar_snapshot -HostSurface 'collaboration_spawn' -HostAvailablePairs @('gpt-5.6-sol|low', 'gpt-5.6-sol|medium', 'gpt-5.6-sol|xhigh') -Now $fixture.now

        $result.selected_tier | Should Be 'host_default'
        $result.fallback_reason | Should Match 'tier_unknown'
    }

    It 'ignores stale Radar and falls back only when the host pair is unavailable' {
        Assert-AgentWorkflowFunction 'New-ModelPolicyProposal'
        $fixture = Get-AgentWorkflowFixture 'invalid-request.json'

        $result = New-ModelPolicyProposal -TaskId 'alpha' -RequestedTier 'sol_xhigh' -Rationale 'Host proposal.' -RadarSnapshot $fixture.radar_snapshot -HostSurface 'collaboration_spawn' -HostAvailablePairs @('gpt-5.6-sol|low') -Now $fixture.now

        $result.selected_tier | Should Be 'host_default'
        $result.fallback_reason | Should Be 'host_pair_unavailable'
        $result.advisory_only | Should Be $true
    }

    It 'does not let malformed local outcomes hide missing host availability' {
        $fixture = Get-AgentWorkflowFixture 'valid-request.json'
        $result = New-ModelPolicyProposal -TaskId 'implement' -RequestedTier 'sol_low' -Rationale 'Host proposal.' -RadarSnapshot $fixture.radar_snapshot -HostSurface 'collaboration_spawn' -HostAvailablePairs @() -LocalOutcomes @([pscustomobject]@{}) -Now $fixture.now
        $result.selected_tier | Should Be 'host_default'
        $result.fallback_reason | Should Match 'local_outcome_invalid|host_pair_availability_unknown'
        $result.selection_semantics | Should Be 'host_proposal_validation_only'

        $validOutcome = $fixture.model_proposals[0].local_outcomes[0]
        $invalidTime = New-ModelPolicyProposal -TaskId 'implement' -RequestedTier 'sol_low' -Rationale 'Host proposal.' -RadarSnapshot $fixture.radar_snapshot -HostSurface 'collaboration_spawn' -HostAvailablePairs @() -LocalOutcomes @($validOutcome) -Now 'not-a-time'
        $invalidTime.selected_tier | Should Be 'host_default'
        $invalidTime.fallback_reason | Should Match 'local_outcome_invalid'
        @($invalidTime.evidence_sources.local.rejected_findings | Where-Object code -eq 'local_outcome_evaluation_time_invalid').Count | Should Be 1
    }

    It 'rejects non-finite local outcome metrics and non-RFC3339 sample times' {
        $fixture = Get-AgentWorkflowFixture 'valid-request.json'
        $outcome = $fixture.model_proposals[0].local_outcomes[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $outcome.actual_cost = [double]::NaN
        $nonFinite = Test-AgentLocalOutcomeContract -Outcome $outcome -Anchor (Get-AgentModelTierAnchor 'sol_low') -Now $fixture.now
        @($nonFinite.findings | Where-Object code -eq 'local_outcome_metric_invalid').Count | Should Be 1

        $outcome.actual_cost = 0.38
        $outcome.sampled_at = '08/04/2026'
        $cultureDate = Test-AgentLocalOutcomeContract -Outcome $outcome -Anchor (Get-AgentModelTierAnchor 'sol_low') -Now $fixture.now
        @($cultureDate.findings | Where-Object code -eq 'local_outcome_sampled_at_invalid').Count | Should Be 1
    }

    It 'requires non-empty commands strict non-future time and outer task revision binding for completion evidence' {
        $fixture = Get-AgentWorkflowFixture 'valid-request.json'

        $emptyCommandEvidence = New-AgentTestVerificationReceipt 'discover'
        $emptyCommandEvidence.commands = @('  ')
        (Test-AgentCompletionVerificationReceipt -Evidence $emptyCommandEvidence -EvaluationTime $fixture.now) | Should Be $false

        $nonStringCommandEvidence = New-AgentTestVerificationReceipt 'discover'
        $nonStringCommandEvidence.commands = @(123)
        (Test-AgentCompletionVerificationReceipt -Evidence $nonStringCommandEvidence -EvaluationTime $fixture.now) | Should Be $false

        $cultureDateEvidence = New-AgentTestVerificationReceipt 'discover'
        $cultureDateEvidence.verified_at = '08/05/2026'
        (Test-AgentCompletionVerificationReceipt -Evidence $cultureDateEvidence -EvaluationTime $fixture.now) | Should Be $false

        $futureEvidence = New-AgentTestVerificationReceipt 'discover'
        $futureEvidence.verified_at = '2099-01-01T00:00:00Z'
        (Test-AgentCompletionVerificationReceipt -Evidence $futureEvidence -EvaluationTime $fixture.now) | Should Be $false

        $validEvidence = New-AgentTestVerificationReceipt 'discover'
        (Test-AgentCompletionVerificationReceipt -Evidence $validEvidence -EvaluationTime $fixture.now) | Should Be $true
        (Test-AgentCompletionVerificationReceipt -Evidence $validEvidence) | Should Be $false

        $wrongRevision = @([pscustomobject]@{ task_id = 'discover'; base_revision = 'other-revision'; status = 'verified'; verification_receipt = (New-AgentTestVerificationReceipt 'discover') })
        $admission = Test-AgentParallelAdmission -TaskGraph $fixture.task_graph -TaskIds @('implement', 'document') -CompletedTaskIds @('discover') -CompletedTaskReceipts $wrongRevision -EvaluationTime $fixture.now
        @($admission.findings | Where-Object code -eq 'completion_receipt_revision_mismatch').Count | Should Be 1

        $missingEvaluation = Test-AgentParallelAdmission -TaskGraph $fixture.task_graph -TaskIds @('implement', 'document') -CompletedTaskIds @('discover') -CompletedTaskReceipts $fixture.completion_receipts
        @($missingEvaluation.findings | Where-Object code -eq 'completion_evaluation_time_invalid').Count | Should Be 1
    }

    It 'does not let successful local outcomes promote unknown spawn availability' {
        $fixture = Get-AgentWorkflowFixture 'valid-request.json'
        $validOutcome = $fixture.model_proposals[0].local_outcomes[0]

        $result = New-ModelPolicyProposal -TaskId 'implement' -RequestedTier 'sol_low' -Rationale 'Host proposal.' -RadarSnapshot $fixture.radar_snapshot -HostSurface 'collaboration_spawn' -HostAvailablePairs @() -LocalOutcomes @($validOutcome) -Now $fixture.now

        $result.selected_tier | Should Be 'host_default'
        $result.fallback_reason | Should Match 'host_pair_availability_unknown'
        $result.evidence_sources.host_availability.surface | Should Be 'collaboration_spawn'
        $result.evidence_sources.host_availability.state | Should Be 'unknown'
        $result.evidence_sources.PSObject.Properties.Name | Should Not Contain 'radar'
    }

    It 'requires availability evidence to name the host surface' {
        $fixture = Get-AgentWorkflowFixture 'valid-request.json'

        $result = New-ModelPolicyProposal -TaskId 'implement' -RequestedTier 'sol_low' -Rationale 'Host proposal.' -RadarSnapshot $fixture.radar_snapshot -HostAvailablePairs @('gpt-5.6-sol|low') -Now $fixture.now

        $result.selected_tier | Should Be 'host_default'
        $result.fallback_reason | Should Match 'host_surface_unknown'
        $result.evidence_sources.host_availability.state | Should Be 'unknown'
    }

    It 'accepts a serial-only request and validates every model proposal against the TaskGraph' {
        $fixture = Get-AgentWorkflowFixture 'valid-request.json'
        $fixture.requested_parallel_task_ids = @()
        (Test-AgentWorkflowRequest $fixture).pass | Should Be $true

        $fixture.model_proposals += ($fixture.model_proposals[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
        $fixture.model_proposals[0].task_id = 'missing-task'
        $fixture.model_proposals[0].rationale = ''
        $fixture.model_proposals[1].task_id = 'missing-task'
        $invalid = Test-AgentWorkflowRequest $fixture
        foreach ($code in @('model_proposal_task_unknown', 'model_proposal_duplicate', 'model_proposal_rationale_required')) {
            @($invalid.findings | Where-Object code -eq $code).Count | Should BeGreaterThan 0
        }
    }

    It 'requires a FailurePacket before a model tier can change' {
        Assert-AgentWorkflowFunction 'New-AgentFailurePacket'
        Assert-AgentWorkflowFunction 'Test-AgentFailurePacketContract'
        $packet = New-AgentFailurePacket -IssueId 'issue-capacity-1' -TaskId 'implement' -BaseRevision '84cb53aa' -FailureKind capacity -AttemptCount 2 -EscalationCount 0 -AttemptedTier sol_low -AttemptedModel 'gpt-5.6-sol' -AttemptedEffort low -Commands @('focused tests') -Failures @('reasoning incomplete') -VerifiedFacts @('inputs present') -ExactWriteSet @('src/Domain/Feature.ps1') -CorrectionSummary 'Added the missing invariant.' -NextRecommendation 'replan and escalate'

        (Test-AgentFailurePacketContract $packet).pass | Should Be $true
        $packet.issue_id | Should Be 'issue-capacity-1'
        $packet.schema_version | Should Be 1
    }

    It 'chooses corrected retry rescope bounded escalation and supervisor takeover by failure kind' {
        Assert-AgentWorkflowFunction 'Get-AgentEscalationDecision'
        $base = [pscustomobject]@{ schema_version = 1; issue_id = 'issue-1'; task_id = 'task-1'; base_revision = '84cb53aa'; failure_kind = 'capacity'; attempt_count = 1; escalation_count = 0; attempted_tier = 'sol_low'; attempted_model = 'gpt-5.6-sol'; attempted_effort = 'low'; commands = @('test'); failures = @('incomplete'); verified_facts = @('context complete'); unresolved_questions = @(); artifacts = @(); exact_write_set = @('src/a.ps1'); correction_summary = 'Tightened acceptance criteria.'; next_recommendation = 'retry' }

        (Get-AgentEscalationDecision -FailurePacket $base).action | Should Be 'corrected_retry'
        $base.failure_kind = 'context'
        (Get-AgentEscalationDecision -FailurePacket $base).action | Should Be 'rescope_task_graph'
        $base.attempt_count = 2
        (Get-AgentEscalationDecision -FailurePacket $base).action | Should Be 'supervisor_takeover'
        $base.failure_kind = 'tool'
        (Get-AgentEscalationDecision -FailurePacket $base).action | Should Be 'supervisor_takeover'
        $base.failure_kind = 'capacity'
        $lunaEscalation = Get-AgentEscalationDecision -FailurePacket $base
        $lunaEscalation.action | Should Be 'replan_and_escalate'
        $lunaEscalation.next_tier | Should Be 'sol_medium'
        $base.attempted_tier = 'sol_medium'; $base.escalation_count = 1
        (Get-AgentEscalationDecision -FailurePacket $base).next_tier | Should Be 'sol_xhigh'
        $base.attempted_tier = 'terra_high'
        (Get-AgentEscalationDecision -FailurePacket $base).action | Should Be 'supervisor_review'
        $base.failure_kind = 'permission'
        (Get-AgentEscalationDecision -FailurePacket $base).action | Should Be 'fail_closed'
        $base.failure_kind = 'capacity'; $base.attempt_count = 4; $base.escalation_count = 2; $base.attempted_tier = 'sol_xhigh'
        (Get-AgentEscalationDecision -FailurePacket $base).action | Should Be 'supervisor_takeover'
    }

    It 'rejects contradictory escalation counts and uncorrected retries' {
        $packet = New-AgentFailurePacket -IssueId 'issue-bad' -TaskId 'implement' -BaseRevision '84cb53aa' -FailureKind capacity -AttemptCount 1 -EscalationCount 2 -AttemptedTier sol_low -Failures @('incomplete')
        $invalid = Test-AgentFailurePacketContract $packet
        @($invalid.findings | Where-Object code -eq 'escalation_count_inconsistent').Count | Should Be 1
        @($invalid.findings | Where-Object code -eq 'correction_evidence_required').Count | Should Be 1
        (Get-AgentEscalationDecision $packet).action | Should Be 'supervisor_review'

        $corrected = New-AgentFailurePacket -IssueId 'issue-good' -TaskId 'implement' -BaseRevision '84cb53aa' -FailureKind capacity -AttemptCount 1 -EscalationCount 0 -AttemptedTier sol_low -Commands @('focused test') -Failures @('incomplete') -VerifiedFacts @('context complete') -CorrectionSummary 'Corrected the missing context.'
        $decision = Get-AgentEscalationDecision $corrected
        $decision.action | Should Be 'corrected_retry'
        $decision.parallel_allowed | Should Be $false
        $decision.requires_parallel_readmission | Should Be $true

        $secretPacket = New-AgentFailurePacket -IssueId 'issue-secret' -TaskId 'implement' -BaseRevision '84cb53aa' -FailureKind tool -AttemptCount 1 -AttemptedTier sol_low -Failures @('token spaced-secret-value')
        @((Test-AgentFailurePacketContract $secretPacket).findings | Where-Object code -eq 'sensitive_value_present').Count | Should Be 1
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

    It 'rejects a repository-local input path that traverses an outbound junction' {
        $oldRoot = $script:Root
        $workspace = Join-Path $TestDrive 'agent-input-root'
        $outside = Join-Path $TestDrive 'agent-input-outside'
        $junction = Join-Path $workspace 'linked'
        New-Item -ItemType Directory -Path $workspace, $outside -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repoRoot 'tests\fixtures\agent-workflow\valid-request.json') -Destination (Join-Path $outside 'request.json')
        New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
        try {
            $script:Root = $workspace
            { Read-AgentWorkflowRequest (Join-Path $junction 'request.json') } | Should Throw
        }
        finally {
            $script:Root = $oldRoot
        }
    }

    It 'keeps the domain and application contracts free of IO clock environment and terminal effects' {
        Assert-AgentWorkflowFunction 'Test-AgentTaskGraphContract'
        $text = @('src\Domain\AgentWorkflow.ps1', 'src\Application\ModelAndAgentPolicy.ps1') | ForEach-Object { Get-Content -LiteralPath (Join-Path $repoRoot $_) -Raw }
        ($text -join "`n") | Should Not Match '(?im)^\s*(Get-Content|Set-Content|Add-Content|Remove-Item|Copy-Item|Move-Item|Test-Path|Resolve-Path|Get-Date|Write-Host|Write-Output|Start-Process|Invoke-WebRequest|exit)\b'
        ($text -join "`n") | Should Not Match '(?i)\$env:'
    }
}
