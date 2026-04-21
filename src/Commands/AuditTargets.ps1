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
4. 建议结果优先覆盖“新增建议”与“卸载建议”，并确保每项都包含：
   - ``reason_user_profile``（简短，1 句话）
   - ``reason_target_repo``（简短，1 句话）
   - ``sources``（可追溯来源链接）
5. 对研究过但当前不应安装的技能，写入 ``do_not_install``；重叠信息仅写入 ``overlap_findings``，不要据此自动卸载。
6. 在 recommendations.json 自检通过后再执行 dry-run。
7. 读取 dry-run 结果并向用户汇总可安装/可卸载项及其原始序号。
8. 若“新增建议”或“卸载建议”为空，必须明确写出“无该类建议”并给 1 句简短原因。
9. 在没有用户明确确认前，不执行真正的安装或卸载。

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
- 新增建议的 ``install.mode`` 只能是 ``manual`` 或 ``vendor``，``confidence`` 只能是 ``low`` / ``medium`` / ``high``。
- 任一建议缺少 ``reason_user_profile`` 或 ``reason_target_repo``，视为未完成。
- 证据不足时，宁可不推荐；不要“猜测式”新增或卸载。

阶段 3：执行前自检
- recommendations.json 必须可解析为 JSON，且 ``schema_version`` 必须是 ``2``。
- 每条新增/卸载建议都必须包含双理由与至少 1 个真实 ``sources``。
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
- 优先参考官方文档、skills.sh、find-skills、GitHub 高质量项目、GitHub Trending。
- 每条建议都要能回答两个问题：为什么适合用户长期工作流、为什么符合目标仓事实或 profile-only 场景。
- 若来源相互冲突，选择更高可信来源并在 ``sources`` 中保留依据。
- ``overlap_findings`` 仅作报告，不可直接视为卸载建议；确需卸载时，必须单独给出双理由。
- ``do_not_install`` 用于记录“已研究但当前不建议安装”的技能，避免重复研究。
- 不得伪造仓库事实、来源链接、来源结论，或把模板示例伪装成真实结论。

## 交付方式

- 如果用户让你“代理执行审查流程”，你应先完成 ``recommendations.json``。
- 然后执行 dry-run。
- 最后按 dry-run 结果向用户列出新增/卸载建议清单（逐项含原始序号 + 双理由），等待用户确认要执行的序号。
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

