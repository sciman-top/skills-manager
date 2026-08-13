$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
. (Join-Path $repoRoot 'src\Domain\RuleDocument.ps1')
. (Join-Path $repoRoot 'src\Domain\RuleResponsibility.ps1')

Describe 'Rule contracts' {

    It 'keeps both declarative schemas at version 1' {
        foreach ($name in @('rule-document', 'rule-responsibility')) {
            $schema = Get-Content -LiteralPath (Join-Path $repoRoot ('config\{0}.schema.json' -f $name)) -Raw | ConvertFrom-Json
            $schema.'$schema' | Should Be 'https://json-schema.org/draft/2020-12/schema'
            $schema.properties.schema_version.const | Should Be 1
        }
    }

    It 'constructs and validates distinct plain-object contracts' {
        $finding = New-RuleFinding -Kind deterministic -Code byte_budget_exceeded -Severity warning -Path 'AGENTS.md' -Message 'Over budget.' -Disposition adapt
        $document = New-RuleDocument -Host codex -Scope repo -Responsibility project_action -Path 'AGENTS.md' -Owner repo -ContentHash ('a' * 64) -ByteSize 10 -DiscoveryState observed -SourceOfTruth repo -Findings @($finding)
        $responsibility = New-RuleResponsibility -ConstraintId R1 -CommonIntent 'Declare destination.' -ProjectActions @('AGENTS.md') -Coverage covered -Evidence @('repo')

        (Test-RuleDocumentContract $document).pass | Should Be $true
        (Test-RuleResponsibilityContract $responsibility).pass | Should Be $true
        $document.PSObject.Properties.Name | Should Contain 'discovery_state'
        $responsibility.PSObject.Properties.Name | Should Contain 'coverage'
    }

    It 'fails closed when a semantic finding tries to block' {
        $finding = New-RuleFinding -Kind semantic -Code responsibility_gap -Severity error -Path 'AGENTS.md' -Message 'Gap.' -Blocking
        $document = New-RuleDocument -Host codex -Scope repo -Responsibility project_action -Path 'AGENTS.md' -Owner repo -ContentHash ('b' * 64) -ByteSize 10 -DiscoveryState observed -SourceOfTruth repo -Findings @($finding)

        $result = Test-RuleDocumentContract $document
        $result.pass | Should Be $false
        @($result.findings | Where-Object code -eq 'semantic_finding_cannot_block').Count | Should Be 1
    }

    It 'requires a recovery condition for not_applicable responsibility coverage' {
        $item = New-RuleResponsibility -ConstraintId E6 -CommonIntent 'Data migrations.' -Coverage not_applicable
        $result = Test-RuleResponsibilityContract $item

        $result.pass | Should Be $false
        @($result.findings | Where-Object code -eq 'recovery_condition_required').Count | Should Be 1
    }

    It 'keeps the new domain modules free of IO environment clock and terminal effects' {
        $text = @('RuleDocument.ps1', 'RuleResponsibility.ps1') | ForEach-Object { Get-Content -LiteralPath (Join-Path $repoRoot ('src\Domain\{0}' -f $_)) -Raw }
        ($text -join "`n") | Should Not Match '(?im)^\s*(Get-Content|Set-Content|Add-Content|Remove-Item|Copy-Item|Move-Item|Test-Path|Resolve-Path|Get-Date|Write-Host|Write-Output|Start-Process|Invoke-WebRequest|exit)\b'
        ($text -join "`n") | Should Not Match '(?i)\$env:'
    }

    It 'parses and constructs the plain objects under the PowerShell 7 runtime' {
        $paths = @('OperationPlan.ps1', 'RuleDocument.ps1', 'RuleResponsibility.ps1') | ForEach-Object { (Join-Path $repoRoot ('src\Domain\{0}' -f $_)).Replace("'", "''") }
        $scriptText = ($paths | ForEach-Object { ". '$_'" }) -join '; '
        $scriptText += "; (New-RuleResponsibility -ConstraintId R1 -CommonIntent x -Coverage covered).schema_version | ConvertTo-Json -Compress"
        $output = @(& pwsh -NoProfile -ExecutionPolicy Bypass -Command $scriptText 2>&1)

        $LASTEXITCODE | Should Be 0
        ($output -join "`n" | ConvertFrom-Json) | Should Be 1
    }
}
