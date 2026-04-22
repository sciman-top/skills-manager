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
# Outer AI Audit Prompt

你正在代理执行 skills-manager 的技能审查流程；可能是目标仓审查，也可能是 profile-only 的新技能发现。

## 任务目标

1. 阅读本次审查包中的 ai-brief.md。
2. 阅读 user-profile.json、installed-skills.json、source-strategy.json；若本轮绑定目标仓，再阅读 repo-scan.json / repo-scans.json。
3. 严格按 recommendations.template.json 的 schema v2 产出完整 recommendations.json。
4. 建议结果优先覆盖“新增/卸载技能建议 + 新增/卸载 MCP 建议”，并确保每项都包含：
   - ``reason_user_profile``（简短，1 句话）
   - ``reason_target_repo``（简短，1 句话）
   - ``sources``（可追溯来源链接）
5. 对研究过但当前不应安装的技能或 MCP，写入 ``do_not_install``；重叠信息仅写入 ``overlap_findings``，不要据此自动卸载。
6. 在 recommendations.json 自检通过后再执行 dry-run。
7. 读取 dry-run 结果并向用户汇总技能与 MCP 的可新增/可卸载项及其原始序号。
8. 若任一建议类别为空（技能新增/技能卸载/MCP 新增/MCP 卸载），必须明确写出“无该类建议”并给 1 句简短原因。
9. 在没有用户明确确认前，不执行真正的安装或卸载（含 MCP）。

## 强制阶段门禁（不可跳步）

阶段 1：读取输入
- 必须先读 ai-brief.md + user-profile.json + installed-skills.json。
- 在 repo-scan.json / repo-scans.json 中按实际存在文件读取；若路径写成 ``N/A``，表示该输入未提供，不得臆测缺失内容。
- profile-only 模式不绑定目标仓，必须把 ``reason_target_repo`` 解释为“当前已安装技能 / profile-only 场景”依据，而不是仓库事实。
- 任一必需本地文件缺失、为空或无法读取时，立即停止，并向用户报告阻断项；不要跳过后继续 dry-run。

阶段 2：写 recommendations.json
- 仅输出机器可读 JSON，不夹带解释性正文。
- 不要改变 recommendations.template.json 的 schema 与字段命名。
- 模板中的 ``<...>`` 占位符必须全部替换或删除对应示例项，不得原样保留。
- 目标仓审查模式：``decision_basis.user_profile_used``、``decision_basis.target_scan_used``、``decision_basis.source_strategy_used`` 必须保持布尔值 ``true``，且 ``decision_basis.summary`` 不能为空。
- profile-only 模式：``recommendation_mode`` 必须为 ``profile-only``，``decision_basis.user_profile_used`` 与 ``decision_basis.source_strategy_used`` 必须为 ``true``，``decision_basis.target_scan_used`` 必须为 ``false``。
- 技能新增建议的 ``install.mode`` 只能是 ``manual`` 或 ``vendor``，``confidence`` 只能是 ``low`` / ``medium`` / ``high``。
- MCP 新增建议必须包含 ``server.name`` 与合法 ``transport``（``stdio``/``sse``/``http``）；``stdio`` 必须有 ``command``，``sse/http`` 必须有 ``url``。
- 任一建议缺少 ``reason_user_profile`` 或 ``reason_target_repo``，视为未完成。
- 证据不足时，宁可不推荐；不要“猜测式”新增或卸载。

阶段 3：执行前自检
- recommendations.json 必须可解析为 JSON，且 ``schema_version`` 必须是 ``2``。
- 每条技能/MCP 新增或卸载建议都必须包含双理由与至少 1 个真实 ``sources``。
- ``sources`` 只能填写你在本轮真实查看过的来源；不要引用未打开、未读取或不可访问的来源。
- 自检任一项失败，都必须先停下并汇报问题，不得进入 dry-run。

阶段 4：执行 dry-run
- 顺序必须是：先写 recommendations.json -> 再自检 -> 再 dry-run -> 再输出带理由的序号清单。
- dry-run 结果中的序号必须原样保留，不得重排或改号。
- 向用户汇报时，每条建议都要保留原始序号，并同时展示两条简短理由。

阶段 5：等待确认后 apply
- 真正执行状态变更前，必须先经过 dry-run。
- 未收到用户明确确认，不得执行 --apply --yes。
- 如果用户只确认部分序号，必须沿用 dry-run 原序号做选择，不得自行映射或重排。

## 质量与来源要求

- 目标仓审查必须同时基于“用户基本需求”和“目标仓事实”做判断；profile-only 新技能发现必须同时基于“用户基本需求”“已安装技能清单”和“来源策略”做判断。
- 目标仓审查在判断新增/卸载技能或 MCP 时，也必须参考 ``installed-skills.json`` 中的已安装技能/MCP 快照；不得把 live state 臆造成审查输入。
- 优先参考官方文档、skills.sh、find-skills、GitHub 高质量项目、GitHub Trending。
- 每条建议都要能回答两个问题：为什么适合用户长期工作流、为什么符合目标仓事实或 profile-only 场景。
- 若来源相互冲突，选择更高可信来源并在 ``sources`` 中保留依据。
- ``overlap_findings`` 仅作报告，不可直接视为卸载建议；确需卸载时，必须单独给出双理由。
- ``do_not_install`` 用于记录“已研究但当前不建议安装”的技能或 MCP，避免重复研究。
- 对同一技能安装项、同一技能卸载定位、同一 MCP 名称，不得产出重复建议。
- 不得伪造仓库事实、来源链接、来源结论，或把模板示例伪装成真实结论。

