function Get-WorkflowCatalog {
    $doctorStrictStep = [pscustomobject]@{
        id = "doctor_strict"
        title = "严格健康检查（doctor --strict）"
        command = "doctor --strict --threshold-ms 8000"
        action = {
            $report = Invoke-Doctor @("--strict", "--threshold-ms", "8000")
            if ($report -and $report.PSObject.Properties.Match("pass").Count -gt 0 -and -not [bool]$report.pass) {
                throw "doctor --strict failed"
            }
        }
    }

    return [ordered]@{
        quickstart = [pscustomobject]@{
            key = "quickstart"
            name = "新手"
            description = "从浏览技能到安装、重建并同步、严格检查的一条龙流程。"
            steps = @(
                [pscustomobject]@{
                    id = "discover"
                    title = "浏览技能"
                    command = "发现"
                    action = { 发现 }
                },
                [pscustomobject]@{
                    id = "install_interactive"
                    title = "选择安装"
                    command = "安装"
                    action = { 安装 }
                },
                [pscustomobject]@{
                    id = "build_apply"
                    title = "重建并同步"
                    command = "构建生效"
                    action = { 构建生效 }
                },
                $doctorStrictStep
            )
        }
        maintenance = [pscustomobject]@{
            key = "maintenance"
            name = "维护"
            description = "适合日常维护：更新上游、重建并同步、同步 MCP、严格检查。"
            steps = @(
                [pscustomobject]@{
                    id = "update"
                    title = "更新上游"
                    command = "更新"
                    action = { 更新 }
                },
                [pscustomobject]@{
                    id = "build_apply"
                    title = "重建并同步"
                    command = "构建生效"
                    action = { 构建生效 }
                },
                [pscustomobject]@{
                    id = "sync_mcp"
                    title = "同步 MCP"
                    command = "同步MCP"
                    action = { 同步MCP }
                },
                $doctorStrictStep
            )
        }
        audit = [pscustomobject]@{
            key = "audit"
            name = "审查"
            description = "聚焦目标仓审查：查看需求、生成审查包、回看最近状态。"
            steps = @(
                [pscustomobject]@{
                    id = "audit_profile_show"
                    title = "查看需求"
                    command = "审查目标 需求查看"
                    action = { Invoke-AuditTargetsCommand @("profile-show") }
                },
                [pscustomobject]@{
                    id = "audit_target_list"
                    title = "目标仓列表"
                    command = "审查目标 列出"
                    action = { Invoke-AuditTargetsCommand @("list") }
                },
                [pscustomobject]@{
                    id = "audit_scan"
                    title = "生成审查包"
                    command = "审查目标 扫描"
                    action = { Invoke-AuditTargetsCommand @("scan") }
                },
                [pscustomobject]@{
                    id = "audit_status"
                    title = "查看最近状态"
                    command = "审查目标 状态"
                    action = { Invoke-AuditTargetsCommand @("status") }
                }
            )
        }
        all = [pscustomobject]@{
            key = "all"
            name = "全流程"
            description = "通用一键巡检：更新上游、浏览技能、重建并同步、同步 MCP、严格检查。"
            steps = @(
                [pscustomobject]@{
                    id = "update"
                    title = "更新上游"
                    command = "更新"
                    action = { 更新 }
                },
                [pscustomobject]@{
                    id = "discover"
                    title = "浏览技能"
                    command = "发现"
                    action = { 发现 }
                },
                [pscustomobject]@{
                    id = "build_apply"
                    title = "重建并同步"
                    command = "构建生效"
                    action = { 构建生效 }
                },
                [pscustomobject]@{
                    id = "sync_mcp"
                    title = "同步 MCP"
                    command = "同步MCP"
                    action = { 同步MCP }
                },
                $doctorStrictStep
            )
        }
    }
}

function Resolve-WorkflowProfileKey([string]$profile) {
    if ([string]::IsNullOrWhiteSpace($profile)) { return $null }
    $k = $profile.Trim().ToLowerInvariant()
    switch ($k) {
        "新手" { return "quickstart" }
        "quickstart" { return "quickstart" }
        "start" { return "quickstart" }
        "onboarding" { return "quickstart" }
        "维护" { return "maintenance" }
        "maintenance" { return "maintenance" }
        "maintain" { return "maintenance" }
        "审查" { return "audit" }
        "audit" { return "audit" }
        "全流程" { return "all" }
        "all" { return "all" }
        "full" { return "all" }
        default { return $null }
    }
}

