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

    It 'keeps GPT and GLM selection task-fit instead of imposing a fixed pipeline' {
        $skill = Get-Content -LiteralPath (Join-Path $repoRoot 'overrides/custom/ai-coding-workflow/SKILL.md') -Raw

        $skill | Should -Match '(?i)GPT/Codex and GLM/ZCode'
        $skill | Should -Match '(?i)not stages in a fixed\s+pipeline'
        $skill | Should -Match '(?i)same-task acceptance'
        $skill | Should -Match '(?i)current help, schema, documentation and actual inputs'
    }

    It 'keeps the reusable task contract and failure recovery in the resident entrypoint' {
        $skill = Get-Content -LiteralPath (Join-Path $repoRoot 'overrides/custom/ai-coding-workflow/SKILL.md') -Raw

        foreach ($field in @('Goal:', 'Context:', 'Constraints:', 'Exact write set:', 'Minimum proof:', 'Done when:', 'Stop:')) {
            $skill | Should -Match ([regex]::Escape($field))
        }
        $skill | Should -Match '(?i)After two\s+failed corrections'
        $skill | Should -Match '(?i)fresh/cleared or compacted context'
        $skill | Should -Match '(?i)evidence, not permission'
        $skill | Should -Match '(?i)Report gaps, not style preferences'
    }

    It 'keeps the resident context budget and comprehension rules explicit' {
        $skill = Get-Content -LiteralPath (Join-Path $repoRoot 'overrides/custom/ai-coding-workflow/SKILL.md') -Raw

        $skill | Should -Match '(?i)removing it\s+would cause a mistake'
        $skill | Should -Match '(?i)bloated resident\s+file makes the model\s+ignore the rules that matter'
        $skill | Should -Match '(?i)Load the rest just in time'
        $skill | Should -Match '(?i)Green checks prove behavior, not comprehension'
    }

    It 'retains the explicit-use constraint for strict TDD' {
        $metadata = Get-Content -LiteralPath (Join-Path $repoRoot 'overrides/patches/test-driven-development/agents/openai.yaml') -Raw
        $skill = Get-Content -LiteralPath (Join-Path $repoRoot 'overrides/patches/test-driven-development/SKILL.md') -Raw
        $metadata | Should -Match 'allow_implicit_invocation:\s*true'
        $skill | Should -Match '(?i)user explicitly requests strict TDD'
        $skill | Should -Match '(?i)Do not require TDD for routine implementation'
    }
}
