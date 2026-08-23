BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    $verifierPath = Join-Path $repoRoot 'scripts\quality\verify-cold-skill-host-events.ps1'
    $fixturesRoot = Join-Path $repoRoot 'tests\fixtures\cold-skill-routing\host-events'

    function Invoke-HostEventVerifier([string]$Fixture, [string]$ScenarioId) {
        $output = & pwsh -NoProfile -File $verifierPath -EventsPath (Join-Path $fixturesRoot $Fixture) -ScenarioId $ScenarioId 2>&1
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

    It 'rejects unbacked child claims, repeated discovery, and forbidden discovery' {
        $cases = @(
            @{ Fixture = 'invalid-s30-bare-wait.jsonl'; Scenario = 'S30-live-derived'; Code = 'H005_NATIVE_CHILD_SPAWN_MISSING' }
            @{ Fixture = 'invalid-s30-repeat-discovery.jsonl'; Scenario = 'S30-live-derived'; Code = 'H004_MULTIPLE_DISCOVERY_ATTEMPTS' }
            @{ Fixture = 'invalid-s36-router.jsonl'; Scenario = 'S36-live-derived'; Code = 'H003_FORBIDDEN_DISCOVERY_OBSERVED' }
        )

        foreach ($case in $cases) {
            $result = Invoke-HostEventVerifier $case.Fixture $case.Scenario
            $result.ExitCode | Should -Be 1 -Because ("fixture {0} must fail closed" -f $case.Fixture)
            $result.Output | Should -Match ([regex]::Escape($case.Code))
        }
    }
}
