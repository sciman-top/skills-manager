function Get-AuditTargetsConfigPath {
    return (Join-Path $script:Root "audit-targets.json")
}

function Get-AuditOuterAiPromptOverridePath {
    return (Join-Path $script:Root "overrides\audit-outer-ai-prompt.md")
}

function Get-DefaultAuditOuterAiPrompt {
    return @"
# Audit Recommendations Workflow

目标：基于一个当前 run 的 ``snapshot.json`` 完成 ``recommendations.json``，再执行预检与 dry-run；未经明确确认不得 apply。

1. 只读 ``reports/skill-audit/<run-id>/snapshot.json``。先遵守其中 ``native_ai_review``，再从全仓汇总的 ``target_profile.user_need_summary`` 和 ``target_profile.prioritized_needs.primary_needs`` 开始。``target_scans`` 仅用于逐条证据归属、冲突定位和覆盖统计，不是独立的用户需求画像。用宿主 AI 做跨文件的只读语义综合，核对其 ``requirement_signals``、``artifact_capabilities`` 及逐条 evidence；不得用用户长期偏好、个人技术栈或未扫描仓库事实补充整体需求。
2. 重点不是原始命中数量：大仓的文件量、接口/持久化/测试/运维等技术上下文，不能自动等同于用户主需求。只有源代码证据能说明核心用户路径时，才可把次级项提升；必须在结论里写出提升依据和不确定性。
3. 需要澄清语义时，只能读取 snapshot 明确列出的目标仓 evidence 路径及其紧邻实现/测试文件。源代码优先于测试，测试优先于依赖，依赖优先于文档；冲突与低置信度必须保留为 observation 或 ``do_not_install``，不能推断成安装结论。
4. ``removal_candidates`` 与 ``mcp_removal_candidates`` 可以产生，但只能由宿主 AI 的语义裁决产生，不是“画像未命中”的反推。逐项读取当前安装能力、触发条件与替代项：在 ``semantic_review`` 中记录 ``decision_owner=host_ai``、实际能力、一般/专用分类、替代覆盖或过时依据、已知使用事实、迁移、回滚、不确定性及 ``requires_user_confirmation=true``。同名、存在 override、配置依赖可满足、或本次重点需求未命中只能是重叠线索，不能单独证明等价、非使用或可删除。
5. 通用编码能力与专用能力使用同一退役门槛：通用能力不因未成为主需求而降级；专用能力必须比较其独特触发、目标仓主旅程覆盖、替代质量、迁移代价和回滚。usage_evidence.state 可为 ``observed_used``、``observed_unused`` 或 ``unknown``；unknown 保留不确定性，不能伪造为未使用，但也不能阻止有明确替代/过时依据的迁移候选。
6. 用户报告“从未成功调用”时，必须写入 ``overlap_findings`` 的 report-only 观察：注明这是用户报告而非遥测，并将后续动作限定为核对 current profile 投影、宿主可见清单或任务路由。它不能转换为 ``observed_unused``、``removal_candidate`` 或 MCP 卸载结论。
7. 初始 ``recommendations.json`` 是未审阅的空基线，不证明名单最优。新增按当前需求、能力缺口、候选收益和可达性判断；退役按替代/过时、迁移和回滚判断。缺少历史调用记录不能单独推出保留或删除。宿主将具名任务证据填入 ``usage_observations``，区分发现、加载、执行和验收，以及实际观察、用户报告和受控重放。每条新增建议必须有扫描画像理由、真实来源、匹配的 ``source_observations`` 与符合 snapshot policy 的 ``keyword_trace``。不得把 external/system/plugin skills 当作可自动卸载项；MCP payload 不得包含明文凭据。
8. 执行：
   ``.\skills.ps1 审查目标 预检 --recommendations "reports\skill-audit\<run-id>\recommendations.json"``
9. 预检通过后执行：
   ``.\skills.ps1 审查目标 校验预演 --recommendations "reports\skill-audit\<run-id>\recommendations.json" --dry-run-ack "我知道未落盘"``
9. 从 ``receipt.json`` 汇报四类结果、``persisted=false`` 与 truth boundary；任一失败即停止。只有用户明确授权后才可执行 ``--apply --yes``。
"@
}

function Get-AuditOuterAiPromptContent {
    $overridePath = Get-AuditOuterAiPromptOverridePath
    if (Test-Path -LiteralPath $overridePath -PathType Leaf) {
        $content = Get-ContentUtf8 $overridePath
        if (-not [string]::IsNullOrWhiteSpace($content)) {
            return $content
        }
    }
    return (Get-DefaultAuditOuterAiPrompt)
}

