BeforeAll {
    function New-ReferenceRefreshFixture {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Root,
            [string]$Name = 'demo'
        )

        $remote = Join-Path $Root ($Name + '-remote.git')
        $publisher = Join-Path $Root ($Name + '-publisher')
        $referencesRoot = Join-Path $Root ($Name + '-references')
        $consumer = Join-Path $referencesRoot 'core\demo'
        New-Item -ItemType Directory -Path (Split-Path $consumer -Parent) -Force | Out-Null

        & git init --bare --initial-branch=main -q $remote
        & git clone -q $remote $publisher
        & git -C $publisher config user.name fixture
        & git -C $publisher config user.email fixture@example.invalid
        Set-Content -LiteralPath (Join-Path $publisher 'README.md') -Value 'one' -Encoding UTF8
        & git -C $publisher add README.md
        & git -C $publisher commit -q -m one
        & git -C $publisher push -q origin main
        & git clone -q $remote $consumer
        $consumerOriginBefore = (& git -C $consumer rev-parse origin/main).Trim()

        Set-Content -LiteralPath (Join-Path $publisher 'README.md') -Value 'two' -Encoding UTF8
        & git -C $publisher add README.md
        & git -C $publisher commit -q -m two
        & git -C $publisher push -q origin main
        $remoteHead = (& git -C $publisher rev-parse HEAD).Trim()

        return [pscustomobject]@{
            Remote = $remote
            ReferencesRoot = $referencesRoot
            Consumer = $consumer
            ConsumerOriginBefore = $consumerOriginBefore
            RemoteHead = $remoteHead
        }
    }

    function Write-ReferenceRefreshManifest {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Path,
            [Parameter(Mandatory = $true)]
            [string]$ReferencesRoot,
            [Parameter(Mandatory = $true)]
            [string]$UpstreamUrl
        )

        $manifest = [ordered]@{
            schema_version = 1
            references_root = $ReferencesRoot
            default_refresh_set = @('demo')
            repos = @([ordered]@{
                    name = 'demo'
                    tier = 'core-mainline'
                    status = 'active'
                    upstream_url = $UpstreamUrl
                    relative_path = 'core/demo'
                })
        }
        [System.IO.File]::WriteAllText($Path, ($manifest | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
    }

}
Describe 'Reference refresh origin identity guard' {
    BeforeAll {
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$refreshScript = Join-Path $repoRoot 'scripts\refresh-reference-repos.ps1'
}

    It 'fetches when the existing clone origin exactly matches the manifest upstream' {
        $fixture = New-ReferenceRefreshFixture -Root (Join-Path $TestDrive 'matching')
        $manifestPath = Join-Path $TestDrive 'matching-manifest.json'
        Write-ReferenceRefreshManifest -Path $manifestPath -ReferencesRoot $fixture.ReferencesRoot -UpstreamUrl $fixture.Remote

        $result = & $refreshScript -ManifestPath $manifestPath -OutputDirectory (Join-Path $TestDrive 'matching-reports') -FetchOnly

        $result.results[0].status | Should -Be 'fetch-only'
        (& git -C $fixture.Consumer rev-parse origin/main).Trim() | Should -Be $fixture.RemoteHead
    }

    It 'blocks a mismatched origin before fetch and reports both identities' {
        $fixture = New-ReferenceRefreshFixture -Root (Join-Path $TestDrive 'mismatch')
        $manifestPath = Join-Path $TestDrive 'mismatch-manifest.json'
        $expected = Join-Path $TestDrive 'different-remote.git'
        & git init --bare --initial-branch=main -q $expected
        Write-ReferenceRefreshManifest -Path $manifestPath -ReferencesRoot $fixture.ReferencesRoot -UpstreamUrl $expected

        $result = & $refreshScript -ManifestPath $manifestPath -OutputDirectory (Join-Path $TestDrive 'mismatch-reports') -FetchOnly

        $result.results[0].status | Should -Be 'origin-identity-mismatch'
        $result.results[0].expected_upstream | Should -Be $expected
        @($result.results[0].actual_origin) | Should -Be @($fixture.Remote)
        (& git -C $fixture.Consumer rev-parse origin/main).Trim() | Should -Be $fixture.ConsumerOriginBefore
        $report = Get-Content -LiteralPath $result.output_path -Raw -Encoding UTF8
        $report | Should -Match ([regex]::Escape(('期望 origin：`' + $expected + '`')))
        $report | Should -Match ([regex]::Escape(('实际 origin：`' + $fixture.Remote + '`')))
    }

    It 'blocks a missing origin before fetch and reports the missing identity' {
        $fixture = New-ReferenceRefreshFixture -Root (Join-Path $TestDrive 'missing')
        $manifestPath = Join-Path $TestDrive 'missing-manifest.json'
        Write-ReferenceRefreshManifest -Path $manifestPath -ReferencesRoot $fixture.ReferencesRoot -UpstreamUrl $fixture.Remote
        & git -C $fixture.Consumer remote remove origin

        $result = & $refreshScript -ManifestPath $manifestPath -OutputDirectory (Join-Path $TestDrive 'missing-reports') -FetchOnly

        $result.results[0].status | Should -Be 'origin-missing'
        $result.results[0].expected_upstream | Should -Be $fixture.Remote
        @($result.results[0].actual_origin).Count | Should -Be 0
    }

    It 'blocks multiple inconsistent origin fetch URLs before fetch' {
        $fixture = New-ReferenceRefreshFixture -Root (Join-Path $TestDrive 'multiple')
        $manifestPath = Join-Path $TestDrive 'multiple-manifest.json'
        $unexpected = Join-Path $TestDrive 'unexpected-remote.git'
        & git init --bare --initial-branch=main -q $unexpected
        & git -C $fixture.Consumer config --add remote.origin.url $unexpected
        Write-ReferenceRefreshManifest -Path $manifestPath -ReferencesRoot $fixture.ReferencesRoot -UpstreamUrl $fixture.Remote

        $result = & $refreshScript -ManifestPath $manifestPath -OutputDirectory (Join-Path $TestDrive 'multiple-reports') -FetchOnly

        $result.results[0].status | Should -Be 'origin-identity-mismatch'
        @($result.results[0].actual_origin).Count | Should -Be 2
        @($result.results[0].actual_origin) | Should -Contain $fixture.Remote
        @($result.results[0].actual_origin) | Should -Contain $unexpected
        (& git -C $fixture.Consumer rev-parse origin/main).Trim() | Should -Be $fixture.ConsumerOriginBefore
    }

    It 'treats equivalent local path and file URL forms as the same repository identity' {
        $fixture = New-ReferenceRefreshFixture -Root (Join-Path $TestDrive 'equivalent')
        $manifestPath = Join-Path $TestDrive 'equivalent-manifest.json'
        $fileUrl = ([System.Uri]::new($fixture.Remote)).AbsoluteUri
        Write-ReferenceRefreshManifest -Path $manifestPath -ReferencesRoot $fixture.ReferencesRoot -UpstreamUrl $fileUrl

        $result = & $refreshScript -ManifestPath $manifestPath -OutputDirectory (Join-Path $TestDrive 'equivalent-reports') -FetchOnly

        $result.results[0].status | Should -Be 'fetch-only'
        (& git -C $fixture.Consumer rev-parse origin/main).Trim() | Should -Be $fixture.RemoteHead
    }

    It 'treats GitHub HTTPS and SCP-style SSH forms as the same repository identity' {
        $fixture = New-ReferenceRefreshFixture -Root (Join-Path $TestDrive 'github-equivalent')
        $manifestPath = Join-Path $TestDrive 'github-equivalent-manifest.json'
        & git -C $fixture.Consumer remote set-url origin 'git@github.com:OpenAI/Codex.git'
        Set-Content -LiteralPath (Join-Path $fixture.Consumer 'dirty.txt') -Value 'keep this checkout offline' -Encoding UTF8
        Write-ReferenceRefreshManifest -Path $manifestPath -ReferencesRoot $fixture.ReferencesRoot -UpstreamUrl 'https://github.com/openai/codex.git'

        $result = & $refreshScript -ManifestPath $manifestPath -OutputDirectory (Join-Path $TestDrive 'github-equivalent-reports') -FetchOnly -SkipDirtyRepos

        $result.results[0].status | Should -Be 'skipped-dirty'
        $result.results[0].note | Should -Match 'dirty worktree; skipped by policy'
    }
}
