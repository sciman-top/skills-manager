BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'skills.ps1')

    function New-ExecutionAdmissionFixture([string]$RootPath) {
        $skillPath = Join-Path $RootPath 'agent\grill-with-docs\SKILL.md'
        $dependencyPath = Join-Path $RootPath 'agent\grilling\SKILL.md'
        $fixturePath = Join-Path $RootPath 'reports\fixture-plan.md'
        foreach ($path in @($skillPath, $dependencyPath, $fixturePath)) {
            $parent = Split-Path -Parent $path
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        }
        Set-Content -LiteralPath $skillPath -Value 'grill-with-docs entrypoint' -Encoding UTF8
        Set-Content -LiteralPath $dependencyPath -Value 'grilling entrypoint' -Encoding UTF8
        Set-Content -LiteralPath $fixturePath -Value 'ExecutionAdmission proposal' -Encoding UTF8

        $contract = [pscustomobject][ordered]@{
            mode = 'multi_turn_user_decision'
            native_agent = 'design-griller'
            conversation_owner = 'parent'
            stop_condition = 'one_question_then_wait'
        }
        $closure = @(
            [pscustomobject][ordered]@{ kind = 'skill'; name = 'grill-with-docs'; path = $skillPath; availability = 'available'; load_side_effect = 'read_only'; side_effect = 'controlled_write'; entrypoint_hash_validated = $true; contained = $true; dependencies = @('grilling'); execution_contract = $contract },
            [pscustomobject][ordered]@{ kind = 'skill'; name = 'grilling'; path = $dependencyPath; availability = 'available'; load_side_effect = 'read_only'; side_effect = 'read_only'; entrypoint_hash_validated = $true; contained = $true; dependencies = @(); execution_contract = $contract }
        )
        return [pscustomobject][ordered]@{
            validation = [pscustomobject][ordered]@{
                load_validation = [pscustomobject]@{ pass = $true }
                selected = @($closure[0])
                validated_closure = $closure
                execution_contract = $contract
                routing_receipt = [pscustomobject]@{
                    receipt_id = 'crr-1111111111111111'
                    query_sha256 = ('a' * 64)
                    catalog_fingerprint = ('b' * 64)
                    truth_boundary = 'candidate_load_validated'
                    validated_candidates = 'grill-with-docs'
                    validated_closure = @('grill-with-docs', 'grilling')
                    execution_contract = $contract
                }
            }
            allowed_read_set = @($fixturePath, $skillPath, $dependencyPath)
            fixture_path = $fixturePath
            skill_path = $skillPath
        }
    }
}

