Describe 'CLI alias dispatch' {
    It 'routes <Command> once and preserves its arguments' -ForEach @(
        @{ Command = '规则全域应用'; Expected = 'apply'; Tokens = @('--plan', 'fixture', '--json') }
        @{ Command = 'rule-estate-apply'; Expected = 'apply'; Tokens = @('--plan', 'fixture', '--json') }
        @{ Command = 'RULE-ESTATE-APPLY'; Expected = 'apply'; Tokens = @('--plan', 'fixture', '--json') }
        @{ Command = '安装MCP'; Expected = 'install'; Tokens = @('fixture', '--json') }
        @{ Command = 'mcp-install'; Expected = 'install'; Tokens = @('fixture', '--json') }
        @{ Command = 'ai-risk-control'; Expected = 'risk'; Tokens = @('fixture', '--json') }
        @{ Command = '风险控制'; Expected = 'risk'; Tokens = @('fixture', '--json') }
        # release-update returns a string only on its --json branch (the non-JSON branch
        # returns a PSObject), so this pins both the guard and the ASCII seam.
        @{ Command = 'release-update'; Expected = 'release'; Tokens = @('--json') }
        @{ Command = '发行更新'; Expected = 'release'; Tokens = @('--json') }
        @{ Command = 'release-update-schedule'; Expected = 'release-schedule'; Tokens = @('--json') }
        @{ Command = '发行更新调度'; Expected = 'release-schedule'; Tokens = @('--json') }
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
                function Invoke-RuleEstateApplyCommand($Tokens) {
                    return [pscustomobject]@{
                        json = $true
                        output = (@{ handler = 'apply'; tokens = @($Tokens) } | ConvertTo-Json -Compress)
                        exit_code = 0
                    }
                }
                function 安装MCP($Tokens) { @{ handler = 'install'; tokens = @($Tokens) } | ConvertTo-Json -Compress }
                function Invoke-AiRiskControlCommand($Tokens) { [pscustomobject]@{ handler = 'risk'; tokens = @($Tokens) } }
                function Invoke-ReleaseUpdateCommand($Tokens) { @{ handler = 'release'; tokens = @($Tokens) } | ConvertTo-Json -Compress }
                function Invoke-ReleaseUpdateScheduleCommand($Tokens) { @{ handler = 'release-schedule'; tokens = @($Tokens) } | ConvertTo-Json -Compress }
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
