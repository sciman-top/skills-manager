Describe 'reference refresh remote provenance safety' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $script:refreshScript = Join-Path $repoRoot 'scripts\refresh-reference-repos.ps1'
    }

    It 'does not fetch an existing checkout whose origin differs from the manifest upstream' {
        $referencesRoot = Join-Path $TestDrive 'references'
        $repoPath = Join-Path $referencesRoot 'victim'
        $declaredRemote = Join-Path $TestDrive 'declared.git'
        $attackerRemote = Join-Path $TestDrive 'attacker.git'
        $outputDirectory = Join-Path $TestDrive 'reports'
        $manifestPath = Join-Path $TestDrive 'manifest.json'

        $null = New-Item -ItemType Directory -Path $referencesRoot, $outputDirectory
        & git init --bare $declaredRemote | Out-Null
        & git init --bare $attackerRemote | Out-Null
        & git init $repoPath | Out-Null
        & git -C $repoPath config user.email 'fixture@example.invalid'
        & git -C $repoPath config user.name 'Fixture'
        Set-Content -LiteralPath (Join-Path $repoPath 'README.md') -Value 'fixture' -Encoding UTF8
        & git -C $repoPath add README.md
        & git -C $repoPath commit -m 'fixture' | Out-Null
        & git -C $repoPath remote add origin $attackerRemote

        [ordered]@{
            schema_version = 1
            references_root = $referencesRoot
            default_refresh_set = @('victim')
            repos = @([ordered]@{
                name = 'victim'
                relative_path = 'victim'
                tier = 'core-mainline'
                status = 'active'
                upstream_url = $declaredRemote
                branch = 'main'
            })
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

        $result = & $script:refreshScript -ManifestPath $manifestPath -ReferencesRoot $referencesRoot -OutputDirectory $outputDirectory -RepoNames victim -FetchOnly
        $record = @($result.results)[0]

        $record.status | Should Be 'origin-identity-mismatch'
        $record.origin_matches_manifest | Should Be $false
        [System.IO.Path]::GetFullPath([string]$record.declared_upstream) | Should Be ([System.IO.Path]::GetFullPath($declaredRemote))
        [System.IO.Path]::GetFullPath([string]$record.actual_origin) | Should Be ([System.IO.Path]::GetFullPath($attackerRemote))
        $record.remote_refs_current | Should Be $false
    }

    It 'records the verified actual origin on a successful fetch-only refresh' {
        $referencesRoot = Join-Path $TestDrive 'matching-references'
        $repoPath = Join-Path $referencesRoot 'matching'
        $remote = Join-Path $TestDrive 'matching.git'
        $outputDirectory = Join-Path $TestDrive 'matching-reports'
        $manifestPath = Join-Path $TestDrive 'matching-manifest.json'

        $null = New-Item -ItemType Directory -Path $referencesRoot, $outputDirectory
        & git init --bare $remote | Out-Null
        & git init $repoPath | Out-Null
        & git -C $repoPath config user.email 'fixture@example.invalid'
        & git -C $repoPath config user.name 'Fixture'
        Set-Content -LiteralPath (Join-Path $repoPath 'README.md') -Value 'fixture' -Encoding UTF8
        & git -C $repoPath add README.md
        & git -C $repoPath commit -m 'fixture' | Out-Null
        & git -C $repoPath remote add origin $remote

        [ordered]@{
            schema_version = 1
            references_root = $referencesRoot
            default_refresh_set = @('matching')
            repos = @([ordered]@{ name='matching'; relative_path='matching'; tier='core-mainline'; status='active'; upstream_url=$remote; branch='main' })
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

        $result = & $script:refreshScript -ManifestPath $manifestPath -ReferencesRoot $referencesRoot -OutputDirectory $outputDirectory -RepoNames matching -FetchOnly
        $record = @($result.results)[0]

        $record.status | Should Be 'fetch-only'
        $record.origin_matches_manifest | Should Be $true
        [System.IO.Path]::GetFullPath([string]$record.actual_origin) | Should Be ([System.IO.Path]::GetFullPath($remote))
        $record.remote_refs_current | Should Be $true
    }

    It 'blocks cloning an unreviewed conditional candidate before creating its checkout' {
        $referencesRoot = Join-Path $TestDrive 'blocked-references'
        $remote = Join-Path $TestDrive 'blocked.git'
        $outputDirectory = Join-Path $TestDrive 'blocked-reports'
        $manifestPath = Join-Path $TestDrive 'blocked-manifest.json'
        $destination = Join-Path $referencesRoot 'conditional\blocked'

        $null = New-Item -ItemType Directory -Path $referencesRoot, $outputDirectory
        & git init --bare --initial-branch=main $remote | Out-Null
        [ordered]@{
            schema_version = 1
            references_root = $referencesRoot
            default_refresh_set = @()
            repos = @([ordered]@{
                name = 'blocked'
                relative_path = 'conditional/blocked'
                tier = 'conditional-not-cloned'
                status = 'not-cloned'
                upstream_url = $remote
            })
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

        $result = & $script:refreshScript -ManifestPath $manifestPath -ReferencesRoot $referencesRoot -OutputDirectory $outputDirectory -RepoNames blocked -CloneMissing -FetchOnly
        $record = @($result.results)[0]

        $record.status | Should Be 'clone-blocked'
        $record.note | Should Match 'review metadata'
        Test-Path -LiteralPath $destination | Should Be $false
    }

    It 'blocks cloning a conditional candidate whose license is unresolved' {
        $referencesRoot = Join-Path $TestDrive 'unknown-license-references'
        $remote = Join-Path $TestDrive 'unknown-license.git'
        $outputDirectory = Join-Path $TestDrive 'unknown-license-reports'
        $manifestPath = Join-Path $TestDrive 'unknown-license-manifest.json'
        $destination = Join-Path $referencesRoot 'conditional\unknown-license'

        $null = New-Item -ItemType Directory -Path $referencesRoot, $outputDirectory
        & git init --bare --initial-branch=main $remote | Out-Null
        [ordered]@{
            schema_version = 1
            references_root = $referencesRoot
            default_refresh_set = @()
            repos = @([ordered]@{
                name = 'unknown-license'; relative_path = 'conditional/unknown-license'; tier = 'conditional-not-cloned'; status = 'not-cloned'; upstream_url = $remote
                review_revision = '1111111111111111111111111111111111111111'; license = 'NOASSERTION'; review_decision = 'defer'; reviewed_at = '2026-08-08'
                review_evidence = 'fixture evidence'; activation_trigger = 'fixture trigger'
            })
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

        $result = & $script:refreshScript -ManifestPath $manifestPath -ReferencesRoot $referencesRoot -OutputDirectory $outputDirectory -RepoNames unknown-license -CloneMissing -FetchOnly
        $record = @($result.results)[0]

        $record.status | Should Be 'clone-blocked'
        $record.note | Should Match 'license'
        Test-Path -LiteralPath $destination | Should Be $false
    }

    It 'checks out the reviewed revision in detached state after cloning a conditional candidate' {
        $referencesRoot = Join-Path $TestDrive 'reviewed-references'
        $remote = Join-Path $TestDrive 'reviewed.git'
        $publisher = Join-Path $TestDrive 'reviewed-publisher'
        $outputDirectory = Join-Path $TestDrive 'reviewed-reports'
        $manifestPath = Join-Path $TestDrive 'reviewed-manifest.json'
        $destination = Join-Path $referencesRoot 'conditional\reviewed'

        $null = New-Item -ItemType Directory -Path $referencesRoot, $outputDirectory
        & git init --bare --initial-branch=main $remote | Out-Null
        & git clone $remote $publisher | Out-Null
        & git -C $publisher config user.email 'fixture@example.invalid'
        & git -C $publisher config user.name 'Fixture'
        Set-Content -LiteralPath (Join-Path $publisher 'README.md') -Value 'reviewed' -Encoding UTF8
        & git -C $publisher add README.md
        & git -C $publisher commit -m 'reviewed revision' | Out-Null
        & git -C $publisher push origin main | Out-Null
        $reviewRevision = (& git -C $publisher rev-parse HEAD).Trim()
        Set-Content -LiteralPath (Join-Path $publisher 'README.md') -Value 'newer' -Encoding UTF8
        & git -C $publisher add README.md
        & git -C $publisher commit -m 'newer revision' | Out-Null
        & git -C $publisher push origin main | Out-Null

        [ordered]@{
            schema_version = 1
            references_root = $referencesRoot
            default_refresh_set = @()
            repos = @([ordered]@{
                name = 'reviewed'
                relative_path = 'conditional/reviewed'
                tier = 'conditional-not-cloned'
                status = 'not-cloned'
                upstream_url = $remote
                review_revision = $reviewRevision
                license = 'MIT'
                review_decision = 'adapt'
                reviewed_at = '2026-08-08'
                review_evidence = 'fixture evidence'
                activation_trigger = 'fixture trigger'
            })
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

        $result = & $script:refreshScript -ManifestPath $manifestPath -ReferencesRoot $referencesRoot -OutputDirectory $outputDirectory -RepoNames reviewed -CloneMissing -FetchOnly
        $record = @($result.results)[0]

        $record.status | Should Be 'cloned'
        $record.consumable_revision | Should Be $reviewRevision
        (& git -C $destination rev-parse HEAD).Trim() | Should Be $reviewRevision
        @(& git -C $destination branch --show-current).Count | Should Be 0
    }
}
