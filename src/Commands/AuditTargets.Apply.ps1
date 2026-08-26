function Get-AuditPersistedChangeTotal($counts) {
    if ($null -eq $counts) { return 0 }
    $total = 0
    foreach ($field in @("add_installed", "remove_removed", "mcp_add_added", "mcp_add_updated", "mcp_remove_removed")) {
        if ($counts.PSObject.Properties.Match($field).Count -gt 0) {
            $total += [int]$counts.$field
        }
    }
    return $total
}

function Get-AuditDryRunSummaryPath([string]$recommendationsPath) {
    return (Get-AuditReceiptPath $recommendationsPath)
}

function ConvertTo-AuditJsonArray($value) {
    $items = New-Object System.Collections.Generic.List[object]
    if ($null -ne $value) {
        foreach ($item in @($value)) {
            if ($null -ne $item) {
                $items.Add($item) | Out-Null
            }
        }
    }
    return @($items.ToArray())
}

function New-AuditDryRunSummary($plan, [string]$recommendationsPath) {
    $add = @()
    $index = 1
    foreach ($item in @($plan.items)) {
        $itemIndex = if ($item.PSObject.Properties.Match("original_index").Count -gt 0) { [int]$item.original_index } else { $index }
        $add += [pscustomobject]([ordered]@{
            index = $itemIndex
            original_index = $itemIndex
            name = [string]$item.name
            reason_target_profile = [string]$item.reason_target_profile
            sources = @($item.sources)
            keyword_trace = $item.keyword_trace
            status = [string]$item.status
        })
        $index++
    }
    $remove = @()
    $index = 1
    foreach ($item in @($plan.removal_candidates)) {
        $itemIndex = if ($item.PSObject.Properties.Match("original_index").Count -gt 0) { [int]$item.original_index } else { $index }
        $remove += [pscustomobject]([ordered]@{
            index = $itemIndex
            original_index = $itemIndex
            name = [string]$item.name
            installed = [ordered]@{
                vendor = [string]$item.vendor
                from = [string]$item.from
            }
            reason_target_profile = [string]$item.reason_target_profile
            sources = @($item.sources)
            keyword_trace = $item.keyword_trace
            status = [string]$item.status
        })
        $index++
    }
    $mcpAdd = @()
    $index = 1
    foreach ($item in @($plan.mcp_items)) {
        $itemIndex = if ($item.PSObject.Properties.Match("original_index").Count -gt 0) { [int]$item.original_index } else { $index }
        $mcpAdd += [pscustomobject]([ordered]@{
            index = $itemIndex
            original_index = $itemIndex
            name = [string]$item.name
            reason_target_profile = [string]$item.reason_target_profile
            sources = @($item.sources)
            keyword_trace = $item.keyword_trace
            status = [string]$item.status
        })
        $index++
    }
    $mcpRemove = @()
    $index = 1
    foreach ($item in @($plan.mcp_removal_candidates)) {
        $itemIndex = if ($item.PSObject.Properties.Match("original_index").Count -gt 0) { [int]$item.original_index } else { $index }
        $mcpRemove += [pscustomobject]([ordered]@{
            index = $itemIndex
            original_index = $itemIndex
            name = [string]$item.name
            installed_name = [string]$item.installed_name
            reason_target_profile = [string]$item.reason_target_profile
            sources = @($item.sources)
            keyword_trace = $item.keyword_trace
            status = [string]$item.status
        })
        $index++
    }
    return [pscustomobject]([ordered]@{
        schema_version = 1
        generated_at = (Get-Date).ToString("o")
        mode = "dry_run"
        success = $true
        persisted = $false
        recommendations_path = $recommendationsPath
        run_id = [string]$plan.run_id
        target = [string]$plan.target
        decision_basis_summary = [string]$plan.decision_basis.summary
        empty_recommendation_reasons = if ($plan.PSObject.Properties.Match("empty_recommendation_reasons").Count -gt 0) { ConvertTo-AuditJsonArray $plan.empty_recommendation_reasons } else { @() }
            source_observations = if ($plan.PSObject.Properties.Match("source_observations").Count -gt 0) { @(ConvertTo-AuditJsonArray $plan.source_observations) } else { @() }
        counts = [ordered]@{
            add = @($add).Count
            remove = @($remove).Count
            mcp_add = @($mcpAdd).Count
            mcp_remove = @($mcpRemove).Count
        }
        add = @($add)
        remove = @($remove)
        mcp_add = @($mcpAdd)
        mcp_remove = @($mcpRemove)
    })
}

function Get-AuditSourceEvidencePolicy([string]$recommendationDir) {
    $path = Join-Path $recommendationDir "snapshot.json"
    $policy = [ordered]@{ enabled = $false; source_strategy_path = $path; min_unique_sources_for_changes = 0; require_http_source_for_changes = $false; require_source_observations_for_changes = $false }
    try {
        $snapshot = Read-AuditSnapshot $recommendationDir
        $data = $snapshot.source_strategy
        if ($data.PSObject.Properties.Match("evidence_policy").Count -eq 0 -or $null -eq $data.evidence_policy) {
            return [pscustomobject]$policy
        }
        $e = $data.evidence_policy
        $min = 0
        if ($e.PSObject.Properties.Match("min_unique_sources_for_changes").Count -gt 0) {
            $min = [int]$e.min_unique_sources_for_changes
        }
        $needHttp = $false
        if ($e.PSObject.Properties.Match("require_http_source_for_changes").Count -gt 0) {
            $needHttp = [bool]$e.require_http_source_for_changes
        }
        $needObservations = $false
        if ($e.PSObject.Properties.Match("require_source_observations_for_changes").Count -gt 0) {
            $needObservations = [bool]$e.require_source_observations_for_changes
        }
        $policy.enabled = ($min -gt 0 -or $needHttp -or $needObservations)
        $policy.min_unique_sources_for_changes = if ($min -lt 0) { 0 } else { $min }
        $policy.require_http_source_for_changes = $needHttp
        $policy.require_source_observations_for_changes = $needObservations
        return [pscustomobject]$policy
    }
    catch {
        return [pscustomobject]$policy
    }
}

function Test-AuditRecommendationSourceCoveragePolicy($rec, $policy) {
    $coverage = Get-AuditRecommendationSourceCoverage $rec
    $issues = New-Object System.Collections.Generic.List[string]
    if ($null -eq $policy -or -not [bool]$policy.enabled) {
        return [pscustomobject]([ordered]@{
            pass = $true
            issues = @()
            coverage = $coverage
        })
    }
    if ([int]$coverage.total_change_items -eq 0) {
        return [pscustomobject]([ordered]@{
            pass = $true
            issues = @()
            coverage = $coverage
        })
    }
    $requiredUnique = [int]$policy.min_unique_sources_for_changes
    if ($requiredUnique -gt 0 -and [int]$coverage.unique_source_count -lt $requiredUnique) {
        $issues.Add(("insufficient_source_coverage：变更建议共 {0} 项，但 unique sources={1}，低于阈值 {2}。" -f [int]$coverage.total_change_items, [int]$coverage.unique_source_count, $requiredUnique)) | Out-Null
    }
    if ([bool]$policy.require_http_source_for_changes -and [int]$coverage.http_source_count -lt 1) {
        $issues.Add("insufficient_source_coverage：变更建议缺少可验证的 http/https 来源。") | Out-Null
    }
    if ([bool]$policy.require_source_observations_for_changes -and [int]$coverage.items_with_source_observation -lt [int]$coverage.total_change_items) {
        $missing = @($coverage.change_items_missing_source_observation | Select-Object -First 5) -join ", "
        $issues.Add(("insufficient_source_coverage：变更建议需要对应 source_observations，已覆盖 {0}/{1}。缺失：{2}" -f [int]$coverage.items_with_source_observation, [int]$coverage.total_change_items, $missing)) | Out-Null
    }
    return [pscustomobject]([ordered]@{
        pass = ($issues.Count -eq 0)
        issues = @($issues)
        coverage = $coverage
    })
}