function Parse-WorkflowArgs([string[]]$tokens) {
    $opts = [ordered]@{
        profile = $null
        list = $false
        continue_on_error = $false
        no_prompt = $false
    }
    if ($null -eq $tokens) { return [pscustomobject]$opts }

    :tokenLoop for ($i = 0; $i -lt $tokens.Count; $i++) {
        $token = [string]$tokens[$i]
        if ([string]::IsNullOrWhiteSpace($token)) { continue }
        $lower = $token.Trim().ToLowerInvariant()
        switch ($lower) {
            "--list" { $opts.list = $true; continue tokenLoop }
            "-l" { $opts.list = $true; continue tokenLoop }
            "--continue-on-error" { $opts.continue_on_error = $true; continue tokenLoop }
            "--no-prompt" { $opts.no_prompt = $true; continue tokenLoop }
            "--profile" {
                Need ($i + 1 -lt $tokens.Count) "--profile 缺少值"
                $rawProfile = [string]$tokens[++$i]
                $resolved = Resolve-WorkflowProfileKey $rawProfile
                Need (-not [string]::IsNullOrWhiteSpace($resolved)) ("未知工作流场景：{0}" -f $rawProfile)
                $opts.profile = $resolved
                continue tokenLoop
            }
        }

        if ($token.StartsWith("-")) {
            throw ("未知一键参数：{0}" -f $token)
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$opts.profile)) {
            throw ("重复的场景参数：{0}" -f $token)
        }
        $positional = Resolve-WorkflowProfileKey $token
        Need (-not [string]::IsNullOrWhiteSpace($positional)) ("未知工作流场景：{0}" -f $token)
        $opts.profile = $positional
    }

    return [pscustomobject]$opts
}

function Write-WorkflowCatalog($catalog) {
    Write-Host "=== 一键工作流可用场景 ===" -ForegroundColor Cyan
    foreach ($key in @("quickstart", "maintenance", "audit", "all")) {
        if (-not $catalog.Contains($key)) { continue }
        $w = $catalog[$key]
        Write-Host ("- {0} ({1}): {2}" -f $w.name, $w.key, $w.description)
    }
    Write-Host ""
    Write-Host "示例：" -ForegroundColor DarkGray
    Write-Host ".\skills.ps1 一键 新手"
    Write-Host ".\skills.ps1 一键 维护 --continue-on-error"
    Write-Host ".\skills.ps1 一键 审查 --no-prompt"
    Write-Host ".\skills.ps1 workflow all --no-prompt"
}

function Select-WorkflowProfileInteractively($catalog) {
    while ($true) {
        Write-Host ""
        Write-Host "=== 选择一键工作流场景 ==="
        Write-Host "1) 新手（浏览技能 -> 选择安装 -> 重建并同步 -> doctor --strict）"
        Write-Host "2) 维护（更新上游 -> 重建并同步 -> 同步 MCP -> doctor --strict）"
        Write-Host "3) 审查（查看需求 -> 目标仓列表 -> 生成审查包 -> 查看最近状态）"
        Write-Host "4) 全流程（更新上游 -> 浏览技能 -> 重建并同步 -> 同步 MCP -> doctor --strict）"
        Write-Host "0) 取消"
        $choice = Read-MenuChoice "请选择（回车取消）"
        switch ($choice) {
            "1" { return "quickstart" }
            "2" { return "maintenance" }
            "3" { return "audit" }
            "4" { return "all" }
            "0" { return $null }
            default { Write-Host "无效选择。" }
        }
    }
}

function Get-WorkflowPreviewLines($workflow) {
    $lines = New-Object System.Collections.Generic.List[string]
    $idx = 0
    foreach ($step in @($workflow.steps)) {
        $idx++
        $line = ("{0,2}. {1}  [{2}]" -f $idx, [string]$step.title, [string]$step.command)
        $lines.Add($line) | Out-Null
    }
    return $lines.ToArray()
}

