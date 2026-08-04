Describe 'Cross-thread guard installer and doctor' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $installer = Join-Path $repoRoot 'scripts\hooks\Install-CrossThreadGuard.ps1'
        $doctor = Join-Path $repoRoot 'scripts\hooks\Test-CrossThreadGuard.ps1'
        $sourceHook = Join-Path $repoRoot 'scripts\hooks\block-cross-thread-send.ps1'
    }

    BeforeEach {
        $script:codexHome = Join-Path $TestDrive 'codex-home'
        $null = New-Item -ItemType Directory -Path $script:codexHome -Force
        $script:configPath = Join-Path $script:codexHome 'config.toml'
        $script:originalConfig = "approval_policy = `"never`"`n[features]`nhooks = true`n"
        Set-Content -LiteralPath $script:configPath -Value $script:originalConfig -NoNewline

        [ordered]@{
            description = 'existing hooks'
            hooks = [ordered]@{
                PostToolUse = @(
                    [ordered]@{
                        matcher = 'existing_tool'
                        hooks = @([ordered]@{ type = 'command'; command = 'existing.ps1' })
                    }
                )
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $script:codexHome 'hooks.json')
    }

    It 'installs to a stable host path, preserves other hooks, and never edits config.toml' {
        $receipt = & $installer -CodexHome $script:codexHome -SourceHookPath $sourceHook
        $receipt.status | Should Be 'installed_untrusted'
        (Get-Content -Raw -LiteralPath $script:configPath) | Should Be $script:originalConfig

        $hostHook = Join-Path $script:codexHome 'scripts\block-cross-thread-send.ps1'
        (Get-FileHash -Algorithm SHA256 -LiteralPath $hostHook).Hash | Should Be (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceHook).Hash

        $hooks = Get-Content -Raw -LiteralPath (Join-Path $script:codexHome 'hooks.json') | ConvertFrom-Json
        @($hooks.hooks.PostToolUse).Count | Should Be 1
        @($hooks.hooks.PreToolUse).Count | Should Be 1
        $hooks.hooks.PreToolUse[0].matcher | Should Be '*'
        $hooks.hooks.PreToolUse[0].hooks[0].command | Should Match ([regex]::Escape($hostHook))
        $hooks.hooks.PreToolUse[0].hooks[0].command | Should Match ([regex]::Escape($receipt.source_sha256))
    }

    It 'reports soft_guard_only until slash-hooks trust and a fresh-session live probe exist' {
        $null = & $installer -CodexHome $script:codexHome -SourceHookPath $sourceHook
        $result = & $doctor -CodexHome $script:codexHome -SourceHookPath $sourceHook
        $result.configuration_ready | Should Be $true
        $result.simulation_passed | Should Be $true
        $result.simulation_cases.direct_send_tool | Should Be $true
        $result.simulation_cases.multiline_shell_send | Should Be $true
        $result.simulation_cases.nested_shell_send | Should Be $true
        $result.simulation_cases.read_only_subexpression_send | Should Be $true
        $result.simulation_cases.reader_exec_option_send | Should Be $true
        $result.trust_status | Should Be 'unverified_requires_slash_hooks'
        $result.live_path_status | Should Be 'unverified_requires_fresh_session_probe'
        $result.specialized_path_boundary | Should Be 'guardrail_only'
        $result.overall | Should Be 'soft_guard_only'
    }
}
