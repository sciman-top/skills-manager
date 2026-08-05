$ErrorActionPreference = "Stop"

Describe "Generated sync script" {
    It "Uses a content diff instead of porcelain metadata for change detection" {
        $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $scriptPath = Join-Path $repoRoot "tests\check-generated-sync.ps1"
        $raw = Get-Content -LiteralPath $scriptPath -Raw

        $raw | Should Match 'git diff --quiet HEAD -- skills\.ps1'
        $raw | Should Match '\$diffExitCode -notin @\(0, 1\)'
        $raw | Should Not Match 'git status --porcelain -- skills\.ps1'
    }

    It "Allows local dirty worktree when explicitly requested and build refreshes generated file" {
        $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $workspace = Join-Path $TestDrive "generated-sync-dev-mode"
        $testsDir = Join-Path $workspace "tests"
        $srcDir = Join-Path $workspace "src"
        New-Item -ItemType Directory -Path $testsDir -Force | Out-Null
        New-Item -ItemType Directory -Path $srcDir -Force | Out-Null

        Copy-Item -LiteralPath (Join-Path $repoRoot "tests\check-generated-sync.ps1") -Destination (Join-Path $testsDir "check-generated-sync.ps1")
        Set-Content -Path (Join-Path $workspace "build.ps1") -Value '$text = Get-Content -Raw ".\src\source.txt"; Set-Content -Path ".\skills.ps1" -Value $text -NoNewline'
        Set-Content -Path (Join-Path $srcDir "source.txt") -Value "v1" -NoNewline
        Set-Content -Path (Join-Path $workspace "skills.ps1") -Value "v1" -NoNewline

        Push-Location $workspace
        try {
            & git init | Out-Null
            & git config user.email "tests@example.com"
            & git config user.name "tests"
            & git add build.ps1 skills.ps1 src/source.txt tests/check-generated-sync.ps1
            & git commit -m "init" | Out-Null

            Set-Content -Path (Join-Path $srcDir "source.txt") -Value "v2" -NoNewline
        }
        finally {
            Pop-Location
        }

        $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $workspace "tests\check-generated-sync.ps1") -AllowDirtyWorktree 2>&1)
        $text = ($output | Out-String)

        $text | Should Match "已在当前工作树中刷新生成产物"
        $text | Should Not Match "检测到生成产物漂移"
    }

    It "Keeps strict mode failing when generated file is dirty relative to HEAD" {
        $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $workspace = Join-Path $TestDrive "generated-sync-strict-mode"
        $testsDir = Join-Path $workspace "tests"
        $srcDir = Join-Path $workspace "src"
        New-Item -ItemType Directory -Path $testsDir -Force | Out-Null
        New-Item -ItemType Directory -Path $srcDir -Force | Out-Null

        Copy-Item -LiteralPath (Join-Path $repoRoot "tests\check-generated-sync.ps1") -Destination (Join-Path $testsDir "check-generated-sync.ps1")
        Set-Content -Path (Join-Path $workspace "build.ps1") -Value '$text = Get-Content -Raw ".\src\source.txt"; Set-Content -Path ".\skills.ps1" -Value $text -NoNewline'
        Set-Content -Path (Join-Path $srcDir "source.txt") -Value "v1" -NoNewline
        Set-Content -Path (Join-Path $workspace "skills.ps1") -Value "v1" -NoNewline

        Push-Location $workspace
        try {
            & git init | Out-Null
            & git config user.email "tests@example.com"
            & git config user.name "tests"
            & git add build.ps1 skills.ps1 src/source.txt tests/check-generated-sync.ps1
            & git commit -m "init" | Out-Null

            Set-Content -Path (Join-Path $srcDir "source.txt") -Value "v2" -NoNewline
        }
        finally {
            Pop-Location
        }

        $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $workspace "tests\check-generated-sync.ps1") 2>&1)
        $text = ($output | Out-String)

        $text | Should Match "检测到生成产物漂移"
    }

    It "fails even in dirty-worktree mode when consecutive builds are not idempotent" {
        $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $workspace = Join-Path $TestDrive "generated-sync-nondeterministic"
        $testsDir = Join-Path $workspace "tests"
        New-Item -ItemType Directory -Path $testsDir -Force | Out-Null

        Copy-Item -LiteralPath (Join-Path $repoRoot "tests\check-generated-sync.ps1") -Destination (Join-Path $testsDir "check-generated-sync.ps1")
        Set-Content -Path (Join-Path $workspace "build.ps1") -Value @'
$counterPath = '.\build-counter.txt'
$counter = if (Test-Path -LiteralPath $counterPath) { [int](Get-Content -LiteralPath $counterPath -Raw) } else { 0 }
$counter++
Set-Content -LiteralPath $counterPath -Value $counter -NoNewline
Set-Content -LiteralPath '.\skills.ps1' -Value ("generated-{0}" -f $counter) -NoNewline
'@
        Set-Content -Path (Join-Path $workspace "skills.ps1") -Value "generated-0" -NoNewline

        Push-Location $workspace
        try {
            & git init | Out-Null
            & git config user.email "tests@example.com"
            & git config user.name "tests"
            & git add build.ps1 skills.ps1 tests/check-generated-sync.ps1
            & git commit -m "init" | Out-Null
        }
        finally {
            Pop-Location
        }

        $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $workspace "tests\check-generated-sync.ps1") -AllowDirtyWorktree 2>&1)
        $text = ($output | Out-String)

        $LASTEXITCODE | Should Not Be 0
        $text | Should Match 'generated_non_idempotent'
    }

    It "Recognizes a Git worktree instead of reporting no-repo" {
        $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $workspace = Join-Path $TestDrive "generated-sync"
        $testsDir = Join-Path $workspace "tests"
        New-Item -ItemType Directory -Path $testsDir -Force | Out-Null

        Copy-Item -LiteralPath (Join-Path $repoRoot "tests\check-generated-sync.ps1") -Destination (Join-Path $testsDir "check-generated-sync.ps1")
        Set-Content -Path (Join-Path $workspace "build.ps1") -Value 'Write-Host "build ok"'
        Set-Content -Path (Join-Path $workspace "skills.ps1") -Value "# generated"

        Push-Location $workspace
        try {
            & git init | Out-Null
            & git config user.email "tests@example.com"
            & git config user.name "tests"
            & git add build.ps1 skills.ps1 tests/check-generated-sync.ps1
            & git commit -m "init" | Out-Null
        }
        finally {
            Pop-Location
        }

        $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $workspace "tests\check-generated-sync.ps1") -StrictNoGit 2>&1)
        $text = ($output | Out-String)

        $text | Should Match "生成产物一致性校验通过"
        $text | Should Not Match "未检测到 Git 工作树"
    }
}
