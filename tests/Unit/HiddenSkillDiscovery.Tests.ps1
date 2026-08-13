BeforeAll {
    . $PSScriptRoot\..\..\skills.ps1

}
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
            $rawMarkers = @(Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { -not $_.PSIsContainer -and $_.Name -match "^(SKILL|AGENTS|GEMINI|CLAUDE)\.md$" })
            $items = @(Get-SkillsUnder $root "skills")
            $matchingItems = @($items | Where-Object { $_.from -eq ".curated\demo-skill" })
            if ($matchingItems.Count -ne 1) {
                $rawSummary = @($rawMarkers | ForEach-Object { $_.FullName }) -join "; "
                $itemSummary = @($items | ForEach-Object { "from=$($_.from); full=$($_.full)" }) -join "; "
                Write-Host ("Hidden discovery diagnostics: attributes={0}; raw=[{1}]; items=[{2}]" -f
                    (Get-Item -LiteralPath $curated -Force).Attributes,
                    $rawSummary,
                    $itemSummary)
            }

            (((Get-Item -LiteralPath $curated -Force).Attributes -band [System.IO.FileAttributes]::Hidden) -ne 0) | Should -Be $true
            $matchingItems.Count | Should -Be 1
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

    It "Normalizes aliased base paths before calculating relative skill paths" {
        $root = Join-Path $env:TEMP ("skills-manager-base-alias-test-" + [Guid]::NewGuid().ToString("N"))
        $aliasParent = Join-Path $root "alias-parent"
        $actualBase = Join-Path $root "skill-root"
        $skillDir = Join-Path $actualBase ".curated\demo-skill"
        $skillFile = Join-Path $skillDir "SKILL.md"

        try {
            New-Item -ItemType Directory -Path $aliasParent -Force | Out-Null
            New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
            Set-Content -LiteralPath $skillFile -Value "---`nname: demo-skill`ndescription: demo`n---" -Encoding UTF8

            $aliasedBase = Join-Path $aliasParent "..\skill-root"
            $script:SkillListCache = @{}
            $items = @(Get-SkillsUnder $aliasedBase "skills")

            @($items | Where-Object { $_.from -eq ".curated\demo-skill" }).Count | Should -Be 1
        }
        finally {
            if (Test-Path -LiteralPath $root) {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
