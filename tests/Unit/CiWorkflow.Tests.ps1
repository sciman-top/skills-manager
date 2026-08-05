Describe 'GitHub CI workflow supply-chain contract' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $script:workflow = Get-Content -LiteralPath (Join-Path $repoRoot '.github\workflows\ci.yml') -Raw
    }

    It 'pins checkout and the Pester package bytes and bounds job runtime' {
        $script:workflow | Should Match 'timeout-minutes:\s*20'
        $script:workflow | Should Match 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1'
        $script:workflow | Should Match '898210e1a30c52cd46ba317c2278a9324345214213aa2f7d6b7dfa7b98f37ac9'
        $script:workflow | Should Match 'Get-FileHash[^\r\n]+SHA256'
        $script:workflow | Should Match 'GITHUB_ENV'
        $script:workflow | Should Not Match 'SkipPublisherCheck'
    }
}
