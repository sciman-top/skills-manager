Describe 'find-skills Windows fallback' {
    BeforeEach {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $script:search = Join-Path $repoRoot 'overrides\patches\find-skills\scripts\search-skills.ps1'
        $script:cache = Join-Path $TestDrive 'npm-cache'
        $script:packageRoot = Join-Path $cache '_npx\fixture\node_modules\skills'
        $script:cli = Join-Path $packageRoot 'bin\cli.mjs'
        New-Item -ItemType Directory -Path (Split-Path $cli -Parent) -Force | Out-Null
        Set-Content -LiteralPath $cli -Encoding UTF8 -Value 'fixture'
        [ordered]@{
            name = 'skills'
            version = '1.2.3'
            bin = [ordered]@{ skills = './bin/cli.mjs' }
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $packageRoot 'package.json') -Encoding UTF8
        $script:node = Join-Path $TestDrive 'fake-node.ps1'
        @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Remaining)
$Remaining | ConvertTo-Json -Compress
'@ | Set-Content -LiteralPath $node -Encoding UTF8
    }

    It 'runs the validated cached JS CLI with the exact query and owner' {
        $result = & $search -Query 'react performance' -Owner 'vercel-labs' -NpmCacheRoot $cache -NodeCommand $node -NoCacheHydration | ConvertFrom-Json

        $result[0] | Should -Be $cli
        $result[1] | Should -Be 'find'
        $result[2] | Should -Be 'react performance'
        $result[3] | Should -Be '--owner'
        $result[4] | Should -Be 'vercel-labs'
    }

    It 'fails closed when the cached package identity is invalid' {
        $manifestPath = Join-Path $packageRoot 'package.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.name = 'lookalike-skills'
        $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

        { & $search -Query 'react' -NpmCacheRoot $cache -NodeCommand $node -NoCacheHydration } |
            Should -Throw 'No validated cached Skills CLI was found. Run npx skills once with network access, then retry.'
    }

    It 'rejects a manifest whose skills bin does not name the expected entrypoint' {
        $manifestPath = Join-Path $packageRoot 'package.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.bin.skills = './bin/other.mjs'
        $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

        { & $search -Query 'react' -NpmCacheRoot $cache -NodeCommand $node -NoCacheHydration } |
            Should -Throw 'No validated cached Skills CLI was found. Run npx skills once with network access, then retry.'
    }

    It 'rejects a cached package junction that escapes the npm cache' {
        Remove-Item -LiteralPath $packageRoot -Recurse -Force
        $outside = Join-Path $TestDrive 'outside-skills'
        New-Item -ItemType Directory -Path (Join-Path $outside 'bin') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $outside 'bin\cli.mjs') -Encoding UTF8 -Value 'outside'
        '{"name":"skills","version":"1.2.3","bin":{"skills":"./bin/cli.mjs"}}' |
            Set-Content -LiteralPath (Join-Path $outside 'package.json') -Encoding UTF8
        New-Item -ItemType Junction -Path $packageRoot -Target $outside | Out-Null

        { & $search -Query 'react' -NpmCacheRoot $cache -NodeCommand $node -NoCacheHydration } |
            Should -Throw 'No validated cached Skills CLI was found. Run npx skills once with network access, then retry.'
    }

    It 'does not embed a global install or PATH mutation' {
        $source = Get-Content -LiteralPath $search -Raw
        $source | Should -Not -Match 'npm\s+install\s+-g'
        $source | Should -Not -Match '\$env:PATH\s*='
        $source | Should -Match 'npx\.cmd'
        $source | Should -Match 'node_modules\\skills'
    }
}
