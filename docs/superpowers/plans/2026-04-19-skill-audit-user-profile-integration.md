# Skill Audit User Profile Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a global user profile to the skill audit workflow, make user-profile plus target-repo the mandatory decision basis for outer AI recommendations, and integrate the workflow into commands, menu, reports, and docs.

**Architecture:** Extend `audit-targets.json` from schema v1 to v2 with a top-level `user_profile`, keep deterministic storage and validation in `AuditTargets.ps1`, and let the outer AI handle semantic structuring plus network research. Reuse the existing `审查目标` command family, add profile subcommands and a menu-driven audit hub, and enforce the new recommendation schema and source-strategy rules during scan/apply.

**Tech Stack:** PowerShell 5.1 script modules, Pester 3.4.0 tests, existing `build.ps1` script assembly, JSON config and report files.

---

### Task 1: Expand Audit Config Schema To v2

**Files:**
- Modify: `src/Commands/AuditTargets.ps1`
- Modify: `tests/Unit/AuditTargets.Tests.ps1`
- Modify: `build.ps1`
- Modify: `skills.ps1`

- [ ] **Step 1: Write the failing tests for v2 config defaults and migration**

```powershell
It "Creates audit-targets config with user_profile in version 2" {
    $oldRoot = $script:Root
    try {
        $script:Root = Join-Path $TestDrive "ws-audit-v2-init"
        New-Item -ItemType Directory -Path $script:Root -Force | Out-Null

        Initialize-AuditTargetsConfig | Out-Null
        $cfg = Load-AuditTargetsConfig

        $cfg.version | Should Be 2
        $cfg.user_profile | Should Not BeNullOrEmpty
        $cfg.user_profile.raw_text | Should Be ""
        $cfg.user_profile.summary | Should Be ""
        $cfg.user_profile.structured.primary_work_types.Count | Should Be 0
    }
    finally {
        $script:Root = $oldRoot
    }
}

It "Migrates version 1 audit config to version 2 with empty user_profile" {
    $oldRoot = $script:Root
    try {
        $script:Root = Join-Path $TestDrive "ws-audit-v1-migrate"
        New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
        Set-ContentUtf8 (Join-Path $script:Root "audit-targets.json") '{"version":1,"path_base":"skills_manager_root","targets":[]}'

        $cfg = Load-AuditTargetsConfig

        $cfg.version | Should Be 2
        $cfg.user_profile.raw_text | Should Be ""
        $cfg.user_profile.summary | Should Be ""
    }
    finally {
        $script:Root = $oldRoot
    }
}
```

- [ ] **Step 2: Run the targeted unit test filter and confirm failure**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\AuditTargets.Tests.ps1 -TestName 'Creates audit-targets config with user_profile in version 2','Migrates version 1 audit config to version 2 with empty user_profile'"
```

Expected: FAIL because config schema still returns version `1` and has no `user_profile`.

- [ ] **Step 3: Implement v2 config helpers in `src/Commands/AuditTargets.ps1`**

```powershell
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

function Ensure-AuditUserProfile($cfg) {
    if (-not $cfg.PSObject.Properties.Match("user_profile").Count -or $null -eq $cfg.user_profile) {
        $cfg | Add-Member -NotePropertyName user_profile -NotePropertyValue (New-DefaultAuditUserProfile) -Force
    }
    $profile = $cfg.user_profile
    foreach ($name in @("raw_text", "summary", "last_structured_at", "structured_by")) {
        if (-not $profile.PSObject.Properties.Match($name).Count) {
            $profile | Add-Member -NotePropertyName $name -NotePropertyValue "" -Force
        }
    }
    if (-not $profile.PSObject.Properties.Match("structured").Count -or $null -eq $profile.structured) {
        $profile | Add-Member -NotePropertyName structured -NotePropertyValue (New-DefaultAuditUserProfile).structured -Force
    }
    foreach ($field in @("primary_work_types", "preferred_agents", "tech_stack", "common_tasks", "constraints", "avoidances", "decision_preferences")) {
        if (-not $profile.structured.PSObject.Properties.Match($field).Count -or $null -eq $profile.structured.$field) {
            $profile.structured | Add-Member -NotePropertyName $field -NotePropertyValue @() -Force
        }
        elseif (-not (Assert-IsArray $profile.structured.$field)) {
            $profile.structured.$field = @($profile.structured.$field)
        }
    }
}
```

- [ ] **Step 4: Update the existing default config and loader to use schema v2**

```powershell
function New-DefaultAuditTargetsConfig {
    return [pscustomobject]@{
        version = 2
        path_base = "skills_manager_root"
        user_profile = New-DefaultAuditUserProfile
        targets = @()
    }
}

