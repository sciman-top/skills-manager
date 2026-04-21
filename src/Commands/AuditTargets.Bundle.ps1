function Invoke-AuditTargetsScan {
    param(
        [string]$Target,
        [string]$OutDir,
        [switch]$Force
    )
    $cfg = Load-AuditTargetsConfig
    Assert-AuditUserProfileReady $cfg
    $targets = @($cfg.targets)
    if (-not [string]::IsNullOrWhiteSpace($Target)) {
        $targets = @($targets | Where-Object { $_.name -eq (Normalize-Name $Target) })
        Need ($targets.Count -gt 0) ("未找到目标仓：{0}" -f $Target)
    }
    else {
        $targets = @($targets | Where-Object {
                if ($_.PSObject.Properties.Match("enabled").Count -eq 0) { return $true }
                return [bool]$_.enabled
            })
    }
    Need ($targets.Count -gt 0) "没有可扫描的目标仓。"

    $runId = Get-AuditRunId
    $reportRoot = if ([string]::IsNullOrWhiteSpace($OutDir)) {
        Get-AuditReportRoot $runId
    }
    else {
        Resolve-AuditTargetPath $OutDir
    }
    if (-not [string]::IsNullOrWhiteSpace($OutDir) -and (Test-Path -LiteralPath $reportRoot -PathType Container) -and -not $Force) {
        $existing = @(Get-ChildItem -LiteralPath $reportRoot -Force -ErrorAction SilentlyContinue)
        if ($existing.Count -gt 0) {
            throw ("--out 目录已存在且非空，请使用新的 run-id 目录，或显式追加 --force：{0}" -f $reportRoot)
        }
    }
    EnsureDir $reportRoot

    $userProfilePath = Join-Path $reportRoot "user-profile.json"
    Write-AuditJsonFile $userProfilePath (Get-AuditUserProfileOutput $cfg)

    $scans = @()
    foreach ($t in $targets) {
        $resolved = Resolve-AuditTargetPath ([string]$t.path)
        $scans += New-AuditRepoScan ([string]$t.name) $resolved ([string]$t.path)
    }

    $repoScanPath = ""
    $repoScansPath = ""
    if ($scans.Count -eq 1) {
        $repoScanPath = Join-Path $reportRoot "repo-scan.json"
        Write-AuditJsonFile $repoScanPath $scans[0]
    }
    else {
        $repoScansPath = Join-Path $reportRoot "repo-scans.json"
        Write-AuditJsonFile $repoScansPath ([pscustomobject]@{ schema_version = 1; run_id = $runId; scans = @($scans) })
    }

    $installedPath = Join-Path $reportRoot "installed-skills.json"
    $installedSkills = @()
    try {
        try {
            $liveCfg = LoadCfg
        }
        catch {
            Log ("审查包生成时读取 skills.json 失败，已回退为空安装快照：{0}" -f $_.Exception.Message) "WARN"
            $liveCfg = New-AuditInstalledFactsFallbackCfg
        }
        $installedSkills = @(Get-InstalledSkillFacts $liveCfg)
    }
    catch {
        throw ("生成 installed-skills.json 失败：{0}" -f $_.Exception.Message)
    }
    $liveState = Get-AuditLiveInstalledState $liveCfg
    Write-AuditJsonFile $installedPath ([pscustomobject]@{
            schema_version = 1
            snapshot_kind = "audit_input"
            source_of_truth = "live_mappings"
            captured_at = (Get-Date).ToString("o")
            live_skill_count = [int]$liveState.skill_count
            live_fingerprint = [string]$liveState.fingerprint
            skills = @($installedSkills)
        })

    $sourceStrategyPath = Join-Path $reportRoot "source-strategy.json"
    Write-AuditJsonFile $sourceStrategyPath (New-AuditSourceStrategy "target-repo" "")

    $templatePath = Join-Path $reportRoot "recommendations.template.json"
    $templateTarget = if ($scans.Count -eq 1) { [string]$scans[0].target.name } else { "*" }
    Write-AuditJsonFile $templatePath (New-AuditRecommendationsTemplate $runId $templateTarget "target-repo")

    $briefPath = Join-Path $reportRoot "ai-brief.md"
    Write-AuditAiBrief $briefPath $scans $userProfilePath $repoScanPath $repoScansPath $installedPath $templatePath "target-repo" "" $sourceStrategyPath
    $outerAiPromptPath = Join-Path $reportRoot "outer-ai-prompt.md"
    Write-AuditOuterAiPromptFile $outerAiPromptPath $reportRoot $briefPath $userProfilePath $repoScanPath $repoScansPath $installedPath $templatePath "target-repo" "" $sourceStrategyPath

    $requiredFiles = New-Object System.Collections.Generic.List[object]
    $requiredFiles.Add([pscustomobject]@{ label = "user-profile.json"; path = $userProfilePath }) | Out-Null
    if ($scans.Count -eq 1) {
        $requiredFiles.Add([pscustomobject]@{ label = "repo-scan.json"; path = $repoScanPath }) | Out-Null
    }
    else {
        $requiredFiles.Add([pscustomobject]@{ label = "repo-scans.json"; path = $repoScansPath }) | Out-Null
    }
    $requiredFiles.Add([pscustomobject]@{ label = "installed-skills.json"; path = $installedPath }) | Out-Null
    $requiredFiles.Add([pscustomobject]@{ label = "source-strategy.json"; path = $sourceStrategyPath }) | Out-Null
    $requiredFiles.Add([pscustomobject]@{ label = "recommendations.template.json"; path = $templatePath }) | Out-Null
    $requiredFiles.Add([pscustomobject]@{ label = "ai-brief.md"; path = $briefPath }) | Out-Null
    $requiredFiles.Add([pscustomobject]@{ label = "outer-ai-prompt.md"; path = $outerAiPromptPath }) | Out-Null
    Assert-AuditBundleRequiredFiles ($requiredFiles.ToArray())
    Write-Host ("审查包已生成：{0}" -f $reportRoot) -ForegroundColor Green
    Write-Host "关键产物：" -ForegroundColor Cyan
    Write-Host ("- user-profile.json: {0}" -f $userProfilePath)
    if ($scans.Count -eq 1) {
        Write-Host ("- repo-scan.json: {0}" -f $repoScanPath)
    }
    else {
        Write-Host ("- repo-scans.json: {0}" -f $repoScansPath)
    }
    Write-Host ("- installed-skills.json: {0}" -f $installedPath)
    Write-Host ("- source-strategy.json: {0}" -f $sourceStrategyPath)
    Write-Host ("- ai-brief.md: {0}" -f $briefPath)
    Write-Host ("- outer-ai-prompt.md: {0}" -f $outerAiPromptPath)
    Write-Host ("- recommendations.template.json: {0}" -f $templatePath)
    Write-Host "下一步：把 outer-ai-prompt.md 交给 AI；AI 应先填写并自检 recommendations.json，再执行 dry-run，并按原序号列出新增/卸载清单。" -ForegroundColor Yellow
    return [pscustomobject]@{
        run_id = $runId
        path = $reportRoot
        scans = @($scans)
    }
}

