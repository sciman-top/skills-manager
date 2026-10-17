Describe 'Independent model preset behavior' {
    It 'verifies routes, launch arguments, disposable projections and exact rollback' {
        $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
        $output = & pwsh -NoProfile -File (Join-Path $repoRoot 'src/model-orchestration/Test-ModelPreset.ps1') 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
    }
}
