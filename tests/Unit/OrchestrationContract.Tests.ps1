Describe 'Host orchestration handoff contracts' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    }

    It 'keeps orchestration implementation and host agent templates retired' {
        $claudeGuide = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'docs\runbooks\claude-subagent-orchestration.md')
        $retiredPaths = @(
            'src\Application\NativeAgentBridge.ps1',
            'src\Domain\ExecutionAdmission.ps1',
            'overrides\resources\native-agent-bridge'
        )
        foreach ($path in $retiredPaths) {
            Test-Path -LiteralPath (Join-Path $repoRoot $path) | Should -BeFalse -Because $path
        }
        $claudeGuide | Should -Match '(?is)由 Claude Code 及其用户配置决定'
        $claudeGuide | Should -Match '(?is)认证、额度、限流或 provider 错误时立即停止'
        $claudeGuide | Should -Match '(?is)结果不确定时不重放'
    }

    It 'makes the high-value PowerPoint audit skill explicit and negatively scoped' {
        $metadata = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'overrides\custom\custom-powerpoint-accessibility\agents\openai.yaml')
        $config = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'skills.json') | ConvertFrom-Json

        $metadata | Should -Match 'allow_implicit_invocation:\s*true'
        $metadata | Should -Match 'only to audit or validate a PPT/PPTX'
        $metadata | Should -Match 'do not use it to create slides'
        $metadata | Should -Match 'format-only conversion'
        @($config.skill_projection.discovery_catalog.domain_memberships.ppt) | Should -Contain 'custom-powerpoint-accessibility'
    }
}
