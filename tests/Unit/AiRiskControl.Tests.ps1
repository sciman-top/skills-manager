# Unit tests for the read-only ai-risk-control command surface.
# The --checks integration path spawns the bundled host self-check scripts; those
# scripts carry their own controlled acceptance fixtures, so these tests keep
# to argument parsing, asset inventory, and output contracts without spawning
# live diagnostics.

BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    # Core.ps1 owns the bounded external-command reader the checks path uses.
    . (Join-Path $repoRoot 'src/Core.ps1')
    . (Join-Path $repoRoot 'src/Commands/AiRiskControl.ps1')
}

Describe 'Parse-AiRiskControlArgs' {
    It 'returns safe defaults for an empty token list' {
        $opts = Parse-AiRiskControlArgs @()
        $opts.platform | Should -Be 'all'
        $opts.mode | Should -Be 'auto'
        $opts.json | Should -BeFalse
        $opts.run | Should -BeFalse
        $opts.help | Should -BeFalse
        $opts.out_path | Should -Be ''
        $opts.v2ray_config | Should -Be ''
        $opts.event | Should -Be ''
        $opts.plan | Should -BeFalse
        $opts.retry_after | Should -Be ''
        $opts.reset_at | Should -Be ''
    }

    It 'parses a full option set' {
        $opts = Parse-AiRiskControlArgs @('--platform', 'workbuddy', '--mode', 'direct', '--json', '--checks', '--out', 'x.json', '--v2ray-config', 'guiNConfig.json')
        $opts.platform | Should -Be 'workbuddy'
        $opts.mode | Should -Be 'direct'
        $opts.json | Should -BeTrue
        $opts.run | Should -BeTrue
        $opts.out_path | Should -Be 'x.json'
        $opts.v2ray_config | Should -Be 'guiNConfig.json'
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
    }

    It 'rejects values outside the allowed sets' {
        { Parse-AiRiskControlArgs @('--platform', 'gemini') } | Should -Throw
        { Parse-AiRiskControlArgs @('--mode', 'tor') } | Should -Throw
        { Parse-AiRiskControlArgs @('--event', 'unknown') } | Should -Throw
        { Parse-AiRiskControlArgs @('--event', 'workbuddy-rate-limit', '--platform', 'antigravity') } | Should -Throw
        { Parse-AiRiskControlArgs @('--retry-after', '60') } | Should -Throw
    }

    It 'rejects flags that require a value' {
        { Parse-AiRiskControlArgs @('--platform') } | Should -Throw
        { Parse-AiRiskControlArgs @('--out') } | Should -Throw
        { Parse-AiRiskControlArgs @('--v2ray-config') } | Should -Throw
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

Describe 'Invoke-AiRiskControlReadOnlyCheck' {
    BeforeAll {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("airc-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $passScript = Join-Path $tmp 'pass.ps1'
        Set-Content -Path $passScript -Value "Write-Output 'marker-ok'; exit 0"
        $failScript = Join-Path $tmp 'fail.ps1'
        Set-Content -Path $failScript -Value "Write-Output 'marker-fail'; exit 1"
    }
    AfterAll {
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    }

    It 'reports not_available for a missing script' {
        $result = Invoke-AiRiskControlReadOnlyCheck (Join-Path $tmp 'missing.ps1')
        $result.status | Should -Be 'not_available'
        $result.exit_code | Should -BeNullOrEmpty
    }

    It 'reports pass with output for a zero-exit script' {
        $result = Invoke-AiRiskControlReadOnlyCheck $passScript
        $result.status | Should -Be 'pass'
        $result.exit_code | Should -Be 0
        $result.output | Should -Match 'marker-ok'
    }

    It 'reports findings for a non-zero exit script' {
        $result = Invoke-AiRiskControlReadOnlyCheck $failScript
        $result.status | Should -Be 'findings'
        $result.exit_code | Should -Be 1
        $result.output | Should -Match 'marker-fail'
    }

    It 'bounds a slow check with a timeout instead of hanging' {
        $slowScript = Join-Path $tmp 'slow.ps1'
        Set-Content -Path $slowScript -Value 'Start-Sleep -Seconds 30; exit 0'
        $result = Invoke-AiRiskControlReadOnlyCheck $slowScript -TimeoutSeconds 2
        $result.status | Should -Be 'timeout'
        $result.exit_code | Should -BeNullOrEmpty
    }
}

Describe 'AI risk policy helpers' {
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

    It 'redacts credentials and identifiers from check output' {
        $value = Protect-AiRiskControlOutput 'Bearer abc apiKey="secret" https://user:pass@example.com 12345678-1234-1234-1234-123456789abc'
        $value | Should -Not -Match 'abc|secret|user:pass|12345678-1234'
        $value | Should -Match '<redacted>'
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
        ($result.notes -join ' ') | Should -Match 'read.only|v2rayN'
    }

    It 'inventories repository assets without running host checks' {
        $result = Invoke-AiRiskControlCommand @()
        $result.command | Should -Be 'ai-risk-control'
        $result.schema_version | Should -Be 1
        $result.truth_boundary | Should -Be 'repo_verified'
        $result.network.mutation | Should -Be 'none'
        @($result.assets).Count | Should -Be 5
        @($result.assets | Where-Object { -not $_.exists }) | Should -BeNullOrEmpty
        $result.controls.repository_assets | Should -Be 'present'
        $result.acceptance.repo_verified | Should -BeTrue
        $result.status | Should -Be 'pass'
        $result.exit_code | Should -Be 0
        $result.policy.forbidden_operations | Should -Contain 'account_rotation_or_bulk_registration'
        $result.policy.platform_contracts.workbuddy.blocked | Should -Contain 'token extraction or connector-proxy bypass'
        $result.policy.enforcement | Should -Be 'advisory_only; this command does not intercept host requests or enforce client concurrency'
        @($result.checks).Count | Should -Be 0
        $result.side_effects -join ';' | Should -Match 'no configuration writes'
    }

    It 'hashes an explicit v2rayN config without mutating anything' {
        $cfg = Join-Path $tmp 'guiNConfig.json'
        Set-Content -Path $cfg -Value '{"SysProxyType":2}'
        $expected = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($cfg))).ToLowerInvariant()
        $result = Invoke-AiRiskControlCommand @('--v2ray-config', $cfg)
        $result.network.v2ray_config.exists | Should -BeTrue
        $result.network.v2ray_config.readable | Should -BeTrue
        $result.network.v2ray_config.sha256 | Should -Be $expected
        $result.network.mutation | Should -Be 'none'
    }

    It 'returns a bounded incident plan without enabling a bypass' {
        $result = Invoke-AiRiskControlCommand @('--platform', 'workbuddy', '--event', 'workbuddy-account-risk', '--plan')
        $result.incident.category | Should -Be 'account_safety'
        $result.incident.severity | Should -Be 'critical'
        $result.plan.stop_conditions -join ';' | Should -Match '轮换|伪造|提取'
        $result.side_effects -join ';' | Should -Match 'no configuration writes'
    }

    It 'reports a server hinted cooldown without retrying' {
        $result = Invoke-AiRiskControlCommand @('--platform', 'workbuddy', '--event', 'workbuddy-rate-limit', '--retry-after', '60', '--plan')
        $result.cooldown.state | Should -Be 'server_hint'
        $result.cooldown.automatic_retry | Should -BeFalse
        $result.incident.basis | Should -Match 'user_selected_scenario'
    }

    It 'reports not_configured rather than a risk finding when the antigravity deployment root is absent' {
        $previous = $env:AG_RISK_V2RAY_ROOT
        $env:AG_RISK_V2RAY_ROOT = Join-Path $tmp 'no-such-v2rayN'
        try {
            $result = Invoke-AiRiskControlCommand @('--platform', 'antigravity', '--checks')
            @($result.checks).Count | Should -Be 1
            $result.checks[0].status | Should -Be 'not_configured'
            $result.status | Should -Be 'pass'
            $result.exit_code | Should -Be 0
        }
        finally { $env:AG_RISK_V2RAY_ROOT = $previous }
    }

    It 'declares which host check variant was used' {
        $result = Invoke-AiRiskControlCommand @()
        $result.check_variants.workbuddy | Should -Match 'MCP'
        $result.check_variants.timeout_seconds | Should -Be 180
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