function Parse-AuditTargetsArgs([string[]]$tokens) {
    $result = [ordered]@{
        action = "list"
        name = $null
        path = $null
        profile = $null
        target = $null
        out = $null
        query = $null
        recommendations = $null
        dry_run_ack = $null
        add_selection = $null
        remove_selection = $null
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
            "--profile" {
                Need ($i + 1 -lt $items.Count) "--profile 缺少值"
                $result.profile = [string]$items[++$i]
                continue
            }
            "--out" {
                Need ($i + 1 -lt $items.Count) "--out 缺少值"
                $result.out = [string]$items[++$i]
                continue
            }
            "--query" {
                Need ($i + 1 -lt $items.Count) "--query 缺少值"
                $result.query = [string]$items[++$i]
                continue
            }
            "--recommendations" {
                Need ($i + 1 -lt $items.Count) "--recommendations 缺少值"
                $result.recommendations = [string]$items[++$i]
                continue
            }
            "--dry-run-ack" {
                Need ($i + 1 -lt $items.Count) "--dry-run-ack 缺少值"
                $result.dry_run_ack = [string]$items[++$i]
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

function New-AuditSourceStrategy([string]$Mode = "target-repo", [string]$Query = "") {
    $normalizedMode = if ([string]::IsNullOrWhiteSpace($Mode)) { "target-repo" } else { $Mode.ToLowerInvariant() }
    Need ($normalizedMode -eq "target-repo" -or $normalizedMode -eq "profile-only") ("未知审查来源模式：{0}" -f $Mode)
    return [pscustomobject]([ordered]@{
        schema_version = 1
        mode = $normalizedMode
        query = [string]$Query
        sources = @(
            [ordered]@{
                id = "official-docs"
                name = "Official documentation"
                use_for = "Verify current APIs, platform rules, support status, and recommended implementation patterns."
            },
            [ordered]@{
                id = "skills-sh"
                name = "skills.sh"
                use_for = "Discover skill-packaged implementations and compare skill metadata quality."
            },
            [ordered]@{
                id = "github-trending-monthly"
                name = "GitHub Trending monthly"
                url = "https://github.com/trending?since=monthly"
                use_for = "Find active, recently relevant community projects; never treat popularity alone as enough evidence."
            },
            [ordered]@{
                id = "strong-community-projects"
                name = "High-quality community projects"
                use_for = "Check maintenance activity, examples, issues, releases, and adoption fit."
            },
            [ordered]@{
                id = "best-practices"
                name = "Best-practice guides"
                use_for = "Compare proposed skills against mature workflow and operational guidance."
            },
            [ordered]@{
                id = "find-skills"
                name = "Installed find-skills workflow"
                use_for = "Use the local skill discovery workflow as an input source when available."
            }
        )
        scoring = [ordered]@{
            authority = "Prefer first-party documentation and maintained source repositories."
            fit = "Match the user's structured profile and, in target-repo mode, concrete repo scan facts."
            duplication_risk = "Penalize recommendations that duplicate installed skills without a clear incremental benefit."
            maintenance = "Prefer projects with recent activity, clear license, and usable documentation."
            operational_cost = "Prefer skills that are easy to install, verify, and roll back."
        }
        required_evidence = @(
            "Every add/remove recommendation must cite sources inspected in this run.",
            "Do not fabricate repository facts, source links, or source conclusions.",
            "For profile-only mode, explain reason_target_repo as installed-skill inventory / profile-only context, not as a target repository claim."
        )
    })
}

function Get-AuditRunId {
    return (Get-Date -Format "yyyyMMdd-HHmmss-fff")
}

function Get-AuditReportRoot([string]$runId) {
    return (Join-Path $script:Root (Join-Path "reports\skill-audit" $runId))
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

Use the generated user profile JSON, installed skills JSON, and source strategy JSON to decide:

- Which installed skills should be kept for the user's long-term workflow.
- Which installed skills should be proposed for removal because they no longer fit.
- Which missing skills are strongly justified without binding the decision to a target repository.

External research is intentionally performed by the outer AI agent. Search official documentation, strong community projects, best practices, https://skills.sh/, GitHub Trending, and the find-skills workflow.

Primary output file (must be valid JSON, no prose):

$templatePath

Scan inputs:
- Single-target scan JSON: N/A
- Multi-target scans JSON: N/A
- Source strategy JSON: $SourceStrategyPath

Rules:

- Profile-only mode has no target repo scan; do not fabricate repository facts.
- All decisions must be based on user-profile.json, installed-skills.json, source-strategy.json, and real external research.
- Use ``reason_target_repo`` to explain the current installed-skill inventory / profile-only context; do not claim target repository evidence.
- If any required local input is missing, unreadable, or empty, stop and report the blocker instead of guessing.
- Network research is authorized within this audit workflow, but installation still requires --apply --yes.
- Replace every template placeholder wrapped in `<...>` or delete the example entry entirely; do not leave placeholder values in the final file.
- Keep ``recommendation_mode`` as ``profile-only``.
- Keep ``decision_basis.user_profile_used`` and ``decision_basis.source_strategy_used`` as boolean ``true``; keep ``decision_basis.target_scan_used`` as boolean ``false``; provide a non-empty ``decision_basis.summary``.
- New installs require ``reason_user_profile``, ``reason_target_repo``, source links, confidence, repo, skill path, ref, and mode.
- Removal recommendations must include ``reason_user_profile``, ``reason_target_repo``, sources, and the exact installed ``vendor``/``from`` pair.
- `install.mode` must stay `manual` or `vendor`; `confidence` must stay `low`, `medium`, or `high`.
- Each add/remove recommendation must keep both reasons concise and user-readable.
- If either reason field is missing on any recommendation, treat the run as incomplete and stop before dry-run summary.
- Overlap findings are report-only; do not recommend automatic uninstall.
- Use `do_not_install` for researched options that should stay out of the repo right now.
- Prefer high-reputation sources and avoid weak duplicate skills.
- Cover the built-in default sources and record the actual sources you used.
- Keep recommendations machine-readable JSON matching the template.
- The template already includes placeholder example items. Replace placeholder values or delete the example entries you do not need; do not invent a different schema.
- Cite only sources you actually inspected during this run. Do not fabricate source links or source conclusions.
- If evidence is insufficient, leave the category empty and explain briefly instead of forcing low-quality recommendations.
- After dry-run, show numbered add/remove lists with one-line reasons per item (``reason_user_profile`` + ``reason_target_repo``).
- If a list is empty, explicitly output "no add recommendations" or "no removal recommendations" with a brief reason.
- Keep dry-run numbering stable; do not renumber or reorder indexes in the user-facing summary.

Pre-dry-run self-check:

- recommendations.json parses as JSON and keeps `schema_version = 2`.
- ``recommendation_mode`` is ``profile-only``.
- ``decision_basis.user_profile_used`` and ``decision_basis.source_strategy_used`` are ``true``.
- ``decision_basis.target_scan_used`` is ``false``.
- No remaining placeholder values wrapped in `<...>`.
- Each add/remove item has both reasons plus at least one real source.
- Stop before dry-run if any self-check item fails.

Execution order:

1) Read all local inputs
2) Write ``recommendations.json`` from ``recommendations.template.json``
3) Run the self-check and stop if any item fails
4) Execute dry-run
5) Summarize dry-run with original indexes and one-line dual-reason entries
6) Wait for explicit user confirmation before apply

User-facing dry-run summary format:

- add: `[index] <skill-name> | user: <reason_user_profile> | context: <reason_target_repo>`
- remove: `[index] <skill-name> | user: <reason_user_profile> | context: <reason_target_repo>`
- empty category: `no add recommendations: <brief reason>` / `no removal recommendations: <brief reason>`

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

Use the generated user profile JSON, repo scan JSON, and installed skills JSON to decide:

- Which installed skills should be kept for each target repository.
- Which installed skills should be proposed for removal.
- Which missing skills are strongly justified for these targets.

External research is intentionally performed by the outer AI agent. Search official documentation, strong community projects, best practices, https://skills.sh/, GitHub Trending, and the find-skills workflow.

Primary output file (must be valid JSON, no prose):

