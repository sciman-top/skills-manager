# Skills Manager Audit & Optimization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix reliability/UX issues in `skills.ps1`, simplify selection logic, and add practical discovery/diagnostics while keeping the project minimal.

**Architecture:** Centralize config validation and UI list rendering, add safe naming to avoid mapping collisions, and introduce lightweight discovery/status commands. Keep the build pipeline intact and update help/README to match the actual menu flow.

**Tech Stack:** PowerShell 5.1, JSON config (`skills.json`)

---

### Task 1: Add config validation + normalization

**Files:**
- Modify: `skills.ps1`

**Step 1: Write the failing test**

```powershell
# Manual checklist:
# - vendors must be an array of objects with name/repo
# - targets must be an array of objects with path
# - mappings must be an array of objects with vendor/from/to
# - helpful error messages on bad schema
```

**Step 2: Run test to verify it fails**

Run: edit a temporary copy of `skills.json` to make `targets` a string, then run `.\skills.ps1 构建生效`
Expected: current script throws unclear errors or fails later

**Step 3: Write minimal implementation**

```powershell
function Normalize-Cfg($cfg) {
  if($cfg.mappings -eq $null){ $cfg | Add-Member -NotePropertyName mappings -NotePropertyValue @() }
  if([string]::IsNullOrWhiteSpace($cfg.sync_mode)){ $cfg.sync_mode = "link" }
  return $cfg
}

function Assert-Cfg($cfg) {
  Need ($cfg.vendors -is [System.Collections.IEnumerable]) "skills.json 的 vendors 必须是数组"
  Need ($cfg.targets -is [System.Collections.IEnumerable]) "skills.json 的 targets 必须是数组"
  foreach($v in $cfg.vendors){
    Need (-not [string]::IsNullOrWhiteSpace($v.name)) "vendor 缺少 name"
    Need (-not [string]::IsNullOrWhiteSpace($v.repo)) "vendor $($v.name) 缺少 repo"
  }
  foreach($t in $cfg.targets){
    Need (-not [string]::IsNullOrWhiteSpace($t.path)) "target 缺少 path"
  }
  foreach($m in $cfg.mappings){
    Need (-not [string]::IsNullOrWhiteSpace($m.vendor)) "mapping 缺少 vendor"
    Need (-not [string]::IsNullOrWhiteSpace($m.from)) "mapping 缺少 from"
    Need (-not [string]::IsNullOrWhiteSpace($m.to)) "mapping 缺少 to"
  }
}

function LoadCfg() {
  Need (Test-Path $CfgPath) "缺少配置文件：$CfgPath"
  $cfg = Get-Content $CfgPath -Raw | ConvertFrom-Json
  Need ($cfg.vendors -ne $null) "skills.json 缺少 vendors"
  Need ($cfg.targets -ne $null) "skills.json 缺少 targets"
  $cfg = Normalize-Cfg $cfg
  Assert-Cfg $cfg
  return $cfg
}
```

**Step 4: Run test to verify it passes**

Run: restore `skills.json` and run `.\skills.ps1 构建生效`
Expected: normal build flow; invalid configs now fail with clear messages

**Step 5: Commit**

```bash
git add skills.ps1
git commit -m "feat: validate and normalize skills config"
```

---

### Task 2: Fix mapping name collisions and centralize mapping naming

**Files:**
- Modify: `skills.ps1`

**Step 1: Write the failing test**

```powershell
# Manual checklist:
# - Two skills with same leaf name under same vendor should get unique "to"
# - "to" should be stable and readable
```

**Step 2: Run test to verify it fails**

Run: in install list, pick two skills with identical leaf names under same vendor
Expected: current logic maps both to "<vendor>-<leaf>", causing collisions

**Step 3: Write minimal implementation**

```powershell
function Make-TargetName([string]$vendor, [string]$from) {
  $suffix = ($from -replace "[\\\\/]", "-")
  return "{0}-{1}" -f $vendor, $suffix
}

# In 安装:
$to = Make-TargetName $item.vendor $item.from
```

**Step 4: Run test to verify it passes**

Run: select two same-leaf skills
Expected: distinct `to` names in `skills.json`

**Step 5: Commit**

```bash
git add skills.ps1
git commit -m "fix: avoid mapping name collisions"
```

---

### Task 3: Improve robocopy error handling

**Files:**
- Modify: `skills.ps1`

**Step 1: Write the failing test**

```powershell
# Manual checklist:
# - robocopy errors (exit code >= 8) should stop the script
# - success codes (0-7) should continue
```

**Step 2: Run test to verify it fails**