function Show-AuditOuterAiPromptTemplate {
    $overridePath = Get-AuditOuterAiPromptOverridePath
    if (Test-Path -LiteralPath $overridePath -PathType Leaf) {
        Write-Host ("当前使用自定义提示词：{0}" -f $overridePath) -ForegroundColor Green
    }
    else {
        Write-Host "当前使用内置默认提示词。" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host (Get-AuditOuterAiPromptContent)
}

function Edit-AuditOuterAiPromptTemplate {
    $path = Get-AuditOuterAiPromptOverridePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Set-ContentUtf8 $path (Get-DefaultAuditOuterAiPrompt)
    }
    Invoke-StartProcess "notepad.exe" ("`"{0}`"" -f $path)
    Write-Host ("已打开提示词文件：{0}" -f $path) -ForegroundColor Green
}

function Test-AuditObjectLike($value) {
    if ($null -eq $value) { return $false }
    return ($value -is [pscustomobject]) -or ($value -is [hashtable]) -or ($value -is [System.Collections.IDictionary])
}

function Get-AuditObjectFieldValue($source, [string]$fieldName, [ref]$value) {
    if ($null -eq $source) { return $false }
    if ($source -is [hashtable] -or $source -is [System.Collections.IDictionary]) {
        if ($source.Contains($fieldName)) {
            $value.Value = $source[$fieldName]
            return $true
        }
        return $false
    }
    if ($source.PSObject.Properties.Match($fieldName).Count -gt 0) {
        $value.Value = $source.$fieldName
        return $true
    }
    return $false
}

function Convert-AuditStringArray($value) {
    if ($null -eq $value) { return @() }
    $items = if (Assert-IsArray $value) { @($value) } else { @($value) }
    $normalized = New-Object System.Collections.Generic.List[string]
    foreach ($item in $items) {
        if ($null -eq $item) { continue }
        $text = [string]$item
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $normalized.Add($text.Trim()) | Out-Null
    }
    return @($normalized)
}

function Convert-AuditObjectArray($value) {
    if ($null -eq $value) { return @() }
    $items = New-Object System.Collections.Generic.List[object]
    if (Assert-IsArray $value) {
        foreach ($item in $value) { if ($null -ne $item) { $items.Add($item) | Out-Null } }
    }
    else {
        $items.Add($value) | Out-Null
    }
    return @($items.ToArray())
}

function New-DefaultAuditTargetsConfig {
    return [pscustomobject]@{
        version = 3
        path_base = "skills_manager_root"
        targets = @()
    }
}

function Save-AuditTargetsConfig($cfg) {
    $json = $cfg | ConvertTo-Json -Depth 20
    Set-ContentUtf8 (Get-AuditTargetsConfigPath) $json
}

function Initialize-AuditTargetsConfig {
    $path = Get-AuditTargetsConfigPath
    if (Test-Path -LiteralPath $path -PathType Leaf) { return $false }
    Save-AuditTargetsConfig (New-DefaultAuditTargetsConfig)
    return $true
}

function Load-AuditTargetsConfig {
    $path = Get-AuditTargetsConfigPath
    Need (Test-Path -LiteralPath $path -PathType Leaf) "缺少 audit-targets.json，请先运行：./skills.ps1 审查目标 初始化"
    $cfg = $null
    $lastError = $null
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        try {
            $raw = Get-ContentUtf8 $path
            if ([string]::IsNullOrWhiteSpace($raw)) {
                throw "audit-targets.json 为空"
            }
            $cfg = $raw | ConvertFrom-Json
            $lastError = $null
            break
        }
        catch {
            $lastError = $_.Exception.Message
            if ($attempt -lt 3) {
                Start-Sleep -Milliseconds 150
                continue
            }
        }
    }
    if ($null -eq $cfg) {
        throw ("audit-targets.json 解析失败：{0}" -f $lastError)
    }

    $changed = $false
    if (-not $cfg.PSObject.Properties.Match("version").Count) {
        $cfg | Add-Member -NotePropertyName version -NotePropertyValue 1
        $changed = $true
    }
    if ([int]$cfg.version -lt 3) {
        $cfg.version = 3
        $changed = $true
    }
    if (-not $cfg.PSObject.Properties.Match("path_base").Count) {
        $cfg | Add-Member -NotePropertyName path_base -NotePropertyValue "skills_manager_root"
        $changed = $true
    }
    if (-not $cfg.PSObject.Properties.Match("targets").Count -or $null -eq $cfg.targets) {
        $cfg | Add-Member -NotePropertyName targets -NotePropertyValue @() -Force
        $changed = $true
    }
    if ($cfg.PSObject.Properties.Match("user_profile").Count -gt 0) {
        $cfg.PSObject.Properties.Remove("user_profile")
        $changed = $true
    }

    Need ([int]$cfg.version -eq 3) "audit-targets.json version 仅支持 3"
    Need ([string]$cfg.path_base -eq "skills_manager_root") "audit-targets.json path_base 仅支持 skills_manager_root"
    if (-not (Assert-IsArray $cfg.targets)) { $cfg.targets = @($cfg.targets) }
    if ($changed) {
        Save-AuditTargetsConfig $cfg
    }
    return $cfg
}

function Resolve-AuditTargetPath([string]$path) {
    Need (-not [string]::IsNullOrWhiteSpace($path)) "目标仓路径不能为空"
    $expanded = [Environment]::ExpandEnvironmentVariables($path.Trim())
    if ($expanded -eq "~" -or $expanded.StartsWith("~\") -or $expanded.StartsWith("~/")) {
        $userHome = [Environment]::GetFolderPath("UserProfile")
        if ($expanded.Length -eq 1) {
            $expanded = $userHome
        }
        else {
            $expanded = Join-Path $userHome $expanded.Substring(2)
        }
    }
    if ([System.IO.Path]::IsPathRooted($expanded)) {
        return [System.IO.Path]::GetFullPath($expanded)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $script:Root $expanded))
}

function Add-AuditTargetConfigEntry([string]$name, [string]$path, [string[]]$tags = @(), [string]$notes = "") {
    Initialize-AuditTargetsConfig | Out-Null
    $cfg = Load-AuditTargetsConfig
    $normName = Normalize-NameWithNotice $name "target 名称"
    Need (-not [string]::IsNullOrWhiteSpace($normName)) "target 名称不能为空"
    Need (-not [string]::IsNullOrWhiteSpace($path)) "target path 不能为空"

    $entry = [pscustomobject]@{
        name = $normName
        path = $path
        enabled = $true
        tags = @($tags | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        notes = $notes
    }

    $existing = @($cfg.targets | Where-Object { $_.name -eq $normName })
    if ($existing.Count -gt 0) {
        $existing[0].path = $entry.path
        $existing[0].enabled = $entry.enabled
        $existing[0].tags = $entry.tags
        $existing[0].notes = $entry.notes
    }
    else {
        $cfg.targets += $entry
    }
    Save-AuditTargetsConfig $cfg
    return $cfg
}

function Update-AuditTargetConfigEntry([string]$name, [string]$path, [string[]]$tags = @(), [string]$notes = "") {
    Initialize-AuditTargetsConfig | Out-Null
    $cfg = Load-AuditTargetsConfig
    $normName = Normalize-NameWithNotice $name "target 名称"
    Need (-not [string]::IsNullOrWhiteSpace($normName)) "target 名称不能为空"
    Need (-not [string]::IsNullOrWhiteSpace($path)) "target path 不能为空"

    $existing = @($cfg.targets | Where-Object { $_.name -eq $normName })
    Need ($existing.Count -gt 0) ("未找到目标仓：{0}" -f $normName)

    $existing[0].path = $path
    $existing[0].enabled = $true
    $existing[0].tags = @($tags | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $existing[0].notes = $notes
    Save-AuditTargetsConfig $cfg
    return $cfg
}

function Remove-AuditTargetConfigEntry([string]$name) {
    Initialize-AuditTargetsConfig | Out-Null
    $cfg = Load-AuditTargetsConfig
    $normName = Normalize-NameWithNotice $name "target 名称"
    Need (-not [string]::IsNullOrWhiteSpace($normName)) "target 名称不能为空"
    $before = @($cfg.targets).Count
    $cfg.targets = @($cfg.targets | Where-Object { $_.name -ne $normName })
    Need (@($cfg.targets).Count -lt $before) ("未找到目标仓：{0}" -f $normName)
    Save-AuditTargetsConfig $cfg
    return $cfg
}

function Write-AuditTargetsList {
    $cfg = Load-AuditTargetsConfig
    $items = @($cfg.targets)
    if ($items.Count -eq 0) {
        Write-Host "未登记目标仓。"
        return
    }
    foreach ($t in $items) {
        $resolved = Resolve-AuditTargetPath ([string]$t.path)
        $exists = Test-Path -LiteralPath $resolved
        $enabled = if ($t.PSObject.Properties.Match("enabled").Count -gt 0) { [bool]$t.enabled } else { $true }
        $enabledText = if ($enabled) { "enabled" } else { "disabled" }
        Write-Host ("- {0} [{1}] {2} -> {3} exists={4}" -f [string]$t.name, $enabledText, [string]$t.path, $resolved, $exists)
    }
}

function Get-AuditRunId {
    return (Get-Date -Format "yyyyMMdd-HHmmss-fff")
}

function Get-AuditPromptContractVersion {
    return "audit-prompt-v20260913.1"
}

function Get-AuditReportRoot([string]$runId) {
    return (Join-Path $script:Root (Join-Path "reports\skill-audit" $runId))
}

function Test-AuditPlaceholderToken([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    return ([regex]::IsMatch($text, "<[^>]+>"))
}

function Get-AuditRunCandidateBuckets([string[]]$RequiredFiles = @()) {
    $auditRoot = Join-Path $script:Root "reports\skill-audit"
    $result = [ordered]@{
        known = New-Object System.Collections.Generic.List[string]
        fresh = New-Object System.Collections.Generic.List[string]
        unknown = New-Object System.Collections.Generic.List[string]
        stale = New-Object System.Collections.Generic.List[string]
        missing_required = New-Object System.Collections.Generic.List[string]
        missing_required_details = New-Object System.Collections.Generic.List[string]
    }
    if (-not (Test-Path -LiteralPath $auditRoot -PathType Container)) {
        return [pscustomobject]@{
            known = @()
            fresh = @()
            unknown = @()
            stale = @()
            missing_required = @()
            missing_required_details = @()
        }
    }
    $dirs = @(
        Get-ChildItem -LiteralPath $auditRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object -Property @{ Expression = { $_.LastWriteTimeUtc }; Descending = $true }, @{ Expression = { $_.Name }; Descending = $true }
    )
    $liveStateResolved = $false
    $liveState = $null
    $liveStateAvailable = $false
    $currentPromptVersion = ""
    foreach ($dir in $dirs) {
        $result.known.Add([string]$dir.Name) | Out-Null
        $ok = $true
        $missing = New-Object System.Collections.Generic.List[string]
        foreach ($relative in @($RequiredFiles)) {
            if (-not (Test-AuditFile $dir.FullName ([string]$relative))) {
                $ok = $false
                $missing.Add([string]$relative) | Out-Null
            }
        }
        if (-not $ok) {
            $result.missing_required.Add([string]$dir.Name) | Out-Null
            $result.missing_required_details.Add(("{0}(缺少: {1})" -f [string]$dir.Name, (($missing.ToArray()) -join ","))) | Out-Null
            continue
        }

        $snapshotPath = Join-Path $dir.FullName "snapshot.json"
        $canCheckStale = Test-Path -LiteralPath $snapshotPath -PathType Leaf
        if (-not $canCheckStale) {
            $result.unknown.Add([string]$dir.Name) | Out-Null
            continue
        }

        if (-not $liveStateResolved) {
            $liveStateResolved = $true
            try {
                $liveState = Get-AuditLiveInstalledState
                $liveStateAvailable = $true
                $currentPromptVersion = Get-AuditPromptContractVersion
            }
            catch {
                $liveStateAvailable = $false
            }
        }
        if (-not $liveStateAvailable) {
            $result.unknown.Add([string]$dir.Name) | Out-Null
            continue
        }

        $isStale = $false
        try {
            $snapshotState = Get-AuditInstalledSnapshotState $snapshotPath
            $snapshotStaleness = Get-AuditInstalledSnapshotStaleness $snapshotState $liveState
            if ([bool]$snapshotStaleness.is_stale) {
                $isStale = $true
            }
        }
        catch {
            $result.unknown.Add([string]$dir.Name) | Out-Null
            continue
        }

        try {
            $snapshotRaw = Get-ContentUtf8 $snapshotPath
            if (-not [string]::IsNullOrWhiteSpace($snapshotRaw)) {
                $snapshot = $snapshotRaw | ConvertFrom-Json
                if ($snapshot.PSObject.Properties.Match("prompt_contract_version").Count -gt 0) {
                    $runPromptVersion = ([string]$snapshot.prompt_contract_version).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($runPromptVersion) -and [string]$runPromptVersion -ne [string]$currentPromptVersion) {
                        $isStale = $true
                    }
                }
            }
        }
        catch {
            $result.unknown.Add([string]$dir.Name) | Out-Null
            continue
        }

        if ($isStale) {
            $result.stale.Add([string]$dir.Name) | Out-Null
        }
        else {
            $result.fresh.Add([string]$dir.Name) | Out-Null
        }
    }

    return [pscustomobject]@{
        known = @($result.known.ToArray())
        fresh = @($result.fresh.ToArray())
        unknown = @($result.unknown.ToArray())
        stale = @($result.stale.ToArray())
        missing_required = @($result.missing_required.ToArray())
        missing_required_details = @($result.missing_required_details.ToArray())
    }
}

function Get-AuditLatestRunId([string[]]$RequiredFiles = @()) {
    $buckets = Get-AuditRunCandidateBuckets -RequiredFiles $RequiredFiles
    if (@($buckets.fresh).Count -gt 0) { return [string]$buckets.fresh[0] }
    if (@($buckets.unknown).Count -gt 0) { return [string]$buckets.unknown[0] }
    return ""
}

function Resolve-AuditRunIdInput([string]$runId, [string]$FlagName = "--run-id", [string[]]$RequiredFiles = @()) {
    if ([string]::IsNullOrWhiteSpace($runId)) { return $runId }
    $trimmed = [string]$runId
    if (-not (Test-AuditPlaceholderToken $trimmed)) { return $trimmed }
    if ([regex]::IsMatch($trimmed, "<\s*run[-_]?id\s*>", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        $resolved = Get-AuditLatestRunId -RequiredFiles $RequiredFiles
        if (-not [string]::IsNullOrWhiteSpace($resolved)) {
            return $resolved
        }
        throw ("{0} 使用占位符但未找到可用 run-id。{1}" -f $FlagName, (Get-AuditRunIdHintText $RequiredFiles))
    }
    throw ("{0} 包含未替换占位符：{1}`n{2}" -f $FlagName, $runId, (Get-AuditRunIdHintText $RequiredFiles))
}

function Resolve-AuditPathRunIdPlaceholder([string]$path, [string]$FlagName = "--recommendations", [string[]]$RequiredFiles = @()) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $path }
    if (-not (Test-AuditPlaceholderToken $path)) { return $path }
    if (-not [regex]::IsMatch($path, "<\s*run[-_]?id\s*>", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        throw ("{0} 路径包含未替换占位符：{1}`n{2}" -f $FlagName, $path, (Get-AuditRunIdHintText $RequiredFiles))
    }

    $resolvedRunId = Get-AuditLatestRunId -RequiredFiles $RequiredFiles
    if ([string]::IsNullOrWhiteSpace($resolvedRunId)) {
        throw ("{0} 路径使用 <run-id> 占位符但未找到可用 run。{1}" -f $FlagName, (Get-AuditRunIdHintText $RequiredFiles))
    }
    $resolvedPath = [regex]::Replace($path, "<\s*run[-_]?id\s*>", [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $resolvedRunId }, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (Test-AuditPlaceholderToken $resolvedPath) {
        throw ("{0} 路径仍包含未替换占位符：{1}`n{2}" -f $FlagName, $resolvedPath, (Get-AuditRunIdHintText $RequiredFiles))
    }
    return $resolvedPath
}

function Get-AuditRunIdHintText([string[]]$RequiredFiles = @()) {
    $buckets = Get-AuditRunCandidateBuckets -RequiredFiles $RequiredFiles
    $ids = @($buckets.known)
    if (@($ids).Count -eq 0) {
        return "可用 run-id：无（先执行 .\skills.ps1 审查目标 扫描）"
    }
    if (@($RequiredFiles).Count -eq 0) {
        return ("可用 run-id：{0}" -f ($ids -join ", "))
    }

    if (@($buckets.fresh).Count -gt 0) {
        return ("可用 fresh run-id：{0}" -f ((@($buckets.fresh)) -join ", "))
    }

    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add("可用 fresh run-id：无（先执行 .\skills.ps1 审查目标 扫描）") | Out-Null
    if (@($buckets.stale).Count -gt 0) {
        $parts.Add(("stale run-id：{0}" -f ((@($buckets.stale)) -join ", "))) | Out-Null
    }
    if (@($buckets.unknown).Count -gt 0) {
        $parts.Add(("未校验 freshness 的候选 run-id：{0}" -f ((@($buckets.unknown)) -join ", "))) | Out-Null
    }
    if (@($buckets.missing_required_details).Count -gt 0) {
        $parts.Add(("缺少必要文件的 run-id：{0}" -f ((@($buckets.missing_required_details)) -join "; "))) | Out-Null
    }
    return (($parts.ToArray()) -join "; ")
}

function Get-AuditKeywordsFromText([string]$text, [int]$Limit = 120) {
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $ordered = New-Object System.Collections.Generic.List[string]
    foreach ($match in [regex]::Matches($text, "(?i)\b[a-z][a-z0-9_-]{2,}\b")) {
        $token = ([string]$match.Value).Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($token)) { continue }
        if ($seen.Add($token)) {
            $ordered.Add($token) | Out-Null
            if ($ordered.Count -ge $Limit) { return @($ordered) }
        }
    }
    foreach ($match in [regex]::Matches($text, "[\u4e00-\u9fff]{2,}")) {
        $token = ([string]$match.Value).Trim()
        if ([string]::IsNullOrWhiteSpace($token)) { continue }
        if ($seen.Add($token)) {
            $ordered.Add($token) | Out-Null
            if ($ordered.Count -ge $Limit) { return @($ordered) }
        }
    }
    return @($ordered)
}

