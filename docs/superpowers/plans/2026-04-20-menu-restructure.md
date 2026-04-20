# Menu Restructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the interactive menu around expert-first direct actions, move complex domains into structured submenus, and align help/docs/tests with the new wording without changing command semantics.

**Architecture:** Keep all command handlers and CLI aliases intact. Concentrate navigation changes in `src/Commands/Utils.ps1`, update workflow copy in `src/Commands/Workflow.ps1`, and lock the new wording with focused Pester tests before regenerating `skills.ps1`.

**Tech Stack:** PowerShell, Pester, generated `skills.ps1`, Markdown docs

---

## File Map

- Create: `tests/Unit/MenuStructure.Tests.ps1`
- Modify: `src/Commands/Utils.ps1`
- Modify: `src/Commands/Workflow.ps1`
- Modify: `tests/Unit/AuditTargets.Tests.ps1`
- Modify: `tests/Unit/Workflow.Tests.ps1`
- Modify: `README.md`
- Modify: `README.en.md`
- Regenerate: `skills.ps1`

## Implementation Notes

- Do not rename CLI commands such as `发现`, `安装`, `构建生效`, `更新`, `审查目标`, or `一键`.
- Only change menu labels, submenu structure, help wording, workflow descriptions, and docs/tests that assert those strings.
- Rebuild `skills.ps1` after every `src/` change so source and generated entry stay in sync.
- Keep submenu depth to 2 levels total: main menu + one submenu.

### Task 1: Top-Level Menu Skeleton And New Submenu Helpers

**Files:**
- Create: `tests/Unit/MenuStructure.Tests.ps1`
- Modify: `src/Commands/Utils.ps1`
- Regenerate: `skills.ps1`

- [ ] **Step 1: Write the failing menu-structure test file**

```powershell
. $PSScriptRoot\..\..\skills.ps1

Describe "Interactive menu structure" {
    It "Documents the expert-first top-level menu in source" {
        $raw = Get-Content -LiteralPath (Join-Path $Root "src/Commands/Utils.ps1") -Raw
        $raw | Should Match '1\) 浏览技能'
        $raw | Should Match '2\) 选择安装'
        $raw | Should Match '3\) 粘贴命令导入'
        $raw | Should Match '4\) 卸载技能'
        $raw | Should Match '5\) 重建并同步'
        $raw | Should Match '6\) 更新上游'
        $raw | Should Match '7\) 目标仓审查'
        $raw | Should Match '8\) MCP 服务'
        $raw | Should Match '9\) 技能库管理'
        $raw | Should Match '10\) 更多'
    }

    It "Adds dedicated submenu helpers for non-daily domains" {
        $raw = Get-Content -LiteralPath (Join-Path $Root "src/Commands/Utils.ps1") -Raw
        $raw | Should Match 'function MCP菜单'
        $raw | Should Match 'function 技能库管理菜单'
        $raw | Should Match 'function 更多菜单'
        $raw | Should Match '"8"\s*\{\s*MCP菜单\s*\}'
        $raw | Should Match '"9"\s*\{\s*技能库管理菜单\s*\}'
        $raw | Should Match '"10"\s*\{\s*更多菜单\s*\}'
    }
}
```

- [ ] **Step 2: Run the new test file and verify it fails**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\MenuStructure.Tests.ps1"
```

Expected:

```text
FAIL because the menu still contains `发现技能` / `命令导入安装` / `构建并生效`
FAIL because `function MCP菜单`, `function 技能库管理菜单`, and `function 更多菜单` do not exist yet
```

- [ ] **Step 3: Implement the new submenu helpers in `src/Commands/Utils.ps1`**

Add these helpers above `function 审查目标菜单`:

```powershell
function MCP菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== MCP 服务 ==="
        Write-Host "1) 新增 MCP 服务"
        Write-Host "2) 卸载 MCP 服务"
        Write-Host "3) 同步 MCP 配置"
        Write-Host "0) 返回"
        $c = Read-HostSafe "请选择"
        switch ($c) {
            "1" { 安装MCP }
            "2" { 卸载MCP }
            "3" { 同步MCP }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}

function 技能库管理菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== 技能库管理 ==="
        Write-Host "1) 新增技能库"
        Write-Host "2) 删除技能库"
        Write-Host "3) 生成锁文件"
        Write-Host "4) 打开配置"
        Write-Host "0) 返回"
        $c = Read-HostSafe "请选择"
        switch ($c) {
            "1" { 新增技能库 }
            "2" { 删除技能库 }
            "3" { 锁定 }
            "4" { 打开配置 }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}

