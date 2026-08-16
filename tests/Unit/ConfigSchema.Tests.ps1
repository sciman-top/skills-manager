Describe 'skills.json versioned schema contract' {
    BeforeAll {
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $repoRoot 'scripts\verify-skills-config.ps1'
$fixtureRoot = Join-Path $repoRoot 'tests\fixtures\config-schema'
function Invoke-ConfigVerifier([string]$ConfigPath, [string]$Mode = 'enforce', [switch]$External, [switch]$RequireDeclaredSchemaVersion) {
        $versionArgs = if ($RequireDeclaredSchemaVersion) { @{ RequireDeclaredSchemaVersion = $true } } else { @{} }
        $output = if ($External) {
            @(& pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -ConfigPath $ConfigPath -Mode $Mode @versionArgs 2>&1)
        }
        else {
            @(& $scriptPath -ConfigPath $ConfigPath -Mode $Mode -NoExit @versionArgs 2>&1)
        }
        return [pscustomobject]@{ exit_code = $LASTEXITCODE; result = (($output -join "`n") | ConvertFrom-Json) }
    }
}

    It 'accepts the current repository config without modifying it' {
        $configPath = Join-Path $repoRoot 'skills.json'
        $before = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash
        $run = Invoke-ConfigVerifier $configPath -External
        $after = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash

        $run.exit_code | Should -Be 0
        $run.result.valid | Should -Be $true
        $run.result.finding_count | Should -Be 0
        $run.result.version_source | Should -Be 'declared'
        $before | Should -Be $after
        $run.result.config_sha256_before | Should -Be $run.result.config_sha256_after
    }

    It 'accepts explicit schema v1 without legacy observations' {
        $run = Invoke-ConfigVerifier (Join-Path $fixtureRoot 'known-good-v1.json')
        $run.exit_code | Should -Be 0
        $run.result.config_version | Should -Be 1
        $run.result.version_source | Should -Be 'declared'
        $run.result.observation_count | Should -Be 0
    }

    It 'reads a missing version as legacy v1 with an observation' {
        $run = Invoke-ConfigVerifier (Join-Path $fixtureRoot 'legacy-v1.json')
        $run.exit_code | Should -Be 0
        $run.result.valid | Should -Be $true
        $run.result.config_version | Should -Be 1
        $run.result.version_source | Should -Be 'legacy_default'
        @($run.result.observations | Where-Object code -eq 'legacy_schema_version_missing').Count | Should -Be 1
    }

    It 'fails closed when a declared version is required for a legacy config' {
        $run = Invoke-ConfigVerifier (Join-Path $fixtureRoot 'legacy-v1.json') -RequireDeclaredSchemaVersion
        $run.exit_code | Should -Be 1
        $run.result.valid | Should -Be $false
        @($run.result.findings | Where-Object code -eq 'schema_version_required').Count | Should -Be 1
    }

    $invalidCases = @(
        @{ file = 'wrong-type.json'; code = 'type_mismatch' },
        @{ file = 'unknown-enum.json'; code = 'enum_invalid' },
        @{ file = 'unsafe-path.json'; code = 'unsafe_relative_path' }
    )
    It 'fails closed for <file>' -ForEach $invalidCases {
            $path = Join-Path $fixtureRoot $file
            $before = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            $run = Invoke-ConfigVerifier $path
            $after = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            $run.exit_code | Should -Be 1
            $run.result.valid | Should -Be $false
            @($run.result.findings | Where-Object code -eq $code).Count | Should -BeGreaterThan 0
            $before | Should -Be $after
    }

    It 'reports invalid input in observe mode without exposing the rejected value' {
        $run = Invoke-ConfigVerifier (Join-Path $fixtureRoot 'unsafe-path.json') 'observe'
        $serialized = $run.result | ConvertTo-Json -Depth 10
        $run.exit_code | Should -Be 0
        $run.result.pass | Should -Be $true
        $run.result.valid | Should -Be $false
        $run.result.would_block | Should -Be $true
        $serialized | Should -Not -Match '\.\./escape'
    }

    It 'fails closed when a discovery domain references a non-canonical skill' {
        $config = Get-Content -LiteralPath (Join-Path $repoRoot 'skills.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $config.skill_projection.discovery_catalog.domain_memberships.engineering += 'missing-canonical-skill'
        $configPath = Join-Path $TestDrive 'dangling-domain-membership.json'
        $config | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $configPath -Encoding UTF8

        $run = Invoke-ConfigVerifier $configPath

        $run.exit_code | Should -Be 1
        $run.result.valid | Should -Be $false
        @($run.result.findings | Where-Object code -eq 'discovery_membership_unknown').Count | Should -Be 1
    }

    It 'keeps the declarative schema parseable and documents compatibility and secret policy' {
        $schema = Get-Content -LiteralPath (Join-Path $repoRoot 'config\skills.schema.json') -Raw | ConvertFrom-Json
        $schema.'$schema' | Should -Be 'https://json-schema.org/draft/2020-12/schema'
        $schema.properties.schema_version.const | Should -Be 1
        $schema.'x-compatibility-policy'.missing_schema_version | Should -Be 'legacy-v1-observation'
        $schema.'x-secret-policy'.validator_output | Should -Be 'code-path-message-only'
    }
}