function Merge-AuditKeywordSets([object[]]$Sets, [int]$Limit = 160) {
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $ordered = New-Object System.Collections.Generic.List[string]
    foreach ($set in @($Sets)) {
        foreach ($token in @(Convert-AuditStringArray $set)) {
            if ($seen.Add($token)) {
                $ordered.Add($token) | Out-Null
                if ($ordered.Count -ge $Limit) { return @($ordered) }
            }
        }
    }
    return @($ordered)
}

function Merge-AuditArtifactCapabilities($scans) {
    $accumulator = @{}
    foreach ($scan in @($scans)) {
        $target = Get-CfgObjectProperty $scan "target"
        $targetName = [string](Get-CfgObjectProperty $target "name")
        $detected = Get-CfgObjectProperty $scan "detected"
        foreach ($capability in @(Convert-AuditObjectArray (Get-CfgObjectProperty $detected "artifact_capabilities"))) {
            $artifact = [string](Get-CfgObjectProperty $capability "artifact")
            foreach ($action in @(Convert-AuditStringArray (Get-CfgObjectProperty $capability "actions"))) {
                $evidence = @(Convert-AuditObjectArray (Get-CfgObjectProperty $capability "evidence"))
                if ($evidence.Count -eq 0) {
                    Add-AuditArtifactEvidence $accumulator $artifact $action "documentation" "" "legacy_artifact_signal" $targetName
                    continue
                }
                foreach ($item in $evidence) {
                    Add-AuditArtifactEvidence $accumulator $artifact $action ([string](Get-CfgObjectProperty $item "kind")) ([string](Get-CfgObjectProperty $item "path")) ([string](Get-CfgObjectProperty $item "signal")) $targetName
                }
            }
        }
    }
    return @(ConvertTo-AuditArtifactCapabilityArray $accumulator)
}

