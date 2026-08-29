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
5. 通用编码能力与专用能力使用同一退役门槛：通用能力不因未成为主需求而降级；专用能力必须比较其独特触发、目标仓主旅程覆盖、替代质量、迁移代价和回滚。静态扫描不能得知实际使用频率时写 ``usage_evidence.state=unknown``，保留不确定性并等待当前用户在 ``--apply --yes`` 的明确确认，绝不伪造为未使用。
6. 用户报告“从未成功调用”时，必须写入 ``overlap_findings`` 的 report-only 观察：注明这是用户报告而非遥测，并将后续动作限定为核对 current profile 投影、宿主可见清单或任务路由。它不能转换为 ``observed_unused``、``removal_candidate`` 或 MCP 卸载结论。
7. 初始生成的 ``recommendations.json`` 是可预检的零变更裁决，不是待填写的示例。只有在扫描画像、当前 profile 的有效能力、调用/可达性证据与审阅来源共同形成明确缺口时，才替换零变更理由并加入变更项；零变更是完整、有效的结论。每条新增建议必须有扫描画像理由、真实来源、匹配的 ``source_observations`` 与符合 snapshot policy 的 ``keyword_trace``。不得把 external/system/plugin skills 当作可自动卸载项；MCP payload 不得包含明文凭据。
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
    return "audit-prompt-v20260829.3"
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

function Test-AuditFile([string]$root, [string]$relative) {
    return (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)
}

function Add-AuditUniqueValue([System.Collections.Generic.List[string]]$items, [string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return }
    if (-not $items.Contains($value)) { $items.Add($value) | Out-Null }
}

function Get-AuditPackageJson([string]$root) {
    $path = Join-Path $root "package.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { return (Get-ContentUtf8 $path | ConvertFrom-Json) }
    catch { return $null }
}

function Get-AuditPackagePropertyNames($obj, [string]$propertyName) {
    if ($null -eq $obj) { return @() }
    if (-not $obj.PSObject.Properties.Match($propertyName).Count) { return @() }
    $value = $obj.$propertyName
    if ($null -eq $value) { return @() }
    return @($value.PSObject.Properties | ForEach-Object { $_.Name })
}

function Get-AuditPackageScriptNames($pkg) {
    if ($null -eq $pkg) { return @() }
    if (-not $pkg.PSObject.Properties.Match("scripts").Count -or $null -eq $pkg.scripts) { return @() }
    return @($pkg.scripts.PSObject.Properties | ForEach-Object { $_.Name })
}

