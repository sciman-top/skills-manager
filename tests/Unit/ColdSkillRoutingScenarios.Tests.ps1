BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    $matrixPath = Join-Path $repoRoot 'tests\fixtures\cold-skill-routing\scenarios.json'
    $matrix = Get-Content -LiteralPath $matrixPath -Raw -Encoding UTF8 | ConvertFrom-Json

    # Enumerations are the deterministic routing oracle (implementation plan §3.2).
    # The matrix is test input only; production runtime code must never read it.
    $script:ExpectedSourceSha256 = 'd03ad0d4f7459f425e3c9fbc6e20350d46dde2e2deb7249ea29b8c332c5d366b'
    $script:VariantEnum = @('explicit', 'implicit', 'implicit_narrow', 'single')
    $script:RouteClassEnum = @('visible_direct', 'cold_candidate', 'discovery_only', 'ordinary_no_skill', 'write_plan_only', 'target_bound', 'artifact_workflow_deferred')
    $script:ColdDiscoveryEnum = @('required', 'forbidden', 'conditional')
    $script:ExecutionContractEnum = @('none', 'one_shot', 'parent_user_input', 'multi_turn_user_decision', 'deferred_to_candidate')
    $script:SideEffectCeilingEnum = @('none', 'read_only', 'planning_only', 'controlled_write', 'artifact_creation', 'live_app_control', 'branch_dependent')
    $script:VerificationModeEnum = @('routing_only', 'routing_only_then_artifact_run', 'platform_gated', 'contract_branching', 'host_judgment', 'event_fields_reporting')
    $script:ForbiddenEventEnum = @(
        'cold_discovery', 'second_discovery', 'candidate_execution', 'native_child', 'writes', 'unadmitted_writes',
        'external_calls', 'dependency_install', 'commit_or_push', 'skill_creation', 'skill_installation',
        'unauthorized_target_operation', 'writes_outside_specified_target', 'multi_turn_summary_substitution',
        'unverified_artifact_delivery', 'fabricated_invocation_evidence', 'fail_open_on_unknown_contract', 'unjustified_discovery'
    )

    function Get-ScenarioGroup([int]$SourceIndex) {
        return @($matrix.scenarios | Where-Object { [int]$_.source_index -eq $SourceIndex })
    }
}