function Merge-AuditRequirementSignals($scans) {
    $accumulator = @{}
    foreach ($scan in @($scans)) {
        $target = Get-CfgObjectProperty $scan "target"
        $targetName = [string](Get-CfgObjectProperty $target "name")
        $detected = Get-CfgObjectProperty $scan "detected"
        foreach ($signal in @(Convert-AuditObjectArray (Get-CfgObjectProperty $detected "requirement_signals"))) {
            $domain = [string](Get-CfgObjectProperty $signal "domain")
            $subject = [string](Get-CfgObjectProperty $signal "subject")
            foreach ($action in @(Convert-AuditStringArray (Get-CfgObjectProperty $signal "actions"))) {
                $evidence = @(Convert-AuditObjectArray (Get-CfgObjectProperty $signal "evidence"))
                if ($evidence.Count -eq 0) {
                    Add-AuditRequirementEvidence $accumulator $domain $subject $action "documentation" "" "legacy_requirement_signal" $targetName
                    continue
                }
                foreach ($item in $evidence) {
                    Add-AuditRequirementEvidence $accumulator $domain $subject $action ([string](Get-CfgObjectProperty $item "kind")) ([string](Get-CfgObjectProperty $item "path")) ([string](Get-CfgObjectProperty $item "signal")) $targetName
                }
            }
        }
    }
    return @(ConvertTo-AuditRequirementSignalArray $accumulator)
}

function Get-AuditNeedEvidenceCoverage($entry) {
    $kinds = @("source_code", "supporting_code", "test", "dependency", "documentation")
    $targetsByKind = @{}
    $countByKind = @{}
    foreach ($kind in $kinds) {
        $targetsByKind[$kind] = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
        $countByKind[$kind] = 0
    }
    foreach ($evidence in @(Convert-AuditObjectArray (Get-CfgObjectProperty $entry "evidence"))) {
        $kind = [string](Get-CfgObjectProperty $evidence "kind")
        if ($kind -notin $kinds) { continue }
        $countByKind[$kind] = [int]$countByKind[$kind] + 1
        $target = ([string](Get-CfgObjectProperty $evidence "target")).Trim()
        if (-not [string]::IsNullOrWhiteSpace($target)) { $targetsByKind[$kind].Add($target) | Out-Null }
    }
    $allTargets = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($kind in $kinds) { foreach ($target in $targetsByKind[$kind]) { $allTargets.Add($target) | Out-Null } }
    return [pscustomobject]([ordered]@{
            source_code_target_count = $targetsByKind["source_code"].Count
            supporting_code_target_count = $targetsByKind["supporting_code"].Count
            test_target_count = $targetsByKind["test"].Count
            dependency_target_count = $targetsByKind["dependency"].Count
            documentation_target_count = $targetsByKind["documentation"].Count
            distinct_target_count = $allTargets.Count
            source_code_evidence_count = [int]$countByKind["source_code"]
            supporting_code_evidence_count = [int]$countByKind["supporting_code"]
            test_evidence_count = [int]$countByKind["test"]
            dependency_evidence_count = [int]$countByKind["dependency"]
            documentation_evidence_count = [int]$countByKind["documentation"]
        })
}

function Get-AuditNeedRole([string]$Kind, [string]$Domain, [string]$Subject) {
    if ($Kind -eq "artifact") { return "supporting_artifact" }
    $key = ("{0}/{1}" -f $Domain.Trim().ToLowerInvariant(), $Subject.Trim().ToLowerInvariant())
    if ($key -in @("workflow/document_processing", "workflow/ocr", "workflow/analytics", "ai/content_generation")) { return "product_workflow" }
    if ($key -in @("interface/web_ui", "interface/desktop_ui", "integration/http_api", "data/persistence")) { return "delivery_surface" }
    if ($key -in @("automation/browser_automation", "quality/automated_testing", "operations/backup_recovery")) { return "engineering_or_operations" }
    return "unclassified"
}

