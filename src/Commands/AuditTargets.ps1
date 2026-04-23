function Get-AuditTargetsConfigPath {
    return (Join-Path $script:Root "audit-targets.json")
}

function Get-AuditStructuredProfileDefaultPath {
    return (Join-Path $script:Root "reports\skill-audit\user-profile.structured.json")
}

function Get-AuditOuterAiPromptOverridePath {
    return (Join-Path $script:Root "overrides\audit-outer-ai-prompt.md")
}

function Get-DefaultAuditOuterAiPrompt {
    return @"
# Outer AI Audit Prompt (Short / Codex + Claude)

目标：代理完成审查流程；先产出并自检 recommendations.json，再执行 dry-run。

1) run-id
- 允许 ``<run-id>``，自动解析最近可用 run（必须含 recommendations.json / installed-skills.json / audit-meta.json）。
- 若无可用 run：立即停止并报告：先执行 ``.\skills.ps1 审查目标 扫描``。

2) 画像预检查
- 检查 audit-targets.json.user_profile。
- 若 summary 为空或 structured 不完整：补全 ``reports/skill-audit/user-profile.structured.json``（schema 不变，summary 非空，structured_by="outer-ai"），然后执行：
  ``.\skills.ps1 审查目标 需求结构化 --profile "reports\skill-audit\user-profile.structured.json"``
- 导入后复查；失败最多重试 1 次，再失败立即停止。

3) 只读输入（必须真实读取）
- outer-ai-prompt.md、ai-brief.md、user-profile.json、installed-skills.json（仅输入快照）、source-strategy.json、recommendations.template.json
- repo-scan.json / repo-scans.json：存在才读；N/A/profile-only 不得臆造仓库事实

4) 产出 recommendations.json
- 路径：``reports/skill-audit/<run-id>/recommendations.json``
- ``schema_version=2``；不得保留 ``<...>``；``decision_basis.summary`` 非空
- 每条新增/卸载（skills/MCP）必须有：``reason_user_profile``、``reason_target_repo``、``sources``（仅本轮真实来源）
- MCP 新增写 ``mcp_new_servers`` 且 ``name==server.name``；MCP 卸载写 ``mcp_removal_candidates``
- ``overlap_findings`` 仅报告；``do_not_install`` 仅记录当前不应安装项；证据不足留空

5) 自检后 dry-run
- 自检：JSON/schema/双理由/sources/无占位符
- dry-run：
  ``.\skills.ps1 审查目标 应用 --recommendations "reports\skill-audit\<run-id>\recommendations.json" --dry-run-ack "我知道未落盘"``
- 自检或 dry-run 失败即停止并报告阻断项

6) 汇报格式（按 dry-run 原序号，不重排）
- 新增建议 / 卸载建议 / MCP 新增建议 / MCP 卸载建议
- 每项：序号、名称、reason_user_profile、reason_target_repo、sources
- 空类必须写“无该类建议”，并给 1 句原因

安全约束：未收到明确确认，不执行 ``--apply --yes``。
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

function New-DefaultAuditUserProfile {
    return [pscustomobject]@{
        raw_text = ""
        summary = ""
        structured = [pscustomobject]@{
            primary_work_types = @()
            preferred_agents = @()
            tech_stack = @()
            common_tasks = @()
            constraints = @()
            avoidances = @()
            decision_preferences = @()
        }
        last_structured_at = ""
        structured_by = ""
    }
}

