# Enable/Disable Skills Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add CLI commands to temporarily disable/enable installed skills without removing them from configuration, ensuring `agent/` and targets reflect the active state.

**Architecture:** 
- specific entries in `skills.json` mappings will gain a `"disabled": true` property.
- `skills.ps1` build process will filter out disabled mappings.
- New CLI menus `禁用` (Disable) and `启用` (Enable) will toggle this property.

**Tech Stack:** PowerShell

---

### Task 1: Update `skills.ps1` Core Logic

**Files:**
- Modify: `skills.ps1`

**Step 1: Update `构建Agent` to respect disabled status**

Modify `构建Agent` function in `skills.ps1`.
Inside the loop `foreach($m in $cfg.mappings)`, add a check:
```powershell
    if($m.disabled){ continue }
```

**Step 2: Update `Get-InstalledSet` helper**

We need a way to distinguish "installed (mapped)" vs "active (enabled)".
Existing `Get-InstalledSet` returns all mapped items. This is correct for `安装` (we don't want to double-install).
We might need a helper `Get-EnabledSet` or just filter in place for the `禁用` command.

**Step 3: Add `禁用` (Disable) function**

Add a new function `禁用` that:
1. Loads config.
2. Filters `cfg.mappings` for items where `!$_.disabled`.
3. Prompts user to select from these items.
4. Updates selected items: `$item.disabled = $true`.
5. Saves config.
6. Calls `构建生效`.

**Step 4: Add `启用` (Enable) function**

Add a new function `启用` that:
1. Loads config.
2. Filters `cfg.mappings` for items where `$_.disabled`.
3. Prompts user to select from these items.
4. Updates selected items: `$item.disabled = $false` (or remove property).
5. Saves config.
6. Calls `构建生效`.

**Step 5: Update `菜单` and `Cmd` param**

Add the new options to the `ValidateSet` at the top of the script and the `switch` statements in `菜单` and `Main`.

### Task 2: Verification

**Files:**
- Modify: `skills.json` (via script)

**Step 1: Install a test skill (if not present)**
Run `.\skills.ps1 安装` and pick something small if needed, or use existing.

**Step 2: Disable the skill**
Run `.\skills.ps1 禁用` -> select the skill.
Check `skills.json`: should see `"disabled": true`.
Check `agent/`: folder should be gone.

**Step 3: Enable the skill**
Run `.\skills.ps1 启用` -> select the skill.
Check `skills.json`: `"disabled"` should be false or gone.
Check `agent/`: folder should be back.