function Invoke-AuditSkillDiscovery {
    param(
        [string]$Query,
        [string]$OutDir,
        [switch]$Force
    )
    $cfg = Load-AuditTargetsConfig
    Assert-AuditUserProfileReady $cfg

    $runId = Get-AuditRunId
    $reportRoot = if ([string]::IsNullOrWhiteSpace($OutDir)) {
        Get-AuditReportRoot $runId
    }
    else {
        Resolve-AuditTargetPath $OutDir
    }
    if (-not [string]::IsNullOrWhiteSpace($OutDir) -and (Test-Path -LiteralPath $reportRoot -PathType Container) -and -not $Force) {
        $existing = @(Get-ChildItem -LiteralPath $reportRoot -Force -ErrorAction SilentlyContinue)
        if ($existing.Count -gt 0) {
            throw ("--out 目录已存在且非空，请使用新的 run-id 目录，或显式追加 --force：{0}" -f $reportRoot)
        }
    }
    EnsureDir $reportRoot

    $userProfilePath = Join-Path $reportRoot "user-profile.json"
    Write-AuditJsonFile $userProfilePath (Get-AuditUserProfileOutput $cfg)

    $installedPath = Join-Path $reportRoot "installed-skills.json"
    $installedSkills = @()
    try {
        try {
            $liveCfg = LoadCfg
        }
        catch {
            Log ("新技能发现生成时读取 skills.json 失败，已回退为空安装快照：{0}" -f $_.Exception.Message) "WARN"
            $liveCfg = New-AuditInstalledFactsFallbackCfg
        }
        $installedSkills = @(Get-InstalledSkillFacts $liveCfg)
    }
    catch {
        throw ("生成 installed-skills.json 失败：{0}" -f $_.Exception.Message)
    }
    $liveState = Get-AuditLiveInstalledState $liveCfg
    Write-AuditJsonFile $installedPath ([pscustomobject]@{
            schema_version = 1
            snapshot_kind = "audit_input"
            source_of_truth = "live_mappings"
            captured_at = (Get-Date).ToString("o")
            live_skill_count = [int]$liveState.skill_count
            live_fingerprint = [string]$liveState.fingerprint
            skills = @($installedSkills)
        })

    $sourceStrategyPath = Join-Path $reportRoot "source-strategy.json"
    Write-AuditJsonFile $sourceStrategyPath (New-AuditSourceStrategy "profile-only" $Query)

    $templatePath = Join-Path $reportRoot "recommendations.template.json"
    Write-AuditJsonFile $templatePath (New-AuditRecommendationsTemplate $runId "profile-only" "profile-only" $Query)

    $briefPath = Join-Path $reportRoot "ai-brief.md"
    Write-AuditAiBrief $briefPath @() $userProfilePath "" "" $installedPath $templatePath "profile-only" $Query $sourceStrategyPath
    $outerAiPromptPath = Join-Path $reportRoot "outer-ai-prompt.md"
    Write-AuditOuterAiPromptFile $outerAiPromptPath $reportRoot $briefPath $userProfilePath "" "" $installedPath $templatePath "profile-only" $Query $sourceStrategyPath

    $requiredFiles = New-Object System.Collections.Generic.List[object]
    $requiredFiles.Add([pscustomobject]@{ label = "user-profile.json"; path = $userProfilePath }) | Out-Null
    $requiredFiles.Add([pscustomobject]@{ label = "installed-skills.json"; path = $installedPath }) | Out-Null
    $requiredFiles.Add([pscustomobject]@{ label = "source-strategy.json"; path = $sourceStrategyPath }) | Out-Null
    $requiredFiles.Add([pscustomobject]@{ label = "recommendations.template.json"; path = $templatePath }) | Out-Null
    $requiredFiles.Add([pscustomobject]@{ label = "ai-brief.md"; path = $briefPath }) | Out-Null
    $requiredFiles.Add([pscustomobject]@{ label = "outer-ai-prompt.md"; path = $outerAiPromptPath }) | Out-Null
    Assert-AuditBundleRequiredFiles ($requiredFiles.ToArray())

    Write-Host ("新技能发现包已生成：{0}" -f $reportRoot) -ForegroundColor Green
    Write-Host "关键产物：" -ForegroundColor Cyan
    Write-Host ("- user-profile.json: {0}" -f $userProfilePath)
    Write-Host ("- installed-skills.json: {0}" -f $installedPath)
    Write-Host ("- source-strategy.json: {0}" -f $sourceStrategyPath)
    Write-Host ("- ai-brief.md: {0}" -f $briefPath)
    Write-Host ("- outer-ai-prompt.md: {0}" -f $outerAiPromptPath)
    Write-Host ("- recommendations.template.json: {0}" -f $templatePath)
    Write-Host "下一步：把 outer-ai-prompt.md 交给 AI；AI 应先填写并自检 recommendations.json，再执行 dry-run，并按原序号列出新增/卸载清单。" -ForegroundColor Yellow
    return [pscustomobject]@{
        run_id = $runId
        path = $reportRoot
        mode = "profile-only"
        query = [string]$Query
        scans = @()
    }
}
