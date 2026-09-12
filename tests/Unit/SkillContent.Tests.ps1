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

    It 'retains the explicit-use constraint for strict TDD' {
        $metadata = Get-Content -LiteralPath (Join-Path $repoRoot 'overrides/patches/test-driven-development/agents/openai.yaml') -Raw
        $skill = Get-Content -LiteralPath (Join-Path $repoRoot 'overrides/patches/test-driven-development/SKILL.md') -Raw
        $metadata | Should -Match 'allow_implicit_invocation:\s*true'
        $skill | Should -Match '(?i)user explicitly requests strict TDD'
        $skill | Should -Match '(?i)Do not require TDD for routine implementation'
    }
}