function Get-AuditRepositoryRelativePath([string]$root, [string]$fullPath) {
    if ([string]::IsNullOrWhiteSpace($root) -or [string]::IsNullOrWhiteSpace($fullPath)) { return $fullPath }
    try {
        $normalizedRoot = [System.IO.Path]::GetFullPath($root).TrimEnd('\', '/')
        $normalizedPath = [System.IO.Path]::GetFullPath($fullPath)
        if ($normalizedPath.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $normalizedPath.Substring($normalizedRoot.Length).TrimStart('\', '/').Replace('/', '\')
        }
    }
    catch {
    }
    return $fullPath
}

function Add-AuditCommandsFromText([string]$content, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$testCommands) {
    if ([string]::IsNullOrWhiteSpace($content)) { return }
    if ([regex]::IsMatch($content, "(?im)\bdotnet\s+build\b")) { Add-AuditUniqueValue $buildCommands "dotnet build" }
    if ([regex]::IsMatch($content, "(?im)\bdotnet\s+test\b")) { Add-AuditUniqueValue $testCommands "dotnet test" }
    if ([regex]::IsMatch($content, "(?im)\bnpm\s+run\s+build\b")) { Add-AuditUniqueValue $buildCommands "npm run build" }
    if ([regex]::IsMatch($content, "(?im)\bnpm\s+test\b")) { Add-AuditUniqueValue $testCommands "npm test" }
    if ([regex]::IsMatch($content, "(?im)\bpnpm\s+build\b")) { Add-AuditUniqueValue $buildCommands "pnpm build" }
    if ([regex]::IsMatch($content, "(?im)\bpnpm\s+test\b")) { Add-AuditUniqueValue $testCommands "pnpm test" }
    if ([regex]::IsMatch($content, "(?im)\byarn\s+build\b")) { Add-AuditUniqueValue $buildCommands "yarn build" }
    if ([regex]::IsMatch($content, "(?im)\byarn\s+test\b")) { Add-AuditUniqueValue $testCommands "yarn test" }
    if ([regex]::IsMatch($content, "(?im)\buv\s+run\s+pytest\b")) { Add-AuditUniqueValue $testCommands "uv run pytest" }
    if ([regex]::IsMatch($content, "(?im)\bpoetry\s+run\s+pytest\b")) { Add-AuditUniqueValue $testCommands "poetry run pytest" }
    if ([regex]::IsMatch($content, "(?im)\bpytest\b")) { Add-AuditUniqueValue $testCommands "pytest" }
}

function Add-AuditPowerShellFacts([string]$resolvedPath, [System.Collections.Generic.List[string]]$languages, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$testCommands, [System.Collections.Generic.List[string]]$notableFiles) {
    $buildPath = Join-Path $resolvedPath "build.ps1"
    if (Test-Path -LiteralPath $buildPath -PathType Leaf) {
        Add-AuditUniqueValue $languages "powershell"
        Add-AuditUniqueValue $buildCommands "pwsh -NoProfile -ExecutionPolicy Bypass -File build.ps1"
        Add-AuditUniqueValue $notableFiles "build.ps1"
    }
    $testPath = Join-Path $resolvedPath "tests\run.ps1"
    if (Test-Path -LiteralPath $testPath -PathType Leaf) {
        Add-AuditUniqueValue $languages "powershell"
        Add-AuditUniqueValue $testCommands "pwsh -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1"
        Add-AuditUniqueValue $notableFiles "tests\run.ps1"
    }
    if (@(Get-ChildItem -LiteralPath $resolvedPath -Filter "*.ps1" -File -ErrorAction SilentlyContinue).Count -gt 0) {
        Add-AuditUniqueValue $languages "powershell"
    }
}

function Add-AuditDocumentedCommandFacts([string]$resolvedPath, [System.Collections.Generic.List[string]]$languages, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$testCommands, [System.Collections.Generic.List[string]]$notableFiles) {
    foreach ($relativePath in @("README.md", "AGENTS.md", "CLAUDE.md", "GEMINI.md")) {
        $path = Join-Path $resolvedPath $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        try { $content = Get-ContentUtf8 $path }
        catch { continue }
        foreach ($match in [regex]::Matches($content, '`(?<command>(?:pwsh|powershell|python|uv|poetry|pytest|dotnet|npm|pnpm|yarn)\b[^`\r\n]{1,500})`', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $command = ([string]$match.Groups["command"].Value).Trim()
            if ([string]::IsNullOrWhiteSpace($command)) { continue }
            if ($command -match "(?i)^(?:pwsh|powershell)(?:\.exe)?\b") { Add-AuditUniqueValue $languages "powershell" }
            if ($command -match "(?i)^(?:python|uv|poetry|pytest)\b") { Add-AuditUniqueValue $languages "python" }
            if ($command -match "(?i)(?:\bbuild(?:\.ps1)?\b|\bpy_compile\b|\bdotnet\s+build\b|\b(?:npm|pnpm|yarn)\s+(?:run\s+)?build\b)") {
                Add-AuditUniqueValue $buildCommands $command
            }
            if ($command -match "(?i)(?:tests?[\\/]run\.ps1\b|\bpytest\b|\bunittest\b|\bdotnet\s+test\b|\b(?:npm|pnpm|yarn)\s+(?:run\s+)?test\b)") {
                Add-AuditUniqueValue $testCommands $command
            }
        }
        Add-AuditUniqueValue $notableFiles $relativePath
    }
}

function Add-AuditCiWorkflowFacts([string]$resolvedPath, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$testCommands, [System.Collections.Generic.List[string]]$notableFiles) {
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($fileName in @("azure-pipelines.yml", ".gitlab-ci.yml")) {
        $candidate = Join-Path $resolvedPath $fileName
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $candidates.Add($candidate) | Out-Null
        }
    }
    $githubWorkflowDir = Join-Path $resolvedPath ".github\workflows"
    if (Test-Path -LiteralPath $githubWorkflowDir -PathType Container) {
        $workflowFiles = @(
            Get-ChildItem -LiteralPath $githubWorkflowDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @(".yml", ".yaml") } |
            Select-Object -First 20
        )
        foreach ($wf in $workflowFiles) {
            $candidates.Add($wf.FullName) | Out-Null
        }
    }

    foreach ($filePath in @($candidates)) {
        Add-AuditUniqueValue $notableFiles (Get-AuditRepositoryRelativePath $resolvedPath $filePath)
        try {
            $content = Get-ContentUtf8 $filePath
        }
        catch {
            continue
        }
        Add-AuditCommandsFromText $content $buildCommands $testCommands
    }
}

function Add-AuditPyProjectFacts([string]$resolvedPath, [System.Collections.Generic.List[string]]$frameworks, [System.Collections.Generic.List[string]]$packageManagers, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$testCommands, [System.Collections.Generic.List[string]]$notableFiles) {
    $path = Join-Path $resolvedPath "pyproject.toml"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    Add-AuditUniqueValue $notableFiles "pyproject.toml"
    $content = ""
    try {
        $content = Get-ContentUtf8 $path
    }
    catch {
        return
    }
    if ([regex]::IsMatch($content, "(?im)^\s*\[tool\.poetry\]")) {
        Add-AuditUniqueValue $packageManagers "poetry"
        Add-AuditUniqueValue $buildCommands "poetry build"
    }
    if ([regex]::IsMatch($content, "(?im)^\s*\[tool\.uv\]")) {
        Add-AuditUniqueValue $packageManagers "uv"
        Add-AuditUniqueValue $buildCommands "uv build"
    }
    if ([regex]::IsMatch($content, "(?im)^\s*\[tool\.hatch")) {
        Add-AuditUniqueValue $packageManagers "hatch"
        Add-AuditUniqueValue $buildCommands "hatch build"
    }
    if ([regex]::IsMatch($content, "(?im)^\s*\[tool\.pdm")) {
        Add-AuditUniqueValue $packageManagers "pdm"
        Add-AuditUniqueValue $buildCommands "pdm build"
    }
    if ([regex]::IsMatch($content, "(?i)\bfastapi\b")) { Add-AuditUniqueValue $frameworks "fastapi" }
    if ([regex]::IsMatch($content, "(?i)\bdjango\b")) { Add-AuditUniqueValue $frameworks "django" }
    if ([regex]::IsMatch($content, "(?i)\bflask\b")) { Add-AuditUniqueValue $frameworks "flask" }
    if ([regex]::IsMatch($content, "(?i)\bpytest\b")) { Add-AuditUniqueValue $testCommands "pytest" }
}

function Add-AuditMakefileFacts([string]$resolvedPath, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$testCommands, [System.Collections.Generic.List[string]]$notableFiles) {
    foreach ($name in @("Makefile", "makefile", "GNUmakefile")) {
        $path = Join-Path $resolvedPath $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        Add-AuditUniqueValue $notableFiles $name
        $content = ""
        try {
            $content = Get-ContentUtf8 $path
        }
        catch {
            continue
        }
        if ([regex]::IsMatch($content, "(?im)^\s*build\s*:")) { Add-AuditUniqueValue $buildCommands "make build" }
        if ([regex]::IsMatch($content, "(?im)^\s*(test|check)\s*:")) { Add-AuditUniqueValue $testCommands "make test" }
        if ([regex]::IsMatch($content, "(?im)^\s*ci\s*:")) { Add-AuditUniqueValue $testCommands "make ci" }
    }
}

function Add-AuditJavaFacts([string]$resolvedPath, [System.Collections.Generic.List[string]]$languages, [System.Collections.Generic.List[string]]$frameworks, [System.Collections.Generic.List[string]]$packageManagers, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$testCommands, [System.Collections.Generic.List[string]]$notableFiles) {
    $pomPath = Join-Path $resolvedPath "pom.xml"
    $gradleCandidates = @("build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts")
    $hasPom = Test-Path -LiteralPath $pomPath -PathType Leaf
    $hasGradle = $false
    foreach ($gradleFile in @($gradleCandidates)) {
        if (Test-Path -LiteralPath (Join-Path $resolvedPath $gradleFile) -PathType Leaf) {
            $hasGradle = $true
            Add-AuditUniqueValue $notableFiles $gradleFile
        }
    }
    if (-not $hasPom -and -not $hasGradle) { return }

    Add-AuditUniqueValue $languages "java"
    if ($hasPom) {
        Add-AuditUniqueValue $notableFiles "pom.xml"
        Add-AuditUniqueValue $packageManagers "maven"
        Add-AuditUniqueValue $buildCommands "mvn -B -DskipTests package"
        Add-AuditUniqueValue $testCommands "mvn -B test"
        try {
            $pomRaw = Get-ContentUtf8 $pomPath
            if ([regex]::IsMatch($pomRaw, "(?i)spring-boot")) { Add-AuditUniqueValue $frameworks "spring-boot" }
            if ([regex]::IsMatch($pomRaw, "(?i)junit")) { Add-AuditUniqueValue $testCommands "mvn -B test" }
        }
        catch {
        }
    }
    if ($hasGradle) {
        Add-AuditUniqueValue $packageManagers "gradle"
        Add-AuditUniqueValue $buildCommands "gradle build"
        Add-AuditUniqueValue $testCommands "gradle test"
        foreach ($gradleFile in @("build.gradle", "build.gradle.kts")) {
            $gradlePath = Join-Path $resolvedPath $gradleFile
            if (-not (Test-Path -LiteralPath $gradlePath -PathType Leaf)) { continue }
            try {
                $gradleRaw = Get-ContentUtf8 $gradlePath
                if ([regex]::IsMatch($gradleRaw, "(?i)spring-boot")) { Add-AuditUniqueValue $frameworks "spring-boot" }
            }
            catch {
            }
        }
    }
    if (Test-Path -LiteralPath (Join-Path $resolvedPath "mvnw") -PathType Leaf) {
        Add-AuditUniqueValue $notableFiles "mvnw"
        Add-AuditUniqueValue $buildCommands "./mvnw -B -DskipTests package"
        Add-AuditUniqueValue $testCommands "./mvnw -B test"
    }
    if (Test-Path -LiteralPath (Join-Path $resolvedPath "gradlew") -PathType Leaf) {
        Add-AuditUniqueValue $notableFiles "gradlew"
        Add-AuditUniqueValue $buildCommands "./gradlew build"
        Add-AuditUniqueValue $testCommands "./gradlew test"
    }
}

function Add-AuditRubyFacts([string]$resolvedPath, [System.Collections.Generic.List[string]]$languages, [System.Collections.Generic.List[string]]$frameworks, [System.Collections.Generic.List[string]]$packageManagers, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$testCommands, [System.Collections.Generic.List[string]]$notableFiles) {
    $gemfilePath = Join-Path $resolvedPath "Gemfile"
    $gemspecFiles = @(Get-ChildItem -LiteralPath $resolvedPath -Filter "*.gemspec" -File -ErrorAction SilentlyContinue | Select-Object -First 10)
    $hasGemfile = Test-Path -LiteralPath $gemfilePath -PathType Leaf
    if (-not $hasGemfile -and $gemspecFiles.Count -eq 0) { return }

    Add-AuditUniqueValue $languages "ruby"
    Add-AuditUniqueValue $packageManagers "bundler"
    Add-AuditUniqueValue $buildCommands "bundle install"
    Add-AuditUniqueValue $testCommands "bundle exec rspec"
    if ($hasGemfile) {
        Add-AuditUniqueValue $notableFiles "Gemfile"
        try {
            $gemRaw = Get-ContentUtf8 $gemfilePath
            if ([regex]::IsMatch($gemRaw, "(?i)\brails\b")) { Add-AuditUniqueValue $frameworks "rails" }
            if ([regex]::IsMatch($gemRaw, "(?i)\brspec\b")) { Add-AuditUniqueValue $testCommands "bundle exec rspec" }
            if ([regex]::IsMatch($gemRaw, "(?i)\bminitest\b")) { Add-AuditUniqueValue $testCommands "bundle exec ruby -Itest" }
        }
        catch {
        }
    }
    if (Test-Path -LiteralPath (Join-Path $resolvedPath "Gemfile.lock") -PathType Leaf) {
        Add-AuditUniqueValue $notableFiles "Gemfile.lock"
    }
    if (Test-Path -LiteralPath (Join-Path $resolvedPath "Rakefile") -PathType Leaf) {
        Add-AuditUniqueValue $notableFiles "Rakefile"
        Add-AuditUniqueValue $buildCommands "bundle exec rake build"
    }
    foreach ($gemspec in @($gemspecFiles)) {
        Add-AuditUniqueValue $notableFiles (Get-AuditRepositoryRelativePath $resolvedPath $gemspec.FullName)
    }
}

function Add-AuditPhpFacts([string]$resolvedPath, [System.Collections.Generic.List[string]]$languages, [System.Collections.Generic.List[string]]$frameworks, [System.Collections.Generic.List[string]]$packageManagers, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$testCommands, [System.Collections.Generic.List[string]]$notableFiles) {
    $composerPath = Join-Path $resolvedPath "composer.json"
    if (-not (Test-Path -LiteralPath $composerPath -PathType Leaf)) { return }
    Add-AuditUniqueValue $languages "php"
    Add-AuditUniqueValue $packageManagers "composer"
    Add-AuditUniqueValue $notableFiles "composer.json"
    Add-AuditUniqueValue $buildCommands "composer install --no-interaction"
    Add-AuditUniqueValue $testCommands "composer test"
    try {
        $composer = Get-ContentUtf8 $composerPath | ConvertFrom-Json
        $deps = @()
        $deps += Get-AuditPackagePropertyNames $composer "require"
        $deps += Get-AuditPackagePropertyNames $composer "require-dev"
        foreach ($dep in $deps) {
            if ([string]$dep -match "(?i)^laravel/framework$") { Add-AuditUniqueValue $frameworks "laravel" }
            if ([string]$dep -match "(?i)^symfony/") { Add-AuditUniqueValue $frameworks "symfony" }
            if ([string]$dep -match "(?i)^phpunit/phpunit$") { Add-AuditUniqueValue $testCommands "vendor/bin/phpunit" }
        }
        $scripts = Get-AuditPackagePropertyNames $composer "scripts"
        if ($scripts -contains "test") { Add-AuditUniqueValue $testCommands "composer test" }
        if ($scripts -contains "build") { Add-AuditUniqueValue $buildCommands "composer build" }
    }
    catch {
    }
    foreach ($phpunit in @("phpunit.xml", "phpunit.xml.dist")) {
        if (Test-Path -LiteralPath (Join-Path $resolvedPath $phpunit) -PathType Leaf) {
            Add-AuditUniqueValue $notableFiles $phpunit
            Add-AuditUniqueValue $testCommands "vendor/bin/phpunit"
        }
    }
    if (Test-Path -LiteralPath (Join-Path $resolvedPath "composer.lock") -PathType Leaf) {
        Add-AuditUniqueValue $notableFiles "composer.lock"
    }
}

function Add-AuditContainerFacts([string]$resolvedPath, [System.Collections.Generic.List[string]]$frameworks, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$notableFiles) {
    $hasContainer = $false
    foreach ($dockerFile in @("Dockerfile", "docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml")) {
        $path = Join-Path $resolvedPath $dockerFile
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        Add-AuditUniqueValue $notableFiles $dockerFile
        $hasContainer = $true
    }
    if (-not $hasContainer) { return }
    Add-AuditUniqueValue $frameworks "docker"
    Add-AuditUniqueValue $buildCommands "docker build ."
    Add-AuditUniqueValue $buildCommands "docker compose up --build"
}

function Add-AuditMonorepoFacts([string]$resolvedPath, [System.Collections.Generic.List[string]]$frameworks, [System.Collections.Generic.List[string]]$packageManagers, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$testCommands, [System.Collections.Generic.List[string]]$notableFiles) {
    if (Test-Path -LiteralPath (Join-Path $resolvedPath "pnpm-workspace.yaml") -PathType Leaf) {
        Add-AuditUniqueValue $notableFiles "pnpm-workspace.yaml"
        Add-AuditUniqueValue $frameworks "monorepo"
        Add-AuditUniqueValue $packageManagers "pnpm"
        Add-AuditUniqueValue $buildCommands "pnpm -r build"
        Add-AuditUniqueValue $testCommands "pnpm -r test"
    }
    if (Test-Path -LiteralPath (Join-Path $resolvedPath "turbo.json") -PathType Leaf) {
        Add-AuditUniqueValue $notableFiles "turbo.json"
        Add-AuditUniqueValue $frameworks "turbo"
        Add-AuditUniqueValue $frameworks "monorepo"
        Add-AuditUniqueValue $buildCommands "npx turbo run build"
        Add-AuditUniqueValue $testCommands "npx turbo run test"
    }
    if (Test-Path -LiteralPath (Join-Path $resolvedPath "nx.json") -PathType Leaf) {
        Add-AuditUniqueValue $notableFiles "nx.json"
        Add-AuditUniqueValue $frameworks "nx"
        Add-AuditUniqueValue $frameworks "monorepo"
        Add-AuditUniqueValue $buildCommands "npx nx run-many -t build"
        Add-AuditUniqueValue $testCommands "npx nx run-many -t test"
    }
    if (Test-Path -LiteralPath (Join-Path $resolvedPath "lerna.json") -PathType Leaf) {
        Add-AuditUniqueValue $notableFiles "lerna.json"
        Add-AuditUniqueValue $frameworks "lerna"
        Add-AuditUniqueValue $frameworks "monorepo"
        Add-AuditUniqueValue $buildCommands "npx lerna run build"
        Add-AuditUniqueValue $testCommands "npx lerna run test"
    }
}

function Get-AuditGeneratedPathSegments([string]$resolvedPath) {
    $cacheKey = [System.IO.Path]::GetFullPath($resolvedPath).TrimEnd('\', '/')
    if ($null -eq $script:AuditGeneratedPathSegmentsCache) { $script:AuditGeneratedPathSegmentsCache = @{} }
    if ($script:AuditGeneratedPathSegmentsCache.ContainsKey($cacheKey)) {
        return @($script:AuditGeneratedPathSegmentsCache[$cacheKey])
    }
    $segments = New-Object System.Collections.Generic.List[string]
    foreach ($name in @(
            '.git', '.runtime', '.worktrees', '.txn', '.agent-build', '.tmp', '.artifacts',
            '.cache', '.pytest_cache', '.next', '.nuxt', '.vite', '.turbo', '.gradle',
            'node_modules', 'vendor', 'imports', 'reports', 'artifacts', 'bin', 'obj',
            'dist', 'build', 'out', 'coverage', 'tmp', 'temp', 'target', '__pycache__',
            '.venv', 'venv', 'env'
        )) {
        Add-AuditUniqueValue $segments $name
    }
    $configPath = Join-Path $resolvedPath 'skills.json'
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        try {
            $cfg = Get-ContentUtf8 $configPath | ConvertFrom-Json
            $managedPath = [string](Get-CfgObjectProperty (Get-CfgObjectProperty $cfg 'skill_projection') 'managed_source_path')
            if (-not [string]::IsNullOrWhiteSpace($managedPath)) {
                $firstSegment = @($managedPath -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
                if ($firstSegment.Count -eq 1) { Add-AuditUniqueValue $segments ([string]$firstSegment[0]) }
            }
        }
        catch {
            # A malformed local config must not weaken the static generated-path exclusions.
        }
    }
    $resolvedSegments = @($segments.ToArray())
    $script:AuditGeneratedPathSegmentsCache[$cacheKey] = $resolvedSegments
    return @($resolvedSegments)
}

function Test-AuditIgnoredRecursivePath([string]$resolvedPath, [string]$candidatePath) {
    $relativePath = Get-AuditRepositoryRelativePath $resolvedPath $candidatePath
    $segments = @($relativePath -split '[\\/]')
    $ignored = @(Get-AuditGeneratedPathSegments $resolvedPath)
    foreach ($segment in $segments) {
        if ($segment -in $ignored) { return $true }
    }
    return $false
}

function Get-AuditRecursiveFiles([string]$resolvedPath, [string]$filter, [int]$limit = 40) {
    return @(
        Get-ChildItem -LiteralPath $resolvedPath -Filter $filter -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { -not (Test-AuditIgnoredRecursivePath $resolvedPath $_.FullName) } |
            Select-Object -First $limit
    )
}

function Get-AuditSourceFileIndex([string]$resolvedPath) {
    # Source scanning is the hot path.  Several language/manifest probes already
    # walk the same tree; keep one deterministic, filtered index per target so the
    # expensive recursive enumeration is not repeated for every probe.
    $cacheKey = [System.IO.Path]::GetFullPath($resolvedPath).TrimEnd('\', '/')
    if ($null -eq $script:AuditSourceFileIndexCache) { $script:AuditSourceFileIndexCache = @{} }
    if ($script:AuditSourceFileIndexCache.ContainsKey($cacheKey)) {
        return @($script:AuditSourceFileIndexCache[$cacheKey])
    }
    $extensions = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($extension in @('.cs', '.fs', '.vb', '.py', '.js', '.jsx', '.ts', '.tsx', '.java', '.kt', '.go', '.rs', '.rb', '.php', '.ps1')) {
        $null = $extensions.Add($extension)
    }
    $files = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($fullPath in [System.IO.Directory]::EnumerateFiles($resolvedPath, '*', [System.IO.SearchOption]::AllDirectories)) {
            if (Test-AuditIgnoredRecursivePath $resolvedPath $fullPath) { continue }
            if (-not $extensions.Contains([System.IO.Path]::GetExtension($fullPath))) { continue }
            try { $files.Add([System.IO.FileInfo]::new($fullPath)) | Out-Null } catch { continue }
        }
    }
    catch {
        # Preserve the previous best-effort behaviour if a provider/ACL blocks
        # .NET enumeration part-way through a tree.
        $files.Clear()
        foreach ($file in @(Get-ChildItem -LiteralPath $resolvedPath -File -Recurse -ErrorAction SilentlyContinue)) {
            if ((Test-AuditIgnoredRecursivePath $resolvedPath $file.FullName) -or -not $extensions.Contains($file.Extension)) { continue }
            $files.Add($file) | Out-Null
        }
    }
    $result = @($files.ToArray() | Sort-Object FullName)
    $script:AuditSourceFileIndexCache[$cacheKey] = $result
    return $result
}

function Get-AuditSourceEvidenceKind([string]$RelativePath) {
    $normalized = ([string]$RelativePath).Replace('/', '\')
    if ($normalized -match '(?i)(^|\\)(tests?|spec|__tests__|testdata)(\\|$)|(?i)(test|spec)\.[a-z0-9]+$') { return "test" }
    if ($normalized -match '(?i)(^|\\)(examples?|samples?|fixtures?|mocks?|stubs?|benchmarks?|demos?)(\\|$)') { return "non_product_code" }
    if ($normalized -match '(?i)(^|\\)(tools|scripts|build|migrations?)(\\|$)') { return "supporting_code" }
    return "source_code"
}

function Select-AuditBalancedSourceFiles([string]$resolvedPath, [object[]]$Files, [int]$Limit = 600) {
    if ($Limit -le 0 -or @($Files).Count -eq 0) { return @() }
    if (@($Files).Count -le $Limit) { return @($Files) }

    # A lexical prefix can omit entire applications in a large repository.  Round-robin
    # across two-level source areas so a bounded scan remains representative and repeatable.
    $buckets = @{}
    foreach ($file in @($Files | Sort-Object FullName)) {
        $relative = Get-AuditRepositoryRelativePath $resolvedPath $file.FullName
        $segments = @($relative -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $directoryCount = [Math]::Max(0, $segments.Count - 1)
        $bucketDepth = [Math]::Min(2, $directoryCount)
        $bucket = if ($bucketDepth -eq 0) { '(root)' } else { ($segments | Select-Object -First $bucketDepth) -join '/' }
        if (-not $buckets.ContainsKey($bucket)) {
            $buckets[$bucket] = New-Object System.Collections.Generic.Queue[object]
        }
        $buckets[$bucket].Enqueue($file)
    }

    $selected = New-Object System.Collections.Generic.List[object]
    $keys = @($buckets.Keys | Sort-Object)
    while ($selected.Count -lt $Limit) {
        $added = $false
        foreach ($key in $keys) {
            $queue = $buckets[$key]
            if ($queue.Count -eq 0) { continue }
            $selected.Add($queue.Dequeue()) | Out-Null
            $added = $true
            if ($selected.Count -ge $Limit) { break }
        }
        if (-not $added) { break }
    }
    return @($selected.ToArray() | Sort-Object FullName)
}

function New-AuditArtifactCapabilityAccumulator {
    return @{}
}

function Add-AuditArtifactEvidence {
    param(
        $Accumulator,
        [string]$Artifact,
        [string]$Action,
        [string]$Kind,
        [string]$Path,
        [string]$Signal,
        [string]$Target = ""
    )
    if ($null -eq $Accumulator -or [string]::IsNullOrWhiteSpace($Artifact) -or [string]::IsNullOrWhiteSpace($Action)) { return }
    $artifactKey = $Artifact.Trim().ToLowerInvariant()
    $actionKey = $Action.Trim().ToLowerInvariant()
    if (-not $Accumulator.ContainsKey($artifactKey)) {
        $Accumulator[$artifactKey] = [pscustomobject]@{
            artifact = $artifactKey
            actions = New-Object System.Collections.Generic.List[string]
            evidence = New-Object System.Collections.Generic.List[object]
            targets = New-Object System.Collections.Generic.List[string]
        }
    }
    $entry = $Accumulator[$artifactKey]
    Add-AuditUniqueValue $entry.actions $actionKey
    if (-not [string]::IsNullOrWhiteSpace($Target)) { Add-AuditUniqueValue $entry.targets $Target.Trim() }
    $evidenceKey = "{0}|{1}|{2}|{3}" -f $Kind, $Path, $Signal, $Target
    foreach ($existing in @($entry.evidence.ToArray())) {
        $existingKey = "{0}|{1}|{2}|{3}" -f [string]$existing.kind, [string]$existing.path, [string]$existing.signal, [string]$existing.target
        if ($existingKey -eq $evidenceKey) { return }
    }
    if ($entry.evidence.Count -ge 48) { return }
    $evidence = [ordered]@{
        kind = $Kind
        path = $Path
        signal = $Signal
    }
    if (-not [string]::IsNullOrWhiteSpace($Target)) { $evidence.target = $Target.Trim() }
    $entry.evidence.Add([pscustomobject]$evidence) | Out-Null
}

function Get-AuditArtifactConfidence($entry) {
    $kinds = @($entry.evidence | ForEach-Object { [string]$_.kind })
    if (@($kinds | Where-Object { $_ -in @("source_code", "supporting_code") }).Count -gt 0) { return "high" }
    if (@($kinds | Where-Object { $_ -eq "test" }).Count -gt 0) { return "medium" }
    if (@($kinds | Where-Object { $_ -eq "dependency" }).Count -gt 0) { return "medium" }
    return "low"
}

function Get-AuditArtifactEvidenceStatus($entry) {
    $kinds = @($entry.evidence | ForEach-Object { [string]$_.kind })
    if (@($kinds | Where-Object { $_ -in @("source_code", "supporting_code") }).Count -gt 0) { return "implemented" }
    if (@($kinds | Where-Object { $_ -eq "test" }).Count -gt 0) { return "test_covered" }
    if (@($kinds | Where-Object { $_ -eq "dependency" }).Count -gt 0) { return "dependency_indicated" }
    return "documented"
}

function ConvertTo-AuditArtifactCapabilityArray($Accumulator) {
    if ($null -eq $Accumulator) { return @() }
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @($Accumulator.Values | Sort-Object artifact)) {
        $result.Add([pscustomobject]([ordered]@{
                    artifact = [string]$entry.artifact
                    actions = @($entry.actions | Sort-Object)
                    confidence = Get-AuditArtifactConfidence $entry
                    evidence_status = Get-AuditArtifactEvidenceStatus $entry
                    targets = @($entry.targets | Sort-Object)
                    evidence = @($entry.evidence.ToArray())
                })) | Out-Null
    }
    return @($result.ToArray())
}

function New-AuditRequirementSignalAccumulator {
    return @{}
}

function Add-AuditRequirementEvidence {
    param(
        $Accumulator,
        [string]$Domain,
        [string]$Subject,
        [string]$Action,
        [string]$Kind,
        [string]$Path,
        [string]$Signal,
        [string]$Target = ""
    )
    if ($null -eq $Accumulator -or [string]::IsNullOrWhiteSpace($Domain) -or [string]::IsNullOrWhiteSpace($Subject) -or [string]::IsNullOrWhiteSpace($Action)) { return }
    $domainKey = $Domain.Trim().ToLowerInvariant()
    $subjectKey = $Subject.Trim().ToLowerInvariant()
    $key = "{0}|{1}" -f $domainKey, $subjectKey
    if (-not $Accumulator.ContainsKey($key)) {
        $Accumulator[$key] = [pscustomobject]@{
            domain = $domainKey
            subject = $subjectKey
            actions = New-Object System.Collections.Generic.List[string]
            evidence = New-Object System.Collections.Generic.List[object]
            targets = New-Object System.Collections.Generic.List[string]
        }
    }
    $entry = $Accumulator[$key]
    Add-AuditUniqueValue $entry.actions $Action.Trim().ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($Target)) { Add-AuditUniqueValue $entry.targets $Target.Trim() }
    $evidenceKey = "{0}|{1}|{2}|{3}" -f $Kind, $Path, $Signal, $Target
    foreach ($existing in @($entry.evidence.ToArray())) {
        $existingKey = "{0}|{1}|{2}|{3}" -f [string]$existing.kind, [string]$existing.path, [string]$existing.signal, [string]$existing.target
        if ($existingKey -eq $evidenceKey) { return }
    }
    if ($entry.evidence.Count -ge 48) { return }
    $evidence = [ordered]@{ kind = $Kind; path = $Path; signal = $Signal }
    if (-not [string]::IsNullOrWhiteSpace($Target)) { $evidence.target = $Target.Trim() }
    $entry.evidence.Add([pscustomobject]$evidence) | Out-Null
}

function Get-AuditRequirementSignalConfidence($entry) {
    $kinds = @($entry.evidence | ForEach-Object { [string]$_.kind })
    if (@($kinds | Where-Object { $_ -in @("source_code", "supporting_code") }).Count -gt 0) { return "high" }
    if (@($kinds | Where-Object { $_ -eq "test" }).Count -gt 0) { return "medium" }
    if (@($kinds | Where-Object { $_ -in @("dependency", "project_file") }).Count -gt 0) { return "medium" }
    return "low"
}

function Get-AuditRequirementSignalStatus($entry) {
    $kinds = @($entry.evidence | ForEach-Object { [string]$_.kind })
    if (@($kinds | Where-Object { $_ -in @("source_code", "supporting_code") }).Count -gt 0) { return "implemented" }
    if (@($kinds | Where-Object { $_ -eq "test" }).Count -gt 0) { return "test_covered" }
    if (@($kinds | Where-Object { $_ -in @("dependency", "project_file") }).Count -gt 0) { return "dependency_indicated" }
    return "documented"
}

function ConvertTo-AuditRequirementSignalArray($Accumulator) {
    if ($null -eq $Accumulator) { return @() }
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @($Accumulator.Values | Sort-Object domain, subject)) {
        $result.Add([pscustomobject]([ordered]@{
                    domain = [string]$entry.domain
                    subject = [string]$entry.subject
                    actions = @($entry.actions | Sort-Object)
                    confidence = Get-AuditRequirementSignalConfidence $entry
                    evidence_status = Get-AuditRequirementSignalStatus $entry
                    targets = @($entry.targets | Sort-Object)
                    evidence = @($entry.evidence.ToArray())
                })) | Out-Null
    }
    return @($result.ToArray())
}

function Test-AuditRuleDefinitionLine([string]$Line) {
    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }
    # Scanner metadata is not target behaviour.  Excluding these declarations keeps
    # a repository from self-reporting the vocabulary used by the scanner itself.
    return [regex]::IsMatch($Line, "(?i)\b(?:artifact|domain|subject|pattern|actions)\s*=")
}