function Load-AuditTargetsConfig {
    $path = Get-AuditTargetsConfigPath
    Need (Test-Path -LiteralPath $path -PathType Leaf) "缺少 audit-targets.json，请先运行：./skills.ps1 审查目标 初始化"
    try {
        $cfg = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    }
    catch {
        throw ("audit-targets.json 解析失败：{0}" -f $_.Exception.Message)
    }

    if (-not $cfg.PSObject.Properties.Match("version").Count) {
        $cfg | Add-Member -NotePropertyName version -NotePropertyValue 1
    }
    if ([int]$cfg.version -eq 1) {
        $cfg.version = 2
    }
    if (-not $cfg.PSObject.Properties.Match("path_base").Count) {
        $cfg | Add-Member -NotePropertyName path_base -NotePropertyValue "skills_manager_root"
    }
    if (-not $cfg.PSObject.Properties.Match("targets").Count -or $null -eq $cfg.targets) {
        $cfg | Add-Member -NotePropertyName targets -NotePropertyValue @() -Force
    }
    Ensure-AuditUserProfile $cfg

    Need ([int]$cfg.version -eq 2) "audit-targets.json version 仅支持 2"
    Need ([string]$cfg.path_base -eq "skills_manager_root") "audit-targets.json path_base 仅支持 skills_manager_root"
    if (-not (Assert-IsArray $cfg.targets)) { $cfg.targets = @($cfg.targets) }
    return $cfg
}
```

- [ ] **Step 5: Rebuild the generated entry script**

Run:

```powershell
./build.ps1
```

Expected: `Build success: D:\OneDrive\CODE\skills-manager\skills.ps1`

- [ ] **Step 6: Re-run the targeted tests and confirm pass**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\AuditTargets.Tests.ps1 -TestName 'Creates audit-targets config with user_profile in version 2','Migrates version 1 audit config to version 2 with empty user_profile'"
```

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add src/Commands/AuditTargets.ps1 tests/Unit/AuditTargets.Tests.ps1 build.ps1 skills.ps1
git commit -m "feat: add audit config user profile schema"
```

### Task 2: Add User Profile Commands And Validation

**Files:**
- Modify: `src/Commands/AuditTargets.ps1`
- Modify: `tests/Unit/AuditTargets.Tests.ps1`
- Modify: `skills.ps1`

- [ ] **Step 1: Write the failing tests for profile-set, profile-show, and scan blocking**

```powershell
It "Saves raw user profile text and clears stale structured fields" {
    $oldRoot = $script:Root
    try {
        $script:Root = Join-Path $TestDrive "ws-profile-set"
        New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
        Initialize-AuditTargetsConfig | Out-Null
        $cfg = Load-AuditTargetsConfig
        $cfg.user_profile.summary = "stale"
        $cfg.user_profile.structured.primary_work_types = @("old")
        Save-AuditTargetsConfig $cfg

        Set-AuditUserProfileRawText "I maintain multi-agent automation and repo governance workflows."
        $saved = Load-AuditTargetsConfig

        $saved.user_profile.raw_text | Should Match "multi-agent automation"
        $saved.user_profile.summary | Should Be ""
        $saved.user_profile.structured.primary_work_types.Count | Should Be 0
    }
    finally {
        $script:Root = $oldRoot
    }
}

It "Blocks scan when user_profile.raw_text is missing" {
    $oldRoot = $script:Root
    try {
        $script:Root = Join-Path $TestDrive "ws-profile-required"
        New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
        Initialize-AuditTargetsConfig | Out-Null
        Add-AuditTargetConfigEntry "demo" "..\\demo" | Out-Null

        { Invoke-AuditTargetsScan -Target "demo" } | Should Throw
    }
    finally {
        $script:Root = $oldRoot
    }
}
```

- [ ] **Step 2: Run the targeted tests and confirm failure**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\AuditTargets.Tests.ps1 -TestName 'Saves raw user profile text and clears stale structured fields','Blocks scan when user_profile.raw_text is missing'"
```

