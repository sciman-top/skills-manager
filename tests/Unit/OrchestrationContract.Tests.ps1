Describe 'Host orchestration handoff contracts' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    }

    It 'keeps subagent selection and model defaults with the native host' {
        $grilling = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'overrides\patches\grilling\SKILL.md')
        $claudeGuide = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'docs\runbooks\claude-subagent-orchestration.md')

        $grilling | Should -Not -Match '(?i)independent reviewer|native agents|host may select'
        foreach ($retired in @('execution_contract', 'one_shot', 'multi_turn_user_decision', 'host_admission_required', 'design-griller', 'cold-capability-runner')) {
            $claudeGuide | Should -Not -Match ([regex]::Escape($retired))
        }
        $claudeGuide | Should -Match '(?i)不生成子代理定义'
        $claudeGuide | Should -Match '(?i)不固定模型档位'
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