function New-AuditPrioritizedNeed {
    param(
        $Entry,
        [ValidateSet("requirement", "artifact")][string]$Kind,
        [int]$MinimumProductWorkflowSourceTargetCount = 1
    )
    $domain = if ($Kind -eq "requirement") { [string](Get-CfgObjectProperty $Entry "domain") } else { "artifact" }
    $subject = if ($Kind -eq "requirement") { [string](Get-CfgObjectProperty $Entry "subject") } else { [string](Get-CfgObjectProperty $Entry "artifact") }
    $role = Get-AuditNeedRole $Kind $domain $subject
    $coverage = Get-AuditNeedEvidenceCoverage $Entry
    $score = 0
    if ([int]$coverage.source_code_target_count -gt 0) {
        $score += 45
        $score += [Math]::Min(3, [Math]::Max(0, [int]$coverage.source_code_target_count - 1)) * 8
    }
    if ([int]$coverage.test_target_count -gt 0) { $score += 6 }
    if ([int]$coverage.dependency_target_count -gt 0) { $score += 4 }
    if ([int]$coverage.documentation_target_count -gt 0) { $score += 2 }
    switch ($role) {
        "product_workflow" { $score += 18 }
        "supporting_artifact" { $score += 12 }
        "delivery_surface" { $score += 4 }
    }
    if ([int]$coverage.source_code_target_count -eq 0) { $score = [Math]::Min($score, 35) }
    $limitations = New-Object System.Collections.Generic.List[string]
    if ([int]$coverage.source_code_target_count -eq 0) { $limitations.Add("no_implemented_source_evidence") | Out-Null }
    if ([int]$coverage.supporting_code_target_count -gt 0) { $limitations.Add("supporting_code_not_direct_product_journey") | Out-Null }
    if ([int]$coverage.source_code_target_count -lt 2) { $limitations.Add("single_target_or_unattributed_source_support") | Out-Null }
    if ([int]$coverage.test_target_count -eq 0) { $limitations.Add("no_test_evidence") | Out-Null }
    if ($role -in @("delivery_surface", "engineering_or_operations")) { $limitations.Add("technical_context_not_direct_product_intent") | Out-Null }
    $band = "observation"
    if ([int]$coverage.source_code_target_count -gt 0) {
        if ($role -eq "product_workflow" -and [int]$coverage.source_code_target_count -ge $MinimumProductWorkflowSourceTargetCount -and $score -ge 63) { $band = "primary_candidate" }
        elseif ($role -eq "supporting_artifact" -and [int]$coverage.source_code_target_count -ge 2 -and $score -ge 65) { $band = "primary_candidate" }
        else { $band = "secondary" }
    }
    elseif ([int]$coverage.dependency_target_count -gt 0) {
        $band = "secondary"
    }
    $label = if ($Kind -eq "artifact") { $subject } else { "{0}/{1}" -f $domain, $subject }
    return [pscustomobject]([ordered]@{
            key = $label
            kind = $Kind
            domain = $domain
            subject = $subject
            role = $role
            priority_score = [int][Math]::Min(100, $score)
            priority_band = $band
            confidence = [string](Get-CfgObjectProperty $Entry "confidence")
            evidence_status = [string](Get-CfgObjectProperty $Entry "evidence_status")
            actions = @(Convert-AuditStringArray (Get-CfgObjectProperty $Entry "actions"))
            targets = @(Convert-AuditStringArray (Get-CfgObjectProperty $Entry "targets"))
            evidence_coverage = $coverage
            limitations = @($limitations.ToArray())
        })
}

function New-AuditPrioritizedNeeds($RequirementSignals, $ArtifactCapabilities, [int]$MinimumProductWorkflowSourceTargetCount = 1) {
    $requirements = @(
        foreach ($signal in @(Convert-AuditObjectArray $RequirementSignals)) { New-AuditPrioritizedNeed $signal "requirement" $MinimumProductWorkflowSourceTargetCount }
    )
    $artifacts = @(
        foreach ($artifact in @(Convert-AuditObjectArray $ArtifactCapabilities)) { New-AuditPrioritizedNeed $artifact "artifact" }
    )
    $primaryCandidates = @($requirements | Where-Object priority_band -eq "primary_candidate" | Sort-Object @{ Expression = "priority_score"; Descending = $true }, key)
    $primary = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in @($primaryCandidates | Select-Object -First 5)) {
        $candidate.priority_band = "primary"
        $primary.Add($candidate) | Out-Null
    }
    $secondary = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in @($requirements | Sort-Object @{ Expression = "priority_score"; Descending = $true }, key)) {
        if (@($primary | Where-Object key -eq $candidate.key).Count -gt 0) { continue }
        if ($candidate.priority_band -eq "primary_candidate") { $candidate.priority_band = "secondary" }
        if ($candidate.priority_band -eq "secondary") { $secondary.Add($candidate) | Out-Null }
    }
    $observations = @($requirements | Where-Object priority_band -eq "observation" | Sort-Object @{ Expression = "priority_score"; Descending = $true }, key)
    return [pscustomobject]([ordered]@{
            schema_version = 1
            ranking_method = "role_then_source_coverage_v2"
            policy = @(
                "Raw evidence count does not determine priority; source-backed distinct target coverage is capped to avoid large-repository bias.",
                "A multi-target portfolio requires implemented source evidence from at least two targets before the scanner automatically promotes a product workflow to primary; a host-AI review may explicitly promote a single-target core user journey with recorded evidence and uncertainty.",
                "Product workflows can become primary candidates; delivery, engineering, and operations signals remain context unless host AI verifies a core user journey.",
                "Documentation-only evidence remains an observation and must not justify an install, removal, or MCP mutation."
            )
            primary_needs = @($primary.ToArray())
            secondary_needs = @($secondary.ToArray())
            supporting_artifacts = @($artifacts | Sort-Object @{ Expression = "priority_score"; Descending = $true }, key)
            observations = @($observations)
    })
}

function New-AuditUserNeedSummary($prioritizedNeeds, [int]$TargetCount = 0) {
    $primary = New-Object System.Collections.Generic.List[object]
    foreach ($need in @(Convert-AuditObjectArray (Get-CfgObjectProperty $prioritizedNeeds "primary_needs"))) {
        $coverage = Get-CfgObjectProperty $need "evidence_coverage"
        $primary.Add([pscustomobject]([ordered]@{
                    key = [string](Get-CfgObjectProperty $need "key")
                    role = [string](Get-CfgObjectProperty $need "role")
                    confidence = [string](Get-CfgObjectProperty $need "confidence")
                    evidence_status = [string](Get-CfgObjectProperty $need "evidence_status")
                    target_scope = @(Convert-AuditStringArray (Get-CfgObjectProperty $need "targets"))
                    source_code_target_count = [int](Get-CfgObjectProperty $coverage "source_code_target_count")
                    limitations = @(Convert-AuditStringArray (Get-CfgObjectProperty $need "limitations"))
                })) | Out-Null
    }
    return [pscustomobject]([ordered]@{
            derivation = "target_scans_only"
            scope = "portfolio"
            profile_kind = "portfolio_capability_profile"
            primary_needs = @($primary.ToArray())
            interpretation_rules = @(
                "This is the aggregate user-need summary across all enabled target repositories.",
                "Target-level scan partitions are evidence attribution only; they must not be treated as separate user-need profiles.",
                "A listed limitation is an uncertainty boundary, not evidence of absence or a reason to add, remove, or configure a capability."
            )
        })
}

function New-AuditTargetEvidencePartitions($scans) {
    $profiles = New-Object System.Collections.Generic.List[object]
    foreach ($scan in @($scans)) {
        $target = Get-CfgObjectProperty $scan "target"
        $targetName = [string](Get-CfgObjectProperty $target "name")
        $requirements = @(Merge-AuditRequirementSignals @($scan))
        $artifacts = @(Merge-AuditArtifactCapabilities @($scan))
        $needs = New-AuditPrioritizedNeeds $requirements $artifacts
        $profiles.Add([pscustomobject]([ordered]@{
                    target = $targetName
                    scan_risks = @(Convert-AuditStringArray (Get-CfgObjectProperty $scan "risks"))
                    prioritized_needs = $needs
                })) | Out-Null
    }
    return @($profiles.ToArray() | Sort-Object target)
}