Expected: FAIL because the profile helpers and scan guard do not exist yet.

- [ ] **Step 3: Extend argument parsing with profile subcommands**

```powershell
switch ($head) {
    "需求设置" { $result.action = "profile_set"; $items = @($items | Select-Object -Skip 1) }
    "profile-set" { $result.action = "profile_set"; $items = @($items | Select-Object -Skip 1) }
    "需求查看" { $result.action = "profile_show"; $items = @($items | Select-Object -Skip 1) }
    "profile-show" { $result.action = "profile_show"; $items = @($items | Select-Object -Skip 1) }
    "需求结构化" { $result.action = "profile_structure"; $items = @($items | Select-Object -Skip 1) }
    "profile-structure" { $result.action = "profile_structure"; $items = @($items | Select-Object -Skip 1) }
}
```

- [ ] **Step 4: Implement profile storage and display helpers**

```powershell
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
    Write-Host $cfg.user_profile.raw_text
    Write-Host ""
    Write-Host ("summary: {0}" -f [string]$cfg.user_profile.summary)
    Write-Host ("structured_by: {0}" -f [string]$cfg.user_profile.structured_by)
}
```

- [ ] **Step 5: Add the scan precondition for `user_profile.raw_text`**

```powershell
function Assert-AuditUserProfileReady($cfg) {
    Need (-not [string]::IsNullOrWhiteSpace([string]$cfg.user_profile.raw_text)) "缺少用户基本需求，请先运行：./skills.ps1 审查目标 需求设置"
}

function Invoke-AuditTargetsScan {
    param(
        [string]$Target,
        [string]$OutDir
    )
    $cfg = Load-AuditTargetsConfig
    Assert-AuditUserProfileReady $cfg
    # existing target filtering continues below
}
```

- [ ] **Step 6: Route the new actions in `Invoke-AuditTargetsCommand`**

```powershell
"profile_set" {
    $rawText = Read-HostSafe "请输入用户基本需求（长文本）"
    Set-AuditUserProfileRawText $rawText
    Write-Host "已保存用户基本需求。请重新导入结构化结果。" -ForegroundColor Green
}
"profile_show" { Show-AuditUserProfile }
```

- [ ] **Step 7: Rebuild and rerun the targeted tests**

Run:

```powershell
./build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\AuditTargets.Tests.ps1 -TestName 'Saves raw user profile text and clears stale structured fields','Blocks scan when user_profile.raw_text is missing'"
```

Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add src/Commands/AuditTargets.ps1 tests/Unit/AuditTargets.Tests.ps1 skills.ps1
git commit -m "feat: add audit user profile commands"
```

### Task 3: Import Structured Profile And Emit User Profile Report

**Files:**
- Modify: `src/Commands/AuditTargets.ps1`
- Modify: `tests/Unit/AuditTargets.Tests.ps1`
- Modify: `tests/E2E/SkillAudit.Tests.ps1`
- Modify: `skills.ps1`

- [ ] **Step 1: Write the failing tests for structured profile import and report output**

```powershell
It "Imports structured profile JSON from file" {
    $oldRoot = $script:Root
    try {
        $script:Root = Join-Path $TestDrive "ws-profile-structure"
        New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
        Initialize-AuditTargetsConfig | Out-Null
        Set-AuditUserProfileRawText "I maintain repo governance workflows."

        $profilePath = Join-Path $TestDrive "profile.json"
        Set-ContentUtf8 $profilePath '{"summary":"repo-governance focus","structured":{"primary_work_types":["repo-governance"],"preferred_agents":["codex"],"tech_stack":["powershell"],"common_tasks":["skill review"],"constraints":["windows-first"],"avoidances":["opaque automation"],"decision_preferences":["evidence-first"]},"structured_by":"outer-ai"}'

        Import-AuditStructuredProfile $profilePath
        $saved = Load-AuditTargetsConfig

        $saved.user_profile.summary | Should Be "repo-governance focus"
        $saved.user_profile.structured.primary_work_types[0] | Should Be "repo-governance"
        $saved.user_profile.structured_by | Should Be "outer-ai"
    }
    finally {
        $script:Root = $oldRoot
    }
}
```

- [ ] **Step 2: Run the targeted unit test and confirm failure**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\AuditTargets.Tests.ps1 -TestName 'Imports structured profile JSON from file'"
```

