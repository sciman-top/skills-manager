Describe 'Host orchestration handoff contracts' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
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
