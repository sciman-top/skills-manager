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
            Test-Path -LiteralPath (Join-Path $file.DirectoryName 'agents\openai.yaml') -PathType Leaf |
                Should -BeTrue -Because ($file.DirectoryName + ' must keep agents/openai.yaml aligned')
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
        $skill | Should -Match '(?is)Start with one narrow slice'
        $skill | Should -Match '(?is)existing\s+contract or a cross-cutting change.*independent proof'
        $skill | Should -Match '(?is)Tests must not only mirror mocks'
        $skill | Should -Match '(?is)change-detector'
        $skill | Should -Match '(?is)old failure.*before changing behavior'
        $skill | Should -Match '(?is)API, schema, or data changes.*every known consumer.*migration rollback'
        $skill | Should -Match '(?is)pre-existing baseline or sandbox/environment failures'
        $skill | Should -Match '(?is)On auth, quota, rate-limit or provider errors, stop and preserve the raw\s+error'
        $skill | Should -Match '(?is)Stop background servers/watchers.*remove temporary verification\s+files'
        $skill | Should -Match '(?is)generated\s+outputs.*source or generator.*check drift'
        $skill | Should -Match '(?is)no\s+source.*reproducible regeneration.*cleanup.*conformance test'
        $skill | Should -Match '(?is)dependencies only for a current need'
        $skill | Should -Match '(?is)Redact secrets from logs.*screenshots.*receipts'
        $skill | Should -Match '(?is)Verify candidate findings against callers, guards and tests'
        $skill | Should -Match '(?i)Report gaps, not style preferences'
    }

    It 'keeps patched core review and verification skills grounded in callers, baseline separation, and pipeline-safe evidence' {
        $review = Get-Content -LiteralPath (Join-Path $repoRoot 'overrides/patches/code-review-and-quality/SKILL.md') -Raw
        $review | Should -Match '(?i)inline'
        $review | Should -Match '(?is)verify it against reaching callers, guards, and existing tests'
        $review | Should -Match '(?is)Separate pre-existing base defects from regressions'

        $debug = Get-Content -LiteralPath (Join-Path $repoRoot 'overrides/patches/systematic-debugging/SKILL.md') -Raw
        $debug | Should -Match '(?is)isolate pre-existing baseline or\s+sandbox/environment failures'
        $debug | Should -Match '(?is)auth, quota, rate-limit, or\s+provider errors, stop and preserve the raw error'

        $verify = Get-Content -LiteralPath (Join-Path $repoRoot 'overrides/patches/verification-before-completion/SKILL.md') -Raw
        $verify | Should -Match '(?is)verify actual VCS diffs and command output'
    }

    It 'keeps checked-in skill instructions free of retired test files and local-only scratch paths' {
        $files = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'overrides/custom'), (Join-Path $repoRoot 'overrides/patches') -Recurse -File -Filter SKILL.md)
        foreach ($file in $files) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            $content | Should -Not -Match 'RuleEstate\.Tests\.ps1' -Because $file.FullName
            $content | Should -Not -Match 'artifacts/work/ai-session-verify' -Because $file.FullName
        }
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
        $guide | Should -Match 'https://developers\.openai\.com/codex/skills'
        $guide | Should -Match 'https://code\.claude\.com/docs/en/best-practices'
        $guide | Should -Match 'https://github\.com/github/spec-kit'
    }
}