function Get-AuditEvidenceLines([string]$Content) {
    $result = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($Content)) { return @() }
    $lines = @($Content -split "`r?`n")
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $text = [string]$lines[$index]
        if ([string]::IsNullOrWhiteSpace($text) -or (Test-AuditRuleDefinitionLine $text)) { continue }
        $result.Add([pscustomobject]@{ number = $index + 1; text = $text }) | Out-Null
    }
    return @($result.ToArray())
}

function Test-AuditScannerSelfFile([string]$RelativePath) {
    # When a configured target IS this repository, the scanner's own sources and
    # fixtures describe signal vocabulary; they must not become target evidence.
    $normalized = ([string]$RelativePath).Replace('/', '\')
    return [regex]::IsMatch($normalized, '(?i)(^|\\)src\\Commands\\AuditTargets(\.[^\\]+)?\.ps1$') -or
        [regex]::IsMatch($normalized, '(?i)(^|\\)src\\Application\\CapabilityInventory\.ps1$') -or
        [regex]::IsMatch($normalized, '(?i)(^|\\)tests\\(Unit|E2E)\\(AuditTargets[^\\]*|SkillAudit[^\\]*|CapabilityInventory[^\\]*|ReadOnlyCli[^\\]*)\.Tests\.ps1$')
}

function Test-AuditSelfReferentialAnalysisFile([string]$Content) {
    if ([string]::IsNullOrWhiteSpace($Content)) { return $false }
    $definesBothExtractors = [regex]::IsMatch($Content, "(?i)function\s+Add-AuditArtifactFactsFromText\b") -and
        [regex]::IsMatch($Content, "(?i)function\s+Add-AuditRequirementFactsFromText\b")
    if ($definesBothExtractors) { return $true }

    # Fixture code for the scanner describes hypothetical target repositories.  It is
    # evidence about the scanner, not a capability supplied by the scanned target.
    return [regex]::IsMatch($Content, "(?i)\bNew-AuditRepoScan\b") -and
        [regex]::IsMatch($Content, "(?i)\bSet-ContentUtf8\b") -and
        [regex]::IsMatch($Content, "(?i)\b(?:artifact_capabilities|requirement_signals)\b")
}

function Add-AuditRequirementFactsFromText {
    param(
        $Accumulator,
        [string]$Content,
        [string]$Kind,
        [string]$RelativePath
    )
    if ($null -eq $Accumulator -or [string]::IsNullOrWhiteSpace($Content)) { return }
    $signals = @(
        [pscustomobject]@{ domain = "interface"; subject = "web_ui"; action = "deliver"; pattern = "(?i)\breact\b|\bvue\b|\bsvelte\b|\bnext(?:js)?\b|\bvite\b" },
        [pscustomobject]@{ domain = "interface"; subject = "desktop_ui"; action = "deliver"; pattern = "(?i)usewpf|\bwpf\b|\bwinforms\b|\bavalonia\b|\bdesktop app\b" },
        [pscustomobject]@{ domain = "integration"; subject = "http_api"; action = "serve"; pattern = "(?i)map(get|post|put|delete)|\bcontroller\b|fastapi|flask|express\s*\(|asp\.?net\s*(core)?\s*(api)?" },
        [pscustomobject]@{ domain = "data"; subject = "persistence"; action = "store"; pattern = "(?i)entityframework|\bdbcontext\b|\bpostgres(?:ql)?\b|\bsqlite\b|\bmongodb\b|\bredis\b" },
        [pscustomobject]@{ domain = "automation"; subject = "browser_automation"; action = "automate"; pattern = "(?i)playwright|puppeteer|selenium|browser[_ -]?automation" },
        [pscustomobject]@{ domain = "workflow"; subject = "document_processing"; action = "process"; pattern = "(?i)docling|document ai|document[_ -]?(import|extract|process)|openxml|(?:^|[_\W])docx(?:$|[_\W])|(?:^|[_\W])pdf(?:$|[_\W])" },
        [pscustomobject]@{ domain = "workflow"; subject = "ocr"; action = "recognize"; pattern = "(?i)\bocr\b|rapidocr|paddleocr|tesseract|easyocr" },
        [pscustomobject]@{ domain = "workflow"; subject = "analytics"; action = "analyze"; pattern = "(?i)assessment analytics|question stats|\banalytics\b|\bctt\b|试题统计" },
        [pscustomobject]@{ domain = "ai"; subject = "content_generation"; action = "generate"; pattern = "(?i)images api|image generation|\b(?:generate|create|produce)_(?:image|content|article|poster|courseware)\w*\b|\b(?:image|content|article|poster|courseware)_(?:generate|create|produce)\w*\b|(?:generate|create|produce)\w*[^\r\n]{0,80}\b(?:image|content|article|poster|courseware)\b|\b(?:image|content|article|poster|courseware)\b[^\r\n]{0,80}(?:generate|create|produce)\w*" },
        [pscustomobject]@{ domain = "ai"; subject = "model_integration"; action = "integrate"; pattern = "(?i)\bopenai\b|\banthropic\b|\bllm\b|\bmodel provider\b" },
        [pscustomobject]@{ domain = "quality"; subject = "automated_testing"; action = "validate"; pattern = "(?i)\bpytest\b|\bpester\b|\bdotnet test\b|\bjest\b|\bvitest\b|\bplaywright test\b|\bunit test" },
        [pscustomobject]@{ domain = "operations"; subject = "backup_recovery"; action = "recover"; pattern = "(?i)\bbackup\b|\brestore\b|disaster recovery|\bwinpe\b" }
    )
    foreach ($line in @(Get-AuditEvidenceLines $Content)) {
        foreach ($signal in @($signals)) {
            if ([regex]::IsMatch([string]$line.text, [string]$signal.pattern)) {
                Add-AuditRequirementEvidence $Accumulator $signal.domain $signal.subject $signal.action $Kind $RelativePath ("{0}:{1}@L{2}" -f $signal.domain, $signal.subject, $line.number)
            }
        }
    }
}

function Add-AuditArtifactFactsFromText {
    param(
        $Accumulator,
        [string]$Content,
        [string]$Kind,
        [string]$RelativePath
    )
    if ($null -eq $Accumulator -or [string]::IsNullOrWhiteSpace($Content)) { return }
    $artifacts = @(
        [pscustomobject]@{ artifact = "pdf"; pattern = "(?i)(?:\.pdf\b|(?:^|[_\W])pdf(?:$|[_\W])|pdftotext|pdftoppm|pdfreader|pdfwriter|questpdf|pdfsharp|pdfpig|pypdf|pdfplumber|pymupdf|pdfjs)" },
        [pscustomobject]@{ artifact = "docx"; pattern = "(?i)(?:\.docx\b|(?:^|[_\W])docx(?:$|[_\W])|wordprocessingdocument|openxml.*word|python-docx)" },
        [pscustomobject]@{ artifact = "pptx"; pattern = "(?i)(?:\.pptx\b|(?:^|[_\W])pptx(?:$|[_\W])|powerpoint|presentationml|pptxgenjs|幻灯片|课件)" },
        [pscustomobject]@{ artifact = "xlsx"; pattern = "(?i)(?:\.xlsx\b|(?:^|[_\W])xlsx(?:$|[_\W])|\bexcel\b|spreadsheetml|openpyxl|closedxml|epplus)" },
        [pscustomobject]@{ artifact = "image"; pattern = "(?i)(?:\bimage\b|\bpng\b|\bjpe?g\b|\bsvg\b|\bwebp\b|\bbitmap\b|pillow|imagesharp|skia(?:sharp)?)" }
    )
    $actions = @(
        [pscustomobject]@{ action = "read"; pattern = "(?i)\b(?:parse|extract|import|load|open|ingest)(?:[A-Z][\w]*|_[\w]+|s|ed|ing|er|all|async)?\b|\bread(?:_(?:[\w]+)|(?-i:[A-Z])[\w]*|s|ed|ing|er|all|async)?\b|adapter" },
        [pscustomobject]@{ action = "generate"; pattern = "(?i)\b(export|generate|create|write|save|output|deliver|produce)\w*\b" },
        [pscustomobject]@{ action = "render"; pattern = "(?i)\b(render|preview|rasteri[sz]e|thumbnail)\w*\b|pdftoppm" },
        [pscustomobject]@{ action = "ocr"; pattern = "(?i)\bocr\b|tesseract|rapidocr|paddleocr|easyocr" },
        [pscustomobject]@{ action = "edit"; pattern = "(?i)\b(edit|modify|transform|resize|crop|compose)\w*\b" }
    )
    $lines = @(Get-AuditEvidenceLines $Content)
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $current = $lines[$index]
        $next = if ($index + 1 -lt $lines.Count -and [int]$lines[$index + 1].number -eq [int]$current.number + 1) { $lines[$index + 1] } else { $null }
        foreach ($artifact in @($artifacts)) {
            $artifactOnCurrentLine = [regex]::IsMatch([string]$current.text, [string]$artifact.pattern)
            $artifactOnNextLine = $null -ne $next -and [regex]::IsMatch([string]$next.text, [string]$artifact.pattern)
            if (-not $artifactOnCurrentLine -and -not $artifactOnNextLine) { continue }
            foreach ($action in @($actions)) {
                $actionOnCurrentLine = [regex]::IsMatch([string]$current.text, [string]$action.pattern)
                $actionOnNextLine = $null -ne $next -and [regex]::IsMatch([string]$next.text, [string]$action.pattern)
                $matched = ($artifactOnCurrentLine -and ($actionOnCurrentLine -or $actionOnNextLine)) -or ($actionOnCurrentLine -and $artifactOnNextLine)
                if ($matched) {
                    $location = if ($null -ne $next -and ($artifactOnNextLine -or $actionOnNextLine) -and -not ($artifactOnCurrentLine -and $actionOnCurrentLine)) { "L{0}-L{1}" -f $current.number, $next.number } else { "L{0}" -f $current.number }
                    Add-AuditArtifactEvidence $Accumulator $artifact.artifact $action.action $Kind $RelativePath ("{0}:{1}@{2}" -f $artifact.artifact, $action.action, $location)
                }
            }
        }
    }
}

