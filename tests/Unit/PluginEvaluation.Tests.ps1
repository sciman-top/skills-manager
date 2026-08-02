$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'skills.ps1')
$fixtureRoot = Join-Path $repoRoot 'tests\fixtures\phase3-acceptance'

Describe 'Layered plugin evaluation' {
    It 'uses static and behavior fixtures as blockers without calling a provider' {
        $report = New-PluginEvaluationReport (Join-Path $fixtureRoot 'valid-plugin')
        $report.pass | Should Be $true
        $report.layers.static.state | Should Be 'pass'
        $report.layers.behavior_fixture.state | Should Be 'pass'
        $report.layers.model_snapshot.state | Should Be 'not_run'
        $report.layers.host_load.state | Should Be 'not_run'
        $report.layers.live_workflow.state | Should Be 'not_run'
        $report.provider_calls | Should Be 0
    }

    It 'does not let an optional model snapshot override deterministic gates' {
        $invalid = New-PluginEvaluationReport (Join-Path $fixtureRoot 'invalid-missing-license') ([pscustomobject]@{ state = 'pass'; score = 1.0 })
        $invalid.pass | Should Be $false
        $invalid.layers.static.state | Should Be 'fail'
        $invalid.layers.model_snapshot.state | Should Be 'pass'

        $valid = New-PluginEvaluationReport (Join-Path $fixtureRoot 'valid-plugin') ([pscustomobject]@{ state = 'fail'; score = 0.0 })
        $valid.pass | Should Be $true
        $valid.layers.model_snapshot.blocking | Should Be $false
    }
}
