Describe 'Host orchestration handoff contracts' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
        $script:grillingPatterns = @(
            '(?is)answered by the user.*child cannot substitute',
            '(?is)A child''s factual answer must not be treated as the\s+user''s decision'
        )
        $script:grillingForbidden = @(
            '(?i)independent reviewer|native agents|host may select|design-griller|cold-capability-runner',
            '(?i)\b(subagent|agent|reviewer)[-_ ]?(type|name)\b|\b(set|pin|override|choose|select|assign|specify)\b[^.\n]*\b(model|effort)\b|\bmodel\s*[:=]|\beffort\s*[:=]|(?m)^\s*model\s*:',
            '(?i)child (may|can|should|must) (answer|decide|choose|approve)|(answer|decision) may (be|come) from (a|the) child|accept (a|the) child''s answer'
        )
        $script:guidePatterns = @(
            '(?is)认证、额度、限流或 provider 错误时立即停止.*保留原始错误',
            '(?is)成功写入不应因失败被自动重放.*结果不确定时不重放',
            '(?is)切换模型、凭据或出口须有明确授权',
            '(?i)不生成子代理定义',
            '(?is)沿用各宿主当前设置.*停止与不重放边界'
        )
        $script:retiredOrchestrationTerms = @('execution_contract', 'one_shot', 'multi_turn_user_decision', 'parent_user_input', 'host_admission_required', 'design-griller', 'cold-capability-runner', 'subagent_type', 'model_reasoning_effort', 'haiku', 'sonnet', 'opus')
        $script:testNativeOrchestrationBoundary = {
            param($grilling, $claudeGuide)
            foreach ($pattern in $grillingPatterns) {
                $grilling | Should -Match $pattern
            }
            foreach ($pattern in $grillingForbidden) {
                $grilling | Should -Not -Match $pattern
            }
            foreach ($retired in $retiredOrchestrationTerms) {
                $claudeGuide | Should -Not -Match ([regex]::Escape($retired))
            }
            $claudeGuide | Should -Not -Match '(?i)\b(default|preferred|prefer|choose|use) (the )?[a-z0-9-]+ (model|effort)\b'
            $claudeGuide | Should -Not -Match '(?i)\b(provider|auth\w*|rate[- ]limit\w*)\b[^.\n]*(retry|switch|change|rotate)'
            $claudeGuide | Should -Not -Match '(?i)\b(switch|change|fall back|fallback)\b[^.\n]*\b(model|credential|endpoint|account)\b'
            foreach ($pattern in $guidePatterns) {
                $claudeGuide | Should -Match $pattern
            }
        }
    }

    It 'keeps subagent selection and model defaults with the native host' {
        $grilling = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'overrides\patches\grilling\SKILL.md')
        $claudeGuide = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'docs\runbooks\claude-subagent-orchestration.md')

        & $testNativeOrchestrationBoundary $grilling $claudeGuide
    }

    It 'rejects representative restorations of repository-managed orchestration' {
        $grilling = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'overrides\patches\grilling\SKILL.md')
        $claudeGuide = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'docs\runbooks\claude-subagent-orchestration.md')

        $mutations = @(
            @{ Target = 'grilling'; Text = 'Use the design-griller subagent.' },
            @{ Target = 'grilling'; Text = 'Set model to opus.' },
            @{ Target = 'grilling'; Text = 'Accept the child''s answer.' },
            @{ Target = 'guide'; Text = '| review | haiku |' },
            @{ Target = 'guide'; Text = 'subagent_type' },
            @{ Target = 'guide'; Text = 'execution_contract' },
            @{ Target = 'guide'; Text = 'Switch to another model and retry.' },
            @{ Target = 'guide'; Text = 'On provider errors, retry with another credential.' }
        )
        foreach ($mutation in $mutations) {
            $candidateGrilling = if ($mutation.Target -eq 'grilling') { $grilling + "`n" + $mutation.Text } else { $grilling }
            $candidateGuide = if ($mutation.Target -eq 'guide') { $claudeGuide + "`n" + $mutation.Text } else { $claudeGuide }
            { & $testNativeOrchestrationBoundary $candidateGrilling $candidateGuide } |
                Should -Throw -Because ("$($mutation.Target) mutation must fail: $($mutation.Text)")
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