function Get-AuditPrioritizedNeedKeywords($prioritizedNeeds) {
    if ($null -eq $prioritizedNeeds) { return @() }
    $sets = New-Object System.Collections.Generic.List[object]
    foreach ($need in @(Convert-AuditObjectArray (Get-CfgObjectProperty $prioritizedNeeds "primary_needs"))) {
        $sets.Add(@([string](Get-CfgObjectProperty $need "domain"), [string](Get-CfgObjectProperty $need "subject"), [string](Get-CfgObjectProperty $need "key"))) | Out-Null
        foreach ($action in @(Convert-AuditStringArray (Get-CfgObjectProperty $need "actions"))) { $sets.Add(@($action, ("{0}_{1}" -f [string](Get-CfgObjectProperty $need "subject"), $action))) | Out-Null }
    }
    return @(Merge-AuditKeywordSets @($sets.ToArray()) 80)
}

function Get-AuditArtifactCapabilityKeywords($capabilities) {
    $sets = New-Object System.Collections.Generic.List[object]
    foreach ($capability in @(Convert-AuditObjectArray $capabilities)) {
        $artifact = [string](Get-CfgObjectProperty $capability "artifact")
        if ([string]::IsNullOrWhiteSpace($artifact)) { continue }
        $sets.Add(@($artifact)) | Out-Null
        foreach ($action in @(Convert-AuditStringArray (Get-CfgObjectProperty $capability "actions"))) {
            $sets.Add(@($action, ("{0}_{1}" -f $artifact, $action))) | Out-Null
        }
    }
    return @(Merge-AuditKeywordSets @($sets.ToArray()) 80)
}

function Get-AuditRequirementSignalKeywords($signals) {
    $sets = New-Object System.Collections.Generic.List[object]
    foreach ($signal in @(Convert-AuditObjectArray $signals)) {
        $domain = [string](Get-CfgObjectProperty $signal "domain")
        $subject = [string](Get-CfgObjectProperty $signal "subject")
        if (-not [string]::IsNullOrWhiteSpace($domain)) { $sets.Add(@($domain)) | Out-Null }
        if ([string]::IsNullOrWhiteSpace($subject)) { continue }
        $sets.Add(@($subject, ("{0}_{1}" -f $domain, $subject))) | Out-Null
        foreach ($action in @(Convert-AuditStringArray (Get-CfgObjectProperty $signal "actions"))) {
            $sets.Add(@($action, ("{0}_{1}" -f $subject, $action))) | Out-Null
        }
    }
    return @(Merge-AuditKeywordSets @($sets.ToArray()) 120)
}

function Get-AuditRepoScanKeywords($scan) {
    if ($null -eq $scan) { return @() }
    $sets = New-Object System.Collections.Generic.List[object]
    $targetValue = $null
    if (Get-AuditObjectFieldValue $scan "target" ([ref]$targetValue) -and $null -ne $targetValue) {
        $targetName = $null
        if (Get-AuditObjectFieldValue $targetValue "name" ([ref]$targetName)) {
            $sets.Add((Get-AuditKeywordsFromText ([string]$targetName) 12)) | Out-Null
        }
    }
    $detectedValue = $null
    if (Get-AuditObjectFieldValue $scan "detected" ([ref]$detectedValue) -and $null -ne $detectedValue) {
        foreach ($name in @("languages", "package_managers", "frameworks", "build_commands", "test_commands", "capabilities", "agent_rule_files", "notable_files")) {
            $fieldValue = $null
            if (Get-AuditObjectFieldValue $detectedValue $name ([ref]$fieldValue)) {
                $sets.Add((Convert-AuditStringArray $fieldValue)) | Out-Null
            }
        }
        $sets.Add((Get-AuditArtifactCapabilityKeywords (Get-CfgObjectProperty $detectedValue "artifact_capabilities"))) | Out-Null
        $sets.Add((Get-AuditRequirementSignalKeywords (Get-CfgObjectProperty $detectedValue "requirement_signals"))) | Out-Null
    }
    $riskValue = $null
    if (Get-AuditObjectFieldValue $scan "risks" ([ref]$riskValue)) {
        $sets.Add((Convert-AuditStringArray $riskValue)) | Out-Null
    }
    return (Merge-AuditKeywordSets ($sets.ToArray()) 180)
}

function Get-AuditInstalledStateKeywords($installedSkills, $installedMcpServers) {
    $sets = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($installedSkills)) {
        $sets.Add((Get-AuditKeywordsFromText ([string]$item.name) 20)) | Out-Null
        $sets.Add((Get-AuditKeywordsFromText ([string]$item.description) 30)) | Out-Null
        $sets.Add((Get-AuditKeywordsFromText ([string]$item.trigger_summary) 30)) | Out-Null
        $sets.Add((Convert-AuditStringArray @([string]$item.vendor, [string]$item.source_kind))) | Out-Null
    }
    foreach ($server in @($installedMcpServers)) {
        $sets.Add((Convert-AuditStringArray @([string]$server.name, [string]$server.transport))) | Out-Null
    }
    return (Merge-AuditKeywordSets ($sets.ToArray()) 240)
}

function Normalize-AuditCoveragePhrase([string]$Text) {
    # Subject phrases and prose use different separators ("web_ui" vs "web ui");
    # normalizing both sides to single spaces lets one phrase form match the other.
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    return ((($Text -replace '[_\-]+', ' ') -replace '\s+', ' ').Trim().ToLowerInvariant())
}

function Get-AuditCoverageNeedTokens($Need) {
    # Coverage is asserted from the subject phrase only.  The bare domain word
    # ("workflow", "ai", "artifact", ...) matches too many descriptions to carry
    # signal, and action verbs hit homographs ("read" in "read-only", "deliver"
    # in "deliverable") that assert coverage the skill does not provide.
    $domain = [string](Get-CfgObjectProperty $Need "domain")
    $subject = Normalize-AuditCoveragePhrase ([string](Get-CfgObjectProperty $Need "subject"))
    if ([string]::IsNullOrWhiteSpace($subject) -or [string]::Equals($subject, (Normalize-AuditCoveragePhrase $domain), [System.StringComparison]::OrdinalIgnoreCase)) { return @() }
    return @($subject)
}

function Get-AuditCoverageKeywordMatches($NeedTokens, $Skills) {
    $matched = New-Object System.Collections.Generic.List[string]
    foreach ($skill in @(Convert-AuditObjectArray $Skills)) {
        $hayText = (([string](Get-CfgObjectProperty $skill "name")) + ' ' + ([string](Get-CfgObjectProperty $skill "description")) + ' ' + ([string](Get-CfgObjectProperty $skill "trigger_summary")) + ' ' + ((Convert-AuditStringArray (Get-CfgObjectProperty $skill "enabled_tools")) -join ' '))
        $hay = Normalize-AuditCoveragePhrase $hayText
        if ([string]::IsNullOrWhiteSpace($hay)) { continue }
        foreach ($token in @($NeedTokens)) {
            if (-not [string]::IsNullOrWhiteSpace($token) -and $hay.Contains($token)) { Add-AuditUniqueValue $matched ([string](Get-CfgObjectProperty $skill "name")); break }
        }
    }
    return @($matched.ToArray() | Sort-Object -Unique)
}

