$ErrorActionPreference = "Stop"

Describe "Release packaging scripts" {
    function New-TestFile([string]$Path, [string]$Content = "fixture") {
        $parent = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Path))
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
    }

    function New-InstallFixture([string]$Workspace) {
        New-Item -ItemType Directory -Path $Workspace -Force | Out-Null
        New-TestFile (Join-Path $Workspace "skills.lock.json") "{}"
        New-TestFile (Join-Path $Workspace "build.ps1") @'
$callLog = Join-Path $PSScriptRoot 'calls.log'
Add-Content -LiteralPath $callLog -Value 'build'
exit 0
'@
        New-TestFile (Join-Path $Workspace "skills.ps1") @'
$callLog = Join-Path $PSScriptRoot 'calls.log'
Add-Content -LiteralPath $callLog -Value ("skills " + ($args -join " "))
exit 0
'@
    }

    It "Creates a portable package from a whitelist and excludes runtime state" {
        $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
        $scriptPath = Join-Path $repoRoot "scripts\release\pack-portable.ps1"
        Test-Path -LiteralPath $scriptPath | Should Be $true

        $workspace = Join-Path $TestDrive "portable-source"
        $out = Join-Path $TestDrive "out"
        $expanded = Join-Path $TestDrive "expanded"

        New-TestFile (Join-Path $workspace "README.md")
        New-TestFile (Join-Path $workspace "skills.ps1")
        New-TestFile (Join-Path $workspace "skills.cmd")
        New-TestFile (Join-Path $workspace "skills.json") "{}"
        New-TestFile (Join-Path $workspace "skills.lock.json") "{}"
        New-TestFile (Join-Path $workspace "install.ps1")
        New-TestFile (Join-Path $workspace "src\Core.ps1")
        New-TestFile (Join-Path $workspace "config\skill-routing-policy.json") "{}"
        New-TestFile (Join-Path $workspace "scripts\quality\check-doctor-json.ps1")
        New-TestFile (Join-Path $workspace "tests\run.ps1")
        New-TestFile (Join-Path $workspace "overrides\custom\custom-demo\SKILL.md")
        New-TestFile (Join-Path $workspace "docs\runbooks\migration.md")
        New-TestFile (Join-Path $workspace "docs\change-evidence\template.md")
        New-TestFile (Join-Path $workspace "docs\change-evidence\20260530-audit-runtime-test.md")
        New-TestFile (Join-Path $workspace "references\README.md")
        New-TestFile (Join-Path $workspace "references\reference-shelf.manifest.json") "{}"
        New-TestFile (Join-Path $workspace "references\updates\README.md")
        New-TestFile (Join-Path $workspace ".codex\config.toml")
        New-TestFile (Join-Path $workspace "agent\demo\SKILL.md")
        New-TestFile (Join-Path $workspace "vendor\demo\SKILL.md")
        New-TestFile (Join-Path $workspace "imports\demo\SKILL.md")
        New-TestFile (Join-Path $workspace "reports\skill-audit\run\ai-brief.md")
        New-TestFile (Join-Path $workspace "build.log")
        New-TestFile (Join-Path $workspace ".build-cache.json") "{}"
        New-Item -ItemType Directory -Path (Join-Path $workspace "scripts\release") -Force | Out-Null
        Copy-Item -LiteralPath $scriptPath -Destination (Join-Path $workspace "scripts\release\pack-portable.ps1")

        & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Root $workspace -Out $out -Version "1.2.3-test" -SkipVerification -AllowDirtyWorktree | Out-Null
        $LASTEXITCODE | Should Be 0

        $zip = Join-Path $out "skills-manager-1.2.3-test-portable.zip"
        Test-Path -LiteralPath $zip | Should Be $true
        Expand-Archive -LiteralPath $zip -DestinationPath $expanded -Force

        Test-Path -LiteralPath (Join-Path $expanded "skills.ps1") | Should Be $true
        Test-Path -LiteralPath (Join-Path $expanded "install.ps1") | Should Be $true
        Test-Path -LiteralPath (Join-Path $expanded "src\Core.ps1") | Should Be $true
        Test-Path -LiteralPath (Join-Path $expanded "config\skill-routing-policy.json") | Should Be $true
        Test-Path -LiteralPath (Join-Path $expanded "scripts\release\pack-portable.ps1") | Should Be $true
        Test-Path -LiteralPath (Join-Path $expanded "docs\change-evidence\template.md") | Should Be $true
        Test-Path -LiteralPath (Join-Path $expanded "references\README.md") | Should Be $true
        Test-Path -LiteralPath (Join-Path $expanded "references\reference-shelf.manifest.json") | Should Be $true
        Test-Path -LiteralPath (Join-Path $expanded "references\updates\README.md") | Should Be $true

        Test-Path -LiteralPath (Join-Path $expanded ".codex") | Should Be $false
        Test-Path -LiteralPath (Join-Path $expanded "agent") | Should Be $false
        Test-Path -LiteralPath (Join-Path $expanded "vendor") | Should Be $false
        Test-Path -LiteralPath (Join-Path $expanded "imports") | Should Be $false
        Test-Path -LiteralPath (Join-Path $expanded "reports") | Should Be $false
        Test-Path -LiteralPath (Join-Path $expanded "build.log") | Should Be $false
        Test-Path -LiteralPath (Join-Path $expanded ".build-cache.json") | Should Be $false
        Test-Path -LiteralPath (Join-Path $expanded "docs\change-evidence\20260530-audit-runtime-test.md") | Should Be $false

        $manifest = Get-Content -LiteralPath (Join-Path $expanded "PORTABLE-MANIFEST.json") -Raw | ConvertFrom-Json
        @($manifest.included_files) -contains "skills.json" | Should Be $true
        @($manifest.included_files) -contains "imports/demo/SKILL.md" | Should Be $false
    }

    It "Installs for the current user by rebuilding locked sources, optionally syncing MCP, then running doctor" {
        $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
        $installPath = Join-Path $repoRoot "install.ps1"
        Test-Path -LiteralPath $installPath | Should Be $true

        $workspace = Join-Path $TestDrive "install-current-user"
        New-InstallFixture $workspace

        & pwsh -NoProfile -ExecutionPolicy Bypass -File $installPath -Root $workspace -Mode CurrentUser -SyncMcp -SkipEnvironmentCheck | Out-Null
        $LASTEXITCODE | Should Be 0

        $calls = Get-Content -LiteralPath (Join-Path $workspace "calls.log")
        ($calls -join "|") | Should Be "build|skills 更新 -Locked|skills 同步MCP|skills doctor --strict --threshold-ms 8000"
    }

    It "Supports portable-only validation without applying skills or MCP configuration" {
        $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
        $installPath = Join-Path $repoRoot "install.ps1"
        Test-Path -LiteralPath $installPath | Should Be $true

        $workspace = Join-Path $TestDrive "install-portable"
        New-InstallFixture $workspace

        & pwsh -NoProfile -ExecutionPolicy Bypass -File $installPath -Root $workspace -Mode PortableOnly -SyncMcp -SkipEnvironmentCheck | Out-Null
        $LASTEXITCODE | Should Be 0

        $calls = Get-Content -LiteralPath (Join-Path $workspace "calls.log")
        ($calls -join "|") | Should Be "build|skills doctor --strict --threshold-ms 8000"
    }
}
