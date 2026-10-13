# Unit tests for the read-only ai-risk-control command surface.
# The command provides repository policy assets and triage plans. It does not
# spawn host self-check scripts or inspect account/client state.

BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src/Commands/AiRiskControl.ps1')
}

Describe 'Parse-AiRiskControlArgs' {
    It 'returns safe defaults for an empty token list' {
        $opts = Parse-AiRiskControlArgs @()
        $opts.platform | Should -Be 'all'
        $opts.json | Should -BeFalse
        $opts.help | Should -BeFalse
        $opts.out_path | Should -Be ''
        $opts.event | Should -Be ''
        $opts.plan | Should -BeFalse
        $opts.retry_after | Should -Be ''
        $opts.reset_at | Should -Be ''
    }

    It 'parses a full option set' {
        $opts = Parse-AiRiskControlArgs @('--platform', 'workbuddy', '--json', '--out', 'x.json')
        $opts.platform | Should -Be 'workbuddy'
        $opts.json | Should -BeTrue
        $opts.out_path | Should -Be 'x.json'
    }

    It 'parses the help flag' {
        $opts = Parse-AiRiskControlArgs @('--help')
        $opts.help | Should -BeTrue
    }

    It 'parses an incident plan request' {
        $opts = Parse-AiRiskControlArgs @('--event', 'workbuddy-rate-limit', '--plan', '--retry-after', '60', '--reset-at', '2026-10-04T00:00:00Z')
        $opts.event | Should -Be 'workbuddy-rate-limit'
        $opts.plan | Should -BeTrue
        $opts.retry_after | Should -Be '60'
        $opts.reset_at | Should -Be '2026-10-04T00:00:00Z'
    }

    It 'rejects an unknown option' {
        { Parse-AiRiskControlArgs @('--bogus') } | Should -Throw
        { Parse-AiRiskControlArgs @('--checks') } | Should -Throw
    }

    It 'rejects values outside the allowed sets' {
        { Parse-AiRiskControlArgs @('--platform', 'gemini') } | Should -Throw
        { Parse-AiRiskControlArgs @('--event', 'unknown') } | Should -Throw
        { Parse-AiRiskControlArgs @('--event', 'workbuddy-rate-limit', '--platform', 'antigravity') } | Should -Throw
        { Parse-AiRiskControlArgs @('--retry-after', '60') } | Should -Throw
    }

    It 'rejects flags that require a value' {
        { Parse-AiRiskControlArgs @('--platform') } | Should -Throw
        { Parse-AiRiskControlArgs @('--out') } | Should -Throw
    }
}

