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

    It 'asks only about outcome-changing gaps after repository facts are checked' {
        $result = Invoke-AiCodingCommand @('--template', 'implementation')

        $result.output | Should -Match '会改变结果、权限或范围的关键缺口'
        $result.output | Should -Match '仓库事实或只读调查确定'
    }

    It 'grounds full-stack work in verified APIs and producer-consumer contracts' {
        $implementation = Invoke-AiCodingCommand @('--template', 'implementation')
        $review = Invoke-AiCodingCommand @('--template', 'review')
        $checklist = Invoke-AiCodingCommand @('--template', 'checklist')

        $implementation.output | Should -Match '禁止凭记忆编造 API、配置键、依赖、版本'
        $implementation.output | Should -Match '生产者与所有已知消费者'
        $review.output | Should -Match '虚构的 API、配置键、依赖或版本'
        $review.output | Should -Match '只验证 mock 调用'
        $checklist.output | Should -Match '贯通窄垂直切片'
        $checklist.output | Should -Match '秘密未进入日志或工件'
    }

    It 'supports help and fails closed for unknown options or templates' {
        $help = Invoke-AiCodingCommand @('--help')
        $help.output | Should -Match 'implementation \| review \| failure \| handoff \| checklist'

        { Invoke-AiCodingCommand @('--unknown') } | Should -Throw '*Unknown ai-coding option*'
        { Invoke-AiCodingCommand @('--template', 'all') } | Should -Throw '*Unknown ai-coding template*'
    }
}