function Invoke-WorkflowStep([int]$Index, [int]$Total, $Step) {
    $title = [string]$Step.title
    $command = [string]$Step.command
    $id = [string]$Step.id
    Write-Host ("[{0}/{1}] {2}" -f $Index, $Total, $title) -ForegroundColor Cyan
    Write-Host ("  command: {0}" -f $command) -ForegroundColor DarkGray

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $error = ""
    $success = $false
    try {
        & $Step.action
        $success = $true
        Write-Host ("  ✅ 完成（{0} ms）" -f [int]$sw.ElapsedMilliseconds) -ForegroundColor Green
    }
    catch {
        $error = $_.Exception.Message
        Write-Host ("  ❌ 失败（{0} ms）：{1}" -f [int]$sw.ElapsedMilliseconds, $error) -ForegroundColor Red
    }
    finally {
        $sw.Stop()
    }

    return [pscustomobject]@{
        id = $id
        title = $title
        command = $command
        success = $success
        duration_ms = [int]$sw.ElapsedMilliseconds
        error = $error
    }
}

function Write-WorkflowResultSummary($workflow, $results, [int]$totalMs) {
    $failed = @($results | Where-Object { -not [bool]$_.success })
    $passed = @($results | Where-Object { [bool]$_.success })
    Write-Host ""
    Write-Host ("=== 一键工作流完成：{0} ===" -f [string]$workflow.name) -ForegroundColor Cyan
    Write-Host ("总耗时：{0} ms" -f $totalMs)
    Write-Host ("步骤：成功 {0} / 失败 {1}" -f $passed.Count, $failed.Count)
    if ($failed.Count -gt 0) {
        foreach ($item in $failed) {
            Write-Host ("- 失败：{0} => {1}" -f [string]$item.command, [string]$item.error) -ForegroundColor Yellow
        }
    }
}

function Invoke-Workflow([string[]]$tokens = @()) {
    $opts = Parse-WorkflowArgs $tokens
    $catalog = Get-WorkflowCatalog

    if ($opts.list) {
        Write-WorkflowCatalog $catalog
        return [pscustomobject]@{ pass = $true; listed = $true }
    }

    $profileKey = [string]$opts.profile
    if ([string]::IsNullOrWhiteSpace($profileKey)) {
        if ($opts.no_prompt) {
            $profileKey = "all"
            Write-Host "未指定场景且启用 --no-prompt，默认使用：全流程（all）"
        }
        else {
            $profileKey = Select-WorkflowProfileInteractively $catalog
            if ([string]::IsNullOrWhiteSpace($profileKey)) {
                Write-Host "已取消一键工作流。"
                return [pscustomobject]@{ pass = $false; canceled = $true }
            }
        }
    }

    Need ($catalog.Contains($profileKey)) ("未知工作流场景：{0}" -f $profileKey)
    $workflow = $catalog[$profileKey]
    $preview = @(Get-WorkflowPreviewLines $workflow)

    if (-not $opts.no_prompt) {
        if (-not (Confirm-WithSummary ("将执行一键工作流：{0}" -f [string]$workflow.name) $preview "确认继续执行？" "Y")) {
            Write-Host "已取消一键工作流。"
            return [pscustomobject]@{ pass = $false; canceled = $true }
        }
    }

    return (Invoke-WithMetric "workflow_run" {
        $results = New-Object System.Collections.Generic.List[object]
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $index = 0
        foreach ($step in @($workflow.steps)) {
            $index++
            $result = Invoke-WorkflowStep $index @($workflow.steps).Count $step
            $results.Add($result) | Out-Null
            if (-not [bool]$result.success -and -not [bool]$opts.continue_on_error) {
                break
            }
        }
        $sw.Stop()

        $resultArray = $results.ToArray()
        Write-WorkflowResultSummary $workflow $resultArray ([int]$sw.ElapsedMilliseconds)
        $failed = @($resultArray | Where-Object { -not [bool]$_.success })
        $pass = ($failed.Count -eq 0)
        Log ("一键工作流执行完成：{0}（pass={1}）" -f [string]$workflow.key, $pass) "INFO" -Data @{
            profile = [string]$workflow.key
            pass = $pass
            total_ms = [int]$sw.ElapsedMilliseconds
            step_total = @($resultArray).Count
            step_failed = $failed.Count
        }
        if (-not $pass -and -not [bool]$opts.continue_on_error) {
            throw ("一键工作流失败：{0}" -f [string]$failed[0].error)
        }
        return [pscustomobject]@{
            pass = $pass
            profile = [string]$workflow.key
            continue_on_error = [bool]$opts.continue_on_error
            results = @($resultArray)
            total_ms = [int]$sw.ElapsedMilliseconds
        }
    } @{ command = "一键工作流"; profile = [string]$workflow.key } -NoHost)
}
