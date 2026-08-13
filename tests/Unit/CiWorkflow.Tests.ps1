Describe 'GitHub CI workflow supply-chain contract' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $script:workflow = Get-Content -LiteralPath (Join-Path $repoRoot '.github\workflows\ci.yml') -Raw
    }

    It 'pins checkout and the Pester package bytes and bounds job runtime' {
        $script:workflow | Should -Match 'timeout-minutes:\s*20'
        $script:workflow | Should -Match 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1'
        $script:workflow | Should -Match 'Pester/6\.1\.0'
        $script:workflow | Should -Match '0207a75ea09f81b27c1ded44898b2bb3c845bafa02045bd64a39e26a53ca41b4'
        $script:workflow | Should -Match 'Get-FileHash[^\r\n]+SHA256'
        $script:workflow | Should -Match 'GITHUB_ENV'
        $script:workflow | Should -Match '(?s)Rebuild locked skill sources.*skills\.ps1 更新 -Locked -SkipHostProjection.*Run repository full quality gate'
        $script:workflow | Should -Not -Match 'SkipPublisherCheck'
    }

    It 'avoids duplicate feature-branch push runs while retaining PR main and tag coverage' {
        $script:workflow | Should -Match '(?ms)^on:\s*\r?\n\s+push:\s*\r?\n\s+branches:\s*\r?\n\s+- main\s*\r?\n\s+tags:\s*\r?\n\s+- ''\*''\s*\r?\n\s+pull_request:\s*$'
    }

    It 'runs the repository gate once in clean CI' {
        $script:workflow | Should -Match '(?s)- name: Run repository full quality gate\s+shell: pwsh\s+run: \.\\scripts\\quality\\run-local-quality-gates\.ps1 -Profile full'
        $script:workflow | Should -Not -Match '(?s)- name: Run repository full quality gate\s+shell: pwsh\s+env:'
    }

    It 'keeps tests read-only and grants release write access only to the tag job' {
        $script:workflow | Should -Match '(?ms)^permissions:\s*\r?\n\s+contents:\s*read\s*$'
        $script:workflow | Should -Match '(?ms)^  release:\s*\r?\n\s+if: startsWith\(github\.ref, ''refs/tags/v''\)\s*\r?\n\s+needs: test'
        $script:workflow | Should -Match '(?ms)^  release:.*?permissions:\s*\r?\n\s+contents:\s*write'
        $script:workflow | Should -Match '(?s)  release:.*?- name: Rebuild locked skill sources\s+shell: pwsh\s+run: \.\\skills\.ps1 更新 -Locked -SkipHostProjection\s+- name: Build release packages'
        @([regex]::Matches($script:workflow, '(?m)^\s+contents:\s*write\s*$')).Count | Should -Be 1
    }
}