Expected: FAIL because the import helper does not exist.

- [ ] **Step 3: Implement structured profile import**

```powershell
function Import-AuditStructuredProfile([string]$path) {
    Need (-not [string]::IsNullOrWhiteSpace($path)) "--profile 缺少值"
    Need (Test-Path -LiteralPath $path -PathType Leaf) ("profile 文件不存在：{0}" -f $path)
    $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json

    $cfg = Load-AuditTargetsConfig
    $cfg.user_profile.summary = [string]$data.summary
    $cfg.user_profile.structured = $data.structured
    Ensure-AuditUserProfile $cfg
    $cfg.user_profile.last_structured_at = (Get-Date).ToString("o")
    $cfg.user_profile.structured_by = if ($data.PSObject.Properties.Match("structured_by").Count) { [string]$data.structured_by } else { "outer-ai" }
    Save-AuditTargetsConfig $cfg
}
```

- [ ] **Step 4: Emit `user-profile.json` during scan**

```powershell
$profileOut = [pscustomobject]@{
    schema_version = 1
    raw_text = [string]$cfg.user_profile.raw_text
    summary = [string]$cfg.user_profile.summary
    structured = $cfg.user_profile.structured
    last_structured_at = [string]$cfg.user_profile.last_structured_at
    structured_by = [string]$cfg.user_profile.structured_by
}
Write-AuditJsonFile (Join-Path $reportRoot "user-profile.json") $profileOut
```

- [ ] **Step 5: Update `ai-brief.md` generation to reference the new profile file and dual-basis rule**

```powershell
- External AI decisions must be based on BOTH user-profile.json and target repo scan facts.
- Network research is authorized within this audit workflow, but installation still requires --apply --yes.
- You must cover the required built-in source categories and record the actual sources you used.
```

- [ ] **Step 6: Rebuild and rerun the targeted unit tests**

Run:

```powershell
./build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\AuditTargets.Tests.ps1 -TestName 'Imports structured profile JSON from file'"
```

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add src/Commands/AuditTargets.ps1 tests/Unit/AuditTargets.Tests.ps1 tests/E2E/SkillAudit.Tests.ps1 skills.ps1
git commit -m "feat: emit audit user profile reports"
```

### Task 4: Enforce Recommendation Schema v2 And Removal Candidates

**Files:**
- Modify: `src/Commands/AuditTargets.ps1`
- Modify: `tests/Unit/AuditTargets.Tests.ps1`
- Modify: `tests/E2E/SkillAudit.Tests.ps1`
- Modify: `skills.ps1`

- [ ] **Step 1: Write failing tests for schema v2 validation**

```powershell
It "Rejects recommendations without decision_basis for user profile and target scan" {
    $path = Join-Path $TestDrive "recommendations-no-basis.json"
    Set-ContentUtf8 $path '{"schema_version":2,"run_id":"r1","target":"demo","new_skills":[],"overlap_findings":[],"removal_candidates":[],"do_not_install":[]}'

    { Load-AuditRecommendations $path } | Should Throw
}

It "Allows removal candidates but does not create uninstall plan items" {
    $path = Join-Path $TestDrive "recommendations-removal.json"
    Set-ContentUtf8 $path '{"schema_version":2,"run_id":"r1","target":"demo","decision_basis":{"user_profile_used":true,"target_scan_used":true,"source_strategy_used":true,"summary":"ok"},"new_skills":[],"overlap_findings":[],"removal_candidates":[{"name":"old-skill","reason_user_profile":"user no longer needs it","reason_target_repo":"repo stack no longer matches","sources":["https://example.com"]}],"do_not_install":[]}'

    $rec = Load-AuditRecommendations $path
    $plan = New-AuditInstallPlan $rec

    @($plan.items).Count | Should Be 0
    @($plan.removal_candidates).Count | Should Be 1
}
```

- [ ] **Step 2: Run the targeted tests and confirm failure**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\AuditTargets.Tests.ps1 -TestName 'Rejects recommendations without decision_basis for user profile and target scan','Allows removal candidates but does not create uninstall plan items'"
```

