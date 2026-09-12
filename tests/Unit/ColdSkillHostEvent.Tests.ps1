BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    $verifierPath = Join-Path $repoRoot 'scripts\quality\verify-cold-skill-host-events.ps1'
    $fixturesRoot = Join-Path $repoRoot 'tests\fixtures\cold-skill-routing\host-events'

    function Invoke-HostEventVerifier([string]$Fixture, [string]$ScenarioId, [string]$ChildRolloutFixture = '') {
        $arguments = @('-NoProfile', '-File', $verifierPath, '-EventsPath', (Join-Path $fixturesRoot $Fixture), '-ScenarioId', $ScenarioId)
        if (-not [string]::IsNullOrWhiteSpace($ChildRolloutFixture)) {
            $arguments += @('-ChildRolloutPath', (Join-Path $fixturesRoot $ChildRolloutFixture))
        }
        $output = & pwsh @arguments 2>&1
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = (@($output) -join "`n") }
    }
}

Describe 'Cold skill raw host-event verifier' {
    It 'accepts a multi-turn host stream only with spawn, child id, and child-bound wait' {
        $result = Invoke-HostEventVerifier 'valid-s30.jsonl' 'S30-live-derived'

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'findings=0'
    }

    It 'accepts an ordinary no-skill stream without router or child events' {
        $result = Invoke-HostEventVerifier 'valid-s35.jsonl' 'S35-live-derived'

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'findings=0'
    }

    It 'rejects a plausible answer without required cold discovery' {
        $result = Invoke-HostEventVerifier 'valid-s35.jsonl' 'S01-explicit'

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'H009_REQUIRED_DISCOVERY_MISSING'
    }

    It 'checks specialist history boundaries from a bound parent rollout' {
        $parentPath = Join-Path $TestDrive 'parent.jsonl'
        foreach ($case in @(
            @{ Fork = 'all'; Exit = 1 }
            @{ Fork = $null; Exit = 1 }
            @{ Fork = '0'; Exit = 1 }
            @{ Fork = 'none'; Exit = 0 }
            @{ Fork = '2'; Exit = 0 }
        )) {
            $spawnArgs = @{ agent_type = 'cold-capability-runner' }
            if ($null -ne $case.Fork) { $spawnArgs.fork_turns = $case.Fork }
            $call = @{ type = 'response_item'; payload = @{ type = 'function_call'; name = 'spawn_agent'; arguments = ($spawnArgs | ConvertTo-Json -Compress) } }
            @(
                '{"type":"session_meta","payload":{"id":"fixture-root"}}'
                ($call | ConvertTo-Json -Depth 5 -Compress)
            ) | Set-Content -LiteralPath $parentPath
            $output = & pwsh -NoProfile -File $verifierPath -EventsPath (Join-Path $fixturesRoot 'valid-s31.jsonl') -ScenarioId 'S31-live-derived' -ParentRolloutPath $parentPath 2>&1
            $LASTEXITCODE | Should -Be $case.Exit -Because ("fork_turns={0}" -f $case.Fork)
            if ($case.Exit -eq 1) { ($output -join "`n") | Should -Match 'H010_SPECIALIST_HISTORY_NOT_ISOLATED' }
        }
    }

    It 'accepts a one-shot runner stream only with a native child identifier' {
        $result = Invoke-HostEventVerifier 'valid-s31.jsonl' 'S31-live-derived'

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'findings=0'
    }

    It 'uses an exactly-bound child rollout as the spawn authority for a raw exec stream' {
        $result = Invoke-HostEventVerifier 'valid-s30-rollout-witness-host.jsonl' 'S30-live-derived' 'valid-s30-design-griller-child-rollout.jsonl'

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'findings=0'
    }

    It 'rejects a child rollout whose parent binding does not match the raw host stream' {
        $result = Invoke-HostEventVerifier 'valid-s30-rollout-witness-host.jsonl' 'S30-live-derived' 'invalid-s30-wrong-parent-child-rollout.jsonl'

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'H008_ROLLOUT_CHILD_EVIDENCE_INVALID'
        $result.Output | Should -Match 'H005_NATIVE_CHILD_SPAWN_MISSING'
    }

    It 'rejects unbacked child claims, repeated discovery, and forbidden discovery' {
        $cases = @(
            @{ Fixture = 'invalid-s30-bare-wait.jsonl'; Scenario = 'S30-live-derived'; Code = 'H005_NATIVE_CHILD_SPAWN_MISSING' }
            @{ Fixture = 'invalid-s30-repeat-discovery.jsonl'; Scenario = 'S30-live-derived'; Code = 'H004_MULTIPLE_DISCOVERY_ATTEMPTS' }
            @{ Fixture = 'invalid-s31-no-spawn.jsonl'; Scenario = 'S31-live-derived'; Code = 'H005_NATIVE_CHILD_SPAWN_MISSING' }
            @{ Fixture = 'invalid-s36-router.jsonl'; Scenario = 'S03-explicit'; Code = 'H003_FORBIDDEN_DISCOVERY_OBSERVED' }
        )

        foreach ($case in $cases) {
            $result = Invoke-HostEventVerifier $case.Fixture $case.Scenario
            $result.ExitCode | Should -Be 1 -Because ("fixture {0} must fail closed" -f $case.Fixture)
            $result.Output | Should -Match ([regex]::Escape($case.Code))
        }
    }
}
