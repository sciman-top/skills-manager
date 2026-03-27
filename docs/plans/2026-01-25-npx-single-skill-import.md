# Npx-Compatible Single Skill Import Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add npx-style single-skill import (with sparse-checkout option) that installs into manual/ and updates cleanly.

**Architecture:** Extend `skills.ps1` with argument parsing for `add`/`npx`, import logic that clones to a cache and mirrors only the chosen skill into `manual/`, and update flow to refresh imports. Persist import metadata in `skills.json` for repeatable updates.

**Tech Stack:** PowerShell 5.1+, Git, robocopy

---

### Task 1: Extend config schema for imports

**Files:**
- Modify: `skills.json`
- Modify: `skills.ps1`

**Step 1: Add default imports structure**

```powershell
# In Normalize-Cfg
if($cfg.imports -eq $null){ $cfg | Add-Member -NotePropertyName imports -NotePropertyValue @() }
```

**Step 2: Add validation for imports**

```powershell
Need (Assert-IsArray $cfg.imports) "skills.json 的 imports 必须是数组"
foreach($i in $cfg.imports){
  Need (-not [string]::IsNullOrWhiteSpace($i.name)) "import 缺少 name"
  Need (-not [string]::IsNullOrWhiteSpace($i.repo)) "import 缺少 repo"
}
```

**Step 3: Add imports to `skills.json`**

```json
"imports": []
```

**Step 4: Manual validation**

Run: `.
\skills.ps1 发现`
Expected: Script loads without JSON validation errors.

---

### Task 2: Add add/npx command parsing and import logic

**Files:**
- Modify: `skills.ps1`

**Step 1: Add helpers for argument parsing**

```powershell
function Split-Args([string]$line) { ... }
function Parse-AddArgs([string[]]$tokens) { ... }
function Get-AddTokensFromNpx([string[]]$tokens) { ... }
```

**Step 2: Add git clone/update helpers**

```powershell
function Clone-Repo(...) { ... }
function Update-Repo(...) { ... }
```

**Step 3: Implement Add-ImportManual**

```powershell
function Add-ImportManual($args) { ... }
```

**Step 4: Wire commands**

```powershell
switch($Cmd){
  "add" { Add-FromArgs }
  "npx" { Npx-Add }
}
```

**Step 5: Manual validation**

Run (example):
- `.
\skills.ps1 add https://github.com/adithya-s-k/manim_skill --skill manim-composerd`
Expected: manual/manim-composerd populated, imports updated.

---

### Task 3: Update update flow to refresh imports

**Files:**
- Modify: `skills.ps1`

**Step 1: Add UpdateImports**

```powershell
function UpdateImports { ... }
```

**Step 2: Call UpdateImports in 更新**

```powershell
function 更新 { UpdateImports; 更新Vendor; 构建生效 }
```

**Step 3: Manual validation**

Run: `.
\skills.ps1 更新`
Expected: imports refreshed then build completes.

---

### Task 4: Documentation updates

**Files:**
- Modify: `README.md`
- Modify: `skills.ps1` (帮助)

**Step 1: Add README usage examples**

```markdown
.
\skills.ps1 add <repo> --skill <name> [--ref <branch/tag>] [--sparse]
.
\skills.ps1 npx "skills add <repo> --skill <name>"
```

**Step 2: Update 帮助 text**

Include the new commands and flags.

**Step 3: Manual validation**

Run: `.
\skills.ps1 帮助`
Expected: help output includes add/npx examples.

---

### Task 5: Final verification sweep

**Files:**
- None

**Step 1: JSON lint (optional)**

Run: `powershell -NoProfile -Command "Get-Content skills.json -Raw | ConvertFrom-Json | Out-Null"`
Expected: no errors.

**Step 2: Smoke test build**

Run: `.
\skills.ps1 构建生效`
Expected: build completes without errors.

**Step 3: Commit (optional)**

```bash
git add skills.ps1 skills.json README.md
git commit -m "feat: add npx-style single skill import"
```