function Get-AuditStructuredProfileFieldNames {
    return @("primary_work_types", "preferred_agents", "tech_stack", "common_tasks", "constraints", "avoidances", "decision_preferences")
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

function Normalize-AuditStructuredProfile($structuredInput) {
    $normalized = [pscustomobject]@{}
    foreach ($field in Get-AuditStructuredProfileFieldNames) {
        $normalized | Add-Member -NotePropertyName $field -NotePropertyValue @() -Force
    }
    if (-not (Test-AuditObjectLike $structuredInput)) {
        return $normalized
    }
    foreach ($field in Get-AuditStructuredProfileFieldNames) {
        $rawValue = $null
        if (Get-AuditObjectFieldValue $structuredInput $field ([ref]$rawValue)) {
            $normalized.$field = @(Convert-AuditStringArray $rawValue)
        }
    }
    return $normalized
}

function Ensure-AuditUserProfile($cfg) {
    $changed = $false
    if (-not $cfg.PSObject.Properties.Match("user_profile").Count -or $null -eq $cfg.user_profile) {
        $cfg | Add-Member -NotePropertyName user_profile -NotePropertyValue (New-DefaultAuditUserProfile) -Force
        $changed = $true
    }

    $profile = $cfg.user_profile
    foreach ($name in @("raw_text", "summary", "last_structured_at", "structured_by")) {
        if (-not $profile.PSObject.Properties.Match($name).Count) {
            $profile | Add-Member -NotePropertyName $name -NotePropertyValue "" -Force
            $changed = $true
        }
        elseif ($null -eq $profile.$name) {
            $profile.$name = ""
            $changed = $true
        }
        elseif (-not ($profile.$name -is [string])) {
            $profile.$name = [string]$profile.$name
            $changed = $true
        }
    }
    if (-not $profile.PSObject.Properties.Match("structured").Count) {
        $profile | Add-Member -NotePropertyName structured -NotePropertyValue (Normalize-AuditStructuredProfile $null) -Force
        $changed = $true
    }
    $currentStructuredJson = ($profile.structured | ConvertTo-Json -Depth 20 -Compress)
    $normalizedStructured = Normalize-AuditStructuredProfile $profile.structured
    $normalizedStructuredJson = ($normalizedStructured | ConvertTo-Json -Depth 20 -Compress)
    if ($currentStructuredJson -ne $normalizedStructuredJson) {
        $profile.structured = $normalizedStructured
        $changed = $true
    }
    return $changed
}

function New-DefaultAuditTargetsConfig {
    return [pscustomobject]@{
        version = 2
        path_base = "skills_manager_root"
        user_profile = New-DefaultAuditUserProfile
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
    if ([int]$cfg.version -eq 1) {
        $cfg.version = 2
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
    if (Ensure-AuditUserProfile $cfg) {
        $changed = $true
    }

    Need ([int]$cfg.version -eq 2) "audit-targets.json version 仅支持 2"
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

function Set-AuditUserProfileRawText([string]$rawText) {
    Initialize-AuditTargetsConfig | Out-Null
    $cfg = Load-AuditTargetsConfig
    Need (-not [string]::IsNullOrWhiteSpace($rawText)) "用户基本需求不能为空"
    $cfg.user_profile.raw_text = $rawText.Trim()
    $cfg.user_profile.summary = ""
    $cfg.user_profile.structured = (New-DefaultAuditUserProfile).structured
    $cfg.user_profile.last_structured_at = ""
    $cfg.user_profile.structured_by = ""
    Save-AuditTargetsConfig $cfg
}

function Show-AuditUserProfile {
    $cfg = Load-AuditTargetsConfig
    Write-Host "=== 用户基本需求 ==="
    Write-Host ([string]$cfg.user_profile.raw_text)
    Write-Host ""
    Write-Host ("summary: {0}" -f [string]$cfg.user_profile.summary)
    Write-Host ("structured_by: {0}" -f [string]$cfg.user_profile.structured_by)
}

function New-AuditStructuredProfileDraft([string]$rawText) {
    return [pscustomobject]@{
        raw_text = $rawText
        summary = ""
        structured = (New-DefaultAuditUserProfile).structured
        last_structured_at = ""
        structured_by = "outer-ai"
    }
}

function Get-AuditFallbackSummaryFromRawText([string]$rawText) {
    $normalized = [regex]::Replace([string]$rawText, "\s+", " ").Trim()
    if ([string]::IsNullOrWhiteSpace($normalized)) { return "" }
    if ($normalized.Length -le 120) { return $normalized }
    return ($normalized.Substring(0, 120) + "...")
}

function Get-AuditStructuredProfileRequiredNonEmptyFields {
    return @("primary_work_types", "tech_stack", "common_tasks", "decision_preferences")
}

function Test-AuditTimestampString([string]$value) {
    if ([string]::IsNullOrWhiteSpace([string]$value)) { return $false }
    $parsed = [DateTimeOffset]::MinValue
    return [DateTimeOffset]::TryParse([string]$value, [ref]$parsed)
}

function Convert-AuditTimestampToIso($value, [switch]$FallbackNow) {
    if ($value -is [DateTimeOffset]) {
        return ([DateTimeOffset]$value).ToString("o")
    }
    if ($value -is [DateTime]) {
        return ([DateTimeOffset]$value).ToString("o")
    }
    if ($null -ne $value) {
        $text = [string]$value
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $parsed = [DateTimeOffset]::MinValue
            if ([DateTimeOffset]::TryParse($text, [ref]$parsed)) {
                return $parsed.ToString("o")
            }
        }
    }
    if ($FallbackNow) {
        return (Get-Date).ToString("o")
    }
    return ""
}

function Get-AuditStructuredFallbackValues([string]$field, [string]$rawText) {
    $summary = Get-AuditFallbackSummaryFromRawText $rawText
    $generic = if ([string]::IsNullOrWhiteSpace($summary)) { "general workflow" } else { $summary }
    switch ($field) {
        "primary_work_types" { return @("需求分析与交付") }
        "tech_stack" {
            if ([regex]::IsMatch($rawText, "(?i)\bwindows\b")) { return @("Windows") }
            return @("Mixed stack")
        }
        "common_tasks" { return @($generic) }
        "decision_preferences" { return @("evidence-first") }
        default { return @() }
    }
}

function Test-AuditStructuredProfileComplete($structuredInput) {
    if (-not (Test-AuditObjectLike $structuredInput)) { return $false }
    $normalized = Normalize-AuditStructuredProfile $structuredInput
    foreach ($field in Get-AuditStructuredProfileFieldNames) {
        if ($normalized.PSObject.Properties.Match($field).Count -eq 0) { return $false }
        if (-not (Assert-IsArray $normalized.$field)) { return $false }
    }
    foreach ($required in Get-AuditStructuredProfileRequiredNonEmptyFields) {
        if (@($normalized.$required).Count -eq 0) { return $false }
    }
    return $true
}

function New-AuditPrecheckStructuredProfile($cfg) {
    $rawText = [string]$cfg.user_profile.raw_text
    $summary = [string]$cfg.user_profile.summary
    if ([string]::IsNullOrWhiteSpace($summary)) {
        $summary = Get-AuditFallbackSummaryFromRawText $rawText
    }
    $structured = Normalize-AuditStructuredProfile $cfg.user_profile.structured
    foreach ($field in Get-AuditStructuredProfileRequiredNonEmptyFields) {
        if (@($structured.$field).Count -eq 0) {
            $structured.$field = @(Get-AuditStructuredFallbackValues $field $rawText)
        }
    }
    return [pscustomobject]@{
        raw_text = $rawText
        summary = $summary
        structured = $structured
        last_structured_at = (Get-Date).ToString("o")
        structured_by = "outer-ai"
    }
}

function Ensure-AuditUserProfilePrecheck {
    $profilePath = Get-AuditStructuredProfileDefaultPath
    $maxAttempts = 2

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $cfg = Load-AuditTargetsConfig
        Need (-not [string]::IsNullOrWhiteSpace([string]$cfg.user_profile.raw_text)) "缺少用户基本需求，请先运行：./skills.ps1 审查目标 需求设置"

        $summaryMissing = [string]::IsNullOrWhiteSpace([string]$cfg.user_profile.summary)
        $structuredIncomplete = -not (Test-AuditStructuredProfileComplete $cfg.user_profile.structured)
        $timestampInvalid = -not (Test-AuditTimestampString ([string]$cfg.user_profile.last_structured_at))
        if (-not $summaryMissing -and -not $structuredIncomplete -and -not $timestampInvalid) {
            return $cfg
        }

        Write-AuditJsonFile $profilePath (New-AuditPrecheckStructuredProfile $cfg)
        try {
            Invoke-AuditStructuredProfileFlow $profilePath
        }
        catch {
            if ($attempt -ge $maxAttempts) {
                throw ("画像预检查失败：自动导入结构化需求失败（已重试 1 次）。请先执行：.\skills.ps1 审查目标 需求结构化 --profile `"{0}`"。错误：{1}" -f $profilePath, $_.Exception.Message)
            }
        }
    }

    throw ("画像预检查失败：summary/structured/last_structured_at 仍不完整（已重试 1 次）。请先执行：.\skills.ps1 审查目标 需求结构化 --profile `"{0}`"" -f $profilePath)
}

function Write-AuditStructuredProfileDraft([string]$profilePath, [string]$rawText) {
    if ([string]::IsNullOrWhiteSpace($profilePath)) {
        $profilePath = Get-AuditStructuredProfileDefaultPath
    }
    $resolved = Resolve-AuditTargetPath $profilePath
    Write-AuditJsonFile $resolved (New-AuditStructuredProfileDraft $rawText)
    return $resolved
}

function Import-AuditUserProfileStructured([string]$profilePath) {
    if ([string]::IsNullOrWhiteSpace($profilePath)) {
        $profilePath = Get-AuditStructuredProfileDefaultPath
    }
    $resolved = Resolve-AuditTargetPath $profilePath
    Need (Test-Path -LiteralPath $resolved -PathType Leaf) ("找不到 profile 文件：{0}" -f $profilePath)

    try {
        $raw = Get-ContentUtf8 $resolved
        Need (-not [string]::IsNullOrWhiteSpace($raw)) ("profile 文件为空：{0}" -f $profilePath)
        $imported = $raw | ConvertFrom-Json
    }
    catch {
        throw ("profile 文件解析失败：{0}" -f $_.Exception.Message)
    }
    Need (Test-AuditObjectLike $imported) ("profile 文件根节点必须是对象：{0}" -f $profilePath)

    Initialize-AuditTargetsConfig | Out-Null
    $cfg = Load-AuditTargetsConfig

    $importedRawText = $null
    if (Get-AuditObjectFieldValue $imported "raw_text" ([ref]$importedRawText)) {
        $text = [string]$importedRawText
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $cfg.user_profile.raw_text = $text.Trim()
        }
    }

    $importedSummary = $null
    if (Get-AuditObjectFieldValue $imported "summary" ([ref]$importedSummary)) {
        $cfg.user_profile.summary = [string]$importedSummary
    }

    $importedStructured = $null
    if (Get-AuditObjectFieldValue $imported "structured" ([ref]$importedStructured)) {
        Need (Test-AuditObjectLike $importedStructured) ("profile.structured 必须是对象：{0}" -f $profilePath)
        $cfg.user_profile.structured = Normalize-AuditStructuredProfile $importedStructured
    }

    $importedStructuredBy = $null
    if (Get-AuditObjectFieldValue $imported "structured_by" ([ref]$importedStructuredBy)) {
        $cfg.user_profile.structured_by = [string]$importedStructuredBy
    }
    else {
        $cfg.user_profile.structured_by = "manual"
    }

    $importedStructuredAt = $null
    if (Get-AuditObjectFieldValue $imported "last_structured_at" ([ref]$importedStructuredAt)) {
        $cfg.user_profile.last_structured_at = Convert-AuditTimestampToIso $importedStructuredAt -FallbackNow
    }
    else {
        $cfg.user_profile.last_structured_at = (Get-Date).ToString("o")
    }
    if (-not (Test-AuditTimestampString ([string]$cfg.user_profile.last_structured_at))) {
        $cfg.user_profile.last_structured_at = (Get-Date).ToString("o")
    }

    Ensure-AuditUserProfile $cfg | Out-Null
    Need (-not [string]::IsNullOrWhiteSpace([string]$cfg.user_profile.raw_text)) "导入后用户基本需求为空，请在 profile.raw_text 填写非空文本或先执行“需求设置”"
    Save-AuditTargetsConfig $cfg
}

function Invoke-AuditStructuredProfileFlow([string]$profilePath = "") {
    $cfg = Load-AuditTargetsConfig
    $defaultPath = Get-AuditStructuredProfileDefaultPath
    $chosen = if ([string]::IsNullOrWhiteSpace($profilePath)) { $defaultPath } else { $profilePath }
    $resolved = Resolve-AuditTargetPath $chosen

    if (Test-Path -LiteralPath $resolved -PathType Leaf) {
        Import-AuditUserProfileStructured $chosen
        Write-Host ("已导入结构化需求：{0}" -f $resolved) -ForegroundColor Green
        return
    }

    $draft = Write-AuditStructuredProfileDraft $chosen ([string]$cfg.user_profile.raw_text)
    Write-Host ("未找到结构化 profile，已生成默认草稿：{0}" -f $draft) -ForegroundColor Yellow
    Write-Host "请让 AI 或手动填写该文件后，再运行：./skills.ps1 审查目标 需求结构化" -ForegroundColor Yellow
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

function Assert-AuditUserProfileReady($cfg) {
    Need (-not [string]::IsNullOrWhiteSpace([string]$cfg.user_profile.raw_text)) "缺少用户基本需求，请先运行：./skills.ps1 审查目标 需求设置"
    Need (Test-AuditObjectLike $cfg.user_profile.structured) "用户结构化需求格式异常，请先运行：./skills.ps1 审查目标 需求结构化"
    foreach ($field in Get-AuditStructuredProfileFieldNames) {
        Need ($cfg.user_profile.structured.PSObject.Properties.Match($field).Count -gt 0) ("用户结构化需求缺少字段：{0}" -f $field)
        Need (Assert-IsArray $cfg.user_profile.structured.$field) ("用户结构化需求字段必须为数组：{0}" -f $field)
    }
    foreach ($required in Get-AuditStructuredProfileRequiredNonEmptyFields) {
        Need (@($cfg.user_profile.structured.$required).Count -gt 0) ("用户结构化需求字段不能为空：{0}" -f $required)
    }
    if ([string]::IsNullOrWhiteSpace([string]$cfg.user_profile.summary)) {
        Write-Host "提示：用户结构化 summary 为空，建议先完善结构化需求后再生成审查包。" -ForegroundColor Yellow
    }
    Need (Test-AuditTimestampString ([string]$cfg.user_profile.last_structured_at)) "用户结构化时间戳缺失或无效，请先运行：./skills.ps1 审查目标 需求结构化"
}

function Get-AuditUserProfileOutput($cfg) {
    return [pscustomobject]@{
        schema_version = 1
        raw_text = [string]$cfg.user_profile.raw_text
        summary = [string]$cfg.user_profile.summary
        structured = $cfg.user_profile.structured
        last_structured_at = Convert-AuditTimestampToIso $cfg.user_profile.last_structured_at -FallbackNow
        structured_by = [string]$cfg.user_profile.structured_by
    }
}

function Get-AuditRunId {
    return (Get-Date -Format "yyyyMMdd-HHmmss-fff")
}

function Get-AuditPromptContractVersion {
    return "audit-prompt-v20260422.3"
}

function Get-AuditReportRoot([string]$runId) {
    return (Join-Path $script:Root (Join-Path "reports\skill-audit" $runId))
}

function Test-AuditPlaceholderToken([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    return ([regex]::IsMatch($text, "<[^>]+>"))
}

function Get-AuditKnownRunIds {
    $auditRoot = Join-Path $script:Root "reports\skill-audit"
    if (-not (Test-Path -LiteralPath $auditRoot -PathType Container)) { return @() }
    $dirs = @(Get-ChildItem -LiteralPath $auditRoot -Directory -ErrorAction SilentlyContinue)
    return @($dirs | Select-Object -ExpandProperty Name | Sort-Object)
}

function Get-AuditLatestRunId([string[]]$RequiredFiles = @()) {
    $auditRoot = Join-Path $script:Root "reports\skill-audit"
    if (-not (Test-Path -LiteralPath $auditRoot -PathType Container)) { return "" }
    $dirs = @(
        Get-ChildItem -LiteralPath $auditRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object -Property @{ Expression = { $_.LastWriteTimeUtc }; Descending = $true }, @{ Expression = { $_.Name }; Descending = $true }
    )
    $liveStateResolved = $false
    $liveState = $null
    $liveStateAvailable = $false
    $currentPromptVersion = ""
    $freshCandidates = New-Object System.Collections.Generic.List[string]
    $unknownCandidates = New-Object System.Collections.Generic.List[string]
    $staleCandidates = New-Object System.Collections.Generic.List[string]
    foreach ($dir in $dirs) {
        $ok = $true
        foreach ($relative in @($RequiredFiles)) {
            if (-not (Test-AuditFile $dir.FullName ([string]$relative))) {
                $ok = $false
                break
            }
        }
        if (-not $ok) { continue }

        $snapshotPath = Join-Path $dir.FullName "installed-skills.json"
        $metaPath = Join-Path $dir.FullName "audit-meta.json"
        $canCheckStale = (Test-Path -LiteralPath $snapshotPath -PathType Leaf) -and (Test-Path -LiteralPath $metaPath -PathType Leaf)
        if (-not $canCheckStale) {
            $unknownCandidates.Add([string]$dir.Name) | Out-Null
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
            $unknownCandidates.Add([string]$dir.Name) | Out-Null
            continue
        }

        $isStale = $false
        try {
            $snapshotState = Get-AuditInstalledSnapshotState $snapshotPath
            $skillSnapshotStale = ([string]$snapshotState.fingerprint -ne [string]$liveState.fingerprint)
            $mcpSnapshotStale = $false
            if ($snapshotState.PSObject.Properties.Match("mcp_fingerprint").Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$snapshotState.mcp_fingerprint)) {
                $mcpSnapshotStale = ([string]$snapshotState.mcp_fingerprint -ne [string]$liveState.mcp_fingerprint)
            }
            if ($skillSnapshotStale -or $mcpSnapshotStale) {
                $isStale = $true
            }
        }
        catch {
            $unknownCandidates.Add([string]$dir.Name) | Out-Null
            continue
        }

        try {
            $metaRaw = Get-ContentUtf8 $metaPath
            if (-not [string]::IsNullOrWhiteSpace($metaRaw)) {
                $meta = $metaRaw | ConvertFrom-Json
                if ($meta.PSObject.Properties.Match("prompt_contract_version").Count -gt 0) {
                    $runPromptVersion = ([string]$meta.prompt_contract_version).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($runPromptVersion) -and [string]$runPromptVersion -ne [string]$currentPromptVersion) {
                        $isStale = $true
                    }
                }
            }
        }
        catch {
            $unknownCandidates.Add([string]$dir.Name) | Out-Null
            continue
        }

        if ($isStale) {
            $staleCandidates.Add([string]$dir.Name) | Out-Null
        }
        else {
            $freshCandidates.Add([string]$dir.Name) | Out-Null
        }
    }
    if ($freshCandidates.Count -gt 0) { return [string]$freshCandidates[0] }
    if ($unknownCandidates.Count -gt 0) { return [string]$unknownCandidates[0] }
    if ($staleCandidates.Count -gt 0) { return "" }
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
    $ids = @(Get-AuditKnownRunIds)
    if ($ids.Count -eq 0) {
        return "可用 run-id：无（先执行 .\skills.ps1 审查目标 扫描）"
    }
    if (@($RequiredFiles).Count -eq 0) {
        return ("可用 run-id：{0}" -f ($ids -join ", "))
    }

    $valid = New-Object System.Collections.Generic.List[string]
    $invalid = New-Object System.Collections.Generic.List[string]
    foreach ($id in $ids) {
        $runRoot = Get-AuditReportRoot $id
        $missing = New-Object System.Collections.Generic.List[string]
        foreach ($relative in @($RequiredFiles)) {
            if (-not (Test-AuditFile $runRoot ([string]$relative))) {
                $missing.Add([string]$relative) | Out-Null
            }
        }
        if ($missing.Count -eq 0) {
            $valid.Add([string]$id) | Out-Null
        }
        else {
            $invalid.Add(("{0}(缺少: {1})" -f $id, ($missing -join ","))) | Out-Null
        }
    }

    if ($valid.Count -gt 0) {
        return ("可用 run-id：{0}" -f ($valid -join ", "))
    }
    return ("可用 run-id：无（先执行 .\skills.ps1 审查目标 扫描）; 不可用 run：{0}" -f ($invalid -join "; "))
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

function Add-AuditDotnetFacts([string]$resolvedPath, [System.Collections.Generic.List[string]]$frameworks, [System.Collections.Generic.List[string]]$packageManagers, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$testCommands, [System.Collections.Generic.List[string]]$notableFiles) {
    $slnFiles = @(Get-ChildItem -LiteralPath $resolvedPath -Filter "*.sln" -File -ErrorAction SilentlyContinue | Select-Object -First 10)
    $csprojFiles = @(Get-ChildItem -LiteralPath $resolvedPath -Filter "*.csproj" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 40)
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

function Get-AuditGitInfo([string]$resolvedPath) {
    $info = [ordered]@{
        is_repo = $false
        branch = ""
        commit = ""
        dirty = $false
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
            if ($LASTEXITCODE -eq 0) { $info.dirty = ($status.Count -gt 0) }
        }
    }
    finally {
        Pop-Location
    }
    return [pscustomobject]$info
}

function New-AuditRepoScan([string]$targetName, [string]$resolvedPath, [string]$inputPath) {
    $exists = Test-Path -LiteralPath $resolvedPath -PathType Container
    $risks = New-Object System.Collections.Generic.List[string]
    $languages = New-Object System.Collections.Generic.List[string]
    $packageManagers = New-Object System.Collections.Generic.List[string]
    $frameworks = New-Object System.Collections.Generic.List[string]
    $buildCommands = New-Object System.Collections.Generic.List[string]
    $testCommands = New-Object System.Collections.Generic.List[string]
    $agentRuleFiles = New-Object System.Collections.Generic.List[string]
    $notableFiles = New-Object System.Collections.Generic.List[string]

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
        Add-AuditPyProjectFacts $resolvedPath $frameworks $packageManagers $buildCommands $testCommands $notableFiles
        Add-AuditDotnetFacts $resolvedPath $frameworks $packageManagers $buildCommands $testCommands $notableFiles
        Add-AuditCiWorkflowFacts $resolvedPath $buildCommands $testCommands $notableFiles
        $slnFiles = @(Get-ChildItem -LiteralPath $resolvedPath -Filter "*.sln" -File -ErrorAction SilentlyContinue)
        $csprojFiles = @(Get-ChildItem -LiteralPath $resolvedPath -Filter "*.csproj" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
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
            agent_rule_files = @($agentRuleFiles)
            notable_files = @($notableFiles)
        }
        risks = @($risks)
    })
}

function Write-AuditJsonFile([string]$path, $data) {
    EnsureDir (Split-Path $path -Parent)
    Set-ContentUtf8 $path ($data | ConvertTo-Json -Depth 40)
}

function Write-AuditAiBrief([string]$path, $scanData, [string]$userProfilePath, [string]$repoScanPath, [string]$repoScansPath, [string]$installedSkillsPath, [string]$templatePath, [string]$Mode = "target-repo", [string]$Query = "", [string]$SourceStrategyPath = "") {
    $normalizedMode = if ([string]::IsNullOrWhiteSpace($Mode)) { "target-repo" } else { $Mode.ToLowerInvariant() }
    $targetNames = @($scanData | ForEach-Object { $_.target.name })
    if ([string]::IsNullOrWhiteSpace($repoScanPath)) { $repoScanPath = "N/A" }
    if ([string]::IsNullOrWhiteSpace($repoScansPath)) { $repoScansPath = "N/A" }
    if ([string]::IsNullOrWhiteSpace($SourceStrategyPath)) { $SourceStrategyPath = "N/A" }

    if ($normalizedMode -eq "profile-only") {
        $queryText = if ([string]::IsNullOrWhiteSpace($Query)) { "N/A" } else { $Query }
        $content = @"
# Skill Audit Brief

Run ID: $(Split-Path (Split-Path $path -Parent) -Leaf)
Mode: profile-only skill discovery
Targets: N/A
Discovery query: $queryText

Use the generated user profile JSON, installed-skills snapshot JSON, and source strategy JSON to decide:

- Which installed skills should be kept for the user's long-term workflow.
- Which installed skills should be proposed for removal because they no longer fit.
- Which installed MCP servers should be kept or removed.
- Which missing skills are strongly justified without binding the decision to a target repository.
- Which missing MCP servers are strongly justified without binding the decision to a target repository.

External research is intentionally performed by the outer AI agent. Search official documentation, strong community projects, best practices, https://skills.sh/, GitHub Trending, and the find-skills workflow.

Primary output file (must be valid JSON, no prose):

$templatePath

Scan inputs:
- Single-target scan JSON: N/A
- Multi-target scans JSON: N/A
- Source strategy JSON: $SourceStrategyPath

Rules:

- Profile-only mode has no target repo scan; do not fabricate repository facts.
- All decisions must be based on user-profile.json, installed-skills.json (audit snapshot, not live source of truth), source-strategy.json, and real external research.
- Use ``reason_target_repo`` to explain the current installed-skill inventory / profile-only context; do not claim target repository evidence.
- If any required local input is missing, unreadable, or empty, stop and report the blocker instead of guessing.
- Network research is authorized within this audit workflow, but installation still requires --apply --yes.
- Replace every template placeholder wrapped in `<...>` or delete the example entry entirely; do not leave placeholder values in the final file.
- Keep ``recommendation_mode`` as ``profile-only``.
- Keep ``decision_basis.user_profile_used`` and ``decision_basis.source_strategy_used`` as boolean ``true``; keep ``decision_basis.target_scan_used`` as boolean ``false``; provide a non-empty ``decision_basis.summary``.
- Skill installs require ``reason_user_profile``, ``reason_target_repo``, source links, confidence, repo, skill path, ref, and mode.
- Skill removals must include ``reason_user_profile``, ``reason_target_repo``, sources, and the exact installed ``vendor``/``from`` pair.
- MCP installs must include ``reason_user_profile``, ``reason_target_repo``, sources, confidence, and a valid ``server`` payload.
- MCP removals must include ``reason_user_profile``, ``reason_target_repo``, sources, and ``installed.name``.
- Skill ``install.mode`` must stay ``manual`` or ``vendor``; ``confidence`` must stay ``low``, ``medium``, or ``high``.
- MCP ``server.transport`` must stay ``stdio``/``sse``/``http``; ``stdio`` requires ``command``; ``sse/http`` requires ``url``.
- Each add/remove recommendation must keep both reasons concise and user-readable.
- If either reason field is missing on any recommendation, treat the run as incomplete and stop before dry-run summary.
- Overlap findings are report-only; do not recommend automatic uninstall.
- Use ``do_not_install`` for researched options that should stay out of the repo right now.
- Prefer high-reputation sources and avoid weak duplicate skills.
- Cover the built-in default sources and record the actual sources you used.
- Keep recommendations machine-readable JSON matching the template.
- The template already includes placeholder example items. Replace placeholder values or delete the example entries you do not need; do not invent a different schema.
- Cite only sources you actually inspected during this run. Do not fabricate source links or source conclusions.
- If evidence is insufficient, leave the category empty and explain briefly instead of forcing low-quality recommendations.
- After dry-run, show numbered skill add/remove and MCP add/remove lists with one-line reasons per item (``reason_user_profile`` + ``reason_target_repo``).
- If a list is empty, explicitly output "no <category> recommendations" with a brief reason.
- Keep dry-run numbering stable; do not renumber or reorder indexes in the user-facing summary.

Pre-dry-run self-check:

- recommendations.json parses as JSON and keeps ``schema_version = 2``.
- ``recommendation_mode`` is ``profile-only``.
- ``decision_basis.user_profile_used`` and ``decision_basis.source_strategy_used`` are ``true``.
- ``decision_basis.target_scan_used`` is ``false``.
- No remaining placeholder values wrapped in `<...>`.
- Each skill/MCP add/remove item has both reasons plus at least one real source.
- Stop before dry-run if any self-check item fails.

Execution order:

1) Read all local inputs
2) Write ``recommendations.json`` from ``recommendations.template.json``
3) Run the self-check and stop if any item fails
4) Execute dry-run
5) Summarize dry-run with original indexes and one-line dual-reason entries
6) Wait for explicit user confirmation before apply