$templatePath

Scan inputs:
- Single-target scan JSON: $repoScanPath
- Multi-target scans JSON: $repoScansPath
- Source strategy JSON: $SourceStrategyPath

Rules:

- All decisions must be based on BOTH user-profile.json and target repo scan facts.
- Use source-strategy.json to cover the built-in source set and explain source tradeoffs.
- Treat any scan path shown as `N/A` as "not provided"; do not infer hidden content from it.
- If any required local input is missing, unreadable, or empty, stop and report the blocker instead of guessing.
- Network research is authorized within this audit workflow, but installation still requires --apply --yes.
- Replace every template placeholder wrapped in `<...>` or delete the example entry entirely; do not leave placeholder values in the final file.
- Keep `decision_basis.user_profile_used`, `decision_basis.target_scan_used`, and `decision_basis.source_strategy_used` as boolean `true`, and provide a non-empty `decision_basis.summary`.
- New installs require ``reason_user_profile``, ``reason_target_repo``, source links, confidence, repo, skill path, ref, and mode.
- Removal recommendations must include ``reason_user_profile``, ``reason_target_repo``, sources, and the exact installed ``vendor``/``from`` pair.
- `install.mode` must stay `manual` or `vendor`; `confidence` must stay `low`, `medium`, or `high`.
- Each add/remove recommendation must keep both reasons concise and user-readable.
- If either reason field is missing on any recommendation, treat the run as incomplete and stop before dry-run summary.
- Overlap findings are report-only; do not recommend automatic uninstall.
- Use `do_not_install` for researched options that should stay out of the repo right now.
- Prefer high-reputation sources and avoid weak duplicate skills.
- Cover the built-in default sources and record the actual sources you used.
- Keep recommendations machine-readable JSON matching the template.
- The template already includes placeholder example items. Replace placeholder values or delete the example entries you do not need; do not invent a different schema.
- Cite only sources you actually inspected during this run. Do not fabricate repository facts, source links, or source conclusions.
- If evidence is insufficient, leave the category empty and explain briefly instead of forcing low-quality recommendations.
- After dry-run, show numbered add/remove lists with one-line reasons per item (``reason_user_profile`` + ``reason_target_repo``).
- If a list is empty, explicitly output "no add recommendations" or "no removal recommendations" with a brief reason.
- Keep dry-run numbering stable; do not renumber or reorder indexes in the user-facing summary.

Pre-dry-run self-check:

- recommendations.json parses as JSON and keeps `schema_version = 2`.
- `decision_basis` keeps all required boolean flags at `true`.
- No remaining placeholder values wrapped in `<...>`.
- Each add/remove item has both reasons plus at least one real source.
- Stop before dry-run if any self-check item fails.

Execution order:

1) Read all local inputs
2) Write ``recommendations.json`` from ``recommendations.template.json``
3) Run the self-check and stop if any item fails
4) Execute dry-run
5) Summarize dry-run with original indexes and one-line dual-reason entries
6) Wait for explicit user confirmation before apply

User-facing dry-run summary format:

- add: `[index] <skill-name> | user: <reason_user_profile> | repo: <reason_target_repo>`
- remove: `[index] <skill-name> | user: <reason_user_profile> | repo: <reason_target_repo>`
- empty category: `no add recommendations: <brief reason>` / `no removal recommendations: <brief reason>`

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
        "1. 阅读 ai-brief.md，并按存在文件读取 repo-scan.json / repo-scans.json，同时读取 source-strategy.json。"
    }
    $basisCheckStep = if ($normalizedMode -eq "profile-only") {
        "   - recommendations.json 与模板字段同构，``recommendation_mode = profile-only``，``decision_basis.user_profile_used`` / ``decision_basis.source_strategy_used`` 为 ``true``，``decision_basis.target_scan_used`` 为 ``false``"
    }
    else {
        "   - recommendations.json 与模板字段同构，``decision_basis`` 三个布尔字段都为 ``true``"
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
- 模式：$normalizedMode
- 发现查询：$queryText
- 任务说明：$briefPath
- 用户画像：$userProfilePath
- 单目标扫描：$repoScanPath
- 多目标扫描：$repoScansPath
- 已安装技能：$installedSkillsPath
- 来源策略：$SourceStrategyPath
- 推荐模板：$templatePath

## Required Execution Sequence

$inputReadStep
2. 按 recommendations.template.json schema v2 写出 recommendations.json
3. 先做自检（全部通过后再 dry-run）：
   - recommendations.json 可解析为 JSON，且 ``schema_version = 2``
$basisCheckStep
   - 不保留模板占位符 ``<...>`` 或未替换的示例值
   - 每条新增/卸载建议都包含 ``reason_user_profile`` + ``reason_target_repo`` + 至少 1 个真实 ``sources``
   - 新增建议的 ``install.mode`` 只能是 ``manual`` 或 ``vendor``，``confidence`` 只能是 ``low`` / ``medium`` / ``high``
4. 执行 dry-run：
   .\skills.ps1 审查目标 应用 --recommendations "$([System.IO.Path]::Combine($reportRoot, 'recommendations.json'))" --dry-run-ack "我知道未落盘"
5. 根据 dry-run 结果，向用户列出“新增建议 / 卸载建议”及序号
6. 等待用户确认后，再执行：
   .\skills.ps1 审查目标 应用 --recommendations "$([System.IO.Path]::Combine($reportRoot, 'recommendations.json'))" --apply --yes

## Output Contract

- ``recommendations.json`` 必须与模板 schema 一致
- 新增与卸载建议都必须保留双依据和来源，且每项理由要简短可读
- 若任一建议缺少 ``reason_user_profile`` 或 ``reason_target_repo``，视为未完成，不得进入下一步
- 若证据不足，允许不推荐；不得“猜测式”新增/卸载
- ``overlap_findings`` 仅用于报告重叠，``do_not_install`` 用于记录“已研究但当前不应安装”的技能
- ``sources`` 只能填写本轮真实查看过的来源；不得伪造仓库事实或来源结论
- 如果你继续执行 dry-run，请在总结里按 dry-run 原序号列出“新增建议 / 卸载建议”
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
- 空列表：``无新增建议：<简短原因>`` / ``无卸载建议：<简短原因>``
"@
    Set-ContentUtf8 $path $content
}

