$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'skills.ps1')
$fixtureRoot = Join-Path $repoRoot 'tests\fixtures\phase3-acceptance'

Describe 'Plugin inventory snapshot adapter' {
    It 'preserves official personal and workspace scopes without side effects' {
        $officialPath = Join-Path $fixtureRoot 'official-inventory.json'
        $personalPath = Join-Path $fixtureRoot 'personal-inventory.json'
        $workspacePath = Join-Path $fixtureRoot 'workspace-inventory.json'
        $snapshotPaths = @($officialPath, $personalPath, $workspacePath)
        $hashes = @($snapshotPaths | ForEach-Object { Get-FileContentHash $_ })
        $result = New-PluginInventoryFromSnapshots `
            (Get-Content -Raw $officialPath | ConvertFrom-Json) `
            (Get-Content -Raw $personalPath | ConvertFrom-Json) `
            (Get-Content -Raw $workspacePath | ConvertFrom-Json)

        $result.pass | Should Be $true
        @($result.descriptors).Count | Should Be 3
        @($result.descriptors | ForEach-Object components | ForEach-Object distribution_scope | Sort-Object) -join ',' | Should Be 'official,personal,workspace'
        $result.provider_calls | Should Be 0
        $result.native_mutations | Should Be 0
        $result.writes | Should Be 0
        @($snapshotPaths | ForEach-Object { Get-FileContentHash $_ }) -join ',' | Should Be ($hashes -join ',')
    }

    It 'fails closed when the current CLI envelope arrays are absent' {
        $result = New-PluginInventoryFromSnapshots ([pscustomobject]@{ installed = @() })
        $result.pass | Should Be $false
        @($result.findings.code) | Should Contain 'plugin_snapshot_array_missing'
    }
}
