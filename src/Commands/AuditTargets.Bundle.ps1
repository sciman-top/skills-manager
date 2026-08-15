function New-AuditInstalledStateSnapshot([string]$context) {
    try {
        try { $liveCfg = LoadCfg }
        catch {
            Log ("{0}读取 skills.json 失败，已回退为空安装快照：{1}" -f $context, $_.Exception.Message) "WARN"
            $liveCfg = New-AuditInstalledFactsFallbackCfg
        }
        $installedSkills = @(Get-InstalledSkillFacts $liveCfg)
        $externalSkills = @(Get-AuditExternalSkillFacts $liveCfg)
        $installedMcpServers = @(Get-AuditMcpServerFacts $liveCfg)
        $liveState = Get-AuditLiveInstalledState $liveCfg
        return [pscustomobject]([ordered]@{
            snapshot_kind = "audit_input"
            source_of_truth = "live_mappings"
            captured_at = (Get-Date).ToString("o")
            live_skill_count = [int]$liveState.skill_count
            live_fingerprint = [string]$liveState.fingerprint
            live_external_skill_count = if ($liveState.PSObject.Properties.Match('external_skill_count').Count -gt 0) { [int]$liveState.external_skill_count } else { 0 }
            live_external_skill_fingerprint = if ($liveState.PSObject.Properties.Match('external_skill_fingerprint').Count -gt 0) { [string]$liveState.external_skill_fingerprint } else { '' }
            live_mcp_server_count = if ($liveState.PSObject.Properties.Match("mcp_server_count").Count -gt 0) { [int]$liveState.mcp_server_count } else { 0 }
            live_mcp_fingerprint = if ($liveState.PSObject.Properties.Match("mcp_fingerprint").Count -gt 0) { [string]$liveState.mcp_fingerprint } else { "" }
            host_projection = if ($liveState.PSObject.Properties.Match('host_projection').Count -gt 0) { $liveState.host_projection } else { $null }
            skills = @($installedSkills)
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
    $installedState = New-AuditInstalledStateSnapshot $(if ($Mode -eq "profile-only") { "新技能发现" } else { "审查包生成时" })
    $sourceStrategy = New-AuditSourceStrategy $Mode $Query
    $decisionInsights = New-AuditDecisionInsights $Config $Scans @($installedState.skills + $installedState.external_skills) $installedState.mcp_servers $Mode
    $target = if (@($Scans).Count -eq 1) { [string]$Scans[0].target.name } elseif ($Mode -eq "profile-only") { "profile-only" } else { "*" }
    $snapshotPath = Join-Path $ReportRoot "snapshot.json"
    $recommendationsPath = Join-Path $ReportRoot "recommendations.json"
    $receiptPath = Join-Path $ReportRoot "receipt.json"
    $snapshot = [pscustomobject]([ordered]@{
        schema_version = 1
        snapshot_kind = "audit_input"
        run_id = $RunId
        mode = $Mode
        query = [string]$Query
        generated_at = (Get-Date).ToString("o")
        prompt_contract_version = Get-AuditPromptContractVersion
        user_profile = Get-AuditUserProfileOutput $Config
        installed_state = $installedState
        target_scans = @($Scans)
        source_strategy = $sourceStrategy
        decision_insights = $decisionInsights
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
    param([string]$Target, [string]$OutDir, [switch]$Force)
    $cfg = Ensure-AuditUserProfilePrecheck
    Assert-AuditUserProfileReady $cfg
    $targets = @($cfg.targets)
    if (-not [string]::IsNullOrWhiteSpace($Target)) {
        $targets = @($targets | Where-Object { $_.name -eq (Normalize-Name $Target) })
        Need ($targets.Count -gt 0) ("未找到目标仓：{0}" -f $Target)
    }
    else {
        $targets = @($targets | Where-Object { $_.PSObject.Properties.Match("enabled").Count -eq 0 -or [bool]$_.enabled })
    }
    Need ($targets.Count -gt 0) "没有可扫描的目标仓。"
    $runId = Get-AuditRunId
    $reportRoot = Resolve-AuditBundleOutputDirectory $OutDir $runId -Force:$Force
    $scans = @($targets | ForEach-Object {
        $resolved = Resolve-AuditTargetPath ([string]$_.path)
        New-AuditRepoScan ([string]$_.name) $resolved ([string]$_.path)
    })
    return Write-AuditThreeFileBundle $reportRoot $runId "target-repo" "" $cfg $scans
}

function Invoke-AuditSkillDiscovery {
    param([string]$Query, [string]$OutDir, [switch]$Force)
    $cfg = Ensure-AuditUserProfilePrecheck
    Assert-AuditUserProfileReady $cfg
    $runId = Get-AuditRunId
    $reportRoot = Resolve-AuditBundleOutputDirectory $OutDir $runId -Force:$Force
    return Write-AuditThreeFileBundle $reportRoot $runId "profile-only" $Query $cfg @()
}
