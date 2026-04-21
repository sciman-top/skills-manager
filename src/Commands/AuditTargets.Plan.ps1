function Ensure-AuditArrayProperty($obj, [string]$name) {
    if (-not $obj.PSObject.Properties.Match($name).Count -or $null -eq $obj.$name) {
        $obj | Add-Member -NotePropertyName $name -NotePropertyValue @() -Force
    }
    elseif (-not (Assert-IsArray $obj.$name)) {
        $obj.$name = @($obj.$name)
    }
}

function Normalize-AuditSources($item, [string]$kind) {
    Ensure-AuditArrayProperty $item "sources"
    $normalized = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($source in @($item.sources)) {
        if ($null -eq $source) { continue }
        $text = ([string]$source).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($seen.Add($text)) {
            $normalized.Add($text) | Out-Null
        }
    }
    $item.sources = @($normalized)
    Need (@($item.sources).Count -gt 0) ("{0} 至少需要一个非空 source：{1}" -f $kind, [string]$item.name)
}

function Assert-AuditRequiredBooleanTrue($value, [string]$fieldName) {
    Need ($value -is [bool]) ("{0} 必须是布尔值 true" -f $fieldName)
    Need ([bool]$value) ("{0} 必须为 true" -f $fieldName)
}

function Assert-AuditReasonPair($item, [string]$name) {
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.reason_user_profile)) ("{0} 缺少 reason_user_profile：{1}" -f $name, [string]$item.name)
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.reason_target_repo)) ("{0} 缺少 reason_target_repo：{1}" -f $name, [string]$item.name)
    Normalize-AuditSources $item $name
}

function Assert-AuditRecommendationItem($item) {
    Need ($null -ne $item) "推荐项不能为空"
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.name)) "推荐项缺少 name"
    Assert-AuditReasonPair $item "推荐项"
    Need ($item.PSObject.Properties.Match("install").Count -gt 0 -and $null -ne $item.install) ("推荐项缺少 install：{0}" -f [string]$item.name)

    $install = $item.install
    Need (-not [string]::IsNullOrWhiteSpace([string]$install.repo)) ("推荐项缺少 install.repo：{0}" -f [string]$item.name)
    Need (Looks-LikeRepoInput ([string]$install.repo)) ("install.repo 不是有效仓库输入：{0}" -f [string]$install.repo)

    Need ($install.PSObject.Properties.Match("skill").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$install.skill)) ("推荐项缺少 install.skill：{0}" -f [string]$item.name)
    $skillPath = [string]$install.skill
    $normalizedSkill = Normalize-SkillPath $skillPath
    Need (Test-SafeRelativePath $normalizedSkill -AllowDot) ("install.skill 路径非法：{0}" -f $skillPath)
    $install.skill = $normalizedSkill

    Need ($install.PSObject.Properties.Match("mode").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$install.mode)) ("推荐项缺少 install.mode：{0}" -f [string]$item.name)
    $mode = [string]$install.mode
    $mode = $mode.ToLowerInvariant()
    Need ($mode -eq "manual" -or $mode -eq "vendor") ("install.mode 仅支持 manual 或 vendor：{0}" -f $mode)
    $install.mode = $mode

    $confidence = ([string]$item.confidence).ToLowerInvariant()
    Need ($confidence -eq "low" -or $confidence -eq "medium" -or $confidence -eq "high") ("confidence 仅支持 low/medium/high：{0}" -f [string]$item.confidence)
    $item.confidence = $confidence
    $item | Add-Member -NotePropertyName reason -NotePropertyValue ("用户需求：{0}；目标仓/场景：{1}" -f [string]$item.reason_user_profile, [string]$item.reason_target_repo) -Force
}

function Assert-AuditRemovalCandidate($item) {
    Need ($null -ne $item) "卸载建议不能为空"
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.name)) "卸载建议缺少 name"
    Assert-AuditReasonPair $item "卸载建议"
    Need ($item.PSObject.Properties.Match("installed").Count -gt 0 -and $null -ne $item.installed) ("卸载建议缺少 installed：{0}" -f [string]$item.name)
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.installed.vendor)) ("卸载建议缺少 installed.vendor：{0}" -f [string]$item.name)
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.installed.from)) ("卸载建议缺少 installed.from：{0}" -f [string]$item.name)
}