function Add-AuditArtifactFactsFromDependencyText {
    param(
        $Accumulator,
        [string]$Content,
        [string]$RelativePath
    )
    if ($null -eq $Accumulator -or [string]::IsNullOrWhiteSpace($Content)) { return }
    $signals = @(
        [pscustomobject]@{ artifact = "pdf"; actions = @("read"); pattern = "(?i)pdfpig|pdfplumber|\bpypdf\b|pymupdf|pdfjs-dist" },
        [pscustomobject]@{ artifact = "pdf"; actions = @("generate", "edit"); pattern = "(?i)questpdf|itext(?:7)?|pdfsharp|pdf-lib|reportlab|weasyprint" },
        [pscustomobject]@{ artifact = "pdf"; actions = @("render"); pattern = "(?i)pdf2image|poppler|pdftoppm" },
        [pscustomobject]@{ artifact = "docx"; actions = @("read", "edit", "generate"); pattern = "(?i)documentformat\.openxml|openxml|python-docx|docxjs|\bdocx\b" },
        [pscustomobject]@{ artifact = "pptx"; actions = @("read", "edit", "generate"); pattern = "(?i)documentformat\.openxml|openxml|python-pptx|pptxgenjs|\bpptx\b" },
        [pscustomobject]@{ artifact = "xlsx"; actions = @("read", "edit", "generate"); pattern = "(?i)documentformat\.openxml|openxml|openpyxl|closedxml|epplus|exceldatareader|exceljs|\bnpoi\b" },
        [pscustomobject]@{ artifact = "image"; actions = @("read", "edit", "render"); pattern = "(?i)pillow|imagesharp|skia(?:sharp)?|\bsharp\b|imagemagick" },
        [pscustomobject]@{ artifact = "image"; actions = @("ocr"); pattern = "(?i)tesseract|rapidocr|paddleocr|easyocr" }
    )
    foreach ($signal in @($signals)) {
        if (-not [regex]::IsMatch($Content, [string]$signal.pattern)) { continue }
        foreach ($action in @($signal.actions)) {
            Add-AuditArtifactEvidence $Accumulator $signal.artifact $action "dependency" $RelativePath ("dependency:{0}" -f $signal.artifact)
        }
    }
}

