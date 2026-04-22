function Parse-AuditTargetsArgs([string[]]$tokens) {
    $result = [ordered]@{
        action = "list"
        name = $null
        path = $null
        profile = $null
        target = $null
        run_id = $null
        out = $null
        query = $null
        recommendations = $null
        dry_run_ack = $null
        stale_ack = $null
        allow_stale_snapshot = $false
        force = $false
        add_selection = $null
        remove_selection = $null
        mcp_add_selection = $null
        mcp_remove_selection = $null
        apply = $false
        yes = $false
        tags = @()
        notes = ""
    }

    $items = @($tokens | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($items.Count -gt 0) {
        $head = ([string]$items[0]).ToLowerInvariant()
        switch ($head) {
            "初始化" { $result.action = "init"; $items = @($items | Select-Object -Skip 1) }
            "init" { $result.action = "init"; $items = @($items | Select-Object -Skip 1) }
            "需求设置" { $result.action = "profile_set"; $items = @($items | Select-Object -Skip 1) }
            "profile-set" { $result.action = "profile_set"; $items = @($items | Select-Object -Skip 1) }
            "需求查看" { $result.action = "profile_show"; $items = @($items | Select-Object -Skip 1) }
            "profile-show" { $result.action = "profile_show"; $items = @($items | Select-Object -Skip 1) }
            "需求结构化" { $result.action = "profile_structure"; $items = @($items | Select-Object -Skip 1) }
            "profile-structure" { $result.action = "profile_structure"; $items = @($items | Select-Object -Skip 1) }
            "添加" { $result.action = "add"; $items = @($items | Select-Object -Skip 1) }
            "add" { $result.action = "add"; $items = @($items | Select-Object -Skip 1) }
            "修改" { $result.action = "update"; $items = @($items | Select-Object -Skip 1) }
            "update" { $result.action = "update"; $items = @($items | Select-Object -Skip 1) }
            "删除" { $result.action = "remove"; $items = @($items | Select-Object -Skip 1) }
            "remove" { $result.action = "remove"; $items = @($items | Select-Object -Skip 1) }
            "列表" { $result.action = "list"; $items = @($items | Select-Object -Skip 1) }
            "list" { $result.action = "list"; $items = @($items | Select-Object -Skip 1) }
            "扫描" { $result.action = "scan"; $items = @($items | Select-Object -Skip 1) }
            "scan" { $result.action = "scan"; $items = @($items | Select-Object -Skip 1) }
            "发现新技能" { $result.action = "discover_skills"; $items = @($items | Select-Object -Skip 1) }
            "discover-skills" { $result.action = "discover_skills"; $items = @($items | Select-Object -Skip 1) }
            "discover" { $result.action = "discover_skills"; $items = @($items | Select-Object -Skip 1) }
            "状态" { $result.action = "status"; $items = @($items | Select-Object -Skip 1) }
            "status" { $result.action = "status"; $items = @($items | Select-Object -Skip 1) }
            "预检" { $result.action = "preflight"; $items = @($items | Select-Object -Skip 1) }
            "preflight" { $result.action = "preflight"; $items = @($items | Select-Object -Skip 1) }
            "应用确认" { $result.action = "apply_flow"; $items = @($items | Select-Object -Skip 1) }
            "apply-flow" { $result.action = "apply_flow"; $items = @($items | Select-Object -Skip 1) }
            "应用" { $result.action = "apply"; $items = @($items | Select-Object -Skip 1) }
            "apply" { $result.action = "apply"; $items = @($items | Select-Object -Skip 1) }
            default { throw ("未知审查目标子命令：{0}" -f $items[0]) }
        }
    }

    $positional = @()
    for ($i = 0; $i -lt $items.Count; $i++) {
        $t = [string]$items[$i]
        $key = $t.ToLowerInvariant()
        switch ($key) {
            "--target" {
                Need ($i + 1 -lt $items.Count) "--target 缺少值"
                $result.target = [string]$items[++$i]
                continue
            }
            "--run-id" {
                Need ($i + 1 -lt $items.Count) "--run-id 缺少值"
                $result.run_id = Resolve-AuditRunIdInput ([string]$items[++$i]) "--run-id"
                continue
            }
            "--profile" {
                Need ($i + 1 -lt $items.Count) "--profile 缺少值"
                $result.profile = [string]$items[++$i]
                continue
            }
            "--out" {
                Need ($i + 1 -lt $items.Count) "--out 缺少值"
                $result.out = [string]$items[++$i]
                if (Test-AuditPlaceholderToken $result.out) {
                    throw ("--out 路径包含未替换占位符：{0}`n{1}" -f $result.out, (Get-AuditRunIdHintText))
                }
                continue
            }
            "--query" {
                Need ($i + 1 -lt $items.Count) "--query 缺少值"
                $result.query = [string]$items[++$i]
                continue
            }
            "--recommendations" {
                Need ($i + 1 -lt $items.Count) "--recommendations 缺少值"
                $result.recommendations = Resolve-AuditPathRunIdPlaceholder ([string]$items[++$i]) "--recommendations" @("recommendations.json")
                continue
            }
            "--dry-run-ack" {
                Need ($i + 1 -lt $items.Count) "--dry-run-ack 缺少值"
                $result.dry_run_ack = [string]$items[++$i]
                continue
            }
            "--stale-ack" {
                Need ($i + 1 -lt $items.Count) "--stale-ack 缺少值"
                $result.stale_ack = [string]$items[++$i]
                continue
            }
            "--allow-stale-snapshot" {
                $result.allow_stale_snapshot = $true
                continue
            }
            "--force" {
                $result.force = $true
                continue
            }
            "--add-indexes" {
                Need ($i + 1 -lt $items.Count) "--add-indexes 缺少值"
                $result.add_selection = [string]$items[++$i]
                continue
            }
            "--remove-indexes" {
                Need ($i + 1 -lt $items.Count) "--remove-indexes 缺少值"
                $result.remove_selection = [string]$items[++$i]
                continue
            }
            "--mcp-add-indexes" {
                Need ($i + 1 -lt $items.Count) "--mcp-add-indexes 缺少值"
                $result.mcp_add_selection = [string]$items[++$i]
                continue
            }
            "--mcp-remove-indexes" {
                Need ($i + 1 -lt $items.Count) "--mcp-remove-indexes 缺少值"
                $result.mcp_remove_selection = [string]$items[++$i]
                continue
            }
            "--apply" {
                $result.apply = $true
                continue
            }
            "--yes" {
                $result.yes = $true
                continue
            }
            "--tag" {
                Need ($i + 1 -lt $items.Count) "--tag 缺少值"
                $result.tags += [string]$items[++$i]
                continue
            }
            "--notes" {
                Need ($i + 1 -lt $items.Count) "--notes 缺少值"
                $result.notes = [string]$items[++$i]
                continue
            }
            default {
                $positional += $t
            }
        }
    }

    if ($result.action -eq "add" -or $result.action -eq "update") {
        Need ($positional.Count -ge 2) "目标仓操作需要 name 和 path"
        $result.name = [string]$positional[0]
        $result.path = [string]$positional[1]
    }
    elseif ($result.action -eq "remove") {
        Need ($positional.Count -ge 1) "删除目标仓需要 name"
        $result.name = [string]$positional[0]
    }
    return [pscustomobject]$result
}

function Invoke-AuditTargetsCommand([string[]]$tokens = @()) {
    $opts = Parse-AuditTargetsArgs $tokens
    switch ($opts.action) {
        "init" {
            if (Initialize-AuditTargetsConfig) {
                Write-Host "已创建 audit-targets.json" -ForegroundColor Green
            }
            else {
                Write-Host "audit-targets.json 已存在，未覆盖。" -ForegroundColor Yellow
            }
        }
        "profile_set" {
            $rawText = Read-HostSafe "请输入用户基本需求（长文本）"
            Set-AuditUserProfileRawText $rawText
            $defaultPath = Get-AuditStructuredProfileDefaultPath
            $profilePath = Read-HostSafe ("结构化 profile 文件路径（回车使用默认：{0}；输入 0 跳过）" -f $defaultPath)
            if ([string]$profilePath.Trim() -eq "0") {
                Write-Host "已保存用户基本需求。结构化导入已跳过。" -ForegroundColor Green
            }
            else {
                Invoke-AuditStructuredProfileFlow $profilePath
            }
        }
        "profile_show" { Show-AuditUserProfile }
        "profile_structure" {
            Invoke-AuditStructuredProfileFlow $opts.profile
        }
        "add" {
            Add-AuditTargetConfigEntry $opts.name $opts.path $opts.tags $opts.notes | Out-Null
            Write-Host ("已登记目标仓：{0}" -f (Normalize-Name $opts.name)) -ForegroundColor Green
        }
        "update" {
            Update-AuditTargetConfigEntry $opts.name $opts.path $opts.tags $opts.notes | Out-Null
            Write-Host ("已更新目标仓：{0}" -f (Normalize-Name $opts.name)) -ForegroundColor Green
        }
        "remove" {
            Remove-AuditTargetConfigEntry $opts.name | Out-Null
            Write-Host ("已删除目标仓：{0}" -f (Normalize-Name $opts.name)) -ForegroundColor Green
        }
        "list" { Write-AuditTargetsList }
        "status" { Show-AuditLatestStatus }
        "preflight" { Invoke-AuditRecommendationsPreflight -RecommendationsPath $opts.recommendations -RunId $opts.run_id | Out-Null }
        "scan" { Invoke-AuditTargetsScan -Target $opts.target -OutDir $opts.out -Force:$opts.force | Out-Null }
        "discover_skills" { Invoke-AuditSkillDiscovery -Query $opts.query -OutDir $opts.out -Force:$opts.force | Out-Null }
        "apply_flow" { Invoke-AuditRecommendationsTwoStageApply -RecommendationsPath $opts.recommendations -AddSelection $opts.add_selection -RemoveSelection $opts.remove_selection -McpAddSelection $opts.mcp_add_selection -McpRemoveSelection $opts.mcp_remove_selection -DryRunAck $opts.dry_run_ack -StaleAck $opts.stale_ack -AllowStaleSnapshot:$opts.allow_stale_snapshot | Out-Null }
        "apply" { Invoke-AuditRecommendationsApply -RecommendationsPath $opts.recommendations -AddSelection $opts.add_selection -RemoveSelection $opts.remove_selection -McpAddSelection $opts.mcp_add_selection -McpRemoveSelection $opts.mcp_remove_selection -DryRunAck $opts.dry_run_ack -StaleAck $opts.stale_ack -AllowStaleSnapshot:$opts.allow_stale_snapshot -RequireDryRunAck (-not $opts.apply) -Apply:$opts.apply -Yes:$opts.yes | Out-Null }
    }
}