function Load-AuditRecommendations([string]$path) {
    Need (-not [string]::IsNullOrWhiteSpace($path)) "--recommendations 缺少值"
    Need (Test-Path -LiteralPath $path -PathType Leaf) ("recommendations 文件不存在：{0}" -f $path)
    try {
        $raw = Get-ContentUtf8 $path
        Need (-not [string]::IsNullOrWhiteSpace($raw)) ("recommendations 文件为空：{0}" -f $path)
        $rec = $raw | ConvertFrom-Json
    }
    catch {
        throw ("recommendations JSON 解析失败：{0}" -f $_.Exception.Message)
    }

    Need ([int]$rec.schema_version -eq 2) "recommendations.schema_version 仅支持 2"
    Need (-not [string]::IsNullOrWhiteSpace([string]$rec.run_id)) "recommendations 缺少 run_id"
    Need (-not [string]::IsNullOrWhiteSpace([string]$rec.target)) "recommendations 缺少 target"
    Need ($rec.PSObject.Properties.Match("decision_basis").Count -gt 0 -and $null -ne $rec.decision_basis) "recommendations 缺少 decision_basis"
    Need (Test-AuditJsonProperty $rec.decision_basis "user_profile_used") "decision_basis 缺少 user_profile_used"
    Need (Test-AuditJsonProperty $rec.decision_basis "target_scan_used") "decision_basis 缺少 target_scan_used"
    Need (Test-AuditJsonProperty $rec.decision_basis "source_strategy_used") "decision_basis 缺少 source_strategy_used"
    $recommendationMode = "target-repo"
    if ($rec.PSObject.Properties.Match("recommendation_mode").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$rec.recommendation_mode)) {
        $recommendationMode = ([string]$rec.recommendation_mode).ToLowerInvariant()
    }
    Need ($recommendationMode -eq "target-repo" -or $recommendationMode -eq "profile-only") ("recommendation_mode 仅支持 target-repo 或 profile-only：{0}" -f $recommendationMode)
    Assert-AuditRequiredBooleanTrue $rec.decision_basis.user_profile_used "decision_basis.user_profile_used"
    Need ($rec.decision_basis.target_scan_used -is [bool]) "decision_basis.target_scan_used 必须是布尔值"
    if ($recommendationMode -eq "profile-only") {
        Need (-not [bool]$rec.decision_basis.target_scan_used) "profile-only 模式下 decision_basis.target_scan_used 必须为 false"
    }
    else {
        Assert-AuditRequiredBooleanTrue $rec.decision_basis.target_scan_used "decision_basis.target_scan_used"
    }
    Assert-AuditRequiredBooleanTrue $rec.decision_basis.source_strategy_used "decision_basis.source_strategy_used"
    Need (-not [string]::IsNullOrWhiteSpace([string]$rec.decision_basis.summary)) "decision_basis.summary 不能为空"
    Ensure-AuditArrayProperty $rec "new_skills"
    Ensure-AuditArrayProperty $rec "overlap_findings"
    Ensure-AuditArrayProperty $rec "removal_candidates"
    Ensure-AuditArrayProperty $rec "do_not_install"

    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($rec.new_skills)) {
        Assert-AuditRecommendationItem $item
        $install = $item.install
        $key = "{0}|{1}|{2}" -f (Normalize-RepoUrl ([string]$install.repo)), (Normalize-SkillPath ([string]$install.skill)), ([string]$install.mode)
        Need ($seen.Add($key)) ("重复推荐安装项：{0}" -f $key)
    }

    $seenRemovals = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($rec.removal_candidates)) {
        Assert-AuditRemovalCandidate $item
        $key = "{0}|{1}" -f [string]$item.installed.vendor, [string]$item.installed.from
        Need ($seenRemovals.Add($key)) ("重复卸载建议：{0}" -f $key)
    }
    return $rec
}