function Test-AuditJsonProperty($obj, [string]$name) {
    if ($null -eq $obj) { return $false }
    return ($obj.PSObject.Properties.Match($name).Count -gt 0)
}

function Assert-AuditBundleFileContent([string]$path, [string]$label) {
    $raw = Get-ContentUtf8 $path
    Need (-not [string]::IsNullOrWhiteSpace($raw)) ("审查包文件为空：{0} -> {1}" -f $label, $path)

    $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    if ($ext -eq ".md") { return }
    if ($ext -ne ".json") { return }

    try {
        $data = $raw | ConvertFrom-Json
    }
    catch {
        throw ("审查包 JSON 解析失败：{0} -> {1}；{2}" -f $label, $path, $_.Exception.Message)
    }
    Need ($null -ne $data) ("审查包 JSON 为空对象：{0} -> {1}" -f $label, $path)

    switch ($label) {
        "user-profile.json" {
            Need (Test-AuditJsonProperty $data "raw_text") ("user-profile 缺少 raw_text：{0}" -f $path)
            Need (-not [string]::IsNullOrWhiteSpace([string]$data.raw_text)) ("user-profile.raw_text 不能为空：{0}" -f $path)
            Need (Test-AuditJsonProperty $data "structured") ("user-profile 缺少 structured：{0}" -f $path)
        }
        "installed-skills.json" {
            Need (Test-AuditJsonProperty $data "skills") ("installed-skills 缺少 skills：{0}" -f $path)
            Need (Assert-IsArray $data.skills) ("installed-skills.skills 必须为数组：{0}" -f $path)
        }
        "source-strategy.json" {
            Need (Test-AuditJsonProperty $data "mode") ("source-strategy 缺少 mode：{0}" -f $path)
            Need (Test-AuditJsonProperty $data "sources") ("source-strategy 缺少 sources：{0}" -f $path)
            Need (Assert-IsArray $data.sources) ("source-strategy.sources 必须为数组：{0}" -f $path)
            Need (@($data.sources).Count -gt 0) ("source-strategy.sources 不能为空：{0}" -f $path)
        }
        "recommendations.template.json" {
            Need (Test-AuditJsonProperty $data "schema_version") ("recommendations.template 缺少 schema_version：{0}" -f $path)
            Need ([int]$data.schema_version -eq 2) ("recommendations.template schema_version 必须为 2：{0}" -f $path)
            Need (Test-AuditJsonProperty $data "decision_basis") ("recommendations.template 缺少 decision_basis：{0}" -f $path)
        }
        "repo-scan.json" {
            Need (Test-AuditJsonProperty $data "target") ("repo-scan 缺少 target：{0}" -f $path)
            Need (Test-AuditJsonProperty $data "detected") ("repo-scan 缺少 detected：{0}" -f $path)
        }
        "repo-scans.json" {
            Need (Test-AuditJsonProperty $data "scans") ("repo-scans 缺少 scans：{0}" -f $path)
            Need (Assert-IsArray $data.scans) ("repo-scans.scans 必须为数组：{0}" -f $path)
            Need (@($data.scans).Count -gt 0) ("repo-scans.scans 不能为空：{0}" -f $path)
        }
    }
}

function Assert-AuditBundleRequiredFiles([object[]]$files) {
    foreach ($file in @($files)) {
        Need ($null -ne $file) "审查包关键产物定义不能为空"
        $path = [string]$file.path
        $label = [string]$file.label
        if ([string]::IsNullOrWhiteSpace($label)) { $label = $path }
        Need (-not [string]::IsNullOrWhiteSpace($path)) ("审查包关键产物路径不能为空：{0}" -f $label)
        Need (Test-Path -LiteralPath $path -PathType Leaf) ("审查包缺少关键产物：{0} -> {1}" -f $label, $path)
        Assert-AuditBundleFileContent $path $label
    }
}

