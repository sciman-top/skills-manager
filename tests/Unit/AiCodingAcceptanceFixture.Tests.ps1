BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $fixture = Join-Path $repoRoot 'tests/fixtures/ai-coding-workflow'
    $runner = Join-Path $fixture 'Test-Labels.ps1'
    $pwshPath = (Get-Command pwsh -ErrorAction Stop).Source
}

Describe 'Reusable AI coding acceptance fixture' {
    It 'keeps the checked-in baseline defective and detects its case comparison failure' {
        $source = Join-Path $fixture 'Labels.ps1'
        $before = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        $output = & $pwshPath -NoProfile -File $runner 2>&1
        $exitCode = $LASTEXITCODE
        $exitCode | Should -Be 1
        ($output -join "`n") | Should -Match 'FAIL case-and-trim:'
        (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash | Should -Be $before
    }

    It 'accepts a conforming implementation supplied from a disposable directory' {
        $source = Join-Path $TestDrive 'Labels.ps1'
        @'
function Get-NormalizedLabels {
    param([AllowNull()][AllowEmptyCollection()][string[]]$Labels)
    $result = @()
    foreach ($label in $Labels) {
        if ([string]::IsNullOrWhiteSpace($label)) { continue }
        $value = $label.Trim()
        $duplicate = $false
        foreach ($previous in $result) {
            if ([StringComparer]::OrdinalIgnoreCase.Equals($previous, $value)) {
                $duplicate = $true
                break
            }
        }
        if (-not $duplicate) { $result += $value }
    }
    $result
}
'@ | Set-Content -LiteralPath $source -Encoding utf8
        $output = & $pwshPath -NoProfile -File $runner -SourcePath $source 2>&1
        $exitCode = $LASTEXITCODE
        $exitCode | Should -Be 0
        ($output -join "`n") | Should -Match 'cases=11 failed=0'
    }

    It 'rejects a hardcoded answer that only satisfies the demonstrated failing example' {
        $source = Join-Path $TestDrive 'Hardcoded.ps1'
        'function Get-NormalizedLabels { param($Labels) @("Alpha", "BETA") }' |
            Set-Content -LiteralPath $source -Encoding utf8
        $output = & $pwshPath -NoProfile -File $runner -SourcePath $source 2>&1
        $exitCode = $LASTEXITCODE
        $exitCode | Should -Be 1
        ($output -join "`n") | Should -Match 'FAIL empty:'
        ($output -join "`n") | Should -Match 'FAIL order:'
    }
}