## 交付方式

- 如果用户让你“代理执行审查流程”，你应先完成 ``recommendations.json``。
- 然后执行 dry-run。
- 最后按 dry-run 结果向用户列出技能与 MCP 的新增/卸载建议清单（逐项含原始序号 + 双理由），等待用户确认要执行的序号。
- 若存在阻断项或证据不足，先汇报阻断项或“无该类建议”的原因，再等待用户决策。
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
    if (Get-AuditObjectFieldValue $imported "last_structured_at" ([ref]$importedStructuredAt) -and -not [string]::IsNullOrWhiteSpace([string]$importedStructuredAt)) {
        $cfg.user_profile.last_structured_at = [string]$importedStructuredAt
    }
    else {
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
    if ([string]::IsNullOrWhiteSpace([string]$cfg.user_profile.summary)) {
        Write-Host "提示：用户结构化 summary 为空，建议先完善结构化需求后再生成审查包。" -ForegroundColor Yellow
    }
}

function Get-AuditUserProfileOutput($cfg) {
    return [pscustomobject]@{
        schema_version = 1
        raw_text = [string]$cfg.user_profile.raw_text
        summary = [string]$cfg.user_profile.summary
        structured = $cfg.user_profile.structured
        last_structured_at = [string]$cfg.user_profile.last_structured_at
        structured_by = [string]$cfg.user_profile.structured_by
    }
}

function Get-AuditRunId {
    return (Get-Date -Format "yyyyMMdd-HHmmss-fff")
}

function Get-AuditPromptContractVersion {
    return "audit-prompt-v20260422.1"
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
    if ($staleCandidates.Count -gt 0) { return [string]$staleCandidates[0] }
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
        throw ("{0} 使用占位符但未找到可用 run-id。{1}" -f $FlagName, (Get-AuditRunIdHintText))
    }
    throw ("{0} 包含未替换占位符：{1}`n{2}" -f $FlagName, $runId, (Get-AuditRunIdHintText))
}

function Resolve-AuditPathRunIdPlaceholder([string]$path, [string]$FlagName = "--recommendations", [string[]]$RequiredFiles = @()) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $path }
    if (-not (Test-AuditPlaceholderToken $path)) { return $path }
    if (-not [regex]::IsMatch($path, "<\s*run[-_]?id\s*>", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        throw ("{0} 路径包含未替换占位符：{1}`n{2}" -f $FlagName, $path, (Get-AuditRunIdHintText))
    }

    $resolvedRunId = Get-AuditLatestRunId -RequiredFiles $RequiredFiles
    if ([string]::IsNullOrWhiteSpace($resolvedRunId)) {
        throw ("{0} 路径使用 <run-id> 占位符但未找到可用 run。{1}" -f $FlagName, (Get-AuditRunIdHintText))
    }
    $resolvedPath = [regex]::Replace($path, "<\s*run[-_]?id\s*>", [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $resolvedRunId }, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (Test-AuditPlaceholderToken $resolvedPath) {
        throw ("{0} 路径仍包含未替换占位符：{1}`n{2}" -f $FlagName, $resolvedPath, (Get-AuditRunIdHintText))
    }
    return $resolvedPath
}

function Get-AuditRunIdHintText {
    $ids = @(Get-AuditKnownRunIds)
    if ($ids.Count -eq 0) {
        return "可用 run-id：无（请先运行：.\skills.ps1 审查目标 扫描）"
    }
    return ("可用 run-id：{0}" -f ($ids -join ", "))
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
        }

        if (Test-AuditFile $resolvedPath "pnpm-lock.yaml") { Add-AuditUniqueValue $packageManagers "pnpm"; Add-AuditUniqueValue $notableFiles "pnpm-lock.yaml" }
        if (Test-AuditFile $resolvedPath "yarn.lock") { Add-AuditUniqueValue $packageManagers "yarn"; Add-AuditUniqueValue $notableFiles "yarn.lock" }
        if (Test-AuditFile $resolvedPath "package-lock.json") { Add-AuditUniqueValue $packageManagers "npm"; Add-AuditUniqueValue $notableFiles "package-lock.json" }
        if (Test-AuditFile $resolvedPath "pyproject.toml") { Add-AuditUniqueValue $languages "python"; Add-AuditUniqueValue $notableFiles "pyproject.toml" }
        if (Test-AuditFile $resolvedPath "requirements.txt") { Add-AuditUniqueValue $languages "python"; Add-AuditUniqueValue $notableFiles "requirements.txt" }
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
        $slnFiles = @(Get-ChildItem -LiteralPath $resolvedPath -Filter "*.sln" -File -ErrorAction SilentlyContinue)
        $csprojFiles = @(Get-ChildItem -LiteralPath $resolvedPath -Filter "*.csproj" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 10)
        if ($slnFiles.Count -gt 0 -or $csprojFiles.Count -gt 0) { Add-AuditUniqueValue $languages "dotnet" }
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