function New-AuditInstallPlan($recommendations, $cfg = $null) {
    if ($null -eq $cfg) { $cfg = LoadCfg }
    $installedFacts = @(Get-InstalledSkillFacts $cfg)
    $items = @()
    foreach ($item in @($recommendations.new_skills)) {
        $install = $item.install
        $tokens = @([string]$install.repo, "--skill", [string]$install.skill)
        if ($install.PSObject.Properties.Match("ref").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$install.ref)) {
            $tokens += @("--ref", [string]$install.ref)
        }
        if ($install.PSObject.Properties.Match("mode").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$install.mode)) {
            $tokens += @("--mode", [string]$install.mode)
        }
        $items += [pscustomobject]([ordered]@{
            name = [string]$item.name
            reason = [string]$item.reason
            reason_user_profile = [string]$item.reason_user_profile
            reason_target_repo = [string]$item.reason_target_repo
            confidence = [string]$item.confidence
            sources = @($item.sources)
            tokens = @($tokens)
            status = "planned"
        })
    }

    $removals = @()
    foreach ($item in @($recommendations.removal_candidates)) {
        $match = @($installedFacts | Where-Object { $_.vendor -eq [string]$item.installed.vendor -and $_.from -eq [string]$item.installed.from })
        $status = if ($match.Count -eq 1) { "planned" } elseif ($match.Count -eq 0) { "not_found" } else { "ambiguous" }
        $matched = if ($match.Count -gt 0) { $match[0] } else { $null }
        $removals += [pscustomobject]([ordered]@{
            name = [string]$item.name
            vendor = [string]$item.installed.vendor
            from = [string]$item.installed.from
            reason = ("用户需求：{0}；目标仓/场景：{1}" -f [string]$item.reason_user_profile, [string]$item.reason_target_repo)
            reason_user_profile = [string]$item.reason_user_profile
            reason_target_repo = [string]$item.reason_target_repo
            sources = @($item.sources)
            matched_skill = $matched
            status = $status
        })
    }
    return [pscustomobject]([ordered]@{
        schema_version = 2
        run_id = [string]$recommendations.run_id
        target = [string]$recommendations.target
        decision_basis = $recommendations.decision_basis
        items = @($items)
        overlap_findings = @($recommendations.overlap_findings)
        removal_candidates = @($removals)
        do_not_install = @($recommendations.do_not_install)
    })
}

function Get-AuditApplyReportPath([string]$recommendationsPath) {
    $dir = Split-Path $recommendationsPath -Parent
    if ([string]::IsNullOrWhiteSpace($dir)) { $dir = "." }
    return (Join-Path $dir "apply-report.json")
}

function Get-AuditItemsStatusCount($items, [string]$status) {
    return @($items | Where-Object { [string]$_.status -eq $status }).Count
}

function New-AuditChangedCounts($items, $removals) {
    return [pscustomobject]([ordered]@{
        add_total = @($items).Count
        add_planned = Get-AuditItemsStatusCount $items "planned"
        add_installed = Get-AuditItemsStatusCount $items "installed"
        add_failed = Get-AuditItemsStatusCount $items "failed"
        remove_total = @($removals).Count
        remove_planned = Get-AuditItemsStatusCount $removals "planned"
        remove_removed = Get-AuditItemsStatusCount $removals "removed"
        remove_not_found = Get-AuditItemsStatusCount $removals "not_found"
        remove_ambiguous = Get-AuditItemsStatusCount $removals "ambiguous"
    })
}

function Write-AuditRecommendationSummary($plan, $snapshotState = $null, $liveState = $null) {
    Write-Host ""
    Write-Host "=== 审查建议摘要 ==="
    Write-Host ("决策依据: {0}" -f [string]$plan.decision_basis.summary)
    if ($null -ne $snapshotState -and $null -ne $liveState) {
        Write-Host ("口径: live={0} (source_of_truth), snapshot={1} (audit_input)" -f [int]$liveState.skill_count, [int]$snapshotState.skill_count)
    }
    Write-Host "提示：以下序号为原序号；后续 dry-run 汇报与 apply 选择必须沿用原序号。"
    Write-Host ""
    Write-Host ("新增建议: {0} 项" -f @($plan.items).Count)
    if (@($plan.items).Count -eq 0) {
        Write-Host "无新增建议：当前输入证据未形成可执行新增项。"
    }
    else {
        $index = 1
        foreach ($item in @($plan.items)) {
            Write-Host ("{0}) {1}" -f $index, [string]$item.name)
            Write-Host ("   用户需求: {0}" -f [string]$item.reason_user_profile)
            Write-Host ("   目标仓/场景: {0}" -f [string]$item.reason_target_repo)
            $index++
        }
    }
    Write-Host ""
    Write-Host ("卸载建议: {0} 项" -f @($plan.removal_candidates).Count)
    if (@($plan.removal_candidates).Count -eq 0) {
        Write-Host "无卸载建议：当前输入证据未形成可执行卸载项。"
    }
    else {
        $index = 1
        foreach ($item in @($plan.removal_candidates)) {
            Write-Host ("{0}) {1} [{2}|{3}] status={4}" -f $index, [string]$item.name, [string]$item.vendor, [string]$item.from, [string]$item.status)
            Write-Host ("   用户需求: {0}" -f [string]$item.reason_user_profile)
            Write-Host ("   目标仓/场景: {0}" -f [string]$item.reason_target_repo)
            $index++
        }
    }
}