function New-AuditCoverageStatement($PrioritizedNeeds, $ProfileSelectedSkills, $CatalogSupplySkills, $ExternalSkills = @(), $McpServers = @()) {
    # A positive coverage assertion: for each prioritized need, which current-profile
    # skills plausibly cover it, which cold-catalog skills would additionally cover
    # it, and which host-native (external) skills or MCP servers already expose it.
    # Subject-phrase plausibility only — never a proof of host loading or successful
    # invocation — so that "no add needed" and profile-promotion questions become
    # checkable against data instead of intuition.
    $skills = @(Convert-AuditObjectArray $ProfileSelectedSkills)
    $catalogSkills = @(Convert-AuditObjectArray $CatalogSupplySkills)
    $externalSkills = @(Convert-AuditObjectArray $ExternalSkills)
    $mcpServers = @(Convert-AuditObjectArray $McpServers)
    if ($skills.Count -eq 0 -and $catalogSkills.Count -eq 0 -and $externalSkills.Count -eq 0 -and $mcpServers.Count -eq 0) { return @() }
    $statement = @()
    $needs = @()
    foreach ($need in @(Convert-AuditObjectArray (Get-CfgObjectProperty $PrioritizedNeeds "primary_needs"))) { $needs += $need }
    foreach ($need in @(Convert-AuditObjectArray (Get-CfgObjectProperty $PrioritizedNeeds "secondary_needs"))) { $needs += $need }
    foreach ($need in @(Convert-AuditObjectArray (Get-CfgObjectProperty $PrioritizedNeeds "supporting_artifacts"))) { $needs += $need }
    foreach ($need in @($needs)) {
        $needTokens = @(Get-AuditCoverageNeedTokens $need)
        $matched = @(Get-AuditCoverageKeywordMatches $needTokens $skills)
        $catalogMatched = @(Get-AuditCoverageKeywordMatches $needTokens $catalogSkills)
        $coldCatalogMatched = @($catalogMatched | Where-Object { $_ -notin $matched })
        $externalMatched = @((Get-AuditCoverageKeywordMatches $needTokens $externalSkills) | Where-Object { $_ -notin $matched })
        $mcpMatched = @(Get-AuditCoverageKeywordMatches $needTokens $mcpServers)
        $statement += [pscustomobject]([ordered]@{
                need = [string](Get-CfgObjectProperty $need "key")
                priority_band = [string](Get-CfgObjectProperty $need "priority_band")
                covered_by = $matched
                coverage = if (@($matched).Count -gt 0) { "keyword_plausibly_covered_by_profile" } else { "keyword_unmatched_by_profile" }
                cold_catalog_covered_by = @($coldCatalogMatched | Sort-Object -Unique)
                external_covered_by = @($externalMatched | Sort-Object -Unique)
                mcp_covered_by = @($mcpMatched | Sort-Object -Unique)
            })
    }
    return @($statement)
}

function New-AuditTargetProfile($scans, $ProfileSelectedSkills = $null, $CatalogSupplySkills = $null, $ExternalSkills = @(), $McpServers = @()) {
    Need (@($scans).Count -gt 0) "扫描画像至少需要一个目标仓扫描结果。"
    $completedScans = @($scans | Where-Object {
        (Get-CfgObjectProperty (Get-CfgObjectProperty $_ "scan_coverage") "confidence_ceiling") -ne "skipped_dirty"
    })
    $fields = @("languages", "package_managers", "frameworks", "build_commands", "test_commands", "capabilities", "agent_rule_files", "notable_files", "risks")
    $profile = [ordered]@{
        schema_version = 3
        derived_at = (Get-Date).ToString("o")
        derivation = "target_scans_only"
        target_names = @()
        scanned_target_count = $completedScans.Count
        skipped_target_count = @($scans).Count - $completedScans.Count
    }
    foreach ($field in $fields) { $profile[$field] = @() }
    $values = @{}
    foreach ($field in $fields) { $values[$field] = New-Object System.Collections.Generic.List[object] }
    $targetNames = New-Object System.Collections.Generic.List[string]
    foreach ($scan in @($scans)) {
        $target = Get-CfgObjectProperty $scan "target"
        $name = [string](Get-CfgObjectProperty $target "name")
        if (-not [string]::IsNullOrWhiteSpace($name)) { Add-AuditUniqueValue $targetNames $name }
        $detected = Get-CfgObjectProperty $scan "detected"
        foreach ($field in $fields) {
            $value = Get-CfgObjectProperty $detected $field
            foreach ($item in @(Convert-AuditStringArray $value)) { $values[$field].Add($item) | Out-Null }
        }
        foreach ($item in @(Convert-AuditStringArray (Get-CfgObjectProperty $scan "risks"))) { $values["risks"].Add($item) | Out-Null }
    }
    $profile.target_names = @($targetNames)
    $profile.profile_kind = "portfolio_capability_profile"
    $profile.scope = "portfolio"
    foreach ($field in $fields) { $profile[$field] = @(Merge-AuditKeywordSets @($values[$field].ToArray()) 160) }
    $profile.artifact_capabilities = @(Merge-AuditArtifactCapabilities $scans)
    $profile.requirement_signals = @(Merge-AuditRequirementSignals $scans)
    $minimumProductWorkflowSourceTargetCount = if ($completedScans.Count -gt 1) { 2 } else { 1 }
    $profile.prioritized_needs = New-AuditPrioritizedNeeds $profile.requirement_signals $profile.artifact_capabilities $minimumProductWorkflowSourceTargetCount
    $profile.user_need_summary = New-AuditUserNeedSummary $profile.prioritized_needs $completedScans.Count
    $profile.target_evidence_partitions = @(New-AuditTargetEvidencePartitions $scans)
    $profile.coverage_statement = @(New-AuditCoverageStatement $profile.prioritized_needs $ProfileSelectedSkills $CatalogSupplySkills $ExternalSkills $McpServers)
    $technology = @($profile.languages + $profile.frameworks + $profile.package_managers | Select-Object -First 8)
    $capability = @($profile.capabilities | Select-Object -First 6)
    $primary = @($profile.prioritized_needs.primary_needs | ForEach-Object { [string]$_.key })
    $secondaryCount = @($profile.prioritized_needs.secondary_needs).Count
    $observationCount = @($profile.prioritized_needs.observations).Count
    $primaryText = if ($primary.Count -gt 0) { $primary -join ', ' } else { "无达到主需求阈值的扫描信号" }
    $profile.summary = "由 $($profile.scanned_target_count) 个已扫描目标仓派生的全仓汇总画像（跳过=$($profile.skipped_target_count)）；重点需求：$primaryText；次级需求=$secondaryCount；观察项=$observationCount。目标仓扫描仅用于证据归属与覆盖统计；技术信号：$($technology -join ', ')；能力信号：$($capability -join ', ')。"
    return [pscustomobject]$profile
}