function Add-AuditArtifactManifestFacts([string]$resolvedPath, $Accumulator, $RequirementAccumulator = $null) {
    $manifestFiles = New-Object System.Collections.Generic.List[object]
    foreach ($relativePath in @("package.json", "pyproject.toml", "requirements.txt", "packages.props", "Directory.Packages.props")) {
        $fullPath = Join-Path $resolvedPath $relativePath
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) { $manifestFiles.Add((Get-Item -LiteralPath $fullPath)) | Out-Null }
    }
    foreach ($file in @(Get-AuditRecursiveFiles $resolvedPath "*.csproj" 80) + @(Get-AuditRecursiveFiles $resolvedPath "requirements*.txt" 24)) {
        if ($null -ne $file) { $manifestFiles.Add($file) | Out-Null }
    }
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in @($manifestFiles.ToArray())) {
        if ($null -eq $file -or -not $seen.Add([string]$file.FullName)) { continue }
        if ($file.Length -gt 1048576) { continue }
        try {
            $content = Get-ContentUtf8 $file.FullName
            $relativePath = Get-AuditRepositoryRelativePath $resolvedPath $file.FullName
            Add-AuditArtifactFactsFromDependencyText $Accumulator $content $relativePath
            Add-AuditRequirementFactsFromText $RequirementAccumulator $content "dependency" $relativePath
        }
        catch {
            continue
        }
    }
}

