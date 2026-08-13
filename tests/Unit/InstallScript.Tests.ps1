$ErrorActionPreference = "Stop"

Describe "Install script" {
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

    It "Installs for the current user by rebuilding locked sources, optionally syncing MCP, then running doctor" {
        $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
        $installPath = Join-Path $repoRoot "install.ps1"
        $workspace = Join-Path $TestDrive "install-current-user"
        New-InstallFixture $workspace

        & pwsh -NoProfile -ExecutionPolicy Bypass -File $installPath -Root $workspace -Mode CurrentUser -SyncMcp -SkipEnvironmentCheck | Out-Null
        $LASTEXITCODE | Should Be 0

        $calls = Get-Content -LiteralPath (Join-Path $workspace "calls.log")
        ($calls -join "|") | Should Be "build|skills 更新 -Locked|skills 同步MCP|skills doctor --strict"
    }

    It "Supports portable-only validation without applying skills or MCP configuration" {
        $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
        $installPath = Join-Path $repoRoot "install.ps1"
        $workspace = Join-Path $TestDrive "install-portable"
        New-InstallFixture $workspace

        & pwsh -NoProfile -ExecutionPolicy Bypass -File $installPath -Root $workspace -Mode PortableOnly -SyncMcp -SkipEnvironmentCheck | Out-Null
        $LASTEXITCODE | Should Be 0

        $calls = Get-Content -LiteralPath (Join-Path $workspace "calls.log")
        ($calls -join "|") | Should Be "build|skills doctor --strict"
    }
}
