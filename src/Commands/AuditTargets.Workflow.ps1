function Get-AuditWorkflowReportPath([string]$recommendationsPath) {
    return (Get-AuditReceiptPath $recommendationsPath)
}

function Get-AuditWorkflowInputState([string]$recommendationsPath) {
    $dir = Split-Path $recommendationsPath -Parent
    if ([string]::IsNullOrWhiteSpace($dir)) { $dir = "." }
    $inputs = @(
        [pscustomobject]@{ name = "recommendations.json"; path = $recommendationsPath },
        [pscustomobject]@{ name = "snapshot.json"; path = (Join-Path $dir "snapshot.json") }
    )
    $files = @()
    $pairs = @()
    foreach ($input in $inputs) {
        $exists = Test-Path -LiteralPath $input.path -PathType Leaf
        $hash = if ($exists) { [string](Get-FileContentHash $input.path) } else { "" }
        $files += [pscustomobject]([ordered]@{
            name = [string]$input.name
            exists = [bool]$exists
            sha256 = $hash
        })
        $pairs += ("{0}|{1}|{2}" -f [string]$input.name, ([bool]$exists).ToString().ToLowerInvariant(), $hash)
    }
    $fileFingerprint = Get-AuditFingerprintFromVendorFromPairs $pairs $true
    $targetSnapshot = Get-AuditTargetRepoSnapshotState $dir
    $targetLive = Get-AuditTargetRepoLiveState $targetSnapshot
    $targetFingerprint = [string]$targetLive.fingerprint
    return [pscustomobject]([ordered]@{
        fingerprint = Get-AuditFingerprintFromVendorFromPairs @(("files|{0}" -f $fileFingerprint), ("targets|{0}" -f $targetFingerprint)) $true
        file_fingerprint = $fileFingerprint
        target_repo_fingerprint = $targetFingerprint
        files = @($files)
        target_repos = $targetLive
    })
}

function ConvertTo-AuditWorkflowCategoryItems($items) {
    $result = @()
    $fallbackIndex = 1
    foreach ($item in @($items)) {
        $originalIndex = if ($item.PSObject.Properties.Match("original_index").Count -gt 0) { [int]$item.original_index } else { $fallbackIndex }
        $result += [pscustomobject]([ordered]@{
            original_index = $originalIndex
            name = [string]$item.name
            reason_user_profile = [string]$item.reason_user_profile
            reason_target_repo = [string]$item.reason_target_repo
            sources = @($item.sources)
            status = [string]$item.status
        })
        $fallbackIndex++
    }
    return @($result)
}

function Get-AuditWorkflowEmptyReason($recommendations, [string]$prefix, [int]$itemCount) {
    if ($itemCount -gt 0) { return "" }
    foreach ($reason in @($recommendations.empty_recommendation_reasons)) {
        $text = [string]$reason
        if ($text.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $separator = $text.IndexOf(":")
            if ($separator -lt 0) { $separator = $text.IndexOf("：") }
            if ($separator -ge 0 -and $separator + 1 -lt $text.Length) {
                return $text.Substring($separator + 1).Trim()
            }
            return $text.Trim()
        }
    }
    return [string]$recommendations.decision_basis.summary
}

function New-AuditWorkflowCategories($dryRunReport, $recommendations) {
    $addItems = @(ConvertTo-AuditWorkflowCategoryItems $dryRunReport.items)
    $removeItems = @(ConvertTo-AuditWorkflowCategoryItems $dryRunReport.removal_candidates)
    $mcpAddItems = @(ConvertTo-AuditWorkflowCategoryItems $dryRunReport.mcp_items)
    $mcpRemoveItems = @(ConvertTo-AuditWorkflowCategoryItems $dryRunReport.mcp_removal_candidates)
    return @(
        [pscustomobject]([ordered]@{ order = 1; key = "add"; label = "新增技能"; empty_reason = Get-AuditWorkflowEmptyReason $recommendations "new_skills" $addItems.Count; items = $addItems }),
        [pscustomobject]([ordered]@{ order = 2; key = "remove"; label = "卸载技能"; empty_reason = Get-AuditWorkflowEmptyReason $recommendations "removal_candidates" $removeItems.Count; items = $removeItems }),
        [pscustomobject]([ordered]@{ order = 3; key = "mcp_add"; label = "MCP 新增"; empty_reason = Get-AuditWorkflowEmptyReason $recommendations "mcp_new_servers" $mcpAddItems.Count; items = $mcpAddItems }),
        [pscustomobject]([ordered]@{ order = 4; key = "mcp_remove"; label = "MCP 卸载"; empty_reason = Get-AuditWorkflowEmptyReason $recommendations "mcp_removal_candidates" $mcpRemoveItems.Count; items = $mcpRemoveItems })
    )
}

