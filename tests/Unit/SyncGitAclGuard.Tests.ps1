$ErrorActionPreference = "Stop"

Describe "sync-git-acl-guard script" {
    BeforeAll {
        $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $scriptPath = Join-Path $repoRoot "scripts\sync-git-acl-guard.ps1"
    }

    It "Copies source guard script into explicit repo roots" {
        $workspace = Join-Path $TestDrive ("sync-git-acl-guard-copy-" + [guid]::NewGuid().ToString("N"))
        $sourceDir = Join-Path $workspace "source"
        $repoA = Join-Path $workspace "repo-a"
        $repoB = Join-Path $workspace "repo-b"
        $sourceScript = Join-Path $sourceDir "git-acl-guard.ps1"
        $expected = "Write-Host 'guard-v2'"

        New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
        New-Item -ItemType Directory -Path $repoA -Force | Out-Null
        New-Item -ItemType Directory -Path $repoB -Force | Out-Null
        Set-Content -LiteralPath $sourceScript -Value $expected -NoNewline

        New-Item -ItemType Directory -Path (Join-Path $repoA ".git") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $repoB ".git") -Force | Out-Null

        $output = @(
            & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
                -SourceScript $sourceScript `
                -ScanRoot $workspace 2>&1
        )
        $LASTEXITCODE | Should Be 0

        $destA = Join-Path $repoA "scripts\git-acl-guard.ps1"
        $destB = Join-Path $repoB "scripts\git-acl-guard.ps1"
        (Test-Path -LiteralPath $destA -PathType Leaf) | Should Be $true
        (Test-Path -LiteralPath $destB -PathType Leaf) | Should Be $true
        (Get-Content -LiteralPath $destA -Raw) | Should Be $expected
        (Get-Content -LiteralPath $destB -Raw) | Should Be $expected
    }

    It "Honors WhatIf by skipping directory creation and file copy" {
        $workspace = Join-Path $TestDrive ("sync-git-acl-guard-whatif-" + [guid]::NewGuid().ToString("N"))
        $sourceDir = Join-Path $workspace "source"
        $repo = Join-Path $workspace "repo"
        $sourceScript = Join-Path $sourceDir "git-acl-guard.ps1"

        New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        Set-Content -LiteralPath $sourceScript -Value "Write-Host 'guard-v3'" -NoNewline

        New-Item -ItemType Directory -Path (Join-Path $repo ".git") -Force | Out-Null

        $output = @(
            & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
                -SourceScript $sourceScript `
                -ScanRoot $workspace `
                -WhatIf 2>&1
        )
        $LASTEXITCODE | Should Be 0

        $destDir = Join-Path $repo "scripts"
        $destPath = Join-Path $destDir "git-acl-guard.ps1"
        (Test-Path -LiteralPath $destDir) | Should Be $false
        (Test-Path -LiteralPath $destPath) | Should Be $false
    }
}
