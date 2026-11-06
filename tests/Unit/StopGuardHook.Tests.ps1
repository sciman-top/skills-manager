BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
    $script:Hook = Join-Path $script:RepoRoot 'scripts\guard-stop-verification.ps1'
    function Invoke-StopGuard([string]$Json) {
        $output = @($Json | & pwsh -NoProfile -File $script:Hook 2>&1)
        return [pscustomobject]@{ exit_code = $LASTEXITCODE; output = ($output -join "`n") }
    }
    function New-StopEvent([string]$Message, [bool]$Active = $false) {
        return (@{ stop_hook_active = $Active; last_assistant_message = $Message } | ConvertTo-Json -Compress)
    }
}

Describe 'Stop guard is registered for Codex' {
    It 'declares a Stop hook that runs the shared verification guard from the git root' {
        $config = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.codex\config.toml') -Raw
        $config | Should -Match '(?m)^\[\[hooks\.Stop\]\]'
        $config | Should -Match 'guard-stop-verification\.ps1'
        $config | Should -Match 'git rev-parse --show-toplevel'
    }

    It 'requires a bounded timeout so the stop path cannot hang the turn' {
        # 用 `\r?$` 而不是 `$`：仓库按 .gitattributes 在 Windows 检出为 CRLF，
        # 只写 `$` 时行尾的 \r 会让断言在 CI 上失败而本地通过。
        $config = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.codex\config.toml') -Raw
        $stopBlock = [regex]::Match($config, '(?s)\[\[hooks\.Stop\]\].*$').Value
        $timeout = [regex]::Match($stopBlock, '(?m)^timeout = (?<t>\d+)\r?$')
        $timeout.Success | Should -BeTrue
        [int]$timeout.Groups['t'].Value | Should -BeLessOrEqual 600
    }
}

Describe 'Stop guard fails open on input it cannot interpret' {
    It 'allows malformed JSON' {
        (Invoke-StopGuard 'not json').exit_code | Should -Be 0
    }

    It 'allows a turn that this hook already continued' {
        # Without this the hook loops: every continuation would re-trigger it.
        (Invoke-StopGuard (New-StopEvent 'anything' $true)).exit_code | Should -Be 0
    }
}