function Get-AuditDecisionQualityPolicy([string]$recommendationDir) {
    $path = Join-Path $recommendationDir "snapshot.json"
    $policy = [ordered]@{ enabled = $false; source_strategy_path = $path; mode = "target-repo"; require_keyword_trace_for_changes = $false; require_keyword_trace_membership = $false; min_target_profile_keywords_per_change = 0; min_target_repo_keywords_per_change = 0; min_installed_state_keywords_per_change = 0 }
    try {
        $snapshot = Read-AuditSnapshot $recommendationDir
        $data = $snapshot.source_strategy
        if ($data.PSObject.Properties.Match("mode").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$data.mode)) {
            $policy.mode = ([string]$data.mode).Trim().ToLowerInvariant()
        }
        if ($data.PSObject.Properties.Match("decision_quality_policy").Count -eq 0 -or $null -eq $data.decision_quality_policy) {
            return [pscustomobject]$policy
        }
        $q = $data.decision_quality_policy
        if ($q.PSObject.Properties.Match("require_keyword_trace_for_changes").Count -gt 0) {
            $policy.require_keyword_trace_for_changes = [bool]$q.require_keyword_trace_for_changes
        }
        if ($q.PSObject.Properties.Match("require_keyword_trace_membership").Count -gt 0) {
            $policy.require_keyword_trace_membership = [bool]$q.require_keyword_trace_membership
        }
        if ($q.PSObject.Properties.Match("min_target_profile_keywords_per_change").Count -gt 0) {
            $policy.min_target_profile_keywords_per_change = [Math]::Max(0, [int]$q.min_target_profile_keywords_per_change)
        }
        if ($q.PSObject.Properties.Match("min_target_repo_keywords_per_change").Count -gt 0) {
            $policy.min_target_repo_keywords_per_change = [Math]::Max(0, [int]$q.min_target_repo_keywords_per_change)
        }
        if ($q.PSObject.Properties.Match("min_installed_state_keywords_per_change").Count -gt 0) {
            $policy.min_installed_state_keywords_per_change = [Math]::Max(0, [int]$q.min_installed_state_keywords_per_change)
        }
        $policy.enabled = (
            [bool]$policy.require_keyword_trace_for_changes -or
            [bool]$policy.require_keyword_trace_membership -or
            [int]$policy.min_target_profile_keywords_per_change -gt 0 -or
            [int]$policy.min_target_repo_keywords_per_change -gt 0 -or
            [int]$policy.min_installed_state_keywords_per_change -gt 0
        )
        return [pscustomobject]$policy
    }
    catch {
        return [pscustomobject]$policy
    }
}

function Get-AuditDecisionInsights([string]$recommendationDir) {
    $path = Join-Path $recommendationDir "snapshot.json"
    $result = [ordered]@{
        exists = $false
        path = $path
        mode = "target-repo"
        keywords = [ordered]@{
            target_profile = @()
            target_repo = @()
            installed_state = @()
        }
    }
    try {
        $snapshot = Read-AuditSnapshot $recommendationDir
        $data = $snapshot.decision_insights
        $result.exists = $true
        if ($data.PSObject.Properties.Match("mode").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$data.mode)) {
            $result.mode = ([string]$data.mode).Trim().ToLowerInvariant()
        }
        if ($data.PSObject.Properties.Match("keywords").Count -gt 0 -and $null -ne $data.keywords) {
            foreach ($field in @("target_profile", "target_repo", "installed_state")) {
                if ($data.keywords.PSObject.Properties.Match($field).Count -gt 0) {
                    $result.keywords[$field] = @(Normalize-AuditStringArray $data.keywords.$field)
                }
            }
        }
        return [pscustomobject]$result
    }
    catch {
        return [pscustomobject]$result
    }
}

function Test-AuditRecommendationDecisionQualityPolicy($rec, $policy, $decisionInsights) {
    $coverage = [ordered]@{
        total_change_items = Get-AuditRecommendationChangeItemCount $rec
        items_with_complete_keyword_trace = 0
        target_profile_keyword_ref_count = 0
        target_keyword_ref_count = 0
        installed_keyword_ref_count = 0
        unique_target_profile_keywords = @()
        unique_target_keywords = @()
        unique_installed_keywords = @()
    }
    $issues = New-Object System.Collections.Generic.List[string]
    if ($null -eq $policy -or -not [bool]$policy.enabled) {
        return [pscustomobject]([ordered]@{
                pass = $true
                issues = @()
                coverage = [pscustomobject]$coverage
            })
    }
    if ([int]$coverage.total_change_items -eq 0) {
        return [pscustomobject]([ordered]@{
                pass = $true
                issues = @()
                coverage = [pscustomobject]$coverage
            })
    }

    $recommendationMode = "target-repo"
    if ($rec.PSObject.Properties.Match("recommendation_mode").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$rec.recommendation_mode)) {
        $recommendationMode = ([string]$rec.recommendation_mode).Trim().ToLowerInvariant()
    }
    $requiredTargetProfile = [int]$policy.min_target_profile_keywords_per_change
    $requiredTarget = [int]$policy.min_target_repo_keywords_per_change
    $requiredInstalled = [int]$policy.min_installed_state_keywords_per_change
    if ([bool]$policy.require_keyword_trace_for_changes) {
        if ($requiredTargetProfile -lt 1) { $requiredTargetProfile = 1 }
        if ($requiredTarget -lt 1) { $requiredTarget = 1 }
        if ($requiredInstalled -lt 1) { $requiredInstalled = 1 }
    }

    $targetProfileSet = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $targetSet = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $installedSet = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($token in @(Normalize-AuditStringArray $decisionInsights.keywords.target_profile)) { $null = $targetProfileSet.Add($token) }
    $targetTokens = @(Normalize-AuditStringArray $decisionInsights.keywords.target_repo)
    foreach ($token in @($targetTokens)) { $null = $targetSet.Add($token) }
    foreach ($token in @(Normalize-AuditStringArray $decisionInsights.keywords.installed_state)) { $null = $installedSet.Add($token) }
    if ([bool]$policy.require_keyword_trace_membership -and -not [bool]$decisionInsights.exists) {
        $issues.Add("insufficient_decision_quality：snapshot.json decision_insights 缺失或不可读，无法校验 keyword_trace 归属。") | Out-Null
    }

    $uniqueTargetProfile = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $uniqueTarget = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $uniqueInstalled = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $collections = @(
        @{ kind = "skill-add"; items = @($rec.new_skills) },
        @{ kind = "skill-remove"; items = @($rec.removal_candidates) },
        @{ kind = "mcp-add"; items = @($rec.mcp_new_servers) },
        @{ kind = "mcp-remove"; items = @($rec.mcp_removal_candidates) }
    )
    foreach ($group in @($collections)) {
        foreach ($item in @($group.items)) {
            $trace = $null
            if ($item.PSObject.Properties.Match("keyword_trace").Count -gt 0 -and $null -ne $item.keyword_trace -and (Test-AuditObjectLike $item.keyword_trace)) {
                $trace = $item.keyword_trace
            }
            $targetProfileRefs = @()
            $targetRefs = @()
            $installedRefs = @()
            if ($null -ne $trace) {
                if ($trace.PSObject.Properties.Match("target_profile").Count -gt 0) { $targetProfileRefs = @(Normalize-AuditStringArray $trace.target_profile) }
                if ($trace.PSObject.Properties.Match("target_repo").Count -gt 0) { $targetRefs = @(Normalize-AuditStringArray $trace.target_repo) }
                if ($trace.PSObject.Properties.Match("installed_state").Count -gt 0) { $installedRefs = @(Normalize-AuditStringArray $trace.installed_state) }
            }

            if (@($targetProfileRefs).Count -gt 0 -and @($targetRefs).Count -gt 0 -and @($installedRefs).Count -gt 0) {
                $coverage.items_with_complete_keyword_trace = [int]$coverage.items_with_complete_keyword_trace + 1
            }
            $coverage.target_profile_keyword_ref_count = [int]$coverage.target_profile_keyword_ref_count + @($targetProfileRefs).Count
            $coverage.target_keyword_ref_count = [int]$coverage.target_keyword_ref_count + @($targetRefs).Count
            $coverage.installed_keyword_ref_count = [int]$coverage.installed_keyword_ref_count + @($installedRefs).Count

            foreach ($token in @($targetProfileRefs)) { $null = $uniqueTargetProfile.Add($token) }
            foreach ($token in @($targetRefs)) { $null = $uniqueTarget.Add($token) }
            foreach ($token in @($installedRefs)) { $null = $uniqueInstalled.Add($token) }

            if ($requiredTargetProfile -gt 0 -and @($targetProfileRefs).Count -lt $requiredTargetProfile) {
                $issues.Add(("insufficient_decision_quality：{0} `{1}` 的 keyword_trace.target_profile 数量为 {2}，低于阈值 {3}。" -f [string]$group.kind, [string]$item.name, @($targetProfileRefs).Count, $requiredTargetProfile)) | Out-Null
            }
            if ($requiredTarget -gt 0 -and @($targetRefs).Count -lt $requiredTarget) {
                $issues.Add(("insufficient_decision_quality：{0} `{1}` 的 keyword_trace.target_repo 数量为 {2}，低于阈值 {3}。" -f [string]$group.kind, [string]$item.name, @($targetRefs).Count, $requiredTarget)) | Out-Null
            }
            if ($requiredInstalled -gt 0 -and @($installedRefs).Count -lt $requiredInstalled) {
                $issues.Add(("insufficient_decision_quality：{0} `{1}` 的 keyword_trace.installed_state 数量为 {2}，低于阈值 {3}。" -f [string]$group.kind, [string]$item.name, @($installedRefs).Count, $requiredInstalled)) | Out-Null
            }

            if ([bool]$policy.require_keyword_trace_membership -and [bool]$decisionInsights.exists) {
                $unknownTargetProfile = @($targetProfileRefs | Where-Object { -not $targetProfileSet.Contains([string]$_) })
                if (@($unknownTargetProfile).Count -gt 0) {
                    $issues.Add(("insufficient_decision_quality：{0} `{1}` 的 keyword_trace.target_profile 包含未知关键词：{2}" -f [string]$group.kind, [string]$item.name, (@($unknownTargetProfile | Select-Object -First 3) -join ", "))) | Out-Null
                }
                $unknownTarget = @($targetRefs | Where-Object { -not $targetSet.Contains([string]$_) })
                if (@($unknownTarget).Count -gt 0) {
                    $issues.Add(("insufficient_decision_quality：{0} `{1}` 的 keyword_trace.target_repo 包含未知关键词：{2}" -f [string]$group.kind, [string]$item.name, (@($unknownTarget | Select-Object -First 3) -join ", "))) | Out-Null
                }
                $unknownInstalled = @($installedRefs | Where-Object { -not $installedSet.Contains([string]$_) })
                if (@($unknownInstalled).Count -gt 0) {
                    $issues.Add(("insufficient_decision_quality：{0} `{1}` 的 keyword_trace.installed_state 包含未知关键词：{2}" -f [string]$group.kind, [string]$item.name, (@($unknownInstalled | Select-Object -First 3) -join ", "))) | Out-Null
                }
            }
        }
    }
    $coverage.unique_target_profile_keywords = @($uniqueTargetProfile | Sort-Object)
    $coverage.unique_target_keywords = @($uniqueTarget | Sort-Object)
    $coverage.unique_installed_keywords = @($uniqueInstalled | Sort-Object)
    return [pscustomobject]([ordered]@{
            pass = ($issues.Count -eq 0)
            issues = @($issues)
            coverage = [pscustomobject]$coverage
        })
}

