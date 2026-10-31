BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src/Domain/SkillMetadata.ps1')
}

Describe 'Checked-in skill content' {
    It 'keeps override entrypoints parseable without rebuilding imported sources' {
        $files = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'overrides/custom'), (Join-Path $repoRoot 'overrides/patches') -Recurse -File -Filter SKILL.md)
        $files.Count | Should -BeGreaterThan 0
        foreach ($file in $files) {
            $metadata = Read-SkillMetadata $file.FullName
            $metadata.valid | Should -BeTrue -Because ($file.FullName + ': ' + ($metadata.findings.code -join ', '))
        }
    }

    It 'exposes the daily workflow and retains its evidence boundary identifiers' {
        $config = Get-Content -LiteralPath (Join-Path $repoRoot 'skills.json') -Raw | ConvertFrom-Json
        @($config.skill_projection.discovery_catalog.domain_memberships.coding) | Should -Contain 'ai-coding-workflow'
        $skill = Get-Content -LiteralPath (Join-Path $repoRoot 'overrides/custom/ai-coding-workflow/SKILL.md') -Raw
        foreach ($boundary in @('repo_verified', 'filesystem_projected', 'host_loaded', 'live_accepted')) {
            $skill | Should -Match ([regex]::Escape($boundary))
        }
    }

    It 'keeps the reusable task contract and failure recovery in the resident entrypoint' {
        $skill = Get-Content -LiteralPath (Join-Path $repoRoot 'overrides/custom/ai-coding-workflow/SKILL.md') -Raw

        $skill | Should -Match '(?i)full-stack'
        foreach ($field in @('Goal:', 'Context:', 'Constraints:', 'Exact write set:', 'Minimum proof:', 'Done when:', 'Stop:')) {
            $skill | Should -Match ([regex]::Escape($field))
        }
        $skill | Should -Match '(?is)After two failed corrections.*ask the user\s+for clarification'
        $skill | Should -Match '(?i)handoff does not replace clarification'
        $skill | Should -Match '(?i)evidence, not permission'
        $skill | Should -Match '(?is)untrusted\s+evidence.*embedded\s+commands'
        $skill | Should -Match '(?is)preview/dry-run external/host writes.*rollback/compensation'
        $skill | Should -Match '(?is)never reconstruct APIs.*from memory'
        $skill | Should -Match '(?is)vertical slice.*UI/API/service/data'
        $skill | Should -Match '(?is)Tests must not only mirror mocks'
        $skill | Should -Match '(?is)API, schema, or data changes.*every known consumer.*migration rollback'
        $skill | Should -Match '(?is)Redact secrets from logs.*screenshots.*receipts'
        $skill | Should -Match '(?i)Report gaps, not style preferences'
    }

    It 'retains the explicit-use constraint for strict TDD' {
        $metadata = Get-Content -LiteralPath (Join-Path $repoRoot 'overrides/patches/test-driven-development/agents/openai.yaml') -Raw
        $skill = Get-Content -LiteralPath (Join-Path $repoRoot 'overrides/patches/test-driven-development/SKILL.md') -Raw
        $metadata | Should -Match 'allow_implicit_invocation:\s*true'
        $skill | Should -Match '(?i)user explicitly requests strict TDD'
        $skill | Should -Match '(?i)Do not require TDD for routine implementation'
    }

    It 'keeps the reference guide evidence-backed and focused on recurring AI coding failures' {
        $guide = Get-Content -LiteralPath (Join-Path $repoRoot 'docs/product/ai-coding-workflow-guide.md') -Raw

        $guide | Should -Match '## 3\. 常见失效模式与防线'
        $guide | Should -Match '虚构 API 或依赖'
        $guide | Should -Match '测试假阳性'
        $guide | Should -Match '全栈接缝断裂'
        $guide | Should -Match 'https://developers\.openai\.com/codex/prompting'
        $guide | Should -Match 'https://code\.claude\.com/docs/en/best-practices'
        $guide | Should -Match 'https://github\.com/github/spec-kit'
    }
}