function Add-AuditArtifactSourceFacts([string]$resolvedPath, $Accumulator, [System.Collections.Generic.List[string]]$risks, $RequirementAccumulator = $null) {
    $allSourceFiles = @(Get-AuditSourceFileIndex $resolvedPath)
    $limit = 600
    $selectedSourceFiles = @(Select-AuditBalancedSourceFiles $resolvedPath $allSourceFiles $limit)
    if ($allSourceFiles.Count -gt $limit) { Add-AuditUniqueValue $risks "artifact_source_scan_truncated" }
    $sourceScanKindCounts = @{ source_code = 0; supporting_code = 0; test = 0; non_product_code = 0 }
    $sourceScanLargeFileCount = 0
    $sourceScanReadFailureCount = 0
    $sourceScanTextTruncatedCount = 0
    $sourceScanSelfReferentialCount = 0
    foreach ($file in @($selectedSourceFiles)) {
        if ($file.Length -gt 1048576) { $sourceScanLargeFileCount++; continue }
        try {
            $content = Get-ContentUtf8 $file.FullName
            $contentBytes = [System.Text.Encoding]::UTF8.GetBytes($content)
            if ($contentBytes.Length -gt 262144) {
                $sourceScanTextTruncatedCount++
                $cutLength = 262144
                while ($cutLength -gt 0 -and (($contentBytes[$cutLength] -band 0xC0) -eq 0x80)) { $cutLength-- }
                $content = [System.Text.Encoding]::UTF8.GetString($contentBytes, 0, $cutLength)
            }
            if (Test-AuditSelfReferentialAnalysisFile $content) {
                $sourceScanSelfReferentialCount++
                continue
            }
            $relativePath = Get-AuditRepositoryRelativePath $resolvedPath $file.FullName
            if (Test-AuditScannerSelfFile $relativePath) {
                $sourceScanSelfReferentialCount++
                continue
            }
            $kind = Get-AuditSourceEvidenceKind $relativePath
            if ($sourceScanKindCounts.ContainsKey($kind)) { $sourceScanKindCounts[$kind]++ }
            Add-AuditArtifactFactsFromText $Accumulator $content $kind $relativePath
            Add-AuditRequirementFactsFromText $RequirementAccumulator $content $kind $relativePath
        }
        catch {
            $sourceScanReadFailureCount++
        }
    }
    $script:AuditLastSourceScanCoverage = [pscustomobject]([ordered]@{
            population_count = @($allSourceFiles).Count
            sampled_count = @($selectedSourceFiles).Count
            sample_limit = $limit
            truncated = (@($allSourceFiles).Count -gt $limit)
            large_file_count = $sourceScanLargeFileCount
            text_truncated_count = $sourceScanTextTruncatedCount
            self_referential_count = $sourceScanSelfReferentialCount
            read_failure_count = $sourceScanReadFailureCount
            sampled_by_kind = [pscustomobject]([ordered]@{
                    source_code = [int]$sourceScanKindCounts.source_code
                    supporting_code = [int]$sourceScanKindCounts.supporting_code
                    test = [int]$sourceScanKindCounts.test
                    non_product_code = [int]$sourceScanKindCounts.non_product_code
                })
            confidence_ceiling = if (@($allSourceFiles).Count -eq 0) { "unknown" } elseif (@($allSourceFiles).Count -le $limit -and $sourceScanLargeFileCount -eq 0 -and $sourceScanTextTruncatedCount -eq 0 -and $sourceScanSelfReferentialCount -eq 0 -and $sourceScanReadFailureCount -eq 0) { "complete_source_population" } else { "representative_sample" }
        })
}

function Add-AuditDotnetFacts([string]$resolvedPath, [System.Collections.Generic.List[string]]$frameworks, [System.Collections.Generic.List[string]]$packageManagers, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$testCommands, [System.Collections.Generic.List[string]]$notableFiles) {
    $slnFiles = @(Get-ChildItem -LiteralPath $resolvedPath -Filter "*.sln" -File -ErrorAction SilentlyContinue | Select-Object -First 10)
    $csprojFiles = @(Get-AuditRecursiveFiles $resolvedPath "*.csproj" 40)
    if ($slnFiles.Count -eq 0 -and $csprojFiles.Count -eq 0) { return }
    Add-AuditUniqueValue $packageManagers "nuget"
    Add-AuditUniqueValue $buildCommands "dotnet build"
    $hasTests = $false
    foreach ($sln in @($slnFiles)) {
        Add-AuditUniqueValue $notableFiles (Get-AuditRepositoryRelativePath $resolvedPath $sln.FullName)
    }
    foreach ($proj in @($csprojFiles)) {
        Add-AuditUniqueValue $notableFiles (Get-AuditRepositoryRelativePath $resolvedPath $proj.FullName)
        if ($proj.Name -match "(?i)test") { $hasTests = $true }
        try {
            $xml = [xml](Get-ContentUtf8 $proj.FullName)
        }
        catch {
            continue
        }
        $projectNode = $xml.Project
        if ($null -ne $projectNode -and $projectNode.Attributes["Sdk"]) {
            $sdk = [string]$projectNode.Attributes["Sdk"].Value
            if ($sdk -match "(?i)web") { Add-AuditUniqueValue $frameworks "aspnetcore" }
        }
        $packageRefs = @($xml.SelectNodes("//PackageReference"))
        foreach ($ref in $packageRefs) {
            $include = ""
            if ($ref.Attributes["Include"]) { $include = [string]$ref.Attributes["Include"].Value }
            if ([string]::IsNullOrWhiteSpace($include)) { continue }
            if ($include -match "(?i)Microsoft\.AspNetCore") { Add-AuditUniqueValue $frameworks "aspnetcore" }
            if ($include -match "(?i)EntityFrameworkCore") { Add-AuditUniqueValue $frameworks "efcore" }
            if ($include -match "(?i)xunit|nunit|mstest|Microsoft\.NET\.Test\.Sdk") { $hasTests = $true }
        }
    }
    if ($hasTests -or $slnFiles.Count -gt 0) {
        Add-AuditUniqueValue $testCommands "dotnet test"
    }
}

function Add-AuditDesignDocumentFacts([string]$resolvedPath, [System.Collections.Generic.List[string]]$languages, [System.Collections.Generic.List[string]]$frameworks, [System.Collections.Generic.List[string]]$packageManagers, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$testCommands, [System.Collections.Generic.List[string]]$capabilities, [System.Collections.Generic.List[string]]$notableFiles, [System.Collections.Generic.List[string]]$risks, $ArtifactCapabilities = $null, $RequirementSignals = $null) {
    $docCandidates = @(
        "README.md",
        "ALL_IN_ONE_EXECUTIVE_SPEC.md",
        "docs\03_Architecture.md",
        "docs\04_TechnologyStack.md",
        "docs\07_Document_AI_ImportPipeline.md",
        "docs\12_PaperGeneration_ExportLayout.md",
        "docs\13_AssessmentAnalytics.md",
        "docs\14_BackupRecoveryMigration.md",
        "docs\18_TestStrategy.md"
    )
    $contents = New-Object System.Collections.Generic.List[string]
    $designRepoDetected = $false
    foreach ($relativePath in @($docCandidates)) {
        $fullPath = Join-Path $resolvedPath $relativePath
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }
        Add-AuditUniqueValue $notableFiles $relativePath
        try {
            $text = Get-ContentUtf8 $fullPath
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                $contents.Add($text) | Out-Null
                Add-AuditArtifactFactsFromText $ArtifactCapabilities $text "documentation" $relativePath
                Add-AuditRequirementFactsFromText $RequirementSignals $text "documentation" $relativePath
                if ($text -match "编码前设计包" -or $text -match "(?i)\bpre-implementation\b" -or $text -match "(?i)\bdesign package\b") {
                    $designRepoDetected = $true
                }
            }
        }
        catch {
            continue
        }
    }
    if ($contents.Count -eq 0) { return }

    $combined = ($contents -join "`n")
    if ([string]::IsNullOrWhiteSpace($combined)) { return }

    if ($designRepoDetected) {
        Add-AuditUniqueValue $risks "design_package_only"
    }

    if ([regex]::IsMatch($combined, "(?i)react\s*\+\s*typescript|\breact\b")) {
        Add-AuditUniqueValue $languages "javascript"
        Add-AuditUniqueValue $frameworks "react"
        Add-AuditUniqueValue $packageManagers "npm"
    }
    if ([regex]::IsMatch($combined, "(?i)\btypescript\b")) {
        Add-AuditUniqueValue $languages "javascript"
        Add-AuditUniqueValue $packageManagers "npm"
    }
    if ([regex]::IsMatch($combined, "(?i)\bvite\b")) {
        Add-AuditUniqueValue $frameworks "vite"
        Add-AuditUniqueValue $packageManagers "npm"
        Add-AuditUniqueValue $buildCommands "npm run build"
    }
    if ([regex]::IsMatch($combined, "(?i)\basp\.?net\s*core\b")) {
        Add-AuditUniqueValue $languages "dotnet"
        Add-AuditUniqueValue $frameworks "aspnetcore"
        Add-AuditUniqueValue $packageManagers "nuget"
        Add-AuditUniqueValue $buildCommands "dotnet build"
    }
    if ([regex]::IsMatch($combined, "(?i)\bef\s*core\b|EntityFrameworkCore")) {
        Add-AuditUniqueValue $languages "dotnet"
        Add-AuditUniqueValue $frameworks "efcore"
        Add-AuditUniqueValue $packageManagers "nuget"
        Add-AuditUniqueValue $buildCommands "dotnet build"
    }
    if ([regex]::IsMatch($combined, "(?i)\bpython\b|\bdocling\b|\bpaddleocr\b|\bocr\b")) {
        Add-AuditUniqueValue $languages "python"
        Add-AuditUniqueValue $packageManagers "pip"
    }
    if ([regex]::IsMatch($combined, "(?i)\bplaywright\b")) {
        Add-AuditUniqueValue $frameworks "playwright"
        Add-AuditUniqueValue $testCommands "npx playwright test"
    }
    if ([regex]::IsMatch($combined, "(?i)\bnpm run build\b")) {
        Add-AuditUniqueValue $buildCommands "npm run build"
    }
    if ([regex]::IsMatch($combined, "(?i)\bdotnet test\b")) {
        Add-AuditUniqueValue $testCommands "dotnet test"
    }
    if ([regex]::IsMatch($combined, "(?i)\bui smoke\b")) {
        Add-AuditUniqueValue $testCommands "ui smoke"
    }

    if ([regex]::IsMatch($combined, "(?i)\bdocling\b|\bpaddleocr\b|\bocr\b|\bdocument ai\b|\bimport pipeline\b|\bopenxml\b")) {
        Add-AuditUniqueValue $capabilities "document_import"
        Add-AuditUniqueValue $capabilities "ocr_pipeline"
    }
    if ([regex]::IsMatch($combined, "(?i)\bquestion extraction\b|\b题目抽取\b|\bstructured extraction\b")) {
        Add-AuditUniqueValue $capabilities "question_extraction"
    }
    if ([regex]::IsMatch($combined, "(?i)\breview queue\b|\breview workflow\b|\b人工复核\b")) {
        Add-AuditUniqueValue $capabilities "review_queue"
    }
    if ([regex]::IsMatch($combined, "(?i)\bpaper generation\b|\bexport layout\b|\blayout engine\b|\bword export\b|\bdocx export\b|\bpdf export\b|\b试卷生成\b")) {
        Add-AuditUniqueValue $capabilities "paper_generation"
        Add-AuditUniqueValue $capabilities "document_export"
    }
    if ([regex]::IsMatch($combined, "(?i)\bexcel import\b|\bassessment analytics\b|\bctt\b|\bquestion stats\b|\b试题统计\b|\banalytics\b")) {
        Add-AuditUniqueValue $capabilities "assessment_analytics"
        Add-AuditUniqueValue $capabilities "spreadsheet_import"
    }
    if ([regex]::IsMatch($combined, "(?i)\bbackup\b|\brestore\b|\bdisaster recovery\b|\b恢复\b|\b迁移\b|\bmanifest hash\b|\bwinpe\b")) {
        Add-AuditUniqueValue $capabilities "backup_recovery"
        Add-AuditUniqueValue $capabilities "migration_recovery"
    }
}