function New-AuditDecisionInsights($targetProfile, $scans, $installedSkills, $installedMcpServers, $installedState = $null, $externalSkills = @()) {
    $repoKeywordSets = @()
    foreach ($scan in @($scans)) {
        $targetValue = Get-CfgObjectProperty $scan "target"
        $targetNameValue = Get-CfgObjectProperty $targetValue "name"
        $targetName = if ([string]::IsNullOrWhiteSpace([string]$targetNameValue)) { "*" } else { [string]$targetNameValue }
        $repoKeywordSets += [pscustomobject]([ordered]@{
                target = $targetName
                keywords = @(Get-AuditRepoScanKeywords $scan)
                risks = if ($scan.PSObject.Properties.Match("risks").Count -gt 0) { @(Convert-AuditStringArray $scan.risks) } else { @() }
            })
    }
    $primaryFocusKeywords = @(Get-AuditPrioritizedNeedKeywords (Get-CfgObjectProperty $targetProfile "prioritized_needs"))
    $profileKeywords = @(Merge-AuditKeywordSets @(
            $primaryFocusKeywords,
            (Convert-AuditStringArray $targetProfile.target_names),
            (Convert-AuditStringArray $targetProfile.languages),
            (Convert-AuditStringArray $targetProfile.package_managers),
            (Convert-AuditStringArray $targetProfile.frameworks),
            (Convert-AuditStringArray $targetProfile.build_commands),
            (Convert-AuditStringArray $targetProfile.test_commands),
            (Convert-AuditStringArray $targetProfile.capabilities),
            (Get-AuditArtifactCapabilityKeywords (Get-CfgObjectProperty $targetProfile "artifact_capabilities")),
            (Get-AuditRequirementSignalKeywords (Get-CfgObjectProperty $targetProfile "requirement_signals")),
            (Convert-AuditStringArray $targetProfile.agent_rule_files),
            (Convert-AuditStringArray $targetProfile.notable_files),
            (Convert-AuditStringArray $targetProfile.risks)
        ) 220)
    $installedKeywords = @(Get-AuditInstalledStateKeywords @($installedSkills + $externalSkills) $installedMcpServers)
    $configuredSupplyCount = 0
    $profileSelectedCount = @($installedSkills).Count
    $invocationEvidenceState = 'not_observed'
    if ($null -ne $installedState) {
        if ($installedState.PSObject.Properties.Match('configured_supply_skills').Count -gt 0) { $configuredSupplyCount = @($installedState.configured_supply_skills).Count }
        if ($installedState.PSObject.Properties.Match('skills').Count -gt 0) { $profileSelectedCount = @($installedState.skills).Count }
        if ($installedState.PSObject.Properties.Match('invocation_evidence').Count -gt 0 -and $null -ne $installedState.invocation_evidence -and $installedState.invocation_evidence.PSObject.Properties.Match('state').Count -gt 0) {
            $invocationEvidenceState = [string]$installedState.invocation_evidence.state
        }
    }
    return [pscustomobject]([ordered]@{
            schema_version = 1
            generated_at = (Get-Date).ToString("o")
            derivation = "target_scans_only"
            summary = [ordered]@{
                target_profile_keyword_count = @($profileKeywords).Count
                primary_need_count = @(Convert-AuditObjectArray (Get-CfgObjectProperty (Get-CfgObjectProperty $targetProfile "prioritized_needs") "primary_needs")).Count
                secondary_need_count = @(Convert-AuditObjectArray (Get-CfgObjectProperty (Get-CfgObjectProperty $targetProfile "prioritized_needs") "secondary_needs")).Count
                installed_state_keyword_count = @($installedKeywords).Count
                installed_skill_count = @($installedSkills).Count
                external_skill_count = @($externalSkills).Count
                installed_mcp_server_count = @($installedMcpServers).Count
                configured_supply_skill_count = $configuredSupplyCount
                current_profile_selected_skill_count = $profileSelectedCount
                invocation_evidence_state = $invocationEvidenceState
            }
            keywords = [ordered]@{
                primary_target_profile = @($primaryFocusKeywords)
                target_profile = @($profileKeywords)
                target_repo = @($profileKeywords)
                installed_state = @($installedKeywords)
            }
            target_repo_by_target = @($repoKeywordSets)
            targets = @($repoKeywordSets)
            decision_checklist = @(
                "Start with target_profile.user_need_summary and target_profile.prioritized_needs.primary_needs; prevalence alone is not a user-priority claim.",
                "Scan all enabled target repositories and use target_scans only for evidence attribution, conflict localization, and coverage accounting.",
                "A host-AI promotion from secondary/context to primary requires inspected source evidence of a core user journey and a recorded uncertainty boundary.",
                "Each add/remove recommendation should keep keyword_trace.target_profile with keywords from decision-insights.keywords.target_profile.",
                "keyword_trace.installed_state should align with decision-insights.keywords.installed_state."
                "installed_state.skills contains current-profile selections only; configured supply is source and rollback context, not a live callable inventory."
                "not_observed is scanner telemetry absence, not non-use or a veto on additions and supported retirement. Review explicit usage_observations separately; usage affects migration and verification, not whether a candidate may be reviewed."
                "The aggregate profile is the only user-need decision surface; target_repo_by_target is evidence attribution, not a per-repository recommendation surface."
            )
        })
}

function Write-AuditJsonFile([string]$path, $data) {
    EnsureDir (Split-Path $path -Parent)
    Set-ContentUtf8 $path ($data | ConvertTo-Json -Depth 40)
}

function Get-AuditReceiptPath([string]$recommendationsPath) {
    $dir = Split-Path $recommendationsPath -Parent
    if ([string]::IsNullOrWhiteSpace($dir)) { $dir = "." }
    return (Join-Path $dir "receipt.json")
}

function Read-AuditSnapshot([string]$recommendationDir) {
    if ([string]::IsNullOrWhiteSpace($recommendationDir)) { $recommendationDir = "." }
    $path = Join-Path $recommendationDir "snapshot.json"
    Need (Test-Path -LiteralPath $path -PathType Leaf) ("缺少 snapshot.json：{0}" -f $path)
    try { $snapshot = Get-ContentUtf8 $path | ConvertFrom-Json }
    catch { throw ("snapshot.json 解析失败：{0}" -f $_.Exception.Message) }
    Need ($null -ne $snapshot -and [int]$snapshot.schema_version -eq 2) ("snapshot.json schema_version 无效：{0}" -f $path)
    return $snapshot
}

function Write-AuditReceiptSection([string]$recommendationsPath, [string]$section, $data) {
    $path = Get-AuditReceiptPath $recommendationsPath
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try { $receipt = Get-ContentUtf8 $path | ConvertFrom-Json }
        catch { throw ("receipt.json 解析失败：{0}" -f $_.Exception.Message) }
    }
    else {
        $receipt = [pscustomobject]([ordered]@{
            schema_version = 1
            run_id = Split-Path (Split-Path $recommendationsPath -Parent) -Leaf
            mode = "audit"
            created_at = (Get-Date).ToString("o")
            updated_at = $null
            success = $false
            persisted = $false
            truth_boundary = "receipt_created_not_applied"
        })
    }
    if ($receipt.PSObject.Properties.Match($section).Count -eq 0) {
        $receipt | Add-Member -NotePropertyName $section -NotePropertyValue $data
    }
    else { $receipt.$section = $data }
    $receipt | Add-Member -NotePropertyName updated_at -NotePropertyValue ((Get-Date).ToString("o")) -Force
    if ($null -ne $data) {
        if ($data.PSObject.Properties.Match("run_id").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$data.run_id)) { $receipt | Add-Member -NotePropertyName run_id -NotePropertyValue ([string]$data.run_id) -Force }
        if ($data.PSObject.Properties.Match("mode").Count -gt 0) { $receipt | Add-Member -NotePropertyName mode -NotePropertyValue ([string]$data.mode) -Force }
        if ($data.PSObject.Properties.Match("success").Count -gt 0) { $receipt | Add-Member -NotePropertyName success -NotePropertyValue ([bool]$data.success) -Force }
        if ($data.PSObject.Properties.Match("persisted").Count -gt 0) { $receipt | Add-Member -NotePropertyName persisted -NotePropertyValue ([bool]$data.persisted) -Force }
    }
    $truthBoundary = if ([bool]$receipt.persisted) { "filesystem_changes_persisted_not_host_loaded" } elseif ($section -eq "scan") { "repo_snapshot_created_not_reviewed_not_applied" } else { "repo_verified_not_applied" }
    $receipt | Add-Member -NotePropertyName truth_boundary -NotePropertyValue $truthBoundary -Force
    Write-AuditJsonFile $path $receipt
    return $path
}