function New-AuditRecommendationsTemplate([string]$runId, [string]$targetName, [string]$Mode = "target-repo", [string]$Query = "") {
    $normalizedMode = if ([string]::IsNullOrWhiteSpace($Mode)) { "target-repo" } else { $Mode.ToLowerInvariant() }
    Need ($normalizedMode -eq "target-repo" -or $normalizedMode -eq "profile-only") ("未知 recommendations 模式：{0}" -f $Mode)
    $isProfileOnly = ($normalizedMode -eq "profile-only")
    $targetScanUsed = -not $isProfileOnly
    $templateNotes = if ($isProfileOnly) {
        @(
            "Replace placeholder values wrapped in <> before using this file.",
            "Delete example entries that are not needed, but keep the schema shape unchanged.",
            "This is profile-only skill discovery: reason_target_repo means installed-skill inventory / profile-only context, not target repository facts."
        )
    }
    else {
        @(
            "Replace placeholder values wrapped in <> before using this file.",
            "Delete example entries that are not needed, but keep the schema shape unchanged.",
            "All install/remove decisions must cite both user-profile and target-repo reasons."
        )
    }
    $basisSummary = if ($isProfileOnly) {
        "<why these recommendations reflect the user profile, installed-skill inventory, and source strategy without target repo facts>"
    }
    else {
        "<why these recommendations reflect both the user profile and the target repo facts>"
    }
    $targetReasonInstall = if ($isProfileOnly) { "<which installed-skill inventory or profile-only context justifies this skill>" } else { "<which detected target-repo facts justify this skill>" }
    $targetReasonRemoval = if ($isProfileOnly) { "<why the installed-skill inventory or profile-only context no longer justifies this skill>" } else { "<why the target repo no longer justifies this skill>" }
    $targetReasonDoNotInstall = if ($isProfileOnly) { "<why the profile-only context does not justify it>" } else { "<why the target repo does not justify it>" }
    return [pscustomobject]([ordered]@{
        schema_version = 2
        run_id = $runId
        target = $targetName
        recommendation_mode = $normalizedMode
        discovery_query = [string]$Query
        template_notes = @($templateNotes)
        decision_basis = [ordered]@{
            user_profile_used = $true
            target_scan_used = $targetScanUsed
            source_strategy_used = $true
            summary = $basisSummary
        }
        new_skills = @(
            [ordered]@{
                name = "<new-skill-name>"
                reason_user_profile = "<why the user's long-term workflow benefits from this skill>"
                reason_target_repo = $targetReasonInstall
                install = [ordered]@{
                    repo = "<owner/repo-or-local-path>"
                    skill = "<relative-skill-path-or-.>"
                    ref = "<branch-or-tag>"
                    mode = "manual"
                }
                confidence = "medium"
                sources = @("<source-url-1>")
                source_categories = @("official-docs", "skills.sh")
            }
        )
        overlap_findings = @(
            [ordered]@{
                name = "<existing-skill-or-skill-pair>"
                reason_user_profile = "<why overlap matters for the user's workflow>"
                reason_target_repo = $targetReasonInstall
                sources = @("<source-url-1>")
                note = "<report-only observation; no automatic uninstall>"
            }
        )
        removal_candidates = @(
            [ordered]@{
                name = "<installed-skill-name>"
                reason_user_profile = "<why the user profile no longer justifies this skill>"
                reason_target_repo = $targetReasonRemoval
                sources = @("<source-url-1>")
                source_categories = @("official-docs")
                installed = [ordered]@{
                    vendor = "<installed-vendor>"
                    from = "<installed-from>"
                }
            }
        )
        do_not_install = @(
            [ordered]@{
                name = "<skill-not-recommended>"
                reason_user_profile = "<why the user profile does not justify it>"
                reason_target_repo = $targetReasonDoNotInstall
                sources = @("<source-url-1>")
                note = "<why it should not be added now>"
            }
        )
    })
}

function Get-SkillMetadataFromFile([string]$skillFile) {
    $meta = [ordered]@{
        declared_name = ""
        description = ""
        trigger_summary = ""
    }
    if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) {
        return [pscustomobject]$meta
    }

    $lines = @(Get-Content -LiteralPath $skillFile -TotalCount 120 -ErrorAction SilentlyContinue)
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($meta.declared_name) -and $line -match "^\s*name:\s*(.+?)\s*$") {
            $meta.declared_name = $Matches[1].Trim().Trim("'`"")
        }
        if ([string]::IsNullOrWhiteSpace($meta.description) -and $line -match "^\s*description:\s*(.+?)\s*$") {
            $meta.description = $Matches[1].Trim().Trim("'`"")
        }
        if ([string]::IsNullOrWhiteSpace($meta.trigger_summary) -and $line -match "(?i)trigger|use when|when to use|使用场景") {
            $meta.trigger_summary = $line.Trim()
        }
    }
    return [pscustomobject]$meta
}

function Resolve-InstalledSkillLocalPath($cfg, $mapping) {
    if ($null -eq $mapping) { return "" }
    $vendor = [string]$mapping.vendor
    $from = [string]$mapping.from
    if ($vendor -eq "manual") {
        $imp = @($cfg.imports | Where-Object { $_.name -eq $from } | Select-Object -First 1)
        if ($imp.Count -eq 0) { return (Join-Path $script:ImportDir $from) }
        $skillPath = Normalize-SkillPath ([string]$imp[0].skill)
        if ([string]::IsNullOrWhiteSpace($skillPath) -or $skillPath -eq ".") {
            return (Join-Path $script:ImportDir $from)
        }
        return (Join-Path (Join-Path $script:ImportDir $from) $skillPath)
    }
    if ($vendor -eq "overrides") {
        return (Join-Path $script:OverridesDir $from)
    }
    return (Join-Path (VendorPath $vendor) $from)
}

