BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
    . (Join-Path $repoRoot 'src\Domain\RuleDocument.ps1')
    . (Join-Path $repoRoot 'src\Domain\RuleResponsibility.ps1')
    . (Join-Path $repoRoot 'src\Application\RuleAdvisor.ps1')

}
Describe 'Responsibility coverage and semantic advisor' {
    It 'records a covered global plus project action contract' {
        $constraints = @([pscustomobject]@{ constraint_id = 'R1'; common_intent = 'Declare destination'; platform_deltas = @('codex'); project_actions = @('repo path'); enforcement_refs = @('script'); evidence = @('AGENTS.md'); need_kind = 'project_guidance' })
        $result = Invoke-RuleAdvisor -Constraints $constraints

        $result.coverage[0].coverage | Should -Be 'covered'
        $result.recommendations[0].disposition | Should -Be 'adopt'
        $result.recommendations[0].surface | Should -Be 'AGENTS.md'
        $result.recommendations[0].blocking | Should -Be $false
    }

    It 'reports gaps conflicts duplicates and bounded not_applicable states' {
        $constraints = @(
            [pscustomobject]@{ constraint_id = 'gap'; common_intent = 'x'; project_actions = @(); evidence = @() },
            [pscustomobject]@{ constraint_id = 'conflict'; common_intent = 'x'; project_actions = @('a'); conflict = $true; evidence = @('e') },
            [pscustomobject]@{ constraint_id = 'duplicate'; common_intent = 'x'; project_actions = @('same'); enforcement_refs = @('same'); evidence = @('e') },
            [pscustomobject]@{ constraint_id = 'na'; common_intent = 'x'; not_applicable = $true; recovery_condition = 'when data exists'; evidence = @('e') }
        )
        $result = Invoke-RuleAdvisor -Constraints $constraints

        (@($result.coverage.coverage | Sort-Object) -join ',') | Should -Be 'conflict,duplicated,gap,not_applicable'
        $result.blocking_count | Should -Be 0
        $result.provider_calls | Should -Be 0
    }

    It 'flags responsibility scope mismatch as recommendation-only semantic finding' {
        $document = New-RuleDocument -Host codex -Scope global -Responsibility project_action -Path 'global/AGENTS.md' -Owner user -ByteSize 0 -DiscoveryState observed -SourceOfTruth fixture
        $result = Invoke-RuleAdvisor -Documents @($document)

        @($result.findings | Where-Object code -eq responsibility_scope_mismatch).Count | Should -Be 1
        $result.findings[0].kind | Should -Be 'semantic'
        $result.findings[0].blocking | Should -Be $false
    }

    It 'routes reusable and enforceable needs to the smallest matching official surface' {
        $constraints = @(
            [pscustomobject]@{ constraint_id = 'workflow'; common_intent = 'x'; project_actions = @('a'); need_kind = 'repeatable_workflow' },
            [pscustomobject]@{ constraint_id = 'external'; common_intent = 'x'; project_actions = @('a'); need_kind = 'external_data_or_action' },
            [pscustomobject]@{ constraint_id = 'enforce'; common_intent = 'x'; project_actions = @('a'); need_kind = 'deterministic_enforcement' }
        )
        $result = Invoke-RuleAdvisor -Constraints $constraints

        (@($result.recommendations.surface) -join ',') | Should -Be 'hook_config_script_or_ci,mcp_or_connector,skill'
    }
}
