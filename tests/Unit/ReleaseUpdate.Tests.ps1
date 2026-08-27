BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'skills.ps1')
}

Describe 'GitHub Release update contract' {
    AfterEach { $script:ReleaseUpdateHttpGet = $null }

    It 'requires explicit confirmation before applying a release update' {
        { Get-ReleaseUpdateTokens @('--apply') } | Should -Throw '*必须显式加 --yes*'
        (Get-ReleaseUpdateTokens @('--check','--json')).action | Should -Be 'check'
        (Get-ReleaseUpdateTokens @('--apply','--yes','--sync-mcp')).sync_mcp | Should -BeTrue
    }

    It 'parses only an exact SHA-256 entry for the requested release asset' {
        $text = @"
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa *other.zip
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb *skills-manager-v1-bootstrap.zip
"@
        (ConvertFrom-ReleaseChecksumText $text 'skills-manager-v1-bootstrap.zip') | Should -Be ([string]::new([char]'b', 64))
        { ConvertFrom-ReleaseChecksumText $text 'missing.zip' } | Should -Throw '*未包含发布资产*'
    }

    It 'uses the latest Release assets and checksum instead of trusting a filename guess' {
        $script:ReleaseUpdateHttpGet = {
            param($Uri, $OutFile)
            if ($Uri -match '/releases/latest$') {
                return [pscustomobject]@{
                    tag_name = 'v2026.08.27'; draft = $false; prerelease = $false; html_url = 'https://example.invalid/release'
                    assets = @(
                        [pscustomobject]@{ name = 'skills-manager-v2026.08.27-bootstrap.zip'; browser_download_url = 'https://example.invalid/bootstrap.zip' },
                        [pscustomobject]@{ name = 'skills-manager-v2026.08.27-SHA256SUMS.txt'; browser_download_url = 'https://example.invalid/checksums.txt' }
                    )
                }
            }
            return ([string]::new([char]'c', 64)) + ' *skills-manager-v2026.08.27-bootstrap.zip'
        }
        $snapshot = Get-ReleaseUpdateSnapshot 'sciman-top/skills-manager' ([pscustomobject]@{ version = 'v2026.08.01' })
        $snapshot.update_available | Should -BeTrue
        $snapshot.latest_version | Should -Be 'v2026.08.27'
        $snapshot.bootstrap_sha256 | Should -Be ([string]::new([char]'c', 64))
    }

    It 'refuses automatic replacement when a Release-managed file has changed locally' {
        $root = Join-Path $TestDrive 'release-install'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $file = Join-Path $root 'skills.ps1'
        Set-Content -LiteralPath $file -Value 'known-good' -Encoding utf8
        $manifest = [pscustomobject]@{ files = @([pscustomobject]@{ path = 'skills.ps1'; sha256 = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() }) }
        (Test-ReleaseUpdatePristineInstallation $root $manifest) | Should -BeTrue
        Set-Content -LiteralPath $file -Value 'locally-modified' -Encoding utf8
        { Test-ReleaseUpdatePristineInstallation $root $manifest } | Should -Throw '*本地发行文件已修改*'
    }

    It 'requires an explicit schedule action and rejects auto-apply on disable' {
        { Get-ReleaseUpdateScheduleTokens @() } | Should -Throw '*必须指定*'
        (Get-ReleaseUpdateScheduleTokens @('--enable','--time=08:30','--auto-apply')).auto_apply | Should -BeTrue
        { Get-ReleaseUpdateScheduleTokens @('--disable','--auto-apply') } | Should -Throw '*仅可与 --enable*'
    }

    It 'keeps the only scheduler mutation in the constrained Release updater entrypoint' {
        $scheduler = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\release\register-release-update-task.ps1') -Raw
        $scheduler | Should -Match "\$taskName = 'skills-manager-release-update'"
        $scheduler | Should -Match '-LogonType Interactive -RunLevel Limited'
        $scheduler | Should -Not -Match '(?i)-RunLevel\s+Highest'
        (Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\quality\run-local-quality-gates.ps1') -Raw) | Should -Match 'approvedSchedulerPath'
    }
}
