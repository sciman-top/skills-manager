. $PSScriptRoot\..\..\skills.ps1

Describe "Hidden skill discovery" {
    It "Discovers skill markers under hidden directories" {
        $root = Join-Path $env:TEMP ("skills-manager-hidden-test-" + [Guid]::NewGuid().ToString("N"))
        $curated = Join-Path $root ".curated"
        $skillDir = Join-Path $curated "demo-skill"
        $skillFile = Join-Path $skillDir "SKILL.md"

        try {
            New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
            @"
---
name: demo-skill
description: demo
---
"@ | Set-Content -LiteralPath $skillFile -Encoding UTF8

            $curatedItem = Get-Item -LiteralPath $curated -Force
            $curatedItem.Attributes = ($curatedItem.Attributes -bor [System.IO.FileAttributes]::Hidden)

            $script:SkillListCache = @{}
            $items = Get-SkillsUnder $root "skills"
            ($items | Where-Object { $_.from -eq ".curated\demo-skill" }).Count | Should Be 1
        }
        finally {
            if (Test-Path -LiteralPath $root) {
                Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    try { $_.Attributes = [System.IO.FileAttributes]::Normal } catch {}
                }
                try {
                    (Get-Item -LiteralPath $root -Force).Attributes = [System.IO.FileAttributes]::Directory
                }
                catch {}
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