function Get-AuditGitChangedPaths {
    $paths = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::Ordinal)
    $pathGroups = @(
        @(& git -c core.quotepath=false diff --cached --name-only --no-ext-diff 2>$null),
        @(& git -c core.quotepath=false diff --name-only --no-ext-diff 2>$null),
        @(& git -c core.quotepath=false ls-files --others --exclude-standard 2>$null)
    )
    foreach ($group in $pathGroups) {
        foreach ($path in @($group)) {
            $text = [string]$path
            if (-not [string]::IsNullOrWhiteSpace($text)) { $paths.Add($text) | Out-Null }
        }
    }
    return @($paths)
}

function Get-AuditGitPathStatePairs($paths) {
    # 单次全量 ls-files 取代逐路径派生进程（脏路径多时每路径一个 git 进程是扫描
    # 的主要耗时）；pathspec 的目录前缀语义用前缀过滤等价复现。
    $pathList = @($paths)
    if ($pathList.Count -eq 0) { return @() }
    $repoRoot = [string](Get-Location).Path
    $allIndexLines = @(& git -c core.quotepath=false ls-files --stage 2>$null)
    $pairs = @()
    foreach ($path in $pathList) {
        $fullPath = Join-Path $repoRoot ([string]$path)
        $prefix = "{0}/" -f [string]$path
        $indexState = @($allIndexLines | Where-Object {
                $tab = $_.IndexOf("`t")
                if ($tab -lt 0) { return $false }
                $indexed = $_.Substring($tab + 1)
                ([string]$indexed -eq [string]$path) -or ([string]$indexed).StartsWith($prefix, [System.StringComparison]::Ordinal)
            })
        $indexFingerprint = Get-AuditFingerprintFromVendorFromPairs $indexState $true
        $worktreeState = "missing"
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            $worktreeState = "file:" + [string](Get-FileContentHash $fullPath)
        }
        elseif (Test-Path -LiteralPath $fullPath -PathType Container) {
            $nestedHead = (& git -C $fullPath rev-parse HEAD 2>$null)
            $nestedStatus = @(& git -C $fullPath status --porcelain 2>$null)
            $nestedPairs = @("head|" + ([string]$nestedHead).Trim())
            $nestedPairs += @($nestedStatus | ForEach-Object { "status|" + [string]$_ })
            $worktreeState = "directory:" + (Get-AuditFingerprintFromVendorFromPairs $nestedPairs $true)
        }
        $pairs += ("path|{0}|index|{1}|worktree|{2}" -f [string]$path, $indexFingerprint, $worktreeState)
    }
    return @($pairs)
}

function Get-AuditGitInfo([string]$resolvedPath) {
    $info = [ordered]@{
        is_repo = $false
        branch = ""
        commit = ""
        dirty = $false
        status_count = 0
        status_fingerprint = ""
    }
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container)) { return [pscustomobject]$info }

    Push-Location $resolvedPath
    try {
        $inside = (& git rev-parse --is-inside-work-tree 2>$null)
        if ($LASTEXITCODE -eq 0 -and [string]$inside -eq "true") {
            $info.is_repo = $true
            $branch = (& git rev-parse --abbrev-ref HEAD 2>$null)
            if ($LASTEXITCODE -eq 0) { $info.branch = ([string]$branch).Trim() }
            $commit = (& git rev-parse HEAD 2>$null)
            if ($LASTEXITCODE -eq 0) { $info.commit = ([string]$commit).Trim() }
            $status = @(& git status --porcelain 2>$null)
            if ($LASTEXITCODE -eq 0) {
                $statusLines = @($status | ForEach-Object { [string]$_ })
                $changedPaths = @(Get-AuditGitChangedPaths)
                $statePairs = @($statusLines | ForEach-Object { "status|" + [string]$_ })
                $statePairs += @(Get-AuditGitPathStatePairs $changedPaths)
                $info.dirty = ($statusLines.Count -gt 0)
                $info.status_count = $statusLines.Count
                $info.status_fingerprint = Get-AuditFingerprintFromVendorFromPairs $statePairs $true
            }
        }
    }
    finally {
        Pop-Location
    }
    return [pscustomobject]$info
}

