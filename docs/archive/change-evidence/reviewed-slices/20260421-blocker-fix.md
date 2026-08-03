# 2026-04-21 Blocker Fix Evidence

- Rule ID: R1/R2/R6/R8
- Risk Level: Medium (config + test fixture encoding)

## Basis

- Blocker 1: `tests/Unit/GeneratedSyncScript.Tests.ps1` failed due script parsing/encoding issue in `tests/check-generated-sync.ps1`.
- Blocker 2: `./skills.ps1 构建生效` failed on `manual/*` mappings with `manual 导入不存在或无效`.

## Commands

1. `./build.ps1`
2. `./skills.ps1 发现`
3. `./skills.ps1 doctor --strict --threshold-ms 8000`
4. `./skills.ps1 构建生效`
5. `powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module Pester; Invoke-Pester -Script tests\Unit\GeneratedSyncScript.Tests.ps1"`

## Key Output

- `Build success: ...\skills.ps1`
- `发现` 输出 3 项 workspace 技能：`openpyxl / python-docx / python-pptx`
- `doctor --strict` 通过（exit code 0）
- `构建生效` 通过（exit code 0），构建摘要 `mappings=63，imports(manual)=3`
- Pester: `Passed: 3 Failed: 0`

## Changes

- `tests/check-generated-sync.ps1`
  - 以 UTF-8 BOM 重写，修复 Windows PowerShell 解析乱码导致的测试失败。
- `skills.json`
  - 删除 28 个不可解析的 `manual` 映射，仅保留当前可解析映射：
    - `openpyxl`
    - `python-docx`
    - `python-pptx`

## Rollback

1. `git restore --source=HEAD~1 -- tests/check-generated-sync.ps1 skills.json`（按需替换为目标提交）
2. 重新执行：
   - `./build.ps1`
   - `./skills.ps1 doctor --strict --threshold-ms 8000`
   - `./skills.ps1 构建生效`
