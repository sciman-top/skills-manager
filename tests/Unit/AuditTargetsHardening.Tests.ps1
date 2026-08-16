BeforeAll {
    . $PSScriptRoot\..\..\skills.ps1
    $script:Root = $Root
    $script:CfgPath = $CfgPath
    $script:ImportDir = $ImportDir
    $script:OverridesDir = $OverridesDir

    function New-TestAuditGitRepository([string]$Path) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Push-Location $Path
        try {
            git init --quiet
            git config user.email "audit-tests@example.com"
            git config user.name "Audit Tests"
            Set-ContentUtf8 (Join-Path $Path "README.md") "# Audit target"
            git add README.md
            git commit --quiet -m "initial"
        }
        finally {
            Pop-Location
        }
    }

    function New-TestAuditRecommendation([string]$Path, [string]$RunId = "r-hardening") {
        Set-ContentUtf8 $Path ('{"schema_version":2,"run_id":"' + $RunId + '","target":"demo","decision_basis":{"user_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[],"mcp_removal_candidates":[]}')
    }

    function New-TestHardeningAuditSnapshot {
        param(
            [string]$Path,
            [string]$RunId = "r-hardening",
            [object[]]$Scans = @()
        )
        $live = Get-AuditLiveInstalledState
        $installedState = [pscustomobject]@{
            snapshot_kind = "audit_input"
            captured_at = (Get-Date).ToString("o")
            live_fingerprint = [string]$live.fingerprint
            live_external_skill_fingerprint = if ($live.PSObject.Properties.Match("external_skill_fingerprint").Count -gt 0) { [string]$live.external_skill_fingerprint } else { "" }
            live_mcp_fingerprint = if ($live.PSObject.Properties.Match("mcp_fingerprint").Count -gt 0) { [string]$live.mcp_fingerprint } else { "" }
            skills = @()
            external_skills = @()
            mcp_servers = @()
            host_projection = if ($live.PSObject.Properties.Match("host_projection").Count -gt 0) { $live.host_projection } else { $null }
        }
        $profile = [pscustomobject]@{
            raw_text = "audit hardening"
            summary = "audit hardening"
            last_structured_at = (Get-Date).ToString("o")
            structured_by = "test"
            structured = [pscustomobject]@{
                primary_work_types = @("audit")
                preferred_agents = @()
                tech_stack = @("powershell")
                common_tasks = @("review")
                constraints = @("safe")
                avoidances = @()
                decision_preferences = @("evidence-first")
            }
        }
        Write-AuditJsonFile $Path ([pscustomobject]@{
            schema_version = 1
            run_id = $RunId
            mode = "target-repo"
            prompt_contract_version = Get-AuditPromptContractVersion
            user_profile = $profile
            installed_state = $installedState
            target_scans = @($Scans)
            source_strategy = [pscustomobject]@{ mode="target-repo"; sources=@(); evidence_policy=$null; decision_quality_policy=$null }
            decision_insights = [pscustomobject]@{ mode="target-repo"; keywords=[pscustomobject]@{ user_profile=@("audit"); target_repo=@("repo"); profile_only_context=@("audit"); installed_state=@("skills") } }
        })
    }

}
Describe "Audit target hardening" {
    It "Preserves ordered-dictionary target names in decision insights" {
        $scan = [pscustomobject]@{
            target = [ordered]@{ name = "ordered-target" }
            detected = [ordered]@{
                languages = @("powershell")
                package_managers = @()
                frameworks = @()
                build_commands = @()
                test_commands = @()
                capabilities = @()
                agent_rule_files = @()
                notable_files = @()
            }
            risks = @()
        }

        $insights = New-AuditDecisionInsights $null @($scan) @() @() "target-repo"

        $insights.targets[0].target | Should -Be "ordered-target"
    }

    It "Captures target worktree fingerprints and detects status drift" {
        $repo = Join-Path $TestDrive "target-state-repo"
        New-TestAuditGitRepository $repo
        $runDir = Join-Path $TestDrive "target-state-run"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
        $scan = New-AuditRepoScan "target-state" $repo $repo
        New-TestHardeningAuditSnapshot (Join-Path $runDir "snapshot.json") "r-target-state" @($scan)

        $snapshot = Get-AuditTargetRepoSnapshotState $runDir
        $liveBefore = Get-AuditTargetRepoLiveState $snapshot
        $fresh = Get-AuditTargetRepoStaleness $snapshot $liveBefore
        Set-ContentUtf8 (Join-Path $repo "new-file.txt") "drift"
        $liveAfter = Get-AuditTargetRepoLiveState $snapshot
        $stale = Get-AuditTargetRepoStaleness $snapshot $liveAfter

        $snapshot.targets[0].status_fingerprint | Should -Not -BeNullOrEmpty
        $fresh.is_stale | Should -Be $false
        $stale.is_stale | Should -Be $true
        @($stale.drifted_targets).Count | Should -Be 1
        $stale.drifted_targets[0].changes | Should -Contain "worktree"
    }

    It "Detects content drift when dirty paths and status codes stay unchanged" {
        $repo = Join-Path $TestDrive "same-status-content-drift-repo"
        New-TestAuditGitRepository $repo
        Set-ContentUtf8 (Join-Path $repo "README.md") "first tracked change"
        Set-ContentUtf8 (Join-Path $repo "untracked.txt") "first untracked content"
        $runDir = Join-Path $TestDrive "same-status-content-drift-run"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
        $scan = New-AuditRepoScan "same-status-content-drift" $repo $repo
        New-TestHardeningAuditSnapshot (Join-Path $runDir "snapshot.json") "r-same-status-content-drift" @($scan)

        $snapshot = Get-AuditTargetRepoSnapshotState $runDir
        $liveBefore = Get-AuditTargetRepoLiveState $snapshot
        Set-ContentUtf8 (Join-Path $repo "README.md") "second tracked change"
        Set-ContentUtf8 (Join-Path $repo "untracked.txt") "second untracked content"
        $liveAfter = Get-AuditTargetRepoLiveState $snapshot
        $staleness = Get-AuditTargetRepoStaleness $snapshot $liveAfter

        $snapshot.targets[0].status_count | Should -Be $liveAfter.targets[0].status_count
        $snapshot.targets[0].status_fingerprint | Should -Not -Be $liveAfter.targets[0].status_fingerprint
        $staleness.is_stale | Should -Be $true
        $staleness.drifted_targets[0].changes | Should -Contain "worktree"
    }

    It "Preflight rejects a target repository that drifted after scan" {
        $repo = Join-Path $TestDrive "preflight-target-repo"
        New-TestAuditGitRepository $repo
        $runDir = Join-Path $TestDrive "preflight-target-run"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
        $recPath = Join-Path $runDir "recommendations.json"
        New-TestAuditRecommendation $recPath "r-preflight-target-drift"
        $scan = New-AuditRepoScan "preflight-target" $repo $repo
        New-TestHardeningAuditSnapshot (Join-Path $runDir "snapshot.json") "r-preflight-target-drift" @($scan)
        Set-ContentUtf8 (Join-Path $repo "changed-after-scan.txt") "changed"

        $thrown = $false
        try {
            Invoke-AuditRecommendationsPreflight -RecommendationsPath $recPath | Out-Null
        }
        catch {
            $thrown = $true
            $_.Exception.Message | Should -Match "target_repo_drift"
        }

        $report = (Get-ContentUtf8 (Join-Path $runDir "receipt.json") | ConvertFrom-Json).preflight
        $thrown | Should -Be $true
        $report.success | Should -Be $false
        $report.error_code | Should -Be "target_repo_drift"
        $report.target_staleness.is_stale | Should -Be $true
        $report.target_staleness.drifted_targets[0].changes | Should -Contain "worktree"
    }

    It "Discovers PowerShell entrypoints and documented Python gates" {
        $repo = Join-Path $TestDrive "powershell-repo"
        New-Item -ItemType Directory -Path (Join-Path $repo "tests") -Force | Out-Null
        Set-ContentUtf8 (Join-Path $repo "build.ps1") 'Write-Host "build"'
        Set-ContentUtf8 (Join-Path $repo "tests\run.ps1") 'Invoke-Pester'
        Set-ContentUtf8 (Join-Path $repo "README.md") @"
# Commands

- Build: ``python -m py_compile app.py test_app.py``
- Test: ``uv run --project ./runtime python -m pytest``
- Contract: ``python -m unittest test_app.py``
"@

        $scan = New-AuditRepoScan "powershell-repo" $repo $repo

        $scan.detected.languages | Should -Contain "powershell"
        $scan.detected.languages | Should -Contain "python"
        $scan.detected.build_commands | Should -Contain "pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1"
        $scan.detected.test_commands | Should -Contain "pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1"
        $scan.detected.build_commands | Should -Contain "python -m py_compile app.py test_app.py"
        $scan.detected.test_commands | Should -Contain "uv run --project ./runtime python -m pytest"
        $scan.detected.test_commands | Should -Contain "python -m unittest test_app.py"
    }

    It "Writes a structured preflight report for invalid recommendations" {
        $runDir = Join-Path $TestDrive "invalid-preflight"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
        $recPath = Join-Path $runDir "recommendations.json"
        Set-ContentUtf8 $recPath '{"schema_version":2,"run_id":"r-invalid","target":"demo","decision_basis":{"user_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[{"name":"routing","reason_user_profile":"u","reason_target_repo":"t","sources":["https://example.com"],"note":"invalid","routing":{"router":"missing","selection_policy":"router first","members":[{"name":"actual","role":"router"},{"name":"executor","role":"executor"}]}}],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[],"mcp_removal_candidates":[]}'
        New-TestHardeningAuditSnapshot (Join-Path $runDir "snapshot.json") "r-invalid"

        $thrown = $false
        try {
            Invoke-AuditRecommendationsPreflight -RecommendationsPath $recPath | Out-Null
        }
        catch {
            $thrown = $true
        }

        $reportPath = Join-Path $runDir "receipt.json"
        $report = (Get-ContentUtf8 $reportPath | ConvertFrom-Json).preflight
        $thrown | Should -Be $true
        (Test-Path -LiteralPath $reportPath) | Should -Be $true
        $report.success | Should -Be $false
        $report.error_code | Should -Be "invalid_recommendations"
        ($report.issues -join " ") | Should -Match "routing.router"
    }

    It "Allows host AI to own overlap selection without pretending it is a skill router" {
        $recPath = Join-Path $TestDrive "host-native-overlap.json"
        Set-ContentUtf8 $recPath '{"schema_version":2,"run_id":"r-host-native","target":"demo","decision_basis":{"user_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[{"name":"native-selection","reason_user_profile":"u","reason_target_repo":"t","sources":["https://example.com"],"note":"host selects","routing":{"decision_owner":"host_ai","selection_policy":"use the narrowest matching skill","members":[{"name":"alpha","role":"executor"},{"name":"beta","role":"validator"}]}}],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[],"mcp_removal_candidates":[]}'

        $rec = Load-AuditRecommendations $recPath

        $rec.overlap_findings[0].routing.decision_owner | Should -Be "host_ai"
        $rec.overlap_findings[0].routing.router | Should -BeNullOrEmpty
    }

    It "Rejects a host-native fallback router that is not a declared router member" {
        $recPath = Join-Path $TestDrive "host-native-invalid-fallback.json"
        Set-ContentUtf8 $recPath '{"schema_version":2,"run_id":"r-host-native-invalid","target":"demo","decision_basis":{"user_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[{"name":"native-selection","reason_user_profile":"u","reason_target_repo":"t","sources":["https://example.com"],"note":"host selects","routing":{"decision_owner":"host_ai","fallback_router":"missing","selection_policy":"use the narrowest matching skill","members":[{"name":"alpha","role":"executor"},{"name":"beta","role":"validator"}]}}],"removal_candidates":[],"do_not_install":[],"mcp_new_servers":[],"mcp_removal_candidates":[]}'

        { Load-AuditRecommendations $recPath | Out-Null } | Should -Throw
    }

    It "Finds exact reverse references before a skill removal mutates configuration" {
        $repo = Join-Path $TestDrive "removal-closure"
        New-Item -ItemType Directory -Path (Join-Path $repo "config") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $repo "overrides\patches") -Force | Out-Null
        $cfg = [pscustomobject]@{
            skill_projection = [pscustomobject]@{
                discovery_catalog = [pscustomobject]@{ domain_memberships = [pscustomobject]@{} }
            }
        }
        Set-ContentUtf8 (Join-Path $repo "config\skill-dependency-closure.json") '{"dependencies":[{"skill":"consumer","requires":["retired-skill"],"note":"retired-skill-extra"}]}'
        Set-ContentUtf8 (Join-Path $repo "overrides\patches\provenance.json") '{"patches":[]}'
        $removals = @([pscustomobject]@{ name = "retired-skill"; original_index = 3 })

        $check = Test-AuditRemovalDependencyClosure -Config $cfg -RemovalCandidates $removals -RepositoryRoot $repo

        $check.ok | Should -Be $false
        $check.blocked[0].name | Should -Be "retired-skill"
        $check.blocked[0].original_index | Should -Be 3
        $check.blocked[0].references[0].file | Should -Be "config/skill-dependency-closure.json"
        $check.blocked[0].references[0].path | Should -Be '$.dependencies[0].requires[0]'
        @($check.blocked[0].references).Count | Should -Be 1

        $substringOnly = Test-AuditRemovalDependencyClosure -Config $cfg -RemovalCandidates @([pscustomobject]@{ name = "retired" }) -RepositoryRoot $repo
        $substringOnly.ok | Should -Be $true
    }

    It "Reports removal dependency blockers from preflight" {
        $runDir = Join-Path $TestDrive "removal-preflight"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
        $recPath = Join-Path $runDir "recommendations.json"
        Set-ContentUtf8 $recPath '{"schema_version":2,"run_id":"r-removal-blocked","target":"demo","decision_basis":{"user_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[],"removal_candidates":[{"name":"retired-skill","reason_user_profile":"u","reason_target_repo":"t","sources":["https://example.com"],"installed":{"vendor":"manual","from":"retired-skill"}}],"do_not_install":[],"mcp_new_servers":[],"mcp_removal_candidates":[]}'
        New-TestHardeningAuditSnapshot (Join-Path $runDir "snapshot.json") "r-removal-blocked"
        Mock Test-AuditRemovalDependencyClosure {
            [pscustomobject]@{
                ok = $false
                blocked = @([pscustomobject]@{
                        name = "retired-skill"
                        original_index = 1
                        references = @([pscustomobject]@{ file = "config/skill-dependency-closure.json"; path = '$.dependencies[0].requires[0]' })
                    })
                issues = @('removal_dependency_blocked：1) retired-skill <- config/skill-dependency-closure.json$.dependencies[0].requires[0]')
            }
        }

        { Invoke-AuditRecommendationsPreflight -RecommendationsPath $recPath | Out-Null } | Should -Throw

        $report = (Get-ContentUtf8 (Join-Path $runDir "receipt.json") | ConvertFrom-Json).preflight
        $report.success | Should -Be $false
        $report.error_code | Should -Be "removal_dependency_blocked"
        $report.removal_dependency_check.blocked[0].name | Should -Be "retired-skill"
    }

    It "Scopes host projection health to the admitted resident set" {
        $managedRoot = Join-Path $TestDrive "bounded-managed-root"
        $userRoot = Join-Path $TestDrive "bounded-user-root"
        foreach ($name in @("resident-skill", "cold-skill")) {
            $skillRoot = Join-Path $managedRoot $name
            New-Item -ItemType Directory -Path $skillRoot -Force | Out-Null
            Set-ContentUtf8 (Join-Path $skillRoot "SKILL.md") ("---`nname: {0}`ndescription: test`n---" -f $name)
        }
        New-Item -ItemType Directory -Path $userRoot -Force | Out-Null
        New-Item -ItemType Junction -Path (Join-Path $userRoot "resident-skill") -Target (Join-Path $managedRoot "resident-skill") | Out-Null
        $cfg = [pscustomobject]@{
            skill_projection = [pscustomobject]@{
                managed_source_path = $managedRoot
                user_skill_root = $userRoot
                managed_link_includes = @("resident-skill")
                managed_link_excludes = @()
            }
        }

        $state = Get-AuditHostProjectionState $cfg

        $state.status | Should -Be "available"
        $state.managed_count | Should -Be 1
        $state.broken_count | Should -Be 0
        $state.stale_count | Should -Be 0
    }

    It "Makes dry-run summaries self-contained and keeps category-specific empty reasons" {
        $plan = [pscustomobject]@{
            run_id = "r-summary"
            target = "demo"
            decision_basis = [pscustomobject]@{ summary = "fallback summary" }
            empty_recommendation_reasons = @(
                "new_skills: no skill gap",
                "removal_candidates: no removable skill",
                "mcp_new_servers: no MCP gap",
                "mcp_removal_candidates: no removable MCP"
            )
            source_observations = @()
            items = @()
            removal_candidates = @()
            mcp_items = @()
            mcp_removal_candidates = @()
        }
        $summary = New-AuditDryRunSummary $plan "recommendations.json"
        $categories = New-AuditWorkflowCategories ([pscustomobject]@{
                items = @()
                removal_candidates = @()
                mcp_items = @()
                mcp_removal_candidates = @()
            }) $plan

        $summary.mode | Should -Be "dry_run"
        $summary.success | Should -Be $true
        $summary.persisted | Should -Be $false
        $categories[0].empty_reason | Should -Be "no skill gap"
        $categories[1].empty_reason | Should -Be "no removable skill"
        $categories[2].empty_reason | Should -Be "no MCP gap"
        $categories[3].empty_reason | Should -Be "no removable MCP"
    }

    It "Stops validated dry-run when a target repository changes during preflight" {
        $repo = Join-Path $TestDrive "workflow-target-repo"
        New-TestAuditGitRepository $repo
        $runDir = Join-Path $TestDrive "workflow-target-run"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
        $recPath = Join-Path $runDir "recommendations.json"
        New-TestAuditRecommendation $recPath "r-workflow-target-drift"
        $scan = New-AuditRepoScan "workflow-target" $repo $repo
        New-TestHardeningAuditSnapshot (Join-Path $runDir "snapshot.json") "r-workflow-target-drift" @($scan)

        Mock Invoke-AuditRecommendationsPreflight {
            Set-ContentUtf8 (Join-Path $repo "changed-during-preflight.txt") "changed"
            [pscustomobject]@{
                success = $true
                live_state = [pscustomobject]@{ fingerprint = "skills"; mcp_fingerprint = "mcp"; external_skill_fingerprint = "external" }
            }
        }
        Mock Invoke-AuditRecommendationsApply { throw "dry-run must not execute" }

        $thrown = $false
        try {
            Invoke-AuditRecommendationsValidateDryRun -RecommendationsPath $recPath -DryRunAck "我知道未落盘" | Out-Null
        }
        catch {
            $thrown = $true
            $_.Exception.Message | Should -Match "target_repo_drift"
        }

        $saved = (Get-ContentUtf8 (Get-AuditWorkflowReportPath $recPath) | ConvertFrom-Json).workflow
        $thrown | Should -Be $true
        $saved.failed_stage | Should -Be "input_stability"
        $saved.error_code | Should -Be "target_repo_drift"
        $saved.input_stability.preflight_target_repos_matched | Should -Be $false
        $saved.next_command | Should -Match "审查目标 扫描"
        Should -Invoke Invoke-AuditRecommendationsApply -Times 0 -Exactly -Scope It
    }
}