User-facing dry-run summary format:

- add: ``[index] <skill-name> | user: <reason_user_profile> | context: <reason_target_repo>``
- remove: ``[index] <skill-name> | user: <reason_user_profile> | context: <reason_target_repo>``
- mcp-add: ``[index] <mcp-name> | user: <reason_user_profile> | context: <reason_target_repo>``
- mcp-remove: ``[index] <mcp-name> | user: <reason_user_profile> | context: <reason_target_repo>``
- empty category: ``no add recommendations: <brief reason>`` / ``no removal recommendations: <brief reason>`` / ``no mcp-add recommendations: <brief reason>`` / ``no mcp-remove recommendations: <brief reason>``

User profile JSON: $userProfilePath
Installed skills JSON: $installedSkillsPath
Source strategy JSON: $SourceStrategyPath
"@
        Set-ContentUtf8 $path $content
        return
    }

    $content = @"
# Skill Audit Brief

Run ID: $(Split-Path (Split-Path $path -Parent) -Leaf)
Targets: $($targetNames -join ", ")

Use the generated user profile JSON, repo scan JSON, and installed-skills snapshot JSON to decide:

- Which installed skills should be kept for each target repository.
- Which installed skills should be proposed for removal.
- Which installed MCP servers should be kept for each target repository.
- Which installed MCP servers should be proposed for removal.
- Which missing skills are strongly justified for these targets.
- Which missing MCP servers are strongly justified for these targets.

