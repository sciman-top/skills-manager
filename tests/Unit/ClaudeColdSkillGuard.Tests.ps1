BeforeAll {
    $script:claudeColdSkillGuardPath = Join-Path $PSScriptRoot '..\..\scripts\hooks\claude-cold-skill-guard.ps1'
    function Invoke-ClaudeColdSkillGuardProbe {
        param(
            [Parameter(Mandatory)]
            [hashtable]$InputObject,
            [Parameter(Mandatory)]
            [string]$StateRoot
        )

        $json = $InputObject | ConvertTo-Json -Depth 40 -Compress
        $env:SKILLS_MANAGER_COLD_ROUTER_STATE_ROOT = $StateRoot
        $output = $json | & pwsh -NoProfile -File $script:claudeColdSkillGuardPath 2>$null
        if ($LASTEXITCODE -ne 0) { throw "guard exit code $LASTEXITCODE" }
        if (@($output).Count -eq 0) { return $null }
        return ($output -join "`n") | ConvertFrom-Json -Depth 20
    }
}

Describe 'Claude cold-skill source guard' {
    BeforeAll {
        $script:stateRoot = Join-Path $TestDrive 'cold-router-state'
        New-Item -ItemType Directory -Path $script:stateRoot -Force | Out-Null
    }

    It 'blocks direct imports reads before routing' {
        $result = Invoke-ClaudeColdSkillGuardProbe @{ hook_event_name = 'PreToolUse'; session_id = 's-direct'; tool_name = 'Bash'; tool_input = @{ command = 'cat imports/codebase-design/skills/engineering/codebase-design/SKILL.md' } } $script:stateRoot
        $result.hookSpecificOutput.permissionDecision | Should -Be 'deny'
    }

    It 'blocks direct Read tool access to vendor and agent before routing' {
        $result = Invoke-ClaudeColdSkillGuardProbe @{ hook_event_name = 'PreToolUse'; session_id = 's-read'; tool_name = 'Read'; tool_input = @{ file_path = 'D:\CODE\skills-manager\agent\codebase-design\SKILL.md' } } $script:stateRoot
        $result.hookSpecificOutput.permissionDecision | Should -Be 'deny'
    }

    It 'blocks PowerShell and search-tool cold source access before routing' {
        $result = Invoke-ClaudeColdSkillGuardProbe @{ hook_event_name = 'PreToolUse'; session_id = 's-powershell'; tool_name = 'PowerShell'; tool_input = @{ command = 'Get-Content imports/codebase-design/SKILL.md' } } $script:stateRoot
        $result.hookSpecificOutput.permissionDecision | Should -Be 'deny'
        $result = Invoke-ClaudeColdSkillGuardProbe @{ hook_event_name = 'PreToolUse'; session_id = 's-grep'; tool_name = 'Grep'; tool_input = @{ pattern = 'deep module'; path = 'vendor/codebase-design' } } $script:stateRoot
        $result.hookSpecificOutput.permissionDecision | Should -Be 'deny'
    }

    It 'records a validated closure after a successful router result' {
        $route = @{ load_validation = @{ pass = $true }; validated_closure = @(@{ name = 'codebase-design' }) } | ConvertTo-Json -Depth 10 -Compress
        $result = Invoke-ClaudeColdSkillGuardProbe @{ hook_event_name = 'PostToolUse'; session_id = 's-route'; tool_name = 'Bash'; tool_input = @{ command = 'pwsh -File ~/.claude/skills/capability-router/scripts/route-capability.ps1 -AutoDiscover' }; tool_response = $route } $script:stateRoot
        $result | Should -BeNullOrEmpty
        $state = Get-Content -Raw (Join-Path $script:stateRoot 's-route.json') | ConvertFrom-Json
        $state.validated_skill_names | Should -Contain 'codebase-design'
    }

    It 'parses structured Bash stdout from a router PostToolUse event' {
        $route = @{ load_validation = @{ pass = $true }; validated_closure = @(@{ name = 'domain-modeling' }) } | ConvertTo-Json -Depth 10 -Compress
        Invoke-ClaudeColdSkillGuardProbe @{ hook_event_name = 'PostToolUse'; session_id = 's-structured'; tool_name = 'Bash'; tool_input = @{ command = 'pwsh -File ~/.claude/skills/capability-router/scripts/route-capability.ps1 -AutoDiscover' }; tool_response = @{ stdout = $route; stderr = ''; exit_code = 0 } } $script:stateRoot | Out-Null
        $result = Invoke-ClaudeColdSkillGuardProbe @{ hook_event_name = 'PreToolUse'; session_id = 's-structured'; tool_name = 'Bash'; tool_input = @{ command = 'cat agent/domain-modeling/SKILL.md' } } $script:stateRoot
        $result | Should -BeNullOrEmpty
    }

    It 'allows only the validated agent closure after routing' {
        $route = @{ load_validation = @{ pass = $true }; validated_closure = @(@{ name = 'codebase-design' }) } | ConvertTo-Json -Depth 10 -Compress
        Invoke-ClaudeColdSkillGuardProbe @{ hook_event_name = 'PostToolUse'; session_id = 's-allow'; tool_name = 'Bash'; tool_input = @{ command = 'pwsh -File ~/.claude/skills/capability-router/scripts/route-capability.ps1 -AutoDiscover' }; tool_response = $route } $script:stateRoot | Out-Null
        $result = Invoke-ClaudeColdSkillGuardProbe @{ hook_event_name = 'PreToolUse'; session_id = 's-allow'; tool_name = 'Bash'; tool_input = @{ command = 'cat agent/codebase-design/SKILL.md' } } $script:stateRoot
        $result | Should -BeNullOrEmpty
        $result = Invoke-ClaudeColdSkillGuardProbe @{ hook_event_name = 'PreToolUse'; session_id = 's-allow'; tool_name = 'Bash'; tool_input = @{ command = 'cat agent/domain-modeling/SKILL.md' } } $script:stateRoot
        $result.hookSpecificOutput.permissionDecision | Should -Be 'deny'
    }

    It 'fails closed for stale state' {
        $path = Join-Path $script:stateRoot 's-stale.json'
        @{ schema_version = 1; session_id = 's-stale'; expires_at = '2000-01-01T00:00:00Z'; validated_skill_names = @('codebase-design') } | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding utf8NoBOM
        $result = Invoke-ClaudeColdSkillGuardProbe @{ hook_event_name = 'PreToolUse'; session_id = 's-stale'; tool_name = 'Bash'; tool_input = @{ command = 'cat agent/codebase-design/SKILL.md' } } $script:stateRoot
        $result.hookSpecificOutput.permissionDecision | Should -Be 'deny'
    }
}