function Write-AuditApplyStageReceipt([string]$recommendationsPath, $report) {
    $section = if ([string]$report.mode -eq "dry_run") { "dry_run" } else { "apply" }
    return (Write-AuditReceiptSection $recommendationsPath $section ([pscustomobject]$report))
}

function Apply-AuditMcpSelections($selectedAddItems, $selectedRemoveItems) {
    $selectedAddItems = @($selectedAddItems)
    $selectedRemoveItems = @($selectedRemoveItems)
    if ($selectedAddItems.Count -eq 0 -and $selectedRemoveItems.Count -eq 0) {
        return [pscustomobject]@{ changed = $false }
    }

    $cfg = LoadCfg
    $cfgRaw = Get-Content $CfgPath -Raw
    $servers = @(if ($cfg.PSObject.Properties.Match("mcp_servers").Count -gt 0 -and $null -ne $cfg.mcp_servers) { @($cfg.mcp_servers) } else { @() })
    $changed = $false
    $removedNames = New-Object System.Collections.Generic.List[string]

    foreach ($item in $selectedAddItems) {
        $candidate = $item.server
        $existing = @($servers | Where-Object { [string]$_.name -eq [string]$candidate.name })
        if ($existing.Count -eq 1 -and (Test-McpServerEquivalent $existing[0] $candidate)) {
            $item.status = "already_present"
            continue
        }
        $replaced = $false
        for ($i = 0; $i -lt $servers.Count; $i++) {
            if ([string]$servers[$i].name -eq [string]$candidate.name) {
                $servers[$i] = $candidate
                $replaced = $true
                $changed = $true
                break
            }
        }
        if ($replaced) {
            $item.status = "updated"
        }
        else {
            $servers += $candidate
            $item.status = "added"
            $changed = $true
        }
    }

    foreach ($item in $selectedRemoveItems) {
        $name = [string]$item.installed_name
        $matches = @($servers | Where-Object { [string]$_.name -eq $name })
        if ($matches.Count -eq 0) {
            $item.status = "not_found"
            continue
        }
        if ($matches.Count -gt 1) {
            $item.status = "ambiguous"
            continue
        }
        $servers = @($servers | Where-Object { [string]$_.name -ne $name })
        $removedNames.Add($name) | Out-Null
        $item.status = "removed"
        $changed = $true
    }

    if (-not $changed) {
        return [pscustomobject]@{ changed = $false }
    }

    if ($cfg.PSObject.Properties.Match("mcp_servers").Count -eq 0) {
        $cfg | Add-Member -NotePropertyName mcp_servers -NotePropertyValue @() -Force
    }
    $cfg.mcp_servers = @($servers)
    Remove-McpProfileServerReferences $cfg @($removedNames.ToArray()) | Out-Null
    SaveCfgSafe $cfg $cfgRaw
    同步MCP
    return [pscustomobject]@{ changed = $true }
}

function Resolve-AuditRecommendationsPathForPreflight([string]$RecommendationsPath, [string]$RunId) {
    if (-not [string]::IsNullOrWhiteSpace($RecommendationsPath)) {
        $resolvedInputPath = Resolve-AuditPathRunIdPlaceholder $RecommendationsPath "--recommendations" @("snapshot.json", "recommendations.json", "receipt.json")
        return (Resolve-AuditTargetPath $resolvedInputPath)
    }
    Need (-not [string]::IsNullOrWhiteSpace($RunId)) "预检至少需要 --run-id 或 --recommendations 其一"
    $resolvedRunId = Resolve-AuditRunIdInput $RunId "--run-id" @("snapshot.json", "recommendations.json", "receipt.json")
    return (Join-Path (Get-AuditReportRoot $resolvedRunId) "recommendations.json")
}

function Get-AuditRunPromptContractVersion([string]$recommendationDir) {
    try { return ([string](Read-AuditSnapshot $recommendationDir).prompt_contract_version).Trim() }
    catch { return "" }
}

function Test-AuditTargetProfilePreflight([string]$recommendationDir) {
    $path = Join-Path $recommendationDir "snapshot.json"
    $issues = New-Object System.Collections.Generic.List[string]
    try {
        $snapshot = Read-AuditSnapshot $recommendationDir
        Need ($null -ne $snapshot.target_profile) ("snapshot.target_profile 缺失：{0}" -f $path)
        Need ([string]$snapshot.target_profile.derivation -eq "target_scans_only") ("snapshot.target_profile.derivation 必须为 target_scans_only：{0}" -f $path)
        Need (@($snapshot.target_scans).Count -gt 0) ("snapshot.target_scans 不能为空：{0}" -f $path)
    }
    catch {
        $issues.Add([string]$_.Exception.Message) | Out-Null
    }
    return [pscustomobject]@{
        path = $path
        exists = (Test-Path -LiteralPath $path -PathType Leaf)
        ok = ($issues.Count -eq 0)
        skipped = $false
        skipped_reason = ""
        issues = @($issues)
    }
}

function Get-AuditPreflightRunIdFromBundle([string]$recommendationDir, [string]$fallbackRunId) {
    try {
        $runId = [string](Read-AuditSnapshot $recommendationDir).run_id
        if (-not [string]::IsNullOrWhiteSpace($runId)) { return $runId }
    } catch { }
    if (-not [string]::IsNullOrWhiteSpace($fallbackRunId) -and [string]$fallbackRunId -ne "<run-id>") {
        return [string]$fallbackRunId
    }
    return (Split-Path -Leaf $recommendationDir)
}

