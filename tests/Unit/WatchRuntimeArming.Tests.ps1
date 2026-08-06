Describe 'watch runtime generation and shutdown arming preflight' {
    BeforeAll {
        $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
        $script:repoRoot = $repoRoot
        $script:generationScript = Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\scripts\New-WatchRuntimeGeneration.ps1'
        $script:preflightScript = Join-Path $repoRoot 'overrides\custom\watch-interrupted-task\scripts\Test-WatchRuntimeArming.ps1'
        $script:hookSource = Join-Path $repoRoot 'scripts\hooks\block-cross-thread-send.ps1'
        $script:policySource = Join-Path $repoRoot 'scripts\hooks\CrossThreadGuardPolicy.ps1'

        function New-WatchRuntimeFixture {
            $fixtureRoot = Join-Path $TestDrive ('watch-runtime-' + [guid]::NewGuid().ToString('N'))
            $fixtureScripts = Join-Path $fixtureRoot 'overrides\custom\watch-interrupted-task\scripts'
            $fixtureHooks = Join-Path $fixtureRoot 'scripts\hooks'
            $null = New-Item -ItemType Directory -Path $fixtureScripts -Force
            $null = New-Item -ItemType Directory -Path $fixtureHooks -Force
            Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'overrides\custom\watch-interrupted-task\scripts') -Filter '*.ps1' -File |
                Copy-Item -Destination $fixtureScripts
            Copy-Item -LiteralPath $script:hookSource -Destination $fixtureHooks
            Copy-Item -LiteralPath $script:policySource -Destination $fixtureHooks

            git -C $fixtureRoot init --quiet
            git -C $fixtureRoot config user.email 'watch-runtime-tests@example.invalid'
            git -C $fixtureRoot config user.name 'Watch Runtime Tests'
            git -C $fixtureRoot add -- overrides scripts
            git -C $fixtureRoot commit --quiet -m 'fixture baseline'
            if ($LASTEXITCODE -ne 0) { throw 'fixture_commit_failed' }

            return [pscustomobject]@{
                Root = $fixtureRoot
                GenerationScript = Join-Path $fixtureScripts 'New-WatchRuntimeGeneration.ps1'
                PreflightScript = Join-Path $fixtureScripts 'Test-WatchRuntimeArming.ps1'
                HookSource = Join-Path $fixtureHooks 'block-cross-thread-send.ps1'
                PolicySource = Join-Path $fixtureHooks 'CrossThreadGuardPolicy.ps1'
                Head = (& git -C $fixtureRoot rev-parse HEAD).Trim()
            }
        }
    }

    It 'derives one deterministic generation from the exact clean HEAD and committed source blobs' {
        $fixture = New-WatchRuntimeFixture
        $first = & $fixture.GenerationScript -InstalledHookPath $fixture.HookSource -InstalledPolicyPath $fixture.PolicySource
        $second = & $fixture.GenerationScript -InstalledHookPath $fixture.HookSource -InstalledPolicyPath $fixture.PolicySource

        $first.watch_runtime_generation_id | Should Match '^watch-runtime-generation:[0-9a-f]{64}$'
        $first.watch_runtime_generation_id | Should Be $second.watch_runtime_generation_id
        $first.source_commit | Should Be $fixture.Head
        $first.repo_clean | Should Be $true
        $first.source_blobs_verified | Should Be $true
        @($first.committed_source_hashes.PSObject.Properties).Count | Should BeGreaterThan 4
        $first.installed_hook_sha256 | Should Be $first.hook_source_sha256
        $first.installed_policy_sha256 | Should Be $first.hook_policy_source_sha256
        $first.generation_binding_sha256 | Should Match '^[0-9a-f]{64}$'
    }

    It 'removes the caller-controlled SourceCommit interface and rejects nonexistent or non-HEAD commits' {
        $fixture = New-WatchRuntimeFixture
        foreach ($commit in @(('a' * 40), $fixture.Head)) {
            { & $fixture.GenerationScript -SourceCommit $commit -InstalledHookPath $fixture.HookSource -InstalledPolicyPath $fixture.PolicySource } | Should Throw
        }
    }

    It 'rejects tracked worktree and index changes before generating a runtime identity' {
        foreach ($mode in @('worktree', 'index')) {
            $fixture = New-WatchRuntimeFixture
            Add-Content -LiteralPath $fixture.HookSource -Value "# $mode drift"
            if ($mode -ceq 'index') {
                git -C $fixture.Root add -- scripts/hooks/block-cross-thread-send.ps1
                if ($LASTEXITCODE -ne 0) { throw 'fixture_stage_failed' }
            }
            try {
                $null = & $fixture.GenerationScript -InstalledHookPath $fixture.HookSource -InstalledPolicyPath $fixture.PolicySource
                throw 'expected_generation_rejection_missing'
            }
            catch {
                $_.Exception.Message | Should Match '^tracked_(worktree|index)_dirty$'
            }
        }
    }

    It 'rejects a source blob drift even when Git status is hidden by an assume-unchanged flag' {
        $fixture = New-WatchRuntimeFixture
        git -C $fixture.Root update-index --assume-unchanged -- scripts/hooks/block-cross-thread-send.ps1
        Add-Content -LiteralPath $fixture.HookSource -Value '# hidden drift'

        try {
            $null = & $fixture.GenerationScript -InstalledHookPath $fixture.HookSource -InstalledPolicyPath $fixture.PolicySource
            throw 'expected_generation_rejection_missing'
        }
        catch {
            $_.Exception.Message | Should Match '^source_blob_mismatch:scripts/hooks/block-cross-thread-send\.ps1$'
        }
    }

    It 'arms only when generation, trusted guard, live probes, and native capability all agree' {
        $fixture = New-WatchRuntimeFixture
        $generation = ((& $fixture.GenerationScript -InstalledHookPath $fixture.HookSource -InstalledPolicyPath $fixture.PolicySource -AsJson) | ConvertFrom-Json)
        $guard = [ordered]@{
            configuration_ready = $true
            trust_status = 'trusted'
            live_path_status = 'verified'
            watch_runtime_generation_id = $generation.watch_runtime_generation_id
            source_sha256 = $generation.hook_source_sha256
            host_sha256 = $generation.hook_source_sha256
            policy_source_sha256 = $generation.hook_policy_source_sha256
            policy_host_sha256 = $generation.hook_policy_source_sha256
            target_prompt_sha256 = $generation.target_prompt_sha256
            shutdown_target_prompt_sha256 = $generation.shutdown_target_prompt_sha256
            fleet_prompt_sha256 = $generation.fleet_prompt_sha256
            fleet_shutdown_prompt_sha256 = $generation.fleet_shutdown_prompt_sha256
        } | ConvertTo-Json -Compress
        $live = [ordered]@{
            fresh_session = $true
            host_automation_id_supported = $true
            full_heartbeat_update_supported = $true
            target_self_pause_allowed = $true
            target_self_delete_blocked = $true
            cross_target_pause_blocked = $true
            paused_target_cleanup_delete_allowed = $true
            supervisor_final_self_delete_allowed = $true
            exact_shutdown_guard_allowed = $true
            native_receipt_verified = $true
        } | ConvertTo-Json -Compress
        $result = & $fixture.PreflightScript -GenerationJson ($generation | ConvertTo-Json -Compress) -GuardStatusJson $guard -LiveProbeJson $live -NativeAutomationCapabilityReady -AsJson | ConvertFrom-Json

        $result.status | Should Be 'shutdown_armed'
        $result.arming_ready | Should Be $true
        $result.rollback_required | Should Be $false
        @($result.findings).Count | Should Be 0
    }

    It 'fails closed when any arming evidence is missing or inconsistent' {
        $fixture = New-WatchRuntimeFixture
        { & $fixture.PreflightScript -NativeAutomationCapabilityReady } | Should Throw

        $generation = (& $fixture.GenerationScript -InstalledHookPath $fixture.HookSource -InstalledPolicyPath $fixture.PolicySource -AsJson)
        $invalid = & $fixture.PreflightScript -GenerationJson $generation -GuardStatusJson '{}' -LiveProbeJson '{}' -AsJson | ConvertFrom-Json
        $invalid.status | Should Be 'not_armed'
        $invalid.arming_ready | Should Be $false
        $invalid.rollback_required | Should Be $true
        @($invalid.findings) | Should Contain 'guard_not_ready'
    }
}
