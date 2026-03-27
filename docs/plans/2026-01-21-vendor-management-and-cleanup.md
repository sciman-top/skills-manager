# Vendor Management and Cleanup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add vendor add/remove flows to the menu (rename 初始化), add cleanup for invalid mappings, and enhance install filtering, while removing the "打开配置" menu entry.

**Architecture:** Introduce vendor CRUD helpers that safely update `skills.json` with rollback on failure, reuse existing config validation, and add user-facing commands for cleanup and filtering. Keep the JSON schema unchanged; implement all behaviors in `skills.ps1` and update README/help/menu strings accordingly.

**Tech Stack:** PowerShell 5.1, JSON config (`skills.json`)

---

### Task 1: Add vendor add/remove flows and rename 初始化

**Files:**
- Modify: `skills.ps1`
- Modify: `README.md`

**Step 1: Write the failing test**

```powershell
# Manual checklist:
# - 菜单“新增技能库”存在并替代“初始化”
# - 新增流程提示输入 URL/可选分支(ref)/可选 name
# - 成功时写入 skills.json 并自动初始化
# - 失败时不污染 skills.json（回滚或先验证后写入）
# - 菜单包含“删除技能库”，可选择现有 vendor 删除
# - 删除后自动更新 vendor 目录并不崩溃
# - 菜单中移除“打开配置文件”
```

**Step 2: Run test to verify it fails**

Run: `.\skills.ps1 menu`
Expected: 仍显示初始化/打开配置，且无新增/删除技能库流程

**Step 3: Write minimal implementation**

```powershell
# Add helpers
function SaveCfgSafe($cfg) { $cfg | ConvertTo-Json -Depth 50 | Set-Content -Encoding UTF8 $CfgPath }
function CloneVendorTemp($repo, $ref, $name) { 
  $tmp = Join-Path $VendorDir ("_tmp_" + $name)
  if(Test-Path $tmp){ Remove-Item -Recurse -Force $tmp }
  Exec ("git clone {0} `"{1}`"" -f $repo, $tmp)
  Push-Location $tmp; Exec ("git checkout {0}" -f $ref); Pop-Location
  return $tmp
}
function FinalizeVendorDir($tmp, $name) {
  $dst = VendorPath $name
  if(Test-Path $dst){ throw "vendor 已存在：$name" }
  Move-Item -Force $tmp $dst
}

# 新增技能库 (renamed 初始化)
function 新增技能库 {
  Preflight
  $repo = Read-Host "请输入技能库地址 (git URL)"
  Need (-not [string]::IsNullOrWhiteSpace($repo)) "技能库地址不能为空"
  $ref = Read-Host "可选：输入分支/Tag（留空默认 main）"
  if([string]::IsNullOrWhiteSpace($ref)){ $ref = "main" }
  $name = Read-Host "可选：输入自定义名称（留空自动从 URL 推断）"
  if([string]::IsNullOrWhiteSpace($name)){ $name = (Split-Path ($repo.TrimEnd('/').Replace('.git','')) -Leaf) }
  # 先 clone 到临时目录，成功再写入 skills.json 并移动
  $tmp = $null
  try {
    $tmp = CloneVendorTemp $repo $ref $name
    $cfg = LoadCfg
    if($cfg.vendors | Where-Object { $_.name -eq $name }) { throw "vendor 名称已存在：$name" }
    $cfg.vendors += @{ name=$name; repo=$repo; ref=$ref }
    SaveCfgSafe $cfg
    FinalizeVendorDir $tmp $name
  } catch {
    if($tmp -and (Test-Path $tmp)){ Remove-Item -Recurse -Force $tmp }
    throw
  }
  Write-Host "新增完成。"
}