function Invoke-AuditRecommendationsPreflight {
    param(
        [string]$RecommendationsPath,
        [string]$RunId,
        [object]$InitialWorkflowInputState = $null
    )
    $resolvedRecommendations = Resolve-AuditRecommendationsPathForPreflight $RecommendationsPath $RunId
    $recommendationDir = Split-Path -Parent $resolvedRecommendations
    if ([string]::IsNullOrWhiteSpace($recommendationDir)) { $recommendationDir = "." }
    $recommendationsExists = Test-Path -LiteralPath $resolvedRecommendations -PathType Leaf
    $rec = $null
    $recommendationValidationIssue = ""
    if ($recommendationsExists) {
        try { $rec = Load-AuditRecommendations $resolvedRecommendations }
        catch { $recommendationValidationIssue = "invalid_recommendations：{0}" -f [string]$_.Exception.Message }
    }
    else {
        $recommendationValidationIssue = "recommendations_missing：recommendations.json 不存在：{0}" -f $resolvedRecommendations
    }
    $snapshotPath = Join-Path $recommendationDir "snapshot.json"
    Need (Test-Path -LiteralPath $snapshotPath -PathType Leaf) ("缺少 snapshot.json：{0}" -f $snapshotPath)
    $snapshot = Read-AuditSnapshot $recommendationDir
    $liveState = Get-AuditLiveInstalledState
    $snapshotState = Get-AuditInstalledSnapshotState $snapshotPath
    $snapshotStaleness = Get-AuditInstalledSnapshotStaleness $snapshotState $liveState
    $isSnapshotStale = [bool]$snapshotStaleness.is_stale

    $runPromptVersion = Get-AuditRunPromptContractVersion $recommendationDir
    $currentPromptVersion = Get-AuditPromptContractVersion
    $promptVersionMatched = (-not [string]::IsNullOrWhiteSpace($runPromptVersion) -and [string]$runPromptVersion -eq [string]$currentPromptVersion)
    $sourcePolicy = Get-AuditSourceEvidencePolicy $recommendationDir
    $decisionQualityPolicy = Get-AuditDecisionQualityPolicy $recommendationDir
    $decisionInsights = Get-AuditDecisionInsights $recommendationDir
    if ($null -ne $rec) {
        $sourceCoverageCheck = Test-AuditRecommendationSourceCoveragePolicy $rec $sourcePolicy
        $decisionQualityCheck = Test-AuditRecommendationDecisionQualityPolicy $rec $decisionQualityPolicy $decisionInsights
    }
    else {
        $sourceCoverageCheck = [pscustomobject]@{
            ok = $true
            issues = @()
            coverage = [ordered]@{
                total_change_items = 0
                unique_sources = @()
                unique_source_count = 0
                http_source_count = 0
                source_observation_count = 0
                items_with_source_observation = 0
                change_items_missing_source_observation = @()
            }
        }
        $decisionQualityCheck = [pscustomobject]@{
            ok = $true
            issues = @()
            coverage = [ordered]@{
                total_change_items = 0
                items_with_complete_keyword_trace = 0
                target_profile_keyword_ref_count = 0
                target_keyword_ref_count = 0
                installed_keyword_ref_count = 0
                unique_target_profile_keywords = @()
                unique_target_keywords = @()
                unique_installed_keywords = @()
            }
        }
    }
    $targetProfileCheck = Test-AuditTargetProfilePreflight $recommendationDir
    $targetSnapshotState = Get-AuditTargetRepoSnapshotState $recommendationDir
    $targetLiveState = if ($null -ne $InitialWorkflowInputState -and $null -ne $InitialWorkflowInputState.target_repos) {
        $InitialWorkflowInputState.target_repos
    }
    else {
        Get-AuditTargetRepoLiveState $targetSnapshotState
    }
    $targetStaleness = Get-AuditTargetRepoStaleness $targetSnapshotState $targetLiveState
    if ($null -ne $rec) {
        $removalDependencyCheck = Test-AuditRemovalDependencyClosure -Config (LoadCfg) -RemovalCandidates @($rec.removal_candidates) -RepositoryRoot $Root
    }
    else {
        $removalDependencyCheck = [pscustomobject]@{ ok = $true; checked_files = @(); blocked = @(); issues = @() }
    }

    $issues = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($recommendationValidationIssue)) {
        $issues.Add($recommendationValidationIssue) | Out-Null
    }
    $changeItemCount = if ($null -ne $rec) { Get-AuditRecommendationChangeItemCount $rec } else { 0 }
    $hasScanContract = $snapshot.PSObject.Properties.Match("scan_contract").Count -gt 0 -and $null -ne $snapshot.scan_contract
    if ($hasScanContract -and $changeItemCount -gt 0 -and [string]::IsNullOrWhiteSpace([string]$snapshot.query)) {
        $issues.Add("query_required_for_changes：全仓能力盘点未提供用户任务语境，不能据此新增、删除或替换 skill/MCP；请使用 --query 重新扫描。") | Out-Null
    }
    if ([bool]$targetStaleness.is_stale) {
        $targetNames = (@($targetStaleness.drifted_targets) | ForEach-Object { [string]$_.name }) -join ", "
        $issues.Add(("target_repo_drift：目标仓扫描快照与当前 HEAD/工作树不一致：{0}。请重新运行审查目标 扫描。" -f $targetNames)) | Out-Null
    }
    if ($isSnapshotStale) {
        $issues.Add("stale_snapshot：审查快照与当前生效配置不一致，请先重新运行审查目标 扫描。") | Out-Null
    }
    if (-not $promptVersionMatched) {
        $runPromptDisplay = if ([string]::IsNullOrWhiteSpace($runPromptVersion)) { "missing" } else { [string]$runPromptVersion }
        $issues.Add(("prompt_contract_mismatch：run={0}，current={1}。请先重新运行审查目标 扫描生成新 run。" -f $runPromptDisplay, $currentPromptVersion)) | Out-Null
    }
    foreach ($issue in @($sourceCoverageCheck.issues)) {
        $issues.Add([string]$issue) | Out-Null
    }
    foreach ($issue in @($decisionQualityCheck.issues)) {
        $issues.Add([string]$issue) | Out-Null
    }
    foreach ($issue in @($targetProfileCheck.issues)) {
        $issues.Add(("target_profile_invalid：{0}" -f [string]$issue)) | Out-Null
    }
    foreach ($issue in @($removalDependencyCheck.issues)) {
        $issues.Add([string]$issue) | Out-Null
    }
    $sourceCoveragePassed = if ($sourceCoverageCheck.PSObject.Properties.Match("pass").Count -gt 0) { [bool]$sourceCoverageCheck.pass } else { [bool]$sourceCoverageCheck.ok }
    $decisionQualityPassed = if ($decisionQualityCheck.PSObject.Properties.Match("pass").Count -gt 0) { [bool]$decisionQualityCheck.pass } else { [bool]$decisionQualityCheck.ok }

    $report = [ordered]@{
        schema_version = 1
        preflight_mode = "recommendations"
        run_id = if ($null -ne $rec) { [string]$rec.run_id } else { Get-AuditPreflightRunIdFromBundle $recommendationDir $RunId }
        target = if ($null -ne $rec) { [string]$rec.target } else { "" }
        success = ($issues.Count -eq 0)
        error_code = if (-not $recommendationsExists) { "recommendations_missing" } elseif (-not [string]::IsNullOrWhiteSpace($recommendationValidationIssue)) { "invalid_recommendations" } elseif ([bool]$targetStaleness.is_stale) { "target_repo_drift" } elseif (-not [bool]$removalDependencyCheck.ok) { "removal_dependency_blocked" } elseif ($isSnapshotStale) { "stale_snapshot" } elseif (-not $promptVersionMatched) { "prompt_contract_mismatch" } elseif (-not $sourceCoveragePassed) { "insufficient_source_coverage" } elseif (-not $decisionQualityPassed) { "insufficient_decision_quality" } elseif (-not [bool]$targetProfileCheck.ok) { "target_profile_invalid" } elseif ($hasScanContract -and $changeItemCount -gt 0 -and [string]::IsNullOrWhiteSpace([string]$snapshot.query)) { "query_required_for_changes" } else { "" }
        recommendations_path = $resolvedRecommendations
        recommendations_exists = $recommendationsExists
        prompt_contract = [ordered]@{
            run = $runPromptVersion
            current = $currentPromptVersion
            matched = $promptVersionMatched
        }
        source_evidence_policy = $sourcePolicy
        source_coverage = $sourceCoverageCheck.coverage
        decision_quality_policy = $decisionQualityPolicy
        decision_quality = $decisionQualityCheck.coverage
        decision_insights = $decisionInsights
        target_profile_check = $targetProfileCheck
        snapshot_state = $snapshotState
        live_state = $liveState
        snapshot_staleness = $snapshotStaleness
        target_snapshot_state = $targetSnapshotState
        target_live_state = $targetLiveState
        target_staleness = $targetStaleness
        removal_dependency_check = $removalDependencyCheck
        issues = @($issues)
    }
    $reportPath = Write-AuditReceiptSection $resolvedRecommendations "preflight" ([pscustomobject]$report)

    Write-Host ("预检报告：{0}" -f $reportPath) -ForegroundColor Cyan
    if ($issues.Count -eq 0) {
        if ($recommendationsExists) {
            Write-Host "预检通过：快照与提示词契约均匹配，可继续研究与 dry-run。" -ForegroundColor Green
        }
        else {
            Write-Host "预检通过：审查包快照与提示词契约均匹配；recommendations.json 尚未生成，可继续生成建议。" -ForegroundColor Green
        }
        return [pscustomobject]$report
    }

    foreach ($issue in @($issues)) {
        Write-Host ("- {0}" -f [string]$issue) -ForegroundColor Red
    }
    throw ("预检失败：{0}" -f ($issues -join " | "))
}