function New-AuditRepoScan([string]$targetName, [string]$resolvedPath, [string]$inputPath) {
    # A scan is a single consistency window.  Do not reuse a source index from a
    # prior scan invocation where the target may have changed.
    $script:AuditSourceFileIndexCache = @{}
    $exists = Test-Path -LiteralPath $resolvedPath -PathType Container
    $risks = New-Object System.Collections.Generic.List[string]
    $languages = New-Object System.Collections.Generic.List[string]
    $packageManagers = New-Object System.Collections.Generic.List[string]
    $frameworks = New-Object System.Collections.Generic.List[string]
    $buildCommands = New-Object System.Collections.Generic.List[string]
    $testCommands = New-Object System.Collections.Generic.List[string]
    $capabilities = New-Object System.Collections.Generic.List[string]
    $artifactCapabilities = New-AuditArtifactCapabilityAccumulator
    $requirementSignals = New-AuditRequirementSignalAccumulator
    $agentRuleFiles = New-Object System.Collections.Generic.List[string]
    $notableFiles = New-Object System.Collections.Generic.List[string]
    $scanCoverage = [pscustomobject]([ordered]@{
            population_count = 0
            sampled_count = 0
            sample_limit = 600
            truncated = $false
            large_file_count = 0
            text_truncated_count = 0
            self_referential_count = 0
            read_failure_count = 0
            sampled_by_kind = [pscustomobject]@{ source_code = 0; supporting_code = 0; test = 0; non_product_code = 0 }
            confidence_ceiling = "unknown"
        })
    $script:AuditLastSourceScanCoverage = $null

    if (-not $exists) {
        Add-AuditUniqueValue $risks "target_missing"
    }

    $gitInfo = Get-AuditGitInfo $resolvedPath
    if ($exists -and -not $gitInfo.is_repo) {
        Add-AuditUniqueValue $risks "not_a_git_repo"
    }
    if ($gitInfo.dirty) {
        Add-AuditUniqueValue $risks "git_dirty"
    }

    if ($exists) {
        $pkg = Get-AuditPackageJson $resolvedPath
        if ($pkg) {
            Add-AuditUniqueValue $packageManagers "npm"
            Add-AuditUniqueValue $languages "javascript"
            Add-AuditUniqueValue $notableFiles "package.json"

            $deps = @()
            $deps += Get-AuditPackagePropertyNames $pkg "dependencies"
            $deps += Get-AuditPackagePropertyNames $pkg "devDependencies"
            foreach ($dep in $deps) {
                switch -Regex ($dep) {
                    "^vite$" { Add-AuditUniqueValue $frameworks "vite" }
                    "^next$" { Add-AuditUniqueValue $frameworks "nextjs" }
                    "^react$" { Add-AuditUniqueValue $frameworks "react" }
                    "^vue$" { Add-AuditUniqueValue $frameworks "vue" }
                    "^svelte$" { Add-AuditUniqueValue $frameworks "svelte" }
                    "^@playwright/test$" { Add-AuditUniqueValue $frameworks "playwright" }
                }
            }

            $scripts = Get-AuditPackageScriptNames $pkg
            if ($scripts -contains "build") { Add-AuditUniqueValue $buildCommands "npm run build" }
            if ($scripts -contains "test") { Add-AuditUniqueValue $testCommands "npm test" }
            if ($scripts -contains "test:ci") { Add-AuditUniqueValue $testCommands "npm run test:ci" }
            if ($scripts -contains "ci:test") { Add-AuditUniqueValue $testCommands "npm run ci:test" }
            if ($scripts -contains "typecheck") { Add-AuditUniqueValue $buildCommands "npm run typecheck" }
            if ($pkg.PSObject.Properties.Match("packageManager").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$pkg.packageManager)) {
                $pm = ([string]$pkg.packageManager).Trim().ToLowerInvariant()
                if ($pm.StartsWith("pnpm@")) { Add-AuditUniqueValue $packageManagers "pnpm" }
                elseif ($pm.StartsWith("yarn@")) { Add-AuditUniqueValue $packageManagers "yarn" }
                elseif ($pm.StartsWith("npm@")) { Add-AuditUniqueValue $packageManagers "npm" }
            }
        }

        if (Test-AuditFile $resolvedPath "pnpm-lock.yaml") { Add-AuditUniqueValue $packageManagers "pnpm"; Add-AuditUniqueValue $notableFiles "pnpm-lock.yaml" }
        if (Test-AuditFile $resolvedPath "yarn.lock") { Add-AuditUniqueValue $packageManagers "yarn"; Add-AuditUniqueValue $notableFiles "yarn.lock" }
        if (Test-AuditFile $resolvedPath "package-lock.json") { Add-AuditUniqueValue $packageManagers "npm"; Add-AuditUniqueValue $notableFiles "package-lock.json" }
        if (Test-AuditFile $resolvedPath "pyproject.toml") { Add-AuditUniqueValue $languages "python"; Add-AuditUniqueValue $notableFiles "pyproject.toml"; Add-AuditUniqueValue $packageManagers "pip" }
        if (Test-AuditFile $resolvedPath "requirements.txt") { Add-AuditUniqueValue $languages "python"; Add-AuditUniqueValue $notableFiles "requirements.txt"; Add-AuditUniqueValue $packageManagers "pip" }
        if (Test-AuditFile $resolvedPath "uv.lock") { Add-AuditUniqueValue $packageManagers "uv"; Add-AuditUniqueValue $notableFiles "uv.lock" }
        if (Test-AuditFile $resolvedPath "go.mod") { Add-AuditUniqueValue $languages "go"; Add-AuditUniqueValue $notableFiles "go.mod" }
        if (Test-AuditFile $resolvedPath "Cargo.toml") { Add-AuditUniqueValue $languages "rust"; Add-AuditUniqueValue $notableFiles "Cargo.toml" }

        foreach ($viteFile in @("vite.config.js", "vite.config.ts", "vite.config.mjs", "vite.config.mts")) {
            if (Test-AuditFile $resolvedPath $viteFile) {
                Add-AuditUniqueValue $frameworks "vite"
                Add-AuditUniqueValue $notableFiles $viteFile
            }
        }
        foreach ($nextFile in @("next.config.js", "next.config.ts", "next.config.mjs")) {
            if (Test-AuditFile $resolvedPath $nextFile) {
                Add-AuditUniqueValue $frameworks "nextjs"
                Add-AuditUniqueValue $notableFiles $nextFile
            }
        }
        foreach ($playwrightFile in @("playwright.config.js", "playwright.config.ts", "playwright.config.mjs")) {
            if (Test-AuditFile $resolvedPath $playwrightFile) {
                Add-AuditUniqueValue $frameworks "playwright"
                Add-AuditUniqueValue $notableFiles $playwrightFile
            }
        }
        foreach ($ruleFile in @("AGENTS.md", "CLAUDE.md", "GEMINI.md")) {
            if (Test-AuditFile $resolvedPath $ruleFile) {
                Add-AuditUniqueValue $agentRuleFiles $ruleFile
                Add-AuditUniqueValue $notableFiles $ruleFile
            }
        }
        Add-AuditMonorepoFacts $resolvedPath $frameworks $packageManagers $buildCommands $testCommands $notableFiles
        Add-AuditContainerFacts $resolvedPath $frameworks $buildCommands $notableFiles
        Add-AuditPyProjectFacts $resolvedPath $frameworks $packageManagers $buildCommands $testCommands $notableFiles
        Add-AuditJavaFacts $resolvedPath $languages $frameworks $packageManagers $buildCommands $testCommands $notableFiles
        Add-AuditRubyFacts $resolvedPath $languages $frameworks $packageManagers $buildCommands $testCommands $notableFiles
        Add-AuditPhpFacts $resolvedPath $languages $frameworks $packageManagers $buildCommands $testCommands $notableFiles
        Add-AuditMakefileFacts $resolvedPath $buildCommands $testCommands $notableFiles
        Add-AuditDotnetFacts $resolvedPath $frameworks $packageManagers $buildCommands $testCommands $notableFiles
        Add-AuditPowerShellFacts $resolvedPath $languages $buildCommands $testCommands $notableFiles
        Add-AuditDocumentedCommandFacts $resolvedPath $languages $buildCommands $testCommands $notableFiles
        Add-AuditDesignDocumentFacts $resolvedPath $languages $frameworks $packageManagers $buildCommands $testCommands $capabilities $notableFiles $risks $artifactCapabilities $requirementSignals
        Add-AuditCiWorkflowFacts $resolvedPath $buildCommands $testCommands $notableFiles
        Add-AuditArtifactManifestFacts $resolvedPath $artifactCapabilities $requirementSignals
        Add-AuditArtifactSourceFacts $resolvedPath $artifactCapabilities $risks $requirementSignals
        if ($null -ne $script:AuditLastSourceScanCoverage) { $scanCoverage = $script:AuditLastSourceScanCoverage }
        $slnFiles = @(Get-ChildItem -LiteralPath $resolvedPath -Filter "*.sln" -File -ErrorAction SilentlyContinue)
        $csprojFiles = @(Get-AuditRecursiveFiles $resolvedPath "*.csproj" 1)
        if ($slnFiles.Count -gt 0 -or $csprojFiles.Count -gt 0) {
            Add-AuditUniqueValue $languages "dotnet"
        }
    }

    return [pscustomobject]([ordered]@{
        schema_version = 1
        scanned_at = (Get-Date).ToString("o")
        target = [ordered]@{
            name = $targetName
            path = $inputPath
            resolved_path = $resolvedPath
            exists = $exists
        }
        git = $gitInfo
        detected = [ordered]@{
            languages = @($languages)
            package_managers = @($packageManagers)
            frameworks = @($frameworks)
            build_commands = @($buildCommands)
            test_commands = @($testCommands)
            capabilities = @($capabilities)
            artifact_capabilities = @(ConvertTo-AuditArtifactCapabilityArray $artifactCapabilities)
            requirement_signals = @(ConvertTo-AuditRequirementSignalArray $requirementSignals)
            agent_rule_files = @($agentRuleFiles)
            notable_files = @($notableFiles)
        }
        scan_coverage = $scanCoverage
        risks = @($risks)
    })
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
    $accumulator = New-AuditArtifactCapabilityAccumulator
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
    $accumulator = New-AuditRequirementSignalAccumulator
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

function New-AuditCoverageStatement($PrioritizedNeeds, $ProfileSelectedSkills) {
    # A positive coverage assertion: for each prioritized need, which current-profile
    # skills plausibly cover it.  Keyword plausibility only — never a proof of host
    # loading or successful invocation — so that "no add needed" becomes checkable.
    $skills = @(Convert-AuditObjectArray $ProfileSelectedSkills)
    if ($skills.Count -eq 0) { return @() }
    $statement = @()
    $needs = @()
    foreach ($need in @(Convert-AuditObjectArray (Get-CfgObjectProperty $PrioritizedNeeds "primary_needs"))) { $needs += $need }
    foreach ($need in @(Convert-AuditObjectArray (Get-CfgObjectProperty $PrioritizedNeeds "secondary_needs"))) { $needs += $need }
    foreach ($need in @(Convert-AuditObjectArray (Get-CfgObjectProperty $PrioritizedNeeds "supporting_artifacts"))) { $needs += $need }
    foreach ($need in @($needs)) {
        $needTokens = @(Merge-AuditKeywordSets @(
                @([string](Get-CfgObjectProperty $need "domain")),
                @([string](Get-CfgObjectProperty $need "subject")),
                @(Convert-AuditStringArray (Get-CfgObjectProperty $need "actions"))
            ) 40)
        $matched = New-Object System.Collections.Generic.List[string]
        foreach ($skill in @($skills)) {
            $hay = ((([string](Get-CfgObjectProperty $skill "name")) + ' ' + ([string](Get-CfgObjectProperty $skill "description")) + ' ' + ([string](Get-CfgObjectProperty $skill "trigger_summary")))).ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($hay)) { continue }
            foreach ($token in @($needTokens)) {
                if (-not [string]::IsNullOrWhiteSpace($token) -and $hay.Contains($token.ToLowerInvariant())) { Add-AuditUniqueValue $matched ([string](Get-CfgObjectProperty $skill "name")); break }
            }
        }
        $statement += [pscustomobject]([ordered]@{
                need = [string](Get-CfgObjectProperty $need "key")
                priority_band = [string](Get-CfgObjectProperty $need "priority_band")
                covered_by = @($matched.ToArray() | Sort-Object -Unique)
                coverage = if (@($matched).Count -gt 0) { "keyword_plausibly_covered_by_profile" } else { "keyword_unmatched_by_profile" }
            })
    }
    return @($statement)
}

function New-AuditTargetProfile($scans, $ProfileSelectedSkills = $null) {
    Need (@($scans).Count -gt 0) "扫描画像至少需要一个目标仓扫描结果。"
    $fields = @("languages", "package_managers", "frameworks", "build_commands", "test_commands", "capabilities", "agent_rule_files", "notable_files", "risks")
    $profile = [ordered]@{
        schema_version = 3
        derived_at = (Get-Date).ToString("o")
        derivation = "target_scans_only"
        target_names = @()
        scanned_target_count = @($scans).Count
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
    $minimumProductWorkflowSourceTargetCount = if (@($scans).Count -gt 1) { 2 } else { 1 }
    $profile.prioritized_needs = New-AuditPrioritizedNeeds $profile.requirement_signals $profile.artifact_capabilities $minimumProductWorkflowSourceTargetCount
    $profile.user_need_summary = New-AuditUserNeedSummary $profile.prioritized_needs @($scans).Count
    $profile.target_evidence_partitions = @(New-AuditTargetEvidencePartitions $scans)
    $profile.coverage_statement = @(New-AuditCoverageStatement $profile.prioritized_needs $ProfileSelectedSkills)
    $technology = @($profile.languages + $profile.frameworks + $profile.package_managers | Select-Object -First 8)
    $capability = @($profile.capabilities | Select-Object -First 6)
    $primary = @($profile.prioritized_needs.primary_needs | ForEach-Object { [string]$_.key })
    $secondaryCount = @($profile.prioritized_needs.secondary_needs).Count
    $observationCount = @($profile.prioritized_needs.observations).Count
    $primaryText = if ($primary.Count -gt 0) { $primary -join ', ' } else { "无达到主需求阈值的扫描信号" }
    $profile.summary = "由 $($profile.scanned_target_count) 个启用目标仓派生的全仓汇总画像；重点需求：$primaryText；次级需求=$secondaryCount；观察项=$observationCount。目标仓扫描仅用于证据归属与覆盖统计；技术信号：$($technology -join ', ')；能力信号：$($capability -join ', ')。"
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
                "not_observed invocation evidence cannot establish non-use or justify retirement without reachability or route validation."
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

