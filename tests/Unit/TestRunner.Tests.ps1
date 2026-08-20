BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    $runnerPath = Join-Path $repoRoot 'tests\run.ps1'

    function New-RunnerFixture([string]$Name, [string]$TestBody) {
        $root = Join-Path $TestDrive $Name
        $unit = Join-Path $root 'Unit'
        $e2e = Join-Path $root 'E2E'
        New-Item -ItemType Directory -Path $unit, $e2e -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $unit 'Fixture.Tests.ps1') -Value $TestBody -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $e2e 'Fixture.Tests.ps1') -Value @'
Describe 'E2E fixture' {
    It 'passes' { $true | Should -Be $true }
}
'@ -Encoding UTF8
        return [pscustomobject]@{ unit = $unit; e2e = $e2e }
    }

}
Describe 'Repository test runner output contract' {
    It 'prints one stable summary line for a passing run' {
        $fixture = New-RunnerFixture 'pass' @'
Describe 'Noisy fixture' {
    It 'passes without leaking output' {
        Write-Host 'fixture-noise-marker'
        $true | Should -Be $true
    }
}
'@

        $output = @(& pwsh -NoProfile -File $runnerPath -TestPath (Join-Path $fixture.unit 'Fixture.Tests.ps1') *>&1)
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 0
        @($output).Count | Should -Be 1
        [string]$output[0] | Should -Match '^Tests: total=1 passed=1 failed=0 skipped=0 duration=[0-9.]+s$'
        ($output -join "`n") | Should -Not -Match 'fixture-noise-marker'
    }

    It 'prints bounded failure diagnostics without leaking fixture output' {
        $fixture = New-RunnerFixture 'fail' @'
Describe 'Noisy failing fixture' {
    It 'fails clearly' {
        Write-Host 'fixture-noise-marker'
        1 | Should -Be 2
    }
}
'@

        $output = @(& pwsh -NoProfile -File $runnerPath -UnitTestPath $fixture.unit -E2ETestPath $fixture.e2e *>&1)
        $exitCode = $LASTEXITCODE
        $text = $output -join "`n"

        $exitCode | Should -Not -Be 0
        $text | Should -Match 'Tests: total=2 passed=1 failed=1 skipped=0 duration=[0-9.]+s'
        $text | Should -Match 'FAILED: fails clearly'
        $text | Should -Match 'Expected 2, but got 1\.'
        $text | Should -Not -Match 'fixture-noise-marker'
        @($output).Count | Should -BeLessThan 10
    }

    It 'filters a large test file by full test name' {
        $fixture = New-RunnerFixture 'name-filter' @'
Describe 'Filtered fixture' {
    It 'chosen test' { $true | Should -Be $true }
    It 'other test' { throw 'should not run' }
}
'@

        $output = @(& pwsh -NoProfile -File $runnerPath -TestPath (Join-Path $fixture.unit 'Fixture.Tests.ps1') -TestName '*chosen test' *>&1)
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 0
        [string]$output[0] | Should -Match '^Tests: total=[0-9]+ passed=1 failed=0 skipped=0 duration=[0-9.]+s$'
    }

    It 'fails when one test container cannot be parsed even if another container passes' {
        $fixture = New-RunnerFixture 'container-fail' @'
Describe 'Broken fixture' {
    It 'cannot be discovered' {
}
'@

        $output = @(& pwsh -NoProfile -File $runnerPath -UnitTestPath $fixture.unit -E2ETestPath $fixture.e2e *>&1)
        $exitCode = $LASTEXITCODE
        $text = $output -join "`n"

        $exitCode | Should -Not -Be 0
        $text | Should -Match 'CONTAINER FAILED:'
        $text | Should -Match 'Pester container failures: 1'
    }
}