Run: point `skills.json` mapping to a missing folder and run `.\skills.ps1 构建生效`
Expected: current script continues despite robocopy failure

**Step 3: Write minimal implementation**

```powershell
function RoboMirror([string]$src, [string]$dst) {
  EnsureDir $dst
  & robocopy $src $dst /MIR /NFL /NDL /NJH /NJS /NP | Out-Host
  if($LASTEXITCODE -ge 8){ throw "robocopy 失败（exit=$LASTEXITCODE）：$src -> $dst" }
}
```

**Step 4: Run test to verify it passes**

Run: repeat missing-folder case
Expected: script stops with clear robocopy error

**Step 5: Commit**

```bash
git add skills.ps1
git commit -m "fix: fail on robocopy errors"
```

---

### Task 4: Add "发现" and "状态" commands + shared list rendering

**Files:**
- Modify: `skills.ps1`

**Step 1: Write the failing test**

```powershell
# Manual checklist:
# - `.\skills.ps1 发现` lists all skills with installed marker
# - `.\skills.ps1 状态` shows sync mode, target paths, counts, and invalid mappings
# - install/uninstall use the same list rendering helper
```

**Step 2: Run test to verify it fails**

Run: `.\skills.ps1 发现`
Expected: command not found

**Step 3: Write minimal implementation**

```powershell
function Write-ItemsInColumns($items, [scriptblock]$formatter) {
  $count = $items.Count
  if($count -eq 0){ return }
  $width = (try { [int]$Host.UI.RawUI.WindowSize.Width } catch { 120 })
  $sample = @()
  for($i=0; $i -lt $count; $i++){
    $sample += (& $formatter ($i+1) $items[$i])
  }
  $maxLen = ($sample | Measure-Object -Maximum -Property Length).Maximum
  if(-not $maxLen){ $maxLen = 40 }
  $colWidth = $maxLen + 2
  $cols = [Math]::Max(1, [Math]::Floor($width / $colWidth))
  $rows = [Math]::Ceiling($count / $cols)
  for($r=0; $r -lt $rows; $r++){
    for($c=0; $c -lt $cols; $c++){
      $i = $r + ($c * $rows)
      if($i -ge $count){ continue }
      $text = (& $formatter ($i+1) $items[$i])
      $pad = " " * ($colWidth - $text.Length)
      Write-Host -NoNewline ($text + $pad)
    }
    Write-Host ""
  }
}

function 发现 {
  Preflight
  $filter = Read-Host "可选：输入关键词过滤（留空表示不过滤）"
  $list = 收集Skills $filter
  $cfg = LoadCfg
  $installed = Get-InstalledSet $cfg
  Write-ItemsInColumns $list { param($idx,$item)
    $mark = if($installed.Contains("$($item.vendor)|$($item.from)")){"*"}else{" "}
    return ("{0,3}) [{1}] {2} :: {3}" -f $idx, $mark, $item.vendor, $item.from)
  }
}

function 状态 {
  Preflight
  $cfg = LoadCfg
  $list = 收集Skills ""
  $installed = Get-InstalledSet $cfg
  $total = $list.Count
  $mapped = $cfg.mappings.Count
  Write-Host ("sync_mode: {0}" -f $cfg.sync_mode)
  Write-Host ("vendors: {0}  mappings: {1}  discovered: {2}" -f $cfg.vendors.Count, $mapped, $total)
  Write-Host "targets:"
  foreach($t in $cfg.targets){ Write-Host ("  - {0}" -f $t.path) }
}
```

**Step 4: Run test to verify it passes**

Run: `.\skills.ps1 发现` and `.\skills.ps1 状态`
Expected: lists and summary appear; install/uninstall still work

**Step 5: Commit**

```bash
git add skills.ps1
git commit -m "feat: add discover and status commands"
```

---

### Task 5: Update menu/help text and README to match behavior

**Files:**
- Modify: `skills.ps1`
- Modify: `README.md`

**Step 1: Write the failing test**

```powershell
# Manual checklist:
# - menu includes 发现/状态
# - 帮助/README no longer mention "选择" as the main flow
# - "构建并生效" description is accurate
```

**Step 2: Run test to verify it fails**

Run: `.\skills.ps1 帮助`
Expected: current text still references old flow

**Step 3: Write minimal implementation**

```powershell
# Update menu labels and help text.
# Update README quickstart flow to 初始化 -> 发现 -> 安装 -> 构建并生效 (or 安装 already triggers build).
```

**Step 4: Run test to verify it passes**

Run: `.\skills.ps1 帮助`
Expected: updated text matches menu and behavior

**Step 5: Commit**

```bash
git add README.md skills.ps1
git commit -m "docs: align help and README with new commands"
```

