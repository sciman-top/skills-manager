BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src\Commands\AiCoding.ps1')
}

Describe 'ai-coding read-only templates' {
    It 'returns the checklist by default' {
        $result = Invoke-AiCodingCommand @()

        $result.exit_code | Should -Be 0
        $result.json | Should -BeFalse
        $result.output | Should -Match '\[ \]'
        $result.output | Should -Match 'Goal / Context / Constraints / Done when'
    }

    It 'supports JSON output for each public template' {
        foreach ($name in @('implementation', 'review', 'failure', 'handoff', 'checklist')) {
            $result = Invoke-AiCodingCommand @('--template', $name, '--json')
            $payload = $result.output | ConvertFrom-Json

            $result.json | Should -BeTrue
            $payload.command | Should -Be 'ai-coding'
            $payload.template | Should -Be $name
            $payload.truth_boundary | Should -Be 'read_only_template'
            $payload.writes | Should -Be 0
            $payload.provider_calls | Should -Be 0
            $payload.native_mutations | Should -Be 0
            $payload.content | Should -Not -BeNullOrEmpty
        }
    }

    It 'supports help and fails closed for unknown options or templates' {
        $help = Invoke-AiCodingCommand @('--help')
        $help.output | Should -Match 'implementation \| review \| failure \| handoff \| checklist'

        { Invoke-AiCodingCommand @('--unknown') } | Should -Throw '*Unknown ai-coding option*'
        { Invoke-AiCodingCommand @('--template', 'all') } | Should -Throw '*Unknown ai-coding template*'
    }
}
