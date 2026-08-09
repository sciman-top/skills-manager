Describe 'Cross-thread guard installer and doctor' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $installer = Join-Path $repoRoot 'scripts\hooks\Install-CrossThreadGuard.ps1'
        $doctor = Join-Path $repoRoot 'scripts\hooks\Test-CrossThreadGuard.ps1'
        $sourceHook = Join-Path $repoRoot 'scripts\hooks\block-cross-thread-send.ps1'
        $sourcePolicy = Join-Path $repoRoot 'scripts\hooks\CrossThreadGuardPolicy.ps1'
    }

    BeforeEach {
        $script:codexHome = Join-Path $TestDrive ('codex-home-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $script:codexHome -Force
        $script:configPath = Join-Path $script:codexHome 'config.toml'
        $script:originalConfig = "approval_policy = `"never`"`n[features]`nhooks = true`n"
        Set-Content -LiteralPath $script:configPath -Value $script:originalConfig -NoNewline
        [ordered]@{
            description = 'existing hooks'
            hooks = [ordered]@{
                PostToolUse = @([ordered]@{ matcher='existing_tool'; hooks=@([ordered]@{ type='command'; command='existing.ps1' }) })
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $script:codexHome 'hooks.json')
    }

    It 'keeps trusted hook bytes stable across checkouts' {
        $attributes = Get-Content -Raw -LiteralPath (Join-Path $repoRoot '.gitattributes')
        $attributes | Should Match '(?m)^scripts/hooks/block-cross-thread-send\.ps1 text eol=lf\r?$'
        $attributes | Should Match '(?m)^scripts/hooks/CrossThreadGuardPolicy\.ps1 text eol=lf\r?$'
        @([System.IO.File]::ReadAllBytes($sourceHook) | Where-Object { $_ -eq 13 }).Count | Should Be 0
        @([System.IO.File]::ReadAllBytes($sourcePolicy) | Where-Object { $_ -eq 13 }).Count | Should Be 0
    }

    It 'installs revision 6 generic cross-thread guard and preserves unrelated hooks' {
        $receipt = & $installer -CodexHome $script:codexHome -SourceHookPath $sourceHook
        $receipt.status | Should Be 'installed_untrusted'
        $receipt.policy_revision | Should Be 6
        @($receipt.PSObject.Properties.Name) | Should Not Contain 'watch_runtime_status'
        @($receipt.PSObject.Properties.Name) | Should Not Contain 'legacy_doctor_removed'
        (Get-Content -Raw -LiteralPath $script:configPath) | Should Be $script:originalConfig

        $hostHook = Join-Path $script:codexHome 'scripts\block-cross-thread-send.ps1'
        $hostPolicy = Join-Path $script:codexHome 'scripts\CrossThreadGuardPolicy.ps1'
        (Get-FileHash -Algorithm SHA256 -LiteralPath $hostHook).Hash | Should Be (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceHook).Hash
        (Get-FileHash -Algorithm SHA256 -LiteralPath $hostPolicy).Hash | Should Be (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePolicy).Hash

        $hooks = Get-Content -Raw -LiteralPath (Join-Path $script:codexHome 'hooks.json') | ConvertFrom-Json
        @($hooks.hooks.PostToolUse).Count | Should Be 1
        @($hooks.hooks.PreToolUse).Count | Should Be 1
        $hooks.hooks.PreToolUse[0].hooks[0].statusMessage | Should Match 'cross-task injection'
        $hooks.hooks.PreToolUse[0].hooks[0].statusMessage | Should Not Match 'watch|heartbeat'
    }

    It 'validates malformed hooks JSON before touching host scripts' {
        $hooksPath = Join-Path $script:codexHome 'hooks.json'
        Set-Content -LiteralPath $hooksPath -Value '{' -NoNewline
        { & $installer -CodexHome $script:codexHome -SourceHookPath $sourceHook } | Should Throw
        (Get-Content -Raw -LiteralPath $hooksPath) | Should Be '{'
        Test-Path -LiteralPath (Join-Path $script:codexHome 'scripts\block-cross-thread-send.ps1') | Should Be $false
    }

    It 'reports the generic static guard while trust and live probes remain open' {
        $null = & $installer -CodexHome $script:codexHome -SourceHookPath $sourceHook
        $result = & $doctor -CodexHome $script:codexHome -SourceHookPath $sourceHook
        $result.configuration_ready | Should Be $false
        $result.static_configuration_ready | Should Be $true
        $result.simulation_passed | Should Be $true
        $result.simulation_cases.direct_send_blocked | Should Be $true
        $result.simulation_cases.direct_handoff_blocked | Should Be $true
        $result.simulation_cases.automation_mutation_blocked | Should Be $true
        $result.simulation_cases.power_mutation_blocked | Should Be $true
        $result.simulation_cases.read_only_view_allowed | Should Be $true
        @($result.PSObject.Properties.Name) | Should Not Contain 'watch_runtime_status'
        $result.overall | Should Be 'soft_guard_only'
    }

    It 'restores managed targets when the final hooks document move fails' {
        $hostScripts = Join-Path $script:codexHome 'scripts'
        $null = New-Item -ItemType Directory -Path $hostScripts -Force
        $hostHook = Join-Path $hostScripts 'block-cross-thread-send.ps1'
        $hostPolicy = Join-Path $hostScripts 'CrossThreadGuardPolicy.ps1'
        $hooksPath = Join-Path $script:codexHome 'hooks.json'
        $oldHook = 'old-hook-bytes'
        $oldPolicy = 'old-policy-bytes'
        $oldHooks = Get-Content -Raw -LiteralPath $hooksPath
        Set-Content -LiteralPath $hostHook -Value $oldHook -NoNewline
        Set-Content -LiteralPath $hostPolicy -Value $oldPolicy -NoNewline
        { & $installer -CodexHome $script:codexHome -SourceHookPath $sourceHook -InjectFinalHooksMoveFailure } | Should Throw
        (Get-Content -Raw -LiteralPath $hostHook) | Should Be $oldHook
        (Get-Content -Raw -LiteralPath $hostPolicy) | Should Be $oldPolicy
        (Get-Content -Raw -LiteralPath $hooksPath) | Should Be $oldHooks
    }
}
