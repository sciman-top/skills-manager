function New-AuditInstalledStateSnapshot([string]$context) {
    try {
        try { $liveCfg = LoadCfg }
        catch {
            Log ("{0}读取 skills.json 失败，已回退为空安装快照：{1}" -f $context, $_.Exception.Message) "WARN"
            $liveCfg = New-AuditInstalledFactsFallbackCfg
        }
        $liveState = Get-AuditLiveInstalledState $liveCfg
        $configuredSupplySkills = if ($liveState.PSObject.Properties.Match('configured_supply_skills').Count -gt 0) { @($liveState.configured_supply_skills) } else { @(Get-InstalledSkillFacts $liveCfg) }
        $installedSkills = if ($liveState.PSObject.Properties.Match('profile_selected_skills').Count -gt 0) { @($liveState.profile_selected_skills) } else { @() }
        $externalSkills = @(Get-AuditExternalSkillFacts $liveCfg)
        $installedMcpServers = @(Get-AuditMcpServerFacts $liveCfg)
        return [pscustomobject]([ordered]@{
            snapshot_kind = "audit_input"
            source_of_truth = "live_configuration_and_profile_selection"
            captured_at = (Get-Date).ToString("o")
            live_skill_count = [int]$liveState.skill_count
            live_fingerprint = [string]$liveState.fingerprint
            live_configured_supply_skill_count = if ($liveState.PSObject.Properties.Match('configured_supply_skill_count').Count -gt 0) { [int]$liveState.configured_supply_skill_count } else { @($configuredSupplySkills).Count }
            live_configured_supply_fingerprint = if ($liveState.PSObject.Properties.Match('configured_supply_fingerprint').Count -gt 0) { [string]$liveState.configured_supply_fingerprint } else { Get-AuditFingerprintFromSkillFacts $configuredSupplySkills }
            inventory_semantics = [pscustomobject]([ordered]@{
                    skills = 'current_profile_selected_skills'
                    configured_supply_skills = 'all configured mapping and override sources; not an assertion of current host visibility or invocation'
                })
            profile_selection = if ($liveState.PSObject.Properties.Match('profile_selection').Count -gt 0) { $liveState.profile_selection } else { $null }
            profile_selection_status = if ($liveState.PSObject.Properties.Match('profile_selection_status').Count -gt 0) { [string]$liveState.profile_selection_status } else { 'not_observed' }
            profile_selection_unresolved_names = if ($liveState.PSObject.Properties.Match('profile_selection_unresolved_names').Count -gt 0) { @($liveState.profile_selection_unresolved_names) } else { @() }
            invocation_evidence = if ($liveState.PSObject.Properties.Match('invocation_evidence').Count -gt 0) { $liveState.invocation_evidence } else { [pscustomobject]@{ state = 'not_observed'; scope = 'audit_scanner'; evidence = 'No invocation ledger was supplied.' } }
            live_external_skill_count = if ($liveState.PSObject.Properties.Match('external_skill_count').Count -gt 0) { [int]$liveState.external_skill_count } else { 0 }
            live_external_skill_fingerprint = if ($liveState.PSObject.Properties.Match('external_skill_fingerprint').Count -gt 0) { [string]$liveState.external_skill_fingerprint } else { '' }
            live_mcp_server_count = if ($liveState.PSObject.Properties.Match("mcp_server_count").Count -gt 0) { [int]$liveState.mcp_server_count } else { 0 }
            live_mcp_fingerprint = if ($liveState.PSObject.Properties.Match("mcp_fingerprint").Count -gt 0) { [string]$liveState.mcp_fingerprint } else { "" }
            host_projection = if ($liveState.PSObject.Properties.Match('host_projection').Count -gt 0) { $liveState.host_projection } else { $null }
            skills = @($installedSkills)
            configured_supply_skills = @($configuredSupplySkills)
            external_skills = @($externalSkills)
            mcp_servers = @($installedMcpServers)
        })
    }
    catch { throw ("生成安装状态快照失败：{0}" -f $_.Exception.Message) }
}

