BeforeAll {
    . (Join-Path $PSScriptRoot '../../src/Main.ps1')
}

Describe 'CLI alias dispatch' {
    It 'routes <Command> once and preserves its arguments' -ForEach @(
        @{ Command = '安装MCP'; Expected = 'install'; Tokens = @('fixture', '--json') }
        @{ Command = 'mcp-install'; Expected = 'install'; Tokens = @('fixture', '--json') }
        # release-update returns a string only on its --json branch (the non-JSON branch
        # returns a PSObject), so this pins both the guard and the ASCII seam.
        @{ Command = 'release-update'; Expected = 'release'; Tokens = @('--json') }
        @{ Command = '发行更新'; Expected = 'release'; Tokens = @('--json') }
        @{ Command = 'ai-coding'; Expected = 'ai-coding'; Tokens = @('fixture', '--json') }
        @{ Command = 'AI编码'; Expected = 'ai-coding'; Tokens = @('fixture', '--json') }
        @{ Command = '帮助'; Expected = 'help'; Tokens = @() }
        @{ Command = 'help'; Expected = 'help'; Tokens = @() }
        @{ Command = '--help'; Expected = 'help'; Tokens = @() }
        @{ Command = '-h'; Expected = 'help'; Tokens = @() }
    ) {
        # Run the actual entrypoint with inert handlers in a disposable runspace:
        # its exit statement must not terminate Pester or invoke host mutations.
        $pipeline = [powershell]::Create()
        try {
            $driver = {
                param($MainPath, $Command)
                $Cmd = $Command
                $CommandArgs = @('--json')
                $Filter = 'fixture'
                $RunPlan = $true
                function Merge-FilterAndArgs($Filter, $Remaining) { return ,(@($Filter) + $Remaining) }
                # The dispatch seam escapes non-ASCII JSON for stdout; this runspace is
                # bare, so stub it — routing is what this test pins, not the escaping.
                function ConvertTo-AsciiJson([string]$Json) { return $Json }
                function 安装MCP($Tokens) { @{ handler = 'install'; tokens = @($Tokens) } | ConvertTo-Json -Compress }
                function Invoke-ReleaseUpdateCommand($Tokens) { @{ handler = 'release'; tokens = @($Tokens) } | ConvertTo-Json -Compress }
                function Invoke-AiCodingCommand($Tokens) { [pscustomobject]@{ handler = 'ai-coding'; tokens = @($Tokens); json = $true; output = (@{ handler = 'ai-coding'; tokens = @($Tokens) } | ConvertTo-Json -Compress); exit_code = 0 } }
                function 帮助 { @{ handler = 'help'; tokens = @() } | ConvertTo-Json -Compress }
                & $MainPath
            }
            $mainPath = Join-Path $PSScriptRoot '../../src/Main.ps1'
            $output = @($pipeline.AddScript($driver.ToString()).AddArgument($mainPath).AddArgument($Command).Invoke())
            $pipeline.HadErrors | Should -BeFalse
            $output.Count | Should -Be 1
            $record = $output[0] | ConvertFrom-Json
            $record.handler | Should -Be $Expected
            @($record.tokens).Count | Should -Be $Tokens.Count
            (@($record.tokens) -join '|') | Should -Be ($Tokens -join '|')
        }
        finally { $pipeline.Dispose() }
    }
}

Describe 'Unhandled command arguments fail closed' {
    It 'rejects extra tokens for commands that have no command-argument parser' {
        { Assert-NoUnhandledCommandArgs '构建生效' @('-Help') } |
            Should -Throw '*命令 ''构建生效'' 不支持额外参数：-Help*'
        { Assert-NoUnhandledCommandArgs '更新' @('--dry-run') } |
            Should -Throw '*命令 ''更新'' 不支持额外参数*'
    }

    It 'leaves command-owned argument parsers untouched' {
        { Assert-NoUnhandledCommandArgs 'ai-coding' @('--help') } | Should -Not -Throw
        { Assert-NoUnhandledCommandArgs '审查目标' @('列表') } | Should -Not -Throw
        { Assert-NoUnhandledCommandArgs '构建生效' @() } | Should -Not -Throw
    }

    It 'stops build dispatch before the handler executes' {
        $pipeline = [powershell]::Create()
        try {
            $driver = {
                param($MainPath)
                $Cmd = '构建生效'
                $CommandArgs = @('-Help')
                $Filter = ''
                $RunPlan = $false
                function Merge-FilterAndArgs($Filter, $Remaining) { return ,(@($Filter) + $Remaining) }
                function ConvertTo-AsciiJson([string]$Json) { return $Json }
                function Log {}
                function Write-Host {
                    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Messages)
                    Write-Output ($Messages -join ' ')
                }
                function 构建生效 { Write-Output 'BUILD_RAN' }
                & $MainPath
            }
            $mainPath = Join-Path $PSScriptRoot '../../src/Main.ps1'
            $output = @($pipeline.AddScript($driver.ToString()).AddArgument($mainPath).Invoke())
            ($output -join "`n") | Should -Match '不支持额外参数'
            ($output -join "`n") | Should -Not -Match 'BUILD_RAN'
        }
        finally { $pipeline.Dispose() }
    }
}