External research is intentionally performed by the outer AI agent. Search official documentation, strong community projects, best practices, https://skills.sh/, GitHub Trending, and the find-skills workflow.

Primary output file (must be valid JSON, no prose):

$templatePath

Scan inputs:
- Single-target scan JSON: $repoScanPath
- Multi-target scans JSON: $repoScansPath
- Source strategy JSON: $SourceStrategyPath

Rules:

- All decisions must be based on BOTH user-profile.json and target repo scan facts, and must use installed-skills.json as the audit snapshot for currently installed skills and MCP servers.
- Use source-strategy.json to cover the built-in source set and explain source tradeoffs.
- Treat any scan path shown as ``N/A`` as "not provided"; do not infer hidden content from it.
- If any required local input is missing, unreadable, or empty, stop and report the blocker instead of guessing.
- Network research is authorized within this audit workflow, but installation still requires --apply --yes.
- Replace every template placeholder wrapped in `<...>` or delete the example entry entirely; do not leave placeholder values in the final file.
- Keep ``decision_basis.user_profile_used``, ``decision_basis.target_scan_used``, and ``decision_basis.source_strategy_used`` as boolean ``true``, and provide a non-empty ``decision_basis.summary``.
- Skill installs require ``reason_user_profile``, ``reason_target_repo``, source links, confidence, repo, skill path, ref, and mode.
- Skill removals must include ``reason_user_profile``, ``reason_target_repo``, sources, and the exact installed ``vendor``/``from`` pair.
- MCP installs must include ``reason_user_profile``, ``reason_target_repo``, sources, confidence, and a valid ``server`` payload.
- MCP removals must include ``reason_user_profile``, ``reason_target_repo``, sources, and ``installed.name``.
- Skill ``install.mode`` must stay ``manual`` or ``vendor``; ``confidence`` must stay ``low``, ``medium``, or ``high``.
- MCP ``server.transport`` must stay ``stdio``/``sse``/``http``; ``stdio`` requires ``command``; ``sse/http`` requires ``url``.
- Each add/remove recommendation must keep both reasons concise and user-readable.
- If either reason field is missing on any recommendation, treat the run as incomplete and stop before dry-run summary.
- Overlap findings are report-only; do not recommend automatic uninstall.
- Use ``do_not_install`` for researched options that should stay out of the repo right now.
- Prefer high-reputation sources and avoid weak duplicate skills.
- Cover the built-in default sources and record the actual sources you used.
- Keep recommendations machine-readable JSON matching the template.
- The template already includes placeholder example items. Replace placeholder values or delete the example entries you do not need; do not invent a different schema.
- Cite only sources you actually inspected during this run. Do not fabricate repository facts, source links, or source conclusions.
- If evidence is insufficient, leave the category empty and explain briefly instead of forcing low-quality recommendations.
- After dry-run, show numbered skill add/remove and MCP add/remove lists with one-line reasons per item (``reason_user_profile`` + ``reason_target_repo``).
- If a list is empty, explicitly output "no <category> recommendations" with a brief reason.
- Keep dry-run numbering stable; do not renumber or reorder indexes in the user-facing summary.

