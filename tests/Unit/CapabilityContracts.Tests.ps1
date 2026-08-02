$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
. (Join-Path $repoRoot 'src\Domain\CapabilityDescriptor.ps1')
. (Join-Path $repoRoot 'src\Domain\RuleDocument.ps1')
. (Join-Path $repoRoot 'src\Domain\RuleResponsibility.ps1')

Describe 'Phase 1 capability and rule contracts' {
    $source = [pscustomobject]@{ type = 'git'; path_or_url = 'https://example.invalid/repo'; revision = 'abc123'; checksum = $null; license = 'MIT'; trust_tier = 'official' }

    It 'keeps all three declarative schemas at version 1' {
        foreach ($name in @('capability-descriptor', 'rule-document', 'rule-responsibility')) {
            $schema = Get-Content -LiteralPath (Join-Path $repoRoot ('config\{0}.schema.json' -f $name)) -Raw | ConvertFrom-Json
            $schema.'$schema' | Should Be 'https://json-schema.org/draft/2020-12/schema'
            $schema.properties.schema_version.const | Should Be 1
        }
    }

    It 'constructs and validates distinct plain-object contracts' {
        $descriptor = New-CapabilityDescriptor -Kind plugin -Name 'Demo' -TruthOrigin official -Source $source -Lifecycle active -HostCompatibility @('codex')
        $finding = New-RuleFinding -Kind deterministic -Code byte_budget_exceeded -Severity warning -Path 'AGENTS.md' -Message 'Over budget.' -Disposition adapt
        $document = New-RuleDocument -Host codex -Scope repo -Responsibility project_action -Path 'AGENTS.md' -Owner repo -ContentHash ('a' * 64) -ByteSize 10 -DiscoveryState observed -SourceOfTruth repo -Findings @($finding)
        $responsibility = New-RuleResponsibility -ConstraintId R1 -CommonIntent 'Declare destination.' -ProjectActions @('AGENTS.md') -Coverage covered -Evidence @('repo')

        (Test-CapabilityDescriptorContract $descriptor).pass | Should Be $true
        (Test-RuleDocumentContract $document).pass | Should Be $true
        (Test-RuleResponsibilityContract $responsibility).pass | Should Be $true
        $descriptor.PSObject.Properties.Name | Should Contain 'truth_origin'
        $document.PSObject.Properties.Name | Should Contain 'discovery_state'
        $responsibility.PSObject.Properties.Name | Should Contain 'coverage'
    }

    It 'produces stable descriptor ids and JSON for reordered array input' {
        $first = New-CapabilityDescriptor -Kind skill -Name demo -TruthOrigin reference -Source $source -HostCompatibility @('claude', 'codex') -Components @(@{ kind = 'b' }, @{ kind = 'a' })
        $second = New-CapabilityDescriptor -Kind skill -Name demo -TruthOrigin reference -Source $source -HostCompatibility @('codex', 'claude') -Components @(@{ kind = 'a' }, @{ kind = 'b' })

        $first.id | Should Be $second.id
        ($first | ConvertTo-Json -Depth 20 -Compress) | Should Be ($second | ConvertTo-Json -Depth 20 -Compress)
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
        $text = @('CapabilityDescriptor.ps1', 'RuleDocument.ps1', 'RuleResponsibility.ps1') | ForEach-Object { Get-Content -LiteralPath (Join-Path $repoRoot ('src\Domain\{0}' -f $_)) -Raw }
        ($text -join "`n") | Should Not Match '(?im)^\s*(Get-Content|Set-Content|Add-Content|Remove-Item|Copy-Item|Move-Item|Test-Path|Resolve-Path|Get-Date|Write-Host|Write-Output|Start-Process|Invoke-WebRequest|exit)\b'
        ($text -join "`n") | Should Not Match '(?i)\$env:'
    }

    It 'parses and constructs the plain objects under bounded Windows PowerShell 5.1 smoke' {
        $paths = @('OperationPlan.ps1', 'CapabilityDescriptor.ps1', 'RuleDocument.ps1', 'RuleResponsibility.ps1') | ForEach-Object { (Join-Path $repoRoot ('src\Domain\{0}' -f $_)).Replace("'", "''") }
        $scriptText = ($paths | ForEach-Object { ". '$_'" }) -join '; '
        $scriptText += "; `$s=[pscustomobject]@{type='git';path_or_url='x'}; `$d=New-CapabilityDescriptor -Kind skill -Name x -TruthOrigin candidate -Source `$s; `$d.schema_version | ConvertTo-Json -Compress"
        $output = @(& powershell.exe -NoProfile -Command $scriptText 2>&1)

        $LASTEXITCODE | Should Be 0
        ($output -join "`n" | ConvertFrom-Json) | Should Be 1
    }
}