function Get-AuditWorkflowErrorCode([string]$stage, [string]$message) {
    foreach ($code in @(
            "recommendations_missing",
            "prompt_contract_mismatch",
            "stale_snapshot",
            "insufficient_source_coverage",
            "insufficient_decision_quality",
            "user_profile_invalid",
            "workflow_input_changed",
            "live_state_changed",
            "dry_run_not_confirmed",
            "unexpected_persistence"
            "target_repo_drift"
        )) {
        if ($message -match [regex]::Escape($code)) { return $code }
    }
    if ($stage -eq "recommendations_validation") { return "invalid_recommendations" }
    if ($stage -eq "preflight") { return "preflight_failed" }
    if ($stage -eq "input_stability") { return "workflow_input_changed" }
    return "dry_run_failed"
}

function Get-AuditWorkflowNextCommand([string]$errorCode, [string]$recommendationsPath) {
    if ($errorCode -eq "recommendations_missing") {
        return ("先读取同目录 snapshot.json 并完成 recommendations.json，再运行：.\skills.ps1 审查目标 校验预演 --recommendations `"{0}`" --dry-run-ack `"{1}`"" -f $recommendationsPath, (Get-AuditDryRunAckToken))
    }
    if ($errorCode -eq "stale_snapshot" -or $errorCode -eq "prompt_contract_mismatch" -or $errorCode -eq "live_state_changed" -or $errorCode -eq "target_repo_drift") {
        return ".\skills.ps1 审查目标 扫描"
    }
    return ("修复报告中的阻断项后重试：.\skills.ps1 审查目标 校验预演 --recommendations `"{0}`" --dry-run-ack `"{1}`"" -f $recommendationsPath, (Get-AuditDryRunAckToken))
}

function Invoke-AuditRecommendationsValidateDryRun {
    param(
        [string]$RecommendationsPath,
        [string]$RunId,
        [string]$DryRunAck
    )
    $resolvedRecommendations = Resolve-AuditRecommendationsPathForPreflight $RecommendationsPath $RunId
    $workflowPath = Get-AuditWorkflowReportPath $resolvedRecommendations
    $recommendationDir = Split-Path -Parent $resolvedRecommendations
    if ([string]::IsNullOrWhiteSpace($recommendationDir)) { $recommendationDir = "." }
    $stages = [pscustomobject]([ordered]@{
        recommendations_validation = [pscustomobject]@{ status = "not_run" }
        preflight = [pscustomobject]@{ status = "not_run" }
        dry_run = [pscustomobject]@{ status = "not_run" }
        input_stability = [pscustomobject]@{ status = "not_run" }
    })
    $report = [ordered]@{
        schema_version = 1
        workflow = "recommendations_validate_dry_run"
        generated_at = (Get-Date).ToString("o")
        run_id = ""
        target = ""
        success = $false
        persisted = $false
        failed_stage = ""
        error_code = ""
        error_message = ""
        next_command = ""
        recommendations_path = $resolvedRecommendations
        recommendations_sha256 = ""
        stages = $stages
        input_stability = [pscustomobject]([ordered]@{
            before = $null
            after_preflight = $null
            after_dry_run = $null
            preflight_matched = $false
            preflight_files_matched = $false
            preflight_target_repos_matched = $false
            live_state_matched = $false
            target_repos_matched = $false
            matched = $false
        })
        reports = [pscustomobject]([ordered]@{
            receipt = $workflowPath
        })
        changed_counts = New-AuditChangedCounts @() @()
        categories = @()
        items = @()
        removal_candidates = @()
        mcp_items = @()
        mcp_removal_candidates = @()
    }
    $currentStage = "recommendations_validation"
    try {
        if (-not (Test-Path -LiteralPath $resolvedRecommendations -PathType Leaf)) {
            throw ("recommendations_missing：recommendations.json 不存在：{0}" -f $resolvedRecommendations)
        }

        $report.input_stability.before = Get-AuditWorkflowInputState $resolvedRecommendations
        $report.recommendations_sha256 = [string](Get-FileContentHash $resolvedRecommendations)
        $rec = Load-AuditRecommendations $resolvedRecommendations
        $report.run_id = [string]$rec.run_id
        $report.target = [string]$rec.target
        $report.stages.recommendations_validation.status = "passed"

        $currentStage = "preflight"
        $preflightReport = Invoke-AuditRecommendationsPreflight -RecommendationsPath $resolvedRecommendations
        Need ([bool]$preflightReport.success) "preflight_failed：预检报告未通过"
        $report.stages.preflight.status = "passed"

        $currentStage = "input_stability"
        $report.input_stability.after_preflight = Get-AuditWorkflowInputState $resolvedRecommendations
        $report.input_stability.preflight_files_matched = ([string]$report.input_stability.before.file_fingerprint -eq [string]$report.input_stability.after_preflight.file_fingerprint)
        $report.input_stability.preflight_target_repos_matched = ([string]$report.input_stability.before.target_repo_fingerprint -eq [string]$report.input_stability.after_preflight.target_repo_fingerprint)
        $report.input_stability.preflight_matched = ([bool]$report.input_stability.preflight_files_matched -and [bool]$report.input_stability.preflight_target_repos_matched)
        if (-not [bool]$report.input_stability.preflight_target_repos_matched) {
            throw "target_repo_drift：preflight 前后目标仓 HEAD 或工作树状态发生变化，已停止 dry-run。"
        }
        if (-not [bool]$report.input_stability.preflight_matched) {
            throw "workflow_input_changed：preflight 前后审查输入发生变化，已停止 dry-run。"
        }

        $currentStage = "dry_run"
        $dryRunReport = Invoke-AuditRecommendationsApply -RecommendationsPath $resolvedRecommendations -DryRunAck $DryRunAck -RequireDryRunAck $true
        if (-not [bool]$dryRunReport.success) {
            throw "dry_run_not_confirmed：dry-run 未完成或确认口令不匹配。"
        }
        if ([bool]$dryRunReport.persisted) {
            throw "unexpected_persistence：校验预演不允许写入技能或 MCP 配置。"
        }
        $report.stages.dry_run.status = "passed"

        $currentStage = "input_stability"
        $report.input_stability.after_dry_run = Get-AuditWorkflowInputState $resolvedRecommendations
        $filesMatched = ([string]$report.input_stability.before.file_fingerprint -eq [string]$report.input_stability.after_dry_run.file_fingerprint)
        $targetReposMatched = ([string]$report.input_stability.before.target_repo_fingerprint -eq [string]$report.input_stability.after_dry_run.target_repo_fingerprint)
        $liveStaleness = Get-AuditInstalledSnapshotStaleness $preflightReport.live_state $dryRunReport.live_state
        $report.input_stability.live_state_matched = (-not [bool]$liveStaleness.is_stale)
        $report.input_stability.target_repos_matched = $targetReposMatched
        $report.input_stability.matched = ($filesMatched -and $targetReposMatched -and [bool]$report.input_stability.live_state_matched)
        if (-not $targetReposMatched) {
            throw "target_repo_drift：preflight 到 dry-run 结束期间目标仓 HEAD 或工作树状态发生变化。"
        }
        if (-not $filesMatched) {
            throw "workflow_input_changed：preflight 到 dry-run 结束期间审查输入发生变化。"
        }
        if (-not [bool]$report.input_stability.live_state_matched) {
            throw "live_state_changed：preflight 到 dry-run 期间受管技能、外部能力或 MCP 状态发生变化。"
        }
        $report.stages.input_stability.status = "passed"

        $report.success = $true
        $report.persisted = $false
        $report.failed_stage = ""
        $report.error_code = ""
        $report.error_message = ""
        $report.next_command = ""
        $report.changed_counts = $dryRunReport.changed_counts
        $report.categories = @(New-AuditWorkflowCategories $dryRunReport $rec)
        $report.items = @($dryRunReport.items)
        $report.removal_candidates = @($dryRunReport.removal_candidates)
        $report.mcp_items = @($dryRunReport.mcp_items)
        $report.mcp_removal_candidates = @($dryRunReport.mcp_removal_candidates)
        Write-AuditReceiptSection $resolvedRecommendations "workflow" ([pscustomobject]$report) | Out-Null
        Write-Host ("校验预演报告：{0}" -f $workflowPath) -ForegroundColor Cyan
        Write-Host "校验预演通过：preflight 与 dry-run 已按序完成，persisted=false。" -ForegroundColor Green
        return [pscustomobject]$report
    }
    catch {
        $message = [string]$_.Exception.Message
        $errorCode = Get-AuditWorkflowErrorCode $currentStage $message
        $report.success = $false
        $report.persisted = $false
        $report.failed_stage = $currentStage
        $report.error_code = $errorCode
        $report.error_message = $message
        $report.next_command = Get-AuditWorkflowNextCommand $errorCode $resolvedRecommendations
        if ($currentStage -eq "recommendations_validation") { $report.stages.recommendations_validation.status = "failed" }
        elseif ($currentStage -eq "preflight") { $report.stages.preflight.status = "failed" }
        elseif ($currentStage -eq "dry_run") { $report.stages.dry_run.status = "failed" }
        else { $report.stages.input_stability.status = "failed" }
        if (Test-Path -LiteralPath $recommendationDir -PathType Container) {
            Write-AuditReceiptSection $resolvedRecommendations "workflow" ([pscustomobject]$report) | Out-Null
            Write-Host ("校验预演报告：{0}" -f $workflowPath) -ForegroundColor Cyan
        }
        throw
    }
}