function 更多菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== 更多 ==="
        Write-Host "1) 一键工作流"
        Write-Host "2) 自动更新设置"
        Write-Host "3) 解除关联"
        Write-Host "4) 清理备份"
        Write-Host "0) 返回"
        $c = Read-HostSafe "请选择"
        switch ($c) {
            "1" { Invoke-Workflow @() }
            "2" { 自动更新设置 }
            "3" { 解除关联 }
            "4" { 清理备份 }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}
```

- [ ] **Step 4: Replace the top-level `菜单` block with the new expert-first order**

Replace the old body of `function 菜单` with:

```powershell
function 菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== Skills 管理器 ==="
        Write-Host "1) 浏览技能"
        Write-Host "2) 选择安装"
        Write-Host "3) 粘贴命令导入"
        Write-Host "4) 卸载技能"
        Write-Host "5) 重建并同步"
        Write-Host "6) 更新上游"
        Write-Host "7) 目标仓审查"
        Write-Host "8) MCP 服务"
        Write-Host "9) 技能库管理"
        Write-Host "10) 更多"
        Write-Host "98) 帮助"
        Write-Host "0) 退出"
        $c = Read-HostSafe "请选择"
        switch ($c) {
            "1" { 发现 }
            "2" { 安装 }
            "3" { 命令导入安装 }
            "4" { 卸载 }
            "5" { 构建生效 }
            "6" { 更新 }
            "7" { 审查目标菜单 }
            "8" { MCP菜单 }
            "9" { 技能库管理菜单 }
            "10" { 更多菜单 }
            "98" { 帮助 }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}
```

- [ ] **Step 5: Rebuild `skills.ps1` and rerun the focused test file**

Run:

```powershell
./build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\MenuStructure.Tests.ps1"
```

Expected:

```text
Build success: D:\OneDrive\CODE\skills-manager\skills.ps1
PASS Interactive menu structure
```

- [ ] **Step 6: Commit the menu skeleton change**

```powershell
git add src/Commands/Utils.ps1 tests/Unit/MenuStructure.Tests.ps1 skills.ps1
git commit -m "feat: add expert-first menu skeleton"
```

### Task 2: Audit Hub Reordering And Recommended/Advanced Split

**Files:**
- Modify: `tests/Unit/AuditTargets.Tests.ps1`
- Modify: `src/Commands/Utils.ps1`
- Regenerate: `skills.ps1`

- [ ] **Step 1: Add failing audit-menu assertions**

Add this `It` block under the existing `Context "Recommendations"` in `tests/Unit/AuditTargets.Tests.ps1`:

```powershell
It "Documents the renamed audit hub with recommended and advanced actions" {
    $raw = Get-Content -LiteralPath (Join-Path $Root "src/Commands/Utils.ps1") -Raw
    $raw | Should Match '7\) 目标仓审查'
    $raw | Should Match '=== 目标仓审查 ==='
    $raw | Should Match '5\) 应用建议（推荐）'
    $raw | Should Match '12\) 查看 AI 提示词'
    $raw | Should Match '13\) 编辑 AI 提示词'
    $raw | Should Match '14\) 直接执行建议（高级）'
    $raw | Should Not Match '17\) 审查目标（需求 / 目标仓 / 审查包 / 自检后 dry-run / 按原序号选择增删）'
}
```

- [ ] **Step 2: Run the targeted audit tests and verify the new assertion fails**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\AuditTargets.Tests.ps1 -TestName 'Documents the renamed audit hub with recommended and advanced actions'"
```

Expected:

```text
FAIL because the source still says `=== 审查目标 ===` and uses the old long-form menu label
```

- [ ] **Step 3: Rework `审查目标菜单` to match the approved order**

Replace the display text and switch order with:

```powershell
function 审查目标菜单 {
    while ($true) {
        Write-Host ""
        Write-Host "=== 目标仓审查 ==="
        Write-Host "1) 查看需求"
        Write-Host "2) 编辑需求"
        Write-Host "3) 目标仓列表"
        Write-Host "4) 生成审查包"
        Write-Host "5) 应用建议（推荐）"
        Write-Host "6) 查看最近状态"
        Write-Host "7) 新增目标仓"
        Write-Host "8) 修改目标仓"
        Write-Host "9) 删除目标仓"
        Write-Host "10) 导入结构化需求"
        Write-Host "11) 初始化审查配置"
        Write-Host "12) 查看 AI 提示词"
        Write-Host "13) 编辑 AI 提示词"
        Write-Host "14) 直接执行建议（高级）"
        Write-Host "0) 返回"
        $c = Read-HostSafe "请选择"
        switch ($c) {
            "1" { Invoke-AuditTargetsCommand @("profile-show") }
            "2" { Invoke-AuditTargetsCommand @("profile-set") }
            "3" { Invoke-AuditTargetsCommand @("list") }
            "4" { Invoke-AuditTargetsCommand @("scan") }
            "5" {
                $path = Read-HostSafe "recommendations 文件路径"
                if (-not [string]::IsNullOrWhiteSpace($path)) {
                    Invoke-AuditTargetsCommand @("apply-flow", "--recommendations", $path)
                }
            }
            "6" { Invoke-AuditTargetsCommand @("status") }
            "7" {
                $name = Read-HostSafe "目标仓名称"
                $path = Read-HostSafe "目标仓路径"
                if (-not [string]::IsNullOrWhiteSpace($name) -and -not [string]::IsNullOrWhiteSpace($path)) {
                    Invoke-AuditTargetsCommand @("add", $name, $path)
                }
            }
            "8" {
                $cfg = Load-AuditTargetsConfig
                $targets = @($cfg.targets)
                if ($targets.Count -eq 0) {
                    Write-Host "未登记目标仓。"
                    continue
                }
                $selection = Select-Items $targets `
                { param($idx, $item)
                    $enabled = if ($item.PSObject.Properties.Match("enabled").Count -gt 0) { [bool]$item.enabled } else { $true }
                    $enabledText = if ($enabled) { "enabled" } else { "disabled" }
                    return ("{0,3}) [{1}] {2} -> {3}" -f $idx, $enabledText, [string]$item.name, [string]$item.path)
                } `
                    "请选择要修改的目标仓（输入 0 取消）" `
                    "未解析到有效序号，已取消修改。"
                if ($selection.canceled -or @($selection.items).Count -eq 0) {
                    Write-Host "已取消修改目标仓。"
                    continue
                }
                $name = [string]$selection.items[0].name
                $path = Read-HostSafe "新的目标仓路径"
                if (-not [string]::IsNullOrWhiteSpace($name) -and -not [string]::IsNullOrWhiteSpace($path)) {
                    Invoke-AuditTargetsCommand @("update", $name, $path)
                }
            }
            "9" {
                $cfg = Load-AuditTargetsConfig
                $targets = @($cfg.targets)
                if ($targets.Count -eq 0) {
                    Write-Host "未登记目标仓。"
                    continue
                }
                $selection = Select-Items $targets `
                { param($idx, $item)
                    $enabled = if ($item.PSObject.Properties.Match("enabled").Count -gt 0) { [bool]$item.enabled } else { $true }
                    $enabledText = if ($enabled) { "enabled" } else { "disabled" }
                    return ("{0,3}) [{1}] {2} -> {3}" -f $idx, $enabledText, [string]$item.name, [string]$item.path)
                } `
                    "请选择要删除的目标仓（输入 0 取消）" `
                    "未解析到有效序号，已取消删除。"
                if ($selection.canceled -or @($selection.items).Count -eq 0) {
                    Write-Host "已取消删除目标仓。"
                    continue
                }
                $picked = $selection.items[0]
                $preview = @(
                    ("name: {0}" -f [string]$picked.name),
                    ("path: {0}" -f [string]$picked.path)
                ) -join "`n"
                if (-not (Confirm-WithSummary "将删除以下目标仓" $preview "确认删除该目标仓？" "Y")) {
                    Write-Host "已取消删除目标仓。"
                    continue
                }
                $name = [string]$picked.name
                if (-not [string]::IsNullOrWhiteSpace($name)) {
                    Invoke-AuditTargetsCommand @("remove", $name)
                }
            }
            "10" {
                $defaultPath = Get-AuditStructuredProfileDefaultPath
                $profile = Read-HostSafe ("请输入结构化 profile 文件路径（回车使用默认：{0}）" -f $defaultPath)
                if ([string]::IsNullOrWhiteSpace($profile)) {
                    Invoke-AuditTargetsCommand @("profile-structure")
                }
                else {
                    Invoke-AuditTargetsCommand @("profile-structure", "--profile", $profile)
                }
            }
            "11" { Invoke-AuditTargetsCommand @("init") }
            "12" { Show-AuditOuterAiPromptTemplate }
            "13" { Edit-AuditOuterAiPromptTemplate }
            "14" {
                $path = Read-HostSafe "recommendations 文件路径"
                if (-not [string]::IsNullOrWhiteSpace($path)) {
                    Invoke-AuditTargetsCommand @("apply", "--recommendations", $path, "--apply", "--yes")
                }
            }
            "0" { return }
            default { Write-Host "无效选择。" }
        }
    }
}
```

Also update the main menu label line to:

```powershell
Write-Host "7) 目标仓审查"
```

- [ ] **Step 4: Rebuild and rerun the audit test**

Run:

```powershell
./build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\AuditTargets.Tests.ps1 -TestName 'Documents the renamed audit hub with recommended and advanced actions'"
```

Expected:

```text
Build success: D:\OneDrive\CODE\skills-manager\skills.ps1
PASS Documents the renamed audit hub with recommended and advanced actions
```

- [ ] **Step 5: Commit the audit hub change**

```powershell
git add src/Commands/Utils.ps1 tests/Unit/AuditTargets.Tests.ps1 skills.ps1
git commit -m "feat: reorganize audit hub for expert use"
```

### Task 3: Help Output And README Alignment

**Files:**
- Modify: `tests/Unit/MenuStructure.Tests.ps1`
- Modify: `src/Commands/Utils.ps1`
- Modify: `README.md`
- Modify: `README.en.md`
- Regenerate: `skills.ps1`

- [ ] **Step 1: Extend the menu test file with help-copy assertions**

Append this test to `tests/Unit/MenuStructure.Tests.ps1`:

```powershell
It "Groups help text around the new hub labels" {
    $raw = Get-Content -LiteralPath (Join-Path $Root "src/Commands/Utils.ps1") -Raw
    $raw | Should Match '浏览技能'
    $raw | Should Match '选择安装'
    $raw | Should Match '重建并同步'
    $raw | Should Match '目标仓审查'
    $raw | Should Match 'MCP 服务'
    $raw | Should Match '技能库管理'
    $raw | Should Match '更多'
}
```

- [ ] **Step 2: Run the menu test file and verify the help assertion fails**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\MenuStructure.Tests.ps1"
```