Pre-dry-run self-check:

- recommendations.json parses as JSON and keeps ``schema_version = 2``.
- ``decision_basis`` keeps all required boolean flags at ``true``.
- ``decision_basis.summary`` is non-empty.
- No remaining placeholder values wrapped in `<...>`.
- Each skill/MCP add/remove item has both reasons plus at least one real source.
- Each MCP add item keeps ``name == server.name``.
- No duplicate skill add/remove or MCP add/remove recommendations remain in the final file.
- Stop before dry-run if any self-check item fails.

Execution order:

1) Read all local inputs
2) Write ``recommendations.json`` from ``recommendations.template.json``
3) Run the self-check and stop if any item fails
4) Execute dry-run
5) Summarize dry-run with original indexes and one-line dual-reason entries
6) Wait for explicit user confirmation before apply

User-facing dry-run summary format:

- add: ``[index] <skill-name> | user: <reason_user_profile> | repo: <reason_target_repo>``
- remove: ``[index] <skill-name> | user: <reason_user_profile> | repo: <reason_target_repo>``
- mcp-add: ``[index] <mcp-name> | user: <reason_user_profile> | repo: <reason_target_repo>``
- mcp-remove: ``[index] <mcp-name> | user: <reason_user_profile> | repo: <reason_target_repo>``
- empty category: `no add recommendations: <brief reason>` / `no removal recommendations: <brief reason>` / `no mcp-add recommendations: <brief reason>` / `no mcp-remove recommendations: <brief reason>`