Expected: FAIL because the loader still expects schema `1`.

- [ ] **Step 3: Upgrade recommendation loading and validation to schema v2**

```powershell
Need ([int]$rec.schema_version -eq 2) "recommendations.schema_version 仅支持 2"
Need ($rec.PSObject.Properties.Match("decision_basis").Count -gt 0 -and $null -ne $rec.decision_basis) "recommendations 缺少 decision_basis"
Need ([bool]$rec.decision_basis.user_profile_used) "decision_basis.user_profile_used 必须为 true"
Need ([bool]$rec.decision_basis.target_scan_used) "decision_basis.target_scan_used 必须为 true"
Need ([bool]$rec.decision_basis.source_strategy_used) "decision_basis.source_strategy_used 必须为 true"
Need (-not [string]::IsNullOrWhiteSpace([string]$rec.decision_basis.summary)) "decision_basis.summary 不能为空"
Ensure-AuditArrayProperty $rec "removal_candidates"
```

- [ ] **Step 4: Validate dual reasons on install and removal items**

```powershell
function Assert-AuditReasonPair($item, [string]$name) {
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.reason_user_profile)) ("{0} 缺少 reason_user_profile：{1}" -f $name, [string]$item.name)
    Need (-not [string]::IsNullOrWhiteSpace([string]$item.reason_target_repo)) ("{0} 缺少 reason_target_repo：{1}" -f $name, [string]$item.name)
    Ensure-AuditArrayProperty $item "sources"
    Need (@($item.sources).Count -gt 0) ("{0} 至少需要一个 source：{1}" -f $name, [string]$item.name)
}
```

- [ ] **Step 5: Carry removal candidates through plan and apply report without uninstalling**

```powershell
return [pscustomobject]([ordered]@{
    schema_version = 2
    run_id = [string]$recommendations.run_id
    target = [string]$recommendations.target
    items = @($items)
    overlap_findings = @($recommendations.overlap_findings)
    removal_candidates = @($recommendations.removal_candidates)
    do_not_install = @($recommendations.do_not_install)
})
```

- [ ] **Step 6: Rebuild and rerun the targeted tests**

Run:

```powershell
./build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\AuditTargets.Tests.ps1 -TestName 'Rejects recommendations without decision_basis for user profile and target scan','Allows removal candidates but does not create uninstall plan items'"
```

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add src/Commands/AuditTargets.ps1 tests/Unit/AuditTargets.Tests.ps1 tests/E2E/SkillAudit.Tests.ps1 skills.ps1
git commit -m "feat: enforce audit recommendation schema v2"
```

### Task 5: Add Menu Integration And Help Copy

**Files:**
- Modify: `src/Commands/Utils.ps1`
- Modify: `src/Commands/AuditTargets.ps1`
- Modify: `tests/Unit/AuditTargets.Tests.ps1`
- Modify: `skills.ps1`

- [ ] **Step 1: Write failing menu routing tests**

```powershell
It "Shows audit menu entry in the main menu help text" {
    (Get-Content -LiteralPath (Join-Path $Root "src/Commands/Utils.ps1") -Raw) | Should Match "17\) 审查目标"
}
```

- [ ] **Step 2: Add a dedicated audit submenu helper**

```powershell
function 审查目标菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== 审查目标 ==="
        Write-Host "1) 设置用户基本需求"
        Write-Host "2) 查看用户基本需求"
        Write-Host "3) 导入结构化需求"
        Write-Host "4) 添加目标仓"
        Write-Host "5) 列出目标仓"
        Write-Host "6) 生成审查包"
        Write-Host "7) 应用 recommendations（dry-run）"
        Write-Host "8) 应用 recommendations（--apply --yes）"
        Write-Host "0) 返回"
        $c = Read-HostSafe "请选择"
        switch ($c) {
            "1" { Invoke-AuditTargetsCommand @("需求设置") }
            "2" { Invoke-AuditTargetsCommand @("需求查看") }
            "3" { $path = Read-HostSafe "请输入结构化 profile 文件路径"; Invoke-AuditTargetsCommand @("需求结构化", "--profile", $path) }
            "4" { $name = Read-HostSafe "请输入目标仓名称"; $path = Read-HostSafe "请输入目标仓路径"; Invoke-AuditTargetsCommand @("添加", $name, $path) }
            "5" { Invoke-AuditTargetsCommand @("列表") }
            "6" { Invoke-AuditTargetsCommand @("扫描") }
            "7" { $path = Read-HostSafe "请输入 recommendations 文件路径"; Invoke-AuditTargetsCommand @("应用", "--recommendations", $path) }
            "8" { $path = Read-HostSafe "请输入 recommendations 文件路径"; Invoke-AuditTargetsCommand @("应用", "--recommendations", $path, "--apply", "--yes") }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}
