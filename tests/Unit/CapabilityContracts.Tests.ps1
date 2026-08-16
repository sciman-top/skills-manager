BeforeAll {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
    . (Join-Path $repoRoot 'src\Domain\RuleDocument.ps1')
    . (Join-Path $repoRoot 'src\Domain\RuleResponsibility.ps1')

}
Describe 'Rule contracts' {

    It 'constructs distinct plain objects with their invariants applied' {
        $finding = New-RuleFinding -Kind deterministic -Code byte_budget_exceeded -Severity warning -Path 'AGENTS.md' -Message 'Over budget.' -Disposition adapt
        $document = New-RuleDocument -Host codex -Scope repo -Responsibility project_action -Path 'AGENTS.md' -Owner repo -ContentHash ('a' * 64) -ByteSize 10 -DiscoveryState observed -SourceOfTruth repo -Findings @($finding)
        $responsibility = New-RuleResponsibility -ConstraintId R1 -CommonIntent 'Declare destination.' -ProjectActions @('AGENTS.md') -Coverage covered -Evidence @('repo')

        $document.schema_version | Should -Be 1
        $responsibility.schema_version | Should -Be 1
        $document.PSObject.Properties.Name | Should -Contain 'discovery_state'
        $responsibility.PSObject.Properties.Name | Should -Contain 'coverage'
    }

    It 'rejects a semantic finding that tries to block at construction time' {
        { New-RuleFinding -Kind semantic -Code responsibility_gap -Severity error -Path 'AGENTS.md' -Message 'Gap.' -Blocking } | Should -Throw '*cannot block*'
    }

    It 'requires a recovery condition for not_applicable responsibility coverage' {
        { New-RuleResponsibility -ConstraintId E6 -CommonIntent 'Data migrations.' -Coverage not_applicable } | Should -Throw '*recovery condition*'
    }

    It 'keeps the new domain modules free of IO environment clock and terminal effects' {
        $text = @('RuleDocument.ps1', 'RuleResponsibility.ps1') | ForEach-Object { Get-Content -LiteralPath (Join-Path $repoRoot ('src\Domain\{0}' -f $_)) -Raw }
        ($text -join "`n") | Should -Not -Match '(?im)^\s*(Get-Content|Set-Content|Add-Content|Remove-Item|Copy-Item|Move-Item|Test-Path|Resolve-Path|Get-Date|Write-Host|Write-Output|Start-Process|Invoke-WebRequest|exit)\b'
        ($text -join "`n") | Should -Not -Match '(?i)\$env:'
    }

    It 'parses and constructs the plain objects under the PowerShell 7 runtime' {
        $paths = @('OperationPlan.ps1', 'RuleDocument.ps1', 'RuleResponsibility.ps1') | ForEach-Object { (Join-Path $repoRoot ('src\Domain\{0}' -f $_)).Replace("'", "''") }
        $scriptText = ($paths | ForEach-Object { ". '$_'" }) -join '; '
        $scriptText += "; (New-RuleResponsibility -ConstraintId R1 -CommonIntent x -Coverage covered).schema_version | ConvertTo-Json -Compress"
        $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -Command $scriptText 2>&1)

        $LASTEXITCODE | Should -Be 0
        ($output -join "`n" | ConvertFrom-Json) | Should -Be 1
    }
}
