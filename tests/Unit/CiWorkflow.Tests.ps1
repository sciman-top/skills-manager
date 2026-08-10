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
        $script:workflow | Should Match '(?s)Rebuild locked skill sources.*skills\.ps1 更新 -Locked -SkipHostProjection.*Run repository full quality gate'
        $script:workflow | Should Not Match 'SkipPublisherCheck'
    }

    It 'avoids duplicate feature-branch push runs while retaining PR main and tag coverage' {
        $script:workflow | Should Match '(?ms)^on:\s*\r?\n\s+push:\s*\r?\n\s+branches:\s*\r?\n\s+- main\s*\r?\n\s+tags:\s*\r?\n\s+- ''\*''\s*\r?\n\s+pull_request:\s*$'
    }

    It 'keeps sample-dependent sync MCP performance observational in clean CI' {
        $script:workflow | Should Match '(?s)- name: Run repository full quality gate\s+shell: pwsh\s+run: \.\\scripts\\quality\\run-local-quality-gates\.ps1 -Profile full\s+- name: Observe sync MCP performance threshold'
        $script:workflow | Should Match '(?s)- name: Observe sync MCP performance threshold\s+shell: pwsh\s+run: \.\\scripts\\quality\\check-doctor-json\.ps1 -SyncMcpThresholdMs 12000 -WarnOnly'
        $script:workflow | Should Not Match '(?s)- name: Run repository full quality gate\s+shell: pwsh\s+env:'
    }
}
