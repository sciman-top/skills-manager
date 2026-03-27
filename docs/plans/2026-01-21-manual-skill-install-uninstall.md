# Manual Skill Source + Install/Uninstall Split Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a local `manual/` skill source that syncs into Claude/Codex without new config, and split install/uninstall into separate filtered menus.

**Architecture:** Extend the skill discovery/build pipeline to include a virtual "manual" vendor rooted at `manual/`. Keep `skills.json` schema unchanged by handling manual paths in code and treating manual mappings as a special vendor during build and selection.

**Tech Stack:** PowerShell 5.1, JSON config (`skills.json`)

---

### Task 1: Add manual source constants and validation

**Files:**
- Modify: `skills.ps1`

**Step 1: Write the failing test**

```powershell
# Pseudo-checklist for manual dir integration:
# - manual/ exists or is created by Preflight
# - manual skills are discoverable (SKILL.md)
# - manual vendor can be resolved during build
```

**Step 2: Run test to verify it fails**

Run: (manual checklist; no automated tests)
Expected: Manual skills not discoverable, build fails for vendor "manual"

**Step 3: Write minimal implementation**

```powershell
$ManualDir = Join-Path $Root "manual"

function Preflight {
  ...
  EnsureDir $ManualDir
}
```

**Step 4: Run test to verify it passes**

Run: `.\skills.ps1 发现`
Expected: manual/ skills appear once implemented in later tasks

**Step 5: Commit**

```bash
git add skills.ps1
git commit -m "feat: add manual skills root"
```

---

### Task 2: Discover skills from manual/ and vendors

**Files:**
- Modify: `skills.ps1`

**Step 1: Write the failing test**

```powershell
# checklist: 收集Skills should include manual/ SKILL.md as vendor "manual"
# with from path relative to manual/
```

**Step 2: Run test to verify it fails**

Run: `.\skills.ps1 发现`
Expected: manual/ skills still missing

**Step 3: Write minimal implementation**

```powershell
function 收集Skills([string]$filter) {
  $cfg = LoadCfg
  $items = @()

  foreach($v in $cfg.vendors){ ... } # existing

  # manual/ skills
  if(Test-Path $ManualDir){
    $found = Get-ChildItem $ManualDir -Recurse -Filter SKILL.md -ErrorAction SilentlyContinue
    foreach($f in $found){
      $dir = $f.Directory.FullName
      $rel = $dir.Substring($ManualDir.Length).TrimStart("\\")
      $items += [pscustomobject]@{ vendor="manual"; from=$rel; full=$dir }
    }
  }
  ...
}
```

**Step 4: Run test to verify it passes**

Run: `.\skills.ps1 发现`
Expected: manual skills listed with vendor `manual`

**Step 5: Commit**

```bash
git add skills.ps1
git commit -m "feat: discover manual skills"
```

---

### Task 3: Resolve manual vendor during build

**Files:**
- Modify: `skills.ps1`

**Step 1: Write the failing test**

```powershell
# checklist: mappings with vendor "manual" build from manual/ paths
```

**Step 2: Run test to verify it fails**

Run: `.\skills.ps1 构建生效`
Expected: fails with "不存在的 vendor"

**Step 3: Write minimal implementation**

```powershell
function Resolve-SourceBase([string]$vendorName, $cfg) {
  if($vendorName -eq "manual"){ return $ManualDir }
  $v = $cfg.vendors | Where-Object { $_.name -eq $vendorName } | Select-Object -First 1
  if(-not $v){ throw "白名单引用了不存在的 vendor：$vendorName" }
  return (VendorPath $v.name)
}

# In 构建Agent:
$base = Resolve-SourceBase $m.vendor $cfg
$src = Join-Path $base $m.from
```

**Step 4: Run test to verify it passes**

Run: `.\skills.ps1 构建生效`
Expected: manual skills mirror into `agent/` then sync to targets

**Step 5: Commit**

```bash
git add skills.ps1
git commit -m "feat: build manual skills"
```

---

### Task 4: Split install/uninstall menus with filtered lists

**Files:**
- Modify: `skills.ps1`

**Step 1: Write the failing test**

```powershell
# checklist: Install shows only not-installed
# Uninstall shows only installed
# No color distinction in these lists
```

**Step 2: Run test to verify it fails**

Run: `.\skills.ps1 menu`
Expected: only unified "选择" exists

**Step 3: Write minimal implementation**

```powershell
function 安装 {
  Preflight
  $filter = Read-Host "可选：输入关键词过滤（留空表示不过滤）"
  $list = 收集Skills $filter
  $cfg = LoadCfg
  $installed = New-Object System.Collections.Generic.HashSet[string]
  foreach($m in $cfg.mappings){ $installed.Add("$($m.vendor)|$($m.from)") | Out-Null }

  $available = $list | Where-Object { -not $installed.Contains("$($_.vendor)|$($_.from)") }
  # render without colors and without installed mark
  # select indices -> append to mappings (merge with existing)
}

function 卸载 {
  Preflight
  $filter = Read-Host "可选：输入关键词过滤（留空表示不过滤）"
  $list = 收集Skills $filter
  $cfg = LoadCfg
  $installed = New-Object System.Collections.Generic.HashSet[string]
  foreach($m in $cfg.mappings){ $installed.Add("$($m.vendor)|$($m.from)") | Out-Null }

  $onlyInstalled = $list | Where-Object { $installed.Contains("$($_.vendor)|$($_.from)") }
  # render without colors and without installed mark
  # select indices -> remove from mappings
}
```

**Step 4: Run test to verify it passes**

Run: `.\skills.ps1 menu`
Expected: separate 安装/卸载 entries; install list excludes installed; uninstall list shows only installed; no color

**Step 5: Commit**

```bash
git add skills.ps1
git commit -m "feat: split install/uninstall menus"
```

---

### Task 5: Update help text and command routing

**Files:**
- Modify: `skills.ps1`

**Step 1: Write the failing test**

```powershell
# checklist: help/menu mention manual/ source and install/uninstall split
```

**Step 2: Run test to verify it fails**

Run: `.\skills.ps1 帮助`
Expected: old unified wording

**Step 3: Write minimal implementation**

```powershell
# Update "帮助" text and menu options to use 安装/卸载
# Update ValidateSet/Cmd switch to include "安装","卸载"
```

**Step 4: Run test to verify it passes**

Run: `.\skills.ps1 帮助`
Expected: mentions manual/ and split operations

**Step 5: Commit**

```bash
git add skills.ps1
git commit -m "docs: update help for manual install/uninstall"
```