Expected:

```text
FAIL because `帮助` still uses `发现` / `命令导入安装` / `构建并生效` and does not mention the new hub names
```

- [ ] **Step 3: Rewrite the `帮助` block to match the new navigation model**

Update the opening part of `function 帮助` so it starts like this:

```powershell
Skills 管理器（中文菜单）

推荐使用顺序：
  1) 浏览技能：查看当前已接入来源中的可用技能
  2) 选择安装 / 粘贴命令导入：把技能加入白名单
  3) 重建并同步：重建 agent/ 并同步到 targets
  4) 更新上游：拉取上游后重建并同步
  5) 目标仓审查：生成审查包并应用建议

菜单分组：
  - MCP 服务：新增、卸载、同步 MCP
  - 技能库管理：新增/删除技能库、生成锁文件、打开配置
  - 更多：一键工作流、自动更新设置、解除关联、清理备份
```

Also update the feature bullets so they use the same new labels:

```powershell
- 浏览技能：列出当前已接入技能库中的可用技能；只查看，不改配置
- 选择安装：从当前来源中勾选技能，写入 mappings 白名单
- 粘贴命令导入：解析 add / npx 命令；支持批量导入并自动构建生效
- 重建并同步：使用当前本地配置重建输出并同步到 targets
- 目标仓审查：维护需求上下文、目标仓列表、审查包生成和建议应用
```

- [ ] **Step 4: Add the new menu terminology to both READMEs**

Add this block near the interactive-menu guidance in `README.md`:

```markdown
交互菜单已按熟手高频动作重排，主菜单优先显示：

- 浏览技能
- 选择安装
- 粘贴命令导入
- 卸载技能
- 重建并同步（CLI 命令仍为 `构建生效`）
- 更新上游（CLI 命令仍为 `更新`）
- 目标仓审查
- MCP 服务
- 技能库管理
- 更多
```

Add this matching block near the interactive-menu guidance in `README.en.md`:

```markdown
The interactive menu is organized around expert-first direct actions. The top level now prioritizes:

- Browse Skills
- Pick Install
- Paste Command Import
- Remove Skills
- Rebuild and Sync (CLI command remains `构建生效`)
- Update Upstream (CLI command remains `更新`)
- Target Repo Audit
- MCP Services
- Skill Library Admin
- More
```