Describe 'Execution admission' {
    It 'creates a content-addressed read-only admission and a content-addressed one-question plan' {
        $root = Join-Path $TestDrive 'valid'
        $fixture = New-ExecutionAdmissionFixture $root
        $issuedAt = '2026-08-24T08:00:00Z'

        $admission = New-ExecutionAdmission -OriginalRequest '请逐轮审问这份提案，不改文件。' -AdmittedGoal '审问 ExecutionAdmission 提案的接口和不变量。' -Validation $fixture.validation -AllowedReadSet $fixture.allowed_read_set -AuthorityBasis 'current_user_design_decision' -IssuedAt $issuedAt -RepoRoot $root
        $plan = New-ExecutionPlan -Admission $admission

        (Test-ExecutionAdmissionContract -Admission $admission -RepoRoot $root).pass | Should -BeTrue
        (Test-ExecutionPlanContract -Plan $plan -Admission $admission).pass | Should -BeTrue
        $admission.admission_id | Should -Match '^adm-[a-f0-9]{64}$'
        $plan.plan_id | Should -Match '^plan-[a-f0-9]{64}$'
        $admission.requested_operation | Should -Be 'read_only'
        @($admission.exact_write_set) | Should -Be @()
        $plan.action | Should -Be 'ask_one_question'
        $plan.adapter | Should -Be 'design-griller'
    }

    It 'rejects mutation of an immutable read-only admission payload' {
        $root = Join-Path $TestDrive 'mutation'
        $fixture = New-ExecutionAdmissionFixture $root
        $admission = New-ExecutionAdmission -OriginalRequest '请逐轮审问这份提案，不改文件。' -AdmittedGoal '审问 ExecutionAdmission 提案的接口和不变量。' -Validation $fixture.validation -AllowedReadSet $fixture.allowed_read_set -AuthorityBasis 'current_user_design_decision' -IssuedAt '2026-08-24T08:00:00Z' -RepoRoot $root
        $admission.exact_write_set = @('D:\\CODE\\skills-manager\\AGENTS.md')

        $result = Test-ExecutionAdmissionContract -Admission $admission -RepoRoot $root

        $result.pass | Should -BeFalse
        @($result.findings | ForEach-Object code) | Should -Contain 'read_only_write_set_not_empty'
        @($result.findings | ForEach-Object code) | Should -Contain 'admission_id_mismatch'
    }

    It 'rejects a closure hash drift before the design-griller can be dispatched' {
        $root = Join-Path $TestDrive 'drift'
        $fixture = New-ExecutionAdmissionFixture $root
        $admission = New-ExecutionAdmission -OriginalRequest '请逐轮审问这份提案，不改文件。' -AdmittedGoal '审问 ExecutionAdmission 提案的接口和不变量。' -Validation $fixture.validation -AllowedReadSet $fixture.allowed_read_set -AuthorityBasis 'current_user_design_decision' -IssuedAt '2026-08-24T08:00:00Z' -RepoRoot $root
        $plan = New-ExecutionPlan -Admission $admission
        Set-Content -LiteralPath $fixture.skill_path -Value 'tampered entrypoint' -Encoding UTF8

        $result = Test-ExecutionAdmissionRevalidation -Admission $admission -Plan $plan -Validation $fixture.validation -RepoRoot $root

        $result.pass | Should -BeFalse
        $result.disposition | Should -Be 'reject'
        @($result.findings | ForEach-Object code) | Should -Contain 'closure_hash_drift'
    }

    It 'fails closed when the router contract is not the design-griller multi-turn contract' {
        $root = Join-Path $TestDrive 'contract'
        $fixture = New-ExecutionAdmissionFixture $root
        $fixture.validation.execution_contract = [pscustomobject]@{ mode = 'one_shot'; native_agent = 'cold-capability-runner'; conversation_owner = 'runner'; stop_condition = 'parent_contract' }

        { New-ExecutionAdmission -OriginalRequest '请逐轮审问这份提案，不改文件。' -AdmittedGoal '审问 ExecutionAdmission 提案的接口和不变量。' -Validation $fixture.validation -AllowedReadSet $fixture.allowed_read_set -AuthorityBasis 'current_user_design_decision' -IssuedAt '2026-08-24T08:00:00Z' -RepoRoot $root } | Should -Throw '*execution_contract_invalid*'
    }

    It 'derives a successor only after predecessor revalidation and an attributable user answer' {
        $root = Join-Path $TestDrive 'successor'
        $fixture = New-ExecutionAdmissionFixture $root
        $request = '请逐轮审问这份提案，不改文件。'
        $admission = New-ExecutionAdmission -OriginalRequest $request -AdmittedGoal '审问 ExecutionAdmission 提案的接口和不变量。' -Validation $fixture.validation -AllowedReadSet $fixture.allowed_read_set -AuthorityBasis 'current_user_design_decision' -IssuedAt '2026-08-24T08:00:00Z' -RepoRoot $root
        $plan = New-ExecutionPlan -Admission $admission

        $successor = New-ExecutionAdmissionSuccessor -PriorAdmission $admission -PriorPlan $plan -OriginalRequest $request -AttributableUserAnswer '接受推荐。' -Validation $fixture.validation -IssuedAt '2026-08-24T08:01:00Z' -RepoRoot $root
        $result = Test-ExecutionAdmissionContinuation -PriorAdmission $admission -PriorPlan $plan -SuccessorAdmission $successor.admission -SuccessorPlan $successor.plan -Validation $fixture.validation -RepoRoot $root

        $result.pass | Should -BeTrue
        $successor.enforcement | Should -Be 'parent_side_soft_guard_only'
        $successor.admission.prior_admission_id | Should -Be $admission.admission_id
        $successor.admission.attributable_user_answer_sha256 | Should -Match '^[a-f0-9]{64}$'
        $successor.admission.admission_id | Should -Not -Be $admission.admission_id
        $successor.plan.admission_id | Should -Be $successor.admission.admission_id
    }

    It 'fails closed when a successor lacks an answer, reuses a request, or is not later than its predecessor' {
        $root = Join-Path $TestDrive 'successor-reject'
        $fixture = New-ExecutionAdmissionFixture $root
        $request = '请逐轮审问这份提案，不改文件。'
        $admission = New-ExecutionAdmission -OriginalRequest $request -AdmittedGoal '审问 ExecutionAdmission 提案的接口和不变量。' -Validation $fixture.validation -AllowedReadSet $fixture.allowed_read_set -AuthorityBasis 'current_user_design_decision' -IssuedAt '2026-08-24T08:00:00Z' -RepoRoot $root
        $plan = New-ExecutionPlan -Admission $admission

        { New-ExecutionAdmissionSuccessor -PriorAdmission $admission -PriorPlan $plan -OriginalRequest $request -AttributableUserAnswer '' -Validation $fixture.validation -IssuedAt '2026-08-24T08:01:00Z' -RepoRoot $root } | Should -Throw '*attributable_user_answer_missing*'
        { New-ExecutionAdmissionSuccessor -PriorAdmission $admission -PriorPlan $plan -OriginalRequest '不同的请求' -AttributableUserAnswer '接受推荐。' -Validation $fixture.validation -IssuedAt '2026-08-24T08:01:00Z' -RepoRoot $root } | Should -Throw '*continuation_request_mismatch*'
        { New-ExecutionAdmissionSuccessor -PriorAdmission $admission -PriorPlan $plan -OriginalRequest $request -AttributableUserAnswer '接受推荐。' -Validation $fixture.validation -IssuedAt '2026-08-24T08:00:00Z' -RepoRoot $root } | Should -Throw '*continuation_issued_at_not_later*'
    }
}
