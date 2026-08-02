$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'skills.ps1')
$fixtureSource = Join-Path $repoRoot 'tests\fixtures\phase3-acceptance'

Describe 'Phase 3 repository-side acceptance' {
    function New-AcceptanceFixture {
        $root = Join-Path $TestDrive 'phase3'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        Get-ChildItem -LiteralPath $fixtureSource -Force | Copy-Item -Destination $root -Recurse -Force
        return $root
    }

    It 'runs inventory lint export and eval through single JSON envelopes' {
        $root = New-AcceptanceFixture
        $inventory = Invoke-PluginInventoryCommand @('--official', (Join-Path $root 'official-inventory.json'), '--personal', (Join-Path $root 'personal-inventory.json'), '--workspace', (Join-Path $root 'workspace-inventory.json'), '--json')
        $lint = Invoke-PluginLintCommand @('--path', (Join-Path $root 'valid-plugin'), '--json')
        $out = Join-Path $root 'exported\teacher-workflows'
        $export = Invoke-PluginExportCommand @('--candidate', (Join-Path $root 'candidate.json'), '--fixture-root', $root, '--out', $out, '--token', 'EXPORT_PLUGIN_FIXTURE', '--json')
        $eval = Invoke-PluginEvalCommand @('--path', $out, '--json')

        foreach ($result in @($inventory, $lint, $export, $eval)) {
            $result.exit_code | Should Be 0
            ($result.output | ConvertFrom-Json).schema_version | Should Be 1
            ($result.output | ConvertFrom-Json).truth_boundary | Should Be 'repo_or_fixture_only'
        }
    }

    It 'preserves real config reference and plugin inventory state' {
        $paths = @(
            (Join-Path $repoRoot 'skills.json'),
            'D:\CODE-other\governed-ai-coding-runtime\AGENTS.md'
        ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
        $before = @{}; foreach ($path in $paths) { $before[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
        $root = New-AcceptanceFixture
        $result = Invoke-PluginLintCommand @('--path', (Join-Path $root 'valid-plugin'), '--json')
        $result.exit_code | Should Be 0
        foreach ($path in $paths) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash | Should Be $before[$path] }
    }

    It 'keeps invalid distribution and model evidence truthfully bounded' {
        $root = New-AcceptanceFixture
        $lint = Invoke-PluginLintCommand @('--path', (Join-Path $root 'invalid-missing-license'), '--json')
        $lint.exit_code | Should Be 2
        $report = New-PluginEvaluationReport (Join-Path $root 'valid-plugin') ([pscustomobject]@{ state = 'fail' })
        $report.pass | Should Be $true
        $report.layers.model_snapshot.blocking | Should Be $false
        $report.layers.host_load.state | Should Be 'not_run'
        $report.layers.live_workflow.state | Should Be 'not_run'
    }
}