function Complete-AuditRecommendationsDryRun {
    param(
        $Plan,
        [System.Collections.IDictionary]$Report,
        [string]$RecommendationsPath,
        [string]$DryRunAck,
        [bool]$RequireDryRunAck
    )

    Write-Host "dry-run 预览（沿用原序号）："
    foreach ($item in @($Plan.items)) { Write-Host ("DRYRUN install: {0}" -f ($item.tokens -join " ")) }
    foreach ($item in @($Plan.removal_candidates)) { Write-Host ("DRYRUN remove: [{0}|{1}] {2}" -f [string]$item.vendor, [string]$item.from, [string]$item.name) }
    foreach ($item in @($Plan.mcp_items)) {
        $server = $item.server
        $transport = if ($server.PSObject.Properties.Match("transport").Count -gt 0) { [string]$server.transport } else { "stdio" }
        if ($transport -eq "stdio") {
            $argsText = if ($server.PSObject.Properties.Match("args").Count -gt 0 -and $null -ne $server.args -and @($server.args).Count -gt 0) { " " + ((@($server.args) | ForEach-Object { [string]$_ }) -join " ") } else { "" }
            Write-Host ("DRYRUN mcp-add: {0} --transport stdio --cmd {1}{2}" -f [string]$server.name, [string]$server.command, $argsText)
        }
        else { Write-Host ("DRYRUN mcp-add: {0} --transport {1} --url {2}" -f [string]$server.name, $transport, [string]$server.url) }
    }
    foreach ($item in @($Plan.mcp_removal_candidates)) { Write-Host ("DRYRUN mcp-remove: {0}" -f [string]$item.installed_name) }
    Write-Host "DRY-RUN 完成：未修改任何技能映射或 MCP 配置（未落盘）。" -ForegroundColor Red
    Write-Host ("如需真正执行，请运行：.\skills.ps1 审查目标 应用 --recommendations `"{0}`" --apply --yes" -f $RecommendationsPath) -ForegroundColor Red
    if ($RequireDryRunAck) {
        $ackToken = Get-AuditDryRunAckToken
        $ackInput = ""
        if (-not [string]::IsNullOrWhiteSpace($DryRunAck)) { $ackInput = [string]$DryRunAck }
        elseif (-not [Console]::IsInputRedirected) { $ackInput = Read-HostSafe ("请输入确认口令 `"{0}`" 表示你已知晓 dry-run 未落盘（回车取消）" -f $ackToken) }
        else { Write-Host ("当前为非交互环境。请追加参数：--dry-run-ack `"{0}`"" -f $ackToken) -ForegroundColor Red }
        if ([string]::IsNullOrWhiteSpace($ackInput) -or $ackInput.Trim() -ne $ackToken) {
            $Report.success = $false
            $Report["canceled"] = $true
            $Report["dry_run_acknowledged"] = $false
            $Report["dry_run_ack_expected"] = $ackToken
            $Report["dry_run_ack_received"] = [string]$ackInput
            $Report.changed_counts = New-AuditChangedCounts $Plan.items $Plan.removal_candidates $Plan.mcp_items $Plan.mcp_removal_candidates
            Write-AuditApplyStageReceipt $RecommendationsPath ([pscustomobject]$Report) | Out-Null
            return [pscustomobject]$Report
        }
        $Report["dry_run_acknowledged"] = $true
    }
    $dryRunSummaryPath = Get-AuditDryRunSummaryPath $RecommendationsPath
    $dryRunSummary = New-AuditDryRunSummary $Plan $RecommendationsPath
    $Report["summary"] = $dryRunSummary
    $Report["dry_run_summary_path"] = $dryRunSummaryPath
    Write-Host ("dry-run 机器可读摘要：{0}" -f $dryRunSummaryPath) -ForegroundColor Cyan
    Write-AuditApplyStageReceipt $RecommendationsPath ([pscustomobject]$Report) | Out-Null
    return [pscustomobject]$Report
}

function Resolve-AuditApplySelections {
    param(
        $Plan,
        [string]$AddSelection,
        [string]$RemoveSelection,
        [string]$McpAddSelection,
        [string]$McpRemoveSelection
    )

    $selectedAdd = Resolve-AuditSelection $AddSelection $Plan.items "请输入要安装的新增建议序号（空=跳过，0=取消）" "新增建议序号无效"
    if ($selectedAdd.canceled) { return [pscustomobject]@{ canceled = $true } }
    $selectedRemove = Resolve-AuditSelection $RemoveSelection @($Plan.removal_candidates | Where-Object { $_.status -eq "planned" }) "请输入要卸载的建议序号（空=跳过，0=取消）" "卸载建议序号无效"
    if ($selectedRemove.canceled) { return [pscustomobject]@{ canceled = $true } }
    $selectedMcpAdd = Resolve-AuditSelection $McpAddSelection @($Plan.mcp_items | Where-Object { $_.status -eq "planned" }) "请输入要新增的 MCP 建议序号（空=跳过，0=取消）" "MCP 新增建议序号无效"
    if ($selectedMcpAdd.canceled) { return [pscustomobject]@{ canceled = $true } }
    $selectedMcpRemove = Resolve-AuditSelection $McpRemoveSelection @($Plan.mcp_removal_candidates | Where-Object { $_.status -eq "planned" }) "请输入要卸载的 MCP 建议序号（空=跳过，0=取消）" "MCP 卸载建议序号无效"
    if ($selectedMcpRemove.canceled) { return [pscustomobject]@{ canceled = $true } }
    return [pscustomobject]@{
        canceled = $false
        add = $selectedAdd
        remove = $selectedRemove
        mcp_add = $selectedMcpAdd
        mcp_remove = $selectedMcpRemove
    }
}

function Test-AuditApplyWorkflowReceipt([string]$RecommendationsPath) {
    $resolved = [IO.Path]::GetFullPath($RecommendationsPath)
    $workflowPath = Get-AuditWorkflowReportPath $resolved
    if (-not (Test-Path -LiteralPath $workflowPath -PathType Leaf)) {
        return [pscustomobject]@{ pass=$false; code='validated_dry_run_required'; message='Apply requires a successful 校验预演 workflow receipt.'; path=$workflowPath }
    }
    try {
        $container = Get-ContentUtf8 $workflowPath | ConvertFrom-Json
        $receipt = $container.workflow
    }
    catch { return [pscustomobject]@{ pass=$false; code='validated_dry_run_invalid'; message=('Workflow receipt is invalid JSON: {0}' -f $_.Exception.Message); path=$workflowPath } }
    if ($null -eq $receipt) { return [pscustomobject]@{ pass=$false; code='validated_dry_run_incomplete'; message='receipt.json does not contain a workflow section.'; path=$workflowPath } }
    $shapeValid = $receipt.schema_version -eq 1 -and [string]$receipt.workflow -eq 'recommendations_validate_dry_run' -and [bool]$receipt.success -and -not [bool]$receipt.persisted -and [string]$receipt.stages.preflight.status -eq 'passed' -and [string]$receipt.stages.dry_run.status -eq 'passed' -and [string]$receipt.stages.input_stability.status -eq 'passed' -and [bool]$receipt.input_stability.matched
    if (-not $shapeValid) { return [pscustomobject]@{ pass=$false; code='validated_dry_run_incomplete'; message='Workflow receipt does not prove preflight, dry-run, and stable inputs.'; path=$workflowPath } }
    if ([IO.Path]::GetFullPath([string]$receipt.recommendations_path) -ne $resolved -or [string]$receipt.recommendations_sha256 -ne [string](Get-FileContentHash $resolved)) {
        return [pscustomobject]@{ pass=$false; code='validated_dry_run_stale'; message='Recommendations changed after the validated dry-run.'; path=$workflowPath }
    }
    $current = Get-AuditWorkflowInputState $resolved
    $accepted = $receipt.input_stability.after_dry_run
    if ($null -eq $accepted -or [string]$current.file_fingerprint -ne [string]$accepted.file_fingerprint -or [string]$current.target_repo_fingerprint -ne [string]$accepted.target_repo_fingerprint) {
        return [pscustomobject]@{ pass=$false; code='validated_dry_run_stale'; message='Audit bundle or target repositories changed after the validated dry-run.'; path=$workflowPath }
    }
    return [pscustomobject]@{ pass=$true; code=''; message=''; path=$workflowPath; receipt=$receipt; current_state=$current }
}

function New-AuditApplyTransactionSnapshot {
    $exists = Test-Path -LiteralPath $CfgPath -PathType Leaf
    [byte[]]$bytes = if ($exists) { [IO.File]::ReadAllBytes([IO.Path]::GetFullPath($CfgPath)) } else { [byte[]]::new(0) }
    return [pscustomobject][ordered]@{ config_path=[IO.Path]::GetFullPath($CfgPath); config_existed=[bool]$exists; config_bytes=$bytes }
}

function Restore-AuditApplyTransaction {
    param($Snapshot,[bool]$SkillProjectionAttempted,[bool]$McpProjectionAttempted)
    $errors = New-Object System.Collections.Generic.List[string]
    try {
        if ([bool]$Snapshot.config_existed) { Write-BytesAtomic -Path ([string]$Snapshot.config_path) -Bytes ([byte[]]$Snapshot.config_bytes) }
        elseif ([IO.File]::Exists([string]$Snapshot.config_path)) { [IO.File]::Delete([string]$Snapshot.config_path) }
    }
    catch { $errors.Add(('config_restore_failed:{0}' -f $_.Exception.Message)) | Out-Null }
    $configRestoreFailed = @($errors | Where-Object { $_.StartsWith('config_restore_failed:',[StringComparison]::Ordinal) }).Count -gt 0
    if (-not $configRestoreFailed -and $SkillProjectionAttempted) {
        try { 构建生效 }
        catch { $errors.Add(('skill_projection_restore_failed:{0}' -f $_.Exception.Message)) | Out-Null }
    }
    if (-not $configRestoreFailed -and $McpProjectionAttempted) {
        try { 同步MCP }
        catch { $errors.Add(('mcp_projection_restore_failed:{0}' -f $_.Exception.Message)) | Out-Null }
    }
    return [pscustomobject][ordered]@{
        status = $(if($errors.Count -eq 0){'restored'}else{'failed'})
        config_restored = (-not $configRestoreFailed)
        skill_projection_attempted = $SkillProjectionAttempted
        mcp_projection_attempted = $McpProjectionAttempted
        errors = @($errors.ToArray())
        residual_cache_boundary = 'Downloaded import/vendor caches and removal backup directories are not deleted automatically; restored config makes unreferenced caches inactive.'
    }
}

function Set-AuditApplyItemsRolledBack($Plan) {
    foreach($item in @($Plan.items)+@($Plan.removal_candidates)+@($Plan.mcp_items)+@($Plan.mcp_removal_candidates)) {
        if([string]$item.status -in @('installed','removed','added','updated','failed')){$item.status='rolled_back'}
    }
}

function Invoke-AuditRecommendationsApply {
    param(
        [string]$RecommendationsPath,
        [string]$AddSelection,
        [string]$RemoveSelection,
        [string]$McpAddSelection,
        [string]$McpRemoveSelection,
        [string]$DryRunAck,
        [object]$PreflightReport = $null,
        [bool]$RequireDryRunAck = $true,
        [switch]$Apply,
        [switch]$Yes
    )
    if ($Apply -and -not $Yes) {
        throw "执行安装必须同时传入 --apply --yes"
    }
    if ($Apply -and $Yes) {
        if ([string]::IsNullOrWhiteSpace($AddSelection)) { $AddSelection = "all" }
        if ([string]::IsNullOrWhiteSpace($RemoveSelection)) { $RemoveSelection = "all" }
        if ([string]::IsNullOrWhiteSpace($McpAddSelection)) { $McpAddSelection = "all" }
        if ([string]::IsNullOrWhiteSpace($McpRemoveSelection)) { $McpRemoveSelection = "all" }
    }
    $rec = Load-AuditRecommendations $RecommendationsPath
    $recommendationDir = Split-Path -Parent $RecommendationsPath
    if ([string]::IsNullOrWhiteSpace($recommendationDir)) { $recommendationDir = "." }
    if ($Apply) {
        $workflowReceipt = Test-AuditApplyWorkflowReceipt $RecommendationsPath
        if (-not [bool]$workflowReceipt.pass) { throw ('{0}：{1}' -f [string]$workflowReceipt.code,[string]$workflowReceipt.message) }
    }
    $snapshotPath = Join-Path $recommendationDir "snapshot.json"
    Need (Test-Path -LiteralPath $snapshotPath -PathType Leaf) ("缺少 snapshot.json：{0}" -f $snapshotPath)
    $sourcePolicy = Get-AuditSourceEvidencePolicy $recommendationDir
    $decisionQualityPolicy = Get-AuditDecisionQualityPolicy $recommendationDir
    $canReusePreflight = ($null -ne $PreflightReport -and [bool]$PreflightReport.success -and
        $null -ne $PreflightReport.source_coverage -and $null -ne $PreflightReport.decision_quality -and
        $null -ne $PreflightReport.snapshot_state -and $null -ne $PreflightReport.live_state)
    if ($canReusePreflight) {
        $sourceCoverageCheck = [pscustomobject]@{ pass = $true; issues = @(); coverage = $PreflightReport.source_coverage }
        $decisionInsights = $PreflightReport.decision_insights
        $decisionQualityCheck = [pscustomobject]@{ pass = $true; issues = @(); coverage = $PreflightReport.decision_quality }
    }
    else {
        $sourceCoverageCheck = Test-AuditRecommendationSourceCoveragePolicy $rec $sourcePolicy
        $decisionInsights = Get-AuditDecisionInsights $recommendationDir
        $decisionQualityCheck = Test-AuditRecommendationDecisionQualityPolicy $rec $decisionQualityPolicy $decisionInsights
    }
    if (-not [bool]$sourceCoverageCheck.pass) {
        $sourceMessage = ($sourceCoverageCheck.issues -join " | ")
        $sourceReport = [ordered]@{
            schema_version = 2
            run_id = [string]$rec.run_id
            target = [string]$rec.target
            mode = if ($Apply) { "apply" } else { "dry_run" }
            success = $false
            persisted = $false
            error_code = "insufficient_source_coverage"
            error_message = $sourceMessage
            source_evidence_policy = $sourcePolicy
            source_coverage = $sourceCoverageCheck.coverage
            decision_quality_policy = $decisionQualityPolicy
            decision_quality = $decisionQualityCheck.coverage
            decision_insights = $decisionInsights
            changed_counts = New-AuditChangedCounts @() @()
            items = @()
            removal_candidates = @()
            mcp_items = @()
            mcp_removal_candidates = @()
            overlap_findings = @()
            do_not_install = @()
            source_observations = @(ConvertTo-AuditJsonArray $rec.source_observations)
            rollback = @()
        }
        Write-AuditApplyStageReceipt $RecommendationsPath ([pscustomobject]$sourceReport) | Out-Null
        throw $sourceMessage
    }
    if (-not [bool]$decisionQualityCheck.pass) {
        $qualityMessage = ($decisionQualityCheck.issues -join " | ")
        $qualityReport = [ordered]@{
            schema_version = 2
            run_id = [string]$rec.run_id
            target = [string]$rec.target
            mode = if ($Apply) { "apply" } else { "dry_run" }
            success = $false
            persisted = $false
            error_code = "insufficient_decision_quality"
            error_message = $qualityMessage
            source_evidence_policy = $sourcePolicy
            source_coverage = $sourceCoverageCheck.coverage
            decision_quality_policy = $decisionQualityPolicy
            decision_quality = $decisionQualityCheck.coverage
            decision_insights = $decisionInsights
            changed_counts = New-AuditChangedCounts @() @()
            items = @()
            removal_candidates = @()
            mcp_items = @()
            mcp_removal_candidates = @()
            overlap_findings = @()
            do_not_install = @()
            source_observations = @(ConvertTo-AuditJsonArray $rec.source_observations)
            rollback = @()
        }
        Write-AuditApplyStageReceipt $RecommendationsPath ([pscustomobject]$qualityReport) | Out-Null
        throw $qualityMessage
    }
    $liveState = if ($canReusePreflight) { $PreflightReport.live_state } else { Get-AuditLiveInstalledState }
    $snapshotState = if ($canReusePreflight) { $PreflightReport.snapshot_state } else { Get-AuditInstalledSnapshotState $snapshotPath }
    $snapshotStaleness = if ($canReusePreflight) { $PreflightReport.snapshot_staleness } else { Get-AuditInstalledSnapshotStaleness $snapshotState $liveState }
    $isSnapshotStale = [bool]$snapshotStaleness.is_stale
    if ($isSnapshotStale) {
        $staleMessage = "审查快照与当前生效配置不一致（stale_snapshot）。请先运行：.\skills.ps1 审查目标 扫描 重新生成 run 后再应用 recommendations。"
        $staleReport = [ordered]@{
            schema_version = 2
            run_id = [string]$rec.run_id
            target = [string]$rec.target
            mode = if ($Apply) { "apply" } else { "dry_run" }
            success = $false
            persisted = $false
            error_code = "stale_snapshot"
            error_message = $staleMessage
            source_evidence_policy = $sourcePolicy
            source_coverage = $sourceCoverageCheck.coverage
            decision_quality_policy = $decisionQualityPolicy
            decision_quality = $decisionQualityCheck.coverage
            decision_insights = $decisionInsights
            snapshot_state = $snapshotState
            live_state = $liveState
            snapshot_staleness = $snapshotStaleness
            changed_counts = New-AuditChangedCounts @() @()
            items = @()
            removal_candidates = @()
            mcp_items = @()
            mcp_removal_candidates = @()
            overlap_findings = @()
            do_not_install = @()
            source_observations = @(ConvertTo-AuditJsonArray $rec.source_observations)
            rollback = @()
        }
        Write-AuditApplyStageReceipt $RecommendationsPath ([pscustomobject]$staleReport) | Out-Null
        throw $staleMessage
    }
    $plan = New-AuditInstallPlan $rec
    $report = [ordered]@{
        schema_version = 2
        run_id = [string]$rec.run_id
        target = [string]$rec.target
        decision_basis = $plan.decision_basis
        mode = if ($Apply) { "apply" } else { "dry_run" }
        success = $true
        persisted = $false
        source_evidence_policy = $sourcePolicy
        source_coverage = $sourceCoverageCheck.coverage
        decision_quality_policy = $decisionQualityPolicy
        decision_quality = $decisionQualityCheck.coverage
        decision_insights = $decisionInsights
        allow_stale_snapshot = $false
        stale_snapshot_detected = [bool]$isSnapshotStale
        stale_acknowledged = $false
        changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
        snapshot_state = $snapshotState
        live_state = $liveState
        snapshot_staleness = $snapshotStaleness
        items = @($plan.items)
        removal_candidates = @($plan.removal_candidates)
        mcp_items = @($plan.mcp_items)
        mcp_removal_candidates = @($plan.mcp_removal_candidates)
        overlap_findings = @($plan.overlap_findings)
        do_not_install = @($plan.do_not_install)
        source_observations = @(ConvertTo-AuditJsonArray $plan.source_observations)
        rollback = @()
        compensation = [pscustomobject]@{ status='not_required'; config_restored=$false; skill_projection_attempted=$false; mcp_projection_attempted=$false; errors=@() }
    }

    Write-AuditRecommendationSummary $plan $snapshotState $liveState

    if (-not $Apply) {
        return (Complete-AuditRecommendationsDryRun -Plan $plan -Report $report -RecommendationsPath $RecommendationsPath -DryRunAck $DryRunAck -RequireDryRunAck $RequireDryRunAck)
    }

    $selections = Resolve-AuditApplySelections -Plan $plan -AddSelection $AddSelection -RemoveSelection $RemoveSelection -McpAddSelection $McpAddSelection -McpRemoveSelection $McpRemoveSelection
    if ($selections.canceled) {
        $report.success = $false
        $report["canceled"] = $true
        $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
        $report.persisted = $false
        Write-AuditApplyStageReceipt $RecommendationsPath ([pscustomobject]$report) | Out-Null
        return [pscustomobject]$report
    }
    $selectedAdd = $selections.add
    $selectedRemove = $selections.remove
    $selectedMcpAdd = $selections.mcp_add
    $selectedMcpRemove = $selections.mcp_remove
    $workflowReceipt = Test-AuditApplyWorkflowReceipt $RecommendationsPath
    if (-not [bool]$workflowReceipt.pass) { throw ('{0}：{1}' -f [string]$workflowReceipt.code,[string]$workflowReceipt.message) }
    $transaction = New-AuditApplyTransactionSnapshot
    $skillMutationAttempted = $false
    $mcpMutationAttempted = $false

    try {
        foreach ($item in @($selectedAdd.items)) {
            $commandText = ".\skills.ps1 add {0}" -f ($item.tokens -join " ")
            try {
                Write-Host ("Installing recommended skill: {0}" -f $item.name) -ForegroundColor Cyan
                $beforeCfg = LoadCfg
                $skillMutationAttempted = $true
                $ok = Add-ImportFromArgs $item.tokens -NoBuild
                if (-not $ok) { throw ("推荐技能安装失败：{0}" -f $item.name) }
                Ensure-AuditNewManualImportsMapped $beforeCfg | Out-Null
                $item.status = "installed"
                $item | Add-Member -NotePropertyName command -NotePropertyValue $commandText -Force
                $report.rollback += ("Remove matching imports/mappings for recommended skill '{0}' if rollback is required." -f $item.name)
            }
            catch {
                $item.status = "failed"
                $item | Add-Member -NotePropertyName command -NotePropertyValue $commandText -Force
                $item | Add-Member -NotePropertyName error -NotePropertyValue $_.Exception.Message -Force
                $report.success = $false
                $report.items = @($plan.items)
                $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
                $report.persisted = ((Get-AuditPersistedChangeTotal $report.changed_counts) -gt 0)
                Write-AuditApplyStageReceipt $RecommendationsPath ([pscustomobject]$report) | Out-Null
                throw
            }
        }

        if (@($selectedRemove.items).Count -gt 0) {
            $skillMutationAttempted = $true
            Remove-AuditSelectedInstalledSkills $selectedRemove.items | Out-Null
            foreach ($item in @($selectedRemove.items)) {
                $report.rollback += ("Re-add removed skill mapping/import for '{0}' if rollback is required." -f $item.name)
            }
        }

        if (@($selectedMcpAdd.items).Count -gt 0 -or @($selectedMcpRemove.items).Count -gt 0) {
            try {
                $mcpMutationAttempted = $true
                Apply-AuditMcpSelections $selectedMcpAdd.items $selectedMcpRemove.items | Out-Null
                foreach ($item in @($selectedMcpAdd.items)) {
                    if ([string]$item.status -eq "added" -or [string]$item.status -eq "updated") {
                        $report.rollback += ("Restore previous MCP config for '{0}' if rollback is required." -f [string]$item.name)
                    }
                }
                foreach ($item in @($selectedMcpRemove.items)) {
                    if ([string]$item.status -eq "removed") {
                        $report.rollback += ("Re-add removed MCP server '{0}' if rollback is required." -f [string]$item.installed_name)
                    }
                }
            }
            catch {
                foreach ($item in @($selectedMcpAdd.items)) {
                    if ([string]$item.status -eq "planned") { $item.status = "failed" }
                    $item | Add-Member -NotePropertyName error -NotePropertyValue $_.Exception.Message -Force
                }
                foreach ($item in @($selectedMcpRemove.items)) {
                    if ([string]$item.status -eq "planned") { $item.status = "failed" }
                    $item | Add-Member -NotePropertyName error -NotePropertyValue $_.Exception.Message -Force
                }
                $report.success = $false
                $report.items = @($plan.items)
                $report.removal_candidates = @($plan.removal_candidates)
                $report.mcp_items = @($plan.mcp_items)
                $report.mcp_removal_candidates = @($plan.mcp_removal_candidates)
                $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
                $report.persisted = ((Get-AuditPersistedChangeTotal $report.changed_counts) -gt 0)
                Write-AuditApplyStageReceipt $RecommendationsPath ([pscustomobject]$report) | Out-Null
                throw
            }
        }

        $hasSkillChanges = (@($selectedAdd.items).Count -gt 0 -or @($selectedRemove.items).Count -gt 0)
        $hasMcpChanges = (@($selectedMcpAdd.items).Count -gt 0 -or @($selectedMcpRemove.items).Count -gt 0)

        if ($hasSkillChanges) {
            构建生效
        }
        if ($hasSkillChanges -or $hasMcpChanges) {
            $doctorResult = Invoke-Doctor @("--strict")
            if ($doctorResult -and $doctorResult.PSObject.Properties.Match("pass").Count -gt 0 -and -not [bool]$doctorResult.pass) {
                $report.success = $false
                $report.items = @($plan.items)
                $report.removal_candidates = @($plan.removal_candidates)
                $report.mcp_items = @($plan.mcp_items)
                $report.mcp_removal_candidates = @($plan.mcp_removal_candidates)
                $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
                $report.persisted = ((Get-AuditPersistedChangeTotal $report.changed_counts) -gt 0)
                Write-AuditApplyStageReceipt $RecommendationsPath ([pscustomobject]$report) | Out-Null
                throw "doctor --strict failed after applying recommendations"
            }
        }

        $report.items = @($plan.items)
        $report.removal_candidates = @($plan.removal_candidates)
        $report.mcp_items = @($plan.mcp_items)
        $report.mcp_removal_candidates = @($plan.mcp_removal_candidates)
        $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
        $report.persisted = ((Get-AuditPersistedChangeTotal $report.changed_counts) -gt 0)
        Write-AuditApplyStageReceipt $RecommendationsPath ([pscustomobject]$report) | Out-Null
        return [pscustomobject]$report
    }
    catch {
        $originalFailure = $_
        if ($report.success) { $report.success = $false }
        if($skillMutationAttempted -or $mcpMutationAttempted) {
            $report.compensation = Restore-AuditApplyTransaction -Snapshot $transaction -SkillProjectionAttempted $skillMutationAttempted -McpProjectionAttempted $mcpMutationAttempted
            if([string]$report.compensation.status -eq 'restored'){Set-AuditApplyItemsRolledBack $plan}
        }
        $report.items = @($plan.items)
        $report.removal_candidates = @($plan.removal_candidates)
        $report.mcp_items = @($plan.mcp_items)
        $report.mcp_removal_candidates = @($plan.mcp_removal_candidates)
        $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
        $report.persisted = if([string]$report.compensation.status -eq 'restored'){$false}else{((Get-AuditPersistedChangeTotal $report.changed_counts) -gt 0)}
        Write-AuditApplyStageReceipt $RecommendationsPath ([pscustomobject]$report) | Out-Null
        if([string]$report.compensation.status -eq 'failed'){throw ('{0}; compensation_failed:{1}' -f $originalFailure.Exception.Message,(@($report.compensation.errors)-join '|'))}
        throw $originalFailure
    }
}

function Get-AuditApplyConfirmationToken([string]$runId) {
    if ([string]::IsNullOrWhiteSpace($runId)) { return "APPLY" }
    return ("APPLY {0}" -f $runId)
}

function Get-AuditDryRunAckToken {
    return "我知道未落盘"
}

function Invoke-AuditRecommendationsTwoStageApply {
    param(
        [string]$RecommendationsPath,
        [string]$AddSelection,
        [string]$RemoveSelection,
        [string]$McpAddSelection,
        [string]$McpRemoveSelection,
        [string]$DryRunAck
    )
    $dryRunReport = Invoke-AuditRecommendationsValidateDryRun -RecommendationsPath $RecommendationsPath -DryRunAck $DryRunAck
    if ($dryRunReport.PSObject.Properties.Match("success").Count -gt 0 -and -not [bool]$dryRunReport.success) {
        Write-Host "应用确认结束：dry-run 未完成确认，未执行落盘。" -ForegroundColor Yellow
        return $dryRunReport
    }
    $plannedAdds = @($dryRunReport.items | Where-Object { [string]$_.status -eq "planned" }).Count
    $plannedRemoves = @($dryRunReport.removal_candidates | Where-Object { [string]$_.status -eq "planned" }).Count
    $plannedMcpAdds = @($dryRunReport.mcp_items | Where-Object { [string]$_.status -eq "planned" }).Count
    $plannedMcpRemoves = @($dryRunReport.mcp_removal_candidates | Where-Object { [string]$_.status -eq "planned" }).Count
    if ($plannedAdds -eq 0 -and $plannedRemoves -eq 0 -and $plannedMcpAdds -eq 0 -and $plannedMcpRemoves -eq 0) {
        Write-Host "应用确认结束：无可执行变更，保持当前状态。" -ForegroundColor Yellow
        return $dryRunReport
    }

    $confirmToken = Get-AuditApplyConfirmationToken ([string]$dryRunReport.run_id)
    Write-Host ""
    Write-Host ("确认口令：{0}" -f $confirmToken) -ForegroundColor Yellow
    $confirmation = Read-HostSafe "请输入确认口令后回车执行（回车取消）"
    if ([string]::IsNullOrWhiteSpace($confirmation) -or $confirmation.Trim() -ne $confirmToken) {
        Write-Host "已取消执行。未做任何落盘更改。" -ForegroundColor Yellow
        return [pscustomobject]([ordered]@{
            schema_version = 2
            run_id = [string]$dryRunReport.run_id
            target = [string]$dryRunReport.target
            mode = "apply_flow"
            success = $false
            canceled = $true
            expected_confirmation = $confirmToken
            received_confirmation = [string]$confirmation
        })
    }
    return (Invoke-AuditRecommendationsApply -RecommendationsPath $RecommendationsPath -AddSelection $AddSelection -RemoveSelection $RemoveSelection -McpAddSelection $McpAddSelection -McpRemoveSelection $McpRemoveSelection -Apply -Yes)
}

function Get-AuditLatestApplyReportPath {
    $auditRoot = Join-Path $script:Root "reports\skill-audit"
    if (-not (Test-Path -LiteralPath $auditRoot -PathType Container)) { return $null }
    foreach ($candidate in @(Get-ChildItem -Path $auditRoot -Recurse -File -Filter "receipt.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
        try {
            $receipt = Get-ContentUtf8 $candidate.FullName | ConvertFrom-Json
            if ($null -ne $receipt.apply -or $null -ne $receipt.dry_run -or $null -ne $receipt.workflow) { return [string]$candidate.FullName }
        } catch { }
    }
    return $null
}

function Show-AuditLatestStatus {
    $path = Get-AuditLatestApplyReportPath
    if ([string]::IsNullOrWhiteSpace($path)) {
        Write-Host "未找到含 dry-run/apply 状态的 receipt.json。请先执行：审查目标 校验预演 或 审查目标 应用。" -ForegroundColor Yellow
        return
    }
    try {
        $raw = Get-ContentUtf8 $path
        Need (-not [string]::IsNullOrWhiteSpace($raw)) ("状态文件为空：{0}" -f $path)
        $receipt = $raw | ConvertFrom-Json
        $report = if ($null -ne $receipt.apply) { $receipt.apply } elseif ($null -ne $receipt.dry_run) { $receipt.dry_run } else { $receipt.workflow }
    }
    catch {
        throw ("读取状态文件失败：{0}" -f $_.Exception.Message)
    }
    $counts = if ($report.PSObject.Properties.Match("changed_counts").Count -gt 0 -and $null -ne $report.changed_counts) { $report.changed_counts } else { $null }
    $persisted = if ($report.PSObject.Properties.Match("persisted").Count -gt 0) { [bool]$report.persisted } else { $false }
    Write-Host "=== 审查目标最近状态 ==="
    Write-Host ("report: {0}" -f $path)
    Write-Host ("run_id: {0}" -f [string]$report.run_id)
    Write-Host ("mode: {0}" -f [string]$report.mode)
    Write-Host ("success: {0}" -f [string]$report.success)
    Write-Host ("persisted: {0}" -f $persisted)
    if ($null -ne $counts) {
        Write-Host ("changes: add_installed={0}, remove_removed={1}, add_planned={2}, remove_planned={3}, remove_not_found={4}" -f [int]$counts.add_installed, [int]$counts.remove_removed, [int]$counts.add_planned, [int]$counts.remove_planned, [int]$counts.remove_not_found)
        if ($counts.PSObject.Properties.Match("mcp_add_total").Count -gt 0) {
            Write-Host ("mcp_changes: add_added={0}, add_updated={1}, add_planned={2}, remove_removed={3}, remove_planned={4}, remove_not_found={5}" -f [int]$counts.mcp_add_added, [int]$counts.mcp_add_updated, [int]$counts.mcp_add_planned, [int]$counts.mcp_remove_removed, [int]$counts.mcp_remove_planned, [int]$counts.mcp_remove_not_found)
        }
    }
    if ([string]$report.mode -eq "dry_run" -and -not $persisted) {
        Write-Host "警告：最近一次仅为 dry-run，未落盘。" -ForegroundColor Red
    }
}