function Get-InstalledSkillFacts($cfg = $null) {
    if ($null -eq $cfg) { $cfg = LoadCfg }
    $facts = @()
    foreach ($m in @($cfg.mappings)) {
        if ($null -eq $m) { continue }
        if (-not (Should-SyncMappingToAgent $m)) { continue }
        $vendor = [string]$m.vendor
        $from = [string]$m.from
        $to = [string]$m.to
        $localPath = Resolve-InstalledSkillLocalPath $cfg $m
        $skillFile = Join-Path $localPath "SKILL.md"
        $meta = Get-SkillMetadataFromFile $skillFile

        $repo = ""
        $ref = ""
        $skillPath = $from
        if ($vendor -eq "manual") {
            $imp = @($cfg.imports | Where-Object { $_.name -eq $from } | Select-Object -First 1)
            if ($imp.Count -gt 0) {
                $repo = [string]$imp[0].repo
                $ref = [string]$imp[0].ref
                $skillPath = [string]$imp[0].skill
            }
        }
        elseif ($vendor -ne "overrides") {
            $v = @($cfg.vendors | Where-Object { $_.name -eq $vendor } | Select-Object -First 1)
            if ($v.Count -gt 0) {
                $repo = [string]$v[0].repo
                $ref = [string]$v[0].ref
            }
        }

        $facts += [pscustomobject]([ordered]@{
            name = if ([string]::IsNullOrWhiteSpace($meta.declared_name)) { $to } else { $meta.declared_name }
            source_kind = $vendor
            vendor = $vendor
            from = $from
            to = $to
            repo = $repo
            ref = $ref
            skill_path = $skillPath
            declared_name = $meta.declared_name
            description = $meta.description
            trigger_summary = $meta.trigger_summary
            local_path = $localPath
        })
    }
    return @($facts)
}

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