Describe 'Cold skill routing scenario matrix' {
    It 'pins provenance to the approved user-supplied attachment hash' {
        $matrix.schema_version | Should -Be 1
        $matrix.source_provenance.source_kind | Should -Be 'user_supplied_attachment'
        $matrix.source_provenance.source_sha256 | Should -Be $ExpectedSourceSha256
        $matrix.source_provenance.source_description | Should -Not -BeNullOrEmpty
    }

    It 'covers source groups 1..29 exactly once with unique scenario ids' {
        @($matrix.scenarios).Count | Should -BeGreaterThan 29
        $corpus = @($matrix.scenarios | Where-Object { [string]$_.source_kind -ne 'derived_test_case' })
        $derived = @($matrix.scenarios | Where-Object { [string]$_.source_kind -eq 'derived_test_case' })
        @($corpus).Count + @($derived).Count | Should -Be @($matrix.scenarios).Count
        @($derived).Count | Should -BeGreaterThan 0 -Because 'at least the live-derived miss sample must stay tracked'

        $indexes = @($corpus | ForEach-Object { [int]$_.source_index } | Sort-Object -Unique)
        $indexes.Count | Should -Be 29
        $indexes[0] | Should -Be 1
        $indexes[28] | Should -Be 29
        $missing = @(1..29 | Where-Object { $_ -notin $indexes })
        @($missing).Count | Should -Be 0

        foreach ($entry in $derived) {
            [int]$entry.source_index | Should -BeGreaterThan 29 -Because ("derived entry {0} must not masquerade as user corpus" -f $entry.id)
            ([string]$entry.derived_from).Trim().Length | Should -BeGreaterThan 0 -Because ("derived entry {0} must record its origin" -f $entry.id)
        }

        $ids = @($matrix.scenarios | ForEach-Object id)
        @($ids | Sort-Object -Unique).Count | Should -Be $ids.Count
    }

    It 'keeps every entry inside the declared enums with a non-empty verbatim request' {
        foreach ($scenario in @($matrix.scenarios)) {
            $scenario.variant | Should -BeIn $VariantEnum -Because ("scenario {0} variant" -f $scenario.id)
            $scenario.route_class | Should -BeIn $RouteClassEnum -Because ("scenario {0} route_class" -f $scenario.id)
            $scenario.cold_discovery | Should -BeIn $ColdDiscoveryEnum -Because ("scenario {0} cold_discovery" -f $scenario.id)
            $scenario.execution_contract | Should -BeIn $ExecutionContractEnum -Because ("scenario {0} execution_contract" -f $scenario.id)
            $scenario.side_effect_ceiling | Should -BeIn $SideEffectCeilingEnum -Because ("scenario {0} side_effect_ceiling" -f $scenario.id)
            $scenario.verification_mode | Should -BeIn $VerificationModeEnum -Because ("scenario {0} verification_mode" -f $scenario.id)

            ([string]$scenario.request_verbatim).Trim().Length | Should -BeGreaterThan 0 -Because ("scenario {0} verbatim request" -f $scenario.id)

            foreach ($event in @($scenario.forbidden_events)) {
                $event | Should -BeIn $ForbiddenEventEnum -Because ("scenario {0} forbidden event {1}" -f $scenario.id, $event)
            }
            @($scenario.forbidden_events).Count | Should -BeGreaterThan 0 -Because ("scenario {0} must forbid at least one event" -f $scenario.id)
            @($scenario.forbidden_events | Sort-Object -Unique).Count | Should -Be @($scenario.forbidden_events).Count -Because ("scenario {0} forbidden events must be unique" -f $scenario.id)
            @($scenario.allowed_candidate_names | Sort-Object -Unique).Count | Should -Be @($scenario.allowed_candidate_names).Count -Because ("scenario {0} allowed candidates must be unique" -f $scenario.id)
        }
    }

    It 'never hard-pins an implicit cold scenario to a single candidate skill' {
        foreach ($scenario in @($matrix.scenarios)) {
            if ($scenario.variant -notin @('implicit', 'implicit_narrow')) { continue }
            if ($scenario.cold_discovery -eq 'forbidden') { continue }
            @($scenario.allowed_candidate_names).Count | Should -Not -Be 1 -Because ("implicit scenario {0} must not hard-code a unique cold skill hit" -f $scenario.id)
        }
    }

    It 'keeps the explicit grill-with-docs interview as a three-member multi-turn closure' {
        $explicit = Get-ScenarioGroup 1 | Where-Object variant -eq 'explicit'
        @($explicit).Count | Should -Be 1
        $explicit.route_class | Should -Be 'cold_candidate'
        $explicit.cold_discovery | Should -Be 'required'
        $explicit.execution_contract | Should -Be 'multi_turn_user_decision'
        $explicit.expected_native_agent | Should -Be 'design-griller'
        @($explicit.closure_members | Sort-Object) | Should -Be @('domain-modeling', 'grill-with-docs', 'grilling')
        @($explicit.allowed_candidate_names) | Should -Be @('grill-with-docs')

        $implicit = Get-ScenarioGroup 1 | Where-Object variant -eq 'implicit'
        @($implicit).Count | Should -Be 1
        $implicit.cold_discovery | Should -Be 'conditional'
        $implicit.execution_contract | Should -Be 'deferred_to_candidate'
    }

    It 'forbids cold discovery for visible-direct, target-bound, write-plan and deferred-image groups' {
        $forbiddenGroups = @(2, 3, 4, 5, 6, 7, 8, 10, 11, 16, 17, 18, 19, 20, 21, 22, 23, 24)
        foreach ($group in $forbiddenGroups) {
            foreach ($scenario in (Get-ScenarioGroup $group)) {
                $scenario.cold_discovery | Should -Be 'forbidden' -Because ("group {0} scenario {1}" -f $group, $scenario.id)
                $scenario.forbidden_events | Should -Contain 'cold_discovery' -Because ("group {0} scenario {1} must forbid the router event" -f $group, $scenario.id)
            }
        }
    }

    It 'gates target-bound groups 16-18 on a live target object' {
        foreach ($group in @(16, 17, 18)) {
            foreach ($scenario in (Get-ScenarioGroup $group)) {
                $scenario.route_class | Should -Be 'target_bound' -Because ("group {0} scenario {1}" -f $group, $scenario.id)
                $scenario.verification_mode | Should -Be 'platform_gated' -Because ("group {0} scenario {1}" -f $group, $scenario.id)
                @($scenario.required_context).Count | Should -BeGreaterThan 0 -Because ("group {0} scenario {1} must declare the live target object requirements" -f $group, $scenario.id)
                $scenario.forbidden_events | Should -Contain 'unauthorized_target_operation'
            }
        }
    }

    It 'keeps artifact groups 12-15 and 19-20 deferred with split routing/artifact verification' {
        foreach ($group in @(12, 13, 14, 15, 19, 20)) {
            foreach ($scenario in (Get-ScenarioGroup $group)) {
                $scenario.route_class | Should -Be 'artifact_workflow_deferred' -Because ("group {0} scenario {1}" -f $group, $scenario.id)
                $scenario.verification_mode | Should -Be 'routing_only_then_artifact_run' -Because ("group {0} scenario {1}" -f $group, $scenario.id)
            }
        }
    }

    It 'lets group 27 discover candidates but never execute them' {
        $scenario = Get-ScenarioGroup 27
        @($scenario).Count | Should -Be 1
        $scenario[0].route_class | Should -Be 'discovery_only'
        $scenario[0].cold_discovery | Should -Be 'conditional'
        $scenario[0].execution_contract | Should -Be 'none'
        $scenario[0].forbidden_events | Should -Contain 'candidate_execution'
        $scenario[0].forbidden_events | Should -Contain 'writes'
    }

    It 'keeps group 28 as execution-contract branching with fail-closed unknowns' {
        $scenario = Get-ScenarioGroup 28
        @($scenario).Count | Should -Be 1
        $scenario[0].verification_mode | Should -Be 'contract_branching'
        $scenario[0].execution_contract | Should -Be 'deferred_to_candidate'
        $scenario[0].forbidden_events | Should -Contain 'multi_turn_summary_substitution'
        $scenario[0].forbidden_events | Should -Contain 'fail_open_on_unknown_contract'
        $scenario[0].request_verbatim | Should -Match 'one_shot'
        $scenario[0].request_verbatim | Should -Match 'parent_user_input'
        $scenario[0].request_verbatim | Should -Match 'multi_turn_user_decision'
        $scenario[0].request_verbatim | Should -Match 'fail closed'
    }

    It 'lets the daily default wording skip cold discovery entirely' {
        $scenario = Get-ScenarioGroup 29
        @($scenario).Count | Should -Be 1
        $scenario[0].route_class | Should -Be 'ordinary_no_skill'
        $scenario[0].cold_discovery | Should -Be 'conditional'
        $scenario[0].verification_mode | Should -Be 'host_judgment'
    }

    It 'keeps group 26 as an evidence-field probe that rejects fabricated invocation evidence' {
        $scenario = Get-ScenarioGroup 26
        @($scenario).Count | Should -Be 1
        $scenario[0].verification_mode | Should -Be 'event_fields_reporting'
        $scenario[0].forbidden_events | Should -Contain 'fabricated_invocation_evidence'
        foreach ($field in @('host_visible', 'implicit_candidate', 'cold_discovery_attempted', 'skill_md_loaded', 'native_child_started', 'side_effect_authorized', 'live_result_accepted')) {
            $scenario[0].request_verbatim | Should -Match ([regex]::Escape($field)) -Because ("group 26 must report the seven event fields verbatim, including {0}" -f $field)
        }
    }

    It 'keeps the live-derived compound interrogation sample as a non-collapsible multi-turn oracle' {
        $s30 = @($matrix.scenarios | Where-Object id -eq 'S30-live-derived')
        @($s30).Count | Should -Be 1
        $s30[0].source_kind | Should -Be 'derived_test_case'
        $s30[0].route_class | Should -Be 'cold_candidate'
        $s30[0].cold_discovery | Should -Be 'conditional'
        $s30[0].execution_contract | Should -Be 'multi_turn_user_decision'
        $s30[0].forbidden_events | Should -Contain 'multi_turn_summary_substitution'
        @($s30[0].allowed_candidate_names).Count | Should -Not -Be 1 -Because 'implicit compound request must not hard-pin a unique skill'
        $s30[0].request_verbatim | Should -Match '审问'
        $s30[0].request_verbatim | Should -Match '官方文档'
    }

    It 'pins CSR-170 fresh-host probes to distinct positive and negative routing boundaries' {
        $byId = @{}
        foreach ($scenario in @($matrix.scenarios | Where-Object id -in @('S32-live-derived', 'S33-live-derived', 'S34-live-derived', 'S35-live-derived', 'S36-live-derived', 'S37-live-derived'))) {
            $byId[$scenario.id] = $scenario
        }

        $byId.Keys.Count | Should -Be 6

        $byId['S32-live-derived'].route_class | Should -Be 'cold_candidate'
        $byId['S32-live-derived'].execution_contract | Should -Be 'multi_turn_user_decision'
        $byId['S32-live-derived'].request_verbatim | Should -Match '一题一题'
        $byId['S32-live-derived'].request_verbatim | Should -Match '官方与项目资料'

        $byId['S33-live-derived'].route_class | Should -Be 'cold_candidate'
        $byId['S33-live-derived'].execution_contract | Should -Be 'one_shot'
        $byId['S33-live-derived'].request_verbatim | Should -Match '单轮只读'

        $byId['S34-live-derived'].verification_mode | Should -Be 'contract_branching'
        $byId['S34-live-derived'].execution_contract | Should -Be 'deferred_to_candidate'
        $byId['S34-live-derived'].forbidden_events | Should -Contain 'fail_open_on_unknown_contract'

        foreach ($id in @('S35-live-derived', 'S37-live-derived')) {
            $byId[$id].route_class | Should -Be 'ordinary_no_skill'
            $byId[$id].cold_discovery | Should -Be 'forbidden'
            $byId[$id].forbidden_events | Should -Contain 'cold_discovery'
        }

        $byId['S36-live-derived'].route_class | Should -Be 'visible_direct'
        $byId['S36-live-derived'].cold_discovery | Should -Be 'forbidden'
        $byId['S36-live-derived'].execution_contract | Should -Be 'multi_turn_user_decision'
    }
}
