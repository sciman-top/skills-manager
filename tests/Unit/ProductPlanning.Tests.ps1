Describe 'vNext product planning contract' {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    $scriptPath = Join-Path $repoRoot 'scripts\verify-vnext-planning.ps1'
    $currentPhase = 'P6'
    $currentManifestRelative = 'tasks\skills-manager-vnext-phase6.tasks.json'
    $currentSpecRelative = 'docs\superpowers\specs\2026-08-07-capability-manager-vnext-phase-6-design.md'
    $requiredFiles = @(
        'docs\product\README.md', 'docs\product\skills-manager-vnext-prd.md', 'docs\product\skills-manager-vnext-architecture.md',
        'docs\product\skills-manager-vnext-roadmap.md', 'docs\product\rule-governance-adoption-matrix.md',
        'docs\superpowers\specs\2026-08-01-capability-manager-vnext-phase-0-design.md',
        'docs\superpowers\specs\2026-08-02-capability-manager-vnext-phase-1-design.md',
        'docs\superpowers\specs\2026-08-02-capability-manager-vnext-phase-2-design.md',
        'docs\superpowers\specs\2026-08-02-capability-manager-vnext-phase-3-design.md',
        'docs\superpowers\specs\2026-08-02-capability-manager-vnext-phase-4-design.md',
        'docs\superpowers\specs\2026-08-03-capability-manager-vnext-phase-5-design.md', $currentSpecRelative,
        'tasks\skills-manager-vnext-phase0.tasks.json', 'tasks\skills-manager-vnext-phase1.tasks.json',
        'tasks\skills-manager-vnext-phase2.tasks.json', 'tasks\skills-manager-vnext-phase3.tasks.json',
        'tasks\skills-manager-vnext-phase4.tasks.json', 'tasks\skills-manager-vnext-phase5.tasks.json', $currentManifestRelative,
        'tasks\plan.md', 'tasks\todo.md', 'README.md', 'AGENTS.md', 'config\vnext-phase4-entry-gate.json'
    )

    function Invoke-PlanningVerifier([string]$Root, [string]$ManifestPath = '', [string]$SpecPath = '', [switch]$External) {
        $params = @{ RepoRoot = $Root; Json = $true }
        if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) { $params.ManifestPath = $ManifestPath }
        if (-not [string]::IsNullOrWhiteSpace($SpecPath)) { $params.SpecPath = $SpecPath }
        $output = if ($External) {
            @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -RepoRoot $Root -Json 2>&1)
        }
        else {
            @(& $scriptPath @params -NoExit 2>&1)
        }
        return [pscustomobject]@{ exit_code = $LASTEXITCODE; output = ($output -join "`n") }
    }

    function New-PlanningFixture([string]$Name) {
        $fixtureRoot = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
        $currentManifest = Get-Content -LiteralPath (Join-Path $repoRoot $currentManifestRelative) -Raw | ConvertFrom-Json
        $historicalEvidence = @('phase0', 'phase1', 'phase2', 'phase3', 'phase4', 'phase5') | ForEach-Object {
            $manifest = Get-Content -LiteralPath (Join-Path $repoRoot ('tasks\skills-manager-vnext-{0}.tasks.json' -f $_)) -Raw | ConvertFrom-Json
            @($manifest.tasks | Where-Object status -eq 'done' | ForEach-Object write_set | Where-Object { $_ -like 'docs/change-evidence/*' -and $_ -notmatch '[*?<>]' })
        }
        $currentEvidence = @($currentManifest.tasks | Where-Object status -eq 'done' | ForEach-Object write_set | Where-Object { $_ -like 'docs/change-evidence/*' -and $_ -notmatch '[*?<>]' })
        foreach ($relativePath in @($requiredFiles) + @($historicalEvidence) + @($currentEvidence) + @([string]$currentManifest.latest_evidence) | Sort-Object -Unique) {
            $source = Join-Path $repoRoot $relativePath
            $destination = Join-Path $fixtureRoot $relativePath
            New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
        return $fixtureRoot
    }

    function Get-FirstOpenTask([string]$FixtureRoot) {
        $manifestPath = Join-Path $FixtureRoot $currentManifestRelative
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        return @($manifest.tasks | Where-Object { [string]$_.status -ne 'done' } | Select-Object -First 1)
    }

    It 'accepts the current repository planning contract' {
        $result = Invoke-PlanningVerifier $repoRoot -External
        $parsed = $result.output | ConvertFrom-Json
        $currentManifest = Get-Content -LiteralPath (Join-Path $repoRoot $currentManifestRelative) -Raw | ConvertFrom-Json
        $result.exit_code | Should Be 0
        $parsed.pass | Should Be $true
        $parsed.finding_count | Should Be 0
        $parsed.task_count | Should Be 12
        $parsed.current_phase | Should Be $currentPhase
        $parsed.historical_mode | Should Be $false
        $parsed.truth_level | Should Be 'host_evaluation_partial'
        $parsed.full_gate | Should Be ([string]$currentManifest.full_gate)
        $parsed.runtime_migration | Should Be 'completed'
        $parsed.host_evaluation | Should Be 'host_evaluation_partial'
        $parsed.host_inventory_loaded | Should Be 'observed'
        $parsed.host_invocation_observed | Should Be 'not_observed'
        $parsed.live_accepted | Should Be 'not_accepted'
        $currentMainChain = @($currentManifest.main_chain) -join "`n"
        $currentMainChain | Should Match 'managed_link_includes'
        $currentMainChain | Should Match 'host AI.*capability-router only for explicit cold discovery or policy validation'
        $currentMainChain | Should Not Match '(?i)project all enabled skills'
    }

    It 'requires the unique top-level engineering constitution and governance decrease clause in the PRD' {
        $fixtureRoot = New-PlanningFixture 'missing-engineering-constitution'
        $path = Join-Path $fixtureRoot 'docs\product\skills-manager-vnext-prd.md'
        $content = (Get-Content -LiteralPath $path -Raw).Replace('### PP-000 Host-native-first main-chain-first self-retiring', '### PP-000 removed')
        Set-Content -LiteralPath $path -Value $content -Encoding UTF8

        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json

        @($parsed.findings | Where-Object code -eq 'engineering_constitution_missing').Count | Should Be 1
        $parsed.pass | Should Be $false

        $policyFixtureRoot = New-PlanningFixture 'missing-governance-decrease-clause'
        $policyPath = Join-Path $policyFixtureRoot 'docs\product\skills-manager-vnext-prd.md'
        $policy = '同等风险基线下，经代表性真实任务证明的宿主原生能力越强，本项目附加治理负担必须递减'
        $policyContent = (Get-Content -LiteralPath $policyPath -Raw).Replace($policy, '治理递减条款已删除')
        Set-Content -LiteralPath $policyPath -Value $policyContent -Encoding UTF8

        $policyParsed = (Invoke-PlanningVerifier $policyFixtureRoot).output | ConvertFrom-Json

        @($policyParsed.findings | Where-Object code -eq 'engineering_constitution_missing').Count | Should Be 1
        $policyParsed.pass | Should Be $false

        $scopeFixtureRoot = New-PlanningFixture 'missing-scope-stop-clause'
        $scopePath = Join-Path $scopeFixtureRoot 'docs\product\skills-manager-vnext-prd.md'
        $scopeContent = Get-Content -LiteralPath $scopePath -Raw
        $scopeContent = $scopeContent.Replace('达到已声明的停止条件必须结束', '停止条件条款已删除').Replace('“继续/自动自主连续执行”只授权冻结范围内推进，不授权范围扩展', '连续执行范围条款已删除').Replace('scope expansion', 'scope marker removed')
        Set-Content -LiteralPath $scopePath -Value $scopeContent -Encoding UTF8

        $scopeParsed = (Invoke-PlanningVerifier $scopeFixtureRoot).output | ConvertFrom-Json

        @($scopeParsed.findings | Where-Object code -eq 'engineering_constitution_missing').Count | Should Be 3
        $scopeParsed.pass | Should Be $false
    }

    It 'requires the repository action mapping without duplicating the constitution' {
        $fixtureRoot = New-PlanningFixture 'missing-engineering-constitution-mapping'
        $path = Join-Path $fixtureRoot 'AGENTS.md'
        $content = (Get-Content -LiteralPath $path -Raw).Replace('TOP_LEVEL_ENGINEERING_PRINCIPLE: PP-000', 'TOP_LEVEL_ENGINEERING_PRINCIPLE: missing')
        Set-Content -LiteralPath $path -Value $content -Encoding UTF8

        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json

        @($parsed.findings | Where-Object code -eq 'engineering_constitution_mapping_missing').Count | Should Be 1
        $parsed.pass | Should Be $false

        $closeoutFixtureRoot = New-PlanningFixture 'missing-proportional-closeout-mapping'
        $closeoutPath = Join-Path $closeoutFixtureRoot 'AGENTS.md'
        $closeoutContent = Get-Content -LiteralPath $closeoutPath -Raw
        $closeoutContent = $closeoutContent.Replace('focused closeout', 'focused mapping removed').Replace('integration_blocker', 'integration mapping removed')
        Set-Content -LiteralPath $closeoutPath -Value $closeoutContent -Encoding UTF8

        $closeoutParsed = (Invoke-PlanningVerifier $closeoutFixtureRoot).output | ConvertFrom-Json

        @($closeoutParsed.findings | Where-Object code -eq 'engineering_constitution_mapping_missing').Count | Should Be 2
        $closeoutParsed.pass | Should Be $false
    }

    It 'requires proportional closeout and a candidate before the exact-source full gate and push' {
        $agentsPath = Join-Path $repoRoot 'AGENTS.md'
        $content = Get-Content -LiteralPath $agentsPath -Raw
        $closeout = @($content -split "`r?`n" | Where-Object { $_ -match 'Git closeout' } | Select-Object -First 1)[0]
        $candidate = $closeout.IndexOf('candidate commit', [StringComparison]::OrdinalIgnoreCase)
        $full = $closeout.IndexOf('full', [StringComparison]::OrdinalIgnoreCase)
        $receipt = $closeout.IndexOf('current receipt verifier', [StringComparison]::OrdinalIgnoreCase)
        $push = $closeout.IndexOf('推送', [StringComparison]::OrdinalIgnoreCase)

        $candidate | Should BeGreaterThan -1
        $full | Should BeGreaterThan $candidate
        $receipt | Should BeGreaterThan $full
        $push | Should BeGreaterThan $receipt
        $content | Should Not Match 'full 通过后提交'
        $content.Contains('closeout=`proportional_focused_or_full`') | Should Be $true
        $content | Should Match 'focused closeout'
        $content | Should Match 'full closeout'
        $content | Should Not Match 'closeout 只走 full'
    }

    It 'requires bounded autonomy and proportional verification in the execution index' {
        $planPath = Join-Path $repoRoot 'tasks\plan.md'
        $content = Get-Content -LiteralPath $planPath -Raw

        $content | Should Match 'verification ceiling'
        $content | Should Match 'scope expansion requires re-admission'
        $content | Should Match 'out-of-scope remote divergence'
        $content | Should Match 'minimal user closure.*stop'

        $fixtureRoot = New-PlanningFixture 'missing-bounded-execution-contract'
        $fixturePath = Join-Path $fixtureRoot 'tasks\plan.md'
        $fixtureContent = Get-Content -LiteralPath $fixturePath -Raw
        foreach ($marker in @('verification ceiling', 'scope expansion requires re-admission', 'out-of-scope remote divergence', 'minimal user closure -> stop')) {
            $fixtureContent = $fixtureContent.Replace($marker, ('removed-{0}' -f $marker.Length))
        }
        Set-Content -LiteralPath $fixturePath -Value $fixtureContent -Encoding UTF8

        $todoPath = Join-Path $fixtureRoot 'tasks\todo.md'
        $todoContent = (Get-Content -LiteralPath $todoPath -Raw).Replace('frozen verification ceiling', 'verification marker removed')
        Set-Content -LiteralPath $todoPath -Value $todoContent -Encoding UTF8

        $architecturePath = Join-Path $fixtureRoot 'docs\product\skills-manager-vnext-architecture.md'
        $architectureContent = (Get-Content -LiteralPath $architecturePath -Raw).Replace('focused 发现的跨面风险', 'risk marker removed')
        Set-Content -LiteralPath $architecturePath -Value $architectureContent -Encoding UTF8

        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json

        @($parsed.findings | Where-Object code -eq 'engineering_execution_contract_missing').Count | Should Be 6
        $parsed.pass | Should Be $false
    }

    It 'requires current product documents to delegate dynamic truth to the current manifest' {
        $fixtureRoot = New-PlanningFixture 'current-truth-source'
        $truthMarker = 'CURRENT_PHASE_TRUTH_SOURCE: tasks/skills-manager-vnext-phase6.tasks.json'
        foreach ($relativePath in @(
            'docs\product\README.md',
            'docs\product\skills-manager-vnext-prd.md',
            'docs\product\skills-manager-vnext-architecture.md',
            'docs\product\skills-manager-vnext-roadmap.md'
        )) {
            $path = Join-Path $fixtureRoot $relativePath
            $content = (Get-Content -LiteralPath $path -Raw).Replace($truthMarker, 'CURRENT_PHASE_TRUTH_SOURCE: tasks/missing-current-phase.tasks.json')
            Set-Content -LiteralPath $path -Value $content -Encoding UTF8
        }

        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json

        @($parsed.findings | Where-Object code -eq current_truth_source_mismatch).Count | Should Be 4
        $parsed.pass | Should Be $false
    }

    It 'requires the tracked manifest to delegate current full status to an exact-source receipt' {
        $fixtureRoot = New-PlanningFixture 'full-receipt-authority'
        $path = Join-Path $fixtureRoot $currentManifestRelative
        $manifest = Get-Content $path -Raw | ConvertFrom-Json
        $manifest.full_gate = 'passed'
        $manifest.PSObject.Properties.Remove('full_gate_receipt')
        $manifest | ConvertTo-Json -Depth 100 | Set-Content $path -Encoding UTF8

        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json

        @($parsed.findings | Where-Object code -eq phase_full_gate_authority_invalid).Count | Should Be 1
        $parsed.pass | Should Be $false
    }

    It 'fails closed when the current phase truth ladder is incomplete' {
        $fixtureRoot = New-PlanningFixture 'missing-phase-truth'; $path = Join-Path $fixtureRoot $currentManifestRelative
        $manifest = Get-Content $path -Raw | ConvertFrom-Json
        $manifest.PSObject.Properties.Remove('truth_level')
        $manifest | ConvertTo-Json -Depth 100 | Set-Content $path -Encoding UTF8

        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json

        @($parsed.findings | Where-Object code -eq phase_truth_field_missing).Count | Should Be 1
        $parsed.pass | Should Be $false
    }

    It 'rejects inventory evidence promoted to invocation and failed used for missing live observability' {
        $fixtureRoot = New-PlanningFixture 'truth-overpromotion'; $path = Join-Path $fixtureRoot $currentManifestRelative
        $manifest = Get-Content $path -Raw | ConvertFrom-Json
        $manifest.truth_level = 'host_inventory_loaded'
        $manifest.host_invocation_observed = 'observed'
        $manifest.live_accepted = 'failed'
        $manifest | ConvertTo-Json -Depth 100 | Set-Content $path -Encoding UTF8

        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json

        @($parsed.findings | Where-Object code -eq phase_truth_order_invalid).Count | Should Be 1
        @($parsed.findings | Where-Object code -eq phase_truth_value_invalid).Count | Should Be 1
        $parsed.pass | Should Be $false
    }

    It 'fails closed on duplicate task ids' {
        $fixtureRoot = New-PlanningFixture 'duplicate-task'; $path = Join-Path $fixtureRoot $currentManifestRelative
        $manifest = Get-Content $path -Raw | ConvertFrom-Json; $manifest.tasks = @($manifest.tasks) + @($manifest.tasks[0]); $manifest | ConvertTo-Json -Depth 100 | Set-Content $path -Encoding UTF8
        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq duplicate_task_id).Count | Should Be 1
    }

    It 'rejects redundant standalone full-suite verification' {
        $fixtureRoot = New-PlanningFixture 'redundant-full-suite'; $path = Join-Path $fixtureRoot $currentManifestRelative
        $manifest = Get-Content $path -Raw | ConvertFrom-Json
        $manifest.tasks[0].status = 'done'
        $manifest.tasks[0].verification = @('tests/run.ps1', 'scripts/quality/run-local-quality-gates.ps1 -Profile full -AllowDirtyWorktree')
        $manifest | ConvertTo-Json -Depth 100 | Set-Content $path -Encoding UTF8
        $todoPath = Join-Path $fixtureRoot 'tasks\todo.md'
        $todo = (Get-Content $todoPath -Raw).Replace(('- [ ] `{0}`' -f $manifest.tasks[0].id), ('- [x] `{0}`' -f $manifest.tasks[0].id))
        Set-Content $todoPath $todo -Encoding UTF8
        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq redundant_full_test_invocation).Count | Should Be 1
    }

    It 'rejects a current spec that schedules the full suite before the full gate' {
        $fixtureRoot = New-PlanningFixture 'redundant-spec-suite'
        $specPath = Join-Path $fixtureRoot $currentSpecRelative
        $spec = Get-Content -LiteralPath $specPath -Raw
        $spec = $spec.Replace('2. affected Pester tests', '2. affected Pester tests, then `tests/run.ps1`')
        Set-Content -LiteralPath $specPath -Value $spec -Encoding UTF8
        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq redundant_full_test_spec).Count | Should Be 1
    }

    It 'rejects a historical phase gate left open after the current phase advanced' {
        $fixtureRoot = New-PlanningFixture 'historical-phase-open'
        $gatePath = Join-Path $fixtureRoot 'config\vnext-phase4-entry-gate.json'
        $gate = Get-Content -LiteralPath $gatePath -Raw | ConvertFrom-Json
        $gate.status = 'in_progress'
        $gate | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $gatePath -Encoding UTF8
        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq historical_phase_not_closed).Count | Should Be 1
    }

    It 'blocks a P6 manifest if the roadmap regresses admission to hold' {
        $fixtureRoot = New-PlanningFixture 'p6-hold'
        $roadmapPath = Join-Path $fixtureRoot 'docs\product\skills-manager-vnext-roadmap.md'
        $roadmap = (Get-Content -LiteralPath $roadmapPath -Raw).Replace('P6_ADMISSION_STATUS: admitted', 'P6_ADMISSION_STATUS: hold')
        Set-Content -LiteralPath $roadmapPath -Value $roadmap -Encoding UTF8
        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq next_phase_started_while_on_hold).Count | Should Be 1
    }

    It 'fails closed on unknown dependencies' {
        $fixtureRoot = New-PlanningFixture 'unknown-dependency'; $path = Join-Path $fixtureRoot $currentManifestRelative
        $manifest = Get-Content $path -Raw | ConvertFrom-Json; $manifest.tasks[1].depends_on = @('SMV-P2-999'); $manifest | ConvertTo-Json -Depth 100 | Set-Content $path -Encoding UTF8
        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq unknown_task_dependency).Count | Should Be 1
    }

    It 'accepts the manifest as the sole current task and status truth' {
        $fixtureRoot = New-PlanningFixture 'manifest-only-task-truth'
        $tasks = @((Get-Content (Join-Path $fixtureRoot $currentManifestRelative) -Raw | ConvertFrom-Json).tasks)
        foreach ($relativePath in @($currentSpecRelative, 'tasks\plan.md', 'tasks\todo.md')) {
            $path = Join-Path $fixtureRoot $relativePath
            $text = Get-Content -LiteralPath $path -Raw
            foreach ($task in $tasks) { $text = $text.Replace([string]$task.id, '') }
            Set-Content -LiteralPath $path -Value $text -Encoding UTF8
        }

        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json

        $parsed.pass | Should Be $true
        @($parsed.findings | Where-Object code -match 'task_(?:plan|todo)_|task_missing_from_spec').Count | Should Be 0
    }

    It 'fails closed when a done task evidence file is missing' {
        $fixtureRoot = New-PlanningFixture 'missing-evidence'; $path = Join-Path $fixtureRoot $currentManifestRelative
        $manifest = Get-Content $path -Raw | ConvertFrom-Json
        $manifest.tasks[0].status = 'done'
        $manifest | ConvertTo-Json -Depth 100 | Set-Content $path -Encoding UTF8
        $todoPath = Join-Path $fixtureRoot 'tasks\todo.md'
        $todo = (Get-Content $todoPath -Raw).Replace(('- [ ] `{0}`' -f $manifest.tasks[0].id), ('- [x] `{0}`' -f $manifest.tasks[0].id))
        Set-Content $todoPath $todo -Encoding UTF8
        $doneTask = @($manifest.tasks | Where-Object { [string]$_.status -eq 'done' -and @($_.write_set | Where-Object { $_ -like 'docs/change-evidence/*' -and $_ -notmatch '[*?<>]' }).Count -gt 0 } | Select-Object -Last 1)
        $doneTask | Should Not BeNullOrEmpty
        $evidencePath = @($doneTask.write_set | Where-Object { $_ -like 'docs/change-evidence/*' -and $_ -notmatch '[*?<>]' } | Select-Object -Last 1)
        $missingEvidencePath = Join-Path $fixtureRoot $evidencePath
        if (Test-Path -LiteralPath $missingEvidencePath) { Remove-Item -LiteralPath $missingEvidencePath -Force }
        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq done_task_evidence_missing).Count | Should BeGreaterThan 0
    }

    It 'allows done tasks to share one phase-level logical-slice evidence file' {
        $fixtureRoot = New-PlanningFixture 'shared-phase-evidence'; $path = Join-Path $fixtureRoot $currentManifestRelative
        $manifest = Get-Content $path -Raw | ConvertFrom-Json
        $manifest.tasks[0].write_set = @($manifest.tasks[0].write_set | Where-Object { $_ -notlike 'docs/change-evidence/*' })
        $manifest | ConvertTo-Json -Depth 100 | Set-Content $path -Encoding UTF8

        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        $parsed.pass | Should Be $true
        @($parsed.findings | Where-Object code -eq done_task_missing_evidence_path).Count | Should Be 0
    }

    It 'does not self-lock README links or its own AGENTS registration' {
        $fixtureRoot = New-PlanningFixture 'planning-self-lock'
        $readmePath = Join-Path $fixtureRoot 'README.md'
        $agentsPath = Join-Path $fixtureRoot 'AGENTS.md'
        Set-Content -LiteralPath $readmePath -Value ((Get-Content $readmePath -Raw).Replace('docs/product/README.md', 'docs/product/index.md')) -Encoding UTF8
        Set-Content -LiteralPath $agentsPath -Value ((Get-Content $agentsPath -Raw).Replace('verify-vnext-planning.ps1', 'planning-contract.ps1')) -Encoding UTF8

        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        $parsed.pass | Should Be $true
        @($parsed.findings | Where-Object code -in @('readme_missing_product_docs_link', 'agents_missing_planning_gate')).Count | Should Be 0
    }

    It 'fails closed when plan and current manifest phases differ' {
        $fixtureRoot = New-PlanningFixture 'phase-mismatch'; $path = Join-Path $fixtureRoot $currentManifestRelative
        $manifest = Get-Content $path -Raw | ConvertFrom-Json; $manifest.current_phase = 'P1'; $manifest | ConvertTo-Json -Depth 100 | Set-Content $path -Encoding UTF8
        $parsed = (Invoke-PlanningVerifier $fixtureRoot).output | ConvertFrom-Json
        @($parsed.findings | Where-Object code -eq plan_manifest_phase_mismatch).Count | Should Be 1
    }

    It 'validates P0 through P5 through explicit historical routing' {
        foreach ($phase in @(0, 1, 2, 3, 4, 5)) {
            $date = if ($phase -eq 0) { '2026-08-01' } elseif ($phase -eq 5) { '2026-08-03' } else { '2026-08-02' }
            $result = Invoke-PlanningVerifier $repoRoot ('tasks/skills-manager-vnext-phase{0}.tasks.json' -f $phase) ('docs/superpowers/specs/{0}-capability-manager-vnext-phase-{1}-design.md' -f $date, $phase)
            $result.exit_code | Should Be 0
            ($result.output | ConvertFrom-Json).current_phase | Should Be ('P{0}' -f $phase)
        }
    }
}
