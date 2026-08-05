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
}
