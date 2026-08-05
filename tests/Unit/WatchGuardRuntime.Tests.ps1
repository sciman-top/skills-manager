Describe 'watch guard fresh runtime doctor' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $runtimeDoctor = Join-Path $repoRoot 'scripts\hooks\Test-WatchGuardRuntime.ps1'
        $sourceHook = Join-Path $repoRoot 'scripts\hooks\block-cross-thread-send.ps1'
    }

    BeforeEach {
        $script:codexHome = Join-Path $TestDrive 'codex-home'
        $hostScripts = Join-Path $script:codexHome 'scripts'
        $null = New-Item -ItemType Directory -Path $hostScripts -Force
        $script:hostHook = Join-Path $hostScripts 'block-cross-thread-send.ps1'
        Copy-Item -LiteralPath $sourceHook -Destination $script:hostHook
        $script:hostHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $script:hostHook).Hash.ToLowerInvariant()
    }

    function New-HooksListJson {
        param([string]$TrustStatus = 'trusted', [bool]$Enabled = $true)

        return [ordered]@{
            id = 2
            result = [ordered]@{
                data = @([ordered]@{
                    cwd = 'D:\CODE\skills-manager'
                    hooks = @([ordered]@{
                        key = 'C:\Users\test\.codex\hooks.json:pre_tool_use:0:0'
                        eventName = 'preToolUse'
                        handlerType = 'command'
                        matcher = '*'
                        command = 'pwsh -NoProfile -ExecutionPolicy Bypass -File "{0}" -ExpectedScriptSha256 "{1}"' -f $script:hostHook, $script:hostHash
                        enabled = $Enabled
                        currentHash = 'sha256:' + ('a' * 64)
                        trustStatus = $TrustStatus
                    })
                })
            }
        } | ConvertTo-Json -Depth 12 -Compress
    }

    It 'reports the exact trusted fresh-session definition as ready' {
        $result = & $runtimeDoctor -CodexHome $script:codexHome -HooksListJson (New-HooksListJson)
        $result.configuration_ready | Should Be $true
        $result.trust_status | Should Be 'trusted'
        $result.current_hash | Should Be ('sha256:' + ('a' * 64))
        $result.host_sha256 | Should Be $script:hostHash
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

    It 'ignores app-server notifications that do not carry a JSON-RPC id' {
        $fakeBin = Join-Path $TestDrive 'fake-bin'
        $null = New-Item -ItemType Directory -Path $fakeBin -Force
        $fakeCodex = Join-Path $fakeBin 'codex.cmd'
        $notification = @{ jsonrpc = '2.0'; method = 'server/ready'; params = @{} } | ConvertTo-Json -Compress
        $initialize = @{ jsonrpc = '2.0'; id = 1; result = @{} } | ConvertTo-Json -Compress
        $hooksList = New-HooksListJson
        @(
            '@echo off'
            ('echo ' + $notification)
            ('echo ' + $initialize)
            ('echo ' + $hooksList)
            'more >nul'
        ) | Set-Content -LiteralPath $fakeCodex -Encoding Ascii

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
        $result.error | Should BeNullOrEmpty
    }
}
