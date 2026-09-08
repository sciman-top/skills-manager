Describe 'release-update-worker staged payload integrity' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $workerSource = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\release\release-update-worker.ps1') -Raw
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($workerSource, [ref]$null, [ref]$null)
        $fn = $ast.Find({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Assert-StagedPayloadIntegrity' }, $true)
        $manifestFn = $ast.Find({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Get-ReleaseManifestSha256' }, $true)
        $rollbackFn = $ast.Find({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Invoke-ReleaseUpdateRollback' }, $true)
        if ($null -eq $fn) { throw 'Assert-StagedPayloadIntegrity not found in worker script' }
        if ($null -eq $manifestFn) { throw 'Get-ReleaseManifestSha256 not found in worker script' }
        if ($null -eq $rollbackFn) { throw 'Invoke-ReleaseUpdateRollback not found in worker script' }
        . ([scriptblock]::Create($fn.Extent.Text))
        . ([scriptblock]::Create($manifestFn.Extent.Text))
        . ([scriptblock]::Create($rollbackFn.Extent.Text))
        $script:roots = [System.Collections.Generic.List[string]]::new()

        function New-StagedPackage {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('worker-integrity-' + [guid]::NewGuid().ToString('N'))
            $script:roots.Add($root) | Out-Null
            New-Item -ItemType Directory -Path $root | Out-Null
            $files = @()
            foreach ($relative in @('skills.ps1', 'install.ps1')) {
                $path = Join-Path $root $relative
                Set-Content -LiteralPath $path -Value ('payload ' + $relative) -Encoding UTF8
                $files += [ordered]@{
                    path   = $relative
                    size   = (Get-Item -LiteralPath $path).Length
                    sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            }
            $manifest = [ordered]@{ schema_version = 2; product = 'skills-manager'; version = 'v9.99'; package = 'bootstrap'; publishable = $true; files = @($files) }
            $manifestPath = Join-Path $root 'RELEASE-MANIFEST.json'
            $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8
            return [pscustomobject]@{
                root           = $root
                manifest_sha   = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
                manifest_path  = $manifestPath
            }
        }
    }

    AfterAll {
        foreach ($r in @($script:roots)) { Remove-Item -LiteralPath $r -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'passes a genuine freshly built package including the manifest itself' {
        $pkg = New-StagedPackage
        { Assert-StagedPayloadIntegrity $pkg.root $pkg.manifest_sha } | Should -Not -Throw
    }

    It 'rejects a payload file modified after handoff' {
        $pkg = New-StagedPackage
        Set-Content -LiteralPath (Join-Path $pkg.root 'skills.ps1') -Value 'tampered' -Encoding UTF8
        { Assert-StagedPayloadIntegrity $pkg.root $pkg.manifest_sha } | Should -Throw '*modified after handoff*'
    }

    It 'rejects an unmanifested file added after handoff' {
        $pkg = New-StagedPackage
        Set-Content -LiteralPath (Join-Path $pkg.root 'UNEXPECTED.ps1') -Value 'payload' -Encoding UTF8
        # The count guard fires first for an added file; the per-file
        # unmanifested check covers same-count swaps.
        { Assert-StagedPayloadIntegrity $pkg.root $pkg.manifest_sha } | Should -Throw '*does not match the manifest*'
    }

    It 'rejects a swapped manifest that no longer matches the handoff hash' {
        $pkg = New-StagedPackage
        $manifest = Get-Content -LiteralPath $pkg.manifest_path -Raw | ConvertFrom-Json
        $manifest.version = 'v9.98'
        $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $pkg.manifest_path -Encoding utf8
        { Assert-StagedPayloadIntegrity $pkg.root $pkg.manifest_sha } | Should -Throw '*changed after handoff*'
    }

    It 'keeps a backup-only recovery path when current went missing mid-swap' {
        $workerScript = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\release\release-update-worker.ps1') -Raw
        $workerScript | Should -Match '(?s)function Invoke-ReleaseUpdateRollback.*?Move-Item -LiteralPath \$backup -Destination \$current -ErrorAction Stop'
    }

    It 'verifies a successful rollback and reports rollback failure without claiming recovery' {
        $current = Join-Path ([IO.Path]::GetTempPath()) ('worker-rollback-current-' + [guid]::NewGuid().ToString('N'))
        $backup = Join-Path ([IO.Path]::GetTempPath()) ('worker-rollback-backup-' + [guid]::NewGuid().ToString('N'))
        $failed = $current + '.failed'
        $script:roots.Add($current) | Out-Null
        $script:roots.Add($backup) | Out-Null
        try {
            New-Item -ItemType Directory -Path $backup -Force | Out-Null
            $manifestPath = Join-Path $backup 'RELEASE-MANIFEST.json'
            Set-Content -LiteralPath $manifestPath -Value '{"version":"previous"}' -Encoding UTF8
            $expected = Get-ReleaseManifestSha256 $backup

            $result = Invoke-ReleaseUpdateRollback $current $backup $failed $expected

            $result.status | Should -Be 'rolled_back'
            Test-Path -LiteralPath $current -PathType Container | Should -BeTrue
            Test-Path -LiteralPath $backup -PathType Container | Should -BeFalse

            $blockedCurrent = Join-Path ([IO.Path]::GetTempPath()) ('worker-rollback-blocked-' + [guid]::NewGuid().ToString('N'))
            $blockedBackup = Join-Path ([IO.Path]::GetTempPath()) ('worker-rollback-blocked-backup-' + [guid]::NewGuid().ToString('N'))
            $script:roots.Add($blockedCurrent) | Out-Null
            $script:roots.Add($blockedBackup) | Out-Null
            Set-Content -LiteralPath $blockedCurrent -Value 'blocking file' -Encoding UTF8
            New-Item -ItemType Directory -Path $blockedBackup -Force | Out-Null

            $failedResult = Invoke-ReleaseUpdateRollback $blockedCurrent $blockedBackup ($blockedCurrent + '.failed') ''

            $failedResult.status | Should -Be 'rollback_failed'
            Test-Path -LiteralPath $blockedBackup -PathType Container | Should -BeTrue

            # 恢复成功但交接时没记录清单哈希：无法证明恢复内容，必须如实报 rollback_failed。
            $unverifiedCurrent = Join-Path ([IO.Path]::GetTempPath()) ('worker-rollback-unverified-' + [guid]::NewGuid().ToString('N'))
            $unverifiedBackup = Join-Path ([IO.Path]::GetTempPath()) ('worker-rollback-unverified-backup-' + [guid]::NewGuid().ToString('N'))
            $script:roots.Add($unverifiedCurrent) | Out-Null
            $script:roots.Add($unverifiedBackup) | Out-Null
            New-Item -ItemType Directory -Path $unverifiedBackup -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $unverifiedBackup 'RELEASE-MANIFEST.json') -Value '{"version":"previous"}' -Encoding UTF8

            $unverified = Invoke-ReleaseUpdateRollback $unverifiedCurrent $unverifiedBackup ($unverifiedCurrent + '.failed') ''

            $unverified.status | Should -Be 'rollback_failed'
            $unverified.message | Should -Match 'no RELEASE-MANIFEST\.json hash was recorded'
            Test-Path -LiteralPath $unverifiedCurrent -PathType Container | Should -BeTrue
            Test-Path -LiteralPath $unverifiedBackup -PathType Container | Should -BeFalse
        }
        finally {
            foreach ($path in @($current, $backup, $failed)) {
                if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }
    }
}
