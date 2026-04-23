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
    $dir = Split-Path $recommendationsPath -Parent
    if ([string]::IsNullOrWhiteSpace($dir)) { $dir = "." }
    return (Join-Path $dir "dry-run-summary.json")
}

function New-AuditDryRunSummary($plan, [string]$recommendationsPath) {
    $add = @()
    $index = 1
    foreach ($item in @($plan.items)) {
        $add += [pscustomobject]([ordered]@{
            index = $index
            name = [string]$item.name
            reason_user_profile = [string]$item.reason_user_profile
            reason_target_repo = [string]$item.reason_target_repo
            sources = @($item.sources)
            keyword_trace = $item.keyword_trace
            status = [string]$item.status
        })
        $index++
    }
    $remove = @()
    $index = 1
    foreach ($item in @($plan.removal_candidates)) {
        $remove += [pscustomobject]([ordered]@{
            index = $index
            name = [string]$item.name
            installed = [ordered]@{
                vendor = [string]$item.vendor
                from = [string]$item.from
            }
            reason_user_profile = [string]$item.reason_user_profile
            reason_target_repo = [string]$item.reason_target_repo
            sources = @($item.sources)
            keyword_trace = $item.keyword_trace
            status = [string]$item.status
        })
        $index++
    }
    $mcpAdd = @()
    $index = 1
    foreach ($item in @($plan.mcp_items)) {
        $mcpAdd += [pscustomobject]([ordered]@{
            index = $index
            name = [string]$item.name
            reason_user_profile = [string]$item.reason_user_profile
            reason_target_repo = [string]$item.reason_target_repo
            sources = @($item.sources)
            keyword_trace = $item.keyword_trace
            status = [string]$item.status
        })
        $index++
    }
    $mcpRemove = @()
    $index = 1
    foreach ($item in @($plan.mcp_removal_candidates)) {
        $mcpRemove += [pscustomobject]([ordered]@{
            index = $index
            name = [string]$item.name
            installed_name = [string]$item.installed_name
            reason_user_profile = [string]$item.reason_user_profile
            reason_target_repo = [string]$item.reason_target_repo
            sources = @($item.sources)
            keyword_trace = $item.keyword_trace
            status = [string]$item.status
        })
        $index++
    }
    return [pscustomobject]([ordered]@{
        schema_version = 1
        generated_at = (Get-Date).ToString("o")
        recommendations_path = $recommendationsPath
        run_id = [string]$plan.run_id
        target = [string]$plan.target
        decision_basis_summary = [string]$plan.decision_basis.summary
        empty_recommendation_reasons = if ($plan.PSObject.Properties.Match("empty_recommendation_reasons").Count -gt 0) { @($plan.empty_recommendation_reasons) } else { @() }
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
    $path = Join-Path $recommendationDir "source-strategy.json"
    $policy = [ordered]@{
        enabled = $false
        source_strategy_path = $path
        min_unique_sources_for_changes = 0
        require_http_source_for_changes = $false
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]$policy
    }
    try {
        $raw = Get-ContentUtf8 $path
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return [pscustomobject]$policy
        }
        $data = $raw | ConvertFrom-Json
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
        $policy.enabled = ($min -gt 0 -or $needHttp)
        $policy.min_unique_sources_for_changes = if ($min -lt 0) { 0 } else { $min }
        $policy.require_http_source_for_changes = $needHttp
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
    return [pscustomobject]([ordered]@{
        pass = ($issues.Count -eq 0)
        issues = @($issues)
        coverage = $coverage
    })
}

function Get-AuditDecisionQualityPolicy([string]$recommendationDir) {
    $path = Join-Path $recommendationDir "source-strategy.json"
    $policy = [ordered]@{
        enabled = $false
        source_strategy_path = $path
        mode = "target-repo"
        require_keyword_trace_for_changes = $false
        require_keyword_trace_membership = $false
        min_user_profile_keywords_per_change = 0
        min_target_repo_keywords_per_change = 0
        min_installed_state_keywords_per_change = 0
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]$policy
    }
    try {
        $raw = Get-ContentUtf8 $path
        if ([string]::IsNullOrWhiteSpace($raw)) { return [pscustomobject]$policy }
        $data = $raw | ConvertFrom-Json
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
        if ($q.PSObject.Properties.Match("min_user_profile_keywords_per_change").Count -gt 0) {
            $policy.min_user_profile_keywords_per_change = [Math]::Max(0, [int]$q.min_user_profile_keywords_per_change)
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
            [int]$policy.min_user_profile_keywords_per_change -gt 0 -or
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
    $path = Join-Path $recommendationDir "decision-insights.json"
    $result = [ordered]@{
        exists = $false
        path = $path
        mode = "target-repo"
        keywords = [ordered]@{
            user_profile = @()
            target_repo = @()
            profile_only_context = @()
            installed_state = @()
        }
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]$result
    }
    try {
        $raw = Get-ContentUtf8 $path
        if ([string]::IsNullOrWhiteSpace($raw)) { return [pscustomobject]$result }
        $data = $raw | ConvertFrom-Json
        $result.exists = $true
        if ($data.PSObject.Properties.Match("mode").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$data.mode)) {
            $result.mode = ([string]$data.mode).Trim().ToLowerInvariant()
        }
        if ($data.PSObject.Properties.Match("keywords").Count -gt 0 -and $null -ne $data.keywords) {
            foreach ($field in @("user_profile", "target_repo", "profile_only_context", "installed_state")) {
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
        user_keyword_ref_count = 0
        target_keyword_ref_count = 0
        installed_keyword_ref_count = 0
        unique_user_keywords = @()
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
    $requiredUser = [int]$policy.min_user_profile_keywords_per_change
    $requiredTarget = [int]$policy.min_target_repo_keywords_per_change
    $requiredInstalled = [int]$policy.min_installed_state_keywords_per_change
    if ([bool]$policy.require_keyword_trace_for_changes) {
        if ($requiredUser -lt 1) { $requiredUser = 1 }
        if ($requiredTarget -lt 1) { $requiredTarget = 1 }
        if ($requiredInstalled -lt 1) { $requiredInstalled = 1 }
    }

    $userSet = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $targetSet = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $installedSet = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($token in @(Normalize-AuditStringArray $decisionInsights.keywords.user_profile)) { $null = $userSet.Add($token) }
    $targetTokens = if ($recommendationMode -eq "profile-only") { @(Normalize-AuditStringArray $decisionInsights.keywords.profile_only_context) } else { @(Normalize-AuditStringArray $decisionInsights.keywords.target_repo) }
    foreach ($token in @($targetTokens)) { $null = $targetSet.Add($token) }
    foreach ($token in @(Normalize-AuditStringArray $decisionInsights.keywords.installed_state)) { $null = $installedSet.Add($token) }
    if ([bool]$policy.require_keyword_trace_membership -and -not [bool]$decisionInsights.exists) {
        $issues.Add("insufficient_decision_quality：decision-insights.json 缺失或不可读，无法校验 keyword_trace 归属。") | Out-Null
    }

    $uniqueUser = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
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
            $userRefs = @()
            $targetRefs = @()
            $installedRefs = @()
            if ($null -ne $trace) {
                if ($trace.PSObject.Properties.Match("user_profile").Count -gt 0) { $userRefs = @(Normalize-AuditStringArray $trace.user_profile) }
                if ($trace.PSObject.Properties.Match("target_repo_or_context").Count -gt 0) { $targetRefs = @(Normalize-AuditStringArray $trace.target_repo_or_context) }
                if ($trace.PSObject.Properties.Match("installed_state").Count -gt 0) { $installedRefs = @(Normalize-AuditStringArray $trace.installed_state) }
            }

            if (@($userRefs).Count -gt 0 -and @($targetRefs).Count -gt 0 -and @($installedRefs).Count -gt 0) {
                $coverage.items_with_complete_keyword_trace = [int]$coverage.items_with_complete_keyword_trace + 1
            }
            $coverage.user_keyword_ref_count = [int]$coverage.user_keyword_ref_count + @($userRefs).Count
            $coverage.target_keyword_ref_count = [int]$coverage.target_keyword_ref_count + @($targetRefs).Count
            $coverage.installed_keyword_ref_count = [int]$coverage.installed_keyword_ref_count + @($installedRefs).Count

            foreach ($token in @($userRefs)) { $null = $uniqueUser.Add($token) }
            foreach ($token in @($targetRefs)) { $null = $uniqueTarget.Add($token) }
            foreach ($token in @($installedRefs)) { $null = $uniqueInstalled.Add($token) }

            if ($requiredUser -gt 0 -and @($userRefs).Count -lt $requiredUser) {
                $issues.Add(("insufficient_decision_quality：{0} `{1}` 的 keyword_trace.user_profile 数量为 {2}，低于阈值 {3}。" -f [string]$group.kind, [string]$item.name, @($userRefs).Count, $requiredUser)) | Out-Null
            }
            if ($requiredTarget -gt 0 -and @($targetRefs).Count -lt $requiredTarget) {
                $issues.Add(("insufficient_decision_quality：{0} `{1}` 的 keyword_trace.target_repo_or_context 数量为 {2}，低于阈值 {3}。" -f [string]$group.kind, [string]$item.name, @($targetRefs).Count, $requiredTarget)) | Out-Null
            }
            if ($requiredInstalled -gt 0 -and @($installedRefs).Count -lt $requiredInstalled) {
                $issues.Add(("insufficient_decision_quality：{0} `{1}` 的 keyword_trace.installed_state 数量为 {2}，低于阈值 {3}。" -f [string]$group.kind, [string]$item.name, @($installedRefs).Count, $requiredInstalled)) | Out-Null
            }

            if ([bool]$policy.require_keyword_trace_membership -and [bool]$decisionInsights.exists) {
                $unknownUser = @($userRefs | Where-Object { -not $userSet.Contains([string]$_) })
                if (@($unknownUser).Count -gt 0) {
                    $issues.Add(("insufficient_decision_quality：{0} `{1}` 的 keyword_trace.user_profile 包含未知关键词：{2}" -f [string]$group.kind, [string]$item.name, (@($unknownUser | Select-Object -First 3) -join ", "))) | Out-Null
                }
                $unknownTarget = @($targetRefs | Where-Object { -not $targetSet.Contains([string]$_) })
                if (@($unknownTarget).Count -gt 0) {
                    $issues.Add(("insufficient_decision_quality：{0} `{1}` 的 keyword_trace.target_repo_or_context 包含未知关键词：{2}" -f [string]$group.kind, [string]$item.name, (@($unknownTarget | Select-Object -First 3) -join ", "))) | Out-Null
                }
                $unknownInstalled = @($installedRefs | Where-Object { -not $installedSet.Contains([string]$_) })
                if (@($unknownInstalled).Count -gt 0) {
                    $issues.Add(("insufficient_decision_quality：{0} `{1}` 的 keyword_trace.installed_state 包含未知关键词：{2}" -f [string]$group.kind, [string]$item.name, (@($unknownInstalled | Select-Object -First 3) -join ", "))) | Out-Null
                }
            }
        }
    }
    $coverage.unique_user_keywords = @($uniqueUser | Sort-Object)
    $coverage.unique_target_keywords = @($uniqueTarget | Sort-Object)
    $coverage.unique_installed_keywords = @($uniqueInstalled | Sort-Object)
    return [pscustomobject]([ordered]@{
            pass = ($issues.Count -eq 0)
            issues = @($issues)
            coverage = [pscustomobject]$coverage
        })
}

function Write-AuditRuntimeEvidence([string]$mode, [string]$recommendationsPath, $report, [string[]]$commands = @()) {
    try {
        $date = Get-Date -Format "yyyyMMdd"
        $time = Get-Date -Format "HHmmss"
        $dir = Join-Path $script:Root "docs\change-evidence"
        EnsureDir $dir
        $safeMode = if ([string]::IsNullOrWhiteSpace($mode)) { "unknown" } else { ([regex]::Replace($mode.ToLowerInvariant(), "[^a-z0-9_-]", "-")) }
        $runId = if ($null -ne $report -and $report.PSObject.Properties.Match("run_id").Count -gt 0) { [string]$report.run_id } else { "" }
        $safeRun = if ([string]::IsNullOrWhiteSpace($runId)) { "no-runid" } else { ([regex]::Replace($runId, "[^a-zA-Z0-9_-]", "-")) }
        $path = Join-Path $dir ("{0}-audit-runtime-{1}-{2}-{3}.md" -f $date, $safeMode, $safeRun, $time)
        $changedCountsJson = if ($null -ne $report -and $report.PSObject.Properties.Match("changed_counts").Count -gt 0) { ($report.changed_counts | ConvertTo-Json -Depth 10 -Compress) } else { "{}" }
        $rollbackText = if ($null -ne $report -and $report.PSObject.Properties.Match("rollback").Count -gt 0 -and @($report.rollback).Count -gt 0) {
            (@($report.rollback) | ForEach-Object { "- " + [string]$_ }) -join "`r`n"
        }
        else {
            "- 无"
        }
        $commandText = if (@($commands).Count -gt 0) { (@($commands) | ForEach-Object { "- `"$_`"" }) -join "`r`n" } else { "- 无" }
        $content = @"
# Audit Runtime Evidence

- mode: $mode
- run_id: $runId
- recommendations: $recommendationsPath
- success: $([bool]$report.success)
- persisted: $([bool]$report.persisted)
- timestamp: $(Get-Date -Format "o")

## Commands
$commandText

## Key Output
- changed_counts: $changedCountsJson

## Rollback
$rollbackText
"@
        Set-ContentUtf8 $path $content
        return $path
    }
    catch {
        Log ("写入审查运行证据失败：{0}" -f $_.Exception.Message) "WARN"
        return ""
    }
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
    SaveCfgSafe $cfg $cfgRaw
    同步MCP
    return [pscustomobject]@{ changed = $true }
}

function Resolve-AuditRecommendationsPathForPreflight([string]$RecommendationsPath, [string]$RunId) {
    if (-not [string]::IsNullOrWhiteSpace($RecommendationsPath)) {
        $resolvedInputPath = Resolve-AuditPathRunIdPlaceholder $RecommendationsPath "--recommendations" @("recommendations.json", "installed-skills.json", "audit-meta.json")
        return (Resolve-AuditTargetPath $resolvedInputPath)
    }
    Need (-not [string]::IsNullOrWhiteSpace($RunId)) "预检至少需要 --run-id 或 --recommendations 其一"
    $resolvedRunId = Resolve-AuditRunIdInput $RunId "--run-id" @("recommendations.json", "installed-skills.json", "audit-meta.json")
    return (Join-Path (Get-AuditReportRoot $resolvedRunId) "recommendations.json")
}

function Get-AuditRunPromptContractVersion([string]$recommendationDir) {
    $metaPath = Join-Path $recommendationDir "audit-meta.json"
    if (Test-Path -LiteralPath $metaPath -PathType Leaf) {
        try {
            $metaRaw = Get-ContentUtf8 $metaPath
            if (-not [string]::IsNullOrWhiteSpace($metaRaw)) {
                $meta = $metaRaw | ConvertFrom-Json
                if ($meta.PSObject.Properties.Match("prompt_contract_version").Count -gt 0) {
                    $version = ([string]$meta.prompt_contract_version).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($version)) {
                        return $version
                    }
                }
            }
        }
        catch {
            # Fallback to outer-ai-prompt.md parser
        }
    }
    $promptPath = Join-Path $recommendationDir "outer-ai-prompt.md"
    if (Test-Path -LiteralPath $promptPath -PathType Leaf) {
        $promptRaw = Get-ContentUtf8 $promptPath
        if (-not [string]::IsNullOrWhiteSpace($promptRaw)) {
            $match = [regex]::Match($promptRaw, "(?m)^\s*Prompt-Contract-Version:\s*(?<version>\S+)\s*$")
            if ($match.Success) {
                return ([string]$match.Groups["version"].Value).Trim()
            }
        }
    }
    return ""
}

function Test-AuditUserProfilePreflight([string]$recommendationDir) {
    $path = Join-Path $recommendationDir "user-profile.json"
    $issues = New-Object System.Collections.Generic.List[string]
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    if (-not $exists) {
        return [pscustomobject]@{
            path = $path
            exists = $false
            ok = $true
            skipped = $true
            skipped_reason = "missing_optional_user_profile"
            issues = @($issues)
        }
    }

    try {
        Assert-AuditBundleFileContent $path "user-profile.json"
    }
    catch {
        $issues.Add([string]$_.Exception.Message) | Out-Null
    }
    return [pscustomobject]@{
        path = $path
        exists = $true
        ok = ($issues.Count -eq 0)
        skipped = $false
        skipped_reason = ""
        issues = @($issues)
    }
}

function Invoke-AuditRecommendationsPreflight {
    param(
        [string]$RecommendationsPath,
        [string]$RunId
    )
    $resolvedRecommendations = Resolve-AuditRecommendationsPathForPreflight $RecommendationsPath $RunId
    $rec = Load-AuditRecommendations $resolvedRecommendations
    $recommendationDir = Split-Path -Parent $resolvedRecommendations
    if ([string]::IsNullOrWhiteSpace($recommendationDir)) { $recommendationDir = "." }
    $snapshotPath = Join-Path $recommendationDir "installed-skills.json"
    $liveState = Get-AuditLiveInstalledState
    if (Test-Path -LiteralPath $snapshotPath -PathType Leaf) {
        $snapshotState = Get-AuditInstalledSnapshotState $snapshotPath
    }
    else {
        $snapshotState = New-AuditInstalledSnapshotFallbackState $liveState $snapshotPath
    }
    $skillSnapshotStale = ([string]$snapshotState.fingerprint -ne [string]$liveState.fingerprint)
    $mcpSnapshotStale = $false
    if ($snapshotState.PSObject.Properties.Match("mcp_fingerprint").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$snapshotState.mcp_fingerprint)) {
        $mcpSnapshotStale = ([string]$snapshotState.mcp_fingerprint -ne [string]$liveState.mcp_fingerprint)
    }
    $isSnapshotStale = ($skillSnapshotStale -or $mcpSnapshotStale)

    $runPromptVersion = Get-AuditRunPromptContractVersion $recommendationDir
    $currentPromptVersion = Get-AuditPromptContractVersion
    $promptVersionMatched = (-not [string]::IsNullOrWhiteSpace($runPromptVersion) -and [string]$runPromptVersion -eq [string]$currentPromptVersion)
    $sourcePolicy = Get-AuditSourceEvidencePolicy $recommendationDir
    $sourceCoverageCheck = Test-AuditRecommendationSourceCoveragePolicy $rec $sourcePolicy
    $decisionQualityPolicy = Get-AuditDecisionQualityPolicy $recommendationDir
    $decisionInsights = Get-AuditDecisionInsights $recommendationDir
    $decisionQualityCheck = Test-AuditRecommendationDecisionQualityPolicy $rec $decisionQualityPolicy $decisionInsights
    $userProfileCheck = Test-AuditUserProfilePreflight $recommendationDir

    $issues = New-Object System.Collections.Generic.List[string]
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
    foreach ($issue in @($userProfileCheck.issues)) {
        $issues.Add(("user_profile_invalid：{0}" -f [string]$issue)) | Out-Null
    }

    $report = [ordered]@{
        schema_version = 1
        run_id = [string]$rec.run_id
        target = [string]$rec.target
        success = ($issues.Count -eq 0)
        recommendations_path = $resolvedRecommendations
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
        user_profile_check = $userProfileCheck
        snapshot_state = $snapshotState
        live_state = $liveState
        issues = @($issues)
    }
    $reportPath = Join-Path $recommendationDir "preflight-report.json"
    Write-AuditJsonFile $reportPath ([pscustomobject]$report)

    Write-Host ("预检报告：{0}" -f $reportPath) -ForegroundColor Cyan
    if ($issues.Count -eq 0) {
        Write-Host "预检通过：快照与提示词契约均匹配，可继续研究与 dry-run。" -ForegroundColor Green
        return [pscustomobject]$report
    }

    foreach ($issue in @($issues)) {
        Write-Host ("- {0}" -f [string]$issue) -ForegroundColor Red
    }
    throw ("预检失败：{0}" -f ($issues -join " | "))
}

function Invoke-AuditRecommendationsApply {
    param(
        [string]$RecommendationsPath,
        [string]$AddSelection,
        [string]$RemoveSelection,
        [string]$McpAddSelection,
        [string]$McpRemoveSelection,
        [string]$DryRunAck,
        [string]$StaleAck,
        [switch]$AllowStaleSnapshot,
        [bool]$RequireDryRunAck = $true,
        [switch]$Apply,
        [switch]$Yes
    )
    if ($Apply -and -not $Yes) {
        throw "执行安装必须同时传入 --apply --yes"
    }
    $rec = Load-AuditRecommendations $RecommendationsPath
    $recommendationDir = Split-Path -Parent $RecommendationsPath
    if ([string]::IsNullOrWhiteSpace($recommendationDir)) { $recommendationDir = "." }
    $sourcePolicy = Get-AuditSourceEvidencePolicy $recommendationDir
    $sourceCoverageCheck = Test-AuditRecommendationSourceCoveragePolicy $rec $sourcePolicy
    $decisionQualityPolicy = Get-AuditDecisionQualityPolicy $recommendationDir
    $decisionInsights = Get-AuditDecisionInsights $recommendationDir
    $decisionQualityCheck = Test-AuditRecommendationDecisionQualityPolicy $rec $decisionQualityPolicy $decisionInsights
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
            rollback = @()
        }
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$sourceReport)
        $evidenceMode = if ($Apply) { "apply-blocked" } else { "dry-run-blocked" }
        $evidencePath = Write-AuditRuntimeEvidence $evidenceMode $RecommendationsPath ([pscustomobject]$sourceReport) @(".\\skills.ps1 审查目标 应用 --recommendations `"$RecommendationsPath`"")
        if (-not [string]::IsNullOrWhiteSpace($evidencePath)) {
            Write-Host ("审查运行证据：{0}" -f $evidencePath) -ForegroundColor Cyan
        }
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
            rollback = @()
        }
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$qualityReport)
        $evidenceMode = if ($Apply) { "apply-blocked" } else { "dry-run-blocked" }
        $evidencePath = Write-AuditRuntimeEvidence $evidenceMode $RecommendationsPath ([pscustomobject]$qualityReport) @(".\\skills.ps1 审查目标 应用 --recommendations `"$RecommendationsPath`"")
        if (-not [string]::IsNullOrWhiteSpace($evidencePath)) {
            Write-Host ("审查运行证据：{0}" -f $evidencePath) -ForegroundColor Cyan
        }
        throw $qualityMessage
    }
    $snapshotPath = Join-Path $recommendationDir "installed-skills.json"
    $liveState = Get-AuditLiveInstalledState
    if (Test-Path -LiteralPath $snapshotPath -PathType Leaf) {
        $snapshotState = Get-AuditInstalledSnapshotState $snapshotPath
    }
    else {
        Log ("recommendations 同目录缺少 installed-skills.json，已回退为 live state 快照：{0}" -f $snapshotPath) "WARN"
        $snapshotState = New-AuditInstalledSnapshotFallbackState $liveState $snapshotPath
    }
    $skillSnapshotStale = ([string]$snapshotState.fingerprint -ne [string]$liveState.fingerprint)
    $mcpSnapshotStale = $false
    if ($snapshotState.PSObject.Properties.Match("mcp_fingerprint").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$snapshotState.mcp_fingerprint)) {
        $mcpSnapshotStale = ([string]$snapshotState.mcp_fingerprint -ne [string]$liveState.mcp_fingerprint)
    }
    $isSnapshotStale = ($skillSnapshotStale -or $mcpSnapshotStale)
    if ($isSnapshotStale -and -not $AllowStaleSnapshot) {
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
            changed_counts = New-AuditChangedCounts @() @()
            items = @()
            removal_candidates = @()
            mcp_items = @()
            mcp_removal_candidates = @()
            overlap_findings = @()
            do_not_install = @()
            rollback = @()
        }
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$staleReport)
        throw $staleMessage
    }
    if ($isSnapshotStale -and $AllowStaleSnapshot) {
        $staleAckToken = Get-AuditStaleSnapshotAckToken ([string]$rec.run_id)
        Write-Host ""
        Write-Host "WARNING: 当前正在使用过期审查快照（stale_snapshot）继续执行。" -ForegroundColor Red
        Write-Host ("WARNING: live={0}, snapshot={1}" -f [int]$liveState.skill_count, [int]$snapshotState.skill_count) -ForegroundColor Red
        if ($liveState.PSObject.Properties.Match("mcp_server_count").Count -gt 0 -or $snapshotState.PSObject.Properties.Match("mcp_server_count").Count -gt 0) {
            $liveMcp = if ($liveState.PSObject.Properties.Match("mcp_server_count").Count -gt 0) { [int]$liveState.mcp_server_count } else { 0 }
            $snapshotMcp = if ($snapshotState.PSObject.Properties.Match("mcp_server_count").Count -gt 0) { [int]$snapshotState.mcp_server_count } else { 0 }
            Write-Host ("WARNING: mcp live={0}, snapshot={1}" -f $liveMcp, $snapshotMcp) -ForegroundColor Red
        }
        $staleAckInput = ""
        if (-not [string]::IsNullOrWhiteSpace($StaleAck)) {
            $staleAckInput = [string]$StaleAck
        }
        elseif (-not [Console]::IsInputRedirected) {
            $staleAckInput = Read-HostSafe ("请输入二次确认口令 `"{0}`"（回车取消）" -f $staleAckToken)
        }
        else {
            $hint = ("当前为非交互环境。请追加参数：--stale-ack `"{0}`"" -f $staleAckToken)
            $staleReport = [ordered]@{
                schema_version = 2
                run_id = [string]$rec.run_id
                target = [string]$rec.target
                mode = if ($Apply) { "apply" } else { "dry_run" }
                success = $false
                persisted = $false
                error_code = "stale_snapshot_ack_required"
                error_message = $hint
                source_evidence_policy = $sourcePolicy
                source_coverage = $sourceCoverageCheck.coverage
                decision_quality_policy = $decisionQualityPolicy
                decision_quality = $decisionQualityCheck.coverage
                decision_insights = $decisionInsights
                snapshot_state = $snapshotState
                live_state = $liveState
                changed_counts = New-AuditChangedCounts @() @()
                items = @()
                removal_candidates = @()
                mcp_items = @()
                mcp_removal_candidates = @()
                overlap_findings = @()
                do_not_install = @()
                rollback = @()
                allow_stale_snapshot = $true
                stale_snapshot_detected = $true
                stale_acknowledged = $false
                stale_ack_expected = $staleAckToken
                stale_ack_received = ""
            }
            Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$staleReport)
            throw $hint
        }
        if ([string]::IsNullOrWhiteSpace($staleAckInput) -or $staleAckInput.Trim() -ne $staleAckToken) {
            $staleReport = [ordered]@{
                schema_version = 2
                run_id = [string]$rec.run_id
                target = [string]$rec.target
                mode = if ($Apply) { "apply" } else { "dry_run" }
                success = $false
                persisted = $false
                error_code = "stale_snapshot_ack_mismatch"
                error_message = "二次确认口令不匹配，已取消执行。"
                source_evidence_policy = $sourcePolicy
                source_coverage = $sourceCoverageCheck.coverage
                decision_quality_policy = $decisionQualityPolicy
                decision_quality = $decisionQualityCheck.coverage
                decision_insights = $decisionInsights
                snapshot_state = $snapshotState
                live_state = $liveState
                changed_counts = New-AuditChangedCounts @() @()
                items = @()
                removal_candidates = @()
                mcp_items = @()
                mcp_removal_candidates = @()
                overlap_findings = @()
                do_not_install = @()
                rollback = @()
                allow_stale_snapshot = $true
                stale_snapshot_detected = $true
                stale_acknowledged = $false
                stale_ack_expected = $staleAckToken
                stale_ack_received = [string]$staleAckInput
            }
            Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$staleReport)
            throw "二次确认失败：未通过过期快照确认。"
        }
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
        allow_stale_snapshot = [bool]$AllowStaleSnapshot
        stale_snapshot_detected = [bool]$isSnapshotStale
        stale_acknowledged = if ($isSnapshotStale -and $AllowStaleSnapshot) { $true } else { $false }
        changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
        snapshot_state = $snapshotState
        live_state = $liveState
        items = @($plan.items)
        removal_candidates = @($plan.removal_candidates)
        mcp_items = @($plan.mcp_items)
        mcp_removal_candidates = @($plan.mcp_removal_candidates)
        overlap_findings = @($plan.overlap_findings)
        do_not_install = @($plan.do_not_install)
        rollback = @()
    }

    Write-AuditRecommendationSummary $plan $snapshotState $liveState

    if (-not $Apply) {
        Write-Host "dry-run 预览（沿用原序号）："
        foreach ($item in @($plan.items)) {
            Write-Host ("DRYRUN install: {0}" -f ($item.tokens -join " "))
        }
        foreach ($item in @($plan.removal_candidates)) {
            Write-Host ("DRYRUN remove: [{0}|{1}] {2}" -f [string]$item.vendor, [string]$item.from, [string]$item.name)
        }
        foreach ($item in @($plan.mcp_items)) {
            $server = $item.server
            $transport = if ($server.PSObject.Properties.Match("transport").Count -gt 0) { [string]$server.transport } else { "stdio" }
            if ($transport -eq "stdio") {
                $argsText = if ($server.PSObject.Properties.Match("args").Count -gt 0 -and $null -ne $server.args -and @($server.args).Count -gt 0) { " " + ((@($server.args) | ForEach-Object { [string]$_ }) -join " ") } else { "" }
                Write-Host ("DRYRUN mcp-add: {0} --transport stdio --cmd {1}{2}" -f [string]$server.name, [string]$server.command, $argsText)
            }
            else {
                Write-Host ("DRYRUN mcp-add: {0} --transport {1} --url {2}" -f [string]$server.name, $transport, [string]$server.url)
            }
        }
        foreach ($item in @($plan.mcp_removal_candidates)) {
            Write-Host ("DRYRUN mcp-remove: {0}" -f [string]$item.installed_name)
        }
        $dryRunSummaryPath = Get-AuditDryRunSummaryPath $RecommendationsPath
        $dryRunSummary = New-AuditDryRunSummary $plan $RecommendationsPath
        Write-AuditJsonFile $dryRunSummaryPath $dryRunSummary
        $report["dry_run_summary_path"] = $dryRunSummaryPath
        Write-Host ("dry-run 机器可读摘要：{0}" -f $dryRunSummaryPath) -ForegroundColor Cyan
        Write-Host "DRY-RUN 完成：未修改任何技能映射或 MCP 配置（未落盘）。" -ForegroundColor Red
        Write-Host ("如需真正执行，请运行：.\skills.ps1 审查目标 应用 --recommendations `"{0}`" --apply --yes" -f $RecommendationsPath) -ForegroundColor Red
        if ($RequireDryRunAck) {
            $ackToken = Get-AuditDryRunAckToken
            $ackInput = ""
            if (-not [string]::IsNullOrWhiteSpace($DryRunAck)) {
                $ackInput = [string]$DryRunAck
            }
            elseif (-not [Console]::IsInputRedirected) {
                $ackInput = Read-HostSafe ("请输入确认口令 `"{0}`" 表示你已知晓 dry-run 未落盘（回车取消）" -f $ackToken)
            }
            else {
                Write-Host ("当前为非交互环境。请追加参数：--dry-run-ack `"{0}`"" -f $ackToken) -ForegroundColor Red
            }
            if ([string]::IsNullOrWhiteSpace($ackInput) -or $ackInput.Trim() -ne $ackToken) {
                $report.success = $false
                $report["canceled"] = $true
                $report["dry_run_acknowledged"] = $false
                $report["dry_run_ack_expected"] = $ackToken
                $report["dry_run_ack_received"] = [string]$ackInput
                $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
                Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
                $evidencePath = Write-AuditRuntimeEvidence "dry-run-canceled" $RecommendationsPath ([pscustomobject]$report) @(".\\skills.ps1 审查目标 应用 --recommendations `"$RecommendationsPath`"")
                if (-not [string]::IsNullOrWhiteSpace($evidencePath)) {
                    Write-Host ("审查运行证据：{0}" -f $evidencePath) -ForegroundColor Cyan
                }
                return [pscustomobject]$report
            }
            $report["dry_run_acknowledged"] = $true
        }
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
        $evidencePath = Write-AuditRuntimeEvidence "dry-run" $RecommendationsPath ([pscustomobject]$report) @(".\\skills.ps1 审查目标 应用 --recommendations `"$RecommendationsPath`" --dry-run-ack `"$([string]$DryRunAck)`"")
        if (-not [string]::IsNullOrWhiteSpace($evidencePath)) {
            Write-Host ("审查运行证据：{0}" -f $evidencePath) -ForegroundColor Cyan
        }
        return [pscustomobject]$report
    }

    $selectedAdd = Resolve-AuditSelection $AddSelection $plan.items "请输入要安装的新增建议序号（空=跳过，0=取消）" "新增建议序号无效"
    if ($selectedAdd.canceled) {
        $report.success = $false
        $report["canceled"] = $true
        $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
        $report.persisted = $false
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
        return [pscustomobject]$report
    }
    $selectedRemove = Resolve-AuditSelection $RemoveSelection @($plan.removal_candidates | Where-Object { $_.status -eq "planned" }) "请输入要卸载的建议序号（空=跳过，0=取消）" "卸载建议序号无效"
    if ($selectedRemove.canceled) {
        $report.success = $false
        $report["canceled"] = $true
        $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
        $report.persisted = $false
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
        return [pscustomobject]$report
    }
    $selectedMcpAdd = Resolve-AuditSelection $McpAddSelection @($plan.mcp_items | Where-Object { $_.status -eq "planned" }) "请输入要新增的 MCP 建议序号（空=跳过，0=取消）" "MCP 新增建议序号无效"
    if ($selectedMcpAdd.canceled) {
        $report.success = $false
        $report["canceled"] = $true
        $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
        $report.persisted = $false
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
        return [pscustomobject]$report
    }
    $selectedMcpRemove = Resolve-AuditSelection $McpRemoveSelection @($plan.mcp_removal_candidates | Where-Object { $_.status -eq "planned" }) "请输入要卸载的 MCP 建议序号（空=跳过，0=取消）" "MCP 卸载建议序号无效"
    if ($selectedMcpRemove.canceled) {
        $report.success = $false
        $report["canceled"] = $true
        $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
        $report.persisted = $false
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
        return [pscustomobject]$report
    }

    try {
        foreach ($item in @($selectedAdd.items)) {
            $commandText = ".\skills.ps1 add {0}" -f ($item.tokens -join " ")
            try {
                Write-Host ("Installing recommended skill: {0}" -f $item.name) -ForegroundColor Cyan
                $beforeCfg = LoadCfg
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
                Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
                throw
            }
        }

        if (@($selectedRemove.items).Count -gt 0) {
            Remove-AuditSelectedInstalledSkills $selectedRemove.items | Out-Null
            foreach ($item in @($selectedRemove.items)) {
                $report.rollback += ("Re-add removed skill mapping/import for '{0}' if rollback is required." -f $item.name)
            }
        }

        if (@($selectedMcpAdd.items).Count -gt 0 -or @($selectedMcpRemove.items).Count -gt 0) {
            try {
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
                Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
                throw
            }
        }

        $hasSkillChanges = (@($selectedAdd.items).Count -gt 0 -or @($selectedRemove.items).Count -gt 0)
        $hasMcpChanges = (@($selectedMcpAdd.items).Count -gt 0 -or @($selectedMcpRemove.items).Count -gt 0)

        if ($hasSkillChanges) {
            构建生效
        }
        if ($hasSkillChanges -or $hasMcpChanges) {
            $doctorResult = Invoke-Doctor @("--strict", "--threshold-ms", "8000")
            if ($doctorResult -and $doctorResult.PSObject.Properties.Match("pass").Count -gt 0 -and -not [bool]$doctorResult.pass) {
                $report.success = $false
                $report.items = @($plan.items)
                $report.removal_candidates = @($plan.removal_candidates)
                $report.mcp_items = @($plan.mcp_items)
                $report.mcp_removal_candidates = @($plan.mcp_removal_candidates)
                $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
                $report.persisted = ((Get-AuditPersistedChangeTotal $report.changed_counts) -gt 0)
                Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
                throw "doctor --strict failed after applying recommendations"
            }
        }

        $report.items = @($plan.items)
        $report.removal_candidates = @($plan.removal_candidates)
        $report.mcp_items = @($plan.mcp_items)
        $report.mcp_removal_candidates = @($plan.mcp_removal_candidates)
        $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
        $report.persisted = ((Get-AuditPersistedChangeTotal $report.changed_counts) -gt 0)
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
        $evidencePath = Write-AuditRuntimeEvidence "apply" $RecommendationsPath ([pscustomobject]$report) @(".\\skills.ps1 审查目标 应用 --recommendations `"$RecommendationsPath`" --apply --yes")
        if (-not [string]::IsNullOrWhiteSpace($evidencePath)) {
            Write-Host ("审查运行证据：{0}" -f $evidencePath) -ForegroundColor Cyan
        }
        return [pscustomobject]$report
    }
    catch {
        if ($report.success) { $report.success = $false }
        $report.items = @($plan.items)
        $report.removal_candidates = @($plan.removal_candidates)
        $report.mcp_items = @($plan.mcp_items)
        $report.mcp_removal_candidates = @($plan.mcp_removal_candidates)
        $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates $plan.mcp_items $plan.mcp_removal_candidates
        $report.persisted = ((Get-AuditPersistedChangeTotal $report.changed_counts) -gt 0)
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
        $evidencePath = Write-AuditRuntimeEvidence "apply-failed" $RecommendationsPath ([pscustomobject]$report) @(".\\skills.ps1 审查目标 应用 --recommendations `"$RecommendationsPath`" --apply --yes")
        if (-not [string]::IsNullOrWhiteSpace($evidencePath)) {
            Write-Host ("审查运行证据：{0}" -f $evidencePath) -ForegroundColor Cyan
        }
        throw
    }
}

function Get-AuditApplyConfirmationToken([string]$runId) {
    if ([string]::IsNullOrWhiteSpace($runId)) { return "APPLY" }
    return ("APPLY {0}" -f $runId)
}

function Get-AuditDryRunAckToken {
    return "我知道未落盘"
}

function Get-AuditStaleSnapshotAckToken([string]$runId) {
    if ([string]::IsNullOrWhiteSpace($runId)) { return "我确认使用过期快照" }
    return ("我确认使用过期快照 {0}" -f $runId)
}

function Invoke-AuditRecommendationsTwoStageApply {
    param(
        [string]$RecommendationsPath,
        [string]$AddSelection,
        [string]$RemoveSelection,
        [string]$McpAddSelection,
        [string]$McpRemoveSelection,
        [string]$DryRunAck,
        [string]$StaleAck,
        [switch]$AllowStaleSnapshot
    )
    $dryRunReport = Invoke-AuditRecommendationsApply -RecommendationsPath $RecommendationsPath -AddSelection $AddSelection -RemoveSelection $RemoveSelection -McpAddSelection $McpAddSelection -McpRemoveSelection $McpRemoveSelection -DryRunAck $DryRunAck -StaleAck $StaleAck -AllowStaleSnapshot:$AllowStaleSnapshot -RequireDryRunAck $true
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
    return (Invoke-AuditRecommendationsApply -RecommendationsPath $RecommendationsPath -AddSelection $AddSelection -RemoveSelection $RemoveSelection -McpAddSelection $McpAddSelection -McpRemoveSelection $McpRemoveSelection -StaleAck $StaleAck -AllowStaleSnapshot:$AllowStaleSnapshot -Apply -Yes)
}

function Get-AuditLatestApplyReportPath {
    $auditRoot = Join-Path $script:Root "reports\skill-audit"
    if (-not (Test-Path -LiteralPath $auditRoot -PathType Container)) { return $null }
    $candidates = @(Get-ChildItem -Path $auditRoot -Recurse -File -Filter "apply-report.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($candidates.Count -eq 0) { return $null }
    return [string]$candidates[0].FullName
}

function Show-AuditLatestStatus {
    $path = Get-AuditLatestApplyReportPath
    if ([string]::IsNullOrWhiteSpace($path)) {
        Write-Host "未找到 apply-report.json。请先执行：审查目标 应用确认 或 审查目标 应用。" -ForegroundColor Yellow
        return
    }
    try {
        $raw = Get-ContentUtf8 $path
        Need (-not [string]::IsNullOrWhiteSpace($raw)) ("状态文件为空：{0}" -f $path)
        $report = $raw | ConvertFrom-Json
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