function Write-AuditThreeFileBundle {
    param(
        [string]$ReportRoot,
        [string]$RunId,
        [string]$Mode,
        [string]$Query,
        $Config,
        [object[]]$Scans
    )
    Need ($Mode -eq "target-repo") "审查包只支持基于目标仓扫描的 target-repo 模式。"
    Need (@($Scans).Count -gt 0) "审查包至少需要一个目标仓扫描结果。"
    $installedState = New-AuditInstalledStateSnapshot "审查包生成时"
    $sourceStrategy = New-AuditSourceStrategy $Mode $Query
    $targetProfile = New-AuditTargetProfile $Scans $installedState.skills
    $decisionInsights = New-AuditDecisionInsights $targetProfile $Scans $installedState.skills $installedState.mcp_servers $installedState $installedState.external_skills
    $target = "*"
    $snapshotPath = Join-Path $ReportRoot "snapshot.json"
    $recommendationsPath = Join-Path $ReportRoot "recommendations.json"
    $receiptPath = Join-Path $ReportRoot "receipt.json"
    $snapshot = [pscustomobject]([ordered]@{
        schema_version = 2
        snapshot_kind = "audit_input"
        run_id = $RunId
        mode = $Mode
        query = [string]$Query
        scan_contract = [pscustomobject]([ordered]@{
                schema_version = 1
                purpose = if ([string]::IsNullOrWhiteSpace($Query)) { "repository_capability_inventory" } else { "task_oriented_capability_fit" }
                query = [string]$Query
                target_count = @($Scans).Count
                aggregation = "all_enabled_targets"
                target_selector_policy = "--target is accepted only for compatibility and does not narrow the scan"
                evidence_scope = @("target repository files under the configured path, excluding generated/dependency/cache paths", "configured entrypoints and public contracts", "tests and formal product documents")
                prohibited_scope = @("user personal directories", "host auth/provider/session state", "unscanned repositories", "generated outputs and dependency caches")
                scan_budget = [pscustomobject]@{ max_source_files = 600; max_file_bytes = 1048576; max_text_bytes_per_file = 262144 }
                interpretation = if ([string]::IsNullOrWhiteSpace($Query)) { "No user goal was supplied; output is repository capability evidence only." } else { "The query is decision context, not proof that the repository lacks a capability." }
                stop_conditions = @("insufficient evidence", "target drift", "representative sampling ceiling", "contradictory evidence")
            })
        generated_at = (Get-Date).ToString("o")
        prompt_contract_version = Get-AuditPromptContractVersion
        installed_state = $installedState
        target_scans = @($Scans)
        target_profile = $targetProfile
        source_strategy = $sourceStrategy
        decision_insights = $decisionInsights
        native_ai_review = [pscustomobject]([ordered]@{
                schema_version = 2
                decision_owner = "host_ai"
                purpose = "Read-only semantic synthesis that highlights supported user needs and judges skill/MCP lifecycle candidates from explicit evidence; deterministic scanners remain the source of traceable facts and never infer retirement from profile absence."
                allowed_inputs = @("snapshot.json", "target_scans[].detected.*.evidence", "target_scans[].target.resolved_path referenced by evidence")
                prohibited_inputs = @("user-profile.json", "unscanned personal directories", "host auth/provider/session state", "unverified marketplace claims")
                required_output_properties = @("reason_target_profile", "sources", "confidence", "keyword_trace", "uncertainty_or_do_not_install", "semantic_review_for_each_retirement")
                evidence_rules = @(
                    "Reconcile contradictory source, dependency, test, and documentation evidence; do not silently choose the most optimistic interpretation.",
                    "Start from target_profile.user_need_summary and target_profile.prioritized_needs.primary_needs. Raw hit counts and large-repository file volume do not prove user priority.",
                    "The portfolio image is the only user-need decision surface; target_scans are evidence partitions, not separate user-need profiles.",
                    "Promote a secondary or technical-context signal only after inspecting source evidence that establishes a core user journey; record the reason and uncertainty in recommendations.json.",
                    "Treat interface, persistence, testing, and operations signals as delivery context by default, not as direct product intent.",
                    "Treat low-confidence or documented-only signals as observations, not automatic install or removal justification.",
                    "installed_state.skills means current_profile_selected_skills, not all configured supply. Read configured_supply_skills only for source identity, rollback, and overlap analysis; it is not current host visibility or invocation evidence.",
                    "A profile absence, same-name implementation, override, or dependency closure is only an overlap fact. Host AI may propose retirement only after reviewing installed behavior, replacement coverage or obsolescence, usage evidence, migration, rollback, uncertainty, and the need for current-user confirmation.",
                    "installed_state.invocation_evidence=not_observed is not non-use. A user statement of no successful use may indicate a reachability or matching failure and must not be converted directly into a removal candidate.",
                    "Classify general and specialized skills by the reviewed task trigger and unique behavior, not by whether this scan calls them a primary need.",
                    "Each recommendation must remain reproducible from snapshot facts and current inspected sources."
                    "When scan_coverage.confidence_ceiling is representative_sample, sample-only signals cannot be treated as complete repository coverage."
                    "A blank query permits repository capability inventory only; task-specific recommendations require an explicit query and target-local evidence."
                )
                mutation_policy = "recommendations.json only; host, skill, MCP, target-repository, and provider mutation are outside semantic review."
            })
        write_contract = [pscustomobject]@{
            editable_file = "recommendations.json"
            immutable_files = @("snapshot.json", "receipt.json")
            next_command = (".\skills.ps1 审查目标 校验预演 --recommendations `"{0}`" --dry-run-ack `"{1}`"" -f $recommendationsPath, (Get-AuditDryRunAckToken))
        }
        truth_boundary = "repo_snapshot_not_host_loaded"
    })
    $recommendations = New-AuditRecommendationsTemplate $RunId $target $Mode $Query
    Write-AuditJsonFile $snapshotPath $snapshot
    Write-AuditJsonFile $recommendationsPath $recommendations
    $receipt = [pscustomobject]([ordered]@{
        schema_version = 1
        run_id = $RunId
        mode = $Mode
        created_at = (Get-Date).ToString("o")
        updated_at = (Get-Date).ToString("o")
        success = $true
        persisted = $false
        truth_boundary = "repo_snapshot_created_not_reviewed_not_applied"
        scan = [pscustomobject]@{
            success = $true
            snapshot_sha256 = Get-FileContentHash $snapshotPath
            recommendations_template_sha256 = Get-FileContentHash $recommendationsPath
            target_count = @($Scans).Count
        }
        preflight = $null
        dry_run = $null
        workflow = $null
        apply = $null
    })
    Write-AuditJsonFile $receiptPath $receipt

    $required = @(
        [pscustomobject]@{ label = "snapshot.json"; path = $snapshotPath },
        [pscustomobject]@{ label = "recommendations.json"; path = $recommendationsPath },
        [pscustomobject]@{ label = "receipt.json"; path = $receiptPath }
    )
    Assert-AuditBundleRequiredFiles $required
    Write-Host ("审查包已生成：{0}" -f $ReportRoot) -ForegroundColor Green
    Write-Host "运行包固定为三个文件：" -ForegroundColor Cyan
    foreach ($item in $required) { Write-Host ("- {0}: {1}" -f $item.label, $item.path) }
    Write-Host "下一步：只读 snapshot.json，完成 recommendations.json，再执行校验预演；receipt.json 由命令维护。" -ForegroundColor Yellow
    return [pscustomobject]@{
        run_id = $RunId
        path = $ReportRoot
        mode = $Mode
        query = [string]$Query
        scans = @($Scans)
        files = @($required | ForEach-Object { [string]$_.path })
    }
}

function Resolve-AuditBundleOutputDirectory([string]$OutDir, [string]$RunId, [switch]$Force) {
    $reportRoot = if ([string]::IsNullOrWhiteSpace($OutDir)) { Get-AuditReportRoot $RunId } else { Resolve-AuditTargetPath $OutDir }
    if (-not [string]::IsNullOrWhiteSpace($OutDir) -and (Test-Path -LiteralPath $reportRoot -PathType Container) -and -not $Force) {
        if (@(Get-ChildItem -LiteralPath $reportRoot -Force -ErrorAction SilentlyContinue).Count -gt 0) {
            throw ("--out 目录已存在且非空，请使用新的 run-id 目录，或显式追加 --force：{0}" -f $reportRoot)
        }
    }
    EnsureDir $reportRoot
    return $reportRoot
}

function Invoke-AuditTargetsScan {
    param([string]$Target, [string]$Query = "", [string]$OutDir, [switch]$Force)
    $cfg = Load-AuditTargetsConfig
    $targets = @($cfg.targets)
    if (-not [string]::IsNullOrWhiteSpace($Target)) {
        Write-Warning "审查目标 扫描始终汇总全部 enabled 目标仓；--target 仅为兼容保留，不再缩小扫描范围。"
    }
    $targets = @($targets | Where-Object { $_.PSObject.Properties.Match("enabled").Count -eq 0 -or [bool]$_.enabled })
    Need ($targets.Count -gt 0) "没有可扫描的目标仓。"
    $runId = Get-AuditRunId
    $reportRoot = Resolve-AuditBundleOutputDirectory $OutDir $runId -Force:$Force
    $scans = @($targets | ForEach-Object {
        $resolved = Resolve-AuditTargetPath ([string]$_.path)
        New-AuditRepoScan ([string]$_.name) $resolved ([string]$_.path)
    })
    return Write-AuditThreeFileBundle $reportRoot $runId "target-repo" ([string]$Query) $cfg $scans
}
