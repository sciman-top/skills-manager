Describe 'watch runtime generation and shutdown arming preflight' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $generationScript = Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\scripts\New-WatchRuntimeGeneration.ps1'
        $preflightScript = Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\scripts\Test-WatchRuntimeArming.ps1'
        $script:generationScript = $generationScript
        $script:preflightScript = $preflightScript
        $script:hookSource = Join-Path $repoRoot 'scripts\hooks\block-cross-thread-send.ps1'
    }

    It 'binds one generation to source prompt and hook identities' {
        $generation = & $script:generationScript -SourceCommit ('a' * 40) -InstalledHookPath $script:hookSource
        $generation.watch_runtime_generation_id | Should Match '^watch-runtime-generation:[0-9a-f]{64}$'
        $generation.source_commit | Should Be ('a' * 40)
        $generation.target_prompt_sha256 | Should Match '^[0-9a-f]{64}$'
        $generation.shutdown_target_prompt_sha256 | Should Match '^[0-9a-f]{64}$'
        $generation.fleet_prompt_sha256 | Should Match '^[0-9a-f]{64}$'
        $generation.fleet_shutdown_prompt_sha256 | Should Match '^[0-9a-f]{64}$'
        $generation.hook_source_sha256 | Should Match '^[0-9a-f]{64}$'
        $generation.installed_hook_sha256 | Should Be $generation.hook_source_sha256
        $generation.generation_binding_sha256 | Should Match '^[0-9a-f]{64}$'
        $generation.shutdown_target_prompt_sha256 | Should Not Be $generation.target_prompt_sha256
    }

    It 'arms only when generation guard trust live probes and native automation capability all match' {
        $generation = & $script:generationScript -SourceCommit ('b' * 40) -InstalledHookPath $script:hookSource
        $guard = [ordered]@{
            configuration_ready = $true
            trust_status = 'trusted'
            live_path_status = 'verified'
            watch_runtime_generation_id = $generation.watch_runtime_generation_id
            source_sha256 = $generation.hook_source_sha256
            host_sha256 = $generation.hook_source_sha256
            target_prompt_sha256 = $generation.target_prompt_sha256
            shutdown_target_prompt_sha256 = $generation.shutdown_target_prompt_sha256
            fleet_prompt_sha256 = $generation.fleet_prompt_sha256
            fleet_shutdown_prompt_sha256 = $generation.fleet_shutdown_prompt_sha256
        } | ConvertTo-Json -Compress
        $live = [ordered]@{ fresh_session=$true; target_self_pause_allowed=$true; target_self_delete_blocked=$true; cross_target_pause_blocked=$true; supervisor_cleanup_delete_allowed=$true; supervisor_final_self_delete_allowed=$true; native_receipt_verified=$true } | ConvertTo-Json -Compress

        $ready = & $script:preflightScript -GenerationJson ($generation | ConvertTo-Json -Compress) -GuardStatusJson $guard -LiveProbeJson $live -NativeAutomationCapabilityReady
        $ready.arming_ready | Should Be $true
        $ready.status | Should Be 'shutdown_armed'

        foreach ($case in @('generation', 'hook', 'trust', 'live', 'native')) {
            $guardCase = $guard | ConvertFrom-Json
            $liveCase = $live | ConvertFrom-Json
            $native = $true
            switch ($case) {
                'generation' { $guardCase.watch_runtime_generation_id = 'watch-runtime-generation:' + ('0' * 64) }
                'hook' { $guardCase.host_sha256 = '0' * 64 }
                'trust' { $guardCase.trust_status = 'untrusted' }
                'live' { $liveCase.fresh_session = $false }
                'native' { $native = $false }
            }
            $params = @{ GenerationJson=($generation | ConvertTo-Json -Compress); GuardStatusJson=($guardCase | ConvertTo-Json -Compress); LiveProbeJson=($liveCase | ConvertTo-Json -Compress) }
            if ($native) { $params.NativeAutomationCapabilityReady = $true }
            $blocked = & $script:preflightScript @params
            $blocked.arming_ready | Should Be $false
            $blocked.status | Should Be 'not_armed'
            $blocked.rollback_required | Should Be $true
        }
    }
}