User profile JSON: $userProfilePath
Installed skills JSON: $installedSkillsPath
Source strategy JSON: $SourceStrategyPath
"@
    Set-ContentUtf8 $path $content
}

function Write-AuditOuterAiPromptFile([string]$path, [string]$reportRoot, [string]$briefPath, [string]$userProfilePath, [string]$repoScanPath, [string]$repoScansPath, [string]$installedSkillsPath, [string]$templatePath, [string]$Mode = "target-repo", [string]$Query = "", [string]$SourceStrategyPath = "") {
    $normalizedMode = if ([string]::IsNullOrWhiteSpace($Mode)) { "target-repo" } else { $Mode.ToLowerInvariant() }
    if ([string]::IsNullOrWhiteSpace($repoScanPath)) { $repoScanPath = "N/A" }
    if ([string]::IsNullOrWhiteSpace($repoScansPath)) { $repoScansPath = "N/A" }
    if ([string]::IsNullOrWhiteSpace($SourceStrategyPath)) { $SourceStrategyPath = "N/A" }
    $queryText = if ([string]::IsNullOrWhiteSpace($Query)) { "N/A" } else { $Query }
    $inputReadStep = if ($normalizedMode -eq "profile-only") {
        "1. 阅读 ai-brief.md、user-profile.json、installed-skills.json、source-strategy.json；repo-scan 输入为 N/A 时代表本轮不绑定目标仓。"
    }
    else {
        "1. 阅读 ai-brief.md、user-profile.json、installed-skills.json，并按存在文件读取 repo-scan.json / repo-scans.json，同时读取 source-strategy.json。"
    }
    $basisCheckStep = if ($normalizedMode -eq "profile-only") {
        "   - recommendations.json 与模板字段同构，``recommendation_mode = profile-only``，``decision_basis.user_profile_used`` / ``decision_basis.source_strategy_used`` 为 ``true``，``decision_basis.target_scan_used`` 为 ``false``，且 ``decision_basis.summary`` 非空"
    }
    else {
        "   - recommendations.json 与模板字段同构，``decision_basis`` 三个布尔字段都为 ``true``，且 ``decision_basis.summary`` 非空"
    }
    $modeBlocking = if ($normalizedMode -eq "profile-only") {
        '- 本轮是 profile-only；不得编造目标仓事实，``reason_target_repo`` 必须解释当前已安装技能 / profile-only 场景依据'
    }
    else {
        "- 若 ``repo-scan.json`` / ``repo-scans.json`` 路径显示为 ``N/A``，表示该输入未提供，不可臆造其内容"
    }
    $content = @"
$(Get-AuditOuterAiPromptContent)

---

## Current Audit Run Files

- 审查包目录：$reportRoot
- Prompt-Contract-Version: $(Get-AuditPromptContractVersion)
- 模式：$normalizedMode
- 发现查询：$queryText
- 任务说明：$briefPath
- 用户画像：$userProfilePath
- 单目标扫描：$repoScanPath
- 多目标扫描：$repoScansPath
- 已安装技能与 MCP：$installedSkillsPath
- 来源策略：$SourceStrategyPath
- 推荐模板：$templatePath

## Required Execution Sequence

$inputReadStep
2. 按 recommendations.template.json schema v2 写出 recommendations.json
3. 先做自检（全部通过后再 dry-run）：
   - recommendations.json 可解析为 JSON，且 ``schema_version = 2``
$basisCheckStep
   - 不保留模板占位符 ``<...>`` 或未替换的示例值
   - 每条技能/MCP 新增或卸载建议都包含 ``reason_user_profile`` + ``reason_target_repo`` + 至少 1 个真实 ``sources``
   - 技能新增建议的 ``install.mode`` 只能是 ``manual`` 或 ``vendor``，``confidence`` 只能是 ``low`` / ``medium`` / ``high``
   - MCP 新增建议必须包含合法 ``server``（``transport``=``stdio``/``sse``/``http``；``stdio`` 要有 ``command``，``sse/http`` 要有 ``url``），且 ``name`` 必须等于 ``server.name``
   - 不得保留重复的技能新增/卸载建议或重复的 MCP 新增/卸载建议
4. 执行 dry-run：
   .\skills.ps1 审查目标 应用 --recommendations "$([System.IO.Path]::Combine($reportRoot, 'recommendations.json'))" --dry-run-ack "我知道未落盘"
5. 根据 dry-run 结果，向用户列出“技能新增/卸载建议 + MCP 新增/卸载建议”及序号
6. 等待用户确认后，再执行：
   .\skills.ps1 审查目标 应用 --recommendations "$([System.IO.Path]::Combine($reportRoot, 'recommendations.json'))" --apply --yes

## Output Contract

- ``recommendations.json`` 必须与模板 schema 一致
- 技能与 MCP 的新增/卸载建议都必须保留双依据和来源，且每项理由要简短可读
- 若任一建议缺少 ``reason_user_profile`` 或 ``reason_target_repo``，视为未完成，不得进入下一步
- 若证据不足，允许不推荐；不得“猜测式”新增/卸载
- 目标仓模式下，新增/卸载技能或 MCP 的判断必须同时参考用户画像、目标仓事实、已安装技能/MCP 快照、来源策略
- ``overlap_findings`` 仅用于报告重叠，``do_not_install`` 用于记录“已研究但当前不应安装”的技能或 MCP
- ``sources`` 只能填写本轮真实查看过的来源；不得伪造仓库事实或来源结论
- MCP 新增建议里 ``name`` 与 ``server.name`` 必须一致；任一类别不得出现重复建议
- 如果你继续执行 dry-run，请在总结里按 dry-run 原序号列出“技能新增/卸载建议 + MCP 新增/卸载建议”
- 每条建议必须同时展示两条简短理由（用户需求 + 目标仓/场景）
- 某一类为空时，必须显式写“无该类建议”并给 1 句简短原因
- 未经用户明确确认，不得执行 --apply --yes

## Blocking Conditions

- 任一必需输入文件缺失、为空或不可读时，立即停止并汇报阻断项
$modeBlocking
- 若自检失败、仍有 ``<...>`` 占位符、或来源并非本轮真实查看结果，必须先修正再继续

## User Summary Format

- 新增建议：``[序号] <skill-name> | 用户需求：<reason_user_profile> | 目标仓/场景：<reason_target_repo>``
- 卸载建议：``[序号] <skill-name> | 用户需求：<reason_user_profile> | 目标仓/场景：<reason_target_repo>``
- MCP 新增建议：``[序号] <mcp-name> | 用户需求：<reason_user_profile> | 目标仓/场景：<reason_target_repo>``
- MCP 卸载建议：``[序号] <mcp-name> | 用户需求：<reason_user_profile> | 目标仓/场景：<reason_target_repo>``
- 空列表：``无新增建议：<简短原因>`` / ``无卸载建议：<简短原因>`` / ``无 MCP 新增建议：<简短原因>`` / ``无 MCP 卸载建议：<简短原因>``
"@
    Set-ContentUtf8 $path $content
}


