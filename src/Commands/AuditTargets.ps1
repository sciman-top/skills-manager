function Get-AuditTargetsConfigPath {
    return (Join-Path $script:Root "audit-targets.json")
}

function Get-AuditStructuredProfileDefaultPath {
    return (Join-Path $script:Root "reports\skill-audit\user-profile.structured.json")
}

function Get-AuditUserProfileSnapshotPath {
    return (Join-Path $script:Root "reports\skill-audit\user-profile.json")
}

function Get-AuditUserProfileSummarySnapshotPath {
    return (Join-Path $script:Root "reports\skill-audit\user-profile.json.summary")
}

function Get-AuditOuterAiPromptOverridePath {
    return (Join-Path $script:Root "overrides\audit-outer-ai-prompt.md")
}

function Get-DefaultAuditOuterAiPrompt {
    return @"
# Audit Recommendations Workflow

目标：基于一个当前 run 的 ``snapshot.json`` 完成 ``recommendations.json``，再执行预检与 dry-run；未经明确确认不得 apply。

1. 只读 ``reports/skill-audit/<run-id>/snapshot.json``。它聚合用户画像、已安装技能/MCP、目标仓扫描、来源策略、决策关键词与 prompt contract；不得修改。
2. 只编辑同目录 ``recommendations.json``：保持 schema v2，删除全部 ``<...>`` 示例占位符；每条新增/卸载建议必须有双理由、真实来源、匹配的 ``source_observations`` 与符合 snapshot policy 的 ``keyword_trace``。
3. 不得把 external/system/plugin skills 当作可自动卸载项；MCP payload 不得包含明文凭据。证据不足时保留空类别或 ``do_not_install``，不要强行推荐。
4. 执行：
   ``.\skills.ps1 审查目标 预检 --recommendations "reports\skill-audit\<run-id>\recommendations.json"``
5. 预检通过后执行：
   ``.\skills.ps1 审查目标 校验预演 --recommendations "reports\skill-audit\<run-id>\recommendations.json" --dry-run-ack "我知道未落盘"``
6. 从 ``receipt.json`` 汇报四类结果、``persisted=false`` 与 truth boundary；任一失败即停止。只有用户明确授权后才可执行 ``--apply --yes``。
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

function Write-AuditUserProfileSnapshot($cfg) {
    $profile = Get-AuditUserProfileOutput $cfg
    Write-AuditJsonFile (Get-AuditUserProfileSnapshotPath) $profile
    Set-ContentUtf8 (Get-AuditUserProfileSummarySnapshotPath) ([string]$profile.summary)
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
            Write-AuditUserProfileSnapshot $cfg
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
    Write-AuditUserProfileSnapshot $cfg
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
    return "audit-prompt-v20260815.1"
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

function Test-AuditIgnoredRecursivePath([string]$resolvedPath, [string]$candidatePath) {
    $relativePath = Get-AuditRepositoryRelativePath $resolvedPath $candidatePath
    $segments = @($relativePath -split '[\\/]')
    foreach ($segment in $segments) {
        if ($segment -in @('.git', '.runtime', '.worktrees', 'node_modules')) { return $true }
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

function Add-AuditDesignDocumentFacts([string]$resolvedPath, [System.Collections.Generic.List[string]]$languages, [System.Collections.Generic.List[string]]$frameworks, [System.Collections.Generic.List[string]]$packageManagers, [System.Collections.Generic.List[string]]$buildCommands, [System.Collections.Generic.List[string]]$testCommands, [System.Collections.Generic.List[string]]$capabilities, [System.Collections.Generic.List[string]]$notableFiles, [System.Collections.Generic.List[string]]$risks) {
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
    $pairs = @()
    $repoRoot = [string](Get-Location).Path
    foreach ($path in @($paths)) {
        $fullPath = Join-Path $repoRoot ([string]$path)
        $indexState = @(& git -c core.quotepath=false ls-files --stage -- $path 2>$null)
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
    $exists = Test-Path -LiteralPath $resolvedPath -PathType Container
    $risks = New-Object System.Collections.Generic.List[string]
    $languages = New-Object System.Collections.Generic.List[string]
    $packageManagers = New-Object System.Collections.Generic.List[string]
    $frameworks = New-Object System.Collections.Generic.List[string]
    $buildCommands = New-Object System.Collections.Generic.List[string]
    $testCommands = New-Object System.Collections.Generic.List[string]
    $capabilities = New-Object System.Collections.Generic.List[string]
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
        Add-AuditDesignDocumentFacts $resolvedPath $languages $frameworks $packageManagers $buildCommands $testCommands $capabilities $notableFiles $risks
        Add-AuditCiWorkflowFacts $resolvedPath $buildCommands $testCommands $notableFiles
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
            agent_rule_files = @($agentRuleFiles)
            notable_files = @($notableFiles)
        }
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

function Get-AuditUserProfileKeywords($cfg) {
    if ($null -eq $cfg -or $cfg.PSObject.Properties.Match("user_profile").Count -eq 0 -or $null -eq $cfg.user_profile) {
        return @()
    }
    $profile = $cfg.user_profile
    $sets = New-Object System.Collections.Generic.List[object]
    $sets.Add((Get-AuditKeywordsFromText ([string]$profile.raw_text) 80)) | Out-Null
    $sets.Add((Get-AuditKeywordsFromText ([string]$profile.summary) 80)) | Out-Null
    if (Test-AuditObjectLike $profile.structured) {
        foreach ($field in @("primary_work_types", "preferred_agents", "tech_stack", "common_tasks", "constraints", "avoidances", "decision_preferences")) {
            $fieldValue = $null
            if (Get-AuditObjectFieldValue $profile.structured $field ([ref]$fieldValue)) {
                $sets.Add((Convert-AuditStringArray $fieldValue)) | Out-Null
            }
        }
    }
    return (Merge-AuditKeywordSets ($sets.ToArray()) 200)
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

function Get-AuditMissingPreferredAgents($cfg, $installedSkills) {
    if ($null -eq $cfg -or $cfg.PSObject.Properties.Match("user_profile").Count -eq 0 -or $null -eq $cfg.user_profile) { return @() }
    if (-not (Test-AuditObjectLike $cfg.user_profile.structured)) { return @() }
    $preferred = @()
    $raw = $null
    if (Get-AuditObjectFieldValue $cfg.user_profile.structured "preferred_agents" ([ref]$raw)) {
        $preferred = @(Convert-AuditStringArray $raw)
    }
    if ($preferred.Count -eq 0) { return @() }
    $installedTokens = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($installedSkills)) {
        foreach ($token in @([string]$item.name, [string]$item.to, [string]$item.from, [string]$item.declared_name)) {
            if ([string]::IsNullOrWhiteSpace($token)) { continue }
            $installedTokens.Add($token.ToLowerInvariant()) | Out-Null
        }
    }
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($pref in @($preferred)) {
        $needle = ([string]$pref).ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($needle)) { continue }
        $matched = $false
        foreach ($token in @($installedTokens)) {
            if ($token.Contains($needle) -or $needle.Contains($token)) {
                $matched = $true
                break
            }
        }
        if (-not $matched) {
            $missing.Add([string]$pref) | Out-Null
        }
    }
    return @($missing)
}

function New-AuditDecisionInsights($cfg, $scans, $installedSkills, $installedMcpServers, [string]$Mode = "target-repo") {
    $normalizedMode = if ([string]::IsNullOrWhiteSpace($Mode)) { "target-repo" } else { $Mode.ToLowerInvariant() }
    $userKeywords = @(Get-AuditUserProfileKeywords $cfg)
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
    $repoKeywords = @()
    if (@($repoKeywordSets).Count -gt 0) {
        $repoKeywords = @(Merge-AuditKeywordSets @($repoKeywordSets | ForEach-Object { $_.keywords }) 220)
    }
    $installedKeywords = @(Get-AuditInstalledStateKeywords $installedSkills $installedMcpServers)
    $profileOnlyContext = @(Merge-AuditKeywordSets @($userKeywords, $installedKeywords) 180)
    return [pscustomobject]([ordered]@{
            schema_version = 1
            generated_at = (Get-Date).ToString("o")
            mode = $normalizedMode
            summary = [ordered]@{
                user_keyword_count = @($userKeywords).Count
                repo_keyword_count = @($repoKeywords).Count
                installed_state_keyword_count = @($installedKeywords).Count
                installed_skill_count = @($installedSkills).Count
                installed_mcp_server_count = @($installedMcpServers).Count
            }
            keywords = [ordered]@{
                user_profile = @($userKeywords)
                target_repo = @($repoKeywords)
                installed_state = @($installedKeywords)
                profile_only_context = @($profileOnlyContext)
            }
            targets = @($repoKeywordSets)
            explicit_preferences = [ordered]@{
                missing_preferred_agents = @(Get-AuditMissingPreferredAgents $cfg $installedSkills)
            }
            decision_checklist = @(
                "Each add/remove recommendation should keep keyword_trace.user_profile with keywords from decision-insights.keywords.user_profile.",
                "In target-repo mode, keyword_trace.target_repo_or_context should align with decision-insights.keywords.target_repo.",
                "In profile-only mode, keyword_trace.target_repo_or_context should align with decision-insights.keywords.profile_only_context.",
                "keyword_trace.installed_state should align with decision-insights.keywords.installed_state."
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
    Need ($null -ne $snapshot -and [int]$snapshot.schema_version -eq 1) ("snapshot.json schema_version 无效：{0}" -f $path)
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

