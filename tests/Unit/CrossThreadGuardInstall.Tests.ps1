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
                PostToolUse = @([ordered]@{
                    matcher = 'existing_tool'
                    hooks = @([ordered]@{ type = 'command'; command = 'existing.ps1' })
                })
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $script:codexHome 'hooks.json')
    }

    It 'keeps the trusted hook bytes stable across checkouts' {
        $attributes = Get-Content -Raw -LiteralPath (Join-Path $repoRoot '.gitattributes')
        $attributes | Should Match '(?m)^scripts/hooks/block-cross-thread-send\.ps1 text eol=lf\r?$'
        $attributes | Should Match '(?m)^scripts/hooks/CrossThreadGuardPolicy\.ps1 text eol=lf\r?$'
        @([System.IO.File]::ReadAllBytes($sourceHook) | Where-Object { $_ -eq 13 }).Count | Should Be 0
        @([System.IO.File]::ReadAllBytes($sourcePolicy) | Where-Object { $_ -eq 13 }).Count | Should Be 0
    }

    It 'installs the revision-4 retired-watch guard and preserves unrelated hooks and config' {
        $hostScripts = Join-Path $script:codexHome 'scripts'
        $null = New-Item -ItemType Directory -Path $hostScripts -Force
        @'
[CmdletBinding()]
# retired managed runtime probe
clientInfo = 'watch-guard-runtime-doctor'
watch_runtime_generation_id = 'legacy'
'@ | Set-Content -LiteralPath (Join-Path $hostScripts 'Test-WatchGuardRuntime.ps1') -NoNewline

        $receipt = & $installer -CodexHome $script:codexHome -SourceHookPath $sourceHook
        $receipt.status | Should Be 'installed_untrusted'
        $receipt.policy_revision | Should Be 4
        $receipt.watch_runtime_status | Should Be 'retired_fail_closed'
        $receipt.legacy_doctor_removed | Should Be $true
        (Get-Content -Raw -LiteralPath $script:configPath) | Should Be $script:originalConfig

        $hostHook = Join-Path $hostScripts 'block-cross-thread-send.ps1'
        $hostPolicy = Join-Path $hostScripts 'CrossThreadGuardPolicy.ps1'
        (Get-FileHash -Algorithm SHA256 -LiteralPath $hostHook).Hash | Should Be (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceHook).Hash
        (Get-FileHash -Algorithm SHA256 -LiteralPath $hostPolicy).Hash | Should Be (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePolicy).Hash
        Test-Path -LiteralPath (Join-Path $hostScripts 'Test-WatchGuardRuntime.ps1') | Should Be $false

        $hooks = Get-Content -Raw -LiteralPath (Join-Path $script:codexHome 'hooks.json') | ConvertFrom-Json
        @($hooks.hooks.PostToolUse).Count | Should Be 1
        @($hooks.hooks.PreToolUse).Count | Should Be 1
        $hooks.hooks.PreToolUse[0].matcher | Should Be '*'
        $command = [string]$hooks.hooks.PreToolUse[0].hooks[0].command
        $command | Should Match ([regex]::Escape($hostHook))
        $command | Should Match ([regex]::Escape($receipt.source_sha256))
        $command | Should Match ([regex]::Escape($receipt.policy_source_sha256))
        $command | Should Not Match 'ExpectedTargetPromptSha256|ExpectedShutdownTargetPromptSha256|ExpectedFleetPromptSha256|ExpectedFleetShutdownPromptSha256|ExpectedRuntimeGenerationId|AutomationRoot|WatchFleetStateRoot'
        $hooks.hooks.PreToolUse[0].hooks[0].commandWindows | Should Be $command
        $hooks.hooks.PreToolUse[0].hooks[0].statusMessage | Should Match 'retired watch lifecycle'
        $receipt.policy_source_sha256 | Should Be $receipt.policy_host_sha256
    }

    It 'validates malformed hooks JSON before touching host scripts' {
        $hooksPath = Join-Path $script:codexHome 'hooks.json'
        Set-Content -LiteralPath $hooksPath -Value '{' -NoNewline

        { & $installer -CodexHome $script:codexHome -SourceHookPath $sourceHook } | Should Throw

        (Get-Content -Raw -LiteralPath $hooksPath) | Should Be '{'
        Test-Path -LiteralPath (Join-Path $script:codexHome 'scripts\block-cross-thread-send.ps1') | Should Be $false
        Test-Path -LiteralPath (Join-Path $script:codexHome 'scripts\CrossThreadGuardPolicy.ps1') | Should Be $false
    }

    It 'preserves unrelated groups with a similar status message' {
        $hooksPath = Join-Path $script:codexHome 'hooks.json'
        $document = Get-Content -Raw -LiteralPath $hooksPath | ConvertFrom-Json
        $document.hooks | Add-Member -MemberType NoteProperty -Name PreToolUse -Value @([pscustomobject]@{
            matcher = 'unrelated_tool'
            hooks = @([pscustomobject]@{
                type = 'command'
                command = 'unrelated.ps1'
                statusMessage = 'Blocking retired watch lifecycle for another product'
            })
        })
        $document | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $hooksPath

        $null = & $installer -CodexHome $script:codexHome -SourceHookPath $sourceHook
        $installed = Get-Content -Raw -LiteralPath $hooksPath | ConvertFrom-Json
        @($installed.hooks.PreToolUse | Where-Object { $_.matcher -eq 'unrelated_tool' }).Count | Should Be 1
    }

    It 'reports a static retired-watch guard while trust and fresh live probes remain open' {
        $null = & $installer -CodexHome $script:codexHome -SourceHookPath $sourceHook
        $result = & $doctor -CodexHome $script:codexHome -SourceHookPath $sourceHook

        $result.configuration_ready | Should Be $false
        $result.static_configuration_ready | Should Be $true
        $result.hash_matches | Should Be $true
        $result.definition_matches | Should Be $true
        $result.simulation_passed | Should Be $true
        $result.simulation_cases.direct_send_blocked | Should Be $true
        $result.simulation_cases.direct_handoff_blocked | Should Be $true
        $result.simulation_cases.heartbeat_mutation_blocked | Should Be $true
        $result.simulation_cases.heartbeat_power_blocked | Should Be $true
        $result.simulation_cases.exact_legacy_delete_allowed | Should Be $true
        $result.simulation_cases.negated_delete_blocked | Should Be $true
        $result.simulation_cases.read_only_view_allowed | Should Be $true
        $result.watch_runtime_status | Should Be 'retired_fail_closed'
        @($result.PSObject.Properties.Name) | Should Not Contain 'watch_runtime_generation_id'
        @($result.PSObject.Properties.Name) | Should Not Contain 'prompt_digests_match'
        $result.trust_status | Should Be 'unverified_requires_slash_hooks'
        $result.live_path_status | Should Be 'unverified_requires_fresh_session_probe'
        $result.specialized_path_boundary | Should Be 'guardrail_only'
        $result.overall | Should Be 'soft_guard_only'
    }

    It 'detects installed policy drift without consulting retired prompt generators' {
        $null = & $installer -CodexHome $script:codexHome -SourceHookPath $sourceHook
        $hostPolicy = Join-Path $script:codexHome 'scripts\CrossThreadGuardPolicy.ps1'
        Add-Content -LiteralPath $hostPolicy -Value '# drift'

        $result = & $doctor -CodexHome $script:codexHome -SourceHookPath $sourceHook
        $result.hash_matches | Should Be $false
        $result.static_configuration_ready | Should Be $false
        $result.overall | Should Be 'soft_guard_only'
    }

    # Keep this fault-injection test last because Pester 4 retains command mocks
    # for the enclosing Describe scope after an It block completes.
    It 'restores every managed target when the final hooks document move fails' {
        $hostScripts = Join-Path $script:codexHome 'scripts'
        $null = New-Item -ItemType Directory -Path $hostScripts -Force
        $hostHook = Join-Path $hostScripts 'block-cross-thread-send.ps1'
        $hostDoctor = Join-Path $hostScripts 'Test-WatchGuardRuntime.ps1'
        $hostPolicy = Join-Path $hostScripts 'CrossThreadGuardPolicy.ps1'
        $hooksPath = Join-Path $script:codexHome 'hooks.json'
        $oldHook = 'old-hook-bytes'
        $oldDoctor = 'old-doctor-bytes'
        $oldPolicy = 'old-policy-bytes'
        $oldHooks = Get-Content -Raw -LiteralPath $hooksPath
        Set-Content -LiteralPath $hostHook -Value $oldHook -NoNewline
        Set-Content -LiteralPath $hostDoctor -Value $oldDoctor -NoNewline
        Set-Content -LiteralPath $hostPolicy -Value $oldPolicy -NoNewline

        { & $installer -CodexHome $script:codexHome -SourceHookPath $sourceHook -InjectFinalHooksMoveFailure } | Should Throw
        (Get-Content -Raw -LiteralPath $hostHook) | Should Be $oldHook
        (Get-Content -Raw -LiteralPath $hostDoctor) | Should Be $oldDoctor
        (Get-Content -Raw -LiteralPath $hostPolicy) | Should Be $oldPolicy
        (Get-Content -Raw -LiteralPath $hooksPath) | Should Be $oldHooks
    }
}
