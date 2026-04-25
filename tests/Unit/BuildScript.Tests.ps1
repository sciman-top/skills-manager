$ErrorActionPreference = "Stop"

Describe "Build script" {
    It "Concatenates source files without injecting separator spaces" {
        $workspace = Join-Path $TestDrive "build-script"
        $srcRoot = Join-Path $workspace "src"
        $commandsRoot = Join-Path $srcRoot "Commands"
        New-Item -ItemType Directory -Path $commandsRoot -Force | Out-Null

        $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $buildPath = Join-Path $repoRoot "build.ps1"
        Copy-Item -LiteralPath $buildPath -Destination (Join-Path $workspace "build.ps1")

        $buildRaw = Get-Content -LiteralPath $buildPath -Raw
        $files = @([regex]::Matches($buildRaw, '"([^"]+\.ps1)"') | ForEach-Object { $_.Groups[1].Value })
        $files = @($files | Where-Object { $_ -ne "skills.ps1" })

        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        $contents = @{}
        for ($i = 0; $i -lt $files.Count; $i++) {
            $relativePath = $files[$i]
            $content = "chunk-$i"
            $contents[$relativePath] = $content

            $filePath = Join-Path $srcRoot $relativePath
            $parent = Split-Path $filePath -Parent
            if (-not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            [System.IO.File]::WriteAllText($filePath, $content, $utf8NoBom)
        }

        & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $workspace "build.ps1") | Out-Null

        $actual = [System.IO.File]::ReadAllText((Join-Path $workspace "skills.ps1"))
        $expected = (($files | ForEach-Object { $contents[$_] + "`r`n" }) -join "")

        $actual | Should Be $expected
    }
}