- [ ] **Step 5: Rebuild and rerun the focused menu tests**

Run:

```powershell
./build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\MenuStructure.Tests.ps1"
```

Expected:

```text
Build success: D:\OneDrive\CODE\skills-manager\skills.ps1
PASS Interactive menu structure
```

- [ ] **Step 6: Commit the help and README alignment**

```powershell
git add src/Commands/Utils.ps1 tests/Unit/MenuStructure.Tests.ps1 README.md README.en.md skills.ps1
git commit -m "docs: align menu help and readmes"
```

### Task 4: Workflow Copy Alignment And Final Verification

**Files:**
- Modify: `tests/Unit/Workflow.Tests.ps1`
- Modify: `src/Commands/Workflow.ps1`
- Regenerate: `skills.ps1`

- [ ] **Step 1: Add failing workflow wording assertions**

Add these tests in `tests/Unit/Workflow.Tests.ps1`:

```powershell
It "Uses menu-aligned wording in the workflow catalog" {
    $catalog = Get-WorkflowCatalog
    $catalog.quickstart.steps[0].title | Should Be "浏览技能"
    $catalog.quickstart.steps[1].title | Should Be "选择安装"
    $catalog.quickstart.steps[2].title | Should Be "重建并同步"
    $catalog.maintenance.description | Should Match "重建并同步"
    $catalog.audit.description | Should Match "目标仓审查"
}

It "Uses menu-aligned wording in the interactive workflow picker source" {
    $raw = Get-Content -LiteralPath (Join-Path $Root "src/Commands/Workflow.ps1") -Raw
    $raw | Should Match '1\) 新手（浏览技能 -> 选择安装 -> 重建并同步 -> doctor --strict）'
    $raw | Should Match '2\) 维护（更新上游 -> 重建并同步 -> 同步MCP -> doctor --strict）'
}
```

- [ ] **Step 2: Run the workflow tests and verify they fail**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\Workflow.Tests.ps1"
```

Expected:

```text
FAIL because the catalog still says `发现可用技能`, `交互选择安装`, and `构建并生效`
```

- [ ] **Step 3: Update `src/Commands/Workflow.ps1` wording to match the new menu language**

Make these replacements in `Get-WorkflowCatalog` and `Select-WorkflowProfileInteractively`:

```powershell
description = "从浏览技能到安装、重建并同步、严格检查的一条龙流程。"
title = "浏览技能"
title = "选择安装"
title = "重建并同步"

description = "适合日常维护：更新上游、重建并同步、同步 MCP、严格检查。"
title = "更新上游"
title = "重建并同步"

description = "聚焦目标仓审查：查看需求、生成审查包、回看最近状态。"

Write-Host "1) 新手（浏览技能 -> 选择安装 -> 重建并同步 -> doctor --strict）"
Write-Host "2) 维护（更新上游 -> 重建并同步 -> 同步MCP -> doctor --strict）"
Write-Host "3) 审查（查看需求 -> 目标仓列表 -> 生成审查包 -> 查看最近状态）"
Write-Host "4) 全流程（更新上游 -> 浏览技能 -> 重建并同步 -> 同步MCP -> doctor --strict）"
```

- [ ] **Step 4: Rebuild and rerun the focused test files**

Run:

```powershell
./build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\MenuStructure.Tests.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\AuditTargets.Tests.ps1 -TestName 'Documents the renamed audit hub with recommended and advanced actions'"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\Workflow.Tests.ps1"
```

Expected:

```text
Build success: D:\OneDrive\CODE\skills-manager\skills.ps1
PASS Interactive menu structure
PASS Documents the renamed audit hub with recommended and advanced actions
PASS Workflow command
```

- [ ] **Step 5: Run the full project gates in repository order**

Run:

```powershell
./build.ps1
./skills.ps1 发现
./skills.ps1 doctor --strict --threshold-ms 8000
./skills.ps1 构建生效
```

Expected:

```text
All four commands exit 0
No doctor strict failure
No build/sync failure summary
Generated skills.ps1 stays in sync with src/
```

- [ ] **Step 6: Commit the workflow alignment and verified rollout**

```powershell
git add src/Commands/Workflow.ps1 tests/Unit/Workflow.Tests.ps1 skills.ps1
git commit -m "feat: align workflow copy with menu restructure"
```