```

- [ ] **Step 3: Insert the new top-level menu item and route**

```powershell
Write-Host "17) 审查目标（用户基本需求 / 目标仓 / 扫描 / 应用）"

"17" { 审查目标菜单 }
```

- [ ] **Step 4: Update `帮助` to mention the new global user-profile rule and networking rule**

```powershell
  - 审查目标：围绕“用户基本需求 + 目标仓”生成审查包，外层 AI 可在本流程内联网研究，但安装仍需 --apply --yes
```

- [ ] **Step 5: Rebuild and run a smoke verification for the menu script**

Run:

```powershell
./build.ps1
```

Expected: build succeeds and the generated `skills.ps1` contains the new menu text.

- [ ] **Step 6: Commit**

```bash
git add src/Commands/Utils.ps1 src/Commands/AuditTargets.ps1 skills.ps1 tests/Unit/AuditTargets.Tests.ps1
git commit -m "feat: add audit workflow menu integration"
```

### Task 6: Update README And Evidence Docs

**Files:**
- Modify: `README.md`
- Modify: `README.en.md`
- Modify: `docs/change-evidence/20260419-skill-audit-implementation.md`

- [ ] **Step 1: Update Chinese README audit section**

```markdown
- 用户基本需求是全局上下文，目标仓是项目级上下文。
- 外层 AI 对技能取舍必须同时基于两者。
- 用户启动审查流程后，外层 AI 可以在该流程内自主联网搜索。
- 安装仍需 `--apply --yes`。
```

- [ ] **Step 2: Update English README audit section with the same rules**

```markdown
- The user profile is global context; target repositories are project-level context.
- Outer AI decisions must use both.
- Starting the audit workflow authorizes network research within that workflow.
- Installation still requires `--apply --yes`.
```

- [ ] **Step 3: Extend the evidence file to mention schema v2 and menu integration**

```text
数据变更治理(...)=adds audit-targets.json schema v2 with global user_profile; adds user-profile.json scan output; recommendations schema v2 with decision_basis and removal_candidates; menu entry integrated into main interactive flow
```

- [ ] **Step 4: Review the diff and commit**

Run:

```bash
git add README.md README.en.md docs/change-evidence/20260419-skill-audit-implementation.md
git commit -m "docs: document audit user profile workflow"
```

- [ ] **Step 5: Run the full verification sequence**

Run:

```powershell
./build.ps1
./skills.ps1 发现
./skills.ps1 doctor --strict --threshold-ms 8000
./skills.ps1 构建生效
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run.ps1
```

Expected:
- build success
- discover lists installed skills
- doctor strict passes
- build/apply succeeds
- full Pester suite passes with zero failures

- [ ] **Step 6: Commit the final verification-only delta if needed**

```bash
git status --short
```

Expected: either clean working tree or only expected generated doc/evidence changes already committed.

## Self-Review

Spec coverage:
- v2 config and global user profile: Task 1
- profile commands and required raw text: Task 2
- structured import and user-profile report: Task 3
- decision basis, source strategy, removal candidates: Task 4
- menu integration and UX copy: Task 5
- README/help/evidence updates and full verification: Task 6

Placeholder scan:
- No `TBD`, `TODO`, or “implement later” placeholders remain.
- Each task contains exact files, code snippets, commands, and expected outcomes.

Type consistency:
- Config uses `version = 2`, `user_profile`, and fixed structured field names throughout.
- Recommendation validation consistently refers to `decision_basis`, `reason_user_profile`, `reason_target_repo`, and `removal_candidates`.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-19-skill-audit-user-profile-integration.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
