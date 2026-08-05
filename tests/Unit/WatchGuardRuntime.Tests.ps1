Describe 'watch guard fresh runtime doctor' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $runtimeDoctor = Join-Path $repoRoot 'scripts\hooks\Test-WatchGuardRuntime.ps1'
        $sourceHook = Join-Path $repoRoot 'scripts\hooks\block-cross-thread-send.ps1'
        $targetGenerator = Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\scripts\New-WatchHeartbeatPrompt.ps1'
        $fleetGenerator = Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\scripts\New-WatchFleetSupervisorPrompt.ps1'
        $script:targetPromptDigest = ((& $targetGenerator -TargetThreadId 'digest-probe' -AsJson) | ConvertFrom-Json).prompt_sha256
        $script:fleetPromptDigest = ((& $fleetGenerator -SupervisorThreadId 'digest-probe' -AsJson) | ConvertFrom-Json).prompt_sha256
    }

    BeforeEach {
        $script:codexHome = Join-Path $TestDrive 'codex-home'
        $hostScripts = Join-Path $script:codexHome 'scripts'
        $null = New-Item -ItemType Directory -Path $hostScripts -Force
        $script:hostHook = Join-Path $hostScripts 'block-cross-thread-send.ps1'
        Copy-Item -LiteralPath $sourceHook -Destination $script:hostHook
        $script:hostHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $script:hostHook).Hash.ToLowerInvariant()
        $script:hookCommand = 'pwsh -NoProfile -ExecutionPolicy Bypass -File "{0}" -ExpectedScriptSha256 "{1}" -ExpectedTargetPromptSha256 "{2}" -ExpectedFleetPromptSha256 "{3}"' -f $script:hostHook, $script:hostHash, $script:targetPromptDigest, $script:fleetPromptDigest
        Write-SourceHooksJson
    }

    function Write-SourceHooksJson {
        param([bool]$CommandWindowsMatches = $true)

        [ordered]@{
            hooks = [ordered]@{
                PreToolUse = @([ordered]@{
                    matcher = '*'
                    hooks = @([ordered]@{
                        type = 'command'
                        command = $script:hookCommand
                        commandWindows = if ($CommandWindowsMatches) { $script:hookCommand } else { 'pwsh -File wrong.ps1' }
                    })
                })
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $script:codexHome 'hooks.json') -Encoding utf8
    }

    function New-HooksListJson {
        param(
            [string]$TrustStatus = 'trusted',
            [bool]$Enabled = $true,
            [string]$EventName = 'preToolUse',
            [string]$HandlerType = 'command',
            [string]$Matcher = '*'
        )

        return [ordered]@{
            id = 2
            result = [ordered]@{
                data = @([ordered]@{
                    cwd = 'D:\CODE\skills-manager'
                    hooks = @([ordered]@{
                        key = 'C:\Users\test\.codex\hooks.json:pre_tool_use:0:0'
                        eventName = $EventName
                        handlerType = $HandlerType
                        matcher = $Matcher
                        command = $script:hookCommand
                        enabled = $Enabled
                        currentHash = 'sha256:' + ('a' * 64)
                        trustStatus = $TrustStatus
                    })
                })
            }
        } | ConvertTo-Json -Depth 12 -Compress
    }

    It 'reports the exact trusted revision-3 definition as ready' {
        $result = & $runtimeDoctor -CodexHome $script:codexHome -HooksListJson (New-HooksListJson)
        $result.configuration_ready | Should Be $true
        $result.trust_status | Should Be 'trusted'
        $result.current_hash | Should Be ('sha256:' + ('a' * 64))
        $result.host_sha256 | Should Be $script:hostHash
        $result.target_prompt_sha256 | Should Be $script:targetPromptDigest
        $result.fleet_prompt_sha256 | Should Be $script:fleetPromptDigest
        $result.runtime_shape_matches | Should Be $true
        $result.source_shape_matches | Should Be $true
        $result.live_send_probe_required | Should Be $true
        $result.live_automation_probe_required | Should Be $true
        $result.overall | Should Be 'trusted_requires_live_probes'
    }

    It 'stays fail closed when the exact definition is modified or disabled' {
        foreach ($case in @(
            [ordered]@{ TrustStatus = 'modified'; Enabled = $true },
            [ordered]@{ TrustStatus = 'trusted'; Enabled = $false }
        )) {
            $result = & $runtimeDoctor -CodexHome $script:codexHome -HooksListJson (New-HooksListJson -TrustStatus $case.TrustStatus -Enabled $case.Enabled)
            $result.configuration_ready | Should Be $false
            $result.overall | Should Be 'soft_guard_only'
        }
    }

    It 'rejects non-PreToolUse event, wrong matcher or handler, and source commandWindows drift' {
        foreach ($json in @(
            (New-HooksListJson -EventName 'postToolUse'),
            (New-HooksListJson -Matcher 'codex_app__automation_update'),
            (New-HooksListJson -HandlerType 'prompt')
        )) {
            $result = & $runtimeDoctor -CodexHome $script:codexHome -HooksListJson $json
            $result.configuration_ready | Should Be $false
            $result.overall | Should Be 'soft_guard_only'
        }

        Write-SourceHooksJson -CommandWindowsMatches $false
        $result = & $runtimeDoctor -CodexHome $script:codexHome -HooksListJson (New-HooksListJson)
        $result.runtime_shape_matches | Should Be $true
        $result.source_shape_matches | Should Be $false
        $result.configuration_ready | Should Be $false
        $result.overall | Should Be 'soft_guard_only'
    }

    It 'uses pwsh to launch a fresh app-server and ignores notifications without an id' {
        $fakeBin = Join-Path $TestDrive 'fake-bin'
        $null = New-Item -ItemType Directory -Path $fakeBin -Force
        $fakeCodex = Join-Path $fakeBin 'codex.ps1'
        $notification = @{ jsonrpc = '2.0'; method = 'server/ready'; params = @{} } | ConvertTo-Json -Compress
        $initialize = @{ jsonrpc = '2.0'; id = 1; result = @{} } | ConvertTo-Json -Compress
        $hooksList = New-HooksListJson
        @(
            ('Write-Output ''' + ($notification -replace "'", "''") + '''')
            ('Write-Output ''' + ($initialize -replace "'", "''") + '''')
            ('Write-Output ''' + ($hooksList -replace "'", "''") + '''')
            '[Console]::In.ReadToEnd() | Out-Null'
        ) | Set-Content -LiteralPath $fakeCodex -Encoding utf8

        $originalPath = $env:PATH
        try {
            $env:PATH = $fakeBin + [System.IO.Path]::PathSeparator + $originalPath
            $result = & $runtimeDoctor -CodexHome $script:codexHome -TimeoutSeconds 5
        }
        finally {
            $env:PATH = $originalPath
        }

        $result.fresh_process | Should Be $true
        $result.configuration_ready | Should Be $true
        $result.hook_count | Should Be 1
        $result.launcher_executable | Should Match 'pwsh(?:\.exe)?$'
        $result.error | Should BeNullOrEmpty
    }
}
