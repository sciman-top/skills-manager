BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\scripts\audit\invocation-evidence-lib.ps1')
}

Describe 'Invocation evidence parsing (field-order tolerant)' {
    It 'finds Skill and MCP tool-calls when fields are reordered' {
        $line = '{"response":{"candidates":[{"content":[{"toolName":"Skill","input":{"args":"x","skill":"capability-router"},"type":"tool-call"},{"toolCallId":"call_9","toolName":"mcp__microsoft-learn__microsoft_docs_search","input":{"query":"q"},"type":"tool-call"}]}]}}'
        $parsed = $line | ConvertFrom-Json
        $found = [System.Collections.Generic.List[object]]::new()
        Find-InvocationToolCalls -Node $parsed -Found $found

        $found.Count | Should -Be 2
        $skillNames = @($found | ForEach-Object { Get-InvocationSkillName $_ } | Where-Object { $_ })
        $skillNames | Should -Contain 'capability-router'
        $servers = @($found | ForEach-Object { Get-InvocationServerFromToolName ([string]$_.PSObject.Properties['toolName'].Value) } | Where-Object { $_ })
        $servers | Should -Contain 'microsoft-learn'
    }

    It 'accepts OpenAI-style string arguments for Skill calls' {
        $line = '{"choices":[{"message":{"tool_calls":[{"type":"tool-call","function":"ignored","toolName":"Skill","arguments":"{\"skill\":\"research\",\"args\":\"--deep\"}"}]}}]}'
        $parsed = $line | ConvertFrom-Json
        $found = [System.Collections.Generic.List[object]]::new()
        Find-InvocationToolCalls -Node $parsed -Found $found

        $found.Count | Should -Be 1
        Get-InvocationSkillName $found[0] | Should -Be 'research'
    }

    It 'ignores tool definitions and non tool-call records' {
        $line = '{"tools":[{"name":"Skill","description":"Execute a skill"},{"type":"tool-result","toolName":"Skill"}]}'
        $parsed = $line | ConvertFrom-Json
        $found = [System.Collections.Generic.List[object]]::new()
        Find-InvocationToolCalls -Node $parsed -Found $found

        $found.Count | Should -Be 0
    }

    It 'returns empty server for non-mcp tool names' {
        Get-InvocationServerFromToolName 'Bash' | Should -Be ''
        Get-InvocationServerFromToolName 'mcp__web-reader__read' | Should -Be 'web-reader'
    }
}