Describe 'Get-AiRiskControlAsset' {
    BeforeAll {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("airc-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $tmp 'sub') -Force | Out-Null
        Set-Content -Path (Join-Path $tmp 'file.txt') -Value 'x'
    }
    AfterAll {
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    }

    It 'classifies file, directory, and missing targets' {
        $file = Get-AiRiskControlAsset $tmp 'file.txt'
        $file.exists | Should -BeTrue
        $file.kind | Should -Be 'file'

        $dir = Get-AiRiskControlAsset $tmp 'sub'
        $dir.exists | Should -BeTrue
        $dir.kind | Should -Be 'directory'

        $missing = Get-AiRiskControlAsset $tmp 'nope.txt'
        $missing.exists | Should -BeFalse
        $missing.kind | Should -Be 'missing'
    }
}

Describe 'AI risk policy helpers' {
    It 'keeps a selected ban scenario distinct from a confirmed account ban' {
        $result = Get-AiRiskControlIncidentPlan 'antigravity-ban'
        $result.basis | Should -Match 'user_selected_scenario'
        $result.diagnosis | Should -Match 'service disabled.*一般 403.*权限、资格与认证'
        $result.immediate | Should -Contain '使用当前 Google 官方支持或反馈入口'
    }

    It 'separates Antigravity, Gemini API, and Gemini CLI quota diagnosis without retrying' {
        $result = Get-AiRiskControlIncidentPlan 'antigravity-rate-limit'
        $result.diagnosis | Should -Match 'Antigravity 订阅五小时/周额度.*Gemini API project/model/spend cap.*Gemini CLI 认证额度'
        $result.immediate -join ';' | Should -Match '停止当前请求的重试.*五小时刷新不保证周额度恢复'
        $result.immediate -join ';' | Should -Match '不自动换模型重放'
    }

    It 'triages output quality using visible model, output, and tool evidence' {
        $result = Get-AiRiskControlIncidentPlan 'antigravity-degradation'
        $result.diagnosis | Should -Match '可见模型.*上下文.*思考/采样参数.*输出截断.*工具失败'
        $result.immediate -join ';' | Should -Match 'finishReason/usage（若入口提供）.*具体遗漏'
        $result.immediate -join ';' | Should -Match '遇到 429、认证或明确服务拒绝时停止当前任务'
    }

    It 'does not invent a cooldown without a server hint' {
        $result = Get-AiRiskControlCooldown
        $result.state | Should -Be 'unknown'
        $result.automatic_retry | Should -BeFalse
    }

    It 'uses the later of Retry-After and reset-at as the review boundary' {
        $result = Get-AiRiskControlCooldown -RetryAfter '60' -ResetAt '2026-10-04T00:02:00Z' -Now ([datetimeoffset]'2026-10-04T00:00:00Z')
        $result.state | Should -Be 'server_hint'
        $result.earliest_review_at | Should -Match '00:02:00'
        $result.automatic_retry | Should -BeFalse
    }

}

Describe 'Invoke-AiRiskControlCommand' {
    BeforeAll {
        $repoRoot = (Get-Item (Join-Path $PSScriptRoot '../..')).FullName
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("airc-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    }
    AfterAll {
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    }

    It 'help returns usage and the read-only policy notes' {
        $result = Invoke-AiRiskControlCommand @('--help')
        $result.usage | Should -Match 'ai-risk-control'
        ($result.notes -join ' ') | Should -Match '默认只读|不运行宿主自检脚本'
    }

    It 'inventories repository assets without running host checks' {
        $result = Invoke-AiRiskControlCommand @()
        $result.command | Should -Be 'ai-risk-control'
        $result.schema_version | Should -Be 2
        $result.truth_boundary | Should -Be 'repo_verified'
        @($result.assets).Count | Should -Be 2
        @($result.assets | Where-Object { -not $_.exists }) | Should -BeNullOrEmpty
        $result.controls.repository_assets | Should -Be 'present'
        $result.acceptance.repo_verified | Should -BeTrue
        $result.status | Should -Be 'pass'
        $result.exit_code | Should -Be 0
        $result.policy.forbidden_operations | Should -Contain 'account_rotation_or_bulk_registration'
        $result.policy.platform_contracts.workbuddy.blocked | Should -Contain 'token extraction or connector-proxy bypass'
        @($result.policy.official_sources.url) | Should -Contain 'https://antigravity.google/docs/faq/'
        $result.policy.platform_contracts.antigravity.allowed | Should -Contain 'agy -p direct scripting or CI within the current FAQ'
        ($result.policy.platform_contracts.antigravity.allowed -join ';') | Should -Not -Match 'stable low-frequency egress'
        $result.policy.enforcement | Should -Be 'advisory_only; this command does not intercept host requests or enforce client concurrency'
        $result.status_scope | Should -Match 'not host_state'
        $result.side_effects -join ';' | Should -Match 'no host configuration reads or writes'
    }

    It 'returns a bounded incident plan without enabling a bypass' {
        $result = Invoke-AiRiskControlCommand @('--platform', 'workbuddy', '--event', 'workbuddy-account-risk', '--plan')
        $result.incident.category | Should -Be 'account_safety'
        $result.incident.severity | Should -Be 'critical'
        $result.plan.stop_conditions -join ';' | Should -Match '轮换|伪造|提取'
        $result.side_effects -join ';' | Should -Match 'no host configuration reads or writes'
    }

    It 'distinguishes generic 403 from explicit Antigravity service-disabled guidance' {
        $result = Invoke-AiRiskControlCommand @('--platform', 'antigravity', '--event', 'antigravity-ban')
        $result.incident.diagnosis | Should -Match '一般 403 仍需区分权限、资格与认证问题'
        $result.incident.immediate | Should -Contain '使用当前 Google 官方支持或反馈入口'
        ($result.incident.immediate -join ';') | Should -Not -Match '再认证'
    }

    It 'reports a server hinted cooldown without retrying' {
        $result = Invoke-AiRiskControlCommand @('--platform', 'workbuddy', '--event', 'workbuddy-rate-limit', '--retry-after', '60', '--plan')
        $result.cooldown.state | Should -Be 'server_hint'
        $result.cooldown.automatic_retry | Should -BeFalse
        $result.incident.basis | Should -Match 'user_selected_scenario'
    }

    It 'writes a JSON report when --out is given' {
        $out = Join-Path $tmp 'report.json'
        $null = Invoke-AiRiskControlCommand @('--json', '--out', $out)
        Test-Path $out | Should -BeTrue
        $report = Get-Content $out -Raw | ConvertFrom-Json
        $report.command | Should -Be 'ai-risk-control'
        $report.platform | Should -Be 'all'
    }
}

Describe 'CLI wiring contract' {
    It 'registers the command in the entrypoint ValidateSet' {
        $versionText = Get-Content (Join-Path $PSScriptRoot '../../src/Version.ps1') -Raw
        $versionText | Should -Match 'ai-risk-control'
        $versionText | Should -Match '风险控制'
    }
}

