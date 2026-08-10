Describe 'Host skill selection effectiveness evaluation' {
    BeforeAll {
        $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $scriptPath = Join-Path $repoRoot 'scripts\evaluate-host-skill-selection.ps1'
    }

    It 'Validates the P6 host-native selection corpus without legacy cold-load probes or model calls' {
        $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Json

        $LASTEXITCODE | Should Be 0
        $plan = ($raw -join "`n") | ConvertFrom-Json
        $plan.valid | Should Be $true
        $plan.execute | Should Be $false
        $plan.selection_case_count | Should Be 33
        $plan.cold_load_case_count | Should Be 0
        $plan.planned_calls | Should Be 33
        $plan.evaluation_cwd | Should Be 'isolated_non_repo_directory'
        $plan.real_profile_mutation_required | Should Be $false
        $plan.selection_execution_mode | Should Be 'host_native'

        $corpus = Get-Content -LiteralPath (Join-Path $repoRoot 'config\host-skill-selection-evaluation.json') -Raw | ConvertFrom-Json
        @($corpus.cases.category | Sort-Object -Unique).Count | Should Be 8
        @($corpus.cases | Where-Object language -eq 'zh').Count | Should Be 16
        @($corpus.cases | Where-Object language -eq 'en').Count | Should Be 17

        @($corpus.cases | Where-Object { $null -ne $_.cold_probe }).Count | Should Be 0
        foreach ($expectedNativeTarget in @{
            'direct-python-tests-en' = 'python-testing-patterns'
            'indirect-copy-edit-zh' = 'copy-editing'
            'indirect-cold-doc-zh' = 'doc-coauthoring'
            'negative-cold-ui-review-en' = 'web-design-guidelines'
            'ambiguous-cold-architecture-en' = 'codebase-design'
            'architecture-python-stack-en' = 'modern-python'
            'architecture-cold-dotnet-zh' = 'dotnet-backend-patterns'
            'side-effect-mcp-builder-en' = 'mcp-builder'
        }.GetEnumerator()) {
            $case = $corpus.cases | Where-Object id -eq $expectedNativeTarget.Key
            @($case.expected.required) | Should Contain $expectedNativeTarget.Value
            @($case.expected.required) | Should Not Contain 'capability-router'
        }

        $fallbackCase = $corpus.cases | Where-Object id -eq 'direct-policy-fallback-en'
        @($fallbackCase.expected.required) | Should Contain 'capability-router'
        $fallbackCase.explicit_fallback | Should Be $true

        $approvedPlanCase = $corpus.cases | Where-Object id -eq 'ambiguous-approved-plan-zh'
        @($approvedPlanCase.expected.required_any[0]) | Should Contain 'draft-tickets'
    }

    It 'Keeps legacy profile labels as read-only corpus metadata' {
        $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
            -CaseId 'direct-debug-zh,architecture-python-stack-en' -Mode selection -Json

        $LASTEXITCODE | Should Be 0
        $plan = ($raw -join "`n") | ConvertFrom-Json
        $plan.selection_case_count | Should Be 2
        $plan.cold_load_case_count | Should Be 0
        $plan.planned_calls | Should Be 2
        $plan.real_profile_mutation_required | Should Be $false
        $plan.profile_compatibility_mode | Should Be 'read_only_metadata'
    }

    It 'contains no profile mutation command or authorization switch' {
        $scriptText = Get-Content -LiteralPath $scriptPath -Raw
        $scriptText | Should Not Match 'AllowRealProfileMutation'
        $scriptText | Should Not Match 'Set-EvaluationProfile'
        $scriptText | Should Not Match "'技能配置'\s+'使用'"
    }

    It 'Keeps the retired cold-load mode as a zero-call compatibility surface' {
        $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Mode cold_load -Json

        $LASTEXITCODE | Should Be 0
        $plan = ($raw -join "`n") | ConvertFrom-Json
        $plan.selection_case_count | Should Be 0
        $plan.cold_load_case_count | Should Be 0
        $plan.planned_calls | Should Be 0
        $plan.real_profile_mutation_required | Should Be $false
    }

    It 'Accepts one semantically equivalent skill from a required-any group' {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        $functionAst = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ExpectationResult' }, $true)
        . ([scriptblock]::Create($functionAst.Extent.Text))

        $withoutAlternatives = Get-ExpectationResult ([pscustomobject]@{ required = @('target'); forbidden = @() }) @('target')
        $withoutAlternatives.pass | Should Be $true
        @($withoutAlternatives.missing).Count | Should Be 0

        $withAlternative = Get-ExpectationResult ([pscustomobject]@{ required = @(); required_any = @(, @('webapp-testing', 'playwright')); forbidden = @() }) @('playwright')
        $withAlternative.pass | Should Be $true
        @($withAlternative.missing).Count | Should Be 0

        $corpus = Get-Content -LiteralPath (Join-Path $repoRoot 'config\host-skill-selection-evaluation.json') -Raw | ConvertFrom-Json
        $browserCase = $corpus.cases | Where-Object id -eq 'side-effect-browser-test-zh'
        @($browserCase.expected.required_any[0]) | Should Contain 'playwright'
        @($browserCase.expected.required_any[0]) | Should Contain 'webapp-testing'
    }

    It 'models explicit router fallback as a named host invocation instead of implicit catalog selection' {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        $functionAst = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-HostSelectionPrompt' }, $true)
        ($null -ne $functionAst) | Should Be $true
        if ($null -ne $functionAst) {
            . ([scriptblock]::Create($functionAst.Extent.Text))
            $explicitPrompt = Get-HostSelectionPrompt ([pscustomobject]@{ request = 'validate policy'; explicit_fallback = $true })
            $ordinaryPrompt = Get-HostSelectionPrompt ([pscustomobject]@{ request = 'debug this'; explicit_fallback = $false })
            $explicitPrompt | Should Match '\$capability-router'
            $ordinaryPrompt | Should Not Match 'explicitly invoked `\$capability-router`'
        }
    }

    It 'Separates uncached input and command round metrics from cumulative cached usage' {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        foreach ($functionName in @('Get-HostUsageMetrics', 'Get-HostCommandMetrics')) {
            $functionAst = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName }, $true)
            ($null -ne $functionAst) | Should Be $true
            . ([scriptblock]::Create($functionAst.Extent.Text))
        }

        $events = @(
            [pscustomobject]@{ type = 'item.completed'; item = [pscustomobject]@{ id = '1'; type = 'command_execution'; command = 'route-capability.ps1 -Query q' } },
            [pscustomobject]@{ type = 'item.completed'; item = [pscustomobject]@{ id = '2'; type = 'command_execution'; command = 'Get-Content -Raw SKILL.md' } },
            [pscustomobject]@{ type = 'turn.completed'; usage = [pscustomobject]@{ input_tokens = 1000; cached_input_tokens = 800; output_tokens = 50 } }
        )

        $usage = Get-HostUsageMetrics $events
        $commands = Get-HostCommandMetrics $events
        $usage.uncached_input_tokens | Should Be 200
        $usage.cached_input_ratio | Should Be 0.8
        $commands.command_count | Should Be 2
        $commands.router_call_count | Should Be 1
        $commands.command_item_count | Should Be 2
        $commands.tool_round_count | Should BeNullOrEmpty
        $commands.tool_round_source | Should Be 'unavailable_from_exec_jsonl'
    }

    It 'Rejects unsafe case identifiers before execution' {
        $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -CaseId '../escape' -Json 2>&1

        $LASTEXITCODE | Should Not Be 0
        ($raw -join "`n") | Should Match 'no evaluation cases selected'
    }
}
