BeforeAll {
    $ErrorActionPreference = "Stop"
}

Describe "Build script" {
    It "Emits the thin entry and per-source lib files for <Ending> sources" -ForEach @(
        @{ Ending = 'LF'; Newline = "`n" }, @{ Ending = 'CRLF'; Newline = "`r`n" }
    ) {
        $workspace = Join-Path $TestDrive "build-script-$Ending"
        $srcRoot = Join-Path $workspace "src"
        $commandsRoot = Join-Path $srcRoot "Commands"
        New-Item -ItemType Directory -Path $commandsRoot -Force | Out-Null

        $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $buildPath = Join-Path $repoRoot "build.ps1"
        Copy-Item -LiteralPath $buildPath -Destination (Join-Path $workspace "build.ps1")

        $buildRaw = Get-Content -LiteralPath $buildPath -Raw
        # 只从 $Files 清单块提取，避免正文里重复出现的文件名字面量混入。
        $filesBlockStart = $buildRaw.IndexOf('$Files = @(')
        $filesBlockEnd = $buildRaw.IndexOf(')', $filesBlockStart)
        $files = @(
            [regex]::Matches($buildRaw.Substring($filesBlockStart, $filesBlockEnd - $filesBlockStart), '"([^"]+\.ps1)"') |
                ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
        $files = @($files | Where-Object { $_ -ne "skills.ps1" })

        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        $contents = @{}
        for ($i = 0; $i -lt $files.Count; $i++) {
            $relativePath = $files[$i]
            $content = "# chunk-$i${Newline}chunk-$i"
            if ($relativePath -in @('Infrastructure/AtomicFile.ps1', 'Application/HostRegistry.ps1', 'Application/GlobalRuleProjection.ps1')) {
                $content = [IO.File]::ReadAllText((Join-Path $repoRoot "src/$relativePath")).Replace("`r`n", "`n").Replace("`n", $Newline)
            }
            $contents[$relativePath] = $content.Replace("`r`n", "`n").Replace("`n", "`r`n")

            $filePath = Join-Path $srcRoot $relativePath
            $parent = Split-Path $filePath -Parent
            if (-not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            [System.IO.File]::WriteAllText($filePath, $content, $utf8NoBom)
        }

        Copy-Item -LiteralPath (Join-Path $repoRoot 'rules') -Destination $workspace -Recurse
        & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $workspace "build.ps1") | Out-Null
        $LASTEXITCODE | Should -Be 0

        $crlf = { param([string]$Text) $Text.Replace("`r`n", "`n").Replace("`n", "`r`n") }

        # 薄入口：Version 开头、Main 结尾、惰性加载器居中（mock 无 switch -> 空计划表）。
        $thin = [IO.File]::ReadAllText((Join-Path $workspace "skills.ps1"))
        $versionPart = & $crlf ($contents['Version.ps1'] + "`r`n")
        $mainPart = & $crlf ($contents['Main.ps1'])
        $thin | Should -Match ([regex]::Escape('SkillsLibPackPlan'))
        $thin | Should -Match ([regex]::Escape("Join-Path `$PSScriptRoot 'skills.lib'"))
        $thin.StartsWith($versionPart, [StringComparison]::Ordinal) | Should -BeTrue
        $thin.EndsWith($mainPart, [StringComparison]::Ordinal) | Should -BeTrue

        # 库文件：每个非薄入口源文件 1:1 落盘（规范化换行 + BOM）。
        $libDir = Join-Path $workspace "skills.lib"
        $libFiles = @(Get-ChildItem -LiteralPath $libDir -File -Filter '*.ps1' | ForEach-Object Name | Sort-Object)
        $expectedLibs = @($files | Where-Object { $_ -notin @('Version.ps1', 'Main.ps1') } | ForEach-Object { $_.Replace('/', '.') } | Sort-Object)
        $libFiles | Should -Be $expectedLibs
        $bom = [byte[]](0xEF, 0xBB, 0xBF)
        foreach ($relativePath in @($files | Where-Object { $_ -notin @('Version.ps1', 'Main.ps1') })) {
            $libPath = Join-Path $libDir ($relativePath.Replace('/', '.'))
            $libBytes = [IO.File]::ReadAllBytes($libPath)
            @($libBytes[0..2]) | Should -Be $bom
            ([Text.Encoding]::UTF8.GetString($libBytes)).TrimStart([char]0xFEFF) | Should -Be (& $crlf $contents[$relativePath])
        }

        & pwsh -NoProfile -File (Join-Path $workspace "build.ps1") -Check | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It "Keeps the generated pack plan a total function over the CLI ValidateSet" {
        $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $thin = Get-Content -LiteralPath (Join-Path $repoRoot 'skills.ps1') -Raw
        $validateSetLine = @($thin -split "`r?`n" | Where-Object { $_ -match '^\s*\[ValidateSet\(' })[0]
        $labels = [regex]::Matches($validateSetLine, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
        ($labels.Count -gt 50) | Should -BeTrue
        foreach ($label in $labels) {
            $thin | Should -Match ("'{0}' = @\(" -f [regex]::Escape($label))
        }
        # 计划引用的每个库文件都必须真实存在；基础清单同理。
        $libDir = Join-Path $repoRoot 'skills.lib'
        foreach ($m in [regex]::Matches($thin, "'[^']+\.ps1'")) {
            $name = $m.Value.Trim("'")
            (Test-Path -LiteralPath (Join-Path $libDir $name) -PathType Leaf) | Should -BeTrue
        }
        # 陈旧库文件（清单外）必须为空：目录完全由 build 拥有。
        $expected = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($m in [regex]::Matches($thin, "'[^']+\.ps1'")) { [void]$expected.Add($m.Value.Trim("'")) }
        @(Get-ChildItem -LiteralPath $libDir -File -Filter '*.ps1' | Where-Object Name | ForEach-Object Name | Where-Object { -not $expected.Contains($_) }) | Should -Be @()
    }
}