function Write-AuditRecommendationSummary($plan) {
    Write-Host ""
    Write-Host "=== 审查建议摘要 ==="
    Write-Host ("决策依据: {0}" -f [string]$plan.decision_basis.summary)
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

function Invoke-AuditTargetsScan {
    param(
        [string]$Target,
        [string]$OutDir
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
        $installedSkills = @(Get-InstalledSkillFacts)
    }
    catch {
        throw ("生成 installed-skills.json 失败：{0}" -f $_.Exception.Message)
    }
    Write-AuditJsonFile $installedPath ([pscustomobject]@{ schema_version = 1; skills = @($installedSkills) })

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
        [string]$OutDir
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
    EnsureDir $reportRoot

    $userProfilePath = Join-Path $reportRoot "user-profile.json"
    Write-AuditJsonFile $userProfilePath (Get-AuditUserProfileOutput $cfg)

    $installedPath = Join-Path $reportRoot "installed-skills.json"
    $installedSkills = @()
    try {
        $installedSkills = @(Get-InstalledSkillFacts)
    }
    catch {
        throw ("生成 installed-skills.json 失败：{0}" -f $_.Exception.Message)
    }
    Write-AuditJsonFile $installedPath ([pscustomobject]@{ schema_version = 1; skills = @($installedSkills) })

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

function Invoke-AuditRecommendationsApply {
    param(
        [string]$RecommendationsPath,
        [string]$AddSelection,
        [string]$RemoveSelection,
        [string]$DryRunAck,
        [bool]$RequireDryRunAck = $true,
        [switch]$Apply,
        [switch]$Yes
    )
    if ($Apply -and -not $Yes) {
        throw "执行安装必须同时传入 --apply --yes"
    }
    $rec = Load-AuditRecommendations $RecommendationsPath
    $plan = New-AuditInstallPlan $rec
    $report = [ordered]@{
        schema_version = 2
        run_id = [string]$rec.run_id
        target = [string]$rec.target
        decision_basis = $plan.decision_basis
        mode = if ($Apply) { "apply" } else { "dry_run" }
        success = $true
        persisted = $false
        changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates
        items = @($plan.items)
        removal_candidates = @($plan.removal_candidates)
        overlap_findings = @($plan.overlap_findings)
        do_not_install = @($plan.do_not_install)
        rollback = @()
    }

    Write-AuditRecommendationSummary $plan

    if (-not $Apply) {
        Write-Host "dry-run 预览（沿用原序号）："
        foreach ($item in @($plan.items)) {
            Write-Host ("DRYRUN install: {0}" -f ($item.tokens -join " "))
        }
        foreach ($item in @($plan.removal_candidates)) {
            Write-Host ("DRYRUN remove: [{0}|{1}] {2}" -f [string]$item.vendor, [string]$item.from, [string]$item.name)
        }
        Write-Host "DRY-RUN 完成：未修改任何技能映射（未落盘）。" -ForegroundColor Red
        Write-Host ("如需真正执行，请运行：.\skills.ps1 审查目标 应用 --recommendations `"{0}`" --apply --yes" -f $RecommendationsPath) -ForegroundColor Red
        if ($RequireDryRunAck) {
            $ackToken = Get-AuditDryRunAckToken
            $ackInput = ""
            if (-not [string]::IsNullOrWhiteSpace($DryRunAck)) {
                $ackInput = [string]$DryRunAck
            }
            elseif (-not [Console]::IsInputRedirected) {
                $ackInput = Read-HostSafe ("请输入确认口令 `"{0}`" 表示你已知晓 dry-run 未落盘（回车取消）" -f $ackToken)
            }
            else {
                Write-Host ("当前为非交互环境。请追加参数：--dry-run-ack `"{0}`"" -f $ackToken) -ForegroundColor Red
            }
            if ([string]::IsNullOrWhiteSpace($ackInput) -or $ackInput.Trim() -ne $ackToken) {
                $report.success = $false
                $report["canceled"] = $true
                $report["dry_run_acknowledged"] = $false
                $report["dry_run_ack_expected"] = $ackToken
                $report["dry_run_ack_received"] = [string]$ackInput
                $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates
                Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
                return [pscustomobject]$report
            }
            $report["dry_run_acknowledged"] = $true
        }
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
        return [pscustomobject]$report
    }

    $selectedAdd = Resolve-AuditSelection $AddSelection $plan.items "请输入要安装的新增建议序号（空=跳过，0=取消）" "新增建议序号无效"
    if ($selectedAdd.canceled) {
        $report.success = $false
        $report["canceled"] = $true
        $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates
        $report.persisted = $false
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
        return [pscustomobject]$report
    }
    $selectedRemove = Resolve-AuditSelection $RemoveSelection @($plan.removal_candidates | Where-Object { $_.status -eq "planned" }) "请输入要卸载的建议序号（空=跳过，0=取消）" "卸载建议序号无效"
    if ($selectedRemove.canceled) {
        $report.success = $false
        $report["canceled"] = $true
        $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates
        $report.persisted = $false
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
        return [pscustomobject]$report
    }

    try {
        foreach ($item in @($selectedAdd.items)) {
            $commandText = ".\skills.ps1 add {0}" -f ($item.tokens -join " ")
            try {
                Write-Host ("Installing recommended skill: {0}" -f $item.name) -ForegroundColor Cyan
                $beforeCfg = LoadCfg
                $ok = Add-ImportFromArgs $item.tokens -NoBuild
                if (-not $ok) { throw ("推荐技能安装失败：{0}" -f $item.name) }
                Ensure-AuditNewManualImportsMapped $beforeCfg | Out-Null
                $item.status = "installed"
                $item | Add-Member -NotePropertyName command -NotePropertyValue $commandText -Force
                $report.rollback += ("Remove matching imports/mappings for recommended skill '{0}' if rollback is required." -f $item.name)
            }
            catch {
                $item.status = "failed"
                $item | Add-Member -NotePropertyName command -NotePropertyValue $commandText -Force
                $item | Add-Member -NotePropertyName error -NotePropertyValue $_.Exception.Message -Force
                $report.success = $false
                $report.items = @($plan.items)
                $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates
                $report.persisted = (([int]$report.changed_counts.add_installed + [int]$report.changed_counts.remove_removed) -gt 0)
                Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
                throw
            }
        }

        if (@($selectedRemove.items).Count -gt 0) {
            Remove-AuditSelectedInstalledSkills $selectedRemove.items | Out-Null
            foreach ($item in @($selectedRemove.items)) {
                $report.rollback += ("Re-add removed skill mapping/import for '{0}' if rollback is required." -f $item.name)
            }
        }

        if (@($selectedAdd.items).Count -gt 0 -or @($selectedRemove.items).Count -gt 0) {
            构建生效
            $doctorResult = Invoke-Doctor @("--strict", "--threshold-ms", "8000")
            if ($doctorResult -and $doctorResult.PSObject.Properties.Match("pass").Count -gt 0 -and -not [bool]$doctorResult.pass) {
                $report.success = $false
                $report.items = @($plan.items)
                $report.removal_candidates = @($plan.removal_candidates)
                $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates
                $report.persisted = (([int]$report.changed_counts.add_installed + [int]$report.changed_counts.remove_removed) -gt 0)
                Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
                throw "doctor --strict failed after applying recommendations"
            }
        }

        $report.items = @($plan.items)
        $report.removal_candidates = @($plan.removal_candidates)
        $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates
        $report.persisted = (([int]$report.changed_counts.add_installed + [int]$report.changed_counts.remove_removed) -gt 0)
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
        return [pscustomobject]$report
    }
    catch {
        if ($report.success) { $report.success = $false }
        $report.items = @($plan.items)
        $report.removal_candidates = @($plan.removal_candidates)
        $report.changed_counts = New-AuditChangedCounts $plan.items $plan.removal_candidates
        $report.persisted = (([int]$report.changed_counts.add_installed + [int]$report.changed_counts.remove_removed) -gt 0)
        Write-AuditJsonFile (Get-AuditApplyReportPath $RecommendationsPath) ([pscustomobject]$report)
        throw
    }
}

function Get-AuditApplyConfirmationToken([string]$runId) {
    if ([string]::IsNullOrWhiteSpace($runId)) { return "APPLY" }
    return ("APPLY {0}" -f $runId)
}

function Get-AuditDryRunAckToken {
    return "我知道未落盘"
}

function Invoke-AuditRecommendationsTwoStageApply {
    param(
        [string]$RecommendationsPath,
        [string]$AddSelection,
        [string]$RemoveSelection,
        [string]$DryRunAck
    )
    $dryRunReport = Invoke-AuditRecommendationsApply -RecommendationsPath $RecommendationsPath -AddSelection $AddSelection -RemoveSelection $RemoveSelection -DryRunAck $DryRunAck -RequireDryRunAck $true
    if ($dryRunReport.PSObject.Properties.Match("success").Count -gt 0 -and -not [bool]$dryRunReport.success) {
        Write-Host "应用确认结束：dry-run 未完成确认，未执行落盘。" -ForegroundColor Yellow
        return $dryRunReport
    }
    $plannedAdds = @($dryRunReport.items | Where-Object { [string]$_.status -eq "planned" }).Count
    $plannedRemoves = @($dryRunReport.removal_candidates | Where-Object { [string]$_.status -eq "planned" }).Count
    if ($plannedAdds -eq 0 -and $plannedRemoves -eq 0) {
        Write-Host "应用确认结束：无可执行变更，保持当前状态。" -ForegroundColor Yellow
        return $dryRunReport
    }

    $confirmToken = Get-AuditApplyConfirmationToken ([string]$dryRunReport.run_id)
    Write-Host ""
    Write-Host ("确认口令：{0}" -f $confirmToken) -ForegroundColor Yellow
    $confirmation = Read-HostSafe "请输入确认口令后回车执行（回车取消）"
    if ([string]::IsNullOrWhiteSpace($confirmation) -or $confirmation.Trim() -ne $confirmToken) {
        Write-Host "已取消执行。未做任何落盘更改。" -ForegroundColor Yellow
        return [pscustomobject]([ordered]@{
            schema_version = 2
            run_id = [string]$dryRunReport.run_id
            target = [string]$dryRunReport.target
            mode = "apply_flow"
            success = $false
            canceled = $true
            expected_confirmation = $confirmToken
            received_confirmation = [string]$confirmation
        })
    }
    return (Invoke-AuditRecommendationsApply -RecommendationsPath $RecommendationsPath -AddSelection $AddSelection -RemoveSelection $RemoveSelection -Apply -Yes)
}

function Get-AuditLatestApplyReportPath {
    $auditRoot = Join-Path $script:Root "reports\skill-audit"
    if (-not (Test-Path -LiteralPath $auditRoot -PathType Container)) { return $null }
    $candidates = @(Get-ChildItem -Path $auditRoot -Recurse -File -Filter "apply-report.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($candidates.Count -eq 0) { return $null }
    return [string]$candidates[0].FullName
}

function Show-AuditLatestStatus {
    $path = Get-AuditLatestApplyReportPath
    if ([string]::IsNullOrWhiteSpace($path)) {
        Write-Host "未找到 apply-report.json。请先执行：审查目标 应用确认 或 审查目标 应用。" -ForegroundColor Yellow
        return
    }
    try {
        $raw = Get-ContentUtf8 $path
        Need (-not [string]::IsNullOrWhiteSpace($raw)) ("状态文件为空：{0}" -f $path)
        $report = $raw | ConvertFrom-Json
    }
    catch {
        throw ("读取状态文件失败：{0}" -f $_.Exception.Message)
    }
    $counts = if ($report.PSObject.Properties.Match("changed_counts").Count -gt 0 -and $null -ne $report.changed_counts) { $report.changed_counts } else { $null }
    $persisted = if ($report.PSObject.Properties.Match("persisted").Count -gt 0) { [bool]$report.persisted } else { $false }
    Write-Host "=== 审查目标最近状态 ==="
    Write-Host ("report: {0}" -f $path)
    Write-Host ("run_id: {0}" -f [string]$report.run_id)
    Write-Host ("mode: {0}" -f [string]$report.mode)
    Write-Host ("success: {0}" -f [string]$report.success)
    Write-Host ("persisted: {0}" -f $persisted)
    if ($null -ne $counts) {
        Write-Host ("changes: add_installed={0}, remove_removed={1}, add_planned={2}, remove_planned={3}, remove_not_found={4}" -f [int]$counts.add_installed, [int]$counts.remove_removed, [int]$counts.add_planned, [int]$counts.remove_planned, [int]$counts.remove_not_found)
    }
    if ([string]$report.mode -eq "dry_run" -and -not $persisted) {
        Write-Host "警告：最近一次仅为 dry-run，未落盘。" -ForegroundColor Red
    }
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
        "scan" { Invoke-AuditTargetsScan -Target $opts.target -OutDir $opts.out | Out-Null }
        "discover_skills" { Invoke-AuditSkillDiscovery -Query $opts.query -OutDir $opts.out | Out-Null }
        "apply_flow" { Invoke-AuditRecommendationsTwoStageApply -RecommendationsPath $opts.recommendations -AddSelection $opts.add_selection -RemoveSelection $opts.remove_selection -DryRunAck $opts.dry_run_ack | Out-Null }
        "apply" { Invoke-AuditRecommendationsApply -RecommendationsPath $opts.recommendations -AddSelection $opts.add_selection -RemoveSelection $opts.remove_selection -DryRunAck $opts.dry_run_ack -RequireDryRunAck (-not $opts.apply) -Apply:$opts.apply -Yes:$opts.yes | Out-Null }
    }
}