function Resolve-AuditSelection([string]$selectionText, $items, [string]$prompt, [string]$invalidMsg) {
    $items = @($items)
    if ($items.Count -eq 0) { return [pscustomobject]@{ items = @(); canceled = $false } }
    if ([string]::IsNullOrWhiteSpace($selectionText)) {
        Write-SelectionHint
        $selection = Read-SelectionIndices $prompt $items.Count $invalidMsg
        if ($selection.canceled) { return [pscustomobject]@{ items = @(); canceled = $true } }
        $idx = @($selection.indices)
    }
    else {
        $idx = @(Parse-IndexSelection $selectionText $items.Count)
        if ($idx.Count -eq 0 -and $selectionText.Trim().ToLowerInvariant() -eq "0") {
            return [pscustomobject]@{ items = @(); canceled = $true }
        }
        if ($idx.Count -eq 0) { throw $invalidMsg }
    }
    $selected = @()
    foreach ($n in $idx) { $selected += $items[$n - 1] }
    return [pscustomobject]@{ items = @($selected); canceled = $false }
}

function Remove-AuditSelectedInstalledSkills($selectedItems) {
    $cfg = LoadCfg
    $removedMappings = 0
    $removedVendorImports = 0
    $deletedManualImports = 0
    $deletedLegacyManualDirs = 0
    $deletedOverrides = 0
    $backedOverrides = 0
    foreach ($item in @($selectedItems)) {
        $vendor = [string]$item.vendor
        $from = [string]$item.from
        if ($vendor -eq "manual") {
            $before = @($cfg.imports).Count
            $cfg.imports = @($cfg.imports | Where-Object { -not ($_.mode -eq "manual" -and $_.name -eq $from) })
            $deletedManualImports += ($before - @($cfg.imports).Count)

            $legacyPath = Join-Path $ManualDir $from
            if (Test-Path $legacyPath) {
                Invoke-RemoveItem $legacyPath -Recurse
                $deletedLegacyManualDirs++
            }
            $cfg.mappings = @($cfg.mappings | Where-Object { -not ("$($_.vendor)|$($_.from)" -eq "manual|$from") })
        }
        elseif ($vendor -eq "overrides") {
            $bak = Backup-OverrideDir $from
            if ($bak) { $backedOverrides++ }
            $deletedOverrides++
        }
        else {
            $cfg.mappings = @($cfg.mappings | Where-Object { -not ("$($_.vendor)|$($_.from)" -eq "$vendor|$from") })
            $removedMappings++

            $skillPath = Normalize-SkillPath $from
            $hasSameMapping = @($cfg.mappings | Where-Object { $_.vendor -eq $vendor -and $_.from -eq $skillPath }).Count -gt 0
            if (-not $hasSameMapping) {
                $beforeImports = @($cfg.imports).Count
                $cfg.imports = @($cfg.imports | Where-Object {
                        $mode = if ($_.PSObject.Properties.Match("mode").Count -gt 0) { [string]$_.mode } else { "manual" }
                        if ($mode -ne "vendor") { return $true }
                        if ([string]$_.name -ne $vendor) { return $true }
                        $importSkill = Normalize-SkillPath ([string]$_.skill)
                        return ($importSkill -ne $skillPath)
                    })
                $removedVendorImports += ($beforeImports - @($cfg.imports).Count)
            }
        }
        $item.status = "removed"
    }
    SaveCfg $cfg
    if (@($selectedItems).Count -gt 0) {
        Clear-SkillsCache
    }
    return [pscustomobject]@{
        removed_mappings = $removedMappings
        removed_vendor_imports = $removedVendorImports
        deleted_manual_imports = $deletedManualImports
        deleted_legacy_manual_dirs = $deletedLegacyManualDirs
        deleted_overrides = $deletedOverrides
        backed_overrides = $backedOverrides
    }
}

function Ensure-AuditNewManualImportsMapped($beforeCfg) {
    $before = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($i in @($beforeCfg.imports)) {
        if ($null -eq $i) { continue }
        $before.Add([string]$i.name) | Out-Null
    }

    $cfg = LoadCfg
    $existingMappings = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($m in @($cfg.mappings)) {
        if ($null -eq $m) { continue }
        $existingMappings.Add(("{0}|{1}" -f [string]$m.vendor, [string]$m.from)) | Out-Null
    }

    $changed = $false
    foreach ($i in @($cfg.imports)) {
        if ($null -eq $i) { continue }
        $mode = if ($i.PSObject.Properties.Match("mode").Count -gt 0) { [string]$i.mode } else { "manual" }
        if ($mode -ne "manual") { continue }
        $name = [string]$i.name
        if ($before.Contains($name)) { continue }
        $key = "manual|{0}" -f $name
        if ($existingMappings.Contains($key)) { continue }
        $cfg.mappings += @{ vendor = "manual"; from = $name; to = $name }
        $existingMappings.Add($key) | Out-Null
        $changed = $true
    }
    if ($changed) { SaveCfg $cfg }
    return $changed
}
