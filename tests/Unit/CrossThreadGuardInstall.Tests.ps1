Describe 'Cross-thread guard installer and doctor' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $installer = Join-Path $repoRoot 'scripts\hooks\Install-CrossThreadGuard.ps1'
        $doctor = Join-Path $repoRoot 'scripts\hooks\Test-CrossThreadGuard.ps1'
        $sourceHook = Join-Path $repoRoot 'scripts\hooks\block-cross-thread-send.ps1'
        $sourceRuntimeDoctor = Join-Path $repoRoot 'scripts\hooks\Test-WatchGuardRuntime.ps1'
        $targetGenerator = Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\scripts\New-WatchHeartbeatPrompt.ps1'
        $fleetGenerator = Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\scripts\New-WatchFleetSupervisorPrompt.ps1'
        $script:targetPromptDigest = ((& $targetGenerator -TargetThreadId 'digest-probe' -AsJson) | ConvertFrom-Json).prompt_sha256
        $script:fleetPromptDigest = ((& $fleetGenerator -SupervisorThreadId 'digest-probe' -AsJson) | ConvertFrom-Json).prompt_sha256
        $script:fleetShutdownPromptDigest = ((& $fleetGenerator -SupervisorThreadId 'digest-probe' -ShutdownWhenAllStopped -AsJson) | ConvertFrom-Json).prompt_sha256
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
                PostToolUse = @([ordered]@{
                    matcher = 'existing_tool'
                    hooks = @([ordered]@{ type = 'command'; command = 'existing.ps1' })
                })
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $script:codexHome 'hooks.json')
    }

    It 'keeps the trusted hook bytes stable across checkouts' {
        $attributesPath = Join-Path $repoRoot '.gitattributes'
        Test-Path -LiteralPath $attributesPath | Should Be $true
        (Get-Content -Raw -LiteralPath $attributesPath) | Should Match '(?m)^scripts/hooks/block-cross-thread-send\.ps1 text eol=lf\r?$'
        (Get-Content -Raw -LiteralPath $attributesPath) | Should Match '(?m)^scripts/hooks/Test-WatchGuardRuntime\.ps1 text eol=lf\r?$'
        @([System.IO.File]::ReadAllBytes($sourceHook) | Where-Object { $_ -eq 13 }).Count | Should Be 0
        @([System.IO.File]::ReadAllBytes($sourceRuntimeDoctor) | Where-Object { $_ -eq 13 }).Count | Should Be 0
    }

    It 'installs canonical revision-3 provenance and preserves other hooks and config' {
        $receipt = & $installer -CodexHome $script:codexHome -SourceHookPath $sourceHook
        $receipt.status | Should Be 'installed_untrusted'
        (Get-Content -Raw -LiteralPath $script:configPath) | Should Be $script:originalConfig

        $hostHook = Join-Path $script:codexHome 'scripts\block-cross-thread-send.ps1'
        $hostRuntimeDoctor = Join-Path $script:codexHome 'scripts\Test-WatchGuardRuntime.ps1'
        (Get-FileHash -Algorithm SHA256 -LiteralPath $hostHook).Hash | Should Be (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceHook).Hash
        (Get-FileHash -Algorithm SHA256 -LiteralPath $hostRuntimeDoctor).Hash | Should Be (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceRuntimeDoctor).Hash

        $hooks = Get-Content -Raw -LiteralPath (Join-Path $script:codexHome 'hooks.json') | ConvertFrom-Json
        @($hooks.hooks.PostToolUse).Count | Should Be 1
        @($hooks.hooks.PreToolUse).Count | Should Be 1
        $hooks.hooks.PreToolUse[0].matcher | Should Be '*'
        $command = [string]$hooks.hooks.PreToolUse[0].hooks[0].command
        $command | Should Match ([regex]::Escape($hostHook))
        $command | Should Match ([regex]::Escape($receipt.source_sha256))
        $command | Should Match ([regex]::Escape($script:targetPromptDigest))
        $command | Should Match ([regex]::Escape($script:fleetPromptDigest))
        $command | Should Match ([regex]::Escape($script:fleetShutdownPromptDigest))
        $hooks.hooks.PreToolUse[0].hooks[0].commandWindows | Should Be $command
        $receipt.target_prompt_sha256 | Should Be $script:targetPromptDigest
        $receipt.fleet_prompt_sha256 | Should Be $script:fleetPromptDigest
        $receipt.fleet_shutdown_prompt_sha256 | Should Be $script:fleetShutdownPromptDigest
    }

    It 'validates malformed hooks JSON before touching host scripts' {
        $hooksPath = Join-Path $script:codexHome 'hooks.json'
        $malformed = '{'
        Set-Content -LiteralPath $hooksPath -Value $malformed -NoNewline

        { & $installer -CodexHome $script:codexHome -SourceHookPath $sourceHook } | Should Throw

        (Get-Content -Raw -LiteralPath $hooksPath) | Should Be $malformed
        Test-Path -LiteralPath (Join-Path $script:codexHome 'scripts\block-cross-thread-send.ps1') | Should Be $false
        Test-Path -LiteralPath (Join-Path $script:codexHome 'scripts\Test-WatchGuardRuntime.ps1') | Should Be $false
    }

    It 'preserves unrelated groups with a similar status message' {
        $hooksPath = Join-Path $script:codexHome 'hooks.json'
        $document = Get-Content -Raw -LiteralPath $hooksPath | ConvertFrom-Json
        $document.hooks | Add-Member -MemberType NoteProperty -Name PreToolUse -Value @([pscustomobject]@{
            matcher = 'unrelated_tool'
            hooks = @([pscustomobject]@{
                type = 'command'
                command = 'unrelated.ps1'
                statusMessage = 'Blocking target heartbeat automation mutation for another product'
            })
        })
        $document | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $hooksPath

        $null = & $installer -CodexHome $script:codexHome -SourceHookPath $sourceHook
        $installed = Get-Content -Raw -LiteralPath $hooksPath | ConvertFrom-Json
        @($installed.hooks.PreToolUse | Where-Object { $_.matcher -eq 'unrelated_tool' }).Count | Should Be 1
    }

    It 'reports soft_guard_only until slash-hooks trust and fresh live probes exist' {
        $null = & $installer -CodexHome $script:codexHome -SourceHookPath $sourceHook
        $result = & $doctor -CodexHome $script:codexHome -SourceHookPath $sourceHook
        $result.configuration_ready | Should Be $false
        $result.static_configuration_ready | Should Be $true
        $result.prompt_digests_match | Should Be $true
        $result.simulation_passed | Should Be $true
        $result.simulation_cases.direct_send_tool | Should Be $true
        $result.simulation_cases.code_mode_shell_send | Should Be $true
        $result.simulation_cases.code_mode_target_self_delete | Should Be $true
        $result.simulation_cases.code_mode_automation_live_probe_sentinel | Should Be $true
        $result.simulation_cases.standard_fleet_shutdown_blocked | Should Be $true
        $result.simulation_cases.armed_fleet_shutdown_allowed | Should Be $true
        $result.trust_status | Should Be 'unverified_requires_slash_hooks'
        $result.live_path_status | Should Be 'unverified_requires_fresh_session_probe'
        $result.specialized_path_boundary | Should Be 'guardrail_only'
        $result.overall | Should Be 'soft_guard_only'
    }

    It 'detects canonical prompt generator drift even when the installed command still has valid hashes' {
        $null = & $installer -CodexHome $script:codexHome -SourceHookPath $sourceHook
        $driftedTargetGenerator = Join-Path $TestDrive 'New-WatchHeartbeatPrompt.ps1'
        Copy-Item -LiteralPath $targetGenerator -Destination $driftedTargetGenerator
        ((Get-Content -Raw -LiteralPath $driftedTargetGenerator) -replace 'operating_mode=conditional_recovery', 'operating_mode=conditional_recovery_drift') | Set-Content -LiteralPath $driftedTargetGenerator -NoNewline

        $result = & $doctor -CodexHome $script:codexHome -SourceHookPath $sourceHook `
            -SourceTargetPromptGeneratorPath $driftedTargetGenerator -SourceFleetPromptGeneratorPath $fleetGenerator
        $result.prompt_digests_match | Should Be $false
        $result.static_configuration_ready | Should Be $false
        $result.overall | Should Be 'soft_guard_only'
    }
}
