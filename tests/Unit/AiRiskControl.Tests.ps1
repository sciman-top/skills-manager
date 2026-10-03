# Unit tests for the read-only ai-risk-control command surface.
# The --checks integration path spawns the bundled host self-check scripts; those
# scripts carry their own controlled acceptance fixtures, so these tests keep
# to argument parsing, asset inventory, and output contracts without spawning
# live diagnostics.

BeforeAll {
    . (Join-Path $PSScriptRoot '../../src/Commands/AiRiskControl.ps1')
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

    It 'rejects an unknown option' {
        { Parse-AiRiskControlArgs @('--bogus') } | Should -Throw
    }

    It 'rejects values outside the allowed sets' {
        { Parse-AiRiskControlArgs @('--platform', 'gemini') } | Should -Throw
        { Parse-AiRiskControlArgs @('--mode', 'tor') } | Should -Throw
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

