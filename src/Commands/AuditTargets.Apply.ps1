function Invoke-AuditRecommendationsApply {
    param(
        [string]$RecommendationsPath,
        [string]$AddSelection,
        [string]$RemoveSelection,
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
    $snapshotPath = Join-Path $recommendationDir "installed-skills.json"
    $liveState = Get-AuditLiveInstalledState
    if (Test-Path -LiteralPath $snapshotPath -PathType Leaf) {
        $snapshotState = Get-AuditInstalledSnapshotState $snapshotPath
    }
    else {
        Log ("recommendations 同目录缺少 installed-skills.json，已回退为 live state 快照：{0}" -f $snapshotPath) "WARN"
        $snapshotState = New-AuditInstalledSnapshotFallbackState $liveState $snapshotPath
    }
    $isSnapshotStale = ([string]$snapshotState.fingerprint -ne [string]$liveState.fingerprint)
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
            snapshot_state = $snapshotState
            live_state = $liveState
            changed_counts = New-AuditChangedCounts @() @()
            items = @()
            removal_candidates = @()
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
                snapshot_state = $snapshotState
                live_state = $liveState
                changed_counts = New-AuditChangedCounts @() @()
                items = @()
                removal_candidates = @()
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
                snapshot_state = $snapshotState
                live_state = $liveState
                changed_counts = New-AuditChangedCounts @() @()
                items = @()
                removal_candidates = @()
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
        allow_stale_snapshot = [bool]$AllowStaleSnapshot
        stale_snapshot_detected = [bool]$isSnapshotStale
        stale_acknowledged = if ($isSnapshotStale -and $AllowStaleSnapshot) { $true } else { $false }
        changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates
        snapshot_state = $snapshotState
        live_state = $liveState
        items = @($plan.items)
        removal_candidates = @($plan.removal_candidates)
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
        Write-Host "DRY-RUN 完成：未修改任何技能映射（未落盘）。" -ForegroundColor Red
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
                $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates
                Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
                return [pscustomobject]$report
            }
            $report["dry_run_acknowledged"] = $true
        }
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
        return [pscustomobject]$report
    }

    $selectedAdd = Resolve-AuditSelection $AddSelection $plan.items "请输入要安装的新增建议序号（空=跳过，0=取消）" "新增建议序号无效"
    if ($selectedAdd.canceled) {
        $report.success = $false
        $report["canceled"] = $true
        $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates
        $report.persisted = $false
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
        return [pscustomobject]$report
    }
    $selectedRemove = Resolve-AuditSelection $RemoveSelection @($plan.removal_candidates | Where-Object { $_.status -eq "planned" }) "请输入要卸载的建议序号（空=跳过，0=取消）" "卸载建议序号无效"
    if ($selectedRemove.canceled) {
        $report.success = $false
        $report["canceled"] = $true
        $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates
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
                $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates
                $report.persisted = (([int]$report.changed_counts.add_installed + [int]$report.changed_counts.remove_removed) -gt 0)
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

        if (@($selectedAdd.items).Count -gt 0 -or @($selectedRemove.items).Count -gt 0) {
            构建生效
            $doctorResult = Invoke-Doctor @("--strict", "--threshold-ms", "8000")
            if ($doctorResult -and $doctorResult.PSObject.Properties.Match("pass").Count -gt 0 -and -not [bool]$doctorResult.pass) {
                $report.success = $false
                $report.items = @($plan.items)
                $report.removal_candidates = @($plan.removal_candidates)
                $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates
                $report.persisted = (([int]$report.changed_counts.add_installed + [int]$report.changed_counts.remove_removed) -gt 0)
                Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
                throw "doctor --strict failed after applying recommendations"
            }
        }

        $report.items = @($plan.items)
        $report.removal_candidates = @($plan.removal_candidates)
        $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates
        $report.persisted = (([int]$report.changed_counts.add_installed + [int]$report.changed_counts.remove_removed) -gt 0)
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
        return [pscustomobject]$report
    }
    catch {
        if ($report.success) { $report.success = $false }
        $report.items = @($plan.items)
        $report.removal_candidates = @($plan.removal_candidates)
        $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates
        $report.persisted = (([int]$report.changed_counts.add_installed + [int]$report.changed_counts.remove_removed) -gt 0)
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
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
        [string]$DryRunAck,
        [string]$StaleAck,
        [switch]$AllowStaleSnapshot
    )
    $dryRunReport = Invoke-AuditRecommendationsApply -RecommendationsPath $RecommendationsPath -AddSelection $AddSelection -RemoveSelection $RemoveSelection -DryRunAck $DryRunAck -StaleAck $StaleAck -AllowStaleSnapshot:$AllowStaleSnapshot -RequireDryRunAck $true
    if ($dryRunReport.PSObject.Properties.Match("success").Count -gt 0 -and -not [bool]$dryRunReport.success) {
        Write-Host "应用确认结束：dry-run 未完成确认，未执行落盘。" -ForegroundColor Yellow
        return $dryRunReport
    }
    $plannedAdds = @($dryRunReport.items | Where-Object { [string]$_.status -eq "planned" }).Count
    $plannedRemoves = @($dryRunReport.removal_candidates | Where-Object { [string]$_.status -eq "planned" }).Count
    if ($plannedAdds -eq 0 -and $plannedRemoves -eq 0) {
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
    return (Invoke-AuditRecommendationsApply -RecommendationsPath $RecommendationsPath -AddSelection $AddSelection -RemoveSelection $RemoveSelection -StaleAck $StaleAck -AllowStaleSnapshot:$AllowStaleSnapshot -Apply -Yes)
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
    }
    if ([string]$report.mode -eq "dry_run" -and -not $persisted) {
        Write-Host "警告：最近一次仅为 dry-run，未落盘。" -ForegroundColor Red
    }
}
