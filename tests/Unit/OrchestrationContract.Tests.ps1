Describe 'Host orchestration handoff contracts' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    }

    It 'requires bounded scope, routing hints, and parent-observed completion evidence' {
        $template = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'overrides\resources\requesting-code-review\code-reviewer.md')

        $template | Should -Match 'actual_model: parent_observed_from_session_metadata'
        $template | Should -Match 'actual_reasoning_effort: parent_observed_from_session_metadata'
        $template | Should -Match 'fallback: none \| serial \| blocked'
    }

    It 'keeps model selection as a task-shape hypothesis with parent-observed evidence' {
        $template = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'overrides\resources\requesting-code-review\code-reviewer.md')

        foreach ($profile in @('sol_xhigh_supervisor', 'sol_medium_worker', 'terra_xhigh_worker', 'terra_high_worker')) {
            $template | Should -Match ([regex]::Escape($profile))
        }
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
