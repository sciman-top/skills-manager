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
        $physicalFn = $ast.Find({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Assert-PhysicalChainHasNoReparse' }, $true)
        . ([scriptblock]::Create($physicalFn.Extent.Text))
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

    It 'preserves an unowned backup on preflight failure with current missing=<CurrentMissing>' -TestCases @(
        @{ CurrentMissing=$false }, @{ CurrentMissing=$true }
    ) {
        param($CurrentMissing)
        $root = Join-Path $TestDrive 'preflight-conflict'
        $current = Join-Path $root 'current'
        $backup = Join-Path $root 'backup'
        $staged = Join-Path $root 'staged'
        New-Item -ItemType Directory -Path $current,$backup,$staged -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $current 'RELEASE-MANIFEST.json') -Value '{"version":"current"}'
        Set-Content -LiteralPath (Join-Path $backup 'RELEASE-MANIFEST.json') -Value '{"version":"unowned"}'
        $currentHash = Get-ReleaseManifestSha256 $current
        $backupHash = Get-ReleaseManifestSha256 $backup
        if ($CurrentMissing) { Remove-Item -LiteralPath $current -Recurse -Force }
        $worker = Join-Path $root 'worker.ps1'
        Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/release/release-update-worker.ps1') -Destination $worker
        & pwsh -NoProfile -File $worker -CurrentRoot $current -StagedRoot $staged -BackupRoot $backup -ExpectedVersion v2026.09.13 -PackageType portable -ParentProcessId 2147483647 -ManifestSha256 unused 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 1
        if ($CurrentMissing) { Test-Path -LiteralPath $current | Should -BeFalse }
        else { Get-ReleaseManifestSha256 $current | Should -Be $currentHash }
        Get-ReleaseManifestSha256 $backup | Should -Be $backupHash
        @(Get-ChildItem -LiteralPath $backup -Recurse -Force).Count | Should -Be 1
        @(Get-ChildItem -LiteralPath $root -Directory -Filter 'current.failed-*').Count | Should -Be 0
        $receiptRoot = if ($CurrentMissing) { $root } else { $current }
        (Get-Content -LiteralPath (Join-Path $receiptRoot 'reports/release-update/last.json') -Raw | ConvertFrom-Json).status | Should -Be 'not_started'
    }

    It 'runs the real worker through <PackageType> replacement and recovery' -TestCases @(
        @{ PackageType='portable'; ExpectedStatus='updated'; ExpectedExit=0 },
        @{ PackageType='bootstrap'; ExpectedStatus='rolled_back'; ExpectedExit=1 }
    ) {
        param($PackageType,$ExpectedStatus,$ExpectedExit)
        $root = Join-Path $TestDrive ('worker-' + $PackageType)
        $current = Join-Path $root 'current'
        $staged = Join-Path $root 'staged'
        $backup = Join-Path $root 'backup'
        New-Item -ItemType Directory -Path $current -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $current 'RELEASE-MANIFEST.json') -Value '{"version":"previous"}'
        $oldHash = Get-ReleaseManifestSha256 $current
        $pkg = New-StagedPackage
        Copy-Item -LiteralPath $pkg.root -Destination $staged -Recurse
        Set-Content -LiteralPath (Join-Path $staged 'install.ps1') -Value 'exit 7'
        $manifestPath = Join-Path $staged 'RELEASE-MANIFEST.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.package = $PackageType
        $manifest.version = 'v2026.09.13'
        foreach ($entry in $manifest.files) {
            $entry.sha256 = (Get-FileHash -LiteralPath (Join-Path $staged $entry.path)).Hash.ToLowerInvariant()
        }
        $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath
        $newHash = Get-ReleaseManifestSha256 $staged
        $worker = Join-Path $root 'worker.ps1'
        Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/release/release-update-worker.ps1') -Destination $worker
        & pwsh -NoProfile -File $worker -CurrentRoot $current -StagedRoot $staged -BackupRoot $backup -ExpectedVersion v2026.09.13 -PackageType $PackageType -ParentProcessId 2147483647 -ManifestSha256 $newHash 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be $ExpectedExit
        (Get-Content -LiteralPath (Join-Path $current 'reports/release-update/last.json') -Raw | ConvertFrom-Json).status | Should -Be $ExpectedStatus
        if ($PackageType -eq 'portable') {
            Get-ReleaseManifestSha256 $current | Should -Be $newHash
            Get-ReleaseManifestSha256 $backup | Should -Be $oldHash
        }
        else {
            Get-ReleaseManifestSha256 $current | Should -Be $oldHash
            $failed = @(Get-ChildItem -LiteralPath $root -Directory -Filter 'current.failed-*')
            $failed.Count | Should -Be 1
            Get-ReleaseManifestSha256 $failed[0].FullName | Should -Be $newHash
        }
    }

    It 'preserves both directories when the owned backup no longer matches its recorded hash' {
        $current = Join-Path $TestDrive 'hash-current'
        $backup = Join-Path $TestDrive 'hash-backup'
        New-Item -ItemType Directory -Path $current,$backup | Out-Null
        Set-Content -LiteralPath (Join-Path $current 'RELEASE-MANIFEST.json') -Value '{"version":"current"}'
        Set-Content -LiteralPath (Join-Path $backup 'RELEASE-MANIFEST.json') -Value '{"version":"previous"}'
        $expected = Get-ReleaseManifestSha256 $backup
        Set-Content -LiteralPath (Join-Path $backup 'RELEASE-MANIFEST.json') -Value '{"version":"changed"}'
        $result = Invoke-ReleaseUpdateRollback $current $backup ($current + '.failed') $expected
        $result.status | Should -Be 'rollback_failed'
        (Get-Content (Join-Path $current 'RELEASE-MANIFEST.json') -Raw | ConvertFrom-Json).version | Should -Be 'current'
        Test-Path -LiteralPath $backup | Should -BeTrue
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

            # Missing provenance must block before moving either directory.
            $unverifiedCurrent = Join-Path ([IO.Path]::GetTempPath()) ('worker-rollback-unverified-' + [guid]::NewGuid().ToString('N'))
            $unverifiedBackup = Join-Path ([IO.Path]::GetTempPath()) ('worker-rollback-unverified-backup-' + [guid]::NewGuid().ToString('N'))
            $script:roots.Add($unverifiedCurrent) | Out-Null
            $script:roots.Add($unverifiedBackup) | Out-Null
            New-Item -ItemType Directory -Path $unverifiedBackup -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $unverifiedBackup 'RELEASE-MANIFEST.json') -Value '{"version":"previous"}' -Encoding UTF8

            $unverified = Invoke-ReleaseUpdateRollback $unverifiedCurrent $unverifiedBackup ($unverifiedCurrent + '.failed') ''

            $unverified.status | Should -Be 'rollback_failed'
            $unverified.message | Should -Match 'no RELEASE-MANIFEST\.json hash was recorded'
            Test-Path -LiteralPath $unverifiedCurrent -PathType Container | Should -BeFalse
            Test-Path -LiteralPath $unverifiedBackup -PathType Container | Should -BeTrue
        }
        finally {
            foreach ($path in @($current, $backup, $failed)) {
                if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }
    }
}
