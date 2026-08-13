BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src\Infrastructure\AtomicFile.ps1')

}
Describe 'UTF-8 atomic file infrastructure seam' {
    It 'writes identical UTF-8 without BOM through the helper and legacy wrapper' {
        . (Join-Path $repoRoot 'skills.ps1')
        $helperPath = Join-Path $TestDrive 'helper\unicode.txt'
        $wrapperPath = Join-Path $TestDrive 'wrapper\unicode.txt'
        $content = "ASCII and 中文`nsecond line"

        Write-Utf8FileAtomic -Path $helperPath -Content $content
        Set-ContentUtf8 $wrapperPath $content

        $helperBytes = [System.IO.File]::ReadAllBytes($helperPath)
        $wrapperBytes = [System.IO.File]::ReadAllBytes($wrapperPath)
        ([System.BitConverter]::ToString($helperBytes)) | Should -Be ([System.BitConverter]::ToString($wrapperBytes))
        @($helperBytes[0..2]) -join ',' | Should -Not -Be '239,187,191'
        [System.Text.Encoding]::UTF8.GetString($helperBytes) | Should -Be $content
    }

    It 'overwrites read-only and hidden files while clearing write-block attributes' {
        $path = Join-Path $TestDrive 'attributes.txt'
        [System.IO.File]::WriteAllText($path, 'old')
        $item = Get-Item -LiteralPath $path -Force
        $item.Attributes = $item.Attributes -bor [System.IO.FileAttributes]::ReadOnly -bor [System.IO.FileAttributes]::Hidden

        Write-Utf8FileAtomic -Path $path -Content 'new'

        [System.IO.File]::ReadAllText($path) | Should -Be 'new'
        $attributes = (Get-Item -LiteralPath $path -Force).Attributes
        ($attributes -band [System.IO.FileAttributes]::ReadOnly) | Should -Be 0
        ($attributes -band [System.IO.FileAttributes]::Hidden) | Should -Be 0
    }

    It 'leaves the original intact and removes transaction files when replacement fails' {
        $path = Join-Path $TestDrive 'locked.txt'
        [System.IO.File]::WriteAllText($path, 'original')
        $lock = New-Object System.IO.FileStream($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        try {
            { Write-Utf8FileAtomic -Path $path -Content 'replacement' -MaxAttempts 1 -DelayMs 0 } | Should -Throw
        }
        finally {
            $lock.Dispose()
        }

        [System.IO.File]::ReadAllText($path) | Should -Be 'original'
        @(Get-ChildItem -LiteralPath $TestDrive -Force | Where-Object Name -match '\.(tmp|bak)-').Count | Should -Be 0
    }

    It 'keeps SaveCfg as a direct production caller while the legacy wrapper remains available' {
        $configSource = Get-Content -LiteralPath (Join-Path $repoRoot 'src\Config.ps1') -Raw
        $coreSource = Get-Content -LiteralPath (Join-Path $repoRoot 'src\Core.ps1') -Raw

        $configSource | Should -Match '(?s)function SaveCfg\(\$cfg\).*?Write-Utf8FileAtomic\s+-Path\s+\$CfgPath\s+-Content\s+\$json'
        $coreSource | Should -Match '(?s)function Set-ContentUtf8.*?Write-Utf8FileAtomic'
    }

    It 'parses and writes a no-BOM file in the PowerShell 7 runtime' {
        $sourcePath = (Join-Path $repoRoot 'src\Infrastructure\AtomicFile.ps1').Replace("'", "''")
        $targetPath = (Join-Path $TestDrive 'ps51.txt').Replace("'", "''")
        $scriptText = ". '$sourcePath'; Write-Utf8FileAtomic -Path '$targetPath' -Content 'ps51'; [BitConverter]::ToString([IO.File]::ReadAllBytes('$targetPath'))"

        $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -Command $scriptText 2>&1)
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 0
        ($output -join "`n") | Should -Be '70-73-35-31'
    }
}