# 删除技能库
function 删除技能库 {
  Preflight
  $cfg = LoadCfg
  Need ($cfg.vendors.Count -gt 0) "当前没有可删除的技能库。"
  # 列表选择并删除 vendor + 删除对应 vendor/ 目录
}
```

**Step 4: Run test to verify it passes**

Run: `.\skills.ps1 menu` then try add/remove with a test URL
Expected: 菜单更新，新增成功会写入并初始化；失败不会污染 skills.json

**Step 5: Commit**

```bash
git add skills.ps1 README.md
git commit -m "feat: add vendor add/remove flows"
```

---

### Task 2: Add “清理无效映射” command

**Files:**
- Modify: `skills.ps1`
- Modify: `README.md`

**Step 1: Write the failing test**

```powershell
# Manual checklist:
# - 命令“清理无效映射”可执行
# - 自动检测无 SKILL.md 或 vendor 不存在的 mapping 并移除
# - 提示移除数量并可继续构建
```

**Step 2: Run test to verify it fails**

Run: `.\skills.ps1 清理无效映射`
Expected: command not found

**Step 3: Write minimal implementation**

```powershell
function 清理无效映射 {
  Preflight
  $cfg = LoadCfg
  $valid = @()
  $removed = 0
  foreach($m in $cfg.mappings){
    try {
      $base = Resolve-SourceBase $m.vendor $cfg
      $src = Join-Path $base $m.from
      if(Test-Path (Join-Path $src "SKILL.md")) { $valid += $m } else { $removed++ }
    } catch { $removed++ }
  }
  $cfg.mappings = $valid
  SaveCfg $cfg
  Write-Host ("已清理无效映射：{0} 项。" -f $removed)
}
```

**Step 4: Run test to verify it passes**

Run: `.\skills.ps1 清理无效映射`
Expected: 输出清理数量

**Step 5: Commit**

```bash
git add skills.ps1 README.md
git commit -m "feat: add mapping cleanup command"
```

---

### Task 3: Enhance install/uninstall filtering

**Files:**
- Modify: `skills.ps1`

**Step 1: Write the failing test**

```powershell
# Manual checklist:
# - 支持多关键词过滤（空格分隔）
# - 可选正则模式（例如以 /regex/ 前缀触发）
```

**Step 2: Run test to verify it fails**

Run: enter "docx pdf" filter
Expected: current filter treats as literal string, not AND search

**Step 3: Write minimal implementation**

```powershell
function Filter-Skills($items, [string]$filter) {
  if([string]::IsNullOrWhiteSpace($filter)){ return $items }
  $f = $filter.Trim()
  if($f.StartsWith("/")){
    $pattern = $f.Trim("/")
    return $items | Where-Object { $_.vendor -match $pattern -or $_.from -match $pattern }
  }
  $terms = $f.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
  foreach($t in $terms){
    $items = $items | Where-Object { $_.vendor -like "*$t*" -or $_.from -like "*$t*" }
  }
  return $items
}
```

**Step 4: Run test to verify it passes**

Run: filter "docx pdf" and "/docx|pdf/"
Expected: results match AND/regex behavior

**Step 5: Commit**

```bash
git add skills.ps1
git commit -m "feat: improve skill filtering"
```

---

### Task 4: Update menu/help/README for new commands

**Files:**
- Modify: `skills.ps1`
- Modify: `README.md`

**Step 1: Write the failing test**

```powershell
# Manual checklist:
# - menu shows 新增技能库 / 删除技能库 / 清理无效映射
# - 帮助与 README 说明新增功能与流程
# - 删除“打开配置文件”入口
```

**Step 2: Run test to verify it fails**

Run: `.\skills.ps1 帮助`
Expected: still shows old menu/flow

**Step 3: Write minimal implementation**

```powershell
# Update menu entries, help text, README sections and quickstart.
# Mention filtering syntax and vendor add/remove flows.
```

**Step 4: Run test to verify it passes**

Run: `.\skills.ps1 帮助`
Expected: updated documentation

**Step 5: Commit**

```bash
git add skills.ps1 README.md
git commit -m "docs: update help and README for vendor management"
```

