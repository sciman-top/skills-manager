$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repoRoot 'src\Domain\OperationPlan.ps1')
. (Join-Path $repoRoot 'src\Domain\CapabilityDescriptor.ps1')
. (Join-Path $repoRoot 'src\Application\CapabilityInventory.ps1')

Describe 'Read-only capability inventory' {
    function New-TestDescriptor([string]$Origin, [string]$Lifecycle, [string]$Location) {
        return New-CapabilityDescriptor -Kind plugin -Name demo -TruthOrigin $Origin -Lifecycle $Lifecycle -Source ([pscustomobject]@{ type = 'manifest'; path_or_url = $Location; revision = 'r1'; checksum = $null; license = $null; trust_tier = $Origin })
    }

    It 'preserves same-name descriptors from distinct truth origins' {
        $runtime = New-TestDescriptor runtime active 'skills.json'
        $official = New-TestDescriptor official active 'official://plugins/demo'
        $inventory = New-CapabilityInventory @($runtime, $official)

        @($inventory.descriptors).Count | Should Be 2
        @($inventory.decisions).Count | Should Be 1
        $inventory.decisions[0].disposition | Should Be 'alternative'
        $inventory.read_only | Should Be $true
    }

    It 'does not promote deprecated or historical reference truth to active' {
        $active = New-TestDescriptor official active 'official://plugins/demo'
        $old = New-TestDescriptor reference historical 'git://historical/demo'
        $inventory = New-CapabilityInventory @($old, $active)

        @($inventory.descriptors | Where-Object lifecycle -eq 'historical').Count | Should Be 1
        $inventory.decisions[0].disposition | Should Be 'conflict'
    }

    It 'converts supplied config objects without reading or changing their source file' {
        $config = [pscustomobject]@{ vendors = [ordered]@{ demo = @{ repo = 'owner/demo' } }; mcp_servers = [ordered]@{ docs = @{ command = 'npx'; args = @('secret-arg') } } }
        $before = $config | ConvertTo-Json -Depth 20 -Compress
        $descriptors = ConvertTo-CapabilityDescriptorsFromSkillsConfig $config

        @($descriptors).Count | Should Be 2
        ($config | ConvertTo-Json -Depth 20 -Compress) | Should Be $before
        ($descriptors | ConvertTo-Json -Depth 20 -Compress) | Should Not Match 'secret-arg'
    }

    It 'converts the real array-shaped config domains into runtime descriptors' {
        $config = [pscustomobject]@{
            vendors = @([pscustomobject]@{ name = 'demo-vendor'; repo = 'owner/vendor' })
            imports = @([pscustomobject]@{ name = 'demo-import'; skill = 'skills/demo'; repo = 'owner/import' })
            mappings = @([pscustomobject]@{ vendor = 'demo-vendor'; from = 'skills/demo'; to = 'demo-skill' })
            mcp_servers = @([pscustomobject]@{ name = 'docs'; command = 'npx'; args = @('secret-arg') })
        }

        $descriptors = @(ConvertTo-CapabilityDescriptorsFromSkillsConfig $config)

        $descriptors.Count | Should Be 4
        @($descriptors | Where-Object truth_origin -eq runtime).Count | Should Be 4
        (@($descriptors.components.kind | Sort-Object) -join ',') | Should Be 'import,mapping,mcp_server,vendor'
        ($descriptors | ConvertTo-Json -Depth 20 -Compress) | Should Not Match 'secret-arg'
    }

    It 'returns structured validation findings and zero side-effect counters' {
        $inventory = New-CapabilityInventory @([pscustomobject]@{ schema_version = 1; id = 'bad' })

        @($inventory.descriptors).Count | Should Be 0
        @($inventory.findings).Count | Should BeGreaterThan 0
        $inventory.provider_calls | Should Be 0
        $inventory.native_mutations | Should Be 0
        $inventory.writes | Should Be 0
        $inventory.profile_changed | Should Be $false
    }
}
